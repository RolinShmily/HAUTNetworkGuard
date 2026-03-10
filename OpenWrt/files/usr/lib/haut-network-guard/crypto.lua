#!/usr/bin/lua
-- HAUT Network Guard - 加密模块
-- SRUN3K 协议加密 (与 Windows/macOS 一致)

local crypto = {}

-- 位运算函数
local bxor, band, rshift

-- 尝试加载 bit 库
local function try_load_bit_lib()
    local ok, lib = pcall(require, "bit")
    if ok and lib and lib.bxor then
        return lib.bxor, lib.band, lib.rshift
    end

    ok, lib = pcall(require, "bit32")
    if ok and lib and lib.bxor then
        return lib.bxor, lib.band, lib.rshift
    end

    ok, lib = pcall(require, "nixio")
    if ok and lib and lib.bit and lib.bit.bxor then
        return lib.bit.bxor, lib.bit.band, lib.bit.rshift
    end

    return nil
end

local loaded_bxor, loaded_band, loaded_rshift = try_load_bit_lib()

if loaded_bxor then
    bxor = loaded_bxor
    band = loaded_band
    rshift = loaded_rshift
else
    bxor = function(a, b)
        local result, bitval = 0, 1
        a = (a or 0) % 0x100000000
        b = (b or 0) % 0x100000000
        for _ = 0, 31 do
            if a % 2 ~= b % 2 then result = result + bitval end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            bitval = bitval * 2
        end
        return result
    end

    band = function(a, b)
        local result, bitval = 0, 1
        a = (a or 0) % 0x100000000
        b = (b or 0) % 0x100000000
        for _ = 0, 31 do
            if a % 2 == 1 and b % 2 == 1 then result = result + bitval end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            bitval = bitval * 2
        end
        return result
    end

    rshift = function(n, bits)
        return math.floor(((n or 0) % 0x100000000) / (2 ^ bits))
    end
end

-- SRUN3K 用户名加密: 每个字符 ASCII + 4，前缀 "{SRUN3}\r\n"
function crypto.encrypt_username(username)
    local result = {}
    for i = 1, #username do
        result[i] = string.char(username:byte(i) + 4)
    end
    return "{SRUN3}\r\n" .. table.concat(result)
end

-- SRUN3K 密码加密: XOR(反向密钥索引) + 位分割 + 奇偶交替
function crypto.encrypt_password(password)
    local key = "1234567890"
    local key_len = #key
    local result = {}

    for i = 1, #password do
        local c = password:byte(i)
        local key_index = key_len - ((i - 1) % key_len)
        local k = key:byte(key_index)
        local ki = bxor(c, k)

        local low_bits = band(ki, 0x0F) + 0x36
        local high_bits = band(rshift(ki, 4), 0x0F) + 0x63

        if (i - 1) % 2 == 0 then
            table.insert(result, string.char(low_bits))
            table.insert(result, string.char(high_bits))
        else
            table.insert(result, string.char(high_bits))
            table.insert(result, string.char(low_bits))
        end
    end

    return table.concat(result)
end

return crypto
