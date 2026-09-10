--[[--
Plugin Manager for Updates Manager
Handles plugin update checking and installation
]]--

local DataStorage = require("datastorage")
local logger = require("logger")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")

local PluginManager = {}

-- Path to plugins directory
PluginManager.PLUGINS_DIR = DataStorage:getDataDir() .. "/plugins"

-- Get latest release from GitHub repository (legacy function, kept for compatibility)
-- Note: This function uses Utils which may not be available in subprocess
-- Use checkForUpdates instead which accepts httpGet/parseJSON as parameters
function PluginManager.getLatestRelease(owner, repo)
    local Utils = require("utils")
    local api_url = string.format("https://api.github.com/repos/%s/%s/releases/latest", owner, repo)
    
    local content, code = Utils.httpGet(api_url, {
        ["Accept"] = "application/vnd.github.v3+json",
    })
    
    if not content or code ~= 200 then
        logger.warn("UpdatesManager: Failed to get latest release:", api_url, code)
        return nil
    end
    
    local release = Utils.parseJSON(content)
    if not release then
        return nil
    end
    
    return {
        tag_name = release.tag_name,
        name = release.name,
        body = release.body,
        published_at = release.published_at,
        assets = release.assets or {},
        html_url = release.html_url,
    }
end

-- Scan installed plugins and read their metadata
function PluginManager.scanInstalledPlugins(include_defaults)
    include_defaults = include_defaults or false
    local plugins = {}
    local plugins_dir = PluginManager.PLUGINS_DIR
    
    -- Load default plugins list
    local Config = require("updatesmanager_config")
    local default_plugins_map = {}
    if not include_defaults then
        for _, default_name in ipairs(Config.DEFAULT_PLUGINS or {}) do
            default_plugins_map[default_name] = true
        end
    end
    
    if not lfs.attributes(plugins_dir, "mode") or lfs.attributes(plugins_dir, "mode") ~= "directory" then
        logger.info("UpdatesManager: Plugins directory does not exist:", plugins_dir)
        return plugins
    end
    
    for entry in lfs.dir(plugins_dir) do
        if entry ~= "." and entry ~= ".." then
            local plugin_path = plugins_dir .. "/" .. entry
            local mode = lfs.attributes(plugin_path, "mode")
            
            -- Check if it's a plugin directory (ends with .koplugin)
            if mode == "directory" and entry:match("%.koplugin$") then
                local meta_file = plugin_path .. "/_meta.lua"
                if lfs.attributes(meta_file, "mode") == "file" then
                    -- Try to load _meta.lua
                    local ok, meta_data = pcall(dofile, meta_file)
                    if ok and meta_data and type(meta_data) == "table" then
                        local plugin_name = meta_data.name or entry:gsub("%.koplugin$", "")
                        
                        -- Skip default plugins unless explicitly requested
                        if not include_defaults and default_plugins_map[plugin_name] then
                            goto continue
                        end
                        
                        plugins[plugin_name] = {
                            name = plugin_name,
                            fullname = meta_data.fullname or plugin_name,
                            version = meta_data.version or "unknown",
                            description = meta_data.description or "",
                            path = plugin_path,
                            entry = entry,
                            meta = meta_data,
                        }
                    end
                end
            end
            ::continue::
        end
    end
    
    return plugins
end

