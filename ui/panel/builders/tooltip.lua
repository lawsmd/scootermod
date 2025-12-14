local addonName, addon = ...
addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Tooltip renderer: Custom implementation for tooltip text styling
-- Uses a single tabbed Text section with "Title" tab
function panel.RenderTooltip()
    local render = function()
        local component = addon.Components["tooltip"]
        if not component then return end

        if panel and panel.PrepareDynamicSettingWidgets then
            panel:PrepareDynamicSettingWidgets("tooltip")
        end

        local init = {}

        -- Text Section (collapsible header)
        local textExpInit = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
            name = "Text",
            sectionKey = "Text",
            componentId = "tooltip",
            expanded = panel:IsSectionExpanded("tooltip", "Text"),
        })
        textExpInit.GetExtent = function() return 30 end
        table.insert(init, textExpInit)

        -- Tabbed Text Section data with build function
        local data = {
            sectionTitle = "",
            tabAText = "Name & Title",
            tabBText = "Line 2",
            tabCText = "Line 3",
            tabDText = "Line 4",
            tabEText = "Line 5",
            tabFText = "Line 6",
            tabGText = "Line 7",
        }

        data.build = function(frame)
            local db = component.db or {}

            -- Clean up deprecated settings from DB (color and offsets removed)
            if db.textTitle then
                db.textTitle.color = nil
                db.textTitle.offset = nil
            end

            local function applyText()
                if addon.ApplyStyles then addon:ApplyStyles() end
            end

            local function fontOptions()
                return addon.BuildFontOptionsContainer()
            end

            -- Helper: format integer for slider display
            local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end

            -- Helper: add slider control
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
                local styleOptions = function()
                    local container = Settings.CreateControlTextContainer()
                    container:Add("NONE", "Regular")
                    container:Add("OUTLINE", "Outline")
                    container:Add("THICKOUTLINE", "Thick Outline")
                    return container:GetData()
                end
                addDropdown(parent, label, styleOptions, getFunc, setFunc, yRef)
            end

            -- Helper to build a single page's controls
            local function buildPage(pageFrame, dbKey, labelPrefix, defaultSize)
                local yRef = { y = -50 }

                -- 1. Font Face
                addDropdown(pageFrame, labelPrefix .. " Font", fontOptions,
                    function()
                        return (db[dbKey] and db[dbKey].fontFace) or "FRIZQT__"
                    end,
                    function(v)
                        db[dbKey] = db[dbKey] or {}
                        db[dbKey].fontFace = v
                        applyText()
                    end,
                    yRef)

                -- 2. Font Size
                addSlider(pageFrame, labelPrefix .. " Size", 6, 32, 1,
                    function()
                        return (db[dbKey] and db[dbKey].size) or defaultSize
                    end,
                    function(v)
                        db[dbKey] = db[dbKey] or {}
                        db[dbKey].size = tonumber(v) or defaultSize
                        applyText()
                    end,
                    yRef)

                -- 3. Font Style
                addStyle(pageFrame, labelPrefix .. " Style",
                    function()
                        return (db[dbKey] and db[dbKey].style) or "OUTLINE"
                    end,
                    function(v)
                        db[dbKey] = db[dbKey] or {}
                        db[dbKey].style = v
                        applyText()
                    end,
                    yRef)
            end

            -- Build all 7 tabs
            buildPage(frame.PageA, "textTitle", "Title", 14)
            buildPage(frame.PageB, "textLine2", "Line 2", 12)
            buildPage(frame.PageC, "textLine3", "Line 3", 12)
            buildPage(frame.PageD, "textLine4", "Line 4", 12)
            buildPage(frame.PageE, "textLine5", "Line 5", 12)
            buildPage(frame.PageF, "textLine6", "Line 6", 12)
            buildPage(frame.PageG, "textLine7", "Line 7", 12)
        end

        local tabbedInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
        -- Height:
        -- Multi-row tabs (6+ tabs) require more height because the border is pushed down ~21px.
        -- Formula: 30 (top) + (3 settings * 34) + 20 (bottom) + 21 (multi-row drop) = 173 + 21 = ~194px
        -- Using 200px to be safe and provide comfortable bottom padding.
        tabbedInit.GetExtent = function() return 200 end
        tabbedInit:AddShownPredicate(function()
            return panel:IsSectionExpanded("tooltip", "Text")
        end)
        table.insert(init, tabbedInit)

        -- Visibility Section (collapsible header)
        local visExpInit = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
            name = "Visibility",
            sectionKey = "Visibility",
            componentId = "tooltip",
            expanded = panel:IsSectionExpanded("tooltip", "Visibility"),
        })
        visExpInit.GetExtent = function() return 30 end
        table.insert(init, visExpInit)

        -- Hide Tooltip Health Bar checkbox
        local db = component.db or {}
        local hideHealthBarSetting = CreateLocalSetting("Hide Tooltip Health Bar", "boolean",
            function() return not not db.hideHealthBar end,
            function(v)
                db.hideHealthBar = not not v
                if addon and addon.ApplyStyles then addon:ApplyStyles() end
            end,
            db.hideHealthBar or false
        )
        local hideHealthBarInit = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", {
            name = "Hide Tooltip Health Bar",
            setting = hideHealthBarSetting,
            options = {},
        })
        hideHealthBarInit.GetExtent = function() return 34 end
        hideHealthBarInit:AddShownPredicate(function()
            return panel:IsSectionExpanded("tooltip", "Visibility")
        end)
        -- Apply theme to checkbox
        local baseInitFrame = hideHealthBarInit.InitFrame
        hideHealthBarInit.InitFrame = function(self, frame)
            if baseInitFrame then baseInitFrame(self, frame) end
            if panel and panel.ApplyRobotoWhite then
                if frame.Text then panel.ApplyRobotoWhite(frame.Text) end
                local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
                if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
            end
        end
        table.insert(init, hideHealthBarInit)

        -- Actually display the content in the right pane
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

    return { mode = "list", render = render, componentId = "tooltip" }
end
