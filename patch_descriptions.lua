--[[--
Patch Descriptions Manager
Handles loading and managing patch descriptions from multiple sources:
1. Comments in patch files
2. Local user-edited descriptions
]]--

local DataStorage = require("datastorage")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local PatchDescriptions = {}

-- Path to local descriptions file
PatchDescriptions.LOCAL_DESCRIPTIONS_FILE = DataStorage:getSettingsDir() .. "/updatesmanager_patch_descriptions.json"

-- Load local descriptions
function PatchDescriptions.loadLocalDescriptions()
    local descriptions = {}
    
    local file = io.open(PatchDescriptions.LOCAL_DESCRIPTIONS_FILE, "r")
    if file then
        local content = file:read("*a")
        file:close()
        local ok, data = pcall(json.decode, content)
        if ok and data then
            descriptions = data
        end
    end
    
    return descriptions
end

-- Save local descriptions
function PatchDescriptions.saveLocalDescriptions(descriptions)
    local settings_dir = DataStorage:getSettingsDir()
    if lfs.attributes(settings_dir, "mode") ~= "directory" then
        lfs.mkdir(settings_dir)
    end
    
    local ok, content = pcall(json.encode, descriptions)
    if not ok then
        logger.err("UpdatesManager: Failed to encode patch descriptions")
        return false
    end
    
    local file = io.open(PatchDescriptions.LOCAL_DESCRIPTIONS_FILE, "w")
    if file then
        file:write(content)
        file:close()
        return true
    end
    
    return false
end

-- Parse description from patch file comments
function PatchDescriptions.parseFromComments(patch_content)
    if not patch_content or patch_content == "" then
        return nil
    end
    
    local description_lines = {}
    local in_description = false
    
    for line in patch_content:gmatch("([^\n]+)") do
        -- Check for comment lines
        if line:match("^%-%-") then
            local comment = line:match("^%-%-%s*(.+)")
            if comment then
                -- Skip metadata comments like --[[-- or --]]
                if not comment:match("^%[%[") and not comment:match("%]%]$") then
                    -- Skip decorative lines (========, ----, etc.)
                    local trimmed = comment:match("^%s*(.-)%s*$")
                    if trimmed and trimmed ~= "" then
                        -- Skip lines that are mostly decorative characters
                        if not trimmed:match("^[=%-_%.%*#]+$") and
                           -- Skip version checks and other metadata
                           not trimmed:match("^%s*@") and 
                           not trimmed:match("^%s*version") and
                           not trimmed:match("^%s*requires") and
                           -- Skip lines with "Edit your" or similar template text
                           not trimmed:match("^%[%[.*[Ee]dit") and
                           not trimmed:match("[Ee]dit your") then
                            table.insert(description_lines, trimmed)
                            in_description = true
                        end
                    end
                end
            end
        elseif in_description then
            -- Stop at first non-comment line after description
            break
        end
    end
    
    if #description_lines > 0 then
        return table.concat(description_lines, "\n")
    end
    
    return nil
end

-- Get description for a patch (priority: local > comments)
function PatchDescriptions.getDescription(patch_name, repo_patch, patch_content)
    -- Priority 1: Local user-edited description
    local local_descriptions = PatchDescriptions.loadLocalDescriptions()
    if local_descriptions[patch_name] and local_descriptions[patch_name] ~= "" then
        return local_descriptions[patch_name]
    end
    
    -- Priority 2: Parse from patch file comments
    if patch_content then
        local comment_desc = PatchDescriptions.parseFromComments(patch_content)
        if comment_desc and comment_desc ~= "" then
            return comment_desc
        end
    end
    
    return nil
end

-- Set local description for a patch
function PatchDescriptions.setDescription(patch_name, description)
    local descriptions = PatchDescriptions.loadLocalDescriptions()
    descriptions[patch_name] = description or ""
    return PatchDescriptions.saveLocalDescriptions(descriptions)
end

return PatchDescriptions

