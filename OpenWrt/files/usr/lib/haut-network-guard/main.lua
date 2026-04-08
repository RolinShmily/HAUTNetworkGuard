#!/usr/bin/lua
-- HAUT Network Guard - OpenWrt 版本
-- 主程序入口

local VERSION = "1.3.12"

package.path = package.path .. ";/usr/lib/haut-network-guard/?.lua"

local api = require("api")
local log = require("log")

local function trim_value(value)
    if not value then return "" end
    value = tostring(value)
    value = value:gsub("^\239\187\191", "")
    value = value:gsub("\r", "")
    value = value:gsub("\n", "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

local function read_uci_value(key)
    local handle = io.popen("uci -q get " .. key .. " 2>/dev/null")
    if not handle then
        return nil
    end
    local value = handle:read("*a")
    handle:close()
    return trim_value(value)
end

-- 读取 UCI 配置
local function read_config()
    local config = {
        username = "",
        password = "",
        enabled = true,
        interval = 30,
        log_level = "info"
    }

    config.username = read_uci_value("haut-network-guard.main.username") or ""
    config.password = read_uci_value("haut-network-guard.main.password") or ""
    config.log_level = read_uci_value("haut-network-guard.main.log_level") or "info"

    local enabled_value = read_uci_value("haut-network-guard.main.enabled")
    if enabled_value ~= nil and enabled_value ~= "" then
        config.enabled = (enabled_value ~= "0")
    end

    local interval_value = read_uci_value("haut-network-guard.main.interval")
    if interval_value ~= nil and interval_value ~= "" then
        config.interval = tonumber(interval_value) or 30
    end

    -- 限制检测间隔，避免请求过于频繁导致风控
    if config.interval < 30 then
        config.interval = 30
    elseif config.interval > 300 then
        config.interval = 300
    end

    return config
end

local function config_signature(config)
    return string.format(
        "enabled=%s username=%s username_len=%d password_len=%d interval=%d log_level=%s",
        tostring(config.enabled),
        log.mask_secret(config.username),
        #(config.username or ""),
        #(config.password or ""),
        tonumber(config.interval) or -1,
        tostring(config.log_level)
    )
end

-- 格式化流量
local function format_bytes(bytes)
    if bytes < 1024 then
        return string.format("%d B", bytes)
    elseif bytes < 1048576 then
        return string.format("%.2f KB", bytes / 1024)
    elseif bytes < 1073741824 then
        return string.format("%.2f MB", bytes / 1048576)
    else
        return string.format("%.2f GB", bytes / 1073741824)
    end
end

-- 格式化时间
local function format_time(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then
        return string.format("%d小时%d分%d秒", hours, mins, secs)
    elseif mins > 0 then
        return string.format("%d分%d秒", mins, secs)
    else
        return string.format("%d秒", secs)
    end
end

-- 主循环
local function main()
    log.info("HAUT Network Guard v" .. VERSION .. " 启动")
    log.info("运行环境: OpenWrt/procd 自动登录守护进程")

    while true do
        local config = read_config()
        log.debug("配置快照: " .. config_signature(config))
        local sleep_seconds = config.interval

        if not config.enabled then
            log.warn("服务已禁用，等待下一轮检测")
        elseif config.username == "" or config.password == "" then
            log.error("未配置用户名或密码，等待下一轮检测")
        else
            local user_info = api.get_user_info()

            if user_info then
                log.info(string.format(
                    "在线 - IP: %s, 流量: %s, 时长: %s",
                    user_info.ip,
                    format_bytes(user_info.bytes),
                    format_time(user_info.seconds)
                ))
            else
                log.warn("离线，尝试登录...")

                local success, msg = api.login(config.username, config.password)
                if success then
                    log.info("登录成功: " .. msg)
                else
                    log.error("登录失败: " .. msg)
                end
            end
        end

        os.execute("sleep " .. sleep_seconds)
    end
end

main()
