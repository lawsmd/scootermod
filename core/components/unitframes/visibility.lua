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

-- Target/Focus Misc.: Threat Meter visibility
-- Frame paths:
--   Target: TargetFrame.TargetFrameContent.TargetFrameContentContextual.NumericalThreat
--   Focus:  FocusFrame.TargetFrameContent.TargetFrameContentContextual.NumericalThreat
do
    local _threatMeterHooked = { Target = false, Focus = false }
    local _originalThreatMeterAlpha = { Target = nil, Focus = nil }

    local function getThreatMeterFrame(unit)
        local parentFrame = (unit == "Target") and _G.TargetFrame or (unit == "Focus") and _G.FocusFrame or nil
        if not parentFrame then return nil end
        local content = parentFrame.TargetFrameContent
        if not content then return nil end
        local contextual = content.TargetFrameContentContextual
        if not contextual then return nil end
        return contextual.NumericalThreat
    end

    local function applyThreatMeterVisibility(unit)
        local threatFrame = getThreatMeterFrame(unit)
        if not threatFrame then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        db.unitFrames = db.unitFrames or {}
        db.unitFrames[unit] = db.unitFrames[unit] or {}
        db.unitFrames[unit].misc = db.unitFrames[unit].misc or {}
        local cfg = db.unitFrames[unit].misc

        local hideThreatMeter = (cfg.hideThreatMeter == true)

        -- Capture original alpha on first run
        if _originalThreatMeterAlpha[unit] == nil then
            _originalThreatMeterAlpha[unit] = threatFrame:GetAlpha() or 1
        end

        if hideThreatMeter then
            -- Hide via SetAlpha(0) - safe for protected frames
            if threatFrame.SetAlpha then
                pcall(threatFrame.SetAlpha, threatFrame, 0)
            end
        else
            -- Restore original alpha
            if threatFrame.SetAlpha then
                pcall(threatFrame.SetAlpha, threatFrame, _originalThreatMeterAlpha[unit])
            end
        end
    end

    -- Install hooks to maintain visibility state when Blizzard updates the threat meter
    local function installThreatMeterHooks(unit)
        if _threatMeterHooked[unit] then return end
        _threatMeterHooked[unit] = true

        local threatFrame = getThreatMeterFrame(unit)
        if not threatFrame then return end

        -- Hook Show() to re-apply visibility when Blizzard shows the frame
        if threatFrame.Show then
            hooksecurefunc(threatFrame, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                db.unitFrames = db.unitFrames or {}
                db.unitFrames[unit] = db.unitFrames[unit] or {}
                db.unitFrames[unit].misc = db.unitFrames[unit].misc or {}
                local cfg = db.unitFrames[unit].misc
                if cfg.hideThreatMeter == true then
                    if self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end
            end)
        end

        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to change it
        if threatFrame.SetAlpha then
            hooksecurefunc(threatFrame, "SetAlpha", function(self, alpha)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                db.unitFrames = db.unitFrames or {}
                db.unitFrames[unit] = db.unitFrames[unit] or {}
                db.unitFrames[unit].misc = db.unitFrames[unit].misc or {}
                local cfg = db.unitFrames[unit].misc
                if cfg.hideThreatMeter == true and alpha and alpha > 0 then
                    -- Defer to avoid recursion
                    if not self._ScootThreatAlphaDeferred then
                        self._ScootThreatAlphaDeferred = true
                        C_Timer.After(0, function()
                            self._ScootThreatAlphaDeferred = nil
                            if cfg.hideThreatMeter == true and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
        end
    end

    function addon.ApplyTargetThreatMeterVisibility()
        installThreatMeterHooks("Target")
        applyThreatMeterVisibility("Target")
    end

    function addon.ApplyFocusThreatMeterVisibility()
        installThreatMeterHooks("Focus")
        applyThreatMeterVisibility("Focus")
    end

    function addon.ApplyAllThreatMeterVisibility()
        addon.ApplyTargetThreatMeterVisibility()
        addon.ApplyFocusThreatMeterVisibility()
    end
end

-- Target Misc.: Boss Icon visibility
-- Frame path:
--   Target: TargetFrame.TargetFrameContent.TargetFrameContentContextual.BossIcon
do
    local _bossIconHooked = false
    local _originalBossIconAlpha = nil

    local function getBossIconFrame()
        local tf = _G.TargetFrame
        if not tf then return nil end
        local content = tf.TargetFrameContent
        if not content then return nil end
        local contextual = content.TargetFrameContentContextual
        if not contextual then return nil end
        return contextual.BossIcon
    end

    local function applyBossIconVisibility()
        local bossIconFrame = getBossIconFrame()
        if not bossIconFrame then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        db.unitFrames = db.unitFrames or {}
        db.unitFrames.Target = db.unitFrames.Target or {}
        db.unitFrames.Target.misc = db.unitFrames.Target.misc or {}
        local cfg = db.unitFrames.Target.misc

        local hideBossIcon = (cfg.hideBossIcon == true)

        -- Capture original alpha on first run
        if _originalBossIconAlpha == nil then
            _originalBossIconAlpha = bossIconFrame:GetAlpha() or 1
        end

        if hideBossIcon then
            -- Hide via SetAlpha(0) - safe for protected frames
            if bossIconFrame.SetAlpha then
                pcall(bossIconFrame.SetAlpha, bossIconFrame, 0)
            end
        else
            -- Restore original alpha
            if bossIconFrame.SetAlpha then
                pcall(bossIconFrame.SetAlpha, bossIconFrame, _originalBossIconAlpha)
            end
        end
    end

    local function installBossIconHooks()
        if _bossIconHooked then return end
        _bossIconHooked = true

        local bossIconFrame = getBossIconFrame()
        if not bossIconFrame then return end

        if bossIconFrame.Show then
            hooksecurefunc(bossIconFrame, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                db.unitFrames = db.unitFrames or {}
                db.unitFrames.Target = db.unitFrames.Target or {}
                db.unitFrames.Target.misc = db.unitFrames.Target.misc or {}
                local cfg = db.unitFrames.Target.misc
                if cfg.hideBossIcon == true then
                    if self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end
            end)
        end

        if bossIconFrame.SetAlpha then
            hooksecurefunc(bossIconFrame, "SetAlpha", function(self, alpha)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                db.unitFrames = db.unitFrames or {}
                db.unitFrames.Target = db.unitFrames.Target or {}
                db.unitFrames.Target.misc = db.unitFrames.Target.misc or {}
                local cfg = db.unitFrames.Target.misc
                if cfg.hideBossIcon == true and alpha and alpha > 0 then
                    if not self._ScootBossIconAlphaDeferred then
                        self._ScootBossIconAlphaDeferred = true
                        C_Timer.After(0, function()
                            self._ScootBossIconAlphaDeferred = nil
                            if cfg.hideBossIcon == true and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
        end
    end

    function addon.ApplyTargetBossIconVisibility()
        installBossIconHooks()
        applyBossIconVisibility()
    end
end

-- Player Misc.: Role Icon visibility
-- Frame path: PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.RoleIcon
do
    local _roleIconHooked = false
    local _originalRoleIconAlpha = nil

    local function getRoleIconFrame()
        local pf = _G.PlayerFrame
        if not pf then return nil end
        local content = pf.PlayerFrameContent
        if not content then return nil end
        local contextual = content.PlayerFrameContentContextual
        if not contextual then return nil end
        return contextual.RoleIcon
    end

    local function applyRoleIconVisibility()
        local roleIconFrame = getRoleIconFrame()
        if not roleIconFrame then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        db.unitFrames = db.unitFrames or {}
        db.unitFrames.Player = db.unitFrames.Player or {}
        db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
        local cfg = db.unitFrames.Player.misc

        local hideRoleIcon = (cfg.hideRoleIcon == true)

        -- Capture original alpha on first run
        if _originalRoleIconAlpha == nil then
            _originalRoleIconAlpha = roleIconFrame:GetAlpha() or 1
        end

        if hideRoleIcon then
            -- Hide via SetAlpha(0) - safe for protected frames
            if roleIconFrame.SetAlpha then
                pcall(roleIconFrame.SetAlpha, roleIconFrame, 0)
            end
        else
            -- Restore original alpha
            if roleIconFrame.SetAlpha then
                pcall(roleIconFrame.SetAlpha, roleIconFrame, _originalRoleIconAlpha)
            end
        end
    end

    -- Install hooks to maintain visibility state when Blizzard updates the role icon
    local function installRoleIconHooks()
        if _roleIconHooked then return end
        _roleIconHooked = true

        local roleIconFrame = getRoleIconFrame()
        if not roleIconFrame then return end

        -- Hook Show() to re-apply visibility when Blizzard shows the frame
        if roleIconFrame.Show then
            hooksecurefunc(roleIconFrame, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                db.unitFrames = db.unitFrames or {}
                db.unitFrames.Player = db.unitFrames.Player or {}
                db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
                local cfg = db.unitFrames.Player.misc
                if cfg.hideRoleIcon == true then
                    if self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end
            end)
        end

        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to change it
        if roleIconFrame.SetAlpha then
            hooksecurefunc(roleIconFrame, "SetAlpha", function(self, alpha)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                db.unitFrames = db.unitFrames or {}
                db.unitFrames.Player = db.unitFrames.Player or {}
                db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
                local cfg = db.unitFrames.Player.misc
                if cfg.hideRoleIcon == true and alpha and alpha > 0 then
                    -- Defer to avoid recursion
                    if not self._ScootRoleIconAlphaDeferred then
                        self._ScootRoleIconAlphaDeferred = true
                        C_Timer.After(0, function()
                            self._ScootRoleIconAlphaDeferred = nil
                            if cfg.hideRoleIcon == true and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
        end
    end

    function addon.ApplyPlayerRoleIconVisibility()
        installRoleIconHooks()
        applyRoleIconVisibility()
    end
end

-- Player Misc.: Group Number visibility
-- Frame paths:
--   PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.GroupIndicator (container with texture child)
--   PlayerFrameGroupIndicatorText (global FontString)
do
    local _groupNumberHooked = false
    local _originalGroupIndicatorAlpha = nil
    local _originalGroupIndicatorTextAlpha = nil

    local function getGroupIndicatorFrame()
        local pf = _G.PlayerFrame
        if not pf then return nil end
        local content = pf.PlayerFrameContent
        if not content then return nil end
        local contextual = content.PlayerFrameContentContextual
        if not contextual then return nil end
        return contextual.GroupIndicator
    end

    local function getGroupIndicatorTextFrame()
        return _G.PlayerFrameGroupIndicatorText
    end

    local function applyGroupNumberVisibility()
        local groupIndicatorFrame = getGroupIndicatorFrame()
        local groupIndicatorText = getGroupIndicatorTextFrame()

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        db.unitFrames = db.unitFrames or {}
        db.unitFrames.Player = db.unitFrames.Player or {}
        db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
        local cfg = db.unitFrames.Player.misc

        local hideGroupNumber = (cfg.hideGroupNumber == true)

        -- Apply to GroupIndicator container frame
        if groupIndicatorFrame then
            -- Capture original alpha on first run
            if _originalGroupIndicatorAlpha == nil then
                _originalGroupIndicatorAlpha = groupIndicatorFrame:GetAlpha() or 1
            end

            if hideGroupNumber then
                if groupIndicatorFrame.SetAlpha then
                    pcall(groupIndicatorFrame.SetAlpha, groupIndicatorFrame, 0)
                end
            else
                if groupIndicatorFrame.SetAlpha then
                    pcall(groupIndicatorFrame.SetAlpha, groupIndicatorFrame, _originalGroupIndicatorAlpha)
                end
            end
        end

        -- Apply to GroupIndicator text (global FontString)
        if groupIndicatorText then
            -- Capture original alpha on first run
            if _originalGroupIndicatorTextAlpha == nil then
                _originalGroupIndicatorTextAlpha = groupIndicatorText:GetAlpha() or 1
            end

            if hideGroupNumber then
                if groupIndicatorText.SetAlpha then
                    pcall(groupIndicatorText.SetAlpha, groupIndicatorText, 0)
                end
            else
                if groupIndicatorText.SetAlpha then
                    pcall(groupIndicatorText.SetAlpha, groupIndicatorText, _originalGroupIndicatorTextAlpha)
                end
            end
        end
    end

    -- Install hooks to maintain visibility state when Blizzard updates the group indicator
    local function installGroupNumberHooks()
        if _groupNumberHooked then return end
        _groupNumberHooked = true

        local groupIndicatorFrame = getGroupIndicatorFrame()
        local groupIndicatorText = getGroupIndicatorTextFrame()

        -- Hook GroupIndicator container
        if groupIndicatorFrame then
            if groupIndicatorFrame.Show then
                hooksecurefunc(groupIndicatorFrame, "Show", function(self)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    db.unitFrames = db.unitFrames or {}
                    db.unitFrames.Player = db.unitFrames.Player or {}
                    db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
                    local cfg = db.unitFrames.Player.misc
                    if cfg.hideGroupNumber == true then
                        if self.SetAlpha then
                            pcall(self.SetAlpha, self, 0)
                        end
                    end
                end)
            end

            if groupIndicatorFrame.SetAlpha then
                hooksecurefunc(groupIndicatorFrame, "SetAlpha", function(self, alpha)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    db.unitFrames = db.unitFrames or {}
                    db.unitFrames.Player = db.unitFrames.Player or {}
                    db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
                    local cfg = db.unitFrames.Player.misc
                    if cfg.hideGroupNumber == true and alpha and alpha > 0 then
                        if not self._ScootGroupIndicatorAlphaDeferred then
                            self._ScootGroupIndicatorAlphaDeferred = true
                            C_Timer.After(0, function()
                                self._ScootGroupIndicatorAlphaDeferred = nil
                                if cfg.hideGroupNumber == true and self.SetAlpha then
                                    pcall(self.SetAlpha, self, 0)
                                end
                            end)
                        end
                    end
                end)
            end
        end

        -- Hook GroupIndicator text
        if groupIndicatorText then
            if groupIndicatorText.Show then
                hooksecurefunc(groupIndicatorText, "Show", function(self)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    db.unitFrames = db.unitFrames or {}
                    db.unitFrames.Player = db.unitFrames.Player or {}
                    db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
                    local cfg = db.unitFrames.Player.misc
                    if cfg.hideGroupNumber == true then
                        if self.SetAlpha then
                            pcall(self.SetAlpha, self, 0)
                        end
                    end
                end)
            end

            if groupIndicatorText.SetAlpha then
                hooksecurefunc(groupIndicatorText, "SetAlpha", function(self, alpha)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    db.unitFrames = db.unitFrames or {}
                    db.unitFrames.Player = db.unitFrames.Player or {}
                    db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
                    local cfg = db.unitFrames.Player.misc
                    if cfg.hideGroupNumber == true and alpha and alpha > 0 then
                        if not self._ScootGroupIndicatorTextAlphaDeferred then
                            self._ScootGroupIndicatorTextAlphaDeferred = true
                            C_Timer.After(0, function()
                                self._ScootGroupIndicatorTextAlphaDeferred = nil
                                if cfg.hideGroupNumber == true and self.SetAlpha then
                                    pcall(self.SetAlpha, self, 0)
                                end
                            end)
                        end
                    end
                end)
            end
        end
    end

    function addon.ApplyPlayerGroupNumberVisibility()
        installGroupNumberHooks()
        applyGroupNumberVisibility()
    end
end

-- Apply all Player Misc. visibility settings
function addon.ApplyAllPlayerMiscVisibility()
    if addon.ApplyPlayerRoleIconVisibility then
        addon.ApplyPlayerRoleIconVisibility()
    end
    if addon.ApplyPlayerGroupNumberVisibility then
        addon.ApplyPlayerGroupNumberVisibility()
    end
end

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
