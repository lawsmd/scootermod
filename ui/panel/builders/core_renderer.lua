local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

local common = panel.common or {}
local BuildAuraWrapOptions = common and common.BuildAuraWrapOptions
local BuildAuraDirectionOptions = common and common.BuildAuraDirectionOptions
local BuildDirectionOptions = common and common.BuildDirectionOptions
local ApplyColumnsLabel = common and common.ApplyColumnsLabel
local ApplyIconLimitLabel = common and common.ApplyIconLimitLabel

local function createPRDStyleInitializer(component)
    local initializer = Settings.CreateElementInitializer("ScooterListElementTemplate")
    initializer.GetExtent = function()
        return 220
    end
    initializer:AddShownPredicate(function()
        return panel:IsSectionExpanded(component.id, "Style")
    end)
    initializer.InitFrame = function(self, frame)
        if not component then
            return
        end
        if frame._ScooterPRDStyleBuilt then
            if frame.Refresh then
                frame:Refresh()
            end
            return
        end
        frame._ScooterPRDStyleBuilt = true

        if frame.Text then
            frame.Text:SetText("")
            frame.Text:Hide()
        end

        frame:SetHeight(210)

        local componentSettings = component.settings or {}
        local db = component.db or {}
        local styleState = {}

        local function applyNow()
            if addon and addon.ApplyStyles then
                addon:ApplyStyles()
            end
        end

        local function getDefault(key, fallback)
            local setting = componentSettings[key]
            if setting and setting.default ~= nil then
                if type(setting.default) == "table" then
                    return CopyTable(setting.default)
                end
                return setting.default
            end
            return fallback
        end

        local function getValue(key, fallback)
            local value = db[key]
            if value == nil then
                value = getDefault(key, fallback)
            end
            if type(value) == "table" then
                value = CopyTable(value)
            end
            return value
        end

        local function setValue(key, value, fallback)
            -- Zero‑Touch: do not create component SavedVariables until the user actually changes a setting.
            if not component.db then
                if addon and addon.EnsureComponentDB then
                    addon:EnsureComponentDB(component)
                end
            end
            if not component.db then
                return
            end
            if type(value) == "table" then
                component.db[key] = CopyTable(value)
            else
                component.db[key] = value ~= nil and value or fallback
            end
        end

        local y = -16

        local function buildTextureOptions()
            if addon.BuildBarTextureOptionsContainer then
                return addon.BuildBarTextureOptionsContainer()
            end
            local container = Settings.CreateControlTextContainer()
            container:Add("default", "Default")
            return container:GetData()
        end

        local fgTextureSetting = CreateLocalSetting("Foreground Texture", "string",
            function() return getValue("styleForegroundTexture", "default") or "default" end,
            function(v)
                setValue("styleForegroundTexture", v or "default", "default")
                applyNow()
            end,
            getValue("styleForegroundTexture", "default") or "default"
        )
        local fgTextureInit = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
            name = "Foreground Texture",
            setting = fgTextureSetting,
            options = buildTextureOptions,
        })
        local fgTextureFrame = CreateFrame("Frame", nil, frame, "SettingsDropdownControlTemplate")
        fgTextureFrame.GetElementData = function() return fgTextureInit end
        fgTextureFrame:SetPoint("TOPLEFT", 4, y)
        fgTextureFrame:SetPoint("TOPRIGHT", -16, y)
        fgTextureInit:InitFrame(fgTextureFrame)
        if panel and panel.ApplyRobotoWhite then
            local lbl = fgTextureFrame and (fgTextureFrame.Text or fgTextureFrame.Label)
            if lbl then panel.ApplyRobotoWhite(lbl) end
        end
        if fgTextureFrame.Control and addon.InitBarTextureDropdown then
            addon.InitBarTextureDropdown(fgTextureFrame.Control, fgTextureSetting)
        end
        if fgTextureFrame.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(fgTextureFrame.Control) end
        y = y - 34
        styleState.fgTexture = fgTextureSetting

        local function fgColorOptions()
            local container = Settings.CreateControlTextContainer()
            container:Add("default", "Default")
            container:Add("texture", "Texture Original")
            container:Add("class", "Class Color")
            container:Add("custom", "Custom")
            return container:GetData()
        end
        local function getForegroundMode()
            return getValue("styleForegroundColorMode", "default") or "default"
        end
        local function setForegroundMode(mode)
            setValue("styleForegroundColorMode", mode or "default", "default")
            applyNow()
        end
        local function getForegroundTint()
            return getValue("styleForegroundTint", {1, 1, 1, 1}) or {1, 1, 1, 1}
        end
        local function setForegroundTint(r, g, b, a)
            setValue("styleForegroundTint", {r or 1, g or 1, b or 1, a or 1}, {1, 1, 1, 1})
            applyNow()
        end
        local yRef = { y = y }
        panel.DropdownWithInlineSwatch(frame, yRef, {
            label = "Foreground Color",
            getMode = getForegroundMode,
            setMode = setForegroundMode,
            getColor = function()
                local tint = getForegroundTint()
                return tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
            end,
            setColor = function(r, g, b, a)
                setForegroundTint(r, g, b, a)
            end,
            options = fgColorOptions,
            insideButton = true,
        })
        y = yRef.y

        local spacer = CreateFrame("Frame", nil, frame, "SettingsListElementTemplate")
        spacer:SetHeight(20)
        spacer:SetPoint("TOPLEFT", 4, y)
        spacer:SetPoint("TOPRIGHT", -16, y)
        if spacer.Text then spacer.Text:SetText("") end
        y = y - 24

        local bgTextureSetting = CreateLocalSetting("Background Texture", "string",
            function() return getValue("styleBackgroundTexture", "default") or "default" end,
            function(v)
                setValue("styleBackgroundTexture", v or "default", "default")
                applyNow()
            end,
            getValue("styleBackgroundTexture", "default") or "default"
        )
        local bgTextureInit = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
            name = "Background Texture",
            setting = bgTextureSetting,
            options = buildTextureOptions,
        })
        local bgTextureFrame = CreateFrame("Frame", nil, frame, "SettingsDropdownControlTemplate")
        bgTextureFrame.GetElementData = function() return bgTextureInit end
        bgTextureFrame:SetPoint("TOPLEFT", 4, y)
        bgTextureFrame:SetPoint("TOPRIGHT", -16, y)
        bgTextureInit:InitFrame(bgTextureFrame)
        if panel and panel.ApplyRobotoWhite then
            local lbl = bgTextureFrame and (bgTextureFrame.Text or bgTextureFrame.Label)
            if lbl then panel.ApplyRobotoWhite(lbl) end
        end
        if bgTextureFrame.Control and addon.InitBarTextureDropdown then
            addon.InitBarTextureDropdown(bgTextureFrame.Control, bgTextureSetting)
        end
        if bgTextureFrame.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(bgTextureFrame.Control) end
        y = y - 34
        styleState.bgTexture = bgTextureSetting

        local function bgColorOptions()
            local container = Settings.CreateControlTextContainer()
            container:Add("default", "Default")
            container:Add("texture", "Texture Original")
            container:Add("custom", "Custom")
            return container:GetData()
        end
        local function getBackgroundMode()
            return getValue("styleBackgroundColorMode", "default") or "default"
        end
        local function setBackgroundMode(mode)
            setValue("styleBackgroundColorMode", mode or "default", "default")
            applyNow()
        end
        local function getBackgroundTint()
            return getValue("styleBackgroundTint", {0, 0, 0, 1}) or {0, 0, 0, 1}
        end
        local function setBackgroundTint(r, g, b, a)
            setValue("styleBackgroundTint", {r or 0, g or 0, b or 0, a or 1}, {0, 0, 0, 1})
            applyNow()
        end
        yRef = { y = y }
        panel.DropdownWithInlineSwatch(frame, yRef, {
            label = "Background Color",
            getMode = getBackgroundMode,
            setMode = setBackgroundMode,
            getColor = function()
                local tint = getBackgroundTint()
                return tint[1] or 0, tint[2] or 0, tint[3] or 0, tint[4] or 1
            end,
            setColor = function(r, g, b, a)
                setBackgroundTint(r, g, b, a)
            end,
            options = bgColorOptions,
            insideButton = true,
        })
        y = yRef.y

        local bgOpacitySetting = CreateLocalSetting("Background Opacity", "number",
            function() return getValue("styleBackgroundOpacity", 50) or 50 end,
            function(v)
                local newValue = tonumber(v) or 50
                if newValue < 0 then
                    newValue = 0
                elseif newValue > 100 then
                    newValue = 100
                end
                setValue("styleBackgroundOpacity", newValue, 50)
                applyNow()
            end,
            getValue("styleBackgroundOpacity", 50) or 50
        )
        local bgOpacityOptions = Settings.CreateSliderOptions(0, 100, 1)
        bgOpacityOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return tostring(math.floor((tonumber(value) or 0) + 0.5))
        end)
        local bgOpacityInit = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
            name = "Background Opacity",
            setting = bgOpacitySetting,
            options = bgOpacityOptions,
        })
        local bgOpacityFrame = CreateFrame("Frame", nil, frame, "SettingsSliderControlTemplate")
        bgOpacityFrame.GetElementData = function() return bgOpacityInit end
        bgOpacityFrame:SetPoint("TOPLEFT", 4, y)
        bgOpacityFrame:SetPoint("TOPRIGHT", -16, y)
        bgOpacityInit:InitFrame(bgOpacityFrame)
        if panel and panel.ApplyControlTheme then
            panel.ApplyControlTheme(bgOpacityFrame)
        end
        if panel and panel.ApplyRobotoWhite and bgOpacityFrame.Text then
            panel.ApplyRobotoWhite(bgOpacityFrame.Text)
        end
        styleState.bgOpacity = bgOpacitySetting

        frame._ScooterPRDStyleSettings = styleState
        frame.Refresh = function(self)
            local settings = self._ScooterPRDStyleSettings
            if not settings then return end
            if settings.fgTexture and settings.fgTexture.SetValue then
                settings.fgTexture:SetValue(getValue("styleForegroundTexture", "default") or "default")
            end
            if settings.bgTexture and settings.bgTexture.SetValue then
                settings.bgTexture:SetValue(getValue("styleBackgroundTexture", "default") or "default")
            end
            if settings.bgOpacity and settings.bgOpacity.SetValue then
                settings.bgOpacity:SetValue(getValue("styleBackgroundOpacity", 50) or 50)
            end
        end
        if frame.Refresh then
            frame:Refresh()
        end
    end
    return initializer
end

