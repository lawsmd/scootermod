local addonName, addon = ...

addon.EditMode = {}

local LEO = LibStub("LibEditModeOverride-1.0")

-- Low-level wrappers for LibEditModeOverride
function addon.EditMode.GetSetting(frame, settingId)
    if not LEO or not LEO.GetFrameSetting then return nil end
    return LEO:GetFrameSetting(frame, settingId)
end

function addon.EditMode.SetSetting(frame, settingId, value)
    if not LEO or not LEO.SetFrameSetting then return nil end
    LEO:SetFrameSetting(frame, settingId, value)
end

function addon.EditMode.ReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
    if not LEO or not LEO.ReanchorFrame then return end
    LEO:ReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
end

function addon.EditMode.ApplyChanges()
    if not LEO or not LEO.ApplyChanges then return end
    if not InCombatLockdown() then
        LEO:ApplyChanges()
    else
        LEO:SaveOnly()
    end
end

-- Helper functions
function addon.EditMode.LoadLayouts()
    if not LEO or not LEO.LoadLayouts or not LEO.IsReady then return end
    if LEO:IsReady() then
        LEO:LoadLayouts()
    end
end

function addon.EditMode.SaveOnly()
    if not LEO or not LEO.SaveOnly then return end
    LEO:SaveOnly()
end

function addon.EditMode.IsReady()
    return LEO and LEO.IsReady and LEO:IsReady()
end

function addon.EditMode.HasEditModeSettings(frame)
    return LEO and LEO.HasEditModeSettings and LEO:HasEditModeSettings(frame)
end

--[[----------------------------------------------------------------------------
    State Synchronization Logic
----------------------------------------------------------------------------]]--

-- Back-sync for position
local function roundPositionValue(v)
    v = tonumber(v) or 0
    return v >= 0 and math.floor(v + 0.5) or math.ceil(v - 0.5)
end

--[[----------------------------------------------------------------------------
    Full Sync Functions (Addon DB -> Edit Mode)
----------------------------------------------------------------------------]]--

function addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
    local frame = _G[component.frameName]
    if not frame or not addon.EditMode.HasEditModeSettings(frame) then return false end

    local setting = component.settings[settingId]
    if not setting or setting.type ~= "editmode" then return false end

    local dbValue = component.db[settingId]
    if dbValue == nil then
        dbValue = setting.default
    end
    if dbValue == nil then return false end

    local editModeValue
    -- Convert addon DB value to the value Edit Mode expects
    if settingId == "orientation" then
        editModeValue = (dbValue == "H") and 0 or 1
    elseif settingId == "columns" then
        editModeValue = tonumber(dbValue) or 12
    elseif settingId == "direction" then
        local orientation = component.db.orientation or "H"
        if orientation == "H" then
            editModeValue = (dbValue == "right") and 1 or 0
        else
            editModeValue = (dbValue == "up") and 1 or 0
        end
    elseif settingId == "iconPadding" then
        -- WRITING to the library requires the RAW value.
        editModeValue = tonumber(dbValue) or 2
    elseif settingId == "iconSize" then
        -- Always send raw percentage (50..200), rounded to nearest 10
        local desiredRaw = tonumber(dbValue) or 100
        if desiredRaw < 50 then desiredRaw = 50 end
        if desiredRaw > 200 then desiredRaw = 200 end
        desiredRaw = math.floor(desiredRaw / 10 + 0.5) * 10
        editModeValue = desiredRaw
    else
        editModeValue = tonumber(dbValue) or 0
    end

    if editModeValue ~= nil then
        -- Skip write if no change (prevents unnecessary churn and odd UI snaps)
        local current = addon.EditMode.GetSetting(frame, setting.settingId)
        if current ~= editModeValue then
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            return true
        end
        return false
    end
    return false
end

-- This is the main function for pushing the addon's state to Edit Mode.
function addon.EditMode.SyncComponentToEditMode(component)
    local frame = _G[component.frameName]
    if not frame or not addon.EditMode.HasEditModeSettings(frame) then return end

    -- 1. Sync Position
    local x = component.db.positionX or 0
    local y = component.db.positionY or 0
    addon.EditMode.ReanchorFrame(frame, "CENTER", "UIParent", "CENTER", x, y)

    -- 2. Sync all other Edit Mode settings
    for settingId, setting in pairs(component.settings) do
        if setting.type == "editmode" then
            addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
        end
    end

    -- 3. Apply all changes atomically
    addon.EditMode.ApplyChanges()
