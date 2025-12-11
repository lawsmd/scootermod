local addonName, addon = ...
local Util = addon.ComponentsUtil
local CleanupIconBorderAttachments = Util.CleanupIconBorderAttachments
local ClampOpacity = Util.ClampOpacity
local PlayerInCombat = Util.PlayerInCombat
local HideDefaultBarTextures = Util.HideDefaultBarTextures
local ToggleDefaultIconOverlay = Util.ToggleDefaultIconOverlay

local function getUiScale()
    if UIParent and UIParent.GetEffectiveScale then
        local scale = UIParent:GetEffectiveScale()
        if scale and scale > 0 then
            return scale
        end
    end
    return 1
end

local function pixelsToUiUnits(px)
    return (tonumber(px) or 0) / getUiScale()
end

local function uiUnitsToPixels(u)
    return math.floor(((tonumber(u) or 0) * getUiScale()) + 0.5)
end

local function clampScreenCoordinate(value)
    local v = tonumber(value) or 0
    if v > 2000 then
        v = 2000
    elseif v < -2000 then
        v = -2000
    end
    return math.floor(v + (v >= 0 and 0.5 or -0.5))
end

local function getFrameScreenOffsets(frame)
    if not (frame and frame.GetCenter and UIParent and UIParent.GetCenter) then
        return 0, 0
    end
    local fx, fy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (fx and fy and px and py) then
        return 0, 0
    end
    return math.floor((fx - px) + 0.5), math.floor((fy - py) + 0.5)
end

local pendingPowerBarUnits = {}
local powerBarCombatWatcher = nil

local function ensurePowerBarCombatWatcher()
    if powerBarCombatWatcher then
        return
    end
    powerBarCombatWatcher = CreateFrame("Frame")
    powerBarCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    powerBarCombatWatcher:SetScript("OnEvent", function()
        for unit in pairs(pendingPowerBarUnits) do
            pendingPowerBarUnits[unit] = nil
            if addon.ApplyUnitFrameBarTexturesFor then
                addon.ApplyUnitFrameBarTexturesFor(unit)
            end
        end
    end)
end

local function queuePowerBarReapply(unit)
    ensurePowerBarCombatWatcher()
    pendingPowerBarUnits[unit] = true
end

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

