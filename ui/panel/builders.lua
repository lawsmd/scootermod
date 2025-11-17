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

-- Helper: temporarily pause mousewheel scrolling on the right-hand SettingsList to avoid
-- racing layout during short write windows (e.g., immediate scroll after a toggle)
function panel:PauseScrollWheel(duration)
    local f = self.frame
    local sl = f and f.SettingsList
    if not sl then return end
    if not sl._wheelBlocker then
        local blocker = CreateFrame("Frame", nil, sl)
        blocker:SetAllPoints(sl)
        blocker:EnableMouse(true)
        blocker:EnableMouseWheel(true)
        blocker:SetScript("OnMouseWheel", function() end)
        blocker:Hide()
        sl._wheelBlocker = blocker
    end
    local blocker = sl._wheelBlocker
    blocker:Show()
    if blocker._timer and blocker._timer.Cancel then blocker._timer:Cancel() end
    blocker._timer = C_Timer.NewTimer(duration or 0.25, function()
        if blocker then blocker:Hide() end
    end)
end

-- Component settings list renderers and helpers moved from ScooterSettingsPanel.lua

local function createComponentRenderer(componentId)
    return function()
        local render = function()
            local component = addon.Components[componentId]
            if not component then return end

            local init = {}
            local sections = {}
            -- Store refresh functions for Border/Backdrop sections to call after Display completes
            local borderRefreshFunc = nil
            local backdropRefreshFunc = nil
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
                                -- Theme the label: Roboto + white (override Blizzard yellow)
                                if panel and panel.ApplyRobotoWhite then
                                    if f.Text then panel.ApplyRobotoWhite(f.Text) end
                                    local cb = f.Checkbox or f.CheckBox or (f.Control and f.Control.Checkbox)
                                    if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
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
                                        if btn.ScooterUpdateStyleControlsState then
                                            btn.ScooterUpdateStyleControlsState()
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
                            if panel and panel.ApplyRobotoWhite then
                                local lbl = f and (f.Text or f.Label)
                                if lbl then panel.ApplyRobotoWhite(lbl) end
                            end
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
                elseif (sections[sectionName] and #sections[sectionName] > 0) or (sectionName == "Border" and component and component.settings and component.settings.supportsEmptyBorderSection) or (sectionName == "Misc" and component and component.supportsEmptyVisibilitySection) then
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

                    -- Track Border section controls for Cooldown Manager groups and Action Bars to enable graying out
                    local isCDMBorder = (sectionName == "Border") and (
                        component.id == "essentialCooldowns" or 
                        component.id == "utilityCooldowns" or 
                        component.id == "trackedBuffs" or 
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

                        if ui.dynamicValues and settingId == "direction" then
                            values = ((component.db.orientation or "H") == "H") and {left="Left", right="Right"} or {up="Up", down="Down"}
                        end

                        if (sectionName == "Border" and settingId == "borderTintColor") or (sectionName == "Icon" and settingId == "iconBorderTintColor") then
                        else
                            local settingObj = CreateLocalSetting(label, ui.type or "string",
                                function()
                                    local v = component.db[settingId]
                                    if v == nil then v = setting.default end
                                    -- Coerce direction to a valid option for current orientation to avoid transient 'Custom'
                                    if settingId == "direction" then
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
                                        -- Pre-adjust direction to a valid option for the new orientation BEFORE syncing, to avoid transient 'Custom'
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
                                        -- Hold re-render just a bit longer to let both writes settle
                                        if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                        -- Hide the direction control very briefly to avoid 'Custom' while options swap
                                        if panel then panel._dirReinitHoldUntil = (GetTime and (GetTime() + 0.25)) or (panel._dirReinitHoldUntil or 0) end
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
                                        or settingId == "borderStyle" or settingId == "backdropDisable" then
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
                                if settingId == "positionX" or settingId == "positionY" then ConvertSliderInitializerToTextInput(initSlider) end
                                if settingId == "opacity" or settingId == "barOpacity" then
                                    local baseInit = initSlider.InitFrame
                                    initSlider.InitFrame = function(self, frame)
                                        if baseInit then baseInit(self, frame) end
                                        if not frame.ScooterOpacityHooked then
                                            local original = frame.OnSettingValueChanged
                                            frame.OnSettingValueChanged = function(ctrl, setting, val)
                                                if original then pcall(original, ctrl, setting, val) end
                                                local cv = component.db.opacity or component.db.barOpacity or (component.settings.opacity and component.settings.opacity.default) or (component.settings.barOpacity and component.settings.barOpacity.default) or 100
                                                local c = ctrl:GetSetting()
                                                if c and c.SetValue and type(cv) == 'number' then
                                                    c:SetValue(cv)
                                                end
                                            end
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
                                                local tooltipText = "Opacity priority: With Target takes precedence, then In Combat (this slider), then Out of Combat. The highest priority condition that applies determines the opacity."
                                                -- Position icon next to the label text ("Opacity"), not the slider
                                                local label = frame.Text or frame.Label
                                                if label and panel and panel.CreateInfoIcon then
                                                    -- Create icon using the helper function, which anchors to label's right edge
                                                    frame.ScooterOpacityInfoIcon = panel.CreateInfoIconForLabel(label, tooltipText, 5, 0, 32)
                                                    -- Defer positioning to ensure label is laid out first, then adjust based on actual text width
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
                                                        end
                                                    end)
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
                                elseif settingId == "direction" then
                                    local containerOpts = Settings.CreateControlTextContainer()
                                    local orientation = component and component.db and (component.db.orientation or "H") or "H"
                                    local orderedValues = {}
                                    if orientation == "H" then
                                        table.insert(orderedValues, "right")
                                        table.insert(orderedValues, "left")
                                    else
                                        table.insert(orderedValues, "up")
                                        table.insert(orderedValues, "down")
                                    end
                                    for _, valKey in ipairs(orderedValues) do containerOpts:Add(valKey, values[valKey]) end
                                    data = { setting = settingObj, options = function() return containerOpts:GetData() end, name = label }
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
                                if settingId == "direction" then
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
                                            local isUnitFrameComponent = (component.id == "ufPlayer" or component.id == "ufTarget" or component.id == "ufFocus" or component.id == "ufPet")
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

            -- Ensure header "Copy from" control for Unit Frames (Player/Target/Focus)
            do
                local isUF = (componentId == "ufPlayer") or (componentId == "ufTarget") or (componentId == "ufFocus")
                local header = settingsList and settingsList.Header
                local collapseBtn = header and (header.DefaultsButton or header.CollapseAllButton or header.CollapseButton)
                if header then
                    -- Create once (shared with Action Bars header controls)
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
                    -- Position: always anchor to header's top-right to avoid template differences
                    if dd and lbl then
                        dd:ClearAllPoints()
                        dd:SetPoint("TOPRIGHT", header, "TOPRIGHT", -24, 0)
                        lbl:ClearAllPoints()
                        lbl:SetPoint("RIGHT", dd, "LEFT", -8, 0)
                    end

                    -- Confirmation and error dialogs (one-time registration)
                    if _G and _G.StaticPopupDialogs and not _G.StaticPopupDialogs["SCOOTERMOD_COPY_UF_CONFIRM"] then
                        _G.StaticPopupDialogs["SCOOTERMOD_COPY_UF_CONFIRM"] = {
                            text = "Copy supported Unit Frame settings from %s to %s?",
                            button1 = "Copy",
                            button2 = CANCEL,
                            OnAccept = function(self, data)
                                if data and addon and addon.EditMode and addon.EditMode.CopyUnitFrameFrameSize then
                                    local ok, err = addon.EditMode.CopyUnitFrameFrameSize(data.sourceUnit, data.destUnit)
                                    if addon and addon.CopyUnitFrameTextSettings then
                                        pcall(addon.CopyUnitFrameTextSettings, data.sourceUnit, data.destUnit)
                                    end
                                    if addon and addon.CopyUnitFramePowerTextSettings then
                                        pcall(addon.CopyUnitFramePowerTextSettings, data.sourceUnit, data.destUnit)
                                    end
                                    if addon and addon.CopyUnitFrameBarStyleSettings then
                                        pcall(addon.CopyUnitFrameBarStyleSettings, data.sourceUnit, data.destUnit)
                                    end
                                    if ok then
                                        if data.dropdown then
                                            data.dropdown._ScooterSelectedId = data.sourceUnit
                                            if data.dropdown.SetText and data.sourceLabel then data.dropdown:SetText(data.sourceLabel) end
                                        end
                                        if panel and panel.RefreshCurrentCategoryDeferred then panel.RefreshCurrentCategoryDeferred() end
                                    else
                                        if _G and _G.StaticPopup_Show then
                                            local msg
                                            if err == "focus_requires_larger" then
                                                msg = "Cannot copy to Focus unless 'Use Larger Frame' is enabled."
                                            elseif err == "pet_excluded" then
                                                msg = "Pet is excluded from copy operations."
                                            else
                                                msg = "Copy failed. Please try again."
                                            end
                                            _G.StaticPopupDialogs["SCOOTERMOD_COPY_UF_ERROR"] = _G.StaticPopupDialogs["SCOOTERMOD_COPY_UF_ERROR"] or {
                                                text = "%s",
                                                button1 = OKAY,
                                                timeout = 0,
                                                whileDead = 1,
                                                hideOnEscape = 1,
                                                preferredIndex = 3,
                                            }
                                            _G.StaticPopup_Show("SCOOTERMOD_COPY_UF_ERROR", msg)
                                        end
                                    end
                                end
                            end,
                            OnCancel = function(self, data) end,
                            timeout = 0,
                            whileDead = 1,
                            hideOnEscape = 1,
                            preferredIndex = 3,
                        }
                    end

                    -- Populate dropdown only on UF tabs (Player/Target/Focus). Pet excluded entirely.
                    if isUF and dd and dd.SetupMenu then
                        local currentId = componentId
                        local function unitLabelFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return id
                        end
                        local function unitKeyFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return nil
                        end
                        dd:SetupMenu(function(menu, root)
                            local candidates = { "ufPlayer", "ufTarget", "ufFocus" } -- Pet excluded
                            for _, id in ipairs(candidates) do
                                if id ~= currentId then
                                    local text = unitLabelFor(id)
                                    root:CreateRadio(text, function()
                                        return dd._ScooterSelectedId == id
                                    end, function()
                                        local which = "SCOOTERMOD_COPY_UF_CONFIRM"
                                        local destLabel = unitLabelFor(currentId)
                                        local data = { sourceUnit = unitKeyFor(id), destUnit = unitKeyFor(currentId), sourceLabel = text, destLabel = destLabel, dropdown = dd }
                                        if _G and _G.StaticPopup_Show then
                                            _G.StaticPopup_Show(which, text, destLabel, data)
                                        else
                                            -- Fallback: perform copy directly if popup system is unavailable
                                            if addon and addon.EditMode and addon.EditMode.CopyUnitFrameFrameSize then
                                                local ok = addon.EditMode.CopyUnitFrameFrameSize(data.sourceUnit, data.destUnit)
                                                if addon and addon.CopyUnitFrameTextSettings then pcall(addon.CopyUnitFrameTextSettings, data.sourceUnit, data.destUnit) end
                                                if addon and addon.CopyUnitFramePowerTextSettings then pcall(addon.CopyUnitFramePowerTextSettings, data.sourceUnit, data.destUnit) end
                                                if addon and addon.CopyUnitFrameBarStyleSettings then pcall(addon.CopyUnitFrameBarStyleSettings, data.sourceUnit, data.destUnit) end
                                                if ok then
                                                    dd._ScooterSelectedId = id
                                                    if dd.SetText then dd:SetText(text) end
                                                    if panel and panel.RefreshCurrentCategoryDeferred then panel.RefreshCurrentCategoryDeferred() end
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Ensure a neutral prompt if nothing selected yet
                        if dd.SetShown then dd:SetShown(true) end
                        if lbl and lbl.SetShown then lbl:SetShown(true) end
                        if not dd._ScooterSelectedId and dd.SetText then dd:SetText("Select a frame...") end
                    end

                    -- Visibility per tab
                    if lbl then lbl:SetShown(isUF) end
                    if dd then dd:SetShown(isUF) end
                end
            end

            settingsList:Display(init)
            -- Ensure header "Copy from" is present AFTER Display as well (some templates rebuild header)
            do
                local isUF = (componentId == "ufPlayer") or (componentId == "ufTarget") or (componentId == "ufFocus")
                local header = settingsList and settingsList.Header
                if header then
                    local lbl = header.ScooterCopyFromLabel
                    local dd = header.ScooterCopyFromDropdown
                    if not lbl or not dd then
                        -- Recreate if missing
                        if not header.ScooterCopyFromLabel then
                            local l = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                            l:SetText("Copy from:")
                            if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(l) end
                            header.ScooterCopyFromLabel = l
                        end
                        if not header.ScooterCopyFromDropdown then
                            local d = CreateFrame("DropdownButton", nil, header, "WowStyle1DropdownTemplate")
                            d:SetSize(180, 22)
                            header.ScooterCopyFromDropdown = d
                        end
                        lbl = header.ScooterCopyFromLabel
                        dd  = header.ScooterCopyFromDropdown
                        if dd and lbl then
                            dd:ClearAllPoints(); dd:SetPoint("TOPRIGHT", header, "TOPRIGHT", -24, 0)
                            lbl:ClearAllPoints(); lbl:SetPoint("RIGHT", dd, "LEFT", -8, 0)
                        end
                    end
                    if isUF and dd and dd.SetupMenu then
                        local function unitLabelFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return id
                        end
                        local function unitKeyFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return nil
                        end
                        local currentId = componentId
                        dd:SetupMenu(function(menu, root)
                            local candidates = { "ufPlayer", "ufTarget", "ufFocus" }
                            for _, id in ipairs(candidates) do
                                if id ~= currentId then
                                    local text = unitLabelFor(id)
                                    root:CreateRadio(text, function() return dd._ScooterSelectedId == id end, function()
                                        local which = "SCOOTERMOD_COPY_UF_CONFIRM"
                                        local destLabel = unitLabelFor(currentId)
                                        local data = { sourceUnit = unitKeyFor(id), destUnit = unitKeyFor(currentId), sourceLabel = text, destLabel = destLabel, dropdown = dd }
                                        if _G and _G.StaticPopup_Show then
                                            _G.StaticPopup_Show(which, text, destLabel, data)
                                        else
                                            if addon and addon.EditMode and addon.EditMode.CopyUnitFrameFrameSize then
                                                local ok = addon.EditMode.CopyUnitFrameFrameSize(data.sourceUnit, data.destUnit)
                                                if addon and addon.CopyUnitFrameTextSettings then pcall(addon.CopyUnitFrameTextSettings, data.sourceUnit, data.destUnit) end
                                                if addon and addon.CopyUnitFramePowerTextSettings then pcall(addon.CopyUnitFramePowerTextSettings, data.sourceUnit, data.destUnit) end
                                                if addon and addon.CopyUnitFrameBarStyleSettings then pcall(addon.CopyUnitFrameBarStyleSettings, data.sourceUnit, data.destUnit) end
                                                if ok then
                                                    dd._ScooterSelectedId = id
                                                    if dd.SetText then dd:SetText(text) end
                                                    if panel and panel.RefreshCurrentCategoryDeferred then panel.RefreshCurrentCategoryDeferred() end
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end)
                        if not dd._ScooterSelectedId and dd.SetText then dd:SetText("Select a frame...") end
                        if lbl then lbl:SetShown(true) end
                        if dd then dd:SetShown(true) end
                    else
                        if lbl then lbl:SetShown(false) end
                        if dd then dd:SetShown(false) end
                    end
                end
            end
            -- Mirror Action Bars post-display repair to ensure header children are laid out
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

            -- Ensure header "Copy from" control for Unit Frames (Player/Target/Focus)
            do
                local isUF = (componentId == "ufPlayer") or (componentId == "ufTarget") or (componentId == "ufFocus")
                local header = settingsList and settingsList.Header
                if header then
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
                    -- Anchor to the left of Collapse All/Defaults if available, else top-right fallback
                    if dd and lbl then
                        local collapseBtn = header and (header.CollapseAllButton or header.CollapseButton or header.DefaultsButton)
                        dd:ClearAllPoints()
                        if collapseBtn then
                            dd:SetPoint("RIGHT", collapseBtn, "LEFT", -24, 0)
                        else
                            dd:SetPoint("TOPRIGHT", header, "TOPRIGHT", -24, 0)
                        end
                        lbl:ClearAllPoints()
                        lbl:SetPoint("RIGHT", dd, "LEFT", -8, 0)
                    end

                    -- Populate dropdown only on UF tabs (exclude Pet)
                    if isUF and dd and dd.SetupMenu then
                        local function unitLabelFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return id
                        end
                        local function unitKeyFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return nil
                        end
                        local currentId = componentId
                        dd:SetupMenu(function(menu, root)
                            local candidates = { "ufPlayer", "ufTarget", "ufFocus" }
                            for _, id in ipairs(candidates) do
                                if id ~= currentId then
                                    local text = unitLabelFor(id)
                                    root:CreateRadio(text, function()
                                        return dd._ScooterSelectedId == id
                                    end, function()
                                        local which = "SCOOTERMOD_COPY_UF_CONFIRM"
                                        local destLabel = unitLabelFor(currentId)
                                        local data = { sourceUnit = unitKeyFor(id), destUnit = unitKeyFor(currentId), sourceLabel = text, destLabel = destLabel, dropdown = dd }
                                        if _G and _G.StaticPopup_Show then
                                            _G.StaticPopup_Show(which, text, destLabel, data)
                                        else
                                            if addon and addon.EditMode and addon.EditMode.CopyUnitFrameFrameSize then
                                                local ok = addon.EditMode.CopyUnitFrameFrameSize(data.sourceUnit, data.destUnit)
                                                if ok then
                                                    dd._ScooterSelectedId = id
                                                    if dd.SetText then dd:SetText(text) end
                                                    if panel and panel.RefreshCurrentCategoryDeferred then panel.RefreshCurrentCategoryDeferred() end
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end)
                        if not dd._ScooterSelectedId and dd.SetText then dd:SetText("Select a frame...") end
                        if lbl then lbl:SetShown(true) end
                        if dd then dd:SetShown(true) end
                    end

                    -- Visibility per tab
                    if lbl then lbl:SetShown(isUF) end
                    if dd then dd:SetShown(isUF) end
                end
            end

            settingsList:Display(init)

            -- Post-Display: ensure header controls still exist (some templates rebuild header)
            do
                local isUF = (componentId == "ufPlayer") or (componentId == "ufTarget") or (componentId == "ufFocus")
                local header = settingsList and settingsList.Header
                if header then
                    local lbl = header.ScooterCopyFromLabel
                    local dd = header.ScooterCopyFromDropdown
                    if not lbl or not dd then
                        if not header.ScooterCopyFromLabel then
                            local l = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                            l:SetText("Copy from:")
                            if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(l) end
                            header.ScooterCopyFromLabel = l
                        end
                        if not header.ScooterCopyFromDropdown then
                            local d = CreateFrame("DropdownButton", nil, header, "WowStyle1DropdownTemplate")
                            d:SetSize(180, 22)
                            header.ScooterCopyFromDropdown = d
                        end
                        lbl = header.ScooterCopyFromLabel
                        dd  = header.ScooterCopyFromDropdown
                        if dd and lbl then
                            local collapseBtn = header and (header.CollapseAllButton or header.CollapseButton or header.DefaultsButton)
                            dd:ClearAllPoints()
                            if collapseBtn then
                                dd:SetPoint("RIGHT", collapseBtn, "LEFT", -24, 0)
                            else
                                dd:SetPoint("TOPRIGHT", header, "TOPRIGHT", -24, 0)
                            end
                            lbl:ClearAllPoints(); lbl:SetPoint("RIGHT", dd, "LEFT", -8, 0)
                        end
                    end
                    if isUF and dd and dd.SetupMenu then
                        local function unitLabelFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return id
                        end
                        local function unitKeyFor(id)
                            if id == "ufPlayer" then return "Player" end
                            if id == "ufTarget" then return "Target" end
                            if id == "ufFocus"  then return "Focus" end
                            return nil
                        end
                        local currentId = componentId
                        dd:SetupMenu(function(menu, root)
                            local candidates = { "ufPlayer", "ufTarget", "ufFocus" }
                            for _, id in ipairs(candidates) do
                                if id ~= currentId then
                                    local text = unitLabelFor(id)
                                    root:CreateRadio(text, function() return dd._ScooterSelectedId == id end, function()
                                        local which = "SCOOTERMOD_COPY_UF_CONFIRM"
                                        local destLabel = unitLabelFor(currentId)
                                        local data = { sourceUnit = unitKeyFor(id), destUnit = unitKeyFor(currentId), sourceLabel = text, destLabel = destLabel, dropdown = dd }
                                        if _G and _G.StaticPopup_Show then
                                            _G.StaticPopup_Show(which, text, destLabel, data)
                                        else
                                            if addon and addon.EditMode and addon.EditMode.CopyUnitFrameFrameSize then
                                                local ok = addon.EditMode.CopyUnitFrameFrameSize(data.sourceUnit, data.destUnit)
                                                if ok then
                                                    dd._ScooterSelectedId = id
                                                    if dd.SetText then dd:SetText(text) end
                                                    if panel and panel.RefreshCurrentCategoryDeferred then panel.RefreshCurrentCategoryDeferred() end
                                                end
                                            end
                                        end
                                    end)
                                end
                            end
                        end)
                        if not dd._ScooterSelectedId and dd.SetText then dd:SetText("Select a frame...") end
                        if lbl then lbl:SetShown(true) end
                        if dd then dd:SetShown(true) end
                    else
                        if lbl then lbl:SetShown(false) end
                        if dd then dd:SetShown(false) end
                    end
                end
            end

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
function panel.RenderStanceBar()   return createComponentRenderer("stanceBar")()           end
function panel.RenderMicroBar()    return createComponentRenderer("microBar")()              end

-- Unit Frames placeholder renderers -------------------------------------------
local function createUFRenderer(componentId, title)
        local render = function()
            local f = panel.frame
            if not f or not f.SettingsList then return end

            local init = {}

			-- Top-level Parent Frame rows (no collapsible or tabs)
			-- Shared helpers for the four unit frames
			local function getUiScale()
				return (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
			end
			local function pixelsToUiUnits(px)
				local s = getUiScale()
				if s == 0 then return 0 end
				return px / s
			end
			local function uiUnitsToPixels(u)
				local s = getUiScale()
				return math.floor((u * s) + 0.5)
			end
			local function getUnitFrame()
				local mgr = _G.EditModeManagerFrame
				local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
				local EMSys = _G.Enum and _G.Enum.EditModeSystem
				if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
				local idx = (componentId == "ufPlayer" and EM.Player)
					or (componentId == "ufTarget" and EM.Target)
					or (componentId == "ufFocus" and EM.Focus)
					or (componentId == "ufPet" and EM.Pet)
					or nil
				if not idx then return nil end
				return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
			end
			local function readOffsets()
				local fUF = getUnitFrame()
				if not fUF then return 0, 0 end
				if fUF.GetPoint then
					local p, relTo, rp, ox, oy = fUF:GetPoint(1)
					if p == "CENTER" and rp == "CENTER" and relTo == UIParent and type(ox) == "number" and type(oy) == "number" then
						return uiUnitsToPixels(ox), uiUnitsToPixels(oy)
					end
				end
				if not (fUF.GetCenter and UIParent and UIParent.GetCenter) then return 0, 0 end
				local fx, fy = fUF:GetCenter()
				local px, py = UIParent:GetCenter()
				if not (fx and fy and px and py) then return 0, 0 end
				return math.floor((fx - px) + 0.5), math.floor((fy - py) + 0.5)
			end
			local _pendingPxX, _pendingPxY, _pendingWriteTimer
			local function writeOffsets(newX, newY)
				local fUF = getUnitFrame()
				if not fUF then return end
				local curPxX, curPxY = readOffsets()
				_pendingPxX = (newX ~= nil) and clampPositionValue(roundPositionValue(newX)) or curPxX
				_pendingPxY = (newY ~= nil) and clampPositionValue(roundPositionValue(newY)) or curPxY
				if _pendingWriteTimer and _pendingWriteTimer.Cancel then _pendingWriteTimer:Cancel() end
				_pendingWriteTimer = C_Timer.NewTimer(0.1, function()
					local pxX = clampPositionValue(roundPositionValue(_pendingPxX or 0))
					local pxY = clampPositionValue(roundPositionValue(_pendingPxY or 0))
					local ux = pixelsToUiUnits(pxX)
					local uy = pixelsToUiUnits(pxY)
					-- Normalize anchor once if needed
					if fUF.GetPoint then
						local p, relTo, rp = fUF:GetPoint(1)
						if not (p == "CENTER" and rp == "CENTER" and relTo == UIParent) then
							if fUF.GetCenter and UIParent and UIParent.GetCenter then
								local fx, fy = fUF:GetCenter(); local cx, cy = UIParent:GetCenter()
								if fx and fy and cx and cy then
									local curUx = pixelsToUiUnits((fx - cx))
									local curUy = pixelsToUiUnits((fy - cy))
									if addon and addon.EditMode and addon.EditMode.ReanchorFrame then
										addon.EditMode.ReanchorFrame(fUF, "CENTER", UIParent, "CENTER", curUx, curUy)
										if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
									end
								end
							end
						end
					end
					if addon and addon.EditMode and addon.EditMode.ReanchorFrame then
						addon.EditMode.ReanchorFrame(fUF, "CENTER", UIParent, "CENTER", ux, uy)
						if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
						if fUF and fUF.ClearAllPoints and fUF.SetPoint then
							fUF:ClearAllPoints()
							fUF:SetPoint("CENTER", UIParent, "CENTER", ux, uy)
						end
					end
				end)
			end

			-- X Position (px)
			do
				local label = "X Position (px)"
				local options = Settings.CreateSliderOptions(-1000, 1000, 1)
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(roundPositionValue(v)) end)
				local setting = CreateLocalSetting(label, "number",
					function() local x = readOffsets(); return x end,
					function(v) writeOffsets(v, nil) end,
					0)
				local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
				row.GetExtent = function() return 34 end
				-- Present as numeric text input (previous behavior), not a slider
				if ConvertSliderInitializerToTextInput then ConvertSliderInitializerToTextInput(row) end
				do
					local base = row.InitFrame
					row.InitFrame = function(self, frame)
						if base then base(self, frame) end
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
						if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
					end
				end
				table.insert(init, row)
			end

			-- Y Position (px)
			do
				local label = "Y Position (px)"
				local options = Settings.CreateSliderOptions(-1000, 1000, 1)
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(roundPositionValue(v)) end)
				local setting = CreateLocalSetting(label, "number",
					function() local _, y = readOffsets(); return y end,
					function(v) writeOffsets(nil, v) end,
					0)
				local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
				row.GetExtent = function() return 34 end
				-- Present as numeric text input (previous behavior), not a slider
				if ConvertSliderInitializerToTextInput then ConvertSliderInitializerToTextInput(row) end
				do
					local base = row.InitFrame
					row.InitFrame = function(self, frame)
						if base then base(self, frame) end
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
						if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
					end
				end
				table.insert(init, row)
			end

			-- Player-only: Cast Bar Underneath
			if componentId == "ufPlayer" then
				local function getUF()
					return getUnitFrame()
				end
				local function getCastBar()
					local mgr = _G.EditModeManagerFrame
					local EMSys = _G.Enum and _G.Enum.EditModeSystem
					if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
					return mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
				end
				local label = "Cast Bar Underneath"
				local function getter()
					-- Prefer Unit Frame setting when available (EditMode dump shows index [1] on PlayerFrame)
					local frameUF = getUF()
					local UFSetting = _G.Enum and _G.Enum.EditModeUnitFrameSetting
					local sidUF = UFSetting and UFSetting.CastBarUnderneath or 1
					if frameUF and sidUF and addon and addon.EditMode and addon.EditMode.GetSetting then
						local v = addon.EditMode.GetSetting(frameUF, sidUF)
						if v ~= nil then return (tonumber(v) or 0) ~= 0 end
					end
					-- Fallback to Cast Bar system's lock (legacy)
					local frameCB = getCastBar()
					local sidCB = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.LockToPlayerFrame
					if frameCB and sidCB and addon and addon.EditMode and addon.EditMode.GetSetting then
						local v = addon.EditMode.GetSetting(frameCB, sidCB)
						return (tonumber(v) or 0) ~= 0
					end
					return false
				end
				local function setter(b)
					local val = (b and true) and 1 or 0
					-- Fix note (2025-11-06): Mirror this toggle to BOTH Unit Frame [CastBarUnderneath]
					-- and Cast Bar [LockToPlayerFrame], then call UpdateSystem/RefreshLayout, SaveOnly(),
					-- and a coalesced RequestApplyChanges(). This ensures the on-screen element updates
					-- immediately and the Edit Mode checkbox reflects the new value without needing a reopen.
					-- Write to Unit Frame setting first
					do
						local frameUF = getUF()
						local UFSetting = _G.Enum and _G.Enum.EditModeUnitFrameSetting
						local sidUF = UFSetting and UFSetting.CastBarUnderneath or 1
						if frameUF and sidUF and addon and addon.EditMode and addon.EditMode.SetSetting then
							addon.EditMode.SetSetting(frameUF, sidUF, val)
							-- Try immediate visual refresh on the unit frame
							if type(frameUF.UpdateSystem) == "function" then pcall(frameUF.UpdateSystem, frameUF) end
							if type(frameUF.RefreshLayout) == "function" then pcall(frameUF.RefreshLayout, frameUF) end
							if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
						end
					end
					-- Also mirror to Cast Bar system to ensure immediate visual update
					do
						local frameCB = getCastBar()
						local sidCB = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.LockToPlayerFrame
						if frameCB and sidCB and addon and addon.EditMode and addon.EditMode.SetSetting then
							addon.EditMode.SetSetting(frameCB, sidCB, val)
							if type(frameCB.UpdateSystemSettingLockToPlayerFrame) == "function" then pcall(frameCB.UpdateSystemSettingLockToPlayerFrame, frameCB) end
							if type(frameCB.UpdateSystem) == "function" then pcall(frameCB.UpdateSystem, frameCB) end
							if type(frameCB.RefreshLayout) == "function" then pcall(frameCB.RefreshLayout, frameCB) end
							if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
						end
					end
					-- Coalesced apply to propagate to Edit Mode UI immediately
					if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
					if panel and panel.SuspendRefresh then panel.SuspendRefresh(0.5) end
				end
				local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
				local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
				row.GetExtent = function() return 34 end
				do
					local base = row.InitFrame
					row.InitFrame = function(self, frame)
						if base then base(self, frame) end
                        -- Remove any stray info icon from recycled rows; this row does not use an info icon
                        if frame and frame.ScooterInfoIcon then
                            -- Keep only if explicitly tagged for this exact row (none are)
                            frame.ScooterInfoIcon:Hide()
                            frame.ScooterInfoIcon:SetParent(nil)
                            frame.ScooterInfoIcon = nil
                        end
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
						if panel and panel.ApplyRobotoWhite then
							if frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
							local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
						end
					end
				end
				table.insert(init, row)
			end

			-- Focus-only: Use Larger Frame
			if componentId == "ufFocus" then
				local label = "Use Larger Frame"
				local function getUF() return getUnitFrame() end
				local function getter()
					local frameUF = getUF()
					local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.UseLargerFrame
					if frameUF and settingId and addon and addon.EditMode and addon.EditMode.GetSetting then
						local v = addon.EditMode.GetSetting(frameUF, settingId)
						return (v and v ~= 0) and true or false
					end
					return false
				end
				local function setter(b)
					local frameUF = getUF()
					local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.UseLargerFrame
					local val = (b and true) and 1 or 0
					if frameUF and settingId and addon and addon.EditMode and addon.EditMode.SetSetting then
						addon.EditMode.SetSetting(frameUF, settingId, val)
						if type(frameUF.UpdateSystemSettingFrameSize) == "function" then pcall(frameUF.UpdateSystemSettingFrameSize, frameUF) end
						if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
						if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
					end
				end
				local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
				local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
				row.GetExtent = function() return 34 end
				do
					local base = row.InitFrame
					row.InitFrame = function(self, frame)
						if base then base(self, frame) end
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
						if panel and panel.ApplyRobotoWhite then
							if frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
							local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
						end
					end
				end
				table.insert(init, row)
			end

			-- Frame Size (all four)
			do
				local label = "Frame Size (Scale)"
				local function getUF() return getUnitFrame() end
				local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
				local options = Settings.CreateSliderOptions(100, 200, 5)
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
				local function getter()
					local frameUF = getUF()
					local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.FrameSize
					if frameUF and settingId and addon and addon.EditMode and addon.EditMode.GetSetting then
						local v = addon.EditMode.GetSetting(frameUF, settingId)
						if v == nil then return 100 end
						if v <= 20 then return 100 + (v * 5) end
						return math.max(100, math.min(200, v))
					end
					return 100
				end
				local function setter(raw)
					local frameUF = getUF()
					local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.FrameSize
					local val = tonumber(raw) or 100
					val = math.max(100, math.min(200, val))
					if frameUF and settingId and addon and addon.EditMode and addon.EditMode.SetSetting then
						addon.EditMode.SetSetting(frameUF, settingId, val)
						if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
						if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
					end
				end
				local setting = CreateLocalSetting(label, "number", getter, setter, getter())
				local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
				row.GetExtent = function() return 34 end
				do
					local base = row.InitFrame
					row.InitFrame = function(self, frame)
						if base then base(self, frame) end
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
						if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
					end
				end
				table.insert(init, row)
			end

		-- Use Custom Borders (hide stock frame art to allow custom bar-only borders)
		if componentId == "ufPlayer" or componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet" then
			local unitKey
			if componentId == "ufPlayer" then unitKey = "Player"
			elseif componentId == "ufTarget" then unitKey = "Target"
			elseif componentId == "ufFocus" then unitKey = "Focus"
			elseif componentId == "ufPet" then unitKey = "Pet"
			end

			local label = "Use Custom Borders"
			local function ensureUFDB()
				local db = addon and addon.db and addon.db.profile
				if not db then return nil end
				db.unitFrames = db.unitFrames or {}
				db.unitFrames[unitKey] = db.unitFrames[unitKey] or {}
				return db.unitFrames[unitKey]
			end
			local function getter()
				local t = ensureUFDB(); if not t then return false end
				return not not t.useCustomBorders
			end
			local function setter(b)
				local t = ensureUFDB(); if not t then return end
				local wasEnabled = not not t.useCustomBorders
				t.useCustomBorders = not not b
				-- Clear legacy per-health-bar hide flag when disabling custom borders so stock art restores
				if not b then t.healthBarHideBorder = false end
				-- Reset bar height to 100% when disabling Use Custom Borders
				if wasEnabled and not b then
					t.powerBarHeightPct = 100
				end
				if addon and addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor(unitKey) end
				-- Rerender current category to update enabled/disabled state of Border tab controls and Bar Height sliders
				if panel and panel.RefreshCurrentCategoryDeferred then panel.RefreshCurrentCategoryDeferred() end
			end
			local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
			local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
			row.GetExtent = function() return 34 end
			do
				local base = row.InitFrame
				row.InitFrame = function(self, frame)
					if base then base(self, frame) end
					-- FIRST: Clean up Unit Frame info icons if this frame is being used for a different component
					-- This must happen before any other logic to prevent icon from appearing on recycled frames
					-- Only destroy icons that were created for Unit Frames, allowing other components to have their own icons
					if frame.ScooterInfoIcon and frame.ScooterInfoIcon._isUnitFrameIcon then
						local labelText = frame.Text and frame.Text:GetText() or ""
						local isUnitFrameComponent = (componentId == "ufPlayer" or componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet")
						local isUnitFrameCheckbox = (labelText == "Use Custom Borders")
						if not (isUnitFrameComponent and isUnitFrameCheckbox) then
							-- This is NOT a Unit Frame checkbox - hide and destroy the Unit Frame icon
							-- Other components can have their own icons without interference
							frame.ScooterInfoIcon:Hide()
							frame.ScooterInfoIcon:SetParent(nil)
							frame.ScooterInfoIcon = nil
						end
					end
					-- Hide any stray inline swatch from a previously-recycled tint row
					if frame.ScooterInlineSwatch then
						frame.ScooterInlineSwatch:Hide()
					end
					-- Aggressively restore any swatch-wrapped handlers on recycled rows
					if frame.ScooterInlineSwatchWrapper then
						frame.OnSettingValueChanged = frame.ScooterInlineSwatchBase or frame.OnSettingValueChanged
						frame.ScooterInlineSwatchWrapper = nil
						frame.ScooterInlineSwatchBase = nil
					end
					-- Detach swatch-specific checkbox callbacks so this row behaves like a normal checkbox
					local cb = frame.Checkbox or frame.CheckBox or frame.Control or frame
					if cb and cb.UnregisterCallback and SettingsCheckboxMixin and SettingsCheckboxMixin.Event and cb.ScooterInlineSwatchCallbackOwner then
						cb:UnregisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, cb.ScooterInlineSwatchCallbackOwner)
						cb.ScooterInlineSwatchCallbackOwner = nil
					end
					if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
					if panel and panel.ApplyRobotoWhite then
						if frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
						local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					-- Add info icon next to the label - ONLY for Unit Frame "Use Custom Borders" checkbox
					if frame and frame.Text then
						local labelText = frame.Text:GetText()
						if labelText == "Use Custom Borders" and (componentId == "ufPlayer" or componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet") then
							-- This is the Unit Frame checkbox - create/show the icon
							if panel and panel.CreateInfoIcon then
								if not frame.ScooterInfoIcon then
									local tooltipText = "Enables custom borders by disabling Blizzard's default frame art. Note: This also temporarily disables Aggro Glow and Reputation Colors—we'll restore those features in a future update."
									-- Icon size is 32 (double the original 16) for better visibility
									-- Position icon to the right of the checkbox to ensure no overlap
									local checkbox = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
									if checkbox then
										-- Position icon to the right of the checkbox with spacing
										frame.ScooterInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "RIGHT", 10, 0, 32)
										frame.ScooterInfoIcon:ClearAllPoints()
										frame.ScooterInfoIcon:SetPoint("LEFT", checkbox, "RIGHT", 10, 0)
									else
										-- Fallback: position relative to label if checkbox not found
										frame.ScooterInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "RIGHT", 10, 0, 32)
										if frame.Text then
											frame.ScooterInfoIcon:ClearAllPoints()
											-- Use larger offset to avoid checkbox area (checkbox is ~80px from left, 30px wide)
											frame.ScooterInfoIcon:SetPoint("LEFT", frame.Text, "RIGHT", 40, 0)
										end
									end
									-- Store metadata to identify this as a Unit Frame icon
									frame.ScooterInfoIcon._isUnitFrameIcon = true
									frame.ScooterInfoIcon._componentId = componentId
								else
									-- Icon already exists, ensure it's visible
									frame.ScooterInfoIcon:Show()
								end
							end
						end
					end
				end
			end
			table.insert(init, row)
		end

			-- Second collapsible section: Health Bar (blank for now)
			local expInitializerHB = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
				name = "Health Bar",
				sectionKey = "Health Bar",
				componentId = componentId,
				expanded = panel:IsSectionExpanded(componentId, "Health Bar"),
			})
			expInitializerHB.GetExtent = function() return 30 end
		table.insert(init, expInitializerHB)

		--[[
			UNIT FRAMES TABBED SECTION TAB PRIORITY ORDER (all Player/Target/Focus/Pet sections):
			1. Positioning
			2. Sizing
			3. Style/Texture (corresponds to "Style" tabs)
			4. Border
			5. Visibility
			6. Text Elements (e.g., "% Text", "Value Text")
			
			When adding or reordering tabs in Unit Frames tabbed sections, follow this priority.
		]]--
		-- Health Bar tabs (Direction for Target/Focus, then Style, Border, Text variants)
		local isTargetOrFocusHB = (componentId == "ufTarget" or componentId == "ufFocus")
		local hbTabs = { sectionTitle = "" }
		if isTargetOrFocusHB then
			hbTabs.tabAText = "Direction"
			hbTabs.tabBText = "Style"
			hbTabs.tabCText = "Border"
			hbTabs.tabDText = "% Text"
			hbTabs.tabEText = "Value Text"
		else
			hbTabs.tabAText = "Style"
			hbTabs.tabBText = "Border"
			hbTabs.tabCText = "% Text"
			hbTabs.tabDText = "Value Text"
		end
			hbTabs.build = function(frame)
				local function unitKey()
					if componentId == "ufPlayer" then return "Player" end
					if componentId == "ufTarget" then return "Target" end
					if componentId == "ufFocus" then return "Focus" end
					if componentId == "ufPet" then return "Pet" end
					return nil
				end
				local function ensureUFDB()
					local db = addon and addon.db and addon.db.profile
					if not db then return nil end
					db.unitFrames = db.unitFrames or {}
					local uk = unitKey(); if not uk then return nil end
					db.unitFrames[uk] = db.unitFrames[uk] or {}
					return db.unitFrames[uk]
				end

				-- Local UI helpers (mirror Action Bar Text helpers)
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
					if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
						addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
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

				-- PageA: Direction (Target/Focus only)
				if isTargetOrFocusHB then
					do
						local function applyNow()
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local y = { y = -50 }

						-- Bar Fill Direction dropdown (Target/Focus only)
						local label = "Bar Fill Direction"
						local function fillDirOptions()
							local container = Settings.CreateControlTextContainer()
							container:Add("default", "Left to Right (Default)")
							container:Add("reverse", "Right to Left (Mirrored)")
							return container:GetData()
						end
						local function getter()
							local t = ensureUFDB() or {}
							return t.healthBarReverseFill and "reverse" or "default"
						end
						local function setter(v)
							local t = ensureUFDB(); if not t then return end
							t.healthBarReverseFill = (v == "reverse")
							applyNow()
							-- Refresh the page to update any dependent controls
							if panel and panel.SuspendRefresh then panel.SuspendRefresh(0.25) end
							if panel and panel.RefreshCurrentCategoryDeferred then
								panel.RefreshCurrentCategoryDeferred()
							end
						end
						addDropdown(frame.PageA, label, fillDirOptions, getter, setter, y)
					end
				end

				-- PageC: % Text (or PageB if no Direction tab)
				local percentTextPage = isTargetOrFocusHB and frame.PageD or frame.PageC
				do
					local function applyNow()
						if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(unitKey()) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local function fontOptions()
						return addon.BuildFontOptionsContainer()
					end
					local y = { y = -50 }
					local label = "Disable % Text"
					local function getter()
						local t = ensureUFDB(); return t and not not t.healthPercentHidden or false
					end
					local function setter(v)
						local t = ensureUFDB(); if not t then return end
						t.healthPercentHidden = (v and true) or false
						applyNow()
					end
					local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, percentTextPage, "SettingsCheckboxControlTemplate")
					row.GetElementData = function() return initCb end
					row:SetPoint("TOPLEFT", 4, y.y)
					row:SetPoint("TOPRIGHT", -16, y.y)
					initCb:InitFrame(row)
					if panel and panel.ApplyRobotoWhite then
						if row.Text then panel.ApplyRobotoWhite(row.Text) end
						local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					y.y = y.y - 34
					-- Font controls for % Text
					addDropdown(percentTextPage, "% Text Font", fontOptions,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return s.fontFace or "FRIZQT__" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.fontFace = v; applyNow() end,
						y)
					addStyle(percentTextPage, "% Text Style",
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return s.style or "OUTLINE" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.style = v; applyNow() end,
						y)
					addSlider(percentTextPage, "% Text Size", 6, 48, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return tonumber(s.size) or 14 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.size = tonumber(v) or 14; applyNow() end,
						y)
					addColor(percentTextPage, "% Text Color", true,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
						function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.color = {r,g,b,a}; applyNow() end,
						y)
					addSlider(percentTextPage, "% Text Offset X", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.offset = t.textHealthPercent.offset or {}; t.textHealthPercent.offset.x = tonumber(v) or 0; applyNow() end,
						y)
					addSlider(percentTextPage, "% Text Offset Y", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.offset = t.textHealthPercent.offset or {}; t.textHealthPercent.offset.y = tonumber(v) or 0; applyNow() end,
						y)
				end

				-- PageD: Value Text (or PageD if no Direction tab)
				local valueTextPage = isTargetOrFocusHB and frame.PageE or frame.PageD
				do
					local function applyNow()
						if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(unitKey()) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local function fontOptions()
						return addon.BuildFontOptionsContainer()
					end
					local y = { y = -50 }
					local label = "Disable Value Text"
					local function getter()
						local t = ensureUFDB(); return t and not not t.healthValueHidden or false
					end
					local function setter(v)
						local t = ensureUFDB(); if not t then return end
						t.healthValueHidden = (v and true) or false
						applyNow()
					end
					local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, valueTextPage, "SettingsCheckboxControlTemplate")
					row.GetElementData = function() return initCb end
					row:SetPoint("TOPLEFT", 4, y.y)
					row:SetPoint("TOPRIGHT", -16, y.y)
					initCb:InitFrame(row)
					if panel and panel.ApplyRobotoWhite then
						if row.Text then panel.ApplyRobotoWhite(row.Text) end
						local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					-- Match % Text layout: drop the cursor after the checkbox row
					y.y = y.y - 34
					-- Font controls for Value Text
					addDropdown(valueTextPage, "Value Text Font", fontOptions,
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return s.fontFace or "FRIZQT__" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.fontFace = v; applyNow() end,
						y)
					addStyle(valueTextPage, "Value Text Style",
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return s.style or "OUTLINE" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.style = v; applyNow() end,
						y)
					addSlider(valueTextPage, "Value Text Size", 6, 48, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return tonumber(s.size) or 14 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.size = tonumber(v) or 14; applyNow() end,
						y)
					addColor(valueTextPage, "Value Text Color", true,
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
						function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.color = {r,g,b,a}; applyNow() end,
						y)
					addSlider(valueTextPage, "Value Text Offset X", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.offset = t.textHealthValue.offset or {}; t.textHealthValue.offset.x = tonumber(v) or 0; applyNow() end,
						y)
					addSlider(valueTextPage, "Value Text Offset Y", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.offset = t.textHealthValue.offset or {}; t.textHealthValue.offset.y = tonumber(v) or 0; applyNow() end,
						y)
				end

				-- PageA/PageB: Foreground/Background Texture + Color (PageB for Target/Focus, PageA for Player/Pet)
				local stylePage = isTargetOrFocusHB and frame.PageB or frame.PageA
				do
					local function applyNow()
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local y = { y = -50 }
					-- Foreground Texture dropdown
					local function opts() return addon.BuildBarTextureOptionsContainer() end
					local function getTex() local t = ensureUFDB() or {}; return t.healthBarTexture or "default" end
					local function setTex(v) local t = ensureUFDB(); if not t then return end; t.healthBarTexture = v; applyNow() end
					local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
					local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Foreground Texture", setting = texSetting, options = opts })
					local f = CreateFrame("Frame", nil, stylePage, "SettingsDropdownControlTemplate")
					f.GetElementData = function() return initDrop end
					f:SetPoint("TOPLEFT", 4, y.y)
					f:SetPoint("TOPRIGHT", -16, y.y)
                    initDrop:InitFrame(f)
                    if panel and panel.ApplyRobotoWhite then
                        local lbl = f and (f.Text or f.Label)
                        if lbl then panel.ApplyRobotoWhite(lbl) end
                    end
                    if f.Control and addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(f.Control, texSetting) end
					y.y = y.y - 34

					-- Foreground Color (dropdown + inline swatch)
                    local function colorOpts()
						local container = Settings.CreateControlTextContainer()
                        container:Add("default", "Default")
                        container:Add("texture", "Texture Original")
                        container:Add("class", "Class Color")
                        container:Add("custom", "Custom")
						return container:GetData()
					end
					local function getColorMode() local t = ensureUFDB() or {}; return t.healthBarColorMode or "default" end
					local function setColorMode(v)
						local t = ensureUFDB(); if not t then return end; t.healthBarColorMode = v or "default"; applyNow()
					end
					local function getTintTbl()
						local t = ensureUFDB() or {}; local c = t.healthBarTint or {1,1,1,1}; return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
					end
					local function setTintTbl(r,g,b,a)
						local t = ensureUFDB(); if not t then return end; t.healthBarTint = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
					end
					panel.DropdownWithInlineSwatch(stylePage, y, {
						label = "Foreground Color",
						getMode = getColorMode,
						setMode = setColorMode,
						getColor = getTintTbl,
						setColor = setTintTbl,
						options = colorOpts,
						insideButton = true,
					})

					-- Spacer row between Foreground and Background settings
					do
						local spacer = CreateFrame("Frame", nil, stylePage, "SettingsListElementTemplate")
						spacer:SetHeight(20)
						spacer:SetPoint("TOPLEFT", 4, y.y)
						spacer:SetPoint("TOPRIGHT", -16, y.y)
						if spacer.Text then
							spacer.Text:SetText("")
						end
						y.y = y.y - 24
					end

					-- Background Texture dropdown
					local function getBgTex() local t = ensureUFDB() or {}; return t.healthBarBackgroundTexture or "default" end
					local function setBgTex(v) local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundTexture = v; applyNow() end
					local bgTexSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
					local initBgDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Background Texture", setting = bgTexSetting, options = opts })
					local fbg = CreateFrame("Frame", nil, stylePage, "SettingsDropdownControlTemplate")
					fbg.GetElementData = function() return initBgDrop end
					fbg:SetPoint("TOPLEFT", 4, y.y)
					fbg:SetPoint("TOPRIGHT", -16, y.y)
                    initBgDrop:InitFrame(fbg)
                    if panel and panel.ApplyRobotoWhite then
                        local lbl = fbg and (fbg.Text or fbg.Label)
                        if lbl then panel.ApplyRobotoWhite(lbl) end
                    end
                    if fbg.Control and addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(fbg.Control, bgTexSetting) end
					y.y = y.y - 34

					-- Background Color (dropdown + inline swatch)
                    local function bgColorOpts()
						local container = Settings.CreateControlTextContainer()
                        container:Add("default", "Default")
                        container:Add("texture", "Texture Original")
                        container:Add("custom", "Custom")
						return container:GetData()
					end
					local function getBgColorMode() local t = ensureUFDB() or {}; return t.healthBarBackgroundColorMode or "default" end
					local function setBgColorMode(v)
						local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundColorMode = v or "default"; applyNow()
					end
					local function getBgTintTbl()
						local t = ensureUFDB() or {}; local c = t.healthBarBackgroundTint or {0,0,0,1}; return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
					end
					local function setBgTintTbl(r,g,b,a)
						local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }; applyNow()
					end
					panel.DropdownWithInlineSwatch(stylePage, y, {
						label = "Background Color",
						getMode = getBgColorMode,
						setMode = setBgColorMode,
						getColor = getBgTintTbl,
						setColor = setBgTintTbl,
						options = bgColorOpts,
						insideButton = true,
					})

					-- Background Opacity slider
					local function getBgOpacity() local t = ensureUFDB() or {}; return t.healthBarBackgroundOpacity or 50 end
					local function setBgOpacity(v) local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundOpacity = tonumber(v) or 50; applyNow() end
					local bgOpacitySetting = CreateLocalSetting("Background Opacity", "number", getBgOpacity, setBgOpacity, getBgOpacity())
					local bgOpacityOpts = Settings.CreateSliderOptions(0, 100, 1)
					bgOpacityOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
					local bgOpacityInit = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Background Opacity", setting = bgOpacitySetting, options = bgOpacityOpts })
					local fOpa = CreateFrame("Frame", nil, stylePage, "SettingsSliderControlTemplate")
					fOpa.GetElementData = function() return bgOpacityInit end
					fOpa:SetPoint("TOPLEFT", 4, y.y)
					fOpa:SetPoint("TOPRIGHT", -16, y.y)
					bgOpacityInit:InitFrame(fOpa)
					if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(fOpa) end
					if panel and panel.ApplyRobotoWhite and fOpa.Text then panel.ApplyRobotoWhite(fOpa.Text) end
					y.y = y.y - 48
				end

				-- PageB/PageC: Border (Health Bar only) (PageC for Target/Focus, PageB for Player/Pet)
				local borderPage = isTargetOrFocusHB and frame.PageC or frame.PageB
				do
					local y = { y = -50 }
					local function optionsBorder()
						-- Start with "None", then append all standard bar border styles from the shared provider
						local c = Settings.CreateControlTextContainer()
						c:Add("none", "None")
						if addon and addon.BuildBarBorderOptionsContainer then
							local base = addon.BuildBarBorderOptionsContainer()
							-- Append all entries as-is so future additions appear automatically
							if type(base) == "table" then
								for _, entry in ipairs(base) do
									if entry and entry.value and entry.text then
										c:Add(entry.value, entry.text)
									end
								end
							end
						else
							-- Fallback: ensure at least Default exists
							c:Add("square", "Default (Square)")
						end
						return c:GetData()
					end
					local function isEnabled()
						local t = ensureUFDB() or {}
						return not not t.useCustomBorders
					end
					local function applyNow()
						local uk = unitKey()
						if addon and uk and addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor(uk) end
					end
					local function getStyle()
						local t = ensureUFDB() or {}; return t.healthBarBorderStyle or "square"
					end
					local function setStyle(v)
						local t = ensureUFDB(); if not t then return end
						t.healthBarBorderStyle = v or "square"
						applyNow()
					end
					local styleSetting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
					local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = styleSetting, options = optionsBorder })
					local f = CreateFrame("Frame", nil, borderPage, "SettingsDropdownControlTemplate")
					f.GetElementData = function() return initDrop end
					f:SetPoint("TOPLEFT", 4, y.y)
					f:SetPoint("TOPRIGHT", -16, y.y)
					initDrop:InitFrame(f)
					local lbl = f and (f.Text or f.Label)
					if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
					-- Grey out when Use Custom Borders is off
					local enabled = isEnabled()
					if f.Control and f.Control.SetEnabled then f.Control:SetEnabled(enabled) end
					if lbl and lbl.SetTextColor then
						if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
					end
					y.y = y.y - 34

					-- Border Tint (checkbox + swatch)
					do
						local function getTintEnabled()
							local t = ensureUFDB() or {}; return not not t.healthBarBorderTintEnable
						end
						local function setTintEnabled(b)
							local t = ensureUFDB(); if not t then return end
							t.healthBarBorderTintEnable = not not b
							applyNow()
						end
						local function getTint()
							local t = ensureUFDB() or {}
							local c = t.healthBarBorderTintColor or {1,1,1,1}
							return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
						end
						local function setTint(r, g, b, a)
							local t = ensureUFDB(); if not t then return end
							t.healthBarBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
							applyNow()
						end
						local tintSetting = CreateLocalSetting("Border Tint", "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
						local initCb = CreateCheckboxWithSwatchInitializer(tintSetting, "Border Tint", getTint, setTint, 8)
						local row = CreateFrame("Frame", nil, borderPage, "SettingsCheckboxControlTemplate")
						row.GetElementData = function() return initCb end
						row:SetPoint("TOPLEFT", 4, y.y)
						row:SetPoint("TOPRIGHT", -16, y.y)
						initCb:InitFrame(row)
						-- Grey out when Use Custom Borders is off
						local enabled = isEnabled()
						local ctrl = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox) or row.Control
						if ctrl and ctrl.SetEnabled then ctrl:SetEnabled(enabled) end
						if row.ScooterInlineSwatch and row.ScooterInlineSwatch.EnableMouse then
							row.ScooterInlineSwatch:EnableMouse(enabled)
							if row.ScooterInlineSwatch.SetAlpha then row.ScooterInlineSwatch:SetAlpha(enabled and 1 or 0.5) end
						end
						local labelFS = (ctrl and ctrl.Text) or row.Text
						if labelFS and labelFS.SetTextColor then
							if enabled then labelFS:SetTextColor(1, 1, 1, 1) else labelFS:SetTextColor(0.6, 0.6, 0.6, 1) end
						end
						y.y = y.y - 34
					end

					-- Border Thickness
					do
						local function getThk()
							local t = ensureUFDB() or {}; return tonumber(t.healthBarBorderThickness) or 1
						end
						local function setThk(v)
							local t = ensureUFDB(); if not t then return end
							local nv = tonumber(v) or 1
							if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
							t.healthBarBorderThickness = nv
							applyNow()
						end
						local opts = Settings.CreateSliderOptions(1, 16, 1)
						opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
						local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
						local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
						local sf = CreateFrame("Frame", nil, borderPage, "SettingsSliderControlTemplate")
						sf.GetElementData = function() return initSlider end
						sf:SetPoint("TOPLEFT", 4, y.y)
						sf:SetPoint("TOPRIGHT", -16, y.y)
						initSlider:InitFrame(sf)
						if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
						-- Grey out when Use Custom Borders is off
						local enabled = isEnabled()
						if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled) end
						if sf.Text and sf.Text.SetTextColor then
							if enabled then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
						end
						y.y = y.y - 34
					end

					-- Border Inset (fine adjustments)
					do
						local function getInset()
							local t = ensureUFDB() or {}; return tonumber(t.healthBarBorderInset) or 0
						end
						local function setInset(v)
							local t = ensureUFDB(); if not t then return end
							local nv = tonumber(v) or 0
							if nv < -4 then nv = -4 elseif nv > 4 then nv = 4 end
							t.healthBarBorderInset = nv
							applyNow()
						end
						local opts = Settings.CreateSliderOptions(-4, 4, 1)
						opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
						local insetSetting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
						local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
						local sf = CreateFrame("Frame", nil, borderPage, "SettingsSliderControlTemplate")
						sf.GetElementData = function() return initSlider end
						sf:SetPoint("TOPLEFT", 4, y.y)
						sf:SetPoint("TOPRIGHT", -16, y.y)
						initSlider:InitFrame(sf)
						if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
						local enabled = isEnabled()
						if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled) end
						if sf.Text and sf.Text.SetTextColor then
							if enabled then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
						end
						y.y = y.y - 34
					end
				end

				-- Apply current visibility once when building
				if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(unitKey()) end
			end
			local hbInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", hbTabs)
			-- STATIC HEIGHT for tabbed sections with up to 7-8 settings per tab.
			-- Current: 330px provides comfortable spacing with 2px top gap and room at bottom.
			-- DO NOT reduce below 315px or settings will bleed past the bottom border.
			hbInit.GetExtent = function() return 330 end
			hbInit:AddShownPredicate(function()
				return panel:IsSectionExpanded(componentId, "Health Bar")
			end)
			table.insert(init, hbInit)

			-- Third collapsible section: Power Bar (blank for now)
			local expInitializerPB = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
				name = "Power Bar",
				sectionKey = "Power Bar",
				componentId = componentId,
				expanded = panel:IsSectionExpanded(componentId, "Power Bar"),
			})
			expInitializerPB.GetExtent = function() return 30 end
			table.insert(init, expInitializerPB)

            -- Power Bar tabs (ordered by Unit Frames tab priority: Positioning > Sizing > Style/Texture > Border > Visibility > Text Elements)
            -- Tab name is "Sizing/Direction" for Target/Focus (which support reverse fill), "Sizing" for Player/Pet
            local isTargetOrFocusPB = (componentId == "ufTarget" or componentId == "ufFocus")
            local sizingTabNamePB = isTargetOrFocusPB and "Sizing/Direction" or "Sizing"
            local pbTabs = { sectionTitle = "", tabAText = "Positioning", tabBText = sizingTabNamePB, tabCText = "Style", tabDText = "Border", tabEText = "% Text", tabFText = "Value Text" }
			pbTabs.build = function(frame)
				local function unitKey()
					if componentId == "ufPlayer" then return "Player" end
					if componentId == "ufTarget" then return "Target" end
					if componentId == "ufFocus" then return "Focus" end
					if componentId == "ufPet" then return "Pet" end
					return nil
				end
				local function ensureUFDB()
					local db = addon and addon.db and addon.db.profile
					if not db then return nil end
					db.unitFrames = db.unitFrames or {}
					local uk = unitKey(); if not uk then return nil end
					db.unitFrames[uk] = db.unitFrames[uk] or {}
					return db.unitFrames[uk]
				end

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
					if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
						addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
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

				-- PageA: Positioning (Power Bar)
				do
					local function applyNow()
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local y = { y = -50 }
					local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
					
					-- X Offset slider
					addSlider(frame.PageA, "X Offset", -100, 100, 1,
						function() local t = ensureUFDB() or {}; return tonumber(t.powerBarOffsetX) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.powerBarOffsetX = tonumber(v) or 0; applyNow() end,
						y)
					
					-- Y Offset slider
					addSlider(frame.PageA, "Y Offset", -100, 100, 1,
						function() local t = ensureUFDB() or {}; return tonumber(t.powerBarOffsetY) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.powerBarOffsetY = tonumber(v) or 0; applyNow() end,
						y)
				end

				-- PageB: Sizing/Direction (Power Bar)
				do
					local function applyNow()
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local y = { y = -50 }

					-- Bar Fill Direction dropdown (Target/Focus only)
					if isTargetOrFocusPB then
						local label = "Bar Fill Direction"
						local function fillDirOptions()
							local container = Settings.CreateControlTextContainer()
							container:Add("default", "Left to Right (Default)")
							container:Add("reverse", "Right to Left (Mirrored)")
							return container:GetData()
						end
						local function getter()
							local t = ensureUFDB() or {}
							return t.powerBarReverseFill and "reverse" or "default"
						end
						local function setter(v)
							local t = ensureUFDB(); if not t then return end
							local wasReverse = not not t.powerBarReverseFill
							local willBeReverse = (v == "reverse")
							
							if wasReverse and not willBeReverse then
								-- Switching FROM reverse TO default: Save current width and force to 100
								local currentWidth = tonumber(t.powerBarWidthPct) or 100
								t.powerBarWidthPctSaved = currentWidth
								t.powerBarWidthPct = 100
							elseif not wasReverse and willBeReverse then
								-- Switching FROM default TO reverse: Restore saved width
								local savedWidth = tonumber(t.powerBarWidthPctSaved) or 100
								t.powerBarWidthPct = savedWidth
							end
							
							t.powerBarReverseFill = willBeReverse
							applyNow()
							-- Refresh the page to update Bar Width slider enabled state
							if panel and panel.SuspendRefresh then panel.SuspendRefresh(0.25) end
							if panel and panel.RefreshCurrentCategoryDeferred then
								panel.RefreshCurrentCategoryDeferred()
							end
						end
						addDropdown(frame.PageB, label, fillDirOptions, getter, setter, y)
					end

					-- Bar Width slider (only enabled for Target/Focus with reverse fill)
					local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
					local label = "Bar Width (%)"
					local options = Settings.CreateSliderOptions(50, 150, 1)
					options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)

					-- Getter: Always return the actual stored value
					local function getter()
						local t = ensureUFDB() or {}
						return tonumber(t.powerBarWidthPct) or 100
					end

					-- Setter: Store value normally (only when slider is enabled)
					local function setter(v)
						local t = ensureUFDB(); if not t then return end
						-- For Target/Focus: prevent changes when reverse fill is disabled
						if isTargetOrFocusPB and not t.powerBarReverseFill then
							return -- Silently ignore changes when disabled
						end
						local val = tonumber(v) or 100
						val = math.max(50, math.min(150, val))
						t.powerBarWidthPct = val
						applyNow()
					end

					local setting = CreateLocalSetting(label, "number", getter, setter, getter())
					local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
					local widthSlider = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
					widthSlider.GetElementData = function() return initSlider end
					widthSlider:SetPoint("TOPLEFT", 4, y.y)
					widthSlider:SetPoint("TOPRIGHT", -16, y.y)
					initSlider:InitFrame(widthSlider)
					if widthSlider.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(widthSlider.Text) end

					-- Store reference for later updates
					widthSlider._scooterSetting = setting

					-- Conditional enable/disable based on fill direction (Target/Focus only)
					if isTargetOrFocusPB then
						local t = ensureUFDB() or {}
						local isReverse = not not t.powerBarReverseFill
						
						if isReverse then
							-- Enabled state: full opacity for all elements
							if widthSlider.Text then widthSlider.Text:SetAlpha(1.0) end
							if widthSlider.Label then widthSlider.Label:SetAlpha(1.0) end
							if widthSlider.Control then 
								widthSlider.Control:Show()
								widthSlider.Control:Enable()
								if widthSlider.Control.EnableMouse then widthSlider.Control:EnableMouse(true) end
								if widthSlider.Control.Slider then widthSlider.Control.Slider:Enable() end
								if widthSlider.Control.Slider and widthSlider.Control.Slider.EnableMouse then widthSlider.Control.Slider:EnableMouse(true) end
								widthSlider.Control:SetAlpha(1.0)
							end
							if widthSlider.Slider then widthSlider.Slider:Enable() end
							if widthSlider.Slider and widthSlider.Slider.EnableMouse then widthSlider.Slider:EnableMouse(true) end
							-- Show interactive slider row; hide static replacement (if present)
							widthSlider:Show()
							if widthSlider.ScooterBarWidthStatic then widthSlider.ScooterBarWidthStatic:Hide() end
							if widthSlider.ScooterBarWidthStaticInfo then widthSlider.ScooterBarWidthStaticInfo:Hide() end
						else
							-- Disabled state: gray out all visual elements
							if widthSlider.Text then widthSlider.Text:SetAlpha(0.5) end
							if widthSlider.Label then widthSlider.Label:SetAlpha(0.5) end
							if widthSlider.Control then 
								widthSlider.Control:Disable()
								if widthSlider.Control.EnableMouse then widthSlider.Control:EnableMouse(false) end
								if widthSlider.Control.Slider then widthSlider.Control.Slider:Disable() end
								if widthSlider.Control.Slider and widthSlider.Control.Slider.EnableMouse then widthSlider.Control.Slider:EnableMouse(false) end
								widthSlider.Control:SetAlpha(0.5)
							end
							if widthSlider.Slider then widthSlider.Slider:Disable() end
							if widthSlider.Slider and widthSlider.Slider.EnableMouse then widthSlider.Slider:EnableMouse(false) end
							-- Replace the interactive row with a static, non-interactive row indicating 100%
							widthSlider:Hide()
							if not widthSlider.ScooterBarWidthStatic then
								local static = CreateFrame("Frame", nil, frame.PageB, "SettingsListElementTemplate")
								static:SetHeight(26)
								static:SetPoint("TOPLEFT", widthSlider, "TOPLEFT", 0, 0)
								static:SetPoint("TOPRIGHT", widthSlider, "TOPRIGHT", 0, 0)
								-- Compose label text with value
								local baseLabel = (widthSlider.Text and widthSlider.Text:GetText()) or "Bar Width (%)"
								static.Text:SetText(baseLabel .. " — 100%")
								if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(static.Text) end
								-- Align label to match standard row left inset
								if static.Text then
									static.Text:ClearAllPoints()
									static.Text:SetPoint("LEFT", static, "LEFT", 36.5, 0)
									static.Text:SetJustifyH("LEFT")
								end
								widthSlider.ScooterBarWidthStatic = static
							end
							-- Ensure text reflects forced 100%
							do
								local static = widthSlider.ScooterBarWidthStatic
								if static and static.Text then
									local baseLabel = (widthSlider.Text and widthSlider.Text:GetText()) or "Bar Width (%)"
									static.Text:SetText(baseLabel .. " — 100%")
									-- Ensure alignment remains correct after text update
									static.Text:ClearAllPoints()
									static.Text:SetPoint("LEFT", static, "LEFT", 36.5, 0)
									static.Text:SetJustifyH("LEFT")
								end
							end
							-- Add info icon on the static row explaining why it's disabled
							if panel and panel.CreateInfoIconForLabel and not widthSlider.ScooterBarWidthStaticInfo then
								local tooltipText = "Bar Width scaling is only available when using 'Right to Left (mirrored)' fill direction."
								widthSlider.ScooterBarWidthStaticInfo = panel.CreateInfoIconForLabel(
									widthSlider.ScooterBarWidthStatic.Text,
									tooltipText,
									5, 0, 32
								)
								C_Timer.After(0, function()
									local icon = widthSlider.ScooterBarWidthStaticInfo
									local label = widthSlider.ScooterBarWidthStatic and widthSlider.ScooterBarWidthStatic.Text
									if icon and label then
										icon:ClearAllPoints()
										local textWidth = label:GetStringWidth() or 0
										if textWidth > 0 then
											icon:SetPoint("LEFT", label, "LEFT", textWidth + 5, 0)
										else
											icon:SetPoint("LEFT", label, "RIGHT", 5, 0)
										end
									end
								end)
							end
							if widthSlider.ScooterBarWidthStatic then widthSlider.ScooterBarWidthStatic:Show() end
							if widthSlider.ScooterBarWidthStaticInfo then widthSlider.ScooterBarWidthStaticInfo:Show() end
						end
					else
						-- For Player/Pet, always enabled (no reverse fill option)
						if widthSlider.Text then widthSlider.Text:SetAlpha(1.0) end
						if widthSlider.Label then widthSlider.Label:SetAlpha(1.0) end
						if widthSlider.Control then 
							widthSlider.Control:Show()
							widthSlider.Control:Enable()
							if widthSlider.Control.Slider then widthSlider.Control.Slider:Enable() end
							widthSlider.Control:SetAlpha(1.0)
						end
						if widthSlider.Slider then widthSlider.Slider:Enable() end
						widthSlider:Show()
						if widthSlider.ScooterBarWidthStatic then widthSlider.ScooterBarWidthStatic:Hide() end
						if widthSlider.ScooterBarWidthStaticInfo then widthSlider.ScooterBarWidthStaticInfo:Hide() end
					end

					y.y = y.y - 34
					
					-- Bar Height slider (only enabled when Use Custom Borders is checked)
					local heightLabel = "Bar Height (%)"
					local heightOptions = Settings.CreateSliderOptions(50, 200, 1)
					heightOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
					
					-- Getter: Always return the actual stored value
					local function heightGetter()
						local t = ensureUFDB() or {}
						return tonumber(t.powerBarHeightPct) or 100
					end
					
					-- Setter: Store value normally (only when slider is enabled)
					local function heightSetter(v)
						local t = ensureUFDB(); if not t then return end
						-- Prevent changes when Use Custom Borders is disabled
						if not t.useCustomBorders then
							return -- Silently ignore changes when disabled
						end
						local val = tonumber(v) or 100
						val = math.max(50, math.min(200, val))
						t.powerBarHeightPct = val
						applyNow()
					end
					
					local heightSetting = CreateLocalSetting(heightLabel, "number", heightGetter, heightSetter, heightGetter())
					local initHeightSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = heightLabel, setting = heightSetting, options = heightOptions })
					local heightSlider = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
					heightSlider.GetElementData = function() return initHeightSlider end
					heightSlider:SetPoint("TOPLEFT", 4, y.y)
					heightSlider:SetPoint("TOPRIGHT", -16, y.y)
					initHeightSlider:InitFrame(heightSlider)
					if heightSlider.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(heightSlider.Text) end
					
					-- Add info icon to enabled slider explaining the requirement
					if panel and panel.CreateInfoIconForLabel then
						local tooltipText = "Bar Height customization requires 'Use Custom Borders' to be enabled. This setting allows you to adjust the vertical size of the power bar."
						local label = heightSlider.Text or heightSlider.Label
						if label and not heightSlider.ScooterBarHeightInfoIcon then
							heightSlider.ScooterBarHeightInfoIcon = panel.CreateInfoIconForLabel(label, tooltipText, 5, 0, 32)
							C_Timer.After(0, function()
								local icon = heightSlider.ScooterBarHeightInfoIcon
								local lbl = heightSlider.Text or heightSlider.Label
								if icon and lbl then
									icon:ClearAllPoints()
									local textWidth = lbl:GetStringWidth() or 0
									if textWidth > 0 then
										icon:SetPoint("LEFT", lbl, "LEFT", textWidth + 5, 0)
									else
										icon:SetPoint("LEFT", lbl, "RIGHT", 5, 0)
									end
								end
							end)
						end
					end
					
					-- Store reference for later updates
					heightSlider._scooterSetting = heightSetting
					
					-- Conditional enable/disable based on Use Custom Borders
					local function updateHeightSliderState()
						local t = ensureUFDB() or {}
						local isEnabled = not not t.useCustomBorders
						
						if isEnabled then
							-- Enabled state: full opacity for all elements
							if heightSlider.Text then heightSlider.Text:SetAlpha(1.0) end
							if heightSlider.Label then heightSlider.Label:SetAlpha(1.0) end
							if heightSlider.Control then 
								heightSlider.Control:Show()
								heightSlider.Control:Enable()
								if heightSlider.Control.EnableMouse then heightSlider.Control:EnableMouse(true) end
								if heightSlider.Control.Slider then heightSlider.Control.Slider:Enable() end
								if heightSlider.Control.Slider and heightSlider.Control.Slider.EnableMouse then heightSlider.Control.Slider:EnableMouse(true) end
								heightSlider.Control:SetAlpha(1.0)
							end
							if heightSlider.Slider then heightSlider.Slider:Enable() end
							if heightSlider.Slider and heightSlider.Slider.EnableMouse then heightSlider.Slider:EnableMouse(true) end
							heightSlider:Show()
							if heightSlider.ScooterBarHeightStatic then heightSlider.ScooterBarHeightStatic:Hide() end
							if heightSlider.ScooterBarHeightStaticInfo then heightSlider.ScooterBarHeightStaticInfo:Hide() end
							if heightSlider.ScooterBarHeightInfoIcon then heightSlider.ScooterBarHeightInfoIcon:Show() end
						else
							-- Disabled state: gray out all visual elements
							if heightSlider.Text then heightSlider.Text:SetAlpha(0.5) end
							if heightSlider.Label then heightSlider.Label:SetAlpha(0.5) end
							if heightSlider.Control then 
								heightSlider.Control:Hide()
								heightSlider.Control:Disable()
								if heightSlider.Control.EnableMouse then heightSlider.Control:EnableMouse(false) end
								if heightSlider.Control.Slider then heightSlider.Control.Slider:Disable() end
								if heightSlider.Control.Slider and heightSlider.Control.Slider.EnableMouse then heightSlider.Control.Slider:EnableMouse(false) end
								heightSlider.Control:SetAlpha(0.5)
							end
							if heightSlider.Slider then heightSlider.Slider:Disable() end
							if heightSlider.Slider and heightSlider.Slider.EnableMouse then heightSlider.Slider:EnableMouse(false) end
							heightSlider:SetAlpha(0.5)
							
							-- Create static replacement row if it doesn't exist
							if not heightSlider.ScooterBarHeightStatic then
								local static = CreateFrame("Frame", nil, frame.PageB, "SettingsListElementTemplate")
								static:SetHeight(26)
								static:SetPoint("TOPLEFT", 4, y.y)
								static:SetPoint("TOPRIGHT", -16, y.y)
								static.Text = static:CreateFontString(nil, "OVERLAY", "GameFontNormal")
								static.Text:SetPoint("LEFT", static, "LEFT", 36.5, 0)
								static.Text:SetJustifyH("LEFT")
								if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(static.Text) end
								heightSlider.ScooterBarHeightStatic = static
							end
							local static = heightSlider.ScooterBarHeightStatic
							if static and static.Text then
								local baseLabel = (heightSlider.Text and heightSlider.Text:GetText()) or "Bar Height (%)"
								static.Text:SetText(baseLabel .. " — 100%")
								static.Text:ClearAllPoints()
								static.Text:SetPoint("LEFT", static, "LEFT", 36.5, 0)
								static.Text:SetJustifyH("LEFT")
							end
							-- Add info icon on the static row explaining why it's disabled
							if panel and panel.CreateInfoIconForLabel and not heightSlider.ScooterBarHeightStaticInfo then
								local tooltipText = "Bar Height customization requires 'Use Custom Borders' to be enabled. This setting allows you to adjust the vertical size of the power bar."
								heightSlider.ScooterBarHeightStaticInfo = panel.CreateInfoIconForLabel(
									heightSlider.ScooterBarHeightStatic.Text,
									tooltipText,
									5, 0, 32
								)
								C_Timer.After(0, function()
									local icon = heightSlider.ScooterBarHeightStaticInfo
									local label = heightSlider.ScooterBarHeightStatic and heightSlider.ScooterBarHeightStatic.Text
									if icon and label then
										icon:ClearAllPoints()
										local textWidth = label:GetStringWidth() or 0
										if textWidth > 0 then
											icon:SetPoint("LEFT", label, "LEFT", textWidth + 5, 0)
										else
											icon:SetPoint("LEFT", label, "RIGHT", 5, 0)
										end
									end
								end)
							end
							if heightSlider.ScooterBarHeightStatic then heightSlider.ScooterBarHeightStatic:Show() end
							if heightSlider.ScooterBarHeightStaticInfo then heightSlider.ScooterBarHeightStaticInfo:Show() end
							if heightSlider.ScooterBarHeightInfoIcon then heightSlider.ScooterBarHeightInfoIcon:Hide() end
							heightSlider:Hide()
						end
					end
					
					-- Initial state update
					updateHeightSliderState()
					
					-- Store update function for external calls (e.g., when Use Custom Borders changes)
					heightSlider._updateState = updateHeightSliderState
					
					y.y = y.y - 34
				end

				-- PageE: % Text (Power Percent)
				do
					local function applyNow()
						if addon and addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(unitKey()) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local function fontOptions()
						return addon.BuildFontOptionsContainer()
					end
					local y = { y = -50 }
					local label = "Disable % Text"
					local function getter()
						local t = ensureUFDB(); return t and not not t.powerPercentHidden or false
					end
					local function setter(v)
						local t = ensureUFDB(); if not t then return end
						t.powerPercentHidden = (v and true) or false
						applyNow()
					end
					local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, frame.PageE, "SettingsCheckboxControlTemplate")
					row.GetElementData = function() return initCb end
					row:SetPoint("TOPLEFT", 4, y.y)
					row:SetPoint("TOPRIGHT", -16, y.y)
					initCb:InitFrame(row)
					if panel and panel.ApplyRobotoWhite then
						if row.Text then panel.ApplyRobotoWhite(row.Text) end
						local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					y.y = y.y - 34
					addDropdown(frame.PageE, "% Text Font", fontOptions,
						function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; return s.fontFace or "FRIZQT__" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.fontFace = v; applyNow() end,
						y)
					addStyle(frame.PageE, "% Text Style",
						function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; return s.style or "OUTLINE" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.style = v; applyNow() end,
						y)
					addSlider(frame.PageE, "% Text Size", 6, 48, 1,
						function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; return tonumber(s.size) or 14 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.size = tonumber(v) or 14; applyNow() end,
						y)
					addColor(frame.PageE, "% Text Color", true,
						function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
						function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.color = {r,g,b,a}; applyNow() end,
						y)
					addSlider(frame.PageE, "% Text Offset X", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.offset = t.textPowerPercent.offset or {}; t.textPowerPercent.offset.x = tonumber(v) or 0; applyNow() end,
						y)
					addSlider(frame.PageE, "% Text Offset Y", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.offset = t.textPowerPercent.offset or {}; t.textPowerPercent.offset.y = tonumber(v) or 0; applyNow() end,
						y)
				end

				-- PageF: Value Text (Power Value / RightText). May be a no-op on classes without a separate value element.
				do
					local function applyNow()
						if addon and addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(unitKey()) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local function fontOptions()
						return addon.BuildFontOptionsContainer()
					end
					local y = { y = -50 }
					local label = "Disable Value Text"
					local function getter()
						local t = ensureUFDB(); return t and not not t.powerValueHidden or false
					end
					local function setter(v)
						local t = ensureUFDB(); if not t then return end
						t.powerValueHidden = (v and true) or false
						applyNow()
					end
					local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, frame.PageF, "SettingsCheckboxControlTemplate")
					row.GetElementData = function() return initCb end
					row:SetPoint("TOPLEFT", 4, y.y)
					row:SetPoint("TOPRIGHT", -16, y.y)
					initCb:InitFrame(row)
					if panel and panel.ApplyRobotoWhite then
						if row.Text then panel.ApplyRobotoWhite(row.Text) end
						local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					y.y = y.y - 34
					addDropdown(frame.PageF, "Value Text Font", fontOptions,
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; return s.fontFace or "FRIZQT__" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.fontFace = v; applyNow() end,
						y)
					addStyle(frame.PageF, "Value Text Style",
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; return s.style or "OUTLINE" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.style = v; applyNow() end,
						y)
					addSlider(frame.PageF, "Value Text Size", 6, 48, 1,
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; return tonumber(s.size) or 14 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.size = tonumber(v) or 14; applyNow() end,
						y)
					addColor(frame.PageF, "Value Text Color", true,
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
						function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.color = {r,g,b,a}; applyNow() end,
						y)
					addSlider(frame.PageF, "Value Text Offset X", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.offset = t.textPowerValue.offset or {}; t.textPowerValue.offset.x = tonumber(v) or 0; applyNow() end,
						y)
					addSlider(frame.PageF, "Value Text Offset Y", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.offset = t.textPowerValue.offset or {}; t.textPowerValue.offset.y = tonumber(v) or 0; applyNow() end,
						y)
				end

                -- PageC: Foreground/Background Texture + Color (Power Bar)
				do
					local function applyNow()
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local y = { y = -50 }
					-- Foreground Texture dropdown
					local function opts() return addon.BuildBarTextureOptionsContainer() end
					local function getTex() local t = ensureUFDB() or {}; return t.powerBarTexture or "default" end
					local function setTex(v) local t = ensureUFDB(); if not t then return end; t.powerBarTexture = v; applyNow() end
					local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
					local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Foreground Texture", setting = texSetting, options = opts })
					local f = CreateFrame("Frame", nil, frame.PageC, "SettingsDropdownControlTemplate")
					f.GetElementData = function() return initDrop end
					f:SetPoint("TOPLEFT", 4, y.y)
					f:SetPoint("TOPRIGHT", -16, y.y)
                    initDrop:InitFrame(f)
                    if panel and panel.ApplyRobotoWhite then
                        local lbl = f and (f.Text or f.Label)
                        if lbl then panel.ApplyRobotoWhite(lbl) end
                    end
					if f.Control and addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(f.Control, texSetting) end
					y.y = y.y - 34

					-- Foreground Color (dropdown + inline swatch)
                    local function colorOpts()
						local container = Settings.CreateControlTextContainer()
                        container:Add("default", "Default")
                        container:Add("texture", "Texture Original")
                        container:Add("custom", "Custom")
						return container:GetData()
					end
					local function getColorMode() local t = ensureUFDB() or {}; return t.powerBarColorMode or "default" end
					local function setColorMode(v)
						local t = ensureUFDB(); if not t then return end; t.powerBarColorMode = v or "default"; applyNow()
					end
					local function getTintTbl()
						local t = ensureUFDB() or {}; local c = t.powerBarTint or {1,1,1,1}; return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
					end
					local function setTintTbl(r,g,b,a)
						local t = ensureUFDB(); if not t then return end; t.powerBarTint = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
					end
					panel.DropdownWithInlineSwatch(frame.PageC, y, {
						label = "Foreground Color",
						getMode = getColorMode,
						setMode = setColorMode,
						getColor = getTintTbl,
						setColor = setTintTbl,
						options = colorOpts,
						insideButton = true,
					})

					-- Spacer row between Foreground and Background settings
					do
						local spacer = CreateFrame("Frame", nil, frame.PageC, "SettingsListElementTemplate")
						spacer:SetHeight(20)
						spacer:SetPoint("TOPLEFT", 4, y.y)
						spacer:SetPoint("TOPRIGHT", -16, y.y)
						if spacer.Text then
							spacer.Text:SetText("")
						end
						y.y = y.y - 24
					end

					-- Background Texture dropdown
					local function getBgTex() local t = ensureUFDB() or {}; return t.powerBarBackgroundTexture or "default" end
					local function setBgTex(v) local t = ensureUFDB(); if not t then return end; t.powerBarBackgroundTexture = v; applyNow() end
					local bgTexSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
					local initBgDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Background Texture", setting = bgTexSetting, options = opts })
					local fbg = CreateFrame("Frame", nil, frame.PageC, "SettingsDropdownControlTemplate")
					fbg.GetElementData = function() return initBgDrop end
					fbg:SetPoint("TOPLEFT", 4, y.y)
					fbg:SetPoint("TOPRIGHT", -16, y.y)
                    initBgDrop:InitFrame(fbg)
                    if panel and panel.ApplyRobotoWhite then
                        local lbl = fbg and (fbg.Text or fbg.Label)
                        if lbl then panel.ApplyRobotoWhite(lbl) end
                    end
                    if fbg.Control and addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(fbg.Control, bgTexSetting) end
					y.y = y.y - 34

					-- Background Color (dropdown + inline swatch)
                    local function bgColorOpts()
						local container = Settings.CreateControlTextContainer()
                        container:Add("default", "Default")
                        container:Add("texture", "Texture Original")
                        container:Add("custom", "Custom")
						return container:GetData()
					end
					local function getBgColorMode() local t = ensureUFDB() or {}; return t.powerBarBackgroundColorMode or "default" end
					local function setBgColorMode(v)
						local t = ensureUFDB(); if not t then return end; t.powerBarBackgroundColorMode = v or "default"; applyNow()
					end
					local function getBgTintTbl()
						local t = ensureUFDB() or {}; local c = t.powerBarBackgroundTint or {0,0,0,1}; return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
					end
					local function setBgTintTbl(r,g,b,a)
						local t = ensureUFDB(); if not t then return end; t.powerBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }; applyNow()
					end
					panel.DropdownWithInlineSwatch(frame.PageC, y, {
						label = "Background Color",
						getMode = getBgColorMode,
						setMode = setBgColorMode,
						getColor = getBgTintTbl,
						setColor = setBgTintTbl,
						options = bgColorOpts,
						insideButton = true,
					})

					-- Background Opacity slider
					local function getBgOpacity() local t = ensureUFDB() or {}; return t.powerBarBackgroundOpacity or 50 end
					local function setBgOpacity(v) local t = ensureUFDB(); if not t then return end; t.powerBarBackgroundOpacity = tonumber(v) or 50; applyNow() end
					local bgOpacitySetting = CreateLocalSetting("Background Opacity", "number", getBgOpacity, setBgOpacity, getBgOpacity())
					local bgOpacityOpts = Settings.CreateSliderOptions(0, 100, 1)
					bgOpacityOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
					local bgOpacityInit = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Background Opacity", setting = bgOpacitySetting, options = bgOpacityOpts })
					local fOpa = CreateFrame("Frame", nil, frame.PageC, "SettingsSliderControlTemplate")
					fOpa.GetElementData = function() return bgOpacityInit end
					fOpa:SetPoint("TOPLEFT", 4, y.y)
					fOpa:SetPoint("TOPRIGHT", -16, y.y)
					bgOpacityInit:InitFrame(fOpa)
					if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(fOpa) end
					if panel and panel.ApplyRobotoWhite and fOpa.Text then panel.ApplyRobotoWhite(fOpa.Text) end
					y.y = y.y - 48
				end

                -- PageD: Border (Power Bar)
                do
                    local y = { y = -50 }
                    local function optionsBorder()
                        local c = Settings.CreateControlTextContainer()
                        c:Add("none", "None")
                        if addon and addon.BuildBarBorderOptionsContainer then
                            local base = addon.BuildBarBorderOptionsContainer()
                            if type(base) == "table" then
                                for _, entry in ipairs(base) do
                                    if entry and entry.value and entry.text then
                                        c:Add(entry.value, entry.text)
                                    end
                                end
                            end
                        else
                            c:Add("square", "Default (Square)")
                        end
                        return c:GetData()
                    end
                    local function isEnabled()
                        local t = ensureUFDB() or {}
                        return not not t.useCustomBorders
                    end
                    local function applyNow()
                        local uk = unitKey()
                        if addon and uk and addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor(uk) end
                    end
                    local function getStyle()
                        local t = ensureUFDB() or {}; return t.powerBarBorderStyle or "square"
                    end
                    local function setStyle(v)
                        local t = ensureUFDB(); if not t then return end
                        t.powerBarBorderStyle = v or "square"
                        applyNow()
                    end
                    local styleSetting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
                    local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = styleSetting, options = optionsBorder })
                    local f = CreateFrame("Frame", nil, frame.PageD, "SettingsDropdownControlTemplate")
                    f.GetElementData = function() return initDrop end
                    f:SetPoint("TOPLEFT", 4, y.y)
                    f:SetPoint("TOPRIGHT", -16, y.y)
                    initDrop:InitFrame(f)
                    local lbl = f and (f.Text or f.Label)
                    if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
                    local enabled = isEnabled()
                    if f.Control and f.Control.SetEnabled then f.Control:SetEnabled(enabled) end
                    if lbl and lbl.SetTextColor then
                        if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
                    end
                    y.y = y.y - 34

                    -- Border Tint (checkbox + swatch)
                    do
                        local function getTintEnabled()
                            local t = ensureUFDB() or {}; return not not t.powerBarBorderTintEnable
                        end
                        local function setTintEnabled(b)
                            local t = ensureUFDB(); if not t then return end
                            t.powerBarBorderTintEnable = not not b
                            applyNow()
                        end
                        local function getTint()
                            local t = ensureUFDB() or {}
                            local c = t.powerBarBorderTintColor or {1,1,1,1}
                            return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
                        end
                        local function setTint(r, g, b, a)
                            local t = ensureUFDB(); if not t then return end
                            t.powerBarBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
                            applyNow()
                        end
                        local tintSetting = CreateLocalSetting("Border Tint", "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
                        local initCb = CreateCheckboxWithSwatchInitializer(tintSetting, "Border Tint", getTint, setTint, 8)
                        local row = CreateFrame("Frame", nil, frame.PageD, "SettingsCheckboxControlTemplate")
                        row.GetElementData = function() return initCb end
                        row:SetPoint("TOPLEFT", 4, y.y)
                        row:SetPoint("TOPRIGHT", -16, y.y)
                        initCb:InitFrame(row)
                        local enabled2 = isEnabled()
                        local ctrl = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox) or row.Control
                        if ctrl and ctrl.SetEnabled then ctrl:SetEnabled(enabled2) end
                        if row.ScooterInlineSwatch and row.ScooterInlineSwatch.EnableMouse then
                            row.ScooterInlineSwatch:EnableMouse(enabled2)
                            if row.ScooterInlineSwatch.SetAlpha then row.ScooterInlineSwatch:SetAlpha(enabled2 and 1 or 0.5) end
                        end
                        local labelFS = (ctrl and ctrl.Text) or row.Text
                        if labelFS and labelFS.SetTextColor then
                            if enabled2 then labelFS:SetTextColor(1, 1, 1, 1) else labelFS:SetTextColor(0.6, 0.6, 0.6, 1) end
                        end
                        y.y = y.y - 34
                    end

                    -- Border Thickness
                    do
                        local function getThk()
                            local t = ensureUFDB() or {}; return tonumber(t.powerBarBorderThickness) or 1
                        end
                        local function setThk(v)
                            local t = ensureUFDB(); if not t then return end
                            local nv = tonumber(v) or 1
                            if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
                            t.powerBarBorderThickness = nv
                            applyNow()
                        end
                        local opts = Settings.CreateSliderOptions(1, 16, 1)
                        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
                        local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
                        local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
                        local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
                        sf.GetElementData = function() return initSlider end
                        sf:SetPoint("TOPLEFT", 4, y.y)
                        sf:SetPoint("TOPRIGHT", -16, y.y)
                        initSlider:InitFrame(sf)
                        if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
                        local enabled3 = isEnabled()
                        if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled3) end
                        if sf.Text and sf.Text.SetTextColor then
                            if enabled3 then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
                        end
                        y.y = y.y - 34
                    end

                    -- Border Inset
                    do
                        local function getInset()
                            local t = ensureUFDB() or {}; return tonumber(t.powerBarBorderInset) or 0
                        end
                        local function setInset(v)
                            local t = ensureUFDB(); if not t then return end
                            local nv = tonumber(v) or 0
                            if nv < -4 then nv = -4 elseif nv > 4 then nv = 4 end
                            t.powerBarBorderInset = nv
                            applyNow()
                        end
                        local opts = Settings.CreateSliderOptions(-4, 4, 1)
                        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
                        local insetSetting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
                        local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
                        local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
                        sf.GetElementData = function() return initSlider end
                        sf:SetPoint("TOPLEFT", 4, y.y)
                        sf:SetPoint("TOPRIGHT", -16, y.y)
                        initSlider:InitFrame(sf)
                        if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
                        local enabled4 = isEnabled()
                        if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled4) end
                        if sf.Text and sf.Text.SetTextColor then
                            if enabled4 then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
                        end
                        y.y = y.y - 34
                    end
                end

				-- Apply current visibility once when building
				if addon and addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(unitKey()) end
			end

			local pbInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", pbTabs)
			-- STATIC HEIGHT for tabbed sections with up to 7-8 settings per tab.
			-- Current: 330px provides comfortable spacing with 2px top gap and room at bottom.
			-- DO NOT reduce below 315px or settings will bleed past the bottom border.
			pbInit.GetExtent = function() return 330 end
			pbInit:AddShownPredicate(function()
				return panel:IsSectionExpanded(componentId, "Power Bar")
			end)
			table.insert(init, pbInit)

		-- Fourth collapsible section: Name & Level Text (all unit frames)
		local expInitializerNLT = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
			name = "Name & Level Text",
			sectionKey = "Name & Level Text",
			componentId = componentId,
			expanded = panel:IsSectionExpanded(componentId, "Name & Level Text"),
		})
		expInitializerNLT.GetExtent = function() return 30 end
		table.insert(init, expInitializerNLT)

	-- Name & Level Text tabs: Backdrop / Border / Name Text / Level Text
	local nltTabs = { sectionTitle = "", tabAText = "Backdrop", tabBText = "Border", tabCText = "Name Text", tabDText = "Level Text" }
	nltTabs.build = function(frame)
		-- Helper for unit key
		local function unitKey()
			if componentId == "ufPlayer" then return "Player" end
			if componentId == "ufTarget" then return "Target" end
			if componentId == "ufFocus" then return "Focus" end
			if componentId == "ufPet" then return "Pet" end
			return nil
		end

		-- Helper to ensure unit frame DB
		local function ensureUFDB()
			local db = addon and addon.db and addon.db.profile
			if not db then return nil end
			db.unitFrames = db.unitFrames or {}
			local uk = unitKey(); if not uk then return nil end
			db.unitFrames[uk] = db.unitFrames[uk] or {}
			return db.unitFrames[uk]
		end

		-- Helper functions for controls
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
			return f
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
			if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
				addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
			end
			yRef.y = yRef.y - 34
			return f
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

		-- Tab A: Backdrop
		do
			local function applyNow()
				if addon and addon.ApplyUnitFrameNameLevelTextFor then addon.ApplyUnitFrameNameLevelTextFor(unitKey()) end
				if addon and addon.ApplyStyles then addon:ApplyStyles() end
			end
			local y = { y = -50 }
			
			-- Enable Backdrop
			local function isBackdropEnabled()
				local t = ensureUFDB() or {}; if t.nameBackdropEnabled == nil then return true end; return not not t.nameBackdropEnabled
			end
			-- Hold refs to enable/disable dynamically
			local _bdTexFrame, _bdColorFrame, _bdOpacityFrame, _bdWidthFrame
			local function refreshBackdropEnabledState()
				local en = isBackdropEnabled()
				if _bdTexFrame and _bdTexFrame.Control and _bdTexFrame.Control.SetEnabled then _bdTexFrame.Control:SetEnabled(en) end
				do
					local lbl = _bdTexFrame and (_bdTexFrame.Text or _bdTexFrame.Label)
					if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				end
				if _bdColorFrame and _bdColorFrame.Control and _bdColorFrame.Control.SetEnabled then _bdColorFrame.Control:SetEnabled(en) end
				do
					local lbl = _bdColorFrame and (_bdColorFrame.Text or _bdColorFrame.Label)
					if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				end
				if _bdWidthFrame and _bdWidthFrame.Control and _bdWidthFrame.Control.SetEnabled then _bdWidthFrame.Control:SetEnabled(en) end
				if _bdWidthFrame and _bdWidthFrame.Text and _bdWidthFrame.Text.SetTextColor then _bdWidthFrame.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				if _bdOpacityFrame and _bdOpacityFrame.Control and _bdOpacityFrame.Control.SetEnabled then _bdOpacityFrame.Control:SetEnabled(en) end
				if _bdOpacityFrame and _bdOpacityFrame.Text and _bdOpacityFrame.Text.SetTextColor then _bdOpacityFrame.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				-- Note: Backdrop Color unified control handles its own enabled state via isEnabled callback
			end
			do
				local function getter()
					return isBackdropEnabled()
				end
				local function setter(v)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropEnabled = not not v
					applyNow()
					refreshBackdropEnabledState()
				end
				local setting = CreateLocalSetting("Enable Backdrop", "boolean", getter, setter, getter())
				local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Enable Backdrop", setting = setting, options = {} })
				local row = CreateFrame("Frame", nil, frame.PageA, "SettingsCheckboxControlTemplate")
				row.GetElementData = function() return initCb end
				row:SetPoint("TOPLEFT", 4, y.y)
				row:SetPoint("TOPRIGHT", -16, y.y)
				initCb:InitFrame(row)
				if panel and panel.ApplyRobotoWhite then
					if row.Text then panel.ApplyRobotoWhite(row.Text) end
					local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
					if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
				end
				y.y = y.y - 34
			end
			
			-- Backdrop Texture (no Default entry)
			do
				local function get()
					local t = ensureUFDB() or {}; return t.nameBackdropTexture or ""
				end
				local function set(v)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropTexture = v
					applyNow()
				end
				local function optsFiltered()
					local all = addon.BuildBarTextureOptionsContainer and addon.BuildBarTextureOptionsContainer() or {}
					local out = {}
					for _, o in ipairs(all) do
						if o.value ~= "default" then
							table.insert(out, o)
						end
					end
					return out
				end
				local f = addDropdown(frame.PageA, "Backdrop Texture", optsFiltered, get, set, y)
				-- Gray out when disabled
				do
					local en = isBackdropEnabled()
					if f and f.Control and f.Control.SetEnabled then f.Control:SetEnabled(en) end
					local lbl = f and (f.Text or f.Label)
					if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				end
				_bdTexFrame = f
			end
			
			-- Backdrop Color mode (Default / Texture Original / Custom) with inline color swatch
			do
				local function getMode()
					local t = ensureUFDB() or {}; return t.nameBackdropColorMode or "default"
				end
				local function setMode(v)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropColorMode = v or "default"
					applyNow()
					refreshBackdropEnabledState()
				end
				local function getColor()
					local t = ensureUFDB() or {}; local c = t.nameBackdropTint or {1,1,1,1}; return c
				end
				local function setColor(r,g,b,a)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropTint = {r,g,b,a}
					applyNow()
				end
				local function colorOpts()
					local container = Settings.CreateControlTextContainer()
					container:Add("default", "Default")
					container:Add("texture", "Texture Original")
					container:Add("custom", "Custom")
					return container:GetData()
				end
				local f, swatch = panel.DropdownWithInlineSwatch(frame.PageA, y, {
					label = "Backdrop Color",
					getMode = getMode,
					setMode = setMode,
					getColor = getColor,
					setColor = setColor,
					options = colorOpts,
					isEnabled = function() return isBackdropEnabled() end,
					insideButton = true,
				})
				_bdColorFrame = f
			end
			
			-- Backdrop Width (% of baseline at 100%)
			do
				local function get()
					local t = ensureUFDB() or {}; local v = tonumber(t.nameBackdropWidthPct) or 100; if v < 25 then v = 25 elseif v > 300 then v = 300 end; return v
				end
				local function set(v)
					local t = ensureUFDB(); if not t then return end
					local nv = tonumber(v) or 100
					if nv < 25 then nv = 25 elseif nv > 300 then nv = 300 end
					t.nameBackdropWidthPct = nv
					applyNow()
					refreshBackdropEnabledState()
				end
				local sf = addSlider(frame.PageA, "Backdrop Width (%)", 25, 300, 1, get, set, y)
				do
					local en = isBackdropEnabled()
					if sf and sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(en) end
					if sf and sf.Text and sf.Text.SetTextColor then sf.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				end
				_bdWidthFrame = sf
			end
			
			-- Backdrop Opacity (0-100)
			do
				local function get()
					local t = ensureUFDB() or {}; local v = tonumber(t.nameBackdropOpacity) or 50; if v < 0 then v = 0 elseif v > 100 then v = 100 end; return v
				end
				local function set(v)
					local t = ensureUFDB(); if not t then return end
					local nv = tonumber(v) or 50
					if nv < 0 then nv = 0 elseif nv > 100 then nv = 100 end
					t.nameBackdropOpacity = nv
					applyNow()
					refreshBackdropEnabledState()
				end
				local sf = addSlider(frame.PageA, "Backdrop Opacity", 0, 100, 1, get, set, y)
				do
					local en = isBackdropEnabled()
					if sf and sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(en) end
					if sf and sf.Text and sf.Text.SetTextColor then sf.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				end
				_bdOpacityFrame = sf
			end
			refreshBackdropEnabledState()
		end

		-- Tab B: Border (Name Backdrop border)
		do
			local function applyNow()
				if addon and addon.ApplyUnitFrameNameLevelTextFor then addon.ApplyUnitFrameNameLevelTextFor(unitKey()) end
				if addon and addon.ApplyStyles then addon:ApplyStyles() end
			end
			-- Enable Border checkbox + gating combines with global Use Custom Borders
			local function isEnabled()
				local t = ensureUFDB() or {}
				local localEnabled = not not t.nameBackdropBorderEnabled
				local globalEnabled = not not t.useCustomBorders
				return localEnabled and globalEnabled
			end
			local y = { y = -50 }
			local _brStyleFrame, _brTintRow, _brTintSwatch, _brThickFrame, _brInsetFrame, _brTintLabel
			local function refreshBorderEnabledState()
				local en = isEnabled()
				if _brStyleFrame and _brStyleFrame.Control and _brStyleFrame.Control.SetEnabled then _brStyleFrame.Control:SetEnabled(en) end
				do
					local lbl = _brStyleFrame and (_brStyleFrame.Text or _brStyleFrame.Label)
					if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				end
				if _brThickFrame and _brThickFrame.Control and _brThickFrame.Control.SetEnabled then _brThickFrame.Control:SetEnabled(en) end
				if _brThickFrame and _brThickFrame.Text and _brThickFrame.Text.SetTextColor then _brThickFrame.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				if _brInsetFrame and _brInsetFrame.Control and _brInsetFrame.Control.SetEnabled then _brInsetFrame.Control:SetEnabled(en) end
				if _brInsetFrame and _brInsetFrame.Text and _brInsetFrame.Text.SetTextColor then _brInsetFrame.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				if _brTintRow then
					local ctrl = _brTintRow.Checkbox or _brTintRow.CheckBox or (_brTintRow.Control and _brTintRow.Control.Checkbox) or _brTintRow.Control
					if ctrl and ctrl.SetEnabled then ctrl:SetEnabled(en) end
				end
				if _brTintSwatch and _brTintSwatch.EnableMouse then _brTintSwatch:EnableMouse(en) end
				if _brTintLabel and _brTintLabel.SetTextColor then _brTintLabel:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
			end
			
			-- Enable Border
			do
				local function getter()
					local t = ensureUFDB() or {}; return not not t.nameBackdropBorderEnabled
				end
				local function setter(v)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropBorderEnabled = not not v
					applyNow()
					refreshBorderEnabledState()
				end
				local setting = CreateLocalSetting("Enable Border", "boolean", getter, setter, getter())
				local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Enable Border", setting = setting, options = {} })
				local row = CreateFrame("Frame", nil, frame.PageB, "SettingsCheckboxControlTemplate")
				row.GetElementData = function() return initCb end
				row:SetPoint("TOPLEFT", 4, y.y)
				row:SetPoint("TOPRIGHT", -16, y.y)
				initCb:InitFrame(row)
				if panel and panel.ApplyRobotoWhite then
					if row.Text then panel.ApplyRobotoWhite(row.Text) end
					local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
					if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
				end
				y.y = y.y - 34
			end
			
			-- Border Style
			do
				local function get()
					local t = ensureUFDB() or {}; return t.nameBackdropBorderStyle or "square"
				end
				local function set(v)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropBorderStyle = v or "square"
					applyNow()
					refreshBorderEnabledState()
				end
				local function opts()
					return addon.BuildBarBorderOptionsContainer and addon.BuildBarBorderOptionsContainer() or {
						{ value = "square", text = "Default (Square)" }
					}
				end
				local setting = CreateLocalSetting("Border Style", "string", get, set, get())
				local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = setting, options = opts })
				local f = CreateFrame("Frame", nil, frame.PageB, "SettingsDropdownControlTemplate")
				f.GetElementData = function() return initDrop end
				f:SetPoint("TOPLEFT", 4, y.y)
				f:SetPoint("TOPRIGHT", -16, y.y)
				initDrop:InitFrame(f)
				local lbl = f and (f.Text or f.Label)
				if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
				local en = isEnabled()
				if f.Control and f.Control.SetEnabled then f.Control:SetEnabled(en) end
				if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				y.y = y.y - 34
				_brStyleFrame = f
			end
			
			-- Border Tint (checkbox + swatch)
			do
				local function getTintEnabled()
					local t = ensureUFDB() or {}; return not not t.nameBackdropBorderTintEnable
				end
				local function setTintEnabled(b)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropBorderTintEnable = not not b
					applyNow()
				end
				local function getTint()
					local t = ensureUFDB() or {}
					local c = t.nameBackdropBorderTintColor or {1,1,1,1}
					return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
				end
				local function setTint(r,g,b,a)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
					applyNow()
				end
				local tintSetting = CreateLocalSetting("Border Tint", "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
				local initCb = CreateCheckboxWithSwatchInitializer(tintSetting, "Border Tint", getTint, setTint, 8)
				local row = CreateFrame("Frame", nil, frame.PageB, "SettingsCheckboxControlTemplate")
				row.GetElementData = function() return initCb end
				row:SetPoint("TOPLEFT", 4, y.y)
				row:SetPoint("TOPRIGHT", -16, y.y)
				initCb:InitFrame(row)
				local en = isEnabled()
				local ctrl = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox) or row.Control
				if ctrl and ctrl.SetEnabled then ctrl:SetEnabled(en) end
				if row.ScooterInlineSwatch and row.ScooterInlineSwatch.EnableMouse then
					row.ScooterInlineSwatch:EnableMouse(en)
					if row.ScooterInlineSwatch.SetAlpha then row.ScooterInlineSwatch:SetAlpha(en and 1 or 0.5) end
				end
				local labelFS = (ctrl and ctrl.Text) or row.Text
				if labelFS and labelFS.SetTextColor then
					if en then labelFS:SetTextColor(1, 1, 1, 1) else labelFS:SetTextColor(0.6, 0.6, 0.6, 1) end
				end
				y.y = y.y - 34
				_brTintRow = row
				_brTintSwatch = row.ScooterInlineSwatch
				_brTintLabel = labelFS
			end
			
			-- Border Thickness
			do
				local function get()
					local t = ensureUFDB() or {}; return tonumber(t.nameBackdropBorderThickness) or 1
				end
				local function set(v)
					local t = ensureUFDB(); if not t then return end
					local nv = tonumber(v) or 1
					if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
					t.nameBackdropBorderThickness = nv
					applyNow()
				end
				local opts = Settings.CreateSliderOptions(1, 16, 1)
				opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
				local setting = CreateLocalSetting("Border Thickness", "number", get, set, get())
				local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
				local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = setting, options = opts })
				sf.GetElementData = function() return initSlider end
				sf:SetPoint("TOPLEFT", 4, y.y)
				sf:SetPoint("TOPRIGHT", -16, y.y)
				initSlider:InitFrame(sf)
				if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
				local en = isEnabled()
				if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(en) end
				if sf.Text and sf.Text.SetTextColor then sf.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				y.y = y.y - 34
				_brThickFrame = sf
			end
			
			-- Border Inset
			do
				local function get()
					local t = ensureUFDB() or {}; return tonumber(t.nameBackdropBorderInset) or 0
				end
				local function set(v)
					local t = ensureUFDB(); if not t then return end
					local nv = tonumber(v) or 0
					if nv < -4 then nv = -4 elseif nv > 4 then nv = 4 end
					t.nameBackdropBorderInset = nv
					applyNow()
				end
				local opts = Settings.CreateSliderOptions(-4, 4, 1)
				opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
				local setting = CreateLocalSetting("Border Inset", "number", get, set, get())
				local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
				local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = setting, options = opts })
				sf.GetElementData = function() return initSlider end
				sf:SetPoint("TOPLEFT", 4, y.y)
				sf:SetPoint("TOPRIGHT", -16, y.y)
				initSlider:InitFrame(sf)
				if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
				local en = isEnabled()
				if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(en) end
				if sf.Text and sf.Text.SetTextColor then sf.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				y.y = y.y - 34
				_brInsetFrame = sf
			end
			refreshBorderEnabledState()
		end

		-- Tab C: Name Text
		do
			local function applyNow()
				if addon and addon.ApplyUnitFrameNameLevelTextFor then addon.ApplyUnitFrameNameLevelTextFor(unitKey()) end
				if addon and addon.ApplyStyles then addon:ApplyStyles() end
			end
			local function fontOptions()
				return addon.BuildFontOptionsContainer()
			end
			local y = { y = -50 }
			
			-- Disable Name Text checkbox
			local label = "Disable Name Text"
			local function getter()
				local t = ensureUFDB(); return t and not not t.nameTextHidden or false
			end
			local function setter(v)
				local t = ensureUFDB(); if not t then return end
				t.nameTextHidden = (v and true) or false
				applyNow()
			end
			local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
			local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
			local row = CreateFrame("Frame", nil, frame.PageC, "SettingsCheckboxControlTemplate")
			row.GetElementData = function() return initCb end
			row:SetPoint("TOPLEFT", 4, y.y)
			row:SetPoint("TOPRIGHT", -16, y.y)
			initCb:InitFrame(row)
			if panel and panel.ApplyRobotoWhite then
				if row.Text then panel.ApplyRobotoWhite(row.Text) end
				local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
				if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
			end
			y.y = y.y - 34

			-- Name Container Width (Target/Focus only)
			if componentId == "ufTarget" or componentId == "ufFocus" then
				local function getWidthPct()
					local t = ensureUFDB() or {}
					local s = t.textName or {}
					return tonumber(s.containerWidthPct) or 100
				end
				local function setWidthPct(v)
					local t = ensureUFDB(); if not t then return end
					t.textName = t.textName or {}
					t.textName.containerWidthPct = tonumber(v) or 100
					applyNow()
				end
				local widthRow = addSlider(
					frame.PageC,
					"Name Container Width",
					80, 150, 5,
					getWidthPct,
					setWidthPct,
					y
				)

				-- Info icon tooltip explaining purpose
				if panel and panel.CreateInfoIconForLabel and widthRow then
					local lbl = widthRow.Text or widthRow.Label
					if lbl then
						local icon = panel.CreateInfoIconForLabel(
							lbl,
							"Widen the name container to decrease the truncation of long names or with large name font sizes.",
							5,
							0,
							32
						)
						-- Defer repositioning so we can anchor precisely to the rendered label text.
						if icon and C_Timer and C_Timer.After then
							C_Timer.After(0, function()
								if not (icon:IsShown() and lbl:IsShown()) then return end
								local textWidth = lbl.GetStringWidth and lbl:GetStringWidth() or 0
								icon:ClearAllPoints()
								if textWidth and textWidth > 0 then
									icon:SetPoint("LEFT", lbl, "LEFT", textWidth + 5, 0)
								else
									icon:SetPoint("LEFT", lbl, "RIGHT", 5, 0)
								end
							end)
						end
					end
				end
			end
			
			-- Name Text Font
			addDropdown(frame.PageC, "Name Text Font", fontOptions,
				function() local t = ensureUFDB() or {}; local s = t.textName or {}; return s.fontFace or "FRIZQT__" end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.fontFace = v; applyNow() end,
				y)
			
			-- Name Text Style
			addStyle(frame.PageC, "Name Text Style",
				function() local t = ensureUFDB() or {}; local s = t.textName or {}; return s.style or "OUTLINE" end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.style = v; applyNow() end,
				y)
			
			-- Name Text Size
			addSlider(frame.PageC, "Name Text Size", 6, 48, 1,
				function() local t = ensureUFDB() or {}; local s = t.textName or {}; return tonumber(s.size) or 14 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.size = tonumber(v) or 14; applyNow() end,
				y)
			
		-- Name Text Color (dropdown + inline swatch)
		do
			local function colorOpts()
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default")
				-- Class Color option only available for Player (not Target/Focus/Pet)
				if componentId == "ufPlayer" then
					c:Add("class", "Class Color")
				end
				c:Add("custom", "Custom")
				return c:GetData()
			end
			local function getMode()
				local t = ensureUFDB() or {}; local s = t.textName or {}
				local mode = s.colorMode or "default"
				-- Reset "class" mode to "default" for Target/Focus/Pet (class option not available)
				if (componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet") and mode == "class" then
					mode = "default"
					-- Also update the stored value to prevent it from persisting
					if t then
						t.textName = t.textName or {}
						t.textName.colorMode = "default"
					end
				end
				return mode
			end
			local function setMode(v)
				local t = ensureUFDB(); if not t then return end
				-- Prevent setting "class" mode for Target/Focus/Pet (option not available)
				if (componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet") and v == "class" then
					v = "default"
				end
				t.textName = t.textName or {}; t.textName.colorMode = v or "default"; applyNow()
			end
			local function getColorTbl()
				local t = ensureUFDB() or {}; local s = t.textName or {}; local c = s.color or {1.0,0.82,0.0,1}
				return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
			end
			local function setColorTbl(r,g,b,a)
				local t = ensureUFDB(); if not t then return end
				t.textName = t.textName or {}; t.textName.color = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
			end
			panel.DropdownWithInlineSwatch(frame.PageC, y, {
				label = "Name Text Color",
				getMode = getMode,
				setMode = setMode,
				getColor = getColorTbl,
				setColor = setColorTbl,
				options = colorOpts,
				insideButton = true,
			})
		end
			
			-- Name Text Offset X
			addSlider(frame.PageC, "Name Text Offset X", -100, 100, 1,
				function() local t = ensureUFDB() or {}; local s = t.textName or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.offset = t.textName.offset or {}; t.textName.offset.x = tonumber(v) or 0; applyNow() end,
				y)
			
			-- Name Text Offset Y
			addSlider(frame.PageC, "Name Text Offset Y", -100, 100, 1,
				function() local t = ensureUFDB() or {}; local s = t.textName or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.offset = t.textName.offset or {}; t.textName.offset.y = tonumber(v) or 0; applyNow() end,
				y)
		end

		-- Tab D: Level Text
		do
			local function applyNow()
				if addon and addon.ApplyUnitFrameNameLevelTextFor then addon.ApplyUnitFrameNameLevelTextFor(unitKey()) end
				if addon and addon.ApplyStyles then addon:ApplyStyles() end
			end
			local function fontOptions()
				return addon.BuildFontOptionsContainer()
			end
			local y = { y = -50 }
			
			-- Disable Level Text checkbox
			local label = "Disable Level Text"
			local function getter()
				local t = ensureUFDB(); return t and not not t.levelTextHidden or false
			end
			local function setter(v)
				local t = ensureUFDB(); if not t then return end
				t.levelTextHidden = (v and true) or false
				applyNow()
			end
			local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
			local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
			local row = CreateFrame("Frame", nil, frame.PageD, "SettingsCheckboxControlTemplate")
			row.GetElementData = function() return initCb end
			row:SetPoint("TOPLEFT", 4, y.y)
			row:SetPoint("TOPRIGHT", -16, y.y)
			initCb:InitFrame(row)
			if panel and panel.ApplyRobotoWhite then
				if row.Text then panel.ApplyRobotoWhite(row.Text) end
				local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
				if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
			end
			y.y = y.y - 34
			
			-- Level Text Font
			addDropdown(frame.PageD, "Level Text Font", fontOptions,
				function() local t = ensureUFDB() or {}; local s = t.textLevel or {}; return s.fontFace or "FRIZQT__" end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textLevel = t.textLevel or {}; t.textLevel.fontFace = v; applyNow() end,
				y)
			
			-- Level Text Style
			addStyle(frame.PageD, "Level Text Style",
				function() local t = ensureUFDB() or {}; local s = t.textLevel or {}; return s.style or "OUTLINE" end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textLevel = t.textLevel or {}; t.textLevel.style = v; applyNow() end,
				y)
			
			-- Level Text Size
			addSlider(frame.PageD, "Level Text Size", 6, 48, 1,
				function() local t = ensureUFDB() or {}; local s = t.textLevel or {}; return tonumber(s.size) or 14 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textLevel = t.textLevel or {}; t.textLevel.size = tonumber(v) or 14; applyNow() end,
				y)
			
		-- Level Text Color (dropdown + inline swatch)
		do
			local function colorOpts()
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default")
				c:Add("class", "Class Color")
				c:Add("custom", "Custom")
				return c:GetData()
			end
			local function getMode()
				local t = ensureUFDB() or {}; local s = t.textLevel or {}; return s.colorMode or "default"
			end
			local function setMode(v)
				local t = ensureUFDB(); if not t then return end
				t.textLevel = t.textLevel or {}; t.textLevel.colorMode = v or "default"; applyNow()
			end
			local function getColorTbl()
				local t = ensureUFDB() or {}; local s = t.textLevel or {}; local c = s.color or {1.0,0.82,0.0,1}
				return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
			end
			local function setColorTbl(r,g,b,a)
				local t = ensureUFDB(); if not t then return end
				t.textLevel = t.textLevel or {}; t.textLevel.color = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
			end
			panel.DropdownWithInlineSwatch(frame.PageD, y, {
				label = "Level Text Color",
				getMode = getMode,
				setMode = setMode,
				getColor = getColorTbl,
				setColor = setColorTbl,
				options = colorOpts,
				insideButton = true,
			})
		end
			
			-- Level Text Offset X
			addSlider(frame.PageD, "Level Text Offset X", -100, 100, 1,
				function() local t = ensureUFDB() or {}; local s = t.textLevel or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textLevel = t.textLevel or {}; t.textLevel.offset = t.textLevel.offset or {}; t.textLevel.offset.x = tonumber(v) or 0; applyNow() end,
				y)
			
			-- Level Text Offset Y
			addSlider(frame.PageD, "Level Text Offset Y", -100, 100, 1,
				function() local t = ensureUFDB() or {}; local s = t.textLevel or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textLevel = t.textLevel or {}; t.textLevel.offset = t.textLevel.offset or {}; t.textLevel.offset.y = tonumber(v) or 0; applyNow() end,
				y)
		end
		end

		local nltInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", nltTabs)
		-- Static height for Name & Level Text tabs (Backdrop/Border/Name/Level).
		-- 300px was barely sufficient for 7 controls; with the 8th "Name Container Width"
		-- control on the Name Text tab we align with the 330px class used elsewhere
		-- for tabs with 7-8 settings (see TABBEDSECTIONS.md).
		nltInit.GetExtent = function() return 330 end
		nltInit:AddShownPredicate(function()
			return panel:IsSectionExpanded(componentId, "Name & Level Text")
		end)
		table.insert(init, nltInit)

		-- Fifth collapsible section: Portrait (all unit frames)
		local expInitializerPortrait = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
			name = "Portrait",
			sectionKey = "Portrait",
			componentId = componentId,
			expanded = panel:IsSectionExpanded(componentId, "Portrait"),
		})
		expInitializerPortrait.GetExtent = function() return 30 end
		table.insert(init, expInitializerPortrait)

		-- Portrait tabs: Positioning / Sizing / Mask / Border / Damage Text / Visibility
		-- Damage Text tab only exists for Player frame
		-- Positioning tab disabled for Pet (PetFrame is a managed frame; moving portrait causes entire frame to move)
		local portraitTabs = { sectionTitle = "", tabAText = (componentId ~= "ufPet") and "Positioning" or nil, tabBText = "Sizing", tabCText = "Mask", tabDText = "Border", tabEText = (componentId == "ufPlayer") and "Damage Text" or nil, tabFText = "Visibility" }
		portraitTabs.build = function(frame)
			-- Helper for unit key
			local function unitKey()
				if componentId == "ufPlayer" then return "Player" end
				if componentId == "ufTarget" then return "Target" end
				if componentId == "ufFocus" then return "Focus" end
				if componentId == "ufPet" then return "Pet" end
				return nil
			end

			-- Helper to ensure unit frame DB
			local function ensureUFDB()
				local db = addon and addon.db and addon.db.profile
				if not db then return nil end
				db.unitFrames = db.unitFrames or {}
				local uk = unitKey(); if not uk then return nil end
				db.unitFrames[uk] = db.unitFrames[uk] or {}
				db.unitFrames[uk].portrait = db.unitFrames[uk].portrait or {}
				return db.unitFrames[uk].portrait
			end

			-- Helper functions for controls
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
				return f
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
				if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
					addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
				end
				yRef.y = yRef.y - 34
				return f
			end
			local function addStyle(parent, label, getFunc, setFunc, yRef)
				local function styleOptions()
					local container = Settings.CreateControlTextContainer();
					container:Add("NONE", "Regular");
					container:Add("OUTLINE", "Outline");
					container:Add("THICKOUTLINE", "Thick Outline");
					return container:GetData()
				end
				return addDropdown(parent, label, styleOptions, getFunc, setFunc, yRef)
			end

			-- PageA: Positioning (disabled for Pet - PetFrame is a managed frame; moving portrait causes entire frame to move)
			if componentId ~= "ufPet" then
				do
					local function applyNow()
						if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local y = { y = -50 }
					
					-- X Offset slider
					addSlider(frame.PageA, "X Offset", -100, 100, 1,
						function() local t = ensureUFDB() or {}; return tonumber(t.offsetX) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.offsetX = tonumber(v) or 0; applyNow() end,
						y)
					
					-- Y Offset slider
					addSlider(frame.PageA, "Y Offset", -100, 100, 1,
						function() local t = ensureUFDB() or {}; return tonumber(t.offsetY) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.offsetY = tonumber(v) or 0; applyNow() end,
						y)
				end
			end

			-- PageB: Sizing
			do
				local function applyNow()
					if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
					if addon and addon.ApplyStyles then addon:ApplyStyles() end
				end
				local y = { y = -50 }
				
				-- Portrait Size (Scale) slider
				addSlider(frame.PageB, "Portrait Size (Scale)", 50, 200, 1,
					function() local t = ensureUFDB() or {}; return tonumber(t.scale) or 100 end,
					function(v) local t = ensureUFDB(); if not t then return end; t.scale = tonumber(v) or 100; applyNow() end,
					y)
			end

			-- PageC: Mask
			do
				local function applyNow()
					if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
					if addon and addon.ApplyStyles then addon:ApplyStyles() end
				end
				local y = { y = -50 }
				
				-- Portrait Zoom slider
				-- Note: Zoom out (< 100%) is not supported because portrait textures are already at full bounds (0,1,0,1).
				-- We cannot show pixels beyond the texture bounds. Zoom in (> 100%) works by cropping the edges.
				-- Range: 100-200% (zoom in only)
				addSlider(frame.PageC, "Portrait Zoom", 100, 200, 1,
					function() local t = ensureUFDB() or {}; return tonumber(t.zoom) or 100 end,
					function(v) local t = ensureUFDB(); if not t then return end; t.zoom = tonumber(v) or 100; applyNow() end,
					y)
				
				-- Use Full Circle Mask checkbox (Player only)
				if unitKey() == "Player" then
					do
						local setting = CreateLocalSetting("Use Full Circle Mask", "boolean",
							function() local t = ensureUFDB() or {}; return (t.useFullCircleMask == true) end,
							function(v) local t = ensureUFDB(); if not t then return end; t.useFullCircleMask = (v == true); applyNow() end,
							false)
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Use Full Circle Mask", setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, frame.PageC, "SettingsCheckboxControlTemplate")
						row.GetElementData = function() return initCb end
						row:SetPoint("TOPLEFT", 4, y.y)
						row:SetPoint("TOPRIGHT", -16, y.y)
						initCb:InitFrame(row)
						if panel and panel.ApplyRobotoWhite then
							if row.Text then panel.ApplyRobotoWhite(row.Text) end
							local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
						end
						y.y = y.y - 34
					end
				end
			end

			-- PageD: Border
			do
				local function applyNow()
					if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
					if addon and addon.ApplyStyles then addon:ApplyStyles() end
				end
				local y = { y = -50 }
				
				-- Helper function to check if border is enabled
				local function isEnabled()
					local t = ensureUFDB() or {}
					return not not t.portraitBorderEnable
				end
				
				-- Use Custom Border checkbox
				do
					local setting = CreateLocalSetting("Use Custom Border", "boolean",
						function() local t = ensureUFDB() or {}; return (t.portraitBorderEnable == true) end,
						function(v) 
							local t = ensureUFDB(); if not t then return end
							t.portraitBorderEnable = (v == true)
							-- Refresh the panel to update gray-out state
							if panel and panel.RefreshCurrentCategoryDeferred then
								panel:RefreshCurrentCategoryDeferred()
							end
							applyNow()
						end,
						false)
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Use Custom Border", setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, frame.PageD, "SettingsCheckboxControlTemplate")
					row.GetElementData = function() return initCb end
					row:SetPoint("TOPLEFT", 4, y.y)
					row:SetPoint("TOPRIGHT", -16, y.y)
					initCb:InitFrame(row)
					if panel and panel.ApplyRobotoWhite then
						if row.Text then panel.ApplyRobotoWhite(row.Text) end
						local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					y.y = y.y - 34
				end
				
				-- Border Style dropdown
				do
					local function optionsStyle()
						local c = Settings.CreateControlTextContainer()
						c:Add("texture_c", "Circle")
						c:Add("texture_s", "Circle with Corner")
						c:Add("rare_c", "Rare (Circle)")
						-- Rare (Square) only available for Target and Focus
						if unitKey() == "Target" or unitKey() == "Focus" then
							c:Add("rare_s", "Rare (Square)")
						end
						return c:GetData()
					end
					local function getStyle()
						local t = ensureUFDB() or {}
						local current = t.portraitBorderStyle or "texture_c"
						-- If current style is "default" or "rare_s" for non-Target/Focus, reset to first option
						if current == "default" then
							return "texture_c"
						end
						if current == "rare_s" and unitKey() ~= "Target" and unitKey() ~= "Focus" then
							return "texture_c"
						end
						return current
					end
					local function setStyle(v)
						local t = ensureUFDB(); if not t then return end
						-- Don't allow "default" or "rare_s" for non-Target/Focus
						if v == "default" then
							v = "texture_c"
						end
						if v == "rare_s" and unitKey() ~= "Target" and unitKey() ~= "Focus" then
							v = "texture_c"
						end
						t.portraitBorderStyle = v or "texture_c"
						applyNow()
					end
					local styleSetting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
					local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = styleSetting, options = optionsStyle })
					local f = CreateFrame("Frame", nil, frame.PageD, "SettingsDropdownControlTemplate")
					f.GetElementData = function() return initDrop end
					f:SetPoint("TOPLEFT", 4, y.y)
					f:SetPoint("TOPRIGHT", -16, y.y)
					initDrop:InitFrame(f)
					local lbl = f and (f.Text or f.Label)
					if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
					-- Grey out when Use Custom Border is off
					local enabled = isEnabled()
					if f.Control and f.Control.SetEnabled then f.Control:SetEnabled(enabled) end
					if lbl and lbl.SetTextColor then
						if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
					end
					y.y = y.y - 34
				end
				
				-- Border Inset slider (moved to directly after Border Style)
				do
					local function getInset()
						local t = ensureUFDB() or {}; return tonumber(t.portraitBorderThickness) or 1
					end
					local function setInset(v)
						local t = ensureUFDB(); if not t then return end
						local nv = tonumber(v) or 1
						if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
						t.portraitBorderThickness = nv
						applyNow()
					end
					local opts = Settings.CreateSliderOptions(1, 16, 1)
					opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
					local insetSetting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
					local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
					local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
					sf.GetElementData = function() return initSlider end
					sf:SetPoint("TOPLEFT", 4, y.y)
					sf:SetPoint("TOPRIGHT", -16, y.y)
					initSlider:InitFrame(sf)
					if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
					-- Grey out when Use Custom Border is off
					local enabled = isEnabled()
					if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled) end
					if sf.Text and sf.Text.SetTextColor then
						if enabled then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
					end
					y.y = y.y - 34
				end
				
				-- Border Color (dropdown) + inline Custom Tint swatch (unified control)
				do
					local function colorOpts()
						local container = Settings.CreateControlTextContainer()
						container:Add("texture", "Texture Original")
						container:Add("class", "Class Color")
						container:Add("custom", "Custom")
						return container:GetData()
					end
					local function getColorMode()
						local t = ensureUFDB() or {}
						return t.portraitBorderColorMode or "texture"
					end
					local function setColorMode(v)
						local t = ensureUFDB(); if not t then return end
						t.portraitBorderColorMode = v or "texture"
						applyNow()
					end
					local function getTint()
						local t = ensureUFDB() or {}
						local c = t.portraitBorderTintColor or {1,1,1,1}
						return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
					end
					local function setTint(r, g, b, a)
						local t = ensureUFDB(); if not t then return end
						t.portraitBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
						applyNow()
					end
					panel.DropdownWithInlineSwatch(frame.PageD, y, {
						label = "Border Color",
						getMode = getColorMode,
						setMode = setColorMode,
						getColor = getTint,
						setColor = setTint,
						options = colorOpts,
						isEnabled = isEnabled,
						insideButton = true,
					})
				end
			end

			-- PageE: Damage Text (Player only)
			do
				-- Only show this tab for Player frame
				if unitKey() ~= "Player" then
					-- Empty page for non-Player frames
					local y = { y = -50 }
				else
					local function applyNow()
						if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local function fontOptions()
						return addon.BuildFontOptionsContainer()
					end
					local y = { y = -50 }
					
					-- Helper function to check if damage text is disabled
					local function isDisabled()
						local t = ensureUFDB() or {}
						return not not t.damageTextDisabled
					end
					
					-- Store references to controls for gray-out logic
					local _dtFontFrame, _dtStyleFrame, _dtSizeFrame, _dtColorFrame, _dtOffsetXFrame, _dtOffsetYFrame
					
					-- Function to refresh gray-out state
					local function refreshDamageTextDisabledState()
						local disabled = isDisabled()
						-- Gray out all controls when disabled
						if _dtFontFrame then
							if _dtFontFrame.Control and _dtFontFrame.Control.SetEnabled then _dtFontFrame.Control:SetEnabled(not disabled) end
							local lbl = _dtFontFrame.Text or _dtFontFrame.Label
							if lbl and lbl.SetTextColor then lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
						end
						if _dtStyleFrame then
							if _dtStyleFrame.Control and _dtStyleFrame.Control.SetEnabled then _dtStyleFrame.Control:SetEnabled(not disabled) end
							local lbl = _dtStyleFrame.Text or _dtStyleFrame.Label
							if lbl and lbl.SetTextColor then lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
						end
						if _dtSizeFrame then
							if _dtSizeFrame.Control and _dtSizeFrame.Control.SetEnabled then _dtSizeFrame.Control:SetEnabled(not disabled) end
							if _dtSizeFrame.Text and _dtSizeFrame.Text.SetTextColor then _dtSizeFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
						end
						if _dtColorFrame then
							-- Color dropdown
							if _dtColorFrame.Control and _dtColorFrame.Control.SetEnabled then _dtColorFrame.Control:SetEnabled(not disabled) end
							local lbl = _dtColorFrame.Text or _dtColorFrame.Label
							if lbl and lbl.SetTextColor then lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
							-- Color swatch
							if _dtColorFrame.ScooterInlineSwatch and _dtColorFrame.ScooterInlineSwatch.EnableMouse then
								_dtColorFrame.ScooterInlineSwatch:EnableMouse(not disabled)
								if _dtColorFrame.ScooterInlineSwatch.SetAlpha then _dtColorFrame.ScooterInlineSwatch:SetAlpha(disabled and 0.5 or 1) end
							end
						end
						if _dtOffsetXFrame then
							if _dtOffsetXFrame.Control and _dtOffsetXFrame.Control.SetEnabled then _dtOffsetXFrame.Control:SetEnabled(not disabled) end
							if _dtOffsetXFrame.Text and _dtOffsetXFrame.Text.SetTextColor then _dtOffsetXFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
						end
						if _dtOffsetYFrame then
							if _dtOffsetYFrame.Control and _dtOffsetYFrame.Control.SetEnabled then _dtOffsetYFrame.Control:SetEnabled(not disabled) end
							if _dtOffsetYFrame.Text and _dtOffsetYFrame.Text.SetTextColor then _dtOffsetYFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
						end
					end
					
					-- Disable Damage Text checkbox
					local label = "Disable Damage Text"
					local function getter()
						local t = ensureUFDB(); return t and not not t.damageTextDisabled or false
					end
					local function setter(v)
						local t = ensureUFDB(); if not t then return end
						t.damageTextDisabled = (v and true) or false
						applyNow()
						refreshDamageTextDisabledState()
					end
					local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, frame.PageE, "SettingsCheckboxControlTemplate")
					row.GetElementData = function() return initCb end
					row:SetPoint("TOPLEFT", 4, y.y)
					row:SetPoint("TOPRIGHT", -16, y.y)
					initCb:InitFrame(row)
					if panel and panel.ApplyRobotoWhite then
						if row.Text then panel.ApplyRobotoWhite(row.Text) end
						local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					y.y = y.y - 34
					
					-- Damage Text Font
					_dtFontFrame = addDropdown(frame.PageE, "Font", fontOptions,
						function() local t = ensureUFDB() or {}; local s = t.damageText or {}; return s.fontFace or "FRIZQT__" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.fontFace = v; applyNow() end,
						y)
					
					-- Damage Text Style
					_dtStyleFrame = addStyle(frame.PageE, "Font Style",
						function() local t = ensureUFDB() or {}; local s = t.damageText or {}; return s.style or "OUTLINE" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.style = v; applyNow() end,
						y)
					
					-- Damage Text Size
					_dtSizeFrame = addSlider(frame.PageE, "Font Size", 6, 48, 1,
						function() local t = ensureUFDB() or {}; local s = t.damageText or {}; return tonumber(s.size) or 14 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.size = tonumber(v) or 14; applyNow() end,
						y)
					
					-- Damage Text Color (dropdown + inline swatch)
					do
						local function colorOpts()
							local c = Settings.CreateControlTextContainer()
							c:Add("default", "Default")
							c:Add("class", "Class Color")
							c:Add("custom", "Custom")
							return c:GetData()
						end
						local function getMode()
							local t = ensureUFDB() or {}; local s = t.damageText or {}; return s.colorMode or "default"
						end
						local function setMode(v)
							local t = ensureUFDB(); if not t then return end
							t.damageText = t.damageText or {}; t.damageText.colorMode = v or "default"; applyNow()
						end
						local function getColorTbl()
							local t = ensureUFDB() or {}; local s = t.damageText or {}; local c = s.color or {1.0,0.82,0.0,1}
							return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
						end
						local function setColorTbl(r,g,b,a)
							local t = ensureUFDB(); if not t then return end
							t.damageText = t.damageText or {}; t.damageText.color = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
						end
						_dtColorFrame = panel.DropdownWithInlineSwatch(frame.PageE, y, {
							label = "Font Color",
							getMode = getMode,
							setMode = setMode,
							getColor = getColorTbl,
							setColor = setColorTbl,
							options = colorOpts,
							insideButton = true,
						})
					end
					
					-- Damage Text Offset X
					_dtOffsetXFrame = addSlider(frame.PageE, "Font X Offset", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.damageText or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.offset = t.damageText.offset or {}; t.damageText.offset.x = tonumber(v) or 0; applyNow() end,
						y)
					
					-- Damage Text Offset Y
					_dtOffsetYFrame = addSlider(frame.PageE, "Font Y Offset", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.damageText or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.offset = t.damageText.offset or {}; t.damageText.offset.y = tonumber(v) or 0; applyNow() end,
						y)
					
					-- Initialize gray-out state
					refreshDamageTextDisabledState()
				end
			end

			-- PageF: Visibility
			do
				local function applyNow()
					if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
					if addon and addon.ApplyStyles then addon:ApplyStyles() end
				end
				local y = { y = -50 }
				
				-- Hide Portrait checkbox
				do
					local setting = CreateLocalSetting("Hide Portrait", "boolean",
						function() local t = ensureUFDB() or {}; return (t.hidePortrait == true) end,
						function(v) local t = ensureUFDB(); if not t then return end; t.hidePortrait = (v == true); applyNow() end,
						false)
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Portrait", setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, frame.PageF, "SettingsCheckboxControlTemplate")
					row.GetElementData = function() return initCb end
					row:SetPoint("TOPLEFT", 4, y.y)
					row:SetPoint("TOPRIGHT", -16, y.y)
					initCb:InitFrame(row)
					if panel and panel.ApplyRobotoWhite then
						if row.Text then panel.ApplyRobotoWhite(row.Text) end
						local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					y.y = y.y - 34
				end
				
				-- Hide Rest Loop/Animation checkbox (Player only)
				if unitKey() == "Player" then
					do
						local setting = CreateLocalSetting("Hide Rest Loop/Animation", "boolean",
							function() local t = ensureUFDB() or {}; return (t.hideRestLoop == true) end,
							function(v) local t = ensureUFDB(); if not t then return end; t.hideRestLoop = (v == true); applyNow() end,
							false)
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Rest Loop/Animation", setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, frame.PageF, "SettingsCheckboxControlTemplate")
						row.GetElementData = function() return initCb end
						row:SetPoint("TOPLEFT", 4, y.y)
						row:SetPoint("TOPRIGHT", -16, y.y)
						initCb:InitFrame(row)
						if panel and panel.ApplyRobotoWhite then
							if row.Text then panel.ApplyRobotoWhite(row.Text) end
							local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
						end
						y.y = y.y - 34
					end
				end
				
				-- Hide Status Texture checkbox (Player only)
				if unitKey() == "Player" then
					do
						local setting = CreateLocalSetting("Hide Status Texture", "boolean",
							function() local t = ensureUFDB() or {}; return (t.hideStatusTexture == true) end,
							function(v) local t = ensureUFDB(); if not t then return end; t.hideStatusTexture = (v == true); applyNow() end,
							false)
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Status Texture", setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, frame.PageF, "SettingsCheckboxControlTemplate")
						row.GetElementData = function() return initCb end
						row:SetPoint("TOPLEFT", 4, y.y)
						row:SetPoint("TOPRIGHT", -16, y.y)
						initCb:InitFrame(row)
						if panel and panel.ApplyRobotoWhite then
							if row.Text then panel.ApplyRobotoWhite(row.Text) end
							local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
						end
						y.y = y.y - 34
					end
				end
				
				-- Hide Corner Icon checkbox (Player only)
				if unitKey() == "Player" then
					do
						local setting = CreateLocalSetting("Hide Corner Icon", "boolean",
							function() local t = ensureUFDB() or {}; return (t.hideCornerIcon == true) end,
							function(v) local t = ensureUFDB(); if not t then return end; t.hideCornerIcon = (v == true); applyNow() end,
							false)
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Corner Icon", setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, frame.PageF, "SettingsCheckboxControlTemplate")
						row.GetElementData = function() return initCb end
						row:SetPoint("TOPLEFT", 4, y.y)
						row:SetPoint("TOPRIGHT", -16, y.y)
						initCb:InitFrame(row)
						if panel and panel.ApplyRobotoWhite then
							if row.Text then panel.ApplyRobotoWhite(row.Text) end
							local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
						end
						y.y = y.y - 34
					end
				end
				
				-- Portrait Opacity slider (1-100%)
				addSlider(frame.PageF, "Portrait Opacity", 1, 100, 1,
					function() local t = ensureUFDB() or {}; return tonumber(t.opacity) or 100 end,
					function(v) local t = ensureUFDB(); if not t then return end; t.opacity = tonumber(v) or 100; applyNow() end,
					y)
			end
		end

		local portraitInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", portraitTabs)
		-- STATIC HEIGHT for tabbed sections with up to 7-8 settings per tab.
		-- Current: 330px provides comfortable spacing with 2px top gap and room at bottom.
		-- DO NOT reduce below 315px or settings will bleed past the bottom border.
		portraitInit.GetExtent = function() return 330 end
		portraitInit:AddShownPredicate(function()
			return panel:IsSectionExpanded(componentId, "Portrait")
		end)
		table.insert(init, portraitInit)

		-- Sixth collapsible section: Cast Bar (Player/Target/Focus)
			if componentId == "ufPlayer" or componentId == "ufTarget" or componentId == "ufFocus" then
				local expInitializerCB = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
					name = "Cast Bar",
					sectionKey = "Cast Bar",
					componentId = componentId,
					expanded = panel:IsSectionExpanded(componentId, "Cast Bar"),
				})
				expInitializerCB.GetExtent = function() return 30 end
				table.insert(init, expInitializerCB)

				-- Cast Bar tabbed section:
				-- Tabs (in order): Positioning, Sizing, Style, Border, Icon, Spell Name Text, Cast Time Text, Visibility
				local cbData = {
					sectionTitle = "",
					tabAText = "Positioning",
					tabBText = "Sizing",
					tabCText = "Style",
					tabDText = "Border",
					tabEText = "Icon",
					tabFText = "Spell Name Text",
					tabGText = "Cast Time Text",
					tabHText = "Visibility",
				}
				cbData.build = function(frame)
					-- Helper: map componentId -> unit key
					local function unitKey()
						if componentId == "ufPlayer" then return "Player" end
						if componentId == "ufTarget" then return "Target" end
						if componentId == "ufFocus" then return "Focus" end
						return nil
					end

					-- Helper: ensure Unit Frame Cast Bar DB namespace
					local function ensureCastBarDB()
						local uk = unitKey()
						if not uk then return nil end
						local db = addon and addon.db and addon.db.profile
						if not db then return nil end
						db.unitFrames = db.unitFrames or {}
						db.unitFrames[uk] = db.unitFrames[uk] or {}
						db.unitFrames[uk].castBar = db.unitFrames[uk].castBar or {}
						return db.unitFrames[uk].castBar
					end

					-- Small slider helper (used for Target/Focus offsets, Cast Bar icon sizing, and text controls)
					local function addSlider(parent, label, minV, maxV, step, getFunc, setFunc, yRef)
						local options = Settings.CreateSliderOptions(minV, maxV, step)
						options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
							return tostring(math.floor((tonumber(v) or 0) + 0.5))
						end)
						local setting = CreateLocalSetting(label, "number", getFunc, setFunc, getFunc())
						local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
						local f = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
						f.GetElementData = function() return initSlider end
						f:SetPoint("TOPLEFT", 4, yRef.y)
						f:SetPoint("TOPRIGHT", -16, yRef.y)
						initSlider:InitFrame(f)
						if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
						yRef.y = yRef.y - 34
						return f
					end

					-- Local dropdown/text helpers (mirror Unit Frame Health/Power helpers)
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
						-- When the label mentions "Font", initialize the font dropdown wrapper
						if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
							addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
						end
						yRef.y = yRef.y - 34
						return f
					end

					local function addStyle(parent, label, getFunc, setFunc, yRef)
						local function styleOptions()
							local container = Settings.CreateControlTextContainer()
							container:Add("NONE", "Regular")
							container:Add("OUTLINE", "Outline")
							container:Add("THICKOUTLINE", "Thick Outline")
							return container:GetData()
						end
						return addDropdown(parent, label, styleOptions, getFunc, setFunc, yRef)
					end

					local function addColor(parent, label, hasAlpha, getFunc, setFunc, yRef)
						local f = CreateFrame("Frame", nil, parent, "SettingsListElementTemplate")
						f:SetHeight(26)
						f:SetPoint("TOPLEFT", 4, yRef.y)
						f:SetPoint("TOPRIGHT", -16, yRef.y)
						if f.Text then
							f.Text:SetText(label)
							if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
						end
						local right = CreateFrame("Frame", nil, f)
						right:SetSize(250, 26)
						right:SetPoint("RIGHT", f, "RIGHT", -16, 0)
						if f.Text then
							f.Text:ClearAllPoints()
							f.Text:SetPoint("LEFT", f, "LEFT", 36.5, 0)
							f.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
							f.Text:SetJustifyH("LEFT")
						end
						-- Use centralized color swatch factory
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
						return f
					end

					-- Shared Style tab (all unit frames with a Cast Bar)
					local function buildStyleTab()
						local uk = unitKey()
						if not uk then return end
						local function applyNow()
							if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor(uk) end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end

						local stylePage = frame.PageC
						local y = { y = -50 }

						-- Foreground Texture dropdown
						do
							local function getTex()
								local t = ensureCastBarDB() or {}
								return t.castBarTexture or "default"
							end
							local function setTex(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castBarTexture = v
								applyNow()
							end
							local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
							local function texOptions()
								if addon.BuildBarTextureOptionsContainer then
									return addon.BuildBarTextureOptionsContainer()
								end
								local container = Settings.CreateControlTextContainer()
								container:Add("default", "Default")
								return container:GetData()
							end
							local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Foreground Texture", setting = texSetting, options = texOptions })
							local f = CreateFrame("Frame", nil, stylePage, "SettingsDropdownControlTemplate")
							f.GetElementData = function() return initDrop end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initDrop:InitFrame(f)
							if panel and panel.ApplyRobotoWhite then
								local lbl = f and (f.Text or f.Label)
								if lbl then panel.ApplyRobotoWhite(lbl) end
							end
							if f.Control and addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(f.Control, texSetting) end
							y.y = y.y - 34
						end

						-- Foreground Color (dropdown + inline swatch)
						do
							local function colorOpts()
								local container = Settings.CreateControlTextContainer()
								container:Add("default", "Default")
								container:Add("texture", "Texture Original")
								container:Add("class", "Class Color")
								container:Add("custom", "Custom")
								return container:GetData()
							end
							local function getMode()
								local t = ensureCastBarDB() or {}
								return t.castBarColorMode or "default"
							end
							local function setMode(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castBarColorMode = v or "default"
								applyNow()
							end
							local function getTint()
								local t = ensureCastBarDB() or {}
								local c = t.castBarTint or {1,1,1,1}
								return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
							end
							local function setTint(r,g,b,a)
								local t = ensureCastBarDB(); if not t then return end
								t.castBarTint = { r or 1, g or 1, b or 1, a or 1 }
								applyNow()
							end
							panel.DropdownWithInlineSwatch(stylePage, y, {
								label = "Foreground Color",
								getMode = getMode,
								setMode = setMode,
								getColor = getTint,
								setColor = setTint,
								options = colorOpts,
								insideButton = true,
							})
						end

						-- Background Texture dropdown
						do
							local function getBgTex()
								local t = ensureCastBarDB() or {}
								return t.castBarBackgroundTexture or "default"
							end
							local function setBgTex(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castBarBackgroundTexture = v
								applyNow()
							end
							local bgSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
							local function bgOptions()
								if addon.BuildBarTextureOptionsContainer then
									return addon.BuildBarTextureOptionsContainer()
								end
								local container = Settings.CreateControlTextContainer()
								container:Add("default", "Default")
								return container:GetData()
							end
							local initBg = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Background Texture", setting = bgSetting, options = bgOptions })
							local fbg = CreateFrame("Frame", nil, stylePage, "SettingsDropdownControlTemplate")
							fbg.GetElementData = function() return initBg end
							fbg:SetPoint("TOPLEFT", 4, y.y)
							fbg:SetPoint("TOPRIGHT", -16, y.y)
							initBg:InitFrame(fbg)
							if panel and panel.ApplyRobotoWhite then
								local lbl = fbg and (fbg.Text or fbg.Label)
								if lbl then panel.ApplyRobotoWhite(lbl) end
							end
							if fbg.Control and addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(fbg.Control, bgSetting) end
							y.y = y.y - 34
						end

						-- Background Color (dropdown + inline swatch)
						do
							local function bgColorOpts()
								local container = Settings.CreateControlTextContainer()
								container:Add("default", "Default")
								container:Add("texture", "Texture Original")
								container:Add("custom", "Custom")
								return container:GetData()
							end
							local function getBgMode()
								local t = ensureCastBarDB() or {}
								return t.castBarBackgroundColorMode or "default"
							end
							local function setBgMode(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castBarBackgroundColorMode = v or "default"
								applyNow()
							end
							local function getBgTint()
								local t = ensureCastBarDB() or {}
								local c = t.castBarBackgroundTint or {0,0,0,1}
								return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
							end
							local function setBgTint(r,g,b,a)
								local t = ensureCastBarDB(); if not t then return end
								t.castBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }
								applyNow()
							end
							panel.DropdownWithInlineSwatch(stylePage, y, {
								label = "Background Color",
								getMode = getBgMode,
								setMode = setBgMode,
								getColor = getBgTint,
								setColor = setBgTint,
								options = bgColorOpts,
								insideButton = true,
							})
						end

						-- Background Opacity slider (0–100%)
						do
							local function getBgOpacity()
								local t = ensureCastBarDB() or {}
								return tonumber(t.castBarBackgroundOpacity) or 50
							end
							local function setBgOpacity(v)
								local t = ensureCastBarDB(); if not t then return end
								local val = tonumber(v) or 50
								if val < 0 then val = 0 elseif val > 100 then val = 100 end
								t.castBarBackgroundOpacity = val
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(0, 100, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
								return tostring(math.floor((tonumber(v) or 0) + 0.5))
							end)
							local setting = CreateLocalSetting("Background Opacity", "number", getBgOpacity, setBgOpacity, getBgOpacity())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Background Opacity", setting = setting, options = opts })
							local f = CreateFrame("Frame", nil, stylePage, "SettingsSliderControlTemplate")
							f.GetElementData = function() return initSlider end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(f)
							if panel and panel.ApplyRobotoWhite and f.Text then panel.ApplyRobotoWhite(f.Text) end
						end
					end

					-- Shared Border tab (all unit frames with a Cast Bar)
					local function buildBorderTab()
						local uk = unitKey()
						if not uk then return end

						local function applyNow()
							if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor(uk) end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end

						local borderPage = frame.PageD
						local y = { y = -50 }

						-- Ensure Cast Bar DB namespace
						local function ensureCastBarDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames[uk] = db.unitFrames[uk] or {}
							db.unitFrames[uk].castBar = db.unitFrames[uk].castBar or {}
							return db.unitFrames[uk].castBar
						end

						local function isEnabled()
							local t = ensureCastBarDB() or {}
							return not not t.castBarBorderEnable
						end

						-- Local references so we can gray-out rows without rebuilding the category (avoids flicker)
						local _styleFrame, _colorFrame, _thickFrame, _insetFrame
						local function refreshBorderEnabledState()
							local enabled = isEnabled()

							-- Border Style
							if _styleFrame then
								if _styleFrame.Control and _styleFrame.Control.SetEnabled then
									_styleFrame.Control:SetEnabled(enabled)
								end
								local lbl = _styleFrame.Text or _styleFrame.Label
								if lbl and lbl.SetTextColor then
									if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
								end
							end

							-- Border Color dropdown + swatch
							if _colorFrame then
								if _colorFrame.Control and _colorFrame.Control.SetEnabled then
									_colorFrame.Control:SetEnabled(enabled)
								end
								local lbl = _colorFrame.Text or _colorFrame.Label
								if lbl and lbl.SetTextColor then
									if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
								end
								if _colorFrame.ScooterInlineSwatch and _colorFrame.ScooterInlineSwatch.EnableMouse then
									_colorFrame.ScooterInlineSwatch:EnableMouse(enabled)
									if _colorFrame.ScooterInlineSwatch.SetAlpha then
										_colorFrame.ScooterInlineSwatch:SetAlpha(enabled and 1 or 0.5)
									end
								end
							end

							-- Border Thickness
							if _thickFrame then
								if _thickFrame.Control and _thickFrame.Control.SetEnabled then
									_thickFrame.Control:SetEnabled(enabled)
								end
								if _thickFrame.Text and _thickFrame.Text.SetTextColor then
									if enabled then _thickFrame.Text:SetTextColor(1, 1, 1, 1) else _thickFrame.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
								end
							end

							-- Border Inset
							if _insetFrame then
								if _insetFrame.Control and _insetFrame.Control.SetEnabled then
									_insetFrame.Control:SetEnabled(enabled)
								end
								if _insetFrame.Text and _insetFrame.Text.SetTextColor then
									if enabled then _insetFrame.Text:SetTextColor(1, 1, 1, 1) else _insetFrame.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
								end
							end
						end

						-- Enable Custom Border checkbox
						do
							local label = "Enable Custom Border"
							local function getter()
								local t = ensureCastBarDB() or {}
								return not not t.castBarBorderEnable
							end
							local function setter(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castBarBorderEnable = (v == true)
								applyNow()
								-- Update gray-out state in-place to avoid panel flicker
								refreshBorderEnabledState()
							end
							local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
							local row = CreateFrame("Frame", nil, borderPage, "SettingsCheckboxControlTemplate")
							row.GetElementData = function() return initCb end
							row:SetPoint("TOPLEFT", 4, y.y)
							row:SetPoint("TOPRIGHT", -16, y.y)
							initCb:InitFrame(row)
							if panel and panel.ApplyRobotoWhite then
								if row.Text then panel.ApplyRobotoWhite(row.Text) end
								local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
								if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
							end
							y.y = y.y - 34
						end

						-- Border Style dropdown
						do
							local function optionsBorder()
								if addon.BuildBarBorderOptionsContainer then
									return addon.BuildBarBorderOptionsContainer()
								end
								local c = Settings.CreateControlTextContainer()
								c:Add("square", "Default (Square)")
								return c:GetData()
							end
							local function getStyle()
								local t = ensureCastBarDB() or {}
								return t.castBarBorderStyle or "square"
							end
							local function setStyle(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castBarBorderStyle = v or "square"
								applyNow()
							end
							local setting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
							local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = setting, options = optionsBorder })
							local f = CreateFrame("Frame", nil, borderPage, "SettingsDropdownControlTemplate")
							f.GetElementData = function() return initDrop end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initDrop:InitFrame(f)
							local lbl = f and (f.Text or f.Label)
							if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
							_styleFrame = f
							y.y = y.y - 34
						end

						-- Border Color (dropdown + inline swatch)
						do
							local function colorOpts()
								local c = Settings.CreateControlTextContainer()
								c:Add("default", "Default")
								c:Add("texture", "Texture Original")
								c:Add("custom", "Custom")
								return c:GetData()
							end
							local function getMode()
								local t = ensureCastBarDB() or {}
								return t.castBarBorderColorMode or "default"
							end
							local function setMode(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castBarBorderColorMode = v or "default"
								applyNow()
							end
							local function getTint()
								local t = ensureCastBarDB() or {}
								local c = t.castBarBorderTintColor or {1,1,1,1}
								return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
							end
							local function setTint(r,g,b,a)
								local t = ensureCastBarDB(); if not t then return end
								t.castBarBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
								applyNow()
							end
							_colorFrame = panel.DropdownWithInlineSwatch(borderPage, y, {
								label = "Border Color",
								getMode = getMode,
								setMode = setMode,
								getColor = getTint,
								setColor = setTint,
								options = colorOpts,
								isEnabled = isEnabled,
								insideButton = true,
							})
						end

						-- Border Thickness slider
						do
							local function getThk()
								local t = ensureCastBarDB() or {}
								return tonumber(t.castBarBorderThickness) or 1
							end
							local function setThk(v)
								local t = ensureCastBarDB(); if not t then return end
								local nv = tonumber(v) or 1
								if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
								t.castBarBorderThickness = nv
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(1, 16, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
							local setting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = setting, options = opts })
							local sf = CreateFrame("Frame", nil, borderPage, "SettingsSliderControlTemplate")
							sf.GetElementData = function() return initSlider end
							sf:SetPoint("TOPLEFT", 4, y.y)
							sf:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(sf)
							if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
							_thickFrame = sf
							y.y = y.y - 34
						end
						
						-- Border Inset slider (fine adjustment: negative = push outward, positive = pull inward)
						do
							local function getInset()
								local t = ensureCastBarDB() or {}
								return tonumber(t.castBarBorderInset) or 1
							end
							local function setInset(v)
								local t = ensureCastBarDB(); if not t then return end
								local nv = tonumber(v) or 0
								if nv < -4 then nv = -4 elseif nv > 4 then nv = 4 end
								t.castBarBorderInset = nv
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(-4, 4, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
							local setting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = setting, options = opts })
							local sf = CreateFrame("Frame", nil, borderPage, "SettingsSliderControlTemplate")
							sf.GetElementData = function() return initSlider end
							sf:SetPoint("TOPLEFT", 4, y.y)
							sf:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(sf)
							if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
							_insetFrame = sf
							y.y = y.y - 34
						end

						-- Initialize gray-out state once when building
						refreshBorderEnabledState()
					end

					-- Shared Icon tab (all unit frames with a Cast Bar)
					local function buildIconTab()
						local uk = unitKey()
						if not uk then return end

					local function applyNow()
						if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor(uk) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end

					local function ensureCastBarDB()
						local db = addon and addon.db and addon.db.profile
						if not db then return nil end
						db.unitFrames = db.unitFrames or {}
						db.unitFrames[uk] = db.unitFrames[uk] or {}
						db.unitFrames[uk].castBar = db.unitFrames[uk].castBar or {}
						return db.unitFrames[uk].castBar
					end

					local iconPage = frame.PageE
					local y = { y = -50 }

					-- Local references so we can gray-out rows without rebuilding the category
					local _iconHeightFrame, _iconWidthFrame, _iconPadFrame
					local _iconBorderEnableFrame, _iconBorderStyleFrame, _iconBorderThickFrame, _iconBorderTintFrame

					local function refreshIconEnabledState()
						local t = ensureCastBarDB() or {}
						local enabled = not not (not t.iconDisabled)

						local function setFrameEnabled(row, enabledFlag)
							if not row then return end
							if row.Control and row.Control.SetEnabled then
								row.Control:SetEnabled(enabledFlag)
							end
							local lbl = row.Text or row.Label
							if lbl and lbl.SetTextColor then
								if enabledFlag then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
							end
						end

						setFrameEnabled(_iconHeightFrame, enabled)
						setFrameEnabled(_iconWidthFrame, enabled)
						setFrameEnabled(_iconPadFrame, enabled)
						setFrameEnabled(_iconBorderEnableFrame, enabled)
						setFrameEnabled(_iconBorderStyleFrame, enabled)
						setFrameEnabled(_iconBorderThickFrame, enabled)
						setFrameEnabled(_iconBorderTintFrame, enabled)

						-- Also dim the tint swatch itself
						if _iconBorderTintFrame and _iconBorderTintFrame.ScooterInlineSwatch then
							local sw = _iconBorderTintFrame.ScooterInlineSwatch
							if sw.EnableMouse then sw:EnableMouse(enabled) end
							if sw.SetAlpha then sw:SetAlpha(enabled and 1 or 0.5) end
						end
					end

					-- Disable Icon checkbox (DB-backed; affects icon + border visibility)
					do
						local label = "Disable Icon"
						local function getter()
							local t = ensureCastBarDB() or {}
							return not not t.iconDisabled
						end
						local function setter(v)
							local t = ensureCastBarDB(); if not t then return end
							t.iconDisabled = (v == true)
							applyNow()
							refreshIconEnabledState()
						end
						local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, iconPage, "SettingsCheckboxControlTemplate")
						row.GetElementData = function() return initCb end
						row:SetPoint("TOPLEFT", 4, y.y)
						row:SetPoint("TOPRIGHT", -16, y.y)
						initCb:InitFrame(row)
						if panel and panel.ApplyRobotoWhite then
							if row.Text then panel.ApplyRobotoWhite(row.Text) end
							local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
						end
						-- Player-only: add info icon explaining why the icon is unavailable when unlocked
						if componentId == "ufPlayer" and panel and panel.CreateInfoIconForLabel and row.Text then
							if not row.ScooterInfoIcon then
								local tip = "The Player Cast Bar only has an icon when Positioning > \"Lock to Player Frame\" is enabled."
								local label = row.Text
								row.ScooterInfoIcon = panel.CreateInfoIconForLabel(label, tip, 5, 0, 24)
								-- Defer precise placement so we can anchor just after the label text, not over the checkbox
								if _G.C_Timer and _G.C_Timer.After then
									_G.C_Timer.After(0, function()
										local icon = row.ScooterInfoIcon
										if not (icon and label) then return end
										icon:ClearAllPoints()
										local textWidth = label.GetStringWidth and label:GetStringWidth() or 0
										if textWidth and textWidth > 0 then
											icon:SetPoint("LEFT", label, "LEFT", textWidth + 5, 0)
										else
											icon:SetPoint("LEFT", label, "RIGHT", 5, 0)
										end
									end)
								end
							end
						end
						y.y = y.y - 34
					end

						-- Icon Height (vertical size of the cast bar icon)
						do
							local function getH()
								local t = ensureCastBarDB() or {}
								return tonumber(t.iconHeight) or 16
							end
							local function setH(v)
								local t = ensureCastBarDB(); if not t then return end
								local val = tonumber(v) or 16
								if val < 8 then val = 8 elseif val > 64 then val = 64 end
								t.iconHeight = val
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(8, 64, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
								return tostring(math.floor((tonumber(v) or 0) + 0.5))
							end)
							local setting = CreateLocalSetting("Icon Height", "number", getH, setH, getH())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Icon Height", setting = setting, options = opts })
							local f = CreateFrame("Frame", nil, iconPage, "SettingsSliderControlTemplate")
							f.GetElementData = function() return initSlider end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(f)
							if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
							_iconHeightFrame = f
							y.y = y.y - 34
						end

						-- Icon Width (horizontal size of the cast bar icon)
						do
							local function getW()
								local t = ensureCastBarDB() or {}
								return tonumber(t.iconWidth) or 16
							end
							local function setW(v)
								local t = ensureCastBarDB(); if not t then return end
								local val = tonumber(v) or 16
								if val < 8 then val = 8 elseif val > 64 then val = 64 end
								t.iconWidth = val
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(8, 64, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
								return tostring(math.floor((tonumber(v) or 0) + 0.5))
							end)
							local setting = CreateLocalSetting("Icon Width", "number", getW, setW, getW())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Icon Width", setting = setting, options = opts })
							local f = CreateFrame("Frame", nil, iconPage, "SettingsSliderControlTemplate")
							f.GetElementData = function() return initSlider end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(f)
							if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
							_iconWidthFrame = f
							y.y = y.y - 34
						end

						-- Icon/Bar Padding (distance between icon and bar)
						do
							local function getPad()
								local t = ensureCastBarDB() or {}
								return tonumber(t.iconBarPadding) or 0
							end
							local function setPad(v)
								local t = ensureCastBarDB(); if not t then return end
								local val = tonumber(v) or 0
								if val < -20 then val = -20 elseif val > 80 then val = 80 end
								t.iconBarPadding = val
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(-20, 80, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
								return tostring(math.floor((tonumber(v) or 0) + 0.5))
							end)
							local setting = CreateLocalSetting("Icon/Bar Padding", "number", getPad, setPad, getPad())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Icon/Bar Padding", setting = setting, options = opts })
							local f = CreateFrame("Frame", nil, iconPage, "SettingsSliderControlTemplate")
							f.GetElementData = function() return initSlider end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(f)
							if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
							_iconPadFrame = f
							y.y = y.y - 34
						end

						-- Use Custom Icon Border checkbox
						do
							local label = "Use Custom Icon Border"
							local function getter()
								local t = ensureCastBarDB() or {}
								return not not t.iconBorderEnable
							end
							local function setter(v)
								local t = ensureCastBarDB(); if not t then return end
								t.iconBorderEnable = (v == true)
								applyNow()
							end
							local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
							local row = CreateFrame("Frame", nil, iconPage, "SettingsCheckboxControlTemplate")
							row.GetElementData = function() return initCb end
							row:SetPoint("TOPLEFT", 4, y.y)
							row:SetPoint("TOPRIGHT", -16, y.y)
							initCb:InitFrame(row)
							if panel and panel.ApplyRobotoWhite then
								if row.Text then panel.ApplyRobotoWhite(row.Text) end
								local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
								if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
							end
							_iconBorderEnableFrame = row
							y.y = y.y - 34
						end

						-- Icon Border Style dropdown (all icon border library entries)
						do
							local function optionsIconBorder()
								if addon.BuildIconBorderOptionsContainer then
									return addon.BuildIconBorderOptionsContainer()
								end
								local c = Settings.CreateControlTextContainer()
								c:Add("square", "Default")
								return c:GetData()
							end
							local function getStyle()
								local t = ensureCastBarDB() or {}
								return t.iconBorderStyle or "square"
							end
							local function setStyle(v)
								local t = ensureCastBarDB(); if not t then return end
								t.iconBorderStyle = v or "square"
								applyNow()
							end
							local setting = CreateLocalSetting("Icon Border", "string", getStyle, setStyle, getStyle())
							local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Icon Border", setting = setting, options = optionsIconBorder })
							local f = CreateFrame("Frame", nil, iconPage, "SettingsDropdownControlTemplate")
							f.GetElementData = function() return initDrop end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initDrop:InitFrame(f)
							local lbl = f and (f.Text or f.Label)
							if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
							_iconBorderStyleFrame = f
							y.y = y.y - 34
						end

						-- Icon Border Thickness slider
						do
							local function getThk()
								local t = ensureCastBarDB() or {}
								return tonumber(t.iconBorderThickness) or 1
							end
							local function setThk(v)
								local t = ensureCastBarDB(); if not t then return end
								local nv = tonumber(v) or 1
								if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
								t.iconBorderThickness = nv
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(1, 16, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end)
							local setting = CreateLocalSetting("Icon Border Thickness", "number", getThk, setThk, getThk())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Icon Border Thickness", setting = setting, options = opts })
							local f = CreateFrame("Frame", nil, iconPage, "SettingsSliderControlTemplate")
							f.GetElementData = function() return initSlider end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(f)
							if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
							_iconBorderThickFrame = f
							y.y = y.y - 34
						end

						-- Icon Border Tint (checkbox + inline color swatch)
						do
							local label = "Icon Border Tint"
							local function getTintEnabled()
								local t = ensureCastBarDB() or {}
								return not not t.iconBorderTintEnable
							end
							local function setTintEnabled(v)
								local t = ensureCastBarDB(); if not t then return end
								t.iconBorderTintEnable = (v == true)
								applyNow()
							end
							local function getTintColor()
								local t = ensureCastBarDB() or {}
								local c = t.iconBorderTintColor or {1,1,1,1}
								return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
							end
							local function setTintColor(r, g, b, a)
								local t = ensureCastBarDB(); if not t then return end
								t.iconBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
								applyNow()
							end

							local setting = CreateLocalSetting(label, "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
							local initCb = CreateCheckboxWithSwatchInitializer(setting, label, getTintColor, setTintColor, 8)
							local row = CreateFrame("Frame", nil, iconPage, "SettingsCheckboxControlTemplate")
							row.GetElementData = function() return initCb end
							row:SetPoint("TOPLEFT", 4, y.y)
							row:SetPoint("TOPRIGHT", -16, y.y)
							initCb:InitFrame(row)
							if panel and panel.ApplyRobotoWhite then
								if row.Text then panel.ApplyRobotoWhite(row.Text) end
								local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
								if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
							end
							_iconBorderTintFrame = row
						end

						-- Initialize gray-out state once when building
						refreshIconEnabledState()
					end

					-- PLAYER CAST BAR (Edit Mode–managed)
					if componentId == "ufPlayer" then
						-- Utilities reused from Parent Frame positioning
						local function getUiScale() return (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1 end
						local function uiUnitsToPixels(u) local s = getUiScale(); return math.floor((u * s) + 0.5) end
						local function pixelsToUiUnits(px) local s = getUiScale(); if s == 0 then return 0 end; return px / s end

						local function getCastBar()
							local mgr = _G.EditModeManagerFrame
							local EMSys = _G.Enum and _G.Enum.EditModeSystem
							if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
							return mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
						end

						-- Positioning tab content (PageA)
						local yA = { y = -50 }

						-- Local refs so we can gray-out the offset sliders based on the lock state
						local _offsetXFrame, _offsetYFrame

						local lockSetting -- forward-declared so isLocked/refresh can see it
						local function isLocked()
							return (lockSetting and lockSetting.GetValue and lockSetting:GetValue()) and true or false
						end

						local function refreshOffsetEnabledState()
							local enabled = isLocked()
							local function applyToRow(row)
								if not row then return end
								if row.Control and row.Control.SetEnabled then
									row.Control:SetEnabled(enabled)
								end
								local lbl = row.Text or row.Label
								if lbl and lbl.SetTextColor then
									lbl:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1)
								end
							end
							applyToRow(_offsetXFrame)
							applyToRow(_offsetYFrame)
						end

						local function addCheckboxLock()
							local label = "Lock to Player Frame"
							local function getter()
								local frame = getCastBar()
								local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.LockToPlayerFrame
								if frame and sid and addon and addon.EditMode and addon.EditMode.GetSetting then
									local v = addon.EditMode.GetSetting(frame, sid)
									return (v and v ~= 0) and true or false
								end
								return false
							end
							local function setter(b)
								local val = (b and true) and 1 or 0
								-- Fix note (2025-11-06): Keep Cast Bar <-> Unit Frame in lockstep by writing to
								-- Cast Bar [LockToPlayerFrame] and mirroring to Player Unit Frame [CastBarUnderneath],
								-- then nudge UpdateSystem/RefreshLayout, SaveOnly(), and coalesced RequestApplyChanges().
								-- This prevents stale visuals and keeps Edit Mode UI in sync instantly.
								-- Write to Cast Bar system
								do
									local frame = getCastBar()
									local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.LockToPlayerFrame
									if frame and sid and addon and addon.EditMode and addon.EditMode.SetSetting then
										addon.EditMode.SetSetting(frame, sid, val)
										if type(frame.UpdateSystemSettingLockToPlayerFrame) == "function" then pcall(frame.UpdateSystemSettingLockToPlayerFrame, frame) end
										if type(frame.UpdateSystem) == "function" then pcall(frame.UpdateSystem, frame) end
										if type(frame.RefreshLayout) == "function" then pcall(frame.RefreshLayout, frame) end
									end
								end
								-- Mirror to Player Unit Frame setting [Cast Bar Underneath] to keep both UIs in sync
								do
									local mgr = _G.EditModeManagerFrame
									local EMSys = _G.Enum and _G.Enum.EditModeSystem
									local EMUF = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
									local frameUF = (mgr and EMSys and EMUF and mgr.GetRegisteredSystemFrame) and mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EMUF.Player) or nil
									local UFSetting = _G.Enum and _G.Enum.EditModeUnitFrameSetting
									local sidUF = UFSetting and UFSetting.CastBarUnderneath or 1
									if frameUF and sidUF and addon and addon.EditMode and addon.EditMode.SetSetting then
										addon.EditMode.SetSetting(frameUF, sidUF, val)
										if type(frameUF.UpdateSystem) == "function" then pcall(frameUF.UpdateSystem, frameUF) end
										if type(frameUF.RefreshLayout) == "function" then pcall(frameUF.RefreshLayout, frameUF) end
									end
								end
								if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end

								-- When unlocking the Player Cast Bar (val == 0), enforce Disable Icon in
								-- ScooterMod's DB so our icon border logic does not draw when Blizzard
								-- hides the icon in free-floating mode.
								do
									local db = addon and addon.db and addon.db.profile
									if db then
										db.unitFrames = db.unitFrames or {}
										db.unitFrames.Player = db.unitFrames.Player or {}
										db.unitFrames.Player.castBar = db.unitFrames.Player.castBar or {}
										if val == 0 then
											db.unitFrames.Player.castBar.iconDisabled = true
										end
									end
								end

								-- Re-style immediately so icon visibility/borders and offsets match the new lock state.
								-- Limit this to the Player cast bar only to avoid triggering broader panel refresh
								-- machinery that can cause visible flicker in the settings list.
								if addon and addon.ApplyUnitFrameCastBarFor then
									addon.ApplyUnitFrameCastBarFor("Player")
								end

								-- Update offset slider enabled state to reflect the new lock mode without
								-- forcing a full category rebuild (which can cause visible flicker).
								if refreshOffsetEnabledState then
									refreshOffsetEnabledState()
								end
							end
							local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
							local row = CreateFrame("Frame", nil, frame.PageA, "SettingsCheckboxControlTemplate")
							row.GetElementData = function() return initCb end
							row:SetPoint("TOPLEFT", 4, yA.y)
							row:SetPoint("TOPRIGHT", -16, yA.y)
							initCb:InitFrame(row)
							if panel and panel.ApplyRobotoWhite then
								if row.Text then panel.ApplyRobotoWhite(row.Text) end
								local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
								if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
							end
							yA.y = yA.y - 34
							return setting
						end

						lockSetting = addCheckboxLock()

						-- X/Y Offset sliders (only applied when locked; greyed out when unlocked)
						do
							local function applyNow()
								if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor("Player") end
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end

							_offsetXFrame = addSlider(
								frame.PageA,
								"X Offset",
								-150,
								150,
								1,
								function()
									local t = ensureCastBarDB() or {}
									return tonumber(t.offsetX) or 0
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.offsetX = tonumber(v) or 0
									applyNow()
								end,
								yA
							)

							_offsetYFrame = addSlider(
								frame.PageA,
								"Y Offset",
								-150,
								150,
								1,
								function()
									local t = ensureCastBarDB() or {}
									return tonumber(t.offsetY) or 0
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.offsetY = tonumber(v) or 0
									applyNow()
								end,
								yA
							)

							-- Initialize grey-out state once when building
							if refreshOffsetEnabledState then
								refreshOffsetEnabledState()
							end
						end

					-- Sizing tab (PageB): Bar Size (Scale) 100..150 step 10
					do
						local y = { y = -50 }
						local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
						local options = Settings.CreateSliderOptions(100, 150, 10)
						options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
						local label = "Bar Size (Scale)"
						local function getCastBar()
							local mgr = _G.EditModeManagerFrame
							local EMSys = _G.Enum and _G.Enum.EditModeSystem
							if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
							return mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
						end
						local function getter()
							local frame = getCastBar()
							local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.BarSize
							if frame and sid and addon and addon.EditMode and addon.EditMode.GetSetting then
								local v = addon.EditMode.GetSetting(frame, sid)
								if v == nil then return 100 end
								return math.max(100, math.min(150, v))
							end
							return 100
						end
						local function setter(raw)
							local frame = getCastBar()
							local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.BarSize
							local val = tonumber(raw) or 100
							val = math.floor(math.max(100, math.min(150, val)) / 10 + 0.5) * 10
							if frame and sid and addon and addon.EditMode and addon.EditMode.SetSetting then
								addon.EditMode.SetSetting(frame, sid, val)
								if type(frame.UpdateSystemSettingBarSize) == "function" then pcall(frame.UpdateSystemSettingBarSize, frame) end
								if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
								if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
							end
						end
						local setting = CreateLocalSetting(label, "number", getter, setter, getter())
						local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
						local f = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
						f.GetElementData = function() return initSlider end
						f:SetPoint("TOPLEFT", 4, y.y)
						f:SetPoint("TOPRIGHT", -16, y.y)
						initSlider:InitFrame(f)
						if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
						y.y = y.y - 34
					end

					-- Bar Width slider (Player only for now, percent of original width)
					do
						local y = { y = -90 } -- place just below Bar Size (Scale)
						local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
						local options = Settings.CreateSliderOptions(50, 150, 1)
						options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)

						local label = "Bar Width (%)"
						local function getter()
							local db = addon and addon.db and addon.db.profile
							if not db then return 100 end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Player = db.unitFrames.Player or {}
							db.unitFrames.Player.castBar = db.unitFrames.Player.castBar or {}
							local t = db.unitFrames.Player.castBar
							return tonumber(t.widthPct) or 100
						end
						local function setter(v)
							local db = addon and addon.db and addon.db.profile
							if not db then return end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Player = db.unitFrames.Player or {}
							db.unitFrames.Player.castBar = db.unitFrames.Player.castBar or {}
							local t = db.unitFrames.Player.castBar
							local val = tonumber(v) or 100
							if val < 50 then val = 50 elseif val > 150 then val = 150 end
							t.widthPct = val
							if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor("Player") end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end

						local setting = CreateLocalSetting(label, "number", getter, setter, getter())
						local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
						local f = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
						f.GetElementData = function() return initSlider end
						f:SetPoint("TOPLEFT", 4, y.y)
						f:SetPoint("TOPRIGHT", -16, y.y)
						initSlider:InitFrame(f)
						if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
					end

					-- Spell Name Text tab (PageF): Disable Spell Name Text + styling (Player only)
					do
						-- Only meaningful for the Player cast bar; leave PageF empty for Target/Focus
						if unitKey() == "Player" then
							local function applyNow()
								if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor("Player") end
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							local function fontOptions()
								return addon.BuildFontOptionsContainer()
							end
							local y = { y = -50 }

							local function isDisabled()
								local t = ensureCastBarDB() or {}
								return not not t.spellNameTextDisabled
							end

							-- Local references so we can gray-out rows without rebuilding the category
							local _snFontFrame, _snStyleFrame, _snSizeFrame, _snColorFrame, _snOffsetXFrame, _snOffsetYFrame

							local function refreshSpellNameDisabledState()
								local disabled = isDisabled()

								-- Font
								if _snFontFrame then
									if _snFontFrame.Control and _snFontFrame.Control.SetEnabled then
										_snFontFrame.Control:SetEnabled(not disabled)
									end
									local lbl = _snFontFrame.Text or _snFontFrame.Label
									if lbl and lbl.SetTextColor then
										lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
									end
								end

								-- Font Style
								if _snStyleFrame then
									if _snStyleFrame.Control and _snStyleFrame.Control.SetEnabled then
										_snStyleFrame.Control:SetEnabled(not disabled)
									end
									local lbl = _snStyleFrame.Text or _snStyleFrame.Label
									if lbl and lbl.SetTextColor then
										lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
									end
								end

								-- Font Size
								if _snSizeFrame then
									if _snSizeFrame.Control and _snSizeFrame.Control.SetEnabled then
										_snSizeFrame.Control:SetEnabled(not disabled)
									end
									if _snSizeFrame.Text and _snSizeFrame.Text.SetTextColor then
										_snSizeFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
									end
								end

								-- Font Color (dropdown + inline swatch)
								if _snColorFrame then
									if _snColorFrame.Control and _snColorFrame.Control.SetEnabled then
										_snColorFrame.Control:SetEnabled(not disabled)
									end
									local lbl = _snColorFrame.Text or _snColorFrame.Label
									if lbl and lbl.SetTextColor then
										lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
									end
									if _snColorFrame.ScooterInlineSwatch and _snColorFrame.ScooterInlineSwatch.EnableMouse then
										_snColorFrame.ScooterInlineSwatch:EnableMouse(not disabled)
										if _snColorFrame.ScooterInlineSwatch.SetAlpha then
											_snColorFrame.ScooterInlineSwatch:SetAlpha(disabled and 0.5 or 1)
										end
									end
								end

								-- X Offset
								if _snOffsetXFrame then
									if _snOffsetXFrame.Control and _snOffsetXFrame.Control.SetEnabled then
										_snOffsetXFrame.Control:SetEnabled(not disabled)
									end
									if _snOffsetXFrame.Text and _snOffsetXFrame.Text.SetTextColor then
										_snOffsetXFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
									end
								end

								-- Y Offset
								if _snOffsetYFrame then
									if _snOffsetYFrame.Control and _snOffsetYFrame.Control.SetEnabled then
										_snOffsetYFrame.Control:SetEnabled(not disabled)
									end
									if _snOffsetYFrame.Text and _snOffsetYFrame.Text.SetTextColor then
										_snOffsetYFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
									end
								end
							end

							-- Disable Spell Name Text checkbox
							do
								local label = "Disable Spell Name Text"
								local function getter()
									local t = ensureCastBarDB() or {}
									return not not t.spellNameTextDisabled
								end
								local function setter(v)
									local t = ensureCastBarDB(); if not t then return end
									t.spellNameTextDisabled = (v == true)
									applyNow()
									refreshSpellNameDisabledState()
								end
								local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
								local row = CreateFrame("Frame", nil, frame.PageF, "SettingsCheckboxControlTemplate")
								row.GetElementData = function() return initCb end
								row:SetPoint("TOPLEFT", 4, y.y)
								row:SetPoint("TOPRIGHT", -16, y.y)
								initCb:InitFrame(row)
								if panel and panel.ApplyRobotoWhite then
									if row.Text then panel.ApplyRobotoWhite(row.Text) end
									local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
									if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
								end
								y.y = y.y - 34
							end

							-- Spell Name Font
							_snFontFrame = addDropdown(frame.PageF, "Spell Name Font", fontOptions,
								function()
									local t = ensureCastBarDB() or {}
									local s = t.spellNameText or {}
									return s.fontFace or "FRIZQT__"
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.spellNameText = t.spellNameText or {}
									t.spellNameText.fontFace = v
									applyNow()
								end,
								y)

							-- Spell Name Font Style
							_snStyleFrame = addStyle(frame.PageF, "Spell Name Font Style",
								function()
									local t = ensureCastBarDB() or {}
									local s = t.spellNameText or {}
									return s.style or "OUTLINE"
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.spellNameText = t.spellNameText or {}
									t.spellNameText.style = v
									applyNow()
								end,
								y)

							-- Spell Name Font Size
							_snSizeFrame = addSlider(frame.PageF, "Spell Name Font Size", 6, 48, 1,
								function()
									local t = ensureCastBarDB() or {}
									local s = t.spellNameText or {}
									return tonumber(s.size) or 14
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.spellNameText = t.spellNameText or {}
									t.spellNameText.size = tonumber(v) or 14
									applyNow()
								end,
								y)

							-- Spell Name Font Color
							_snColorFrame = addColor(frame.PageF, "Spell Name Font Color", true,
								function()
									local t = ensureCastBarDB() or {}
									local s = t.spellNameText or {}
									local c = s.color or {1,1,1,1}
									return c[1], c[2], c[3], c[4]
								end,
								function(r,g,b,a)
									local t = ensureCastBarDB(); if not t then return end
									t.spellNameText = t.spellNameText or {}
									t.spellNameText.color = {r or 1, g or 1, b or 1, a or 1}
									applyNow()
								end,
								y)

							-- Spell Name X Offset
							_snOffsetXFrame = addSlider(frame.PageF, "Spell Name X Offset", -100, 100, 1,
								function()
									local t = ensureCastBarDB() or {}
									local s = t.spellNameText or {}
									local o = s.offset or {}
									return tonumber(o.x) or 0
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.spellNameText = t.spellNameText or {}
									t.spellNameText.offset = t.spellNameText.offset or {}
									t.spellNameText.offset.x = tonumber(v) or 0
									applyNow()
								end,
								y)

							-- Spell Name Y Offset
							_snOffsetYFrame = addSlider(frame.PageF, "Spell Name Y Offset", -100, 100, 1,
								function()
									local t = ensureCastBarDB() or {}
									local s = t.spellNameText or {}
									local o = s.offset or {}
									return tonumber(o.y) or 0
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.spellNameText = t.spellNameText or {}
									t.spellNameText.offset = t.spellNameText.offset or {}
									t.spellNameText.offset.y = tonumber(v) or 0
									applyNow()
								end,
								y)

							-- Initialize gray-out state
							refreshSpellNameDisabledState()
						end
					end

					-- Cast Time Text tab (PageG): Show Cast Time checkbox + styling (Player only)
					do
						local y = { y = -50 }
						local function applyNow()
							if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor("Player") end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local label = "Show Cast Time"
						local function getCastBar()
							local mgr = _G.EditModeManagerFrame
							local EMSys = _G.Enum and _G.Enum.EditModeSystem
							if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
							return mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
						end
						local function getter()
							local frameCB = getCastBar()
							local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.ShowCastTime
							if frameCB and sid and addon and addon.EditMode and addon.EditMode.GetSetting then
								local v = addon.EditMode.GetSetting(frameCB, sid)
								return (tonumber(v) or 0) == 1
							end
							return false
						end
						local function setter(b)
							local frameCB = getCastBar()
							local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.ShowCastTime
							local val = (b and true) and 1 or 0
							if frameCB and sid and addon and addon.EditMode and addon.EditMode.SetSetting then
								addon.EditMode.SetSetting(frameCB, sid, val)
								if type(frameCB.UpdateSystemSettingShowCastTime) == "function" then pcall(frameCB.UpdateSystemSettingShowCastTime, frameCB) end
								if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
								if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
								-- Reapply Scooter styling so Cast Time text reflects current settings immediately
								applyNow()
							end
						end
						local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, frame.PageG, "SettingsCheckboxControlTemplate")
						row.GetElementData = function() return initCb end
						row:SetPoint("TOPLEFT", 4, y.y)
						row:SetPoint("TOPRIGHT", -16, y.y)
						initCb:InitFrame(row)
						if panel and panel.ApplyRobotoWhite then
							if row.Text then panel.ApplyRobotoWhite(row.Text) end
							local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
						end
						y.y = y.y - 34

						-- Cast Time Font
						local function fontOptions()
							return addon.BuildFontOptionsContainer()
						end
						addDropdown(frame.PageG, "Cast Time Font", fontOptions,
							function()
								local t = ensureCastBarDB() or {}
								local s = t.castTimeText or {}
								return s.fontFace or "FRIZQT__"
							end,
							function(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castTimeText = t.castTimeText or {}
								t.castTimeText.fontFace = v
								applyNow()
							end,
							y)

						-- Cast Time Font Style
						addStyle(frame.PageG, "Cast Time Font Style",
							function()
								local t = ensureCastBarDB() or {}
								local s = t.castTimeText or {}
								return s.style or "OUTLINE"
							end,
							function(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castTimeText = t.castTimeText or {}
								t.castTimeText.style = v
								applyNow()
							end,
							y)

						-- Cast Time Font Size
						addSlider(frame.PageG, "Cast Time Font Size", 6, 48, 1,
							function()
								local t = ensureCastBarDB() or {}
								local s = t.castTimeText or {}
								return tonumber(s.size) or 14
							end,
							function(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castTimeText = t.castTimeText or {}
								t.castTimeText.size = tonumber(v) or 14
								applyNow()
							end,
							y)

						-- Cast Time Font Color
						addColor(frame.PageG, "Cast Time Font Color", true,
							function()
								local t = ensureCastBarDB() or {}
								local s = t.castTimeText or {}
								local c = s.color or {1,1,1,1}
								return c[1], c[2], c[3], c[4]
							end,
							function(r,g,b,a)
								local t = ensureCastBarDB(); if not t then return end
								t.castTimeText = t.castTimeText or {}
								t.castTimeText.color = {r or 1, g or 1, b or 1, a or 1}
								applyNow()
							end,
							y)

						-- Cast Time X Offset
						addSlider(frame.PageG, "Cast Time X Offset", -100, 100, 1,
							function()
								local t = ensureCastBarDB() or {}
								local s = t.castTimeText or {}
								local o = s.offset or {}
								return tonumber(o.x) or 0
							end,
							function(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castTimeText = t.castTimeText or {}
								t.castTimeText.offset = t.castTimeText.offset or {}
								t.castTimeText.offset.x = tonumber(v) or 0
								applyNow()
							end,
							y)

						-- Cast Time Y Offset
						addSlider(frame.PageG, "Cast Time Y Offset", -100, 100, 1,
							function()
								local t = ensureCastBarDB() or {}
								local s = t.castTimeText or {}
								local o = s.offset or {}
								return tonumber(o.y) or 0
							end,
							function(v)
								local t = ensureCastBarDB(); if not t then return end
								t.castTimeText = t.castTimeText or {}
								t.castTimeText.offset = t.castTimeText.offset or {}
								t.castTimeText.offset.y = tonumber(v) or 0
								applyNow()
							end,
							y)
					end
					-- Placeholder tab (Visibility) is wired by title only for now.

					-- TARGET/FOCUS CAST BAR (addon-only X/Y offsets + width)
					else
						local uk = unitKey()
						if uk == "Target" or uk == "Focus" then
							local function applyNow()
								if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor(uk) end
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							-- PageA: Positioning (X/Y offsets)
							do
								local y = { y = -50 }
								-- X Offset slider (-150..150 px)
								addSlider(frame.PageA, "X Offset", -150, 150, 1,
									function()
										local t = ensureCastBarDB() or {}
										return tonumber(t.offsetX) or 0
									end,
									function(v)
										local t = ensureCastBarDB(); if not t then return end
										t.offsetX = tonumber(v) or 0
										applyNow()
									end,
									y)

								-- Y Offset slider (-150..150 px)
								addSlider(frame.PageA, "Y Offset", -150, 150, 1,
									function()
										local t = ensureCastBarDB() or {}
										return tonumber(t.offsetY) or 0
									end,
									function(v)
										local t = ensureCastBarDB(); if not t then return end
										t.offsetY = tonumber(v) or 0
										applyNow()
									end,
									y)
							end

							-- PageB: Sizing (Bar Width %)
							do
								local y = { y = -50 }
								local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
								local options = Settings.CreateSliderOptions(50, 150, 1)
								options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)

								local label = "Bar Width (%)"
								local function getter()
									local t = ensureCastBarDB() or {}
									return tonumber(t.widthPct) or 100
								end
								local function setter(v)
									local t = ensureCastBarDB(); if not t then return end
									local val = tonumber(v) or 100
									if val < 50 then val = 50 elseif val > 150 then val = 150 end
									t.widthPct = val
									applyNow()
								end

								local setting = CreateLocalSetting(label, "number", getter, setter, getter())
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
								local f = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
								f.GetElementData = function() return initSlider end
								f:SetPoint("TOPLEFT", 4, y.y)
								f:SetPoint("TOPRIGHT", -16, y.y)
								initSlider:InitFrame(f)
								if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
							end
						end
					end

					-- Build Style, Border, and Icon tabs for any unit with a Cast Bar (Player/Target/Focus)
					buildStyleTab()
					buildBorderTab()
					buildIconTab()
				end

				local tabCBC = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", cbData)
				-- STATIC HEIGHT: Cast Bar tabs now have multiple controls (Style, Icon, text, etc.).
				-- Bump slightly above 330px to accommodate one additional row (Disable Icon) while
				-- keeping spacing consistent with other Unit Frame tabbed sections.
				tabCBC.GetExtent = function() return 364 end
				tabCBC:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Cast Bar") end)
				table.insert(init, tabCBC)
			end

			-- Fifth collapsible section: Buffs & Debuffs (Target only)
			if componentId == "ufTarget" then
				local expInitializerBD = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
					name = "Buffs & Debuffs",
					sectionKey = "Buffs & Debuffs",
					componentId = componentId,
					expanded = panel:IsSectionExpanded(componentId, "Buffs & Debuffs"),
				})
				expInitializerBD.GetExtent = function() return 30 end
				table.insert(init, expInitializerBD)

				-- Tabbed section within Buffs & Debuffs: Positioning (first tab)
				local bdData = { sectionTitle = "", tabAText = "Positioning" }
				bdData.build = function(frame)
					-- Positioning tab (PageA): "Buffs on Top" checkbox wired to Edit Mode
					local y = { y = -50 }
					local function getUnitFrame()
						local mgr = _G.EditModeManagerFrame
						local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
						local EMSys = _G.Enum and _G.Enum.EditModeSystem
						if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
						local idx = EM.Target
						return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
					end
					local label = "Buffs on Top"
					local function getter()
						local frameUF = getUnitFrame()
						local sid = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.BuffsOnTop
						if frameUF and sid and addon and addon.EditMode and addon.EditMode.GetSetting then
							local v = addon.EditMode.GetSetting(frameUF, sid)
							return (tonumber(v) or 0) == 1
						end
						return false
					end
					local function setter(b)
						local frameUF = getUnitFrame()
						local sid = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.BuffsOnTop
						local val = (b and true) and 1 or 0
						if frameUF and sid and addon and addon.EditMode and addon.EditMode.SetSetting then
							addon.EditMode.SetSetting(frameUF, sid, val)
							-- Nudge visuals; call specific updater if present, else coalesced apply
							if type(frameUF.UpdateSystemSettingBuffsOnTop) == "function" then pcall(frameUF.UpdateSystemSettingBuffsOnTop, frameUF) end
							if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
							if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
						end
					end
					local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, frame.PageA, "SettingsCheckboxControlTemplate")
					row.GetElementData = function() return initCb end
					row:SetPoint("TOPLEFT", 4, y.y)
					row:SetPoint("TOPRIGHT", -16, y.y)
					initCb:InitFrame(row)
					if panel and panel.ApplyRobotoWhite then
						if row.Text then panel.ApplyRobotoWhite(row.Text) end
						local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					y.y = y.y - 34
				end

				local tabBD = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", bdData)
				tabBD.GetExtent = function() return 120 end
				tabBD:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Buffs & Debuffs") end)
				table.insert(init, tabBD)
			end

			-- Sixth collapsible section: Buffs & Debuffs (Focus only)
			if componentId == "ufFocus" then
				local expInitializerBDF = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
					name = "Buffs & Debuffs",
					sectionKey = "Buffs & Debuffs",
					componentId = componentId,
					expanded = panel:IsSectionExpanded(componentId, "Buffs & Debuffs"),
				})
				expInitializerBDF.GetExtent = function() return 30 end
				table.insert(init, expInitializerBDF)

				local bdDataF = { sectionTitle = "", tabAText = "Positioning" }
				bdDataF.build = function(frame)
					local y = { y = -50 }
					local function getUnitFrame()
						local mgr = _G.EditModeManagerFrame
						local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
						local EMSys = _G.Enum and _G.Enum.EditModeSystem
						if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
						local idx = EM.Focus
						return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
					end
					local function isUseLargerEnabled()
						local fUF = getUnitFrame()
						local sidULF = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.UseLargerFrame
						if fUF and sidULF and addon and addon.EditMode and addon.EditMode.GetSetting then
							local v = addon.EditMode.GetSetting(fUF, sidULF)
							return (v and v ~= 0) and true or false
						end
						return false
					end
					local label = "Buffs on Top"
					local function getter()
						local frameUF = getUnitFrame()
						local sid = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.BuffsOnTop
						if frameUF and sid and addon and addon.EditMode and addon.EditMode.GetSetting then
							local v = addon.EditMode.GetSetting(frameUF, sid)
							return (tonumber(v) or 0) == 1
						end
						return false
					end
					local function setter(b)
						-- Respect gating: if Use Larger Frame is not enabled, ignore writes
						if not isUseLargerEnabled() then return end
						local frameUF = getUnitFrame()
						local sid = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.BuffsOnTop
						local val = (b and true) and 1 or 0
						if frameUF and sid and addon and addon.EditMode and addon.EditMode.SetSetting then
							addon.EditMode.SetSetting(frameUF, sid, val)
							if type(frameUF.UpdateSystemSettingBuffsOnTop) == "function" then pcall(frameUF.UpdateSystemSettingBuffsOnTop, frameUF) end
							if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
							if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
						end
					end
					local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, frame.PageA, "SettingsCheckboxControlTemplate")
					row.GetElementData = function() return initCb end
					row:SetPoint("TOPLEFT", 4, y.y)
					row:SetPoint("TOPRIGHT", -16, y.y)
					initCb:InitFrame(row)
					if panel and panel.ApplyRobotoWhite then
						if row.Text then panel.ApplyRobotoWhite(row.Text) end
						local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					-- Gray out when Use Larger Frame is unchecked and show disclaimer
					local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
					local disabled = not isUseLargerEnabled()
					if cb then if disabled then cb:Disable() else cb:Enable() end end
					local disclaimer = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
					disclaimer:SetText("Parent Frame > Sizing > 'Use Larger Frame' required")
					disclaimer:SetJustifyH("LEFT")
					if disclaimer.SetWordWrap then disclaimer:SetWordWrap(true) end
					if disclaimer.SetNonSpaceWrap then disclaimer:SetNonSpaceWrap(true) end
					local anchor = (cb and cb.Text) or row.Text or row
					disclaimer:ClearAllPoints()
					disclaimer:SetPoint("LEFT", anchor, "RIGHT", 42, 0)
					disclaimer:SetPoint("RIGHT", row, "RIGHT", -12, 0)
					disclaimer:SetShown(disabled)

					-- Expose a lightweight gating refresher to avoid full category rebuilds
					panel.RefreshFocusBuffsOnTopGating = function()
						local isDisabled = not isUseLargerEnabled()
						if cb then if isDisabled then cb:Disable() else cb:Enable() end end
						if disclaimer then disclaimer:SetShown(isDisabled) end
					end
					if panel.RefreshFocusBuffsOnTopGating then panel.RefreshFocusBuffsOnTopGating() end
					y.y = y.y - 34
				end

				local tabBDF = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", bdDataF)
				tabBDF.GetExtent = function() return 120 end
				tabBDF:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Buffs & Debuffs") end)
				table.insert(init, tabBDF)
			end

            local settingsList = f.SettingsList
            settingsList.Header.Title:SetText(title or componentId)
            settingsList:Display(init)
            settingsList:Show()
            f.Canvas:Hide()
        end
        return { mode = "list", render = render, componentId = componentId }
end

function panel.RenderUFPlayer() return createUFRenderer("ufPlayer", "Player") end
function panel.RenderUFTarget() return createUFRenderer("ufTarget", "Target") end
function panel.RenderUFFocus()  return createUFRenderer("ufFocus",  "Focus")  end
function panel.RenderUFPet()    return createUFRenderer("ufPet",    "Pet")    end

