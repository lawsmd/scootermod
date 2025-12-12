local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

--------------------------------------------------------------------------------
-- Group Frames Builder Module
--------------------------------------------------------------------------------
-- This module provides renderers for the Group Frames category:
--   - Party Frames (gfParty)
--   - Raid Frames (gfRaid)
--
-- Frame Targets:
--   Party: PartyFrame / CompactPartyFrame (Enum.EditModeUnitFrameSystemIndices.Party)
--   Raid:  CompactRaidFrameContainer (Enum.EditModeUnitFrameSystemIndices.Raid)
--------------------------------------------------------------------------------

-- Helper: Get Party Frame from Edit Mode
local function getPartyFrame()
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EM.Party)
end

-- Helper: Get Raid Frame from Edit Mode
local function getRaidFrame()
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EM.Raid)
end

--------------------------------------------------------------------------------
-- Party Frames Renderer (gfParty)
--------------------------------------------------------------------------------
-- Collapsible sections: Positioning, Sizing, Border, Style, Text, Visibility
-- All sections are empty placeholders for now.
--------------------------------------------------------------------------------

function panel.RenderGFParty()
    local componentId = "gfParty"
    local title = "Party Frames"

    local render = function()
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then return end

        local init = {}

        -- Helper to add a collapsible section header
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

        -- Add all six collapsible sections (empty placeholders)
        addHeader("Positioning", "Positioning")
        addHeader("Sizing", "Sizing")
        addHeader("Border", "Border")
        addHeader("Style", "Style")
        addHeader("Text", "Text")
        addHeader("Visibility", "Visibility")

        -- Set right pane title
        if right.SetTitle then
            right:SetTitle(title)
        end

        right:Display(init)
    end

    return { mode = "list", render = render, componentId = componentId }
end

--------------------------------------------------------------------------------
-- Raid Frames Renderer (gfRaid)
--------------------------------------------------------------------------------
-- Collapsible sections: Positioning, Sizing*, Border, Style, Text, Visibility
-- *Sizing uses a tabbed section with 10-man, 25-man, 40-man tabs
--------------------------------------------------------------------------------

