--[[--
UI Manager for Updates Manager
Handles all user interface dialogs and menus
]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local Font = require("ui/font")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local NetworkMgr = require("ui/network/manager")
local _ = require("updatesmanager_gettext")
local T = require("ffi/util").template
local logger = require("logger")

local UIManager_Updates = {}

local function sanitizeMarkdownLine(line)
    if not line then
        return ""
    end

    local sanitized = line
    -- Inline links: [text](url)
    sanitized = sanitized:gsub("%b[]%b()", function(match)
        local label = match:match("%[(.-)%]%(")
        return label or ""
    end)

    -- Markdown images: ![alt](url) → strip completely
    sanitized = sanitized:gsub("!%b[]%b()", "")

    -- HTML image tags: <img ...> → strip completely
    sanitized = sanitized:gsub("<img.-?>", "")

    -- Reference links: [text][ref]
    sanitized = sanitized:gsub("%b[]%[%w-%]", function(match)
        local label = match:match("%[(.-)%]%[")
        return label or ""
    end)

    -- Inline code
    sanitized = sanitized:gsub("`([^`]+)`", "%1")
    -- Bold markers
    sanitized = sanitized:gsub("%*%*([^%*]+)%*%*", "%1")
    sanitized = sanitized:gsub("__([^_]+)__", "%1")

    return sanitized
end

function UIManager_Updates:_markdownToPlainText(markdown)
    if not markdown or markdown:match("^%s*$") then
        return nil
    end

    local lines = {}
    local needs_ptf = false
    local cleaned = markdown:gsub("\r\n", "\n"):gsub("\r", "\n")
    cleaned = cleaned:gsub("<br%s*/?>", "\n")

    for line in (cleaned .. "\n"):gmatch("(.-)\n") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == "" then
            table.insert(lines, "")
        else
            local lower_line = trimmed:lower()
            if lower_line:match("^full%s+changelog") or lower_line:match("^see%s+full%s+changelog") then
                goto continue
            end
            local processed = sanitizeMarkdownLine(trimmed)
            local heading_prefix, heading_text = processed:match("^(#+)%s*(.+)$")
            if heading_prefix then
                needs_ptf = true
                table.insert(lines, TextBoxWidget.PTF_BOLD_START .. heading_text .. TextBoxWidget.PTF_BOLD_END)
            else
                local list_item = processed:match("^[-*+]%s+(.+)$")
                if list_item then
                    table.insert(lines, "• " .. list_item)
                else
                    local number, content = processed:match("^(%d+)%.%s+(.+)$")
                    if number then
                        table.insert(lines, number .. ". " .. content)
                    else
                        table.insert(lines, processed)
                    end
                end
            end
        end
        ::continue::
    end

    local text = table.concat(lines, "\n")
    if needs_ptf then
        text = TextBoxWidget.PTF_HEADER .. text
    end
    return text
end

function UIManager_Updates:_createChangelogWidget(markdown)
    local text = self:_markdownToPlainText(markdown) or _("No changelog available for this version.")
    local width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9) - 2*(Size.border.window + Size.padding.button)
    return TextBoxWidget:new{
        text = text,
        width = width,
        face = Font:getFace("smallinfofont"),
        alignment = "left",
        line_height = 0.2,
    }
end

function UIManager_Updates:showPluginChangelog(update)
    if not update then
        self:showInfo(_("No changelog available"))
        return
    end

    local release = update.release or {}
    local changelog = release.body
    if not changelog or changelog:match("^%s*$") then
        self:showInfo(_("No changelog available for this version."))
        return
    end

    local plugin_name = update.installed_plugin.fullname or update.installed_plugin.name or _("Unknown plugin")
    local version = release.version or release.tag_name or _("unknown")
    local text_widget = self:_createChangelogWidget(changelog)

    local dialog
    dialog = ButtonDialog:new{
        title = T(_("Changelog — %1 (%2)"), plugin_name, version),
        _added_widgets = {
            text_widget,
        },
        buttons = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        if dialog then
                            dialog:onClose()
                        end
                    end,
                },
            },
        },
    }

    UIManager:show(dialog)