end


--[[----------------------------------------------------------------------------
    Back-Sync Functions (Edit Mode -> Addon DB)
----------------------------------------------------------------------------]]--

-- Syncs a single simple setting from Edit Mode to the addon DB
function addon.EditMode.SyncEditModeSettingToComponent(component, settingId)
    local frame = _G[component.frameName]
    if not frame or not addon.EditMode.HasEditModeSettings(frame) then return false end

    local setting = component.settings[settingId]
    if not setting or setting.type ~= "editmode" then return false end

    local editModeValue = addon.EditMode.GetSetting(frame, setting.settingId)
    if editModeValue == nil then return false end

    local dbValue
    -- Convert Edit Mode value to the value addon DB expects
    if settingId == "orientation" then
        dbValue = (editModeValue == 0) and "H" or "V"
    elseif settingId == "columns" then
        dbValue = math.max(1, math.min(20, tonumber(editModeValue) or 12))
    elseif settingId == "direction" then
        local orientation = component.db.orientation or "H"
        if orientation == "H" then
            dbValue = (editModeValue == 1) and "right" or "left"
        else
            dbValue = (editModeValue == 1) and "up" or "down"
        end
    elseif settingId == "iconPadding" then
        -- Library now returns raw value (2-10); store directly
        dbValue = tonumber(editModeValue) or 2
    elseif settingId == "iconSize" then
        -- Adaptive read: support either index (0-15) or raw (50-200)
        local v = tonumber(editModeValue) or 100
        if v <= 15 then
            dbValue = (v * 10) + 50
        else
            dbValue = v
        end
    else
        dbValue = tonumber(editModeValue) or 0
    end

    if component.db[settingId] ~= dbValue then
        component.db[settingId] = dbValue
        return true -- Indicates a change was made
    end
    return false
end
-- Syncs the frame's position from Edit Mode to the addon DB
function addon.EditMode.SyncComponentPositionFromEditMode(component)
    local frame = _G[component.frameName]
    if not frame then return false end

    local offsetX, offsetY
    if frame.GetCenter and UIParent and UIParent.GetCenter then
        local fx, fy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if fx and fy and ux and uy then
            offsetX = roundPositionValue(fx - ux)
            offsetY = roundPositionValue(fy - uy)
        end
    end

    if offsetX == nil or offsetY == nil then return false end

    local changed = false
    if component.db.positionX ~= offsetX then
        component.db.positionX = offsetX
        changed = true
    end
    if component.db.positionY ~= offsetY then
        component.db.positionY = offsetY
        changed = true
    end

    return changed
end

--[[----------------------------------------------------------------------------
    Initialization and Event Handling
----------------------------------------------------------------------------]]--

-- Centralized helper to run all back-sync operations
function addon.EditMode.RefreshSyncAndNotify(origin)
    if LEO and LEO:IsReady() then
        LEO:LoadLayouts()
    end

    addon:SyncAllEditModeSettings()

    if addon._dbgSync and origin then
        print("ScooterMod RefreshSyncAndNotify origin=" .. tostring(origin))
    end
end

-- Initialize Edit Mode integration
function addon.EditMode.Initialize()
    if not addon._hookedSave and type(_G.C_EditMode) == "table" and type(_G.C_EditMode.SaveLayouts) == "function" then
        hooksecurefunc(_G.C_EditMode, "SaveLayouts", function()
            C_Timer.After(0.0, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass1") end end)
            C_Timer.After(0.3, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass2") end end)
        end)
        addon._hookedSave = true
    end

    if _G.EventRegistry and not addon._editModeCBRegistered then
        local ER = _G.EventRegistry
        if type(ER.RegisterCallback) == "function" then
            ER:RegisterCallback("EditMode.Enter", function() end, addon)
            ER:RegisterCallback("EditMode.Exit", function()
                C_Timer.After(0.1, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("EditModeExit:pass1") end end)
                C_Timer.After(0.5, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("EditModeExit:pass2") end end)
            end, addon)
            addon._editModeCBRegistered = true
        end
    end
end
