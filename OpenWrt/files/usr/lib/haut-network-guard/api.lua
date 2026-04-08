#!/usr/bin/lua
-- HAUT Network Guard - API 模块
-- SRUN3K 协议 (与 macOS/Windows 一致)

local api = {}
local crypto = require("crypto")
local log = require("log")

-- 配置
api.BASE_URL = "http://172.16.154.130"
api.LOGIN_URL = "http://172.16.154.130:69/cgi-bin/srun_portal"
api.USER_AGENT = "HAUTNetworkGuard/1.3.14 OpenWrt"

local request_seq = 0

-- URL 编码: 仅允许 [A-Za-z0-9-._~] 不编码
local function url_encode(str)
    if not str then return "" end
    return string.gsub(str, "([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function shell_quote(str)
    return "'" .. tostring(str or ""):gsub("'", "'\\''") .. "'"
end

local function next_request_id(prefix)
    request_seq = request_seq + 1
    return string.format("%s-%d-%d", prefix or "req", os.time(), request_seq)
end

local function make_temp_path(prefix)
    prefix = prefix or "haut-network-guard"
    return string.format("/tmp/%s-%d-%d.tmp", prefix, os.time(), math.random(1000, 9999))
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return "" end
    local content = file:read("*a") or ""
    file:close()
    return content
end

local function write_temp_file(path, content)
    local file, err = io.open(path, "wb")
    if not file then
        return nil, err or "open_failed"
    end
    file:write(content or "")
    file:close()
    return true
end

-- 生成 jQuery 回调名
local function gen_callback()
    local timestamp = os.time() * 1000 + math.random(0, 999)
    return "jQuery_" .. tostring(timestamp), timestamp
end

local function classify_login_response(response)
    local body = tostring(response or "")
    if body:find("login_ok") then
        return "success", "登录成功"
    end
    if body:find("already_online") then
        return "already_online", "已在线"
    end

    local error_code = body:match("E(%d+)")
    if error_code == "2531" then
        return "user_not_found", "login_error#E2531:User not found"
    end
    if error_code then
        return "error_code", "login_error#E" .. error_code
    end

    return "unknown", log.preview(body, 180)
end

-- HTTP GET 请求
local function http_get(url, req_id)
    local err_file = make_temp_path("haut-network-guard-curl-get")
    local cmd = string.format(
        "curl -sS --connect-timeout 5 --max-time 8 -A %s %s 2>%s",
        shell_quote(api.USER_AGENT),
        shell_quote(url),
        shell_quote(err_file)
    )

    log.debug(string.format("[%s] HTTP GET %s", req_id, url))
    local handle = io.popen(cmd)
    if not handle then
        os.remove(err_file)
        return nil, "popen_failed"
    end

    local result = handle:read("*a") or ""
    handle:close()

    local stderr = read_file(err_file)
    os.remove(err_file)
    if stderr ~= "" then
        log.debug(string.format("[%s] HTTP GET stderr=%s", req_id, log.preview(stderr)))
    end

    log.debug(string.format("[%s] HTTP GET 响应=%s", req_id, log.bytes_summary(result)))
    return result, nil
end

-- HTTP POST 请求
local function http_post(url, body, req_id)
    local tmp_body = make_temp_path("haut-network-guard-body")
    local err_file = make_temp_path("haut-network-guard-curl-post")
    local ok, err = write_temp_file(tmp_body, body)
    if not ok then
        return nil, "write_temp_failed:" .. tostring(err)
    end

    local cmd = string.format(
        "curl -sS --connect-timeout 5 --max-time 10 -A %s " ..
        "-H 'Content-Type: application/x-www-form-urlencoded' " ..
        "--data-binary @%s %s 2>%s",
        shell_quote(api.USER_AGENT),
        shell_quote(tmp_body),
        shell_quote(url),
        shell_quote(err_file)
    )

    log.debug(string.format("[%s] HTTP POST %s, body=%s", req_id, url, log.bytes_summary(body)))
    local handle = io.popen(cmd)
    if not handle then
        os.remove(tmp_body)
        os.remove(err_file)
        return nil, "popen_failed"
    end

    local result = handle:read("*a") or ""
    handle:close()

    local stderr = read_file(err_file)
    os.remove(tmp_body)
    os.remove(err_file)
    if stderr ~= "" then
        log.debug(string.format("[%s] HTTP POST stderr=%s", req_id, log.preview(stderr)))
    end

    log.debug(string.format("[%s] HTTP POST 响应=%s", req_id, log.bytes_summary(result)))
    return result, nil
end

-- 发送登录请求 (SRUN3K POST 协议，无 IP 参数)
function api.login(username, password, context)
    context = context or {}
    local req_id = next_request_id("login")
    local source = tostring(context.source or "unknown")
    username = tostring(username or "")
    password = tostring(password or "")

    log.info(string.format(
        "[%s] 自动登录请求 source=%s user=%s user_len=%d pass_len=%d",
        req_id, source, log.mask_username(username), #username, #password
    ))
    if username:find("[%z\1-\31\127]") then
        log.warn(string.format("[%s] 用户名包含控制字符，可能导致 E2531", req_id))
    end

    local enc_username = crypto.encrypt_username(username)
    local enc_password = crypto.encrypt_password(password)
    local body = "action=login"
        .. "&username=" .. url_encode(enc_username)
        .. "&password=" .. url_encode(enc_password)
        .. "&ac_id=1&drop=0&pop=1&type=10&n=117&mbytes=0&minutes=0"
        .. "&mac=02%3A00%3A00%3A00%3A00%3A00"

    log.debug(string.format(
        "[%s] 登录编码长度 user_raw=%d user_enc=%d pass_raw=%d pass_enc=%d",
        req_id, #username, #enc_username, #password, #enc_password
    ))

    local response, post_err = http_post(api.LOGIN_URL, body, req_id)
    if post_err then
        log.error(string.format("[%s] 登录请求失败: %s", req_id, post_err))
        return false, "登录请求失败", "network_error"
    end
    if response == "" then
        log.error(string.format("[%s] 登录请求无响应", req_id))
        return false, "登录请求失败", "network_error"
    end

    local category, message = classify_login_response(response)
    log.info(string.format("[%s] 登录响应分类=%s, msg=%s", req_id, category, message))
    if category == "success" or category == "already_online" then
        return true, message, category
    end

    log.debug(string.format("[%s] 登录响应预览=%s", req_id, log.preview(response, 180)))
    return false, message, category
end

-- 发送注销请求
function api.logout()
    local req_id = next_request_id("logout")
    local body = "action=logout"

    log.info(string.format("[%s] 注销请求", req_id))
    local response, post_err = http_post(api.LOGIN_URL, body, req_id)
    if post_err then
        log.error(string.format("[%s] 注销请求失败: %s", req_id, post_err))
        return false, "注销请求失败"
    end
    if response == "" then
        log.error(string.format("[%s] 注销请求无响应", req_id))
        return false, "注销请求失败"
    end

    log.info(string.format("[%s] 注销响应=%s", req_id, log.preview(response, 120)))
    if response:find("logout_ok") or response:find("not_online") then
        return true, "注销成功"
    end
    return false, log.preview(response, 180)
end

-- 获取用户信息
function api.get_user_info(source)
    local req_id = next_request_id("status")
    source = source or "unknown"
    local callback, timestamp = gen_callback()
    local url = string.format(
        "%s/cgi-bin/rad_user_info?callback=%s&_=%.0f",
        api.BASE_URL, callback, math.floor(timestamp)
    )

    local response, get_err = http_get(url, req_id)
    if get_err or not response or response == "" then
        log.debug(string.format("[%s] 状态检测无响应 source=%s", req_id, source))
        return nil
    end
    if response:find("not_online") then
        log.debug(string.format("[%s] 状态检测: not_online", req_id))
        return nil
    end

    local username = response:match('"user_name":"([^"]+)"')
    local sum_bytes = response:match('"sum_bytes":(%d+)')
    local sum_seconds = response:match('"sum_seconds":(%d+)')
    local user_ip = response:match('"online_ip":"([^"]+)"')

    if username then
        log.debug(string.format(
            "[%s] 状态检测在线 user=%s ip=%s",
            req_id, log.mask_username(username), tostring(user_ip or "")
        ))
        return {
            username = username,
            ip = user_ip or "",
            bytes = tonumber(sum_bytes) or 0,
            seconds = tonumber(sum_seconds) or 0
        }
    end

    log.debug(string.format("[%s] 状态响应未匹配预期字段: %s", req_id, log.preview(response, 180)))
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