end

function UIManager_Updates:_buildPluginUpdateRow(dialog, check_button, update)
    local row = HorizontalGroup:new{
        align = "top",
    }
    row.parent = dialog

    local label_widget = TextWidget:new{
        text = "changelog",
        face = Font:getFace("xx_smallinfofont"),
    }
    local icon_button = IconButton:new{
        icon = "notice-info",
        width = Screen:scaleBySize(28),
        height = Screen:scaleBySize(28),
        padding = Size.padding.tiny,
        callback = function()
            self:showPluginChangelog(update)
        end,
        show_parent = dialog,
    }

    local action_group = HorizontalGroup:new{
        align = "center",
    }
    table.insert(action_group, label_widget)
    table.insert(action_group, HorizontalSpan:new{ width = Size.span.horizontal_small })
    table.insert(action_group, icon_button)

    local reserved = action_group:getSize().w + Size.span.horizontal_small
    local available = dialog:getAddedWidgetAvailableWidth() - reserved
    if available > 0 then
        check_button.width = available
        check_button:initCheckButton(check_button.checked)
    end

    table.insert(row, check_button)
    table.insert(row, HorizontalSpan:new{ width = Size.span.horizontal_small })
    table.insert(row, action_group)

    return row
end

-- Show info message
function UIManager_Updates:showInfo(text, timeout)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout or 3,
    })
end

-- Show processing message
function UIManager_Updates:showProcessing(text)
    if self.processing_msg then
        UIManager:close(self.processing_msg)
    end
    self.processing_msg = InfoMessage:new{
        text = text,
        dismissable = false,
    }
    UIManager:show(self.processing_msg)
end

-- Update processing message text
function UIManager_Updates:updateProcessing(text)
    if self.processing_msg then
        -- Close old message and create new one with updated text
        UIManager:close(self.processing_msg)
        self.processing_msg = InfoMessage:new{
            text = text,
            dismissable = false,
        }
        UIManager:show(self.processing_msg)
    end
end

-- Close processing message
function UIManager_Updates:closeProcessing()
    if self.processing_msg then
        UIManager:close(self.processing_msg)
        self.processing_msg = nil
    end
end

