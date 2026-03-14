#!/usr/bin/lua
-- HAUT Network Guard - OpenWrt 版本
-- 主程序入口

local VERSION = "1.3.11"

package.path = package.path .. ";/usr/lib/haut-network-guard/?.lua"

local api = require("api")
local log = require("log")

-- 读取 UCI 配置
local function read_config()
    local config = {
        username = "",
        password = "",
        enabled = true,
        interval = 30
    }

    local handle = io.popen("uci -q get haut-network-guard.main.username 2>/dev/null")
    if handle then
        config.username = handle:read("*l") or ""
        handle:close()
    end

    handle = io.popen("uci -q get haut-network-guard.main.password 2>/dev/null")
    if handle then
        config.password = handle:read("*l") or ""
        handle:close()
    end

    handle = io.popen("uci -q get haut-network-guard.main.enabled 2>/dev/null")
    if handle then
        local val = handle:read("*l")
        config.enabled = (val ~= "0")
        handle:close()
    end

    handle = io.popen("uci -q get haut-network-guard.main.interval 2>/dev/null")
    if handle then
        config.interval = tonumber(handle:read("*l")) or 30
        handle:close()
    end

    -- 限制检测间隔，避免请求过于频繁导致风控
    if config.interval < 30 then
        config.interval = 30
    elseif config.interval > 300 then
        config.interval = 300
    end

    return config
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

    local config = read_config()

    if not config.enabled then
        log.warn("服务已禁用")
        return
    end

    if config.username == "" or config.password == "" then
        log.error("未配置用户名或密码")
        return
    end

    log.info("用户: " .. config.username)
    log.info("检测间隔: " .. config.interval .. "秒")

    while true do
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

        os.execute("sleep " .. config.interval)
    end
end

main()
