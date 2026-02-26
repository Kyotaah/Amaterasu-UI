--[[
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   天照大神  ·  A M A T E R A S U   U I   L I B R A R Y          ║
║                                                                   ║
║   Public UI Library. Exposes: Lib, Notify, setAccent,            ║
║   startDual, startTriple, startRainbow, stopDynamic,             ║
║   springTween, Store, Emit, On, THEMES.                          ║
║                                                                   ║
║   One-line loader:                                                ║
║   loadstring(game:HttpGet("https://amaterasu-ui.onrender.com/    ║
║   amaterasu_lib.lua"))()                                          ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════════════
--  ENVIRONMENT — cloneref isolation, getgenv session key
-- ═══════════════════════════════════════════════════════════════════

-- cloneref: present in Delta, Wave, Seliox, Xeno, Solara (2024-25).
-- Falls back to identity on executors that don't need it (Synapse Z).
local cloneref = (type(cloneref) == "function") and cloneref or function(x) return x end
-- getgenv: executor global env — more isolated than _G across re-executions.
local genv = (type(getgenv) == "function") and getgenv() or _G

-- ═══════════════════════════════════════════════════════════════════
--  SERVICES — all cloneref'd to bypass game script detection
-- ═══════════════════════════════════════════════════════════════════

local Players      = cloneref(game:GetService("Players"))
local RunService   = cloneref(game:GetService("RunService"))
local TweenService = cloneref(game:GetService("TweenService"))
local Lighting     = cloneref(game:GetService("Lighting"))
local Stats        = cloneref(game:GetService("Stats"))
local RepStore     = cloneref(game:GetService("ReplicatedStorage"))
local CoreGui      = cloneref(game:GetService("CoreGui"))
local HttpService  = cloneref(game:GetService("HttpService"))
local UIS          = cloneref(game:GetService("UserInputService"))

local Player  = Players.LocalPlayer
local Camera  = workspace.CurrentCamera

local TAU = math.pi * 2

-- ═══════════════════════════════════════════════════════════════════
--  LOOP GUARD — kills orphaned loops from previous executions
--  Uses getgenv() for proper isolation across re-runs
-- ═══════════════════════════════════════════════════════════════════

local SESSION = os.clock()
genv.AmaterasuSession = SESSION
local function alive()
    -- pcall guard: genv might be GC'd on very fast re-executions
    local ok, result = pcall(function() return genv.AmaterasuSession == SESSION end)
    return ok and result
end

--- Remove every entry where `pred(entry)` returns true, in-place.
--- Uses the swap-and-shrink idiom: O(n), no table.remove(mid) re-shuffles.
local function pruneArray(t, pred)
    local n = #t
    local wi = 1
    for ri = 1, n do
        if not pred(t[ri]) then
            t[wi] = t[ri]
            wi = wi + 1
        end
    end
    for i = wi, n do t[i] = nil end
end

-- ═══════════════════════════════════════════════════════════════════
--  EVENT BUS — lightweight pub/sub for decoupled component comms
--  Emit(name, ...)  — broadcast event with args
--  On(name, fn)     — subscribe; returns an unsubscribe function
-- ═══════════════════════════════════════════════════════════════════
local _evListeners = {}   -- { [name] = { fn, ... } }

local function Emit(name, ...)
    local listeners = _evListeners[name]
    if not listeners then return end
    local args = { ... }
    pruneArray(listeners, function(fn)
        local ok = pcall(fn, table.unpack(args))
        return not ok  -- remove dead listeners
    end)
end

local function On(name, fn)
    if not _evListeners[name] then _evListeners[name] = {} end
    local list = _evListeners[name]
    list[#list + 1] = fn
    return function()   -- returns disconnect fn
        for i, f in ipairs(_evListeners[name] or {}) do
            if f == fn then table.remove(_evListeners[name], i); return end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  STATE STORE — centralized reactive state with watcher callbacks
--  Store.set(key, val)         → set & notify watchers
--  Store.get(key, default)     → read (returns default if nil)
--  Store.watch(key, fn)        → fn(newVal, oldVal) on every change
--                                returns an unsubscribe function
-- ═══════════════════════════════════════════════════════════════════
local _storeData     = {}   -- key → current value
local _storeWatchers = {}   -- key → { fn, ... }

local Store = {}

function Store.set(key, val)
    local old = _storeData[key]
    if old == val then return end
    _storeData[key] = val
    local ws = _storeWatchers[key]
    if ws then
        pruneArray(ws, function(fn)
            local ok = pcall(fn, val, old)
            return not ok
        end)
    end
    Emit("store:" .. tostring(key), val, old)
end

function Store.get(key, default)
    local v = _storeData[key]
    return (v ~= nil) and v or default
end

function Store.watch(key, fn)
    if not _storeWatchers[key] then _storeWatchers[key] = {} end
    local list = _storeWatchers[key]
    list[#list + 1] = fn
    return function()
        for i, f in ipairs(_storeWatchers[key] or {}) do
            if f == fn then table.remove(_storeWatchers[key], i); return end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  CLEANER — auto-disconnect registry; call :flush() on destroy
--  local c = Cleaner.new()
--  c:add(rbxConn)   -- RBXScriptConnection or function
--  c:flush()        -- disconnects/calls all, clears list
-- ═══════════════════════════════════════════════════════════════════
local Cleaner = {}
Cleaner.__index = Cleaner

function Cleaner.new()
    return setmetatable({ _items = {} }, Cleaner)
end

function Cleaner:add(item)
    self._items[#self._items + 1] = item
    return item   -- pass-through for chaining
end

function Cleaner:flush()
    for _, item in ipairs(self._items) do
        if type(item) == "function" then
            pcall(item)
        elseif type(item) == "table" and type(item.Disconnect) == "function" then
            pcall(function() item:Disconnect() end)
        elseif typeof and typeof(item) == "RBXScriptConnection" then
            pcall(function() item:Disconnect() end)
        end
    end
    self._items = {}
end

-- ═══════════════════════════════════════════════════════════════════
--  FPS TIER THROTTLE — wraps any function so it only fires when
--  current framerate is above a minimum threshold.
--  Keeps expensive non-critical work from running at low FPS.
--  Usage:  local safe = fpsThrottle(myFn, 45)  → safe(...)
-- ═══════════════════════════════════════════════════════════════════
local function fpsThrottle(fn, minFPS)
    minFPS = minFPS or 45
    return function(...)
        if _sharedFPS >= minFPS then
            return fn(...)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  TWEEN HELPER
-- ═══════════════════════════════════════════════════════════════════

local function tween(obj, props, dur, style, dir)
    if not obj then return end
    -- pcall guard: obj may be destroyed between schedule and execution
    local ok, t = pcall(function()
        if not obj.Parent then return nil end
        return TweenService:Create(obj, TweenInfo.new(
            dur   or 0.45,
            style or Enum.EasingStyle.Quint,
            dir   or Enum.EasingDirection.Out
        ), props)
    end)
    if ok and t then
        t:Play()
        return t
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  SPRING TWEEN ENGINE — damped spring simulation
--  Supports: number, UDim2, Color3.  Returns a cancel function.
--  stiffness (k): spring constant — higher = snappier (default 200)
--  damping   (d): damping ratio  — higher = less overshoot (default 18)
--  Typical presets:
--    snappy:  k=300, d=22   bouncy:  k=160, d=12   smooth: k=120, d=20
-- ═══════════════════════════════════════════════════════════════════
local _springConns = {}   -- (obj:prop) key → active RenderStepped conn

local function springTween(obj, prop, target, stiffness, damping)
    if not obj or not pcall(function() return obj.Parent end) then
        return function() end
    end
    stiffness = stiffness or 200
    damping   = damping   or 18

    local key = tostring(obj) .. ":" .. prop
    -- Cancel existing spring on same property
    if _springConns[key] then
        pcall(function() _springConns[key]:Disconnect() end)
        _springConns[key] = nil
    end

    local ok, current = pcall(function() return obj[prop] end)
    if not ok then return function() end end

    -- ── Scalar spring ─────────────────────────────────────────────────────────
    if type(current) == "number" then
        local pos = current
        local vel = 0
        local conn
        conn = RunService.RenderStepped:Connect(function(dt)
            if not alive() or not pcall(function() return obj.Parent end) then
                conn:Disconnect(); _springConns[key] = nil; return
            end
            dt = math.min(dt, 0.05)
            local force = (target - pos) * stiffness - vel * damping
            vel = vel + force * dt
            pos = pos + vel * dt
            pcall(function() obj[prop] = pos end)
            if math.abs(target - pos) < 0.001 and math.abs(vel) < 0.001 then
                pcall(function() obj[prop] = target end)
                conn:Disconnect(); _springConns[key] = nil
            end
        end)
        _springConns[key] = conn
        return function() if conn then pcall(function() conn:Disconnect() end) end end

    -- ── UDim2 spring (4 independent scalars) ─────────────────────────────────
    elseif typeof(current) == "UDim2" then
        local xs,xo = current.X.Scale, current.X.Offset
        local ys,yo = current.Y.Scale, current.Y.Offset
        local txs,txo = target.X.Scale, target.X.Offset
        local tys,tyo = target.Y.Scale, target.Y.Offset
        local vxs,vxo,vys,vyo = 0, 0, 0, 0
        local conn
        conn = RunService.RenderStepped:Connect(function(dt)
            if not alive() or not pcall(function() return obj.Parent end) then
                conn:Disconnect(); _springConns[key] = nil; return
            end
            dt = math.min(dt, 0.05)
            local function step(p, t, v)
                local f = (t - p) * stiffness - v * damping
                v = v + f * dt; p = p + v * dt
                return p, v
            end
            xs,vxs = step(xs,txs,vxs); xo,vxo = step(xo,txo,vxo)
            ys,vys = step(ys,tys,vys); yo,vyo = step(yo,tyo,vyo)
            pcall(function() obj[prop] = UDim2.new(xs,xo,ys,yo) end)
            local mag = math.abs(txs-xs)+math.abs(txo-xo)+math.abs(tys-ys)+math.abs(tyo-yo)
            local spd = math.abs(vxs)+math.abs(vxo)+math.abs(vys)+math.abs(vyo)
            if mag < 0.002 and spd < 0.01 then
                pcall(function() obj[prop] = target end)
                conn:Disconnect(); _springConns[key] = nil
            end
        end)
        _springConns[key] = conn
        return function() if conn then pcall(function() conn:Disconnect() end) end end

    -- ── Color3 spring (R, G, B independently) ────────────────────────────────
    elseif typeof(current) == "Color3" then
        local r,g,b = current.R, current.G, current.B
        local tr,tg,tb = target.R, target.G, target.B
        local vr,vg,vb = 0, 0, 0
        local conn
        conn = RunService.RenderStepped:Connect(function(dt)
            if not alive() or not pcall(function() return obj.Parent end) then
                conn:Disconnect(); _springConns[key] = nil; return
            end
            dt = math.min(dt, 0.05)
            local function step(p, t, v)
                local f = (t - p) * stiffness - v * damping
                v = v + f * dt; p = p + v * dt
                return p, v
            end
            r,vr = step(r,tr,vr); g,vg = step(g,tg,vg); b,vb = step(b,tb,vb)
            pcall(function()
                obj[prop] = Color3.new(
                    math.clamp(r,0,1), math.clamp(g,0,1), math.clamp(b,0,1))
            end)
            if math.abs(tr-r)+math.abs(tg-g)+math.abs(tb-b) < 0.002
            and math.abs(vr)+math.abs(vg)+math.abs(vb) < 0.01 then
                pcall(function() obj[prop] = target end)
                conn:Disconnect(); _springConns[key] = nil
            end
        end)
        _springConns[key] = conn
        return function() if conn then pcall(function() conn:Disconnect() end) end end

    -- ── Fallback: standard tween for unsupported types ────────────────────────
    else
        tween(obj, { [prop] = target }, 0.35, Enum.EasingStyle.Quint)
        return function() end
    end
end

local P = {
    -- Void-glass dark palette — deep obsidian with warm ember undertones
    bg      = Color3.fromRGB(6, 4, 10),      -- absolute void — deepest black-violet
    panel   = Color3.fromRGB(11, 7, 17),     -- shrine wall — elevated void layer
    card    = Color3.fromRGB(18, 11, 26),    -- card surface — deep amethyst dark
    btn     = Color3.fromRGB(255, 255, 255),
    textHi  = Color3.fromRGB(245, 235, 215), -- warm ivory — sacred script
    textLo  = Color3.fromRGB(140, 115, 150), -- muted violet-grey for secondary text
    white   = Color3.fromRGB(255, 255, 255),
    black   = Color3.new(0, 0, 0),
}

-- Accent — runtime-mutable, drives the whole color scheme
-- Creator: Solar Gold (天照 = sun goddess) · Default: Sacred Crimson (divine fire)
local ACCENT = Color3.fromRGB(220, 35, 65)  -- default: Sacred Crimson; override via setAccent()
local accentCallbacks = {}

local function onAccent(fn) accentCallbacks[#accentCallbacks + 1] = fn end

local function setAccent(c)
    -- Perceptual threshold: skip when the new color is nearly identical to current.
    -- Uses squared RGB distance (cheap, no sqrt needed).
    -- Threshold 0.004² = 0.000016 — invisible to the human eye at typical UI sizes.
    -- This stops the rainbow loop (which fires ~33 fps) from thrashing 200+ callbacks
    -- on frames where the hue shift is too small to see.
    local dr = c.R - ACCENT.R
    local dg = c.G - ACCENT.G
    local db = c.B - ACCENT.B
    if (dr*dr + dg*dg + db*db) < 0.000016 then return end

    ACCENT = c
    -- Fire all callbacks; prune dead entries in one pass (swap-and-shrink)
    pruneArray(accentCallbacks, function(fn)
        local ok = pcall(fn, c)
        return not ok   -- remove if pcall failed (dead UI element)
    end)
end

-- ═══════════════════════════════════════════════════════════════════
--  GLOBAL SPIN REGISTRY — ONE Heartbeat loop drives ALL spin rings
--  Replaces N individual RenderStepped connections per panel/window.
--  Registering a grad auto-cleans when its Parent becomes nil.
-- ═══════════════════════════════════════════════════════════════════

local _spinRegistry   = {}    -- { grad, speed, angle }
local _sharedFPS      = 60    -- updated by master loop, read by status bar
local _lastHeartbeatT = os.clock()

-- ── Dynamic theme engine state (driven by master Heartbeat loop) ─────────────
-- Replaces the previous separate task.spawn threads for rainbow/dual/triple.
local _dynMode = nil           -- "rainbow" | "dual" | "triple" | nil
local _dynH    = 0             -- rainbow: current hue (0-1)
local _dynT    = 0             -- dual/triple: interpolation position
local _dynDir  = 1             -- dual: direction of travel (+1/-1)
local _dynC1   = Color3.new()  -- dual/triple: color 1
local _dynC2   = Color3.new()  -- dual/triple: color 2
local _dynC3   = Color3.new()  -- triple:      color 3

local _masterConn
_masterConn = RunService.Heartbeat:Connect(function(dt)
    if not alive() then _masterConn:Disconnect(); return end
    -- FPS (smooth, clamped)
    local now = os.clock()
    local raw = 1 / math.max(dt, 0.001)
    _sharedFPS = math.floor(_sharedFPS * 0.85 + raw * 0.15 + 0.5)
    _lastHeartbeatT = now

    -- Spin all registered gradients; auto-prune dead entries in one pass
    pruneArray(_spinRegistry, function(entry)
        if not entry.grad.Parent then return true end   -- remove dead
        entry.angle = (entry.angle + dt * entry.speed) % 360
        entry.grad.Rotation = entry.angle
        return false
    end)

    -- ── Dynamic theme engine (rainbow / dual / triple) ────────────────────────
    -- All three modes are driven here instead of separate task.spawn loops.
    -- This eliminates 1-3 background threads and keeps color updates frame-locked.
    if _dynMode == "rainbow" then
        _dynH = (_dynH + dt * 0.13) % 1   -- full cycle in ~7.7 s
        setAccent(Color3.fromHSV(_dynH, 1, 1))
    elseif _dynMode == "dual" then
        _dynT = _dynT + _dynDir * dt * 0.60
        if _dynT >= 1 then _dynT = 1; _dynDir = -1
        elseif _dynT <= 0 then _dynT = 0; _dynDir = 1 end
        setAccent(_dynC1:Lerp(_dynC2, _dynT))
    elseif _dynMode == "triple" then
        _dynT = (_dynT + dt * 0.40) % 3
        local seg  = math.floor(_dynT)
        local frac = _dynT - seg
        local col
        if seg == 0 then      col = _dynC1:Lerp(_dynC2, frac)
        elseif seg == 1 then  col = _dynC2:Lerp(_dynC3, frac)
        else                  col = _dynC3:Lerp(_dynC1, frac) end
        setAccent(col)
    end
end)

--- Register a UIGradient for continuous rotation.
--- speed = degrees per second (e.g. 60 → full rotation in 6 s)
local function registerSpin(grad, speed)
    -- Don't register the same gradient twice
    for _, e in ipairs(_spinRegistry) do
        if e.grad == grad then e.speed = speed; return end
    end
    _spinRegistry[#_spinRegistry+1] = { grad=grad, speed=speed, angle=0 }
end

--- Attach an onAccent callback to a spinning border UIGradient.
--- Rebuilds the ColorSequence (accent → dark → accent) whenever the theme changes.
--- Deduplicates the identical pattern that was copy-pasted 8+ times.
local function makeBorderGradAccent(grad, dark)
    dark = dark or Color3.fromRGB(10, 12, 22)
    local function rebuild(c)
        if not grad.Parent then return end
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, c),
            ColorSequenceKeypoint.new(0.25, dark),
            ColorSequenceKeypoint.new(0.75, dark),
            ColorSequenceKeypoint.new(1.00, c),
        })
    end
    rebuild(ACCENT)
    onAccent(rebuild)
end



-- ═══════════════════════════════════════════════════════════════════════════════
--  ███████╗ ██████╗ ██████╗ ██████╗     ██╗   ██╗██╗
--  ██╔════╝██╔═══██╗██╔══██╗██╔══██╗    ██║   ██║██║
--  █████╗  ██║   ██║██████╔╝██║  ██║    ██║   ██║██║
--  ██╔══╝  ██║   ██║██╔══██╗██║  ██║    ██║   ██║██║
--  ██║     ╚██████╔╝██║  ██║██████╔╝    ╚██████╔╝██║
--  ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═════╝      ╚═════╝ ╚═╝
--
--  AmaterasuUI  ·  Mobile-First Advanced Roblox GUI Library
--  ─────────────────────────────────────────────────────────────────────────────
--  Architecture  (Bottom-Tab · Glass Panels · Pill Toggles · Spring Animations)
--    ScreenGui
--     └── WindowHolder (scale-in, drag, close/minimize)
--          ├── TopBar     (title · macOS orbs · draggable)
--          ├── ContentArea (full-width scrolling pages per tab)
--          │    └── Page → ScrollFrame → SectionCard → Elements
--          └── BottomTabBar  (iOS-style, accent indicator pill)
--
--  Features
--    ✦  Mobile-first: all hit-areas ≥ 48px, touch-drag sliders & window
--    ✦  Pill-switch toggles with Bounce spring & glow ring
--    ✦  Sweep-hover buttons with full-width accent flash
--    ✦  Cycle picker pills  ‹ VALUE ›
--    ✦  Draggable sliders, value badge, accent halo thumb
--    ✦  Collapsible section cards with accent top-stripe
--    ✦  Animated spinning gradient window border
--    ✦  Scale-spring open / close window animation
--    ✦  Floating FAB toggle button (draggable, spin ring)
--    ✦  Stacked toast notifications (slide in from right, auto-dismiss)
--    ✦  Full live-accent-color propagation on setAccent()
--    ✦  Delta / Synapse / fluxus / all-executor compatible (pcall guards)
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── AmaterasuUI palette (single source of truth) ─────────────────────────────────
-- P is defined above. DARK / CARD / BODY are aliases — they point at the same
-- Color3 objects as P.bg / P.card / P.panel so every surface renders identically.
-- Previously these were hardcoded to slightly different values, causing the
-- window top-bar, section cards and panels to each be a different shade.
P.sidebar = Color3.fromRGB(5, 3, 9)   -- void abyss sidebar

local DARK = P.bg    -- deepest void: window header, top-bar    (6, 4, 10)
local CARD = P.card  -- card surface: deep amethyst dark        (18, 11, 26)
local BODY = P.panel -- mid-layer panel / scroll area           (11, 7, 17)

-- ═══════════════════════════════════════════════════════════════════════════════
--  AmaterasuUI Core Helpers  (aliased as UI for backward compatibility)
-- ═══════════════════════════════════════════════════════════════════════════════
local UI = {}

-- Fast instance factory
function UI.new(class, parent, props)
    local inst = Instance.new(class)
    if props then
        for k, v in pairs(props) do inst[k] = v end
    end
    if parent then inst.Parent = parent end
    return inst
end

-- Shorthand constructors
function UI.corner(parent, r)
    return UI.new("UICorner", parent, { CornerRadius = UDim.new(0, r or 8) })
end

function UI.stroke(parent, color, thickness, transp)
    return UI.new("UIStroke", parent, {
        Color           = color or P.white,
        Thickness       = thickness or 1,
        Transparency    = transp or 0.72,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

function UI.gradient(parent, rotation, colorSeq, transSeq)
    local g = UI.new("UIGradient", parent, { Rotation = rotation or 0 })
    if colorSeq then g.Color        = colorSeq end
    if transSeq then g.Transparency = transSeq end
    return g
end

function UI.padding(parent, all)
    local v = type(all) == "number" and UDim.new(0, all) or UDim.new(0, 0)
    return UI.new("UIPadding", parent, {
        PaddingLeft   = (type(all) == "table" and UDim.new(0, all[1])) or v,
        PaddingRight  = (type(all) == "table" and UDim.new(0, all[2])) or v,
        PaddingTop    = (type(all) == "table" and UDim.new(0, all[3])) or v,
        PaddingBottom = (type(all) == "table" and UDim.new(0, all[4])) or v,
    })
end

-- Text label with sensible defaults
function UI.label(parent, text, size, props)
    local defaults = {
        BackgroundTransparency = 1,
        Text                   = text,
        TextColor3             = P.textHi,
        Font                   = Enum.Font.GothamMedium,
        TextSize               = size or 11,
        ZIndex                 = 10,
        RichText               = true,
        TextXAlignment         = Enum.TextXAlignment.Center,
    }
    if props then for k, v in pairs(props) do defaults[k] = v end end
    return UI.new("TextLabel", parent, defaults)
end

-- Button with hover/press effects
function UI.button(parent, text, zIndex, callback)
    local btn = UI.new("TextButton", parent, {
        BackgroundColor3       = P.btn,
        BackgroundTransparency = 0.84,
        Text                   = text,
        TextColor3             = P.textHi,
        Font                   = Enum.Font.GothamMedium,
        TextSize               = 10,
        ZIndex                 = zIndex or 10,
        AutoButtonColor        = false,
    })
    UI.corner(btn, 8)
    local stroke = UI.stroke(btn, P.white, 1, 0.72)
    btn.MouseEnter:Connect(function()
        tween(btn,    { BackgroundTransparency = 0.58 }, 0.22, Enum.EasingStyle.Sine)
        tween(stroke, { Color = ACCENT, Transparency = 0.30 }, 0.22, Enum.EasingStyle.Sine)
    end)
    btn.MouseLeave:Connect(function()
        tween(btn,    { BackgroundTransparency = 0.84 }, 0.28, Enum.EasingStyle.Sine)
        tween(stroke, { Color = P.white, Transparency = 0.72 }, 0.28, Enum.EasingStyle.Sine)
    end)
    btn.MouseButton1Down:Connect(function()
        tween(btn, { BackgroundTransparency = 0.30, BackgroundColor3 = ACCENT }, 0.10, Enum.EasingStyle.Sine)
    end)
    btn.MouseButton1Up:Connect(function()
        tween(btn, { BackgroundTransparency = 0.58, BackgroundColor3 = P.btn }, 0.18, Enum.EasingStyle.Sine)
    end)
    if callback then btn.MouseButton1Click:Connect(callback) end
    return btn, stroke
end

-- Separator line
function UI.sep(parent, yOffset, zIndex)
    return UI.new("Frame", parent, {
        Size                   = UDim2.new(1, -16, 0, 1),
        Position               = UDim2.new(0, 8, 0, yOffset),
        BackgroundColor3       = P.white,
        BackgroundTransparency = 0.85,
        BorderSizePixel        = 0,
        ZIndex                 = zIndex or 11,
    })
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  ✨ UI.lib PREMIUM UPGRADES  v10  — AmaterasuUI Enhanced Components
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── UI.ripple — Material Design ripple on any TextButton ───────────────────────
-- Spawns a white circle that expands from the tap/click position and fades out.
-- Call once per button; it auto-connects and handles all future clicks.
function UI.ripple(btn, color)
    color = color or Color3.fromRGB(255, 255, 255)
    btn.MouseButton1Down:Connect(function(x, y)
        -- Convert absolute screen position to local frame position
        local abs = btn.AbsolutePosition
        local sz  = btn.AbsoluteSize
        local lx  = x - abs.X
        local ly  = y - abs.Y
        -- Ripple size = diagonal of button so it covers corners
        local maxR = math.sqrt(sz.X^2 + sz.Y^2) * 1.15

        local clip = UI.new("Frame", btn, {
            Size                   = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            ZIndex                 = btn.ZIndex + 2,
            ClipsDescendants       = true,
        })
        local ripple = UI.new("Frame", clip, {
            Size                   = UDim2.new(0, 0, 0, 0),
            Position               = UDim2.new(0, lx, 0, ly),
            AnchorPoint            = Vector2.new(0.5, 0.5),
            BackgroundColor3       = color,
            BackgroundTransparency = 0.62,
            ZIndex                 = btn.ZIndex + 3,
        })
        UI.corner(ripple, 9999)

        -- Expand outward
        tween(ripple, {
            Size                   = UDim2.new(0, maxR * 2, 0, maxR * 2),
            BackgroundTransparency = 0.86,
        }, 0.55, Enum.EasingStyle.Quint)
        -- Fade fully out and clean up
        task.delay(0.38, function()
            if ripple.Parent then
                tween(ripple, { BackgroundTransparency = 1 }, 0.28, Enum.EasingStyle.Sine)
            end
        end)
        task.delay(0.68, function()
            if clip.Parent then clip:Destroy() end
        end)
    end)
end

-- ── UI.tooltip — hover tooltip for any GuiObject ───────────────────────────────
-- Shows a small floating label when the element is hovered.
-- Disappears on MouseLeave. On mobile (touch-only) it's skipped silently.
function UI.tooltip(element, text, yOffset)
    yOffset = yOffset or -28
    local tipHolder, tipBody

    element.MouseEnter:Connect(function()
        if tipHolder then return end  -- already showing

        -- Measure label first pass (approximate)
        local charW  = 6.5
        local tipW   = math.clamp(math.floor(#text * charW) + 22, 50, 220)

        tipHolder = UI.new("Frame", element, {
            Size                   = UDim2.new(0, tipW, 0, 22),
            Position               = UDim2.new(0.5, 0, 0, yOffset),
            AnchorPoint            = Vector2.new(0.5, 1),
            BackgroundTransparency = 1,
            ZIndex                 = 999,
        })

        tipBody = UI.new("Frame", tipHolder, {
            Size                   = UDim2.new(1, 0, 1, 0),
            BackgroundColor3       = Color3.fromRGB(18, 20, 32),
            BackgroundTransparency = 0.06,
            ZIndex                 = 999,
        })
        UI.corner(tipBody, 6)
        UI.stroke(tipBody, P.white, 1, 0.84)

        UI.new("TextLabel", tipBody, {
            Size                   = UDim2.new(1, -6, 1, 0),
            Position               = UDim2.new(0, 3, 0, 0),
            BackgroundTransparency = 1,
            Text                   = text,
            TextColor3             = P.textHi,
            Font                   = Enum.Font.GothamMedium,
            TextSize               = 9,
            ZIndex                 = 1000,
            RichText               = true,
        })

        -- Fade in with slight upward float
        tipHolder.Position = UDim2.new(0.5, 0, 0, yOffset + 6)
        tipBody.BackgroundTransparency = 1
        tween(tipHolder, { Position = UDim2.new(0.5, 0, 0, yOffset) }, 0.18, Enum.EasingStyle.Quint)
        tween(tipBody,   { BackgroundTransparency = 0.06 }, 0.16, Enum.EasingStyle.Sine)
    end)

    element.MouseLeave:Connect(function()
        if not tipHolder then return end
        local th = tipHolder; tipHolder = nil; tipBody = nil
        tween(th, { Position = UDim2.new(0.5, 0, 0, yOffset + 6) }, 0.15, Enum.EasingStyle.Sine)
        task.delay(0.16, function() if th.Parent then th:Destroy() end end)
    end)
end

-- ── UI.badge — accent pill badge (for labels, counts, status) ─────────────────
-- Returns the badge Frame. Set badge:SetText("3") to update count.
function UI.badge(parent, text, zIndex)
    local TEXT_PAD = 8
    local badgeFrame = UI.new("Frame", parent, {
        Size                   = UDim2.new(0, 28, 0, 16),
        BackgroundColor3       = ACCENT,
        BackgroundTransparency = 0.08,
        ZIndex                 = zIndex or 12,
    })
    UI.corner(badgeFrame, 8)
    onAccent(function(c) if badgeFrame.Parent then badgeFrame.BackgroundColor3 = c end end)

    local badgeLbl = UI.new("TextLabel", badgeFrame, {
        Size                   = UDim2.new(1, -TEXT_PAD, 1, 0),
        Position               = UDim2.new(0, TEXT_PAD / 2, 0, 0),
        BackgroundTransparency = 1,
        Text                   = tostring(text),
        TextColor3             = P.white,
        Font                   = Enum.Font.GothamBold,
        TextSize               = 9,
        ZIndex                 = zIndex and zIndex + 1 or 13,
    })

    function badgeFrame:SetText(t)
        badgeLbl.Text = tostring(t)
        -- Pulse animation on update
        tween(badgeFrame, { BackgroundTransparency = 0 }, 0.08, Enum.EasingStyle.Sine)
        task.delay(0.10, function()
            if badgeFrame.Parent then
                tween(badgeFrame, { BackgroundTransparency = 0.08 }, 0.18, Enum.EasingStyle.Sine)
            end
        end)
    end
    function badgeFrame:SetColor(c)
        badgeFrame.BackgroundColor3 = c
    end
    return badgeFrame
end

-- ── UI.progressRing — circular progress indicator using two rotated frames ─────
-- size: pixel size of the ring square. thickness: ring stroke width.
-- Returns a table with :SetProgress(0..1) and :SetColor(color).
function UI.progressRing(parent, size, thickness, zIndex)
    thickness = thickness or 4
    zIndex    = zIndex    or 12
    size      = size      or 32

    local holder = UI.new("Frame", parent, {
        Size                   = UDim2.new(0, size, 0, size),
        BackgroundTransparency = 1,
        ZIndex                 = zIndex,
        ClipsDescendants       = false,
    })

    -- Track background
    local trackBg = UI.new("Frame", holder, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundColor3       = Color3.fromRGB(30, 34, 52),
        BackgroundTransparency = 0.36,
        ZIndex                 = zIndex,
    })
    UI.corner(trackBg, size / 2)
    UI.new("UIStroke", trackBg, {
        Color           = Color3.fromRGB(40, 44, 64),
        Thickness       = thickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })

    -- Accent progress arc (clip-based half-rotation)
    local arc = UI.new("Frame", holder, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        ZIndex                 = zIndex + 1,
    })
    UI.new("UIStroke", arc, {
        Color           = ACCENT,
        Thickness       = thickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
    UI.corner(arc, size / 2)
    onAccent(function(c)
        local s = arc:FindFirstChildWhichIsA("UIStroke")
        if s then s.Color = c end
    end)

    -- Tween the stroke rotation to simulate progress
    local ring = { _progress = 0, holder = holder }
    function ring:SetProgress(p)
        p = math.clamp(p, 0, 1)
        ring._progress = p
        -- Use arc rotation as a visual proxy (works well for 0-100% fill)
        tween(arc, { Rotation = p * 360 }, 0.45, Enum.EasingStyle.Quint)
    end
    function ring:SetColor(c)
        local s = arc:FindFirstChildWhichIsA("UIStroke")
        if s then s.Color = c end
    end
    function ring:SetPosition(pos)
        holder.Position = pos
    end
    function ring:SetAnchor(ap)
        holder.AnchorPoint = ap
    end
    return ring
end

-- ── UI.progressBar — horizontal accent bar with smooth Set(0..1) updates ────────
-- h: pixel height (default 4). Returns { Set(0-1), SetColor(c), Pulse(), Destroy() }.
function UI.progressBar(parent, h, zIndex)
    h      = h      or 4
    zIndex = zIndex or 12
    local track = UI.new("Frame", parent, {
        Size                   = UDim2.new(1, 0, 0, h),
        BackgroundColor3       = Color3.fromRGB(22, 26, 44),
        BackgroundTransparency = 0.28,
        ZIndex                 = zIndex,
        ClipsDescendants       = true,
    })
    UI.corner(track, math.ceil(h / 2))

    local fill = UI.new("Frame", track, {
        Size                   = UDim2.new(0, 0, 1, 0),
        BackgroundColor3       = ACCENT,
        BorderSizePixel        = 0,
        ZIndex                 = zIndex + 1,
    })
    UI.corner(fill, math.ceil(h / 2))
    onAccent(function(c) if fill.Parent then fill.BackgroundColor3 = c end end)

    -- Leading glow dot
    local glow = UI.new("Frame", fill, {
        Size                   = UDim2.new(0, h * 4, h * 2, 0),
        Position               = UDim2.new(1, -h, 0.5, 0),
        AnchorPoint            = Vector2.new(0.5, 0.5),
        BackgroundColor3       = ACCENT,
        BackgroundTransparency = 0.50,
        ZIndex                 = zIndex + 2,
    })
    UI.corner(glow, h * 2)
    onAccent(function(c) if glow.Parent then glow.BackgroundColor3 = c end end)

    local bar = { _v = 0, holder = track }
    function bar:Set(v, instant)
        v = math.clamp(v, 0, 1)
        bar._v = v
        local dur = instant and 0 or 0.35
        tween(fill, { Size = UDim2.new(v, 0, 1, 0) }, dur, Enum.EasingStyle.Quint)
        glow.Visible = v > 0.02 and v < 0.99
    end
    function bar:SetColor(c)
        if fill.Parent then fill.BackgroundColor3 = c end
        if glow.Parent then glow.BackgroundColor3 = c end
    end
    function bar:Pulse()
        tween(fill, { BackgroundTransparency = 0.40 }, 0.08, Enum.EasingStyle.Sine)
        task.delay(0.09, function()
            if fill.Parent then tween(fill, { BackgroundTransparency = 0 }, 0.20, Enum.EasingStyle.Sine) end
        end)
    end
    function bar:Destroy()
        if track.Parent then track:Destroy() end
    end
    return bar
end

-- ── UI.iconButton — compact icon-only TextButton with ripple + glow ────────────
-- icon: text/emoji, size: frame pixel size, callback: click handler
function UI.iconButton(parent, icon, size, zIndex, callback)
    size   = size   or 32
    zIndex = zIndex or 12

    local holder = UI.new("Frame", parent, {
        Size                   = UDim2.new(0, size, 0, size),
        BackgroundColor3       = P.panel,
        BackgroundTransparency = 0.42,
        ZIndex                 = zIndex,
    })
    UI.corner(holder, size / 2)
    UI.stroke(holder, P.white, 1, 0.80)

    local glow = UI.new("Frame", holder, {
        Size                   = UDim2.new(1, 14, 1, 14),
        Position               = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint            = Vector2.new(0.5, 0.5),
        BackgroundColor3       = ACCENT,
        BackgroundTransparency = 1,
        ZIndex                 = zIndex - 1,
    })
    UI.corner(glow, size / 2 + 7)
    onAccent(function(c) if glow.Parent then glow.BackgroundColor3 = c end end)

    local btn = UI.new("TextButton", holder, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                   = icon,
        TextColor3             = P.textHi,
        Font                   = Enum.Font.GothamBold,
        TextSize               = math.floor(size * 0.44),
        ZIndex                 = zIndex + 1,
        AutoButtonColor        = false,
    })
    UI.ripple(btn, ACCENT)

    btn.MouseEnter:Connect(function()
        tween(holder, { BackgroundTransparency = 0.18 }, 0.14, Enum.EasingStyle.Sine)
        tween(glow,   { BackgroundTransparency = 0.72 }, 0.14, Enum.EasingStyle.Sine)
        tween(holder, { Size = UDim2.new(0, size + 3, 0, size + 3) }, 0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    end)
    btn.MouseLeave:Connect(function()
        tween(holder, { BackgroundTransparency = 0.42 }, 0.18, Enum.EasingStyle.Sine)
        tween(glow,   { BackgroundTransparency = 1    }, 0.18, Enum.EasingStyle.Sine)
        tween(holder, { Size = UDim2.new(0, size, 0, size) }, 0.18, Enum.EasingStyle.Sine)
    end)
    btn.MouseButton1Down:Connect(function()
        tween(holder, { Size = UDim2.new(0, size - 3, 0, size - 3) }, 0.08, Enum.EasingStyle.Sine)
        tween(glow,   { BackgroundTransparency = 0.50 }, 0.08, Enum.EasingStyle.Sine)
    end)
    btn.MouseButton1Up:Connect(function()
        tween(holder, { Size = UDim2.new(0, size, 0, size) }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        tween(glow,   { BackgroundTransparency = 1 }, 0.18, Enum.EasingStyle.Sine)
    end)
    if callback then btn.MouseButton1Click:Connect(callback) end

    return { holder = holder, btn = btn }
end

-- ── UI.shimmer — attaches a looping shimmer sweep to any Frame ─────────────────
-- Used as a "skeleton loading" or "active/highlighted" effect.
-- Returns a disconnect function to stop the shimmer.
function UI.shimmer(frame, speed)
    speed = speed or 1.4
    local shim = UI.new("Frame", frame, {
        Size                   = UDim2.new(0.5, 0, 1, 0),
        Position               = UDim2.new(-0.5, 0, 0, 0),
        BackgroundColor3       = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.88,
        ZIndex                 = (frame.ZIndex or 10) + 2,
        ClipsDescendants       = false,
    })
    UI.gradient(shim, 90, nil, NumberSequence.new({
        NumberSequenceKeypoint.new(0,   1),
        NumberSequenceKeypoint.new(0.4, 0.72),
        NumberSequenceKeypoint.new(0.6, 0.72),
        NumberSequenceKeypoint.new(1,   1),
    }))

    local running = true
    task.spawn(function()
        while running and shim.Parent do
            shim.Position = UDim2.new(-0.5, 0, 0, 0)
            tween(shim, { Position = UDim2.new(1, 0, 0, 0) }, speed, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
            task.wait(speed + 0.3)
        end
    end)

    return function()
        running = false
        if shim.Parent then shim:Destroy() end
    end
end

-- ── UI.divider — labeled text separator ─────────────────────────────────────
-- Creates a horizontal rule with centered optional text label.
-- Returns the container frame.
function UI.divider(parent, text, zIndex)
    zIndex = zIndex or 11
    local h = text and text ~= "" and 18 or 10
    local holder = UI.new("Frame", parent, {
        Size                   = UDim2.new(1, 0, 0, h),
        BackgroundTransparency = 1,
        ZIndex                 = zIndex,
    })
    if text and text ~= "" then
        -- Left line
        UI.new("Frame", holder, {
            Size             = UDim2.new(0.38, -4, 0, 1),
            Position         = UDim2.new(0, 6, 0.5, 0),
            AnchorPoint      = Vector2.new(0, 0.5),
            BackgroundColor3 = P.white,
            BackgroundTransparency = 0.82,
            BorderSizePixel  = 0,
            ZIndex           = zIndex,
        })
        -- Label
        UI.new("TextLabel", holder, {
            Size             = UDim2.new(0.24, 0, 1, 0),
            Position         = UDim2.new(0.38, 0, 0, 0),
            BackgroundTransparency = 1,
            Text             = text,
            TextColor3       = P.textLo,
            Font             = Enum.Font.GothamMedium,
            TextSize         = 8,
            TextXAlignment   = Enum.TextXAlignment.Center,
            ZIndex           = zIndex + 1,
        })
        -- Right line
        UI.new("Frame", holder, {
            Size             = UDim2.new(0.38, -4, 0, 1),
            Position         = UDim2.new(0.62, 4, 0.5, 0),
            AnchorPoint      = Vector2.new(0, 0.5),
            BackgroundColor3 = P.white,
            BackgroundTransparency = 0.82,
            BorderSizePixel  = 0,
            ZIndex           = zIndex,
        })
    else
        UI.new("Frame", holder, {
            Size             = UDim2.new(1, -12, 0, 1),
            Position         = UDim2.new(0, 6, 0.5, 0),
            AnchorPoint      = Vector2.new(0, 0.5),
            BackgroundColor3 = P.white,
            BackgroundTransparency = 0.85,
            BorderSizePixel  = 0,
            ZIndex           = zIndex,
        })
    end
    return holder
end

-- ── UI.searchInput — live search/filter box with clear button ──────────────
-- parent: parent frame; placeholder: hint text; onSearch(text): callback
-- Returns { frame=holder, input=ib, SetValue=fn, Clear=fn }
function UI.searchInput(parent, placeholder, onSearch, zIndex)
    zIndex = zIndex or 10
    local holder = UI.new("Frame", parent, {
        Size             = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Color3.fromRGB(16, 20, 34),
        BackgroundTransparency = 0.22,
        ZIndex           = zIndex,
    })
    UI.corner(holder, 8)
    local stroke = UI.stroke(holder, P.white, 1, 0.80)

    -- 🔍 icon
    UI.new("TextLabel", holder, {
        Size             = UDim2.new(0, 22, 1, 0),
        BackgroundTransparency = 1,
        Text             = "🔍",
        TextSize         = 11,
        ZIndex           = zIndex + 1,
    })

    -- Text input
    local ib = UI.new("TextBox", holder, {
        Size             = UDim2.new(1, -48, 1, 0),
        Position         = UDim2.new(0, 22, 0, 0),
        BackgroundTransparency = 1,
        TextColor3       = P.textHi,
        PlaceholderText  = placeholder or "Search…",
        PlaceholderColor3 = P.textLo,
        Font             = Enum.Font.GothamMedium,
        TextSize         = 10,
        ZIndex           = zIndex + 1,
        ClearTextOnFocus = false,
    })

    -- Clear (×) button — only visible when there's text
    local clearBtn = UI.new("TextButton", holder, {
        Size             = UDim2.new(0, 22, 1, 0),
        Position         = UDim2.new(1, -24, 0, 0),
        BackgroundTransparency = 1,
        Text             = "×",
        TextColor3       = P.textLo,
        Font             = Enum.Font.GothamBold,
        TextSize         = 9,
        ZIndex           = zIndex + 2,
        AutoButtonColor  = false,
        Visible          = false,
    })

    ib.Focused:Connect(function()
        tween(stroke, { Color = ACCENT, Transparency = 0.32 }, 0.18)
        tween(holder, { BackgroundTransparency = 0.06 }, 0.18)
    end)
    ib.FocusLost:Connect(function()
        tween(stroke, { Color = P.white, Transparency = 0.80 }, 0.18)
        tween(holder, { BackgroundTransparency = 0.22 }, 0.18)
    end)
    ib:GetPropertyChangedSignal("Text"):Connect(function()
        local t = ib.Text
        clearBtn.Visible = #t > 0
        if onSearch then onSearch(t) end
    end)
    clearBtn.MouseButton1Click:Connect(function()
        ib.Text = ""
        clearBtn.Visible = false
        if onSearch then onSearch("") end
    end)
    onAccent(function(c) if stroke.Parent then stroke.Color = c end end)

    local api = {
        frame    = holder,
        input    = ib,
        SetValue = function(v) ib.Text = tostring(v or "") end,
        Clear    = function() ib.Text = "" end,
    }
    return api
end

-- ── UI.stagger — animate a list of frames sequentially ───────────────────────
-- frames: array of GuiObjects  props: tween target table  delay: gap per item
-- Example: UI.stagger(rows, { BackgroundTransparency = 0 }, 0.25, 0.05)
function UI.stagger(frames, props, dur, delay, style)
    dur   = dur   or 0.28
    delay = delay or 0.055
    style = style or Enum.EasingStyle.Quint
    for i, f in ipairs(frames) do
        task.delay((i - 1) * delay, function()
            if f and f.Parent then
                tween(f, props, dur, style, Enum.EasingDirection.Out)
            end
        end)
    end
end

-- ── UI.contextMenu — animated right-click/long-press popup menu ──────────────
-- items: array of { label, icon (optional), callback }
-- Returns: { Show(x, y), Hide(), Destroy() }
-- Attach via element.MouseButton2Click:Connect(function() ctx.Show(x, y) end)
function UI.contextMenu(parentSg, items)
    local ITEM_H = 34
    local MENU_W = 164
    local PAD    = 6
    local alive2 = true

    -- Full-screen invisible overlay catches clicks outside menu to dismiss
    local overlay = UI.new("Frame", parentSg, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        ZIndex                 = 200,
        Visible                = false,
    })
    -- Make it interactable so clicks register
    local overlayBtn = UI.new("TextButton", overlay, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                   = "",
        ZIndex                 = 200,
        AutoButtonColor        = false,
    })

    local totalH = #items * ITEM_H + PAD * 2
    local menu = UI.new("Frame", parentSg, {
        Size                   = UDim2.new(0, MENU_W, 0, totalH),
        BackgroundColor3       = Color3.fromRGB(13, 16, 26),
        BackgroundTransparency = 0.04,
        ZIndex                 = 201,
        Visible                = false,
        ClipsDescendants       = true,
    })
    UI.corner(menu, 10)
    local menuStroke = UI.stroke(menu, ACCENT, 1.5, 0.52)
    onAccent(function(c)
        if menuStroke and menuStroke.Parent then menuStroke.Color = c end
    end)

    -- Drop shadow behind menu
    local menuShadow = UI.new("Frame", menu, {
        Size             = UDim2.new(1, 24, 1, 24),
        Position         = UDim2.new(0.5, 0, 0.5, 5),
        AnchorPoint      = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.58,
        ZIndex           = 199,
    })
    UI.corner(menuShadow, 13)

    -- Build item rows
    for i, item in ipairs(items) do
        local yOff = PAD + (i - 1) * ITEM_H

        local row = UI.new("TextButton", menu, {
            Size                   = UDim2.new(1, 0, 0, ITEM_H),
            Position               = UDim2.new(0, 0, 0, yOff),
            BackgroundColor3       = ACCENT,
            BackgroundTransparency = 1,
            Text                   = "",
            ZIndex                 = 202,
            AutoButtonColor        = false,
        })

        local iconW = (item.icon) and 28 or 0
        if item.icon then
            UI.new("TextLabel", row, {
                Size                   = UDim2.new(0, iconW, 1, 0),
                BackgroundTransparency = 1,
                Text                   = item.icon,
                TextSize               = 13,
                ZIndex                 = 203,
            })
        end

        local lbl = UI.new("TextLabel", row, {
            Size                   = UDim2.new(1, -(iconW + 10), 1, 0),
            Position               = UDim2.new(0, iconW + 8, 0, 0),
            BackgroundTransparency = 1,
            Text                   = item.label or "",
            TextColor3             = P.textHi,
            Font                   = Enum.Font.GothamMedium,
            TextSize               = 11,
            TextXAlignment         = Enum.TextXAlignment.Left,
            ZIndex                 = 203,
        })

        -- Separator (not after last item)
        if i < #items then
            UI.new("Frame", menu, {
                Size             = UDim2.new(1, -14, 0, 1),
                Position         = UDim2.new(0, 7, 0, yOff + ITEM_H),
                BackgroundColor3 = P.white,
                BackgroundTransparency = 0.90,
                ZIndex           = 202,
            })
        end

        row.MouseEnter:Connect(function()
            tween(row, { BackgroundTransparency = 0.80 }, 0.09, Enum.EasingStyle.Sine)
            tween(lbl, { TextColor3 = P.white }, 0.09, Enum.EasingStyle.Sine)
        end)
        row.MouseLeave:Connect(function()
            tween(row, { BackgroundTransparency = 1 }, 0.13, Enum.EasingStyle.Sine)
            tween(lbl, { TextColor3 = P.textHi }, 0.13, Enum.EasingStyle.Sine)
        end)
        row.MouseButton1Click:Connect(function()
            ctx.Hide()
            if item.callback then task.spawn(function() pcall(item.callback) end) end
        end)
    end

    local visible = false
    local ctx   -- forward-declare so hide() closure can reference it

    local function show(x, y)
        -- Clamp so menu never goes off-screen
        local vp = Camera.ViewportSize
        local clampX = math.min(x, vp.X - MENU_W - 4)
        local clampY = math.min(y, vp.Y - totalH - 4)
        visible = true
        menu.Position = UDim2.new(0, clampX, 0, clampY)
        menu.Size     = UDim2.new(0, MENU_W, 0, 0)
        menu.Visible  = true
        overlay.Visible = true
        -- Spring open
        springTween(menu, "Size", UDim2.new(0, MENU_W, 0, totalH), 280, 22)
    end

    local function hide()
        if not visible then return end
        visible = false
        overlay.Visible = false
        tween(menu, { Size = UDim2.new(0, MENU_W, 0, 0) }, 0.14, Enum.EasingStyle.Quint)
        task.delay(0.16, function()
            if not visible and menu.Parent then menu.Visible = false end
        end)
    end

    overlayBtn.MouseButton1Click:Connect(hide)

    ctx = {
        Show    = show,
        Hide    = hide,
        Destroy = function()
            alive2 = false
            hide()
            task.delay(0.20, function()
                pcall(function() if overlay.Parent  then overlay:Destroy()    end end)
                pcall(function() if menu.Parent     then menu:Destroy()       end end)
            end)
        end,
    }
    return ctx
end

-- ── UI.accentPulse — one-shot accent flash on any frame ─────────────────────
-- Flash the given frame with the accent color and fade back.
-- dur: total duration in seconds (default 0.6)
function UI.accentPulse(frame, dur)
    if not frame or not frame.Parent then return end
    dur = dur or 0.6
    local orig = frame.BackgroundColor3
    local origTr = frame.BackgroundTransparency
    tween(frame, { BackgroundColor3 = ACCENT, BackgroundTransparency = 0.15 },
          dur * 0.2, Enum.EasingStyle.Sine)
    task.delay(dur * 0.2, function()
        if frame.Parent then
            tween(frame, { BackgroundColor3 = orig, BackgroundTransparency = origTr },
                  dur * 0.8, Enum.EasingStyle.Quint)
        end
    end)
end

-- ── UI.spinner — compact standalone loading spinner ─────────────────────────
-- Returns the holder frame. Attach it wherever you need a loading indicator.
-- Call :Destroy() on the returned frame to stop and remove the spinner.
function UI.spinner(parent, size, zIndex)
    size   = size   or 24
    zIndex = zIndex or 12
    local holder = UI.new("Frame", parent, {
        Size                   = UDim2.new(0, size, 0, size),
        BackgroundTransparency = 1,
        ZIndex                 = zIndex,
    })
    local ring = UI.new("Frame", holder, {
        Size             = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(30, 34, 52),
        BackgroundTransparency = 0.40,
        ZIndex           = zIndex,
    })
    UI.corner(ring, size / 2)
    UI.new("UIStroke", ring, {
        Color           = Color3.fromRGB(44, 50, 72),
        Thickness       = math.max(2, math.floor(size * 0.14)),
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
    local arc = UI.new("Frame", holder, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        ZIndex                 = zIndex + 1,
    })
    UI.corner(arc, size / 2)
    local arcStroke = UI.new("UIStroke", arc, {
        Color           = ACCENT,
        Thickness       = math.max(2, math.floor(size * 0.14)),
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
    onAccent(function(c)
        if arcStroke.Parent then arcStroke.Color = c end
    end)
    -- Register the arc frame for spin
    local spinGr = UI.gradient(arc, 0, ColorSequence.new({
        ColorSequenceKeypoint.new(0, ACCENT),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 12, 22)),
    }))
    registerSpin(spinGr, 280)
    return holder
end

-- ── Upgrade existing UI.button to include ripple + tooltip support ─────────────
local _originalButton = UI.button
function UI.button(parent, text, zIndex, callback, tooltipText)
    local btn, stroke = _originalButton(parent, text, zIndex, callback)
    -- Attach ripple to every button by default
    UI.ripple(btn, ACCENT)
    -- Optional tooltip
    if tooltipText then
        UI.tooltip(btn, tooltipText)
    end
    return btn, stroke
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Returns { holder, body, spinGrad, shadow }
function UI.glassPanel(parent, size, pos, zBase)
    zBase = zBase or 5

    local holder = UI.new("Frame", parent, {
        Size                   = size,
        Position               = pos,
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(0.5, 0.5),
        ZIndex                 = zBase,
        ClipsDescendants       = false,
    })

    local shadow = UI.new("Frame", holder, {
        Size                   = UDim2.new(1, 10, 1, 10),
        Position               = UDim2.new(0.5, 0, 0.5, 0),  -- perfectly centered (offset 0)
        AnchorPoint            = Vector2.new(0.5, 0.5),
        BackgroundColor3       = ACCENT,
        BackgroundTransparency = 0.90,
        ZIndex                 = zBase - 1,
    })
    UI.corner(shadow, 20)
    onAccent(function(c) if shadow.Parent then shadow.BackgroundColor3 = c end end)

    local spinFrame = UI.new("Frame", holder, {
        Size                   = UDim2.new(1, 6, 1, 6),
        Position               = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint            = Vector2.new(0.5, 0.5),
        BackgroundColor3       = P.white,
        ZIndex                 = zBase,
    })
    UI.corner(spinFrame, 18)

    local spinGrad = UI.gradient(spinFrame, 0,
        ColorSequence.new({
            ColorSequenceKeypoint.new(0,    ACCENT),
            ColorSequenceKeypoint.new(0.45, Color3.fromRGB(10, 12, 22)),
            ColorSequenceKeypoint.new(1,    ACCENT),
        })
    )
    -- Unified accent sync helper — replaces the 8 identical onAccent blocks
    onAccent(function(c)
        if not spinGrad.Parent then return end
        spinGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    c),
            ColorSequenceKeypoint.new(0.45, Color3.fromRGB(10, 12, 22)),
            ColorSequenceKeypoint.new(1,    c),
        })
    end)
    -- Single master loop handles all spin rings — no per-panel RenderStepped
    registerSpin(spinGrad, 72)

    local body = UI.new("Frame", holder, {
        Name                   = "Body",
        Size                   = UDim2.new(1, 0, 1, 0),
        Position               = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint            = Vector2.new(0.5, 0.5),
        BackgroundColor3       = P.panel,
        BackgroundTransparency = 0.28,
        ZIndex                 = zBase + 1,
        -- Block all touches so they don't pass through to game world
        Active                 = true,
    })
    UI.corner(body, 16)
    UI.stroke(body, P.white, 1.5, 0.72)

    -- Inner gloss strip
    local gloss = UI.new("Frame", body, {
        Size                   = UDim2.new(1, -4, 0.32, 0),
        Position               = UDim2.new(0, 2, 0, 2),
        BackgroundColor3       = P.white,
        BackgroundTransparency = 0.91,
        ZIndex                 = zBase + 2,
        ClipsDescendants       = true,
    })
    UI.corner(gloss, 15)
    UI.gradient(gloss, 90, nil,
        NumberSequence.new({
            NumberSequenceKeypoint.new(0,   0),
            NumberSequenceKeypoint.new(0.6, 0.5),
            NumberSequenceKeypoint.new(1,   1),
        })
    )

    -- spinFrame is exposed so callers (e.g. Notify) can fade it in/out independently
    return { holder = holder, body = body, spinGrad = spinGrad, shadow = shadow, spinFrame = spinFrame }
end

-- ── _makeDraggable — unified drag implementation ─────────────────────────────
-- Used internally by both _drag(handle, target) and UI.draggable(element).
-- handle: the GuiObject whose InputBegan triggers dragging.
-- target: the GuiObject that actually moves (often the same as handle's parent).
-- Uses absolute offset math — zero drift, perfect finger tracking.
-- Polls UIS:GetMouseLocation() every RenderStepped for the smoothest possible
-- position update, synchronized to the render frame.
local function _makeDraggable(handle, target)
    local dragging  = false
    local startMX, startMY     = 0, 0
    local startOffX, startOffY = 0, 0
    local scaleX, scaleY       = 0.5, 0.5

    handle.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1
        and i.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging = true
        pcall(function() i.Handled = true end)
        local mp  = UIS:GetMouseLocation()
        startMX   = mp.X
        startMY   = mp.Y
        local p   = target.Position
        startOffX = p.X.Offset
        startOffY = p.Y.Offset
        scaleX    = p.X.Scale
        scaleY    = p.Y.Scale
    end)

    -- Global release — fires even when finger slides off the element
    local endConn
    endConn = UIS.InputEnded:Connect(function(i)
        if not alive() then endConn:Disconnect(); return end
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                -- Persist final drag position so minimize/restore respects it
                pcall(function()
                    local p = target.Position
                    Store.set("drag_pos:" .. tostring(target), {
                        xs = p.X.Scale, xo = p.X.Offset,
                        ys = p.Y.Scale, yo = p.Y.Offset,
                    })
                end)
            end
        end
    end)

    local _conn
    _conn = RunService.RenderStepped:Connect(function()
        if not alive() then _conn:Disconnect(); endConn:Disconnect(); return end
        if not dragging then return end
        local mp = UIS:GetMouseLocation()
        target.Position = UDim2.new(
            scaleX, startOffX + (mp.X - startMX),
            scaleY, startOffY + (mp.Y - startMY)
        )
    end)
end

-- Internal drag helper (handle ≠ target)
local function _drag(handle, target)
    _makeDraggable(handle, target)
end

-- Public UI.draggable (element is both handle and target)
function UI.draggable(element)
    _makeDraggable(element, element)
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  AmaterasuUI.Window  ·  Mobile-First Windowed GUI with Bottom Tab Navigation
-- ═══════════════════════════════════════════════════════════════════════════════

local Lib = {}


-- ── makeWindowOrb — unified helper used by all Amaterasu windows ───────────────
-- Shared between the main window, emote window, spectator window, etc.
-- bg: orb color | sym: symbol character | action: click handler
local function makeWindowOrb(parent, startPos, bg, sym, action, anchorPoint)
    local orb = UI.new("TextButton", parent, {
        Size             = UDim2.new(0, 14, 0, 14),
        Position         = startPos,
        AnchorPoint      = anchorPoint or Vector2.new(0, 0.5),
        BackgroundColor3 = bg,
        BackgroundTransparency = 0.18,
        Text             = "",
        ZIndex           = 11,
        AutoButtonColor  = false,
    })
    UI.corner(orb, 7)
    local symLbl = UI.new("TextLabel", orb, {
        Size             = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text             = sym,
        TextColor3       = Color3.new(0, 0, 0),
        Font             = Enum.Font.GothamBold,
        TextSize         = 8,
        TextTransparency = 1,
        ZIndex           = 12,
    })
    orb.MouseEnter:Connect(function()
        tween(orb,    { BackgroundTransparency = 0    }, 0.15, Enum.EasingStyle.Sine)
        tween(symLbl, { TextTransparency       = 0.15 }, 0.15, Enum.EasingStyle.Sine)
    end)
    orb.MouseLeave:Connect(function()
        tween(orb,    { BackgroundTransparency = 0.18 }, 0.18, Enum.EasingStyle.Sine)
        tween(symLbl, { TextTransparency       = 1    }, 0.18, Enum.EasingStyle.Sine)
    end)
    orb.MouseButton1Click:Connect(action)
    return orb, symLbl
end

function Lib.Window(sg, title, w, h)
    -- ── Universal device auto-scale ──────────────────────────────────────────
    -- Reference design: 390×844 (iPhone 14).  Scale proportionally on any device.
    -- Portrait phones get a narrower window; tablets/PC get the original size.
    local function computeWindowSize(baseW, baseH)
        local vp  = Camera.ViewportSize
        local vpW = vp.X
        local vpH = vp.Y
        -- Scale factor: clamp between 0.55 (tiny phone) and 1.15 (large monitor)
        local scaleX = math.clamp(vpW / 420, 0.55, 1.15)
        local scaleY = math.clamp(vpH / 844, 0.55, 1.10)
        local scale  = math.min(scaleX, scaleY)   -- uniform — keep aspect ratio
        -- On very small viewports (phones in portrait) cap width to 92% of screen
        local maxW   = vpW * 0.92
        local cw     = math.min(math.floor(baseW * scale), maxW)
        local ch     = math.floor(baseH * scale)
        return cw, ch
    end

    w = w or 390
    h = h or 320
    w, h = computeWindowSize(w, h)

    -- ── Layout constants ─────────────────────────────────────────────────────
    local TAB_BAR_H = 25          -- bottom tab bar height
    local TOP_BAR_H = 25          -- title bar height
    local WIN_RAD   = 14          -- window corner radius
    local MINI_W    = 165         -- compact pill width when header is minimized
    local OPEN_POS  = UDim2.new(0.50, 0, 0.50, 0)
    local CLOSE_POS = UDim2.new(-0.75, 0, 0.50, 0)

    local win = { _tabs = {}, _activeTab = nil, _open = false, _minimized = false }

    -- ── LAYER 0: soft drop shadow ─────────────────────────────────────────────
    local holder = UI.new("Frame", sg, {
        Size                   = UDim2.new(0, w, 0, h),
        Position               = CLOSE_POS,
        AnchorPoint            = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        ZIndex                 = 5,
        ClipsDescendants       = false,
    })
    win.holder = holder

    -- Black drop shadow (thin) — perfectly centered
    local dropShadow = UI.new("Frame", holder, {
        Size                   = UDim2.new(1, 28, 1, 28),
        Position               = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint            = Vector2.new(0.5, 0.5),
        BackgroundColor3       = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.56,
        ZIndex                 = 2,
    })
    UI.corner(dropShadow, WIN_RAD + 4)
    UI.gradient(dropShadow, 90, nil, NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.0),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1,   1.0),
    }))

    -- ── LAYER 1: accent outer glow (subtle) — perfectly centered
    local accentGlow = UI.new("Frame", holder, {
        Size                   = UDim2.new(1, 14, 1, 14),
        Position               = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint            = Vector2.new(0.5, 0.5),
        BackgroundColor3       = ACCENT,
        BackgroundTransparency = 0.82,
        ZIndex                 = 3,
    })
    UI.corner(accentGlow, WIN_RAD + 4)
    onAccent(function(c) if accentGlow.Parent then accentGlow.BackgroundColor3 = c end end)

    -- ── LAYER 2: animated spinning gradient ring ──────────────────────────────
    local spinRing = UI.new("Frame", holder, {
        Size                   = UDim2.new(1, 2, 1, 2),
        Position               = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint            = Vector2.new(0.5, 0.5),
        BackgroundColor3       = P.white,
        ZIndex                 = 4,
    })
    UI.corner(spinRing, WIN_RAD + 1)

    local spinGrad = UI.gradient(spinRing, 0,
        ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, ACCENT),
            ColorSequenceKeypoint.new(0.25, DARK),
            ColorSequenceKeypoint.new(0.75, DARK),
            ColorSequenceKeypoint.new(1.00, ACCENT),
        })
    )
    -- Unified border accent sync — replaces the identical onAccent block
    makeBorderGradAccent(spinGrad, DARK)
    -- Delegate to the single master Heartbeat loop — no per-window RenderStepped
    registerSpin(spinGrad, 60)

    -- ── LAYER 3: frosted glass body ───────────────────────────────────────────
    local body = UI.new("Frame", holder, {
        Size                   = UDim2.new(1, 0, 1, 0),
        Position               = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint            = Vector2.new(0.5, 0.5),
        BackgroundColor3       = P.bg,
        BackgroundTransparency = 0.06,
        ZIndex                 = 5,
        ClipsDescendants       = true,
        -- Active=true: Frame consumes all touches so none pass through to the game
        Active                 = true,
    })
    UI.corner(body, WIN_RAD)
    UI.stroke(body, P.white, 1.2, 0.88)
    win.body = body

    -- ─── TOUCH BLOCKER — invisible TextButton covers 100% of window ──────────
    -- TextButton inherently sinks mouse/touch input; nothing below (game world)
    -- receives the event. This is the most reliable no-passthrough technique.
    -- ZIndex=6 sits above the body base (5) so it catches taps on non-interactive
    -- content Frames. Interactive children (buttons, toggles) use ZIndex 8+ so
    -- they still receive input correctly on top of this blocker.
    UI.new("TextButton", body, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                   = "",
        ZIndex                 = 6,
        AutoButtonColor        = false,
        Active                 = true,
    })

    -- Top gloss shine
    local topGloss = UI.new("Frame", body, {
        Size                   = UDim2.new(1, 0, 0.18, 0),
        BackgroundColor3       = P.white,
        BackgroundTransparency = 0.93,
        ZIndex                 = 6,
        ClipsDescendants       = true,
    })
    UI.corner(topGloss, WIN_RAD)
    UI.gradient(topGloss, 90, nil, NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.0),
        NumberSequenceKeypoint.new(0.7, 0.6),
        NumberSequenceKeypoint.new(1,   1.0),
    }))

    -- ════════════════════════════════════════════════════════════════════════
    --  TOP BAR  (AmaterasuUI style: clean dark strip with title + orbs)
    -- ════════════════════════════════════════════════════════════════════════

    local topBar = UI.new("Frame", body, {
        Size             = UDim2.new(1, 0, 0, TOP_BAR_H + WIN_RAD),
        BackgroundColor3 = DARK,
        BackgroundTransparency = 0.22,
        ZIndex           = 8,
        -- Active=true: required for InputBegan to fire on a Frame (enables drag)
        Active           = true,
    })
    UI.corner(topBar, WIN_RAD)
    -- Accent left bar
    local topAccentBar = UI.new("Frame", topBar, {
        Size             = UDim2.new(0, 3, 0.6, 0),
        Position         = UDim2.new(0, 0, 0.2, 0),
        BackgroundColor3 = ACCENT,
        BorderSizePixel  = 0,
        ZIndex           = 9,
    })
    UI.corner(topAccentBar, 2)
    onAccent(function(c) if topAccentBar.Parent then topAccentBar.BackgroundColor3 = c end end)

    -- Top bar bottom separator
    UI.new("Frame", topBar, {
        Size             = UDim2.new(1, 0, 0, 1),
        Position         = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = P.white,
        BackgroundTransparency = 0.88,
        BorderSizePixel  = 0,
        ZIndex           = 9,
    })

    -- Title label (shifted right to leave room for avatar thumbnail)
    local titleLbl = UI.new("TextLabel", topBar, {
        Size             = UDim2.new(1, -110, 1, 0),
        Position         = UDim2.new(0, 52, 0, 0),
        BackgroundTransparency = 1,
        Text             = title,
        TextColor3       = P.textHi,
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        TextXAlignment   = Enum.TextXAlignment.Left,
        RichText         = true,
        ZIndex           = 10,
    })
    win._titleLbl = titleLbl

    -- ── Profile picture thumbnail ─────────────────────────────────────────
    -- Circular avatar headshot next to the title. Hidden when pill-minimized.
    local avatarSize = TOP_BAR_H - 6   -- fits neatly inside the bar (19px)
    local avatarImg = UI.new("ImageLabel", topBar, {
        Size             = UDim2.new(0, avatarSize, 0, avatarSize),
        Position         = UDim2.new(0, 18, 0.5, 0),
        AnchorPoint      = Vector2.new(0, 0.5),
        BackgroundColor3 = P.bg,
        BackgroundTransparency = 0.3,
        Image            = "",          -- filled async below
        ImageColor3      = Color3.new(1,1,1),
        ZIndex           = 11,
        ClipsDescendants = true,
    })
    UI.corner(avatarImg, avatarSize // 2)  -- full circle clip
    UI.stroke(avatarImg, ACCENT, 1.2, 0.4)
    onAccent(function(c)
        if avatarImg.Parent then
            for _, s in ipairs(avatarImg:GetChildren()) do
                if s:IsA("UIStroke") then s.Color = c end
            end
        end
    end)

    -- Load thumbnail asynchronously so it never blocks the UI build
    task.spawn(function()
        local ok, url = pcall(function()
            return Players:GetUserThumbnailAsync(
                Player.UserId,
                Enum.ThumbnailType.HeadShot,
                Enum.ThumbnailSize.Size48x48
            )
        end)
        if ok and url and avatarImg.Parent then
            avatarImg.Image = url
        end
    end)
    win._avatarImg = avatarImg   -- expose so minWin can hide/show it

    -- ── Window orbs ───────────────────────────────────────────────────────────
    -- Normal (expanded):  far-right  — classic macOS placement
    -- Minimized:          slides left to sit just after the title text
    -- These positions are tweened in minWin so the layout morphs on minimize.
    local ORB_EXPAND_MIN   = UDim2.new(1, -46, 0.5, 0)
    local ORB_EXPAND_CLOSE = UDim2.new(1, -26, 0.5, 0)
    local ORB_MINI_MIN     = UDim2.new(0, 100, 0.5, 0)
    local ORB_MINI_CLOSE   = UDim2.new(0, 120, 0.5, 0)


    local function makeOrb(startPos, bg, sym, action)
        return makeWindowOrb(topBar, startPos, bg, sym, action, Vector2.new(0, 0.5))
    end

    -- ── Close (red X) ─────────────────────────────────────────────────────────
    local function closeWin()
        if not win._open then return end
        win._open      = false
        win._minimized = false
        if win._tabBar      then win._tabBar.Visible      = true end
        if win._contentArea then win._contentArea.Visible = true end

        -- Slow dissolve-down: body fades while height collapses to zero
        tween(body,       { BackgroundTransparency = 1 }, 0.55, Enum.EasingStyle.Quint)
        tween(accentGlow, { BackgroundTransparency = 1 }, 0.40, Enum.EasingStyle.Sine)
        tween(spinRing,   { BackgroundTransparency = 1 }, 0.40, Enum.EasingStyle.Sine)
        tween(dropShadow, { BackgroundTransparency = 1 }, 0.35, Enum.EasingStyle.Sine)
        task.delay(0.10, function()
            if not holder.Parent then return end
            tween(holder, { Size = UDim2.new(0, w, 0, TOP_BAR_H + WIN_RAD) },
                  0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
        end)
        task.delay(0.70, function()
            if not holder.Parent then return end
            holder.Position               = CLOSE_POS
            holder.Size                   = UDim2.new(0, w, 0, h)
            body.BackgroundTransparency   = 0.06
            accentGlow.BackgroundTransparency = 0.82
            spinRing.BackgroundTransparency   = 0
            dropShadow.BackgroundTransparency = 0.56
        end)
    end

    -- ── Minimize (orange –) ───────────────────────────────────────────────────
    -- Orbs slide next to title when minimized, return far-right when restored.
    local orbMinBtn   -- forward ref, assigned after makeOrb calls below
    local orbCloseBtn

    local function minWin()
        win._minimized = not win._minimized
        if win._minimized then
            -- hide content first so it doesn't show during the squeeze
            if win._tabBar      then win._tabBar.Visible      = false end
            if win._contentArea then win._contentArea.Visible = false end
            -- slow smooth accordion collapse + header pill shrink
            tween(holder, { Size = UDim2.new(0, MINI_W, 0, TOP_BAR_H + WIN_RAD) },
                  0.65, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
            -- Move window to saved minimized position (H=0.64, V=0.23)
            tween(holder, { Position = UDim2.new(0.64, 0, 0.10, 0) },
                  0.65, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
            -- orbs glide left toward title
            tween(orbMinBtn,   { Position = ORB_MINI_MIN   }, 0.60, Enum.EasingStyle.Quint)
            tween(orbCloseBtn, { Position = ORB_MINI_CLOSE }, 0.60, Enum.EasingStyle.Quint)
            -- fade title slightly so pill looks clean
            tween(titleLbl, { TextTransparency = 0.55 }, 0.45, Enum.EasingStyle.Sine)
            -- hide avatar so it doesn't poke out of the narrow pill
            if win._avatarImg and win._avatarImg.Parent then
                tween(win._avatarImg, { ImageTransparency = 1, BackgroundTransparency = 1 }, 0.20, Enum.EasingStyle.Sine)
                task.delay(0.22, function() if win._avatarImg.Parent then win._avatarImg.Visible = false end end)
            end
        else
            if win._tabBar      then win._tabBar.Visible      = true end
            if win._contentArea then win._contentArea.Visible = true end
            -- restore title opacity first
            tween(titleLbl, { TextTransparency = 0 }, 0.30, Enum.EasingStyle.Sine)
            -- restore avatar
            if win._avatarImg and win._avatarImg.Parent then
                win._avatarImg.Visible          = true
                win._avatarImg.ImageTransparency = 1
                win._avatarImg.BackgroundTransparency = 0.3
                tween(win._avatarImg, { ImageTransparency = 0 }, 0.30, Enum.EasingStyle.Sine)
            end
            -- slow smooth expand back to full size
            tween(holder, { Size = UDim2.new(0, w, 0, h) },
                  0.75, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            -- Move window back to center when unminimized
            tween(holder, { Position = OPEN_POS },
                  0.75, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            -- orbs glide back far-right
            tween(orbMinBtn,   { Position = ORB_EXPAND_MIN   }, 0.60, Enum.EasingStyle.Quint)
            tween(orbCloseBtn, { Position = ORB_EXPAND_CLOSE }, 0.60, Enum.EasingStyle.Quint)
        end
    end

    orbMinBtn   = makeOrb(ORB_EXPAND_MIN,   Color3.fromRGB(255, 149,   0), "–", minWin)
    orbCloseBtn = makeOrb(ORB_EXPAND_CLOSE, Color3.fromRGB(255,  59,  48), "×", closeWin)

    -- Drag the whole window via the top bar
    _drag(topBar, holder)

    -- ════════════════════════════════════════════════════════════════════════
    --  BOTTOM TAB BAR  (iOS-style, mobile-first navigation)
    -- ════════════════════════════════════════════════════════════════════════

    local tabBar = UI.new("Frame", body, {
        Size             = UDim2.new(1, 0, 0, TAB_BAR_H + WIN_RAD),
        Position         = UDim2.new(0, 0, 1, -(TAB_BAR_H + WIN_RAD)),
        BackgroundColor3 = DARK,
        BackgroundTransparency = 0.10,
        ZIndex           = 8,
    })
    -- UICorner so bottom corners of tabBar match the window radius
    UI.corner(tabBar, WIN_RAD)
    -- Square filler that covers the rounded TOP corners of tabBar
    -- (only the bottom should be rounded — top edge is flat)
    UI.new("Frame", tabBar, {
        Size             = UDim2.new(1, 0, 0, WIN_RAD),
        Position         = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = DARK,
        BackgroundTransparency = 0.10,
        BorderSizePixel  = 0,
        ZIndex           = 8,
    })
    -- Tab bar top separator
    UI.new("Frame", tabBar, {
        Size             = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = P.white,
        BackgroundTransparency = 0.82,
        BorderSizePixel  = 0,
        ZIndex           = 9,
    })

    local tabButtonList = UI.new("Frame", tabBar, {
        Size             = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        ZIndex           = 9,
    })
    UI.new("UIListLayout", tabButtonList, {
        FillDirection       = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment   = Enum.VerticalAlignment.Center,
        Padding             = UDim.new(0, 0),
        SortOrder           = Enum.SortOrder.LayoutOrder,
    })
    win._tabBar = tabBar   -- expose so minWin can hide/show it
    -- tabBar is now created — wire drag so the whole window is draggable from it
    _drag(tabBar, holder)

    -- ════════════════════════════════════════════════════════════════════════
    --  CONTENT AREA  (sits between top bar and tab bar)
    -- ════════════════════════════════════════════════════════════════════════

    local contentArea = UI.new("Frame", body, {
        Size             = UDim2.new(1, 0, 1, -(TOP_BAR_H + TAB_BAR_H + WIN_RAD)),
        Position         = UDim2.new(0, 0, 0, TOP_BAR_H),
        BackgroundTransparency = 1,
        ZIndex           = 7,
        ClipsDescendants = true,
    })
    win._contentArea = contentArea   -- expose so minWin/Toggle can hide/show it

    -- ── Window API ────────────────────────────────────────────────────────────
    function win:Toggle()
        win._open = not win._open
        if win._open then
            -- ── OPEN: rises up from below, layers mist in one by one ─────────
            local wasMin  = win._minimized
            local targetW = wasMin and MINI_W or w
            local targetH = wasMin and (TOP_BAR_H + WIN_RAD) or h
            if win._tabBar      then win._tabBar.Visible      = not wasMin end
            if win._contentArea then win._contentArea.Visible = not wasMin end

            -- Restore orb positions to match the minimized / expanded state
            if wasMin then
                orbMinBtn.Position   = ORB_MINI_MIN
                orbCloseBtn.Position = ORB_MINI_CLOSE
                titleLbl.TextTransparency = 0.55
            else
                orbMinBtn.Position   = ORB_EXPAND_MIN
                orbCloseBtn.Position = ORB_EXPAND_CLOSE
                titleLbl.TextTransparency = 0
            end

            -- Start: correct target width, height=0, shifted 50px below resting position
            holder.Size     = UDim2.new(0, targetW, 0, 0)
            holder.Position = UDim2.new(
                OPEN_POS.X.Scale, OPEN_POS.X.Offset,
                OPEN_POS.Y.Scale, OPEN_POS.Y.Offset + 50
            )
            body.BackgroundTransparency       = 1
            accentGlow.BackgroundTransparency = 1
            spinRing.BackgroundTransparency   = 1
            dropShadow.BackgroundTransparency = 1

            -- Rise into place while the height unfurls
            tween(holder, { Size     = UDim2.new(0, targetW, 0, targetH),
                            Position = OPEN_POS },
                  0.85, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            -- Staggered layer reveal: shadow → glow → ring → body
            task.delay(0.08, function() tween(dropShadow,{ BackgroundTransparency=0.56 }, 0.55, Enum.EasingStyle.Sine) end)
            task.delay(0.20, function() tween(accentGlow, { BackgroundTransparency=0.82 }, 0.55, Enum.EasingStyle.Sine) end)
            task.delay(0.32, function() tween(spinRing,   { BackgroundTransparency=0    }, 0.55, Enum.EasingStyle.Sine) end)
            task.delay(0.44, function() tween(body,       { BackgroundTransparency=0.06 }, 0.55, Enum.EasingStyle.Sine) end)
        else
            -- ── CLOSE: layers evaporate, window drifts up and collapses ──────
            local savedMin = win._minimized

            -- Dissolve layers outward first
            tween(body,       { BackgroundTransparency = 1 }, 0.45, Enum.EasingStyle.Sine)
            tween(accentGlow, { BackgroundTransparency = 1 }, 0.35, Enum.EasingStyle.Sine)
            tween(spinRing,   { BackgroundTransparency = 1 }, 0.35, Enum.EasingStyle.Sine)
            tween(dropShadow, { BackgroundTransparency = 1 }, 0.30, Enum.EasingStyle.Sine)
            -- After brief delay: drift upward while collapsing height to zero
            task.delay(0.15, function()
                if not holder.Parent then return end
                local curW = savedMin and MINI_W or w
                tween(holder, {
                    Size     = UDim2.new(0, curW, 0, 0),
                    Position = UDim2.new(
                        holder.Position.X.Scale, holder.Position.X.Offset,
                        holder.Position.Y.Scale, holder.Position.Y.Offset - 40
                    ),
                }, 0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
            end)
            task.delay(0.75, function()
                if not holder.Parent then return end
                holder.Position               = CLOSE_POS
                holder.Size                   = UDim2.new(0, w, 0, h)
                body.BackgroundTransparency   = 0.06
                accentGlow.BackgroundTransparency = 0.82
                spinRing.BackgroundTransparency   = 0
                dropShadow.BackgroundTransparency = 0.56
                if win._tabBar      then win._tabBar.Visible      = not savedMin end
                if win._contentArea then win._contentArea.Visible = not savedMin end
            end)
        end
    end
    function win:SetTitle(t) if titleLbl.Parent then titleLbl.Text = t end end

    -- Smart helpers ──────────────────────────────────────────────────────────
    -- Retrieve a tab object by its label text (case-insensitive).
    -- Useful for scripted navigation: win:GetTab("Settings"):Select()
    function win:GetTab(label)
        local lc = label:lower()
        for _, t in ipairs(win._tabs) do
            if t._btnLbl and t._btnLbl.Text:lower() == lc then return t end
        end
        return nil
    end

    -- Returns the currently visible tab object.
    function win:GetActiveTab()
        return win._activeTab
    end

    -- ════════════════════════════════════════════════════════════════════════
    --  AddTab
    -- ════════════════════════════════════════════════════════════════════════
    function win:AddTab(label)
        local tab     = { _columns = {} }
        local isFirst = (#win._tabs == 0)
        local tabIdx  = #win._tabs + 1
        tab._idx = tabIdx   -- stored so selectTab can compare direction

        -- ── Tab button in bottom bar ─────────────────────────────────────────
        local tBtn = UI.new("TextButton", tabButtonList, {
            BackgroundTransparency = 1,
            Text             = "",
            ZIndex           = 10,
            AutoButtonColor  = false,
            LayoutOrder      = tabIdx,
        })

        -- Active indicator pill
        local indicPill = UI.new("Frame", tBtn, {
            Size             = UDim2.new(0.55, 0, 0, 3),
            Position         = UDim2.new(0.225, 0, 0, 3),
            BackgroundColor3 = ACCENT,
            BackgroundTransparency = isFirst and 0 or 1,
            BorderSizePixel  = 0,
            ZIndex           = 11,
        })
        UI.corner(indicPill, 2)
        onAccent(function(c)
            if indicPill.Parent and win._activeTab == tab then
                indicPill.BackgroundColor3 = c
            end
        end)

        local tLbl = UI.new("TextLabel", tBtn, {
            Size             = UDim2.new(1, 0, 1, -8),
            Position         = UDim2.new(0, 0, 0, 6),
            BackgroundTransparency = 1,
            Text             = label,
            TextColor3       = isFirst and P.textHi or P.textLo,
            Font             = isFirst and Enum.Font.GothamBold or Enum.Font.GothamMedium,
            TextSize         = 9,
            ZIndex           = 11,
            RichText         = true,
        })
        tab._btnLbl = tLbl

        -- ── Page (full-size frame inside contentArea) ─────────────────────────
        local page = UI.new("Frame", contentArea, {
            Size                   = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            ZIndex                 = 7,
            Visible                = isFirst,
        })
        tab._frame  = page
        tab._btn    = tBtn

        -- Tab button sizing (rebalanced every time a tab is added)
        local function rebalanceTabs()
            local n = #win._tabs
            for _, t in ipairs(win._tabs) do
                if t._btn then
                    t._btn.Size = UDim2.new(1 / n, 0, 1, 0)
                end
            end
        end

        -- Column holder (AmaterasuUI uses a single full-width scrolling column per tab)
        local colCont = UI.new("Frame", page, {
            Size                   = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            ZIndex                 = 7,
        })
        UI.new("UIListLayout", colCont, {
            FillDirection       = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            VerticalAlignment   = Enum.VerticalAlignment.Top,
            Padding             = UDim.new(0, 0),
            SortOrder           = Enum.SortOrder.LayoutOrder,
        })
        tab._colCont = colCont

        -- ── Tab selection — direction-aware page slide ──────────────────────────
        local function selectTab()
            if win._activeTab == tab then return end
            -- Guard: ignore rapid taps while a transition is already in progress
            if win._switching then return end
            win._switching = true
            task.delay(0.36, function() win._switching = false end)

            -- ── Lazy build: run deferred content builder on first open ──────────
            if tab._lazyBuild and not tab._built then
                tab._built = true
                task.spawn(function() pcall(tab._lazyBuild) end)
            end

            local prev = win._activeTab

            -- Determine slide direction by comparing tab indices.
            -- Going right (higher index) → old exits left, new enters from right.
            -- Going left  (lower index)  → old exits right, new enters from left.
            local prevIdx   = prev and prev._idx or 0
            local goingRight = (tab._idx > prevIdx)
            local outX  =  goingRight and -1 or  1   -- outgoing direction
            local inX   =  goingRight and  1 or -1   -- incoming direction

            if prev then
                -- Outgoing page glides away — Quart gives a smooth iOS-like deceleration
                prev._frame.Position = UDim2.new(0, 0, 0, 0)
                tween(prev._frame, { Position = UDim2.new(outX, 0, 0, 0) },
                      0.32, Enum.EasingStyle.Quart)
                task.delay(0.33, function()
                    if prev._frame.Parent then
                        prev._frame.Visible  = false
                        prev._frame.Position = UDim2.new(0, 0, 0, 0)
                    end
                end)
                -- Deactivate previous tab button
                tween(prev._btnLbl, { TextColor3 = P.textLo }, 0.22, Enum.EasingStyle.Sine)
                if prev._indicPill then
                    tween(prev._indicPill,
                        { BackgroundTransparency = 1, Size = UDim2.new(0.15, 0, 0, 2) },
                        0.22, Enum.EasingStyle.Quart)
                end
                prev._btnLbl.Font = Enum.Font.GothamMedium
            end

            win._activeTab = tab

            -- Incoming page glides in from correct side — same Quart timing
            page.Position = UDim2.new(inX, 0, 0, 0)
            page.Visible  = true
            tween(page, { Position = UDim2.new(0, 0, 0, 0) },
                  0.32, Enum.EasingStyle.Quart)

            -- Activate new tab: pill springs in from a tiny seed
            tween(tLbl, { TextColor3 = P.textHi }, 0.22, Enum.EasingStyle.Sine)
            indicPill.Size             = UDim2.new(0.15, 0, 0, 2)
            indicPill.BackgroundTransparency = 0.5
            indicPill.BackgroundColor3 = ACCENT
            tween(indicPill,
                { BackgroundTransparency = 0, Size = UDim2.new(0.55, 0, 0, 3) },
                0.50, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            tLbl.Font = Enum.Font.GothamBold
        end

        tab._indicPill  = indicPill
        tab._built      = true    -- default: eager (no lazy build)
        tab._lazyBuild  = nil     -- set via tab:LazyBuild(fn) to enable deferred mode
        tab.Select      = selectTab

        --- Defer content construction until the tab is first opened.
        --- Pass a function that builds all AddSection/AddButton/etc calls.
        --- This improves startup time for tabs with heavy content.
        function tab:LazyBuild(fn)
            tab._lazyBuild = fn
            tab._built     = false   -- mark unbuilt so selectTab fires fn
        end
        tBtn.MouseButton1Click:Connect(selectTab)
        -- Public: programmatic tab switching (e.g. win:GetTab("Main"):Select())
        tab.Select = selectTab
        tBtn.MouseEnter:Connect(function()
            if win._activeTab ~= tab then
                tween(tLbl, { TextColor3 = P.textHi }, 0.30, Enum.EasingStyle.Sine)
            end
        end)
        tBtn.MouseLeave:Connect(function()
            if win._activeTab ~= tab then
                tween(tLbl, { TextColor3 = P.textLo }, 0.36, Enum.EasingStyle.Sine)
            end
        end)

        if isFirst then win._activeTab = tab end
        win._tabs[#win._tabs + 1] = tab
        rebalanceTabs()

        -- ════════════════════════════════════════════════════════════════════
        --  AddColumn  (AmaterasuUI: mobile single-column; divides width for N cols)
        -- ════════════════════════════════════════════════════════════════════
        function tab:AddColumn()
            local nc  = #tab._columns + 1
            local col = { _sections = {} }

            local colFr = UI.new("ScrollingFrame", colCont, {
                Size                      = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency    = 1,
                BorderSizePixel           = 0,
                ZIndex                    = 8,
                ScrollBarThickness        = 3,
                ScrollBarImageColor3      = ACCENT,
                ScrollBarImageTransparency = 0.38,
                AutomaticCanvasSize       = Enum.AutomaticSize.Y,
                CanvasSize                = UDim2.new(0, 0, 0, 0),
                LayoutOrder               = nc,
            })
            onAccent(function(c)
                if colFr.Parent then colFr.ScrollBarImageColor3 = c end
            end)
            UI.new("UIListLayout", colFr, {
                FillDirection       = Enum.FillDirection.Vertical,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                VerticalAlignment   = Enum.VerticalAlignment.Top,
                Padding             = UDim.new(0, 6),
                SortOrder           = Enum.SortOrder.LayoutOrder,
            })
            UI.new("UIPadding", colFr, {
                PaddingLeft   = UDim.new(0, 4),
                PaddingRight  = UDim.new(0, 4),
                PaddingTop    = UDim.new(0, 23),
                PaddingBottom = UDim.new(0, 6),
            })
            col._frame = colFr
            tab._columns[nc] = col

            -- Rebalance column widths equally
            local function rebalanceCols()
                local n = #tab._columns
                for _, c in ipairs(tab._columns) do
                    c._frame.Size = n == 1
                        and UDim2.new(1, 0, 1, 0)
                        or  UDim2.new(1 / n, 0, 1, 0)
                end
            end
            rebalanceCols()

            -- ════════════════════════════════════════════════════════════════
            --  AddSection
            -- ════════════════════════════════════════════════════════════════
            function col:AddSection(secTitle)
                local sec  = { _collapsed = false }
                local secN = #col._sections + 1

                -- Section card (frosted glass, rounded)
                local card = UI.new("Frame", colFr, {
                    Size             = UDim2.new(1, 0, 0, 0),
                    AutomaticSize    = Enum.AutomaticSize.Y,
                    BackgroundColor3 = CARD,
                    BackgroundTransparency = 0.12,
                    ZIndex           = 9,
                    LayoutOrder      = secN,
                    ClipsDescendants = true,   -- clips content during collapse anim
                })
                UI.corner(card, 12)
                UI.stroke(card, P.white, 1, 0.94)

                local elY = 2

                -- ── Section header (if title provided) ────────────────────
                local arrowRef = nil
                local hSepRef  = nil
                if secTitle and secTitle ~= "" then
                    local hdr = UI.new("Frame", card, {
                        Size             = UDim2.new(1, 0, 0, 28),
                        BackgroundTransparency = 1,
                        ZIndex           = 10,
                        ClipsDescendants = false,
                    })
                    -- Accent left border stripe on header
                    local hStripe = UI.new("Frame", hdr, {
                        Size             = UDim2.new(0, 3, 0.65, 0),
                        Position         = UDim2.new(0, 0, 0.175, 0),
                        BackgroundColor3 = ACCENT,
                        BorderSizePixel  = 0,
                        ZIndex           = 11,
                    })
                    UI.corner(hStripe, 2)
                    onAccent(function(c)
                        if hStripe.Parent then hStripe.BackgroundColor3 = c end
                    end)

                    -- Header title
                    UI.new("TextLabel", hdr, {
                        Size             = UDim2.new(1, -36, 1, 0),
                        Position         = UDim2.new(0, 14, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = secTitle,
                        TextColor3       = P.textHi,
                        Font             = Enum.Font.GothamBold,
                        TextSize         = 10,
                        TextXAlignment   = Enum.TextXAlignment.Left,
                        ZIndex           = 11,
                    })

                    -- Separator under header — hidden when collapsed
                    hSepRef = UI.new("Frame", card, {
                        Size             = UDim2.new(1, -16, 0, 1),
                        Position         = UDim2.new(0, 8, 0, 28),
                        BackgroundColor3 = ACCENT,
                        BackgroundTransparency = 0.72,
                        BorderSizePixel  = 0,
                        ZIndex           = 10,
                    })
                    onAccent(function(c)
                        if hSepRef.Parent then hSepRef.BackgroundColor3 = c end
                    end)

                    -- Collapse arrow
                    arrowRef = UI.new("TextLabel", hdr, {
                        Size             = UDim2.new(0, 22, 1, 0),
                        Position         = UDim2.new(1, -26, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = "v",
                        TextColor3       = P.textLo,
                        Font             = Enum.Font.GothamBold,
                        TextSize         = 11,
                        TextTransparency = 0.45,
                        ZIndex           = 11,
                    })

                    -- Click region for collapsing
                    local hBtn = UI.new("TextButton", hdr, {
                        Size             = UDim2.new(1, 0, 1, 0),
                        BackgroundTransparency = 1,
                        Text             = "",
                        ZIndex           = 13,
                        AutoButtonColor  = false,
                    })
                    hBtn.MouseEnter:Connect(function()
                        tween(hdr,      { BackgroundTransparency = 0.90 }, 0.15, Enum.EasingStyle.Sine)
                        tween(arrowRef, { TextTransparency = 0 }, 0.15, Enum.EasingStyle.Sine)
                    end)
                    hBtn.MouseLeave:Connect(function()
                        tween(hdr,      { BackgroundTransparency = 1 }, 0.20, Enum.EasingStyle.Sine)
                        tween(arrowRef, { TextTransparency = 0.45 }, 0.20, Enum.EasingStyle.Sine)
                    end)
                    hBtn.MouseButton1Click:Connect(function()
                        if sec._doToggle then sec._doToggle() end
                    end)

                    elY = 32   -- 28px header + 1px sep + 3px gap
                end

                -- Animated clip wrapper — height tweens for smooth collapse
                local clipWrapper = UI.new("Frame", card, {
                    Size             = UDim2.new(1, 0, 0, 0),  -- will auto-grow
                    AutomaticSize    = Enum.AutomaticSize.Y,
                    Position         = UDim2.new(0, 0, 0, elY),
                    BackgroundTransparency = 1,
                    ZIndex           = 10,
                    ClipsDescendants = false,
                })

                -- Elements list container
                local elList = UI.new("Frame", clipWrapper, {
                    Size             = UDim2.new(1, 0, 0, 0),
                    AutomaticSize    = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    ZIndex           = 10,
                })
                UI.new("UIListLayout", elList, {
                    FillDirection       = Enum.FillDirection.Vertical,
                    HorizontalAlignment = Enum.HorizontalAlignment.Center,
                    VerticalAlignment   = Enum.VerticalAlignment.Top,
                    Padding             = UDim.new(0, 0),
                    SortOrder           = Enum.SortOrder.LayoutOrder,
                })
                UI.new("UIPadding", elList, {
                    PaddingLeft   = UDim.new(0, 6),
                    PaddingRight  = UDim.new(0, 6),
                    PaddingTop    = UDim.new(0, 2),
                    PaddingBottom = UDim.new(0, 6),
                })
                sec._list = elList

                -- Smooth animated collapse / expand
                sec._doToggle = function()
                    sec._collapsed = not sec._collapsed
                    if arrowRef then
                        tween(arrowRef, {
                            Rotation         = sec._collapsed and -90 or 0,
                            TextTransparency = sec._collapsed and 0.10 or 0.45,
                        }, 0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
                    end

                    if sec._collapsed then
                        local contentH = elList.AbsoluteSize.Y
                        card.AutomaticSize    = Enum.AutomaticSize.None
                        card.ClipsDescendants = true
                        local headerH = elY
                        card.Size = UDim2.new(1, 0, 0, headerH + contentH)
                        tween(card, { Size = UDim2.new(1, 0, 0, headerH) }, 0.46, Enum.EasingStyle.Quint)
                        if hSepRef then
                            tween(hSepRef, { BackgroundTransparency = 1 }, 0.26, Enum.EasingStyle.Sine)
                        end
                        task.delay(0.48, function()
                            if card.Parent then
                                elList.Visible = false
                                if clipWrapper.Parent then clipWrapper.Visible = false end
                            end
                        end)
                    else
                        elList.Visible = true
                        if clipWrapper.Parent then clipWrapper.Visible = true end
                        card.ClipsDescendants = true
                        card.AutomaticSize = Enum.AutomaticSize.None
                        local headerH  = elY
                        local contentH = elList.AbsoluteSize.Y
                        if contentH < 10 then contentH = 120 end
                        card.Size = UDim2.new(1, 0, 0, headerH)
                        tween(card, { Size = UDim2.new(1, 0, 0, headerH + contentH) }, 0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
                        if hSepRef then
                            tween(hSepRef, { BackgroundTransparency = 0.72 }, 0.32, Enum.EasingStyle.Sine)
                        end
                        task.delay(0.58, function()
                            if card.Parent then
                                card.AutomaticSize    = Enum.AutomaticSize.Y
                                card.ClipsDescendants = false
                            end
                        end)
                    end
                end

                col._sections[secN] = sec

                local elemN = 0
                local function eo() elemN = elemN + 1; return elemN end

                -- ════════════════════════════════════════════════════════
                --  TOGGLE  (AmaterasuUI style: large pill, bounce spring, glow)
                -- ════════════════════════════════════════════════════════
                function sec:AddToggle(label, default, callback)
                    local tog = { _val = default }
                    -- Mobile-first: 40px touch target
                    local row = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 40),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })

                    local lbl = UI.new("TextLabel", row, {
                        Size             = UDim2.new(1, -68, 1, 0),
                        Position         = UDim2.new(0, 6, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = label,
                        TextColor3       = default and P.textHi or P.textLo,
                        Font             = Enum.Font.GothamMedium,
                        TextSize         = 11,
                        TextXAlignment   = Enum.TextXAlignment.Left,
                        ZIndex           = 12,
                    })

                    -- AmaterasuUI pill: compact for mobile
                    local PW, PH = 44, 24
                    local KS     = 18   -- knob size
                    local KP     = 3    -- knob padding
                    local K_OFF  = KP
                    local K_ON   = PW - KP - KS
                    local OFF_C  = Color3.fromRGB(24, 28, 46)

                    local pill = UI.new("Frame", row, {
                        Size             = UDim2.new(0, PW, 0, PH),
                        Position         = UDim2.new(1, -(PW + 8), 0.5, 0),
                        AnchorPoint      = Vector2.new(0, 0.5),
                        BackgroundColor3 = default and ACCENT or OFF_C,
                        BackgroundTransparency = default and 0.04 or 0.18,
                        ZIndex           = 12,
                    })
                    UI.corner(pill, PH / 2)

                    -- Glow ring (visible when ON) — perfectly centered
                    local pillGlow = UI.new("Frame", pill, {
                        Size             = UDim2.new(1, 18, 1, 18),
                        Position         = UDim2.new(0.5, 0, 0.5, 0),
                        AnchorPoint      = Vector2.new(0.5, 0.5),
                        BackgroundColor3 = ACCENT,
                        BackgroundTransparency = default and 0.40 or 1,
                        ZIndex           = 11,
                    })
                    UI.corner(pillGlow, PH / 2 + 9)
                    onAccent(function(c)
                        if pillGlow.Parent then pillGlow.BackgroundColor3 = c end
                    end)

                    -- Knob (white circle with shadow)
                    local knob = UI.new("Frame", pill, {
                        Size             = UDim2.new(0, KS, 0, KS),
                        Position         = UDim2.new(0, default and K_ON or K_OFF, 0.5, 0),
                        AnchorPoint      = Vector2.new(0, 0.5),
                        BackgroundColor3 = P.white,
                        ZIndex           = 14,
                    })
                    UI.corner(knob, KS / 2)
                    -- Knob drop-shadow — kept deliberately thin/subtle
                    local knobShadow = UI.new("Frame", knob, {
                        Size             = UDim2.new(1, 4, 1, 4),
                        Position         = UDim2.new(0.5, 0, 0.5, 1),
                        AnchorPoint      = Vector2.new(0.5, 0.5),
                        BackgroundColor3 = Color3.new(0, 0, 0),
                        BackgroundTransparency = 0.88,
                        ZIndex           = 13,
                    })
                    UI.corner(knobShadow, (KS + 4) / 2)

                    -- Invisible hit zone (full row width for easy mobile tap)
                    local hit = UI.new("TextButton", row, {
                        Size             = UDim2.new(1, 0, 1, 0),
                        BackgroundTransparency = 1,
                        Text             = "",
                        ZIndex           = 15,
                        AutoButtonColor  = false,
                    })
                    -- Ripple from the pill region for tactile feedback
                    UI.ripple(hit, ACCENT)

                    -- Live-sync pill to accent whenever theme changes
                    onAccent(function(c)
                        if not pill.Parent then return end
                        if tog._val then
                            pill.BackgroundColor3 = c
                        end
                    end)

                    local function applyVis(v)
                        tog._val = v
                        -- Squeeze pill on transition then spring back for tactile feel
                        if v then
                            tween(knob, { Size = UDim2.new(0, KS * 1.28, 0, KS * 0.80) }, 0.10, Enum.EasingStyle.Sine)
                            task.delay(0.10, function()
                                if knob.Parent then
                                    tween(knob, {
                                        Size     = UDim2.new(0, KS, 0, KS),
                                        Position = UDim2.new(0, K_ON, 0.5, 0),
                                    }, 0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
                                end
                            end)
                        else
                            tween(knob, { Size = UDim2.new(0, KS * 1.28, 0, KS * 0.80) }, 0.10, Enum.EasingStyle.Sine)
                            task.delay(0.10, function()
                                if knob.Parent then
                                    tween(knob, {
                                        Size     = UDim2.new(0, KS, 0, KS),
                                        Position = UDim2.new(0, K_OFF, 0.5, 0),
                                    }, 0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
                                end
                            end)
                        end
                        tween(pill, {
                            BackgroundColor3       = v and ACCENT or OFF_C,
                            BackgroundTransparency = v and 0.04 or 0.18,
                        }, 0.30, Enum.EasingStyle.Quint)
                        tween(pillGlow, {
                            BackgroundTransparency = v and 0.40 or 1,
                        }, 0.30, Enum.EasingStyle.Quint)
                        tween(lbl, { TextColor3 = v and P.textHi or P.textLo }, 0.22, Enum.EasingStyle.Sine)
                    end

                    hit.MouseEnter:Connect(function()
                        tween(pill, { BackgroundTransparency = tog._val and 0 or 0.08 }, 0.18, Enum.EasingStyle.Sine)
                    end)
                    hit.MouseLeave:Connect(function()
                        tween(pill, { BackgroundTransparency = tog._val and 0.04 or 0.18 }, 0.18, Enum.EasingStyle.Sine)
                    end)
                    hit.MouseButton1Down:Connect(function()
                        tween(pill, { Size = UDim2.new(0, PW * 0.92, 0, PH * 0.88) }, 0.09, Enum.EasingStyle.Sine)
                    end)
                    hit.MouseButton1Click:Connect(function()
                        if tog._busy then return end
                        tog._busy = true
                        task.delay(0.55, function() tog._busy = false end)
                        tween(pill, { Size = UDim2.new(0, PW, 0, PH) }, 0.26,
                              Enum.EasingStyle.Back, Enum.EasingDirection.Out)
                        tog._val = not tog._val
                        applyVis(tog._val)
                        if callback then callback(tog._val) end
                    end)

                    function tog:Set(v, silent)
                        tog._val = v; applyVis(v)
                        if callback and not silent then callback(v) end
                    end
                    function tog:Get() return tog._val end
                    return tog
                end

                -- ════════════════════════════════════════════════════════
                --  BUTTON  (full-width, accent sweep, bounce press)
                -- ════════════════════════════════════════════════════════
                function sec:AddButton(label, callback)
                    local bObj   = {}
                    local BTN_BG = Color3.fromRGB(16, 20, 34)
                    local row    = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 34),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })
                    local btn = UI.new("TextButton", row, {
                        Size             = UDim2.new(1, 0, 1, -4),
                        Position         = UDim2.new(0, 0, 0, 2),
                        BackgroundColor3 = BTN_BG,
                        BackgroundTransparency = 0.16,
                        Text             = label,
                        TextColor3       = P.textHi,
                        Font             = Enum.Font.GothamMedium,
                        TextSize         = 11,
                        ZIndex           = 12,
                        AutoButtonColor  = false,
                        ClipsDescendants = true,
                    })
                    UI.corner(btn, 9)
                    local bSt = UI.stroke(btn, P.white, 1, 0.88)
                    -- Ripple on every button click
                    UI.ripple(btn, P.white)
                    local sweep = UI.new("Frame", btn, {
                        Size             = UDim2.new(0, 0, 1, 0),
                        BackgroundColor3 = ACCENT,
                        BackgroundTransparency = 0.76,
                        BorderSizePixel  = 0,
                        ZIndex           = 11,
                    })
                    UI.corner(sweep, 9)
                    onAccent(function(c) if sweep.Parent then sweep.BackgroundColor3 = c end end)

                    btn.MouseEnter:Connect(function()
                        tween(btn,   { BackgroundTransparency = 0.04 }, 0.20, Enum.EasingStyle.Sine)
                        tween(bSt,   { Color = ACCENT, Transparency = 0.38 }, 0.20, Enum.EasingStyle.Sine)
                        tween(sweep, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 0.82 }, 0.30, Enum.EasingStyle.Quart)
                    end)
                    btn.MouseLeave:Connect(function()
                        tween(btn,   { BackgroundTransparency = 0.16 }, 0.22, Enum.EasingStyle.Sine)
                        tween(bSt,   { Color = P.white, Transparency = 0.88 }, 0.22, Enum.EasingStyle.Sine)
                        tween(sweep, { Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 0.76 }, 0.26, Enum.EasingStyle.Quart)
                    end)
                    btn.MouseButton1Down:Connect(function()
                        tween(btn, { BackgroundTransparency = 0, BackgroundColor3 = ACCENT }, 0.08, Enum.EasingStyle.Sine)
                    end)
                    btn.MouseButton1Up:Connect(function()
                        tween(btn, { BackgroundTransparency = 0.16, BackgroundColor3 = BTN_BG }, 0.18, Enum.EasingStyle.Quint)
                    end)
                    -- Fire only on a completed click (down+up on same element), with debounce
                    -- to prevent rapid double-fires from button mashing.
                    local _btnCooldown = false
                    btn.MouseButton1Click:Connect(function()
                        if _btnCooldown then return end
                        _btnCooldown = true
                        task.delay(0.35, function() _btnCooldown = false end)
                        if callback then task.spawn(callback) end
                    end)

                    function bObj:SetText(t)  if btn.Parent then btn.Text = t end end
                    function bObj:SetEnabled(v)
                        if not btn.Parent then return end
                        btn.Active = v
                        tween(btn, { BackgroundTransparency = v and 0.16 or 0.52 }, 0.14)
                        tween(btn, { TextColor3 = v and P.textHi or P.textLo }, 0.14)
                    end
                    bObj._btn = btn
                    return bObj
                end

                -- ════════════════════════════════════════════════════════
                --  CYCLE  (AmaterasuUI: larger, accent-colored arrows)
                -- ════════════════════════════════════════════════════════
                function sec:AddCycle(label, options, defIdx, callback)
                    local cyc = { _idx = defIdx or 1 }
                    local row = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 34),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })
                    UI.new("TextLabel", row, {
                        Size             = UDim2.new(0.45, 0, 1, 0),
                        Position         = UDim2.new(0, 6, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = label,
                        TextColor3       = P.textLo,
                        Font             = Enum.Font.GothamMedium,
                        TextSize         = 11,
                        TextXAlignment   = Enum.TextXAlignment.Left,
                        ZIndex           = 12,
                    })

                    local PILL_W = 110
                    local pill = UI.new("Frame", row, {
                        Size             = UDim2.new(0, PILL_W, 0, 22),
                        Position         = UDim2.new(1, -(PILL_W + 4), 0.5, 0),
                        AnchorPoint      = Vector2.new(0, 0.5),
                        BackgroundColor3 = Color3.fromRGB(14, 18, 30),
                        BackgroundTransparency = 0.16,
                        ZIndex           = 12,
                    })
                    UI.corner(pill, 14)
                    UI.stroke(pill, P.white, 1, 0.88)

                    local lArrow = UI.new("TextButton", pill, {
                        Size             = UDim2.new(0, 30, 1, 0),
                        BackgroundTransparency = 1,
                        Text             = "‹",
                        TextColor3       = P.textLo,
                        Font             = Enum.Font.GothamBold,
                        TextSize         = 16,
                        ZIndex           = 13,
                        AutoButtonColor  = false,
                    })
                    local valLbl = UI.new("TextLabel", pill, {
                        Size             = UDim2.new(1, -60, 1, 0),
                        Position         = UDim2.new(0, 30, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = tostring(options[cyc._idx]),
                        TextColor3       = P.textHi,
                        Font             = Enum.Font.GothamBold,
                        TextSize         = 10,
                        ZIndex           = 13,
                    })
                    local rArrow = UI.new("TextButton", pill, {
                        Size             = UDim2.new(0, 30, 1, 0),
                        Position         = UDim2.new(1, -30, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = "›",
                        TextColor3       = P.textLo,
                        Font             = Enum.Font.GothamBold,
                        TextSize         = 16,
                        ZIndex           = 13,
                        AutoButtonColor  = false,
                    })

                    local function step(d)
                        cyc._idx = ((cyc._idx - 1 + d) % #options) + 1
                        tween(valLbl, { TextTransparency = 1 }, 0.06)
                        task.delay(0.07, function()
                            if valLbl.Parent then
                                valLbl.Text = tostring(options[cyc._idx])
                                tween(valLbl, { TextTransparency = 0 }, 0.10)
                            end
                        end)
                        if callback then callback(cyc._idx) end
                    end

                    lArrow.MouseButton1Click:Connect(function() step(-1) end)
                    rArrow.MouseButton1Click:Connect(function() step(1)  end)
                    for _, ab in ipairs({ lArrow, rArrow }) do
                        ab.MouseEnter:Connect(function()
                            tween(ab, { TextColor3 = ACCENT }, 0.12)
                        end)
                        ab.MouseLeave:Connect(function()
                            tween(ab, { TextColor3 = P.textLo }, 0.12)
                        end)
                    end

                    function cyc:Get() return cyc._idx end
                    return cyc
                end

                -- ════════════════════════════════════════════════════════
                --  SLIDER  (AmaterasuUI: 22px thumb, accent fill, mobile drag)
                -- ════════════════════════════════════════════════════════
                function sec:AddSlider(label, minV, maxV, defV, callback)
                    defV = math.clamp(defV or minV, minV, maxV)
                    local slid  = { _val = defV }
                    local TRH   = 4
                    local TSIZE = 18

                    local row = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 48),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })

                    -- Label
                    UI.new("TextLabel", row, {
                        Size             = UDim2.new(0.62, 0, 0, 20),
                        Position         = UDim2.new(0, 6, 0, 2),
                        BackgroundTransparency = 1,
                        Text             = label,
                        TextColor3       = P.textLo,
                        Font             = Enum.Font.GothamMedium,
                        TextSize         = 11,
                        TextXAlignment   = Enum.TextXAlignment.Left,
                        ZIndex           = 12,
                    })

                    -- Value badge
                    local badge = UI.new("Frame", row, {
                        Size             = UDim2.new(0, 48, 0, 20),
                        Position         = UDim2.new(1, -4, 0, 2),
                        AnchorPoint      = Vector2.new(1, 0),
                        BackgroundColor3 = ACCENT,
                        BackgroundTransparency = 0.72,
                        ZIndex           = 12,
                    })
                    UI.corner(badge, 10)
                    onAccent(function(c) if badge.Parent then badge.BackgroundColor3 = c end end)
                    local badgeLbl = UI.new("TextLabel", badge, {
                        Size             = UDim2.new(1, 0, 1, 0),
                        BackgroundTransparency = 1,
                        Text             = tostring(defV),
                        TextColor3       = P.textHi,
                        Font             = Enum.Font.GothamBold,
                        TextSize         = 10,
                        ZIndex           = 13,
                    })

                    -- Track
                    local trackHolder = UI.new("Frame", row, {
                        Size             = UDim2.new(1, -14, 0, TSIZE + 6),
                        Position         = UDim2.new(0, 7, 0, 28),
                        BackgroundTransparency = 1,
                        ZIndex           = 12,
                    })
                    local trackBg = UI.new("Frame", trackHolder, {
                        Size             = UDim2.new(1, 0, 0, TRH),
                        Position         = UDim2.new(0, 0, 0.5, -TRH / 2),
                        BackgroundColor3 = Color3.fromRGB(22, 26, 44),
                        ZIndex           = 13,
                    })
                    UI.corner(trackBg, TRH / 2)

                    local initT = (defV - minV) / math.max(maxV - minV, 0.0001)
                    local fill  = UI.new("Frame", trackBg, {
                        Size             = UDim2.new(initT, 0, 1, 0),
                        BackgroundColor3 = ACCENT,
                        ZIndex           = 14,
                    })
                    UI.corner(fill, TRH / 2)
                    onAccent(function(c) if fill.Parent then fill.BackgroundColor3 = c end end)

                    -- Fill gradient overlay — subtle brightness only, no color wash
                    local fillGrad = UI.gradient(fill, 0,
                        ColorSequence.new({
                            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
                        }),
                        NumberSequence.new({
                            NumberSequenceKeypoint.new(0, 0.55),
                            NumberSequenceKeypoint.new(1, 0.78),
                        })
                    )

                    local thumb = UI.new("Frame", trackHolder, {
                        Size             = UDim2.new(0, TSIZE, 0, TSIZE),
                        Position         = UDim2.new(initT, -TSIZE / 2, 0.5, -TSIZE / 2),
                        BackgroundColor3 = P.white,
                        ZIndex           = 16,
                    })
                    UI.corner(thumb, TSIZE / 2)

                    -- Accent halo ring on thumb — perfectly centered
                    local halo = UI.new("Frame", thumb, {
                        Size             = UDim2.new(1, 12, 1, 12),
                        Position         = UDim2.new(0.5, 0, 0.5, 0),
                        AnchorPoint      = Vector2.new(0.5, 0.5),
                        BackgroundColor3 = ACCENT,
                        BackgroundTransparency = 0.60,
                        ZIndex           = 15,
                    })
                    UI.corner(halo, (TSIZE + 12) / 2)
                    onAccent(function(c) if halo.Parent then halo.BackgroundColor3 = c end end)

                    -- Thumb inner dot
                    local thumbDot = UI.new("Frame", thumb, {
                        Size             = UDim2.new(0, 8, 0, 8),
                        Position         = UDim2.new(0.5, 0, 0.5, 0),
                        AnchorPoint      = Vector2.new(0.5, 0.5),
                        BackgroundColor3 = ACCENT,
                        BackgroundTransparency = 0.08,
                        ZIndex           = 17,
                    })
                    UI.corner(thumbDot, 4)
                    onAccent(function(c) if thumbDot.Parent then thumbDot.BackgroundColor3 = c end end)

                    local isDragging = false
                    local _lastCbTime = 0
                    local _SLIDER_CB_INTERVAL = 0.05  -- fire callback at most every 50 ms during drag
                    local function applyX(ax)
                        local ap = trackBg.AbsolutePosition.X
                        local as = trackBg.AbsoluteSize.X
                        if as <= 0 then return end
                        local rel = math.clamp((ax - ap) / as, 0, 1)
                        local raw = minV + rel * (maxV - minV)
                        local v
                        if math.floor(minV) == minV and math.floor(maxV) == maxV then
                            v = math.round(raw)
                        else
                            v = math.floor(raw * 100 + 0.5) / 100
                        end
                        v = math.clamp(v, minV, maxV)
                        if v == slid._val then return end
                        slid._val = v
                        local t = (v - minV) / math.max(maxV - minV, 0.0001)
                        fill.Size       = UDim2.new(t, 0, 1, 0)
                        thumb.Position  = UDim2.new(t, -TSIZE / 2, 0.5, -TSIZE / 2)
                        badgeLbl.Text   = tostring(v)
                        -- Throttle: fire callback at most every _SLIDER_CB_INTERVAL seconds
                        local now = os.clock()
                        if callback and (now - _lastCbTime) >= _SLIDER_CB_INTERVAL then
                            _lastCbTime = now
                            callback(v)
                        end
                    end

                    thumb.InputBegan:Connect(function(i)
                        if i.UserInputType == Enum.UserInputType.MouseButton1
                        or i.UserInputType == Enum.UserInputType.Touch then
                            i.Handled = true  -- consume: no pass-through
                            isDragging = true
                            tween(thumb, { BackgroundTransparency = 0.10 }, 0.08)
                            tween(halo,  { BackgroundTransparency = 0.24 }, 0.08)
                        end
                    end)
                    trackBg.InputBegan:Connect(function(i)
                        if i.UserInputType == Enum.UserInputType.MouseButton1
                        or i.UserInputType == Enum.UserInputType.Touch then
                            i.Handled = true  -- consume: no pass-through
                            isDragging = true; applyX(i.Position.X)
                        end
                    end)
                    local uc1 = UIS.InputChanged:Connect(function(i)
                        if isDragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                        or  i.UserInputType == Enum.UserInputType.Touch) then
                            applyX(i.Position.X)
                        end
                    end)
                    local uc2 = UIS.InputEnded:Connect(function(i)
                        if isDragging and (i.UserInputType == Enum.UserInputType.MouseButton1
                        or  i.UserInputType == Enum.UserInputType.Touch) then
                            isDragging = false
                            tween(thumb, { BackgroundTransparency = 0 }, 0.10)
                            tween(halo,  { BackgroundTransparency = 0.60 }, 0.10)
                            -- Always fire callback with final value on release
                            if callback then callback(slid._val) end
                        end
                    end)
                    card.AncestryChanged:Connect(function()
                        if not card.Parent then
                            pcall(function() uc1:Disconnect() end)
                            pcall(function() uc2:Disconnect() end)
                        end
                    end)

                    function slid:Set(v)
                        v = math.clamp(v, minV, maxV); slid._val = v
                        local t = (v - minV) / math.max(maxV - minV, 0.0001)
                        fill.Size      = UDim2.new(t, 0, 1, 0)
                        thumb.Position = UDim2.new(t, -TSIZE / 2, 0.5, -TSIZE / 2)
                        badgeLbl.Text  = tostring(v)
                        if callback then callback(v) end
                    end
                    function slid:Get() return slid._val end
                    return slid
                end

                -- ════════════════════════════════════════════════════════
                --  DROPDOWN  (AmaterasuUI: animated expand, accent highlight)
                -- ════════════════════════════════════════════════════════
                function sec:AddDropdown(label, options, defIdx, callback)
                    local drop   = { _idx = defIdx or 1 }
                    local open   = false
                    local ITEM_H = 32

                    local wrapper = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 46),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                        ClipsDescendants = false,
                    })

                    local header = UI.new("TextButton", wrapper, {
                        Size             = UDim2.new(1, 0, 0, 38),
                        Position         = UDim2.new(0, 0, 0, 4),
                        BackgroundColor3 = Color3.fromRGB(14, 18, 30),
                        BackgroundTransparency = 0.14,
                        Text             = "",
                        ZIndex           = 12,
                        AutoButtonColor  = false,
                    })
                    UI.corner(header, 9)
                    local hSt = UI.stroke(header, P.white, 1, 0.88)

                    local hLbl = UI.new("TextLabel", header, {
                        Size             = UDim2.new(1, -36, 1, 0),
                        Position         = UDim2.new(0, 10, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = (label ~= "" and label .. ":  " or "") .. tostring(options[drop._idx] or "–"),
                        TextColor3       = P.textHi,
                        Font             = Enum.Font.GothamMedium,
                        TextSize         = 11,
                        TextXAlignment   = Enum.TextXAlignment.Left,
                        ZIndex           = 13,
                    })
                    local arrow = UI.new("TextLabel", header, {
                        Size             = UDim2.new(0, 28, 1, 0),
                        Position         = UDim2.new(1, -28, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = "v",
                        TextColor3       = P.textLo,
                        Font             = Enum.Font.GothamBold,
                        TextSize         = 12,
                        ZIndex           = 13,
                    })

                    -- Dropdown list (appears below header)
                    local listFr = UI.new("Frame", wrapper, {
                        Size             = UDim2.new(1, 0, 0, 0),
                        Position         = UDim2.new(0, 0, 0, 44),
                        BackgroundColor3 = Color3.fromRGB(12, 16, 26),
                        BackgroundTransparency = 0.08,
                        ZIndex           = 20,
                        ClipsDescendants = true,
                        Visible          = false,
                    })
                    UI.corner(listFr, 9)
                    UI.stroke(listFr, P.white, 1, 0.90)
                    local listLayout = UI.new("UIListLayout", listFr, {
                        FillDirection   = Enum.FillDirection.Vertical,
                        Padding         = UDim.new(0, 1),
                        SortOrder       = Enum.SortOrder.LayoutOrder,
                    })

                    -- Build option items
                    for i, opt in ipairs(options) do
                        local itemBtn = UI.new("TextButton", listFr, {
                            Size             = UDim2.new(1, 0, 0, ITEM_H),
                            BackgroundTransparency = (i == drop._idx) and 0.80 or 1,
                            BackgroundColor3 = ACCENT,
                            Text             = tostring(opt),
                            TextColor3       = (i == drop._idx) and P.textHi or P.textLo,
                            Font             = (i == drop._idx) and Enum.Font.GothamBold or Enum.Font.GothamMedium,
                            TextSize         = 11,
                            ZIndex           = 21,
                            AutoButtonColor  = false,
                            LayoutOrder      = i,
                        })
                        onAccent(function(c)
                            if itemBtn.Parent and i == drop._idx then
                                itemBtn.BackgroundColor3 = c
                            end
                        end)
                        itemBtn.MouseEnter:Connect(function()
                            if i ~= drop._idx then
                                tween(itemBtn, { BackgroundTransparency = 0.90, BackgroundColor3 = ACCENT }, 0.10)
                                tween(itemBtn, { TextColor3 = P.textHi }, 0.10)
                            end
                        end)
                        itemBtn.MouseLeave:Connect(function()
                            if i ~= drop._idx then
                                tween(itemBtn, { BackgroundTransparency = 1 }, 0.10)
                                tween(itemBtn, { TextColor3 = P.textLo }, 0.10)
                            end
                        end)
                        itemBtn.MouseButton1Click:Connect(function()
                            -- Deselect previous
                            local prev = drop._idx
                            local prevBtn = listFr:FindFirstChild(tostring(prev))
                            -- Just do all buttons
                            for _, ch in ipairs(listFr:GetChildren()) do
                                if ch:IsA("TextButton") then
                                    tween(ch, { BackgroundTransparency = 1 }, 0.10)
                                    tween(ch, { TextColor3 = P.textLo }, 0.10)
                                    ch.Font = Enum.Font.GothamMedium
                                end
                            end
                            drop._idx = i
                            tween(itemBtn, { BackgroundTransparency = 0.80 }, 0.12)
                            tween(itemBtn, { TextColor3 = P.textHi }, 0.12)
                            itemBtn.Font = Enum.Font.GothamBold
                            hLbl.Text = (label ~= "" and label .. ":  " or "") .. tostring(opt)
                            -- Close list
                            open = false
                            wrapper.Size = UDim2.new(1, 0, 0, 46)
                            tween(arrow,  { Rotation = 0 }, 0.18)
                            tween(hSt,    { Transparency = 0.88 }, 0.14)
                            tween(listFr, { Size = UDim2.new(1, 0, 0, 0) }, 0.18, Enum.EasingStyle.Quart)
                            task.delay(0.20, function() if listFr.Parent then listFr.Visible = false end end)
                            if callback then callback(i) end
                        end)
                    end

                    header.MouseButton1Click:Connect(function()
                        open = not open
                        if open then
                            local totalH = #options * ITEM_H + (#options - 1)
                            listFr.Visible = true
                            listFr.Size    = UDim2.new(1, 0, 0, 0)
                            wrapper.Size   = UDim2.new(1, 0, 0, 46 + totalH + 6)
                            tween(listFr, { Size = UDim2.new(1, 0, 0, totalH) }, 0.22, Enum.EasingStyle.Quart)
                            tween(arrow,  { Rotation = 180 }, 0.18)
                            tween(hSt,    { Color = ACCENT, Transparency = 0.42 }, 0.14)
                        else
                            wrapper.Size = UDim2.new(1, 0, 0, 46)
                            tween(arrow,  { Rotation = 0 }, 0.18)
                            tween(hSt,    { Transparency = 0.88 }, 0.14)
                            tween(listFr, { Size = UDim2.new(1, 0, 0, 0) }, 0.18, Enum.EasingStyle.Quart)
                            task.delay(0.20, function() if listFr.Parent then listFr.Visible = false end end)
                        end
                    end)

                    function drop:Get() return drop._idx end
                    function drop:Set(i)
                        drop._idx = i
                        if options[i] then
                            hLbl.Text = (label ~= "" and label .. ":  " or "") .. tostring(options[i])
                        end
                    end
                    return drop
                end

                -- ════════════════════════════════════════════════════════
                --  INPUT  (AmaterasuUI: bordered text box, accent focus ring)
                -- ════════════════════════════════════════════════════════
                function sec:AddInput(label, placeholder, callback)
                    local inp = {}
                    local row = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 52),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })
                    if label and label ~= "" then
                        UI.new("TextLabel", row, {
                            Size             = UDim2.new(1, -8, 0, 16),
                            Position         = UDim2.new(0, 6, 0, 2),
                            BackgroundTransparency = 1,
                            Text             = label,
                            TextColor3       = P.textLo,
                            Font             = Enum.Font.GothamMedium,
                            TextSize         = 10,
                            TextXAlignment   = Enum.TextXAlignment.Left,
                            ZIndex           = 12,
                        })
                    end
                    local ib = UI.new("TextBox", row, {
                        Size             = UDim2.new(1, -8, 0, 30),
                        Position         = UDim2.new(0, 4, 0, 20),
                        BackgroundColor3 = Color3.fromRGB(16, 20, 34),
                        BackgroundTransparency = 0.16,
                        TextColor3       = P.textHi,
                        PlaceholderText  = placeholder or "Enter value…",
                        PlaceholderColor3 = P.textLo,
                        Font             = Enum.Font.GothamMedium,
                        TextSize         = 11,
                        ZIndex           = 12,
                        ClearTextOnFocus = false,
                    })
                    UI.corner(ib, 8)
                    UI.padding(ib, { 10, 6, 0, 0 })
                    local ibSt = UI.stroke(ib, P.white, 1, 0.82)
                    ib.Focused:Connect(function()
                        tween(ibSt, { Color = ACCENT, Transparency = 0.28 }, 0.18)
                        tween(ib,   { BackgroundTransparency = 0.06 }, 0.18)
                    end)
                    ib.FocusLost:Connect(function(enter)
                        tween(ibSt, { Color = P.white, Transparency = 0.82 }, 0.18)
                        tween(ib,   { BackgroundTransparency = 0.16 }, 0.18)
                        if callback and enter then callback(ib.Text) end
                    end)
                    function inp:Get() return ib.Text end
                    function inp:Set(v) ib.Text = tostring(v) end
                    return inp
                end

                -- ════════════════════════════════════════════════════════
                --  LABEL
                -- ════════════════════════════════════════════════════════
                function sec:AddLabel(text, sz)
                    local row = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 20),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })
                    local lbl = UI.new("TextLabel", row, {
                        Size             = UDim2.new(1, -14, 1, 0),
                        Position         = UDim2.new(0, 7, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = text,
                        TextColor3       = P.textLo,
                        Font             = Enum.Font.GothamMedium,
                        TextSize         = sz or 10,
                        TextXAlignment   = Enum.TextXAlignment.Left,
                        RichText         = true,
                        ZIndex           = 12,
                    })
                    return lbl
                end

                -- ════════════════════════════════════════════════════════
                --  SEPARATOR
                -- ════════════════════════════════════════════════════════
                function sec:AddSeparator()
                    local line = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, -12, 0, 1),
                        BackgroundColor3 = P.white,
                        BackgroundTransparency = 0.88,
                        BorderSizePixel  = 0,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })
                    -- spacer
                    UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 3),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })
                end

                -- ════════════════════════════════════════════════════════
                --  DIVIDER  (labeled text separator, accent-tinted lines)
                -- ════════════════════════════════════════════════════════
                function sec:AddDivider(text)
                    local row = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 18),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })
                    local div = UI.divider(row, text, 12)
                    div.Size = UDim2.new(1, -8, 1, 0)
                    div.Position = UDim2.new(0, 4, 0, 0)
                end

                -- ════════════════════════════════════════════════════════
                --  KEYBIND  — rebindable key chip with live rebind mode
                --  name: optional Keybinds system name; nil = standalone
                -- ════════════════════════════════════════════════════════
                function sec:AddKeybind(label, defaultKey, name, callback)
                    local kb = { _key = defaultKey, _waiting = false }

                    local row = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 40),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })
                    UI.new("TextLabel", row, {
                        Size             = UDim2.new(1, -92, 1, 0),
                        Position         = UDim2.new(0, 6, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = label,
                        TextColor3       = P.textHi,
                        Font             = Enum.Font.GothamMedium,
                        TextSize         = 11,
                        TextXAlignment   = Enum.TextXAlignment.Left,
                        ZIndex           = 12,
                    })

                    local chip = UI.new("TextButton", row, {
                        Size             = UDim2.new(0, 82, 0, 24),
                        Position         = UDim2.new(1, -86, 0.5, 0),
                        AnchorPoint      = Vector2.new(0, 0.5),
                        BackgroundColor3 = Color3.fromRGB(20, 24, 38),
                        BackgroundTransparency = 0.18,
                        Text             = defaultKey and defaultKey.Name or "None",
                        TextColor3       = P.textHi,
                        Font             = Enum.Font.Code,
                        TextSize         = 10,
                        ZIndex           = 13,
                        AutoButtonColor  = false,
                    })
                    UI.corner(chip, 6)
                    local chipSt = UI.stroke(chip, ACCENT, 1.5, 0.60)
                    onAccent(function(c) if chipSt.Parent then chipSt.Color = c end end)

                    -- Register with global keybind system if name provided
                    if name then
                        Keybinds.register(name, defaultKey, callback or function() end)
                        local stored = Keybinds.getKey(name)
                        if stored then kb._key = stored; chip.Text = stored.Name end
                        On("keybind:changed", function(n, k)
                            if n == name and chip.Parent then
                                chip.Text = k.Name; kb._key = k
                            end
                        end)
                    end

                    chip.MouseEnter:Connect(function()
                        if not kb._waiting then
                            tween(chip, { BackgroundTransparency = 0.06 }, 0.12)
                        end
                    end)
                    chip.MouseLeave:Connect(function()
                        if not kb._waiting then
                            tween(chip, { BackgroundTransparency = 0.18 }, 0.14)
                        end
                    end)

                    chip.MouseButton1Click:Connect(function()
                        if kb._waiting then return end
                        kb._waiting = true
                        local prev = chip.Text
                        chip.Text = "…"
                        tween(chip, { BackgroundTransparency = 0, BackgroundColor3 = ACCENT }, 0.12)

                        if name then
                            Keybinds.startRebind(name)
                            local unsub
                            unsub = On("keybind:changed", function(n, k)
                                if n == name then
                                    kb._waiting = false
                                    unsub()
                                    if chip.Parent then
                                        chip.Text = k.Name
                                        tween(chip, { BackgroundTransparency = 0.18, BackgroundColor3 = Color3.fromRGB(20, 24, 38) }, 0.18)
                                    end
                                end
                            end)
                        else
                            -- Standalone: listen for next key press
                            local conn
                            conn = UIS.InputBegan:Connect(function(i, gp)
                                if gp or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
                                conn:Disconnect()
                                kb._key = i.KeyCode
                                kb._waiting = false
                                if chip.Parent then
                                    chip.Text = i.KeyCode.Name
                                    tween(chip, { BackgroundTransparency = 0.18, BackgroundColor3 = Color3.fromRGB(20, 24, 38) }, 0.18)
                                end
                                if callback then pcall(callback, i.KeyCode) end
                            end)
                        end
                    end)

                    function kb:Set(key)
                        kb._key = key
                        if chip.Parent then chip.Text = key.Name end
                        if name then Keybinds.setKey(name, key) end
                    end
                    function kb:Get() return kb._key end
                    return kb
                end

                -- ════════════════════════════════════════════════════════
                --  COLOR PICKER — compact HSV picker with hex input
                --  Expands inline below the header chip (like dropdown)
                -- ════════════════════════════════════════════════════════
                function sec:AddColorPicker(label, defaultColor, callback)
                    defaultColor = defaultColor or Color3.fromRGB(0, 255, 150)
                    local cp = { _color = defaultColor }
                    local cpOpen = false
                    local H_SIZE, S_SIZE = 140, 140   -- hue strip height / SV square size
                    local PICKER_H = H_SIZE + 46       -- total expanded height

                    -- Helper: Color3 → 6-char hex string
                    local function toHex(c)
                        return string.format("%02X%02X%02X",
                            math.floor(c.R*255+0.5),
                            math.floor(c.G*255+0.5),
                            math.floor(c.B*255+0.5))
                    end

                    local wrapper = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 44),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                        ClipsDescendants = false,
                    })

                    -- Header row (click to expand/collapse)
                    local header = UI.new("TextButton", wrapper, {
                        Size             = UDim2.new(1, 0, 0, 40),
                        Position         = UDim2.new(0, 0, 0, 4),
                        BackgroundColor3 = Color3.fromRGB(14, 18, 30),
                        BackgroundTransparency = 0.14,
                        Text             = "",
                        ZIndex           = 12,
                        AutoButtonColor  = false,
                    })
                    UI.corner(header, 9)
                    UI.stroke(header, P.white, 1, 0.88)
                    UI.new("TextLabel", header, {
                        Size             = UDim2.new(1, -50, 1, 0),
                        Position         = UDim2.new(0, 10, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = label,
                        TextColor3       = P.textHi,
                        Font             = Enum.Font.GothamMedium,
                        TextSize         = 11,
                        TextXAlignment   = Enum.TextXAlignment.Left,
                        ZIndex           = 13,
                    })
                    local swatch = UI.new("Frame", header, {
                        Size             = UDim2.new(0, 26, 0, 20),
                        Position         = UDim2.new(1, -34, 0.5, 0),
                        AnchorPoint      = Vector2.new(0, 0.5),
                        BackgroundColor3 = defaultColor,
                        ZIndex           = 13,
                    })
                    UI.corner(swatch, 5)
                    UI.stroke(swatch, P.white, 1.5, 0.60)

                    -- Expanded picker frame
                    local pickerFr = UI.new("Frame", wrapper, {
                        Size             = UDim2.new(1, 0, 0, 0),
                        Position         = UDim2.new(0, 0, 0, 48),
                        BackgroundColor3 = Color3.fromRGB(10, 13, 22),
                        BackgroundTransparency = 0.04,
                        ZIndex           = 20,
                        ClipsDescendants = true,
                        Visible          = false,
                    })
                    UI.corner(pickerFr, 9)

                    local cpH, cpS, cpV = Color3.toHSV(defaultColor)

                    -- Saturation/Value square
                    local svSq = UI.new("Frame", pickerFr, {
                        Size     = UDim2.new(0, S_SIZE, 0, H_SIZE),
                        Position = UDim2.new(0, 8, 0, 8),
                        ZIndex   = 21,
                        ClipsDescendants = true,
                    })
                    UI.corner(svSq, 5)
                    local svColorGrad = UI.new("UIGradient", svSq, {
                        Rotation = 0,
                        Color    = ColorSequence.new({
                            ColorSequenceKeypoint.new(0, Color3.new(1,1,1)),
                            ColorSequenceKeypoint.new(1, Color3.fromHSV(cpH, 1, 1)),
                        }),
                    })
                    local svDark = UI.new("Frame", svSq, {
                        Size             = UDim2.new(1,0,1,0),
                        BackgroundTransparency = 1,
                        ZIndex           = 22,
                    })
                    UI.new("UIGradient", svDark, {
                        Rotation = 90,
                        Color    = ColorSequence.new({
                            ColorSequenceKeypoint.new(0, Color3.new(1,1,1)),
                            ColorSequenceKeypoint.new(1, Color3.new(0,0,0)),
                        }),
                        Transparency = NumberSequence.new({
                            NumberSequenceKeypoint.new(0, 1),
                            NumberSequenceKeypoint.new(1, 0),
                        }),
                    })
                    local svDot = UI.new("Frame", svSq, {
                        Size             = UDim2.new(0, 10, 0, 10),
                        Position         = UDim2.new(cpS, -5, 1-cpV, -5),
                        BackgroundColor3 = P.white,
                        ZIndex           = 24,
                    })
                    UI.corner(svDot, 5)
                    UI.stroke(svDot, P.white, 1.5, 0.28)

                    -- Hue strip (vertical)
                    local hueX = S_SIZE + 16
                    local hueStrip = UI.new("Frame", pickerFr, {
                        Size     = UDim2.new(0, 16, 0, H_SIZE),
                        Position = UDim2.new(0, hueX, 0, 8),
                        ZIndex   = 21,
                        ClipsDescendants = true,
                    })
                    UI.corner(hueStrip, 4)
                    UI.new("UIGradient", hueStrip, {
                        Rotation = 90,
                        Color    = ColorSequence.new({
                            ColorSequenceKeypoint.new(0/6,  Color3.fromHSV(0/6,1,1)),
                            ColorSequenceKeypoint.new(1/6,  Color3.fromHSV(1/6,1,1)),
                            ColorSequenceKeypoint.new(2/6,  Color3.fromHSV(2/6,1,1)),
                            ColorSequenceKeypoint.new(3/6,  Color3.fromHSV(3/6,1,1)),
                            ColorSequenceKeypoint.new(4/6,  Color3.fromHSV(4/6,1,1)),
                            ColorSequenceKeypoint.new(5/6,  Color3.fromHSV(5/6,1,1)),
                            ColorSequenceKeypoint.new(1,    Color3.fromHSV(0,1,1)),
                        }),
                    })
                    local hueInd = UI.new("Frame", hueStrip, {
                        Size             = UDim2.new(1, 4, 0, 4),
                        Position         = UDim2.new(-0.125, 0, cpH, -2),
                        AnchorPoint      = Vector2.new(0, 0.5),
                        BackgroundColor3 = P.white,
                        ZIndex           = 23,
                    })
                    UI.corner(hueInd, 2)

                    -- Hex input row
                    local hexRow = UI.new("Frame", pickerFr, {
                        Size     = UDim2.new(1, -16, 0, 28),
                        Position = UDim2.new(0, 8, 0, H_SIZE + 12),
                        BackgroundColor3 = Color3.fromRGB(14, 18, 30),
                        BackgroundTransparency = 0.18,
                        ZIndex   = 21,
                    })
                    UI.corner(hexRow, 6)
                    UI.new("TextLabel", hexRow, {
                        Size             = UDim2.new(0, 20, 1, 0),
                        BackgroundTransparency = 1,
                        Text             = "#",
                        TextColor3       = P.textLo,
                        Font             = Enum.Font.Code,
                        TextSize         = 10,
                        ZIndex           = 22,
                    })
                    local hexInput = UI.new("TextBox", hexRow, {
                        Size             = UDim2.new(1, -28, 1, 0),
                        Position         = UDim2.new(0, 22, 0, 0),
                        BackgroundTransparency = 1,
                        Text             = toHex(defaultColor),
                        TextColor3       = P.textHi,
                        Font             = Enum.Font.Code,
                        TextSize         = 10,
                        ZIndex           = 22,
                        ClearTextOnFocus = false,
                    })

                    -- Core update function — called from both drag inputs
                    local function updateHSV(h, s, v)
                        cpH, cpS, cpV = h, s, v
                        local col = Color3.fromHSV(h, s, v)
                        cp._color = col
                        if swatch.Parent    then swatch.BackgroundColor3 = col end
                        if hueInd.Parent    then hueInd.Position = UDim2.new(-0.125, 0, h, -2) end
                        if svDot.Parent     then svDot.Position  = UDim2.new(s, -5, 1-v, -5) end
                        if svColorGrad.Parent then
                            svColorGrad.Color = ColorSequence.new({
                                ColorSequenceKeypoint.new(0, Color3.new(1,1,1)),
                                ColorSequenceKeypoint.new(1, Color3.fromHSV(h,1,1)),
                            })
                        end
                        if hexInput.Parent then hexInput.Text = toHex(col) end
                        if callback then pcall(callback, col) end
                    end

                    -- SV drag
                    local svDrag = false
                    svSq.InputBegan:Connect(function(i)
                        if i.UserInputType == Enum.UserInputType.MouseButton1
                        or i.UserInputType == Enum.UserInputType.Touch then
                            svDrag = true
                            local s2 = math.clamp((i.Position.X - svSq.AbsolutePosition.X) / math.max(svSq.AbsoluteSize.X,1), 0, 1)
                            local v2 = 1 - math.clamp((i.Position.Y - svSq.AbsolutePosition.Y) / math.max(svSq.AbsoluteSize.Y,1), 0, 1)
                            updateHSV(cpH, s2, v2)
                        end
                    end)
                    local svUIC = UIS.InputChanged:Connect(function(i)
                        if svDrag and (i.UserInputType == Enum.UserInputType.MouseMovement
                        or i.UserInputType == Enum.UserInputType.Touch) then
                            local s2 = math.clamp((i.Position.X - svSq.AbsolutePosition.X) / math.max(svSq.AbsoluteSize.X,1), 0, 1)
                            local v2 = 1 - math.clamp((i.Position.Y - svSq.AbsolutePosition.Y) / math.max(svSq.AbsoluteSize.Y,1), 0, 1)
                            updateHSV(cpH, s2, v2)
                        end
                    end)
                    local svUIE = UIS.InputEnded:Connect(function(i)
                        if i.UserInputType == Enum.UserInputType.MouseButton1
                        or i.UserInputType == Enum.UserInputType.Touch then svDrag = false end
                    end)

                    -- Hue drag
                    local hueDrag = false
                    hueStrip.InputBegan:Connect(function(i)
                        if i.UserInputType == Enum.UserInputType.MouseButton1
                        or i.UserInputType == Enum.UserInputType.Touch then
                            hueDrag = true
                            local h2 = math.clamp((i.Position.Y - hueStrip.AbsolutePosition.Y) / math.max(hueStrip.AbsoluteSize.Y,1), 0, 1)
                            updateHSV(h2, cpS, cpV)
                        end
                    end)
                    local hueUIC = UIS.InputChanged:Connect(function(i)
                        if hueDrag and (i.UserInputType == Enum.UserInputType.MouseMovement
                        or i.UserInputType == Enum.UserInputType.Touch) then
                            local h2 = math.clamp((i.Position.Y - hueStrip.AbsolutePosition.Y) / math.max(hueStrip.AbsoluteSize.Y,1), 0, 1)
                            updateHSV(h2, cpS, cpV)
                        end
                    end)
                    local hueUIE = UIS.InputEnded:Connect(function(i)
                        if i.UserInputType == Enum.UserInputType.MouseButton1
                        or i.UserInputType == Enum.UserInputType.Touch then hueDrag = false end
                    end)

                    -- Hex input → parse on focus lost
                    hexInput.FocusLost:Connect(function()
                        local hex = hexInput.Text:gsub("[^%x]",""):upper():sub(1,6)
                        if #hex == 6 then
                            local r2 = tonumber("0x"..hex:sub(1,2))/255
                            local g2 = tonumber("0x"..hex:sub(3,4))/255
                            local b2 = tonumber("0x"..hex:sub(5,6))/255
                            local h2,s2,v2 = Color3.toHSV(Color3.new(r2,g2,b2))
                            updateHSV(h2,s2,v2)
                        else
                            hexInput.Text = toHex(cp._color)
                        end
                    end)

                    -- Clean up global connections when card is destroyed
                    card.AncestryChanged:Connect(function()
                        if not card.Parent then
                            pcall(function() svUIC:Disconnect()  end)
                            pcall(function() svUIE:Disconnect()  end)
                            pcall(function() hueUIC:Disconnect() end)
                            pcall(function() hueUIE:Disconnect() end)
                        end
                    end)

                    -- Toggle expand/collapse
                    header.MouseButton1Click:Connect(function()
                        cpOpen = not cpOpen
                        if cpOpen then
                            pickerFr.Visible = true
                            pickerFr.Size    = UDim2.new(1,0,0,0)
                            wrapper.Size     = UDim2.new(1,0,0, 44 + PICKER_H + 8)
                            tween(pickerFr, { Size = UDim2.new(1,0,0, PICKER_H) }, 0.22, Enum.EasingStyle.Quart)
                        else
                            wrapper.Size = UDim2.new(1,0,0,44)
                            tween(pickerFr, { Size = UDim2.new(1,0,0,0) }, 0.18, Enum.EasingStyle.Quart)
                            task.delay(0.20, function()
                                if not cpOpen and pickerFr.Parent then pickerFr.Visible = false end
                            end)
                        end
                    end)

                    function cp:Set(color)
                        cp._color = color
                        local h2,s2,v2 = Color3.toHSV(color)
                        updateHSV(h2,s2,v2)
                    end
                    function cp:Get() return cp._color end
                    return cp
                end

                -- ════════════════════════════════════════════════════════
                --  MULTI-TOGGLE — accent chip row; each chip toggles on/off
                --  options: { "Label A", "Label B", ... }
                --  defaults: { true, false, ... }   (parallel table)
                --  callback: function(states)  where states[i] = bool
                -- ════════════════════════════════════════════════════════
                function sec:AddMultiToggle(options, defaults, callback)
                    local mt = { _states = {} }
                    for i = 1, #options do
                        mt._states[i] = (defaults and defaults[i]) or false
                    end

                    local row = UI.new("Frame", elList, {
                        Size             = UDim2.new(1, 0, 0, 36),
                        BackgroundTransparency = 1,
                        ZIndex           = 11,
                        LayoutOrder      = eo(),
                    })
                    UI.new("UIListLayout", row, {
                        FillDirection     = Enum.FillDirection.Horizontal,
                        Padding           = UDim.new(0, 4),
                        VerticalAlignment = Enum.VerticalAlignment.Center,
                        SortOrder         = Enum.SortOrder.LayoutOrder,
                    })
                    UI.new("UIPadding", row, {
                        PaddingLeft  = UDim.new(0, 4),
                        PaddingRight = UDim.new(0, 4),
                    })

                    local chips = {}
                    for i, optLabel in ipairs(options) do
                        local on = mt._states[i]
                        local chip = UI.new("TextButton", row, {
                            Size                   = UDim2.new(0, 0, 0, 26),
                            AutomaticSize          = Enum.AutomaticSize.X,
                            BackgroundColor3       = on and ACCENT or Color3.fromRGB(20, 24, 40),
                            BackgroundTransparency = on and 0.08 or 0.30,
                            Text                   = optLabel,
                            TextColor3             = on and P.white or P.textLo,
                            Font                   = on and Enum.Font.GothamBold or Enum.Font.GothamMedium,
                            TextSize               = 10,
                            ZIndex                 = 12,
                            AutoButtonColor        = false,
                            LayoutOrder            = i,
                        })
                        UI.corner(chip, 13)
                        UI.new("UIPadding", chip, {
                            PaddingLeft  = UDim.new(0, 10),
                            PaddingRight = UDim.new(0, 10),
                        })
                        onAccent(function(c)
                            if chip.Parent and mt._states[i] then
                                chip.BackgroundColor3 = c
                            end
                        end)

                        local idx = i  -- capture
                        chip.MouseButton1Click:Connect(function()
                            mt._states[idx] = not mt._states[idx]
                            local v = mt._states[idx]
                            tween(chip, {
                                BackgroundColor3       = v and ACCENT or Color3.fromRGB(20,24,40),
                                BackgroundTransparency = v and 0.08 or 0.30,
                                TextColor3             = v and P.white or P.textLo,
                            }, 0.16, Enum.EasingStyle.Sine)
                            chip.Font = v and Enum.Font.GothamBold or Enum.Font.GothamMedium
                            if callback then pcall(callback, mt._states) end
                        end)
                        chips[i] = chip
                    end

                    function mt:Set(idx, val, silent)
                        mt._states[idx] = val
                        local chip = chips[idx]
                        if chip and chip.Parent then
                            chip.BackgroundColor3       = val and ACCENT or Color3.fromRGB(20,24,40)
                            chip.BackgroundTransparency = val and 0.08 or 0.30
                            chip.TextColor3             = val and P.white or P.textLo
                            chip.Font = val and Enum.Font.GothamBold or Enum.Font.GothamMedium
                        end
                        if callback and not silent then pcall(callback, mt._states) end
                    end
                    function mt:GetAll() return mt._states end
                    return mt
                end

                function sec:GetContainer() return elList end
                return sec
            end -- AddSection

            return col
        end -- AddColumn

        return tab
    end -- AddTab

    return win
end -- Lib.Window


-- ═══════════════════════════════════════════════════════════════════
--  DYNAMIC THEME ENGINE
-- ═══════════════════════════════════════════════════════════════════

local function stopDynamic()
    _dynMode = nil
end

local function startRainbow()
    _dynH    = 0
    _dynMode = "rainbow"
end

local function startDual(c1, c2, speed)
    -- speed param kept for API compatibility but now unused (driven by dt in Heartbeat)
    _dynC1  = c1
    _dynC2  = c2
    _dynT   = 0
    _dynDir = 1
    _dynMode = "dual"
end

-- Triple-cycle: smoothly steps through 3 colors in a continuous loop
local function startTriple(c1, c2, c3, speed)
    -- speed param kept for API compatibility but now unused (driven by dt in Heartbeat)
    _dynC1  = c1
    _dynC2  = c2
    _dynC3  = c3
    _dynT   = 0
    _dynMode = "triple"
end

-- ────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
--  THEME PRESETS  (grouped by category for sub-tab UI)
-- ═══════════════════════════════════════════════════════════════════

local function D(n,e,c1,c2)     return { name=n, emoji=e, dynamic="dual",   color1=c1, color2=c2 } end
local function T3(n,e,c1,c2,c3) return { name=n, emoji=e, dynamic="triple", color1=c1, color2=c2, color3=c3 } end
local function R(c) return Color3.fromRGB(c[1],c[2],c[3]) end

-- ═══════════════════════════════════════════════════════════════════
--  AMATERASU THEME SYSTEM — Japanese Mythology & Divine Aesthetics
--  Categories: Kami · Yokai · Katana · Mugen · Hanabi · Tensei · Taiyo
-- ═══════════════════════════════════════════════════════════════════
local THEME_CATS = {
    -- ── KAMI (神) — Divine Gods ──────────────────────────────────────
    {
        name = "Kami", emoji = "⛩️",
        themes = {
    D("Amaterasu",          "☀️", R{255,185,20},  R{255,60,0}),
    D("Susanoo",            "⛈️", R{0,120,255},   R{80,0,180}),
    D("Tsukuyomi",          "🌕", R{200,215,255},  R{20,15,50}),
    D("Izanagi",            "🌊", R{0,190,220},   R{20,0,80}),
    D("Izanami",            "💀", R{10,5,15},     R{180,0,60}),
    D("Fujin",              "🌀", R{0,230,200},   R{60,80,200}),
    D("Raijin",             "⚡", R{255,240,80},  R{30,80,220}),
    D("Inari",              "🦊", R{255,140,30},  R{220,0,40}),
    D("Benzaiten",          "🎵", R{255,150,200},  R{120,0,220}),
    D("Bishamonten",        "⚔️", R{220,0,30},    R{255,180,0}),
    D("Ebisu",              "🎣", R{0,180,140},   R{255,200,0}),
    D("Daikokuten",         "🪙", R{255,195,0},   R{160,80,0}),
    D("Kagutsuchi",         "🔥", R{255,40,0},    R{255,180,0}),
    D("Takemikazuchi",      "🗡️", R{240,248,255},  R{60,80,200}),
    D("Okuninushi",         "🌾", R{0,180,80},    R{200,155,0}),
    D("Izumo Dusk",         "🌆", R{220,130,40},  R{80,0,140}),
    D("Shinto Veil",        "⛩️", R{255,60,90},   R{8,4,12}),
    D("Divine Gate",        "🏯", R{210,170,120},  R{120,0,30}),
        },
    },

    -- ── YOKAI (妖怪) — Spirits & Demons ─────────────────────────────
    {
        name = "Yokai", emoji = "👺",
        themes = {
    D("Oni Warlord",        "👹", R{200,0,30},    R{60,0,0}),
    D("Kitsune",            "🦊", R{255,140,0},   R{255,40,0}),
    D("Tengu",              "🐦", R{0,60,20},     R{255,195,0}),
    D("Kappa",              "🐢", R{0,190,130},   R{0,60,30}),
    D("Yuki-Onna",          "❄️", R{220,240,255},  R{10,15,60}),
    D("Tanuki",             "🦝", R{190,120,40},  R{80,40,10}),
    D("Baku",               "😴", R{140,0,220},   R{255,200,80}),
    D("Jorogumo",           "🕷️", R{200,0,80},    R{10,5,20}),
    D("Raiju",              "⚡", R{80,200,255},  R{200,220,255}),
    D("Yamata-Orochi",      "🐍", R{0,180,80},    R{120,0,20}),
    D("Gashadokuro",        "💀", R{200,215,230},  R{5,5,10}),
    D("Nurarihyon",         "🌑", R{30,0,60},     R{100,130,180}),
    D("Ittan-momen",        "🌫️", R{235,238,245},  R{80,80,110}),
    D("Otengu",             "🔴", R{180,0,0},     R{255,220,80}),
    D("Nekomata",           "🐈", R{255,100,160},  R{80,0,140}),
    D("Shikigami",          "🔮", R{120,0,220},   R{0,220,180}),
    D("Hannya Mask",        "🎭", R{220,0,0},     R{255,220,0}),
    D("Nue",                "🌑", R{15,5,25},     R{160,0,200}),
    D("Shuten-doji",        "🍶", R{200,0,30},    R{160,80,0}),
    D("Enenra",             "💨", R{50,50,60},    R{0,220,200}),
    D("Yomotsu",            "🌑", R{5,0,10},     R{100,0,60}),
        },
    },

    -- ── KATANA (刀) — Warrior & Blade Themes ────────────────────────
    {
        name = "Katana", emoji = "🗡️",
        themes = {
    D("Muramasa",           "🗡️", R{220,0,40},    R{10,5,5}),
    D("Masamune",           "⚔️", R{200,215,235},  R{30,40,80}),
    D("Kusarigama",         "⛓️", R{80,85,95},    R{200,0,30}),
    D("Nodachi",            "🌑", R{15,10,20},    R{180,0,40}),
    D("Tanto",              "🔪", R{230,230,240},  R{180,0,30}),
    D("Tachi Flame",        "🔥", R{255,80,0},    R{200,0,20}),
    D("Naginata",           "🌸", R{255,160,200},  R{180,0,40}),
    D("Shirasaya",          "⬜", R{240,240,245},  R{60,60,80}),
    D("Bloodsteel",         "🩸", R{160,0,30},    R{100,110,120}),
    D("Darksteel",          "🌑", R{20,20,30},    R{80,90,120}),
    D("Crimson Guard",      "🛡️", R{200,0,30},    R{80,85,100}),
    D("Void Blade",         "🌀", R{5,0,10},     R{100,0,200}),
    D("Jade Strike",        "💚", R{0,180,80},    R{0,100,40}),
    D("Gilded Edge",        "👑", R{220,185,0},   R{140,100,0}),
    D("Ghost Katana",       "👻", R{220,225,240},  R{10,10,30}),
    D("Ronin Path",         "🌾", R{160,120,60},  R{40,30,20}),
    D("Shogun Decree",      "🏯", R{200,0,30},    R{220,185,0}),
    D("Shadow Dojo",        "🌑", R{10,8,14},    R{140,0,220}),
    D("Steel Sakura",       "🌸", R{255,175,200},  R{120,130,145}),
    D("Iron Oni",           "👺", R{150,0,20},    R{100,110,120}),
    D("Samurai Dusk",       "🌆", R{200,100,30},  R{60,0,100}),
    D("Kendo Storm",        "⛈️", R{0,120,220},   R{200,210,230}),
    D("Demon Slayer",       "🔥", R{255,120,0},   R{0,60,160}),
    D("Last Stand",         "🪖", R{200,0,0},    R{255,185,0}),
        },
    },

    -- ── MUGEN (夢幻) — Dream & Illusion Pastels ───────────────────────
    {
        name = "Mugen", emoji = "💭",
        themes = {
    D("Cherry Mist",        "🌸", R{255,190,210},  R{200,175,255}),
    D("Wisteria Veil",      "🌺", R{200,170,255},  R{255,185,210}),
    D("Moonbloom",          "🌕", R{220,235,255},  R{180,160,255}),
    D("Sakura Fall",        "🌸", R{255,200,215},  R{255,245,250}),
    D("Tanabata",           "⭐", R{150,170,255},  R{255,200,230}),
    D("Morning Crane",      "🕊️", R{200,230,255},  R{240,248,255}),
    D("Yume Kiri",          "🌫️", R{200,195,230},  R{230,225,245}),
    D("Obon Night",         "🏮", R{255,180,60},   R{180,0,80}),
    D("Tsuki no Umi",       "🌊", R{170,195,255},  R{120,145,220}),
    D("Hana Ame",           "🌧️", R{200,220,255},  R{255,200,220}),
    D("Fuji Haze",          "🗻", R{190,185,215},  R{215,210,235}),
    D("Asagao",             "🌷", R{180,160,255},  R{255,175,220}),
    D("Shiro Kiri",         "⬜", R{240,240,250},  R{200,210,235}),
    D("Yuuyake",            "🌅", R{255,200,170},  R{255,170,200}),
    D("Lotus Pond",         "🪷", R{230,185,220},  R{185,225,230}),
    D("Hanami Eve",         "🌸", R{255,210,225},  R{240,235,255}),
    D("Autumn Lantern",     "🏮", R{230,175,140},  R{200,160,200}),
    D("Koi Dream",          "🐟", R{255,155,130},  R{180,215,255}),
    D("Tea Garden",         "🍵", R{200,210,185},  R{230,225,205}),
    D("Silk Road",          "🧵", R{230,195,220},  R{195,215,240}),
        },
    },

    -- ── HANABI (花火) — Fireworks & Vivid Energy ─────────────────────
    {
        name = "Hanabi", emoji = "🎆",
        themes = {
    D("Grand Finale",       "🎆", R{255,0,120},   R{255,240,0}),
    D("Solar Burst",        "☀️", R{255,200,0},   R{255,80,0}),
    D("Thunder Lotus",      "⚡", R{255,235,0},   R{0,180,255}),
    D("Plasma Shrine",      "🔵", R{0,220,255},   R{180,0,255}),
    D("Lava Shrine",        "🌋", R{255,60,0},    R{255,200,0}),
    D("Acid Rain",          "☣️", R{100,255,0},   R{0,220,255}),
    D("Hyperion",           "💥", R{255,0,60},    R{0,200,255}),
    D("UV Temple",          "🔆", R{200,0,255},   R{240,248,255}),
    D("Circuit Torii",      "⚙️", R{0,220,180},   R{255,100,0}),
    D("Strobe Dojo",        "🎵", R{255,0,200},   R{0,255,240}),
    D("Synthwave Shrine",   "🎹", R{255,80,200},  R{80,0,255}),
    D("Gamma Blade",        "🟢", R{0,255,80},    R{200,255,0}),
    D("Vortex Pulse",       "🌀", R{0,100,255},   R{255,0,200}),
    D("Reactor Torii",      "⚛️", R{0,220,200},   R{0,255,120}),
    D("Overdrive",          "🔴", R{255,0,30},    R{255,120,0}),
    D("Neon Oni",           "👺", R{255,0,180},   R{0,255,200}),
    D("Ion Katana",         "⚡", R{0,220,255},   R{240,248,255}),
    D("Glitch Shrine",      "⚠️", R{255,0,230},   R{0,240,255}),
    D("Hot Festival",       "🎉", R{255,100,0},   R{255,0,120}),
    D("Power Chime",        "🔔", R{255,240,0},   R{0,200,255}),
    D("Dragon Festival",    "🐉", R{255,30,0},    R{255,210,0}),
    D("Neon Sakura",        "🌸", R{255,0,160},   R{160,0,255}),
    D("Afterburner",        "🚀", R{255,120,0},   R{255,240,80}),
    D("Radiant Shrine",     "✨", R{255,255,255},  R{255,185,0}),
        },
    },

    -- ── TENSEI (転生) — Triple-Phase Reincarnation ────────────────────
    {
        name = "Tensei", emoji = "♾️",
        themes = {
    T3("Kami Cycle",        "⛩️", R{255,185,20},  R{220,35,65},  R{8,4,12}),
    T3("Solar Eclipse",     "🌑", R{255,200,0},   R{10,5,5},    R{200,0,30}),
    T3("Infernal Torii",    "🔥", R{255,40,0},    R{255,160,0},  R{220,0,40}),
    T3("Three Realms",      "🌌", R{0,220,180},   R{120,0,220},  R{220,0,40}),
    T3("Shinto Aurora",     "🌅", R{0,220,160},   R{120,0,220},  R{5,5,25}),
    T3("Susanoo Storm",     "⛈️", R{0,80,200},    R{220,230,255}, R{5,5,40}),
    T3("Izanami Descent",   "💀", R{5,0,10},     R{180,0,60},   R{255,170,0}),
    T3("Kitsune Nine",      "🦊", R{255,140,0},   R{220,0,40},   R{5,5,10}),
    T3("Raijin Fury",       "⚡", R{50,120,255},  R{255,240,80},  R{200,0,255}),
    T3("Sakura Storm",      "🌸", R{255,180,210},  R{255,0,60},   R{60,0,120}),
    T3("Tsuki Phases",      "🌕", R{240,245,255},  R{120,135,200}, R{10,10,40}),
    T3("Yokai Hunt",        "👺", R{200,0,30},    R{255,140,0},   R{10,5,5}),
    T3("Void Trinity",      "🌑", R{5,0,10},     R{80,0,160},   R{180,0,40}),
    T3("Dragon 3 Fires",    "🐉", R{5,5,10},    R{220,0,0},    R{255,195,0}),
    T3("Spirit Drift",      "👻", R{235,240,255},  R{140,0,220},  R{10,5,25}),
    T3("Oni Cycle",         "👹", R{200,0,30},    R{10,5,5},    R{255,180,0}),
    T3("Divine Sequence",   "✨", R{255,255,255},  R{220,185,0},  R{200,0,30}),
    T3("Muramasa Arc",      "🗡️", R{230,235,245},  R{180,0,40},   R{5,5,5}),
    T3("Mountain Path",     "🗻", R{190,200,230},  R{0,160,140},  R{5,15,50}),
    T3("Obon Spirits",      "🏮", R{255,180,60},  R{180,0,100},  R{15,5,25}),
    T3("Chaos Kanji",       "💥", R{220,0,30},    R{100,0,220},  R{0,220,200}),
    T3("Celestial Accord",  "💫", R{220,185,0},   R{0,160,220},  R{220,0,100}),
    T3("Eternal Shrine",    "⛩️", R{255,185,20},  R{255,60,0},   R{120,0,220}),
    T3("Paradox Gate",      "♾️", R{240,245,255},  R{5,5,10},    R{200,0,30}),
        },
    },

    -- ── TAIYO (太陽) — Rainbow Solar Spectrum ─────────────────────────
    {
        name = "Taiyo", emoji = "🌈",
        themes = {
            { name="Spectrum", emoji="🌈", dynamic="rainbow" },
        },
    },
}

-- Flatten THEME_CATS → THEMES for backward compat (chat commands, persistence)
local THEMES = {}
for _, cat in ipairs(THEME_CATS) do
    for _, t in ipairs(cat.themes) do
        THEMES[#THEMES + 1] = t
    end
end



-- ═══════════════════════════════════════════════════════════════════
--  NOTIFY — toast notification system
-- ═══════════════════════════════════════════════════════════════════

local _notifSg   = newScreenGui("AmaterasuNotify", -2, true)
local notifQueue = {}
local NOTIF_GAP  = 0.11

local function Notify(text, dur, priority)
    dur      = dur      or 4.5
    priority = priority or "normal"

    -- Clamp stack so it never overflows the screen
    local MAX_STACK = 4

    if priority == "low" and #notifQueue >= MAX_STACK then
        return  -- low-priority: silently drop if queue is full
    end

    if #notifQueue >= MAX_STACK then
        if priority == "high" or priority == "critical" then
            -- Evict the oldest non-critical entry
            for i, n in ipairs(notifQueue) do
                if n:GetAttribute("_priority") ~= "critical" then
                    if n and n.Parent then n:Destroy() end
                    table.remove(notifQueue, i)
                    break
                end
            end
        else
            -- normal: evict oldest
            local oldest = table.remove(notifQueue, 1)
            if oldest and oldest.Parent then oldest:Destroy() end
        end
    end

    local idx   = #notifQueue + 1
    local yBase = 0.88 - (idx - 1) * NOTIF_GAP

    -- Build panel — starts at the right edge, off-screen
    local p = UI.glassPanel(_notifSg, UDim2.new(0, 244, 0, 38),
                             UDim2.new(1.15, 0, yBase, 0), 100)
    p.holder.ZIndex = 100

    -- ── All glass layers start invisible — fade in together with the slide ──
    p.body.BackgroundTransparency      = 1
    p.shadow.BackgroundTransparency    = 1
    p.spinFrame.BackgroundTransparency = 1   -- ← was missing; caused the white pop-in

    -- Accent left stripe
    local stripe = UI.new("Frame", p.body, {
        Size             = UDim2.new(0, 3, 0.58, 0),
        Position         = UDim2.new(0, 10, 0.21, 0),
        BackgroundColor3 = ACCENT,
        BorderSizePixel  = 0,
        ZIndex           = 102,
    })
    UI.corner(stripe, 2)
    onAccent(function(c) if stripe.Parent then stripe.BackgroundColor3 = c end end)

    -- Text label (starts transparent — fades in after panel appears)
    local lbl = UI.label(p.body, text, 10, {
        Size             = UDim2.new(1, -26, 1, 0),
        Position         = UDim2.new(0, 20, 0, 0),
        Font             = Enum.Font.GothamMedium,
        TextColor3       = P.textHi,
        TextXAlignment   = Enum.TextXAlignment.Left,
        TextTruncate     = Enum.TextTruncate.AtEnd,
        TextTransparency = 1,
        ZIndex           = 102,
    })

    notifQueue[idx] = p.holder
    p.holder:SetAttribute("_priority", priority)   -- used by high/critical eviction logic

    -- Slide all existing notifications up to make room
    local function repack()
        for i, n in ipairs(notifQueue) do
            if n and n.Parent then
                tween(n, { Position = UDim2.new(0.884, 0, 0.88 - (i-1)*NOTIF_GAP, 0) },
                      0.40, Enum.EasingStyle.Quint)
            end
        end
    end

    -- ── ENTER: spring-slide from right + all layers fade in together ──────────
    -- Start small and off-screen right
    p.holder.Size = UDim2.new(0, 210, 0, 30)
    tween(p.holder, {
        Position = UDim2.new(0.884, 0, yBase, 0),
        Size     = UDim2.new(0, 244, 0, 38),
    }, 0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    -- Fade all glass layers in simultaneously
    tween(p.body,      { BackgroundTransparency = 0.18 }, 0.50, Enum.EasingStyle.Sine)
    tween(p.shadow,    { BackgroundTransparency = 0.88 }, 0.50, Enum.EasingStyle.Sine)
    tween(p.spinFrame, { BackgroundTransparency = 0    }, 0.50, Enum.EasingStyle.Sine)
    -- Text appears slightly later for a staggered feel
    task.delay(0.18, function()
        if lbl.Parent then
            tween(lbl, { TextTransparency = 0 }, 0.34, Enum.EasingStyle.Sine)
        end
    end)
    repack()

    -- ── Time-remaining progress bar at bottom of notification ───────────────────
    local timerBar = UI.new("Frame", p.body, {
        Size                   = UDim2.new(1, -24, 0, 2),
        Position               = UDim2.new(0, 12, 1, -4),
        AnchorPoint            = Vector2.new(0, 1),
        BackgroundColor3       = Color3.fromRGB(30, 34, 54),
        BackgroundTransparency = 0.40,
        ZIndex                 = 103,
        ClipsDescendants       = true,
    })
    UI.corner(timerBar, 1)
    local timerFill = UI.new("Frame", timerBar, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundColor3       = ACCENT,
        BorderSizePixel        = 0,
        ZIndex                 = 104,
    })
    UI.corner(timerFill, 1)
    onAccent(function(c) if timerFill.Parent then timerFill.BackgroundColor3 = c end end)
    -- Shrink from full to zero over `dur` seconds
    task.delay(0.20, function()
        if timerFill.Parent then
            tween(timerFill, { Size = UDim2.new(0, 0, 1, 0) }, dur - 0.20, Enum.EasingStyle.Linear)
        end
    end)

    -- ── SWIPE-TO-DISMISS: right-swipe or tap anywhere on notification ─────────
    -- This also gives a click-to-dismiss for desktop users.
    local dismissed = false
    local swipeStartX = 0
    local swipingNotif = false

    local function dismissNotif()
        if dismissed then return end
        dismissed = true
        tween(lbl,         { TextTransparency = 1 }, 0.18, Enum.EasingStyle.Sine)
        tween(p.body,      { BackgroundTransparency = 1 }, 0.24, Enum.EasingStyle.Sine)
        tween(p.shadow,    { BackgroundTransparency = 1 }, 0.24, Enum.EasingStyle.Sine)
        tween(p.spinFrame, { BackgroundTransparency = 1 }, 0.24, Enum.EasingStyle.Sine)
        tween(p.holder, {
            Position = UDim2.new(1.25, 0, yBase, 0),
            Size     = UDim2.new(0, 200, 0, 28),
        }, 0.32, Enum.EasingStyle.Quint)
        task.delay(0.36, function()
            for i, n in ipairs(notifQueue) do
                if n == p.holder then table.remove(notifQueue, i); break end
            end
            if p.holder and p.holder.Parent then p.holder:Destroy() end
            repack()
        end)
    end

    -- Attach to the body (which now has Active=true)
    p.body.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1 then
            swipeStartX   = i.Position.X
            swipingNotif  = true
        end
    end)
    p.body.InputChanged:Connect(function(i)
        if swipingNotif and (i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseMovement) then
            local dx = i.Position.X - swipeStartX
            if dx > 40 then  -- threshold: 40px right swipe = dismiss
                swipingNotif = false
                dismissNotif()
            elseif dx < -8 then  -- slight left = cancel swipe
                swipingNotif = false
            end
        end
    end)
    p.body.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1 then
            local dx = math.abs(i.Position.X - swipeStartX)
            -- Tap (< 8px movement) = instant dismiss
            if swipingNotif and dx < 8 then
                dismissNotif()
            end
            swipingNotif = false
        end
    end)

    -- ── EXIT: fade out all layers, then slide off-screen right ───────────────
    -- "critical" priority: only dismissable by tap/swipe, never auto-expired
    task.delay(dur, function()
        if priority == "critical" then return end  -- must be manually dismissed
        if dismissed then return end  -- already dismissed by swipe/tap
        dismissNotif()
    end)
end

-- ═══════════════════════════════════════════════════════════════════
--  EXPORTS
-- ═══════════════════════════════════════════════════════════════════

local _genv = (type(getgenv) == "function") and getgenv() or _G

_genv.Lib          = Lib
_genv.Notify       = Notify
_genv.setAccent    = setAccent
_genv.onAccent     = onAccent
_genv.startDual    = startDual
_genv.startTriple  = startTriple
_genv.startRainbow = startRainbow
_genv.stopDynamic  = stopDynamic
_genv.springTween  = springTween
_genv.Store        = Store
_genv.Emit         = Emit
_genv.On           = On
_genv.THEMES       = THEME_CATS

print("[Amaterasu UI] Library loaded ✓")
print("[Amaterasu UI] Globals set: Lib · Notify · setAccent · startDual · startTriple · startRainbow · stopDynamic")
