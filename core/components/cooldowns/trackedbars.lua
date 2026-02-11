local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil

-- Local aliases for promoted functions (performance)
local resolveCDMColor = addon.ResolveCDMColor
local getDefaultFontFace = addon.GetDefaultFontFace
local CDM_VIEWERS = addon.CDM_VIEWERS

--------------------------------------------------------------------------------
-- TrackedBars Styling
--------------------------------------------------------------------------------
-- TrackedBars (BuffBarCooldownViewer) support two modes:
--   Default: Overlay-based bar styling (fill overlay anchored to StatusBar fill)
--   Vertical: Addon-owned vertical stack frames with mirrored data
-- Text styling (SetFont/SetTextColor) remains direct — always safe.
--------------------------------------------------------------------------------

-- Default mode overlay tracking (weak keys for GC)
local trackedBarOverlays = setmetatable({}, { __mode = "k" })

-- Data mirroring for vertical mode (weak keys for GC)
local barItemMirror = setmetatable({}, { __mode = "k" })
local hookedBarItems = setmetatable({}, { __mode = "k" })
local visHookedItems = setmetatable({}, { __mode = "k" })

-- Vertical stack pool and active list
local vertStackPool = {}
local activeVertStacks = {} -- ordered array of { blizzItem = child, frame = vertStack }
local vertContainer = nil
local verticalModeActive = false
local vertRebuildPending = false

-- Alpha enforcement hooks tracking (weak keys)
local alphaEnforcedItems = setmetatable({}, { __mode = "k" })


--------------------------------------------------------------------------------
-- Tracked Bar Mode Helpers
--------------------------------------------------------------------------------

local function getTrackedBarMode()
    local comp = addon.Components and addon.Components.trackedBars
    if not comp or not comp.db then return "default" end
    return comp.db.barMode or "default"
end

local function getTrackedBarSetting(key)
    local comp = addon.Components and addon.Components.trackedBars
    if not comp then return nil end
    if comp.db and comp.db[key] ~= nil then return comp.db[key] end
    if comp.settings and comp.settings[key] then return comp.settings[key].default end
    return nil
end

--------------------------------------------------------------------------------
-- Default Mode: Bar Overlay Creation
--------------------------------------------------------------------------------

local function createBarOverlay(blizzBarItem)
    local barFrame = (blizzBarItem.GetBarFrame and blizzBarItem:GetBarFrame()) or blizzBarItem.Bar
    if not barFrame then return nil end

    local overlay = CreateFrame("Frame", nil, barFrame)
    overlay:SetAllPoints(barFrame)
    overlay:SetFrameLevel(barFrame:GetFrameLevel())  -- Same level, not +1, so OVERLAY-layer text stays on top
    overlay:EnableMouse(false)

    -- BORDER layer sits below OVERLAY where Blizzard's Name/Duration FontStrings live
    overlay.barBg = overlay:CreateTexture(nil, "BACKGROUND", nil, -1)
    overlay.barBg:SetAllPoints(overlay)
    overlay.barBg:Hide()

    overlay.barFill = overlay:CreateTexture(nil, "BORDER", nil, -1)
    overlay.barFill:Hide()

    overlay:Hide()
    return overlay
end

local function getOrCreateBarOverlay(blizzBarItem)
    local existing = trackedBarOverlays[blizzBarItem]
    if existing then return existing end
    local overlay = createBarOverlay(blizzBarItem)
    if overlay then
        trackedBarOverlays[blizzBarItem] = overlay
    end
    return overlay
end

local function anchorFillOverlay(overlay, barFrame)
    if not overlay or not overlay.barFill or not barFrame then return end
    local fill = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
    if not fill then return end
    overlay.barFill:ClearAllPoints()
    overlay.barFill:SetAllPoints(fill)
end

local function hideBarOverlay(blizzBarItem)
    local overlay = trackedBarOverlays[blizzBarItem]
    if not overlay then return end
    overlay:Hide()
    if overlay.barFill then overlay.barFill:Hide() end
    if overlay.barBg then overlay.barBg:Hide() end
end

--------------------------------------------------------------------------------
-- Vertical Mode: Data Mirroring Hooks
--------------------------------------------------------------------------------

