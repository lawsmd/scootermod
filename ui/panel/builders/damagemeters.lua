local addonName, addon = ...

--[[============================================================================
    ██╗     ███████╗ ██████╗  █████╗  ██████╗██╗   ██╗
    ██║     ██╔════╝██╔════╝ ██╔══██╗██╔════╝╚██╗ ██╔╝
    ██║     █████╗  ██║  ███╗███████║██║      ╚████╔╝
    ██║     ██╔══╝  ██║   ██║██╔══██║██║       ╚██╔╝
    ███████╗███████╗╚██████╔╝██║  ██║╚██████╗   ██║
    ╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝   ╚═╝

    ⚠️  WARNING: THIS IS LEGACY CODE - DO NOT MODIFY ⚠️

    This file is part of the LEGACY UI system (ui/panel/).

    The NEW UI is located in: ui/v2/

    For Damage Meter settings, see:
        ui/v2/settings/interface/DamageMeterRenderer.lua

    This legacy code is kept only for backwards compatibility and will
    eventually be removed. ALL new development should happen in ui/v2/.

    If you are an AI assistant or developer reading this:
    - DO NOT add new features to this file
    - DO NOT modify this file for new functionality
    - GO TO ui/v2/ for all UI work

============================================================================]]--

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

--------------------------------------------------------------------------------
-- LEGACY: Damage Meters Builder Module
-- ⚠️ DO NOT MODIFY - Use ui/v2/settings/interface/DamageMeterRenderer.lua instead
--------------------------------------------------------------------------------

-- Helper: Apply styles after changes
local function applyNow()
    if addon and addon.ApplyStyles then addon:ApplyStyles() end
end

--------------------------------------------------------------------------------
-- Damage Meters Renderer
--------------------------------------------------------------------------------

