--[[--
Configuration for Updates Manager plugin
Contains repository lists and settings
]]--

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
    {
        owner = "reuerendo",
        repo = "koreader-patches",
        branch = "main",
        path = "",
        description = "Reuerendo's patches",
    },
    {
        owner = "sparklerfish",
        repo = "KOReader.patches",
        branch = "main",
        path = "",
        description = "Sparklerfish's patches",
    },
    {
        owner = "brugsbells",
        repo = "Koreader-Patches",
        branch = "main",
        path = "",
        description = "Brugsbells's patches",
    },
    {
        owner = "de3sw2aq1",
        repo = "koreader-patches",
        branch = "main",
        path = "patches",
        description = "De3sw2aq1's patches",
    },
    {
        owner = "0zd3m1r",
        repo = "KOReader.patches",
        branch = "main",
        path = "",
        description = "0zd3m1r patches",
    },
    {
        owner = "gilgulgamesh",
        repo = "koreader-patches",
        branch = "main",
        path = "",
        description = "Gilgulgamesh's patches",
    },
    {
        owner = "bartimeausprime",
        repo = "koreaderpatches",
        branch = "main",
        path = "",
        description = "Bartimeausprime's patches",
    },
    {
        owner = "nahuelpucciarelli",
        repo = "KOReader.patches",
        branch = "main",
        path = "",
        description = "Nahuelpucciarelli's patches",
    },
    {
        owner = "dxvgs",
        repo = "KOReader.patches",
        branch = "main",
        path = "",
        description = "Dxvgs's patches",
    },
    {
        owner = "medinauta",
        repo = "Koreader-Patches",
        branch = "main",
        path = "",
        description = "Medinauta's patches",
    },
    {
        owner = "timault",
        repo = "KOReader-Patch",
        branch = "main",
        path = "",
        description = "Timault's patches",
    },
    {
        owner = "Euphoriyy",
        repo = "KOReader.patches",
        branch = "main",
        path = "",
        description = "Euphoriyy's patches",
    },
    {
        owner = "quanganhdo",
        repo = "koreader-user-patches",
        branch = "main",
        path = "",
        description = "Quanganhdo's patches",
    },
    {
        owner = "rkram5424",
        repo = "KOReader.patches",
        branch = "main",
        path = "",
        description = "Rkram5424's patches",
    },
}

