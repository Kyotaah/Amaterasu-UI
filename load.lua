--[[
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   天照大神  ·  A M A T E R A S U   U I   L O A D E R           ║
║                                                                  ║
║   Paste this one line into your executor:                        ║
║                                                                  ║
║   loadstring(game:HttpGet("https://amaterasu-ui.onrender.com/   ║
║   load.lua"))()                                                  ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════════════
--  CONFIG
-- ═══════════════════════════════════════════════════════════════════

local LIB_URL = "https://amaterasu-ui.onrender.com/amaterasu_lib.lua"
local VERSION = "v15.0"

-- ═══════════════════════════════════════════════════════════════════
--  LOADER  —  do not edit below this line
-- ═══════════════════════════════════════════════════════════════════

local function httpGet(url)
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(res) == "string" and #res > 10 then return res end

    if type(syn) == "table" and type(syn.request) == "function" then
        local ok2, r = pcall(syn.request, { Url = url, Method = "GET" })
        if ok2 and r and r.Body and #r.Body > 10 then return r.Body end
    end

    if type(http_request) == "function" then
        local ok3, r = pcall(http_request, { Url = url, Method = "GET" })
        if ok3 and r and r.Body and #r.Body > 10 then return r.Body end
    end

    if type(request) == "function" then
        local ok4, r = pcall(request, { Url = url, Method = "GET" })
        if ok4 and r and r.Body and #r.Body > 10 then return r.Body end
    end

    error("[Amaterasu] No working HTTP function found on this executor.")
end

local function sysNotify(title, text, dur)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title, Text = text, Duration = dur or 6,
        })
    end)
end

print(string.rep("═", 58))
print(string.format("  天照大神  AMATERASU UI  ·  %s", VERSION))
print(string.rep("─", 58))
print(string.format("  Fetching: %s", LIB_URL))
print(string.rep("═", 58))

local source
local ok, err = pcall(function() source = httpGet(LIB_URL) end)

if not ok or not source or #source < 100 then
    local msg = "Failed to fetch: " .. tostring(err or "empty response")
    warn("[Amaterasu] " .. msg)
    sysNotify("⛩️ Amaterasu UI", msg:sub(1, 100), 10)
    return
end

print(string.format("  ✓  Fetched %d bytes", #source))

local fn, compileErr = loadstring(source, "amaterasu_lib")
if not fn then
    local msg = "Compile error: " .. tostring(compileErr)
    warn("[Amaterasu] " .. msg)
    sysNotify("⛩️ Amaterasu UI", msg:sub(1, 100), 10)
    return
end

print("  ✓  Compiled — launching...")
print(string.rep("═", 58))

local runOk, runErr = pcall(fn)
if not runOk then
    warn("[Amaterasu] Runtime error: " .. tostring(runErr))
    sysNotify("⛩️ Amaterasu UI", tostring(runErr):sub(1, 100), 10)
end