-- Show updates list with checkboxes (patches and plugins)
function UIManager_Updates:showUpdatesList(patch_updates, plugin_updates, callback)
    patch_updates = patch_updates or {}
    plugin_updates = plugin_updates or {}
    
    if #patch_updates == 0 and #plugin_updates == 0 then
        self:showInfo(_("No updates available"))
        return
    end
    
    -- Load patch descriptions module
    local PatchDescriptions = require("patch_descriptions")
    
    -- Create checkboxes for each update
    local checks = {}
    local patch_update_states = {} -- Track which patch updates are selected
    local plugin_update_states = {} -- Track which plugin updates are selected
    
    -- Add patch updates
    for i, update in ipairs(patch_updates) do
        patch_update_states[i] = { update = update, selected = true }
        
        local patch_name = update.local_patch.name or update.local_patch.filename
        local author = update.repo_patch.repo_owner or "unknown"
        
        -- Build display text
        local display_text = T(_("%1 (by %2)"), patch_name, author)
        
        table.insert(checks, {
            kind = "patch",
            config = {
                text = display_text,
                checked = true,
                callback = function()
                    patch_update_states[i].selected = not patch_update_states[i].selected
                end,
                hold_callback = function()
                    -- Show patch details on long press
                    self:showPatchDetails(update)
                end,
            },
        })
    end
    
    -- Add plugin updates
    for i, update in ipairs(plugin_updates) do
        plugin_update_states[i] = { update = update, selected = true }
        
        local plugin_name = update.installed_plugin.fullname or update.installed_plugin.name
        local author = update.repo_config.owner or "unknown"
        local current_version = update.installed_plugin.version or "unknown"
        local new_version = update.release.version or update.release.tag_name or "unknown"
        
        -- Build display text (without "Plugin:" prefix)
        local display_text = T(_("%1 (by %2)\n   %3 → %4"), plugin_name, author, current_version, new_version)
        
        table.insert(checks, {
            kind = "plugin",
            update = update,
            config = {
                text = display_text,
                checked = true,
                callback = function()
                    plugin_update_states[i].selected = not plugin_update_states[i].selected
                end,
                hold_callback = function()
                    -- Show plugin details on long press
                    self:showPluginDetails(update)
                end,
            },
        })
    end
    
    local total_updates = #patch_updates + #plugin_updates
    
    -- Create button dialog - use local variable that will be captured in closure
    local button_dialog
    button_dialog = ButtonDialog:new{
        title = T(_("Available Updates (%1)"), total_updates),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        if button_dialog then
                            button_dialog:onClose()
                        end
                    end,
                },
                {
                    text = _("Update Selected"),
                    callback = function()
                        if button_dialog then
                            button_dialog:onClose()
                        end
                        -- Filter selected updates
                        local selected_patches = {}
                        for _, state in ipairs(patch_update_states) do
                            if state.selected then
                                table.insert(selected_patches, state.update)
                            end
                        end
                        
                        local selected_plugins = {}
                        for _, state in ipairs(plugin_update_states) do
                            if state.selected then
                                table.insert(selected_plugins, state.update)
                            end
                        end
                        
                        if callback then
                            callback(selected_patches, selected_plugins)
                        end
                    end,
                },
            },
        },
    }
    
    -- Add line separator
    button_dialog:addWidget(LineWidget:new{
        dimen = Geom:new{
            w = button_dialog.width - 2 * (Size.border.window + Size.padding.button),
            h = Size.line.medium,
        },
        background = Blitbuffer.COLOR_GRAY,
    })
    button_dialog:addWidget(VerticalSpan:new{ width = Size.padding.default })
    
    -- Add checkboxes
    for _, check in ipairs(checks) do
        check.config.parent = button_dialog
        local check_button = CheckButton:new(check.config)
        if check.kind == "plugin" then
            button_dialog:addWidget(self:_buildPluginUpdateRow(button_dialog, check_button, check.update))
        else
            button_dialog:addWidget(check_button)
        end
    end
    
    UIManager:show(button_dialog)
end

-- Show patch details dialog (for updates)
function UIManager_Updates:showPatchDetails(update)
    local PatchDescriptions = require("patch_descriptions")
    local local_patch = update.local_patch
    local repo_patch = update.repo_patch
    
    local patch_name = local_patch.name or local_patch.filename
    local author = repo_patch.repo_owner or "unknown"
    local repo_url = repo_patch.repo_url or ""
    local size = repo_patch.size or local_patch.size or 0
    
    -- Get description (priority: local > updates.json > comments)
    local description = PatchDescriptions.getDescription(
        patch_name,
        repo_patch,
        update.repo_content,
        nil -- updates_json_data would be passed if available
    )
    
    -- If description from updates.json, use it
    if not description and repo_patch.description then
        description = repo_patch.description
    end
    
    -- If still no description, try parsing from content
    if not description and update.repo_content then
        description = PatchDescriptions.parseFromComments(update.repo_content)
    end
    
    local info_text = T(_("Patch: %1\n\nAuthor: %2\nRepository: %3\nSize: %4 bytes"),
        patch_name, author, repo_patch.repo_name or "unknown", size)
    
    if description and description ~= "" then
        info_text = info_text .. "\n\n" .. _("Description:") .. "\n" .. description
    end
    
    if repo_url and repo_url ~= "" then
        info_text = info_text .. "\n\n" .. _("Repository:") .. " " .. repo_url
    end
    
    local button_dialog
    button_dialog = ButtonDialog:new{
        title = _("Patch Information"),
        _added_widgets = {
            TextBoxWidget:new{
                text = info_text,
                width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9) - 2*(Size.border.window + Size.padding.button),
                face = Font:getFace("infofont"),
                alignment = "left",
            },
        },
        buttons = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        if button_dialog then
                            button_dialog:onClose()
                        end
                    end,
                },
                {
                    text = _("Edit Description"),
                    callback = function()
                        if button_dialog then
                            button_dialog:onClose()
                        end
                        self:editPatchDescription(patch_name, description)
                    end,
                },
            },
        },
    }
    
    UIManager:show(button_dialog)
