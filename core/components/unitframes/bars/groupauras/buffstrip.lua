--------------------------------------------------------------------------------
-- groupauras/buffstrip.lua
-- Replacement-overlay rendering for Blizzard buff icons on party/raid frames.
--
-- Background (see ADDONCONTEXT/docs/groupframes/gfauratracking.md):
-- 12.0.5 moved CompactUnitFrame buff rendering into C++ via Blizzard_PrivateAurasUI.
-- The pool frames are forbidden (IsForbidden() == true); the container frame is
-- an EditModeSystemTemplate (Rules 10-11 in debugging/taint.md). Addons can
-- neither modify the buff icons nor the container frame without tainting.
--
-- This module provides the *replacement* workaround: opaque overlay frames drawn
-- on top of whichever Blizzard buff slots are currently rendering, giving them a
-- uniform neutral look so the user's Scoot custom icons dominate visually.
--
-- Taint-safe rules followed:
--   * Overlays are always parented to UIParent (never to CompactUnitFrame).
--   * We only ANCHOR via SetPoint(relativeTo=compactUnitFrame); anchoring is safe,
--     property writes are not.
--   * Reads from the CompactUnitFrame table are pcall-guarded; secret values are
--     swallowed and we fall back to sane defaults.
--   * No write to any Blizzard frame's property table.
--------------------------------------------------------------------------------

local addonName, addon = ...

local HA = addon.AuraTracking
if not HA then return end

--------------------------------------------------------------------------------
-- Constants (mirrored from 12.0.5 Blizzard_PrivateAurasUI.lua / CompactUnitFrame.lua)
--------------------------------------------------------------------------------

local NATIVE_UNIT_FRAME_AURA_SIZE = 11
local CUF_AURA_BOTTOM_OFFSET = 2
local MAX_BUFFS = 6
local OVERLAY_POOL_PREALLOC = 60  -- ~10 frames * 6 slots

-- Grid parameters per auraOrganizationType. Values mirror the Buffs entry of
-- PrivateAuraUnitFrameLayoutTemplates in Blizzard_PrivateAurasUI.lua (12.0.5).
-- columns: horizontal slots per row; anchor: corner of CompactUnitFrame the
-- row originates from; flowX/flowY: per-slot offset direction (in pixels of
-- auraSize) from that anchor.
local AURA_ORG_LAYOUT = {
    -- [Enum.RaidAuraOrganizationType.Legacy] = 0
    [0] = {
        columns = 3,
        anchor = "BOTTOMRIGHT",
        flowX = -1,  -- slots go left from BOTTOMRIGHT
        flowY =  1,  -- rows go up from bottom
        offsetX = -3,
        offsetY = CUF_AURA_BOTTOM_OFFSET,
    },
    -- [Enum.RaidAuraOrganizationType.BuffsTopDebuffsBottom] = 1
    [1] = {
        columns = 6,
        anchor = "TOPRIGHT",
        flowX = -1,
        flowY = -1,  -- downward from top
        offsetX = -3,
        offsetY = -3,
    },
    -- [Enum.RaidAuraOrganizationType.BuffsRightDebuffsLeft] = 2
    [2] = {
        columns = 3,
        anchor = "BOTTOMRIGHT",
        flowX = -1,
        flowY =  1,
        offsetX = -3,
        offsetY = CUF_AURA_BOTTOM_OFFSET,
    },
}

--------------------------------------------------------------------------------
-- Overlay Pool (UIParent-parented, never touches Blizzard frames beyond anchoring)
--------------------------------------------------------------------------------

local overlayPool = {}
local activeOverlays = setmetatable({}, { __mode = "k" })  -- [compactUnitFrame] = {overlay1, ...}

local function CreateOverlayFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(19)  -- below Scoot's custom icons (level 20) but above Blizzard's buffs
    f:SetSize(11, 11)

    local bg = f:CreateTexture(nil, "ARTWORK")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    f.Bg = bg

    local num = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    num:SetPoint("CENTER", f, "CENTER", 0, 0)
    num:SetTextColor(0.9, 0.9, 0.9, 1)
    num:Hide()
    f.Num = num

    f:Hide()
    return f
end

local function PreallocateOverlayPool()
    for i = 1, OVERLAY_POOL_PREALLOC do
        table.insert(overlayPool, CreateOverlayFrame())
    end
end

local function AcquireOverlay()
    local f = table.remove(overlayPool)
    if not f then
        if InCombatLockdown() then return nil end
        f = CreateOverlayFrame()
    end
    return f
