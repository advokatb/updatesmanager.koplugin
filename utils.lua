--[[--
Utility functions for Updates Manager
HTTP requests, file operations, MD5 checksums, etc.
]]--

local http = require("socket/http")
local ltn12 = require("ltn12")
local json = require("json")
local md5 = require("ffi/MD5")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local socketutil = require("socketutil")
local socket = require("socket")

local Utils = {}
local Config = require("updatesmanager_config")

-- Cache for GitHub token (loaded once per session)
local cached_token = nil

-- Load GitHub token (with caching)
local function getGitHubToken()
    if cached_token ~= nil then
        return cached_token
    end
    
    cached_token = Config.loadGitHubToken()
    return cached_token
end

-- Make HTTP GET request and return response
function Utils.httpGet(url, headers)
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
    
    -- Check for timeouts
    if code == socketutil.TIMEOUT_CODE or
       code == socketutil.SSL_HANDSHAKE_CODE or
       code == socketutil.SINK_TIMEOUT_CODE then
        logger.warn("UpdatesManager: Request timed out:", code)
        return nil, code or "timeout"
    end
    
    -- Check for network errors
    if response_headers == nil then
        logger.warn("UpdatesManager: Network error:", status or code)
        return nil, code or "network_error"
    end
    
    if code == 200 then
        local content = table.concat(response_body)
        return content, code, response_headers
    else
        logger.warn("UpdatesManager: HTTP request returned code:", code, status)
        return nil, code, response_headers
    end
end

-- Download file from URL to local path
function Utils.downloadFile(url, local_path, headers)
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
        Utils.ensureDirectory(dir)
    end
    
    local file = io.open(local_path, "wb")
    if not file then
        logger.err("UpdatesManager: Failed to open file for writing:", local_path)
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
    
    -- Check for timeouts
    if code == socketutil.TIMEOUT_CODE or
       code == socketutil.SSL_HANDSHAKE_CODE or
       code == socketutil.SINK_TIMEOUT_CODE then
        logger.warn("UpdatesManager: Download timed out:", code)
        pcall(os.remove, local_path)
        return false
    end
    
    -- Check for network errors
    if response_headers == nil then
        logger.warn("UpdatesManager: Network error during download:", status or code)
        pcall(os.remove, local_path)
        return false
    end
    
    if code == 200 then
        logger.info("UpdatesManager: File downloaded:", local_path)
        return true
    else
        logger.warn("UpdatesManager: Download returned code:", code, status)
        pcall(os.remove, local_path)
        return false
    end
end

-- Get MD5 hash of file
function Utils.getFileMD5(file_path)
    local ok, hash = pcall(md5.sumFile, file_path)
    if ok then
        return hash
    else
        logger.warn("UpdatesManager: Failed to calculate MD5 for:", file_path)
        return nil
    end
end

-- Check if file exists
function Utils.fileExists(path)
    return lfs.attributes(path, "mode") == "file"
end

-- Check if directory exists
function Utils.directoryExists(path)
    if not path then return false end
    local mode = lfs.attributes(path, "mode")
    return mode == "directory"
end

-- Ensure directory exists (create if needed)
function Utils.ensureDirectory(path)
    if Utils.directoryExists(path) then
        return true
    end
    
    -- Try to create directory
    local ok, err = pcall(lfs.mkdir, path)
    if ok then
        return true
    else
        logger.warn("UpdatesManager: Failed to create directory:", path, err)
        return false
    end
end

-- Copy file
function Utils.copyFile(src, dst)
    -- Ensure destination directory exists
    local dir = dst:match("^(.*)/")
    if dir and dir ~= "" then
        Utils.ensureDirectory(dir)
    end
    
    local src_file = io.open(src, "rb")
    if not src_file then
        logger.err("UpdatesManager: Failed to open source file:", src)
        return false
    end
    
    local dst_file = io.open(dst, "wb")
    if not dst_file then
        src_file:close()
        logger.err("UpdatesManager: Failed to open destination file:", dst)
        return false
    end
    
    local content = src_file:read("*a")
    src_file:close()
    
    dst_file:write(content)
    dst_file:close()
    
    return true
end

-- Remove file
function Utils.removeFile(path)
    local ok, err = pcall(os.remove, path)
    if not ok then
        logger.warn("UpdatesManager: Failed to remove file:", path, err)
    end
    return ok
end

-- Parse JSON string
function Utils.parseJSON(json_string)
    local ok, result = pcall(json.decode, json_string)
    if ok then
        return result
    else
        logger.warn("UpdatesManager: Failed to parse JSON:", result)
        return nil
    end
end

-- Extract GitHub username from repository URL
function Utils.extractGitHubUser(repo_url)
    local user = repo_url:match("github%.com/([^/]+)/")
    return user or "unknown"
end

-- Extract repository name from URL
function Utils.extractRepoName(repo_url)
    local repo = repo_url:match("github%.com/[^/]+/([^/]+)")
    return repo or "unknown"
end

-- Check if patch file is disabled (.disabled extension)
function Utils.isPatchDisabled(file_path)
    return file_path:match("%.disabled$") ~= nil
end

-- Get patch name without extension and .disabled
function Utils.getPatchName(file_path)
    local name = file_path:match("([^/]+)$")
    if name then
        name = name:gsub("%.disabled$", "")
        name = name:gsub("%.lua$", "")
        return name
    end
    return nil
end

-- Check if file is a patch file (.lua)
function Utils.isPatchFile(file_path)
    return file_path:match("%.lua$") ~= nil
end

return Utils

