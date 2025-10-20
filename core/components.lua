local addonName, addon = ...

addon.Components = {}

local Component = {}

function Component:New(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Component:SyncEditModeSettings()
    local frame = _G[self.frameName]
    if not frame then return end

    for settingId, setting in pairs(self.settings) do
        if setting.type == "editmode" then
            local value = addon.EditMode.GetSetting(frame, setting.settingId)
            if value ~= nil then
                self.db[settingId] = value
            end
        end
    end
end

function addon:RegisterComponent(component)
    self.Components[component.id] = component
end

function addon:InitializeComponents()
    local essentialCooldowns = Component:New({
        id = "essentialCooldowns",
        name = "Essential Cooldowns",
        frameName = "EssentialCooldownViewer",
        settings = {
            -- Positioning
            orientation = { type = "editmode", settingId = 0, default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }
            }},
            columns = { type = "editmode", settingId = 1, default = 12, ui = {
                label = "# Columns/Rows", widget = "slider", min = 1, max = 24, step = 1
            }},
            direction = { type = "editmode", settingId = 2, default = "right", ui = {
                label = "Icon Direction", widget = "dropdown", values = { left = "Left", right = "Right", up = "Up", down = "Down" }
            }},
            iconPadding = { type = "editmode", settingId = 4, default = 6, ui = {
                label = "Icon Padding", widget = "slider", min = 0, max = 20, step = 1
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1
            }},
            -- Sizing
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10
            }},
            iconWidth = { type = "addon", default = 50, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1
            }},
            iconHeight = { type = "addon", default = 50, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1
            }},
            -- Border
            borderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox"
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", values = { square = "Square", tooltip = "Tooltip", dialog = "Dialog", none = "None" }
            }},
            -- Text, etc. will be added later
        },
        ApplyStyling = function(self)
            local frame = _G[self.frameName]
            if not frame then return end

            local width = self.db.iconWidth
            local height = self.db.iconHeight
            local spacing = self.db.iconPadding

            if frame.SetPadding then
                frame:SetPadding(spacing)
            end

            local borderTextures = {
                square = "Interface\Buttons\UI-Panel-Border",
                tooltip = "Interface\Tooltip\Tooltip-Border",
                dialog = "Interface\DialogFrame\UI-DialogBox-Border",
            }
            local edgeFile = self.db.borderEnable and borderTextures[self.db.borderStyle] or nil

            for i, child in ipairs({ frame:GetChildren() }) do
                child:SetSize(width, height)
                if edgeFile and child.SetBackdrop then
                    child:SetBackdrop({
                        edgeFile = edgeFile,
                        edgeSize = self.db.borderThickness * 4, -- A guess
                        insets = { left = self.db.borderThickness, right = self.db.borderThickness, top = self.db.borderThickness, bottom = self.db.borderThickness },
                    })
                    child:SetBackdropBorderColor(1, 1, 1, 1)
                elseif child.SetBackdrop then
                    child:SetBackdrop(nil)
                end
            end

            if frame.UpdateLayout then
                frame:UpdateLayout()
            end
        end,
    })
    self:RegisterComponent(essentialCooldowns)

    local utilityCooldowns = Component:New({
        id = "utilityCooldowns",
        name = "Utility Cooldowns",
        frameName = "UtilityCooldownViewer", -- A guess, needs verification
        settings = {},
        ApplyStyling = function(self) end,
    })
    self:RegisterComponent(utilityCooldowns)

    local trackedBuffs = Component:New({
        id = "trackedBuffs",
        name = "Tracked Buffs",
        frameName = "TrackedBuffs", -- A guess, needs verification
        settings = {},
        ApplyStyling = function(self) end,
    })
    self:RegisterComponent(trackedBuffs)

    local trackedBars = Component:New({
        id = "trackedBars",
        name = "Tracked Bars",
        frameName = "BuffBarCooldownViewer", -- A guess, needs verification
        settings = {},
        ApplyStyling = function(self) end,
    })
    self:RegisterComponent(trackedBars)
end

function addon:LinkComponentsToDB()
    for id, component in pairs(self.Components) do
        if not self.db.profile.components[id] then
            self.db.profile.components[id] = {}
        end
        component.db = self.db.profile.components[id]
    end
end

function addon:ApplyStyles()
    for id, component in pairs(self.Components) do
        if component.ApplyStyling then
            component:ApplyStyling()
        end
    end
end

function addon:SyncAllEditModeSettings()
    for id, component in pairs(self.Components) do
        if component.SyncEditModeSettings then
            component:SyncEditModeSettings()
        end
    end
end