local addonName, addon = ...

addon.EditMode = {}

local LEO = LibStub("LibEditModeOverride-1.0")

function addon.EditMode.GetSetting(frame, settingId)
    if not LEO or not LEO.GetFrameSetting then return nil end
    return LEO:GetFrameSetting(frame, settingId)
end

function addon.EditMode.SetSetting(frame, settingId, value)
    if not LEO or not LEO.SetFrameSetting then return end
    LEO:SetFrameSetting(frame, settingId, value)
end

function addon.EditMode.LoadLayouts()
    if not LEO or not LEO.LoadLayouts or not LEO.IsReady then return end
    if LEO:IsReady() then
        LEO:LoadLayouts()
    end
end
