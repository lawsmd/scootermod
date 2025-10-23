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

    local changed = false
    for settingId, setting in pairs(self.settings) do
        if setting.type == "editmode" then
            if addon.EditMode.SyncEditModeSettingToComponent(self, settingId) then
                changed = true
            end
        end
    end

    return changed
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
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            columns = { type = "editmode", settingId = 1, default = 12, ui = {
                label = "# Columns/Rows", widget = "slider", min = 1, max = 20, step = 1, section = "Positioning", order = 2, dynamicLabel = true
            }},
            direction = { type = "editmode", settingId = 2, default = "right", ui = {
                label = "Icon Direction", widget = "dropdown", values = { left = "Left", right = "Right", up = "Up", down = "Down" }, section = "Positioning", order = 3, dynamicValues = true
            }},
            iconPadding = { type = "editmode", settingId = 4, default = 2, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 4
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 5
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 6
            }},
            -- Sizing
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            iconWidth = { type = "addon", default = 50, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 2
            }},
            iconHeight = { type = "addon", default = 50, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 3
            }},
            -- Border
            borderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Border", order = 1, tooltip = ""
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", values = { square = "Square", style_tooltip = "Tooltip", dialog = "Dialog", none = "None" }, section = "Border", order = 4
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Border", order = 5
            }},
            -- Visibility
            opacity = { type = "addon", default = 100, ui = {
                label = "Opacity (%)", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 1
            }},
            visibilityMode = { type = "addon", default = "always", ui = {
                label = "Visibility Mode", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 2
            }},
            showTimer = { type = "addon", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 3
            }},
            showTooltip = { type = "addon", default = true, ui = {
                label = "Show Tooltip", widget = "checkbox", section = "Misc", order = 4
            }},
        },
        ApplyStyling = function(self)
            local frame = _G[self.frameName]
            if not frame then return end

            -- Use defaults from component definition if db is not populated
            local width = self.db.iconWidth or self.settings.iconWidth.default
            local height = self.db.iconHeight or self.settings.iconHeight.default
            local spacing = self.db.iconPadding or self.settings.iconPadding.default
            for i, child in ipairs({ frame:GetChildren() }) do
                child:SetSize(width, height)
                if self.db.borderEnable then
                    local style = self.db.borderStyle or "square"
                    if type(style) == "string" and style:find("^atlas:") and addon.Borders and addon.Borders.ApplyAtlas then
                        local key = style:sub(7)
                        if key and #key > 0 then
                            local t = tonumber(self.db.borderThickness) or 1
                            if t < 1 then t = 1 elseif t > 16 then t = 16 end
                            local extra = -math.floor(((t - 1) / 15) * 2 + 0.5)
                            local tint = (self.db.borderTintEnable and (self.db.borderTintColor or {1,1,1,1})) or nil
                            addon.Borders.ApplyAtlas(child, { atlas = key, extraPadding = extra, tintColor = tint })
                        else
                            if addon.Borders and addon.Borders.ApplySquare then
                                addon.Borders.ApplySquare(child, { size = self.db.borderThickness or 1, color = {0,0,0,1} })
                            end
                        end
                    elseif addon.Borders and addon.Borders.ApplySquare then
                        local col = {0,0,0,1}
                        if self.db.borderTintEnable and type(self.db.borderTintColor) == "table" then
                            col = { self.db.borderTintColor[1] or 1, self.db.borderTintColor[2] or 1, self.db.borderTintColor[3] or 1, self.db.borderTintColor[4] or 1 }
                        end
                        addon.Borders.ApplySquare(child, { size = self.db.borderThickness or 1, color = col })
                    end
                else
                    if addon.Borders and addon.Borders.HideAll then
                        addon.Borders.HideAll(child)
                    end
                end
            end

            -- Re-apply padding on the actual item container (matches RIPAuras behavior)
            do
                local ic = (frame.GetItemContainerFrame and frame:GetItemContainerFrame()) or frame
                if ic then
                    if ic.childXPadding ~= nil then ic.childXPadding = spacing end
                    if ic.childYPadding ~= nil then ic.childYPadding = spacing end
                    if ic.iconPadding ~= nil then ic.iconPadding = spacing end
                    if type(ic.MarkDirty) == "function" then
                        pcall(ic.MarkDirty, ic)
                    end
                end
            end

            if frame.UpdateLayout then pcall(frame.UpdateLayout, frame) end
            local ic2 = (frame.GetItemContainerFrame and frame:GetItemContainerFrame()) or frame
            if ic2 and type(ic2.UpdateLayout) == "function" then pcall(ic2.UpdateLayout, ic2) end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    local ic3 = (frame.GetItemContainerFrame and frame:GetItemContainerFrame()) or frame
                    if ic3 and ic3.UpdateLayout then pcall(ic3.UpdateLayout, ic3) end
                end)
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
