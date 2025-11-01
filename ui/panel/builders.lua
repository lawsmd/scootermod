local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Defensive: ensure IsSectionExpanded exists even if mixins didn't load yet
if type(panel.IsSectionExpanded) ~= "function" then
    function panel:IsSectionExpanded(componentId, sectionKey)
        self._expanded = self._expanded or {}
        self._expanded[componentId] = self._expanded[componentId] or {}
        local v = self._expanded[componentId][sectionKey]
        if v == nil then v = false end
        return v
    end
end

-- Component settings list renderers and helpers moved from ScooterSettingsPanel.lua

local function createComponentRenderer(componentId)
    return function()
        local render = function()
            local component = addon.Components[componentId]
            if not component then return end

            local init = {}
            local sections = {}
            for settingId, setting in pairs(component.settings) do
                if setting.ui and not setting.ui.hidden then
                    local section = setting.ui.section or "General"
                    if not sections[section] then sections[section] = {} end
                    table.insert(sections[section], {id = settingId, setting = setting})
                end
            end

            for _, sectionSettings in pairs(sections) do
                table.sort(sectionSettings, function(a, b) return (a.setting.ui.order or 999) < (b.setting.ui.order or 999) end)
            end

            local orderedSections = {"Positioning", "Sizing", "Style", "Border", "Backdrop", "Icon", "Text", "Misc"}
            local function RefreshCurrentCategoryDeferred()
                if panel and panel.RefreshCurrentCategoryDeferred then
                    panel.RefreshCurrentCategoryDeferred()
                end
            end
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
                            if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown then
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
                            local swatch = CreateFrame("Button", nil, right, "ColorSwatchTemplate")
                            swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                            local function update()
                                local r, g, b, a = getFunc()
                                if swatch.Color then swatch.Color:SetColorTexture(r or 1, g or 1, b or 1) end
                                swatch.a = a or 1
                            end
                            swatch:SetScript("OnClick", function()
                                local r, g, b, a = getFunc()
                                ColorPickerFrame:SetupColorPickerAndShow({
                                    r = r or 1, g = g or 1, b = b or 1,
                                    hasOpacity = hasAlpha,
                                    opacity = a or 1,
                                    swatchFunc = function()
                                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                                        local na = hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
                                        setFunc(nr, ng, nb, na)
                                        update()
                                    end,
                                    cancelFunc = function(prev)
                                        if prev then
                                            setFunc(prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1)
                                            update()
                                        end
                                    end,
                                })
                            end)
                            update()
                            yRef.y = yRef.y - 34
                        end

                        local function isActionBar()
                            local id = tostring(component and component.id or "")
                            return id:find("actionBar", 1, true) == 1
                        end

                        local tabAName, tabBName
                        if component and component.id == "trackedBuffs" then
                            tabAName, tabBName = "Stacks", "Cooldown"
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
                            if component and component.id == "trackedBuffs" then
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

                            local labelB_Font = (component and component.id == "trackedBars") and "Duration Font" or "Cooldown Font"
                            local labelB_Size = (component and component.id == "trackedBars") and "Duration Font Size" or "Cooldown Font Size"
                            local labelB_Style = (component and component.id == "trackedBars") and "Duration Style" or "Cooldown Style"
                            local labelB_Color = (component and component.id == "trackedBars") and "Duration Color" or "Cooldown Color"
                            local labelB_OffsetX = (component and component.id == "trackedBars") and "Duration Offset X" or "Cooldown Offset X"
                            local labelB_OffsetY = (component and component.id == "trackedBars") and "Duration Offset Y" or "Cooldown Offset Y"

                            addDropdown(frame.PageB, labelB_Font, fontOptions,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textDuration and db.textDuration.fontFace) or "FRIZQT__"
                                    else
                                        return (db.textCooldown and db.textCooldown.fontFace) or "FRIZQT__"
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.fontFace = v
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.fontFace = v
                                    end
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_Size, 6, 32, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textDuration and db.textDuration.size) or 14
                                    else
                                        return (db.textCooldown and db.textCooldown.size) or 16
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.size = tonumber(v) or 14
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.size = tonumber(v) or 16
                                    end
                                    applyText()
                                end,
                                yB)
                            addStyle(frame.PageB, labelB_Style,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textDuration and db.textDuration.style) or "OUTLINE"
                                    else
                                        return (db.textCooldown and db.textCooldown.style) or "OUTLINE"
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.style = v
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.style = v
                                    end
                                    applyText()
                                end,
                                yB)
                            addColor(frame.PageB, labelB_Color, true,
                                function()
                                    local c
                                    if component and component.id == "trackedBars" then
                                        c = (db.textDuration and db.textDuration.color) or {1,1,1,1}
                                    else
                                        c = (db.textCooldown and db.textCooldown.color) or {1,1,1,1}
                                    end
                                    return c[1], c[2], c[3], c[4]
                                end,
                                function(r,g,b,a)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.color = { r, g, b, a }
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.color = { r, g, b, a }
                                    end
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_OffsetX, -50, 50, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textDuration and db.textDuration.offset and db.textDuration.offset.x) or 0
                                    else
                                        return (db.textCooldown and db.textCooldown.offset and db.textCooldown.offset.x) or 0
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.offset = db.textDuration.offset or {}
                                        db.textDuration.offset.x = tonumber(v) or 0
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.offset = db.textCooldown.offset or {}
                                        db.textCooldown.offset.x = tonumber(v) or 0
                                    end
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_OffsetY, -50, 50, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textDuration and db.textDuration.offset and db.textDuration.offset.y) or 0
                                    else
                                        return (db.textCooldown and db.textCooldown.offset and db.textCooldown.offset.y) or 0
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.offset = db.textDuration.offset or {}
                                        db.textDuration.offset.y = tonumber(v) or 0
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.offset = db.textCooldown.offset or {}
                                        db.textCooldown.offset.y = tonumber(v) or 0
                                    end
                                    applyText()
                                end,
                                yB)

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
                                frame.EnableCustomTexturesRow = row
                                if row.Checkbox then
                                    row.Checkbox:SetHitRectInsets(0, -220, 0, 0)
                                end
                            end
                            if row.Text then
                                row.Text:SetText("Enable Custom Textures")
                                if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(row.Text) end
                            end
                            local checkbox = row.Checkbox
                            if checkbox then
                                checkbox:SetChecked(db.styleEnableCustom ~= false)
                                checkbox.ScooterCustomTexturesDB = db
                                checkbox.ScooterCustomTexturesRefresh = refresh
                                checkbox.ScooterCustomTexturesRefreshLayout = RefreshCurrentCategoryDeferred
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
                                        if btn.ScooterCustomTexturesRefreshLayout then
                                            btn.ScooterCustomTexturesRefreshLayout()
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
                            if addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(f.Control, setting) end
                            yRef.y = yRef.y - 34
                        end
                        local function addColor(parent, label, hasAlpha, getFunc, setFunc, yRef)
                            local f = CreateFrame("Frame", nil, parent, "SettingsListElementTemplate")
                            f:SetHeight(26)
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            f.Text:SetText(label)
                            local right = CreateFrame("Frame", nil, f)
                            right:SetSize(250, 26)
                            right:SetPoint("RIGHT", f, "RIGHT", -16, 0)
                            f.Text:ClearAllPoints()
                            f.Text:SetPoint("LEFT", f, "LEFT", 36.5, 0)
                            f.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
                            f.Text:SetJustifyH("LEFT")
                            local swatch = CreateFrame("Button", nil, right, "ColorSwatchTemplate")
                            swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                            local function update()
                                local r, g, b, a = getFunc()
                                if swatch.Color then swatch.Color:SetColorTexture(r or 1, g or 1, b or 1) end
                                swatch.a = a or 1
                            end
                            swatch:SetScript("OnClick", function()
                                local r, g, b, a = getFunc()
                                ColorPickerFrame:SetupColorPickerAndShow({
                                    r = r or 1, g = g or 1, b = b or 1,
                                    hasOpacity = true,
                                    opacity = a or 1,
                                    swatchFunc = function()
                                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                                        local na = ColorPickerFrame:GetColorAlpha()
                                        setFunc(nr, ng, nb, na)
                                        update(); refresh()
                                    end,
                                    cancelFunc = function(prev)
                                        if prev then setFunc(prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1); update(); refresh() end
                                    end,
                                })
                            end)
                            update()
                            yRef.y = yRef.y - 34
                        end
                        addDropdown(frame.PageA, "Foreground Texture", addon.BuildBarTextureOptionsContainer,
                            function() return db.styleForegroundTexture or (component.settings.styleForegroundTexture and component.settings.styleForegroundTexture.default) end,
                            function(v) db.styleForegroundTexture = v; refresh() end, yA)
                        addColor(frame.PageA, "Foreground Color", true,
                            function() local c = db.styleForegroundColor or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
                            function(r,g,b,a) db.styleForegroundColor = {r,g,b,a}; end, yA)
                        addDropdown(frame.PageB, "Background Texture", addon.BuildBarTextureOptionsContainer,
                            function() return db.styleBackgroundTexture or (component.settings.styleBackgroundTexture and component.settings.styleBackgroundTexture.default) end,
                            function(v) db.styleBackgroundTexture = v; refresh() end, yB)
                        addColor(frame.PageB, "Background Color", true,
                            function() local c = db.styleBackgroundColor or {1,1,1,0.9}; return c[1], c[2], c[3], c[4] end,
                            function(r,g,b,a) db.styleBackgroundColor = {r,g,b,a}; end, yB)
                    end
                    local initializer = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
                    initializer.GetExtent = function() return 160 end
                    initializer:AddShownPredicate(function()
                        return panel:IsSectionExpanded(component.id, "Style")
                    end)
                    table.insert(init, initializer)
                elseif (sections[sectionName] and #sections[sectionName] > 0) or (sectionName == "Border" and component and component.settings and component.settings.supportsEmptyBorderSection) or (sectionName == "Misc" and component and component.supportsEmptyVisibilitySection) then
                    local headerName = (sectionName == "Misc") and "Visibility" or sectionName

                    local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                        name = headerName,
                        sectionKey = sectionName,
                        componentId = component.id,
                        expanded = panel:IsSectionExpanded(component.id, sectionName),
                    })
                    expInitializer.GetExtent = function() return 30 end
                    table.insert(init, expInitializer)

                    for _, item in ipairs(sections[sectionName] or {}) do
                        local settingId = item.id
                        local setting = item.setting
                        local ui = setting.ui
                        local label = ui.label
                        local values = ui.values

                        if ui.dynamicLabel and settingId == "columns" then
                            label = (component.db.orientation or "H") == "H" and "# Columns" or "# Rows"
                        end

                        if ui.dynamicValues and settingId == "direction" then
                            values = ((component.db.orientation or "H") == "H") and {left="Left", right="Right"} or {up="Up", down="Down"}
                        end

                        if (sectionName == "Border" and settingId == "borderTintColor") or (sectionName == "Icon" and settingId == "iconBorderTintColor") then
                        else
                            local settingObj = CreateLocalSetting(label, ui.type or "string",
                                function()
                                    local v = component.db[settingId]
                                    if v == nil then v = setting.default end
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
                                            if addon.EditMode and addon.EditMode.SyncComponentToEditMode then
                                                addon.EditMode.SyncComponentToEditMode(component)
                                                safeSaveOnly(); requestApply()
                                            end
                                    elseif settingId == "opacity" then
                                            if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                            if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                                addon.EditMode.SyncComponentSettingToEditMode(component, "opacity")
                                                safeSaveOnly(); requestApply()
                                            end
                                        
                                    elseif settingId == "orientation" then
                                        if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.1) end
                                        if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
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
                                        local dir = component.db.direction or "right"
                                        if v == "H" then
                                            if dir ~= "left" and dir ~= "right" then component.db.direction = "right" end
                                        else
                                            if dir ~= "up" and dir ~= "down" then component.db.direction = "up" end
                                        end
                                    end

                                    addon:ApplyStyles()

                                    if ui.dynamicLabel or ui.dynamicValues or settingId == "orientation"
                                        or settingId == "iconBorderEnable" or settingId == "iconBorderTintEnable"
                                        or settingId == "iconBorderStyle"
                                        or settingId == "borderEnable" or settingId == "borderTintEnable"
                                        or settingId == "borderStyle" then
                                        RefreshCurrentCategoryDeferred()
                                    end
                                end, setting.default)

                            if ui.widget == "slider" then
                                local options = Settings.CreateSliderOptions(ui.min, ui.max, ui.step)
                                if settingId == "iconSize" then
                                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                                        local snapped = math.floor(v / 10 + 0.5) * 10
                                        return tostring(snapped)
                                    end)
                                elseif settingId == "opacity" or settingId == "opacityOutOfCombat" or settingId == "opacityWithTarget" or settingId == "barOpacity" or settingId == "barOpacityOutOfCombat" or settingId == "barOpacityWithTarget" then
                                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                                        return string.format("%d%%", math.floor((tonumber(v) or 0) + 0.5))
                                    end)
                                else
                                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
                                end
                                local data = { setting = settingObj, options = options, name = label }
                                local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", data)
                                initSlider:AddShownPredicate(function()
                                    return panel:IsSectionExpanded(component.id, sectionName)
                                end)
                                if settingId == "iconBorderThickness" or settingId == "borderThickness" then
                                    initSlider:AddShownPredicate(function()
                                        local db = component and component.db
                                        if settingId == "iconBorderThickness" then
                                            if not db or not db.iconBorderEnable then return false end
                                            return panel:IsSectionExpanded(component.id, sectionName)
                                        else
                                            if not db or not db.borderEnable then return false end
                                            return panel:IsSectionExpanded(component.id, sectionName)
                                        end
                                    end)
                                end
                                if settingId == "opacity" then
                                    initSlider.reinitializeOnValueChanged = false
                                else
                                    initSlider.reinitializeOnValueChanged = true
                                end
                                if settingId == "positionX" or settingId == "positionY" then ConvertSliderInitializerToTextInput(initSlider) end
                                if settingId == "opacity" then
                                    local baseInit = initSlider.InitFrame
                                    initSlider.InitFrame = function(self, frame)
                                        if baseInit then baseInit(self, frame) end
                                        if not frame.ScooterOpacityHooked then
                                            local original = frame.OnSettingValueChanged
                                            frame.OnSettingValueChanged = function(ctrl, setting, val)
                                                if original then pcall(original, ctrl, setting, val) end
                                                local cv = component.db.opacity or (component.settings.opacity and component.settings.opacity.default) or 100
                                                local c = ctrl:GetSetting()
                                                if c and c.SetValue and type(cv) == 'number' then
                                                    c:SetValue(cv)
                                                end
                                            end
                                            frame.ScooterOpacityHooked = true
                                        end
                                        if frame.SliderWithSteppers and frame.SliderWithSteppers.Slider then
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
                                        if lbl and lbl.SetTextColor then panel.ApplyRobotoWhite(lbl) end
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
                                    for _, valKey in ipairs(orderedValues) do containerOpts:Add(valKey, values[valKey]) end
                                    data = { setting = settingObj, options = function() return containerOpts:GetData() end, name = label }
                                end
                                local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", data)
                                local function shouldShowDropdown()
                                    if not panel:IsSectionExpanded(component.id, sectionName) then
                                        return false
                                    end
                                    if component and component.id == "trackedBars" and settingId == "borderStyle" then
                                        local db = component and component.db
                                        if not db or db.styleEnableCustom == false then return false end
                                        return db.borderEnable and db.borderEnable ~= false
                                    end
                                    if settingId == "iconBorderStyle" then
                                        local db = component and component.db
                                        return db and db.iconBorderEnable and db.iconBorderEnable ~= false
                                    end
                                    if settingId == "borderStyle" then
                                        local db = component and component.db
                                        return db and db.borderEnable and db.borderEnable ~= false
                                    end
                                    return true
                                end
                                initDrop:AddShownPredicate(shouldShowDropdown)
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
                                    elseif settingId == "borderTintEnable" then
                                            local db = component and component.db
                                        return db and db.borderEnable
                                        elseif settingId == "backdropTintEnable" then
                                            local db = component and component.db
                                            if not db or db.backdropDisable then return false end
                                            return true
                                        end
                                        return true
                                    end)
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
                                        if frame.ScooterInlineSwatch then
                                            frame.ScooterInlineSwatch:Hide()
                                        end
                                        if frame.ScooterInlineSwatchWrapper and frame.OnSettingValueChanged == frame.ScooterInlineSwatchWrapper then
                                            frame.OnSettingValueChanged = frame.ScooterInlineSwatchBase
                                        end
                                        local cb = frame.Checkbox or frame.CheckBox or frame.Control or frame
                                        if cb and cb.UnregisterCallback and SettingsCheckboxMixin and SettingsCheckboxMixin.Event and cb.ScooterInlineSwatchCallbackOwner then
                                            cb:UnregisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, cb.ScooterInlineSwatchCallbackOwner)
                                            cb.ScooterInlineSwatchCallbackOwner = nil
                                        end
                                        if cb and cb.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(cb.Text) end
                                        if frame and frame.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
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
                            end
                        end
                    end
                end
            end

            local f = panel.frame
            local settingsList = f.SettingsList
            settingsList.Header.Title:SetText(component.name or component.id)
            -- Ensure header "Copy from" control for Action Bars (1-8)
            do
                local isAB = type(component and component.id) == "string" and component.id:match("^actionBar%d$") ~= nil
                local header = settingsList and settingsList.Header
                local collapseBtn = header and header.DefaultsButton
                if header and collapseBtn then
                    -- Create once
                    if not header.ScooterCopyFromLabel then
                        local lbl = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        lbl:SetText("Copy from:")
                        if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
                        header.ScooterCopyFromLabel = lbl
                    end
                    if not header.ScooterCopyFromDropdown then
                        local dd = CreateFrame("DropdownButton", nil, header, "WowStyle1DropdownTemplate")
                        dd:SetSize(180, 22)
                        header.ScooterCopyFromDropdown = dd
                    end
                    local lbl = header.ScooterCopyFromLabel
                    local dd = header.ScooterCopyFromDropdown
                    -- Position: label to the left of dropdown; dropdown just left of Collapse All
                    dd:ClearAllPoints()
                    dd:SetPoint("RIGHT", collapseBtn, "LEFT", -24, 0)
                    lbl:ClearAllPoints()
                    lbl:SetPoint("RIGHT", dd, "LEFT", -8, 0)

                    -- Populate dropdown only on Action Bar tabs
                    if isAB and dd and dd.SetupMenu then
                        -- One-time confirmation dialog registration
                        if _G and _G.StaticPopupDialogs and not _G.StaticPopupDialogs["SCOOTERMOD_COPY_ACTIONBAR_CONFIRM"] then
                            _G.StaticPopupDialogs["SCOOTERMOD_COPY_ACTIONBAR_CONFIRM"] = {
                                text = "Copy settings from %s to %s?\nThis will overwrite all settings on the destination.",
                                button1 = "Copy",
                                button2 = CANCEL,
                                OnAccept = function(self, data)
                                    if data and addon and addon.CopyActionBarSettings then
                                        addon.CopyActionBarSettings(data.sourceId, data.destId)
                                        if data.dropdown then
                                            data.dropdown._ScooterSelectedId = data.sourceId
                                            if data.dropdown.SetText and data.sourceName then data.dropdown:SetText(data.sourceName) end
                                        end
                                        if panel and panel.RefreshCurrentCategoryDeferred then panel.RefreshCurrentCategoryDeferred() end
                                    end
                                end,
                                OnCancel = function(self, data) end,
                                timeout = 0,
                                whileDead = 1,
                                hideOnEscape = 1,
                                preferredIndex = 3,
                            }
                        end
                        local currentId = component.id
                        dd:SetupMenu(function(menu, root)
                            -- Build a list of other action bars
                            for i = 1, 8 do
                                local id = "actionBar" .. tostring(i)
                                if id ~= currentId then
                                    local comp = addon.Components and addon.Components[id]
                                    local text = (comp and comp.name) or ("Action Bar " .. tostring(i))
                                    local desc = root:CreateRadio(text, function()
                                        -- Show checked state if last chosen matches
                                        return dd._ScooterSelectedId == id
                                    end, function()
                                        -- Confirmation before destructive overwrite
                                        local which = "SCOOTERMOD_COPY_ACTIONBAR_CONFIRM"
                                        local destName = component.name or component.id
                                        local data = { sourceId = id, destId = currentId, sourceName = text, destName = destName, dropdown = dd }
                                        if _G and _G.StaticPopup_Show then
                                            _G.StaticPopup_Show(which, text, destName, data)
                                        else
                                            -- Fallback: perform copy directly if popup system is unavailable
                                            if addon and addon.CopyActionBarSettings then addon.CopyActionBarSettings(id, currentId) end
                                            dd._ScooterSelectedId = id
                                            if dd.SetText then dd:SetText(text) end
                                            if panel and panel.RefreshCurrentCategoryDeferred then panel.RefreshCurrentCategoryDeferred() end
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Ensure a neutral prompt if nothing selected yet
                        if not dd._ScooterSelectedId and dd.SetText then dd:SetText("Select a bar...") end
                    end

                    -- Visibility per tab
                    if lbl then lbl:SetShown(isAB) end
                    if dd then dd:SetShown(isAB) end
                end
            end
            settingsList:Display(init)
            local currentCategory = f.CurrentCategory
            if currentCategory and f.CatRenderers then
                local entry = f.CatRenderers[currentCategory]
                if entry then entry._lastInitializers = init end
            end
            if settingsList.RepairDisplay then pcall(settingsList.RepairDisplay, settingsList, { EnumerateInitializers = function() return ipairs(init) end, GetInitializers = function() return init end }) end
            settingsList:Show()
            f.Canvas:Hide()
        end
        return { mode = "list", render = render, componentId = componentId }
    end
end

function panel.RenderEssentialCooldowns() return createComponentRenderer("essentialCooldowns")() end
function panel.RenderUtilityCooldowns()  return createComponentRenderer("utilityCooldowns")()  end
function panel.RenderTrackedBars()       return createComponentRenderer("trackedBars")()       end
function panel.RenderTrackedBuffs()      return createComponentRenderer("trackedBuffs")()      end


-- Action Bars: simple scaffold renderers (empty collapsible sections)
local function createEmptySectionsRenderer(componentId, title)
    return function()
        local render = function()
            local f = panel.frame
            if not f or not f.SettingsList then return end

            local init = {}
            local function addHeader(sectionKey, headerName)
                local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                    name = headerName,
                    sectionKey = sectionKey,
                    componentId = componentId,
                    expanded = panel:IsSectionExpanded(componentId, sectionKey),
                })
                expInitializer.GetExtent = function() return 30 end
                table.insert(init, expInitializer)
            end

            -- Positioning, Sizing, Border, Text, Visibility (Misc header key maps to Visibility)
            addHeader("Positioning", "Positioning")
            addHeader("Sizing", "Sizing")
            addHeader("Border", "Border")
            addHeader("Text", "Text")
            addHeader("Misc", "Visibility")

            local settingsList = f.SettingsList
            settingsList.Header.Title:SetText(title or componentId)
            settingsList:Display(init)
            settingsList:Show()
            f.Canvas:Hide()
        end
        return { mode = "list", render = render, componentId = componentId }
    end