local function applyCustomPowerBarPosition(unit, pb, cfg)
    if unit ~= "Player" or not cfg or not pb then
        return false
    end
    if not cfg.powerBarCustomPositionEnabled then
        -- Restore original state when custom positioning is disabled
        if pb._ScootPowerBarCustomActive then
            restorePowerBarBaseline(pb)
            pb._ScootPowerBarCustomActive = nil
        end
        return false
    end

    if PlayerInCombat() then
        queuePowerBarReapply(unit)
        return true
    end

    capturePowerBarBaseline(pb)
    ensurePowerBarCustomSeed(cfg, pb)

    local posX = clampScreenCoordinate(cfg.powerBarPosX or 0)
    local posY = clampScreenCoordinate(cfg.powerBarPosY or 0)

    -- POLICY COMPLIANT: Do NOT re-parent the frame. Instead:
    -- 1. Keep the frame parented where Blizzard placed it
    -- 2. Use SetIgnoreFramePositionManager to prevent layout manager from overriding
    -- 3. Anchor to UIParent for absolute screen positioning (frames CAN anchor to non-parents)
    -- This preserves scale, text styling, and all other customizations.
    if pb.SetIgnoreFramePositionManager then
        pcall(pb.SetIgnoreFramePositionManager, pb, true)
    end
    if pb.ClearAllPoints and pb.SetPoint then
        pcall(pb.ClearAllPoints, pb)
        pcall(pb.SetPoint, pb, "CENTER", UIParent, "CENTER", pixelsToUiUnits(posX), pixelsToUiUnits(posY))
    end
    pb._ScootPowerBarCustomActive = true
    return true
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
    local function getUnitFrameFor(unit)
        local mgr = _G.EditModeManagerFrame
        local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
        local EMSys = _G.Enum and _G.Enum.EditModeSystem
        if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
            if unit == "Pet" then return _G.PetFrame end
            return nil
        end
        local idx = nil
        if EM then
            idx = (unit == "Player" and EM.Player)
                or (unit == "Target" and EM.Target)
                or (unit == "Focus" and EM.Focus)
                or (unit == "Pet" and EM.Pet)
        end
        if idx then
            return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
        end
        if unit == "Pet" then return _G.PetFrame end
        return nil
    end

    local function findStatusBarByHints(root, hintsTbl, excludesTbl)
        if not root then return nil end
        local hints = hintsTbl or {}
        local excludes = excludesTbl or {}
        local found
        local function matchesName(obj)
            local nm = (obj and obj.GetName and obj:GetName()) or (obj and obj.GetDebugName and obj:GetDebugName()) or ""
            if type(nm) ~= "string" then return false end
            local lnm = string.lower(nm)
            for _, ex in ipairs(excludes) do
                if ex and string.find(lnm, string.lower(ex), 1, true) then
                    return false
                end
            end
            for _, h in ipairs(hints) do
                if h and string.find(lnm, string.lower(h), 1, true) then
                    return true
                end
            end
            return false
        end
        local function scan(obj)
            if not obj or found then return end
            if obj.GetObjectType and obj:GetObjectType() == "StatusBar" then
                if matchesName(obj) then
                    found = obj; return
                end
            end
            if obj.GetChildren then
                local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
                for i = 1, m do
                    local c = select(i, obj:GetChildren())
                    scan(c)
                    if found then return end
                end
            end
        end
        scan(root)
        return found
    end

    local function getNested(root, ...)
        local cur = root
        for i = 1, select('#', ...) do
            local key = select(i, ...)
            if not cur or type(cur) ~= "table" then return nil end
            cur = cur[key]
        end
        return cur
    end

    local function resolveHealthBar(frame, unit)
        -- Deterministic paths from Framestack findings; fallback to conservative search only if missing
        if unit == "Pet" then return _G.PetFrameHealthBar end
        if unit == "Player" then
            local root = _G.PlayerFrame
            local hb = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer", "HealthBar")
            if hb then return hb end
        elseif unit == "Target" then
            local root = _G.TargetFrame
            local hb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
            if hb then return hb end
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            local hb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
            if hb then return hb end
        end
        -- Fallbacks
        if frame and frame.HealthBarsContainer and frame.HealthBarsContainer.HealthBar then return frame.HealthBarsContainer.HealthBar end
        return findStatusBarByHints(frame, {"HealthBarsContainer.HealthBar", ".HealthBar", "HealthBar"}, {"Prediction", "Absorb", "Mana"})
    end

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

    -- (moved ensureTextAndBorderOrdering below resolver functions)

	-- Parent container that holds both Health and Power areas (content main)
	local function resolveUFContentMain(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Pet" then
			return _G.PetFrame
		end
		return nil
	end

    local function resolveHealthContainer(frame, unit)
        if unit == "Pet" then return _G.PetFrame and _G.PetFrame.HealthBarContainer end
        if unit == "Player" then
            local root = _G.PlayerFrame
            local c = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer")
            if c then return c end
        elseif unit == "Target" then
            local root = _G.TargetFrame
            local c = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer")
            if c then return c end
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            local c = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer")
            if c then return c end
        end
        return frame and frame.HealthBarsContainer or nil
    end

    local function resolvePowerBar(frame, unit)
        if unit == "Pet" then return _G.PetFrameManaBar end
        if unit == "Player" then
            local root = _G.PlayerFrame
            local mb = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar")
            if mb then return mb end
        elseif unit == "Target" then
            local root = _G.TargetFrame
            local mb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
            if mb then return mb end
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            local mb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
            if mb then return mb end
        end
        if frame and frame.ManaBar then return frame.ManaBar end
        return findStatusBarByHints(frame, {"ManaBar", ".ManaBar", "PowerBar"}, {"Prediction"})
    end

    -- Resolve the global Alternate Power Bar for the Player frame. This is a standalone
    -- StatusBar named "AlternatePowerBar" managed by Blizzard's AlternatePowerBarBaseMixin.
    local function resolveAlternatePowerBar()
        local bar = _G.AlternatePowerBar
        if bar and bar.GetObjectType and bar:GetObjectType() == "StatusBar" then
            return bar
        end
        return nil
    end

    -- Resolve mask textures per unit and bar type to ensure proper shaping after texture swaps
    local function resolveHealthMask(unit)
        if unit == "Player" then
            local root = _G.PlayerFrame
            return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBarMask
        elseif unit == "Target" then
            local root = _G.TargetFrame
            return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarMask
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarMask
        elseif unit == "Pet" then
            return _G.PetFrameHealthBarMask
        end
        return nil
    end

    local function resolvePowerMask(unit)
        if unit == "Player" then
            local root = _G.PlayerFrame
            return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
                and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
                and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
                and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.ManaBarMask
        elseif unit == "Target" then
            local root = _G.TargetFrame
            return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarMask
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarMask
        elseif unit == "Pet" then
            return _G.PetFrameManaBarMask
        end
        return nil
    end

    -- Compute border holder level below current text and enforce ordering deterministically
    local function ensureTextAndBorderOrdering(unit)
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

    -- Resolve the stock unit frame frame art (the large atlas that includes the health bar border)
    local function resolveUnitFrameFrameTexture(unit)
        if unit == "Player" then
            local root = _G.PlayerFrame
            return root and root.PlayerFrameContainer and root.PlayerFrameContainer.FrameTexture or nil
        elseif unit == "Target" then
            local root = _G.TargetFrame
            return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
        elseif unit == "Pet" then
            return _G.PetFrameTexture
        end
        return nil
    end

    local function ensureMaskOnBarTexture(bar, mask)
        if not bar or not mask or not bar.GetStatusBarTexture then return end
        local tex = bar:GetStatusBarTexture()
        if not tex or not tex.AddMaskTexture then return end
        -- Re-apply mask to the current texture instance and enforce Blizzard's texel snapping settings
        pcall(tex.AddMaskTexture, tex, mask)
        if tex.SetTexelSnappingBias then pcall(tex.SetTexelSnappingBias, tex, 0) end
        if tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
        if tex.SetHorizTile then pcall(tex.SetHorizTile, tex, false) end
        if tex.SetVertTile then pcall(tex.SetVertTile, tex, false) end
        if tex.SetTexCoord then pcall(tex.SetTexCoord, tex, 0, 1, 0, 1) end
    end

    -- Get default background color for unit frame bars (fallback when no custom color is set)
    local function getDefaultBackgroundColor(unit, barKind)
        -- Based on Blizzard source: Player frame HealthBar.Background uses BLACK_FONT_COLOR (0, 0, 0)
        -- Target/Focus/Pet don't have explicit Background textures in XML, use black as well
        -- Power bars (ManaBar) don't have Background textures in XML either, use black
        return 0, 0, 0, 1
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
        if reverse then
            overlay:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
            overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        else
            overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        end
    end

    local function ensureRectHealthOverlay(unit, bar, cfg)
        if not bar then return end

        -- Only Target/Focus use this overlay, and only when the portrait is hidden.
        if unit ~= "Target" and unit ~= "Focus" then
            if bar.ScooterRectFill then
                bar._ScootRectActive = false
                bar.ScooterRectFill:Hide()
            end
            return
        end

        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        local ufCfg = db.unitFrames[unit] or {}
        local portraitCfg = ufCfg.portrait or {}
        local hidePortrait = (portraitCfg.hidePortrait == true)

        bar._ScootRectReverseFill = not not cfg.healthBarReverseFill
        bar._ScootRectActive = hidePortrait and true or false

        if not hidePortrait then
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

        -- Copy the current health bar texture/tint so the overlay visually matches.
        local tex = bar:GetStatusBarTexture()
        if tex then
            local okTex, pathOrTex = pcall(tex.GetTexture, tex)
            if okTex and type(pathOrTex) == "string" and pathOrTex ~= "" then
                bar.ScooterRectFill:SetTexture(pathOrTex)
            else
                if bar.ScooterRectFill.SetColorTexture then
                    bar.ScooterRectFill:SetColorTexture(1, 1, 1, 1)
                end
            end

            if tex.GetVertexColor and bar.ScooterRectFill.SetVertexColor then
                local ok, r, g, b, a = pcall(tex.GetVertexColor, tex)
                if ok then
                    bar.ScooterRectFill:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
                else
                    bar.ScooterRectFill:SetVertexColor(1, 1, 1, 1)
                end
            end
        end

        updateRectHealthOverlay(unit, bar)
    end

    local function applyToBar(bar, textureKey, colorMode, tint, unitForClass, barKind, unitForPower)
        if not bar or type(bar.GetStatusBarTexture) ~= "function" then return end
        
        -- Power bars with default texture + default color: be completely hands-off.
        -- Blizzard dynamically updates power bar texture AND vertex color when power type changes
        -- (e.g., Druid switching between Mana/Energy forms). If we touch ANYTHING here, we risk
        -- overwriting Blizzard's correctly-set state with our stale captured values. By returning
        -- early, we let Blizzard's native system handle everything.
        local isDefaultTexture = (textureKey == nil or textureKey == "" or textureKey == "default")
        local isDefaultColor = (colorMode == nil or colorMode == "" or colorMode == "default")
        if (barKind == "power" or barKind == "altpower") and isDefaultTexture and isDefaultColor then
            return
        end
        
        local tex = bar:GetStatusBarTexture()
        -- Capture original once
        if not bar._ScootUFOrigCaptured then
            if tex and tex.GetAtlas then
                local ok, atlas = pcall(tex.GetAtlas, tex)
                if ok and atlas then bar._ScootUFOrigAtlas = atlas end
            end
			if tex and tex.GetTexture then
				local ok, path = pcall(tex.GetTexture, tex)
				if ok and path then
					-- Some Blizzard status bars use atlases; GetAtlas may return nil while GetTexture returns the atlas token.
					-- Prefer treating such strings as atlases when possible to avoid spritesheet rendering on restore.
					local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(path) ~= nil
					if isAtlas then
						bar._ScootUFOrigAtlas = bar._ScootUFOrigAtlas or path
					else
						bar._ScootUFOrigPath = path
					end
				end
			end
            if tex and tex.GetVertexColor then
                local ok, r, g, b, a = pcall(tex.GetVertexColor, tex)
                if ok then bar._ScootUFOrigVertex = { r or 1, g or 1, b or 1, a or 1 } end
            end
            bar._ScootUFOrigCaptured = true
        end

        local isCustom = type(textureKey) == "string" and textureKey ~= "" and textureKey ~= "default"
        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(textureKey)
        if isCustom and resolvedPath then
            if bar.SetStatusBarTexture then
                -- Mark this write so any SetStatusBarTexture hook can ignore it (avoid recursion)
                bar._ScootUFInternalTextureWrite = true
                pcall(bar.SetStatusBarTexture, bar, resolvedPath)
                bar._ScootUFInternalTextureWrite = nil
            end
            -- Re-fetch the current texture after swapping to ensure subsequent operations target the new texture
            tex = bar:GetStatusBarTexture()
            local r, g, b, a = 1, 1, 1, 1
            if colorMode == "custom" and type(tint) == "table" then
                r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
            elseif colorMode == "class" then
                if addon.GetClassColorRGB then
                    local cr, cg, cb = addon.GetClassColorRGB(unitForClass or "player")
                    r, g, b, a = cr or 1, cg or 1, cb or 1, 1
                end
            elseif colorMode == "texture" then
                -- Apply white (no tint) to preserve texture's original colors
                r, g, b, a = 1, 1, 1, 1
            elseif colorMode == "default" then
                -- When using a custom texture, "Default" should tint to the stock bar color
				if barKind == "cast" then
					-- Stock cast bar yellow from CastingBarFrame mixin.
					r, g, b, a = 1.0, 0.7, 0.0, 1
				elseif barKind == "health" and addon.GetDefaultHealthColorRGB then
                    local hr, hg, hb = addon.GetDefaultHealthColorRGB()
                    r, g, b, a = hr or 0, hg or 1, hb or 0, 1
                elseif (barKind == "power" or barKind == "altpower") and addon.GetPowerColorRGB then
                    -- Power and Alternate Power bars both use the player's power color for Default.
                    local pr, pg, pb = addon.GetPowerColorRGB(unitForPower or unitForClass or "player")
                    r, g, b, a = pr or 1, pg or 1, pb or 1, 1
                else
                    local ov = bar._ScootUFOrigVertex
                    if type(ov) == "table" then r, g, b, a = ov[1] or 1, ov[2] or 1, ov[3] or 1, ov[4] or 1 end
                end
            end
            if tex and tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
        else
            -- Default texture path. If the user selected Class/Custom color, avoid restoring
            -- Blizzard's green/colored atlas because vertex-color multiplies and distorts hues.
            -- Instead, use a neutral white fill and apply the desired color; keep the stock mask.
            local r, g, b, a = 1, 1, 1, 1
            local wantsNeutral = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class")
            if wantsNeutral then
                if colorMode == "custom" then
                    r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
                elseif colorMode == "class" and addon.GetClassColorRGB then
                    local cr, cg, cb = addon.GetClassColorRGB(unitForClass or "player")
                    r, g, b, a = cr or 1, cg or 1, cb or 1, 1
                end
                if tex and tex.SetColorTexture then pcall(tex.SetColorTexture, tex, 1, 1, 1, 1) end
            else
                -- Default color: restore Blizzard's original fill
                -- Note: Power bars with default texture + default color already returned early above.
                if bar._ScootUFOrigCaptured then
                    if bar._ScootUFOrigAtlas then
                        if tex and tex.SetAtlas then
                            pcall(tex.SetAtlas, tex, bar._ScootUFOrigAtlas, true)
                        elseif bar.SetStatusBarTexture then
                            bar._ScootUFInternalTextureWrite = true
                            pcall(bar.SetStatusBarTexture, bar, bar._ScootUFOrigAtlas)
                            bar._ScootUFInternalTextureWrite = nil
                        end
                    elseif bar._ScootUFOrigPath then
                        local treatAsAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(bar._ScootUFOrigPath) ~= nil
                        if treatAsAtlas and tex and tex.SetAtlas then
                            pcall(tex.SetAtlas, tex, bar._ScootUFOrigPath, true)
                        elseif bar.SetStatusBarTexture then
                            bar._ScootUFInternalTextureWrite = true
                            pcall(bar.SetStatusBarTexture, bar, bar._ScootUFOrigPath)
                            bar._ScootUFInternalTextureWrite = nil
                        end
                    end
                end
                if barKind == "cast" then
                    -- Use Blizzard's stock cast bar yellow as the default color.
                    -- Based on Blizzard_CastingBarFrame.lua (CastingBarFrameMixin).
                    r, g, b, a = 1.0, 0.7, 0.0, 1
                else
                    local ov = bar._ScootUFOrigVertex or {1,1,1,1}
                    r, g, b, a = ov[1] or 1, ov[2] or 1, ov[3] or 1, ov[4] or 1
                end
            end
            if tex and tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
        end
    end

    -- Expose helpers for other modules (Cast Bar styling, etc.)
    addon._ApplyToStatusBar = applyToBar

    -- Apply background texture and color to a bar
    local function applyBackgroundToBar(bar, backgroundTextureKey, backgroundColorMode, backgroundTint, backgroundOpacity, unit, barKind)
        if not bar then return end
        
        -- Ensure we have a background texture frame at an appropriate sublevel so it appears
        -- behind the status bar fill but remains visible for cast bars.
        --
        -- For generic unit frame bars (health/power), we keep the background very low in the
        -- BACKGROUND stack (-8) so any stock art sits above it if present.
        --
        -- For CastingBarFrame-based bars (Player/Target/Focus cast bars), Blizzard defines a
        -- `Background` texture at BACKGROUND subLevel=2 (see CastingBarFrameBaseTemplate in
        -- wow-ui-source). Our earlier implementation created ScooterModBG at subLevel=-8,
        -- which meant the stock Background completely covered our overlay and made Scooter
        -- backgrounds effectively invisible even though the region existed in Framestack.
        --
        -- To keep behaviour consistent with other bars while making cast bar backgrounds
        -- visible, we render ScooterModBG above the stock Background (subLevel=3) but still
        -- on the BACKGROUND layer so the status bar fill and FX remain on top.
        if not bar.ScooterModBG then
            local layer = "BACKGROUND"
            local sublevel = -8
            if barKind == "cast" then
                sublevel = 3
            end
            bar.ScooterModBG = bar:CreateTexture(nil, layer, nil, sublevel)
            bar.ScooterModBG:SetAllPoints(bar)
        elseif barKind == "cast" then
            -- If we created ScooterModBG earlier (e.g., before cast styling was enabled),
            -- make sure it sits above the stock Background for CastingBarFrame.
            local _, currentSub = bar.ScooterModBG:GetDrawLayer()
            if currentSub == nil or currentSub < 3 then
                bar.ScooterModBG:SetDrawLayer("BACKGROUND", 3)
            end
        end
        
        -- Get opacity (default 50% based on Blizzard's dead/ghost state alpha)
        local opacity = tonumber(backgroundOpacity) or 50
        opacity = math.max(0, math.min(100, opacity)) / 100
        
        -- Check if we're using a custom background texture
        local isCustomTexture = type(backgroundTextureKey) == "string" and backgroundTextureKey ~= "" and backgroundTextureKey ~= "default"
        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(backgroundTextureKey)
        
        if isCustomTexture and resolvedPath then
            -- Apply custom texture
            pcall(bar.ScooterModBG.SetTexture, bar.ScooterModBG, resolvedPath)
            
            -- Apply color based on mode
            local r, g, b, a = 1, 1, 1, 1
            if backgroundColorMode == "custom" and type(backgroundTint) == "table" then
                r, g, b, a = backgroundTint[1] or 1, backgroundTint[2] or 1, backgroundTint[3] or 1, backgroundTint[4] or 1
            elseif backgroundColorMode == "texture" then
                -- Apply white (no tint) to preserve texture's original colors
                r, g, b, a = 1, 1, 1, 1
            elseif backgroundColorMode == "default" then
                r, g, b, a = getDefaultBackgroundColor(unit, barKind)
            end
            
            if bar.ScooterModBG.SetVertexColor then
                pcall(bar.ScooterModBG.SetVertexColor, bar.ScooterModBG, r, g, b, a)
            end
            -- Apply opacity
            if bar.ScooterModBG.SetAlpha then
                pcall(bar.ScooterModBG.SetAlpha, bar.ScooterModBG, opacity)
            end
            bar.ScooterModBG:Show()
            
            -- Hide Blizzard's stock Background texture when using a custom texture.
            -- CastingBarFrame-based bars (Player/Target/Focus cast bars) have a stock
            -- Background texture at BACKGROUND sublevel 2. Without hiding it, the stock
            -- background shows through since our ScooterModBG sits at sublevel 3.
            -- Use SetAlpha(0) instead of Hide() to avoid fighting Blizzard's internal logic.
            if bar.Background and bar.Background.SetAlpha then
                pcall(bar.Background.SetAlpha, bar.Background, 0)
            end
        else
            -- Default: always show our background with default black color
            -- We don't rely on Blizzard's stock Background texture since it's hidden by default
            pcall(bar.ScooterModBG.SetTexture, bar.ScooterModBG, nil)
            
            local r, g, b, a = getDefaultBackgroundColor(unit, barKind)
            if backgroundColorMode == "custom" and type(backgroundTint) == "table" then
                r, g, b, a = backgroundTint[1] or 1, backgroundTint[2] or 1, backgroundTint[3] or 1, backgroundTint[4] or 1
            end
            
            if bar.ScooterModBG.SetColorTexture then
                pcall(bar.ScooterModBG.SetColorTexture, bar.ScooterModBG, r, g, b, a)
            end
            -- Apply opacity
            if bar.ScooterModBG.SetAlpha then
                pcall(bar.ScooterModBG.SetAlpha, bar.ScooterModBG, opacity)
            end
            bar.ScooterModBG:Show()
            
            -- Restore Blizzard's stock Background texture visibility when using default.
            -- This ensures toggling back to "Default" restores the original look.
            if bar.Background and bar.Background.SetAlpha then
                pcall(bar.Background.SetAlpha, bar.Background, 1)
            end
        end
    end

    addon._ApplyBackgroundToStatusBar = applyBackgroundToBar

    local function applyForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        local cfg = db.unitFrames[unit] or {}
        local frame = getUnitFrameFor(unit)
        if not frame then return end
        local hb = resolveHealthBar(frame, unit)
        if hb then
            local colorModeHB = cfg.healthBarColorMode or "default"
            local texKeyHB = cfg.healthBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or "player"
			-- Avoid applying styling to Target/Focus before they exist; Blizzard will reset sizes on first Update
			if (unit == "Target" or unit == "Focus") and _G.UnitExists and not _G.UnitExists(unitId) then
				return
			end
            applyToBar(hb, texKeyHB, colorModeHB, cfg.healthBarTint, "player", "health", unitId)
            
            -- Apply background texture and color for Health Bar
            local bgTexKeyHB = cfg.healthBarBackgroundTexture or "default"
            local bgColorModeHB = cfg.healthBarBackgroundColorMode or "default"
            local bgOpacityHB = cfg.healthBarBackgroundOpacity or 50
            applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
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
                                    local baseY = (thickness <= 1) and 0 or 1
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

            -- Lightweight persistence hook for Player Health Bar color:
            -- If Blizzard later changes the bar's StatusBarColor (e.g., via class/aggro logic),
            -- re-apply the user's configured Foreground Color without re-running full styling.
            if unit == "Player" and not hb._ScootHealthColorHooked and _G.hooksecurefunc then
                hb._ScootHealthColorHooked = true
                _G.hooksecurefunc(hb, "SetStatusBarColor", function(self, ...)
                    -- CRITICAL: Do NOT call applyToBar during combat - it calls SetStatusBarTexture/SetVertexColor
                    -- on the protected StatusBar, which taints it and causes "blocked from an action" errors.
                    if InCombatLockdown and InCombatLockdown() then return end
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    db.unitFrames = db.unitFrames or {}
                    local cfgP = db.unitFrames.Player or {}
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

        local pb = resolvePowerBar(frame, unit)
        if pb then
            -- Cache combat state once for this styling pass. We avoid all geometry
            -- changes (width/height/anchors/offsets) while in combat to prevent
            -- taint on protected unit frames (see taint.log: TargetFrameToT:Show()).
            local inCombat = InCombatLockdown and InCombatLockdown()
			local powerBarHidden = (cfg.powerBarHidden == true)

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
			else
				-- Restore alpha when coming back from a hidden state so the bar is visible again.
				if pb._ScootUFOrigPBAlpha and pb.SetAlpha then
					pcall(pb.SetAlpha, pb, pb._ScootUFOrigPBAlpha)
				end
			end
            local colorModePB = cfg.powerBarColorMode or "default"
            local texKeyPB = cfg.powerBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or "player"
            applyToBar(pb, texKeyPB, colorModePB, cfg.powerBarTint, "player", "power", unitId)
            
            -- Apply background texture and color for Power Bar
            local bgTexKeyPB = cfg.powerBarBackgroundTexture or "default"
            local bgColorModePB = cfg.powerBarBackgroundColorMode or "default"
            local bgOpacityPB = cfg.powerBarBackgroundOpacity or 50
            applyBackgroundToBar(pb, bgTexKeyPB, bgColorModePB, cfg.powerBarBackgroundTint, bgOpacityPB, unit, "power")
            
            ensureMaskOnBarTexture(pb, resolvePowerMask(unit))

            if unit == "Player" and Util and Util.SetFullPowerSpikeHidden then
                Util.SetFullPowerSpikeHidden(pb, cfg.powerBarHideFullSpikes == true or powerBarHidden)
            end

            -- Hide power feedback animation (Builder/Spender flash when power is spent/gained)
            if unit == "Player" and Util and Util.SetPowerFeedbackHidden then
                Util.SetPowerFeedbackHidden(pb, cfg.powerBarHideFeedback == true or powerBarHidden)
            end

            -- Hide power bar spark (e.g., Elemental Shaman Maelstrom indicator)
            if unit == "Player" and Util and Util.SetPowerBarSparkHidden then
                Util.SetPowerBarSparkHidden(pb, cfg.powerBarHideSpark == true or powerBarHidden)
            end

            -- Apply reverse fill for Target/Focus if configured
            if (unit == "Target" or unit == "Focus") and pb and pb.SetReverseFill then
                local shouldReverse = not not cfg.powerBarReverseFill
                pcall(pb.SetReverseFill, pb, shouldReverse)
            end

            -- Lightweight persistence hooks for Player Power Bar:
            --  - Texture: keep custom texture applied if Blizzard swaps StatusBarTexture.
            --  - Color:   keep Foreground Color (default/class/custom) applied if Blizzard calls SetStatusBarColor.
            -- Note: We allow these hooks to run during combat to maintain visual consistency.
            -- The applyToBar function only changes texture/color (no layout), similar to Cast Bar.
            if unit == "Player" and _G.hooksecurefunc then
                if not pb._ScootPowerTextureHooked then
                    pb._ScootPowerTextureHooked = true
                    _G.hooksecurefunc(pb, "SetStatusBarTexture", function(self, ...)
                        -- Ignore ScooterMod's own writes to avoid recursion.
                        if self._ScootUFInternalTextureWrite then
                            return
                        end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        db.unitFrames = db.unitFrames or {}
                        local cfgP = db.unitFrames.Player or {}
                        local texKey = cfgP.powerBarTexture or "default"
                        local colorMode = cfgP.powerBarColorMode or "default"
                        local tint = cfgP.powerBarTint
                        -- Only re-apply if the user has configured a non-default texture.
                        if not (type(texKey) == "string" and texKey ~= "" and texKey ~= "default") then
                            return
                        end
                        applyToBar(self, texKey, colorMode, tint, "player", "power", "player")
                    end)
                end
                if not pb._ScootPowerColorHooked then
                    pb._ScootPowerColorHooked = true
                    _G.hooksecurefunc(pb, "SetStatusBarColor", function(self, ...)
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        db.unitFrames = db.unitFrames or {}
                        local cfgP = db.unitFrames.Player or {}
                        local texKey = cfgP.powerBarTexture or "default"
                        local colorMode = cfgP.powerBarColorMode or "default"
                        local tint = cfgP.powerBarTint
                        -- If color mode is "texture", the user wants the texture's original colors;
                        -- in that case we allow Blizzard's SetStatusBarColor to stand.
                        if colorMode == "texture" then
                            return
                        end
                        applyToBar(self, texKey, colorMode, tint, "player", "power", "player")
                    end)
                end
            end

            -- Alternate Power Bar styling (Player-only, class/spec gated)
            if unit == "Player" and addon.UnitFrames_PlayerHasAlternatePowerBar and addon.UnitFrames_PlayerHasAlternatePowerBar() then
                local apb = resolveAlternatePowerBar()
                if apb then
                    -- DB namespace for Alternate Power Bar
                    cfg.altPowerBar = cfg.altPowerBar or {}
                    local acfg = cfg.altPowerBar

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

                        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
                        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce alpha=0 when Blizzard updates the element.
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

                        -- Hook SetFontObject to reapply full text styling when Blizzard resets fonts during instance loading.
                        local function hookAltPowerTextFontReset(fs)
                            if not fs or fs._ScooterAltPowerTextFontResetHooked then return end
                            fs._ScooterAltPowerTextFontResetHooked = true
                            if _G.hooksecurefunc then
                                _G.hooksecurefunc(fs, "SetFontObject", function(self, ...)
                                    if not self._ScooterAltPowerTextFontReapplyDeferred then
                                        self._ScooterAltPowerTextFontReapplyDeferred = true
                                        C_Timer.After(0, function()
                                            self._ScooterAltPowerTextFontReapplyDeferred = nil
                                            -- Reapply Player bar textures which includes Alternate Power styling
                                            if addon and addon.ApplyUnitFrameBarTexturesFor then
                                                addon.ApplyUnitFrameBarTexturesFor("Player")
                                            end
                                        end)
                                    end
                                end)
                            end
                        end

                        hookAltPowerTextFontReset(leftFS)
                        hookAltPowerTextFontReset(rightFS)

                        -- Visibility: respect both the bar-wide hidden flag and the per-text toggles.
                        local percentHidden = (acfg.percentHidden == true)
                        local valueHidden = (acfg.valueHidden == true)

                        applyAltPowerTextVisibility(leftFS, altHidden or percentHidden)
                        applyAltPowerTextVisibility(rightFS, altHidden or valueHidden)

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
                            local face = addon.ResolveFontFace
                                and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
                                or (select(1, _G.GameFontNormal:GetFont()))
                            local size = tonumber(styleCfg.size) or 14
                            local outline = tostring(styleCfg.style or "OUTLINE")
                            if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
                            local c = styleCfg.color or { 1, 1, 1, 1 }
                            if fs.SetTextColor then
                                pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
                            end

                            -- Apply text alignment (requires explicit width on the FontString)
                            local alignment = styleCfg.alignment or "LEFT"
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

        -- Experimental: optionally hide the stock frame art (which includes the health bar border)
        do
            local ft = resolveUnitFrameFrameTexture(unit)
            if ft and ft.SetShown then
                local hide = not not (cfg.useCustomBorders or cfg.healthBarHideBorder)
                pcall(ft.SetShown, ft, not hide)
            end
        end
        -- Hide the Player's Alternate Power frame art when Use Custom Borders is enabled.
        -- Framestack: PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture
        if unit == "Player" and _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
            local altTex = _G.PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture
            if altTex and altTex.SetShown then
                if cfg.useCustomBorders then
                    pcall(altTex.SetShown, altTex, false)
                else
                    -- Restore the Alternate Power frame art when custom borders are disabled.
                    pcall(altTex.SetShown, altTex, true)
                end
            end
        end
        -- Hide the Player's Vehicle frame art when Use Custom Borders is enabled.
        -- Framestack: PlayerFrame.PlayerFrameContainer.VehicleFrameTexture
        if unit == "Player" and _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
            local vehicleTex = _G.PlayerFrame.PlayerFrameContainer.VehicleFrameTexture
            if vehicleTex and vehicleTex.SetShown then
                if cfg.useCustomBorders then
                    pcall(vehicleTex.SetShown, vehicleTex, false)
                else
                    -- Restore the Vehicle frame art when custom borders are disabled.
                    pcall(vehicleTex.SetShown, vehicleTex, true)
                end
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
                if reputationColor and reputationColor.SetShown then
                    pcall(reputationColor.SetShown, reputationColor, false)
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
                if reputationColor and reputationColor.SetShown then
                    pcall(reputationColor.SetShown, reputationColor, true)
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
                    if cfg.useCustomBorders then
                        -- Hide and install persistent hook to keep it hidden
                        if frameFlash.SetShown then pcall(frameFlash.SetShown, frameFlash, false) end
                        if frameFlash.Hide then pcall(frameFlash.Hide, frameFlash) end
                        
                        -- Install OnShow hook to prevent Blizzard's code from showing it during combat
                        -- CRITICAL: SetScript must be inside the guard to avoid creating new closures every style pass
                        if not frameFlash._ScootHideHookInstalled then
                            frameFlash._ScootHideHookInstalled = true
                            frameFlash._ScootOrigOnShow = frameFlash:GetScript("OnShow")
                            frameFlash:SetScript("OnShow", function(self)
                                local db = addon and addon.db and addon.db.profile
                                if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.useCustomBorders then
                                    -- Keep it hidden while Use Custom Borders is enabled
                                    self:Hide()
                                else
                                    -- Allow it to show if custom borders are disabled
                                    if self._ScootOrigOnShow then
                                        self._ScootOrigOnShow(self)
                                    end
                                end
                            end)
                        end
                    else
                        -- Restore FrameFlash when Use Custom Borders is disabled
                        -- Restore original OnShow handler
                        if frameFlash._ScootHideHookInstalled and frameFlash._ScootOrigOnShow then
                            frameFlash:SetScript("OnShow", frameFlash._ScootOrigOnShow)
                        else
                            frameFlash:SetScript("OnShow", nil)
                        end
                        -- Show the frame
                        if frameFlash.SetShown then pcall(frameFlash.SetShown, frameFlash, true) end
                        if frameFlash.Show then pcall(frameFlash.Show, frameFlash) end
                    end
                end
            end
        end
        
        -- Hide Flash (aggro/threat glow) for Target when Use Custom Borders is enabled
        if unit == "Target" then
            if _G.TargetFrame and _G.TargetFrame.TargetFrameContainer then
                local targetFlash = _G.TargetFrame.TargetFrameContainer.Flash
                if targetFlash then
                    if cfg.useCustomBorders then
                        -- Hide and install persistent hook to keep it hidden
                        if targetFlash.SetShown then pcall(targetFlash.SetShown, targetFlash, false) end
                        if targetFlash.Hide then pcall(targetFlash.Hide, targetFlash) end
                        
                        -- Install OnShow hook to prevent Blizzard's code from showing it during combat
                        -- CRITICAL: SetScript must be inside the guard to avoid creating new closures every style pass
                        if not targetFlash._ScootHideHookInstalled then
                            targetFlash._ScootHideHookInstalled = true
                            targetFlash._ScootOrigOnShow = targetFlash:GetScript("OnShow")
                            targetFlash:SetScript("OnShow", function(self)
                                local db = addon and addon.db and addon.db.profile
                                if db and db.unitFrames and db.unitFrames.Target and db.unitFrames.Target.useCustomBorders then
                                    -- Keep it hidden while Use Custom Borders is enabled
                                    self:Hide()
                                else
                                    -- Allow it to show if custom borders are disabled
                                    if self._ScootOrigOnShow then
                                        self._ScootOrigOnShow(self)
                                    end
                                end
                            end)
                        end
                    else
                        -- Restore Flash when Use Custom Borders is disabled
                        -- Restore original OnShow handler
                        if targetFlash._ScootHideHookInstalled and targetFlash._ScootOrigOnShow then
                            targetFlash:SetScript("OnShow", targetFlash._ScootOrigOnShow)
                        else
                            targetFlash:SetScript("OnShow", nil)
                        end
                        -- Show the frame
                        if targetFlash.SetShown then pcall(targetFlash.SetShown, targetFlash, true) end
                        if targetFlash.Show then pcall(targetFlash.Show, targetFlash) end
                    end
                end
            end
        end
        
        -- Hide Flash (aggro/threat glow) for Focus when Use Custom Borders is enabled
        if unit == "Focus" then
            if _G.FocusFrame and _G.FocusFrame.TargetFrameContainer then
                local focusFlash = _G.FocusFrame.TargetFrameContainer.Flash
                if focusFlash then
                    if cfg.useCustomBorders then
                        -- Hide and install persistent hook to keep it hidden
                        if focusFlash.SetShown then pcall(focusFlash.SetShown, focusFlash, false) end
                        if focusFlash.Hide then pcall(focusFlash.Hide, focusFlash) end
                        
                        -- Install OnShow hook to prevent Blizzard's code from showing it during combat
                        -- CRITICAL: SetScript must be inside the guard to avoid creating new closures every style pass
                        if not focusFlash._ScootHideHookInstalled then
                            focusFlash._ScootHideHookInstalled = true
                            focusFlash._ScootOrigOnShow = focusFlash:GetScript("OnShow")
                            focusFlash:SetScript("OnShow", function(self)
                                local db = addon and addon.db and addon.db.profile
                                if db and db.unitFrames and db.unitFrames.Focus and db.unitFrames.Focus.useCustomBorders then
                                    -- Keep it hidden while Use Custom Borders is enabled
                                    self:Hide()
                                else
                                    -- Allow it to show if custom borders are disabled
                                    if self._ScootOrigOnShow then
                                        self._ScootOrigOnShow(self)
                                    end
                                end
                            end)
                        end
                    else
                        -- Restore Flash when Use Custom Borders is disabled
                        -- Restore original OnShow handler
                        if focusFlash._ScootHideHookInstalled and focusFlash._ScootOrigOnShow then
                            focusFlash:SetScript("OnShow", focusFlash._ScootOrigOnShow)
                        else
                            focusFlash:SetScript("OnShow", nil)
                        end
                        -- Show the frame
                        if focusFlash.SetShown then pcall(focusFlash.SetShown, focusFlash, true) end
                        if focusFlash.Show then pcall(focusFlash.Show, focusFlash) end
                    end
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
        applyForUnit("Pet")
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
        if not db or not db.unitFrames or not db.unitFrames.Player then return end
        local cfg = db.unitFrames.Player
        if not cfg.useCustomBorders then return end -- Only enforce when custom borders enabled
        
        local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
        local vehicleTex = container and container.VehicleFrameTexture
        if vehicleTex and vehicleTex.SetShown then
            pcall(vehicleTex.SetShown, vehicleTex, false)
        end
    end

    -- Enforce AlternatePowerFrameTexture visibility based on Use Custom Borders setting
    local function EnforceAlternatePowerFrameTextureVisibility()
        local db = addon and addon.db and addon.db.profile
        if not db or not db.unitFrames or not db.unitFrames.Player then return end
        local cfg = db.unitFrames.Player
        if not cfg.useCustomBorders then return end -- Only enforce when custom borders enabled
        
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
        -- TEMPORARY DIAGNOSTIC (2025-11-14):
        -- The hooks below re-apply bar textures and borders after Blizzard updates
        -- unit frames (Player/Target/Focus). These updates can be frequent in combat.
        -- To measure their CPU impact, we keep the z-order defers available but
        -- disable the texture re-application hooks entirely for now.

        if false and _G.PlayerFrame and _G.PlayerFrame.UpdateSystem then
            _G.hooksecurefunc(_G.PlayerFrame, "UpdateSystem", function()
                defer("Player")
                if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                    _G.C_Timer.After(0, function() addon.ApplyUnitFrameBarTexturesFor("Player") end)
                elseif addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Player")
                end
            end)
        end
        if false and type(_G.PlayerFrame_Update) == "function" then
            _G.hooksecurefunc("PlayerFrame_Update", function()
                if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                    _G.C_Timer.After(0, function() addon.ApplyUnitFrameBarTexturesFor("Player") end)
                elseif addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Player")
                end
            end)
        end
        if false and type(_G.TargetFrame_Update) == "function" then
            _G.hooksecurefunc("TargetFrame_Update", function()
                defer("Target")
                if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                    _G.C_Timer.After(0, function() addon.ApplyUnitFrameBarTexturesFor("Target") end)
                elseif addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Target")
                end
            end)
        end
        if false and type(_G.FocusFrame_Update) == "function" then
            _G.hooksecurefunc("FocusFrame_Update", function()
                defer("Focus")
                if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                    _G.C_Timer.After(0, function() addon.ApplyUnitFrameBarTexturesFor("Focus") end)
                elseif addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Focus")
                end
            end)
        end
        if false and type(_G.PetFrame_Update) == "function" then
            _G.hooksecurefunc("PetFrame_Update", function() defer("Pet") end)
        end
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
                if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.useCustomBorders then
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
                if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.useCustomBorders then
                    if self.Hide then pcall(self.Hide, self) end
                end
            end)
        end
    end

end

