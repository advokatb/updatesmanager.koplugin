--[[--
Opt-in background check for *installed* plugins only.

Does not scan patch repositories, does not turn Wi-Fi on, and yields
between HTTP requests so a missing subprocess cannot freeze the UI.
]]--

local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("lib/updatesmanager_i18n").gettext
local T = require("ffi/util").template

local SETTING_ENABLED = "updatesmanager_background_enabled"
local SETTING_INTERVAL = "updatesmanager_background_interval_h"
local SETTING_LAST_CHECK = "updatesmanager_background_last_check"
local DEFAULT_INTERVAL_H = 24

local running = false
local scheduled_fn = nil

local BackgroundCheck = {}

function BackgroundCheck.isEnabled()
    if not G_reader_settings then
        return false
    end
    return G_reader_settings:isTrue(SETTING_ENABLED)
end

function BackgroundCheck.setEnabled(enabled)
    if not G_reader_settings then return end
    G_reader_settings:saveSetting(SETTING_ENABLED, enabled and true or false)
    -- Turning it on should check immediately, not wait out a previous snooze.
    if enabled then
        G_reader_settings:delSetting(SETTING_LAST_CHECK)
    end
end

function BackgroundCheck.getIntervalHours()
    local hours = G_reader_settings and G_reader_settings:readSetting(SETTING_INTERVAL)
    if hours == 12 or hours == 24 then
        return hours
    end
    return DEFAULT_INTERVAL_H
end

function BackgroundCheck.setIntervalHours(hours)
    if not G_reader_settings then return end
    if hours ~= 12 and hours ~= 24 then
        hours = DEFAULT_INTERVAL_H
    end
    G_reader_settings:saveSetting(SETTING_INTERVAL, hours)
end

function BackgroundCheck.clearSettings()
    if not G_reader_settings then return end
    G_reader_settings:delSetting(SETTING_ENABLED)
    G_reader_settings:delSetting(SETTING_INTERVAL)
    G_reader_settings:delSetting(SETTING_LAST_CHECK)
end

function BackgroundCheck.isDue()
    if not G_reader_settings then return false end
    local last = G_reader_settings:readSetting(SETTING_LAST_CHECK)
    if not last then
        return true
    end
    return (os.time() - last) >= (BackgroundCheck.getIntervalHours() * 3600)
end

local function isFileManager(ui)
    return ui ~= nil and ui.file_chooser ~= nil
end

local function isPaused(ui)
    if Device.screen_saver_mode or Device.screen_saver_lock then
        return true
    end
    if not isFileManager(ui) then
        return true
    end
    if not NetworkMgr:isWifiOn() or not NetworkMgr:isOnline() then
        return true
    end
    local UIManager_Updates = require("ui_manager")
    if UIManager_Updates.processing_msg then
        return true
    end
    return false
end

function BackgroundCheck.unschedule()
    if scheduled_fn then
        UIManager:unschedule(scheduled_fn)
        scheduled_fn = nil
    end
end

function BackgroundCheck.ping(plugin, delay)
    if not plugin or not BackgroundCheck.isEnabled() then
        return
    end
    if running then
        return
    end
    if isPaused(plugin.ui) then
        return
    end
    if not BackgroundCheck.isDue() then
        return
    end

    BackgroundCheck.unschedule()
    delay = delay or 0
    scheduled_fn = function()
        scheduled_fn = nil
        BackgroundCheck.run(plugin)
    end
    if delay > 0 then
        UIManager:scheduleIn(delay, scheduled_fn)
    else
        scheduled_fn()
    end
end

function BackgroundCheck.run(plugin)
    if running or not plugin or not BackgroundCheck.isEnabled() then
        return
    end
    if isPaused(plugin.ui) or not BackgroundCheck.isDue() then
        return
    end

    running = true
    logger.info("UpdatesManager: background plugin check starting")

    local PluginManager = require("plugin_manager")
    local Utils = require("utils")
    local installed = PluginManager.scanInstalledPlugins()
    local repos = (plugin.repositories and plugin.repositories.plugins) or {}
    local jobs = PluginManager.listInstalledCheckJobs(repos, installed)

    if #jobs == 0 then
        G_reader_settings:saveSetting(SETTING_LAST_CHECK, os.time())
        running = false
        logger.info("UpdatesManager: background check — no installed plugins match the catalog")
        return
    end

    local updates = {}
    local idx = 1
    local fetched_ok = 0

    local function step()
        if not BackgroundCheck.isEnabled() then
            running = false
            return
        end
        -- Abort without touching last_check so a later ping can retry.
        if isPaused(plugin.ui) then
            logger.info("UpdatesManager: background check paused")
            running = false
            return
        end

        if idx > #jobs then
            running = false
            logger.info("UpdatesManager: background check finished — fetched", fetched_ok, "/", #jobs, "updates", #updates)
            BackgroundCheck.onComplete(plugin, updates, fetched_ok, #jobs)
            return
        end

        local job = jobs[idx]
        idx = idx + 1
        local ok, update, fetched = pcall(
            PluginManager.checkSingleInstalled,
            job.repo_config,
            job.installed_plugin,
            job.matched_name,
            Utils.httpGet,
            Utils.parseJSON
        )
        if not ok then
            logger.warn("UpdatesManager: background check failed for", job.matched_name, update)
        else
            if fetched then
                fetched_ok = fetched_ok + 1
            end
            if update then
                table.insert(updates, update)
            end
        end
        UIManager:nextTick(step)
    end

    UIManager:nextTick(step)
end

local function isTouchMenuOpen()
    local top = UIManager:getTopmostVisibleWidget()
    return top ~= nil and top.tab_item_table ~= nil
end

function BackgroundCheck.onComplete(plugin, updates, fetched_ok, job_count)
    updates = updates or {}
    fetched_ok = fetched_ok or 0
    job_count = job_count or 0

    if #updates == 0 then
        if job_count > 0 and fetched_ok == 0 then
            -- GitHub failed for everything (rate limit / offline). Retry later.
            logger.warn("UpdatesManager: background check got no GitHub responses; not snoozing")
            return
        end
        logger.info("UpdatesManager: background check — no plugin updates")
        G_reader_settings:saveSetting(SETTING_LAST_CHECK, os.time())
        return
    end

    logger.info("UpdatesManager: background check —", #updates, "plugin update(s)")

    local tries = 0
    local function tryShow()
        tries = tries + 1
        if not BackgroundCheck.isEnabled() then
            return
        end
        if not isFileManager(plugin.ui) or Device.screen_saver_mode or Device.screen_saver_lock then
            logger.info("UpdatesManager: background prompt skipped (not in File Manager); will retry later")
            return
        end
        if isTouchMenuOpen() and tries < 40 then
            UIManager:scheduleIn(0.5, tryShow)
            return
        end

        UIManager:show(ConfirmBox:new{
            text = T(_("Plugin updates available (%1)"), #updates),
            ok_text = _("View"),
            cancel_text = _("Later"),
            dismissable = false,
            flush_events_on_show = true,
            ok_callback = function()
                local UIManager_Updates = require("ui_manager")
                UIManager_Updates:showUpdatesList({}, updates, function(_, selected_plugins)
                    if selected_plugins and #selected_plugins > 0 then
                        plugin:installPluginUpdates(selected_plugins)
                    end
                end)
            end,
        })
        -- Count as done only after the prompt is actually on screen (not under the Tools menu).
        G_reader_settings:saveSetting(SETTING_LAST_CHECK, os.time())
    end
    tryShow()
end

return BackgroundCheck