function panel.RenderDamageMeter()
    local componentId = "damageMeter"

    local render = function()
        local component = addon.Components[componentId]
        if not component then return end

        if panel and panel.PrepareDynamicSettingWidgets then
            panel:PrepareDynamicSettingWidgets(componentId)
        end

        local init = {}

        --------------------------------------------------------------------------------
        -- Parent-level Style dropdown
        --------------------------------------------------------------------------------
        do
            local db = component.db or {}
            local label = "Style"

            local function styleOptions()
                local container = Settings.CreateControlTextContainer()
                container:Add(0, "Default")
                container:Add(1, "Bordered")
                container:Add(2, "Thin")
                return container:GetData()
            end

            local function getter()
                return db.style or 0
            end

            local function setter(v)
                C_Timer.After(0, function()
                    db.style = tonumber(v) or 0
                    applyNow()
                end)
            end

            local setting = CreateLocalSetting(label, "number", getter, setter, getter())
            local dropInit = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                name = label,
                setting = setting,
                options = styleOptions,
            })
            dropInit.GetExtent = function() return 34 end

            do
                local baseInitFrame = dropInit.InitFrame
                dropInit.InitFrame = function(self, frame)
                    if baseInitFrame then baseInitFrame(self, frame) end
                    if panel and panel.ApplyRobotoWhite then
                        local lbl = frame.Text or frame.Label
                        if lbl then panel.ApplyRobotoWhite(lbl) end
                    end
                    if frame.Control and panel and panel.ThemeDropdownWithSteppers then
                        panel.ThemeDropdownWithSteppers(frame.Control)
                    end
                end
            end

            table.insert(init, dropInit)
        end

        --------------------------------------------------------------------------------
        -- Layout Section Header (just the header, no content)
        --------------------------------------------------------------------------------
        do
            local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                name = "Layout",
                sectionKey = "Layout",
                componentId = componentId,
                expanded = panel:IsSectionExpanded(componentId, "Layout"),
            })
            expInitializer.GetExtent = function() return 30 end
            table.insert(init, expInitializer)
        end

        --------------------------------------------------------------------------------
        -- Bars Section (Names Text / Numbers Text tabs)
        --------------------------------------------------------------------------------
        do
            local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                name = "Bars",
                sectionKey = "Bars",
                componentId = componentId,
                expanded = panel:IsSectionExpanded(componentId, "Bars"),
            })
            expInitializer.GetExtent = function() return 30 end
            table.insert(init, expInitializer)
        end

        -- Bars tabbed content
        do
            local barsTabs = {
                sectionTitle = "",
                tabAText = "Names Text",
                tabBText = "Numbers Text",
            }

            barsTabs.build = function(frame)
                local db = component.db or {}

                local function applyText()
                    if addon.ApplyStyles then addon:ApplyStyles() end
                end

                -- Helper: format integer for slider display
                local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
                local function fmtDec(v) return string.format("%.2f", tonumber(v) or 0) end

                -- Helper: add slider control
                local function addSlider(parent, label, minV, maxV, step, getFunc, setFunc, yRef, formatter)
                    local options = Settings.CreateSliderOptions(minV, maxV, step)
                    local fmt = formatter or fmtInt
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmt(v) end)
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
                    return f
                end

                -- Helper: add dropdown control
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
                    -- Apply custom font picker popup for font dropdowns (but not font style dropdowns)
                    if type(label) == "string" and string.find(label, "Font") and not string.find(label, "Style") and f.Control and f.Control.Dropdown then
                        if addon.InitFontDropdown then
                            addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
                        end
                    end
                    yRef.y = yRef.y - 34
                end

                -- Helper: add style dropdown
                local function addStyle(parent, label, getFunc, setFunc, yRef)
                    local function styleOptions()
                        local container = Settings.CreateControlTextContainer()
                        container:Add("NONE", "Regular")
                        container:Add("OUTLINE", "Outline")
                        container:Add("THICKOUTLINE", "Thick Outline")
                        container:Add("HEAVYTHICKOUTLINE", "Heavy Thick Outline")
                        container:Add("SHADOW", "Shadow")
                        container:Add("SHADOWOUTLINE", "Shadow Outline")
                        container:Add("SHADOWTHICKOUTLINE", "Shadow Thick Outline")
                        container:Add("HEAVYSHADOWTHICKOUTLINE", "Heavy Shadow Thick Outline")
                        return container:GetData()
                    end
                    addDropdown(parent, label, styleOptions, getFunc, setFunc, yRef)
                end

                -- Helper: add color picker
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
                    local function getColorTable()
                        local r, g, b, a = getFunc()
                        return { r or 1, g or 1, b or 1, a or 1 }
                    end
                    local function setColorTable(r, g, b, a)
                        setFunc(r, g, b, a)
                    end
                    local swatch = CreateColorSwatch(right, getColorTable, setColorTable, hasAlpha)
                    swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                    yRef.y = yRef.y - 34
                end

                -- Helper: add alignment dropdown
                local function addAlignment(parent, label, getFunc, setFunc, yRef)
                    local function alignOpts()
                        local c = Settings.CreateControlTextContainer()
                        c:Add("LEFT", "Left")
                        c:Add("CENTER", "Center")
                        c:Add("RIGHT", "Right")
                        return c:GetData()
                    end
                    addDropdown(parent, label, alignOpts, getFunc, setFunc, yRef)
                end

                local function fontOptions()
                    return addon.BuildFontOptionsContainer()
                end

                --------------------------------------------------------------------------------
                -- PageA: Names Text
                --------------------------------------------------------------------------------
                do
                    local y = { y = -50 }

                    -- Scale Multiplier
                    addSlider(frame.PageA, "Scale Multiplier", 0.5, 1.5, 0.05,
                        function()
                            return (db.textNames and db.textNames.scaleMultiplier) or 1.0
                        end,
                        function(v)
                            db.textNames = db.textNames or {}
                            db.textNames.scaleMultiplier = tonumber(v) or 1.0
                            applyText()
                        end,
                        y, fmtDec)

                    -- Font
                    addDropdown(frame.PageA, "Font", fontOptions,
                        function()
                            return (db.textNames and db.textNames.fontFace) or "FRIZQT__"
                        end,
                        function(v)
                            db.textNames = db.textNames or {}
                            db.textNames.fontFace = v
                            applyText()
                        end,
                        y)

                    -- Style
                    addStyle(frame.PageA, "Style",
                        function()
                            return (db.textNames and db.textNames.fontStyle) or "OUTLINE"
                        end,
                        function(v)
                            db.textNames = db.textNames or {}
                            db.textNames.fontStyle = v
                            applyText()
                        end,
                        y)

                    -- Color
                    addColor(frame.PageA, "Color", true,
                        function()
                            local c = (db.textNames and db.textNames.color) or {1,1,1,1}
                            return c[1], c[2], c[3], c[4]
                        end,
                        function(r,g,b,a)
                            db.textNames = db.textNames or {}
                            db.textNames.color = {r,g,b,a}
                            applyText()
                        end,
                        y)

                    -- Alignment
                    addAlignment(frame.PageA, "Alignment",
                        function()
                            return (db.textNames and db.textNames.alignment) or "LEFT"
                        end,
                        function(v)
                            db.textNames = db.textNames or {}
                            db.textNames.alignment = v
                            applyText()
                        end,
                        y)
                end

                --------------------------------------------------------------------------------
                -- PageB: Numbers Text
                --------------------------------------------------------------------------------
                do
                    local y = { y = -50 }

                    -- Scale Multiplier
                    addSlider(frame.PageB, "Scale Multiplier", 0.5, 1.5, 0.05,
                        function()
                            return (db.textNumbers and db.textNumbers.scaleMultiplier) or 1.0
                        end,
                        function(v)
                            db.textNumbers = db.textNumbers or {}
                            db.textNumbers.scaleMultiplier = tonumber(v) or 1.0
                            applyText()
                        end,
                        y, fmtDec)

                    -- Font
                    addDropdown(frame.PageB, "Font", fontOptions,
                        function()
                            return (db.textNumbers and db.textNumbers.fontFace) or "FRIZQT__"
                        end,
                        function(v)
                            db.textNumbers = db.textNumbers or {}
                            db.textNumbers.fontFace = v
                            applyText()
                        end,
                        y)

                    -- Style
                    addStyle(frame.PageB, "Style",
                        function()
                            return (db.textNumbers and db.textNumbers.fontStyle) or "OUTLINE"
                        end,
                        function(v)
                            db.textNumbers = db.textNumbers or {}
                            db.textNumbers.fontStyle = v
                            applyText()
                        end,
                        y)

                    -- Color
                    addColor(frame.PageB, "Color", true,
                        function()
                            local c = (db.textNumbers and db.textNumbers.color) or {1,1,1,1}
                            return c[1], c[2], c[3], c[4]
                        end,
                        function(r,g,b,a)
                            db.textNumbers = db.textNumbers or {}
                            db.textNumbers.color = {r,g,b,a}
                            applyText()
                        end,
                        y)

                    -- Alignment
                    addAlignment(frame.PageB, "Alignment",
                        function()
                            return (db.textNumbers and db.textNumbers.alignment) or "RIGHT"
                        end,
                        function(v)
                            db.textNumbers = db.textNumbers or {}
                            db.textNumbers.alignment = v
                            applyText()
                        end,
                        y)
                end
            end

            local barsInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", barsTabs)
            -- Height for 5 controls (Scale, Font, Style, Color, Alignment)
            -- Formula: 30 (top) + (5 settings * 34) + 20 (bottom) = ~220px
            barsInit.GetExtent = function() return 230 end
            barsInit:AddShownPredicate(function()
                return panel:IsSectionExpanded(componentId, "Bars")
            end)
            table.insert(init, barsInit)
        end

        -- Display the content
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then return end

        if right.SetTitle then
            right:SetTitle(component.name or "Damage Meters")
        end
        right:Display(init)

        if panel.RefreshDynamicSettingWidgets then
            C_Timer.After(0, function()
                panel:RefreshDynamicSettingWidgets(component)
            end)
        end
    end

    return {
        mode = "list",
        render = render,
        componentId = componentId,
    }
end