local function createComponentRenderer(componentId)
    return function()
        local render = function()
            local component = addon.Components[componentId]
            if not component then return end

            if panel and panel.PrepareDynamicSettingWidgets then
                panel:PrepareDynamicSettingWidgets(component.id)
            end

            local init = {}
            local sections = {}
            -- Store refresh functions for Border/Backdrop sections to call after Display completes
            local borderRefreshFunc = nil
            local backdropRefreshFunc = nil
            for settingId, setting in pairs(component.settings) do
				-- Some entries in component.settings are boolean markers
				-- (e.g., supportsEmptyBorderSection). Only real setting
				-- tables with UI metadata should be turned into controls.
				if type(setting) == "table" and setting.ui and not setting.ui.hidden then
                    local section = setting.ui.section or "General"
                    if not sections[section] then sections[section] = {} end
                    table.insert(sections[section], {id = settingId, setting = setting})
                end
            end

            -- Regression guard: ensure Cooldown Manager components always render both X/Y controls.
            do
                local requiresPositionAxes = component.id == "essentialCooldowns"
                    or component.id == "utilityCooldowns"
                    or component.id == "trackedBuffs"
                    or component.id == "trackedBars"
                if requiresPositionAxes then
                    sections["Positioning"] = sections["Positioning"] or {}
                    local hasPositionX = false
                    local hasPositionY = false
                    for _, entry in ipairs(sections["Positioning"]) do
                        if entry.id == "positionX" then hasPositionX = true end
                        if entry.id == "positionY" then hasPositionY = true end
                        if hasPositionX and hasPositionY then break end
                    end
                    if not hasPositionX and component.settings.positionX then
                        table.insert(sections["Positioning"], { id = "positionX", setting = component.settings.positionX })
                    end
                    if not hasPositionY and component.settings.positionY then
                        table.insert(sections["Positioning"], { id = "positionY", setting = component.settings.positionY })
                    end
                end
            end

            for _, sectionSettings in pairs(sections) do
                table.sort(sectionSettings, function(a, b) return (a.setting.ui.order or 999) < (b.setting.ui.order or 999) end)
            end

            local orderedSections = {"Positioning", "Sizing", "Style", "Border", "Backdrop", "Icon", "Text", "Font", "Misc"}
            for _, sectionName in ipairs(orderedSections) do
                if sectionName == "Text" then
                    local supportsText = component and component.settings and component.settings.supportsText
                    if supportsText then
                        local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                            name = "Text",
                            sectionKey = "Text",
                            componentId = component.id,
                            expanded = panel:IsSectionExpanded(component.id, "Text"),
                        })
                        expInitializer.GetExtent = function() return 30 end
                        table.insert(init, expInitializer)

                        local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
                        local function addSlider(parent, label, minV, maxV, step, getFunc, setFunc, yRef)
                            local options = Settings.CreateSliderOptions(minV, maxV, step)
                            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
                            local setting = CreateLocalSetting(label, "number", getFunc, setFunc, getFunc())
                            local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
                            local f = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
                            f.GetElementData = function() return initSlider end
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            initSlider:InitFrame(f)
                            if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
                            if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
                            yRef.y = yRef.y - 34
                        end
                        local function addDropdown(parent, label, optsProvider, getFunc, setFunc, yRef)
                            local setting = CreateLocalSetting(label, "string", getFunc, setFunc, getFunc())
                            local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = label, setting = setting, options = optsProvider })
                            local f = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
                            f.GetElementData = function() return initDrop end
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            initDrop:InitFrame(f)
                            local lbl = f and (f.Text or f.Label)
                            if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
                            if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
                            if addon.Media and addon.Media.GetBarTextureMenuEntries and string.find(string.lower(label or ""), "texture", 1, true) then
                                local dd = f.Control and f.Control.Dropdown
                                if dd and dd.SetupMenu then
                                    dd:SetupMenu(function(menu, root)
                                        local entries = addon.Media.GetBarTextureMenuEntries()
                                        for _, e in ipairs(entries) do
                                            root:CreateRadio(e.text, function()
                                                return setting:GetValue() == e.key
                                            end, function()
                                                setting:SetValue(e.key)
                                            end)
                                        end
                                    end)
                                end
                            end
                            if type(label) == "string" and string.find(label, "Font") and not string.find(label, "Style") and f.Control and f.Control.Dropdown then
                                if addon.InitFontDropdown then
                                    addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
                                end
                            end
                            if type(label) == "string" and string.find(string.lower(label), "style", 1, true) and f.Control and f.Control.Dropdown then
                                local dd = f.Control.Dropdown
                                if dd and dd.SetupMenu then
                                    dd:SetupMenu(function(menu, root)
                                        local options = {
                                            { key = "NONE", text = "Regular" },
                                            { key = "OUTLINE", text = "Outline" },
                                            { key = "THICKOUTLINE", text = "Thick Outline" },
                                            { key = "HEAVYTHICKOUTLINE", text = "Heavy Thick Outline" },
                                            { key = "SHADOW", text = "Shadow" },
                                            { key = "SHADOWOUTLINE", text = "Shadow Outline" },
                                            { key = "SHADOWTHICKOUTLINE", text = "Shadow Thick Outline" },
                                            { key = "HEAVYSHADOWTHICKOUTLINE", text = "Heavy Shadow Thick Outline" },
                                        }
                                        for _, e in ipairs(options) do
                                            local desc = root:CreateRadio(e.text, function()
                                                return setting:GetValue() == e.key
                                            end, function()
                                                setting:SetValue(e.key)
                                            end)
                                            desc:AddInitializer(function(button)
                                                local face = (addon and addon.Fonts and (addon.Fonts.ROBOTO_MED or addon.Fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
                                                if button and button.Text and button.Text.GetFont then
                                                    local _, sz = button.Text:GetFont()
                                                    button.Text:SetFont(face, sz or 12, "")
                                                    if button.Text.SetTextColor then button.Text:SetTextColor(1, 1, 1, 1) end
                                                end
                                                if button and button.HookScript then
                                                    button:HookScript("OnShow", function()
                                                        if button.Text and button.Text.GetFont then
                                                            local _, sz = button.Text:GetFont()
                                                            button.Text:SetFont(face, sz or 12, "")
                                                            if button.Text.SetTextColor then button.Text:SetTextColor(1, 1, 1, 1) end
                                                        end
                                                    end)
                                                end
                                                if C_Timer and C_Timer.After then C_Timer.After(0, function()
                                                    if button and button.Text and button.Text.GetFont then
                                                        local _, sz = button.Text:GetFont()
                                                        button.Text:SetFont(face, sz or 12, "")
                                                        if button.Text.SetTextColor then button.Text:SetTextColor(1, 1, 1, 1) end
                                                    end
                                                end) end
                                            end)
                                        end
                                    end)
                                end
                            end
                            if type(label) == "string" and string.find(string.lower(label), "texture", 1, true) and f.Control and f.Control.Dropdown then
                                if addon.InitBarTextureDropdown then
                                    addon.InitBarTextureDropdown(f.Control, setting)
                                end
                            end
                            yRef.y = yRef.y - 34
                        end
                        local function addStyle(parent, label, getFunc, setFunc, yRef)
                            local function styleOptions()
                                local container = Settings.CreateControlTextContainer();
                                container:Add("NONE", "Regular");
                                container:Add("OUTLINE", "Outline");
                                container:Add("THICKOUTLINE", "Thick Outline");
                                container:Add("HEAVYTHICKOUTLINE", "Heavy Thick Outline");
                                container:Add("SHADOW", "Shadow");
                                container:Add("SHADOWOUTLINE", "Shadow Outline");
                                container:Add("SHADOWTHICKOUTLINE", "Shadow Thick Outline");
                                container:Add("HEAVYSHADOWTHICKOUTLINE", "Heavy Shadow Thick Outline");
                                return container:GetData()
                            end
                            addDropdown(parent, label, styleOptions, getFunc, setFunc, yRef)
                        end
                        local function addColor(parent, label, hasAlpha, getFunc, setFunc, yRef)
                            local f = CreateFrame("Frame", nil, parent, "SettingsListElementTemplate")
                            f:SetHeight(26)
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            f.Text:SetText(label)
                            if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
                            local right = CreateFrame("Frame", nil, f)
                            right:SetSize(250, 26)
                            right:SetPoint("RIGHT", f, "RIGHT", -16, 0)
                            f.Text:ClearAllPoints()
                            f.Text:SetPoint("LEFT", f, "LEFT", 36.5, 0)
                            f.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
                            f.Text:SetJustifyH("LEFT")
                            -- Use centralized color swatch factory
                            local function getColorTable()
                                local r, g, b, a = getFunc()
                                return {r or 1, g or 1, b or 1, a or 1}
                            end
                            local function setColorTable(r, g, b, a)
                                setFunc(r, g, b, a)
                            end
                            local swatch = CreateColorSwatch(right, getColorTable, setColorTable, hasAlpha)
                            swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                            yRef.y = yRef.y - 34
                        end

                        local function isActionBar()
                            local id = tostring(component and component.id or "")
                            return id:find("actionBar", 1, true) == 1 or id == "petBar"
                        end

                        local tabAName, tabBName
                        if component and component.id == "trackedBuffs" then
                            tabAName, tabBName = "Stacks", "Cooldown"
                        elseif component and (component.id == "buffs" or component.id == "debuffs") then
                            tabAName, tabBName = "Stacks", "Duration"
                        elseif component and component.id == "trackedBars" then
                            tabAName, tabBName = "Name", "Duration"
                        else
                            tabAName, tabBName = "Charges", "Cooldowns"
                        end

                        local data
                        if isActionBar() then
                            data = { sectionTitle = "", tabAText = "Charges", tabBText = "Cooldowns", tabCText = "Hotkey", tabDText = "Macro Name" }
                        else
                            data = { sectionTitle = "", tabAText = tabAName, tabBText = tabBName }
                            if component and component.id == "trackedBars" then
                                data.tabCText = "Stacks"
                            end
                        end

                        data.build = function(frame)
                            local yA = { y = -50 }
                            local yB = { y = -50 }
                            local yC = { y = -50 }
                            local yD = { y = -50 }
                            local db = component.db
                            local function applyText()
                                addon:ApplyStyles()
                            end
                            local function fontOptions()
                                return addon.BuildFontOptionsContainer()
                            end

                            local labelA_Font, labelA_Size, labelA_Style, labelA_Color, labelA_OffsetX, labelA_OffsetY
                            if component and (component.id == "trackedBuffs" or component.id == "buffs" or component.id == "debuffs") then
                                labelA_Font, labelA_Size, labelA_Style, labelA_Color, labelA_OffsetX, labelA_OffsetY = "Stacks Font", "Stacks Font Size", "Stacks Style", "Stacks Color", "Stacks Offset X", "Stacks Offset Y"
                            elseif component and component.id == "trackedBars" then
                                labelA_Font, labelA_Size, labelA_Style, labelA_Color, labelA_OffsetX, labelA_OffsetY = "Name Font", "Name Font Size", "Name Style", "Name Color", "Name Offset X", "Name Offset Y"
                            else
                                labelA_Font, labelA_Size, labelA_Style, labelA_Color, labelA_OffsetX, labelA_OffsetY = "Charges Font", "Charges Font Size", "Charges Style", "Charges Color", "Charges Offset X", "Charges Offset Y"
                            end

                            addDropdown(frame.PageA, labelA_Font, fontOptions,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textName and db.textName.fontFace) or "FRIZQT__"
                                    elseif component and component.id == "trackedBuffs" then
                                        return (db.textStacks and db.textStacks.fontFace) or "FRIZQT__"
                                    else
                                        return (db.textStacks and db.textStacks.fontFace) or "FRIZQT__"
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.fontFace = v
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.fontFace = v
                                    end
                                    applyText()
                                end,
                                yA)
                            addSlider(frame.PageA, labelA_Size, 6, 32, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textName and db.textName.size) or 14
                                    else
                                        return (db.textStacks and db.textStacks.size) or 16
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.size = tonumber(v) or 14
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.size = tonumber(v) or 16
                                    end
                                    applyText()
                                end,
                                yA)
                            addStyle(frame.PageA, labelA_Style,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textName and db.textName.style) or "OUTLINE"
                                    else
                                        return (db.textStacks and db.textStacks.style) or "OUTLINE"
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.style = v
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.style = v
                                    end
                                    applyText()
                                end,
                                yA)
                            addColor(frame.PageA, labelA_Color, true,
                                function()
                                    local c
                                    if component and component.id == "trackedBars" then
                                        c = (db.textName and db.textName.color) or {1,1,1,1}
                                    else
                                        c = (db.textStacks and db.textStacks.color) or {1,1,1,1}
                                    end
                                    return c[1], c[2], c[3], c[4]
                                end,
                                function(r,g,b,a)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.color = { r, g, b, a }
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.color = { r, g, b, a }
                                    end
                                    applyText()
                                end,
                                yA)
                            addSlider(frame.PageA, labelA_OffsetX, -50, 50, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textName and db.textName.offset and db.textName.offset.x) or 0
                                    else
                                        return (db.textStacks and db.textStacks.offset and db.textStacks.offset.x) or 0
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.offset = db.textName.offset or {}
                                        db.textName.offset.x = tonumber(v) or 0
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.offset = db.textStacks.offset or {}
                                        db.textStacks.offset.x = tonumber(v) or 0
                                    end
                                    applyText()
                                end,
                                yA)
                            addSlider(frame.PageA, labelA_OffsetY, -50, 50, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textName and db.textName.offset and db.textName.offset.y) or 0
                                    else
                                        return (db.textStacks and db.textStacks.offset and db.textStacks.offset.y) or 0
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.offset = db.textName.offset or {}
                                        db.textName.offset.y = tonumber(v) or 0
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.offset = db.textStacks.offset or {}
                                        db.textStacks.offset.y = tonumber(v) or 0
                                    end
                                    applyText()
                                end,
                                yA)

                            local isDurationTab = component and (component.id == "trackedBars" or component.id == "buffs" or component.id == "debuffs")
                            local textBKey = isDurationTab and "textDuration" or "textCooldown"
                            local labelBBase = isDurationTab and "Duration" or "Cooldown"
                            local labelB_Font = labelBBase .. " Font"
                            local labelB_Size = labelBBase .. " Font Size"
                            local labelB_Style = labelBBase .. " Style"
                            local labelB_Color = labelBBase .. " Color"
                            local labelB_OffsetX = labelBBase .. " Offset X"
                            local labelB_OffsetY = labelBBase .. " Offset Y"
                            local defaultBSize = (component and component.id == "trackedBars") and 14 or 16

                            addDropdown(frame.PageB, labelB_Font, fontOptions,
                                function()
                                    local cfg = db[textBKey]
                                    return (cfg and cfg.fontFace) or "FRIZQT__"
                                end,
                                function(v)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].fontFace = v
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_Size, 6, 32, 1,
                                function()
                                    local cfg = db[textBKey]
                                    return (cfg and cfg.size) or defaultBSize
                                end,
                                function(v)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].size = tonumber(v) or defaultBSize
                                    applyText()
                                end,
                                yB)
                            addStyle(frame.PageB, labelB_Style,
                                function()
                                    local cfg = db[textBKey]
                                    return (cfg and cfg.style) or "OUTLINE"
                                end,
                                function(v)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].style = v
                                    applyText()
                                end,
                                yB)
                            addColor(frame.PageB, labelB_Color, true,
                                function()
                                    local cfg = db[textBKey]
                                    local c = (cfg and cfg.color) or {1,1,1,1}
                                    return c[1], c[2], c[3], c[4]
                                end,
                                function(r,g,b,a)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].color = { r, g, b, a }
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_OffsetX, -50, 50, 1,
                                function()
                                    local cfg = db[textBKey]
                                    return (cfg and cfg.offset and cfg.offset.x) or 0
                                end,
                                function(v)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].offset = db[textBKey].offset or {}
                                    db[textBKey].offset.x = tonumber(v) or 0
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_OffsetY, -50, 50, 1,
                                function()
                                    local cfg = db[textBKey]
                                    return (cfg and cfg.offset and cfg.offset.y) or 0
                                end,
                                function(v)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].offset = db[textBKey].offset or {}
                                    db[textBKey].offset.y = tonumber(v) or 0
                                    applyText()
                                end,
                                yB)

                            if component and component.id == "trackedBars" then
                                local labelC_Font = "Stacks Font"
                                local labelC_Size = "Stacks Font Size"
                                local labelC_Style = "Stacks Style"
                                local labelC_Color = "Stacks Color"
                                local labelC_OffsetX = "Stacks Offset X"
                                local labelC_OffsetY = "Stacks Offset Y"

                                addDropdown(frame.PageC, labelC_Font, fontOptions,
                                    function()
                                        return (db.textStacks and db.textStacks.fontFace) or "FRIZQT__"
                                    end,
                                    function(v)
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.fontFace = v
                                        applyText()
                                    end,
                                    yC)
                                addSlider(frame.PageC, labelC_Size, 6, 32, 1,
                                    function()
                                        return (db.textStacks and db.textStacks.size) or 14
                                    end,
                                    function(v)
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.size = tonumber(v) or 14
                                        applyText()
                                    end,
                                    yC)
                                addStyle(frame.PageC, labelC_Style,
                                    function()
                                        return (db.textStacks and db.textStacks.style) or "OUTLINE"
                                    end,
                                    function(v)
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.style = v
                                        applyText()
                                    end,
                                    yC)
                                addColor(frame.PageC, labelC_Color, true,
                                    function()
                                        local c = (db.textStacks and db.textStacks.color) or {1,1,1,1}
                                        return c[1], c[2], c[3], c[4]
                                    end,
                                    function(r, g, b, a)
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.color = { r, g, b, a }
                                        applyText()
                                    end,
                                    yC)
                                addSlider(frame.PageC, labelC_OffsetX, -50, 50, 1,
                                    function()
                                        return (db.textStacks and db.textStacks.offset and db.textStacks.offset.x) or 0
                                    end,
                                    function(v)
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.offset = db.textStacks.offset or {}
                                        db.textStacks.offset.x = tonumber(v) or 0
                                        applyText()
                                    end,
                                    yC)
                                addSlider(frame.PageC, labelC_OffsetY, -50, 50, 1,
                                    function()
                                        return (db.textStacks and db.textStacks.offset and db.textStacks.offset.y) or 0
                                    end,
                                    function(v)
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.offset = db.textStacks.offset or {}
                                        db.textStacks.offset.y = tonumber(v) or 0
                                        applyText()
                                    end,
                                    yC)
                            end

                            -- Action Bars only: Page C (Hotkey) and Page D (Macro Name)
                            if isActionBar() then
                                -- Hotkey
                                do
                                    local setting = CreateLocalSetting("Hide Hotkey", "boolean",
                                        function() return not not db.textHotkeyHidden end,
                                        function(v) db.textHotkeyHidden = not not v; applyText() end,
                                        db.textHotkeyHidden)
                                    local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Hotkey", setting = setting, options = {} })
                                    local f = CreateFrame("Frame", nil, frame.PageC, "SettingsCheckboxControlTemplate")
                                    f.GetElementData = function() return initCb end
                                    f:SetPoint("TOPLEFT", 4, yC.y)
                                    f:SetPoint("TOPRIGHT", -16, yC.y)
                                    initCb:InitFrame(f)
                                -- Theme the label: Roboto + white (override Blizzard yellow)
                                if panel and panel.ApplyRobotoWhite then
                                    if f.Text then panel.ApplyRobotoWhite(f.Text) end
                                    local cb = f.Checkbox or f.CheckBox or (f.Control and f.Control.Checkbox)
                                    if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
                                    -- Theme the checkbox checkmark to green
                                    if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
                                end
                                    yC.y = yC.y - 34
                                end
                                addDropdown(frame.PageC, "Hotkey Font", fontOptions,
                                    function() return (db.textHotkey and db.textHotkey.fontFace) or "FRIZQT__" end,
                                    function(v) db.textHotkey = db.textHotkey or {}; db.textHotkey.fontFace = v; applyText() end,
                                    yC)
                                addSlider(frame.PageC, "Hotkey Font Size", 6, 32, 1,
                                    function() return (db.textHotkey and db.textHotkey.size) or 14 end,
                                    function(v) db.textHotkey = db.textHotkey or {}; db.textHotkey.size = tonumber(v) or 14; applyText() end,
                                    yC)
                                addStyle(frame.PageC, "Hotkey Style",
                                    function() return (db.textHotkey and db.textHotkey.style) or "OUTLINE" end,
                                    function(v) db.textHotkey = db.textHotkey or {}; db.textHotkey.style = v; applyText() end,
                                    yC)
                                addColor(frame.PageC, "Hotkey Color", true,
                                    function() local c = (db.textHotkey and db.textHotkey.color) or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
                                    function(r,g,b,a) db.textHotkey = db.textHotkey or {}; db.textHotkey.color = {r,g,b,a}; applyText() end,
                                    yC)
                                addSlider(frame.PageC, "Hotkey Offset X", -50, 50, 1,
                                    function() return (db.textHotkey and db.textHotkey.offset and db.textHotkey.offset.x) or 0 end,
                                    function(v) db.textHotkey = db.textHotkey or {}; db.textHotkey.offset = db.textHotkey.offset or {}; db.textHotkey.offset.x = tonumber(v) or 0; applyText() end,
                                    yC)
                                addSlider(frame.PageC, "Hotkey Offset Y", -50, 50, 1,
                                    function() return (db.textHotkey and db.textHotkey.offset and db.textHotkey.offset.y) or 0 end,
                                    function(v) db.textHotkey = db.textHotkey or {}; db.textHotkey.offset = db.textHotkey.offset or {}; db.textHotkey.offset.y = tonumber(v) or 0; applyText() end,
                                    yC)

                                -- Macro Name
                                do
                                    local setting = CreateLocalSetting("Hide Macro Name", "boolean",
                                        function() return not not db.textMacroHidden end,
                                        function(v) db.textMacroHidden = not not v; applyText() end,
                                        db.textMacroHidden)
                                    local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Macro Name", setting = setting, options = {} })
                                    local f = CreateFrame("Frame", nil, frame.PageD, "SettingsCheckboxControlTemplate")
                                    f.GetElementData = function() return initCb end
                                    f:SetPoint("TOPLEFT", 4, yD.y)
                                    f:SetPoint("TOPRIGHT", -16, yD.y)
                                    initCb:InitFrame(f)
                                -- Theme the label: Roboto + white (override Blizzard yellow)
                                if panel and panel.ApplyRobotoWhite then
                                    if f.Text then panel.ApplyRobotoWhite(f.Text) end
                                    local cb = f.Checkbox or f.CheckBox or (f.Control and f.Control.Checkbox)
                                    if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
                                    -- Theme the checkbox checkmark to green
                                    if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
                                end
                                    yD.y = yD.y - 34
                                end
                                addDropdown(frame.PageD, "Macro Name Font", fontOptions,
                                    function() return (db.textMacro and db.textMacro.fontFace) or "FRIZQT__" end,
                                    function(v) db.textMacro = db.textMacro or {}; db.textMacro.fontFace = v; applyText() end,
                                    yD)
                                addSlider(frame.PageD, "Macro Name Font Size", 6, 32, 1,
                                    function() return (db.textMacro and db.textMacro.size) or 14 end,
                                    function(v) db.textMacro = db.textMacro or {}; db.textMacro.size = tonumber(v) or 14; applyText() end,
                                    yD)
                                addStyle(frame.PageD, "Macro Name Style",
                                    function() return (db.textMacro and db.textMacro.style) or "OUTLINE" end,
                                    function(v) db.textMacro = db.textMacro or {}; db.textMacro.style = v; applyText() end,
                                    yD)
                                addColor(frame.PageD, "Macro Name Color", true,
                                    function() local c = (db.textMacro and db.textMacro.color) or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
                                    function(r,g,b,a) db.textMacro = db.textMacro or {}; db.textMacro.color = {r,g,b,a}; applyText() end,
                                    yD)
                                addSlider(frame.PageD, "Macro Name Offset X", -50, 50, 1,
                                    function() return (db.textMacro and db.textMacro.offset and db.textMacro.offset.x) or 0 end,
                                    function(v) db.textMacro = db.textMacro or {}; db.textMacro.offset = db.textMacro.offset or {}; db.textMacro.offset.x = tonumber(v) or 0; applyText() end,
                                    yD)
                                addSlider(frame.PageD, "Macro Name Offset Y", -50, 50, 1,
                                    function() return (db.textMacro and db.textMacro.offset and db.textMacro.offset.y) or 0 end,
                                    function(v) db.textMacro = db.textMacro or {}; db.textMacro.offset = db.textMacro.offset or {}; db.textMacro.offset.y = tonumber(v) or 0; applyText() end,
                                    yD)
                            end
                        end
                        local initializer = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
                        -- Increased extent to accommodate up to 7 rows on Hotkey/Macro pages
                        initializer.GetExtent = function() return 315 end
                        initializer:AddShownPredicate(function()
                            return panel:IsSectionExpanded(component.id, "Text")
                        end)
                        table.insert(init, initializer)
                    end
                elseif sectionName == "Style" and component and (component.id == "prdHealth" or component.id == "prdPower") then
                    local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                        name = "Style",
                        sectionKey = "Style",
                        componentId = component.id,
                        expanded = panel:IsSectionExpanded(component.id, "Style"),
                    })
                    expInitializer.GetExtent = function()
                        return 30
                    end
                    table.insert(init, expInitializer)

                    local initializer = createPRDStyleInitializer(component)
                    initializer:AddShownPredicate(function()
                        return panel:IsSectionExpanded(component.id, "Style")
                    end)
                    table.insert(init, initializer)
                elseif sectionName == "Border" and component and (component.id == "prdHealth" or component.id == "prdPower") then
                    -- PRD Health/Power use a custom Border block (Style dropdown,
                    -- Tint checkbox+swatch, Thickness slider) built as three
                    -- independent rows. This avoids ScrollBox clipping issues and
                    -- ensures consistent behavior with other settings.
                    local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                        name = "Border",
                        sectionKey = "Border",
                        componentId = component.id,
                        expanded = panel:IsSectionExpanded(component.id, "Border"),
                    })
                    expInitializer.GetExtent = function()
                        return 30
                    end
                    table.insert(init, expInitializer)

                    local componentSettings = component.settings or {}
                    local db = component.db or {}

                    local function readValue(key, fallback)
                        local value = db[key]
                        if value == nil then
                            local setting = componentSettings[key]
                            if setting and setting.default ~= nil then
                                value = setting.default
                            end
                        end
                        if value == nil then
                            value = fallback
                        end
                        if type(value) == "table" then
                            value = CopyTable(value)
                        end
                        return value
                    end

                    local function writeValue(key, value, fallback)
                        if not component.db then
                            return
                        end
                        if type(value) == "table" then
                            component.db[key] = CopyTable(value)
                        else
                            if value == nil then
                                component.db[key] = fallback
                            else
                                component.db[key] = value
                            end
                        end
                    end

                    -- Border Style dropdown
                    local styleOptionsProvider
                    if componentSettings.borderStyle and componentSettings.borderStyle.ui then
                        styleOptionsProvider = componentSettings.borderStyle.ui.optionsProvider
                    end
                    styleOptionsProvider = styleOptionsProvider or function()
                        if addon.BuildBarBorderOptionsContainer then
                            return addon.BuildBarBorderOptionsContainer()
                        end
                        return {}
                    end

                    local borderStyleSetting = CreateLocalSetting("Border Style", "string",
                        function() return readValue("borderStyle", "square") or "square" end,
                        function(v)
                            writeValue("borderStyle", v or "square", "square")
                            if addon and addon.ApplyStyles then addon:ApplyStyles() end
                        end,
                        readValue("borderStyle", "square") or "square"
                    )
                    local borderStyleInit = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                        name = "Border Style",
                        setting = borderStyleSetting,
                        options = styleOptionsProvider,
                    })
                    -- Apply ScooterMod theming to the Border Style row so it
                    -- never falls back to Blizzard's stock font/colors.
                    do
                        local baseInit = borderStyleInit.InitFrame
                        borderStyleInit.InitFrame = function(self, frame)
                            if baseInit then baseInit(self, frame) end
                            if panel and panel.ApplyControlTheme then
                                panel.ApplyControlTheme(frame)
                            end
                            if panel and panel.ApplyRobotoWhite then
                                local lbl = frame.Text or frame.Label
                                if lbl then panel.ApplyRobotoWhite(lbl) end
                            end
                        end
                    end
                    borderStyleInit:AddShownPredicate(function()
                        return panel:IsSectionExpanded(component.id, "Border")
                    end)
                    table.insert(init, borderStyleInit)

                    -- Border Tint checkbox + swatch
                    -- NOTE: getTintColor returns a TABLE {r,g,b,a} to match
                    -- CreateCheckboxWithSwatchInitializer's expected interface.
                    local function getTintColor()
                        local tint = readValue("borderTintColor", {1, 1, 1, 1}) or {1, 1, 1, 1}
                        return { tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1 }
                    end

                    local tintSetting = CreateLocalSetting("Border Tint", "boolean",
                        function() return not not readValue("borderTintEnable", false) end,
                        function(v)
                            writeValue("borderTintEnable", not not v, false)
                            if addon and addon.ApplyStyles then addon:ApplyStyles() end
                        end,
                        readValue("borderTintEnable", false)
                    )
                    local tintInit = CreateCheckboxWithSwatchInitializer(
                        tintSetting,
                        "Border Tint",
                        getTintColor,
                        function(r, g, b, a)
                            writeValue("borderTintColor", {r or 1, g or 1, b or 1, a or 1}, {1, 1, 1, 1})
                            if addon and addon.ApplyStyles then addon:ApplyStyles() end
                        end,
                        8
                    )
                    -- Ensure PRD Border Tint row always uses ScooterMod theming
                    -- and that the swatch reliably opens the color picker even
                    -- if other wrappers interfere.
                    do
                        local baseInit = tintInit.InitFrame
                        tintInit.InitFrame = function(self, frame)
                            if baseInit then baseInit(self, frame) end

                            if panel and panel.ApplyControlTheme then
                                panel.ApplyControlTheme(frame)
                            end
                            if panel and panel.ApplyRobotoWhite then
                                local cb = frame.Checkbox or frame.CheckBox or frame.Control
                                if cb and cb.Text then
                                    panel.ApplyRobotoWhite(cb.Text)
                                end
                                if frame.Text then
                                    panel.ApplyRobotoWhite(frame.Text)
                                end
                            end

                            local swatch = frame.ScooterInlineSwatch
                            if swatch then
                                -- Ensure mouse is enabled and swatch is above other elements
                                swatch:EnableMouse(true)
                                swatch:SetFrameStrata("DIALOG")
                                swatch:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)

                                -- Replace any prior OnClick with a direct call
                                -- into the Blizzard color picker; this mirrors
                                -- the shared helper but keeps PRD isolated
                                -- from recycled-row edge cases.
                                swatch:SetScript("OnClick", function()
                                    local c = getTintColor()
                                    ColorPickerFrame:SetupColorPickerAndShow({
                                        r = c[1] or 1,
                                        g = c[2] or 1,
                                        b = c[3] or 1,
                                        hasOpacity = true,
                                        opacity = c[4] or 1,
                                        swatchFunc = function()
                                            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                                            local na = ColorPickerFrame:GetColorAlpha()
                                            writeValue("borderTintColor", {nr or 1, ng or 1, nb or 1, na or 1}, {1, 1, 1, 1})
                                            if addon and addon.ApplyStyles then addon:ApplyStyles() end
                                            if swatch.Color then
                                                swatch.Color:SetColorTexture(nr or 1, ng or 1, nb or 1, 1)
                                            end
                                        end,
                                        cancelFunc = function(prev)
                                            if not prev then return end
                                            local pr = prev.r or 1
                                            local pg = prev.g or 1
                                            local pb = prev.b or 1
                                            local pa = prev.a or 1
                                            writeValue("borderTintColor", {pr, pg, pb, pa}, {1, 1, 1, 1})
                                            if addon and addon.ApplyStyles then addon:ApplyStyles() end
                                            if swatch.Color then
                                                swatch.Color:SetColorTexture(pr, pg, pb, 1)
                                            end
                                        end,
                                    })
                                end)

                                -- Ensure initial visibility matches checkbox state
                                local isChecked = tintSetting:GetValue()
                                swatch:SetShown(isChecked and true or false)
                            end

                            -- Wire up checkbox to toggle swatch visibility directly
                            local cb = frame.Checkbox or frame.CheckBox or frame.Control
                            if cb and frame.ScooterInlineSwatch then
                                local swatchRef = frame.ScooterInlineSwatch
                                if not cb._prdBorderTintHooked then
                                    cb:HookScript("OnClick", function(button)
                                        local checked = button:GetChecked()
                                        swatchRef:SetShown(checked and true or false)
                                    end)
                                    cb._prdBorderTintHooked = true
                                end
                            end
                        end
                    end
                    tintInit:AddShownPredicate(function()
                        return panel:IsSectionExpanded(component.id, "Border")
                    end)
                    table.insert(init, tintInit)

                    -- Border Thickness slider
                    local thicknessSetting = CreateLocalSetting("Border Thickness", "number",
                        function() return readValue("borderThickness", 1) or 1 end,
                        function(v)
                            local nv = tonumber(v) or 1
                            if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
                            writeValue("borderThickness", nv, 1)
                            if addon and addon.ApplyStyles then addon:ApplyStyles() end
                        end,
                        readValue("borderThickness", 1) or 1
                    )
                    local thicknessOptions = Settings.CreateSliderOptions(1, 8, 0.2)
                    thicknessOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
                        return string.format("%.1f", value)
                    end)
                    local thicknessInit = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
                        name = "Border Thickness",
                        setting = thicknessSetting,
                        options = thicknessOptions,
                    })
                    -- The thickness slider must always adopt ScooterMod theming
                    -- (white Roboto label, consistent slider chrome).
                    do
                        local baseInit = thicknessInit.InitFrame
                        thicknessInit.InitFrame = function(self, frame)
                            if baseInit then baseInit(self, frame) end
                            if panel and panel.ApplyControlTheme then
                                panel.ApplyControlTheme(frame)
                            end
                            if panel and panel.ApplyRobotoWhite and frame.Text then
                                panel.ApplyRobotoWhite(frame.Text)
                            end
                        end
                    end
                    thicknessInit:AddShownPredicate(function()
                        return panel:IsSectionExpanded(component.id, "Border")
                    end)
                    table.insert(init, thicknessInit)
                elseif sectionName == "Style" and component and component.id == "trackedBars" then
                    local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                        name = "Style",
                        sectionKey = "Style",
                        componentId = component.id,
                        expanded = panel:IsSectionExpanded(component.id, "Style"),
                    })
                    expInitializer.GetExtent = function() return 30 end
                    table.insert(init, expInitializer)

                    local data = { sectionTitle = "", tabAText = "Foreground", tabBText = "Background" }
                    data.build = function(frame)
                        local yA = { y = -50 }
                        local yB = { y = -50 }
                        local db = component.db
                        local function refresh()
                            addon:ApplyStyles()
                        end
                        do
                            local row = frame.EnableCustomTexturesRow
                            if not row then
                                row = CreateFrame("Frame", nil, frame, "SettingsCheckboxControlTemplate")
                                row:SetPoint("TOPLEFT", 4, 0)
                                row:SetPoint("TOPRIGHT", -16, 0)
                                row:SetHeight(26)
                                frame.EnableCustomTexturesRow = row
                            end
                            -- Ensure row is visible when this section uses it and does not block tabs
                            row:Show()
                            if row.SetFrameLevel then row:SetFrameLevel((frame:GetFrameLevel() or 1)) end
                            if row.EnableMouse then row:EnableMouse(false) end
                            if row.Checkbox then
                                row.Checkbox:EnableMouse(true)
                                -- Do not extend hit rect into the tab area
                                if row.Checkbox.SetHitRectInsets then row.Checkbox:SetHitRectInsets(0, 0, 0, 0) end
                            end
                            if row.Text then
                                row.Text:SetText("Use Custom Textures")
                                if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(row.Text) end
                            end
                            local checkbox = row.Checkbox
                            if checkbox then
                                checkbox:SetChecked(db.styleEnableCustom ~= false)
                                -- Add info icon next to the checkbox explaining why custom textures remove Blizzard border
                                if panel and panel.CreateInfoIcon and not row.ScooterInfoIcon then
                                    local tooltipText = "Blizzard's Tracked Bar border is tied to the bar texture, so enabling custom textures also removes the default border. This is necessary because the border and texture cannot be separated."
                                    row.ScooterInfoIcon = panel.CreateInfoIcon(row, tooltipText, "LEFT", "RIGHT", 10, 0, 32)
                                    row.ScooterInfoIcon:ClearAllPoints()
                                    row.ScooterInfoIcon:SetPoint("LEFT", checkbox, "RIGHT", 10, 0)
                                    -- Tag this icon so it is not mistaken for other settings when rows are recycled
                                    row.ScooterInfoIcon._isTrackedBarsStyleIcon = true
                                    row.ScooterInfoIcon._ownerKey = "trackedBars_useCustomTextures"
                                end
                                checkbox.ScooterCustomTexturesDB = db
                                checkbox.ScooterCustomTexturesRefresh = refresh
                                if not checkbox.ScooterCustomTexturesHooked then
                                    checkbox:HookScript("OnClick", function(btn)
                                        local checked = btn:GetChecked() and true or false
                                        local targetDb = btn.ScooterCustomTexturesDB
                                        if targetDb then
                                            targetDb.styleEnableCustom = checked
                                            if not checked then
                                                targetDb.borderStyle = "square"
                                            end
                                        end
                                        if btn.ScooterCustomTexturesRefresh then
                                            btn.ScooterCustomTexturesRefresh()
                                        end
                                        if btn.ScooterUpdateStyleControlsState then
                                            btn.ScooterUpdateStyleControlsState()
                                        end
                                    end)
                                    checkbox.ScooterCustomTexturesHooked = true
                                end
                            end
                        end
                        local function addDropdown(parent, label, optsProvider, getFunc, setFunc, yRef)
                            local setting = CreateLocalSetting(label, "string", getFunc, setFunc, getFunc())
                            local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = label, setting = setting, options = optsProvider })
                            local f = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
                            f.GetElementData = function() return initDrop end
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            initDrop:InitFrame(f)
                            if panel and panel.ApplyRobotoWhite then
                                local lbl = f and (f.Text or f.Label)
                                if lbl then panel.ApplyRobotoWhite(lbl) end
                            end
                            if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
                            if addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(f.Control, setting) end
                            yRef.y = yRef.y - 34
                            return f
                        end
                        local function addColor(parent, label, hasAlpha, getFunc, setFunc, yRef)
                            local f = CreateFrame("Frame", nil, parent, "SettingsListElementTemplate")
                            f:SetHeight(26)
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            f.Text:SetText(label)
                            if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
                            local right = CreateFrame("Frame", nil, f)
                            right:SetSize(250, 26)
                            right:SetPoint("RIGHT", f, "RIGHT", -16, 0)
                            f.Text:ClearAllPoints()
                            f.Text:SetPoint("LEFT", f, "LEFT", 36.5, 0)
                            f.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
                            f.Text:SetJustifyH("LEFT")
                            -- Use centralized color swatch factory with refresh callback
                            local function getColorTable()
                                local r, g, b, a = getFunc()
                                return {r or 1, g or 1, b or 1, a or 1}
                            end
                            local function setColorTable(r, g, b, a)
                                setFunc(r, g, b, a)
                                refresh()
                            end
                            local swatch = CreateColorSwatch(right, getColorTable, setColorTable, hasAlpha)
                            swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                            yRef.y = yRef.y - 34
                            return f, swatch
                        end
                        local function addSlider(parent, label, minV, maxV, step, getFunc, setFunc, yRef)
                            local options = Settings.CreateSliderOptions(minV, maxV, step)
                            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
                            local setting = CreateLocalSetting(label, "number", getFunc, function(v) setFunc(v); refresh() end, getFunc())
                            local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
                            local f = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
                            f.GetElementData = function() return initSlider end
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            initSlider:InitFrame(f)
                            if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(f) end
                            if panel and panel.ApplyRobotoWhite and f.Text then panel.ApplyRobotoWhite(f.Text) end
                            yRef.y = yRef.y - 48
                            return f
                        end
                        -- Store references to all controls for enable/disable
                        local styleControls = {}
                        local fgTexDropdown = addDropdown(frame.PageA, "Foreground Texture", function()
                            -- Remove "default" option - only show custom textures
                            local allOptions = addon.BuildBarTextureOptionsContainer and addon.BuildBarTextureOptionsContainer() or {}
                            local filteredOptions = {}
                            for _, option in ipairs(allOptions) do
                                if option.value ~= "default" then
                                    table.insert(filteredOptions, option)
                                end
                            end
                            return filteredOptions
                        end,
                            function() return db.styleForegroundTexture or (component.settings.styleForegroundTexture and component.settings.styleForegroundTexture.default) end,
                            function(v) db.styleForegroundTexture = v; refresh() end, yA)
                        table.insert(styleControls, fgTexDropdown)
                        -- Foreground Color (dropdown + inline swatch)
                        local function fgColorOpts()
                            local container = Settings.CreateControlTextContainer()
                            container:Add("default", "Default")
                            container:Add("texture", "Texture Original")
                            container:Add("custom", "Custom")
                            return container:GetData()
                        end
                        local function getFgColorMode() return db.styleForegroundColorMode or "default" end
                        local function setFgColorMode(v)
                            db.styleForegroundColorMode = v or "default"
                            refresh()
                        end
                        local function getFgTintTbl()
                            local c = db.styleForegroundTint or {1,1,1,1}
                            return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
                        end
                        local function setFgTintTbl(r,g,b,a)
                            db.styleForegroundTint = {r or 1, g or 1, b or 1, a or 1}
                            refresh()
                        end
                        panel.DropdownWithInlineSwatch(frame.PageA, yA, {
                            label = "Foreground Color",
                            getMode = getFgColorMode,
                            setMode = setFgColorMode,
                            getColor = getFgTintTbl,
                            setColor = setFgTintTbl,
                            options = fgColorOpts,
                            insideButton = true,
                        })
                        local bgTexDropdown = addDropdown(frame.PageB, "Background Texture", addon.BuildBarTextureOptionsContainer,
                            function() return db.styleBackgroundTexture or (component.settings.styleBackgroundTexture and component.settings.styleBackgroundTexture.default) end,
                            function(v) db.styleBackgroundTexture = v; refresh() end, yB)
                        table.insert(styleControls, bgTexDropdown)
                        -- Background Color (dropdown + inline swatch)
                        local function bgColorOpts()
                            local container = Settings.CreateControlTextContainer()
                            container:Add("default", "Default")
                            container:Add("texture", "Texture Original")
                            container:Add("custom", "Custom")
                            return container:GetData()
                        end
                        local function getBgColorMode() return db.styleBackgroundColorMode or "default" end
                        local function setBgColorMode(v)
                            db.styleBackgroundColorMode = v or "default"
                            refresh()
                        end
                        local function getBgTintTbl()
                            local c = db.styleBackgroundTint or {0,0,0,1}
                            return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
                        end
                        local function setBgTintTbl(r,g,b,a)
                            db.styleBackgroundTint = {r or 0, g or 0, b or 0, a or 1}
                            refresh()
                        end
                        panel.DropdownWithInlineSwatch(frame.PageB, yB, {
                            label = "Background Color",
                            getMode = getBgColorMode,
                            setMode = setBgColorMode,
                            getColor = getBgTintTbl,
                            setColor = setBgTintTbl,
                            options = bgColorOpts,
                            insideButton = true,
                        })
                        local bgOpacitySlider = addSlider(frame.PageB, "Background Opacity", 0, 100, 1,
                            function() return db.styleBackgroundOpacity or (component.settings.styleBackgroundOpacity and component.settings.styleBackgroundOpacity.default) or 50 end,
                            function(v) db.styleBackgroundOpacity = tonumber(v) or 50 end, yB)
                        table.insert(styleControls, bgOpacitySlider)
                        
                        -- Function to enable/disable all style controls
                        local function updateStyleControlsState()
                            local enabled = db.styleEnableCustom ~= false
                            for _, control in ipairs(styleControls) do
                                if control then
                                    -- Gray out labels
                                    if control.Text then
                                        local alpha = enabled and 1 or 0.5
                                        control.Text:SetTextColor(alpha, alpha, alpha)
                                    end
                                    -- Disable controls
                                    if control.SetEnabled then
                                        control:SetEnabled(enabled)
                                    elseif control.Disable and control.Enable then
                                        if enabled then control:Enable() else control:Disable() end
                                    end
                                    -- For dropdowns, disable the control
                                    if control.Control and control.Control.SetEnabled then
                                        control.Control:SetEnabled(enabled)
                                    end
                                    -- For sliders
                                    if control.Slider and control.Slider.SetEnabled then
                                        control.Slider:SetEnabled(enabled)
                                    end
                                end
                            end
                        end
                        
                        -- Update state initially
                        updateStyleControlsState()
                        
                        -- Hook checkbox to update state
                        if checkbox then
                            checkbox.ScooterUpdateStyleControlsState = updateStyleControlsState
                        end
                    end
                    local initializer = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
                    initializer.GetExtent = function() return 208 end
                    initializer:AddShownPredicate(function()
                        return panel:IsSectionExpanded(component.id, "Style")
                    end)
                    table.insert(init, initializer)
                elseif (sections[sectionName] and #sections[sectionName] > 0)
                    or (sectionName == "Border" and component and component.settings and component.settings.supportsEmptyBorderSection)
                    or (sectionName == "Misc" and component and component.supportsEmptyVisibilitySection)
                    or (sectionName == "Sizing" and component and component.supportsEmptySizingSection)
                    or (sectionName == "Style" and component and component.supportsEmptyStyleSection)
                then
                    local headerName = (sectionName == "Misc") and "Visibility" or sectionName

                    local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                        name = headerName,
                        sectionKey = sectionName,
                        componentId = component.id,
                        expanded = panel:IsSectionExpanded(component.id, sectionName),
                    })
                    expInitializer.GetExtent = function() return 30 end
                    -- Hook section expansion to refresh Border/Backdrop enabled state
                    local isCDMBorderCheck = (sectionName == "Border") and (
                        component.id == "essentialCooldowns" or 
                        component.id == "utilityCooldowns" or 
                        component.id == "trackedBuffs" or 
                        component.id == "buffs" or
                        component.id == "trackedBars" or
                        (type(component.id) == "string" and component.id:match("^actionBar%d$") ~= nil)
                    )
                    local isABBackdropCheck = (sectionName == "Backdrop") and (
                        type(component.id) == "string" and component.id:match("^actionBar%d$") ~= nil
                    )
                    if isCDMBorderCheck or isABBackdropCheck then
                        local baseInit = expInitializer.InitFrame
                        expInitializer.InitFrame = function(self, frame)
                            if baseInit then baseInit(self, frame) end
                            -- Refresh when section is expanded/collapsed
                            if frame and frame.ExpandButton then
                                local expandBtn = frame.ExpandButton
                                if expandBtn and not expandBtn._ScooterRefreshHooked then
                                    expandBtn:HookScript("OnClick", function()
                                        C_Timer.After(0.15, function()
                                            if borderRefreshFunc then borderRefreshFunc() end
                                            if backdropRefreshFunc then backdropRefreshFunc() end
                                        end)
                                    end)
                                    expandBtn._ScooterRefreshHooked = true
                                end
                            end
                        end
                    end
                    table.insert(init, expInitializer)

                    -- Track Border section controls for Cooldown Manager groups, Buffs, and Action Bars to enable graying out
                    local isCDMBorder = (sectionName == "Border") and (
                        component.id == "essentialCooldowns" or 
                        component.id == "utilityCooldowns" or 
                        component.id == "trackedBuffs" or 
                        component.id == "buffs" or
                        component.id == "trackedBars" or
                        (type(component.id) == "string" and component.id:match("^actionBar%d$") ~= nil)
                    )
                    local borderControls = {}
                    local function refreshBorderEnabledState()
                        if not isCDMBorder then return end
                        local enabled = component.db.borderEnable ~= false
                        for _, controlRef in ipairs(borderControls) do
                            if controlRef.frame then
                                local frame = controlRef.frame
                                -- Enable/disable the control
                                if controlRef.type == "slider" then
                                    if frame.Control and frame.Control.SetEnabled then
                                        frame.Control:SetEnabled(enabled)
                                    end
                                    if frame.SliderWithSteppers and frame.SliderWithSteppers.SetEnabled then
                                        frame.SliderWithSteppers:SetEnabled(enabled)
                                    end
                                elseif controlRef.type == "dropdown" then
                                    if frame.Control and frame.Control.SetEnabled then
                                        frame.Control:SetEnabled(enabled)
                                    end
                                elseif controlRef.type == "checkbox" then
                                    local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox) or frame.Control
                                    if cb and cb.SetEnabled then
                                        cb:SetEnabled(enabled)
                                    end
                                    if frame.ScooterInlineSwatch and frame.ScooterInlineSwatch.EnableMouse then
                                        frame.ScooterInlineSwatch:EnableMouse(enabled)
                                    end
                                end
                                -- Gray out labels
                                local lbl = frame.Text or frame.Label
                                if not lbl and frame.GetRegions then
                                    local regions = { frame:GetRegions() }
                                    for i = 1, #regions do
                                        local r = regions[i]
                                        if r and r.IsObjectType and r:IsObjectType("FontString") then
                                            lbl = r; break
                                        end
                                    end
                                end
                                if lbl and lbl.SetTextColor then
                                    lbl:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1)
                                end
                            end
                        end
                    end

                    -- Track Backdrop section controls for Action Bars to enable graying out when backdropDisable is checked
                    local isABBackdrop = (sectionName == "Backdrop") and (
                        type(component.id) == "string" and component.id:match("^actionBar%d$") ~= nil
                    )
                    local backdropControls = {}
                    local function refreshBackdropEnabledState()
                        if not isABBackdrop then return end
                        local enabled = not component.db.backdropDisable
                        for _, controlRef in ipairs(backdropControls) do
                            if controlRef.frame then
                                local frame = controlRef.frame
                                -- Enable/disable the control
                                if controlRef.type == "slider" then
                                    if frame.Control and frame.Control.SetEnabled then
                                        frame.Control:SetEnabled(enabled)
                                    end
                                    if frame.SliderWithSteppers and frame.SliderWithSteppers.SetEnabled then
                                        frame.SliderWithSteppers:SetEnabled(enabled)
                                    end
                                elseif controlRef.type == "dropdown" then
                                    if frame.Control and frame.Control.SetEnabled then
                                        frame.Control:SetEnabled(enabled)
                                    end
                                elseif controlRef.type == "checkbox" then
                                    local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox) or frame.Control
                                    if cb and cb.SetEnabled then
                                        cb:SetEnabled(enabled)
                                    end
                                    if frame.ScooterInlineSwatch and frame.ScooterInlineSwatch.EnableMouse then
                                        frame.ScooterInlineSwatch:EnableMouse(enabled)
                                    end
                                elseif controlRef.type == "color" then
                                    if frame.ScooterColorSwatch and frame.ScooterColorSwatch.EnableMouse then
                                        frame.ScooterColorSwatch:EnableMouse(enabled)
                                    end
                                    if frame.ScooterColorSwatch and frame.ScooterColorSwatch.SetAlpha then
                                        frame.ScooterColorSwatch:SetAlpha(enabled and 1 or 0.5)
                                    end
                                end
                                -- Gray out labels
                                local lbl = frame.Text or frame.Label
                                if not lbl and frame.GetRegions then
                                    local regions = { frame:GetRegions() }
                                    for i = 1, #regions do
                                        local r = regions[i]
                                        if r and r.IsObjectType and r:IsObjectType("FontString") then
                                            lbl = r; break
                                        end
                                    end
                                end
                                if lbl and lbl.SetTextColor then
                                    lbl:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1)
                                end
                            end
                        end
                    end

                    for _, item in ipairs(sections[sectionName] or {}) do
                        local settingId = item.id
                        local setting = item.setting
                        local ui = setting.ui
                        local label = ui.label
                        local values = ui.values

                        if ui.dynamicLabel and settingId == "columns" then
                            label = (component.db.orientation or "H") == "H" and "# Columns" or "# Rows"
                        end

                        if ui.dynamicValues and settingId == "iconWrap" then
                            local o = component.db.orientation or "H"
                            -- Aura Frame and default behavior:
                            --  - Horizontal: Wrap domain is Down/Up.
                            --  - Vertical:   Wrap domain is Left/Right.
                            if o == "H" then
                                values = { down = "Down", up = "Up" }
                            else
                                values = { left = "Left", right = "Right" }
                            end
                        end

                        if ui.dynamicValues and settingId == "direction" then
                            local o = component.db.orientation or "H"
                            -- Uniform behavior for Aura Frame, Cooldowns, and Action Bars:
                            --  - Horizontal: Left/Right
                            --  - Vertical:   Up/Down
                            if o == "H" then
                                values = { left = "Left", right = "Right" }
                            else
                                values = { up = "Up", down = "Down" }
                            end
                        end

                        if (sectionName == "Border" and settingId == "borderTintColor") or (sectionName == "Icon" and settingId == "iconBorderTintColor") then
                        else
                            local settingObj = CreateLocalSetting(label, ui.type or "string",
                                function()
                                    local v = component.db[settingId]
                                    if v == nil then v = setting.default end
                                    -- Normalize Aura Frame iconWrap numeric/enums back to string keys to avoid 'Custom'
                                    if settingId == "iconWrap" then
                                        if type(v) == "number" then
                                            local dirEnum = _G.Enum and _G.Enum.AuraFrameIconDirection
                                            if dirEnum and (v == dirEnum.Up or v == dirEnum.Down or v == dirEnum.Left or v == dirEnum.Right) then
                                                if v == dirEnum.Up then
                                                    v = "up"
                                                elseif v == dirEnum.Down then
                                                    v = "down"
                                                elseif v == dirEnum.Left then
                                                    v = "left"
                                                elseif v == dirEnum.Right then
                                                    v = "right"
                                                end
                                            else
                                                -- Fallback: treat as simple 0/1 index whose meaning depends on orientation.
                                                local o = component.db.orientation or "H"
                                                if o == "H" then
                                                    v = (v == 1) and "up" or "down"
                                                else
                                                    v = (v == 1) and "right" or "left"
                                                end
                                            end
                                        end
                                    end
                                    -- Direction handling:
                                    --  - For Aura Frame (Buffs/Debuffs), underlying values are Left/Right only; we
                                    --    relabel to Up/Down for vertical orientation in the UI. Normalize any
                                    --    legacy 'up'/'down' saved values back into Left/Right so the dropdown
                                    --    does not fall back to 'Custom'.
                                    --  - For Cooldown Viewer / Action Bars, keep orientation-aware coercion to
                                    --    avoid transient 'Custom'.
                                    if settingId == "direction" then
                                        if type(v) == "number" then
                                            local oNum = component.db.orientation or "H"
                                            if oNum == "H" then
                                                v = (v == 1) and "right" or "left"
                                            else
                                                v = (v == 1) and "up" or "down"
                                            end
                                        end
                                        
                                        local o = component.db.orientation or "H"
                                        if o == "H" then
                                            if v ~= "left" and v ~= "right" then v = "right" end
                                        else
                                            if v ~= "up" and v ~= "down" then v = "up" end
                                        end
                                    end
                                    return v
                                end,
                                function(v)
                                    local finalValue
                                    if ui.widget == "dropdown" then
                                        finalValue = v
                                    elseif ui.widget == "checkbox" then
                                        finalValue = not not v
                                    elseif ui.widget == "slider" then
                                        finalValue = tonumber(v) or 0
                                        if settingId == "iconSize" then
                                            if finalValue < (ui.min or 50) then finalValue = ui.min or 50 end
                                            if finalValue > (ui.max or 200) then finalValue = ui.max or 200 end
                                            finalValue = math.floor(finalValue / 10 + 0.5) * 10
                                        elseif settingId == "positionX" or settingId == "positionY" then
                                            finalValue = clampPositionValue(finalValue)
                                        else
                                            finalValue = math.floor(finalValue + 0.5)
                                            if settingId == "opacityOutOfCombat" or settingId == "opacityWithTarget" or settingId == "barOpacityOutOfCombat" or settingId == "barOpacityWithTarget" then
                                                if ui.min then finalValue = math.max(ui.min, finalValue) end
                                                if ui.max then finalValue = math.min(ui.max, finalValue) end
                                            end
                                        end
                                    else
                                        finalValue = tonumber(v) or v
                                    end

                                    local changed = component.db[settingId] ~= finalValue
                                    component.db[settingId] = finalValue

                                    if changed and (setting.type == "editmode" or settingId == "positionX" or settingId == "positionY") then
                                        local function safeSaveOnly()
                                            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
                                        end
                                        local function requestApply()
                                            if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
                                        end
                                        if settingId == "positionX" or settingId == "positionY" then
                                            -- Use position-only sync to avoid cascade of syncing all Edit Mode settings.
                                            -- The new SyncComponentPositionToEditMode handles Save/Apply internally,
                                            -- so we do NOT call safeSaveOnly()/requestApply() here to avoid double calls.
                                            if addon.EditMode and addon.EditMode.SyncComponentPositionToEditMode then
                                                -- Mark this as a recent position write so the back-sync layer
                                                -- can skip immediately re-writing the same offsets back into
                                                -- the DB. This prevents a second Settings row rebuild that
                                                -- would otherwise steal focus from the numeric text input.
                                                component._recentPositionWrite = component._recentPositionWrite or {}
                                                if type(GetTime) == "function" then
                                                    component._recentPositionWrite.time = GetTime()
                                                else
                                                    component._recentPositionWrite.time = nil
                                                end
                                                component._recentPositionWrite.x = component.db.positionX
                                                component._recentPositionWrite.y = component.db.positionY

                                                addon.EditMode.SyncComponentPositionToEditMode(component)
                                                -- NOTE: Do NOT call safeSaveOnly()/requestApply() here!
                                                -- SyncComponentPositionToEditMode handles Save/Apply internally.
                                            end
                                    elseif settingId == "opacity" then
                                            if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                            if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                                addon.EditMode.SyncComponentSettingToEditMode(component, "opacity")
                                                safeSaveOnly(); requestApply()
                                            end
                                        
                                    elseif settingId == "orientation" then
                                        local isAuraFrame = component and (component.id == "buffs" or component.id == "debuffs")

                                        if isAuraFrame then
                                            ------------------------------------------------------------------
                                            -- Aura Frame (Buffs/Debuffs):
                                            -- Mirror Blizzard's orientation remap logic in AceDB and then
                                            -- push the resulting Wrap/Direction into Edit Mode. We rely on
                                            -- our own DB as the source of truth instead of trying to read
                                            -- back mid-flight values from Edit Mode.
                                            ------------------------------------------------------------------
                                            -- Signal the back-sync layer to skip ONE immediate Aura Frame
                                            -- Wrap/Direction read so these freshly remapped values are not
                                            -- clobbered by a stale mid-flight snapshot.
                                            component._skipNextAuraBackSync = true

                                            local oldWrap = component.db.iconWrap or "down"
                                            local oldDir  = component.db.direction or "right"

                                            -- Ensure legacy/string oddities are normalized into the
                                            -- 'down'/'up'/'left'/'right' space before applying the remap.
                                            if oldWrap == "Up" then oldWrap = "up" end
                                            if oldWrap == "Down" then oldWrap = "down" end
                                            if oldWrap == "Left" then oldWrap = "left" end
                                            if oldWrap == "Right" then oldWrap = "right" end
                                            if oldDir == "Up" then oldDir = "up" end
                                            if oldDir == "Down" then oldDir = "down" end
                                            if oldDir == "Left" then oldDir = "left" end
                                            if oldDir == "Right" then oldDir = "right" end

                                            local newWrap = oldWrap
                                            local newDir  = oldDir
                                            local newOrientation = tostring(v)

                                            if newOrientation == "H" then
                                                -- Switching to Horizontal:
                                                --  - If oldWrap was Left/Right, it becomes the new Direction.
                                                --  - If oldDir  was Down/Up, it becomes the new Wrap.
                                                if oldWrap == "left" or oldWrap == "right" then
                                                    newDir = oldWrap
                                                end
                                                if oldDir == "down" or oldDir == "up" then
                                                    newWrap = oldDir
                                                end
                                            else
                                                -- Switching to Vertical:
                                                --  - If oldWrap was Down/Up, it becomes the new Direction.
                                                --  - If oldDir  was Left/Right, it becomes the new Wrap.
                                                if oldWrap == "down" or oldWrap == "up" then
                                                    newDir = oldWrap
                                                end
                                                if oldDir == "left" or oldDir == "right" then
                                                    newWrap = oldDir
                                                end
                                            end

                                            component.db.iconWrap  = newWrap
                                            component.db.direction = newDir

                                            if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                                -- Push the remapped values so Edit Mode matches our DB.
                                                addon.EditMode.SyncComponentSettingToEditMode(component, "iconWrap")
                                                addon.EditMode.SyncComponentSettingToEditMode(component, "direction")
                                            end
                                            if panel and panel.RefreshDynamicSettingWidgets then
                                                panel:RefreshDynamicSettingWidgets(component)
                                            end
                                        else
                                            -- Non-Aura systems: pre-adjust direction to a valid option for the
                                            -- new orientation BEFORE syncing, to avoid transient 'Custom'.
                                            do
                                                local newOrientation = tostring(v)
                                                local dir = component.db.direction or "right"
                                                if newOrientation == "H" then
                                                    if dir ~= "left" and dir ~= "right" then component.db.direction = "right" end
                                                else
                                                    if dir ~= "up" and dir ~= "down" then component.db.direction = "up" end
                                                end
                                                -- Also push direction immediately so Edit Mode reflects valid value during transition
                                                if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                                    addon.EditMode.SyncComponentSettingToEditMode(component, "direction")
                                                end
                                            end
                                            if panel and panel.RefreshDynamicSettingWidgets then
                                                panel:RefreshDynamicSettingWidgets(component)
                                            end
                                            -- Hold re-render just a bit longer to let both writes settle
                                            if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                            -- Hide the direction control very briefly to avoid 'Custom' while options swap
                                            if panel then panel._dirReinitHoldUntil = (GetTime and (GetTime() + 0.25)) or (panel._dirReinitHoldUntil or 0) end
                                        end

                                        if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                            -- ScooterMod -> Edit Mode (orientation) plus coalesced apply.
                                            addon.EditMode.SyncComponentSettingToEditMode(component, "orientation")
                                            safeSaveOnly(); requestApply()
                                        end
                                        elseif settingId == "showTimer" or settingId == "showTooltip" or settingId == "hideWhenInactive" then
                                            if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                            if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                                addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
                                                safeSaveOnly(); requestApply()
                                            end
                                        elseif settingId == "visibilityMode" or settingId == "displayMode" then
                                            if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                            if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                                addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
                                                safeSaveOnly(); requestApply()
                                            end
                                        else
                                            if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                                addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
                                                safeSaveOnly(); requestApply()
                                            end
                                        end
                                    end

                                    -- Removed: Action Bars addon-only width/height handling (see ACTIONBARS.md limitation)

                                    if settingId == "orientation" then
                                        -- For most components (Cooldown Viewer, Action Bars, Unit Frames),
                                        -- coerce the direction domain to match the new orientation:
                                        --  - Horizontal: Left/Right
                                        --  - Vertical:   Up/Down
                                        -- Aura Frame (Buffs/Debuffs) and Micro Bar have bespoke logic
                                        -- and should not be auto-coerced here.
                                        local id = component and component.id
                                        local skipDirClamp = (id == "buffs" or id == "debuffs" or id == "microBar")
                                        if not skipDirClamp then
                                            local dir = component.db.direction or "right"
                                            if v == "H" then
                                                if dir ~= "left" and dir ~= "right" then component.db.direction = "right" end
                                            else
           					if dir ~= "up" and dir ~= "down" then component.db.direction = "up" end
                                            end
                                        end
                                    end

                                    addon:ApplyStyles()

                                    if ui.dynamicLabel or ui.dynamicValues or settingId == "orientation"
                                        or settingId == "iconBorderEnable" or settingId == "iconBorderTintEnable"
                                        or settingId == "iconBorderStyle"
                                        or settingId == "borderEnable" or settingId == "borderTintEnable"
                                        or settingId == "borderStyle" or settingId == "backdropDisable" then
                                        -- For settings that affect dynamic labels/values (including Aura
                                        -- Orientation/Wrap/Direction), trigger a lightweight re-render of
                                        -- the current category so dropdowns rebuild their option sets and
                                        -- selected values from the updated DB, avoiding stale 'Custom' UI.
                                        if addon and addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategoryDeferred then
                                            addon.SettingsPanel.RefreshCurrentCategoryDeferred()
                                        end
                                        -- Refresh Border section enabled state when borderEnable changes
				if isCDMBorder and settingId == "borderEnable" then
                                            C_Timer.After(0, function()
                                                refreshBorderEnabledState()
                                            end)
                                            if borderRefreshFunc then borderRefreshFunc() end
                                        end
                                        -- Refresh Backdrop section enabled state when backdropDisable changes
				if isABBackdrop and settingId == "backdropDisable" then
                                            C_Timer.After(0, function()
                                                refreshBackdropEnabledState()
                                            end)
                                            if backdropRefreshFunc then backdropRefreshFunc() end
                                        end
                                    end
                                end, setting.default)

                            if ui.widget == "slider" then
                                local options = Settings.CreateSliderOptions(ui.min, ui.max, ui.step)
                                if ui.format == "percent" then
                                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                                        return string.format("%d%%", math.floor((tonumber(v) or 0) + 0.5))
                                    end)
                                elseif settingId == "iconSize" then
                                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                                        local snapped = math.floor(v / 10 + 0.5) * 10
                                        return tostring(snapped)
                                    end)
                                elseif settingId == "opacity" or settingId == "opacityOutOfCombat" or settingId == "opacityWithTarget" or settingId == "barOpacity" or settingId == "barOpacityOutOfCombat" or settingId == "barOpacityWithTarget" then
                                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                                        return string.format("%d%%", math.floor((tonumber(v) or 0) + 0.5))
                                    end)
                                elseif settingId == "borderThickness" or settingId == "iconBorderThickness" then
                                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                                        return string.format("%.1f", v)
                                    end)
                                else
                                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
                                end
                                local data = {
                                    setting = settingObj,
                                    options = options,
                                    name = label,
                                    -- Metadata so helpers (e.g., text inputs) can distinguish which
                                    -- component/setting this row belongs to. Used by the X/Y position
                                    -- focus-retention logic to auto-refocus after Settings list
                                    -- reinitialization.
                                    componentId = component.id,
                                    settingId = settingId,
                                }
                                local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", data)
                                initSlider:AddShownPredicate(function()
                                    return panel:IsSectionExpanded(component.id, sectionName)
                                end)
                                -- Track borderThickness slider for Border section graying out (removed hiding predicate)
                                if isCDMBorder and settingId == "borderThickness" then
                                    local baseInit = initSlider.InitFrame
                                    initSlider.InitFrame = function(self, frame)
                                        if baseInit then baseInit(self, frame) end
                                        table.insert(borderControls, { type = "slider", frame = frame })
                                        -- Don't refresh here - wait until after Display completes
                                    end
                                end
                                -- Track backdrop sliders for Backdrop section graying out
                                if isABBackdrop and (settingId == "backdropInset" or settingId == "backdropOpacity") then
                                    local baseInit = initSlider.InitFrame
                                    initSlider.InitFrame = function(self, frame)
                                        if baseInit then baseInit(self, frame) end
                                        table.insert(backdropControls, { type = "slider", frame = frame })
                                        -- Don't refresh here - wait until after Display completes
                                    end
                                end
                                if settingId == "opacity" then
                                    initSlider.reinitializeOnValueChanged = false
                                else
                                    initSlider.reinitializeOnValueChanged = true
                                end
                                if settingId == "positionX" or settingId == "positionY" then
                                    local disableTextInput = setting and setting.ui and setting.ui.disableTextInput
                                    if not disableTextInput then
                                        ConvertSliderInitializerToTextInput(initSlider)
                                    end
                                end
                                if settingId == "opacity" or settingId == "barOpacity" then
                                    local baseInit = initSlider.InitFrame
                                    initSlider.InitFrame = function(self, frame)
                                        if baseInit then baseInit(self, frame) end
                                        -- Recycler safety: refresh references every init; this frame is reused.
                                        frame._ScooterOpacityComponent = component
                                        frame._ScooterOpacitySettingId = settingId
                                        if not frame.ScooterOpacityHooked then
                                            -- IMPORTANT: Never override Blizzard methods (persistent taint).
                                            -- Use hooksecurefunc + deferral to break execution-context taint propagation.
                                            hooksecurefunc(frame, "OnSettingValueChanged", function(ctrl, setting, val)
                                                if not ctrl or ctrl._ScooterOpacityApplying then return end

                                                local run = function()
                                                    local comp = ctrl._ScooterOpacityComponent
                                                    local which = ctrl._ScooterOpacitySettingId
                                                    local db = comp and comp.db
                                                    local cv

                                                    if which == "barOpacity" then
                                                        cv = db and db.barOpacity
                                                        if type(cv) ~= "number" then
                                                            cv = (comp and comp.settings and comp.settings.barOpacity and comp.settings.barOpacity.default) or nil
                                                        end
                                                    else
                                                        -- Default to "opacity"
                                                        cv = db and db.opacity
                                                        if type(cv) ~= "number" then
                                                            cv = (comp and comp.settings and comp.settings.opacity and comp.settings.opacity.default) or nil
                                                        end
                                                    end

                                                    if type(cv) ~= "number" then return end

                                                    local c = ctrl.GetSetting and ctrl:GetSetting() or nil
                                                    if c and c.SetValue then
                                                        ctrl._ScooterOpacityApplying = true
                                                        pcall(c.SetValue, c, cv)
                                                        ctrl._ScooterOpacityApplying = nil
                                                    end
                                                end

                                                if C_Timer and C_Timer.After then
                                                    C_Timer.After(0, run)
                                                else
                                                    run()
                                                end
                                            end)
                                            frame.ScooterOpacityHooked = true
                                        end
                                        -- Boundary hook only applies to Cooldown Manager opacity (50-100), not Action Bar opacity (1-100)
                                        if settingId == "opacity" and frame.SliderWithSteppers and frame.SliderWithSteppers.Slider then
                                            local s = frame.SliderWithSteppers.Slider
                                            if not s.ScooterBoundariesHooked then
                                                s:HookScript("OnValueChanged", function(slider, value)
                                                    local v = math.max(50, math.min(100, math.floor((tonumber(value) or 0) + 0.5)))
                                                    local c = frame:GetSetting()
                                                    if c and c.SetValue and c:GetValue() ~= v then c:SetValue(v) end
                                                end)
                                                s.ScooterBoundariesHooked = true
                                            end
                                        end
                                        if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
                                        -- Add info icon explaining opacity priority (only for components with multiple opacity sliders)
                                        if sectionName == "Misc" and panel and panel.CreateInfoIcon then
                                            -- Check if this component has the other opacity settings (indicating it uses the priority system)
                                            local hasOpacityPriority = false
                                            if settingId == "opacity" then
                                                hasOpacityPriority = (component.settings.opacityOutOfCombat ~= nil) and (component.settings.opacityWithTarget ~= nil)
                                            elseif settingId == "barOpacity" then
                                                hasOpacityPriority = (component.settings.barOpacityOutOfCombat ~= nil) and (component.settings.barOpacityWithTarget ~= nil)
                                            end
                                            if hasOpacityPriority and not frame.ScooterOpacityInfoIcon then
                                                local tooltipText = "Opacity priority: With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity."
                                                -- Position icon next to the label text ("Opacity in Combat"), not the slider
                                                local label = frame.Text or frame.Label
                                                if label and panel and panel.CreateInfoIcon then
                                                    -- Create icon using the helper function, which anchors to label's right edge
                                                    frame.ScooterOpacityInfoIcon = panel.CreateInfoIconForLabel(label, tooltipText, 5, 0, 32)
                                                    if frame.ScooterOpacityInfoIcon then
                                                        frame.ScooterOpacityInfoIcon:Hide()
                                                    end
                                                    -- Defer positioning to ensure label is laid out first, then adjust based on actual text width
                                                    if C_Timer and C_Timer.After then
                                                        C_Timer.After(0, function()
                                                            if frame.ScooterOpacityInfoIcon and label then
                                                                frame.ScooterOpacityInfoIcon:ClearAllPoints()
                                                                -- Get the actual text width and position icon right after the text
                                                                local textWidth = label:GetStringWidth() or 0
                                                                if textWidth > 0 then
                                                                    -- Position relative to label's left edge + text width
                                                                    frame.ScooterOpacityInfoIcon:SetPoint("LEFT", label, "LEFT", textWidth + 5, 0)
                                                                else
                                                                    -- Fallback: use label's right edge if text width unavailable
                                                                    frame.ScooterOpacityInfoIcon:SetPoint("LEFT", label, "RIGHT", 5, 0)
                                                                end
                                                                frame.ScooterOpacityInfoIcon:Show()
                                                            end
                                                        end)
                                                    else
                                                        frame.ScooterOpacityInfoIcon:ClearAllPoints()
                                                        local textWidth = label:GetStringWidth() or 0
                                                        if textWidth > 0 then
                                                            frame.ScooterOpacityInfoIcon:SetPoint("LEFT", label, "LEFT", textWidth + 5, 0)
                                                        else
                                                            frame.ScooterOpacityInfoIcon:SetPoint("LEFT", label, "RIGHT", 5, 0)
                                                        end
                                                        frame.ScooterOpacityInfoIcon:Show()
                                                    end
                                                else
                                                    -- Fallback: create icon anchored to frame if label not found
                                                    frame.ScooterOpacityInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "LEFT", 10, 0, 32)
                                                end
                                            end
                                        end
                                    end
                                end
                                do
                                    local prev = initSlider.InitFrame
                                    initSlider.InitFrame = function(self, frame)
                                        if prev then prev(self, frame) end
                                        if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
                                        local lbl = frame and (frame.Text or frame.Label)
                                        if not lbl then
                                            if frame and frame.GetRegions then
                                                local regions = { frame:GetRegions() }
                                                for i = 1, #regions do
                                                    local r = regions[i]
                                                    if r and r.IsObjectType and r:IsObjectType("FontString") then
                                                        lbl = r; break
                                                    end
                                                end
                                            end
                                        end
                                        local canonicalLabel
                                        -- Defense-in-depth for recycled Settings rows:
                                        -- always reset the visible label text from the
                                        -- component's canonical UI metadata so a row
                                        -- that previously represented a different
                                        -- setting (e.g., Icon Height) cannot retain
                                        -- its old caption when reused for a new logical
                                        -- row (e.g., Icon Padding).
                                        if lbl and lbl.SetText then
                                            local effectiveLabel = label
                                            if setting and setting.ui and type(setting.ui.label) == "string" then
                                                effectiveLabel = setting.ui.label
                                            end
                                            if effectiveLabel then
                                                canonicalLabel = effectiveLabel
                                                lbl:SetText(effectiveLabel)
                                            end
                                        end
                                        if lbl and lbl.SetTextColor then panel.ApplyRobotoWhite(lbl) end
                                        frame.ScooterComponentId = component and component.id or nil
                                        frame.ScooterSettingId = settingId
                                        frame.ScooterCanonicalLabel = canonicalLabel
                                        if frame.ScooterPRDBarHeightInfoIcon then
                                            frame.ScooterPRDBarHeightInfoIcon:Hide()
                                            frame.ScooterPRDBarHeightInfoIcon:SetParent(nil)
                                            frame.ScooterPRDBarHeightInfoIcon = nil
                                        end
                                        if component and component.id == "prdPower" and settingId == "barHeight" then
                                            local targetLabel = frame and (frame.Text or frame.Label)
                                            if targetLabel and panel and panel.CreateInfoIconForLabel then
                                                local tooltipText = "If you are using a custom Bar Height for this Power Bar, we recommend also hiding the 'Bar-Full Spike Animations' via the setting in the Visibility section."
                                                frame.ScooterPRDBarHeightInfoIcon = panel.CreateInfoIconForLabel(targetLabel, tooltipText, 5, 0, 32)
                                                local function repositionIcon()
                                                    local icon = frame.ScooterPRDBarHeightInfoIcon
                                                    local lblRef = frame and (frame.Text or frame.Label)
                                                    if icon and lblRef then
                                                        icon:ClearAllPoints()
                                                        local textWidth = lblRef:GetStringWidth() or 0
                                                        if textWidth > 0 then
                                                            icon:SetPoint("LEFT", lblRef, "LEFT", textWidth + 5, 0)
                                                        else
                                                            icon:SetPoint("LEFT", lblRef, "RIGHT", 5, 0)
                                                        end
                                                    end
                                                end
                                                if C_Timer and C_Timer.After then
                                                    C_Timer.After(0, repositionIcon)
                                                else
                                                    repositionIcon()
                                                end
                                            end
                                        end
                                        if frame.ScooterIconLimitInfoIcon then
                                            frame.ScooterIconLimitInfoIcon:Hide()
                                            frame.ScooterIconLimitInfoIcon:SetParent(nil)
                                            frame.ScooterIconLimitInfoIcon = nil
                                        end
                                        if settingId == "iconLimit" then
                                            ApplyIconLimitLabel(component, frame)
                                            if panel and panel.RegisterDynamicSettingWidget then
                                                panel:RegisterDynamicSettingWidget(component.id, "iconLimit", frame)
                                            end
                                            if lbl and panel and panel.CreateInfoIconForLabel then
                                                local tooltipText = "Sets how many buff icons appear in each row or column before wrapping continues in the Icon Wrap direction."
                                                frame.ScooterIconLimitInfoIcon = panel.CreateInfoIconForLabel(lbl, tooltipText, 5, 0, 32)
                                                if frame.ScooterIconLimitInfoIcon then
                                                    frame.ScooterIconLimitInfoIcon:ClearAllPoints()
                                                    frame.ScooterIconLimitInfoIcon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
                                                end
                                            end
                                        end
                                        -- Tracked Bars: Icon Padding tooltip (clarifies this controls vertical bar spacing)
                                        if frame.ScooterIconPaddingInfoIcon then
                                            frame.ScooterIconPaddingInfoIcon:Hide()
                                            frame.ScooterIconPaddingInfoIcon:SetParent(nil)
                                            frame.ScooterIconPaddingInfoIcon = nil
                                        end
                                        if settingId == "iconPadding" and component and component.id == "trackedBars" then
                                            if lbl and panel and panel.CreateInfoIconForLabel then
                                                local tooltipText = "Controls the vertical spacing between stacked Tracked Bars."
                                                frame.ScooterIconPaddingInfoIcon = panel.CreateInfoIconForLabel(lbl, tooltipText, 5, 0, 32)
                                                if frame.ScooterIconPaddingInfoIcon then
                                                    frame.ScooterIconPaddingInfoIcon:ClearAllPoints()
                                                    frame.ScooterIconPaddingInfoIcon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
                                                end
                                            end
                                        end
                                        if ui.dynamicLabel and settingId == "columns" then
                                            ApplyColumnsLabel(component, frame)
                                            if panel and panel.RegisterDynamicSettingWidget then
                                                panel:RegisterDynamicSettingWidget(component.id, "columns", frame)
                                            end
                                        end
                                        local skipLabelRepair = ui.dynamicLabel or settingId == "iconLimit" or settingId == "columns"
                                        if canonicalLabel and not skipLabelRepair then
                                            local function enforceLabel()
                                                local target = frame and (frame.Text or frame.Label)
                                                if not target and frame and frame.GetRegions then
                                                    local regions = { frame:GetRegions() }
                                                    for i = 1, #regions do
                                                        local region = regions[i]
                                                        if region and region.IsObjectType and region:IsObjectType("FontString") then
                                                            target = region
                                                            break
                                                        end
                                                    end
                                                end
                                                if target and target.GetText and target:GetText() ~= canonicalLabel then
                                                    target:SetText(canonicalLabel)
                                                    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(target) end
                                                end
                                            end
                                            if C_Timer and C_Timer.After then
                                                C_Timer.After(0, enforceLabel)
                                            else
                                                enforceLabel()
                                            end
                                        end
                                    end
                                end
                                table.insert(init, initSlider)
                            elseif ui.widget == "dropdown" then
                                local data
                                if ui.optionsProvider and type(ui.optionsProvider) == "function" then
                                    data = { setting = settingObj, options = ui.optionsProvider, name = label }
                                elseif settingId == "borderStyle" then
                                    if component and component.id == "trackedBars" then
                                        if addon.BuildBarBorderOptionsContainer then
                                            data = { setting = settingObj, options = addon.BuildBarBorderOptionsContainer, name = label }
                                        end
                                    elseif addon.BuildIconBorderOptionsContainer then
                                        data = { setting = settingObj, options = addon.BuildIconBorderOptionsContainer, name = label }
                                    end
                                elseif settingId == "direction" then
                                    local orientation = component and component.db and (component.db.orientation or "H") or "H"
                                    if component and (component.id == "buffs" or component.id == "debuffs") then
                                        data = {
                                            setting = settingObj,
                                            options = function() return BuildAuraDirectionOptions(component) end,
                                            name = label,
                                        }
                                    else
                                        local containerOpts = Settings.CreateControlTextContainer()
                                        local orderedValues = {}
                                        if orientation == "H" then
                                            table.insert(orderedValues, "right")
                                            table.insert(orderedValues, "left")
                                        else
                                            table.insert(orderedValues, "up")
                                            table.insert(orderedValues, "down")
                                        end
                                        local hasOptions = false
                                        for _, valKey in ipairs(orderedValues) do
                                            local vLabel = values and values[valKey]
                                            if vLabel then
                                                containerOpts:Add(valKey, vLabel)
                                                hasOptions = true
                                            end
                                        end
                                        if not hasOptions and values then
                                            for valKey, vLabel in pairs(values) do
                                                if vLabel then
                                                    containerOpts:Add(valKey, vLabel)
                                                    hasOptions = true
                                                end
                                            end
                                        end
                                        data = { setting = settingObj, options = function() return containerOpts:GetData() end, name = label }
                                    end
                                elseif settingId == "iconWrap" and component and (component.id == "buffs" or component.id == "debuffs") then
                                    data = {
                                        setting = settingObj,
                                        options = function() return BuildAuraWrapOptions(component) end,
                                        name = label,
                                    }
                                else
                                    local containerOpts = Settings.CreateControlTextContainer()
                                    local orderedValues = {}
                                    if settingId == "orientation" then
                                        table.insert(orderedValues, "H"); table.insert(orderedValues, "V")
                                    elseif settingId == "visibilityMode" then
                                        table.insert(orderedValues, "always")
                                        table.insert(orderedValues, "combat")
                                        table.insert(orderedValues, "never")
                                    else
                                        for val, _ in pairs(values) do table.insert(orderedValues, val) end
                                    end
                                    for _, valKey in ipairs(orderedValues) do
                                        if values then
                                            local vLabel = values[valKey]
                                            if vLabel ~= nil then
                                                containerOpts:Add(valKey, vLabel)
                                            end
                                        end
                                    end
                                    data = { setting = settingObj, options = function() return containerOpts:GetData() end, name = label }
                                end
                                local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", data)
                                local function shouldShowDropdown()
                                    if not panel:IsSectionExpanded(component.id, sectionName) then
                                        return false
                                    end
                                    -- Removed borderEnable check for CDM Border sections - controls are grayed out instead of hidden
                                    if component and component.id == "trackedBars" and settingId == "borderStyle" then
                                        local db = component and component.db
                                        if not db or db.styleEnableCustom == false then return false end
                                        -- Show always, will be grayed out if borderEnable is false
                                        return true
                                    end
                                    if settingId == "iconBorderStyle" then
                                        local db = component and component.db
                                        return db and db.iconBorderEnable and db.iconBorderEnable ~= false
                                    end
                                    if settingId == "borderStyle" and isCDMBorder then
                                        -- Show always for CDM Border sections and Action Bars, will be grayed out if borderEnable is false
                                        return true
                                    end
                                    if settingId == "borderStyle" then
                                        local db = component and component.db
                                        return db and db.borderEnable and db.borderEnable ~= false
                                    end
                                    return true
                                end
                                initDrop:AddShownPredicate(shouldShowDropdown)
                                -- Track borderStyle dropdown for Border section graying out
                                if isCDMBorder and settingId == "borderStyle" then
                                    local baseInit = initDrop.InitFrame
                                    initDrop.InitFrame = function(self, frame)
                                        if baseInit then baseInit(self, frame) end
                                        table.insert(borderControls, { type = "dropdown", frame = frame })
                                        -- Don't refresh here - wait until after Display completes
                                    end
                                end
                                -- Track backdropStyle dropdown for Backdrop section graying out
                                if isABBackdrop and settingId == "backdropStyle" then
                                    local baseInit = initDrop.InitFrame
                                    initDrop.InitFrame = function(self, frame)
                                        if baseInit then baseInit(self, frame) end
                                        table.insert(backdropControls, { type = "dropdown", frame = frame })
                                        -- Don't refresh here - wait until after Display completes
                                    end
                                end
                                -- For Micro Bar 'direction', hide momentarily during orientation swap to avoid transient 'Custom'
                                if settingId == "direction" and component.id == "microBar" then
                                    initDrop:AddShownPredicate(function()
                                        if not panel or not panel._dirReinitHoldUntil then return true end
                                        local now = GetTime and GetTime() or 0
                                        return now >= panel._dirReinitHoldUntil
                                    end)
                                end
                                if settingId == "visibilityMode" then
                                    initDrop.reinitializeOnValueChanged = false
                                else
                                    initDrop.reinitializeOnValueChanged = true
                                end
                                do
                                    local prev = initDrop.InitFrame
                                    initDrop.InitFrame = function(self, frame)
                                        if prev then prev(self, frame) end
                                        local lbl = frame and (frame.Text or frame.Label)
                                        if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
                                        if frame.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(frame.Control) end
                                        if settingId == "direction" then
                                            if panel and panel.RegisterDynamicSettingWidget then
                                                panel:RegisterDynamicSettingWidget(component.id, "direction", frame)
                                            end
                                            if panel and panel.RefreshDynamicSettingWidgets then
                                                panel:RefreshDynamicSettingWidgets(component)
                                            end
                                        elseif settingId == "iconWrap" and (component.id == "buffs" or component.id == "debuffs") then
                                            if panel and panel.RegisterDynamicSettingWidget then
                                                panel:RegisterDynamicSettingWidget(component.id, "iconWrap", frame)
                                            end
                                            if panel and panel.RefreshDynamicSettingWidgets then
                                                panel:RefreshDynamicSettingWidgets(component)
                                            end
                                        end
                                        -- Apply custom font picker popup for font dropdowns (but not font style dropdowns)
                                        if type(label) == "string" and string.find(label, "Font") and not string.find(label, "Style") and frame.Control and frame.Control.Dropdown then
                                            if addon.InitFontDropdown then
                                                addon.InitFontDropdown(frame.Control.Dropdown, settingObj, data.options)
                                            end
                                        end
                                    end
                                end
                                table.insert(init, initDrop)
                            elseif ui.widget == "checkbox" then
                                local data = { setting = settingObj, name = label, tooltip = ui.tooltip, options = {} }
                                if settingId == "borderTintEnable" or settingId == "iconBorderTintEnable" or settingId == "backdropTintEnable" then
                                    local colorKey = (settingId == "iconBorderTintEnable") and "iconBorderTintColor" or "borderTintColor"
                                    if settingId == "backdropTintEnable" then colorKey = "backdropTintColor" end
                                    local initCb = CreateCheckboxWithSwatchInitializer(
                                        settingObj,
                                        label,
                                        function()
                                            local val = component.db[colorKey]
                                            if val == nil and component.settings and component.settings[colorKey] then
                                                val = component.settings[colorKey].default
                                            end
                                            return val or {1,1,1,1}
                                        end,
                                        function(r, g, b, a)
                                            component.db[colorKey] = { r, g, b, a }
                                            addon:ApplyStyles()
                                        end,
                                        8
                                    )
                                    initCb:AddShownPredicate(function()
                                        if not panel:IsSectionExpanded(component.id, sectionName) then return false end
                                        if settingId == "iconBorderTintEnable" then
                                            local db = component and component.db
                                            return db and db.iconBorderEnable
                                    elseif settingId == "borderTintEnable" and isCDMBorder then
                                            -- Show always for CDM Border sections and Action Bars, will be grayed out if borderEnable is false
                                            return true
                                    elseif settingId == "borderTintEnable" then
                                            local db = component and component.db
                                        return db and db.borderEnable
                                        elseif settingId == "backdropTintEnable" and isABBackdrop then
                                            -- Show always for Action Bar Backdrop sections, will be grayed out if backdropDisable is true
                                            return true
                                        elseif settingId == "backdropTintEnable" then
                                            local db = component and component.db
                                            if not db or db.backdropDisable then return false end
                                            return true
                                        end
                                        return true
                                    end)
                                    -- Track borderTintEnable checkbox for Border section graying out
                                    if isCDMBorder and settingId == "borderTintEnable" then
                                        local baseInit = initCb.InitFrame
                                        initCb.InitFrame = function(self, frame)
                                            if baseInit then baseInit(self, frame) end
                                            table.insert(borderControls, { type = "checkbox", frame = frame })
                                            -- Don't refresh here - wait until after Display completes
                                        end
                                    end
                                    -- Track backdropTintEnable checkbox for Backdrop section graying out
                                    if isABBackdrop and settingId == "backdropTintEnable" then
                                        local baseInit = initCb.InitFrame
                                        initCb.InitFrame = function(self, frame)
                                            if baseInit then baseInit(self, frame) end
                                            table.insert(backdropControls, { type = "checkbox", frame = frame })
                                            -- Don't refresh here - wait until after Display completes
                                        end
                                    end
                                    local baseInit = initCb.InitFrame
                                    initCb.InitFrame = function(self, frame)
                                        if baseInit then baseInit(self, frame) end
                                        local cb = frame.Checkbox or frame.CheckBox or frame.Control or frame
                                        if cb and not cb._ScooterToggleHooked then
                                            cb:HookScript("OnClick", function()
                                                if frame and frame.ScooterInlineSwatch then
                                                    frame.ScooterInlineSwatch:SetShown((cb.GetChecked and cb:GetChecked()) and true or false)
                                                end
                                            end)
                                            cb._ScooterToggleHooked = true
                                        end
                                    end
                                    table.insert(init, initCb)
                                else
                                    local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", data)
                                    if settingId == "visibilityMode" or settingId == "opacity" or settingId == "showTimer" or settingId == "showTooltip" or settingId == "hideWhenInactive" then
                                        initCb.reinitializeOnValueChanged = false
                                    end
                                    initCb:AddShownPredicate(function()
                                        return panel:IsSectionExpanded(component.id, sectionName)
                                    end)
                                    local baseInitFrame = initCb.InitFrame
                                    initCb.InitFrame = function(self, frame)
                                        if baseInitFrame then baseInitFrame(self, frame) end
                                        -- Clean up Unit Frame info icons if this checkbox is NOT a Unit Frame checkbox
                                        -- This prevents Unit Frame icons from appearing on recycled frames (e.g., Action Bar checkboxes)
                                        -- Only destroy icons marked as Unit Frame icons, allowing other components to have their own icons
                                        if frame.ScooterInfoIcon and frame.ScooterInfoIcon._isUnitFrameIcon then
                                            local labelText = frame.Text and frame.Text:GetText() or ""
                                            local isUnitFrameComponent = (component.id == "ufPlayer" or component.id == "ufTarget" or component.id == "ufFocus" or component.id == "ufPet" or component.id == "ufToT")
                                            local isUnitFrameCheckbox = (labelText == "Use Custom Borders")
                                            if not (isUnitFrameComponent and isUnitFrameCheckbox) then
                                                -- This is NOT a Unit Frame checkbox - destroy the Unit Frame icon
                                                -- Other components can create their own icons without interference
                                                frame.ScooterInfoIcon:Hide()
                                                frame.ScooterInfoIcon:SetParent(nil)
                                                frame.ScooterInfoIcon = nil
                                            end
                                        end
                                        if frame.ScooterInlineSwatch then
                                            frame.ScooterInlineSwatch:Hide()
                                        end
                                        -- Aggressively restore any swatch-wrapped handlers on recycled rows
                                        if frame.ScooterInlineSwatchWrapper then
                                            frame.OnSettingValueChanged = frame.ScooterInlineSwatchBase or frame.OnSettingValueChanged
                                            frame.ScooterInlineSwatchWrapper = nil
                                            frame.ScooterInlineSwatchBase = nil
                                        end
                                        local cb = frame.Checkbox or frame.CheckBox or frame.Control or frame
                                        if cb and cb.UnregisterCallback and SettingsCheckboxMixin and SettingsCheckboxMixin.Event and cb.ScooterInlineSwatchCallbackOwner then
                                            cb:UnregisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, cb.ScooterInlineSwatchCallbackOwner)
                                            cb.ScooterInlineSwatchCallbackOwner = nil
                                        end
                                        if cb and cb.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(cb.Text) end
                                        if frame and frame.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
                                        -- Theme the checkbox checkmark to green
                                        if cb and panel and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
                                        -- Clean up or create the PRD-specific info icon for Hide Full Bar Animations
                                        if frame.ScooterFullBarAnimInfoIcon and frame.ScooterFullBarAnimInfoIcon._ScooterIsPRDIcon and not (component.id == "prdPower" and settingId == "hideSpikeAnimations") then
                                            frame.ScooterFullBarAnimInfoIcon:Hide()
                                            frame.ScooterFullBarAnimInfoIcon:SetParent(nil)
                                            frame.ScooterFullBarAnimInfoIcon = nil
                                        end
                                        if component.id == "prdPower" and settingId == "hideSpikeAnimations" and panel and panel.CreateInfoIconForLabel then
                                            local labelFS = frame.Text or (cb and cb.Text)
                                            if labelFS then
                                                if not frame.ScooterFullBarAnimInfoIcon then
                                                    local tooltipText = "Hides Blizzard's full-bar celebration effects on the Personal Resource Display so customized bar sizes stay clean when the resource is full."
                                                    frame.ScooterFullBarAnimInfoIcon = panel.CreateInfoIconForLabel(labelFS, tooltipText, 5, 0, 32)
                                                    if frame.ScooterFullBarAnimInfoIcon then
                                                        frame.ScooterFullBarAnimInfoIcon._ScooterIsPRDIcon = true
                                                    end
                                                end
                                                local function repositionPRDIcon()
                                                    local icon = frame.ScooterFullBarAnimInfoIcon
                                                    local lbl = frame.Text or (cb and cb.Text)
                                                    if icon and lbl then
                                                        icon:ClearAllPoints()
                                                        icon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
                                                        icon:Show()
                                                    end
                                                end
                                                if C_Timer and C_Timer.After then
                                                    C_Timer.After(0, repositionPRDIcon)
                                                else
                                                    repositionPRDIcon()
                                                end
                                            end
                                        end
                                        -- Clean up or create the PRD-specific info icon for Hide Power Feedback
                                        if frame.ScooterPowerFeedbackInfoIcon and frame.ScooterPowerFeedbackInfoIcon._ScooterIsPRDIcon and not (component.id == "prdPower" and settingId == "hidePowerFeedback") then
                                            frame.ScooterPowerFeedbackInfoIcon:Hide()
                                            frame.ScooterPowerFeedbackInfoIcon:SetParent(nil)
                                            frame.ScooterPowerFeedbackInfoIcon = nil
                                        end
                                        if component.id == "prdPower" and settingId == "hidePowerFeedback" and panel and panel.CreateInfoIconForLabel then
                                            local labelFS = frame.Text or (cb and cb.Text)
                                            if labelFS then
                                                if not frame.ScooterPowerFeedbackInfoIcon then
                                                    local tooltipText = "Hides the flash animation that plays when you spend or gain power (energy, mana, rage, etc.). This animation shows a quick highlight on the portion of the bar that changed."
                                                    frame.ScooterPowerFeedbackInfoIcon = panel.CreateInfoIconForLabel(labelFS, tooltipText, 5, 0, 32)
                                                    if frame.ScooterPowerFeedbackInfoIcon then
                                                        frame.ScooterPowerFeedbackInfoIcon._ScooterIsPRDIcon = true
                                                    end
                                                end
                                                local function repositionPRDFeedbackIcon()
                                                    local icon = frame.ScooterPowerFeedbackInfoIcon
                                                    local lbl = frame.Text or (cb and cb.Text)
                                                    if icon and lbl then
                                                        icon:ClearAllPoints()
                                                        icon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
                                                        icon:Show()
                                                    end
                                                end
                                                if C_Timer and C_Timer.After then
                                                    C_Timer.After(0, repositionPRDFeedbackIcon)
                                                else
                                                    repositionPRDFeedbackIcon()
                                                end
                                            end
                                        end
                                        -- Clean up or create the PRD-specific info icon for Minimize Vertical Movement
                                        if frame.ScooterLockVerticalInfoIcon and frame.ScooterLockVerticalInfoIcon._ScooterIsPRDIcon and not (component.id == "prdGlobal" and settingId == "staticPosition") then
                                            frame.ScooterLockVerticalInfoIcon:Hide()
                                            frame.ScooterLockVerticalInfoIcon:SetParent(nil)
                                            frame.ScooterLockVerticalInfoIcon = nil
                                        end
                                        if component.id == "prdGlobal" and settingId == "staticPosition" and panel and panel.CreateInfoIconForLabel then
                                            local labelFS = frame.Text or (cb and cb.Text)
                                            if labelFS then
                                                if not frame.ScooterLockVerticalInfoIcon then
                                                    local tooltipText = "Greatly reduces PRD vertical movement as your camera angle changes. Use the Y Offset slider to set the preferred screen position. Note: A small amount of movement at one specific camera angle is unavoidable due to Blizzard's 3D-to-screen projection system."
                                                    frame.ScooterLockVerticalInfoIcon = panel.CreateInfoIconForLabel(labelFS, tooltipText, 5, 0, 32)
                                                    if frame.ScooterLockVerticalInfoIcon then
                                                        frame.ScooterLockVerticalInfoIcon._ScooterIsPRDIcon = true
                                                    end
                                                end
                                                local function repositionLockVerticalIcon()
                                                    local icon = frame.ScooterLockVerticalInfoIcon
                                                    local lbl = frame.Text or (cb and cb.Text)
                                                    if icon and lbl then
                                                        icon:ClearAllPoints()
                                                        icon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
                                                        icon:Show()
                                                    end
                                                end
                                                if C_Timer and C_Timer.After then
                                                    C_Timer.After(0, repositionLockVerticalIcon)
                                                else
                                                    repositionLockVerticalIcon()
                                                end
                                            end
                                        end
                                        -- Clean up or create the Action Bar-specific info icon for Mouseover Mode
                                        local isActionBarComponent = component.id and component.id:match("^actionBar%d$")
                                        if frame.ScooterMouseoverModeInfoIcon and frame.ScooterMouseoverModeInfoIcon._ScooterIsActionBarIcon and not (isActionBarComponent and settingId == "mouseoverMode") then
                                            frame.ScooterMouseoverModeInfoIcon:Hide()
                                            frame.ScooterMouseoverModeInfoIcon:SetParent(nil)
                                            frame.ScooterMouseoverModeInfoIcon = nil
                                        end
                                        if isActionBarComponent and settingId == "mouseoverMode" and panel and panel.CreateInfoIconForLabel then
                                            local labelFS = frame.Text or (cb and cb.Text)
                                            if labelFS then
                                                if not frame.ScooterMouseoverModeInfoIcon then
                                                    local tooltipText = "When enabled, hovering over this action bar will temporarily set its opacity to 100%, regardless of the other opacity settings configured above."
                                                    frame.ScooterMouseoverModeInfoIcon = panel.CreateInfoIconForLabel(labelFS, tooltipText, 5, 0, 32)
                                                    if frame.ScooterMouseoverModeInfoIcon then
                                                        frame.ScooterMouseoverModeInfoIcon._ScooterIsActionBarIcon = true
                                                    end
                                                end
                                                local function repositionMouseoverIcon()
                                                    local icon = frame.ScooterMouseoverModeInfoIcon
                                                    local lbl = frame.Text or (cb and cb.Text)
                                                    if icon and lbl then
                                                        icon:ClearAllPoints()
                                                        icon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
                                                        icon:Show()
                                                    end
                                                end
                                                if C_Timer and C_Timer.After then
                                                    C_Timer.After(0, repositionMouseoverIcon)
                                                else
                                                    repositionMouseoverIcon()
                                                end
                                            end
                                        end
                                        -- Force-stable handlers for key master toggles to avoid recycled-frame wrapper interference
                                        if settingId == "borderEnable" then
                                            local cbBtn = frame.Checkbox or frame.CheckBox or frame.Control or frame
                                            if cbBtn and not cbBtn._ScooterStableBorderHooked then
                                                cbBtn:HookScript("OnClick", function(btn)
                                                    local newVal = (btn.GetChecked and btn:GetChecked()) and true or false
                                                    -- Write DB directly to ensure immediate effect
                                                    if component and component.db then component.db.borderEnable = newVal end
                                                    -- Also reflect into the Setting object if present
                                                    local st = frame.GetSetting and frame:GetSetting()
                                                    if st and st.SetValue then pcall(st.SetValue, st, newVal) end
                                                    -- Apply visuals and refresh enabled state
                                                    if addon and addon.ApplyStyles then addon:ApplyStyles() end
                                                    if borderRefreshFunc then borderRefreshFunc() end
                                                end)
                                                cbBtn._ScooterStableBorderHooked = true
                                            end
                                        elseif settingId == "backdropDisable" then
                                            local cbBtn = frame.Checkbox or frame.CheckBox or frame.Control or frame
                                            if cbBtn and not cbBtn._ScooterStableBackdropHooked then
                                                cbBtn:HookScript("OnClick", function(btn)
                                                    local newVal = (btn.GetChecked and btn:GetChecked()) and true or false
                                                    if component and component.db then component.db.backdropDisable = newVal end
                                                    local st = frame.GetSetting and frame:GetSetting()
                                                    if st and st.SetValue then pcall(st.SetValue, st, newVal) end
                                                    if addon and addon.ApplyStyles then addon:ApplyStyles() end
                                                    if backdropRefreshFunc then backdropRefreshFunc() end
                                                end)
                                                cbBtn._ScooterStableBackdropHooked = true
                                            end
                                        end
                                        -- Refresh Border section enabled state after borderEnable checkbox is initialized
                                        if isCDMBorder and settingId == "borderEnable" then
                                            C_Timer.After(0, function()
                                                refreshBorderEnabledState()
                                            end)
                                        end
                                        -- Refresh Backdrop section enabled state after backdropDisable checkbox is initialized
                                        if isABBackdrop and settingId == "backdropDisable" then
                                            C_Timer.After(0, function()
                                                refreshBackdropEnabledState()
                                            end)
                                        end
                                    end
                                    table.insert(init, initCb)
                                end
                            elseif ui.widget == "color" then
                                if settingId ~= "borderTintColor" and settingId ~= "backdropTintColor" then
                                    local colorRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
                                    colorRow.GetExtent = function() return 28 end
                                    colorRow.InitFrame = function(self, frame)
                                        if not frame.ScooterColorSwatch then
                                            local swatch = CreateFrame("Button", nil, frame)
                                            swatch:SetSize(20, 20)
                                            swatch:SetPoint("LEFT", frame, "LEFT", 16, 0)
                                            swatch.Color = swatch:CreateTexture(nil, "ARTWORK")
                                            swatch.Color:SetAllPoints(swatch)
                                            frame.ScooterColorSwatch = swatch
                                        end
                                        local swatch = frame.ScooterColorSwatch
                                        local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                                        title:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
                                        title:SetText(label)
                                        local c = component.db[settingId] or setting.default or {1,1,1,1}
                                        swatch.Color:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
                                        swatch:SetScript("OnClick", function()
                                            local cur = component.db[settingId] or setting.default or {1,1,1,1}
                                            ColorPickerFrame:SetupColorPickerAndShow({
                                                r = cur[1] or 1, g = cur[2] or 1, b = cur[3] or 1,
                                                hasOpacity = true,
                                                opacity = cur[4] or 1,
                                                swatchFunc = function()
                                                    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                                                    local na = ColorPickerFrame:GetColorAlpha()
                                                    component.db[settingId] = { nr, ng, nb, na }
                                                    addon:ApplyStyles()
                                                end,
                                                cancelFunc = function(prev)
                                                    if prev then
                                                        component.db[settingId] = { prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1 }
                                                        addon:ApplyStyles()
                                                    end
                                                end,
                                            })
                                        end)
                                    end
                                    colorRow:AddShownPredicate(function()
                                        return panel:IsSectionExpanded(component.id, sectionName)
                                    end)
                                    table.insert(init, colorRow)
                                end
                            elseif ui.widget == "textEntry" then
                                -- Text entry widget for numeric position/offset fields (e.g., PRD Global X/Y Position)
                                -- Creates a simple edit box control without a slider
                                -- Capture values for closures before creating the initializer
                                local capturedLabel = label
                                local capturedComponent = component
                                local capturedSettingId = settingId
                                local capturedSetting = setting
                                local capturedUi = ui
                                local capturedSectionName = sectionName
                                
                                local textEntryRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
                                textEntryRow.GetExtent = function() return 34 end
                                textEntryRow.InitFrame = function(self, frame)
                                    -- Defense against recycled rows: hide any stale controls from other widget types
                                    if frame.SliderWithSteppers then frame.SliderWithSteppers:Hide() end
                                    if frame.Control then
                                        if frame.Control.Hide then pcall(frame.Control.Hide, frame.Control) end
                                    end
                                    if frame.Dropdown then pcall(frame.Dropdown.Hide, frame.Dropdown) end
                                    if frame.Checkbox or frame.CheckBox then
                                        local cb = frame.Checkbox or frame.CheckBox
                                        if cb and cb.Hide then pcall(cb.Hide, cb) end
                                    end
                                    
                                    -- Create or reuse label
                                    -- NOTE: Settings labels must use 36.5px left offset for consistent
                                    -- indentation across all control types (sliders, checkboxes, dropdowns).
                                    -- See INTERFACE.md "Settings Row Label Indentation" for requirements.
                                    if not frame.ScooterTextEntryLabel then
                                        local lbl = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                                        lbl:SetPoint("LEFT", frame, "LEFT", 36.5, 0)
                                        frame.ScooterTextEntryLabel = lbl
                                    end
                                    frame.ScooterTextEntryLabel:SetText(capturedLabel or "")
                                    frame.ScooterTextEntryLabel:Show()
                                    if panel and panel.ApplyRobotoWhite then
                                        panel.ApplyRobotoWhite(frame.ScooterTextEntryLabel)
                                    end
                                    
                                    -- Create or reuse edit box
                                    -- Position matches the slider-to-text-input conversion used by Action Bars
                                    if not frame.ScooterTextEntryInput then
                                        local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
                                        input:SetAutoFocus(false)
                                        input:SetWidth(120)
                                        input:SetHeight(24)
                                        input:SetJustifyH("CENTER")
                                        input:SetPoint("LEFT", frame, "CENTER", -40, 0)
                                        frame.ScooterTextEntryInput = input
                                    end
                                    
                                    local input = frame.ScooterTextEntryInput
                                    
                                    local function restore()
                                        local v = capturedComponent.db[capturedSettingId]
                                        if v == nil then v = capturedSetting.default or 0 end
                                        input:SetText(string.format("%.0f", tonumber(v) or 0))
                                    end
                                    local function commit()
                                        local text = input:GetText()
                                        local num = tonumber(text)
                                        if not num then
                                            restore()
                                            return
                                        end
                                        -- Round to integer
                                        num = math.floor(num + 0.5)
                                        -- Clamp to min/max if specified
                                        if capturedUi.min ~= nil then num = math.max(capturedUi.min, num) end
                                        if capturedUi.max ~= nil then num = math.min(capturedUi.max, num) end
                                        -- Update DB and apply styles
                                        if capturedComponent.db[capturedSettingId] ~= num then
                                            capturedComponent.db[capturedSettingId] = num
                                            addon:ApplyStyles()
                                        end
                                        input:SetText(string.format("%.0f", num))
                                    end
                                    input:SetScript("OnEnterPressed", function(b)
                                        commit()
                                        -- Delay ClearFocus to prevent Enter key from propagating after
                                        -- the EditBox releases keyboard focus. Without this delay, the
                                        -- Enter key can interact with other UI elements and cause
                                        -- unintended actions like closing the settings panel.
                                        C_Timer.After(0, function()
                                            if b and b.ClearFocus then b:ClearFocus() end
                                        end)
                                    end)
                                    input:SetScript("OnEditFocusLost", function(b)
                                        commit()
                                        b:HighlightText(0, 0)
                                    end)
                                    input:SetScript("OnEscapePressed", function(b)
                                        b:ClearFocus()
                                        restore()
                                    end)
                                    
                                    -- Set current value and ensure visibility
                                    local currentValue = capturedComponent.db[capturedSettingId]
                                    if currentValue == nil then currentValue = capturedSetting.default or 0 end
                                    input:SetText(string.format("%.0f", tonumber(currentValue) or 0))
                                    input:Show()
                                    input:SetFrameLevel((frame:GetFrameLevel() or 0) + 5)
                                    
                                    -- Ensure frame is shown
                                    frame:Show()
                                    
                                    -- Tag frame for reuse key matching
                                    frame.ScooterComponentId = capturedComponent.id
                                    frame.ScooterSettingId = capturedSettingId
                                end
                                textEntryRow:AddShownPredicate(function()
                                    return panel:IsSectionExpanded(capturedComponent.id, capturedSectionName)
                                end)
                                textEntryRow.reinitializeOnValueChanged = false
                                table.insert(init, textEntryRow)
                            end
                        end
                    end
                    -- Store refresh functions to call after Display completes
                    if isCDMBorder then
                        borderRefreshFunc = refreshBorderEnabledState
                    end
                    if isABBackdrop then
                        backdropRefreshFunc = refreshBackdropEnabledState
                    end
                end
            end

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
            
            -- Refresh Border/Backdrop enabled state after Display completes (frames now exist)
            if borderRefreshFunc then
                C_Timer.After(0.05, function()
                    borderRefreshFunc()
                end)
            end
            if backdropRefreshFunc then
                C_Timer.After(0.05, function()
                    backdropRefreshFunc()
                end)
            end
        end

        return { mode = "list", render = render, componentId = componentId }
    end -- This end was missing
end

panel.builders = panel.builders or {}
panel.builders.createComponentRenderer = createComponentRenderer