end

-- Show plugin details dialog
function UIManager_Updates:showPluginDetails(update)
    local installed_plugin = update.installed_plugin
    local release = update.release
    local repo_config = update.repo_config
    
    local plugin_name = installed_plugin.fullname or installed_plugin.name
    local author = repo_config.owner or "unknown"
    local current_version = installed_plugin.version or "unknown"
    local new_version = release.version or release.tag_name or "unknown"
    local repo_url = string.format("https://github.com/%s/%s", repo_config.owner, repo_config.repo)
    
    local info_text = T(_("Plugin: %1\n\nAuthor: %2\nCurrent Version: %3\nNew Version: %4\nRepository: %5"),
        plugin_name, author, current_version, new_version, repo_url)
    
    if release.body and release.body ~= "" then
        -- Limit release notes length
        local release_notes = release.body
        if #release_notes > 500 then
            release_notes = release_notes:sub(1, 497) .. "..."
        end
        info_text = info_text .. "\n\n" .. _("Release Notes:") .. "\n" .. release_notes
    end
    
    local button_dialog
    button_dialog = ButtonDialog:new{
        title = _("Plugin Information"),
        _added_widgets = {
            TextBoxWidget:new{
                text = info_text,
                width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9) - 2*(Size.border.window + Size.padding.button),
                face = Font:getFace("infofont"),
                alignment = "left",
            },
        },
        buttons = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        if button_dialog then
                            button_dialog:onClose()
                        end
                    end,
                },
            },
        },
    }
    
    UIManager:show(button_dialog)
end

-- Show patch information dialog (legacy, for installed patches)
function UIManager_Updates:showPatchInfo(patch_info)
    local PatchDescriptions = require("patch_descriptions")
    local patch_name = patch_info.name or "unknown"
    
    -- Load local description if available
    local local_descriptions = PatchDescriptions.loadLocalDescriptions()
    local description = local_descriptions[patch_name]
    
    local info_text = T(_("Patch: %1\n\nPath: %2\nSize: %3 bytes\nMD5: %4"),
        patch_name,
        patch_info.path or "",
        patch_info.size or 0,
        patch_info.md5 or "unknown"
    )
    
    if description and description ~= "" then
        info_text = info_text .. "\n\n" .. _("Description:") .. "\n" .. description
    end
    
    local button_dialog
    button_dialog = ButtonDialog:new{
        title = _("Patch Information"),
        _added_widgets = {
            TextBoxWidget:new{
                text = info_text,
                width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9) - 2*(Size.border.window + Size.padding.button),
                face = Font:getFace("infofont"),
                alignment = "left",
            },
        },
        buttons = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        if button_dialog then
                            button_dialog:onClose()
                        end
                    end,
                },
                {
                    text = _("Edit Description"),
                    callback = function()
                        if button_dialog then
                            button_dialog:onClose()
                        end
                        self:editPatchDescription(patch_name, description)
                    end,
                },
            },
        },
    }
    
    UIManager:show(button_dialog)
end

