local Lib = {}


-- ── makeWindowOrb — unified helper used by all Ford windows ───────────────
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
    w = w or 390
    h = h or 320

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
    --  TOP BAR  (FordUI style: clean dark strip with title + orbs)
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

        -- Column holder (FordUI uses a single full-width scrolling column per tab)
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
        --  AddColumn  (FordUI: mobile single-column; divides width for N cols)
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
                --  TOGGLE  (FordUI style: large pill, bounce spring, glow)
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

                    -- FordUI pill: compact for mobile
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
                --  CYCLE  (FordUI: larger, accent-colored arrows)
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
                --  SLIDER  (FordUI: 22px thumb, accent fill, mobile drag)
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
                --  DROPDOWN  (FordUI: animated expand, accent highlight)
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
                --  INPUT  (FordUI: bordered text box, accent focus ring)
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

return Lib
