local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

local function renderProfilesPresets()
    local function render()
        local f = panel.frame
        if not f or not f.SettingsList then return end
        local settingsList = f.SettingsList
        settingsList.Header.Title:SetText("Presets")
        local init = {}
        local messageRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
        messageRow.GetExtent = function() return 40 end
        messageRow.InitFrame = function(self, frame)
            if frame.InfoText then frame.InfoText:Hide() end
            if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end
            if frame.RenameBtn then frame.RenameBtn:Hide() end
            if frame.CopyBtn then frame.CopyBtn:Hide() end
            if frame.DeleteBtn then frame.DeleteBtn:Hide() end
            if not frame.MessageText then
                local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
                text:SetPoint("LEFT", frame, "LEFT", 16, 0)
                text:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
                text:SetJustifyH("LEFT")
                text:SetText("Preset collections are coming soon. For now, use Edit Mode to swap between Blizzard's Modern and Classic presets.")
                frame.MessageText = text
            else
                frame.MessageText:Show()
            end
        end
        table.insert(init, messageRow)

        settingsList:Display(init)
        if settingsList.RepairDisplay then
            pcall(settingsList.RepairDisplay, settingsList, { EnumerateInitializers = function() return ipairs(init) end, GetInitializers = function() return init end })
        end
        settingsList:Show()
        if f.Canvas then
            f.Canvas:Hide()
        end
    end
    return { mode = "list", render = render, componentId = "profilesPresets" }
end

function panel.RenderProfilesPresets()
    return renderProfilesPresets()
end