-- Edit patch description
function UIManager_Updates:editPatchDescription(patch_name, current_description)
    local PatchDescriptions = require("patch_descriptions")
    local input_dialog
    input_dialog = InputDialog:new{
        title = T(_("Edit Description: %1"), patch_name),
        input = current_description or "",
        allow_newline = true,
        input_multiline = true,
        text_height = Font:getFace("infofont").size * 8,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_description = input_dialog:getInputText()
                        if PatchDescriptions.setDescription(patch_name, new_description) then
                            UIManager:close(input_dialog)
                            self:showInfo(_("Description saved"))
                        else
                            self:showInfo(_("Failed to save description"))
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

-- Show update progress
function UIManager_Updates:showUpdateProgress(current, total, patch_name)
    local text = T(_("Updating %1/%2: %3"), current, total, patch_name or "")
    if self.processing_msg then
        self.processing_msg.text = text
        UIManager:setDirty(nil, "ui")
    else
        self:showProcessing(text)
    end
end

-- Show update results
function UIManager_Updates:showUpdateResults(successful, failed)
    successful = successful or {}
    failed = failed or {}
    
    local texts = {}
    
    -- Process successful patches and plugins
    if successful and type(successful) == "table" then
        local success_list = {}
        for i, patch in ipairs(successful) do
            if patch and type(patch) == "table" then
                local patch_name = nil
                
                -- For plugins, prefer fullname over name
                if patch.fullname then
                    patch_name = patch.fullname
                elseif patch.name then
                    patch_name = patch.name
                elseif patch.filename then
                    patch_name = patch.filename
                end
                
                -- If we don't have name/filename, try to extract from path
                if (not patch_name or patch_name == "unknown") and patch.path then
                    patch_name = patch.path:match("([^/]+)$") or patch.path
                end
                
                -- Remove .lua extension if present (for patches)
                if patch_name then
                    patch_name = patch_name:gsub("%.lua$", "")
                else
                    patch_name = "unknown"
                end
                table.insert(success_list, " · " .. patch_name)
            end
        end
        if #success_list > 0 then
            local header = _("Successfully updated:")
            local list_text = table.concat(success_list, "\n")
            local success_text = header .. "\n" .. list_text
            table.insert(texts, success_text)
        end
    end
    
    -- Process failed patches and plugins
    if failed and type(failed) == "table" then
        local failed_list = {}
        for i, patch in ipairs(failed) do
            if patch and type(patch) == "table" then
                local patch_name = nil
                
                -- For plugins, prefer fullname over name
                if patch.fullname then
                    patch_name = patch.fullname
                elseif patch.name then
                    patch_name = patch.name
                elseif patch.filename then
                    patch_name = patch.filename
                end
                
                -- If we don't have name/filename, try to extract from path
                if (not patch_name or patch_name == "unknown") and patch.path then
                    patch_name = patch.path:match("([^/]+)$") or patch.path
                end
                
                -- Remove .lua extension if present (for patches)
                if patch_name then
                    patch_name = patch_name:gsub("%.lua$", "")
                else
                    patch_name = "unknown"
                end
                table.insert(failed_list, " · " .. patch_name)
            end
        end
        if #failed_list > 0 then
            local failed_text = _("Failed to update:") .. "\n" .. table.concat(failed_list, "\n")
            table.insert(texts, failed_text)
        end
    end
    
    local message = table.concat(texts, "\n\n")
    if message == "" or message == nil then
        message = _("No updates were processed.")
    end
    
    -- Create button dialog - use local variable that will be captured in closure
    local button_dialog
    button_dialog = ButtonDialog:new{
        title = _("Update Results"),
        _added_widgets = {
            TextBoxWidget:new{
                text = message,
                width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9) - 2*(Size.border.window + Size.padding.button),
                face = Font:getFace("infofont"),
                alignment = "left",
            },
        },
        buttons = {
            {
                {
                    text = _("OK"),
                    callback = function()
                        if button_dialog then
                            button_dialog:onClose()
                        end
                        if #successful > 0 then
                            UIManager:askForRestart(_("Patches have been updated. Restart required."))
                        end
                    end,
                },
            },
        },
    }
    
    UIManager:show(button_dialog)
end

-- Show main menu
function UIManager_Updates:showMainMenu(updates_manager)
    local menu_items = {
        {
            text = _("Check for Updates"),
            callback = function()
                updates_manager:checkForUpdates()
            end,
        },
        {
            text = _("View Installed Patches"),
            callback = function()
                updates_manager:showInstalledPatches()
            end,
        },
        {
            text = _("Settings"),
            sub_item_table = {
                {
                    text = _("Repository Settings"),
                    callback = function()
                        updates_manager:showRepositorySettings()
                    end,
                },
            },
        },
    }
    
    local menu = Menu:new{
        title = _("Updates Manager"),
        item_table = menu_items,
    }
    
    UIManager:show(menu)