-- Compare versions (semantic versioning)
-- Returns: true if v1 is newer than v2, false otherwise
-- Supports: "1.0.0", "v1.0.0", or numeric values (converted to string)
function PluginManager.isVersionNewer(v1_str, v2_str)
    if not v1_str or not v2_str then return false end
    
    -- Convert to strings if they are numbers (handles cases where version is numeric in _meta.lua)
    v1_str = tostring(v1_str)
    v2_str = tostring(v2_str)
    
    if v1_str == v2_str then return false end
    
    -- Strip optional leading 'v' prefix (handles "v1.0.0" format)
    v1_str = v1_str:match("^v?(.*)$")
    v2_str = v2_str:match("^v?(.*)$")
    
    -- Normalize versions (handle cases like "1.10" vs "1.2")
    local function normalizeVersion(v_str)
        -- Split by dots
        local parts = {}
        for part in v_str:gmatch("([^.-]+)") do
            local num = tonumber(part)
            if num then
                table.insert(parts, num)
            else
                -- For non-numeric parts, use 0 (pre-release handling)
                table.insert(parts, 0)
            end
        end
        return parts
    end
    
    local v1_parts = normalizeVersion(v1_str)
    local v2_parts = normalizeVersion(v2_str)
    
    -- Compare version parts
    local max_len = math.max(#v1_parts, #v2_parts)
    for i = 1, max_len do
        local p1 = v1_parts[i] or 0
        local p2 = v2_parts[i] or 0
        
        if p1 > p2 then return true end
        if p1 < p2 then return false end
    end
    
    return false -- Versions are equal
end

-- Match plugin name to repository
-- Tries multiple strategies to match installed plugin with repository
local function matchPluginToRepo(plugin_name, repo_name, installed_plugin)
    -- Strategy 1: Exact match
    if plugin_name == repo_name then
        return true
    end
    
    -- Strategy 2: Remove .koplugin suffix from repo
    local repo_base = repo_name:gsub("%.koplugin$", "")
    if plugin_name == repo_base then
        return true
    end
    
    -- Strategy 3: Case-insensitive match
    if plugin_name:lower() == repo_name:lower() then
        return true
    end
    
    -- Strategy 4: Check if plugin entry (directory name) matches
    if installed_plugin and installed_plugin.entry then
        local entry_base = installed_plugin.entry:gsub("%.koplugin$", "")
        if entry_base == repo_name or entry_base == repo_base then
            return true
        end
    end
    
    return false
end

-- Jobs for installed plugins that match a configured repository (no HTTP).
function PluginManager.listInstalledCheckJobs(plugin_repos, installed_plugins)
    local jobs = {}
    local installed_map = installed_plugins or {}

    for _, repo_config in ipairs(plugin_repos or {}) do
        for plugin_name, plugin_data in pairs(installed_map) do
            if matchPluginToRepo(plugin_name, repo_config.repo, plugin_data) then
                table.insert(jobs, {
                    repo_config = repo_config,
                    installed_plugin = plugin_data,
                    matched_name = plugin_name,
                })
                break
            end
        end
    end

    return jobs
end

-- One GitHub releases/latest request for a single installed plugin.
-- Returns an update table or nil.
function PluginManager.checkSingleInstalled(repo_config, installed_plugin, matched_name, httpGet, parseJSON)
    httpGet = httpGet or function() return nil, 0 end
    parseJSON = parseJSON or function() return nil end

    local owner = repo_config.owner
    local repo = repo_config.repo
    local api_url = string.format("https://api.github.com/repos/%s/%s/releases/latest", owner, repo)
    local content, code = httpGet(api_url, {
        ["Accept"] = "application/vnd.github.v3+json",
    })

    if not content or code ~= 200 then
        if code ~= 404 then
            logger.warn("UpdatesManager: Failed to get latest release:", api_url, code)
        end
        return nil, false
    end

    local release_data = parseJSON(content)
    if not release_data or not release_data.tag_name then
        return nil, false
    end

    local release_version = release_data.tag_name:gsub("^v", "")
    local installed_version = installed_plugin.version or "0.0.0"

    if not PluginManager.isVersionNewer(release_version, installed_version) then
        return nil, true
    end

    logger.info("UpdatesManager: Update found for plugin:", matched_name,
               "installed:", installed_version, "available:", release_version)

    local zip_asset = nil
    local asset_pattern = repo_config.asset_pattern
    local lua_pattern = nil
    if asset_pattern then
        local ends_with_anchor = asset_pattern:match("%$$")
        local has_wildcard = asset_pattern:match("%*")
        local has_escaped_dots = asset_pattern:match("%%.")

        if has_wildcard and not has_escaped_dots then
            lua_pattern = asset_pattern:gsub("%.", "%%."):gsub("%*", ".*")
        else
            lua_pattern = asset_pattern
        end

        if not ends_with_anchor then
            lua_pattern = lua_pattern .. "$"
        end
    else
        lua_pattern = "%.zip$"
    end

    for _, asset in ipairs(release_data.assets or {}) do
        if asset.name:match(lua_pattern) then
            zip_asset = asset
            break
        end
    end

    if not zip_asset then
        local pattern_info = asset_pattern and (" (pattern: " .. asset_pattern .. ")") or ""
        logger.warn("UpdatesManager: No matching asset found for plugin:", matched_name .. pattern_info)
        return nil, true
    end

    return {
        installed_plugin = installed_plugin,
        repo_config = repo_config,
        release = {
            tag_name = release_data.tag_name,
            version = release_version,
            name = release_data.name or release_data.tag_name,
            body = release_data.body or "",
            published_at = release_data.published_at,
            html_url = release_data.html_url,
            zip_url = zip_asset.browser_download_url,
            zip_name = zip_asset.name,
            zip_size = zip_asset.size,
        },
    }, true
end

-- Check for plugin updates (installed plugins only)
function PluginManager.checkForUpdates(plugin_repos, installed_plugins, httpGet, parseJSON, rateLimit)
    httpGet = httpGet or function() return nil, 0 end
    parseJSON = parseJSON or function() return nil end
    rateLimit = rateLimit or function() end

    local updates = {}
    local jobs = PluginManager.listInstalledCheckJobs(plugin_repos, installed_plugins)

    for _, job in ipairs(jobs) do
        rateLimit()
        local update = PluginManager.checkSingleInstalled(
            job.repo_config,
            job.installed_plugin,
            job.matched_name,
            httpGet,
            parseJSON
        )
        if update then
            table.insert(updates, update)
        end
    end

    return updates
end

-- Download plugin release asset
function PluginManager.downloadPluginRelease(update_info, local_path, downloadFile)
    downloadFile = downloadFile or function() return false end
    
    local release = update_info.release
    if not release or not release.zip_url then
        logger.warn("UpdatesManager: No ZIP URL in release")
        return false
    end
    
    return downloadFile(release.zip_url, local_path)
end

return PluginManager

