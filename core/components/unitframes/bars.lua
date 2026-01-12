--------------------------------------------------------------------------------
-- bars.lua
-- Unit Frame Bar Styling (Main File)
--
-- This file orchestrates bar styling for all unit frames. The functionality
-- has been modularized into separate files in the bars/ subdirectory:
--   - bars/utils.lua       - Shared utility functions
--   - bars/combat.lua      - Combat deferral systems
--   - bars/resolvers.lua   - Frame resolution helpers
--   - bars/textures.lua    - Texture application functions
--   - bars/alpha.lua       - Alpha enforcement helpers
--   - bars/preemptive.lua  - Pre-emptive hiding and early hooks
--   - bars/raidframes.lua  - Raid frame styling
--   - bars/partyframes.lua - Party frame styling
--------------------------------------------------------------------------------

local addonName, addon = ...
local Util = addon.ComponentsUtil
local CleanupIconBorderAttachments = Util.CleanupIconBorderAttachments
local ClampOpacity = Util.ClampOpacity
local PlayerInCombat = Util.PlayerInCombat
local HideDefaultBarTextures = Util.HideDefaultBarTextures
local ToggleDefaultIconOverlay = Util.ToggleDefaultIconOverlay

-- Reference extracted modules (loaded via TOC before this file)
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat
local Resolvers = addon.BarsResolvers
local Textures = addon.BarsTextures
local Alpha = addon.BarsAlpha
local Preemptive = addon.BarsPreemptive
local RaidFrames = addon.BarsRaidFrames
local PartyFrames = addon.BarsPartyFrames

--------------------------------------------------------------------------------
-- Local aliases to extracted module functions
-- These provide backward compatibility with code in this file
--------------------------------------------------------------------------------

local getUiScale = Utils.getUiScale
local pixelsToUiUnits = Utils.pixelsToUiUnits
local uiUnitsToPixels = Utils.uiUnitsToPixels
local clampScreenCoordinate = Utils.clampScreenCoordinate
local getFrameScreenOffsets = Utils.getFrameScreenOffsets

local queuePowerBarReapply = Combat.queuePowerBarReapply
local queueUnitFrameTextureReapply = Combat.queueUnitFrameTextureReapply
local queueRaidFrameReapply = Combat.queueRaidFrameReapply
local queuePartyFrameReapply = Combat.queuePartyFrameReapply

local function capturePowerBarBaseline(pb)
    if not pb then
        return
    end
    if not pb._ScootPowerBarOrigParent then
        pb._ScootPowerBarOrigParent = pb:GetParent()
    end
    if pb.SetIgnoreFramePositionManager and pb.IsIgnoringFramePositionManager then
        if pb._ScootPowerBarOrigIgnoreManager == nil then
            local ok, ignoring = pcall(pb.IsIgnoringFramePositionManager, pb)
            pb._ScootPowerBarOrigIgnoreManager = ok and ignoring or false
        end
    end
    if not pb._ScootPowerBarOrigPoints and pb.GetNumPoints then
        pb._ScootPowerBarOrigPoints = {}
        local numPoints = pb:GetNumPoints()
        for i = 1, numPoints do
            local point, relativeTo, relativePoint, xOfs, yOfs = pb:GetPoint(i)
            table.insert(pb._ScootPowerBarOrigPoints, { point, relativeTo, relativePoint, xOfs, yOfs })
        end
    end
end

local function restorePowerBarBaseline(pb)
    if not pb then
        return
    end
    -- Note: We do NOT re-parent. The frame stays with its original parent at all times.
    -- We only restore the layout manager state and original anchor points.
    if pb.SetIgnoreFramePositionManager then
        local desired = pb._ScootPowerBarOrigIgnoreManager
        if desired == nil then
            desired = false
        end
        pcall(pb.SetIgnoreFramePositionManager, pb, desired)
    end
    if pb._ScootPowerBarOrigPoints and pb.ClearAllPoints and pb.SetPoint then
        pcall(pb.ClearAllPoints, pb)
        for _, pt in ipairs(pb._ScootPowerBarOrigPoints) do
            pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
        end
    end

    -- Clear custom-position flags when restoring to baseline.
    pb._ScootPowerBarCustomPosEnabled = nil
    pb._ScootPowerBarCustomPosX = nil
    pb._ScootPowerBarCustomPosY = nil
    pb._ScootPowerBarCustomPosUnit = nil
end

local function ensurePowerBarCustomSeed(cfg, pb)
    if not cfg or not cfg.powerBarCustomPositionEnabled or not pb then
        return
    end
    -- Force 0,0 (screen center) for new users to avoid unexpected positioning
    -- Previously tried to seed from current frame position but this caused
    -- the bar to disappear on first enable due to coordinate conversion issues
    if cfg.powerBarPosX == nil then
        cfg.powerBarPosX = 0
    end
    if cfg.powerBarPosY == nil then
        cfg.powerBarPosY = 0
    end
end

-- Persistent custom-position enforcement:
-- Blizzard can reposition the Player ManaBar (e.g., via PlayerFrame_ToPlayerArt calling manaBar:SetPoint).
-- We install a hook on SetPoint to detect those resets and re-apply the custom position when allowed.
local function installPowerBarCustomPositionHook(pb)
    if not pb or pb._ScootPowerBarCustomPosHooked then
        return
    end
    pb._ScootPowerBarCustomPosHooked = true

    if not (_G.hooksecurefunc and pb.SetPoint) then
        return
    end

    _G.hooksecurefunc(pb, "SetPoint", function(self)
        if not self or not self._ScootPowerBarCustomPosEnabled then
            return
        end
        if self._ScootPowerBarSettingPoint then
            return
        end

        -- If we're in combat lockdown, do not attempt to move protected frames.
        -- Instead, queue a re-apply for when combat ends.
        if InCombatLockdown and InCombatLockdown() then
            queuePowerBarReapply(self._ScootPowerBarCustomPosUnit or "Player")
            return
        end

        local x = clampScreenCoordinate(self._ScootPowerBarCustomPosX or 0)
        local y = clampScreenCoordinate(self._ScootPowerBarCustomPosY or 0)

        self._ScootPowerBarSettingPoint = true
        if self.SetIgnoreFramePositionManager then
            pcall(self.SetIgnoreFramePositionManager, self, true)
        end
        if self.ClearAllPoints and self.SetPoint then
            pcall(self.ClearAllPoints, self)
            pcall(self.SetPoint, self, "CENTER", UIParent, "CENTER", pixelsToUiUnits(x), pixelsToUiUnits(y))
        end
        self._ScootPowerBarSettingPoint = nil
    end)
end

local function applyCustomPowerBarPosition(unit, pb, cfg)
    if unit ~= "Player" or not cfg or not pb then
        return false
    end
    if not cfg.powerBarCustomPositionEnabled then
        -- Restore original state when custom positioning is disabled.
        -- Important: clear custom-position flags even if we never successfully applied the move
        -- (e.g., custom enabled while in combat, then disabled before we could apply).
        if pb._ScootPowerBarCustomActive or pb._ScootPowerBarCustomPosEnabled then
            restorePowerBarBaseline(pb)
        end
        pb._ScootPowerBarCustomActive = nil
        return false
    end

    capturePowerBarBaseline(pb)
    ensurePowerBarCustomSeed(cfg, pb)

    local posX = clampScreenCoordinate(cfg.powerBarPosX or 0)
    local posY = clampScreenCoordinate(cfg.powerBarPosY or 0)

    -- Store custom-position state on the frame so the SetPoint hook can re-enforce it.
    pb._ScootPowerBarCustomPosEnabled = true
    pb._ScootPowerBarCustomPosX = posX
    pb._ScootPowerBarCustomPosY = posY
    pb._ScootPowerBarCustomPosUnit = unit
    installPowerBarCustomPositionHook(pb)

    if PlayerInCombat() then
        queuePowerBarReapply(unit)
        return true
    end

    -- POLICY COMPLIANT: Do NOT re-parent the frame. Instead:
    -- 1. Keep the frame parented where Blizzard placed it
    -- 2. Use SetIgnoreFramePositionManager to prevent layout manager from overriding
    -- 3. Anchor to UIParent for absolute screen positioning (frames CAN anchor to non-parents)
    -- This preserves scale, text styling, and all other customizations.
    pb._ScootPowerBarSettingPoint = true
    if pb.SetIgnoreFramePositionManager then
        pcall(pb.SetIgnoreFramePositionManager, pb, true)
    end
    if pb.ClearAllPoints and pb.SetPoint then
        pcall(pb.ClearAllPoints, pb)
        pcall(pb.SetPoint, pb, "CENTER", UIParent, "CENTER", pixelsToUiUnits(posX), pixelsToUiUnits(posY))
    end
    pb._ScootPowerBarSettingPoint = nil
    pb._ScootPowerBarCustomActive = true
    return true
end

-- Debug helper:
-- /scoot debug powerbarpos [simulate]
-- Shows current Player ManaBar points + ScooterMod custom-position state.
function addon.DebugPowerBarPosition(simulateReset)
    if not (addon and addon.DebugShowWindow) then
        return
    end

    local pb =
        _G.PlayerFrame
        and _G.PlayerFrame.PlayerFrameContent
        and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
        and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar

    local lines = {}
    local function push(s) table.insert(lines, tostring(s)) end

    push("InCombatLockdown=" .. tostring((InCombatLockdown and InCombatLockdown()) and true or false))
    push("PlayerInCombat=" .. tostring((PlayerInCombat and PlayerInCombat()) and true or false))
    push("PowerBarFound=" .. tostring(pb ~= nil))

    if not pb then
        addon.DebugShowWindow("Player Power Bar Position", table.concat(lines, "\n"))
        return
    end

    local okIgnore, ignoring = false, nil
    if pb.IsIgnoringFramePositionManager then
        okIgnore, ignoring = pcall(pb.IsIgnoringFramePositionManager, pb)
    end
    push("IsIgnoringFramePositionManager=" .. tostring(okIgnore and ignoring or "<n/a>"))

    push("_ScootPowerBarCustomActive=" .. tostring(pb._ScootPowerBarCustomActive and true or false))
    push("_ScootPowerBarCustomPosEnabled=" .. tostring(pb._ScootPowerBarCustomPosEnabled and true or false))
    push("_ScootPowerBarCustomPosX=" .. tostring(pb._ScootPowerBarCustomPosX))
    push("_ScootPowerBarCustomPosY=" .. tostring(pb._ScootPowerBarCustomPosY))
    push("_ScootPowerBarCustomPosUnit=" .. tostring(pb._ScootPowerBarCustomPosUnit))

    local sx, sy = getFrameScreenOffsets(pb)
    push(string.format("ScreenOffsetFromCenter(px)=%s,%s", tostring(sx), tostring(sy)))

    local function dumpPoints(header)
        push("")
        push(header)
        if not (pb.GetNumPoints and pb.GetPoint) then
            push("<no GetPoint API>")
            return
        end
        local okN, n = pcall(pb.GetNumPoints, pb)
        n = (okN and n) or 0
        push("NumPoints=" .. tostring(n))
        for i = 1, n do
            local ok, point, relTo, relPoint, xOfs, yOfs = pcall(pb.GetPoint, pb, i)
            if ok and point then
                local relName = "<nil>"
                if relTo and relTo.GetName then
                    local okName, nm = pcall(relTo.GetName, relTo)
                    if okName and nm and nm ~= "" then
                        relName = nm
                    else
                        relName = tostring(relTo)
                    end
                else
                    relName = tostring(relTo)
                end
                push(string.format("[%d] %s -> %s (%s) x=%s y=%s", i, tostring(point), tostring(relName), tostring(relPoint), tostring(xOfs), tostring(yOfs)))
            else
                push(string.format("[%d] <error>", i))
            end
        end
    end

    dumpPoints("Points (before)")

    if simulateReset then
        push("")
        push("SimulateReset=true")
        if InCombatLockdown and InCombatLockdown() then
            push("SimulateResetSkipped=InCombatLockdown")
        else
            -- Simulate Blizzard's default reset from PlayerFrame_ToPlayerArt / ToVehicleArt.
            if pb.ClearAllPoints and pb.SetPoint then
                pcall(pb.ClearAllPoints, pb)
                pcall(pb.SetPoint, pb, "TOPLEFT", 85, -61)
            else
                push("SimulateResetSkipped=<no ClearAllPoints/SetPoint>")
            end
        end

        dumpPoints("Points (after simulate)")
    end

    addon.DebugShowWindow("Player Power Bar Position", table.concat(lines, "\n"))
end

