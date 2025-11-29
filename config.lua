--[[--
Configuration for Updates Manager plugin
Contains repository lists and settings
]] --

local DataStorage = require("datastorage")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Config = {}

-- Default list of patch repositories
Config.DEFAULT_PATCH_REPOS = {
    {
        owner = "joshuacant",
        repo = "KOReader.patches",
        branch = "main",
        path = "", -- root path
        description = "Joshua Cant's patches",
    },
    {
        owner = "angelsangita",
        repo = "Koreader-Patches",
        branch = "main",
        path = "",
        description = "Angelsangita's patches",
    },
    {
        owner = "SeriousHornet",
        repo = "KOReader.patches",
        branch = "main",
        path = "",
        description = "SeriousHornet's patches",
    },
    {
        owner = "sebdelsol",
        repo = "KOReader.patches",
        branch = "main",
        path = "",
        description = "Sebdelsol's patches",
    },
    {
        owner = "zenixlabs",
        repo = "koreader-frankenpatches-public",
        branch = "main",
        path = "",
        description = "Zenixlabs patches",
    },
    {
        owner = "omer-faruq",
        repo = "koreader-user-patches",
        branch = "main",
        path = "",
        description = "Omer Faruq's patches",
    },
    {
        owner = "loeffner",
        repo = "KOReader.patches",
        branch = "main",
        path = "project-title", -- patches in subfolder
        description = "Loeffner's project-title patches",
    },
    {
        owner = "advokatb",
        repo = "KOReader-Patches",
        branch = "main",
        path = "",
        description = "Advokatb's patches",
    },
    {
        owner = "prashanthglen",
        repo = "kojustifystatusbar",
        branch = "main",
        path = "",
        description = "Justify status bar patch",
    },
    {
        owner = "clarainna",
        repo = "KOReader-Patches",
        branch = "main",
        path = "",
        description = "Clarainna's patches",
    },
    {
        owner = "whatsnewsisyphus",
        repo = "koreader-patches",
        branch = "main",
        path = "",
        description = "Whatsnewsisyphus's patches",
    },
}

-- Default list of plugin repositories
Config.DEFAULT_PLUGIN_REPOS = {
    {
        owner = "loeffner",
        repo = "WeatherLockscreen",
        description = "Weather Lockscreen plugin",
    },
    {
        owner = "advokatb",
        repo = "readingstreak.koplugin",
        description = "Reading Streak plugin",
    },
    {
        owner = "advokatb",
        repo = "updatesmanager.koplugin",
        description = "Updates Manager plugin",
    },
    {
        owner = "marinov752",
        repo = "emailtokoreader.koplugin",
        description = "Email to KOReader plugin",
    },
    {
        owner = "omer-faruq",
        repo = "memobook.koplugin",
        description = "Memo Book plugin",
    },
    {
        owner = "omer-faruq",
        repo = "rssreader.koplugin",
        description = "RSS Reader plugin",
    },
    {
        owner = "kodermike",
        repo = "airplanemode.koplugin",
        description = "Airplane Mode plugin",
    },
    {
        owner = "kristianpennacchia",
        repo = "zzz-readermenuredesign.koplugin",
        description = "Reader Menu Redesign plugin",
    },
    {
        owner = "kristianpennacchia",
        repo = "wordreference.koplugin",
        description = "WordReference plugin",
    },
    {
        owner = "patelneeraj",
        repo = "filebrowserplus.koplugin",
        description = "File Browser Plus plugin",
    },
    {
        owner = "omer-faruq",
        repo = "webbrowser.koplugin",
        description = "Web Browser plugin",
    },
    {
        owner = "omer-faruq",
        repo = "assistant.koplugin",
        description = "AI Assistant plugin",
    },
    {
        owner = "0xmiki",
        repo = "telegramhighlights.koplugin",
        description = "Telegram Highlights plugin",
    },
    {
        owner = "JoeBumm",
        repo = "Koreader-Menu-customizer",
        description = "Menu Customizer plugin",
    },
    {
        owner = "dani84bs",
        repo = "AnnotationSync.koplugin",
        description = "Sync annotations between devices",
    },
    {
        owner = "agaragou",
        repo = "illustrations.koplugin",
        description = "Illustrations plugin",
    },
    {
        owner = "omer-faruq",
        repo = "tbrplanner.koplugin",
        description = "TBR Planner plugin",
    },
    {
        owner = "omer-faruq",
        repo = "nonogram.koplugin",
        description = "Nonogram plugin",
    },
    -- {
    --     owner = "joshuacant",
    --     repo = "ProjectTitle",
    --     description = "Project Title plugin",
    -- },
    -- Commented out repositories (no proper releases)
    -- {
    --     owner = "bozo22",
    --     repo = "imagebookmarks.koplugin",
    --     description = "Image Bookmarks plugin",
    -- },
    -- {
    --     owner = "roygbyte",
    --     repo = "weather.koplugin",
    --     description = "Weather plugin",
    -- },
    -- {
    --     owner = "0zd3m1r",
    --     repo = "koreader-booknotes-plugin",
    --     description = "Book Notes plugin",
    -- },
    -- {
    --     owner = "0zd3m1r",
    --     repo = "koreader-xray-plugin",
    --     description = "X-Ray plugin",
    -- },
    -- {
    --     owner = "Billiam",
    --     repo = "crashlog.koplugin",
    --     description = "Crash Log plugin",
    -- },
    -- {
    --     owner = "Billiam",
    --     repo = "hardcoverapp.koplugin",
    --     description = "Hardcover App plugin",
    -- },
    -- {
    --     owner = "monk-blade",
    --     repo = "multiline-toc-koreader",
    --     description = "Multiline TOC plugin",
    -- },
    -- {
    --     owner = "Evgeniy-94",
    --     repo = "TelegramDownloader.koplugin",
    --     description = "Telegram Downloader plugin",
    -- },
    -- {
    --     owner = "greywolf1499",
    --     repo = "opds_plus.koplugin",
    --     description = "OPDS Plus plugin",
    -- },
}