end

-- Show installed patches list
function UIManager_Updates:showInstalledPatchesList(patches)
    local PatchDescriptions = require("patch_descriptions")
    local menu_items = {}
    local count = 0
    
    -- Load local descriptions
    local local_descriptions = PatchDescriptions.loadLocalDescriptions()
    
    for filename, patch in pairs(patches) do
        count = count + 1
        local patch_name = patch.name or filename
        local saved_desc = local_descriptions[patch_name]
        
        -- Add description preview to menu item text if available
        local menu_text = patch_name
        if saved_desc and saved_desc ~= "" then
            -- Show first line of description as preview
            local first_line = saved_desc:match("([^\n]+)")
            if first_line and #first_line > 0 then
                if #first_line > 40 then
                    first_line = first_line:sub(1, 37) .. "..."
                end
                menu_text = menu_text .. " - " .. first_line
            end
        end
        
        table.insert(menu_items, {
            text = menu_text,
            callback = function()
                -- Show detailed patch info
                self:showPatchInfo(patch)
            end,
            hold_callback = function()
                -- Show detailed patch info on long press
                self:showPatchInfo(patch)
            end,
        })
    end
    
    if count == 0 then
        self:showInfo(_("No patches installed"))
        return
    end
    
    local menu = Menu:new{
        title = T(_("Installed Patches (%1)"), count),
        item_table = menu_items,
    }
    
    UIManager:show(menu)
end

-- Show installed plugins list
function UIManager_Updates:showInstalledPluginsList(plugins)
    local menu_items = {}
    local count = 0
    
    for plugin_name, plugin in pairs(plugins) do
        count = count + 1
        local display_text = plugin.fullname or plugin.name
        if plugin.version and plugin.version ~= "unknown" then
            display_text = display_text .. " (" .. plugin.version .. ")"
        end
        
        table.insert(menu_items, {
            text = display_text,
            callback = function()
                -- Show plugin info
                self:showPluginInfo(plugin)
            end,
            hold_callback = function()
                -- Show plugin info on long press
                self:showPluginInfo(plugin)
            end,
        })
    end
    
    if count == 0 then
        self:showInfo(_("No plugins installed"))
        return
    end
    
    local menu = Menu:new{
        title = T(_("Installed Plugins (%1)"), count),
        item_table = menu_items,
    }
    
    UIManager:show(menu)
end

-- Show plugin information dialog (for installed plugins)
function UIManager_Updates:showPluginInfo(plugin)
    local plugin_name = plugin.fullname or plugin.name
    local version = plugin.version or "unknown"
    local description = plugin.description or ""
    local path = plugin.path or ""
    
    local info_text = T(_("Plugin: %1\n\nVersion: %2\nPath: %3"),
        plugin_name, version, path)
    
    if description and description ~= "" then
        info_text = info_text .. "\n\n" .. _("Description:") .. "\n" .. description
    end
    
    local button_dialog
    button_dialog = ButtonDialog:new{
        title = _("Plugin Information"),
        _added_widgets = {
            TextBoxWidget:new{
                text = info_text,
                width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9) - 2*(Size.border.window + Size.padding.button),
                face = Font:getFace("infofont"),
                alignment = "left",
            },
        },
        buttons = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        if button_dialog then
                            button_dialog:onClose()
                        end
                    end,
                },
            },
        },
    }
    
    UIManager:show(button_dialog)
end

-- Check network and show message if needed
function UIManager_Updates:checkNetwork(callback)
    if NetworkMgr:isOnline() then
        if callback then callback() end
    else
        UIManager:show(ConfirmBox:new{
            text = _("Network connection required. Turn on Wi-Fi?"),
            ok_text = _("Turn on Wi-Fi"),
            ok_callback = function()
                NetworkMgr:turnOnWifiAndWaitForConnection(function()
                    if callback then callback() end
                end)
            end,
        })
    end
end

return UIManager_Updates

