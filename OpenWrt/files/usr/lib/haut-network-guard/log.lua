#!/usr/bin/lua
-- HAUT Network Guard - 日志模块

local log = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local LABELS = { debug = "DEBUG", info = "INFO", warn = "WARN", error = "ERROR" }

-- 从 UCI 读取日志级别，默认 info
local function get_configured_level()
    local handle = io.popen("uci -q get haut-network-guard.main.log_level 2>/dev/null")
    if handle then
        local val = handle:read("*l") or "info"
        handle:close()
        if LEVELS[val] then return LEVELS[val] end
    end
    return LEVELS.info
end

local min_level = get_configured_level()

local function write_log(level, msg)
    if LEVELS[level] < min_level then return end
    local timestamp = os.date("%H:%M:%S")
    local label = LABELS[level]
    local line = string.format("[%s] [%s] %s", timestamp, label, msg)
    print(line)
    os.execute(string.format("logger -t haut-network-guard '%s'",
        msg:gsub("'", "'\\''")
    ))
end

function log.debug(msg) write_log("debug", msg) end
function log.info(msg)  write_log("info", msg)  end
function log.warn(msg)  write_log("warn", msg)  end
function log.error(msg) write_log("error", msg) end

return log
