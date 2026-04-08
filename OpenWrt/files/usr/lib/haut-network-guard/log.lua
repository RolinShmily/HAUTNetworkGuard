#!/usr/bin/lua
-- HAUT Network Guard - 日志模块

local log = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local LABELS = { debug = "DEBUG", info = "INFO", warn = "WARN", error = "ERROR" }
local LEVEL_REFRESH_SECONDS = 30

-- 从 UCI 读取日志级别，默认 info
local function get_configured_level()
    local handle = io.popen("uci -q get haut-network-guard.main.log_level 2>/dev/null")
    if handle then
        local val = (handle:read("*a") or ""):gsub("[%s\r\n]+$", "")
        handle:close()
        if LEVELS[val] then return LEVELS[val] end
    end
    return LEVELS.info
end

local min_level = LEVELS.info
local last_level_refresh = 0
local startup_timestamp = os.date("%Y-%m-%d %H:%M:%S")
local sequence = 0

local function shell_quote(str)
    return "'" .. tostring(str or ""):gsub("'", "'\\''") .. "'"
end

local function refresh_level_if_needed(force)
    local now = os.time()
    if force or (now - last_level_refresh) >= LEVEL_REFRESH_SECONDS then
        min_level = get_configured_level()
        last_level_refresh = now
    end
end

local function write_log(level, msg)
    refresh_level_if_needed(false)
    if LEVELS[level] < min_level then return end
    sequence = sequence + 1
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local label = LABELS[level]
    local line = string.format("[%s] [%s] [#%d] %s", timestamp, label, sequence, tostring(msg))
    print(line)
    os.execute(string.format("logger -t haut-network-guard %s", shell_quote(line)))
end

function log.debug(msg) write_log("debug", msg) end
function log.info(msg)  write_log("info", msg)  end
function log.warn(msg)  write_log("warn", msg)  end
function log.error(msg) write_log("error", msg) end

function log.mask_username(value)
    local text = tostring(value or "")
    local length = #text
    if length == 0 then return "<empty>" end
    if length == 1 then return "*" end
    if length == 2 then return text:sub(1, 1) .. "*" end
    return text:sub(1, 2) .. string.rep("*", length - 3) .. text:sub(length, length)
end

function log.mask_secret(value)
    return log.mask_username(value)
end

function log.preview(value, max_len)
    max_len = max_len or 120
    if not value then return "(nil)" end
    value = tostring(value):gsub("\r", "\\r"):gsub("\n", "\\n")
    if #value > max_len then
        return value:sub(1, max_len) .. "...(" .. tostring(#value) .. " bytes)"
    end
    return value
end

function log.bytes_summary(value)
    if not value then return "0 bytes" end
    return tostring(#tostring(value)) .. " bytes"
end

function log.refresh_level()
    refresh_level_if_needed(true)
    log.debug("日志级别已刷新: " .. tostring(min_level))
end

refresh_level_if_needed(true)
log.info("日志模块已初始化，startup=" .. startup_timestamp .. ", min_level=" .. tostring(min_level))

return log
