--[[--
Patch Manager for Updates Manager
Handles local patch scanning, update checking, and installation
]]--

local Config = require("updatesmanager_config")
local RepositoryManager = require("repository_manager")
local Version = require("version")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/MD5")

-- Local variable to store injected Utils (for subprocess compatibility)
local injected_Utils = nil

-- Utils will be injected before use, or loaded here if not in subprocess
local function getUtils()
    if injected_Utils then
        return injected_Utils
    end
    local ok, utils = pcall(require, "utils")
    if ok and utils then
        return utils
    end
    error("Utils module not available")
end

local PatchManager = {}

-- Function to inject Utils (called from main.lua before subprocess)
function PatchManager.setUtils(Utils)
    injected_Utils = Utils
end

-- Scan local patches directory for installed patches
function PatchManager.scanLocalPatches()
    local patches_dir = Config.PATCHES_DIR
    
    -- Check if directory exists using lfs directly (more reliable)
    local dir_mode = lfs.attributes(patches_dir, "mode")
    if not dir_mode or dir_mode ~= "directory" then
        logger.info("UpdatesManager: Patches directory does not exist:", patches_dir)
        return {}
    end
    
    local patches = {}
    local md5 = require("ffi/MD5")
    
    for entry in lfs.dir(patches_dir) do
        if entry ~= "." and entry ~= ".." then
            local full_path = patches_dir .. "/" .. entry
            local mode = lfs.attributes(full_path, "mode")
            
            -- Check if it's a .lua file (patch file)
            if mode == "file" and entry:match("%.lua$") then
                -- Skip disabled patches (files ending with .disabled)
                if not entry:match("%.disabled$") then
                    -- Get patch name (remove .lua extension)
                    local patch_name = entry:gsub("%.lua$", "")
                    
                    -- Calculate MD5 hash
                    local md5_hash = nil
                    local ok, hash = pcall(md5.sumFile, full_path)
                    if ok then
                        md5_hash = hash
                    end
                    
                    patches[entry] = {
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
    end
    
    local patch_list = {}
    for _, patch in pairs(patches) do
        table.insert(patch_list, patch)
    end
    
    logger.info("UpdatesManager: Found", #patch_list, "local patches")
    return patches, patch_list -- Return both table (for lookup) and list (for iteration)
end

-- Check if patch meets KOReader version requirements
function PatchManager.checkVersionRequirement(patch_path)
    local file = io.open(patch_path, "r")
    if not file then
        return true -- Can't read, assume OK
    end
    
    local cur_kor_version = Version:getNormalizedCurrentVersion()
    
    -- Check first few lines for version requirement
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

-- Find patch in repository list
function PatchManager.findPatchInRepositories(patch_filename, repositories)
    for _, repo_config in ipairs(repositories) do
        local patches = RepositoryManager.scanRepositoryForPatches(repo_config)
        
        for _, patch in ipairs(patches) do
            if patch.name == patch_filename then
                return patch, repo_config
            end
        end
    end
    
    return nil, nil
end

-- Check for updates in all repositories
function PatchManager.checkForUpdates(repositories)
    local local_patches = PatchManager.scanLocalPatches()
    local updates = {}
    
    logger.info("UpdatesManager: Checking for updates in", #repositories, "repositories")
    
    -- For each local patch, check if it exists in repositories and if it's updated
    for filename, local_patch in pairs(local_patches) do
        local repo_patch, repo_config = PatchManager.findPatchInRepositories(filename, repositories)
        
        if repo_patch then
            -- Check if file has changed (compare SHA or download and compare MD5)
            local repo_content = RepositoryManager.getFileContent(
                repo_patch.repo_owner,
                repo_patch.repo_name,
                repo_patch.repo_branch,
                repo_patch.path
            )
            
            if repo_content then
                -- Write to temp file to calculate MD5
                local temp_path = local_patch.path .. ".temp_check"
                local temp_file = io.open(temp_path, "w")
                if temp_file then
                    temp_file:write(repo_content)
                    temp_file:close()
                    
                    local Utils = getUtils()
                    local repo_md5 = Utils.getFileMD5(temp_path)
                    Utils.removeFile(temp_path)
                    
                    if repo_md5 and repo_md5 ~= local_patch.md5 then
                        -- Update available!
                        table.insert(updates, {
                            local_patch = local_patch,
                            repo_patch = repo_patch,
                            repo_config = repo_config,
                            repo_md5 = repo_md5,
                            repo_content = repo_content,
                        })
                        logger.info("UpdatesManager: Update found for patch:", filename)
                    end
                end
            end
        end
    end
    
    logger.info("UpdatesManager: Found", #updates, "updates")
    return updates
end

-- Install/update patch
function PatchManager.installPatch(update_info)
    local local_patch = update_info.local_patch
    local repo_patch = update_info.repo_patch
    local local_path = local_patch.path
    
    -- Backup existing patch if it exists
    local backup_path = local_path .. ".old"
    local Utils = getUtils()
    if Utils.fileExists(local_path) then
        if not Utils.copyFile(local_path, backup_path) then
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
        if not RepositoryManager.downloadPatch(repo_patch, temp_path) then
            logger.err("UpdatesManager: Failed to download patch")
            return false
        end
    end
    
    -- Verify MD5
    local Utils = getUtils()
    local downloaded_md5 = Utils.getFileMD5(temp_path)
    if downloaded_md5 ~= update_info.repo_md5 then
        logger.err("UpdatesManager: MD5 mismatch for downloaded patch")
        Utils.removeFile(temp_path)
        return false
    end
    
    -- Check version requirement
    if not PatchManager.checkVersionRequirement(temp_path) then
        logger.warn("UpdatesManager: Patch does not meet version requirement")
        Utils.removeFile(temp_path)
        return false
    end
    
    -- Install new patch
    if not Utils.copyFile(temp_path, local_path) then
        logger.err("UpdatesManager: Failed to install patch")
        Utils.removeFile(temp_path)
        return false
    end
    
    -- Clean up temp file
    Utils.removeFile(temp_path)
    
    logger.info("UpdatesManager: Patch installed successfully:", local_path)
    return true
end

-- Get patch information (author, description, etc.)
function PatchManager.getPatchInfo(update_info)
    local info = {
        name = update_info.repo_patch.name,
        author = update_info.repo_patch.repo_owner,
        repo_url = update_info.repo_patch.repo_url,
        repo_name = update_info.repo_patch.repo_name,
        size = update_info.repo_patch.size,
        description = "", -- Could be extracted from README or patch comments
    }
    
    -- Try to extract description from patch content
    if update_info.repo_content then
        -- Look for description in comments at the top of file
        for line in update_info.repo_content:gmatch("([^\n]+)") do
            if line:match("^%-%-") then
                local desc = line:match("^%-%-%s*(.+)")
                if desc and desc ~= "" then
                    info.description = desc
                    break
                end
            else
                break -- Stop at first non-comment line
            end
        end
    end
    
    return info
end

return PatchManager

