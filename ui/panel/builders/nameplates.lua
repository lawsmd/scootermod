local addonName, addon = ...
addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

function panel.RenderNameplatesUnit()
    local render = function()
        local component = addon.Components["nameplatesUnit"]
        if not component then return end

        if panel and panel.PrepareDynamicSettingWidgets then
            panel:PrepareDynamicSettingWidgets("nameplatesUnit")
        end

        local init = {}

        local textHeader = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
            name = "Text",
            sectionKey = "Text",
            componentId = "nameplatesUnit",
            expanded = panel:IsSectionExpanded("nameplatesUnit", "Text"),
        })
        textHeader.GetExtent = function() return 30 end
        table.insert(init, textHeader)

        local data = { sectionTitle = "", tabAText = "Name" }
        data.build = function(frame)
            local db = component.db or {}
            local defaults = component.settings and component.settings.textName and component.settings.textName.default or {}
            local function isDefaultWhiteColor(color)
                if type(color) ~= "table" then
                    return false
                end
                local r = tonumber(color[1]) or 0
                local g = tonumber(color[2]) or 0
                local b = tonumber(color[3]) or 0
                local a = tonumber(color[4])
                if a == nil then
                    a = 1
                end
                return r == 1 and g == 1 and b == 1 and a == 1
            end

            local function migrateColorDefaults()
                if not component or not component.db or component.db._nameplatesColorMigrated then
                    return
                end
                local cfg = component.db.textName
                if cfg and isDefaultWhiteColor(cfg.color) then
                    cfg.color = nil
                end
                component.db._nameplatesColorMigrated = true
            end

            migrateColorDefaults()
            local function ensureConfig()
                if db.textName == nil then
                    if type(defaults) == "table" and CopyTable then
                        db.textName = CopyTable(defaults)
                    elseif type(defaults) == "table" then
                        local copy = {}
                        for k, v in pairs(defaults) do
                            copy[k] = v
                        end
                        db.textName = copy
                    else
                        db.textName = {}
                    end
                end
                return db.textName
            end

            local function applyText()
                if addon and addon.ApplyStyles then
                    addon:ApplyStyles()
                end
            end

            local function fontOptions()
                if addon.BuildFontOptionsContainer then
                    return addon.BuildFontOptionsContainer()
                end
                return Settings.CreateControlTextContainer():GetData()
            end

            local function fmtInt(v)
                return tostring(math.floor((tonumber(v) or 0) + 0.5))
            end

            local function addDropdown(parent, label, optionsProvider, getter, setter, yRef)
                local setting = CreateLocalSetting(label, "string", getter, setter, getter())
                local initializer = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                    name = label,
                    setting = setting,
                    options = optionsProvider,
                })
                local row = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
                row.GetElementData = function() return initializer end
                row:SetPoint("TOPLEFT", 4, yRef.y)
                row:SetPoint("TOPRIGHT", -16, yRef.y)
                initializer:InitFrame(row)
                local lbl = row and (row.Text or row.Label)
                if lbl and panel and panel.ApplyRobotoWhite then
                    panel.ApplyRobotoWhite(lbl)
                end
                if row.Control and panel.ThemeDropdownWithSteppers then
                    panel.ThemeDropdownWithSteppers(row.Control)
                end
                if label:lower():find("font", 1, true) and row.Control and row.Control.Dropdown then
                    if addon.InitFontDropdown then
                        addon.InitFontDropdown(row.Control.Dropdown, setting, optionsProvider)
                    end
                end
                yRef.y = yRef.y - 34
            end

            local function addSlider(parent, label, minV, maxV, step, getter, setter, yRef)
                local options = Settings.CreateSliderOptions(minV, maxV, step)
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
                    return fmtInt(value)
                end)
                local setting = CreateLocalSetting(label, "number", getter, setter, getter())
                local initializer = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
                    name = label,
                    setting = setting,
                    options = options,
                })
                local row = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
                row.GetElementData = function() return initializer end
                row:SetPoint("TOPLEFT", 4, yRef.y)
                row:SetPoint("TOPRIGHT", -16, yRef.y)
                initializer:InitFrame(row)
                if row.Text and panel and panel.ApplyRobotoWhite then
                    panel.ApplyRobotoWhite(row.Text)
                end
                if panel and panel.ApplyControlTheme then
                    panel.ApplyControlTheme(row)
                end
                yRef.y = yRef.y - 34
            end

            local function addStyleDropdown(parent, label, getter, setter, yRef)
                local function styleOptions()
                    local container = Settings.CreateControlTextContainer()
                    container:Add("NONE", "Regular")
                    container:Add("OUTLINE", "Outline")
                    container:Add("THICKOUTLINE", "Thick Outline")
                    return container:GetData()
                end
                addDropdown(parent, label, styleOptions, getter, setter, yRef)
            end

            local function addColorRow(parent, label, getter, setter, yRef)
                local row = CreateFrame("Frame", nil, parent, "SettingsListElementTemplate")
                row:SetHeight(26)
                row:SetPoint("TOPLEFT", 4, yRef.y)
                row:SetPoint("TOPRIGHT", -16, yRef.y)
                if row.Text then
                    row.Text:SetText(label)
                    if panel and panel.ApplyRobotoWhite then
                        panel.ApplyRobotoWhite(row.Text)
                    end
                end
                local right = CreateFrame("Frame", nil, row)
                right:SetSize(250, 26)
                right:SetPoint("RIGHT", row, "RIGHT", -16, 0)
                row.Text:ClearAllPoints()
                row.Text:SetPoint("LEFT", row, "LEFT", 36.5, 0)
                row.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
                row.Text:SetJustifyH("LEFT")
                local function getColorTable()
                    local r, g, b, a = getter()
                    return { r or 1, g or 1, b or 1, a or 1 }
                end
                local function setColorTable(r, g, b, a)
                    setter(r, g, b, a)
                end
                CreateColorSwatch(right, getColorTable, setColorTable, true):SetPoint("LEFT", right, "LEFT", 8, 0)
                yRef.y = yRef.y - 34
            end

            local y = { y = -50 }

            addDropdown(frame.PageA, "Name Font", fontOptions,
                function()
                    local target = ensureConfig()
                    return target.fontFace or "FRIZQT__"
                end,
                function(value)
                    ensureConfig().fontFace = value
                    applyText()
                end,
                y)

            addSlider(frame.PageA, "Name Size", 6, 32, 1,
                function()
                    local target = ensureConfig()
                    return target.size or 14
                end,
                function(value)
                    ensureConfig().size = tonumber(value) or 14
                    applyText()
                end,
                y)

            addStyleDropdown(frame.PageA, "Name Style",
                function()
                    local target = ensureConfig()
                    return target.style or "OUTLINE"
                end,
                function(value)
                    ensureConfig().style = value
                    applyText()
                end,
                y)

            addColorRow(frame.PageA, "Name Color",
                function()
                    local target = ensureConfig()
                    local color = target.color
                    if type(color) ~= "table" then
                        return 1, 1, 1, 1
                    end
                    return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
                end,
                function(r, g, b, a)
                    local target = ensureConfig()
                    target.color = { r or 1, g or 1, b or 1, a or 1 }
                    applyText()
                end,
                y)

            -- Offsets intentionally disabled for Nameplates until Blizzard finalizes Midnight changes.
        end

        local tabbedInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
        tabbedInit.GetExtent = function() return 260 end
        tabbedInit:AddShownPredicate(function()
            return panel:IsSectionExpanded("nameplatesUnit", "Text")
        end)
        table.insert(init, tabbedInit)

        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then return end

        if right.SetTitle then
            right:SetTitle(component.name or component.id)
        end
        right:Display(init)

        if panel.RefreshDynamicSettingWidgets then
            C_Timer.After(0, function()
                panel:RefreshDynamicSettingWidgets(component)
            end)
        end
    end

    return { mode = "list", render = render, componentId = "nameplatesUnit" }
end
