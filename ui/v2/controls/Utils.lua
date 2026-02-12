-- Utils.lua - Shared utilities for UI controls
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

-- Debounce Utility for Edit Mode Sync
-- Coalesces rapid calls into a single delayed call.

local debounceTimers = {}

local function Debounce(key, delay, callback)
    if debounceTimers[key] then
        debounceTimers[key]:Cancel()
        debounceTimers[key] = nil
    end

    delay = delay or 0.2
    debounceTimers[key] = C_Timer.NewTimer(delay, function()
        debounceTimers[key] = nil
        if callback then
            callback()
        end
    end)
end

local function CancelDebounce(key)
    if debounceTimers[key] then
        debounceTimers[key]:Cancel()
        debounceTimers[key] = nil
    end
end

Controls.Debounce = Debounce
Controls.CancelDebounce = CancelDebounce

-- Global Sync Lock System
-- Persists lock state across slider instances that get recreated on panel re-render.

local globalSyncLocks = {}  -- { [debounceKey] = { locked = bool, pendingValue = number } }

local function SetGlobalSyncLock(key, value)
    globalSyncLocks[key] = { locked = true, pendingValue = value }
end

local function ClearGlobalSyncLock(key)
    globalSyncLocks[key] = nil
end

local function IsGlobalSyncLocked(key)
    return globalSyncLocks[key] and globalSyncLocks[key].locked
end

local function GetGlobalSyncPendingValue(key)
    return globalSyncLocks[key] and globalSyncLocks[key].pendingValue
end

Controls.SetGlobalSyncLock = SetGlobalSyncLock
Controls.ClearGlobalSyncLock = ClearGlobalSyncLock
Controls.IsGlobalSyncLocked = IsGlobalSyncLocked
Controls.GetGlobalSyncPendingValue = GetGlobalSyncPendingValue
