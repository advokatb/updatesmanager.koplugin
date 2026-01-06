--[[--
Updates Manager Plugin for KOReader
Manages updates for patches and plugins from multiple GitHub repositories
]] --

local DataStorage = require("datastorage")
local Event = require("ui/event")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local Trapper = require("ui/trapper")

local Config = require("updatesmanager_config")
local PatchManager = require("patch_manager")
local PluginManager = require("plugin_manager")
local RepositoryManager = require("repository_manager")
local UIManager_Updates = require("ui_manager")
local _ = require("updatesmanager_gettext")
local T = require("ffi/util").template

-- Cache for GitHub token (loaded once per session)
local cached_token = nil

-- Load GitHub token (with caching)
local function getGitHubToken()
    if cached_token ~= nil then
        return cached_token
    end
    
    if Config and Config.loadGitHubToken then
        cached_token = Config.loadGitHubToken()
    end
    return cached_token
end

local UpdatesManager = WidgetContainer:extend {
    name = "updatesmanager",
    is_doc_only = false,
}

function UpdatesManager:init()
    -- Load configuration
    self.repositories = Config.loadRepositories()
    
    -- Create GitHub token template file if it doesn't exist
    Config.createGitHubTokenTemplate()

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
        self._menu_registered = true
    end
end

function UpdatesManager:onReaderReady()
    -- Ensure menu is registered in reader mode
    if self.ui and self.ui.menu and not self._menu_registered then
        self.ui.menu:registerToMainMenu(self)
        self._menu_registered = true
    end
end