-- Commented out patch repositories (no proper releases or structure)
-- {
--     owner = "VeeBui",
--     repo = "KOReader-patches",
--     branch = "main",
--     path = "",
--     description = "VeeBui's patches",
-- },

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
        owner = "gitalexcampos",
        repo = "koreader-Highlight-Sync",
        description = "Highlight-Sync plugin",
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
        owner = "omer-faruq",
        repo = "tbrplanner.koplugin",
        description = "TBR Planner plugin",
    },
    {
        owner = "omer-faruq",
        repo = "nonogram.koplugin",
        description = "Nonogram plugin",
    },
    {
        owner = "agaragou",
        repo = "illustrations.koplugin",
        description = "Illustrations plugin",
    },
    {
        owner = "Evgeniy-94",
        repo = "TelegramDownloader.koplugin",
        description = "Telegram Downloader plugin",
    },
    {
        owner = "readest",
        repo = "readest",
        asset_pattern = "*.koplugin.zip",
        description = "Readest ebook reader plugin",
    },
    {
        owner = "OGKevin",
        repo = "kobo.koplugin",
        asset_pattern = "*.koplugin.zip",
        description = "Kobo plugin",
    },
    {
        owner = "oleasteo",
        repo = "koreader-screenlockpin",
        description = "Screen Lock PIN plugin",
    },
    {
        owner = "omer-faruq",
        repo = "notificationlistener.koplugin",
        description = "Notification Listener plugin",
    },
    {
        owner = "omer-faruq",
        repo = "ankiviewer.koplugin",
        description = "Anki Viewer plugin",
    },
    -- {
    --     owner = "markleenders",
    --     repo = "stopwatchtimer.koplugin",
    --     description = "Stopwatch Timer plugin",
    -- },
    {
        owner = "DenisovichDev",
        repo = "randomquote.koplugin",
        description = "Random Quote plugin",
    },
    {
        owner = "agaragou",
        repo = "errol.koplugin",
        description = "Errol plugin",
    },
    {
        owner = "DeclanChidlow",
        repo = "KOReader-Jellyfin-Plugin",
        description = "Jellyfin plugin",
    },
    {
        owner = "omer-faruq",
        repo = "applauncher.koplugin",
        description = "App Launcher plugin",
    },
    {
        owner = "moritz-john",
        repo = "homeassistant.koplugin",
        description = "Home Assistant plugin",
    },
    {
        owner = "KORComic",
        repo = "comicreader.koplugin",
        description = "Comic Reader plugin",
    },
    {
        owner = "kaikozlov",
        repo = "localsend.koplugin",
        asset_pattern = "localsend-koplugin-armv7.zip",
        description = "LocalSend plugin",
    },
    -- {
    --     owner = "tachibana-shin",
    --     repo = "rakuyomi",
    --     asset_pattern = "*kindle*.zip",
    --     description = "Rakuyomi plugin (Kindle build)",
    -- },
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
    --     owner = "greywolf1499",
    --     repo = "opds_plus.koplugin",
    --     description = "OPDS Plus plugin",
    -- },
    -- {
    --     owner = "TomasDiLeo",
    --     repo = "lightsout.koplugin",
    --     description = "Lights Out plugin",
    -- },
    -- {
    --     owner = "jasonchoimtt",
    --     repo = "koreader-syncthing",
    --     description = "Syncthing plugin",
    -- },
    -- {
    --     owner = "KORComic",
    --     repo = "comicmeta.koplugin",
    --     description = "Comic Meta plugin",
    -- },
    -- {
    --     owner = "TomasDiLeo",
    --     repo = "sumpuzzle.koplugin",
    --     description = "Sum Puzzle plugin",
    -- },
    -- {
    --     owner = "m1khal3v",
    --     repo = "koreader-pinlock",
    --     description = "PIN Lock plugin",
    -- },
    -- {
    --     owner = "juancoquet",
    --     repo = "highlights-screensaver",
    --     description = "Highlights Screensaver plugin",
    -- },
    -- {
    --     owner = "marinov752",
    --     repo = "emailtokoreader.koplugin",
    --     description = "Email to KOReader plugin",
    -- },
    -- {
    --     owner = "odrling",
    --     repo = "connections.koplugin",
    --     description = "NYT Connections game plugin",
    -- },
    -- {
    --     owner = "ebanDev",
    --     repo = "iconschanger.koplugin",
    --     description = "Icon Pack Changer plugin",
    -- },
    -- {
    --     owner = "Ajatt-Tools",
    --     repo = "anki.koplugin",
    --     description = "Anki integration plugin",
    -- },
    -- {
    --     owner = "peterstamps",
    --     repo = "KOReader_MyWebDavPlugin",
    --     description = "WebDAV plugin",
    -- },
    -- {
    --     owner = "roygbyte",
    --     repo = "crossword.koplugin",
    --     description = "Crossword puzzle plugin",
    -- },
    -- {
    --     owner = "gitalexcampos",
    --     repo = "koreader-Highlight-Sync",
    --     description = "Highlight Sync plugin",
    -- },
    {
        owner = "Lalocaballero",
        repo = "readmastery.koplugin",
        description = "Read Mastery plugin",
    },
    {
        owner = "TomasDiLeo",
        repo = "pageturner.koplugin",
        description = "Page Turner plugin",
    },
    -- {
    --     owner = "xconny",
    --     repo = "Koreader-Senet",
    --     description = "Senet game plugin",
    -- },
    -- {
    --     owner = "xconny",
    --     repo = "Koreader-Backgammon",
    --     description = "Backgammon games plugin",
    -- },
    -- {
    --     owner = "Shac0x",
    --     repo = "Maximum-koreader",
    --     description = "Maximum manga zoom plugin",
    -- },
    -- {
    --     owner = "iamnotwassim",
    --     repo = "focusruler",
    --     description = "Focus Ruler plugin",
    -- },
    -- {
    --     owner = "wd12d",
    --     repo = "KoStatsMulti-Plugin",
    --     path = "kostats.koplugin",
    --     description = "KoStats Multi plugin",
    -- },
    -- {
    --     owner = "k-nacion",
    --     repo = "highlightsscreensaver.koplugin",
    --     description = "Highlights Screensaver plugin",
    -- },
    -- {
    --     owner = "mm-malkani",
    --     repo = "screenshotorganizer.koplugin",
    --     description = "Screenshot Organizer plugin",
    -- },
    -- {
    --     owner = "fischer-hub",
    --     repo = "annas.koplugin",
    --     description = "Annas plugin",
    -- },
    -- {
    --     owner = "right9code",
    --     repo = "imagesearch.koplugin",
    --     description = "Image Search plugin",
    -- },
    -- {
    --     owner = "right9code",
    --     repo = "fontswitcher.koplugin",
    --     description = "Font Switcher plugin",
    -- },
    -- {
    --     owner = "right9code",
    --     repo = "sleepwaketracker.koplugin",
    --     description = "Sleep/Wake Tracker plugin",
    -- },
    -- {
    --     owner = "CezaryPukownik",
    --     repo = "koreader-notion-sync",
    --     description = "Notion Sync plugin",
    -- },
    {
        owner = "zeeyado",
        repo = "koassistant.koplugin",
        description = "AI Assistant plugin",
    },
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
Config.GITHUB_TOKEN_FILE = DataStorage:getSettingsDir() .. "/updatesmanager_github_token.txt"

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

