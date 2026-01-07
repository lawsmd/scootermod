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

-- Unit frame texture re-apply deferral (combat-safe):
-- If we detect a stock refresh during combat, queue a re-apply for after combat.
local pendingUnitFrameTextureUnits = {}
local unitFrameTextureCombatWatcher = nil

local function ensureUnitFrameTextureCombatWatcher()
    if unitFrameTextureCombatWatcher then
        return
    end
    unitFrameTextureCombatWatcher = CreateFrame("Frame")
    unitFrameTextureCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    unitFrameTextureCombatWatcher:SetScript("OnEvent", function()
        for unit in pairs(pendingUnitFrameTextureUnits) do
            pendingUnitFrameTextureUnits[unit] = nil
            if addon.ApplyUnitFrameBarTexturesFor then
                addon.ApplyUnitFrameBarTexturesFor(unit)
            end
        end
    end)
end

local function queueUnitFrameTextureReapply(unit)
    ensureUnitFrameTextureCombatWatcher()
    pendingUnitFrameTextureUnits[unit] = true
end

-- Raid/GroupFrames styling deferral (combat-safe):
-- We must NEVER apply CompactUnitFrame (raid/party) cosmetic changes during combat, and we must
-- avoid doing synchronous work inside Blizzard's CompactUnitFrame update chains. See DEBUG.md.
local pendingRaidFrameReapply = false
local pendingPartyFrameReapply = false
local raidFrameCombatWatcher = nil

local function ensureRaidFrameCombatWatcher()
    if raidFrameCombatWatcher then
        return
    end
    raidFrameCombatWatcher = CreateFrame("Frame")
    raidFrameCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    raidFrameCombatWatcher:SetScript("OnEvent", function()
        if not pendingRaidFrameReapply and not pendingPartyFrameReapply then
            return
        end
        local doRaid = pendingRaidFrameReapply
        local doParty = pendingPartyFrameReapply
        pendingRaidFrameReapply = false
        pendingPartyFrameReapply = false

        if doRaid then
            if addon.ApplyRaidFrameHealthBarStyle then
                addon.ApplyRaidFrameHealthBarStyle()
            end
            if addon.ApplyRaidFrameStatusTextStyle then
                addon.ApplyRaidFrameStatusTextStyle()
            end
            if addon.ApplyRaidFrameGroupTitlesStyle then
                addon.ApplyRaidFrameGroupTitlesStyle()
            end
            -- Also apply combat-safe overlays (create/update overlays out of combat)
            if addon.ApplyRaidFrameHealthOverlays then
                addon.ApplyRaidFrameHealthOverlays()
            end
            if addon.ApplyRaidFrameNameOverlays then
                addon.ApplyRaidFrameNameOverlays()
            end
        end

        if doParty then
            if addon.ApplyPartyFrameHealthBarStyle then
                addon.ApplyPartyFrameHealthBarStyle()
            end
            if addon.ApplyPartyFrameTitleStyle then
                addon.ApplyPartyFrameTitleStyle()
            end
            -- Also apply combat-safe overlays (create/update overlays out of combat)
            if addon.ApplyPartyFrameHealthOverlays then
                addon.ApplyPartyFrameHealthOverlays()
            end
            if addon.ApplyPartyFrameNameOverlays then
                addon.ApplyPartyFrameNameOverlays()
            end
        end
    end)
end

local function queueRaidFrameReapply()
    ensureRaidFrameCombatWatcher()
    pendingRaidFrameReapply = true
end

local function queuePartyFrameReapply()
    ensureRaidFrameCombatWatcher()
    pendingPartyFrameReapply = true
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
    local function getUnitFrameFor(unit)
        -- ToT is not an Edit Mode frame - resolve directly from TargetFrame
        if unit == "TargetOfTarget" then
            return _G.TargetFrameToT
        end
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
                or (unit == "Boss" and EM.Boss)
        end
        if idx then
            return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
        end
        if unit == "Pet" then return _G.PetFrame end
        -- Fallback for Boss if EM.Boss is unavailable
        if unit == "Boss" then return _G.Boss1TargetFrame end
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
        if unit == "TargetOfTarget" then
            local tot = _G.TargetFrameToT
            return tot and tot.HealthBar or nil
        end
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
        elseif unit == "Boss" then
            -- Boss frames expose healthbar as a direct property (Boss1TargetFrame.healthbar).
            -- This is reliable and doesn't require traversing the nested frame hierarchy.
            if frame and frame.healthbar then return frame.healthbar end
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
		elseif unit == "TargetOfTarget" then
			return _G.TargetFrameToT
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
        if unit == "TargetOfTarget" then
            local tot = _G.TargetFrameToT
            return tot and tot.ManaBar or nil
        end
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
        elseif unit == "Boss" then
            -- Boss frames expose manabar as a direct property (Boss1TargetFrame.manabar).
            -- This is reliable and doesn't require traversing the nested frame hierarchy.
            if frame and frame.manabar then return frame.manabar end
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
        elseif unit == "TargetOfTarget" then
            local tot = _G.TargetFrameToT
            return tot and tot.HealthBar and tot.HealthBar.HealthBarMask or nil
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
        elseif unit == "TargetOfTarget" then
            local tot = _G.TargetFrameToT
            return tot and tot.ManaBar and tot.ManaBar.ManaBarMask or nil
        end
        return nil
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
        elseif unit == "Boss" then
            local root = _G.Boss1TargetFrame
            return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
        elseif unit == "Pet" then
            return _G.PetFrameTexture
        elseif unit == "TargetOfTarget" then
            local tot = _G.TargetFrameToT
            return tot and tot.FrameTexture or nil
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

    local function applyToBar(bar, textureKey, colorMode, tint, unitForClass, barKind, unitForPower, combatSafe)
        if not bar or type(bar.GetStatusBarTexture) ~= "function" then return end

        -- Combat safety: touching protected StatusBars (SetStatusBarTexture / SetVertexColor / CreateTexture)
        -- during combat can taint the execution context and later cause unrelated protected calls to be blocked.
        -- Callers should queue a post-combat reapply instead.
        --
        -- Exception: some callers (e.g., Cast Bar visual-only refresh) intentionally re-apply ONLY
        -- cosmetic texture/color changes during combat to keep styling persistent while avoiding
        -- combat-unsafe layout operations. Those callers may pass combatSafe=true.
        if not combatSafe and InCombatLockdown and InCombatLockdown() then
            return
        end
        
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

        -- Combat safety: creating/modifying textures on protected frames during combat can taint.
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        
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

    -- =========================================================================
    -- Shared Alpha Enforcement Helpers
    -- =========================================================================
    -- These functions are used by both applyForUnit() and InstallEarlyUnitFrameAlphaHooks()
    -- to hide stock art/overlays when custom borders are enabled.
    --
    -- IMPORTANT (taint): Avoid SetShown/Show/Hide and avoid SetScript overrides on Blizzard frames.
    -- We enforce "hidden" visuals via SetAlpha(0/1) + a deferred Show hook. See DEBUG.md.

    local function applyAlpha(frameOrTexture, alpha)
        if not frameOrTexture or not frameOrTexture.SetAlpha then return end
        pcall(frameOrTexture.SetAlpha, frameOrTexture, alpha)
    end

    local function hookAlphaEnforcer(frameOrTexture, computeAlpha)
        if not frameOrTexture or not _G.hooksecurefunc or type(computeAlpha) ~= "function" then return end
        if frameOrTexture._ScootAlphaEnforcerHooked then return end
        frameOrTexture._ScootAlphaEnforcerHooked = true

        -- IMPORTANT (taint/combat): These enforcers only call SetAlpha, which is safe for visual-only
        -- regions/textures even in combat. Do NOT gate on InCombatLockdown(), otherwise Blizzard can
        -- Show()/SetAlpha() during combat and the element may remain visible after combat.
        local function enforce(obj)
            local desired = computeAlpha()
            if obj and obj.GetAlpha and type(obj.GetAlpha) == "function" then
                local ok, current = pcall(obj.GetAlpha, obj)
                if ok and current == desired then
                    return
                end
            end
            applyAlpha(obj, desired)
        end

        local function enforceNowAndDefer(obj)
            -- Immediate enforcement prevents visible pop-in.
            enforce(obj)
            -- One-tick backup in case a later same-frame update adjusts alpha again.
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function() enforce(obj) end)
            end
        end

        -- Re-assert when Blizzard shows the object.
        _G.hooksecurefunc(frameOrTexture, "Show", function(self)
            enforceNowAndDefer(self)
        end)

        -- Re-assert when Blizzard toggles visibility via SetShown (some UI paths never call Show directly).
        if frameOrTexture.SetShown then
            _G.hooksecurefunc(frameOrTexture, "SetShown", function(self)
                enforceNowAndDefer(self)
            end)
        end

        -- Re-assert when Blizzard adjusts alpha (e.g., fades, state transitions).
        if frameOrTexture.SetAlpha then
            _G.hooksecurefunc(frameOrTexture, "SetAlpha", function(self)
                enforce(self)
            end)
        end
    end

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

    -- =========================================================================
    -- Pre-emptive Hiding Functions for Target/Focus Frame Elements
    -- =========================================================================
    -- These functions are called SYNCHRONOUSLY (not deferred) from event handlers
    -- like PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED. They hide elements
    -- BEFORE Blizzard's TargetFrame_Update/FocusFrame_Update runs, preventing
    -- the brief visual "flash" that occurs when relying solely on post-update hooks.
    --
    -- The key insight is that PLAYER_TARGET_CHANGED fires BEFORE Blizzard's
    -- internal handler calls TargetFrame_Update. By hiding elements immediately
    -- in our event handler, they're already hidden when Blizzard tries to show them.

    -- Pre-emptive hide for Target frame elements (ReputationColor, FrameTexture, Flash)
    local function preemptiveHideTargetElements()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Target")
        if not cfg then return end

        -- Only hide if useCustomBorders is enabled
        if cfg.useCustomBorders then
            -- Hide ReputationColor immediately
            local repColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            if repColor and repColor.SetAlpha then
                pcall(repColor.SetAlpha, repColor, 0)
            end

            -- Hide frame texture immediately
            local ft = resolveUnitFrameFrameTexture("Target")
            if ft and ft.SetAlpha then
                pcall(ft.SetAlpha, ft, 0)
            end

            -- Hide Flash (aggro/threat glow) immediately
            local targetFlash = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
                and _G.TargetFrame.TargetFrameContainer.Flash
            if targetFlash and targetFlash.SetAlpha then
                pcall(targetFlash.SetAlpha, targetFlash, 0)
            end
        end

        -- Hide frame texture if healthBarHideBorder is enabled (separate from useCustomBorders)
        if cfg.healthBarHideBorder then
            local ft = resolveUnitFrameFrameTexture("Target")
            if ft and ft.SetAlpha then
                pcall(ft.SetAlpha, ft, 0)
            end
        end
    end
    addon.PreemptiveHideTargetElements = preemptiveHideTargetElements

    -- Pre-emptive hide for Focus frame elements (ReputationColor, FrameTexture, Flash)
    local function preemptiveHideFocusElements()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Focus")
        if not cfg then return end

        -- Only hide if useCustomBorders is enabled
        if cfg.useCustomBorders then
            -- Hide ReputationColor immediately
            local repColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            if repColor and repColor.SetAlpha then
                pcall(repColor.SetAlpha, repColor, 0)
            end

            -- Hide frame texture immediately
            local ft = resolveUnitFrameFrameTexture("Focus")
            if ft and ft.SetAlpha then
                pcall(ft.SetAlpha, ft, 0)
            end

            -- Hide Flash (aggro/threat glow) immediately
            local focusFlash = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
                and _G.FocusFrame.TargetFrameContainer.Flash
            if focusFlash and focusFlash.SetAlpha then
                pcall(focusFlash.SetAlpha, focusFlash, 0)
            end
        end

        -- Hide frame texture if healthBarHideBorder is enabled (separate from useCustomBorders)
        if cfg.healthBarHideBorder then
            local ft = resolveUnitFrameFrameTexture("Focus")
            if ft and ft.SetAlpha then
                pcall(ft.SetAlpha, ft, 0)
            end
        end
    end
    addon.PreemptiveHideFocusElements = preemptiveHideFocusElements

    -- =========================================================================
    -- Early Alpha Hook Installation
    -- =========================================================================
    -- Install alpha enforcement hooks on Target/Focus frame elements during
    -- PLAYER_ENTERING_WORLD, BEFORE the first target is acquired. This ensures
    -- hooks are in place from the start, preventing the "first target flash"
    -- that occurs when hooks are only installed during applyForUnit().

    local function installEarlyAlphaHooks()
        -- Helper to compute alpha based on useCustomBorders setting
        local function makeComputeAlpha(unit)
            return function()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames")
                local cfg2 = unitFrames2 and rawget(unitFrames2, unit)
                return (cfg2 and cfg2.useCustomBorders) and 0 or 1
            end
        end

        local function makeComputeAlphaWithBorder(unit)
            return function()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames")
                local cfg2 = unitFrames2 and rawget(unitFrames2, unit)
                local hide = cfg2 and (cfg2.useCustomBorders or cfg2.healthBarHideBorder)
                return hide and 0 or 1
            end
        end

        -- Target frame elements
        do
            -- ReputationColor
            local targetRepColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            if targetRepColor and not targetRepColor._ScootAlphaEnforcerHooked then
                hookAlphaEnforcer(targetRepColor, makeComputeAlpha("Target"))
            end

            -- FrameTexture
            local targetFT = resolveUnitFrameFrameTexture("Target")
            if targetFT and not targetFT._ScootAlphaEnforcerHooked then
                hookAlphaEnforcer(targetFT, makeComputeAlphaWithBorder("Target"))
            end

            -- Flash (aggro/threat glow)
            local targetFlash = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
                and _G.TargetFrame.TargetFrameContainer.Flash
            if targetFlash and not targetFlash._ScootAlphaEnforcerHooked then
                hookAlphaEnforcer(targetFlash, makeComputeAlpha("Target"))
            end
        end

        -- Focus frame elements
        do
            -- ReputationColor
            local focusRepColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            if focusRepColor and not focusRepColor._ScootAlphaEnforcerHooked then
                hookAlphaEnforcer(focusRepColor, makeComputeAlpha("Focus"))
            end

            -- FrameTexture
            local focusFT = resolveUnitFrameFrameTexture("Focus")
            if focusFT and not focusFT._ScootAlphaEnforcerHooked then
                hookAlphaEnforcer(focusFT, makeComputeAlphaWithBorder("Focus"))
            end

            -- Flash (aggro/threat glow)
            local focusFlash = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
                and _G.FocusFrame.TargetFrameContainer.Flash
            if focusFlash and not focusFlash._ScootAlphaEnforcerHooked then
                hookAlphaEnforcer(focusFlash, makeComputeAlpha("Focus"))
            end
        end

        -- Also do initial hide pass for currently configured settings
        if addon.PreemptiveHideTargetElements then
            addon.PreemptiveHideTargetElements()
        end
        if addon.PreemptiveHideFocusElements then
            addon.PreemptiveHideFocusElements()
        end
    end
    addon.InstallEarlyUnitFrameAlphaHooks = installEarlyAlphaHooks