-- Clear cache
function UpdatesManager:clearCache()
    local cache_file = Config.CACHE_FILE
    local cache_dir = Config.CACHE_DIR
    local lfs = require("libs/libkoreader-lfs")
    local ok = false

    if lfs.attributes(cache_file, "mode") == "file" then
        ok = pcall(os.remove, cache_file)
    end

    if lfs.attributes(cache_dir, "mode") == "directory" then
        -- Try to remove directory (will fail if not empty, but that's ok)
        pcall(os.remove, cache_dir)
    end

    if ok then
        UIManager_Updates:showInfo(_("Cache cleared"))
    else
        UIManager_Updates:showInfo(_("No cache to clear"))
    end
end

-- Check for updates
function UpdatesManager:checkForUpdates(force_refresh)
    force_refresh = force_refresh or false
    UIManager_Updates:checkNetwork(function()
        UIManager_Updates:showProcessing(_("Checking for updates..."))

        -- Pre-load ALL modules before subprocess (they won't load in subprocess due to paths)
        -- Load all required modules that work in subprocess
        local Config = require("updatesmanager_config")
        local Version = require("version")
        local logger = require("logger")
        local lfs = require("libs/libkoreader-lfs")
        local md5 = require("ffi/MD5")
        local http = require("socket/http")
        local ltn12 = require("ltn12")
        local json = require("json")
        local socketutil = require("socketutil")
        local socket = require("socket")
        local T = require("ffi/util").template

        -- Inline HTTP functions (can't use Utils module in subprocess)
        local function httpGet(url, headers)
            headers = headers or {}
            headers["User-Agent"] = headers["User-Agent"] or "KOReader-UpdatesManager/1.0"
            headers["Accept"] = headers["Accept"] or "application/json"
            
            -- Add GitHub token if available and URL is GitHub API
            if url:match("api%.github%.com") or url:match("raw%.githubusercontent%.com") then
                local token = getGitHubToken()
                if token then
                    headers["Authorization"] = "token " .. token
                end
            end

            local response_body = {}
            socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)

            local code, response_headers, status = socket.skip(1, http.request({
                url = url,
                method = "GET",
                headers = headers,
                sink = ltn12.sink.table(response_body),
                redirect = true,
            }))

            socketutil:reset_timeout()

            if code == socketutil.TIMEOUT_CODE or
                code == socketutil.SSL_HANDSHAKE_CODE or
                code == socketutil.SINK_TIMEOUT_CODE then
                return nil, code or "timeout"
            end

            if response_headers == nil then
                return nil, code or "network_error"
            end

            if code == 200 then
                return table.concat(response_body), code, response_headers
            else
                return nil, code, response_headers
            end
        end

        local function parseJSON(json_string)
            local ok, result = pcall(json.decode, json_string)
            return ok and result or nil
        end

        local function downloadFile(url, local_path, headers)
            headers = headers or {}
            headers["User-Agent"] = headers["User-Agent"] or "KOReader-UpdatesManager/1.0"
            
            -- Add GitHub token if available and URL is GitHub
            if url:match("api%.github%.com") or url:match("raw%.githubusercontent%.com") or url:match("github%.com") then
                local token = getGitHubToken()
                if token then
                    headers["Authorization"] = "token " .. token
                end
            end

            -- Ensure directory exists
            local dir = local_path:match("^(.*)/")
            if dir and dir ~= "" then
                if lfs.attributes(dir, "mode") ~= "directory" then
                    lfs.mkdir(dir)
                end
            end

            local file = io.open(local_path, "wb")
            if not file then
                return false
            end

            socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)

            local code, response_headers, status = socket.skip(1, http.request({
                url = url,
                method = "GET",
                headers = headers,
                sink = ltn12.sink.file(file),
                redirect = true,
            }))

            socketutil:reset_timeout()
            file:close()

            if code == socketutil.TIMEOUT_CODE or
                code == socketutil.SSL_HANDSHAKE_CODE or
                code == socketutil.SINK_TIMEOUT_CODE then
                pcall(os.remove, local_path)
                return false
            end

            if response_headers == nil then
                pcall(os.remove, local_path)
                return false
            end

            if code == 200 then
                return true
            else
                pcall(os.remove, local_path)
                return false
            end
        end

        local function removeFile(path)
            local ok, err = pcall(os.remove, path)
            return ok
        end

        local function copyFile(src, dst)
            local dir = dst:match("^(.*)/")
            if dir and dir ~= "" then
                if lfs.attributes(dir, "mode") ~= "directory" then
                    lfs.mkdir(dir)
                end
            end

            local src_file = io.open(src, "rb")
            if not src_file then return false end

            local dst_file = io.open(dst, "wb")
            if not dst_file then
                src_file:close()
                return false
            end

            local content = src_file:read("*a")
            src_file:close()

            dst_file:write(content)
            dst_file:close()

            return true
        end

        local function fileExists(path)
            return lfs.attributes(path, "mode") == "file"
        end

        -- Rate limiting: add delay between requests
        local last_request_time = 0
        local function rateLimit()
            local now = os.time()
            local time_since_last = now - last_request_time
            if time_since_last < 0.5 then -- 500ms between requests
                local sleep_time = 0.5 - time_since_last
                -- Can't use os.execute("sleep") in Lua, so we'll just continue
                -- The delay will happen naturally due to network latency
            end
            last_request_time = os.time()
        end

        -- Create wrapper functions that use inline HTTP functions
        local function getRepositoryFiles(owner, repo, branch, path)
            local url = string.format("https://api.github.com/repos/%s/%s/contents/", owner, repo)
            if path and path ~= "" then
                url = url .. path
            end
            if branch then
                url = url .. "?ref=" .. branch
            end

            rateLimit()
            local content, code = httpGet(url, {
                ["Accept"] = "application/vnd.github.v3+json",
            })

            -- Handle rate limiting
            if code == 403 or code == 429 then
                logger.warn("UpdatesManager: Rate limited by GitHub API (403/429), will retry later")
                return nil
            end

            if not content or code ~= 200 then
                logger.warn("UpdatesManager: Failed to get repository contents:", url, code)
                return nil
            end

            local files = parseJSON(content)
            if not files or type(files) ~= "table" then
                logger.warn("UpdatesManager: Invalid repository contents response")
                return nil
            end

            local lua_files = {}
            for _, item in ipairs(files) do
                if item.type == "file" and item.name:match("%.lua$") then
                    table.insert(lua_files, {
                        name = item.name,
                        path = item.path,
                        sha = item.sha,
                        size = item.size,
                        download_url = item.download_url,
                    })
                end
            end
            return lua_files
        end

        local function getFileContent(owner, repo, branch, file_path)
            local url = string.format("https://raw.githubusercontent.com/%s/%s/%s/", owner, repo, branch) .. file_path
            rateLimit()
            local content, code = httpGet(url)
            -- Handle rate limiting
            if code == 403 or code == 429 then
                logger.warn("UpdatesManager: Rate limited when getting file content (403/429), will retry later")
                return nil
            end
            if not content or code ~= 200 then
                logger.warn("UpdatesManager: Failed to get file content:", url, code)
                return nil
            end
            return content
        end

        -- Cache management
        local function loadCache()
            local cache_file = Config.CACHE_FILE
            local file = io.open(cache_file, "r")
            if file then
                local content = file:read("*a")
                file:close()
                local ok, cache = pcall(json.decode, content)
                if ok and cache then
                    -- Check if cache is still valid (1 hour)
                    local cache_age = os.time() - (cache.timestamp or 0)
                    if cache_age < 3600 then
                        return cache.data
                    end
                end
            end
            return nil
        end

        local function saveCache(data)
            local cache_dir = Config.CACHE_DIR
            if lfs.attributes(cache_dir, "mode") ~= "directory" then
                lfs.mkdir(cache_dir)
            end

            local cache_file = Config.CACHE_FILE
            local cache = {
                timestamp = os.time(),
                data = data
            }
            local file = io.open(cache_file, "w")
            if file then
                local ok, content = pcall(json.encode, cache)
                if ok then
                    file:write(content)
                end
                file:close()
            end
        end

        local function scanRepositoryForPatches(repo_config, compute_md5_for_local_only)
            compute_md5_for_local_only = compute_md5_for_local_only or {}
            local owner = repo_config.owner
            local repo = repo_config.repo
            local branch = repo_config.branch or "main"
            local path = repo_config.path or ""

            local files = getRepositoryFiles(owner, repo, branch, path)
            if not files then
                return {}
            end

            local patches = {}
            for _, file in ipairs(files) do
                if not file.name:match("%.disabled$") then
                    -- Extract patch name (without .lua extension)
                    local patch_name = file.name:gsub("%.lua$", "")
                    local patch_data = {
                        name = file.name,
                        patch_name = patch_name,
                        path = file.path,
                        sha = file.sha,
                        size = file.size,
                        download_url = file.download_url,
                        repo_owner = owner,
                        repo_name = repo,
                        repo_path = path,
                        repo_branch = branch,
                        repo_url = string.format("https://github.com/%s/%s", owner, repo),
                    }

                    -- Compute MD5 on-the-fly only if patch exists locally (to speed up comparison)
                    if compute_md5_for_local_only[patch_name] then
                        rateLimit()
                        local repo_content = getFileContent(owner, repo, branch, file.path)
                        if repo_content then
                            -- Use cache directory for temp file
                            local cache_dir = Config.CACHE_DIR
                            if lfs.attributes(cache_dir, "mode") ~= "directory" then
                                lfs.mkdir(cache_dir)
                            end
                            local temp_path = cache_dir .. "/" .. patch_name .. ".tmp"
                            local temp_file = io.open(temp_path, "w")
                            if temp_file then
                                temp_file:write(repo_content)
                                temp_file:close()

                                local ok, hash = pcall(md5.sumFile, temp_path)
                                if ok then
                                    patch_data.md5 = hash
                                    logger.dbg("UpdatesManager: Computed MD5 on-the-fly for:", patch_name)
                                end
                                removeFile(temp_path)
                            end
                        end
                    end

                    table.insert(patches, patch_data)
                end
            end

            return patches
        end

        local function scanLocalPatches()
            local patches_dir = Config.PATCHES_DIR
            local dir_mode = lfs.attributes(patches_dir, "mode")
            if not dir_mode or dir_mode ~= "directory" then
                return {}
            end

            local patches = {}
            for entry in lfs.dir(patches_dir) do
                if entry ~= "." and entry ~= ".." then
                    local full_path = patches_dir .. "/" .. entry
                    local mode = lfs.attributes(full_path, "mode")

                    if mode == "file" and entry:match("%.lua$") and not entry:match("%.disabled$") then
                        local patch_name = entry:gsub("%.lua$", "")
                        local md5_hash = nil
                        local ok, hash = pcall(md5.sumFile, full_path)
                        if ok then
                            md5_hash = hash
                        end

                        -- Use patch_name as key for consistency with repository patches
                        patches[patch_name] = {
                            filename = entry,
                            name = patch_name,
                            path = full_path,
                            md5 = md5_hash,
                            size = lfs.attributes(full_path, "size") or 0,
                            enabled = true,
                        }
                    end
                end
            end

            return patches
        end

        local function checkForUpdates(repositories, force_refresh, progress_callback)
            progress_callback = progress_callback or function() end
            local local_patches = scanLocalPatches()
            local updates = {}
            local rate_limit_hit = false
            local rate_limit_count = 0


            -- First, scan all repositories ONCE and cache results
            local all_repo_patches = {} -- key: filename, value: {patch, repo_config}
            local cache_key = ""
            for _, repo_config in ipairs(repositories) do
                cache_key = cache_key ..
                    repo_config.owner .. "/" .. repo_config.repo .. "/" .. (repo_config.path or "") .. ";"
            end

            -- Try to load from cache (unless force refresh)
            local cached_data = nil
            if not force_refresh then
                cached_data = loadCache()
            end
            local use_cache = false
            if cached_data and cached_data.cache_key == cache_key then
                use_cache = true
                all_repo_patches = cached_data.patches or {}
                local patch_count = 0
                for _ in pairs(all_repo_patches) do patch_count = patch_count + 1 end
                logger.info("UpdatesManager: Using cached repository patches:", patch_count, "patches")
                progress_callback(_("Using cached data..."))
            else
                -- Build list of local patch names for MD5 computation optimization
                local local_patch_names = {}
                for patch_name, _ in pairs(local_patches) do
                    local_patch_names[patch_name] = true
                end

                -- Scan all repositories once
                logger.info("UpdatesManager: Scanning all repositories (this may take a while)...")
                local total_repos = #repositories
                for i, repo_config in ipairs(repositories) do
                    if rate_limit_hit then
                        logger.warn("UpdatesManager: Stopping scan due to rate limiting")
                        break
                    end

                    -- Update progress
                    local repo_name = repo_config.owner .. "/" .. repo_config.repo
                    if repo_config.path and repo_config.path ~= "" then
                        repo_name = repo_name .. "/" .. repo_config.path
                    end
                    progress_callback(T(_("Scanning repository %1/%2: %3"), i, total_repos, repo_name))

                    rateLimit() -- Add delay to avoid rate limiting
                    -- Only compute MD5 for patches that exist locally
                    local patches = scanRepositoryForPatches(repo_config, local_patch_names)

                    -- Check if we got rate limited
                    if not patches and rate_limit_count > 0 then
                        rate_limit_count = rate_limit_count + 1
                        if rate_limit_count >= 3 then
                            rate_limit_hit = true
                            logger.warn("UpdatesManager: Rate limit hit multiple times, stopping")
                            break
                        end
                    elseif not patches then
                        rate_limit_count = 1
                    else
                        rate_limit_count = 0 -- Reset on success
                    end

                    if patches then
                        for _, patch in ipairs(patches) do
                            -- Store by patch name (filename without .lua), but keep the first match (or could merge)
                            local patch_key = patch.patch_name or patch.name:gsub("%.lua$", "")
                            if not all_repo_patches[patch_key] then
                                all_repo_patches[patch_key] = {
                                    patch = patch,
                                    repo_config = repo_config,
                                }
                            end
                        end
                    end
                end

                -- Save to cache only if we didn't hit rate limits
                if not rate_limit_hit then
                    progress_callback(_("Saving cache..."))
                    saveCache({
                        cache_key = cache_key,
                        patches = all_repo_patches,
                    })
                end
            end

            -- Now check each local patch against cached repository data
            progress_callback(_("Checking for updates..."))
            local local_patch_list = {}
            for patch_name, _ in pairs(local_patches) do
                table.insert(local_patch_list, patch_name)
            end
            local total_patches = #local_patch_list

            for idx, patch_name in ipairs(local_patch_list) do
                local local_patch = local_patches[patch_name]
                -- Match by patch name (without .lua extension)
                local repo_data = all_repo_patches[patch_name]
                if repo_data then
                    local repo_patch = repo_data.patch
                    local repo_config = repo_data.repo_config

                    -- Update progress
                    if total_patches > 0 then
                        progress_callback(T(_("Checking patch %1/%2: %3"), idx, total_patches, patch_name))
                    end

                    -- Use cached MD5 if available (computed during scan)
                    local repo_md5 = repo_patch.md5

                    -- If MD5 not cached, compute it now (shouldn't happen if scan worked correctly)
                    if not repo_md5 then
                        rateLimit()
                        local repo_content = getFileContent(
                            repo_patch.repo_owner,
                            repo_patch.repo_name,
                            repo_patch.repo_branch,
                            repo_patch.path
                        )

                        if repo_content then
                            local temp_path = local_patch.path .. ".temp_check"
                            local temp_file = io.open(temp_path, "w")
                            if temp_file then
                                temp_file:write(repo_content)
                                temp_file:close()

                                local ok, hash = pcall(md5.sumFile, temp_path)
                                if ok then
                                    repo_md5 = hash
                                end
                                removeFile(temp_path)
                            end
                        end
                    end

                    -- Compare MD5 hashes
                    if repo_md5 and local_patch.md5 and repo_md5 ~= local_patch.md5 then
                        -- Download content only when update is found
                        rateLimit()
                        local repo_content = getFileContent(
                            repo_patch.repo_owner,
                            repo_patch.repo_name,
                            repo_patch.repo_branch,
                            repo_patch.path
                        )

                        if repo_content then
                            table.insert(updates, {
                                local_patch = local_patch,
                                repo_patch = repo_patch,
                                repo_config = repo_config,
                                repo_md5 = repo_md5,
                                repo_content = repo_content,
                            })
                            logger.info("UpdatesManager: Update found for patch:", patch_name)
                        end
                    elseif not local_patch.md5 or not repo_md5 then
                        -- If MD5 not available for either, compare by size as fallback
                        if repo_patch.size and local_patch.size and repo_patch.size ~= local_patch.size then
                            -- Size differs, likely an update, download to verify
                            rateLimit()
                            local repo_content = getFileContent(
                                repo_patch.repo_owner,
                                repo_patch.repo_name,
                                repo_patch.repo_branch,
                                repo_patch.path
                            )
                            if repo_content then
                                -- Compute MD5 for downloaded content
                                local temp_path = local_patch.path .. ".temp_check"
                                local temp_file = io.open(temp_path, "w")
                                if temp_file then
                                    temp_file:write(repo_content)
                                    temp_file:close()

                                    local ok, hash = pcall(md5.sumFile, temp_path)
                                    if ok then
                                        repo_md5 = hash
                                    end
                                    removeFile(temp_path)
                                end

                                table.insert(updates, {
                                    local_patch = local_patch,
                                    repo_patch = repo_patch,
                                    repo_config = repo_config,
                                    repo_md5 = repo_md5,
                                    repo_content = repo_content,
                                })
                                logger.info("UpdatesManager: Update found for patch (size differs):", patch_name)
                            end
                        end
                    end
                end
            end

            logger.info("UpdatesManager: Found", #updates, "patch updates")
            progress_callback(_("Checking complete..."))

            -- Now check for plugin updates
            progress_callback(_("Checking for plugin updates..."))
            local plugin_updates = {}
            local plugin_rate_limit_hit = false

            -- Scan installed plugins
            local PluginManager = require("plugin_manager")
            local installed_plugins = PluginManager.scanInstalledPlugins()

            -- Check plugin updates (using inline functions for subprocess compatibility)
            -- Note: self.repositories is captured in closure before subprocess
            local plugin_repos = self.repositories.plugins or {}
            local function checkPluginUpdates()
                if #plugin_repos == 0 then
                    return {}
                end

                -- Use PluginManager.checkForUpdates with inline functions
                local plugin_updates_result = PluginManager.checkForUpdates(
                    plugin_repos,
                    installed_plugins,
                    httpGet,
                    parseJSON,
                    rateLimit
                )

                return plugin_updates_result or {}
            end

            plugin_updates = checkPluginUpdates()

            -- Return result with both patch and plugin updates
            return {
                updates = updates,               -- patch updates
                plugin_updates = plugin_updates, -- plugin updates
                rate_limit_hit = rate_limit_hit,
            }
        end

        -- Create progress file for communication between subprocess and main process
        local progress_file = Config.CACHE_DIR .. "/progress.txt"
        local function writeProgress(text)
            local file = io.open(progress_file, "w")
            if file then
                file:write(text or "")
                file:close()
            end
        end

        -- Clear progress file
        writeProgress("")

        -- Monitor progress file and update UI
        local progress_monitor
        local monitoring_active = true
        local last_progress = ""
        local last_update_time = 0
        progress_monitor = function()
            if not monitoring_active then
                return -- Stop monitoring
            end

            local file = io.open(progress_file, "r")
            if file then
                local content = file:read("*a")
                file:close()
                if content and content ~= "" and content ~= last_progress then
                    last_progress = content
                    -- Throttle updates to avoid too frequent UI refreshes (max once per 0.3 seconds)
                    local now = os.time()
                    if now - last_update_time >= 0.3 then
                        last_update_time = now
                        UIManager_Updates:updateProcessing(content)
                    end
                end
            end

            -- Continue monitoring only if still active
            if monitoring_active then
                UIManager:scheduleIn(0.5, progress_monitor)
            end
        end

        -- Start progress monitoring
        UIManager:scheduleIn(0.5, progress_monitor)

        -- Function to handle result
        local function handleResult(result)
            -- CRITICAL: Stop progress monitoring and close UI FIRST in blocking mode
            monitoring_active = false
            UIManager:unschedule(progress_monitor)
            writeProgress("") -- Clear progress file

            -- Force close processing message immediately
            UIManager_Updates:closeProcessing()
            UIManager:forceRePaint() -- Force UI update

            -- Give UI a moment to update before processing result
            UIManager:scheduleIn(0.1, function()
                -- Handle result (can be updates table or {updates, rate_limit_hit})
                local updates = result
                local rate_limit_hit = false

                local plugin_updates = {}

                if type(result) == "table" and result.rate_limit_hit ~= nil then
                    updates = result.updates or {}
                    plugin_updates = result.plugin_updates or {}
                    rate_limit_hit = result.rate_limit_hit
                elseif type(result) == "table" then
                    -- Check if it's an array of updates (legacy format)
                    if #result > 0 then
                        updates = result
                    else
                        updates = {}
                    end
                else
                    updates = {}
                end

                -- Filter out ignored patches
                local ignored_patches = loadIgnoredPatches()
                if next(ignored_patches) then
                    local filtered_updates = {}
                    local ignored_count = 0
                    for _, update in ipairs(updates) do
                        local patch_name = update.local_patch.name or update.local_patch.filename
                        if patch_name then
                            patch_name = patch_name:gsub("%.lua$", "")
                            if not ignored_patches[patch_name] then
                                table.insert(filtered_updates, update)
                            else
                                ignored_count = ignored_count + 1
                                logger.dbg("UpdatesManager: Ignoring patch update:", patch_name)
                            end
                        end
                    end
                    updates = filtered_updates
                end

                if rate_limit_hit then
                    UIManager_Updates:showInfo(_(
                        "Rate limited by GitHub API. Please try again later or use cached data."))
                elseif (#updates == 0 and #plugin_updates == 0) then
                    UIManager_Updates:showInfo(_("No updates available"))
                else
                    -- Show combined updates list (patches + plugins)
                    UIManager_Updates:showUpdatesList(updates, plugin_updates,
                        function(selected_patches, selected_plugins)
                            if selected_patches and #selected_patches > 0 then
                                self:installUpdates(selected_patches)
                            end
                            if selected_plugins and #selected_plugins > 0 then
                                self:installPluginUpdates(selected_plugins)
                            end
                        end)
                end
            end)
        end

        -- Run in subprocess to avoid blocking UI
        -- Ensure processing_msg exists before using it as trap_widget
        if not UIManager_Updates.processing_msg then
            UIManager_Updates:showProcessing(_("Checking for updates..."))
        end
        local trap_widget = UIManager_Updates.processing_msg
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            -- Create progress callback that writes to file
            local function progressCallback(text)
                local file = io.open(progress_file, "w")
                if file then
                    file:write(text or "")
                    file:close()
                end
            end

            -- Use local functions with Utils from closure
            return checkForUpdates(self.repositories.patches, force_refresh, progressCallback)
        end, trap_widget, function(result)
            -- Callback for async completion
            handleResult(result)
        end)

        -- If subprocess didn't work (blocking mode), handle result directly
        -- CRITICAL: In blocking mode, UI is frozen, so we MUST schedule result handling
        -- to allow UI to update first
        if completed and result then
            -- Stop monitoring immediately
            monitoring_active = false
            UIManager:unschedule(progress_monitor)
            writeProgress("")

            -- Schedule UI update and result handling to allow UI to refresh
            UIManager:scheduleIn(0.2, function()
                UIManager_Updates:closeProcessing()
                UIManager:forceRePaint()

                -- Handle result after UI is closed
                UIManager:scheduleIn(0.1, function()
                    handleResult(result)
                end)
            end)
        elseif not completed then
            monitoring_active = false
            UIManager:unschedule(progress_monitor)
            writeProgress("")
            UIManager:scheduleIn(0.2, function()
                UIManager_Updates:closeProcessing()
                UIManager:forceRePaint()
                UIManager_Updates:showInfo(_("Update check was cancelled"))
            end)
        end
    end) -- Close checkNetwork callback
end

-- Install selected updates
function UpdatesManager:installUpdates(updates)
    if not updates or #updates == 0 then
        return
    end

    UIManager_Updates:showProcessing(_("Installing updates..."))

    -- Pre-load modules before subprocess
    local Version = require("version")
    local logger = require("logger")
    local lfs = require("libs/libkoreader-lfs")
    local md5 = require("ffi/MD5")
    local http = require("socket/http")
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local socket = require("socket")

    -- Inline HTTP functions (can't use Utils module in subprocess)
    local function downloadFile(url, local_path, headers)
        headers = headers or {}
        headers["User-Agent"] = headers["User-Agent"] or "KOReader-UpdatesManager/1.0"

        local dir = local_path:match("^(.*)/")
        if dir and dir ~= "" then
            if lfs.attributes(dir, "mode") ~= "directory" then
                lfs.mkdir(dir)
            end
        end

        local file = io.open(local_path, "wb")
        if not file then return false end

        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)

        local code, response_headers, status = socket.skip(1, http.request({
            url = url,
            method = "GET",
            headers = headers,
            sink = ltn12.sink.file(file),
            redirect = true,
        }))

        socketutil:reset_timeout()
        file:close()

        if code == socketutil.TIMEOUT_CODE or
            code == socketutil.SSL_HANDSHAKE_CODE or
            code == socketutil.SINK_TIMEOUT_CODE then
            pcall(os.remove, local_path)
            return false
        end

        if response_headers == nil then
            pcall(os.remove, local_path)
            return false
        end

        if code == 200 then
            return true
        else
            pcall(os.remove, local_path)
            return false
        end
    end

    local function removeFile(path)
        local ok, err = pcall(os.remove, path)
        return ok
    end

    local function copyFile(src, dst)
        local dir = dst:match("^(.*)/")
        if dir and dir ~= "" then
            if lfs.attributes(dir, "mode") ~= "directory" then
                lfs.mkdir(dir)
            end
        end

        local src_file = io.open(src, "rb")
        if not src_file then return false end

        local dst_file = io.open(dst, "wb")
        if not dst_file then
            src_file:close()
            return false
        end

        local content = src_file:read("*a")
        src_file:close()

        dst_file:write(content)
        dst_file:close()

        return true
    end

    local function fileExists(path)
        return lfs.attributes(path, "mode") == "file"
    end

    local function checkVersionRequirement(patch_path)
        local file = io.open(patch_path, "r")
        if not file then
            return true
        end

        local cur_kor_version = Version:getNormalizedCurrentVersion()

        for i = 1, 3 do
            local line = file:read("*l")
            if not line then break end

            local min_ver = line:match(':korDoesNotMeet%(%"(v.+)%"%)')
            if min_ver then
                min_ver = Version:getNormalizedVersion(min_ver)
                if min_ver and cur_kor_version < min_ver then
                    file:close()
                    return false
                end
            end
        end

        file:close()
        return true
    end

    local function installPatch(update_info)
        local local_patch = update_info.local_patch
        local repo_patch = update_info.repo_patch
        local local_path = local_patch.path

        -- Backup existing patch if it exists
        local backup_path = local_path .. ".old"
        if fileExists(local_path) then
            if not copyFile(local_path, backup_path) then
                logger.err("UpdatesManager: Failed to backup patch:", local_path)
                return false
            end
        end

        -- Download new patch
        local temp_path = local_path .. ".new"
        if update_info.repo_content then
            -- Use cached content
            local temp_file = io.open(temp_path, "w")
            if temp_file then
                temp_file:write(update_info.repo_content)
                temp_file:close()
            else
                logger.err("UpdatesManager: Failed to write temp patch file")
                return false
            end
        else
            -- Download from URL
            local url = repo_patch.download_url
            if not url then
                url = string.format("https://raw.githubusercontent.com/%s/%s/%s/",
                    repo_patch.repo_owner,
                    repo_patch.repo_name,
                    repo_patch.repo_branch
                )
                if repo_patch.repo_path and repo_patch.repo_path ~= "" then
                    url = url .. repo_patch.repo_path .. "/"
                end
                url = url .. repo_patch.name
            end

            if not downloadFile(url, temp_path) then
                logger.err("UpdatesManager: Failed to download patch")
                return false
            end
        end

        -- Verify MD5
        local downloaded_md5 = nil
        local ok, hash = pcall(md5.sumFile, temp_path)
        if ok then
            downloaded_md5 = hash
        end

        if downloaded_md5 ~= update_info.repo_md5 then
            logger.err("UpdatesManager: MD5 mismatch for downloaded patch")
            removeFile(temp_path)
            return false
        end

        -- Check version requirement
        if not checkVersionRequirement(temp_path) then
            logger.warn("UpdatesManager: Patch does not meet version requirement")
            removeFile(temp_path)
            return false
        end

        -- Install new patch
        if not copyFile(temp_path, local_path) then
            logger.err("UpdatesManager: Failed to install patch")
            removeFile(temp_path)
            return false
        end

        -- Clean up temp file
        removeFile(temp_path)

        return true
    end

    local successful = {}
    local failed = {}

    -- Function to handle installation results
    local function handleInstallResults(results)
        -- Force close processing message immediately
        UIManager_Updates:closeProcessing()
        UIManager:forceRePaint()

        -- Give UI a moment to update before showing results
        UIManager:scheduleIn(0.1, function()
            local result_successful = {}
            local result_failed = {}

            if results then
                if results.successful then
                    if type(results.successful) == "table" then
                        result_successful = results.successful
                    end
                end
                if results.failed then
                    if type(results.failed) == "table" then
                        result_failed = results.failed
                    end
                end
            end

            -- Fallback to local variables if results don't have data
            if #result_successful == 0 and #result_failed == 0 then
                result_successful = successful
                result_failed = failed
            end

            UIManager_Updates:showUpdateResults(result_successful, result_failed)
        end)
    end

    -- Ensure processing_msg exists before using it as trap_widget
    if not UIManager_Updates.processing_msg then
        UIManager_Updates:showProcessing(_("Installing updates..."))
    end
    local trap_widget = UIManager_Updates.processing_msg
    local completed, results = Trapper:dismissableRunInSubprocess(function()
        for i, update in ipairs(updates) do
            local patch_name = update.local_patch.name or update.local_patch.filename
            local ok = installPatch(update)
            if ok then
                table.insert(successful, update.local_patch)
            else
                table.insert(failed, update.local_patch)
            end
        end
        return { successful = successful, failed = failed }
    end, trap_widget, function(results)
        -- Callback for async completion
        handleInstallResults(results)
    end)

    -- If subprocess didn't work (blocking mode), handle result directly
    -- CRITICAL: In blocking mode, UI is frozen, so we MUST schedule result handling
    if completed and results then
        -- Schedule UI update and result handling to allow UI to refresh
        UIManager:scheduleIn(0.2, function()
            UIManager_Updates:closeProcessing()
            UIManager:forceRePaint()

            -- Handle results after UI is closed
            UIManager:scheduleIn(0.1, function()
                handleInstallResults(results)
            end)
        end)
    elseif not completed then
        UIManager:scheduleIn(0.2, function()
            UIManager_Updates:closeProcessing()
            UIManager:forceRePaint()
            UIManager_Updates:showInfo(_("Update installation was cancelled"))
        end)
    end
end

-- Install plugin updates
function UpdatesManager:installPluginUpdates(plugin_updates)
    if not plugin_updates or #plugin_updates == 0 then
        return
    end

    UIManager_Updates:showProcessing(_("Installing plugin updates..."))

    -- Pre-load modules before subprocess
    local logger = require("logger")
    local lfs = require("libs/libkoreader-lfs")
    local http = require("socket/http")
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local socket = require("socket")
    local Device = require("device")
    local Archiver = require("ffi/archiver")
    local Config = require("updatesmanager_config")

    -- Inline HTTP functions
    local function downloadFile(url, local_path, headers)
        headers = headers or {}
        headers["User-Agent"] = headers["User-Agent"] or "KOReader-UpdatesManager/1.0"

        local dir = local_path:match("^(.*)/")
        if dir and dir ~= "" then
            if lfs.attributes(dir, "mode") ~= "directory" then
                lfs.mkdir(dir)
            end
        end

        local file = io.open(local_path, "wb")
        if not file then return false end

        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)

        local code, response_headers, status = socket.skip(1, http.request({
            url = url,
            method = "GET",
            headers = headers,
            sink = ltn12.sink.file(file),
            redirect = true,
        }))

        socketutil:reset_timeout()

        -- Safely close file (ltn12.sink.file may have already closed it)
        pcall(function() file:close() end)

        if code == socketutil.TIMEOUT_CODE or
            code == socketutil.SSL_HANDSHAKE_CODE or
            code == socketutil.SINK_TIMEOUT_CODE then
            pcall(os.remove, local_path)
            return false
        end

        if response_headers == nil then
            pcall(os.remove, local_path)
            return false
        end

        if code == 200 then
            return true
        else
            pcall(os.remove, local_path)
            return false
        end
    end

    local function removeFile(path)
        local ok, err = pcall(os.remove, path)
        return ok
    end

    local function copyDirectory(src, dst)
        -- Simple recursive copy using os.execute
        -- Detect OS by checking package.config (Windows uses backslash)
        local is_windows = package.config:sub(1, 1) == "\\"

        if is_windows then
            -- Windows: use xcopy
            local cmd = string.format('xcopy "%s" "%s" /E /I /Y', src, dst)
            os.execute(cmd)
        else
            -- Unix-like: use cp -r
            os.execute(string.format('cp -r "%s" "%s"', src, dst))
        end
    end

    local function installPlugin(update_info)
        local installed_plugin = update_info.installed_plugin
        local release = update_info.release
        local plugin_path = installed_plugin.path
        local plugin_entry = installed_plugin.entry


        -- Backup existing plugin
        local backup_path = plugin_path .. ".old"
        local is_windows = package.config:sub(1, 1) == "\\"

        if lfs.attributes(plugin_path, "mode") == "directory" then
            -- Remove old backup if exists
            if lfs.attributes(backup_path, "mode") == "directory" then
                -- Try to remove old backup
                if is_windows then
                    os.execute(string.format('rmdir /S /Q "%s"', backup_path))
                else
                    os.execute(string.format('rm -rf "%s"', backup_path))
                end
            end
            -- Copy current plugin to backup
            copyDirectory(plugin_path, backup_path)
        end

        -- Download ZIP to temp location
        local cache_dir = Config.CACHE_DIR
        if lfs.attributes(cache_dir, "mode") ~= "directory" then
            lfs.mkdir(cache_dir)
        end
        local zip_path = cache_dir .. "/" .. plugin_entry .. ".zip"

        if not downloadFile(release.zip_url, zip_path) then
            logger.err("UpdatesManager: Failed to download plugin ZIP")
            return false
        end

        -- Extract ZIP directly to final location (with_stripped_root removes root folder from ZIP)
        local plugins_dir = Config.PLUGINS_DIR
        local final_path = plugins_dir .. "/" .. plugin_entry

        -- Remove old plugin directory first
        if lfs.attributes(plugin_path, "mode") == "directory" then
            -- Try to remove (may fail if files are in use, that's OK - user can restart)
            if is_windows then
                os.execute(string.format('rmdir /S /Q "%s"', plugin_path))
            else
                os.execute(string.format('rm -rf "%s"', plugin_path))
            end
        end

        -- Create parent directory if needed
        if lfs.attributes(plugins_dir, "mode") ~= "directory" then
            lfs.mkdir(plugins_dir)
        end

        -- Use Device:unpackArchive to extract directly to final location
        -- with_stripped_root = true removes the root folder from ZIP (e.g., pluginname.koplugin/)
        local ok, err = Device:unpackArchive(zip_path, final_path, true)
        if not ok then
            logger.err("UpdatesManager: Failed to extract plugin ZIP:", err)
            removeFile(zip_path)
            return false
        end

        -- Clean up
        removeFile(zip_path)

        return true
    end

    local successful = {}
    local failed = {}

    -- Function to handle installation results
    local function handleInstallResults(results)
        -- Force close processing message immediately
        UIManager_Updates:closeProcessing()
        UIManager:forceRePaint()

        -- Give UI a moment to update before showing results
        UIManager:scheduleIn(0.1, function()
            local result_successful = {}
            local result_failed = {}

            if results then
                if results.successful then
                    result_successful = results.successful
                end
                if results.failed then
                    result_failed = results.failed
                end
            end

            -- Fallback to local variables if results don't have data
            if #result_successful == 0 and #result_failed == 0 then
                result_successful = successful
                result_failed = failed
            end

            UIManager_Updates:showUpdateResults(result_successful, result_failed)
        end)
    end

    -- Ensure processing_msg exists before using it as trap_widget
    if not UIManager_Updates.processing_msg then
        UIManager_Updates:showProcessing(_("Installing plugin updates..."))
    end
    local trap_widget = UIManager_Updates.processing_msg
    local completed, results = Trapper:dismissableRunInSubprocess(function()
        for i, update in ipairs(plugin_updates) do
            local plugin_name = update.installed_plugin.name or "unknown"
            local ok = installPlugin(update)
            if ok then
                table.insert(successful, update.installed_plugin)
            else
                table.insert(failed, update.installed_plugin)
            end
        end
        return { successful = successful, failed = failed }
    end, trap_widget, function(results)
        -- Callback for async completion
        handleInstallResults(results)
    end)

    -- If subprocess didn't work (blocking mode), handle result directly
    if completed and results then
        UIManager:scheduleIn(0.2, function()
            UIManager_Updates:closeProcessing()
            UIManager:forceRePaint()

            UIManager:scheduleIn(0.1, function()
                handleInstallResults(results)
            end)
        end)
    elseif not completed then
        UIManager:scheduleIn(0.2, function()
            UIManager_Updates:closeProcessing()
            UIManager:forceRePaint()
            UIManager_Updates:showInfo(_("Plugin update installation was cancelled"))
        end)
    end
end

-- Check for patch updates only
-- Load list of ignored patches from file
local function loadIgnoredPatches()
    local ignored = {}
    local Config = require("updatesmanager_config")
    local ignored_file = Config.IGNORED_PATCHES_FILE

    local file = io.open(ignored_file, "r")
    if file then
        for line in file:lines() do
            -- Trim whitespace and skip empty lines and comments
            line = line:match("^%s*(.-)%s*$")
            if line and line ~= "" and not line:match("^#") then
                -- Remove .lua extension if present
                line = line:gsub("%.lua$", "")
                ignored[line] = true
            end
        end
        file:close()
    end

    return ignored
end

function UpdatesManager:checkForPatchUpdates(force_refresh)
    force_refresh = force_refresh or false
    UIManager_Updates:checkNetwork(function()
        UIManager_Updates:showProcessing(_("Checking for patch updates..."))

        -- Pre-load ALL modules before subprocess
        local Config = require("updatesmanager_config")
        local logger = require("logger")
        local lfs = require("libs/libkoreader-lfs")
        local md5 = require("ffi/MD5")
        local http = require("socket/http")
        local ltn12 = require("ltn12")
        local json = require("json")
        local socketutil = require("socketutil")
        local socket = require("socket")
        local T = require("ffi/util").template

        -- Inline HTTP functions (same as in checkForUpdates)
        local function httpGet(url, headers)
            headers = headers or {}
            headers["User-Agent"] = headers["User-Agent"] or "KOReader-UpdatesManager/1.0"
            headers["Accept"] = headers["Accept"] or "application/json"
            
            -- Add GitHub token if available and URL is GitHub API
            if url:match("api%.github%.com") or url:match("raw%.githubusercontent%.com") then
                local token = getGitHubToken()
                if token then
                    headers["Authorization"] = "token " .. token
                end
            end

            local response_body = {}
            socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)

            local code, response_headers, status = socket.skip(1, http.request({
                url = url,
                method = "GET",
                headers = headers,
                sink = ltn12.sink.table(response_body),
                redirect = true,
            }))

            socketutil:reset_timeout()

            if code == socketutil.TIMEOUT_CODE or
                code == socketutil.SSL_HANDSHAKE_CODE or
                code == socketutil.SINK_TIMEOUT_CODE then
                return nil, code or "timeout"
            end

            if response_headers == nil then
                return nil, code or "network_error"
            end

            if code == 200 then
                return table.concat(response_body), code, response_headers
            else
                return nil, code, response_headers
            end
        end

        local function parseJSON(json_string)
            local ok, result = pcall(json.decode, json_string)
            return ok and result or nil
        end

        local function getFileContent(owner, repo, branch, file_path)
            local url = string.format("https://raw.githubusercontent.com/%s/%s/%s/", owner, repo, branch) .. file_path
            local content, code = httpGet(url)
            if code == 403 or code == 429 then
                return nil
            end
            if not content or code ~= 200 then
                return nil
            end
            return content
        end

        local function getRepositoryFiles(owner, repo, branch, path)
            local url = string.format("https://api.github.com/repos/%s/%s/contents/", owner, repo)
            if path and path ~= "" then
                url = url .. path
            end
            if branch then
                url = url .. "?ref=" .. branch
            end

            local content, code = httpGet(url, {
                ["Accept"] = "application/vnd.github.v3+json",
            })

            if code == 403 or code == 429 then
                return nil
            end

            if not content or code ~= 200 then
                return nil
            end

            local files = parseJSON(content)
            if not files or type(files) ~= "table" then
                return nil
            end

            local lua_files = {}
            for _, item in ipairs(files) do
                if item.type == "file" and item.name:match("%.lua$") then
                    table.insert(lua_files, {
                        name = item.name,
                        path = item.path,
                        sha = item.sha,
                        size = item.size,
                        download_url = item.download_url,
                    })
                end
            end
            return lua_files
        end

        local function removeFile(path)
            local ok, err = pcall(os.remove, path)
            return ok
        end

        local function rateLimit()
            -- Simple rate limiting (delay handled by network latency)
        end

        local function loadCache()
            local cache_file = Config.CACHE_FILE
            local file = io.open(cache_file, "r")
            if file then
                local content = file:read("*a")
                file:close()
                local ok, cache = pcall(json.decode, content)
                if ok and cache then
                    local cache_age = os.time() - (cache.timestamp or 0)
                    if cache_age < 3600 then
                        return cache.data
                    end
                end
            end
            return nil
        end

        local function saveCache(data)
            local cache_dir = Config.CACHE_DIR
            if lfs.attributes(cache_dir, "mode") ~= "directory" then
                lfs.mkdir(cache_dir)
            end

            local cache_file = Config.CACHE_FILE
            local cache = {
                timestamp = os.time(),
                data = data
            }
            local file = io.open(cache_file, "w")
            if file then
                local ok, content = pcall(json.encode, cache)
                if ok then
                    file:write(content)
                end
                file:close()
            end
        end

        local function scanRepositoryForPatches(repo_config, compute_md5_for_local_only)
            compute_md5_for_local_only = compute_md5_for_local_only or {}
            local owner = repo_config.owner
            local repo = repo_config.repo
            local branch = repo_config.branch or "main"
            local path = repo_config.path or ""

            local files = getRepositoryFiles(owner, repo, branch, path)
            if not files then
                return {}
            end

            local patches = {}
            for _, file in ipairs(files) do
                if not file.name:match("%.disabled$") then
                    local patch_name = file.name:gsub("%.lua$", "")
                    local patch_data = {
                        name = file.name,
                        patch_name = patch_name,
                        path = file.path,
                        sha = file.sha,
                        size = file.size,
                        download_url = file.download_url,
                        repo_owner = owner,
                        repo_name = repo,
                        repo_path = path,
                        repo_branch = branch,
                        repo_url = string.format("https://github.com/%s/%s", owner, repo),
                    }

                    -- Compute MD5 on-the-fly only if patch exists locally (to speed up comparison)
                    if compute_md5_for_local_only[patch_name] then
                        rateLimit()
                        local repo_content = getFileContent(owner, repo, branch, file.path)
                        if repo_content then
                            local cache_dir = Config.CACHE_DIR
                            if lfs.attributes(cache_dir, "mode") ~= "directory" then
                                lfs.mkdir(cache_dir)
                            end
                            local temp_path = cache_dir .. "/" .. patch_name .. ".tmp"
                            local temp_file = io.open(temp_path, "w")
                            if temp_file then
                                temp_file:write(repo_content)
                                temp_file:close()

                                local ok, hash = pcall(md5.sumFile, temp_path)
                                if ok then
                                    patch_data.md5 = hash
                                    logger.dbg("UpdatesManager: Computed MD5 on-the-fly for:", patch_name)
                                end
                                removeFile(temp_path)
                            end
                        end
                    end

                    table.insert(patches, patch_data)
                end
            end

            return patches
        end

        local function scanLocalPatches()
            local patches_dir = Config.PATCHES_DIR
            local dir_mode = lfs.attributes(patches_dir, "mode")
            if not dir_mode or dir_mode ~= "directory" then
                return {}
            end

            local patches = {}
            for entry in lfs.dir(patches_dir) do
                if entry ~= "." and entry ~= ".." then
                    local full_path = patches_dir .. "/" .. entry
                    local mode = lfs.attributes(full_path, "mode")

                    if mode == "file" and entry:match("%.lua$") and not entry:match("%.disabled$") then
                        local patch_name = entry:gsub("%.lua$", "")
                        local md5_hash = nil
                        local ok, hash = pcall(md5.sumFile, full_path)
                        if ok then
                            md5_hash = hash
                        end

                        patches[patch_name] = {
                            filename = entry,
                            name = patch_name,
                            path = full_path,
                            md5 = md5_hash,
                            size = lfs.attributes(full_path, "size") or 0,
                            enabled = true,
                        }
                    end
                end
            end

            return patches
        end

        local function checkForPatchUpdates(repositories, force_refresh, progress_callback)
            progress_callback = progress_callback or function() end
            local local_patches = scanLocalPatches()
            local updates = {}
            local rate_limit_hit = false
            local rate_limit_count = 0


            local all_repo_patches = {}
            local cache_key = ""
            for _, repo_config in ipairs(repositories) do
                cache_key = cache_key ..
                    repo_config.owner .. "/" .. repo_config.repo .. "/" .. (repo_config.path or "") .. ";"
            end

            local cached_data = nil
            if not force_refresh then
                cached_data = loadCache()
            end
            local use_cache = false
            if cached_data and cached_data.cache_key == cache_key then
                use_cache = true
                all_repo_patches = cached_data.patches or {}
                local patch_count = 0
                for _ in pairs(all_repo_patches) do patch_count = patch_count + 1 end
                logger.info("UpdatesManager: Using cached repository patches:", patch_count, "patches")
                progress_callback(_("Using cached data..."))
            else
                local local_patch_names = {}
                for patch_name, _ in pairs(local_patches) do
                    local_patch_names[patch_name] = true
                end

                logger.info("UpdatesManager: Scanning all repositories (this may take a while)...")
                local total_repos = #repositories
                for i, repo_config in ipairs(repositories) do
                    if rate_limit_hit then
                        break
                    end

                    local repo_name = repo_config.owner .. "/" .. repo_config.repo
                    if repo_config.path and repo_config.path ~= "" then
                        repo_name = repo_name .. "/" .. repo_config.path
                    end
                    progress_callback(T(_("Scanning repository %1/%2: %3"), i, total_repos, repo_name))

                    rateLimit()
                    local patches = scanRepositoryForPatches(repo_config, local_patch_names)

                    if not patches and rate_limit_count > 0 then
                        rate_limit_count = rate_limit_count + 1
                        if rate_limit_count >= 3 then
                            rate_limit_hit = true
                            break
                        end
                    elseif not patches then
                        rate_limit_count = 1
                    else
                        rate_limit_count = 0
                    end

                    if patches then
                        for _, patch in ipairs(patches) do
                            local patch_key = patch.patch_name or patch.name:gsub("%.lua$", "")
                            if not all_repo_patches[patch_key] then
                                all_repo_patches[patch_key] = {
                                    patch = patch,
                                    repo_config = repo_config,
                                }
                            end
                        end
                    end
                end

                if not rate_limit_hit then
                    progress_callback(_("Saving cache..."))
                    saveCache({
                        cache_key = cache_key,
                        patches = all_repo_patches,
                    })
                end
            end

            progress_callback(_("Checking for updates..."))
            local local_patch_list = {}
            for patch_name, _ in pairs(local_patches) do
                table.insert(local_patch_list, patch_name)
            end
            local total_patches = #local_patch_list

            for idx, patch_name in ipairs(local_patch_list) do
                local local_patch = local_patches[patch_name]
                local repo_data = all_repo_patches[patch_name]
                if repo_data then
                    local repo_patch = repo_data.patch
                    local repo_config = repo_data.repo_config

                    if total_patches > 0 then
                        progress_callback(T(_("Checking patch %1/%2: %3"), idx, total_patches, patch_name))
                    end

                    local repo_md5 = repo_patch.md5

                    if not repo_md5 then
                        rateLimit()
                        local repo_content = getFileContent(
                            repo_patch.repo_owner,
                            repo_patch.repo_name,
                            repo_patch.repo_branch,
                            repo_patch.path
                        )

                        if repo_content then
                            local temp_path = local_patch.path .. ".temp_check"
                            local temp_file = io.open(temp_path, "w")
                            if temp_file then
                                temp_file:write(repo_content)
                                temp_file:close()

                                local ok, hash = pcall(md5.sumFile, temp_path)
                                if ok then
                                    repo_md5 = hash
                                end
                                removeFile(temp_path)
                            end
                        end
                    end

                    if repo_md5 and local_patch.md5 and repo_md5 ~= local_patch.md5 then
                        rateLimit()
                        local repo_content = getFileContent(
                            repo_patch.repo_owner,
                            repo_patch.repo_name,
                            repo_patch.repo_branch,
                            repo_patch.path
                        )

                        if repo_content then
                            table.insert(updates, {
                                local_patch = local_patch,
                                repo_patch = repo_patch,
                                repo_config = repo_config,
                                repo_md5 = repo_md5,
                                repo_content = repo_content,
                            })
                            logger.info("UpdatesManager: Update found for patch:", patch_name)
                        end
                    elseif not local_patch.md5 or not repo_md5 then
                        if repo_patch.size and local_patch.size and repo_patch.size ~= local_patch.size then
                            rateLimit()
                            local repo_content = getFileContent(
                                repo_patch.repo_owner,
                                repo_patch.repo_name,
                                repo_patch.repo_branch,
                                repo_patch.path
                            )
                            if repo_content then
                                local temp_path = local_patch.path .. ".temp_check"
                                local temp_file = io.open(temp_path, "w")
                                if temp_file then
                                    temp_file:write(repo_content)
                                    temp_file:close()

                                    local ok, hash = pcall(md5.sumFile, temp_path)
                                    if ok then
                                        repo_md5 = hash
                                    end
                                    removeFile(temp_path)
                                end

                                table.insert(updates, {
                                    local_patch = local_patch,
                                    repo_patch = repo_patch,
                                    repo_config = repo_config,
                                    repo_md5 = repo_md5,
                                    repo_content = repo_content,
                                })
                                logger.info("UpdatesManager: Update found for patch (size differs):", patch_name)
                            end
                        end
                    end
                end
            end

            logger.info("UpdatesManager: Found", #updates, "patch updates")
            progress_callback(_("Checking complete..."))

            return {
                updates = updates,
                rate_limit_hit = rate_limit_hit,
            }
        end

        -- Create progress file
        local progress_file = Config.CACHE_DIR .. "/progress.txt"
        local function writeProgress(text)
            local file = io.open(progress_file, "w")
            if file then
                file:write(text or "")
                file:close()
            end
        end

        writeProgress("")

        -- Monitor progress
        local progress_monitor
        local monitoring_active = true
        local last_progress = ""
        local last_update_time = 0
        progress_monitor = function()
            if not monitoring_active then
                return
            end

            local file = io.open(progress_file, "r")
            if file then
                local content = file:read("*a")
                file:close()
                if content and content ~= "" and content ~= last_progress then
                    last_progress = content
                    local now = os.time()
                    if now - last_update_time >= 0.3 then
                        last_update_time = now
                        UIManager_Updates:updateProcessing(content)
                    end
                end
            end

            if monitoring_active then
                UIManager:scheduleIn(0.5, progress_monitor)
            end
        end

        UIManager:scheduleIn(0.5, progress_monitor)

        local function handleResult(result)
            monitoring_active = false
            UIManager:unschedule(progress_monitor)
            writeProgress("")

            UIManager_Updates:closeProcessing()
            UIManager:forceRePaint()

            UIManager:scheduleIn(0.1, function()
                local updates = result
                local rate_limit_hit = false

                if type(result) == "table" and result.rate_limit_hit ~= nil then
                    updates = result.updates or {}
                    rate_limit_hit = result.rate_limit_hit
                elseif type(result) == "table" then
                    if #result > 0 then
                        updates = result
                    else
                        updates = {}
                    end
                else
                    updates = {}
                end

                -- Filter out ignored patches
                local ignored_patches = loadIgnoredPatches()
                if next(ignored_patches) then
                    local filtered_updates = {}
                    local ignored_count = 0
                    for _, update in ipairs(updates) do
                        local patch_name = update.local_patch.name or update.local_patch.filename
                        if patch_name then
                            patch_name = patch_name:gsub("%.lua$", "")
                            if not ignored_patches[patch_name] then
                                table.insert(filtered_updates, update)
                            else
                                ignored_count = ignored_count + 1
                                logger.dbg("UpdatesManager: Ignoring patch update:", patch_name)
                            end
                        end
                    end
                    updates = filtered_updates
                end

                if rate_limit_hit then
                    UIManager_Updates:showInfo(_(
                        "Rate limited by GitHub API. Please try again later or use cached data."))
                elseif not updates or #updates == 0 then
                    UIManager_Updates:showInfo(_("No patch updates available"))
                else
                    UIManager_Updates:showUpdatesList(updates, {}, function(selected_patches, selected_plugins)
                        if selected_patches and #selected_patches > 0 then
                            self:installUpdates(selected_patches)
                        end
                    end)
                end
            end)
        end

        -- Ensure processing_msg exists before using it as trap_widget
        if not UIManager_Updates.processing_msg then
            UIManager_Updates:showProcessing(_("Checking for patch updates..."))
        end
        local trap_widget = UIManager_Updates.processing_msg
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local function progressCallback(text)
                local file = io.open(progress_file, "w")
                if file then
                    file:write(text or "")
                    file:close()
                end
            end

            return checkForPatchUpdates(self.repositories.patches, force_refresh, progressCallback)
        end, trap_widget, function(result)
            handleResult(result)
        end)

        if completed and result then
            monitoring_active = false
            UIManager:unschedule(progress_monitor)
            writeProgress("")

            UIManager:scheduleIn(0.2, function()
                UIManager_Updates:closeProcessing()
                UIManager:forceRePaint()

                UIManager:scheduleIn(0.1, function()
                    handleResult(result)
                end)
            end)
        elseif not completed then
            monitoring_active = false
            UIManager:unschedule(progress_monitor)
            writeProgress("")
            UIManager:scheduleIn(0.2, function()
                UIManager_Updates:closeProcessing()
                UIManager:forceRePaint()
                UIManager_Updates:showInfo(_("Update check was cancelled"))
            end)
        end
    end)
end

-- Check for plugin updates only
function UpdatesManager:checkForPluginUpdates(force_refresh)
    force_refresh = force_refresh or false
    UIManager_Updates:checkNetwork(function()
        UIManager_Updates:showProcessing(_("Checking for plugin updates..."))

        -- Pre-load modules
        local Config = require("updatesmanager_config")
        local logger = require("logger")
        local http = require("socket/http")
        local ltn12 = require("ltn12")
        local json = require("json")
        local socketutil = require("socketutil")
        local socket = require("socket")
        local PluginManager = require("plugin_manager")

        -- Inline HTTP functions
        local function httpGet(url, headers)
            headers = headers or {}
            headers["User-Agent"] = headers["User-Agent"] or "KOReader-UpdatesManager/1.0"
            headers["Accept"] = headers["Accept"] or "application/json"
            
            -- Add GitHub token if available and URL is GitHub API
            if url:match("api%.github%.com") or url:match("raw%.githubusercontent%.com") then
                local token = getGitHubToken()
                if token then
                    headers["Authorization"] = "token " .. token
                end
            end

            local response_body = {}
            socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)

            local code, response_headers, status = socket.skip(1, http.request({
                url = url,
                method = "GET",
                headers = headers,
                sink = ltn12.sink.table(response_body),
                redirect = true,
            }))

            socketutil:reset_timeout()

            if code == socketutil.TIMEOUT_CODE or
                code == socketutil.SSL_HANDSHAKE_CODE or
                code == socketutil.SINK_TIMEOUT_CODE then
                return nil, code or "timeout"
            end

            if response_headers == nil then
                return nil, code or "network_error"
            end

            if code == 200 then
                return table.concat(response_body), code, response_headers
            else
                return nil, code, response_headers
            end
        end

        local function parseJSON(json_string)
            local ok, result = pcall(json.decode, json_string)
            return ok and result or nil
        end

        local last_request_time = 0
        local function rateLimit()
            local now = os.time()
            local time_since_last = now - last_request_time
            if time_since_last < 0.5 then
                -- Delay handled by network latency
            end
            last_request_time = os.time()
        end

        -- Create progress file
        local progress_file = Config.CACHE_DIR .. "/progress.txt"
        local function writeProgress(text)
            local file = io.open(progress_file, "w")
            if file then
                file:write(text or "")
                file:close()
            end
        end

        writeProgress("")

        -- Monitor progress
        local progress_monitor
        local monitoring_active = true
        local last_progress = ""
        local last_update_time = 0
        progress_monitor = function()
            if not monitoring_active then
                return
            end

            local file = io.open(progress_file, "r")
            if file then
                local content = file:read("*a")
                file:close()
                if content and content ~= "" and content ~= last_progress then
                    last_progress = content
                    local now = os.time()
                    if now - last_update_time >= 0.3 then
                        last_update_time = now
                        UIManager_Updates:updateProcessing(content)
                    end
                end
            end

            if monitoring_active then
                UIManager:scheduleIn(0.5, progress_monitor)
            end
        end

        UIManager:scheduleIn(0.5, progress_monitor)

        local function handleResult(result)
            monitoring_active = false
            UIManager:unschedule(progress_monitor)
            writeProgress("")

            UIManager_Updates:closeProcessing()
            UIManager:forceRePaint()

            UIManager:scheduleIn(0.1, function()
                local plugin_updates = result or {}

                if type(result) == "table" then
                    plugin_updates = result
                else
                    plugin_updates = {}
                end

                if not plugin_updates or #plugin_updates == 0 then
                    UIManager_Updates:showInfo(_("No plugin updates available"))
                else
                    UIManager_Updates:showUpdatesList({}, plugin_updates, function(selected_patches, selected_plugins)
                        if selected_plugins and #selected_plugins > 0 then
                            self:installPluginUpdates(selected_plugins)
                        end
                    end)
                end
            end)
        end

        -- Ensure processing_msg exists before using it as trap_widget
        if not UIManager_Updates.processing_msg then
            UIManager_Updates:showProcessing(_("Checking for plugin updates..."))
        end
        local trap_widget = UIManager_Updates.processing_msg
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local function progressCallback(text)
                local file = io.open(progress_file, "w")
                if file then
                    file:write(text or "")
                    file:close()
                end
            end

            -- Scan installed plugins
            local PluginManager = require("plugin_manager")
            local installed_plugins = PluginManager.scanInstalledPlugins()
            local plugin_repos = self.repositories.plugins or {}

            if #plugin_repos == 0 then
                progressCallback(_("No plugin repositories configured"))
                return {}
            end

            progressCallback(_("Checking plugin updates..."))

            -- Check plugin updates
            local plugin_updates_result = PluginManager.checkForUpdates(
                plugin_repos,
                installed_plugins,
                httpGet,
                parseJSON,
                rateLimit
            )

            progressCallback(_("Checking complete..."))

            return plugin_updates_result or {}
        end, trap_widget, function(result)
            handleResult(result)
        end)

        if completed and result then
            monitoring_active = false
            UIManager:unschedule(progress_monitor)
            writeProgress("")

            UIManager:scheduleIn(0.2, function()
                UIManager_Updates:closeProcessing()
                UIManager:forceRePaint()

                UIManager:scheduleIn(0.1, function()
                    handleResult(result)
                end)
            end)
        elseif not completed then
            monitoring_active = false
            UIManager:unschedule(progress_monitor)
            writeProgress("")
            UIManager:scheduleIn(0.2, function()
                UIManager_Updates:closeProcessing()
                UIManager:forceRePaint()
                UIManager_Updates:showInfo(_("Update check was cancelled"))
            end)
        end
    end)