end

local function ReleaseOverlay(f)
    if not f then return end
    f:Hide()
    f:ClearAllPoints()
    if f.Num then f.Num:Hide() end
    table.insert(overlayPool, f)
end

--------------------------------------------------------------------------------
-- Config reads
--------------------------------------------------------------------------------

local function GetReplacementStyle()
    local db = addon.db and addon.db.profile
    local at = db and db.groupFrames and db.groupFrames.auraTracking
    return (at and at.replacementStyle) or "none"
end

local function ReadGroupType(frame)
    if not frame then return nil end
    local ok, v = pcall(function() return frame.groupType end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function ReadPowerBarUsedHeight(frame)
    if not frame then return 0 end
    local ok, v = pcall(function() return frame.powerBarUsedHeight end)
    if ok and type(v) == "number" then return v end
    return 0
end

local function ReadAuraOrganizationType(frame)
    local groupType = ReadGroupType(frame)
    if not groupType or not EditModeManagerFrame then return 0 end
    local ok, v = pcall(EditModeManagerFrame.GetRaidFrameAuraOrganizationType, EditModeManagerFrame, groupType)
    if ok and type(v) == "number" then return v end
    return 0
end

local function ReadAuraSize(frame)
    local groupType = ReadGroupType(frame)
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    if not groupType or not EditModeManagerFrame or not EM or not EM.IconSize then
        return NATIVE_UNIT_FRAME_AURA_SIZE
    end
    local ok, iconScale = pcall(EditModeManagerFrame.GetRaidFrameIconScale, EditModeManagerFrame, groupType, 1, EM.IconSize)
    if ok and type(iconScale) == "number" and iconScale > 0 then
        return NATIVE_UNIT_FRAME_AURA_SIZE * iconScale
    end
    return NATIVE_UNIT_FRAME_AURA_SIZE
end

--------------------------------------------------------------------------------
-- Buff count scanning — mirrors Blizzard's exact CompactUnitFrame filter.
--
-- `AuraUtil.ForEachAura(unit, "HELPFUL")` over-counts: it returns every helpful
-- aura on the unit (raid buffs, personal buffs, passive auras, weapon enchants,
-- etc.), but CompactUnitFrame only renders auras that pass through
-- `AuraUtil.ProcessAura` → `AuraUtil.AuraUpdateChangedType.Buff`. That function
-- gates on `aura.isHelpful` AND `AuraUtil.ShouldDisplayBuff(sourceUnit, spellId,
-- canApplyAura)`, which handles the raid-vs-personal distinction.
--
-- Blizzard_PrivateAurasUI runs this exact filter at
-- PrivateAuraAnchorContainerMixin:ProcessAura (Blizzard_PrivateAurasUI.lua:418).
-- Blizzard_FrameXMLUtil does NOT use a secure environment, so AuraUtil.* is
-- fully reachable from addon context.
--------------------------------------------------------------------------------

local function CountHelpfulAuras(unit)
    if not unit or not UnitExists(unit) then return 0 end
    if not AuraUtil or not AuraUtil.ForEachAura or not AuraUtil.ProcessAura then return 0 end
    if not AuraUtil.AuraUpdateChangedType then return 0 end

    local BuffType = AuraUtil.AuraUpdateChangedType.Buff
    local count = 0

    local function handle(aura)
        if not aura then return false end
        -- pcall around ProcessAura in case any reads secret out from under us.
        -- Writes aura.isBuff / aura.isPriorityAura side-effectually; that's on a
        -- table we own so taint is not a concern.
        local ok, result = pcall(AuraUtil.ProcessAura, aura, false, false, false, false)
        if ok and result == BuffType then
            count = count + 1
        end
        return count >= MAX_BUFFS  -- stop once we've hit the cap
    end

    pcall(AuraUtil.ForEachAura, unit, "HELPFUL", nil, handle, true)
    return math.min(count, MAX_BUFFS)
end

--------------------------------------------------------------------------------
-- Per-slot positioning
--------------------------------------------------------------------------------

local function PositionOverlay(overlay, frame, slotIndex, layout, auraSize, powerBarUsedHeight)
    local col = (slotIndex - 1) % layout.columns
    local row = math.floor((slotIndex - 1) / layout.columns)
    local extraY = (layout.anchor == "BOTTOMRIGHT" or layout.anchor == "BOTTOMLEFT") and powerBarUsedHeight or 0
    local x = layout.offsetX + (layout.flowX * col * auraSize)
    local y = layout.offsetY + extraY + (layout.flowY * row * auraSize)
    overlay:ClearAllPoints()
    overlay:SetPoint(layout.anchor, frame, layout.anchor, x, y)
    overlay:SetSize(auraSize, auraSize)
end

local function StyleOverlay(overlay, style, slotIndex)
    if style == "numbered" then
        overlay.Bg:SetColorTexture(0, 0, 0, 0.88)
        overlay.Num:SetText(tostring(slotIndex))
        overlay.Num:Show()
    else  -- "solidBlack" or any unknown → opaque black
        overlay.Bg:SetColorTexture(0, 0, 0, 1)
        overlay.Num:Hide()
    end
end

--------------------------------------------------------------------------------
-- Per-frame refresh
--------------------------------------------------------------------------------

function HA.RefreshOverlaysForFrame(frame, unit)
    if not frame then return end
    local style = GetReplacementStyle()
    local actives = activeOverlays[frame]

    -- Style "none" → release all overlays on this frame
    if style == "none" then
        if actives then
            for i = #actives, 1, -1 do
                ReleaseOverlay(actives[i])
                actives[i] = nil
            end
            activeOverlays[frame] = nil
        end
        return
    end

    -- Frame must be visible
    local okVis, visible = pcall(frame.IsVisible, frame)
    if not okVis or not visible then
        if actives then
            for i = #actives, 1, -1 do
                ReleaseOverlay(actives[i])
                actives[i] = nil
            end
            activeOverlays[frame] = nil
        end
        return
    end

    local desired = CountHelpfulAuras(unit)
    if desired <= 0 then
        if actives then
            for i = #actives, 1, -1 do
                ReleaseOverlay(actives[i])
                actives[i] = nil
            end
            activeOverlays[frame] = nil
        end
        return
    end

    -- PvP arena frames set max-buffs to 0; respect that by reading maxBuffs
    local okMax, maxBuffs = pcall(function() return frame.maxBuffs end)
    if okMax and type(maxBuffs) == "number" then
        if maxBuffs <= 0 then
            if actives then
                for i = #actives, 1, -1 do
                    ReleaseOverlay(actives[i])
                    actives[i] = nil
                end
                activeOverlays[frame] = nil
            end
            return
        end
        desired = math.min(desired, maxBuffs)
    end

    local auraOrgType = ReadAuraOrganizationType(frame)
    local layout = AURA_ORG_LAYOUT[auraOrgType] or AURA_ORG_LAYOUT[0]
    local auraSize = ReadAuraSize(frame)
    local powerBarUsedHeight = ReadPowerBarUsedHeight(frame)

    actives = actives or {}
    activeOverlays[frame] = actives

    -- Grow pool on this frame if needed
    while #actives < desired do
        local ov = AcquireOverlay()
        if not ov then break end
        table.insert(actives, ov)
    end

    -- Shrink if we have too many active
    while #actives > desired do
        local ov = table.remove(actives)
        ReleaseOverlay(ov)
    end

    -- Style + position each active overlay
    for i = 1, #actives do
        local ov = actives[i]
        StyleOverlay(ov, style, i)
        PositionOverlay(ov, frame, i, layout, auraSize, powerBarUsedHeight)
        ov:Show()
    end
end

--------------------------------------------------------------------------------
-- Public API (called from core.lua config-change + per-unit refresh paths)
--------------------------------------------------------------------------------

-- Wipe overlays for a frame (e.g., when its unit goes away). Taint-safe.
function HA.ReleaseOverlaysForFrame(frame)
    if not frame then return end
    local actives = activeOverlays[frame]
    if not actives then return end
    for i = #actives, 1, -1 do
        ReleaseOverlay(actives[i])
        actives[i] = nil
    end
    activeOverlays[frame] = nil
end

-- Style-changed refresh: iterate known tracked frames, re-render each. Called by
-- AuraTrackingRenderer set() hooks when the user changes replacementStyle or
-- positionGroupSpacing. Safe OOC (pool expansion) and in combat (uses pre-alloc
-- only; skips grow when lockdown).
function HA.RefreshBuffStripScaling()
    local state = HA._AuraTrackingState
    if not state then return end
    for frame, frameState in pairs(state) do
        if frameState and frameState.unit then
            HA.RefreshOverlaysForFrame(frame, frameState.unit)
        end
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self)
    PreallocateOverlayPool()
    self:UnregisterAllEvents()
end)