end

--------------------------------------------------------------------------------
-- Raid Frame Health Bar Styling
--------------------------------------------------------------------------------
-- Applies foreground/background texture and color settings to all raid frame
-- health bars (CompactRaidGroup*Member*HealthBar and CompactRaidFrame*HealthBar).
--------------------------------------------------------------------------------

do
    -- Cache for discovered raid frame health bars
    local raidHealthBars = {}
    local raidHealthBarsScanned = false

    -- Iterate all raid frame health bars. Blizzard uses two naming patterns:
    --   - Group layout: CompactRaidGroup[1-8]Member[1-5]HealthBar (up to 40)
    --   - Combined layout: CompactRaidFrame[1-40]HealthBar
    local function collectRaidHealthBars()
        raidHealthBars = {}
        -- Pattern 1: Group-based naming (CompactRaidGroup1Member1HealthBar, etc.)
        for group = 1, 8 do
            for member = 1, 5 do
                local frameName = "CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"
                local bar = _G[frameName]
                if bar then
                    table.insert(raidHealthBars, bar)
                end
            end
        end
        -- Pattern 2: Combined naming (CompactRaidFrame1HealthBar, etc.)
        for i = 1, 40 do
            local frameName = "CompactRaidFrame" .. i .. "HealthBar"
            local bar = _G[frameName]
            if bar and not bar._ScootRaidBarCounted then
                -- Avoid duplicates if both patterns exist
                bar._ScootRaidBarCounted = true
                table.insert(raidHealthBars, bar)
            end
        end
        raidHealthBarsScanned = true
    end

    -- Apply styling to a single raid health bar
    local function applyToRaidHealthBar(bar, cfg)
        if not bar then return end

        local texKey = cfg.healthBarTexture or "default"
        local colorMode = cfg.healthBarColorMode or "default"
        local tint = cfg.healthBarTint
        local bgTexKey = cfg.healthBarBackgroundTexture or "default"
        local bgColorMode = cfg.healthBarBackgroundColorMode or "default"
        local bgTint = cfg.healthBarBackgroundTint
        local bgOpacity = cfg.healthBarBackgroundOpacity or 50

        -- Apply foreground texture and color
        if addon._ApplyToStatusBar then
            addon._ApplyToStatusBar(bar, texKey, colorMode, tint, nil, "health", nil)
        end

        -- Apply background texture and color
        if addon._ApplyBackgroundToStatusBar then
            addon._ApplyBackgroundToStatusBar(bar, bgTexKey, bgColorMode, bgTint, bgOpacity, "Raid", "health")
        end
    end

    -- Main entry point: Apply raid frame health bar styling from DB settings
    function addon.ApplyRaidFrameHealthBarStyle()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        -- Zero‑Touch: if the user has never configured groupFrames.raid, do nothing.
        local groupFrames = rawget(db, "groupFrames")
        local cfg = groupFrames and rawget(groupFrames, "raid") or nil
        if not cfg then
            return
        end

        -- Zero‑Touch: if nothing is actually customized (all defaults), do not touch.
        local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                          (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                          (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                          (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
        if not hasCustom then
            return
        end

        -- Combat safety: never style CompactUnitFrame raid bars during combat.
        if InCombatLockdown and InCombatLockdown() then
            queueRaidFrameReapply()
            return
        end

        -- Rescan bars each time to catch frames created/destroyed by Blizzard
        collectRaidHealthBars()

        for _, bar in ipairs(raidHealthBars) do
            applyToRaidHealthBar(bar, cfg)
        end

        -- Clear the counted flag for next scan
        for _, bar in ipairs(raidHealthBars) do
            bar._ScootRaidBarCounted = nil
        end
    end

    -- Helper: Check if a CompactUnitFrame is actually a raid frame (not nameplate/party)
    -- Raid frames have names like "CompactRaidFrame1" or "CompactRaidGroup1Member1"
    local function isRaidFrame(frame)
        if not frame then return false end
        -- Use pcall to safely get name - some frames (nameplates) error on GetName
        local ok, name = pcall(function() return frame:GetName() end)
        if not ok or not name then return false end
        -- Match raid frame naming patterns
        if name:match("^CompactRaidFrame%d+$") then return true end
        if name:match("^CompactRaidGroup%d+Member%d+$") then return true end
        return false
    end

    -- Install hooks to reapply styling when raid frames update
    local function installRaidFrameHooks()
        if addon._RaidFrameHooksInstalled then return end
        addon._RaidFrameHooksInstalled = true

        -- Hook CompactUnitFrame_UpdateAll to catch frame updates
        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
            _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
                -- Only apply to actual raid frames (not nameplates or party frames)
                if frame and frame.healthBar and isRaidFrame(frame) then
                    local db = addon and addon.db and addon.db.profile
                    if db and db.groupFrames and db.groupFrames.raid then
                        local cfg = db.groupFrames.raid
                        -- Only apply if user has customized settings
                        local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                                          (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                                          (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                                          (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
                        if hasCustom then
                            local bar = frame.healthBar
                            local cfgRef = cfg
                            -- IMPORTANT: Always defer to break the CompactUnitFrame execution context chain.
                            if _G.C_Timer and _G.C_Timer.After then
                                _G.C_Timer.After(0, function()
                                    if InCombatLockdown and InCombatLockdown() then
                                        queueRaidFrameReapply()
                                        return
                                    end
                                    applyToRaidHealthBar(bar, cfgRef)
                                end)
                            else
                                if InCombatLockdown and InCombatLockdown() then
                                    queueRaidFrameReapply()
                                    return
                                end
                                applyToRaidHealthBar(bar, cfgRef)
                            end
                        end
                    end
                end
            end)
        end

        -- Hook CompactUnitFrame_SetUnit for when frames get assigned new units
        if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
            _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
                -- Only apply to actual raid frames (not nameplates or party frames)
                if frame and frame.healthBar and unit and isRaidFrame(frame) then
                    local db = addon and addon.db and addon.db.profile
                    if db and db.groupFrames and db.groupFrames.raid then
                        local cfg = db.groupFrames.raid
                        local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                                          (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                                          (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                                          (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
                        if hasCustom then
                            local bar = frame.healthBar
                            local cfgRef = cfg
                            -- Defer to let Blizzard finish setup AND to break taint propagation.
                            if _G.C_Timer and _G.C_Timer.After then
                                _G.C_Timer.After(0, function()
                                    if InCombatLockdown and InCombatLockdown() then
                                        queueRaidFrameReapply()
                                        return
                                    end
                                    applyToRaidHealthBar(bar, cfgRef)
                                end)
                            else
                                if InCombatLockdown and InCombatLockdown() then
                                    queueRaidFrameReapply()
                                    return
                                end
                                applyToRaidHealthBar(bar, cfgRef)
                            end
                        end
                    end
                end
            end)
        end
    end

    -- Install hooks when this module loads
    installRaidFrameHooks()
end

--------------------------------------------------------------------------------
-- Raid Frame Health Bar Overlay (Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned overlay textures on raid health bars that visually
-- replace Blizzard's fill texture. These overlays can be updated during combat
-- without taint because we only manipulate our own textures, not Blizzard's
-- protected StatusBar.
--
-- Pattern: Same as ScooterPartyHealthFill for party frames.
--
-- BACKGROUND TEXTURE NOTE: The background texture (ScooterModBG) does NOT need
-- a separate overlay because it is already an addon-owned texture created via
-- _ApplyBackgroundToStatusBar. Once created, it persists through combat since
-- we own it. The only limitation is initial creation must happen out of combat.
--------------------------------------------------------------------------------

do
    -- Update the overlay texture width based on health bar value
    -- NOTE: No combat guard needed - we only touch our own texture (ScooterRaidHealthFill)
    local function updateRaidHealthOverlay(bar)
        if not bar or not bar.ScooterRaidHealthFill then return end
        if not bar._ScootRaidOverlayActive then
            bar.ScooterRaidHealthFill:Hide()
            return
        end

        local overlay = bar.ScooterRaidHealthFill
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
        -- Raid health bars fill left-to-right
        overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    end

    -- Apply texture and color to the overlay based on config
    local function styleRaidHealthOverlay(bar, cfg)
        if not bar or not bar.ScooterRaidHealthFill or not cfg then return end

        local overlay = bar.ScooterRaidHealthFill
        local texKey = cfg.healthBarTexture or "default"
        local colorMode = cfg.healthBarColorMode or "default"
        local tint = cfg.healthBarTint

        -- Resolve texture path
        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)

        if resolvedPath then
            overlay:SetTexture(resolvedPath)
        else
            -- Default: copy from bar's current texture or use a fallback
            local tex = bar:GetStatusBarTexture()
            local applied = false
            if tex then
                local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
                if okAtlas and atlasName and atlasName ~= "" then
                    if overlay.SetAtlas then
                        pcall(overlay.SetAtlas, overlay, atlasName, true)
                        applied = true
                    end
                end
                if not applied then
                    local okTex, texPath = pcall(tex.GetTexture, tex)
                    if okTex and texPath then
                        if type(texPath) == "string" and texPath:match("^[A-Za-z]") and not texPath:match("\\") and not texPath:match("/") then
                            -- Likely an atlas token, use SetAtlas
                            if overlay.SetAtlas then
                                pcall(overlay.SetAtlas, overlay, texPath, true)
                                applied = true
                            end
                        elseif type(texPath) == "number" or (type(texPath) == "string" and (texPath:match("\\") or texPath:match("/"))) then
                            pcall(overlay.SetTexture, overlay, texPath)
                            applied = true
                        end
                    end
                end
            end
            if not applied then
                -- Ultimate fallback: white texture
                overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
            end
        end

        -- Apply color based on mode
        local r, g, b, a = 1, 1, 1, 1
        if colorMode == "custom" and type(tint) == "table" then
            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
        elseif colorMode == "class" then
            -- For raid frames, we'd need the unit's class - for now use a green health color
            r, g, b, a = 0, 1, 0, 1
        elseif colorMode == "texture" then
            r, g, b, a = 1, 1, 1, 1
        else
            -- Default: use Blizzard's current bar color
            local barR, barG, barB = bar:GetStatusBarColor()
            if barR then
                r, g, b = barR, barG, barB
            else
                r, g, b = 0, 1, 0
            end
        end
        overlay:SetVertexColor(r, g, b, a)
    end

    -- Hide Blizzard's fill texture and install alpha-enforcement hook
    local function hideBlizzardRaidHealthFill(bar)
        if not bar then return end
        local blizzFill = bar:GetStatusBarTexture()
        if not blizzFill then return end

        -- Mark as hidden and set alpha to 0
        blizzFill._ScootHidden = true
        blizzFill:SetAlpha(0)

        -- Install alpha-enforcement hook (only once per texture)
        if not blizzFill._ScootAlphaHooked and _G.hooksecurefunc then
            blizzFill._ScootAlphaHooked = true
            _G.hooksecurefunc(blizzFill, "SetAlpha", function(self, alpha)
                if alpha > 0 and self._ScootHidden then
                    -- Defer to avoid fighting Blizzard's call
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if self._ScootHidden then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end
            end)
        end
    end

    -- Show Blizzard's fill texture (for restore/cleanup)
    local function showBlizzardRaidHealthFill(bar)
        if not bar then return end
        local blizzFill = bar:GetStatusBarTexture()
        if blizzFill then
            blizzFill._ScootHidden = nil
            blizzFill:SetAlpha(1)
        end
    end

    -- Create or update the raid health overlay for a specific bar
    local function ensureRaidHealthOverlay(bar, cfg)
        if not bar then return end

        -- Determine if overlay should be active based on config
        local hasCustom = cfg and (
            (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
            (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
        )

        bar._ScootRaidOverlayActive = hasCustom

        if not hasCustom then
            -- Disable overlay, show Blizzard's texture
            if bar.ScooterRaidHealthFill then
                bar.ScooterRaidHealthFill:Hide()
            end
            showBlizzardRaidHealthFill(bar)
            return
        end

        -- Create overlay texture if it doesn't exist
        if not bar.ScooterRaidHealthFill then
            local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 2)
            overlay:SetVertTile(false)
            overlay:SetHorizTile(false)
            overlay:SetTexCoord(0, 1, 0, 1)
            bar.ScooterRaidHealthFill = overlay

            -- Install hooks for value/size changes - NO COMBAT GUARDS
            -- These hooks only touch our overlay texture, not Blizzard's StatusBar
            if _G.hooksecurefunc and not bar._ScootRaidOverlayHooksInstalled then
                bar._ScootRaidOverlayHooksInstalled = true
                _G.hooksecurefunc(bar, "SetValue", function(self)
                    updateRaidHealthOverlay(self)
                end)
                _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                    updateRaidHealthOverlay(self)
                end)
                if bar.HookScript then
                    bar:HookScript("OnSizeChanged", function(self)
                        updateRaidHealthOverlay(self)
                    end)
                end
            end
        end

        -- Hook SetStatusBarTexture to re-hide Blizzard's fill if it swaps textures
        if not bar._ScootRaidTextureSwapHooked and _G.hooksecurefunc then
            bar._ScootRaidTextureSwapHooked = true
            _G.hooksecurefunc(bar, "SetStatusBarTexture", function(self)
                if self._ScootRaidOverlayActive then
                    -- Blizzard may have created a new texture, re-hide it
                    -- Defer to break execution chain
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            hideBlizzardRaidHealthFill(self)
                        end)
                    end
                end
            end)
        end

        -- Style the overlay and hide Blizzard's fill
        styleRaidHealthOverlay(bar, cfg)
        hideBlizzardRaidHealthFill(bar)

        -- Trigger initial size calculation
        updateRaidHealthOverlay(bar)
    end

    -- Disable overlay and restore Blizzard's appearance for a bar
    local function disableRaidHealthOverlay(bar)
        if not bar then return end
        bar._ScootRaidOverlayActive = false
        if bar.ScooterRaidHealthFill then
            bar.ScooterRaidHealthFill:Hide()
        end
        showBlizzardRaidHealthFill(bar)
    end

    -- Apply overlays to all raid health bars
    function addon.ApplyRaidFrameHealthOverlays()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local groupFrames = rawget(db, "groupFrames")
        local cfg = groupFrames and rawget(groupFrames, "raid") or nil

        -- Zero-Touch check
        local hasCustom = cfg and (
            (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
            (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
        )

        -- Combined layout: CompactRaidFrame1..40HealthBar
        for i = 1, 40 do
            local bar = _G["CompactRaidFrame" .. i .. "HealthBar"]
            if bar then
                if hasCustom then
                    -- Only create overlays out of combat (initial setup)
                    if not (InCombatLockdown and InCombatLockdown()) then
                        ensureRaidHealthOverlay(bar, cfg)
                    elseif bar.ScooterRaidHealthFill then
                        -- Already have overlay, just update styling (safe during combat for our texture)
                        styleRaidHealthOverlay(bar, cfg)
                        updateRaidHealthOverlay(bar)
                    end
                else
                    disableRaidHealthOverlay(bar)
                end
            end
        end

        -- Group layout: CompactRaidGroup1..8Member1..5HealthBar
        for group = 1, 8 do
            for member = 1, 5 do
                local bar = _G["CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"]
                if bar then
                    if hasCustom then
                        if not (InCombatLockdown and InCombatLockdown()) then
                            ensureRaidHealthOverlay(bar, cfg)
                        elseif bar.ScooterRaidHealthFill then
                            styleRaidHealthOverlay(bar, cfg)
                            updateRaidHealthOverlay(bar)
                        end
                    else
                        disableRaidHealthOverlay(bar)
                    end
                end
            end
        end
    end

    -- Restore all raid health bars to stock appearance
    function addon.RestoreRaidFrameHealthOverlays()
        -- Combined layout
        for i = 1, 40 do
            local bar = _G["CompactRaidFrame" .. i .. "HealthBar"]
            if bar then
                disableRaidHealthOverlay(bar)
            end
        end
        -- Group layout
        for group = 1, 8 do
            for member = 1, 5 do
                local bar = _G["CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"]
                if bar then
                    disableRaidHealthOverlay(bar)
                end
            end
        end
    end

    -- Helper: Check if a CompactUnitFrame is a raid frame
    local function isRaidFrame(frame)
        if not frame then return false end
        local ok, name = pcall(function() return frame:GetName() end)
        if not ok or not name then return false end
        if name:match("^CompactRaidFrame%d+$") then return true end
        if name:match("^CompactRaidGroup%d+Member%d+$") then return true end
        return false
    end

    -- Install hooks that trigger overlay setup/updates via CompactUnitFrame events
    local function installRaidHealthOverlayHooks()
        if addon._RaidHealthOverlayHooksInstalled then return end
        addon._RaidHealthOverlayHooksInstalled = true

        local function isRaidHealthBar(frame)
            if not frame or not frame.healthBar then return false end
            return isRaidFrame(frame)
        end

        -- Hook CompactUnitFrame_UpdateAll to set up overlays
        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
            _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
                if not isRaidHealthBar(frame) then return end

                local db = addon and addon.db and addon.db.profile
                local cfg = db and db.groupFrames and db.groupFrames.raid or nil

                local hasCustom = cfg and (
                    (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                    (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
                )

                if hasCustom then
                    local bar = frame.healthBar
                    -- Defer setup to break Blizzard's execution chain
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if not bar then return end
                            -- Only create new overlay out of combat
                            if not bar.ScooterRaidHealthFill then
                                if InCombatLockdown and InCombatLockdown() then
                                    queueRaidFrameReapply()
                                    return
                                end
                            end
                            ensureRaidHealthOverlay(bar, cfg)
                        end)
                    end
                end
            end)
        end

        -- Hook CompactUnitFrame_SetUnit for unit assignment changes
        if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
            _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
                if not unit or not isRaidHealthBar(frame) then return end

                local db = addon and addon.db and addon.db.profile
                local cfg = db and db.groupFrames and db.groupFrames.raid or nil

                local hasCustom = cfg and (
                    (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                    (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
                )

                if hasCustom then
                    local bar = frame.healthBar
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if not bar then return end
                            if not bar.ScooterRaidHealthFill then
                                if InCombatLockdown and InCombatLockdown() then
                                    queueRaidFrameReapply()
                                    return
                                end
                            end
                            ensureRaidHealthOverlay(bar, cfg)
                        end)
                    end
                end
            end)
        end
    end

    installRaidHealthOverlayHooks()
end

--------------------------------------------------------------------------------
-- Raid Frame Text Styling (Player Name)
--------------------------------------------------------------------------------
-- Applies font settings (Baseline 6) to raid frame name text elements.
-- Target: CompactRaidGroup*Member*Name (the name FontString on each raid unit frame)
--------------------------------------------------------------------------------
do
    -- Helper: Check if a CompactUnitFrame is actually a raid frame (not nameplate/party)
    -- Raid frames have names like "CompactRaidFrame1" or "CompactRaidGroup1Member1"
    local function isRaidFrame(frame)
        if not frame then return false end
        -- Use pcall to safely get name - some frames (nameplates) error on GetName
        local ok, name = pcall(function() return frame:GetName() end)
        if not ok or not name then return false end
        -- Match raid frame naming patterns
        if name:match("^CompactRaidFrame%d+$") then return true end
        if name:match("^CompactRaidGroup%d+Member%d+$") then return true end
        return false
    end

    -- Helper: Determine SetJustifyH based on anchor's horizontal component
    local function getJustifyHFromAnchor(anchor)
        if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
            return "LEFT"
        elseif anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then
            return "CENTER"
        elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
            return "RIGHT"
        end
        return "LEFT" -- fallback
    end

    -- Apply text settings to a raid frame's name FontString
    local function applyTextToRaidFrame(frame, cfg)
        if not frame or not cfg then return end

        -- Get the name FontString (frame.name is the standard CompactUnitFrame name element)
        local nameFS = frame.name
        if not nameFS then return end

        -- Resolve font face
        local fontFace = cfg.fontFace or "FRIZQT__"
        local resolvedFace
        if addon and addon.ResolveFontFace then
            resolvedFace = addon.ResolveFontFace(fontFace)
        else
            -- Fallback to GameFontNormal's font
            local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
            resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
        end

        -- Get settings with defaults
        local fontSize = tonumber(cfg.size) or 12
        local fontStyle = cfg.style or "OUTLINE"
        local color = cfg.color or { 1, 1, 1, 1 }
        local anchor = cfg.anchor or "TOPLEFT"
        local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

        -- Apply font (SetFont must be called before SetText)
        local success = pcall(nameFS.SetFont, nameFS, resolvedFace, fontSize, fontStyle)
        if not success then
            -- Fallback to default font on failure
            local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
            if fallback then
                pcall(nameFS.SetFont, nameFS, fallback, fontSize, fontStyle)
            end
        end

        -- Apply color
        if nameFS.SetTextColor then
            pcall(nameFS.SetTextColor, nameFS, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        end

        -- Apply text alignment based on anchor's horizontal component
        if nameFS.SetJustifyH then
            pcall(nameFS.SetJustifyH, nameFS, getJustifyHFromAnchor(anchor))
        end

        -- Capture baseline position on first application so we can restore later
        if not nameFS._ScootOriginalPoint then
            local point, relativeTo, relativePoint, x, y = nameFS:GetPoint(1)
            if point then
                nameFS._ScootOriginalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
            end
        end

        -- Apply anchor-based positioning with offsets relative to selected anchor
        local isDefaultAnchor = (anchor == "TOPLEFT")
        local isZeroOffset = (offsetX == 0 and offsetY == 0)

        if isDefaultAnchor and isZeroOffset and nameFS._ScootOriginalPoint then
            -- Restore baseline (stock position) when user has reset to default
            local orig = nameFS._ScootOriginalPoint
            nameFS:ClearAllPoints()
            nameFS:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
            -- Also restore default text alignment
            if nameFS.SetJustifyH then
                pcall(nameFS.SetJustifyH, nameFS, "LEFT")
            end
        else
            -- Position the name FontString using the user-selected anchor, relative to the frame
            nameFS:ClearAllPoints()
            nameFS:SetPoint(anchor, frame, anchor, offsetX, offsetY)
        end
    end

    -- Collect all raid frame name FontStrings
    local raidNameTexts = {}

    -- Shared helper: used both by ApplyRaidFrameTextStyle() and by CompactUnitFrame hook callbacks.
    -- Must be in outer scope so hooks can call it (Edit Mode will hit hooks before any manual apply).
    local function hasCustomTextSettings(cfg)
        if not cfg then return false end
        if cfg.fontFace and cfg.fontFace ~= "FRIZQT__" then return true end
        if cfg.size and cfg.size ~= 12 then return true end
        if cfg.style and cfg.style ~= "OUTLINE" then return true end
        if cfg.color then
            local c = cfg.color
            if c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or c[4] ~= 1 then return true end
        end
        -- Anchor customization (non-default position)
        if cfg.anchor and cfg.anchor ~= "TOPLEFT" then return true end
        if cfg.offset then
            if (cfg.offset.x and cfg.offset.x ~= 0) or (cfg.offset.y and cfg.offset.y ~= 0) then return true end
        end
        return false
    end

    local function collectRaidNameTexts()
        if wipe then
            wipe(raidNameTexts)
        else
            raidNameTexts = {}
        end

        -- Scan CompactRaidFrame1 through CompactRaidFrame40 (combined layout)
        for i = 1, 40 do
            local frame = _G["CompactRaidFrame" .. i]
            if frame and frame.name and not frame.name._ScootRaidTextCounted then
                frame.name._ScootRaidTextCounted = true
                table.insert(raidNameTexts, frame)
            end
        end

        -- Scan CompactRaidGroup1Member1 through CompactRaidGroup8Member5 (group layout)
        for group = 1, 8 do
            for member = 1, 5 do
                local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
                if frame and frame.name and not frame.name._ScootRaidTextCounted then
                    frame.name._ScootRaidTextCounted = true
                    table.insert(raidNameTexts, frame)
                end
            end
        end
    end

    -- Main entry point: Apply raid frame text styling from DB settings
    function addon.ApplyRaidFrameTextStyle()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        -- Zero‑Touch: only apply if user has configured raid text styling.
        local groupFrames = rawget(db, "groupFrames")
        local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
        local cfg = raidCfg and rawget(raidCfg, "textPlayerName") or nil
        if not cfg then
            return
        end

        -- Zero‑Touch: if user hasn't actually changed anything from the defaults, do nothing.
        if not hasCustomTextSettings(cfg) then
            return
        end

        -- Deprecated: Raid Player Name styling is now driven by overlay FontStrings
        -- (see ApplyRaidFrameNameOverlays). We must avoid moving Blizzard's `frame.name`
        -- because the overlay clipping container copies its anchor geometry to preserve
        -- truncation. Touching `frame.name` here reintroduces leaking/incorrect clipping.
        if addon.ApplyRaidFrameNameOverlays then
            addon.ApplyRaidFrameNameOverlays()
        end
    end

    -- Install hooks to reapply text styling when raid frames update
    local function installRaidFrameTextHooks()
        if addon._RaidFrameTextHooksInstalled then return end
        addon._RaidFrameTextHooksInstalled = true

        -- Deprecated: name styling hooks must not touch Blizzard's `frame.name`.
        -- Overlay system installs its own hooks (installRaidNameOverlayHooks()).
    end

    -- Install hooks when this module loads
    installRaidFrameTextHooks()
end

--------------------------------------------------------------------------------
-- Raid Frame Text Overlay (Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on raid frames that visually replace
-- Blizzard's name text. These overlays can be styled during initial setup and
-- their text content can be updated during combat without taint because we only
-- manipulate our own FontStrings.
--
-- Pattern: Mirror text via SetText hook, style on setup, hide Blizzard's element.
--------------------------------------------------------------------------------

do
    local function isRaidFrame(frame)
        if not frame then return false end
        local ok, name = pcall(function() return frame:GetName() end)
        if not ok or not name then return false end
        if name:match("^CompactRaidFrame%d+$") then return true end
        if name:match("^CompactRaidGroup%d+Member%d+$") then return true end
        return false
    end

    local function hasCustomTextSettings(cfg)
        if not cfg then return false end
        if cfg.fontFace and cfg.fontFace ~= "FRIZQT__" then return true end
        if cfg.size and cfg.size ~= 12 then return true end
        if cfg.style and cfg.style ~= "OUTLINE" then return true end
        if cfg.color then
            local c = cfg.color
            if c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or c[4] ~= 1 then return true end
        end
        -- Anchor customization (non-default position)
        if cfg.anchor and cfg.anchor ~= "TOPLEFT" then return true end
        if cfg.offset then
            if (cfg.offset.x and cfg.offset.x ~= 0) or (cfg.offset.y and cfg.offset.y ~= 0) then return true end
        end
        return false
    end

    local function getJustifyHFromAnchor(anchor)
        if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
            return "LEFT"
        elseif anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then
            return "CENTER"
        elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
            return "RIGHT"
        end
        return "LEFT"
    end

    local function styleRaidNameOverlay(frame, cfg)
        if not frame or not frame.ScooterRaidNameText or not cfg then return end

        local overlay = frame.ScooterRaidNameText
        local container = frame.ScooterRaidNameContainer or frame

        local fontFace = cfg.fontFace or "FRIZQT__"
        local resolvedFace
        if addon and addon.ResolveFontFace then
            resolvedFace = addon.ResolveFontFace(fontFace)
        else
            local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
            resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
        end

        local fontSize = tonumber(cfg.size) or 12
        local fontStyle = cfg.style or "OUTLINE"
        local color = cfg.color or { 1, 1, 1, 1 }
        local anchor = cfg.anchor or "TOPLEFT"
        local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

        local success = pcall(overlay.SetFont, overlay, resolvedFace, fontSize, fontStyle)
        if not success then
            local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
            if fallback then
                pcall(overlay.SetFont, overlay, fallback, fontSize, fontStyle)
            end
        end

        pcall(overlay.SetTextColor, overlay, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        pcall(overlay.SetJustifyH, overlay, getJustifyHFromAnchor(anchor))
        if overlay.SetJustifyV then
            pcall(overlay.SetJustifyV, overlay, "MIDDLE")
        end
        if overlay.SetWordWrap then
            pcall(overlay.SetWordWrap, overlay, false)
        end
        if overlay.SetNonSpaceWrap then
            pcall(overlay.SetNonSpaceWrap, overlay, false)
        end
        if overlay.SetMaxLines then
            pcall(overlay.SetMaxLines, overlay, 1)
        end

        -- Keep the clipping container tall enough for the configured font size.
        -- If the container is created too early (before Blizzard sizes `frame.name`), it can end up 1px tall,
        -- which clips the overlay into a thin horizontal sliver.
        if container and container.SetHeight then
            local minH = math.max(12, (tonumber(fontSize) or 12) + 6)
            if overlay.GetStringHeight then
                local okSH, sh = pcall(overlay.GetStringHeight, overlay)
                if okSH and sh and sh > 0 and (sh + 2) > minH then
                    minH = sh + 2
                end
            end
            pcall(container.SetHeight, container, minH)
        end

        -- Position within an addon-owned clipping container that matches Blizzard's name anchors.
        -- This preserves truncation/clipping even when using single-point anchors (CENTER, etc.).
        overlay:ClearAllPoints()
        overlay:SetPoint(anchor, container, anchor, offsetX, offsetY)
    end

    local function hideBlizzardRaidNameText(frame)
        if not frame or not frame.name then return end
        local blizzName = frame.name

        blizzName._ScootHidden = true
        if blizzName.SetAlpha then
            pcall(blizzName.SetAlpha, blizzName, 0)
        end
        if blizzName.Hide then
            pcall(blizzName.Hide, blizzName)
        end

        if not blizzName._ScootAlphaHooked and _G.hooksecurefunc then
            blizzName._ScootAlphaHooked = true
            _G.hooksecurefunc(blizzName, "SetAlpha", function(self, alpha)
                if alpha > 0 and self._ScootHidden then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if self._ScootHidden then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end
            end)
        end

        if not blizzName._ScootShowHooked and _G.hooksecurefunc then
            blizzName._ScootShowHooked = true
            _G.hooksecurefunc(blizzName, "Show", function(self)
                if not self._ScootHidden then return end
                -- Kill visibility immediately (avoid flicker), then defer Hide to break chains.
                if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if self and self._ScootHidden then
                            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                            if self.Hide then pcall(self.Hide, self) end
                        end
                    end)
                else
                    if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                    if self.Hide then pcall(self.Hide, self) end
                end
            end)
        end
    end

    local function showBlizzardRaidNameText(frame)
        if not frame or not frame.name then return end
        frame.name._ScootHidden = nil
        if frame.name.SetAlpha then
            pcall(frame.name.SetAlpha, frame.name, 1)
        end
        if frame.name.Show then
            pcall(frame.name.Show, frame.name)
        end
    end

    local function ensureRaidNameOverlay(frame, cfg)
        if not frame then return end

        local hasCustom = hasCustomTextSettings(cfg)
        frame._ScootRaidNameOverlayActive = hasCustom

        if not hasCustom then
            if frame.ScooterRaidNameText then
                frame.ScooterRaidNameText:Hide()
            end
            showBlizzardRaidNameText(frame)
            return
        end

        -- Ensure an addon-owned clipping container that matches Blizzard's original name anchors.
        if not frame.ScooterRaidNameContainer then
            local container = CreateFrame("Frame", nil, frame)
            container:SetClipsChildren(true)

            -- Copy the Blizzard name's anchor layout (often two points) so our container width matches stock.
            local p1, r1, rp1, x1, y1 = nil, nil, nil, 0, 0
            local p2, r2, rp2, x2, y2 = nil, nil, nil, 0, 0
            if frame.name and frame.name.GetPoint then
                local ok1, ap1, ar1, arp1, ax1, ay1 = pcall(frame.name.GetPoint, frame.name, 1)
                if ok1 then
                    p1, r1, rp1, x1, y1 = ap1, ar1, arp1, ax1, ay1
                end
                local ok2, ap2, ar2, arp2, ax2, ay2 = pcall(frame.name.GetPoint, frame.name, 2)
                if ok2 then
                    p2, r2, rp2, x2, y2 = ap2, ar2, arp2, ax2, ay2
                end
            end

            container:ClearAllPoints()
            if p1 then
                container:SetPoint(p1, r1 or frame, rp1 or p1, tonumber(x1) or 0, tonumber(y1) or 0)
                if p2 then
                    container:SetPoint(p2, r2 or frame, rp2 or p2, tonumber(x2) or 0, tonumber(y2) or 0)
                else
                    -- Fallback: reasonable right boundary if Blizzard only provided one point.
                    container:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
                end
            else
                -- Ultimate fallback: match common CUF name region bounds.
                container:SetPoint("LEFT", frame, "LEFT", 3, 0)
                container:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
            end

            -- Critical: our container must have a non-zero height or it will clip everything.
            -- Blizzard's name element is usually anchored with left/right + top only, so height is implicit there.
            local fontSize = tonumber(cfg and cfg.size) or 12
            local h = math.max(12, fontSize + 6)
            if frame.name and frame.name.GetHeight then
                local okH, hh = pcall(frame.name.GetHeight, frame.name)
                if okH and hh and hh > h then
                    h = hh
                end
            end
            if container.SetHeight then
                pcall(container.SetHeight, container, h)
            end

            frame.ScooterRaidNameContainer = container
        end

        -- Create overlay FontString if it doesn't exist (as a child of the clipping container)
        if not frame.ScooterRaidNameText then
            local parentForText = frame.ScooterRaidNameContainer or frame
            local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
            overlay:SetDrawLayer("OVERLAY", 7)
            frame.ScooterRaidNameText = overlay

            if frame.name and not frame.name._ScootTextMirrorHooked and _G.hooksecurefunc then
                frame.name._ScootTextMirrorHooked = true
                frame.name._ScootTextMirrorOwner = frame
                _G.hooksecurefunc(frame.name, "SetText", function(self, text)
                    local owner = self._ScootTextMirrorOwner
                    if owner and owner.ScooterRaidNameText and owner._ScootRaidNameOverlayActive then
                        owner.ScooterRaidNameText:SetText(text or "")
                    end
                end)
            end
        end

        styleRaidNameOverlay(frame, cfg)
        hideBlizzardRaidNameText(frame)

        if frame.name and frame.name.GetText then
            local currentText = frame.name:GetText()
            frame.ScooterRaidNameText:SetText(currentText or "")
        end

        frame.ScooterRaidNameText:Show()
    end

    local function disableRaidNameOverlay(frame)
        if not frame then return end
        frame._ScootRaidNameOverlayActive = false
        if frame.ScooterRaidNameText then
            frame.ScooterRaidNameText:Hide()
        end
        showBlizzardRaidNameText(frame)
    end

    function addon.ApplyRaidFrameNameOverlays()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local groupFrames = rawget(db, "groupFrames")
        local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
        local cfg = raidCfg and rawget(raidCfg, "textPlayerName") or nil

        local hasCustom = hasCustomTextSettings(cfg)

        -- Combined layout: CompactRaidFrame1..40
        for i = 1, 40 do
            local frame = _G["CompactRaidFrame" .. i]
            if frame and frame.name then
                if hasCustom then
                    if not (InCombatLockdown and InCombatLockdown()) then
                        ensureRaidNameOverlay(frame, cfg)
                    elseif frame.ScooterRaidNameText then
                        styleRaidNameOverlay(frame, cfg)
                    end
                else
                    disableRaidNameOverlay(frame)
                end
            end
        end

        -- Group layout: CompactRaidGroup1Member1..CompactRaidGroup8Member5
        for group = 1, 8 do
            for member = 1, 5 do
                local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
                if frame and frame.name then
                    if hasCustom then
                        if not (InCombatLockdown and InCombatLockdown()) then
                            ensureRaidNameOverlay(frame, cfg)
                        elseif frame.ScooterRaidNameText then
                            styleRaidNameOverlay(frame, cfg)
                        end
                    else
                        disableRaidNameOverlay(frame)
                    end
                end
            end
        end
    end

    function addon.RestoreRaidFrameNameOverlays()
        for i = 1, 40 do
            local frame = _G["CompactRaidFrame" .. i]
            if frame then
                disableRaidNameOverlay(frame)
            end
        end
        for group = 1, 8 do
            for member = 1, 5 do
                local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
                if frame then
                    disableRaidNameOverlay(frame)
                end
            end
        end
    end

    local function installRaidNameOverlayHooks()
        if addon._RaidNameOverlayHooksInstalled then return end
        addon._RaidNameOverlayHooksInstalled = true

        local function getCfg()
            local db = addon and addon.db and addon.db.profile
            local gf = db and rawget(db, "groupFrames") or nil
            local raidCfg = gf and rawget(gf, "raid") or nil
            return raidCfg and rawget(raidCfg, "textPlayerName") or nil
        end

        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
            _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
                if not (frame and frame.name and isRaidFrame(frame)) then return end
                local cfg = getCfg()
                if not hasCustomTextSettings(cfg) then return end

                local frameRef = frame
                local cfgRef = cfg
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frameRef then return end
                        if InCombatLockdown and InCombatLockdown() then
                            queueRaidFrameReapply()
                            return
                        end
                        ensureRaidNameOverlay(frameRef, cfgRef)
                    end)
                else
                    if InCombatLockdown and InCombatLockdown() then
                        queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end
            end)
        end

        if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
            _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
                if not unit then return end
                if not (frame and frame.name and isRaidFrame(frame)) then return end
                local cfg = getCfg()
                if not hasCustomTextSettings(cfg) then return end

                local frameRef = frame
                local cfgRef = cfg
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frameRef then return end
                        if InCombatLockdown and InCombatLockdown() then
                            queueRaidFrameReapply()
                            return
                        end
                        ensureRaidNameOverlay(frameRef, cfgRef)
                    end)
                else
                    if InCombatLockdown and InCombatLockdown() then
                        queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end
            end)
        end

        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateName then
            _G.hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
                if not (frame and frame.name and isRaidFrame(frame)) then return end
                local cfg = getCfg()
                if not hasCustomTextSettings(cfg) then return end

                local frameRef = frame
                local cfgRef = cfg
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frameRef then return end
                        if InCombatLockdown and InCombatLockdown() then
                            queueRaidFrameReapply()
                            return
                        end
                        ensureRaidNameOverlay(frameRef, cfgRef)
                    end)
                else
                    if InCombatLockdown and InCombatLockdown() then
                        queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end
            end)
        end
    end

    installRaidNameOverlayHooks()
end

--------------------------------------------------------------------------------
-- Raid Frame Text Styling (Status Text)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Player Name to raid unit frame StatusText.
-- Targets:
--   - CompactRaidFrame1..40: frame.statusText (FontString, name "$parentStatusText")
--   - CompactRaidGroup1..8Member1..5: frame.statusText (FontString, name "$parentStatusText")
--------------------------------------------------------------------------------
do
    -- Helper: Determine SetJustifyH based on anchor's horizontal component
    local function getJustifyHFromAnchor(anchor)
        if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
            return "LEFT"
        elseif anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then
            return "CENTER"
        elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
            return "RIGHT"
        end
        return "LEFT"
    end

    local function hasCustomTextSettings(cfg)
        if not cfg then return false end
        if cfg.fontFace and cfg.fontFace ~= "FRIZQT__" then return true end
        if cfg.size and cfg.size ~= 12 then return true end
        if cfg.style and cfg.style ~= "OUTLINE" then return true end
        if cfg.color then
            local c = cfg.color
            if c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or c[4] ~= 1 then return true end
        end
        if cfg.anchor and cfg.anchor ~= "TOPLEFT" then return true end
        if cfg.offset then
            if (cfg.offset.x and cfg.offset.x ~= 0) or (cfg.offset.y and cfg.offset.y ~= 0) then return true end
        end
        return false
    end

    local function applyTextToFontString(fs, ownerFrame, cfg)
        if not fs or not ownerFrame or not cfg then return end

        -- Resolve font face
        local fontFace = cfg.fontFace or "FRIZQT__"
        local resolvedFace
        if addon and addon.ResolveFontFace then
            resolvedFace = addon.ResolveFontFace(fontFace)
        else
            local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
            resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
        end

        -- Get settings with defaults
        local fontSize = tonumber(cfg.size) or 12
        local fontStyle = cfg.style or "OUTLINE"
        local color = cfg.color or { 1, 1, 1, 1 }
        local anchor = cfg.anchor or "TOPLEFT"
        local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

        -- Apply font
        local success = pcall(fs.SetFont, fs, resolvedFace, fontSize, fontStyle)
        if not success then
            local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
            if fallback then
                pcall(fs.SetFont, fs, fallback, fontSize, fontStyle)
            end
        end

        -- Apply color + alignment
        if fs.SetTextColor then
            pcall(fs.SetTextColor, fs, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        end
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, getJustifyHFromAnchor(anchor))
        end

        -- Capture baseline position on first application so we can restore later
        if not fs._ScootOriginalPoint_StatusText then
            local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
            if point then
                fs._ScootOriginalPoint_StatusText = { point, relativeTo, relativePoint, x or 0, y or 0 }
            end
        end

        local isDefaultAnchor = (anchor == "TOPLEFT")
        local isZeroOffset = (offsetX == 0 and offsetY == 0)

        if isDefaultAnchor and isZeroOffset and fs._ScootOriginalPoint_StatusText then
            -- Restore baseline (stock position) when user has reset to default
            local orig = fs._ScootOriginalPoint_StatusText
            fs:ClearAllPoints()
            fs:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
            if fs.SetJustifyH then
                pcall(fs.SetJustifyH, fs, "LEFT")
            end
        else
            -- Position the FontString using the user-selected anchor, relative to the owner frame
            fs:ClearAllPoints()
            fs:SetPoint(anchor, ownerFrame, anchor, offsetX, offsetY)
        end
    end

    local function applyStatusTextToRaidFrame(frame, cfg)
        if not frame or not cfg then return end
        local fs = frame.statusText
        if not fs then return end
        applyTextToFontString(fs, frame, cfg)
    end

    function addon.ApplyRaidFrameStatusTextStyle()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        -- Zero‑Touch: only apply if user has configured raid status text styling.
        local groupFrames = rawget(db, "groupFrames")
        local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
        local cfg = raidCfg and rawget(raidCfg, "textStatusText") or nil
        if not cfg then
            return
        end

        -- Zero‑Touch: if user hasn't actually changed anything from the defaults, do nothing.
        if not hasCustomTextSettings(cfg) then
            return
        end

        if InCombatLockdown and InCombatLockdown() then
            queueRaidFrameReapply()
            return
        end

        -- Combined layout: CompactRaidFrame1..40
        for i = 1, 40 do
            local frame = _G["CompactRaidFrame" .. i]
            if frame and frame.statusText then
                applyStatusTextToRaidFrame(frame, cfg)
            end
        end

        -- Group layout: CompactRaidGroup1..8Member1..5
        for group = 1, 8 do
            for member = 1, 5 do
                local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
                if frame and frame.statusText then
                    applyStatusTextToRaidFrame(frame, cfg)
                end
            end
        end
    end

    local function isRaidFrame(frame)
        if not frame then return false end
        local ok, name = pcall(function() return frame:GetName() end)
        if not ok or not name then return false end
        if name:match("^CompactRaidFrame%d+$") then return true end
        if name:match("^CompactRaidGroup%d+Member%d+$") then return true end
        return false
    end

    local function installRaidFrameStatusTextHooks()
        if addon._RaidFrameStatusTextHooksInstalled then return end
        addon._RaidFrameStatusTextHooksInstalled = true

        local function tryApply(frame)
            if not frame or not frame.statusText or not isRaidFrame(frame) then
                return
            end
            local db = addon and addon.db and addon.db.profile
            local cfg = db and db.groupFrames and db.groupFrames.raid and db.groupFrames.raid.textStatusText or nil
            if not cfg or not hasCustomTextSettings(cfg) then
                return
            end
            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if InCombatLockdown and InCombatLockdown() then
                        queueRaidFrameReapply()
                        return
                    end
                    applyStatusTextToRaidFrame(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    queueRaidFrameReapply()
                    return
                end
                applyStatusTextToRaidFrame(frameRef, cfgRef)
            end
        end

        if _G.hooksecurefunc then
            if _G.CompactUnitFrame_UpdateStatusText then
                _G.hooksecurefunc("CompactUnitFrame_UpdateStatusText", tryApply)
            end
            if _G.CompactUnitFrame_UpdateLayout then
                _G.hooksecurefunc("CompactUnitFrame_UpdateLayout", tryApply)
            end
            if _G.CompactUnitFrame_UpdateAll then
                _G.hooksecurefunc("CompactUnitFrame_UpdateAll", tryApply)
            end
            if _G.CompactUnitFrame_SetUnit then
                _G.hooksecurefunc("CompactUnitFrame_SetUnit", tryApply)
            end
        end
    end

    installRaidFrameStatusTextHooks()
end

--------------------------------------------------------------------------------
-- Raid Frame Text Styling (Group Numbers)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Player Name to raid group title text.
-- Target: CompactRaidGroup1..8Title (Button, parentKey "title").
--------------------------------------------------------------------------------
do
    -- Helper: Determine SetJustifyH based on anchor's horizontal component
    local function getJustifyHFromAnchor(anchor)
        if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
            return "LEFT"
        elseif anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then
            return "CENTER"
        elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
            return "RIGHT"
        end
        return "LEFT"
    end

    local function hasCustomTextSettings(cfg)
        if not cfg then return false end
        if cfg.fontFace and cfg.fontFace ~= "FRIZQT__" then return true end
        if cfg.size and cfg.size ~= 12 then return true end
        if cfg.style and cfg.style ~= "OUTLINE" then return true end
        if cfg.color then
            local c = cfg.color
            if c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or c[4] ~= 1 then return true end
        end
        if cfg.anchor and cfg.anchor ~= "TOPLEFT" then return true end
        if cfg.offset then
            if (cfg.offset.x and cfg.offset.x ~= 0) or (cfg.offset.y and cfg.offset.y ~= 0) then return true end
        end
        return false
    end

    local function applyTextToFontString(fs, ownerFrame, cfg)
        if not fs or not ownerFrame or not cfg then return end

        local fontFace = cfg.fontFace or "FRIZQT__"
        local resolvedFace
        if addon and addon.ResolveFontFace then
            resolvedFace = addon.ResolveFontFace(fontFace)
        else
            local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
            resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
        end

        local fontSize = tonumber(cfg.size) or 12
        local fontStyle = cfg.style or "OUTLINE"
        local color = cfg.color or { 1, 1, 1, 1 }
        local anchor = cfg.anchor or "TOPLEFT"
        local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

        local success = pcall(fs.SetFont, fs, resolvedFace, fontSize, fontStyle)
        if not success then
            local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
            if fallback then
                pcall(fs.SetFont, fs, fallback, fontSize, fontStyle)
            end
        end

        if fs.SetTextColor then
            pcall(fs.SetTextColor, fs, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        end
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, getJustifyHFromAnchor(anchor))
        end

        if not fs._ScootOriginalPoint_GroupTitle then
            local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
            if point then
                fs._ScootOriginalPoint_GroupTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
            end
        end

        local isDefaultAnchor = (anchor == "TOPLEFT")
        local isZeroOffset = (offsetX == 0 and offsetY == 0)

        if isDefaultAnchor and isZeroOffset and fs._ScootOriginalPoint_GroupTitle then
            local orig = fs._ScootOriginalPoint_GroupTitle
            fs:ClearAllPoints()
            fs:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
            if fs.SetJustifyH then
                pcall(fs.SetJustifyH, fs, "LEFT")
            end
        else
            fs:ClearAllPoints()
            fs:SetPoint(anchor, ownerFrame, anchor, offsetX, offsetY)
        end
    end

    local function applyGroupTitleToButton(titleButton, cfg)
        if not titleButton or not cfg then return end
        if not titleButton.GetFontString then return end
        local fs = titleButton:GetFontString()
        if not fs then return end
        applyTextToFontString(fs, titleButton, cfg)
    end

    function addon.ApplyRaidFrameGroupTitlesStyle()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        -- Zero‑Touch: only apply if user has configured raid group title styling.
        local groupFrames = rawget(db, "groupFrames")
        local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
        local cfg = raidCfg and rawget(raidCfg, "textGroupNumbers") or nil
        if not cfg then
            return
        end

        if not hasCustomTextSettings(cfg) then
            return
        end

        if InCombatLockdown and InCombatLockdown() then
            queueRaidFrameReapply()
            return
        end

        for group = 1, 8 do
            local groupFrame = _G["CompactRaidGroup" .. group]
            local titleButton = (groupFrame and groupFrame.title) or _G["CompactRaidGroup" .. group .. "Title"]
            if titleButton then
                applyGroupTitleToButton(titleButton, cfg)
            end
        end
    end

    local function isCompactRaidGroupFrame(frame)
        if not frame then return false end
        local ok, name = pcall(function() return frame:GetName() end)
        if not ok or not name then return false end
        return name:match("^CompactRaidGroup%d+$") ~= nil
    end

    local function installRaidFrameGroupTitleHooks()
        if addon._RaidFrameGroupTitleHooksInstalled then return end
        addon._RaidFrameGroupTitleHooksInstalled = true

        local function tryApplyTitle(groupFrame)
            if not groupFrame or not isCompactRaidGroupFrame(groupFrame) then
                return
            end
            local titleButton = groupFrame.title or _G[groupFrame:GetName() .. "Title"]
            if not titleButton then return end

            local db = addon and addon.db and addon.db.profile
            local cfg = db and db.groupFrames and db.groupFrames.raid and db.groupFrames.raid.textGroupNumbers or nil
            if not cfg or not hasCustomTextSettings(cfg) then
                return
            end

            local titleRef = titleButton
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if InCombatLockdown and InCombatLockdown() then
                        queueRaidFrameReapply()
                        return
                    end
                    applyGroupTitleToButton(titleRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    queueRaidFrameReapply()
                    return
                end
                applyGroupTitleToButton(titleRef, cfgRef)
            end
        end

        if _G.hooksecurefunc then
            if _G.CompactRaidGroup_UpdateLayout then
                _G.hooksecurefunc("CompactRaidGroup_UpdateLayout", tryApplyTitle)
            end
            if _G.CompactRaidGroup_InitializeForGroup then
                _G.hooksecurefunc("CompactRaidGroup_InitializeForGroup", function(groupFrame, groupIndex)
                    tryApplyTitle(groupFrame)
                end)
            end
            if _G.CompactRaidGroup_UpdateUnits then
                _G.hooksecurefunc("CompactRaidGroup_UpdateUnits", tryApplyTitle)
            end
        end
    end

    installRaidFrameGroupTitleHooks()
end

--------------------------------------------------------------------------------
-- Party Frame Health Bar Styling
--------------------------------------------------------------------------------
-- Applies foreground/background texture and color settings to party frame health
-- bars (CompactPartyFrameMember[1-5]HealthBar).
--------------------------------------------------------------------------------

do
    -- Cache for discovered party frame health bars
    local partyHealthBars = {}

    local function collectPartyHealthBars()
        partyHealthBars = {}
        for i = 1, 5 do
            local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
            if bar then
                table.insert(partyHealthBars, bar)
            end
        end
    end

    local function applyToPartyHealthBar(bar, cfg)
        if not bar or not cfg then return end

        local texKey = cfg.healthBarTexture or "default"
        local colorMode = cfg.healthBarColorMode or "default"
        local tint = cfg.healthBarTint
        local bgTexKey = cfg.healthBarBackgroundTexture or "default"
        local bgColorMode = cfg.healthBarBackgroundColorMode or "default"
        local bgTint = cfg.healthBarBackgroundTint
        local bgOpacity = cfg.healthBarBackgroundOpacity or 50

        if addon._ApplyToStatusBar then
            addon._ApplyToStatusBar(bar, texKey, colorMode, tint, nil, "health", nil)
        end

        if addon._ApplyBackgroundToStatusBar then
            addon._ApplyBackgroundToStatusBar(bar, bgTexKey, bgColorMode, bgTint, bgOpacity, "Party", "health")
        end
    end

    function addon.ApplyPartyFrameHealthBarStyle()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        -- Zero‑Touch: only apply if the user has configured groupFrames.party.
        local groupFrames = rawget(db, "groupFrames")
        local cfg = groupFrames and rawget(groupFrames, "party") or nil
        if not cfg then
            return
        end

        -- Zero‑Touch: if nothing is actually customized (all defaults), do not touch.
        local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                          (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                          (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                          (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
        if not hasCustom then
            return
        end

        if InCombatLockdown and InCombatLockdown() then
            queuePartyFrameReapply()
            return
        end

        collectPartyHealthBars()
        for _, bar in ipairs(partyHealthBars) do
            applyToPartyHealthBar(bar, cfg)
        end
    end

    local function isPartyFrame(frame)
        if not frame then return false end
        local ok, name = pcall(function() return frame:GetName() end)
        if not ok or not name then return false end
        return name:match("^CompactPartyFrameMember%d+$") ~= nil
    end

    local function installPartyFrameHooks()
        if addon._PartyFrameHooksInstalled then return end
        addon._PartyFrameHooksInstalled = true

        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
            _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
                if frame and frame.healthBar and isPartyFrame(frame) then
                    local db = addon and addon.db and addon.db.profile
                    local cfg = db and db.groupFrames and db.groupFrames.party or nil
                    if cfg then
                        local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                                          (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                                          (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                                          (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
                        if hasCustom then
                            local bar = frame.healthBar
                            local cfgRef = cfg
                            if _G.C_Timer and _G.C_Timer.After then
                                _G.C_Timer.After(0, function()
                                    if InCombatLockdown and InCombatLockdown() then
                                        queuePartyFrameReapply()
                                        return
                                    end
                                    applyToPartyHealthBar(bar, cfgRef)
                                end)
                            else
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePartyFrameReapply()
                                    return
                                end
                                applyToPartyHealthBar(bar, cfgRef)
                            end
                        end
                    end
                end
            end)
        end

        if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
            _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
                if frame and frame.healthBar and unit and isPartyFrame(frame) then
                    local db = addon and addon.db and addon.db.profile
                    local cfg = db and db.groupFrames and db.groupFrames.party or nil
                    if cfg then
                        local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                                          (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                                          (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                                          (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
                        if hasCustom then
                            local bar = frame.healthBar
                            local cfgRef = cfg
                            if _G.C_Timer and _G.C_Timer.After then
                                _G.C_Timer.After(0, function()
                                    if InCombatLockdown and InCombatLockdown() then
                                        queuePartyFrameReapply()
                                        return
                                    end
                                    applyToPartyHealthBar(bar, cfgRef)
                                end)
                            else
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePartyFrameReapply()
                                    return
                                end
                                applyToPartyHealthBar(bar, cfgRef)
                            end
                        end
                    end
                end
            end)
        end
    end

    installPartyFrameHooks()
end

--------------------------------------------------------------------------------
-- Party Frame Health Bar Overlay (Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned overlay textures on party health bars that visually
-- replace Blizzard's fill texture. These overlays can be updated during combat
-- without taint because we only manipulate our own textures, not Blizzard's
-- protected StatusBar.
--
-- Pattern: Same as ScooterRectFill for individual unit frames.
--
-- BACKGROUND TEXTURE NOTE: The background texture (ScooterModBG) does NOT need
-- a separate overlay because it is already an addon-owned texture created via
-- _ApplyBackgroundToStatusBar. Once created, it persists through combat since
-- we own it. The only limitation is initial creation must happen out of combat.
--------------------------------------------------------------------------------

do
    -- Update the overlay texture width based on health bar value
    -- NOTE: No combat guard needed - we only touch our own texture (ScooterPartyHealthFill)
    local function updatePartyHealthOverlay(bar)
        if not bar or not bar.ScooterPartyHealthFill then return end
        if not bar._ScootPartyOverlayActive then
            bar.ScooterPartyHealthFill:Hide()
            return
        end

        local overlay = bar.ScooterPartyHealthFill
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
        -- Party health bars fill left-to-right
        overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    end

    -- Apply texture and color to the overlay based on config
    local function stylePartyHealthOverlay(bar, cfg)
        if not bar or not bar.ScooterPartyHealthFill or not cfg then return end

        local overlay = bar.ScooterPartyHealthFill
        local texKey = cfg.healthBarTexture or "default"
        local colorMode = cfg.healthBarColorMode or "default"
        local tint = cfg.healthBarTint

        -- Resolve texture path
        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)

        if resolvedPath then
            overlay:SetTexture(resolvedPath)
        else
            -- Default: copy from bar's current texture or use a fallback
            local tex = bar:GetStatusBarTexture()
            local applied = false
            if tex then
                local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
                if okAtlas and atlasName and atlasName ~= "" then
                    if overlay.SetAtlas then
                        pcall(overlay.SetAtlas, overlay, atlasName, true)
                        applied = true
                    end
                end
                if not applied then
                    local okTex, texPath = pcall(tex.GetTexture, tex)
                    if okTex and texPath then
                        if type(texPath) == "string" and texPath:match("^[A-Za-z]") and not texPath:match("\\") and not texPath:match("/") then
                            -- Likely an atlas token, use SetAtlas
                            if overlay.SetAtlas then
                                pcall(overlay.SetAtlas, overlay, texPath, true)
                                applied = true
                            end
                        elseif type(texPath) == "number" or (type(texPath) == "string" and (texPath:match("\\") or texPath:match("/"))) then
                            pcall(overlay.SetTexture, overlay, texPath)
                            applied = true
                        end
                    end
                end
            end
            if not applied then
                -- Ultimate fallback: white texture
                overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
            end
        end

        -- Apply color based on mode
        local r, g, b, a = 1, 1, 1, 1
        if colorMode == "custom" and type(tint) == "table" then
            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
        elseif colorMode == "class" then
            -- For party frames, we'd need the unit's class - for now use a green health color
            -- This could be enhanced to read from UnitClass(bar.unit) if needed
            r, g, b, a = 0, 1, 0, 1
        elseif colorMode == "texture" then
            r, g, b, a = 1, 1, 1, 1
        else
            -- Default: use Blizzard's current bar color
            local barR, barG, barB = bar:GetStatusBarColor()
            if barR then
                r, g, b = barR, barG, barB
            else
                r, g, b = 0, 1, 0
            end
        end
        overlay:SetVertexColor(r, g, b, a)
    end

    -- Hide Blizzard's fill texture and install alpha-enforcement hook
    local function hideBlizzardPartyHealthFill(bar)
        if not bar then return end
        local blizzFill = bar:GetStatusBarTexture()
        if not blizzFill then return end

        -- Mark as hidden and set alpha to 0
        blizzFill._ScootHidden = true
        blizzFill:SetAlpha(0)

        -- Install alpha-enforcement hook (only once per texture)
        if not blizzFill._ScootAlphaHooked and _G.hooksecurefunc then
            blizzFill._ScootAlphaHooked = true
            _G.hooksecurefunc(blizzFill, "SetAlpha", function(self, alpha)
                if alpha > 0 and self._ScootHidden then
                    -- Defer to avoid fighting Blizzard's call
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if self._ScootHidden then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end
            end)
        end
    end

    -- Show Blizzard's fill texture (for restore/cleanup)
    local function showBlizzardPartyHealthFill(bar)
        if not bar then return end
        local blizzFill = bar:GetStatusBarTexture()
        if blizzFill then
            blizzFill._ScootHidden = nil
            blizzFill:SetAlpha(1)
        end
    end

    -- Create or update the party health overlay for a specific bar
    local function ensurePartyHealthOverlay(bar, cfg)
        if not bar then return end

        -- Determine if overlay should be active based on config
        local hasCustom = cfg and (
            (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
            (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
        )

        bar._ScootPartyOverlayActive = hasCustom

        if not hasCustom then
            -- Disable overlay, show Blizzard's texture
            if bar.ScooterPartyHealthFill then
                bar.ScooterPartyHealthFill:Hide()
            end
            showBlizzardPartyHealthFill(bar)
            return
        end

        -- Create overlay texture if it doesn't exist
        if not bar.ScooterPartyHealthFill then
            local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 2)
            overlay:SetVertTile(false)
            overlay:SetHorizTile(false)
            overlay:SetTexCoord(0, 1, 0, 1)
            bar.ScooterPartyHealthFill = overlay

            -- Install hooks for value/size changes - NO COMBAT GUARDS
            -- These hooks only touch our overlay texture, not Blizzard's StatusBar
            if _G.hooksecurefunc and not bar._ScootPartyOverlayHooksInstalled then
                bar._ScootPartyOverlayHooksInstalled = true
                _G.hooksecurefunc(bar, "SetValue", function(self)
                    updatePartyHealthOverlay(self)
                end)
                _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                    updatePartyHealthOverlay(self)
                end)
                if bar.HookScript then
                    bar:HookScript("OnSizeChanged", function(self)
                        updatePartyHealthOverlay(self)
                    end)
                end
            end
        end

        -- Hook SetStatusBarTexture to re-hide Blizzard's fill if it swaps textures
        if not bar._ScootPartyTextureSwapHooked and _G.hooksecurefunc then
            bar._ScootPartyTextureSwapHooked = true
            _G.hooksecurefunc(bar, "SetStatusBarTexture", function(self)
                if self._ScootPartyOverlayActive then
                    -- Blizzard may have created a new texture, re-hide it
                    -- Defer to break execution chain
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            hideBlizzardPartyHealthFill(self)
                        end)
                    end
                end
            end)
        end

        -- Style the overlay and hide Blizzard's fill
        stylePartyHealthOverlay(bar, cfg)
        hideBlizzardPartyHealthFill(bar)

        -- Trigger initial size calculation
        updatePartyHealthOverlay(bar)
    end

    -- Disable overlay and restore Blizzard's appearance for a bar
    local function disablePartyHealthOverlay(bar)
        if not bar then return end
        bar._ScootPartyOverlayActive = false
        if bar.ScooterPartyHealthFill then
            bar.ScooterPartyHealthFill:Hide()
        end
        showBlizzardPartyHealthFill(bar)
    end

    -- Apply overlays to all party health bars
    function addon.ApplyPartyFrameHealthOverlays()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local groupFrames = rawget(db, "groupFrames")
        local cfg = groupFrames and rawget(groupFrames, "party") or nil

        -- Zero-Touch check
        local hasCustom = cfg and (
            (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
            (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
        )

        for i = 1, 5 do
            local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
            if bar then
                if hasCustom then
                    -- Only create overlays out of combat (initial setup)
                    if not (InCombatLockdown and InCombatLockdown()) then
                        ensurePartyHealthOverlay(bar, cfg)
                    elseif bar.ScooterPartyHealthFill then
                        -- Already have overlay, just update styling (safe during combat for our texture)
                        stylePartyHealthOverlay(bar, cfg)
                        updatePartyHealthOverlay(bar)
                    end
                else
                    disablePartyHealthOverlay(bar)
                end
            end
        end
    end

    -- Restore all party health bars to stock appearance
    function addon.RestorePartyFrameHealthOverlays()
        for i = 1, 5 do
            local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
            if bar then
                disablePartyHealthOverlay(bar)
            end
        end
    end

    -- Install hooks that trigger overlay setup/updates via CompactUnitFrame events
    local function installPartyHealthOverlayHooks()
        if addon._PartyHealthOverlayHooksInstalled then return end
        addon._PartyHealthOverlayHooksInstalled = true

        local function isPartyHealthBar(frame)
            if not frame or not frame.healthBar then return false end
            local ok, name = pcall(function() return frame:GetName() end)
            if not ok or not name then return false end
            return name:match("^CompactPartyFrameMember%d+$") ~= nil
        end

        -- Hook CompactUnitFrame_UpdateAll to set up overlays
        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
            _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
                if not isPartyHealthBar(frame) then return end

                local db = addon and addon.db and addon.db.profile
                local cfg = db and db.groupFrames and db.groupFrames.party or nil

                local hasCustom = cfg and (
                    (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                    (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
                )

                if hasCustom then
                    local bar = frame.healthBar
                    -- Defer setup to break Blizzard's execution chain
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if not bar then return end
                            -- Only create new overlay out of combat
                            if not bar.ScooterPartyHealthFill then
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePartyFrameReapply()
                                    return
                                end
                            end
                            ensurePartyHealthOverlay(bar, cfg)
                        end)
                    end
                end
            end)
        end

        -- Hook CompactUnitFrame_SetUnit for unit assignment changes
        if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
            _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
                if not unit or not isPartyHealthBar(frame) then return end

                local db = addon and addon.db and addon.db.profile
                local cfg = db and db.groupFrames and db.groupFrames.party or nil

                local hasCustom = cfg and (
                    (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                    (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
                )

                if hasCustom then
                    local bar = frame.healthBar
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if not bar then return end
                            if not bar.ScooterPartyHealthFill then
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePartyFrameReapply()
                                    return
                                end
                            end
                            ensurePartyHealthOverlay(bar, cfg)
                        end)
                    end
                end
            end)
        end
    end

    installPartyHealthOverlayHooks()
end

--------------------------------------------------------------------------------
-- Party Frame Text Styling (Player Name)
--------------------------------------------------------------------------------
-- Applies font settings (Baseline 6) to party frame name text elements.
-- Target: CompactPartyFrameMember[1-5].name (FontString with parentKey="name")
--------------------------------------------------------------------------------

do
    local function isPartyFrame(frame)
        if not frame then return false end
        local ok, name = pcall(function() return frame:GetName() end)
        if not ok or not name then return false end
        return name:match("^CompactPartyFrameMember%d+$") ~= nil
    end

    local function hasCustomTextSettings(cfg)
        if not cfg then return false end
        if cfg.fontFace and cfg.fontFace ~= "FRIZQT__" then return true end
        if cfg.size and cfg.size ~= 12 then return true end
        if cfg.style and cfg.style ~= "OUTLINE" then return true end
        if cfg.color then
            local c = cfg.color
            if c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or c[4] ~= 1 then return true end
        end
        -- Anchor customization (non-default position)
        if cfg.anchor and cfg.anchor ~= "TOPLEFT" then return true end
        if cfg.offset then
            if (cfg.offset.x and cfg.offset.x ~= 0) or (cfg.offset.y and cfg.offset.y ~= 0) then return true end
        end
        return false
    end

    -- Helper: Determine SetJustifyH based on anchor's horizontal component (party version)
    local function getJustifyHFromAnchorParty(anchor)
        if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
            return "LEFT"
        elseif anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then
            return "CENTER"
        elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
            return "RIGHT"
        end
        return "LEFT" -- fallback
    end

    local function applyTextToPartyFrame(frame, cfg)
        if not frame or not cfg then return end

        local nameFS = frame.name
        if not nameFS then return end

        local fontFace = cfg.fontFace or "FRIZQT__"
        local resolvedFace
        if addon and addon.ResolveFontFace then
            resolvedFace = addon.ResolveFontFace(fontFace)
        else
            local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
            resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
        end

        local fontSize = tonumber(cfg.size) or 12
        local fontStyle = cfg.style or "OUTLINE"
        local color = cfg.color or { 1, 1, 1, 1 }
        local anchor = cfg.anchor or "TOPLEFT"
        local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

        local success = pcall(nameFS.SetFont, nameFS, resolvedFace, fontSize, fontStyle)
        if not success then
            local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
            if fallback then
                pcall(nameFS.SetFont, nameFS, fallback, fontSize, fontStyle)
            end
        end

        if nameFS.SetTextColor then
            pcall(nameFS.SetTextColor, nameFS, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        end

        -- Apply text alignment based on anchor's horizontal component
        if nameFS.SetJustifyH then
            pcall(nameFS.SetJustifyH, nameFS, getJustifyHFromAnchorParty(anchor))
        end

        -- Capture baseline position on first application so we can restore later
        if not nameFS._ScootOriginalPoint then
            local point, relativeTo, relativePoint, x, y = nameFS:GetPoint(1)
            if point then
                nameFS._ScootOriginalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
            end
        end

        -- Apply anchor-based positioning with offsets relative to selected anchor
        local isDefaultAnchor = (anchor == "TOPLEFT")
        local isZeroOffset = (offsetX == 0 and offsetY == 0)

        if isDefaultAnchor and isZeroOffset and nameFS._ScootOriginalPoint then
            -- Restore baseline (stock position) when user has reset to default
            local orig = nameFS._ScootOriginalPoint
            nameFS:ClearAllPoints()
            nameFS:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
            -- Also restore default text alignment
            if nameFS.SetJustifyH then
                pcall(nameFS.SetJustifyH, nameFS, "LEFT")
            end
        else
            -- Position the name FontString using the user-selected anchor, relative to the frame
            nameFS:ClearAllPoints()
            nameFS:SetPoint(anchor, frame, anchor, offsetX, offsetY)
        end

        -- Preserve Blizzard's truncation/clipping behavior: explicitly constrain the name FontString width.
        -- Blizzard normally constrains this via a dual-anchor layout (TOPLEFT + TOPRIGHT). Our single-point
        -- anchor (for 9-way alignment) removes that implicit width, so we restore it with SetWidth.
        if nameFS.SetMaxLines then
            pcall(nameFS.SetMaxLines, nameFS, 1)
        end
        if frame.GetWidth and nameFS.SetWidth then
            local frameWidth = frame:GetWidth()
            local roleIconWidth = 0
            if frame.roleIcon and frame.roleIcon.GetWidth then
                roleIconWidth = frame.roleIcon:GetWidth() or 0
            end
            -- 3px right padding + (role icon area) + 3px left padding ~= 6px padding total, matching CUF defaults.
            local availableWidth = (frameWidth or 0) - (roleIconWidth or 0) - 6
            if availableWidth and availableWidth > 1 then
                pcall(nameFS.SetWidth, nameFS, availableWidth)
            else
                pcall(nameFS.SetWidth, nameFS, 1)
            end
        end
    end

    local partyFrames = {}
    local function collectPartyFrames()
        if wipe then
            wipe(partyFrames)
        else
            partyFrames = {}
        end
        for i = 1, 5 do
            local frame = _G["CompactPartyFrameMember" .. i]
            if frame and frame.name and not frame.name._ScootPartyTextCounted then
                frame.name._ScootPartyTextCounted = true
                table.insert(partyFrames, frame)
            end
        end
    end

    function addon.ApplyPartyFrameTextStyle()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local groupFrames = rawget(db, "groupFrames")
        local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
        local cfg = partyCfg and rawget(partyCfg, "textPlayerName") or nil
        if not cfg then
            return
        end

        if not hasCustomTextSettings(cfg) then
            return
        end

        -- Deprecated: Party Player Name styling is now driven by overlay FontStrings
        -- (see ApplyPartyFrameNameOverlays). Avoid touching Blizzard's `frame.name`
        -- so overlay clipping preserves stock truncation behavior.
        if addon.ApplyPartyFrameNameOverlays then
            addon.ApplyPartyFrameNameOverlays()
        end
    end

    local function installPartyFrameTextHooks()
        if addon._PartyFrameTextHooksInstalled then return end
        addon._PartyFrameTextHooksInstalled = true

        -- Deprecated: name styling hooks must not touch Blizzard's `frame.name`.
        -- Overlay system installs its own hooks (installPartyNameOverlayHooks()).
    end

    installPartyFrameTextHooks()
end

--------------------------------------------------------------------------------
-- Party Frame Text Overlay (Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on party frames that visually replace
-- Blizzard's name text. These overlays can be styled during initial setup and
-- their text content can be updated during combat without taint because we only
-- manipulate our own FontStrings.
--
-- Pattern: Mirror text via SetText hook, style on setup, hide Blizzard's element.
--------------------------------------------------------------------------------

do
    local function isPartyFrame(frame)
        if not frame then return false end
        local ok, name = pcall(function() return frame:GetName() end)
        if not ok or not name then return false end
        return name:match("^CompactPartyFrameMember%d+$") ~= nil
    end

    local function hasCustomTextSettings(cfg)
        if not cfg then return false end
        if cfg.fontFace and cfg.fontFace ~= "FRIZQT__" then return true end
        if cfg.size and cfg.size ~= 12 then return true end
        if cfg.style and cfg.style ~= "OUTLINE" then return true end
        if cfg.color then
            local c = cfg.color
            if c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or c[4] ~= 1 then return true end
        end
        if cfg.anchor and cfg.anchor ~= "TOPLEFT" then return true end
        if cfg.offset then
            if (cfg.offset.x and cfg.offset.x ~= 0) or (cfg.offset.y and cfg.offset.y ~= 0) then return true end
        end
        return false
    end

    local function getJustifyHFromAnchor(anchor)
        if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
            return "LEFT"
        elseif anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then
            return "CENTER"
        elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
            return "RIGHT"
        end
        return "LEFT"
    end

    -- Apply styling to the overlay FontString
    local function stylePartyNameOverlay(frame, cfg)
        if not frame or not frame.ScooterPartyNameText or not cfg then return end

        local overlay = frame.ScooterPartyNameText
        local container = frame.ScooterPartyNameContainer or frame

        local fontFace = cfg.fontFace or "FRIZQT__"
        local resolvedFace
        if addon and addon.ResolveFontFace then
            resolvedFace = addon.ResolveFontFace(fontFace)
        else
            local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
            resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
        end

        local fontSize = tonumber(cfg.size) or 12
        local fontStyle = cfg.style or "OUTLINE"
        local color = cfg.color or { 1, 1, 1, 1 }
        local anchor = cfg.anchor or "TOPLEFT"
        local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

        -- Apply font
        local success = pcall(overlay.SetFont, overlay, resolvedFace, fontSize, fontStyle)
        if not success then
            local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
            if fallback then
                pcall(overlay.SetFont, overlay, fallback, fontSize, fontStyle)
            end
        end

        -- Apply color
        pcall(overlay.SetTextColor, overlay, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)

        -- Apply text alignment
        pcall(overlay.SetJustifyH, overlay, getJustifyHFromAnchor(anchor))
        if overlay.SetJustifyV then
            pcall(overlay.SetJustifyV, overlay, "MIDDLE")
        end
        if overlay.SetWordWrap then
            pcall(overlay.SetWordWrap, overlay, false)
        end
        if overlay.SetNonSpaceWrap then
            pcall(overlay.SetNonSpaceWrap, overlay, false)
        end
        if overlay.SetMaxLines then
            pcall(overlay.SetMaxLines, overlay, 1)
        end

        -- Keep the clipping container tall enough for the configured font size.
        -- If the container is created too early (before Blizzard sizes `frame.name`), it can end up 1px tall,
        -- which clips the overlay into a thin horizontal sliver.
        if container and container.SetHeight then
            local minH = math.max(12, (tonumber(fontSize) or 12) + 6)
            if overlay.GetStringHeight then
                local okSH, sh = pcall(overlay.GetStringHeight, overlay)
                if okSH and sh and sh > 0 and (sh + 2) > minH then
                    minH = sh + 2
                end
            end
            pcall(container.SetHeight, container, minH)
        end

        -- Position within an addon-owned clipping container that matches Blizzard's original name anchors.
        overlay:ClearAllPoints()
        overlay:SetPoint(anchor, container, anchor, offsetX, offsetY)
    end

    -- Hide Blizzard's name FontString and install alpha-enforcement hook
    local function hideBlizzardPartyNameText(frame)
        if not frame or not frame.name then return end
        local blizzName = frame.name

        blizzName._ScootHidden = true
        if blizzName.SetAlpha then
            pcall(blizzName.SetAlpha, blizzName, 0)
        end
        if blizzName.Hide then
            pcall(blizzName.Hide, blizzName)
        end

        -- Install alpha-enforcement hook (only once)
        if not blizzName._ScootAlphaHooked and _G.hooksecurefunc then
            blizzName._ScootAlphaHooked = true
            _G.hooksecurefunc(blizzName, "SetAlpha", function(self, alpha)
                if alpha > 0 and self._ScootHidden then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if self._ScootHidden then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end
            end)
        end

        if not blizzName._ScootShowHooked and _G.hooksecurefunc then
            blizzName._ScootShowHooked = true
            _G.hooksecurefunc(blizzName, "Show", function(self)
                if not self._ScootHidden then return end
                -- Kill visibility immediately (avoid flicker), then defer Hide to break chains.
                if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if self and self._ScootHidden then
                            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                            if self.Hide then pcall(self.Hide, self) end
                        end
                    end)
                else
                    if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                    if self.Hide then pcall(self.Hide, self) end
                end
            end)
        end
    end

    -- Show Blizzard's name FontString (for restore/cleanup)
    local function showBlizzardPartyNameText(frame)
        if not frame or not frame.name then return end
        frame.name._ScootHidden = nil
        if frame.name.SetAlpha then
            pcall(frame.name.SetAlpha, frame.name, 1)
        end
        if frame.name.Show then
            pcall(frame.name.Show, frame.name)
        end
    end

    -- Create or update the party name text overlay for a specific frame
    local function ensurePartyNameOverlay(frame, cfg)
        if not frame then return end

        local hasCustom = hasCustomTextSettings(cfg)
        frame._ScootPartyNameOverlayActive = hasCustom

        if not hasCustom then
            -- Disable overlay, show Blizzard's text
            if frame.ScooterPartyNameText then
                frame.ScooterPartyNameText:Hide()
            end
            showBlizzardPartyNameText(frame)
            return
        end

        -- Ensure an addon-owned clipping container that matches Blizzard's original name anchors.
        if not frame.ScooterPartyNameContainer then
            local container = CreateFrame("Frame", nil, frame)
            container:SetClipsChildren(true)

            local p1, r1, rp1, x1, y1 = nil, nil, nil, 0, 0
            local p2, r2, rp2, x2, y2 = nil, nil, nil, 0, 0
            if frame.name and frame.name.GetPoint then
                local ok1, ap1, ar1, arp1, ax1, ay1 = pcall(frame.name.GetPoint, frame.name, 1)
                if ok1 then
                    p1, r1, rp1, x1, y1 = ap1, ar1, arp1, ax1, ay1
                end
                local ok2, ap2, ar2, arp2, ax2, ay2 = pcall(frame.name.GetPoint, frame.name, 2)
                if ok2 then
                    p2, r2, rp2, x2, y2 = ap2, ar2, arp2, ax2, ay2
                end
            end

            container:ClearAllPoints()
            if p1 then
                container:SetPoint(p1, r1 or frame, rp1 or p1, tonumber(x1) or 0, tonumber(y1) or 0)
                if p2 then
                    container:SetPoint(p2, r2 or frame, rp2 or p2, tonumber(x2) or 0, tonumber(y2) or 0)
                else
                    container:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
                end
            else
                container:SetPoint("LEFT", frame, "LEFT", 3, 0)
                container:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
            end

            -- Critical: container must have height or it will clip everything.
            local fontSize = tonumber(cfg and cfg.size) or 12
            local h = math.max(12, fontSize + 6)
            if frame.name and frame.name.GetHeight then
                local okH, hh = pcall(frame.name.GetHeight, frame.name)
                if okH and hh and hh > h then
                    h = hh
                end
            end
            if container.SetHeight then
                pcall(container.SetHeight, container, h)
            end

            frame.ScooterPartyNameContainer = container
        end

        -- Create overlay FontString if it doesn't exist
        if not frame.ScooterPartyNameText then
            local parentForText = frame.ScooterPartyNameContainer or frame
            local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
            overlay:SetDrawLayer("OVERLAY", 7) -- High sublayer to ensure visibility
            frame.ScooterPartyNameText = overlay

            -- Install SetText hook on Blizzard's name FontString to mirror text
            if frame.name and not frame.name._ScootTextMirrorHooked and _G.hooksecurefunc then
                frame.name._ScootTextMirrorHooked = true
                frame.name._ScootTextMirrorOwner = frame
                _G.hooksecurefunc(frame.name, "SetText", function(self, text)
                    local owner = self._ScootTextMirrorOwner
                    if owner and owner.ScooterPartyNameText and owner._ScootPartyNameOverlayActive then
                        owner.ScooterPartyNameText:SetText(text or "")
                    end
                end)
            end
        end

        -- Style the overlay and hide Blizzard's text
        stylePartyNameOverlay(frame, cfg)
        hideBlizzardPartyNameText(frame)

        -- Copy current text from Blizzard's FontString to our overlay
        if frame.name and frame.name.GetText then
            local currentText = frame.name:GetText()
            frame.ScooterPartyNameText:SetText(currentText or "")
        end

        frame.ScooterPartyNameText:Show()
    end

    -- Disable overlay and restore Blizzard's appearance for a frame
    local function disablePartyNameOverlay(frame)
        if not frame then return end
        frame._ScootPartyNameOverlayActive = false
        if frame.ScooterPartyNameText then
            frame.ScooterPartyNameText:Hide()
        end
        showBlizzardPartyNameText(frame)
    end

    -- Apply overlays to all party frames
    function addon.ApplyPartyFrameNameOverlays()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local groupFrames = rawget(db, "groupFrames")
        local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
        local cfg = partyCfg and rawget(partyCfg, "textPlayerName") or nil

        local hasCustom = hasCustomTextSettings(cfg)

        for i = 1, 5 do
            local frame = _G["CompactPartyFrameMember" .. i]
            if frame then
                if hasCustom then
                    -- Only create overlays out of combat (initial setup)
                    if not (InCombatLockdown and InCombatLockdown()) then
                        ensurePartyNameOverlay(frame, cfg)
                    elseif frame.ScooterPartyNameText then
                        -- Already have overlay, just update styling (safe during combat for our FontString)
                        stylePartyNameOverlay(frame, cfg)
                    end
                else
                    disablePartyNameOverlay(frame)
                end
            end
        end
    end

    -- Restore all party frames to stock appearance
    function addon.RestorePartyFrameNameOverlays()
        for i = 1, 5 do
            local frame = _G["CompactPartyFrameMember" .. i]
            if frame then
                disablePartyNameOverlay(frame)
            end
        end
    end

    -- Install hooks that trigger overlay setup/updates via CompactUnitFrame events
    local function installPartyNameOverlayHooks()
        if addon._PartyNameOverlayHooksInstalled then return end
        addon._PartyNameOverlayHooksInstalled = true

        -- Hook CompactUnitFrame_UpdateAll to set up overlays
        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
            _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
                if not frame or not frame.name or not isPartyFrame(frame) then return end

                local db = addon and addon.db and addon.db.profile
                local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
                local cfg = partyCfg and partyCfg.textPlayerName or nil

                if hasCustomTextSettings(cfg) then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if not frame then return end
                            if not frame.ScooterPartyNameText then
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePartyFrameReapply()
                                    return
                                end
                            end
                            ensurePartyNameOverlay(frame, cfg)
                        end)
                    end
                end
            end)
        end

        -- Hook CompactUnitFrame_SetUnit for unit assignment changes
        if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
            _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
                if not unit or not frame or not frame.name or not isPartyFrame(frame) then return end

                local db = addon and addon.db and addon.db.profile
                local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
                local cfg = partyCfg and partyCfg.textPlayerName or nil

                if hasCustomTextSettings(cfg) then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if not frame then return end
                            if not frame.ScooterPartyNameText then
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePartyFrameReapply()
                                    return
                                end
                            end
                            ensurePartyNameOverlay(frame, cfg)
                        end)
                    end
                end
            end)
        end

        -- Hook CompactUnitFrame_UpdateName for name text updates
        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateName then
            _G.hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
                if not frame or not frame.name or not isPartyFrame(frame) then return end

                local db = addon and addon.db and addon.db.profile
                local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
                local cfg = partyCfg and partyCfg.textPlayerName or nil

                if hasCustomTextSettings(cfg) then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if not frame then return end
                            if not frame.ScooterPartyNameText then
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePartyFrameReapply()
                                    return
                                end
                            end
                            ensurePartyNameOverlay(frame, cfg)
                        end)
                    end
                end
            end)
        end
    end

    installPartyNameOverlayHooks()
end

--------------------------------------------------------------------------------
-- Party Frame Text Styling (Party Title)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Party Frames > Text > Player Name to the party frame title text.
-- Target: CompactPartyFrame.title (Button from CompactRaidGroupTemplate: "$parentTitle", parentKey="title").
--------------------------------------------------------------------------------
do
    local function hasCustomTextSettings(cfg)
        if not cfg then return false end
        if cfg.fontFace and cfg.fontFace ~= "FRIZQT__" then return true end
        if cfg.size and cfg.size ~= 12 then return true end
        if cfg.style and cfg.style ~= "OUTLINE" then return true end
        if cfg.color then
            local c = cfg.color
            if c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or c[4] ~= 1 then return true end
        end
        if cfg.anchor and cfg.anchor ~= "TOPLEFT" then return true end
        if cfg.offset then
            if (cfg.offset.x and cfg.offset.x ~= 0) or (cfg.offset.y and cfg.offset.y ~= 0) then return true end
        end
        return false
    end

    local function getJustifyHFromAnchor(anchor)
        if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
            return "LEFT"
        elseif anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then
            return "CENTER"
        elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
            return "RIGHT"
        end
        return "LEFT"
    end

    local function isCompactPartyFrame(frame)
        if not frame then return false end
        local ok, name = pcall(function() return frame:GetName() end)
        if not ok or not name then return false end
        return name == "CompactPartyFrame"
    end

    local function applyTextToFontString(fs, ownerFrame, cfg)
        if not fs or not ownerFrame or not cfg then return end

        local fontFace = cfg.fontFace or "FRIZQT__"
        local resolvedFace
        if addon and addon.ResolveFontFace then
            resolvedFace = addon.ResolveFontFace(fontFace)
        else
            local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
            resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
        end

        local fontSize = tonumber(cfg.size) or 12
        local fontStyle = cfg.style or "OUTLINE"
        local color = cfg.color or { 1, 1, 1, 1 }
        local anchor = cfg.anchor or "TOPLEFT"
        local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

        local success = pcall(fs.SetFont, fs, resolvedFace, fontSize, fontStyle)
        if not success then
            local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
            if fallback then
                pcall(fs.SetFont, fs, fallback, fontSize, fontStyle)
            end
        end

        if fs.SetTextColor then
            pcall(fs.SetTextColor, fs, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        end
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, getJustifyHFromAnchor(anchor))
        end

        if not fs._ScootOriginalPoint_PartyTitle then
            local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
            if point then
                fs._ScootOriginalPoint_PartyTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
            end
        end

        local isDefaultAnchor = (anchor == "TOPLEFT")
        local isZeroOffset = (offsetX == 0 and offsetY == 0)

        if isDefaultAnchor and isZeroOffset and fs._ScootOriginalPoint_PartyTitle then
            local orig = fs._ScootOriginalPoint_PartyTitle
            fs:ClearAllPoints()
            fs:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
            if fs.SetJustifyH then
                pcall(fs.SetJustifyH, fs, "LEFT")
            end
        else
            fs:ClearAllPoints()
            fs:SetPoint(anchor, ownerFrame, anchor, offsetX, offsetY)
        end
    end

    local function applyPartyTitle(titleButton, cfg)
        if not titleButton or not cfg then return end
        if not titleButton.GetFontString then return end
        local fs = titleButton:GetFontString()
        if not fs then return end
        if cfg.hide == true then
            -- Hide always wins; styling is irrelevant while hidden.
            -- The hide logic is handled by hideBlizzardPartyTitleText below.
            return
        end
        applyTextToFontString(fs, titleButton, cfg)
    end

    -- Hide Blizzard's party title FontString and install alpha-enforcement hook
    local function hideBlizzardPartyTitleText(titleButton)
        if not titleButton or not titleButton.GetFontString then return end
        local fs = titleButton:GetFontString()
        if not fs then return end

        fs._ScootHidden = true
        if fs.SetAlpha then
            pcall(fs.SetAlpha, fs, 0)
        end
        if fs.Hide then
            pcall(fs.Hide, fs)
        end

        -- Install alpha-enforcement hook (only once)
        if not fs._ScootAlphaHooked and _G.hooksecurefunc then
            fs._ScootAlphaHooked = true
            _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                if alpha > 0 and self._ScootHidden then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            if self and self._ScootHidden then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end
            end)
        end

        if not fs._ScootShowHooked and _G.hooksecurefunc then
            fs._ScootShowHooked = true
            _G.hooksecurefunc(fs, "Show", function(self)
                if not self._ScootHidden then return end
                -- Kill visibility immediately (avoid flicker), then defer Hide to break chains.
                if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if self and self._ScootHidden then
                            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                            if self.Hide then pcall(self.Hide, self) end
                        end
                    end)
                else
                    if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                    if self.Hide then pcall(self.Hide, self) end
                end
            end)
        end
    end

    -- Show Blizzard's party title FontString (for restore/cleanup)
    local function showBlizzardPartyTitleText(titleButton)
        if not titleButton or not titleButton.GetFontString then return end
        local fs = titleButton:GetFontString()
        if not fs then return end
        fs._ScootHidden = nil
        if fs.SetAlpha then
            pcall(fs.SetAlpha, fs, 1)
        end
        if fs.Show then
            pcall(fs.Show, fs)
        end
    end

    function addon.ApplyPartyFrameTitleStyle()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local groupFrames = rawget(db, "groupFrames")
        local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
        local cfg = partyCfg and rawget(partyCfg, "textPartyTitle") or nil
        if not cfg then
            return
        end

        -- If the user has asked to hide it, do that even if other style settings are default.
        if cfg.hide ~= true and not hasCustomTextSettings(cfg) then
            return
        end

        if InCombatLockdown and InCombatLockdown() then
            queuePartyFrameReapply()
            return
        end

        local partyFrame = _G.CompactPartyFrame
        local titleButton = partyFrame and partyFrame.title or _G.CompactPartyFrameTitle
        if titleButton then
            if cfg.hide == true then
                hideBlizzardPartyTitleText(titleButton)
            else
                showBlizzardPartyTitleText(titleButton)
                applyPartyTitle(titleButton, cfg)
            end
        end
    end

    local function installPartyTitleHooks()
        if addon._PartyFrameTitleHooksInstalled then return end
        addon._PartyFrameTitleHooksInstalled = true

        local function tryApply(groupFrame)
            if not groupFrame or not isCompactPartyFrame(groupFrame) then
                return
            end
            local db = addon and addon.db and addon.db.profile
            local cfg = db and db.groupFrames and db.groupFrames.party and db.groupFrames.party.textPartyTitle or nil
            if not cfg then
                return
            end
            if cfg.hide ~= true and not hasCustomTextSettings(cfg) then
                return
            end

            local titleButton = groupFrame.title or _G[groupFrame:GetName() .. "Title"]
            if not titleButton then return end

            local titleRef = titleButton
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if InCombatLockdown and InCombatLockdown() then
                        queuePartyFrameReapply()
                        return
                    end
                    if cfgRef.hide == true then
                        hideBlizzardPartyTitleText(titleRef)
                    else
                        showBlizzardPartyTitleText(titleRef)
                        applyPartyTitle(titleRef, cfgRef)
                    end
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    queuePartyFrameReapply()
                    return
                end
                if cfgRef.hide == true then
                    hideBlizzardPartyTitleText(titleRef)
                else
                    showBlizzardPartyTitleText(titleRef)
                    applyPartyTitle(titleRef, cfgRef)
                end
            end
        end

        if _G.hooksecurefunc then
            if _G.CompactRaidGroup_UpdateLayout then
                _G.hooksecurefunc("CompactRaidGroup_UpdateLayout", tryApply)
            end
            if _G.CompactRaidGroup_UpdateUnits then
                _G.hooksecurefunc("CompactRaidGroup_UpdateUnits", tryApply)
            end
            if _G.CompactRaidGroup_UpdateBorder then
                _G.hooksecurefunc("CompactRaidGroup_UpdateBorder", tryApply)
            end
        end
    end

    installPartyTitleHooks()
end

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

--------------------------------------------------------------------------------
-- Raid Frame Overlay Restore (Profile Switch / Category Reset)
--------------------------------------------------------------------------------
-- Centralized function to restore all raid frames to stock Blizzard appearance.
--------------------------------------------------------------------------------

function addon.RestoreAllRaidFrameOverlays()
    if addon.RestoreRaidFrameNameOverlays then
        addon.RestoreRaidFrameNameOverlays()
    end
end
