-- damagemetersv2/events.lua - Event registration, timer ticker, combat state sync
local _, addon = ...
local DM2 = addon.DamageMetersV2

--------------------------------------------------------------------------------
-- Event System
--------------------------------------------------------------------------------

local eventFrame = nil
local updatePending = false
local resetPending = false

local function OnEvent(self, event, ...)
    if not DM2._initialized then return end

    if event == "DAMAGE_METER_RESET" then
        resetPending = true
    end

    -- Combat ended: immediate synchronous full refresh
    if event == "PLAYER_REGEN_ENABLED" then
        DM2._Trace("REGEN_ENABLED -> ExitCombatMode + FullRefresh")
        DM2._ExitCombatMode()
        DM2._FullRefreshAllWindows()
        if DM2._comp then
            DM2._RefreshOpacity(DM2._comp)
        end
        return
    end

    -- Combat started: transition to combat mode
    if event == "PLAYER_REGEN_DISABLED" then
        DM2._Trace("REGEN_DISABLED -> EnterCombatMode")
        DM2._EnterCombatMode()
        if DM2._comp then
            DM2._RefreshOpacity(DM2._comp)
        end
        return
    end

    -- Auto-reset on instance entry
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        -- Defer styling re-apply (existing behavior)
        C_Timer.After(1.0, function()
            if DM2._comp then
                DM2._ApplyStyling(DM2._comp)
            end
        end)

        -- Auto-reset on instance entry
        if isInitialLogin or isReloadingUi then return end

        local comp = DM2._comp
        if not comp or not comp.db then return end

        local mode = comp.db.autoResetData
        if mode ~= "instance" then return end

        local inInstance, instanceType = IsInInstance()
        if not inInstance then return end
        if instanceType ~= "party" and instanceType ~= "raid" and instanceType ~= "scenario" then return end

        if not C_DamageMeter or not C_DamageMeter.ResetAllCombatSessions then return end

        if comp.db.autoResetPrompt then
            if addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOT_DM_RESET_CONFIRM", {
                    onAccept = function()
                        C_DamageMeter.ResetAllCombatSessions()
                    end,
                })
            end
        else
            C_DamageMeter.ResetAllCombatSessions()
        end
        return
    end

    -- Throttled update for damage meter data events
    if not updatePending then
        updatePending = true
        DM2._Trace("THROTTLE event=" .. event .. " inCombat=" .. tostring(DM2._inCombat))
        local throttle = DM2._comp and DM2._comp.db and DM2._comp.db.updateThrottle or 1.0
        C_Timer.After(throttle, function()
            updatePending = false
            if resetPending then
                resetPending = false
                DM2._HandleReset()
            end
            DM2._Trace("TIMER_FIRED calling _UpdateAllWindows")
            DM2._UpdateAllWindows()
        end)
    end
end

--------------------------------------------------------------------------------
-- Timer Ticker (1-second OnUpdate for header stopwatch)
--------------------------------------------------------------------------------

local timerFrame = nil

local function OnTimerUpdate(self, elapsed)
    self._elapsed = (self._elapsed or 0) + elapsed
    if self._elapsed < 1.0 then return end
    self._elapsed = 0

    if not DM2._initialized then return end

    for i = 1, DM2.MAX_WINDOWS do
        local win = DM2._windows[i]
        local cfg = DM2._GetWindowConfig(i)
        if win and cfg and cfg.enabled and win.frame:IsShown() then
            DM2._UpdateTimerText(i)
        end
    end
end

--------------------------------------------------------------------------------
-- Initialization (called from core.lua _Initialize)
--------------------------------------------------------------------------------

function DM2._InitializeEvents(comp)
    -- Event frame
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    eventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
    eventFrame:RegisterEvent("DAMAGE_METER_RESET")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", OnEvent)

    -- Timer ticker
    timerFrame = CreateFrame("Frame")
    timerFrame._elapsed = 0
    timerFrame:SetScript("OnUpdate", OnTimerUpdate)

    -- If already in combat when this loads, sync state
    if InCombatLockdown() then
        DM2._inCombat = true
        DM2._combatStartTime = GetTime()
    end
end