local function installDataMirrorHooks(child)
    if hookedBarItems[child] then return end
    hookedBarItems[child] = true

    local mirror = barItemMirror[child]
    if not mirror then
        mirror = {}
        barItemMirror[child] = mirror
    end

    local barFrame = (child.GetBarFrame and child:GetBarFrame()) or child.Bar
    if barFrame then
        if barFrame.SetValue then
            hooksecurefunc(barFrame, "SetValue", function(_, val)
                local m = barItemMirror[child]
                if not m then return end
                if not issecretvalue(val) then
                    m.barValue = val
                    m.valueTime = GetTime()
                end
                -- Forward to vertical StatusBar (C++ handles secrets natively)
                if verticalModeActive and m.vertStatusBar then
                    pcall(m.vertStatusBar.SetValue, m.vertStatusBar, val)
                end
            end)
        end
        if barFrame.SetMinMaxValues then
            hooksecurefunc(barFrame, "SetMinMaxValues", function(_, minVal, maxVal)
                local m = barItemMirror[child]
                if not m then return end
                if not issecretvalue(minVal) then m.barMin = minVal end
                if not issecretvalue(maxVal) then m.barMax = maxVal end
                -- Forward to vertical StatusBar (C++ handles secrets natively)
                if verticalModeActive and m.vertStatusBar then
                    pcall(m.vertStatusBar.SetMinMaxValues, m.vertStatusBar, minVal, maxVal)
                end
            end)
        end
        if barFrame.Name and barFrame.Name.SetText then
            hooksecurefunc(barFrame.Name, "SetText", function(_, text)
                local m = barItemMirror[child]
                if m then m.nameText = text end
                if verticalModeActive then
                    addon.UpdateVerticalBarText(child, "name")
                end
            end)
        end
        if barFrame.Duration and barFrame.Duration.SetText then
            hooksecurefunc(barFrame.Duration, "SetText", function(_, text)
                local m = barItemMirror[child]
                if m then m.durationText = text end
                if verticalModeActive then
                    addon.UpdateVerticalBarText(child, "duration")
                end
            end)
        end
    end

    local iconFrame = (child.GetIconFrame and child:GetIconFrame()) or child.Icon
    if iconFrame then
        if iconFrame.Icon and iconFrame.Icon.SetTexture then
            hooksecurefunc(iconFrame.Icon, "SetTexture", function(_, tex)
                local m = barItemMirror[child]
                if m then m.spellTexture = tex end
                if verticalModeActive then
                    addon.UpdateVerticalBarText(child, "icon")
                end
            end)
        end
        if iconFrame.Applications and iconFrame.Applications.SetText then
            hooksecurefunc(iconFrame.Applications, "SetText", function(_, text)
                local m = barItemMirror[child]
                if m then m.applicationsText = text end
                if verticalModeActive then
                    addon.UpdateVerticalBarText(child, "applications")
                end
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- Vertical Mode: Stack Frame Creation
--------------------------------------------------------------------------------

local function createVerticalStack()
    local stack = CreateFrame("Frame", nil, UIParent)
    stack:EnableMouse(false)

    -- Icon region (bottom of stack)
    stack.iconRegion = CreateFrame("Frame", nil, stack)
    stack.iconRegion:EnableMouse(true)
    stack.iconTexture = stack.iconRegion:CreateTexture(nil, "ARTWORK")
    stack.iconTexture:SetAllPoints(stack.iconRegion)
    stack.applicationsFS = stack.iconRegion:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    stack.applicationsFS:SetPoint("BOTTOMRIGHT", stack.iconRegion, "BOTTOMRIGHT", -2, 2)
    stack.applicationsFS:SetJustifyH("RIGHT")

    -- Bar region (above icon)
    stack.barRegion = CreateFrame("Frame", nil, stack)
    stack.barRegion:EnableMouse(false)

    stack.barBg = stack.barRegion:CreateTexture(nil, "BACKGROUND", nil, 0)
    stack.barBg:SetAllPoints(stack.barRegion)

    stack.barFill = CreateFrame("StatusBar", nil, stack.barRegion)
    stack.barFill:SetAllPoints(stack.barRegion)
    stack.barFill:SetOrientation("VERTICAL")
    stack.barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    stack.barFill:SetMinMaxValues(0, 1)
    stack.barFill:SetValue(0)

    -- Rotated spell name frame (swapped dimensions, -90deg rotation)
    stack.spellNameFrame = CreateFrame("Frame", nil, stack.barRegion)
    stack.spellNameFS = stack.spellNameFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stack.spellNameFS:SetAllPoints(stack.spellNameFrame)
    stack.spellNameFS:SetJustifyH("CENTER")
    stack.spellNameFS:SetJustifyV("MIDDLE")

    local ag = stack.spellNameFrame:CreateAnimationGroup()
    local rot = ag:CreateAnimation("Rotation")
    rot:SetDegrees(-90)
    rot:SetDuration(0)
    rot:SetEndDelay(2147483647)
    ag:Play()
    stack.spellNameAG = ag

    -- Timer fontstring (top of stack, right-side up)
    stack.timerFS = stack:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stack.timerFS:SetJustifyH("CENTER")

    stack:Hide()
    return stack
end

local function acquireVertStack()
    local stack = table.remove(vertStackPool)
    if not stack then
        stack = createVerticalStack()
    end
    return stack
end

local function releaseVertStack(stack)
    if not stack then return end
    stack:Hide()
    stack:ClearAllPoints()
    stack:SetParent(UIParent)
    stack.iconTexture:SetTexture(nil)
    stack.applicationsFS:SetText("")
    stack.spellNameFS:SetText("")
    stack.timerFS:SetText("")
    stack.barFill:SetMinMaxValues(0, 1)
    stack.barFill:SetValue(0)
    table.insert(vertStackPool, stack)
end

local function releaseAllVertStacks()
    for i = #activeVertStacks, 1, -1 do
        local entry = activeVertStacks[i]
        -- Clear forwarding reference
        local m = barItemMirror[entry.blizzItem]
        if m then m.vertStatusBar = nil end
        releaseVertStack(entry.frame)
        activeVertStacks[i] = nil
    end
end

--------------------------------------------------------------------------------
-- Vertical Mode: Layout and Sizing
--------------------------------------------------------------------------------

local function layoutVerticalStack(stack, displayMode)
    if not stack then return end
    local iconSize = tonumber(getTrackedBarSetting("iconSize")) or 100
    local scale = iconSize / 100
    local barWidth = tonumber(getTrackedBarSetting("barWidth")) or 100
    local barHeight = barWidth * scale -- barWidth setting = vertical bar height
    local iconBarPad = tonumber(getTrackedBarSetting("iconBarPadding")) or 0
    local stackWidth = 30 * scale
    local iconDim = stackWidth

    local iconRatio = tonumber(getTrackedBarSetting("iconTallWideRatio")) or 0
    local iconW, iconH = iconDim, iconDim
    if addon.IconRatio then
        iconW, iconH = addon.IconRatio.GetDimensionsForComponent("trackedBars", iconRatio)
        iconW = (iconW or 30) * scale
        iconH = (iconH or 30) * scale
    else
        iconW = iconDim
        iconH = iconDim
    end
    iconW = math.max(8, iconW)
    iconH = math.max(8, iconH)
    stackWidth = iconW

    displayMode = displayMode or "both"
    local showIcon = (displayMode ~= "name")
    local showName = (displayMode ~= "icon")

    stack.iconRegion:SetShown(showIcon)
    stack.spellNameFS:SetShown(showName)

    -- Timer always at top
    local yOff = 0

    -- Icon at bottom
    if showIcon then
        stack.iconRegion:SetSize(iconW, iconH)
        stack.iconRegion:ClearAllPoints()
        stack.iconRegion:SetPoint("BOTTOM", stack, "BOTTOM", 0, 0)
        yOff = iconH + iconBarPad
    end

    -- Bar region above icon (or at bottom if no icon)
    stack.barRegion:ClearAllPoints()
    stack.barRegion:SetSize(stackWidth, barHeight)
    stack.barRegion:SetPoint("BOTTOM", stack, "BOTTOM", 0, yOff)

    -- Rotated name frame: swapped dimensions so text reads along the bar
    stack.spellNameFrame:ClearAllPoints()
    stack.spellNameFrame:SetSize(barHeight, stackWidth) -- swapped
    stack.spellNameFrame:SetPoint("CENTER", stack.barRegion, "CENTER")

    -- Timer above bar
    stack.timerFS:ClearAllPoints()
    stack.timerFS:SetPoint("BOTTOM", stack.barRegion, "TOP", 0, 2)

    -- Total stack height
    local timerHeight = 16 * scale
    local totalHeight = (showIcon and (iconH + iconBarPad) or 0) + barHeight + timerHeight + 2
    stack:SetSize(stackWidth, totalHeight)
end

local function layoutVerticalStacks()
    if not vertContainer then return end
    local padding = tonumber(getTrackedBarSetting("iconPadding")) or 3
    local xOffset = 0
    for _, entry in ipairs(activeVertStacks) do
        entry.frame:ClearAllPoints()
        entry.frame:SetPoint("BOTTOMLEFT", vertContainer, "BOTTOMLEFT", xOffset, 0)
        xOffset = xOffset + entry.frame:GetWidth() + padding
    end
    vertContainer:SetSize(math.max(1, xOffset), 1)
end

--------------------------------------------------------------------------------
-- Vertical Mode: Fill + Text Updates
--------------------------------------------------------------------------------

function addon.UpdateVerticalBarText(child, which)
    local mirror = barItemMirror[child]
    if not mirror then return end
    local stack
    for _, entry in ipairs(activeVertStacks) do
        if entry.blizzItem == child then
            stack = entry.frame
            break
        end
    end
    if not stack then return end

    if which == "name" then
        stack.spellNameFS:SetText(mirror.nameText or "")
    elseif which == "duration" then
        stack.timerFS:SetText(mirror.durationText or "")
    elseif which == "icon" then
        stack.iconTexture:SetTexture(mirror.spellTexture)
    elseif which == "applications" then
        local txt = mirror.applicationsText or ""
        stack.applicationsFS:SetText(txt)
        stack.applicationsFS:SetShown(txt ~= "" and txt ~= "0" and txt ~= "1")
    end
end

--------------------------------------------------------------------------------
-- Vertical Mode: Style Application
--------------------------------------------------------------------------------

local function styleVerticalStack(stack, component)
    if not stack or not component or not component.db then return end
    local db = component.db
    local defaultFace = select(1, GameFontNormal:GetFont())

    -- Bar textures
    local useCustom = db.styleEnableCustom ~= false
    if useCustom then
        local fgKey = db.styleForegroundTexture or "bevelled"
        local bgKey = db.styleBackgroundTexture or "bevelled"
        local fgPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(fgKey)
        local bgPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(bgKey)

        if fgPath then
            stack.barFill:SetStatusBarTexture(fgPath)
        else
            stack.barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end

        if bgPath then
            stack.barBg:SetTexture(bgPath)
        else
            stack.barBg:SetColorTexture(0, 0, 0, 1)
        end

        -- Foreground color (use same legacy settings as ApplyTrackedBarVisualsForChild)
        local fgColorMode = db.styleForegroundColorMode or "default"
        local fgTint = db.styleForegroundTint or {1,1,1,1}
        local fgR, fgG, fgB, fgA = 1, 1, 1, 1
        if fgColorMode == "custom" and type(fgTint) == "table" then
            fgR, fgG, fgB, fgA = fgTint[1] or 1, fgTint[2] or 1, fgTint[3] or 1, fgTint[4] or 1
        elseif fgColorMode == "class" and addon.GetClassColorRGB then
            local cr, cg, cb = addon.GetClassColorRGB("player")
            fgR, fgG, fgB, fgA = cr or 1, cg or 1, cb or 1, 1
        elseif fgColorMode == "texture" then
            fgR, fgG, fgB, fgA = 1, 1, 1, 1
        elseif fgColorMode == "default" then
            fgR, fgG, fgB, fgA = 1.0, 0.5, 0.25, 1.0
        end
        stack.barFill:GetStatusBarTexture():SetVertexColor(fgR, fgG, fgB, fgA)

        -- Background color + opacity (use same legacy settings as ApplyTrackedBarVisualsForChild)
        local bgColorMode = db.styleBackgroundColorMode or "default"
        local bgTint = db.styleBackgroundTint or {0,0,0,1}
        local bgOpacity = tonumber(db.styleBackgroundOpacity) or 50
        bgOpacity = math.max(0, math.min(100, bgOpacity)) / 100
        local bgR, bgG, bgB, bgA = 0, 0, 0, 1
        if bgColorMode == "custom" and type(bgTint) == "table" then
            bgR, bgG, bgB, bgA = bgTint[1] or 0, bgTint[2] or 0, bgTint[3] or 0, bgTint[4] or 1
        elseif bgColorMode == "class" and addon.GetClassColorRGB then
            local cr, cg, cb = addon.GetClassColorRGB("player")
            bgR, bgG, bgB, bgA = cr or 0, cg or 0, cb or 0, 1
        elseif bgColorMode == "texture" then
            bgR, bgG, bgB, bgA = 1, 1, 1, 1
        elseif bgColorMode == "default" then
            bgR, bgG, bgB, bgA = 0, 0, 0, 1
        end
        stack.barBg:SetVertexColor(bgR, bgG, bgB, bgA)
        stack.barBg:SetAlpha(bgOpacity)

        stack.barFill:Show()
        stack.barBg:Show()
    else
        -- Default CDM look
        stack.barFill:SetStatusBarTexture("UI-HUD-CoolDownManager-Bar")
        stack.barFill:GetStatusBarTexture():SetVertexColor(1.0, 0.5, 0.25, 1.0)
        stack.barBg:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
        stack.barBg:SetVertexColor(1, 1, 1, 1)
        stack.barBg:SetAlpha(1)
        stack.barFill:Show()
        stack.barBg:Show()
    end

    -- Border on bar
    local wantBorder = db.borderEnable
    if wantBorder then
        local styleKey = db.borderStyle or "square"
        local thickness = tonumber(db.borderThickness) or 1
        if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
        local tintEnabled = db.borderTintEnable and type(db.borderTintColor) == "table"
        local color
        if tintEnabled then
            local c = db.borderTintColor
            color = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
        else
            color = {0, 0, 0, 1}
        end
        local inset = tonumber(db.borderInset) or 0
        local handled = false
        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
            handled = addon.BarBorders.ApplyToBarFrame(stack.barRegion, styleKey, {
                color = color,
                thickness = thickness,
                inset = inset,
            })
        end
        if not handled then
            if addon.Borders and addon.Borders.ApplySquare then
                addon.Borders.ApplySquare(stack.barRegion, {
                    size = thickness,
                    color = color,
                    layer = "OVERLAY",
                    layerSublevel = 7,
                    levelOffset = 5,
                    containerParent = stack.barRegion,
                    expandX = 1,
                    expandY = 2,
                    skipDimensionCheck = true,
                })
            end
        end
    else
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(stack.barRegion) end
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(stack.barRegion) end
    end

    -- Icon border
    local iconBorderEnabled = not not db.iconBorderEnable
    local iconStyle = tostring(db.iconBorderStyle or "none")
    local iconThickness = tonumber(db.iconBorderThickness) or 1
    iconThickness = math.max(1, math.min(16, iconThickness))
    local iconBorderInset = tonumber(db.iconBorderInset) or 0
    local iconTintEnabled = not not db.iconBorderTintEnable
    local tintRaw = db.iconBorderTintColor
    local tintColor = {1, 1, 1, 1}
    if type(tintRaw) == "table" then
        tintColor = { tintRaw[1] or 1, tintRaw[2] or 1, tintRaw[3] or 1, tintRaw[4] or 1 }
    end
    if iconBorderEnabled and stack.iconRegion:IsShown() then
        addon.ApplyIconBorderStyle(stack.iconRegion, iconStyle, {
            thickness = iconThickness,
            inset = iconBorderInset,
            color = iconTintEnabled and tintColor or nil,
            tintEnabled = iconTintEnabled,
            db = db,
            thicknessKey = "iconBorderThickness",
            tintColorKey = "iconBorderTintColor",
            defaultThickness = 1,
        })
    else
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(stack.iconRegion) end
    end

    -- Text: Spell Name
    local nameCfg = db.textName or { size = 14, style = "OUTLINE", color = {1,1,1,1} }
    local nameFace = addon.ResolveFontFace and addon.ResolveFontFace(nameCfg.fontFace or "FRIZQT__") or defaultFace
    if addon.ApplyFontStyle then
        addon.ApplyFontStyle(stack.spellNameFS, nameFace, tonumber(nameCfg.size) or 14, nameCfg.style or "OUTLINE")
    else
        stack.spellNameFS:SetFont(nameFace, tonumber(nameCfg.size) or 14, nameCfg.style or "OUTLINE")
    end
    local nc = resolveCDMColor(nameCfg)
    stack.spellNameFS:SetTextColor(nc[1] or 1, nc[2] or 1, nc[3] or 1, nc[4] or 1)

    -- Text: Timer
    local durCfg = db.textDuration or { size = 14, style = "OUTLINE", color = {1,1,1,1} }
    local durFace = addon.ResolveFontFace and addon.ResolveFontFace(durCfg.fontFace or "FRIZQT__") or defaultFace
    if addon.ApplyFontStyle then
        addon.ApplyFontStyle(stack.timerFS, durFace, tonumber(durCfg.size) or 14, durCfg.style or "OUTLINE")
    else
        stack.timerFS:SetFont(durFace, tonumber(durCfg.size) or 14, durCfg.style or "OUTLINE")
    end
    local dc = resolveCDMColor(durCfg)
    stack.timerFS:SetTextColor(dc[1] or 1, dc[2] or 1, dc[3] or 1, dc[4] or 1)

    -- Text: Applications
    local stacksCfg = db.textStacks or { size = 14, style = "OUTLINE", color = {1,1,1,1} }
    local stacksFace = addon.ResolveFontFace and addon.ResolveFontFace(stacksCfg.fontFace or "FRIZQT__") or defaultFace
    if addon.ApplyFontStyle then
        addon.ApplyFontStyle(stack.applicationsFS, stacksFace, tonumber(stacksCfg.size) or 14, stacksCfg.style or "OUTLINE")
    else
        stack.applicationsFS:SetFont(stacksFace, tonumber(stacksCfg.size) or 14, stacksCfg.style or "OUTLINE")
    end
    local sc = resolveCDMColor(stacksCfg)
    stack.applicationsFS:SetTextColor(sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 1)
end

--------------------------------------------------------------------------------
-- Vertical Mode: Tooltip Forwarding
--------------------------------------------------------------------------------

local function setupVertStackTooltip(stack, blizzBarItem)
    stack.iconRegion:SetScript("OnEnter", function()
        pcall(function()
            if blizzBarItem and blizzBarItem.OnEnter then
                blizzBarItem:OnEnter()
            end
        end)
    end)
    stack.iconRegion:SetScript("OnLeave", function()
        pcall(function()
            if blizzBarItem and blizzBarItem.OnLeave then
                blizzBarItem:OnLeave()
            end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Vertical Mode: Blizzard Item Alpha Enforcement
--------------------------------------------------------------------------------

local function enforceBlizzItemAlpha(child)
    -- Always force alpha to 0 (needed on every vertical activation)
    pcall(child.SetAlpha, child, 0)
    -- Install the enforcement hook only once per child
    if alphaEnforcedItems[child] then return end
    alphaEnforcedItems[child] = true
    if child.SetAlpha then
        hooksecurefunc(child, "SetAlpha", function(self, alpha)
            if verticalModeActive and alpha > 0 then
                pcall(self.SetAlpha, self, 0)
            end
        end)
    end
end

local function restoreBlizzItemAlpha(child)
    -- Cannot remove hooks, but verticalModeActive = false stops enforcement
    pcall(child.SetAlpha, child, 1)
end

--------------------------------------------------------------------------------
-- Vertical Mode: Apply/Remove
--------------------------------------------------------------------------------

local function ensureVertContainer()
    if vertContainer then return vertContainer end
    vertContainer = CreateFrame("Frame", nil, UIParent)
    vertContainer:SetPoint("BOTTOMLEFT", _G["BuffBarCooldownViewer"] or UIParent, "BOTTOMLEFT", 0, 0)
    vertContainer:EnableMouse(false)
    vertContainer:SetSize(1, 1)

    vertContainer:Show()
    return vertContainer
end

local function applyVerticalMode(component)
    verticalModeActive = true
    ensureVertContainer()
    local frame = _G[component.frameName]
    if not frame then return end

    local displayMode = getTrackedBarSetting("displayMode") or "both"

    -- Release any previous stacks
    releaseAllVertStacks()

    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        if child.GetBarFrame or child.Bar then
            -- Install data mirror hooks (always, even for hidden items)
            installDataMirrorHooks(child)

            -- Skip hidden/inactive items — respects Blizzard's hideWhenInactive logic
            if not child:IsShown() then
                -- Don't create a vertical stack for items Blizzard has hidden
            else

            -- Acquire vertical stack
            local stack = acquireVertStack()
            stack:SetParent(vertContainer)

            -- Populate from mirror (capture current data)
            local mirror = barItemMirror[child] or {}

            -- Try to read current values from Blizzard frames as initial data
            local barFrame = (child.GetBarFrame and child:GetBarFrame()) or child.Bar
            local iconFrame = (child.GetIconFrame and child:GetIconFrame()) or child.Icon

            -- Capture current icon texture
            if iconFrame and iconFrame.Icon then
                local ok, tex = pcall(iconFrame.Icon.GetTexture, iconFrame.Icon)
                if ok and tex then mirror.spellTexture = tex end
            end

            -- Set mirrored data on stack
            stack.iconTexture:SetTexture(mirror.spellTexture)
            stack.spellNameFS:SetText(mirror.nameText or "")
            stack.timerFS:SetText(mirror.durationText or "")
            local appText = mirror.applicationsText or ""
            stack.applicationsFS:SetText(appText)
            stack.applicationsFS:SetShown(appText ~= "" and appText ~= "0" and appText ~= "1")

            -- Layout the stack geometry
            layoutVerticalStack(stack, displayMode)

            -- Style the stack (textures, borders, fonts)
            styleVerticalStack(stack, component)

            -- Store mirror and StatusBar forwarding reference
            barItemMirror[child] = mirror
            mirror.vertStatusBar = stack.barFill
            table.insert(activeVertStacks, { blizzItem = child, frame = stack })

            -- Sync initial values from Blizzard bar (secret or not — C++ handles both)
            local initBar = (child.GetBarFrame and child:GetBarFrame()) or child.Bar
            if initBar then
                pcall(function()
                    local min, max = initBar:GetMinMaxValues()
                    stack.barFill:SetMinMaxValues(min, max)
                end)
                pcall(function()
                    local val = initBar:GetValue()
                    stack.barFill:SetValue(val)
                end)
            end

            -- Setup tooltip forwarding
            setupVertStackTooltip(stack, child)

            -- Hide Blizzard bar item
            enforceBlizzItemAlpha(child)

            stack:Show()
            end -- else (IsShown)
        end
    end

    layoutVerticalStacks()
    vertContainer:Show()
end

local function removeVerticalMode()
    verticalModeActive = false
    releaseAllVertStacks()
    if vertContainer then
        vertContainer:Hide()
    end

    -- Restore Blizzard bar items
    local comp = addon.Components and addon.Components.trackedBars
    if comp then
        local frame = _G[comp.frameName]
        if frame then
            for _, child in ipairs({ frame:GetChildren() }) do
                restoreBlizzItemAlpha(child)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Vertical Mode: Edit Mode Integration
--------------------------------------------------------------------------------

local vertEditModeHooked = false

local function hookVertEditMode()
    if vertEditModeHooked then return end
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then return end
    if viewer.SetIsEditing then
        hooksecurefunc(viewer, "SetIsEditing", function(self, isEditing)
            if isEditing then
                -- Entering Edit Mode: temporarily show Blizzard bars, hide vert
                if verticalModeActive then
                    if vertContainer then vertContainer:Hide() end
                    for _, child in ipairs({ self:GetChildren() }) do
                        pcall(child.SetAlpha, child, 1)
                    end
                end
            else
                -- Exiting Edit Mode: re-apply if vertical mode
                if getTrackedBarMode() == "vertical" then
                    C_Timer.After(0, function()
                        local comp = addon.Components and addon.Components.trackedBars
                        if comp then applyVerticalMode(comp) end
                    end)
                end
            end
        end)
    end
    vertEditModeHooked = true
end

--------------------------------------------------------------------------------
-- Default Mode: Overlay-Based Styling for ApplyTrackedBarVisualsForChild
--------------------------------------------------------------------------------

function addon.ApplyTrackedBarVisualsForChild(component, child)
    if not component or not child then return end
    if component.id ~= "trackedBars" then return end
    local barFrame = (child.GetBarFrame and child:GetBarFrame()) or child.Bar
    local iconFrame = (child.GetIconFrame and child:GetIconFrame()) or child.Icon
    if not barFrame or not iconFrame then return end

    local function getSettingValue(key)
        if not component then return nil end
        if component.db and component.db[key] ~= nil then return component.db[key] end
        if component.settings and component.settings[key] then return component.settings[key].default end
        return nil
    end

    -- Calculate icon dimensions from ratio
    local iconRatio = tonumber(getSettingValue("iconTallWideRatio")) or 0
    local iconWidth, iconHeight
    if addon.IconRatio then
        iconWidth, iconHeight = addon.IconRatio.GetDimensionsForComponent("trackedBars", iconRatio)
    else
        -- Fallback if IconRatio not loaded
        iconWidth, iconHeight = 30, 30
    end
    if iconWidth and iconHeight and iconFrame.SetSize then
        iconWidth = math.max(8, math.min(32, iconWidth))
        iconHeight = math.max(8, math.min(32, iconHeight))
        iconFrame:SetSize(iconWidth, iconHeight)
        local tex = iconFrame.Icon or (child.GetIconTexture and child:GetIconTexture())
        if tex and tex.SetAllPoints then tex:SetAllPoints(iconFrame) end
        local mask = iconFrame.Mask or iconFrame.IconMask
        if mask and mask.SetAllPoints then mask:SetAllPoints(iconFrame) end
    end

    local desiredPad = tonumber(component.db and component.db.iconBarPadding) or (component.settings.iconBarPadding and component.settings.iconBarPadding.default) or 0
    desiredPad = tonumber(desiredPad) or 0

    local currentGap
    if barFrame.GetLeft and iconFrame.GetRight then
        local bl = barFrame:GetLeft()
        local ir = iconFrame:GetRight()
        if bl and ir then currentGap = bl - ir end
    end

    local deltaPad = (currentGap and (desiredPad - currentGap)) or 0

    if barFrame.ClearAllPoints and barFrame.SetPoint then
        local rightPoint, rightRelTo, rightRelPoint, rx, ry
        if barFrame.GetNumPoints and barFrame.GetPoint then
            local n = barFrame:GetNumPoints()
            for i = 1, n do
                local p, rt, rp, ox, oy = barFrame:GetPoint(i)
                if p == "RIGHT" then rightPoint, rightRelTo, rightRelPoint, rx, ry = p, rt, rp, ox, oy break end
            end
        end
        barFrame:ClearAllPoints()
        if rightPoint and rightRelTo then
            barFrame:SetPoint("RIGHT", rightRelTo, rightRelPoint or "RIGHT", (rx or 0) + deltaPad, ry or 0)
        else
            barFrame:SetPoint("RIGHT", child, "RIGHT", deltaPad, 0)
        end
        local anchorLeftTo, anchorLeftPoint, anchorLeftRelPoint = iconFrame, "RIGHT", "RIGHT"
        if iconFrame.IsShown and not iconFrame:IsShown() then
            anchorLeftTo, anchorLeftPoint, anchorLeftRelPoint = child, "LEFT", "LEFT"
        end
        barFrame:SetPoint("LEFT", anchorLeftTo, anchorLeftPoint, desiredPad, 0)
    end

    -- Overlay-based bar texture styling
    do
        local useCustom = (component.db and component.db.styleEnableCustom) ~= false
        if useCustom then
            local overlay = getOrCreateBarOverlay(child)
            if overlay then
                -- Anchor fill overlay to Blizzard's fill texture (secret-safe)
                anchorFillOverlay(overlay, barFrame)

                -- Apply foreground texture to fill overlay
                local fg = component.db and component.db.styleForegroundTexture or (component.settings.styleForegroundTexture and component.settings.styleForegroundTexture.default)
                local fgPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(fg)
                if fgPath then
                    overlay.barFill:SetTexture(fgPath)
                else
                    overlay.barFill:SetColorTexture(1, 0.5, 0.25, 1)
                end

                -- Foreground color
                local fgColorMode = (component.db and component.db.styleForegroundColorMode) or "default"
                local fgTint = (component.db and component.db.styleForegroundTint) or {1,1,1,1}
                local r, g, b, a = 1, 1, 1, 1
                if fgColorMode == "custom" and type(fgTint) == "table" then
                    r, g, b, a = fgTint[1] or 1, fgTint[2] or 1, fgTint[3] or 1, fgTint[4] or 1
                elseif fgColorMode == "class" and addon.GetClassColorRGB then
                    local cr, cg, cb = addon.GetClassColorRGB("player")
                    r, g, b, a = cr or 1, cg or 1, cb or 1, 1
                elseif fgColorMode == "texture" then
                    r, g, b, a = 1, 1, 1, 1
                elseif fgColorMode == "default" then
                    r, g, b, a = 1.0, 0.5, 0.25, 1.0
                end
                overlay.barFill:SetVertexColor(r, g, b, a)
                overlay.barFill:Show()

                -- Apply background texture to bg overlay
                local bg = component.db and component.db.styleBackgroundTexture or (component.settings.styleBackgroundTexture and component.settings.styleBackgroundTexture.default)
                local bgPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(bg)
                if bgPath then
                    overlay.barBg:SetTexture(bgPath)
                else
                    overlay.barBg:SetColorTexture(0, 0, 0, 1)
                end

                -- Background color + opacity
                local bgColorMode = (component.db and component.db.styleBackgroundColorMode) or "default"
                local bgTint = (component.db and component.db.styleBackgroundTint) or {0,0,0,1}
                local bgOpacity = component.db and component.db.styleBackgroundOpacity or (component.settings.styleBackgroundOpacity and component.settings.styleBackgroundOpacity.default) or 50
                local br, bg2, bb, ba = 0, 0, 0, 1
                if bgColorMode == "custom" and type(bgTint) == "table" then
                    br, bg2, bb, ba = bgTint[1] or 0, bgTint[2] or 0, bgTint[3] or 0, bgTint[4] or 1
                elseif bgColorMode == "class" and addon.GetClassColorRGB then
                    local cr, cg, cb = addon.GetClassColorRGB("player")
                    br, bg2, bb, ba = cr or 0, cg or 0, cb or 0, 1
                elseif bgColorMode == "texture" then
                    br, bg2, bb, ba = 1, 1, 1, 1
                elseif bgColorMode == "default" then
                    br, bg2, bb, ba = 0, 0, 0, 1
                end
                overlay.barBg:SetVertexColor(br, bg2, bb, ba)
                local opacityVal = tonumber(bgOpacity) or 50
                opacityVal = math.max(0, math.min(100, opacityVal)) / 100
                overlay.barBg:SetAlpha(opacityVal)
                overlay.barBg:Show()

                overlay:Show()

                -- Hide Blizzard fill texture so our overlay shows through
                local blizzFill = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
                if blizzFill then pcall(blizzFill.SetAlpha, blizzFill, 0) end
                -- Hide Blizzard background
                if barFrame.BarBG then pcall(barFrame.BarBG.SetAlpha, barFrame.BarBG, 0) end
            end
        else
            -- No custom textures: hide overlay, restore Blizzard defaults
            hideBarOverlay(child)
            local blizzFill = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
            if blizzFill then
                if blizzFill.SetAlpha then pcall(blizzFill.SetAlpha, blizzFill, 1.0) end
                if blizzFill.SetAtlas then pcall(blizzFill.SetAtlas, blizzFill, "UI-HUD-CoolDownManager-Bar", true) end
                if blizzFill.SetVertexColor then pcall(blizzFill.SetVertexColor, blizzFill, 1.0, 0.5, 0.25, 1.0) end
                if blizzFill.SetTexCoord then pcall(blizzFill.SetTexCoord, blizzFill, 0, 1, 0, 1) end
            end
            if barFrame.SetStatusBarAtlas then pcall(barFrame.SetStatusBarAtlas, barFrame, "UI-HUD-CoolDownManager-Bar") end
            if barFrame.BarBG then pcall(barFrame.BarBG.SetAlpha, barFrame.BarBG, 1.0) end
            Util.HideDefaultBarTextures(barFrame, true)
        end
    end

    local wantBorder = component.db and component.db.borderEnable
    local styleKey = component.db and component.db.borderStyle or "square"
    if wantBorder then
        local thickness = tonumber(component.db.borderThickness) or 1
        if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
        -- DEBUG: Trace border tint values
        if addon.debugEnabled then
            print(string.format("[TrackedBars] borderTintEnable=%s, borderTintColor=%s",
                tostring(component.db.borderTintEnable),
                type(component.db.borderTintColor) == "table" and
                    string.format("{%.2f,%.2f,%.2f,%.2f}",
                        component.db.borderTintColor[1] or 0,
                        component.db.borderTintColor[2] or 0,
                        component.db.borderTintColor[3] or 0,
                        component.db.borderTintColor[4] or 0)
                    or "nil"))
        end
        local tintEnabled = component.db.borderTintEnable and type(component.db.borderTintColor) == "table"
        local color
        if tintEnabled then
            local c = component.db.borderTintColor
            color = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
        else
            if styleDef then
                color = {1, 1, 1, 1}
            else
                color = {0, 0, 0, 1}
            end
        end

        local handled = false
        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
            local inset = tonumber(component.db.borderInset) or 0
            handled = addon.BarBorders.ApplyToBarFrame(barFrame, styleKey, {
                color = color,
                thickness = thickness,
                inset = inset,
            })
        end

        if handled then
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(barFrame) end
            Util.HideDefaultBarTextures(barFrame)
        else
            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(barFrame) end
            if addon.Borders and addon.Borders.ApplySquare then
                addon.Borders.ApplySquare(barFrame, {
                    size = thickness,
                    color = color,
                    layer = "OVERLAY",
                    layerSublevel = 7,
                    levelOffset = 5,
                    containerParent = barFrame,
                    expandX = 1,
                    expandY = 2,
                })
            end
            Util.HideDefaultBarTextures(barFrame, true)
        end
    else
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(barFrame) end
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(barFrame) end
        Util.HideDefaultBarTextures(barFrame, true)
    end

    local function shouldShowIconBorder()
        local mode = tostring(getSettingValue("displayMode") or "both")
        if mode == "name" then return false end
        if iconFrame.IsShown and not iconFrame:IsShown() then return false end
        return true
    end

    local iconBorderEnabled = not not getSettingValue("iconBorderEnable")
    local iconStyle = tostring(getSettingValue("iconBorderStyle") or "none")
    local iconThickness = tonumber(getSettingValue("iconBorderThickness")) or 1
    iconThickness = math.max(1, math.min(16, iconThickness))
    local iconBorderInset = tonumber(getSettingValue("iconBorderInset")) or 0
    local iconTintEnabled = not not getSettingValue("iconBorderTintEnable")
    local tintRaw = getSettingValue("iconBorderTintColor")
    local tintColor = {1, 1, 1, 1}
    if type(tintRaw) == "table" then
        tintColor = { tintRaw[1] or 1, tintRaw[2] or 1, tintRaw[3] or 1, tintRaw[4] or 1 }
    end

    if iconBorderEnabled and shouldShowIconBorder() then
        Util.ToggleDefaultIconOverlay(iconFrame, false)
        addon.ApplyIconBorderStyle(iconFrame, iconStyle, {
            thickness = iconThickness,
            inset = iconBorderInset,
            color = iconTintEnabled and tintColor or nil,
            tintEnabled = iconTintEnabled,
            db = component.db,
            thicknessKey = "iconBorderThickness",
            tintColorKey = "iconBorderTintColor",
            defaultThickness = component.settings and component.settings.iconBorderThickness and component.settings.iconBorderThickness.default or 1,
        })
    else
        Util.ToggleDefaultIconOverlay(iconFrame, true)
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(iconFrame) end
    end

    local defaultFace = (select(1, GameFontNormal:GetFont()))

    local function promoteFontLayer(font)
        if font and font.SetDrawLayer then
            font:SetDrawLayer("OVERLAY", 5)
        end
    end
    promoteFontLayer((child.GetNameLabel and child:GetNameLabel()) or child.Name or child.Text or child.Label)
    promoteFontLayer((child.GetDurationLabel and child:GetDurationLabel()) or child.Duration or child.DurationText or child.Timer or child.TimerText)

    local function findFontStringByNameHint(root, hint)
        local target = nil
        local function scan(obj)
            if not obj or target then return end
            if obj.GetObjectType and obj:GetObjectType() == "FontString" then
                local nm = obj.GetName and obj:GetName() or ""
                if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                    target = obj; return
                end
            end
            if obj.GetRegions then
                local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                for i = 1, n do
                    local r = select(i, obj:GetRegions())
                    if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                        local nm = r.GetName and r:GetName() or ""
                        if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                            target = r; return
                        end
                    end
                end
            end
            if obj.GetChildren then
                local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
                for i = 1, m do
                    local c = select(i, obj:GetChildren())
                    scan(c)
                    if target then return end
                end
            end
        end
        scan(root)
        return target
    end

    local function findFontStringOn(obj)
        if not obj then return nil end
        if obj.GetObjectType and obj:GetObjectType() == "FontString" then return obj end
        if obj.GetRegions then
            local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
            for i = 1, n do
                local r = select(i, obj:GetRegions())
                if r and r.GetObjectType and r:GetObjectType() == "FontString" then return r end
            end
        end
        if obj.GetChildren then
            local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
            for i = 1, m do
                local c = select(i, obj:GetChildren())
                local found = findFontStringOn(c)
                if found then return found end
            end
        end
        return nil
    end

    local nameFS = (barFrame and barFrame.Name) or findFontStringByNameHint(barFrame or child, "Bar.Name") or findFontStringByNameHint(child, "Name")
    local durFS  = (barFrame and barFrame.Duration) or findFontStringByNameHint(barFrame or child, "Bar.Duration") or findFontStringByNameHint(child, "Duration")

    if nameFS and nameFS.SetFont then
        local cfg = component.db.textName or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
        local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
        pcall(nameFS.SetDrawLayer, nameFS, "OVERLAY", 10)
        if addon.ApplyFontStyle then addon.ApplyFontStyle(nameFS, face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") else nameFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") end
        local c = resolveCDMColor(cfg)
        if nameFS.SetTextColor then nameFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
        if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, "LEFT") end
        local ox = (cfg.offset and cfg.offset.x) or 0
        local oy = (cfg.offset and cfg.offset.y) or 0
        if (ox ~= 0 or oy ~= 0) and nameFS.ClearAllPoints and nameFS.SetPoint then
            nameFS:ClearAllPoints()
            local anchorTo = barFrame or child
            nameFS:SetPoint("LEFT", anchorTo, "LEFT", ox, oy)
        end
    end

    if durFS and durFS.SetFont then
        local cfg = component.db.textDuration or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
        local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
        pcall(durFS.SetDrawLayer, durFS, "OVERLAY", 10)
        if addon.ApplyFontStyle then addon.ApplyFontStyle(durFS, face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") else durFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") end
        local c = resolveCDMColor(cfg)
        if durFS.SetTextColor then durFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
        if durFS.SetJustifyH then pcall(durFS.SetJustifyH, durFS, "RIGHT") end
        local ox = (cfg.offset and cfg.offset.x) or 0
        local oy = (cfg.offset and cfg.offset.y) or 0
        if (ox ~= 0 or oy ~= 0) and durFS.ClearAllPoints and durFS.SetPoint then
            durFS:ClearAllPoints()
            local anchorTo = barFrame or child
            durFS:SetPoint("RIGHT", anchorTo, "RIGHT", ox, oy)
        end
    end

    local stacksFS
    if iconFrame and iconFrame.Applications then
        if iconFrame.Applications.GetObjectType and iconFrame.Applications:GetObjectType() == "FontString" then
            stacksFS = iconFrame.Applications
        else
            stacksFS = findFontStringOn(iconFrame.Applications)
        end
    end
    if not stacksFS and iconFrame then
        stacksFS = findFontStringByNameHint(iconFrame, "Applications")
    end
    if not stacksFS then
        stacksFS = findFontStringByNameHint(child, "Applications")
    end

    if stacksFS and stacksFS.SetFont then
        local cfg = component.db.textStacks or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
        local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
        pcall(stacksFS.SetDrawLayer, stacksFS, "OVERLAY", 10)
        if addon.ApplyFontStyle then addon.ApplyFontStyle(stacksFS, face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") else stacksFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") end
        local c = resolveCDMColor(cfg)
        if stacksFS.SetTextColor then stacksFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
        if stacksFS.SetJustifyH then pcall(stacksFS.SetJustifyH, stacksFS, "CENTER") end
        local ox = (cfg.offset and cfg.offset.x) or 0
        local oy = (cfg.offset and cfg.offset.y) or 0
        if stacksFS.ClearAllPoints and stacksFS.SetPoint then
            stacksFS:ClearAllPoints()
            local anchorTo = iconFrame or child
            stacksFS:SetPoint("CENTER", anchorTo, "CENTER", ox, oy)
        end
    end
end

--------------------------------------------------------------------------------
-- TrackedBars Hooks
--------------------------------------------------------------------------------

local trackedBarsHooked = false

local function scheduleVerticalRebuild(component)
    if vertRebuildPending then return end
    vertRebuildPending = true
    C_Timer.After(0, function()
        vertRebuildPending = false
        if verticalModeActive then
            applyVerticalMode(component)
        end
    end)
end

local function hookTrackedBars(component)
    if trackedBarsHooked then return end

    local frame = _G[component.frameName]
    if not frame then return end

    if frame.OnAcquireItemFrame then
        hooksecurefunc(frame, "OnAcquireItemFrame", function(viewer, itemFrame)
            -- Always install data mirror hooks (needed for vertical mode)
            installDataMirrorHooks(itemFrame)

            -- Hook visibility changes to refresh vertical layout when buffs activate/deactivate
            if not visHookedItems[itemFrame] and itemFrame.SetShown then
                hooksecurefunc(itemFrame, "SetShown", function()
                    if verticalModeActive then
                        scheduleVerticalRebuild(component)
                    end
                end)
                visHookedItems[itemFrame] = true
            end

            if InCombatLockdown and InCombatLockdown() then return end
            local mode = getTrackedBarMode()
            if mode == "vertical" then
                scheduleVerticalRebuild(component)
            else
                C_Timer.After(0, function()
                    if addon.ApplyTrackedBarVisualsForChild then
                        addon.ApplyTrackedBarVisualsForChild(component, itemFrame)
                    end
                end)
            end
        end)
    end

    if frame.RefreshLayout then
        hooksecurefunc(frame, "RefreshLayout", function()
            if InCombatLockdown and InCombatLockdown() then return end
            local mode = getTrackedBarMode()
            if mode == "vertical" then
                scheduleVerticalRebuild(component)
            else
                C_Timer.After(0, function()
                    if not addon or not addon.Components or not addon.Components.trackedBars then return end
                    local comp = addon.Components.trackedBars
                    local f = _G[comp.frameName]
                    if not f then return end
                    for _, child in ipairs({ f:GetChildren() }) do
                        if addon.ApplyTrackedBarVisualsForChild then
                            addon.ApplyTrackedBarVisualsForChild(comp, child)
                        end
                    end
                end)
            end
        end)
    end

    -- Hook Edit Mode for vertical mode support
    hookVertEditMode()

    trackedBarsHooked = true
end

--------------------------------------------------------------------------------
-- TrackedBars Component Registration
--------------------------------------------------------------------------------

local function TrackedBarsApplyStyling(component)
    local frame = _G[component.frameName]
    if not frame then return end

    hookTrackedBars(component)

    local mode = getTrackedBarMode()
    if mode == "vertical" then
        applyVerticalMode(component)
    else
        -- Default mode: remove vertical if active, apply overlay styling
        if verticalModeActive then
            removeVerticalMode()
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            if addon.ApplyTrackedBarVisualsForChild then
                addon.ApplyTrackedBarVisualsForChild(component, child)
            end
        end
    end
end

addon:RegisterComponentInitializer(function(self)
    local trackedBars = Component:New({
        id = "trackedBars",
        name = "Tracked Bars",
        frameName = "BuffBarCooldownViewer",
        settings = {
            barMode = { type = "addon", default = "default" },
            iconPadding = { type = "editmode", settingId = 4, default = 3, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 1
            }},
            iconBarPadding = { type = "addon", default = 0, ui = {
                label = "Icon/Bar Padding", widget = "slider", min = -20, max = 80, step = 1, section = "Positioning", order = 2
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 3
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 4
            }},
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Bar Scale", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            barWidth = { type = "editmode", settingId = 11, default = 100, ui = {
                label = "Bar Width", widget = "slider", min = 50, max = 200, step = 1, section = "Sizing", order = 2
            }},
            styleEnableCustom = { type = "addon", default = true, ui = {
                label = "Enable Custom Textures", widget = "checkbox", section = "Style", order = 0
            }},
            styleForegroundTexture = { type = "addon", default = "bevelled", ui = {
                label = "Foreground Texture", widget = "dropdown", section = "Style", order = 1, optionsProvider = function()
                    if addon.BuildBarTextureOptionsContainer then return addon.BuildBarTextureOptionsContainer() end
                    local c = Settings.CreateControlTextContainer(); c:Add("bevelled", "Bevelled"); return c:GetData()
                end
            }},
            styleBackgroundTexture = { type = "addon", default = "bevelled", ui = {
                label = "Background Texture", widget = "dropdown", section = "Style", order = 2, optionsProvider = function()
                    if addon.BuildBarTextureOptionsContainer then return addon.BuildBarTextureOptionsContainer() end
                    local c = Settings.CreateControlTextContainer(); c:Add("bevelledGrey", "Bevelled Grey"); return c:GetData()
                end
            }},
            styleForegroundColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Foreground Color", widget = "color", section = "Style", order = 3
            }},
            styleBackgroundColor = { type = "addon", default = {1,1,1,0.9}, ui = {
                label = "Background Color", widget = "color", section = "Style", order = 4
            }},
            styleBackgroundOpacity = { type = "addon", default = 50, ui = {
                label = "Background Opacity", widget = "slider", min = 0, max = 100, step = 1, section = "Style", order = 5
            }},
            borderEnable = { type = "addon", default = false, ui = {
                label = "Use Custom Border", widget = "checkbox", section = "Border", order = 1
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 4,
                optionsProvider = function()
                    if addon.BuildBarBorderOptionsContainer then
                        return addon.BuildBarBorderOptionsContainer()
                    end
                    return {}
                end,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 5
            }},
            borderInset = { type = "addon", default = 0, ui = {
                label = "Border Inset", widget = "slider", min = -4, max = 4, step = 1, section = "Border", order = 6
            }},
            iconTallWideRatio = { type = "addon", default = 0, ui = {
                label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Icon", order = 1
            }},
            iconBorderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Icon", order = 2
            }},
            iconBorderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Icon", order = 4
            }},
            iconBorderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Icon", order = 5
            }},
            iconBorderStyle = { type = "addon", default = "none", ui = {
                label = "Border Style", widget = "dropdown", section = "Icon", order = 6,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end
            }},
            iconBorderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Icon", order = 7
            }},
            iconBorderInset = { type = "addon", default = 0, ui = {
                label = "Border Inset", widget = "slider", min = -4, max = 4, step = 1, section = "Icon", order = 8
            }},
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            opacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 4
            }},
            displayMode = { type = "editmode", default = "both", ui = {
                label = "Display Mode", widget = "dropdown", values = { both = "Icon & Name", icon = "Icon Only", name = "Name Only" }, section = "Misc", order = 5
            }},
            hideWhenInactive = { type = "editmode", default = false, ui = {
                label = "Hide when inactive", widget = "checkbox", section = "Misc", order = 6
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 7
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 8
            }},
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = TrackedBarsApplyStyling,
    })
    self:RegisterComponent(trackedBars)
end)
