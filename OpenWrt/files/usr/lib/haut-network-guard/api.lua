#!/usr/bin/lua
-- HAUT Network Guard - API 模块
-- SRUN3K 协议 (与 macOS/Windows 一致)

local api = {}
local crypto = require("crypto")
local log = require("log")

-- 配置
api.BASE_URL = "http://172.16.154.130"
api.LOGIN_URL = "http://172.16.154.130:69/cgi-bin/srun_portal"

-- URL 编码: 仅允许 [A-Za-z0-9-._~] 不编码
local function url_encode(str)
    if not str then return "" end
    return string.gsub(str, "([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

-- 生成 jQuery 回调名
local function gen_callback()
    local timestamp = os.time() * 1000 + math.random(0, 999)
    return "jQuery_" .. tostring(timestamp), timestamp
end

-- HTTP GET 请求
local function http_get(url)
    local cmd = string.format("curl -s --connect-timeout 5 '%s'", url)
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    return result
end

-- HTTP POST 请求
local function http_post(url, body)
    local cmd = string.format("curl -s --connect-timeout 5 -d '%s' '%s'",
        body:gsub("'", "'\\''"), url)
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    return result
end

-- 发送登录请求 (SRUN3K POST 协议，无 IP 参数)
function api.login(username, password)
    local enc_username = crypto.encrypt_username(username)
    local enc_password = crypto.encrypt_password(password)

    local body = "action=login"
        .. "&username=" .. url_encode(enc_username)
        .. "&password=" .. url_encode(enc_password)
        .. "&ac_id=1&drop=0&pop=1&type=10&n=117&mbytes=0&minutes=0"
        .. "&mac=02%3A00%3A00%3A00%3A00%3A00"

    log.info("登录请求: " .. api.LOGIN_URL)
    log.debug("POST body: " .. body)

    local response = http_post(api.LOGIN_URL, body)

    if not response or response == "" then
        log.error("登录请求无响应")
        return false, "登录请求失败"
    end

    log.info("登录响应: " .. response)

    if response:find("login_ok") then
        return true, "登录成功"
    elseif response:find("already_online") then
        return true, "已在线"
    else
        return false, response
    end
end

-- 发送注销请求
function api.logout()
    local body = "action=logout"

    log.info("注销请求: " .. api.LOGIN_URL)

    local response = http_post(api.LOGIN_URL, body)

    if not response or response == "" then
        log.error("注销请求无响应")
        return false, "注销请求失败"
    end

    log.info("注销响应: " .. response)

    if response:find("logout_ok") or response:find("not_online") then
        return true, "注销成功"
    else
        return false, response
    end
end

-- 获取用户信息 (保持不变，GET rad_user_info)
function api.get_user_info()
    local callback, timestamp = gen_callback()
    local url = string.format(
        "%s/cgi-bin/rad_user_info?callback=%s&_=%.0f",
        api.BASE_URL, callback, math.floor(timestamp)
    )

    local response = http_get(url)
    if not response or response == "" then
        return nil
    end

    if response:find("not_online") then
        return nil
    end

    local username = response:match('"user_name":"([^"]+)"')
    local sum_bytes = response:match('"sum_bytes":(%d+)')
    local sum_seconds = response:match('"sum_seconds":(%d+)')
    local user_ip = response:match('"online_ip":"([^"]+)"')

    if username then
        return {
            username = username,
            ip = user_ip or "",
            bytes = tonumber(sum_bytes) or 0,
            seconds = tonumber(sum_seconds) or 0
        }
    end

    return nil
end

-- 测试网络连接
function api.test_connection()
    local cmd = "curl -s --connect-timeout 3 'http://www.apple.com/library/test/success.html'"
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    return result:find("Success") ~= nil
end

return api