-- Load GitHub Personal Access Token from config file
function Config.loadGitHubToken()
    local token_file = io.open(Config.GITHUB_TOKEN_FILE, "r")
    if not token_file then
        -- Try to create template file if it doesn't exist
        Config.createGitHubTokenTemplate()
        return nil
    end
    
    -- Read all lines and find first non-comment, non-empty line
    for line in token_file:lines() do
        -- Trim whitespace
        line = line:match("^%s*(.-)%s*$")
        -- Skip empty lines and comments
        if line and line ~= "" and not line:match("^#") then
            token_file:close()
            return line
        end
    end
    
    token_file:close()
    return nil
end

-- Create GitHub token template file if it doesn't exist
function Config.createGitHubTokenTemplate()
    -- Check if file already exists
    if lfs.attributes(Config.GITHUB_TOKEN_FILE, "mode") == "file" then
        return
    end
    
    -- Ensure settings directory exists
    local settings_dir = DataStorage:getSettingsDir()
    if lfs.attributes(settings_dir, "mode") ~= "directory" then
        lfs.mkdir(settings_dir)
    end
    
    -- Create template file with instructions
    local template_content = [[# GitHub Personal Access Token Configuration
# This file is used to store your GitHub Personal Access Token to avoid API rate limits.
#
# HOW TO GET A TOKEN:
# 1. Go to https://github.com/settings/tokens
# 2. Click "Generate new token" -> "Generate new token (classic)"
# 3. Give it a name (e.g., "KOReader Updates Manager")
# 4. Select expiration (recommended: 90 days or custom)
# 5. For scopes, you only need "public_repo" (read-only access to public repositories)
# 6. Click "Generate token"
# 7. Copy the token and paste it below (replace this entire line with your token)
#
# WHY USE A TOKEN:
# - Without a token: 60 requests/hour (shared limit for all unauthenticated requests)
# - With a token: 5,000 requests/hour (personal limit)
# - This prevents "403 Rate limit exceeded" errors when checking for updates
#
# SECURITY NOTE:
# - This token only needs "public_repo" scope (read-only access to public repositories)
# - Never share this token or commit it to version control
# - If your token is compromised, revoke it immediately at https://github.com/settings/tokens
#
# USAGE:
# - Remove the "#" from the line below and paste your token
# - Or simply paste your token on a new line (without "#")
# - The plugin will automatically read the first non-comment line
#
# Paste your token here (remove this comment line):

]]
    
    local file = io.open(Config.GITHUB_TOKEN_FILE, "w")
    if file then
        file:write(template_content)
        file:close()
    end
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