end

-- Show installed patches
function UpdatesManager:showInstalledPatches()
    local patches = PatchManager.scanLocalPatches()
    UIManager_Updates:showInstalledPatchesList(patches)
end

-- Show installed plugins
function UpdatesManager:showInstalledPlugins()
    local PluginManager = require("plugin_manager")
    local plugins = PluginManager.scanInstalledPlugins()
    UIManager_Updates:showInstalledPluginsList(plugins)
end

-- Show repository settings
function UpdatesManager:showRepositorySettings()
    -- Show info about repository configuration
    local Config = require("updatesmanager_config")
    local json = require("json")
    local lfs = require("libs/libkoreader-lfs")

    local config_file = Config.CONFIG_FILE
    local config_exists = lfs.attributes(config_file, "mode") == "file"

    local info_text = _("Repository Configuration") .. "\n\n"
    info_text = info_text .. _("Configuration file:") .. "\n" .. config_file .. "\n\n"

    if config_exists then
        local file = io.open(config_file, "r")
        if file then
            local content = file:read("*a")
            file:close()
            local ok, config_data = pcall(json.decode, content)
            if ok and config_data then
                local patch_count = #(config_data.patches or {})
                local plugin_count = #(config_data.plugins or {})
                info_text = info_text ..
                    T(_("Custom repositories:\nPatches: %1\nPlugins: %2"), patch_count, plugin_count)
            else
                info_text = info_text .. _("File exists but could not be parsed")
            end
        end
    else
        info_text = info_text .. _("No custom configuration file found.\nUsing default repositories.")
    end

    info_text = info_text .. "\n\n" .. _("To add custom repositories, edit the configuration file manually.")

    UIManager_Updates:showInfo(info_text, 10)