end

local function createWIPRenderer(componentId, title)
    return function()
        local render = function()
            local f = panel.frame
            if not f or not f.SettingsList then return end
            local init = {}

            local row = Settings.CreateElementInitializer("SettingsListElementTemplate")
            row.GetExtent = function() return 28 end
            row.InitFrame = function(self, frame)
                if frame and frame.Text then
                    frame.Text:SetText("Work in progress")
                    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
                end
            end
            table.insert(init, row)

            local settingsList = f.SettingsList
            settingsList.Header.Title:SetText(title or componentId)
            settingsList:Display(init)
            settingsList:Show()
            f.Canvas:Hide()
        end
        return { mode = "list", render = render, componentId = componentId }
    end
end

-- Export Action Bars renderers
function panel.RenderActionBar1()  return createComponentRenderer("actionBar1")() end
function panel.RenderActionBar2()  return createComponentRenderer("actionBar2")() end
function panel.RenderActionBar3()  return createComponentRenderer("actionBar3")() end
function panel.RenderActionBar4()  return createComponentRenderer("actionBar4")() end
function panel.RenderActionBar5()  return createComponentRenderer("actionBar5")() end
function panel.RenderActionBar6()  return createComponentRenderer("actionBar6")() end
function panel.RenderActionBar7()  return createComponentRenderer("actionBar7")() end
function panel.RenderActionBar8()  return createComponentRenderer("actionBar8")() end
function panel.RenderStanceBar()   return createWIPRenderer("stanceBar",   "Stance Bar")()   end
function panel.RenderMicroBar()    return createWIPRenderer("microBar",    "Micro Bar")()    end