-- Unit Frames: Copy Health/Power Bar Style settings (texture, color mode, tint)
do
    function addon.CopyUnitFrameBarStyleSettings(sourceUnit, destUnit)
        local db = addon and addon.db and addon.db.profile
        if not db then return false end
        db.unitFrames = db.unitFrames or {}
        local src = db.unitFrames[sourceUnit]
        if not src then return false end
        db.unitFrames[destUnit] = db.unitFrames[destUnit] or {}
        local dst = db.unitFrames[destUnit]

        local function deepcopy(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for k, vv in pairs(v) do out[k] = deepcopy(vv) end
            return out
        end

        local keys = {
            "healthBarTexture",
            "healthBarColorMode",
            "healthBarTint",
            "healthBarBackgroundTexture",
            "healthBarBackgroundColorMode",
            "healthBarBackgroundTint",
            "healthBarBackgroundOpacity",
            "powerBarTexture",
            "powerBarColorMode",
            "powerBarTint",
            "powerBarBackgroundTexture",
            "powerBarBackgroundColorMode",
            "powerBarBackgroundTint",
            "powerBarBackgroundOpacity",
            "powerBarHideFullSpikes",
            "powerBarHideFeedback",
            "powerBarHidden",
        }
        for _, k in ipairs(keys) do
            if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
        end

        if addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor(destUnit) end
        return true
    end
end

-- Unit Frames: Apply custom bar textures (Health/Power) with optional tint per unit
do
    -- Use resolver functions from extracted module
    local getUnitFrameFor = Resolvers.getUnitFrameFor
    local resolveHealthBar = Resolvers.resolveHealthBar
    local resolveHealthContainer = Resolvers.resolveHealthContainer
    local resolvePowerBar = Resolvers.resolvePowerBar
    local resolveAlternatePowerBar = Resolvers.resolveAlternatePowerBar
    local resolveHealthMask = Resolvers.resolveHealthMask
    local resolvePowerMask = Resolvers.resolvePowerMask
    local resolveUFContentMain = Resolvers.resolveUFContentMain
    local resolveUnitFrameFrameTexture = Resolvers.resolveUnitFrameFrameTexture
    local resolveBossHealthMask = Resolvers.resolveBossHealthMask
    local resolveBossPowerMask = Resolvers.resolveBossPowerMask
    
    -- Use texture functions from extracted module
    local applyToBar = Textures.applyToBar
    local applyBackgroundToBar = Textures.applyBackgroundToBar
    local ensureMaskOnBarTexture = Textures.ensureMaskOnBarTexture
    
    -- Use alpha functions from extracted module
    local applyAlpha = Alpha.applyAlpha
    local hookAlphaEnforcer = Alpha.hookAlphaEnforcer

    -- Raise unit frame text layers so they always appear above any custom borders
    local function raiseUnitTextLayers(unit, targetLevel)
        -- Never touch protected unit frame hierarchy during combat; doing so taints
        -- later secure operations such as TargetFrameToT:Show().
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        local function safeSetDrawLayer(fs, layer, sub)
            if fs and fs.SetDrawLayer then pcall(fs.SetDrawLayer, fs, layer, sub) end
        end
        local function safeRaiseFrameLevel(frame, baseLevel, bump)
            if not frame then return end
            local cur = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
            local target = math.max(cur, (tonumber(baseLevel) or 0) + (tonumber(bump) or 0))
            if targetLevel and type(targetLevel) == "number" then
                if target < targetLevel then target = targetLevel end
            end
            if frame.SetFrameLevel then pcall(frame.SetFrameLevel, frame, target) end
        end
        if unit == "Pet" then
            safeSetDrawLayer(_G.PetFrameHealthBarText, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameHealthBarTextLeft, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameHealthBarTextRight, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameManaBarText, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameManaBarTextLeft, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameManaBarTextRight, "OVERLAY", 6)
            -- Bump parent levels above any border holder
            local hb = _G.PetFrameHealthBar
            local mb = _G.PetFrameManaBar
            local base = (hb and hb.GetFrameLevel and hb:GetFrameLevel()) or 0
            safeRaiseFrameLevel(hb, base, 12)
            safeRaiseFrameLevel(mb, base, 12)
            return
        end
        if unit == "Boss" then
            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                if bossFrame then
                    local hbContainer = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                    if hbContainer then
                        safeSetDrawLayer(hbContainer.HealthBarText, "OVERLAY", 6)
                        safeSetDrawLayer(hbContainer.LeftText, "OVERLAY", 6)
                        safeSetDrawLayer(hbContainer.RightText, "OVERLAY", 6)
                        local base = (hbContainer.GetFrameLevel and hbContainer:GetFrameLevel())
                            or (bossFrame.GetFrameLevel and bossFrame:GetFrameLevel()) or 0
                        safeRaiseFrameLevel(hbContainer, base, 12)
                    end

                    local mana = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.ManaBar
                    if mana then
                        safeSetDrawLayer(mana.ManaBarText, "OVERLAY", 6)
                        safeSetDrawLayer(mana.LeftText, "OVERLAY", 6)
                        safeSetDrawLayer(mana.RightText, "OVERLAY", 6)
                        local base = (mana.GetFrameLevel and mana:GetFrameLevel())
                            or (bossFrame.GetFrameLevel and bossFrame:GetFrameLevel()) or 0
                        safeRaiseFrameLevel(mana, base, 12)
                    end
                end
            end
            return
        end
        local root = (unit == "Player" and _G.PlayerFrame)
            or (unit == "Target" and _G.TargetFrame)
            or (unit == "Focus" and _G.FocusFrame) or nil
        if not root then return end
        -- Health texts
        local hbContainer = (unit == "Player" and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer)
            or (root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer)
        if hbContainer then
            safeSetDrawLayer(hbContainer.HealthBarText, "OVERLAY", 6)
            safeSetDrawLayer(hbContainer.LeftText, "OVERLAY", 6)
            safeSetDrawLayer(hbContainer.RightText, "OVERLAY", 6)
            local base = (hbContainer.GetFrameLevel and hbContainer:GetFrameLevel()) or ((root.GetFrameLevel and root:GetFrameLevel()) or 0)
            safeRaiseFrameLevel(hbContainer, base, 12)
        end
        -- Mana texts
        local mana
        if unit == "Player" then
            mana = root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
        else
            mana = root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.ManaBar
        end
        if mana then
            safeSetDrawLayer(mana.ManaBarText, "OVERLAY", 6)
            safeSetDrawLayer(mana.LeftText, "OVERLAY", 6)
            safeSetDrawLayer(mana.RightText, "OVERLAY", 6)
            local base = (mana.GetFrameLevel and mana:GetFrameLevel()) or ((root.GetFrameLevel and root:GetFrameLevel()) or 0)
            safeRaiseFrameLevel(mana, base, 12)
        end
    end

    -- Compute border holder level below current text and enforce ordering deterministically
    local function ensureTextAndBorderOrdering(unit)
        -- PetFrame is an Edit Mode managed/protected unit frame.
        -- Even out-of-combat frame-level/strata adjustments on PetFrame children can taint the frame
        -- and later cause protected Edit Mode methods (e.g., PetFrame:HideBase(), PetFrame:SetPointBase())
        -- to be blocked. Do not perform any ordering work for Pet.
        if unit == "Pet" then
            return
        end
        -- Guard against combat lockdown: raising frame levels on protected unit frames
        -- during combat will taint subsequent secure operations (see taint.log).
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        local root = (unit == "Player" and _G.PlayerFrame)
            or (unit == "Target" and _G.TargetFrame)
            or (unit == "Focus" and _G.FocusFrame)
            or (unit == "Pet" and _G.PetFrame) or nil
        if not root then return end
        local hb = resolveHealthBar(root, unit) or nil
        local hbContainer = resolveHealthContainer(root, unit) or nil
        local pb = resolvePowerBar(root, unit) or nil
        local manaContainer
        if unit == "Player" then
            manaContainer = root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar or nil
        else
            manaContainer = root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.ManaBar or nil
        end
        -- Determine bar level and desired ordering: bar < holder < text
        local barLevel = (hb and hb.GetFrameLevel and hb:GetFrameLevel()) or 0
        if pb and pb.GetFrameLevel then
            local pbl = pb:GetFrameLevel() or 0
            if pbl > barLevel then barLevel = pbl end
        end
        local curTextLevel = 0
        if hbContainer and hbContainer.GetFrameLevel then curTextLevel = math.max(curTextLevel, hbContainer:GetFrameLevel() or 0) end
        if manaContainer and manaContainer.GetFrameLevel then curTextLevel = math.max(curTextLevel, manaContainer:GetFrameLevel() or 0) end
        local desiredTextLevel = math.max(curTextLevel, barLevel + 2)
        -- Raise text containers above holder
        if hbContainer and hbContainer.SetFrameLevel then pcall(hbContainer.SetFrameLevel, hbContainer, desiredTextLevel) end
        if manaContainer and manaContainer.SetFrameLevel then pcall(manaContainer.SetFrameLevel, manaContainer, desiredTextLevel) end
        -- Keep text FontStrings at high overlay sublevel
        raiseUnitTextLayers(unit, desiredTextLevel)
        -- Place the textured border holder between bar and text
        do
            local holderLevel = math.max(1, desiredTextLevel - 1, barLevel + 1)
            local hHolder = hb and hb.ScooterStyledBorder or nil
            if hHolder and hHolder.SetFrameLevel then
                -- Lock desired level so internal size hooks won't raise it above text later
                hb._ScooterBorderFixedLevel = holderLevel
                pcall(hHolder.SetFrameLevel, hHolder, holderLevel)
            end
            -- Match holder strata to the text container's strata so frame level ordering decides (bar < holder < text)
            if hHolder and hHolder.SetFrameStrata then
                local s = (hbContainer and hbContainer.GetFrameStrata and hbContainer:GetFrameStrata())
                    or (hb and hb.GetFrameStrata and hb:GetFrameStrata())
                    or (root and root.GetFrameStrata and root:GetFrameStrata())
                    or "MEDIUM"
                pcall(hHolder.SetFrameStrata, hHolder, s)
            end
            local pHolder = pb and pb.ScooterStyledBorder or nil
            if pHolder and pHolder.SetFrameLevel then
                pb._ScooterBorderFixedLevel = holderLevel
                pcall(pHolder.SetFrameLevel, pHolder, holderLevel)
            end
            if pHolder and pHolder.SetFrameStrata then
                local s2 = (manaContainer and manaContainer.GetFrameStrata and manaContainer:GetFrameStrata())
                    or (pb and pb.GetFrameStrata and pb:GetFrameStrata())
                    or (root and root.GetFrameStrata and root:GetFrameStrata())
                    or "MEDIUM"
                pcall(pHolder.SetFrameStrata, pHolder, s2)
            end
            -- No overlay frame creation: respect stock-frame reuse policy
        end
        -- (experimental text reparent/strata bump removed; see HOLDING.md 2025-11-07)
    end

    -- Optional rectangular overlay for unit frame health bars when the portrait is hidden.
    -- This is used to visually "fill in" the right-side chip on Target/Focus when the
    -- circular portrait is hidden, without replacing the stock StatusBar frame.
    local function updateRectHealthOverlay(unit, bar)
        if not bar or not bar.ScooterRectFill then return end
        if not bar._ScootRectActive then
            bar.ScooterRectFill:Hide()
            return
        end

        local overlay = bar.ScooterRectFill
        local totalWidth = bar:GetWidth() or 0
        local minVal, maxVal = bar:GetMinMaxValues()
        local value = bar:GetValue() or minVal

        if not totalWidth or totalWidth <= 0 or not maxVal or maxVal <= minVal then
            overlay:Hide()
            return
        end

        local frac = (value - minVal) / (maxVal - minVal)
        if frac <= 0 then
            overlay:Hide()
            return
        end
        if frac > 1 then frac = 1 end

        overlay:Show()
        overlay:SetWidth(totalWidth * frac)
        overlay:ClearAllPoints()

        local reverse = not not bar._ScootRectReverseFill
        -- Overlay matches the bar frame bounds exactly.
        -- Any bleeding above the frame is covered by extending the border's expandY.
        local topOffset = 0

        if reverse then
            overlay:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, topOffset)
            overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        else
            overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, topOffset)
            overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        end
    end

    local function ensureRectHealthOverlay(unit, bar, cfg)
        if not bar then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end
        -- Zero‑Touch: do not create config tables. If this unit has no config, do nothing.
        local unitFrames = rawget(db, "unitFrames")
        local ufCfg = unitFrames and rawget(unitFrames, unit) or nil
        if not ufCfg then
            return
        end

        -- Determine whether overlay should be active based on unit type:
        -- - Target/Focus: activate when portrait is hidden (fills portrait cut-out on right side)
        -- - Player/TargetOfTarget: activate when using custom borders (fills top-right corner chip in mask)
        -- - Pet: activate when using custom borders (fills top-right corner chip in mask)
        local shouldActivate = false

        if unit == "Target" or unit == "Focus" then
            local portraitCfg = rawget(ufCfg, "portrait")
            shouldActivate = (portraitCfg and portraitCfg.hidePortrait == true) or false
            if cfg and cfg.healthBarReverseFill ~= nil then
                bar._ScootRectReverseFill = not not cfg.healthBarReverseFill
            end
        elseif unit == "Player" then
            shouldActivate = (ufCfg.useCustomBorders == true)
            bar._ScootRectReverseFill = false -- Player health bar always fills left-to-right
        elseif unit == "TargetOfTarget" then
            shouldActivate = (ufCfg.useCustomBorders == true)
            bar._ScootRectReverseFill = false -- ToT health bar always fills left-to-right
        elseif unit == "Pet" then
            -- PetFrame has a small top-right "chip" when we hide Blizzard's border textures
            -- and replace them with a custom border. Use the same overlay approach as Player/ToT.
            shouldActivate = (ufCfg.useCustomBorders == true)
            bar._ScootRectReverseFill = false -- Pet health bar always fills left-to-right
        else
            -- Others: skip
            if bar.ScooterRectFill then
                bar._ScootRectActive = false
                bar.ScooterRectFill:Hide()
            end
            return
        end

        bar._ScootRectActive = shouldActivate

        if not shouldActivate then
            if bar.ScooterRectFill then
                bar.ScooterRectFill:Hide()
            end
            return
        end

        if not bar.ScooterRectFill then
            local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 2)
            overlay:SetVertTile(false)
            overlay:SetHorizTile(false)
            overlay:SetTexCoord(0, 1, 0, 1)
            bar.ScooterRectFill = overlay

            -- Drive overlay width from the health bar's own value/size changes.
            -- NOTE: No combat guard needed here because updateRectHealthOverlay() only
            -- operates on ScooterRectFill (our own child texture), not Blizzard's
            -- protected StatusBar. Cosmetic operations on our own textures are safe.
            if _G.hooksecurefunc and not bar._ScootRectHooksInstalled then
                bar._ScootRectHooksInstalled = true
                _G.hooksecurefunc(bar, "SetValue", function(self)
                    updateRectHealthOverlay(unit, self)
                end)
                _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                    updateRectHealthOverlay(unit, self)
                end)
                if bar.HookScript then
                    bar:HookScript("OnSizeChanged", function(self)
                        updateRectHealthOverlay(unit, self)
                    end)
                end
            end
        end

        -- Copy the configured health bar texture/tint so the overlay visually matches.
        -- We use the CONFIGURED texture from the DB rather than reading from the bar,
        -- because GetTexture() can return a number (texture ID) instead of a string path
        -- after SetStatusBarTexture(), which caused the overlay to fall back to WHITE.
        local texKey = cfg.healthBarTexture or "default"
        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
        
        if resolvedPath then
            -- Custom texture configured - use the resolved path
            bar.ScooterRectFill:SetTexture(resolvedPath)
        else
            -- Default texture - try to copy from bar, with robust fallback
            -- CRITICAL: GetTexture() can return an atlas token STRING. Passing an atlas token
            -- to SetTexture() causes the entire spritesheet to render (see UNITFRAMES.md).
            -- We must check if the string is an atlas and use SetAtlas() instead.
            local tex = bar:GetStatusBarTexture()
            local applied = false
            if tex then
                -- First, try GetAtlas() which is the most reliable for atlas-backed textures
                local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
                if okAtlas and atlasName and atlasName ~= "" then
                    if bar.ScooterRectFill.SetAtlas then
                        pcall(bar.ScooterRectFill.SetAtlas, bar.ScooterRectFill, atlasName, true)
                        applied = true
                    end
                end
                
                if not applied then
                    local okTex, pathOrTex = pcall(tex.GetTexture, tex)
                    if okTex then
                        if type(pathOrTex) == "string" and pathOrTex ~= "" then
                            -- Check if this string is actually an atlas token
                            local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(pathOrTex) ~= nil
                            if isAtlas and bar.ScooterRectFill.SetAtlas then
                                -- Use SetAtlas to avoid spritesheet rendering
                                pcall(bar.ScooterRectFill.SetAtlas, bar.ScooterRectFill, pathOrTex, true)
                                applied = true
                            else
                                -- It's a file path, safe to use SetTexture
                                bar.ScooterRectFill:SetTexture(pathOrTex)
                                applied = true
                            end
                        elseif type(pathOrTex) == "number" and pathOrTex > 0 then
                            -- Texture ID - use it directly
                            bar.ScooterRectFill:SetTexture(pathOrTex)
                            applied = true
                        end
                    end
                end
            end
            
            -- Fallback to stock health bar atlas for this unit
            if not applied then
                local stockAtlas
                if unit == "Player" then
                    stockAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
                elseif unit == "Target" then
                    stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health"
                elseif unit == "Focus" then
                    stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health"
                elseif unit == "TargetOfTarget" then
                    stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- ToT shares party atlas
                elseif unit == "Pet" then
                    -- Best-effort fallback; if this atlas changes, the earlier "copy from bar" path should
                    -- still handle the real default correctly.
                    stockAtlas = "UI-HUD-UnitFrame-Pet-PortraitOn-Bar-Health"
                end
                if stockAtlas and bar.ScooterRectFill.SetAtlas then
                    pcall(bar.ScooterRectFill.SetAtlas, bar.ScooterRectFill, stockAtlas, true)
                elseif bar.ScooterRectFill.SetColorTexture then
                    -- Last resort: use green health color instead of white
                    bar.ScooterRectFill:SetColorTexture(0, 0.8, 0, 1)
                end
            end
        end

        -- Apply vertex color to match configured color mode
        local colorMode = cfg.healthBarColorMode or "default"
        local tint = cfg.healthBarTint
        local r, g, b, a = 1, 1, 1, 1
        if colorMode == "custom" and type(tint) == "table" then
            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
        elseif colorMode == "class" and addon.GetClassColorRGB then
            local cr, cg, cb = addon.GetClassColorRGB("player")
            r, g, b, a = cr or 1, cg or 1, cb or 1, 1
        elseif colorMode == "texture" then
            -- Preserve texture's original colors
            r, g, b, a = 1, 1, 1, 1
        elseif colorMode == "default" then
            -- For default color, try to get the bar's current vertex color
            local tex = bar:GetStatusBarTexture()
            if tex and tex.GetVertexColor then
                local ok, vr, vg, vb, va = pcall(tex.GetVertexColor, tex)
                if ok then
                    r, g, b, a = vr or 1, vg or 1, vb or 1, va or 1
                end
            end
        end
        if bar.ScooterRectFill.SetVertexColor then
            bar.ScooterRectFill:SetVertexColor(r, g, b, a)
        end

        updateRectHealthOverlay(unit, bar)
    end

    -- Expose helpers for other modules (Cast Bar styling, etc.)
    addon._ApplyToStatusBar = applyToBar
    addon._ApplyBackgroundToStatusBar = applyBackgroundToBar

    local function applyForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        -- Zero‑Touch: do not create config tables. If this unit has no config, do nothing.
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end

        -- Zero‑Touch: only apply when at least one bar-related setting is explicitly configured.
        local function hasAnyKey(tbl, keys)
            if not tbl then return false end
            for i = 1, #keys do
                if tbl[keys[i]] ~= nil then return true end
            end
            return false
        end
        local hasAnyBarSetting =
            hasAnyKey(cfg, {
                "useCustomBorders",
                "healthBarTexture", "healthBarColorMode", "healthBarTint",
                "healthBarBackgroundTexture", "healthBarBackgroundColorMode", "healthBarBackgroundTint", "healthBarBackgroundOpacity",
                "powerBarTexture", "powerBarColorMode", "powerBarTint",
                "powerBarBackgroundTexture", "powerBarBackgroundColorMode", "powerBarBackgroundTint", "powerBarBackgroundOpacity",
                "borderStyle", "borderThickness", "borderInset", "borderTintEnable", "borderTintColor",
                "healthBarReverseFill",
            })
        local altCfg = rawget(cfg, "altPowerBar")
        if not hasAnyBarSetting and not hasAnyKey(altCfg, { "enabled", "width", "height", "x", "y", "fontFace", "size", "style", "color", "alignment" }) then
            return
        end
        local frame = getUnitFrameFor(unit)
        if not frame then return end

        -- Boss unit frames commonly appear/update during combat (e.g., INSTANCE_ENCOUNTER_ENGAGE_UNIT / UPDATE_BOSS_FRAMES).
        -- We must NEVER touch protected StatusBars/layout during combat, but we CAN safely hide purely-visual overlays
        -- via SetAlpha + alpha enforcers. Do this BEFORE the combat early-return so "Hide Blizzard Frame Art & Animations"
        -- works immediately and persistently for Boss frames.
        if unit == "Boss" then
            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                if bossFrame then
                    -- FrameTexture (hide for useCustomBorders OR healthBarHideBorder)
                    local bossFT = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.FrameTexture
                    if bossFT then
                        local function computeBossFTAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            local hide = cfgBoss and (cfgBoss.useCustomBorders or cfgBoss.healthBarHideBorder)
                            return hide and 0 or 1
                        end
                        applyAlpha(bossFT, computeBossFTAlpha())
                        hookAlphaEnforcer(bossFT, computeBossFTAlpha)
                    end

                    -- Flash (aggro/threat glow) (hide for useCustomBorders)
                    local bossFlash = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.Flash
                    if bossFlash then
                        local function computeBossFlashAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
                        end
                        applyAlpha(bossFlash, computeBossFlashAlpha())
                        hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
                    end

                    -- ReputationColor strip (hide for useCustomBorders)
                    local bossReputationColor = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                    if bossReputationColor then
                        local function computeBossRepAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
                        end
                        applyAlpha(bossReputationColor, computeBossRepAlpha())
                        hookAlphaEnforcer(bossReputationColor, computeBossRepAlpha)
                    end
                end
            end
        end

        -- Target/Focus frames can be updated/rebuilt by Blizzard during combat (rapid target swaps, faction updates, etc.).
        -- We must NEVER touch protected StatusBars/layout during combat, but we CAN safely enforce visual-only overlays
        -- (like ReputationColor) via SetAlpha + alpha enforcers. Do this BEFORE the combat early-return so the element
        -- stays hidden even if Blizzard recreates the region while we're in combat.
        --
        -- IMPORTANT: Blizzard may recreate the ReputationColor texture during rapid target changes. We must:
        -- 1. Always apply alpha (even if _ScootAlphaEnforcerHooked is set on an old object)
        -- 2. Always try to install enforcer (it will skip if already hooked on THIS object)
        -- 3. Schedule a follow-up re-hide to catch late Blizzard updates
        if unit == "Target" or unit == "Focus" then
            local function computeUseCustomBordersAlpha()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                return (cfg2 and cfg2.useCustomBorders) and 0 or 1
            end

            local reputationColor
            if unit == "Target" and _G.TargetFrame then
                reputationColor = _G.TargetFrame.TargetFrameContent
                    and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                    and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            elseif unit == "Focus" and _G.FocusFrame then
                reputationColor = _G.FocusFrame.TargetFrameContent
                    and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                    and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            end

            if reputationColor then
                -- Always apply current alpha, regardless of hook state
                local desiredAlpha = computeUseCustomBordersAlpha()
                applyAlpha(reputationColor, desiredAlpha)
                hookAlphaEnforcer(reputationColor, computeUseCustomBordersAlpha)
                
                -- Belt-and-suspenders: schedule a follow-up re-hide after Blizzard's updates complete
                -- This catches cases where Blizzard resets alpha after our initial hide
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        -- Re-resolve in case the texture object changed
                        local repColor2
                        if unit == "Target" and _G.TargetFrame then
                            repColor2 = _G.TargetFrame.TargetFrameContent
                                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                        elseif unit == "Focus" and _G.FocusFrame then
                            repColor2 = _G.FocusFrame.TargetFrameContent
                                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                        end
                        if repColor2 and repColor2.SetAlpha then
                            local alpha2 = computeUseCustomBordersAlpha()
                            pcall(repColor2.SetAlpha, repColor2, alpha2)
                            -- Install enforcer on the (possibly new) object
                            hookAlphaEnforcer(repColor2, computeUseCustomBordersAlpha)
                        end
                    end)
                end
            end
        end

        -- Combat safety: do not touch protected unit frame bars during combat. Queue a post-combat reapply.
        if InCombatLockdown and InCombatLockdown() then
            queueUnitFrameTextureReapply(unit)
            return
        end

        -- Target-of-Target can get refreshed frequently by Blizzard (even out of combat),
        -- which can reset its bar textures. Install a lightweight, throttled hook on the
        -- ToT frame's Update() to re-assert our styling shortly after Blizzard updates it.
        if unit == "TargetOfTarget" and _G.hooksecurefunc then
            local tot = _G.TargetFrameToT
            if tot and not tot._ScootToTUpdateHooked and type(tot.Update) == "function" then
                tot._ScootToTUpdateHooked = true
                _G.hooksecurefunc(tot, "Update", function()
                    local db2 = addon and addon.db and addon.db.profile
                    if not db2 then return end
                    local unitFrames2 = rawget(db2, "unitFrames")
                    local cfgT = unitFrames2 and rawget(unitFrames2, "TargetOfTarget") or nil
                    if not cfgT then
                        return
                    end

                    local texKey = cfgT.healthBarTexture or "default"
                    local colorMode = cfgT.healthBarColorMode or "default"
                    local tint = cfgT.healthBarTint

                    local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                    local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                    if not hasCustomTexture and not hasCustomColor then
                        return
                    end

                    if InCombatLockdown and InCombatLockdown() then
                        queueUnitFrameTextureReapply("TargetOfTarget")
                        return
                    end

                    if tot._ScootToTReapplyPending then
                        return
                    end
                    tot._ScootToTReapplyPending = true

                    if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                        _G.C_Timer.After(0, function()
                            tot._ScootToTReapplyPending = nil
                            addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                        end)
                    elseif addon.ApplyUnitFrameBarTexturesFor then
                        tot._ScootToTReapplyPending = nil
                        addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                    end
                end)
            end
        end

        -- Boss frames: apply to Boss1..Boss5 frames (shared config: db.unitFrames.Boss), then return.
        -- Boss frames are individual TargetFrame variants and are NOT the same as the EditMode system frame.
        if unit == "Boss" then
            local function resolveBossHealthMask(bossFrame)
                -- Get mask from the health bar's parent container (HealthBarsContainer)
                local hb = bossFrame and bossFrame.healthbar
                if hb then
                    local parent = hb:GetParent()
                    if parent and parent.HealthBarMask then return parent.HealthBarMask end
                end
                return nil
            end
            local function resolveBossPowerMask(bossFrame)
                -- Get mask from the mana bar directly
                local mb = bossFrame and bossFrame.manabar
                if mb and mb.ManaBarMask then return mb.ManaBarMask end
                return nil
            end

            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                local unitId = "boss" .. i
                -- Apply styling whenever the frame exists. Let resolveHealthBar/resolvePowerBar
                -- handle finding the actual bars within the frame structure.
                if bossFrame then
                    local hb = resolveHealthBar(bossFrame, unit)
                        if hb then
                            local colorModeHB = cfg.healthBarColorMode or "default"
                            local texKeyHB = cfg.healthBarTexture or "default"
                            applyToBar(hb, texKeyHB, colorModeHB, cfg.healthBarTint, "player", "health", unitId)

                            -- Background overlay (only when explicitly customized)
                            do
                                local function hasBackgroundCustomization()
                                    local texKey = cfg.healthBarBackgroundTexture
                                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                                        return true
                                    end
                                    local mode = cfg.healthBarBackgroundColorMode
                                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                                        return true
                                    end
                                    local op = cfg.healthBarBackgroundOpacity
                                    local opNum = tonumber(op)
                                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                                        return true
                                    end
                                    if mode == "custom" and type(cfg.healthBarBackgroundTint) == "table" then
                                        return true
                                    end
                                    return false
                                end
                                if hasBackgroundCustomization() then
                                    local bgTexKeyHB = cfg.healthBarBackgroundTexture or "default"
                                    local bgColorModeHB = cfg.healthBarBackgroundColorMode or "default"
                                    local bgOpacityHB = cfg.healthBarBackgroundOpacity or 50
                                    applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
                                end
                            end

                            ensureMaskOnBarTexture(hb, resolveBossHealthMask(bossFrame))

                            -- Health Bar custom border (same settings as other unit frames)
                            do
                                local styleKey = cfg.healthBarBorderStyle
                                local tintEnabled = not not cfg.healthBarBorderTintEnable
                                local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
                                    cfg.healthBarBorderTintColor[1] or 1,
                                    cfg.healthBarBorderTintColor[2] or 1,
                                    cfg.healthBarBorderTintColor[3] or 1,
                                    cfg.healthBarBorderTintColor[4] or 1,
                                } or {1, 1, 1, 1}
                                local thickness = tonumber(cfg.healthBarBorderThickness) or 1
                                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                                local inset = tonumber(cfg.healthBarBorderInset) or 0
					-- PetFrame is managed/protected: do not create or level custom border frames.
					if unit ~= "Pet" and cfg.useCustomBorders then
                                    if styleKey == "none" or styleKey == nil then
                                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(hb) end
                                    else
                                        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                        local color
                                        if tintEnabled then
                                            color = tintColor
                                        else
                                            if styleDef then
                                                color = {1, 1, 1, 1}
                                            else
                                                color = {0, 0, 0, 1}
                                            end
                                        end
                                        local handled = false
                                        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                                            if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                            handled = addon.BarBorders.ApplyToBarFrame(hb, styleKey, {
                                                color = color,
                                                thickness = thickness,
                                                levelOffset = 1,
                                                containerParent = (hb and hb:GetParent()) or nil,
                                                inset = inset,
                                            })
                                        end
                                        if not handled then
                                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                            if addon.Borders and addon.Borders.ApplySquare then
                                                local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                                local baseY = 1
                                                local baseX = 1
                                                local expandY = baseY - inset
                                                local expandX = baseX - inset
                                                if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                                if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                                addon.Borders.ApplySquare(hb, {
                                                    size = thickness,
                                                    color = sqColor,
                                                    layer = "OVERLAY",
                                                    layerSublevel = 3,
                                                    expandX = expandX,
                                                    expandY = expandY,
                                                })
                                            end
                                        end
                                        ensureTextAndBorderOrdering(unit)
                                    end
                                else
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(hb) end
                                end
                            end

                            -- Boss frames can get refreshed by Blizzard (HealthUpdate, Update) which resets textures.
                            -- Install a hook to re-assert our styling after Blizzard updates.
                            if _G.hooksecurefunc and not bossFrame._ScootBossHealthUpdateHooked then
                                local function installBossHealthHook(hookTarget, hookName)
                                    if hookTarget and type(hookTarget[hookName]) == "function" then
                                        bossFrame._ScootBossHealthUpdateHooked = true
                                        _G.hooksecurefunc(hookTarget, hookName, function()
                                            local db2 = addon and addon.db and addon.db.profile
                                            if not db2 then return end
                                            local unitFrames2 = rawget(db2, "unitFrames")
                                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                            if not cfgBoss then return end

                                            local texKey = cfgBoss.healthBarTexture or "default"
                                            local colorMode = cfgBoss.healthBarColorMode or "default"
                                            local tint = cfgBoss.healthBarTint

                                            local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                            local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                                            if not hasCustomTexture and not hasCustomColor then return end

                                            -- Throttle: skip if a reapply is already pending for this frame
                                            if bossFrame._ScootBossReapplyPending then return end
                                            bossFrame._ScootBossReapplyPending = true

                                            -- Defer to next frame to let Blizzard finish its updates
                                            if _G.C_Timer and _G.C_Timer.After then
                                                _G.C_Timer.After(0, function()
                                                    bossFrame._ScootBossReapplyPending = nil
                                                    -- Use direct property (most reliable)
                                                    local hbReapply = bossFrame.healthbar
                                                    if hbReapply then
                                                        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
                                                        if resolvedPath and hbReapply.SetStatusBarTexture then
                                                            pcall(hbReapply.SetStatusBarTexture, hbReapply, resolvedPath)
                                                        end
                                                        -- Reapply color
                                                        local tex = hbReapply:GetStatusBarTexture()
                                                        if tex and tex.SetVertexColor then
                                                            local r, g, b, a = 1, 1, 1, 1
                                                            if colorMode == "custom" and type(tint) == "table" then
                                                                r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
                                                            elseif colorMode == "class" and addon.GetClassColorRGB then
                                                                local cr, cg, cb = addon.GetClassColorRGB("player")
                                                                r, g, b = cr or 1, cg or 1, cb or 1
                                                            elseif colorMode == "texture" then
                                                                r, g, b, a = 1, 1, 1, 1
                                                            elseif colorMode == "default" and addon.GetDefaultHealthColorRGB then
                                                                local hr, hg, hb = addon.GetDefaultHealthColorRGB()
                                                                r, g, b = hr or 0, hg or 1, hb or 0
                                                            end
                                                            pcall(tex.SetVertexColor, tex, r, g, b, a)
                                                        end
                                                    end
                                                end)
                                            end
                                        end)
                                        return true
                                    end
                                    return false
                                end
                                -- Try HealthUpdate first (more targeted), fall back to Update
                                if not installBossHealthHook(bossFrame, "HealthUpdate") then
                                    installBossHealthHook(bossFrame, "Update")
                                end
                            end
                        end

                        local pb = resolvePowerBar(bossFrame, unit)
                        if pb then
                            local powerBarHidden = (cfg.powerBarHidden == true)
                            local powerBarHideTextureOnly = (cfg.powerBarHideTextureOnly == true)

                            if pb.GetAlpha and pb._ScootUFOrigPBAlpha == nil then
                                local ok, a = pcall(pb.GetAlpha, pb)
                                pb._ScootUFOrigPBAlpha = ok and (a or 1) or 1
                            end

                            if powerBarHidden then
                                if pb.SetAlpha then pcall(pb.SetAlpha, pb, 0) end
                                if pb.ScooterModBG and pb.ScooterModBG.SetAlpha then pcall(pb.ScooterModBG.SetAlpha, pb.ScooterModBG, 0) end
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, false) end
                            elseif powerBarHideTextureOnly then
                                if pb._ScootUFOrigPBAlpha and pb.SetAlpha then pcall(pb.SetAlpha, pb, pb._ScootUFOrigPBAlpha) end
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, true) end
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                            else
                                if pb._ScootUFOrigPBAlpha and pb.SetAlpha then pcall(pb.SetAlpha, pb, pb._ScootUFOrigPBAlpha) end
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, false) end
                            end

                            local colorModePB = cfg.powerBarColorMode or "default"
                            local texKeyPB = cfg.powerBarTexture or "default"
                            applyToBar(pb, texKeyPB, colorModePB, cfg.powerBarTint, "player", "power", unitId)

                            do
                                local function hasBackgroundCustomization()
                                    local texKey = cfg.powerBarBackgroundTexture
                                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                                        return true
                                    end
                                    local mode = cfg.powerBarBackgroundColorMode
                                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                                        return true
                                    end
                                    local op = cfg.powerBarBackgroundOpacity
                                    local opNum = tonumber(op)
                                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                                        return true
                                    end
                                    if mode == "custom" and type(cfg.powerBarBackgroundTint) == "table" then
                                        return true
                                    end
                                    return false
                                end
                                if hasBackgroundCustomization() then
                                    local bgTexKeyPB = cfg.powerBarBackgroundTexture or "default"
                                    local bgColorModePB = cfg.powerBarBackgroundColorMode or "default"
                                    local bgOpacityPB = cfg.powerBarBackgroundOpacity or 50
                                    applyBackgroundToBar(pb, bgTexKeyPB, bgColorModePB, cfg.powerBarBackgroundTint, bgOpacityPB, unit, "power")
                                end
                            end

                            if powerBarHideTextureOnly and not powerBarHidden then
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, true) end
                            end

                            ensureMaskOnBarTexture(pb, resolveBossPowerMask(bossFrame))

                            -- Power Bar custom border (mirrors Health Bar border settings; supports power-specific overrides)
                            do
                                local styleKey = cfg.powerBarBorderStyle or cfg.healthBarBorderStyle
                                local tintEnabled
                                if cfg.powerBarBorderTintEnable ~= nil then
                                    tintEnabled = not not cfg.powerBarBorderTintEnable
                                else
                                    tintEnabled = not not cfg.healthBarBorderTintEnable
                                end
                                local baseTint = type(cfg.powerBarBorderTintColor) == "table" and cfg.powerBarBorderTintColor or cfg.healthBarBorderTintColor
                                local tintColor = type(baseTint) == "table" and {
                                    baseTint[1] or 1,
                                    baseTint[2] or 1,
                                    baseTint[3] or 1,
                                    baseTint[4] or 1,
                                } or {1, 1, 1, 1}
                                local thickness = tonumber(cfg.powerBarBorderThickness) or tonumber(cfg.healthBarBorderThickness) or 1
                                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                                local inset = (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInset) or 0
                                if cfg.useCustomBorders then
                                    if styleKey == "none" or styleKey == nil then
                                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                                    else
                                        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                        local color
                                        if tintEnabled then
                                            color = tintColor
                                        else
                                            if styleDef then
                                                color = {1, 1, 1, 1}
                                            else
                                                color = {0, 0, 0, 1}
                                            end
                                        end
                                        local handled = false
                                        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                                            if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                            handled = addon.BarBorders.ApplyToBarFrame(pb, styleKey, {
                                                color = color,
                                                thickness = thickness,
                                                levelOffset = 1,
                                                containerParent = (pb and pb:GetParent()) or nil,
                                                inset = inset,
                                            })
                                        end
                                        if not handled then
                                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                            if addon.Borders and addon.Borders.ApplySquare then
                                                local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                                local baseY = (thickness <= 1) and 0 or 1
                                                local baseX = 1
                                                local expandY = baseY - inset
                                                local expandX = baseX - inset
                                                if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                                if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                                addon.Borders.ApplySquare(pb, {
                                                    size = thickness,
                                                    color = sqColor,
                                                    layer = "OVERLAY",
                                                    layerSublevel = 3,
                                                    expandX = expandX,
                                                    expandY = expandY,
                                                })
                                            end
                                        end
                                        ensureTextAndBorderOrdering(unit)
                                    end
                                else
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                                end
                            end

                            -- Boss power bars can get refreshed by Blizzard which resets textures.
                            -- Install a hook to re-assert our styling after Blizzard updates.
                            if _G.hooksecurefunc and not bossFrame._ScootBossPowerUpdateHooked then
                                bossFrame._ScootBossPowerUpdateHooked = true
                                -- Hook the power bar's SetValue which is called on every power change
                                if pb.SetValue and type(pb.SetValue) == "function" then
                                    _G.hooksecurefunc(pb, "SetValue", function()
                                        local db2 = addon and addon.db and addon.db.profile
                                        if not db2 then return end
                                        local unitFrames2 = rawget(db2, "unitFrames")
                                        local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                        if not cfgBoss then return end

                                        local texKey = cfgBoss.powerBarTexture or "default"
                                        local colorMode = cfgBoss.powerBarColorMode or "default"
                                        local tint = cfgBoss.powerBarTint

                                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                                        if not hasCustomTexture and not hasCustomColor then return end

                                        -- Throttle: skip if a reapply is already pending
                                        if bossFrame._ScootBossPowerReapplyPending then return end
                                        bossFrame._ScootBossPowerReapplyPending = true

                                        if _G.C_Timer and _G.C_Timer.After then
                                            _G.C_Timer.After(0, function()
                                                bossFrame._ScootBossPowerReapplyPending = nil
                                                local pbReapply = bossFrame.manabar
                                                if pbReapply then
                                                    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
                                                    if resolvedPath and pbReapply.SetStatusBarTexture then
                                                        pcall(pbReapply.SetStatusBarTexture, pbReapply, resolvedPath)
                                                    end
                                                    local tex = pbReapply:GetStatusBarTexture()
                                                    if tex and tex.SetVertexColor then
                                                        local r, g, b, a = 1, 1, 1, 1
                                                        if colorMode == "custom" and type(tint) == "table" then
                                                            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
                                                        elseif colorMode == "class" and addon.GetClassColorRGB then
                                                            local cr, cg, cb = addon.GetClassColorRGB("player")
                                                            r, g, b = cr or 1, cg or 1, cb or 1
                                                        elseif colorMode == "texture" then
                                                            r, g, b, a = 1, 1, 1, 1
                                                        end
                                                        pcall(tex.SetVertexColor, tex, r, g, b, a)
                                                    end
                                                end
                                            end)
                                        end
                                    end)
                                end
                            end
                        end
                end
            end

            -- Boss frame art: Handle all 5 Boss frames (Boss1TargetFrame through Boss5TargetFrame)
            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                if bossFrame and bossFrame.TargetFrameContainer then
                    local bossFT = bossFrame.TargetFrameContainer.FrameTexture
                    if bossFT then
                        local function computeBossAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            local hide = cfgBoss and (cfgBoss.useCustomBorders or cfgBoss.healthBarHideBorder)
                            return hide and 0 or 1
                        end
                        applyAlpha(bossFT, computeBossAlpha())
                        hookAlphaEnforcer(bossFT, computeBossAlpha)
                    end
                    -- Also hide the Flash (aggro/threat glow) if present on Boss frames
                    local bossFlash = bossFrame.TargetFrameContainer.Flash
                    if bossFlash then
                        local function computeBossFlashAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
                        end
                        applyAlpha(bossFlash, computeBossFlashAlpha())
                        hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
                    end
                end
            end

            return
        end

        local hb = resolveHealthBar(frame, unit)
        if hb then
            local colorModeHB = cfg.healthBarColorMode or "default"
            local texKeyHB = cfg.healthBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or "player"
			-- Avoid applying styling to Target/Focus/ToT before they exist; Blizzard will reset sizes on first Update
			if (unit == "Target" or unit == "Focus" or unit == "TargetOfTarget") and _G.UnitExists and not _G.UnitExists(unitId) then
				return
			end
            applyToBar(hb, texKeyHB, colorModeHB, cfg.healthBarTint, "player", "health", unitId)
            
            -- Apply background texture and color for Health Bar
            do
                -- IMPORTANT: Default/clean profiles should not change the look of Blizzard's bars.
                -- Only apply our background overlay if the user actually customized background settings.
                local function hasBackgroundCustomization()
                    local texKey = cfg.healthBarBackgroundTexture
                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                        return true
                    end
                    local mode = cfg.healthBarBackgroundColorMode
                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                        return true
                    end
                    local op = cfg.healthBarBackgroundOpacity
                    local opNum = tonumber(op)
                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                        return true
                    end
                    if mode == "custom" and type(cfg.healthBarBackgroundTint) == "table" then
                        return true
                    end
                    return false
                end
                if hasBackgroundCustomization() then
                    local bgTexKeyHB = cfg.healthBarBackgroundTexture or "default"
                    local bgColorModeHB = cfg.healthBarBackgroundColorMode or "default"
                    local bgOpacityHB = cfg.healthBarBackgroundOpacity or 50
                    applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
                end
            end
			-- When Target/Focus portraits are hidden, draw a rectangular overlay that fills the
			-- right-side "chip" area using the same texture/tint as the health bar.
			ensureRectHealthOverlay(unit, hb, cfg)
            -- If restoring default texture and we lack a captured original, restore to the known stock atlas for this unit
            local isDefaultHB = (texKeyHB == "default" or not addon.Media.ResolveBarTexturePath(texKeyHB))
            if isDefaultHB and not hb._ScootUFOrigAtlas and not hb._ScootUFOrigPath then
				local stockAtlas
				if unit == "Player" then
					stockAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
				elseif unit == "Target" then
					stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health"
				elseif unit == "Focus" then
					stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health" -- Focus reuses Target visuals
				elseif unit == "Pet" then
					stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- Pet frame shares party atlas
				elseif unit == "TargetOfTarget" then
					stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- ToT shares party atlas
				end
                if stockAtlas then
                    local hbTex = hb.GetStatusBarTexture and hb:GetStatusBarTexture()
                    if hbTex and hbTex.SetAtlas then pcall(hbTex.SetAtlas, hbTex, stockAtlas, true) end
					-- Best-effort: ensure the mask uses the matching atlas
					local mask = resolveHealthMask(unit)
					if mask and mask.SetAtlas then
						local maskAtlas
						if unit == "Player" then
							maskAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask"
						elseif unit == "Target" or unit == "Focus" then
							maskAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask"
						elseif unit == "Pet" then
							maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask"
						elseif unit == "TargetOfTarget" then
							maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask" -- ToT shares party mask
						end
						if maskAtlas then pcall(mask.SetAtlas, mask, maskAtlas) end
					end
				end
			end
			ensureMaskOnBarTexture(hb, resolveHealthMask(unit))
            
            -- Apply reverse fill for Target/Focus if configured
            if (unit == "Target" or unit == "Focus") and hb and hb.SetReverseFill then
                local shouldReverse = not not cfg.healthBarReverseFill
                pcall(hb.SetReverseFill, hb, shouldReverse)
            end
            
            -- Hide/Show Over Absorb Glow (Player only)
            -- Frame: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar.OverAbsorbGlow
            if unit == "Player" and hb and Util and Util.SetOverAbsorbGlowHidden then
                Util.SetOverAbsorbGlowHidden(hb, cfg.healthBarHideOverAbsorbGlow == true)
            end
            
            -- Health Bar custom border (Health Bar only)
            do
				local styleKey = cfg.healthBarBorderStyle
				local tintEnabled = not not cfg.healthBarBorderTintEnable
				local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
					cfg.healthBarBorderTintColor[1] or 1,
					cfg.healthBarBorderTintColor[2] or 1,
					cfg.healthBarBorderTintColor[3] or 1,
					cfg.healthBarBorderTintColor[4] or 1,
				} or {1, 1, 1, 1}
                local thickness = tonumber(cfg.healthBarBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                local inset = tonumber(cfg.healthBarBorderInset) or 0
				-- Only draw custom border when Use Custom Borders is enabled
				if hb then
					if cfg.useCustomBorders then
						-- Handle style = "none" to explicitly clear any custom border
						if styleKey == "none" or styleKey == nil then
							if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
							if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(hb) end
						else
							-- Match Tracked Bars: when tint is disabled use white for textured styles,
							-- and black only for the pixel fallback case.
							local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
							local color
							if tintEnabled then
								color = tintColor
							else
								if styleDef then
									color = {1, 1, 1, 1}
								else
									color = {0, 0, 0, 1}
								end
							end
                            local handled = false
                            if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
								-- Clear any prior holder/state to avoid stale tinting when toggling
								if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                handled = addon.BarBorders.ApplyToBarFrame(hb, styleKey, {
                                    color = color,
                                    thickness = thickness,
                                    levelOffset = 1, -- just above bar fill; text will be raised above holder
                                    containerParent = (hb and hb:GetParent()) or nil,
                                    inset = inset,
                                })
							end
                            if not handled then
								-- Fallback: pixel (square) border drawn with our lightweight helper
								if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                if addon.Borders and addon.Borders.ApplySquare then
									local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                    -- Always extend border by 1 pixel to cover any texture bleeding above the frame
                                    local baseY = 1
                                    local baseX = 1
                                    local expandY = baseY - inset
                                    local expandX = baseX - inset
                                    if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                    if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                    addon.Borders.ApplySquare(hb, {
										size = thickness,
										color = sqColor,
                                        layer = "OVERLAY",
                                        layerSublevel = 3,
										expandX = expandX,
										expandY = expandY,
									})
                                end
							end
                            -- Deterministically place border below text and ensure text wins
                            ensureTextAndBorderOrdering(unit)
                            -- Light hook: keep ordering stable on bar resize
                            if hb and not hb._ScootUFZOrderHooked and hb.HookScript then
                                hb:HookScript("OnSizeChanged", function()
                                    if InCombatLockdown and InCombatLockdown() then
                                        return
                                    end
                                    ensureTextAndBorderOrdering(unit)
                                end)
                                hb._ScootUFZOrderHooked = true
                            end
						end
					else
						-- Custom borders disabled -> ensure cleared
						if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
						if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(hb) end
					end
				end
            end

            -- Lightweight persistence hooks for Player Health Bar:
            -- Texture: keep custom texture applied if Blizzard swaps StatusBarTexture.
            -- Color: keep Foreground Color applied if Blizzard calls SetStatusBarColor.
            if unit == "Player" and _G.hooksecurefunc then
                -- Texture hook: reapply custom texture when Blizzard resets it
                if not hb._ScootHealthTextureHooked then
                    hb._ScootHealthTextureHooked = true
                    _G.hooksecurefunc(hb, "SetStatusBarTexture", function(self, ...)
                        -- Ignore ScooterMod's own writes to avoid recursion.
                        if self._ScootUFInternalTextureWrite then
                            return
                        end
                        -- Skip during combat to avoid taint on protected StatusBar.
                        if InCombatLockdown and InCombatLockdown() then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                        if not cfgP then return end
                        local texKey = cfgP.healthBarTexture or "default"
                        local colorMode = cfgP.healthBarColorMode or "default"
                        local tint = cfgP.healthBarTint
                        -- Only re-apply if the user has configured a non-default texture.
                        if not (type(texKey) == "string" and texKey ~= "" and texKey ~= "default") then
                            return
                        end
                        applyToBar(self, texKey, colorMode, tint, "player", "health", "player")
                    end)
                end
                -- Color hook: reapply custom color when Blizzard resets it
                if not hb._ScootHealthColorHooked then
                    hb._ScootHealthColorHooked = true
                    _G.hooksecurefunc(hb, "SetStatusBarColor", function(self, ...)
                        -- CRITICAL: Do NOT call applyToBar during combat - it calls SetStatusBarTexture/SetVertexColor
                        -- on the protected StatusBar, which taints it and causes "blocked from an action" errors.
                        if InCombatLockdown and InCombatLockdown() then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                        if not cfgP then return end
                        local texKey = cfgP.healthBarTexture or "default"
                        local colorMode = cfgP.healthBarColorMode or "default"
                        local tint = cfgP.healthBarTint
                        local unitIdP = "player"
                        -- Only do work when the user has customized either texture or color;
                        -- default settings can safely follow Blizzard's behavior.
                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end
                        applyToBar(self, texKey, colorMode, tint, "player", "health", unitIdP)
                    end)
                end
            end

            -- Lightweight persistence hooks for Target-of-Target Health Bar:
            -- Blizzard can reset the ToT StatusBar's fill texture during rapid updates (often in combat).
            -- We re-assert the configured texture/color by writing to the underlying Texture region
            -- (avoids calling SetStatusBarTexture again inside a secure callstack).
            if unit == "TargetOfTarget" and _G.hooksecurefunc then
                if not hb._ScootToTHealthTextureHooked then
                    hb._ScootToTHealthTextureHooked = true
                    _G.hooksecurefunc(hb, "SetStatusBarTexture", function(self, ...)
                        -- Ignore ScooterMod's own writes to avoid feedback loops.
                        if self._ScootUFInternalTextureWrite then
                            return
                        end

                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgT = unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
                        if not cfgT then return end

                        local texKey = cfgT.healthBarTexture or "default"
                        local colorMode = cfgT.healthBarColorMode or "default"
                        local tint = cfgT.healthBarTint

                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end

                        -- Avoid any writes during combat; defer until after combat.
                        if InCombatLockdown and InCombatLockdown() then
                            queueUnitFrameTextureReapply("TargetOfTarget")
                            return
                        end

                        -- Throttle: coalesce rapid refreshes into a single 0s re-apply.
                        if self._ScootToTReapplyPending then
                            return
                        end
                        self._ScootToTReapplyPending = true
                        if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                            _G.C_Timer.After(0, function()
                                self._ScootToTReapplyPending = nil
                                addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                            end)
                        elseif addon.ApplyUnitFrameBarTexturesFor then
                            self._ScootToTReapplyPending = nil
                            addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                        end
                    end)
                end

                if not hb._ScootToTHealthColorHooked then
                    hb._ScootToTHealthColorHooked = true
                    _G.hooksecurefunc(hb, "SetStatusBarColor", function(self, ...)
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgT = unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
                        if not cfgT then return end

                        local texKey = cfgT.healthBarTexture or "default"
                        local colorMode = cfgT.healthBarColorMode or "default"
                        local tint = cfgT.healthBarTint

                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end

                        if InCombatLockdown and InCombatLockdown() then
                            queueUnitFrameTextureReapply("TargetOfTarget")
                            return
                        end

                        if self._ScootToTReapplyPending then
                            return
                        end
                        self._ScootToTReapplyPending = true
                        if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                            _G.C_Timer.After(0, function()
                                self._ScootToTReapplyPending = nil
                                addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                            end)
                        elseif addon.ApplyUnitFrameBarTexturesFor then
                            self._ScootToTReapplyPending = nil
                            addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                        end
                    end)
                end
            end
		end

        local pb = resolvePowerBar(frame, unit)
        if pb then
            -- Cache combat state once for this styling pass. We avoid all geometry
            -- changes (width/height/anchors/offsets) while in combat to prevent
            -- taint on protected unit frames (see taint.log: TargetFrameToT:Show()).
            local inCombat = InCombatLockdown and InCombatLockdown()
			local powerBarHidden = (cfg.powerBarHidden == true)
			local powerBarHideTextureOnly = (cfg.powerBarHideTextureOnly == true)

			-- Capture original alpha once so we can restore when the bar is un-hidden.
			if pb.GetAlpha and pb._ScootUFOrigPBAlpha == nil then
				local ok, a = pcall(pb.GetAlpha, pb)
				pb._ScootUFOrigPBAlpha = ok and (a or 1) or 1
			end

			-- When the user chooses to hide the Power Bar:
			-- - Fade the StatusBar frame to alpha 0 so the fill/background vanish.
			-- - Hide any ScooterMod-drawn borders/backgrounds associated with this bar.
			if powerBarHidden then
				if pb.SetAlpha then
					pcall(pb.SetAlpha, pb, 0)
				end
				if pb.ScooterModBG and pb.ScooterModBG.SetAlpha then
					pcall(pb.ScooterModBG.SetAlpha, pb.ScooterModBG, 0)
				end
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then
					addon.BarBorders.ClearBarFrame(pb)
				end
				if addon.Borders and addon.Borders.HideAll then
					addon.Borders.HideAll(pb)
				end
				-- Ensure texture-only mode is disabled when full bar is hidden
				if Util and Util.SetPowerBarTextureOnlyHidden then
					Util.SetPowerBarTextureOnlyHidden(pb, false)
				end
			elseif powerBarHideTextureOnly then
				-- Number-only display: Hide the bar texture/fill while keeping text visible.
				-- Use the utility function which installs persistent hooks to survive combat.
				-- Restore bar frame alpha first (in case user toggled from full-hide to texture-only).
				if pb._ScootUFOrigPBAlpha and pb.SetAlpha then
					pcall(pb.SetAlpha, pb, pb._ScootUFOrigPBAlpha)
				end
				
				-- Use persistent utility to hide textures (installs hooks that survive combat)
				if Util and Util.SetPowerBarTextureOnlyHidden then
					Util.SetPowerBarTextureOnlyHidden(pb, true)
				end
				
				-- Clear any custom borders so only text remains
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then
					addon.BarBorders.ClearBarFrame(pb)
				end
				if addon.Borders and addon.Borders.HideAll then
					addon.Borders.HideAll(pb)
				end
			else
				-- Restore alpha when coming back from a hidden state so the bar is visible again.
				if pb._ScootUFOrigPBAlpha and pb.SetAlpha then
					pcall(pb.SetAlpha, pb, pb._ScootUFOrigPBAlpha)
				end
				-- Disable texture-only hiding (restores texture visibility)
				if Util and Util.SetPowerBarTextureOnlyHidden then
					Util.SetPowerBarTextureOnlyHidden(pb, false)
				end
			end
            local colorModePB = cfg.powerBarColorMode or "default"
            local texKeyPB = cfg.powerBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or "player"
            applyToBar(pb, texKeyPB, colorModePB, cfg.powerBarTint, "player", "power", unitId)
            
            -- Apply background texture and color for Power Bar
            do
                -- IMPORTANT: Default/clean profiles should not change the look of Blizzard's bars.
                -- Only apply our background overlay if the user actually customized background settings.
                local function hasBackgroundCustomization()
                    local texKey = cfg.powerBarBackgroundTexture
                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                        return true
                    end
                    local mode = cfg.powerBarBackgroundColorMode
                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                        return true
                    end
                    local op = cfg.powerBarBackgroundOpacity
                    local opNum = tonumber(op)
                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                        return true
                    end
                    if mode == "custom" and type(cfg.powerBarBackgroundTint) == "table" then
                        return true
                    end
                    return false
                end
                if hasBackgroundCustomization() then
                    local bgTexKeyPB = cfg.powerBarBackgroundTexture or "default"
                    local bgColorModePB = cfg.powerBarBackgroundColorMode or "default"
                    local bgOpacityPB = cfg.powerBarBackgroundOpacity or 50
                    applyBackgroundToBar(pb, bgTexKeyPB, bgColorModePB, cfg.powerBarBackgroundTint, bgOpacityPB, unit, "power")
                end
            end
            
            -- Re-apply texture-only hide after styling (ensures newly created ScooterModBG is also hidden)
            if powerBarHideTextureOnly and not powerBarHidden then
                if Util and Util.SetPowerBarTextureOnlyHidden then
                    Util.SetPowerBarTextureOnlyHidden(pb, true)
                end
            end
            
            ensureMaskOnBarTexture(pb, resolvePowerMask(unit))

            -- When texture-only hide is enabled, also hide animations/feedback/spark (they'd look weird floating)
            local hideAllVisuals = powerBarHidden or powerBarHideTextureOnly
            
            if unit == "Player" and Util and Util.SetFullPowerSpikeHidden then
                Util.SetFullPowerSpikeHidden(pb, cfg.powerBarHideFullSpikes == true or hideAllVisuals)
            end

            -- Hide power feedback animation (Builder/Spender flash when power is spent/gained)
            if unit == "Player" and Util and Util.SetPowerFeedbackHidden then
                Util.SetPowerFeedbackHidden(pb, cfg.powerBarHideFeedback == true or hideAllVisuals)
            end

            -- Hide power bar spark (e.g., Elemental Shaman Maelstrom indicator)
            if unit == "Player" and Util and Util.SetPowerBarSparkHidden then
                Util.SetPowerBarSparkHidden(pb, cfg.powerBarHideSpark == true or hideAllVisuals)
            end

            -- Apply reverse fill for Target/Focus if configured
            if (unit == "Target" or unit == "Focus") and pb and pb.SetReverseFill then
                local shouldReverse = not not cfg.powerBarReverseFill
                pcall(pb.SetReverseFill, pb, shouldReverse)
            end

            -- Lightweight persistence hooks for Player Power Bar:
            --  - Texture: keep custom texture applied if Blizzard swaps StatusBarTexture.
            --  - Color:   keep Foreground Color (default/class/custom) applied if Blizzard calls SetStatusBarColor.
            -- IMPORTANT: Do NOT re-apply during combat. Even "cosmetic-only" calls like
            -- SetStatusBarTexture/SetVertexColor on protected unitframe StatusBars can taint the
            -- execution context and later surface as blocked calls in unrelated Blizzard code paths
            -- (e.g., AlternatePowerBar:Hide()).
            --
            -- Also IMPORTANT: Defer work with C_Timer.After(0) to break Blizzard's execution chain
            -- (see DEBUG.md: global hook taint propagation lessons).
            if unit == "Player" and _G.hooksecurefunc then
                if not pb._ScootPowerTextureHooked then
                    pb._ScootPowerTextureHooked = true
                    _G.hooksecurefunc(pb, "SetStatusBarTexture", function(self, ...)
                        -- Ignore ScooterMod's own writes to avoid recursion.
                        if self._ScootUFInternalTextureWrite then
                            return
                        end
                        if InCombatLockdown and InCombatLockdown() then
                            queuePowerBarReapply("Player")
                            return
                        end

                        -- Throttle: coalesce rapid texture resets into a single 0s re-apply.
                        if self._ScootPowerReapplyPending then
                            return
                        end
                        self._ScootPowerReapplyPending = true

                        local bar = self
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if not bar then return end
                                bar._ScootPowerReapplyPending = nil
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePowerBarReapply("Player")
                                    return
                                end
                                local db = addon and addon.db and addon.db.profile
                                if not db then return end
                                local unitFrames = rawget(db, "unitFrames")
                                local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                                if not cfgP then return end
                                local texKey = cfgP.powerBarTexture or "default"
                                local colorMode = cfgP.powerBarColorMode or "default"
                                local tint = cfgP.powerBarTint
                                -- Only re-apply if the user has configured a non-default texture.
                                if not (type(texKey) == "string" and texKey ~= "" and texKey ~= "default") then
                                    return
                                end
                                applyToBar(bar, texKey, colorMode, tint, "player", "power", "player")
                                -- Re-assert texture-only hide after any texture swap. The hide feature
                                -- attaches to the current fill/background textures, so a SetStatusBarTexture
                                -- can create a fresh texture that needs to be re-hidden.
                                if Util and Util.SetPowerBarTextureOnlyHidden and cfgP.powerBarHideTextureOnly == true and not (cfgP.powerBarHidden == true) then
                                    Util.SetPowerBarTextureOnlyHidden(bar, true)
                                end
                            end)
                        else
                            self._ScootPowerReapplyPending = nil
                        end
                    end)
                end
                if not pb._ScootPowerColorHooked then
                    pb._ScootPowerColorHooked = true
                    _G.hooksecurefunc(pb, "SetStatusBarColor", function(self, ...)
                        if InCombatLockdown and InCombatLockdown() then
                            queuePowerBarReapply("Player")
                            return
                        end

                        if self._ScootPowerReapplyPending then
                            return
                        end
                        self._ScootPowerReapplyPending = true

                        local bar = self
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if not bar then return end
                                bar._ScootPowerReapplyPending = nil
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePowerBarReapply("Player")
                                    return
                                end
                                local db = addon and addon.db and addon.db.profile
                                if not db then return end
                                local unitFrames = rawget(db, "unitFrames")
                                local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                                if not cfgP then return end
                                local texKey = cfgP.powerBarTexture or "default"
                                local colorMode = cfgP.powerBarColorMode or "default"
                                local tint = cfgP.powerBarTint

                                -- If color mode is "texture", the user wants the texture's original colors;
                                -- in that case we allow Blizzard's SetStatusBarColor to stand.
                                if colorMode == "texture" then
                                    return
                                end

                                -- Only do work when the user has customized either texture or color;
                                -- default settings can safely follow Blizzard's behavior.
                                local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class")
                                if not hasCustomTexture and not hasCustomColor then
                                    return
                                end

                                applyToBar(bar, texKey, colorMode, tint, "player", "power", "player")
                                -- Re-assert texture-only hide after any styling pass that may refresh textures.
                                if Util and Util.SetPowerBarTextureOnlyHidden and cfgP.powerBarHideTextureOnly == true and not (cfgP.powerBarHidden == true) then
                                    Util.SetPowerBarTextureOnlyHidden(bar, true)
                                end
                            end)
                        else
                            self._ScootPowerReapplyPending = nil
                        end
                    end)
                end
            end

            -- Alternate Power Bar styling (Player-only, class/spec gated)
            if unit == "Player" and addon.UnitFrames_PlayerHasAlternatePowerBar and addon.UnitFrames_PlayerHasAlternatePowerBar() then
                local apb = resolveAlternatePowerBar()
                if apb then
                    -- Zero‑Touch: only style Alternate Power Bar when explicitly configured.
                    local acfg = rawget(cfg, "altPowerBar")
                    if acfg then

                    -- Optional hide toggle
                    local altHidden = (acfg.hidden == true)
                    if apb.GetAlpha and apb._ScootUFOrigAltAlpha == nil then
                        local ok, a = pcall(apb.GetAlpha, apb)
                        apb._ScootUFOrigAltAlpha = ok and (a or 1) or 1
                    end
                    if altHidden then
                        if apb.SetAlpha then pcall(apb.SetAlpha, apb, 0) end
                    else
                        if apb._ScootUFOrigAltAlpha and apb.SetAlpha then
                            pcall(apb.SetAlpha, apb, apb._ScootUFOrigAltAlpha)
                        end
                    end

                    -- Foreground texture / color
                    local altTexKey = acfg.texture or "default"
                    local altColorMode = acfg.colorMode or "default"
                    local altTint = acfg.tint
                    applyToBar(apb, altTexKey, altColorMode, altTint, "player", "altpower", "player")

                    -- Background texture / color / opacity
                    local altBgTexKey = acfg.backgroundTexture or "default"
                    local altBgColorMode = acfg.backgroundColorMode or "default"
                    local altBgOpacity = acfg.backgroundOpacity or 50
                    applyBackgroundToBar(apb, altBgTexKey, altBgColorMode, acfg.backgroundTint, altBgOpacity, unit, "altpower")

                    -- Custom border (shares global Use Custom Borders; Alt Power has its own style/tint/thickness/inset)
                    do
                        -- Global unit-frame switch; borders only draw when this is enabled.
                        local useCustomBorders = not not cfg.useCustomBorders
                        if useCustomBorders then
                            -- Style resolution: prefer Alternate Power–specific, then Power, then Health.
                            local styleKey = acfg.borderStyle
                                or cfg.powerBarBorderStyle
                                or cfg.healthBarBorderStyle

                            -- Tint enable: prefer Alternate Power–specific, then Power, then Health.
                            local tintEnabled
                            if acfg.borderTintEnable ~= nil then
                                tintEnabled = not not acfg.borderTintEnable
                            elseif cfg.powerBarBorderTintEnable ~= nil then
                                tintEnabled = not not cfg.powerBarBorderTintEnable
                            else
                                tintEnabled = not not cfg.healthBarBorderTintEnable
                            end

                            -- Tint color: prefer Alternate Power–specific, then Power, then Health.
                            local baseTint = type(acfg.borderTintColor) == "table" and acfg.borderTintColor
                                or cfg.powerBarBorderTintColor
                                or cfg.healthBarBorderTintColor
                            local tintColor = type(baseTint) == "table" and {
                                baseTint[1] or 1,
                                baseTint[2] or 1,
                                baseTint[3] or 1,
                                baseTint[4] or 1,
                            } or { 1, 1, 1, 1 }

                            -- Thickness / inset: prefer Alternate Power–specific, then Power, then Health.
                            local thickness = tonumber(acfg.borderThickness)
                                or tonumber(cfg.powerBarBorderThickness)
                                or tonumber(cfg.healthBarBorderThickness)
                                or 1
                            if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

                            local inset
                            if acfg.borderInset ~= nil then
                                inset = tonumber(acfg.borderInset) or 0
                            elseif cfg.powerBarBorderInset ~= nil then
                                inset = tonumber(cfg.powerBarBorderInset) or 0
                            else
                                inset = tonumber(cfg.healthBarBorderInset) or 0
                            end

                            if styleKey == "none" or styleKey == nil then
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(apb) end
                            else
                                local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                local color
                                if tintEnabled then
                                    color = tintColor
                                else
                                    if styleDef then
                                        color = { 1, 1, 1, 1 }
                                    else
                                        color = { 0, 0, 0, 1 }
                                    end
                                end

                                local handled = false
                                if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                                    if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                    handled = addon.BarBorders.ApplyToBarFrame(apb, styleKey, {
                                        color = color,
                                        thickness = thickness,
                                        levelOffset = 1,
                                        containerParent = (apb and apb:GetParent()) or nil,
                                        inset = inset,
                                    })
                                end

                                if not handled then
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                    if addon.Borders and addon.Borders.ApplySquare then
                                        local sqColor = tintEnabled and tintColor or { 0, 0, 0, 1 }
                                        local baseY = (thickness <= 1) and 0 or 1
                                        local baseX = 1
                                        local expandY = baseY - inset
                                        local expandX = baseX - inset
                                        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                        addon.Borders.ApplySquare(apb, {
                                            size = thickness,
                                            color = sqColor,
                                            layer = "OVERLAY",
                                            layerSublevel = 3,
                                            expandX = expandX,
                                            expandY = expandY,
                                        })
                                    end
                                end
                            end
                        else
                            -- Global custom borders disabled: clear any previous Alternate Power border.
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(apb) end
                        end
                    end

                    -- % Text and Value Text (AlternatePowerBar.LeftText / RightText)
                    do
                        local leftFS = apb.LeftText
                        local rightFS = apb.RightText
                        -- Also resolve the center TextString (used in NUMERIC display mode)
                        -- This ensures styling persists when Blizzard switches between BOTH and NUMERIC modes
                        local textStringFS = apb.TextString or apb.text

                        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
                        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce BOTH alpha=0 AND font styling when Blizzard updates.
                        local function applyAltPowerTextVisibility(fs, hidden)
                            if not fs then return end
                            if hidden then
                                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                                if not fs._ScooterAltPowerTextVisibilityHooked then
                                    fs._ScooterAltPowerTextVisibilityHooked = true
                                    if _G.hooksecurefunc then
                                        -- Hook Show() to re-enforce alpha=0
                                        _G.hooksecurefunc(fs, "Show", function(self)
                                            if self._ScooterAltPowerTextHidden and self.SetAlpha then
                                                pcall(self.SetAlpha, self, 0)
                                            end
                                        end)
                                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                                            if self._ScooterAltPowerTextHidden and alpha and alpha > 0 then
                                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                                if not self._ScooterAltPowerTextAlphaDeferred then
                                                    self._ScooterAltPowerTextAlphaDeferred = true
                                                    C_Timer.After(0, function()
                                                        self._ScooterAltPowerTextAlphaDeferred = nil
                                                        if self._ScooterAltPowerTextHidden and self.SetAlpha then
                                                            pcall(self.SetAlpha, self, 0)
                                                        end
                                                    end)
                                                end
                                            end
                                        end)
                                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                                        _G.hooksecurefunc(fs, "SetText", function(self)
                                            if self._ScooterAltPowerTextHidden and self.SetAlpha then
                                                pcall(self.SetAlpha, self, 0)
                                            end
                                        end)
                                    end
                                end
                                fs._ScooterAltPowerTextHidden = true
                            else
                                fs._ScooterAltPowerTextHidden = false
                                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
                            end
                        end

                        -- NOTE: SetFont/SetFontObject hooks removed for performance reasons.
                        -- Font persistence is handled by the Character Frame hook in text.lua.

                        -- Visibility: respect both the bar-wide hidden flag and the per-text toggles.
                        local percentHidden = (acfg.percentHidden == true)
                        local valueHidden = (acfg.valueHidden == true)

                        applyAltPowerTextVisibility(leftFS, altHidden or percentHidden)
                        applyAltPowerTextVisibility(rightFS, altHidden or valueHidden)

                        -- Install SetText hook for center TextString to enforce hidden state only
                        if textStringFS and not textStringFS._ScooterAltPowerTextCenterSetTextHooked then
                            textStringFS._ScooterAltPowerTextCenterSetTextHooked = true
                            if _G.hooksecurefunc then
                                _G.hooksecurefunc(textStringFS, "SetText", function(self)
                                    -- Enforce hidden state immediately if configured
                                    if self._ScooterAltPowerTextCenterHidden and self.SetAlpha then
                                        pcall(self.SetAlpha, self, 0)
                                    end
                                end)
                            end
                        end

                        -- Styling (font/size/style/color/offset) using stable baseline anchors
                        addon._ufAltPowerTextBaselines = addon._ufAltPowerTextBaselines or {}
                        local function ensureBaseline(fs, key)
                            addon._ufAltPowerTextBaselines[key] = addon._ufAltPowerTextBaselines[key] or {}
                            local b = addon._ufAltPowerTextBaselines[key]
                            if b.point == nil then
                                if fs and fs.GetPoint then
                                    local p, relTo, rp, x, y = fs:GetPoint(1)
                                    b.point = p or "CENTER"
                                    b.relTo = relTo or (fs.GetParent and fs:GetParent()) or apb
                                    b.relPoint = rp or b.point
                                    b.x = tonumber(x) or 0
                                    b.y = tonumber(y) or 0
                                else
                                    b.point, b.relTo, b.relPoint, b.x, b.y =
                                        "CENTER", (fs and fs.GetParent and fs:GetParent()) or apb, "CENTER", 0, 0
                                end
                            end
                            return b
                        end

                        local function applyAltTextStyle(fs, styleCfg, baselineKey)
                            if not fs or not styleCfg then return end
                            -- Default/clean profiles should not modify Blizzard text.
                            -- Only apply styling if the user has configured any text settings.
                            local function hasTextCustomization(cfgT)
                                if not cfgT then return false end
                                -- Font face may be present as a structural default; treat the stock face as non-customization
                                -- unless other settings are set.
                                if cfgT.fontFace ~= nil and cfgT.fontFace ~= "" and cfgT.fontFace ~= "FRIZQT__" then
                                    return true
                                end
                                if cfgT.size ~= nil or cfgT.style ~= nil or cfgT.color ~= nil or cfgT.alignment ~= nil then
                                    return true
                                end
                                if cfgT.offset and (cfgT.offset.x ~= nil or cfgT.offset.y ~= nil) then
                                    local ox = tonumber(cfgT.offset.x) or 0
                                    local oy = tonumber(cfgT.offset.y) or 0
                                    if ox ~= 0 or oy ~= 0 then
                                        return true
                                    end
                                end
                                return false
                            end
                            if not hasTextCustomization(styleCfg) then
                                return
                            end
                            local face = addon.ResolveFontFace
                                and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
                                or (select(1, _G.GameFontNormal:GetFont()))
                            local size = tonumber(styleCfg.size) or 14
                            local outline = tostring(styleCfg.style or "OUTLINE")
                            -- Set flag to prevent our SetFont hook from triggering a reapply loop
                            fs._ScooterApplyingFont = true
                            if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
                            fs._ScooterApplyingFont = nil
                            local c = styleCfg.color or { 1, 1, 1, 1 }
                            if fs.SetTextColor then
                                pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
                            end

                            -- Apply text alignment (requires explicit width on the FontString)
                            local defaultAlign = "LEFT"
                            -- For the Value (right) text, default to RIGHT align unless explicitly overridden.
                            if baselineKey and baselineKey:find("%-right") then
                                defaultAlign = "RIGHT"
                            end
                            local alignment = styleCfg.alignment or defaultAlign
                            local parentBar = fs:GetParent()
                            if parentBar and parentBar.GetWidth then
                                local barWidth = parentBar:GetWidth()
                                if barWidth and barWidth > 0 and fs.SetWidth then
                                    pcall(fs.SetWidth, fs, barWidth)
                                end
                            end
                            if fs.SetJustifyH then
                                pcall(fs.SetJustifyH, fs, alignment)
                            end

                            local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
                            local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
                            if fs.ClearAllPoints and fs.SetPoint then
                                local b = ensureBaseline(fs, baselineKey)
                                fs:ClearAllPoints()
                                fs:SetPoint(
                                    b.point or "CENTER",
                                    b.relTo or (fs.GetParent and fs:GetParent()) or apb,
                                    b.relPoint or b.point or "CENTER",
                                    (b.x or 0) + ox,
                                    (b.y or 0) + oy
                                )
                            end

                            -- Force text redraw to apply alignment visually
                            if fs.GetText and fs.SetText then
                                local txt = fs:GetText()
                                if txt then
                                    fs:SetText("")
                                    fs:SetText(txt)
                                end
                            end
                        end

                        if leftFS then
                            applyAltTextStyle(leftFS, acfg.textPercent or {}, "Player:altpower-left")
                        end
                        if rightFS then
                            applyAltTextStyle(rightFS, acfg.textValue or {}, "Player:altpower-right")
                        end
                        -- Style center TextString using Value settings (used in NUMERIC display mode)
                        -- If Value text is hidden (or entire bar is hidden), also hide center text
                        if textStringFS then
                            local centerHidden = altHidden or valueHidden
                            if centerHidden then
                                if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 0) end
                                textStringFS._ScooterAltPowerTextCenterHidden = true
                            else
                                if textStringFS._ScooterAltPowerTextCenterHidden then
                                    if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 1) end
                                    textStringFS._ScooterAltPowerTextCenterHidden = nil
                                end
                                applyAltTextStyle(textStringFS, acfg.textValue or {}, "Player:altpower-center")
                            end
                        end
                    end

                    -- Width / height scaling (simple frame SetWidth/SetHeight based on %),
                    -- plus additive X/Y offsets applied from the captured baseline points.
                    if not inCombat then
                        -- Capture originals once
                        if not apb._ScootUFOrigWidth then
                            if apb.GetWidth then
                                local ok, w = pcall(apb.GetWidth, apb)
                                if ok and w then apb._ScootUFOrigWidth = w end
                            end
                        end
                        if not apb._ScootUFOrigHeight then
                            if apb.GetHeight then
                                local ok, h = pcall(apb.GetHeight, apb)
                                if ok and h then apb._ScootUFOrigHeight = h end
                            end
                        end
                        if not apb._ScootUFOrigPoints then
                            local pts = {}
                            local n = (apb.GetNumPoints and apb:GetNumPoints()) or 0
                            for i = 1, n do
                                local p, rel, rp, x, y = apb:GetPoint(i)
                                table.insert(pts, { p, rel, rp, x or 0, y or 0 })
                            end
                            apb._ScootUFOrigPoints = pts
                        end

                        local wPct = tonumber(acfg.widthPct) or 100
                        local hPct = tonumber(acfg.heightPct) or 100
                        local scaleX = math.max(0.5, math.min(1.5, wPct / 100))
                        local scaleY = math.max(0.5, math.min(2.0, hPct / 100))

                        -- Restore baseline first
                        if apb._ScootUFOrigWidth and apb.SetWidth then
                            pcall(apb.SetWidth, apb, apb._ScootUFOrigWidth)
                        end
                        if apb._ScootUFOrigHeight and apb.SetHeight then
                            pcall(apb.SetHeight, apb, apb._ScootUFOrigHeight)
                        end
                        if apb._ScootUFOrigPoints and apb.ClearAllPoints and apb.SetPoint then
                            pcall(apb.ClearAllPoints, apb)
                            for _, pt in ipairs(apb._ScootUFOrigPoints) do
                                pcall(apb.SetPoint, apb, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", pt[4] or 0, pt[5] or 0)
                            end
                        end

                        -- Apply width/height scaling (from center)
                        if apb._ScootUFOrigWidth and apb.SetWidth then
                            pcall(apb.SetWidth, apb, apb._ScootUFOrigWidth * scaleX)
                        end
                        if apb._ScootUFOrigHeight and apb.SetHeight then
                            pcall(apb.SetHeight, apb, apb._ScootUFOrigHeight * scaleY)
                        end

                        -- Apply positioning offsets relative to the original anchor points.
                        local offsetX = tonumber(acfg.offsetX) or 0
                        local offsetY = tonumber(acfg.offsetY) or 0
                        if apb._ScootUFOrigPoints and apb.ClearAllPoints and apb.SetPoint then
                            pcall(apb.ClearAllPoints, apb)
                            for _, pt in ipairs(apb._ScootUFOrigPoints) do
                                local baseX = pt[4] or 0
                                local baseY = pt[5] or 0
                                local newX = baseX + offsetX
                                local newY = baseY + offsetY
                                pcall(apb.SetPoint, apb, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", newX, newY)
                            end
                        end
                    end
                    end -- acfg
                end
            end

            -- Experimental: Power Bar Width scaling (texture/mask only)
            -- For Target/Focus: Only when reverse fill is enabled
            -- For Player/Pet: Always available
            do
                local canScale = false
                if unit == "Player" or unit == "Pet" then
                    canScale = true
                elseif (unit == "Target" or unit == "Focus") and cfg.powerBarReverseFill then
                    canScale = true
                end

                if canScale and not inCombat then
                    local pct = tonumber(cfg.powerBarWidthPct) or 100
                    local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
                    local mask = resolvePowerMask(unit)
					local isMirroredUnit = (unit == "Target" or unit == "Focus")
					local scaleX = math.min(1.5, math.max(0.5, (pct or 100) / 100))

                    -- Capture original PB width once
                    if pb and not pb._ScootUFOrigWidth then
                        if pb.GetWidth then
                            local ok, w = pcall(pb.GetWidth, pb)
                            if ok and w then pb._ScootUFOrigWidth = w end
                        end
                    end

                    -- Capture original PB anchors
                    if pb and not pb._ScootUFOrigPoints then
                        local pts = {}
                        local n = (pb.GetNumPoints and pb:GetNumPoints()) or 0
                        for i = 1, n do
                            local p, rel, rp, x, y = pb:GetPoint(i)
                            table.insert(pts, { p, rel, rp, x or 0, y or 0 })
                        end
                        pb._ScootUFOrigPoints = pts
                    end

                    -- Helper: reanchor PB to grow left
                    local function reapplyPBPointsWithLeftOffset(dx)
                        if not pb or not pb.ClearAllPoints or not pb.SetPoint or not pb._ScootUFOrigPoints then return end
                        pcall(pb.ClearAllPoints, pb)
                        for _, pt in ipairs(pb._ScootUFOrigPoints) do
                            pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", (pt[4] or 0) - dx, pt[5] or 0)
                        end
                    end

                    -- Helper: reanchor PB to grow right
                    local function reapplyPBPointsWithRightOffset(dx)
                        if not pb or not pb.ClearAllPoints or not pb.SetPoint or not pb._ScootUFOrigPoints then return end
                        pcall(pb.ClearAllPoints, pb)
                        for _, pt in ipairs(pb._ScootUFOrigPoints) do
                            pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", (pt[4] or 0) + dx, pt[5] or 0)
                        end
                    end

					-- CRITICAL: Always restore to original state FIRST before applying new width
					-- Always start from the captured baseline to avoid cumulative offsets.
					if pb and pb._ScootUFOrigWidth and pb.SetWidth then
						pcall(pb.SetWidth, pb, pb._ScootUFOrigWidth)
					end
					if pb and pb._ScootUFOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						pcall(pb.ClearAllPoints, pb)
						for _, pt in ipairs(pb._ScootUFOrigPoints) do
							pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
						end
					end

                    if pct > 100 then
                        -- Widen the status bar frame
                        if pb and pb.SetWidth and pb._ScootUFOrigWidth then
                            pcall(pb.SetWidth, pb, pb._ScootUFOrigWidth * scaleX)
                        end

                        -- Reposition the frame to control growth direction
                        if pb and pb._ScootUFOrigWidth then
                            local dx = (pb._ScootUFOrigWidth * (scaleX - 1))
                            if dx and dx ~= 0 then
                                if unit == "Target" or unit == "Focus" then
                                    reapplyPBPointsWithLeftOffset(dx)
                                else
                                    reapplyPBPointsWithRightOffset(dx)
                                end
                            end
                        end

                        -- DO NOT touch the StatusBar texture - it's managed automatically by the StatusBar widget
                        -- REMOVE the mask entirely when widening - it causes rendering artifacts
                        if tex and mask and tex.RemoveMaskTexture then
                            pcall(tex.RemoveMaskTexture, tex, mask)
                        end
                        -- NOTE: Do NOT call SetValue to "refresh" the texture - it taints the protected StatusBar
                        -- and causes "blocked from an action" errors when Blizzard later calls Show().
                        -- The StatusBar refreshes automatically when its dimensions change.
                    elseif pct < 100 then
						-- Narrow the status bar frame
						if pb and pb.SetWidth and pb._ScootUFOrigWidth then
							pcall(pb.SetWidth, pb, pb._ScootUFOrigWidth * scaleX)
						end
						-- Reposition so mirrored bars keep the portrait edge anchored
						if pb and pb._ScootUFOrigWidth then
							local shrinkDx = pb._ScootUFOrigWidth * (1 - scaleX)
							if shrinkDx and shrinkDx ~= 0 and isMirroredUnit then
								reapplyPBPointsWithLeftOffset(-shrinkDx)
							end
						end
						-- Ensure mask remains applied when narrowing
						if pb and mask then
							ensureMaskOnBarTexture(pb, mask)
						end
                    else
                        -- Restore power bar frame
                        if pb and pb._ScootUFOrigWidth and pb.SetWidth then
                            pcall(pb.SetWidth, pb, pb._ScootUFOrigWidth)
                        end
                        if pb and pb._ScootUFOrigPoints and pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            for _, pt in ipairs(pb._ScootUFOrigPoints) do
                                pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
                            end
                        end
                        -- Re-apply mask to texture at original dimensions
                        if pb and mask then
                            ensureMaskOnBarTexture(pb, mask)
                        end
                    end
				elseif not inCombat then
					-- Not scalable (Target/Focus with default fill): ensure we restore any prior width/anchors/mask
					local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
					local mask = resolvePowerMask(unit)
					-- Restore power bar frame
					if pb and pb._ScootUFOrigWidth and pb.SetWidth then
						pcall(pb.SetWidth, pb, pb._ScootUFOrigWidth)
					end
					if pb and pb._ScootUFOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						pcall(pb.ClearAllPoints, pb)
						for _, pt in ipairs(pb._ScootUFOrigPoints) do
							pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
						end
					end
					-- Re-apply mask to texture at original dimensions
					if pb and mask then
						ensureMaskOnBarTexture(pb, mask)
					end
							end
						end
			
			-- Power Bar Height scaling (texture/mask only)
			-- For Target/Focus: Only when reverse fill is enabled
			-- For Player/Pet: Always available
			do
                -- Skip all Power Bar height scaling while in combat; defer to the next
                -- out-of-combat styling pass instead to avoid taint.
                if not inCombat then
				    local canScale = false
				    if unit == "Player" or unit == "Pet" then
					    canScale = true
				    elseif (unit == "Target" or unit == "Focus") and cfg.powerBarReverseFill then
					    canScale = true
				    end
				
				    if canScale then
					    local pct = tonumber(cfg.powerBarHeightPct) or 100
					    local widthPct = tonumber(cfg.powerBarWidthPct) or 100
					    local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
					    local mask = resolvePowerMask(unit)
					
					    -- Capture originals once (height and anchor points)
					    if tex and not tex._ScootUFOrigCapturedHeight then
						    if tex.GetHeight then
							    local ok, h = pcall(tex.GetHeight, tex)
							    if ok and h then tex._ScootUFOrigHeight = h end
						    end
						    -- Texture anchor points already captured by width scaling
						    tex._ScootUFOrigCapturedHeight = true
					    end
					    if mask and not mask._ScootUFOrigCapturedHeight then
						    if mask.GetHeight then
							    local ok, h = pcall(mask.GetHeight, mask)
							    if ok and h then mask._ScootUFOrigHeight = h end
						    end
						    -- Mask anchor points already captured by width scaling
						    mask._ScootUFOrigCapturedHeight = true
					    end
					
					    -- Anchor points should already be captured by width scaling
					    -- If not, capture them now
					    if pb and not pb._ScootUFOrigPoints then
						    local pts = {}
						    local n = (pb.GetNumPoints and pb:GetNumPoints()) or 0
						    for i = 1, n do
							    local p, rel, rp, x, y = pb:GetPoint(i)
							    table.insert(pts, { p, rel, rp, x or 0, y or 0 })
						    end
						    pb._ScootUFOrigPoints = pts
					    end
					
					    -- Helper: reanchor PB to grow downward (keep top fixed)
					    local function reapplyPBPointsWithBottomOffset(dy)
						    -- Positive dy moves BOTTOM/CENTER anchors downward (keep top edge fixed)
						    local pts = pb and pb._ScootUFOrigPoints
						    if not (pb and pts and pb.ClearAllPoints and pb.SetPoint) then return end
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pts) do
							    local p, rel, rp, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
							    local yy = y or 0
							    local anchor = tostring(p or "")
							    local relp = tostring(rp or "")
							    if string.find(anchor, "BOTTOM", 1, true) or string.find(relp, "BOTTOM", 1, true) then
								    yy = (y or 0) - (dy or 0)
							    elseif string.find(anchor, "CENTER", 1, true) or string.find(relp, "CENTER", 1, true) then
								    yy = (y or 0) - ((dy or 0) * 0.5)
							    end
							    pcall(pb.SetPoint, pb, p or "TOP", rel, rp or p or "TOP", x or 0, yy or 0)
						    end
					    end
					
					    local scaleY = math.max(0.5, math.min(2.0, pct / 100))
					
					    -- Capture original PowerBar height once
					    if pb and not pb._ScootUFOrigHeight then
						    if pb.GetHeight then
							    local ok, h = pcall(pb.GetHeight, pb)
							    if ok and h then pb._ScootUFOrigHeight = h end
						    end
					    end
					
					    -- CRITICAL: Always restore to original state FIRST
					    if pb and pb._ScootUFOrigHeight and pb.SetHeight then
						    pcall(pb.SetHeight, pb, pb._ScootUFOrigHeight)
					    end
					    if pb and pb._ScootUFOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pb._ScootUFOrigPoints) do
							    pcall(pb.SetPoint, pb, pt[1] or "TOP", pt[2], pt[3] or pt[1] or "TOP", pt[4] or 0, pt[5] or 0)
						    end
					    end
					
					    if pct ~= 100 then
						    -- Scale the status bar frame height
						    if pb and pb.SetHeight and pb._ScootUFOrigHeight then
							    pcall(pb.SetHeight, pb, pb._ScootUFOrigHeight * scaleY)
						    end
						
						    -- Reposition the frame to grow downward (keep top fixed)
						    if pb and pb._ScootUFOrigHeight then
							    local dy = (pb._ScootUFOrigHeight * (scaleY - 1))
							    if dy and dy ~= 0 then
								    reapplyPBPointsWithBottomOffset(dy)
							    end
						    end
						
						    -- DO NOT touch the StatusBar texture - it's managed automatically by the StatusBar widget
						    -- REMOVE the mask entirely when scaling - it causes rendering artifacts
						    if tex and mask and tex.RemoveMaskTexture then
							    pcall(tex.RemoveMaskTexture, tex, mask)
						    end

							if Util and Util.ApplyFullPowerSpikeScale then
								Util.ApplyFullPowerSpikeScale(pb, scaleY)
							end
						    -- NOTE: Do NOT call SetValue to "refresh" the texture - it taints the protected StatusBar
						    -- and causes "blocked from an action" errors when Blizzard later calls Show().
						    -- The StatusBar refreshes automatically when its dimensions change.
					    else
						    -- Restore (already done above in the restore-first step)
						    -- Re-apply mask ONLY if both Width and Height are at 100%
						    -- (Width scaling removes the mask, so we shouldn't re-apply it if Width is still scaled)
						    if pb and mask and widthPct == 100 then
							    ensureMaskOnBarTexture(pb, mask)
						    end

							if Util and Util.ApplyFullPowerSpikeScale then
								Util.ApplyFullPowerSpikeScale(pb, 1)
							end
					    end
				    else
					    -- Not scalable (Target/Focus with default fill): ensure we restore any prior height/anchors
					    -- Restore power bar frame
					    if pb and pb._ScootUFOrigHeight and pb.SetHeight then
						    pcall(pb.SetHeight, pb, pb._ScootUFOrigHeight)
					    end
					    if pb and pb._ScootUFOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pb._ScootUFOrigPoints) do
							    pcall(pb.SetPoint, pb, pt[1] or "TOP", pt[2], pt[3] or pt[1] or "TOP", pt[4] or 0, pt[5] or 0)
						    end
					    end
						if Util and Util.ApplyFullPowerSpikeScale then
							Util.ApplyFullPowerSpikeScale(pb, 1)
						end
				    end
                end
			end
						
            -- Power Bar positioning offsets / custom positioning (Player only)
            do
                capturePowerBarBaseline(pb)
                local customHandled = applyCustomPowerBarPosition(unit, pb, cfg)
                if not customHandled and not inCombat then
                    local offsetX = tonumber(cfg.powerBarOffsetX) or 0
                    local offsetY = tonumber(cfg.powerBarOffsetY) or 0

                    if not pb._ScootPowerBarOrigPoints then
                        pb._ScootPowerBarOrigPoints = {}
                        for i = 1, pb:GetNumPoints() do
                            local point, relativeTo, relativePoint, xOfs, yOfs = pb:GetPoint(i)
                            table.insert(pb._ScootPowerBarOrigPoints, { point, relativeTo, relativePoint, xOfs, yOfs })
                        end
                    end

                    if offsetX ~= 0 or offsetY ~= 0 then
                        if pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            for _, pt in ipairs(pb._ScootPowerBarOrigPoints) do
                                local newX = (pt[4] or 0) + offsetX
                                local newY = (pt[5] or 0) + offsetY
                                pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", newX, newY)
                            end
                        end
                    else
                        if pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            for _, pt in ipairs(pb._ScootPowerBarOrigPoints) do
                                pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
                            end
                        end
                    end
                end
            end

            -- Power Bar custom border (mirrors Health Bar border settings; supports power-specific overrides)
            do
                local styleKey = cfg.powerBarBorderStyle or cfg.healthBarBorderStyle
                local tintEnabled
                if cfg.powerBarBorderTintEnable ~= nil then
                    tintEnabled = not not cfg.powerBarBorderTintEnable
                else
                    tintEnabled = not not cfg.healthBarBorderTintEnable
                end
                local baseTint = type(cfg.powerBarBorderTintColor) == "table" and cfg.powerBarBorderTintColor or cfg.healthBarBorderTintColor
                local tintColor = type(baseTint) == "table" and {
                    baseTint[1] or 1,
                    baseTint[2] or 1,
                    baseTint[3] or 1,
                    baseTint[4] or 1,
                } or {1, 1, 1, 1}
                local thickness = tonumber(cfg.powerBarBorderThickness) or tonumber(cfg.healthBarBorderThickness) or 1
                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                local inset = (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInset) or 0
                -- PetFrame is managed/protected: do not create or level custom border frames.
                if unit ~= "Pet" and cfg.useCustomBorders then
                    if styleKey == "none" or styleKey == nil then
                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                    else
                        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                        local color
                        if tintEnabled then
                            color = tintColor
                        else
                            if styleDef then
                                color = {1, 1, 1, 1}
                            else
                                color = {0, 0, 0, 1}
                            end
                        end
                        local handled = false
                        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                            if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                            handled = addon.BarBorders.ApplyToBarFrame(pb, styleKey, {
                                color = color,
                                thickness = thickness,
                                levelOffset = 1,
                                containerParent = (pb and pb:GetParent()) or nil,
                                inset = inset,
                            })
                        end
                        if not handled then
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                            if addon.Borders and addon.Borders.ApplySquare then
                                local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                local baseY = (thickness <= 1) and 0 or 1
                                local baseX = 1
                                local expandY = baseY - inset
                                local expandX = baseX - inset
                                if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                addon.Borders.ApplySquare(pb, {
                                    size = thickness,
                                    color = sqColor,
                                    layer = "OVERLAY",
                                    layerSublevel = 3,
                                    expandX = expandX,
                                    expandY = expandY,
                                })
                            end
                        end
                        -- Keep ordering stable for power bar borders as well
                        ensureTextAndBorderOrdering(unit)
                        if pb and not pb._ScootUFZOrderHooked and pb.HookScript then
                            pb:HookScript("OnSizeChanged", function()
                                if InCombatLockdown and InCombatLockdown() then
                                    return
                                end
                                ensureTextAndBorderOrdering(unit)
                            end)
                            pb._ScootUFZOrderHooked = true
                        end
                    end
                else
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                end

                -- NOTE: Spark height adjustment code was removed. The previous implementation
                -- of shrinking the spark to prevent it from extending below custom borders
                -- was causing worse visual artifacts than the original minor issue.
                -- Letting Blizzard manage the spark naturally is the better approach.
            end
        end

        -- Nudge Blizzard to re-evaluate atlases/masks immediately after restoration
        -- NOTE: Pet is excluded because PetFrame is a managed/protected frame. Calling
        -- PetFrame_Update from addon code taints the frame, causing Edit Mode's
        -- InitSystemAnchors to be blocked from calling SetPoint on PetFrame. (see DEBUG.md)
        local function refresh(unitKey)
            if unitKey == "Player" then
                if _G.PlayerFrame_Update then pcall(_G.PlayerFrame_Update) end
            elseif unitKey == "Target" then
                if _G.TargetFrame_Update then pcall(_G.TargetFrame_Update, _G.TargetFrame) end
            elseif unitKey == "Focus" then
                if _G.FocusFrame_Update then pcall(_G.FocusFrame_Update, _G.FocusFrame) end
            -- Pet intentionally excluded: PetFrame is a managed frame; calling PetFrame_Update
            -- from addon code taints the frame and breaks Edit Mode positioning.
            end
        end

        -- Stock frame art (includes the health bar border)
        do
            local ft = resolveUnitFrameFrameTexture(unit)
            if ft then
                local function compute()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    local hide = cfg2 and (cfg2.useCustomBorders or cfg2.healthBarHideBorder)
                    return hide and 0 or 1
                end
                applyAlpha(ft, compute())
                hookAlphaEnforcer(ft, compute)
            end
        end

        -- Boss-specific frame art: Handle all 5 Boss frames (Boss1TargetFrame through Boss5TargetFrame)
        -- Unlike other unit frames where there's a single frame per unit, Boss frames have 5 individual frames
        -- that all share the same config (db.unitFrames.Boss). We must apply hiding to each one.
        if unit == "Boss" then
            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                if bossFrame and bossFrame.TargetFrameContainer then
                    local bossFT = bossFrame.TargetFrameContainer.FrameTexture
                    if bossFT then
                        local function computeBossAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            local hide = cfgBoss and (cfgBoss.useCustomBorders or cfgBoss.healthBarHideBorder)
                            return hide and 0 or 1
                        end
                        applyAlpha(bossFT, computeBossAlpha())
                        hookAlphaEnforcer(bossFT, computeBossAlpha)
                    end
                    -- Also hide the Flash (aggro/threat glow) if present on Boss frames
                    local bossFlash = bossFrame.TargetFrameContainer.Flash
                    if bossFlash then
                        local function computeBossFlashAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
                        end
                        applyAlpha(bossFlash, computeBossFlashAlpha())
                        hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
                    end

                    -- Hide ReputationColor strip (Boss1TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor)
                    -- when "Hide Blizzard Frame Art & Animations" (useCustomBorders) is enabled.
                    local bossReputationColor = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                    if bossReputationColor then
                        local function computeBossReputationAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
                        end
                        applyAlpha(bossReputationColor, computeBossReputationAlpha())
                        hookAlphaEnforcer(bossReputationColor, computeBossReputationAlpha)
                    end
                end
            end
        end

        -- Player-specific frame art
        if unit == "Player" and _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
            local container = _G.PlayerFrame.PlayerFrameContainer
            local altTex = container.AlternatePowerFrameTexture
            local vehicleTex = container.VehicleFrameTexture

            local function compute()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                local cfg2 = unitFrames2 and rawget(unitFrames2, "Player") or nil
                return (cfg2 and cfg2.useCustomBorders) and 0 or 1
            end

            if altTex then
                applyAlpha(altTex, compute())
                hookAlphaEnforcer(altTex, compute)
            end
            if vehicleTex then
                applyAlpha(vehicleTex, compute())
                hookAlphaEnforcer(vehicleTex, compute)
            end
        end
        
        -- Hide static visual elements when Use Custom Borders is enabled.
        -- Rationale: These elements (ReputationColor for Target/Focus, FrameFlash for Player, Flash for Target) have
        -- fixed positions that cannot be adjusted. Since ScooterMod allows users to reposition and
        -- resize health/power bars independently, these static overlays would remain in their original
        -- positions while the bars they're meant to surround/backdrop move elsewhere. This creates
        -- visual confusion, so we disable them when custom borders are active.
        
        -- Hide ReputationColor frame for Target/Focus when Use Custom Borders is enabled
        if (unit == "Target" or unit == "Focus") and cfg.useCustomBorders then
            local frame = getUnitFrameFor(unit)
            if frame then
                local reputationColor
                if unit == "Target" and _G.TargetFrame then
                    reputationColor = _G.TargetFrame.TargetFrameContent 
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                elseif unit == "Focus" and _G.FocusFrame then
                    reputationColor = _G.FocusFrame.TargetFrameContent
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                end
                if reputationColor then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                        return (cfg2 and cfg2.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(reputationColor, 0)
                    hookAlphaEnforcer(reputationColor, computeAlpha)
                end
            end
        elseif (unit == "Target" or unit == "Focus") then
            -- Restore ReputationColor when Use Custom Borders is disabled
            local frame = getUnitFrameFor(unit)
            if frame then
                local reputationColor
                if unit == "Target" and _G.TargetFrame then
                    reputationColor = _G.TargetFrame.TargetFrameContent 
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                elseif unit == "Focus" and _G.FocusFrame then
                    reputationColor = _G.FocusFrame.TargetFrameContent
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                end
                if reputationColor then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                        return (cfg2 and cfg2.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(reputationColor, 1)
                    hookAlphaEnforcer(reputationColor, computeAlpha)
                end
            end

    function addon.UnitFrames_GetPowerBarScreenPosition()
        local frame = getUnitFrameFor("Player")
        if not frame then
            return 0, 0
        end
        local pb = resolvePowerBar(frame, "Player")
        if not pb then
            return 0, 0
        end
        local x, y = getFrameScreenOffsets(pb)
        return clampScreenCoordinate(x), clampScreenCoordinate(y)
    end
        end
        
        -- Hide FrameFlash (aggro/threat glow) for Player when Use Custom Borders is enabled
        if unit == "Player" then
            if _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
                local frameFlash = _G.PlayerFrame.PlayerFrameContainer.FrameFlash
                if frameFlash then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfgP = unitFrames2 and rawget(unitFrames2, "Player") or nil
                        return (cfgP and cfgP.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(frameFlash, computeAlpha())
                    hookAlphaEnforcer(frameFlash, computeAlpha)
                end
            end
        end
        
        -- Hide Flash (aggro/threat glow) for Target when Use Custom Borders is enabled
        if unit == "Target" then
            if _G.TargetFrame and _G.TargetFrame.TargetFrameContainer then
                local targetFlash = _G.TargetFrame.TargetFrameContainer.Flash
                if targetFlash then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfgT = unitFrames2 and rawget(unitFrames2, "Target") or nil
                        return (cfgT and cfgT.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(targetFlash, computeAlpha())
                    hookAlphaEnforcer(targetFlash, computeAlpha)
                end
            end
        end
        
        -- Hide Flash (aggro/threat glow) for Focus when Use Custom Borders is enabled
        if unit == "Focus" then
            if _G.FocusFrame and _G.FocusFrame.TargetFrameContainer then
                local focusFlash = _G.FocusFrame.TargetFrameContainer.Flash
                if focusFlash then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfgF = unitFrames2 and rawget(unitFrames2, "Focus") or nil
                        return (cfgF and cfgF.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(focusFlash, computeAlpha())
                    hookAlphaEnforcer(focusFlash, computeAlpha)
                end
            end
        end
        refresh(unit)
    end

    function addon.ApplyUnitFrameBarTexturesFor(unit)
        applyForUnit(unit)
    end

    function addon.ApplyAllUnitFrameBarTextures()
        applyForUnit("Player")
        applyForUnit("Target")
        applyForUnit("Focus")
        applyForUnit("Boss")
        applyForUnit("Pet")
        applyForUnit("TargetOfTarget")
    end

    -- =========================================================================
    -- Vehicle and Alternate Power Frame Texture Visibility Enforcement
    -- =========================================================================
    -- When entering/exiting vehicles, Blizzard's PlayerFrame_ToVehicleArt() and
    -- PlayerFrame_ToPlayerArt() explicitly show/hide VehicleFrameTexture and
    -- AlternatePowerFrameTexture. These helpers re-enforce hiding when
    -- "Use Custom Borders" is enabled.

    -- Enforce VehicleFrameTexture visibility based on Use Custom Borders setting
    local function EnforceVehicleFrameTextureVisibility()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames") or nil
        local cfg = unitFrames and rawget(unitFrames, "Player") or nil
        if not cfg then return end
        if cfg.useCustomBorders ~= true then return end -- Only enforce when custom borders enabled
        
        local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
        local vehicleTex = container and container.VehicleFrameTexture
        if vehicleTex and vehicleTex.SetShown then
            pcall(vehicleTex.SetShown, vehicleTex, false)
        end
    end

    -- Enforce AlternatePowerFrameTexture visibility based on Use Custom Borders setting
    local function EnforceAlternatePowerFrameTextureVisibility()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames") or nil
        local cfg = unitFrames and rawget(unitFrames, "Player") or nil
        if not cfg then return end
        if cfg.useCustomBorders ~= true then return end -- Only enforce when custom borders enabled
        
        local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
        local altTex = container and container.AlternatePowerFrameTexture
        if altTex and altTex.SetShown then
            pcall(altTex.SetShown, altTex, false)
        end
    end

    -- Install stable hooks to re-assert z-order after Blizzard refreshers
    local function installUFZOrderHooks()
        local function defer(unit)
            if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, function() ensureTextAndBorderOrdering(unit) end) else ensureTextAndBorderOrdering(unit) end
        end
        -- NOTE: Texture re-application hooks were removed (2025-11-14) as dead code.
        -- The z-order enforcement hooks remain active via installUFZOrderHooks().
    end

    if not addon._UFZOrderHooksInstalled then
        addon._UFZOrderHooksInstalled = true
        -- Install hooks synchronously to ensure they're ready before ApplyStyles() runs
        installUFZOrderHooks()
    end

    -- =========================================================================
    -- Vehicle/Alternate Power Frame Texture Visibility Hooks
    -- =========================================================================
    -- Hook Blizzard's vehicle art transition functions to re-enforce hiding
    -- when "Use Custom Borders" is enabled.

    if not addon._VehicleArtHooksInstalled then
        addon._VehicleArtHooksInstalled = true

        -- Hook PlayerFrame_ToVehicleArt to re-enforce VehicleFrameTexture hiding
        -- This is called when entering a vehicle (Blizzard shows VehicleFrameTexture)
        if _G.hooksecurefunc and type(_G.PlayerFrame_ToVehicleArt) == "function" then
            _G.hooksecurefunc("PlayerFrame_ToVehicleArt", function()
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, EnforceVehicleFrameTextureVisibility)
                else
                    EnforceVehicleFrameTextureVisibility()
                end
            end)
        end

        -- Hook PlayerFrame_ToPlayerArt to re-enforce AlternatePowerFrameTexture hiding
        -- This is called when exiting a vehicle (Blizzard shows AlternatePowerFrameTexture)
        if _G.hooksecurefunc and type(_G.PlayerFrame_ToPlayerArt) == "function" then
            _G.hooksecurefunc("PlayerFrame_ToPlayerArt", function()
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, EnforceAlternatePowerFrameTextureVisibility)
                else
                    EnforceAlternatePowerFrameTextureVisibility()
                end
            end)
        end

        -- Install Show() hooks directly on the textures for extra robustness.
        -- This catches ANY Show() call, not just those from known Blizzard functions.
        local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
        
        -- VehicleFrameTexture Show() hook
        local vehicleTex = container and container.VehicleFrameTexture
        if vehicleTex and not vehicleTex._ScootShowHooked then
            vehicleTex._ScootShowHooked = true
            hooksecurefunc(vehicleTex, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                local unitFrames = db and rawget(db, "unitFrames") or nil
                local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                if cfgP and cfgP.useCustomBorders == true then
                    if self.Hide then pcall(self.Hide, self) end
                end
            end)
        end

        -- AlternatePowerFrameTexture Show() hook
        local altTex = container and container.AlternatePowerFrameTexture
        if altTex and not altTex._ScootShowHooked then
            altTex._ScootShowHooked = true
            hooksecurefunc(altTex, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                local unitFrames = db and rawget(db, "unitFrames") or nil
                local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                if cfgP and cfgP.useCustomBorders == true then
                    if self.Hide then pcall(self.Hide, self) end
                end
            end)
        end
    end

    -- Pre-emptive hiding and alpha hooks are now provided by the Preemptive module
    addon.PreemptiveHideTargetElements = Preemptive.hideTargetElements
    addon.PreemptiveHideFocusElements = Preemptive.hideFocusElements
    addon.InstallEarlyUnitFrameAlphaHooks = Preemptive.installEarlyAlphaHooks

end

-- Note: Raid Frame Health Bar Styling and Overlay have been moved to bars/raidframes.lua
-- The module provides: addon.ApplyRaidFrameHealthBarStyle, addon.ApplyRaidFrameHealthOverlays,
-- addon.RestoreRaidFrameHealthOverlays

-- Note: Raid Frame Text Styling has been moved to bars/raidframes.lua
-- The module provides: addon.ApplyRaidFrameTextStyle, addon.ApplyRaidFrameNameOverlays,
-- addon.RestoreRaidFrameNameOverlays, addon.ApplyRaidFrameStatusTextStyle, addon.ApplyRaidFrameGroupTitlesStyle


-- Note: Party Frame Health Bar Styling and Overlay have been moved to bars/partyframes.lua
-- The module provides: addon.ApplyPartyFrameHealthBarStyle, addon.ApplyPartyFrameHealthOverlays,
-- addon.RestorePartyFrameHealthOverlays

-- Note: Party Frame Text Styling has been moved to bars/partyframes.lua
-- The module provides: addon.ApplyPartyFrameTextStyle, addon.ApplyPartyFrameNameOverlays,
-- addon.RestorePartyFrameNameOverlays, addon.ApplyPartyFrameTitleStyle


--------------------------------------------------------------------------------
-- Party Frame Overlay Restore (Profile Switch / Category Reset)
--------------------------------------------------------------------------------
-- Centralized function to restore all party frames to stock Blizzard appearance.
-- Called during profile switches when the new profile has no party frame config,
-- or when the user explicitly resets the Party Frames category to defaults.
--------------------------------------------------------------------------------

function addon.RestoreAllPartyFrameOverlays()
    -- Restore health bar overlays
    if addon.RestorePartyFrameHealthOverlays then
        addon.RestorePartyFrameHealthOverlays()
    end
    -- Restore name text overlays
    if addon.RestorePartyFrameNameOverlays then
        addon.RestorePartyFrameNameOverlays()
    end
end

--------------------------------------------------------------------------------
-- Raid Frame Overlay Restore (Profile Switch / Category Reset)
--------------------------------------------------------------------------------
-- Centralized function to restore all raid frames to stock Blizzard appearance.
-- Called during profile switches when the new profile has no raid frame config,
-- or when the user explicitly resets the Raid Frames category to defaults.
--------------------------------------------------------------------------------

function addon.RestoreAllRaidFrameOverlays()
    -- Restore health bar overlays
    if addon.RestoreRaidFrameHealthOverlays then
        addon.RestoreRaidFrameHealthOverlays()
    end
    -- Restore name text overlays
    if addon.RestoreRaidFrameNameOverlays then
        addon.RestoreRaidFrameNameOverlays()
    end
end