end

-- Add to main menu
function UpdatesManager:addToMainMenu(menu_items)
    menu_items.updates_manager = {
        text = "↻ " .. _("Updates Manager"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Patches"),
                sub_item_table = {
                    {
                        text = _("Check for Updates"),
                        callback = function()
                            self:checkForPatchUpdates(false)
                        end,
                    },
                    {
                        text = _("Force Refresh (ignore cache)"),
                        callback = function()
                            self:checkForPatchUpdates(true)
                        end,
                    },
                    {
                        text = _("Installed Patches"),
                        callback = function()
                            self:showInstalledPatches()
                        end,
                    },
                },
            },
            {
                text = _("Plugins"),
                sub_item_table = {
                    {
                        text = _("Check for Updates"),
                        callback = function()
                            self:checkForPluginUpdates(false)
                        end,
                    },
                    {
                        text = _("Force Refresh"),
                        callback = function()
                            self:checkForPluginUpdates(true)
                        end,
                    },
                    {
                        text = _("Installed Plugins"),
                        callback = function()
                            self:showInstalledPlugins()
                        end,
                    },
                },
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("Repository Settings"),
                        callback = function()
                            self:showRepositorySettings()
                        end,
                    },
                    {
                        text = _("Clear Cache"),
                        callback = function()
                            self:clearCache()
                        end,
                    },
                },
            },
        },
    }
end

function UpdatesManager:addToFileManagerMenu(menu_items)
    self:addToMainMenu(menu_items)
end

return UpdatesManager