function panel.RenderGFRaid()
    local componentId = "gfRaid"
    local title = "Raid Frames"

    local render = function()
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then return end

        local init = {}

        -- Helper to add a collapsible section header
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

        -- 1. Positioning section header (contains tabbed section)
        addHeader("Positioning", "Positioning")

        -- Positioning tabbed section: 10-man, 25-man, 40-man tabs
        -- Each tab will expose X/Y position offsets for the corresponding raid size
        local positioningTabs = {
            sectionTitle = "",
            tabAText = "10-man",
            tabBText = "25-man",
            tabCText = "40-man",
            build = function(frame)
                -- Tab content builders will be populated here once features are implemented
                -- Each tab will expose Edit Mode position settings for the corresponding raid size:
                --   - X Position (px)
                --   - Y Position (px)
                --
                -- The ViewRaidSize setting (Enum.EditModeUnitFrameSetting.ViewRaidSize) controls
                -- which raid size preview is active:
                --   - Enum.ViewRaidSize.Ten
                --   - Enum.ViewRaidSize.TwentyFive
                --   - Enum.ViewRaidSize.Forty

                local y = { y = -10 }

                -- PageA: 10-man Positioning (placeholder)
                if frame.PageA then
                    local placeholder = frame.PageA:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    placeholder:SetPoint("TOPLEFT", frame.PageA, "TOPLEFT", 8, y.y)
                    placeholder:SetText("10-man positioning controls coming soon")
                    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(placeholder) end
                end

                -- PageB: 25-man Positioning (placeholder)
                if frame.PageB then
                    local placeholder = frame.PageB:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    placeholder:SetPoint("TOPLEFT", frame.PageB, "TOPLEFT", 8, y.y)
                    placeholder:SetText("25-man positioning controls coming soon")
                    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(placeholder) end
                end

                -- PageC: 40-man Positioning (placeholder)
                if frame.PageC then
                    local placeholder = frame.PageC:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    placeholder:SetPoint("TOPLEFT", frame.PageC, "TOPLEFT", 8, y.y)
                    placeholder:SetText("40-man positioning controls coming soon")
                    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(placeholder) end
                end
            end,
        }

        local positioningInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", positioningTabs)
        -- Static height for tabbed section with placeholder content
        positioningInit.GetExtent = function() return 120 end
        positioningInit:AddShownPredicate(function()
            return panel:IsSectionExpanded(componentId, "Positioning")
        end)
        table.insert(init, positioningInit)

        -- 2. Sizing section header (contains tabbed section)
        addHeader("Sizing", "Sizing")

        -- Sizing tabbed section: 10-man, 25-man, 40-man tabs
        -- This allows linking Edit Mode size-specific settings
        local sizingTabs = {
            sectionTitle = "",
            tabAText = "10-man",
            tabBText = "25-man",
            tabCText = "40-man",
            build = function(frame)
                -- Tab content builders will be populated here once features are implemented
                -- Each tab will expose Edit Mode settings for the corresponding raid size:
                --   - Frame Width (72-144, step 2)
                --   - Frame Height (36-72, step 2)
                --
                -- The ViewRaidSize setting (Enum.EditModeUnitFrameSetting.ViewRaidSize) controls
                -- which raid size preview is active:
                --   - Enum.ViewRaidSize.Ten
                --   - Enum.ViewRaidSize.TwentyFive
                --   - Enum.ViewRaidSize.Forty

                local y = { y = -10 }

                -- PageA: 10-man Sizing (placeholder)
                if frame.PageA then
                    local placeholder = frame.PageA:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    placeholder:SetPoint("TOPLEFT", frame.PageA, "TOPLEFT", 8, y.y)
                    placeholder:SetText("10-man sizing controls coming soon")
                    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(placeholder) end
                end

                -- PageB: 25-man Sizing (placeholder)
                if frame.PageB then
                    local placeholder = frame.PageB:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    placeholder:SetPoint("TOPLEFT", frame.PageB, "TOPLEFT", 8, y.y)
                    placeholder:SetText("25-man sizing controls coming soon")
                    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(placeholder) end
                end

                -- PageC: 40-man Sizing (placeholder)
                if frame.PageC then
                    local placeholder = frame.PageC:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    placeholder:SetPoint("TOPLEFT", frame.PageC, "TOPLEFT", 8, y.y)
                    placeholder:SetText("40-man sizing controls coming soon")
                    if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(placeholder) end
                end
            end,
        }

        local sizingInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", sizingTabs)
        -- Static height for tabbed section with placeholder content
        -- Formula: ~30 top padding + controls + ~20 bottom padding
        -- Start with 120px for minimal placeholder content; increase when real controls are added
        sizingInit.GetExtent = function() return 120 end
        sizingInit:AddShownPredicate(function()
            return panel:IsSectionExpanded(componentId, "Sizing")
        end)
        table.insert(init, sizingInit)

        -- 3. Border section header (empty placeholder)
        addHeader("Border", "Border")

        -- 4. Style section header with Health Bar styling controls
        addHeader("Style", "Style")

        -- Style section content: Health Bar Foreground/Background Texture & Color
        -- Uses ScooterListElementTemplate for direct control layout under collapsible header
        local styleInit = Settings.CreateElementInitializer("ScooterListElementTemplate")
        -- Height: 16 top + 34 foreground tex + 34 fg color + 24 spacer + 34 bg tex + 34 bg color + 48 opacity
        styleInit.GetExtent = function() return 224 end
        styleInit:AddShownPredicate(function()
            return panel:IsSectionExpanded(componentId, "Style")
        end)
        styleInit.InitFrame = function(self, frame)
            -- Avoid rebuilding if already built
            if frame._ScooterRaidStyleBuilt then return end
            frame._ScooterRaidStyleBuilt = true

            -- Hide default list element text
            if frame.Text then
                frame.Text:SetText("")
                frame.Text:Hide()
            end

            -- Helper: ensure groupFrames.raid DB exists
            local function ensureRaidDB()
                local db = addon and addon.db and addon.db.profile
                if not db then return nil end
                db.groupFrames = db.groupFrames or {}
                db.groupFrames.raid = db.groupFrames.raid or {}
                return db.groupFrames.raid
            end

            local function applyNow()
                if addon and addon.ApplyRaidFrameHealthBarStyle then
                    addon.ApplyRaidFrameHealthBarStyle()
                end
            end

            local y = -16

            -- 1. Foreground Texture dropdown
            local function texOpts() return addon.BuildBarTextureOptionsContainer() end
            local function getTex()
                local t = ensureRaidDB() or {}
                return t.healthBarTexture or "default"
            end
            local function setTex(v)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarTexture = v
                applyNow()
            end
            local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
            local initTexDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                name = "Foreground Texture",
                setting = texSetting,
                options = texOpts
            })
            local fTex = CreateFrame("Frame", nil, frame, "SettingsDropdownControlTemplate")
            fTex.GetElementData = function() return initTexDrop end
            fTex:SetPoint("TOPLEFT", 4, y)
            fTex:SetPoint("TOPRIGHT", -16, y)
            initTexDrop:InitFrame(fTex)
            if panel and panel.ApplyRobotoWhite then
                local lbl = fTex and (fTex.Text or fTex.Label)
                if lbl then panel.ApplyRobotoWhite(lbl) end
            end
            if fTex.Control and panel.ThemeDropdownWithSteppers then
                panel.ThemeDropdownWithSteppers(fTex.Control)
            end
            if fTex.Control and addon.InitBarTextureDropdown then
                addon.InitBarTextureDropdown(fTex.Control, texSetting)
            end
            y = y - 34

            -- 2. Foreground Color (dropdown + inline swatch)
            local function fgColorOpts()
                local container = Settings.CreateControlTextContainer()
                container:Add("default", "Default")
                container:Add("texture", "Texture Original")
                container:Add("class", "Class Color")
                container:Add("custom", "Custom")
                return container:GetData()
            end
            local function getFgColorMode()
                local t = ensureRaidDB() or {}
                return t.healthBarColorMode or "default"
            end
            local function setFgColorMode(v)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarColorMode = v or "default"
                applyNow()
            end
            local function getFgTint()
                local t = ensureRaidDB() or {}
                local c = t.healthBarTint or {1, 1, 1, 1}
                return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
            end
            local function setFgTint(r, g, b, a)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarTint = { r or 1, g or 1, b or 1, a or 1 }
                applyNow()
            end
            local yRef = { y = y }
            panel.DropdownWithInlineSwatch(frame, yRef, {
                label = "Foreground Color",
                getMode = getFgColorMode,
                setMode = setFgColorMode,
                getColor = getFgTint,
                setColor = setFgTint,
                options = fgColorOpts,
                insideButton = true,
            })
            y = yRef.y

            -- Spacer between Foreground and Background
            do
                local spacer = CreateFrame("Frame", nil, frame, "SettingsListElementTemplate")
                spacer:SetHeight(20)
                spacer:SetPoint("TOPLEFT", 4, y)
                spacer:SetPoint("TOPRIGHT", -16, y)
                if spacer.Text then spacer.Text:SetText("") end
                y = y - 24
            end

            -- 3. Background Texture dropdown
            local function getBgTex()
                local t = ensureRaidDB() or {}
                return t.healthBarBackgroundTexture or "default"
            end
            local function setBgTex(v)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarBackgroundTexture = v
                applyNow()
            end
            local bgTexSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
            local initBgTexDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                name = "Background Texture",
                setting = bgTexSetting,
                options = texOpts
            })
            local fBgTex = CreateFrame("Frame", nil, frame, "SettingsDropdownControlTemplate")
            fBgTex.GetElementData = function() return initBgTexDrop end
            fBgTex:SetPoint("TOPLEFT", 4, y)
            fBgTex:SetPoint("TOPRIGHT", -16, y)
            initBgTexDrop:InitFrame(fBgTex)
            if panel and panel.ApplyRobotoWhite then
                local lbl = fBgTex and (fBgTex.Text or fBgTex.Label)
                if lbl then panel.ApplyRobotoWhite(lbl) end
            end
            if fBgTex.Control and panel.ThemeDropdownWithSteppers then
                panel.ThemeDropdownWithSteppers(fBgTex.Control)
            end
            if fBgTex.Control and addon.InitBarTextureDropdown then
                addon.InitBarTextureDropdown(fBgTex.Control, bgTexSetting)
            end
            y = y - 34

            -- 4. Background Color (dropdown + inline swatch)
            local function bgColorOpts()
                local container = Settings.CreateControlTextContainer()
                container:Add("default", "Default")
                container:Add("texture", "Texture Original")
                container:Add("custom", "Custom")
                return container:GetData()
            end
            local function getBgColorMode()
                local t = ensureRaidDB() or {}
                return t.healthBarBackgroundColorMode or "default"
            end
            local function setBgColorMode(v)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarBackgroundColorMode = v or "default"
                applyNow()
            end
            local function getBgTint()
                local t = ensureRaidDB() or {}
                local c = t.healthBarBackgroundTint or {0, 0, 0, 1}
                return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
            end
            local function setBgTint(r, g, b, a)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }
                applyNow()
            end
            yRef = { y = y }
            panel.DropdownWithInlineSwatch(frame, yRef, {
                label = "Background Color",
                getMode = getBgColorMode,
                setMode = setBgColorMode,
                getColor = getBgTint,
                setColor = setBgTint,
                options = bgColorOpts,
                insideButton = true,
            })
            y = yRef.y

            -- 5. Background Opacity slider (0-100)
            local function getBgOpacity()
                local t = ensureRaidDB() or {}
                return t.healthBarBackgroundOpacity or 50
            end
            local function setBgOpacity(v)
                local t = ensureRaidDB()
                if not t then return end
                t.healthBarBackgroundOpacity = tonumber(v) or 50
                applyNow()
            end
            local bgOpacitySetting = CreateLocalSetting("Background Opacity", "number", getBgOpacity, setBgOpacity, getBgOpacity())
            local bgOpacityOpts = Settings.CreateSliderOptions(0, 100, 1)
            bgOpacityOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                return tostring(math.floor(v + 0.5))
            end)
            local bgOpacityInit = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", {
                name = "Background Opacity",
                setting = bgOpacitySetting,
                options = bgOpacityOpts
            })
            local fOpa = CreateFrame("Frame", nil, frame, "SettingsSliderControlTemplate")
            fOpa.GetElementData = function() return bgOpacityInit end
            fOpa:SetPoint("TOPLEFT", 4, y)
            fOpa:SetPoint("TOPRIGHT", -16, y)
            bgOpacityInit:InitFrame(fOpa)
            if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(fOpa) end
            if panel and panel.ApplyRobotoWhite and fOpa.Text then panel.ApplyRobotoWhite(fOpa.Text) end
        end
        table.insert(init, styleInit)

        -- 5. Text section header (contains tabbed section)
        addHeader("Text", "Text")

        -- Text tabbed section: Player Name tab (more tabs can be added later)
        local textTabs = {
            sectionTitle = "",
            tabAText = "Player Name",
            build = function(frame)
                -- Helper: ensure groupFrames.raid.textPlayerName DB exists
                local function ensureTextDB()
                    local db = addon and addon.db and addon.db.profile
                    if not db then return nil end
                    db.groupFrames = db.groupFrames or {}
                    db.groupFrames.raid = db.groupFrames.raid or {}
                    db.groupFrames.raid.textPlayerName = db.groupFrames.raid.textPlayerName or {
                        fontFace = "FRIZQT__",
                        size = 12,
                        style = "OUTLINE",
                        color = { 1, 1, 1, 1 },
                        offset = { x = 0, y = 0 },
                    }
                    return db.groupFrames.raid.textPlayerName
                end

                local function applyNow()
                    if addon and addon.ApplyRaidFrameTextStyle then
                        addon.ApplyRaidFrameTextStyle()
                    end
                end

                local function fontOptions()
                    if addon and addon.BuildFontOptionsContainer then
                        return addon.BuildFontOptionsContainer()
                    end
                    return Settings.CreateControlTextContainer():GetData()
                end

                local function fmtInt(v)
                    return tostring(math.floor((tonumber(v) or 0) + 0.5))
                end

                -- Helper: create a dropdown control
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
                    -- Apply ScooterMod theming to dropdown text and arrows
                    if row.Control and panel.ThemeDropdownWithSteppers then
                        panel.ThemeDropdownWithSteppers(row.Control)
                    end
                    -- Wire font picker for font dropdowns
                    if label:lower():find("font", 1, true) and not label:lower():find("style", 1, true) then
                        if row.Control and row.Control.Dropdown and addon and addon.InitFontDropdown then
                            addon.InitFontDropdown(row.Control.Dropdown, setting, optionsProvider)
                        end
                    end
                    yRef.y = yRef.y - 34
                    return row
                end

                -- Helper: create a slider control
                local function addSlider(parent, label, minV, maxV, step, getter, setter, yRef)
                    local options = Settings.CreateSliderOptions(minV, maxV, step)
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                        return fmtInt(v)
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
                    return row
                end

                -- Helper: create a font style dropdown
                local function addStyleDropdown(parent, label, getter, setter, yRef)
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
                    addDropdown(parent, label, styleOptions, getter, setter, yRef)
                end

                -- Helper: create a color row with swatch
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
                    local swatch = CreateColorSwatch(right, getColorTable, setColorTable, true)
                    swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                    yRef.y = yRef.y - 34
                    return row
                end

                -- PageA: Player Name text settings (Baseline 6)
                if frame.PageA then
                    local y = { y = -50 }

                    -- 1. Font Face
                    addDropdown(frame.PageA, "Player Name Font", fontOptions,
                        function()
                            local cfg = ensureTextDB()
                            return cfg and cfg.fontFace or "FRIZQT__"
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.fontFace = v end
                            applyNow()
                        end,
                        y)

                    -- 2. Font Size
                    addSlider(frame.PageA, "Player Name Size", 6, 32, 1,
                        function()
                            local cfg = ensureTextDB()
                            return cfg and tonumber(cfg.size) or 12
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.size = tonumber(v) or 12 end
                            applyNow()
                        end,
                        y)

                    -- 3. Font Style
                    addStyleDropdown(frame.PageA, "Player Name Style",
                        function()
                            local cfg = ensureTextDB()
                            return cfg and cfg.style or "OUTLINE"
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then cfg.style = v end
                            applyNow()
                        end,
                        y)

                    -- 4. Font Color
                    addColorRow(frame.PageA, "Player Name Color",
                        function()
                            local cfg = ensureTextDB()
                            local c = cfg and cfg.color or { 1, 1, 1, 1 }
                            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                        end,
                        function(r, g, b, a)
                            local cfg = ensureTextDB()
                            if cfg then cfg.color = { r or 1, g or 1, b or 1, a or 1 } end
                            applyNow()
                        end,
                        y)

                    -- 5. X Offset
                    addSlider(frame.PageA, "Player Name Offset X", -50, 50, 1,
                        function()
                            local cfg = ensureTextDB()
                            return cfg and cfg.offset and tonumber(cfg.offset.x) or 0
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then
                                cfg.offset = cfg.offset or {}
                                cfg.offset.x = tonumber(v) or 0
                            end
                            applyNow()
                        end,
                        y)

                    -- 6. Y Offset
                    addSlider(frame.PageA, "Player Name Offset Y", -50, 50, 1,
                        function()
                            local cfg = ensureTextDB()
                            return cfg and cfg.offset and tonumber(cfg.offset.y) or 0
                        end,
                        function(v)
                            local cfg = ensureTextDB()
                            if cfg then
                                cfg.offset = cfg.offset or {}
                                cfg.offset.y = tonumber(v) or 0
                            end
                            applyNow()
                        end,
                        y)
                end
            end,
        }

        local textInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", textTabs)
        -- Static height for Baseline 6 controls: 30 + (6*34) + 20 = 254px, rounded to 270px for safety
        textInit.GetExtent = function() return 270 end
        textInit:AddShownPredicate(function()
            return panel:IsSectionExpanded(componentId, "Text")
        end)
        table.insert(init, textInit)

        -- 6. Visibility section header (empty placeholder)
        addHeader("Visibility", "Visibility")

        -- Set right pane title
        if right.SetTitle then
            right:SetTitle(title)
        end

        right:Display(init)
    end

    return { mode = "list", render = render, componentId = componentId }
end

