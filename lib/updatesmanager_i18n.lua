-- updatesmanager_i18n.lua
-- Translation loader for plugin-specific strings.
-- Checks Updates Manager .po files first, then delegates to KOReader gettext.
-- Does NOT modify the global gettext module.
--
-- Usage:
--   local _ = require("lib/updatesmanager_i18n").gettext
--
-- HOW TO ADD A LANGUAGE
--   1. Copy locale/updatesmanager.pot -> locale/<lang>.po (e.g. locale/ru.po)
--   2. Fill in the msgstr values.
--   3. Done

local logger = require("logger")

local src = debug.getinfo(1, "S").source or ""
src = src:gsub("\\", "/")
local _dir = (src:match("^@(.+/)") or "./")
local _base = (_dir:gsub("lib/$", ""))

local function parsePO(path)
    local f = io.open(path, "r")
    if not f then return nil end

    local map = {}
    local msgid, msgstr, in_id, in_str = nil, nil, false, false

    local function flush()
        if msgid and msgstr and msgid ~= "" and msgstr ~= "" then
            map[msgid] = msgstr
        end
        msgid, msgstr, in_id, in_str = nil, nil, false, false
    end

    local function unescape(s)
        return s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub('\\"', '"'):gsub("\\\\", "\\")
    end

    for raw_line in f:lines() do
        local line = raw_line:match("^%s*(.-)%s*$")
        if line:match("^#") or line == "" then
            if line == "" then flush() end
        elseif line:match('^msgid%s+"') then
            flush()
            msgid  = unescape(line:match('^msgid%s+"(.*)"') or "")
            in_id  = true; in_str = false
        elseif line:match('^msgstr%s+"') then
            msgstr = unescape(line:match('^msgstr%s+"(.*)"') or "")
            in_str = true; in_id  = false
        elseif line:match('^"') then
            local cont = unescape(line:match('^"(.*)"') or "")
            if in_id  and msgid  then msgid  = msgid  .. cont end
            if in_str and msgstr then msgstr = msgstr .. cont end
        end
    end
    flush()
    f:close()
    return map
end

local function detectLang()
    local lang = G_reader_settings and G_reader_settings:readSetting("language")
    if type(lang) == "string" and lang ~= "" then return lang end
    local lc = os.getenv("LANG") or os.getenv("LC_ALL") or os.getenv("LC_MESSAGES") or ""
    lang = lc:match("^([a-zA-Z_]+)")
    return lang or "en"
end

local ok_ko, ko_gettext = pcall(require, "gettext")
if not ok_ko then ko_gettext = function(t) return t end end
local translations

local lang = detectLang()
if lang ~= "en" and lang ~= "en_US" then
    local function try(name)
        local path = _base .. "locale/" .. name .. ".po"
        local t = parsePO(path)
        if t and next(t) then
            local n = 0; for _k in pairs(t) do n = n + 1 end
            logger.dbg("updatesmanager i18n: loaded " .. path .. " — " .. n .. " strings")
            return t
        end
    end
    translations = try(lang) or (function()
        local prefix = lang:match("^([a-zA-Z]+)")
        if prefix and prefix ~= lang then return try(prefix) end
    end)()

    if translations then
        logger.dbg("updatesmanager i18n: installed for language: " .. lang)
    end
end

local function gettext(msgid)
    if translations then
        local t = translations[msgid]
        if t then return t end
    end
    return ko_gettext(msgid)
end

return {
    gettext = gettext,
}