-- Paths
Config.PATCHES_DIR = DataStorage:getDataDir() .. "/patches"
Config.PLUGINS_DIR = DataStorage:getDataDir() .. "/plugins"
Config.CONFIG_FILE = DataStorage:getSettingsDir() .. "/updatesmanager_config.json"
Config.CACHE_DIR = DataStorage:getSettingsDir() .. "/updatesmanager_cache"
Config.CACHE_FILE = Config.CACHE_DIR .. "/repository_cache.json"
Config.PLUGIN_CACHE_FILE = Config.CACHE_DIR .. "/plugin_cache.json"
Config.PATCH_DESCRIPTIONS_FILE = DataStorage:getSettingsDir() .. "/updatesmanager_patch_descriptions.json"
Config.IGNORED_PATCHES_FILE = DataStorage:getSettingsDir() .. "/updatesmanager_ignored_patches.txt"

-- Default plugins that come with KOReader (should be hidden from installed plugins list)
Config.DEFAULT_PLUGINS = {
    "archiveviewer",
    "autodim",
    "autostandby",
    "autosuspend",
    "autoturn",
    "autowarmth",
    "batterystat",
    "bookshortcuts",
    "calibre",
    "coverbrowser",
    "coverimage",
    "docsettingtweak",
    "exporter",
    "externalkeyboard",
    "gestures",
    "hello",
    "hotkeys",
    "httpinspector",
    "japanese",
    "keepalive",
    "kosync",
    "movetoarchive",
    "newsdownloader",
    "opds",
    "perceptionexpander",
    "profiles",
    "qrclipboard",
    "readtimer",
    "SSH",
    "statistics",
    "systemstat",
    "terminal",
    "texteditor",
    "timesync",
    "vocabbuilder",
    "wallabag",
}

-- Load custom repository list from config file
function Config.loadRepositories()
    local repos = {
        patches = {},
        plugins = {},
    }

    -- Start with defaults
    for _, repo in ipairs(Config.DEFAULT_PATCH_REPOS) do
        table.insert(repos.patches, repo)
    end

    for _, repo in ipairs(Config.DEFAULT_PLUGIN_REPOS) do
        table.insert(repos.plugins, repo)
    end

    -- Try to load custom config
    local config_file = io.open(Config.CONFIG_FILE, "r")
    if config_file then
        local content = config_file:read("*a")
        config_file:close()

        local ok, custom_config = pcall(json.decode, content)
        if ok and custom_config then
            -- Merge custom repositories
            if custom_config.patches then
                for _, repo in ipairs(custom_config.patches) do
                    table.insert(repos.patches, repo)
                end
            end
            if custom_config.plugins then
                for _, repo in ipairs(custom_config.plugins) do
                    table.insert(repos.plugins, repo)
                end
            end
        end
    end

    return repos
end

-- Save custom repository list to config file
function Config.saveRepositories(repos)
    local ok, content = pcall(json.encode, repos)
    if not ok then
        logger.err("UpdatesManager: Failed to encode repository configuration")
        return false
    end

    -- Ensure settings directory exists
    local settings_dir = DataStorage:getSettingsDir()
    if lfs.attributes(settings_dir, "mode") ~= "directory" then
        lfs.mkdir(settings_dir)
    end

    local config_file = io.open(Config.CONFIG_FILE, "w")
    if config_file then
        config_file:write(content)
        config_file:close()
        return true
    else
        logger.err("UpdatesManager: Failed to write repository configuration")
        return false
    end
end

return Config
