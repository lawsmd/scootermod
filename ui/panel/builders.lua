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
                        -- Foreground Color dropdown
                        local function fgColorOpts()
                            local container = Settings.CreateControlTextContainer()
                            container:Add("default", "Default")
                            container:Add("texture", "Texture Original")
                            container:Add("custom", "Custom")
                            return container:GetData()
                        end
                        local fgTintRow, fgTintLabel, fgTintSwatch
                        local function getFgColorMode() return db.styleForegroundColorMode or "default" end
                        local function setFgColorMode(v)
                            db.styleForegroundColorMode = v or "default"
                            refresh()
                            local isCustom = (v == "custom")
                            if fgTintLabel then fgTintLabel:SetTextColor(isCustom and 1 or 0.5, isCustom and 1 or 0.5, isCustom and 1 or 0.5) end
                            if fgTintSwatch then fgTintSwatch:SetEnabled(isCustom) end
                        end
                        local fgColorSetting = CreateLocalSetting("Foreground Color", "string", getFgColorMode, setFgColorMode, getFgColorMode())
                        local initFgColor = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Foreground Color", setting = fgColorSetting, options = fgColorOpts })
                        local cfg = CreateFrame("Frame", nil, frame.PageA, "SettingsDropdownControlTemplate")
                        cfg.GetElementData = function() return initFgColor end
                        cfg:SetPoint("TOPLEFT", 4, yA.y)
                        cfg:SetPoint("TOPRIGHT", -16, yA.y)
                        initFgColor:InitFrame(cfg)
                        if panel and panel.ApplyRobotoWhite then
                            local lbl = cfg and (cfg.Text or cfg.Label)
                            if lbl then panel.ApplyRobotoWhite(lbl) end
                        end
                        table.insert(styleControls, cfg)
                        yA.y = yA.y - 34
                        -- Foreground Tint color swatch
                        local function getFgTint()
                            local c = db.styleForegroundTint or {1,1,1,1}; return c[1], c[2], c[3], c[4]
                        end
                        local function setFgTint(r,g,b,a)
                            db.styleForegroundTint = {r,g,b,a}; refresh()
                        end
                        local f2 = CreateFrame("Frame", nil, frame.PageA, "SettingsListElementTemplate")
                        fgTintRow = f2
                        f2:SetHeight(26)
                        f2:SetPoint("TOPLEFT", 4, yA.y)
                        f2:SetPoint("TOPRIGHT", -16, yA.y)
                        f2.Text:SetText("Foreground Tint")
                        if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f2.Text) end
                        fgTintLabel = f2.Text
                        local right = CreateFrame("Frame", nil, f2)
                        right:SetSize(250, 26)
                        right:SetPoint("RIGHT", f2, "RIGHT", -16, 0)
                        f2.Text:ClearAllPoints()
                        f2.Text:SetPoint("LEFT", f2, "LEFT", 36.5, 0)
                        f2.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
                        f2.Text:SetJustifyH("LEFT")
                        local function getFgColorTable()
                            local r, g, b, a = getFgTint()
                            return {r or 1, g or 1, b or 1, a or 1}
                        end
                        local function setFgColorTable(r, g, b, a)
                            setFgTint(r, g, b, a)
                        end
                        local swatch = CreateColorSwatch(right, getFgColorTable, setFgColorTable, true)
                        swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                        fgTintSwatch = swatch
                        local isCustom = (getFgColorMode() == "custom")
                        if fgTintLabel then fgTintLabel:SetTextColor(isCustom and 1 or 0.5, isCustom and 1 or 0.5, isCustom and 1 or 0.5) end
                        if fgTintSwatch then fgTintSwatch:SetEnabled(isCustom) end
                        table.insert(styleControls, fgTintRow)
                        table.insert(styleControls, fgTintSwatch)
                        yA.y = yA.y - 34
                        local bgTexDropdown = addDropdown(frame.PageB, "Background Texture", addon.BuildBarTextureOptionsContainer,
                            function() return db.styleBackgroundTexture or (component.settings.styleBackgroundTexture and component.settings.styleBackgroundTexture.default) end,
                            function(v) db.styleBackgroundTexture = v; refresh() end, yB)
                        table.insert(styleControls, bgTexDropdown)
                        -- Background Color dropdown
                        local function bgColorOpts()
                            local container = Settings.CreateControlTextContainer()
                            container:Add("default", "Default")
                            container:Add("texture", "Texture Original")
                            container:Add("custom", "Custom")
                            return container:GetData()
                        end
                        local bgTintRow, bgTintLabel, bgTintSwatch
                        local function getBgColorMode() return db.styleBackgroundColorMode or "default" end
                        local function setBgColorMode(v)
                            db.styleBackgroundColorMode = v or "default"
                            refresh()
                            local isCustom = (v == "custom")
                            if bgTintLabel then bgTintLabel:SetTextColor(isCustom and 1 or 0.5, isCustom and 1 or 0.5, isCustom and 1 or 0.5) end
                            if bgTintSwatch then bgTintSwatch:SetEnabled(isCustom) end
                        end
                        local bgColorSetting = CreateLocalSetting("Background Color", "string", getBgColorMode, setBgColorMode, getBgColorMode())
                        local initBgColor = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Background Color", setting = bgColorSetting, options = bgColorOpts })
                        local cbg = CreateFrame("Frame", nil, frame.PageB, "SettingsDropdownControlTemplate")
                        cbg.GetElementData = function() return initBgColor end
                        cbg:SetPoint("TOPLEFT", 4, yB.y)
                        cbg:SetPoint("TOPRIGHT", -16, yB.y)
                        initBgColor:InitFrame(cbg)
                        if panel and panel.ApplyRobotoWhite then
                            local lbl = cbg and (cbg.Text or cbg.Label)
                            if lbl then panel.ApplyRobotoWhite(lbl) end
                        end
                        table.insert(styleControls, cbg)
                        yB.y = yB.y - 34
                        -- Background Tint color swatch
                        local function getBgTint()
                            local c = db.styleBackgroundTint or {0,0,0,1}; return c[1], c[2], c[3], c[4]
                        end
                        local function setBgTint(r,g,b,a)
                            db.styleBackgroundTint = {r,g,b,a}; refresh()
                        end
                        local f3 = CreateFrame("Frame", nil, frame.PageB, "SettingsListElementTemplate")
                        bgTintRow = f3
                        f3:SetHeight(26)
                        f3:SetPoint("TOPLEFT", 4, yB.y)
                        f3:SetPoint("TOPRIGHT", -16, yB.y)
                        f3.Text:SetText("Background Tint")
                        if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f3.Text) end
                        bgTintLabel = f3.Text
                        local rightBg = CreateFrame("Frame", nil, f3)
                        rightBg:SetSize(250, 26)
                        rightBg:SetPoint("RIGHT", f3, "RIGHT", -16, 0)
                        f3.Text:ClearAllPoints()
                        f3.Text:SetPoint("LEFT", f3, "LEFT", 36.5, 0)
                        f3.Text:SetPoint("RIGHT", rightBg, "LEFT", 0, 0)
                        f3.Text:SetJustifyH("LEFT")
                        local function getBgColorTable()
                            local r, g, b, a = getBgTint()
                            return {r or 1, g or 1, b or 1, a or 1}
                        end
                        local function setBgColorTable(r, g, b, a)
                            setBgTint(r, g, b, a)
                        end
                        local bgSwatch = CreateColorSwatch(rightBg, getBgColorTable, setBgColorTable, true)
                        bgSwatch:SetPoint("LEFT", rightBg, "LEFT", 8, 0)
                        bgTintSwatch = bgSwatch
                        local isBgCustom = (getBgColorMode() == "custom")
                        if bgTintLabel then bgTintLabel:SetTextColor(isBgCustom and 1 or 0.5, isBgCustom and 1 or 0.5, isBgCustom and 1 or 0.5) end
                        if bgTintSwatch then bgTintSwatch:SetEnabled(isBgCustom) end
                        table.insert(styleControls, bgTintRow)
                        table.insert(styleControls, bgTintSwatch)
                        yB.y = yB.y - 34
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
					t.healthBarHeightPct = 100
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
		-- Health Bar tabs (ordered by Unit Frames tab priority: Positioning > Sizing > Style/Texture > Border > Visibility > Text Elements)
		-- Tab name is "Sizing/Direction" for Target/Focus (which support reverse fill), "Sizing" for Player/Pet
		local isTargetOrFocus = (componentId == "ufTarget" or componentId == "ufFocus")
		local sizingTabName = isTargetOrFocus and "Sizing/Direction" or "Sizing"
		local hbTabs = { sectionTitle = "", tabAText = sizingTabName, tabBText = "Style", tabCText = "Border", tabDText = "% Text", tabEText = "Value Text" }
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

				-- PageA: Sizing/Direction (experimental) — Bar Fill Direction + Health Bar Width
				do
					local function applyNow()
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local y = { y = -50 }
					
					-- Bar Fill Direction dropdown (Target/Focus only)
					if isTargetOrFocus then
						local label = "Bar Fill Direction"
						local function fillDirOptions()
							local container = Settings.CreateControlTextContainer()
							container:Add("default", "Left to Right (default)")
							container:Add("reverse", "Right to Left (mirrored)")
							return container:GetData()
						end
						local function getter()
							local t = ensureUFDB() or {}
							return t.healthBarReverseFill and "reverse" or "default"
						end
						local function setter(v)
							local t = ensureUFDB(); if not t then return end
							local wasReverse = not not t.healthBarReverseFill
							local willBeReverse = (v == "reverse")
							
							if wasReverse and not willBeReverse then
								-- Switching FROM reverse TO default: Save current width and force to 100
								local currentWidth = tonumber(t.healthBarWidthPct) or 100
								t.healthBarWidthPctSaved = currentWidth
								t.healthBarWidthPct = 100
							elseif not wasReverse and willBeReverse then
								-- Switching FROM default TO reverse: Restore saved width
								local savedWidth = tonumber(t.healthBarWidthPctSaved) or 100
								t.healthBarWidthPct = savedWidth
							end
							
							t.healthBarReverseFill = willBeReverse
							applyNow()
							-- Refresh the page to update Bar Width slider enabled state
							if panel and panel.SuspendRefresh then panel.SuspendRefresh(0.25) end
							if panel and panel.RefreshCurrentCategoryDeferred then
								panel.RefreshCurrentCategoryDeferred()
							end
						end
						addDropdown(frame.PageA, label, fillDirOptions, getter, setter, y)
					end
					
					-- Bar Width slider (only enabled for Target/Focus with reverse fill)
					local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
					local label = "Bar Width (%)"
					local options = Settings.CreateSliderOptions(100, 150, 1)
					options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
					
					-- Getter: Always return the actual stored value
					local function getter()
						local t = ensureUFDB() or {}
						return tonumber(t.healthBarWidthPct) or 100
					end
					
					-- Setter: Store value normally (only when slider is enabled)
					local function setter(v)
						local t = ensureUFDB(); if not t then return end
						-- For Target/Focus: prevent changes when reverse fill is disabled
						if isTargetOrFocus and not t.healthBarReverseFill then
							return -- Silently ignore changes when disabled
						end
						local val = tonumber(v) or 100
						val = math.max(100, math.min(150, val))
						t.healthBarWidthPct = val
						applyNow()
					end
					
					local setting = CreateLocalSetting(label, "number", getter, setter, getter())
					local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
					local widthSlider = CreateFrame("Frame", nil, frame.PageA, "SettingsSliderControlTemplate")
					widthSlider.GetElementData = function() return initSlider end
					widthSlider:SetPoint("TOPLEFT", 4, y.y)
					widthSlider:SetPoint("TOPRIGHT", -16, y.y)
					initSlider:InitFrame(widthSlider)
					if widthSlider.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(widthSlider.Text) end
					
					-- Store reference for later updates
					widthSlider._scooterSetting = setting
					
					-- Conditional enable/disable based on fill direction (Target/Focus only)
					if isTargetOrFocus then
						local t = ensureUFDB() or {}
						local isReverse = not not t.healthBarReverseFill
						
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
								local static = CreateFrame("Frame", nil, frame.PageA, "SettingsListElementTemplate")
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
						return tonumber(t.healthBarHeightPct) or 100
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
						t.healthBarHeightPct = val
						applyNow()
					end
					
					local heightSetting = CreateLocalSetting(heightLabel, "number", heightGetter, heightSetter, heightGetter())
					local initHeightSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = heightLabel, setting = heightSetting, options = heightOptions })
					local heightSlider = CreateFrame("Frame", nil, frame.PageA, "SettingsSliderControlTemplate")
					heightSlider.GetElementData = function() return initHeightSlider end
					heightSlider:SetPoint("TOPLEFT", 4, y.y)
					heightSlider:SetPoint("TOPRIGHT", -16, y.y)
					initHeightSlider:InitFrame(heightSlider)
					if heightSlider.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(heightSlider.Text) end
					
					-- Add info icon to enabled slider explaining the requirement
					if panel and panel.CreateInfoIconForLabel then
						local tooltipText = "Bar Height customization requires 'Use Custom Borders' to be enabled. This setting allows you to adjust the vertical size of the health bar."
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
								local static = CreateFrame("Frame", nil, frame.PageA, "SettingsListElementTemplate")
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
								local tooltipText = "Bar Height customization requires 'Use Custom Borders' to be enabled. This setting allows you to adjust the vertical size of the health bar."
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

				-- PageD: % Text
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
					-- Font controls for % Text
					addDropdown(frame.PageD, "% Text Font", fontOptions,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return s.fontFace or "FRIZQT__" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.fontFace = v; applyNow() end,
						y)
					addStyle(frame.PageD, "% Text Style",
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return s.style or "OUTLINE" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.style = v; applyNow() end,
						y)
					addSlider(frame.PageD, "% Text Size", 6, 48, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return tonumber(s.size) or 14 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.size = tonumber(v) or 14; applyNow() end,
						y)
					addColor(frame.PageD, "% Text Color", true,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
						function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.color = {r,g,b,a}; applyNow() end,
						y)
					addSlider(frame.PageD, "% Text Offset X", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.offset = t.textHealthPercent.offset or {}; t.textHealthPercent.offset.x = tonumber(v) or 0; applyNow() end,
						y)
					addSlider(frame.PageD, "% Text Offset Y", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.offset = t.textHealthPercent.offset or {}; t.textHealthPercent.offset.y = tonumber(v) or 0; applyNow() end,
						y)
				end

				-- PageE: Value Text
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
					-- Match % Text layout: drop the cursor after the checkbox row
					y.y = y.y - 34
					-- Font controls for Value Text
					addDropdown(frame.PageE, "Value Text Font", fontOptions,
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return s.fontFace or "FRIZQT__" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.fontFace = v; applyNow() end,
						y)
					addStyle(frame.PageE, "Value Text Style",
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return s.style or "OUTLINE" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.style = v; applyNow() end,
						y)
					addSlider(frame.PageE, "Value Text Size", 6, 48, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return tonumber(s.size) or 14 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.size = tonumber(v) or 14; applyNow() end,
						y)
					addColor(frame.PageE, "Value Text Color", true,
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
						function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.color = {r,g,b,a}; applyNow() end,
						y)
					addSlider(frame.PageE, "Value Text Offset X", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.offset = t.textHealthValue.offset or {}; t.textHealthValue.offset.x = tonumber(v) or 0; applyNow() end,
						y)
					addSlider(frame.PageE, "Value Text Offset Y", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.offset = t.textHealthValue.offset or {}; t.textHealthValue.offset.y = tonumber(v) or 0; applyNow() end,
						y)
				end

				-- PageB: Foreground/Background Texture + Color
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
					local f = CreateFrame("Frame", nil, frame.PageB, "SettingsDropdownControlTemplate")
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
					panel.DropdownWithInlineSwatch(frame.PageB, y, {
						label = "Foreground Color",
						getMode = getColorMode,
						setMode = setColorMode,
						getColor = getTintTbl,
						setColor = setTintTbl,
						options = colorOpts,
						insideButton = true,
					})

					-- Background Texture dropdown
					local function getBgTex() local t = ensureUFDB() or {}; return t.healthBarBackgroundTexture or "default" end
					local function setBgTex(v) local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundTexture = v; applyNow() end
					local bgTexSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
					local initBgDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Background Texture", setting = bgTexSetting, options = opts })
					local fbg = CreateFrame("Frame", nil, frame.PageB, "SettingsDropdownControlTemplate")
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
					panel.DropdownWithInlineSwatch(frame.PageB, y, {
						label = "Background Color",
						getMode = getBgColorMode,
						setMode = setBgColorMode,
						getColor = getBgTintTbl,
						setColor = setBgTintTbl,
						options = bgColorOpts,
						insideButton = true,
					})
					if bgTintLabel then bgTintLabel:SetTextColor(isCustom and 1 or 0.5, isCustom and 1 or 0.5, isCustom and 1 or 0.5) end
					if bgTintSwatch then bgTintSwatch:SetEnabled(isCustom) end
					y.y = y.y - 34

					-- Background Opacity slider
					local function getBgOpacity() local t = ensureUFDB() or {}; return t.healthBarBackgroundOpacity or 50 end
					local function setBgOpacity(v) local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundOpacity = tonumber(v) or 50; applyNow() end
					local bgOpacitySetting = CreateLocalSetting("Background Opacity", "number", getBgOpacity, setBgOpacity, getBgOpacity())
					local bgOpacityOpts = Settings.CreateSliderOptions(0, 100, 1)
					bgOpacityOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
					local bgOpacityInit = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Background Opacity", setting = bgOpacitySetting, options = bgOpacityOpts })
					local fOpa = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
					fOpa.GetElementData = function() return bgOpacityInit end
					fOpa:SetPoint("TOPLEFT", 4, y.y)
					fOpa:SetPoint("TOPRIGHT", -16, y.y)
					bgOpacityInit:InitFrame(fOpa)
					if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(fOpa) end
					if panel and panel.ApplyRobotoWhite and fOpa.Text then panel.ApplyRobotoWhite(fOpa.Text) end
					y.y = y.y - 48
				end

				-- PageC: Border (Health Bar only)
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
					local f = CreateFrame("Frame", nil, frame.PageC, "SettingsDropdownControlTemplate")
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
						local row = CreateFrame("Frame", nil, frame.PageC, "SettingsCheckboxControlTemplate")
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
						local sf = CreateFrame("Frame", nil, frame.PageC, "SettingsSliderControlTemplate")
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
						local sf = CreateFrame("Frame", nil, frame.PageC, "SettingsSliderControlTemplate")
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
							container:Add("default", "Left to Right (default)")
							container:Add("reverse", "Right to Left (mirrored)")
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
					local options = Settings.CreateSliderOptions(100, 150, 1)
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
						val = math.max(100, math.min(150, val))
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
				c:Add("class", "Class Color")
				c:Add("custom", "Custom")
				return c:GetData()
			end
			local function getMode()
				local t = ensureUFDB() or {}; local s = t.textName or {}; return s.colorMode or "default"
			end
			local function setMode(v)
				local t = ensureUFDB(); if not t then return end
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
		nltInit.GetExtent = function() return 300 end
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

		-- Portrait tabs: Positioning / Sizing / Mask / Border / Text / Visibility
		local portraitTabs = { sectionTitle = "", tabAText = "Positioning", tabBText = "Sizing", tabCText = "Mask", tabDText = "Border", tabEText = "Text", tabFText = "Visibility" }
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
			end

			-- PageA: Positioning
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

			-- PageE: Text (placeholder for now)
			do
				local y = { y = -50 }
				-- Controls will be added here later
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

		-- Sixth collapsible section: Cast Bar (Player only)
			if componentId == "ufPlayer" then
				local expInitializerCB = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
					name = "Cast Bar",
					sectionKey = "Cast Bar",
					componentId = componentId,
					expanded = panel:IsSectionExpanded(componentId, "Cast Bar"),
				})
				expInitializerCB.GetExtent = function() return 30 end
				table.insert(init, expInitializerCB)

				-- Cast Bar tabbed section: Positioning / Sizing (Sizing placeholder for now)
				local cbData = { sectionTitle = "", tabAText = "Positioning", tabBText = "Sizing", tabCText = "Cast Time" }
				cbData.build = function(frame)
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
							if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
							if panel and panel.RefreshCurrentCategoryDeferred then panel.RefreshCurrentCategoryDeferred() end
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

					local lockSetting = addCheckboxLock()

					local function isLocked()
						return (lockSetting and lockSetting.GetValue and lockSetting:GetValue()) and true or false
					end

					-- Position inputs only when unlocked
					if not isLocked() then
						local function readOffsets()
							local cb = getCastBar()
							if not cb then return 0, 0 end
							if cb.GetPoint then
								local p, relTo, rp, ox, oy = cb:GetPoint(1)
								if p == "CENTER" and rp == "CENTER" and relTo == UIParent and type(ox) == "number" and type(oy) == "number" then
									return uiUnitsToPixels(ox), uiUnitsToPixels(oy)
								end
							end
							if not (cb.GetCenter and UIParent and UIParent.GetCenter) then return 0, 0 end
							local fx, fy = cb:GetCenter(); local px, py = UIParent:GetCenter(); if not (fx and fy and px and py) then return 0, 0 end
							return math.floor((fx - px) + 0.5), math.floor((fy - py) + 0.5)
						end
						local pendingPxX, pendingPxY, pendingWriteTimer
						local function writeOffsets(newX, newY)
							local cb = getCastBar(); if not cb then return end
							local curX, curY = readOffsets()
							pendingPxX = (newX ~= nil) and clampPositionValue(roundPositionValue(newX)) or curX
							pendingPxY = (newY ~= nil) and clampPositionValue(roundPositionValue(newY)) or curY
							if pendingWriteTimer and pendingWriteTimer.Cancel then pendingWriteTimer:Cancel() end
							pendingWriteTimer = C_Timer.NewTimer(0.1, function()
								local pxX = clampPositionValue(roundPositionValue(pendingPxX or 0))
								local pxY = clampPositionValue(roundPositionValue(pendingPxY or 0))
								local ux = pixelsToUiUnits(pxX)
								local uy = pixelsToUiUnits(pxY)
								if addon and addon.EditMode and addon.EditMode.ReanchorFrame then
									addon.EditMode.ReanchorFrame(cb, "CENTER", UIParent, "CENTER", ux, uy)
									if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
									if cb and cb.ClearAllPoints and cb.SetPoint then
										cb:ClearAllPoints(); cb:SetPoint("CENTER", UIParent, "CENTER", ux, uy)
									end
								end
							end)
						end
						local function addPosInput(label, getter, setter)
							local options = Settings.CreateSliderOptions(-1000, 1000, 1)
							options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(roundPositionValue(v)) end)
							local setting = CreateLocalSetting(label, "number", getter, setter, getter())
							local init = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
							ConvertSliderInitializerToTextInput(init)
							local row = CreateFrame("Frame", nil, frame.PageA, "SettingsSliderControlTemplate")
							row.GetElementData = function() return init end
							row:SetPoint("TOPLEFT", 4, yA.y)
							row:SetPoint("TOPRIGHT", -16, yA.y)
							init:InitFrame(row)
							if row.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(row.Text) end
							yA.y = yA.y - 34
						end
						addPosInput("X Position (px)", function() local x = readOffsets(); return x end, function(v) writeOffsets(v, nil) end)
						addPosInput("Y Position (px)", function() local _, y = readOffsets(); return y end, function(v) writeOffsets(nil, v) end)
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

					-- Cast Time tab (PageC): Show Cast Time checkbox
					do
						local y = { y = -50 }
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
							end
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
					end
				end

				local tabCBC = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", cbData)
				tabCBC.GetExtent = function() return 220 end
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

