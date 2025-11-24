local addonName, addon = ...
local Util = addon.ComponentsUtil
local ClampOpacity = Util.ClampOpacity
local PlayerInCombat = Util.PlayerInCombat

-- Unit Frames: Overall visibility (opacity) per unit
do
    local function getUnitFrameFor(unit)
        local mgr = _G.EditModeManagerFrame
        local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
        local EMSys = _G.Enum and _G.Enum.EditModeSystem
        if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
            -- Fallback for environments where Edit Mode indices aren't available
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
        -- If no index was resolved (older builds lacking EM.Pet), try known globals
        if unit == "Pet" then return _G.PetFrame end
        return nil
    end

    local function applyVisibilityForUnit(unit)
        local frame = getUnitFrameFor(unit)
        if not frame or not frame.SetAlpha then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        db.unitFrames = db.unitFrames or {}
        db.unitFrames[unit] = db.unitFrames[unit] or {}
        local cfg = db.unitFrames[unit]

        -- Base opacity (combat) uses the same 50–100 semantics as Cooldown Manager groups
        local baseRaw = cfg.opacity
        if baseRaw == nil then baseRaw = 100 end
        local baseOpacity = ClampOpacity(baseRaw, 50)

        -- Out-of-combat opacity; falls back to base when unset
        local oocRaw = cfg.opacityOutOfCombat
        local oocOpacity = ClampOpacity(oocRaw == nil and baseOpacity or oocRaw, 1)

        -- With-target opacity; falls back to base when unset
        local tgtRaw = cfg.opacityWithTarget
        local tgtOpacity = ClampOpacity(tgtRaw == nil and baseOpacity or tgtRaw, 1)

        local hasTarget = (UnitExists and UnitExists("target")) and true or false
        local applied = hasTarget and tgtOpacity or (PlayerInCombat() and baseOpacity or oocOpacity)

        pcall(frame.SetAlpha, frame, applied / 100)
    end

    function addon.ApplyUnitFrameVisibilityFor(unit)
        applyVisibilityForUnit(unit)
    end

    function addon.ApplyAllUnitFrameVisibility()
        applyVisibilityForUnit("Player")
        applyVisibilityForUnit("Target")
        applyVisibilityForUnit("Focus")
        applyVisibilityForUnit("Pet")
    end
end

-- (Reverted) No additional hooks for reapplying experimental sizing; rely on normal refresh

function addon:SyncAllEditModeSettings()
    local anyChanged = false
    for id, component in pairs(self.Components) do
        if component.SyncEditModeSettings then
            if component:SyncEditModeSettings() then
                anyChanged = true
            end
        end
        if addon.EditMode.SyncComponentPositionFromEditMode then
            if addon.EditMode.SyncComponentPositionFromEditMode(component) then
                anyChanged = true
            end
        end
    end

    return anyChanged
end
