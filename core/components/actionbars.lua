local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil

-- Store action bar state in a separate table to avoid writing addon data to Blizzard frames.
-- Writing addon data directly to frames (e.g., bar._ScooterMouseoverComponent = self) can
-- taint the frames, causing protected functions like SetShownBase() to be blocked.
local actionBarState = {}  -- { [frame] = { component, baseOpacity, isMousedOver } }
local actionBarHooked = {} -- { [frame] = true } - tracks which frames have had HookScript called

local function getBarState(bar)
    if not actionBarState[bar] then
        actionBarState[bar] = {}
    end
    return actionBarState[bar]
end

local function ApplyActionBarStyling(self)
    local bar = _G[self.frameName]
    if not bar then return end

    local baseOp = tonumber(self.db and self.db.barOpacity)
    if baseOp == nil and self.settings and self.settings.barOpacity then baseOp = self.settings.barOpacity.default end
    baseOp = tonumber(baseOp) or 100
    if baseOp < 1 then baseOp = 1 elseif baseOp > 100 then baseOp = 100 end
    local oocOp = tonumber(self.db and self.db.barOpacityOutOfCombat)
    if oocOp == nil and self.settings and self.settings.barOpacityOutOfCombat then oocOp = self.settings.barOpacityOutOfCombat.default end
    oocOp = tonumber(oocOp) or baseOp
    if oocOp < 1 then oocOp = 1 elseif oocOp > 100 then oocOp = 100 end
    local tgtOp = tonumber(self.db and self.db.barOpacityWithTarget)
    if tgtOp == nil and self.settings and self.settings.barOpacityWithTarget then tgtOp = self.settings.barOpacityWithTarget.default end
    tgtOp = tonumber(tgtOp) or baseOp
    if tgtOp < 1 then tgtOp = 1 elseif tgtOp > 100 then tgtOp = 100 end
    local hasTarget = (UnitExists and UnitExists("target")) and true or false
    local appliedOp = hasTarget and tgtOp or (Util.PlayerInCombat() and baseOp or oocOp)

    -- Mouseover Mode: when enabled, hovering the bar or any of its buttons sets opacity to 100%
    local mouseoverEnabled = self.db and self.db.mouseoverMode
    local state = getBarState(bar)
    
    if mouseoverEnabled then
        -- Store the component reference and opacity values in our separate table (NOT on the bar frame)
        state.component = self
        state.baseOpacity = appliedOp / 100

        -- Helper functions for mouseover handling (use closure to capture bar reference)
        local function onMouseEnter()
            local s = actionBarState[bar]
            if s and s.component and s.component.db and s.component.db.mouseoverMode then
                s.isMousedOver = true
                if bar.SetAlpha then pcall(bar.SetAlpha, bar, 1) end
            end
        end
        local function onMouseLeave()
            local s = actionBarState[bar]
            if s and s.component and s.component.db and s.component.db.mouseoverMode then
                -- Only restore opacity if mouse is not over the bar or any of its buttons
                local isOverBar = bar:IsMouseOver()
                if not isOverBar then
                    s.isMousedOver = false
                    local restoreOp = s.baseOpacity or 1
                    if bar.SetAlpha then pcall(bar.SetAlpha, bar, restoreOp) end
                end
            end
        end

        -- Hook the bar frame itself (for gaps between buttons)
        if not actionBarHooked[bar] then
            bar:HookScript("OnEnter", onMouseEnter)
            bar:HookScript("OnLeave", onMouseLeave)
            actionBarHooked[bar] = true
        end

        -- Hook each button on the bar for mouseover
        local function enumerateButtonsForMouseover()
            local buttons = {}
            local prefix
            if self.frameName == "MainActionBar" then
                prefix = "ActionButton"
            elseif self.frameName == "PetActionBar" then
                prefix = "PetActionButton"
            elseif self.frameName == "StanceBar" then
                prefix = "StanceButton"
            else
                prefix = tostring(self.frameName) .. "Button"
            end
            local maxButtons = self.maxButtons or 12
            for i = 1, maxButtons do
                local btn = _G[prefix .. i]
                if btn then buttons[#buttons + 1] = btn end
            end
            return buttons
        end

        for _, btn in ipairs(enumerateButtonsForMouseover()) do
            if not actionBarHooked[btn] then
                btn:HookScript("OnEnter", onMouseEnter)
                btn:HookScript("OnLeave", onMouseLeave)
                actionBarHooked[btn] = true
            end
        end

        -- If currently moused over, keep at 100%; otherwise use calculated opacity
        if state.isMousedOver then
            if bar.SetAlpha then pcall(bar.SetAlpha, bar, 1) end
        else
            if bar.SetAlpha then pcall(bar.SetAlpha, bar, appliedOp / 100) end
        end
    else
        -- Mouseover mode disabled - just apply the calculated opacity
        state.isMousedOver = false
        if bar.SetAlpha then pcall(bar.SetAlpha, bar, appliedOp / 100) end
    end

    local function enumerateButtons()
        local buttons = {}
        local prefix
        if self.frameName == "MainActionBar" then
            prefix = "ActionButton"
        elseif self.frameName == "PetActionBar" then
            prefix = "PetActionButton"
        elseif self.frameName == "StanceBar" then
            prefix = "StanceButton"
        else
            prefix = tostring(self.frameName) .. "Button"
        end
        local maxButtons = self.maxButtons or 12
        for i = 1, maxButtons do
            local btn = _G[prefix .. i]
            if btn then buttons[#buttons + 1] = btn end
        end
        if #buttons == 0 and bar.GetChildren then
            for _, child in ipairs({ bar:GetChildren() }) do
                local t = child.GetObjectType and child:GetObjectType()
                if t == "Button" or t == "CheckButton" then
                    buttons[#buttons + 1] = child
                end
            end
        end
        return buttons
    end

    local function toggleDefaultButtonArt(button, restore)
        if not button or not button.GetRegions then return end
        if button.GetNormalTexture then
            local nt = button:GetNormalTexture()
            if nt and nt.SetAlpha then pcall(nt.SetAlpha, nt, restore and 1 or 0) end
        end
        for _, r in ipairs({ button:GetRegions() }) do
            if r and r.GetObjectType and r:GetObjectType() == "Texture" then
                local nm = r.GetName and (r:GetName() or "") or ""
                if nm:find("Border", 1, true) or nm:find("BorderShadow", 1, true) or nm:find("SlotArt", 1, true)
                    or nm:find("SlotBackground", 1, true) or nm:find("NormalTexture", 1, true) then
                    pcall(r.SetAlpha, r, restore and 1 or 0)
                end
            end
        end
    end

    local wantBorder = self.db and self.db.borderEnable
    local disableAll = self.db and self.db.borderDisableAll
    local styleKey = (self.db and self.db.borderStyle) or "square"
    if styleKey == "none" then styleKey = "square"; if self.db then self.db.borderStyle = styleKey end end
    local thickness = tonumber(self.db and self.db.borderThickness) or 1
    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
    local tintEnabled = self.db and self.db.borderTintEnable and type(self.db.borderTintColor) == "table"
    local tintColor
    if tintEnabled then
        local c = self.db.borderTintColor or {1,1,1,1}
        tintColor = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
    end

    for _, btn in ipairs(enumerateButtons()) do
        if disableAll then
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(btn) end
            toggleDefaultButtonArt(btn, false)
        elseif wantBorder then
            if styleKey == "square" and addon.Borders and addon.Borders.ApplySquare then
                if addon.Borders.HideAll then addon.Borders.HideAll(btn) end
                local col = tintEnabled and tintColor or {0, 0, 0, 1}
                addon.Borders.ApplySquare(btn, {
                    size = thickness,
                    color = col,
                    layer = "OVERLAY",
                    layerSublevel = 7,
                    expandX = -1,
                    expandY = 0,
                })
                local container = btn.ScootSquareBorderContainer or btn
                local edges = (container and container.ScootSquareBorderEdges) or btn.ScootSquareBorderEdges
                if edges and edges.Right then
                    edges.Right:ClearAllPoints()
                    edges.Right:SetPoint("TOPRIGHT", container or btn, "TOPRIGHT", -2, 0)
                    edges.Right:SetPoint("BOTTOMRIGHT", container or btn, "BOTTOMRIGHT", -2, 0)
                end
                if edges and edges.Top then
                    edges.Top:ClearAllPoints()
                    edges.Top:SetPoint("TOPLEFT", container or btn, "TOPLEFT", 1, 0)
                    edges.Top:SetPoint("TOPRIGHT", container or btn, "TOPRIGHT", -2, 0)
                end
                if edges and edges.Bottom then
                    edges.Bottom:ClearAllPoints()
                    edges.Bottom:SetPoint("BOTTOMLEFT", container or btn, "BOTTOMLEFT", 1, 0)
                    edges.Bottom:SetPoint("BOTTOMRIGHT", container or btn, "BOTTOMRIGHT", -2, 0)
                end
            else
                addon.ApplyIconBorderStyle(btn, styleKey, {
                    thickness = thickness,
                    color = tintColor,
                    tintEnabled = tintEnabled,
                    db = self.db,
                    thicknessKey = "borderThickness",
                    tintColorKey = "borderTintColor",
                    defaultThickness = (self.settings and self.settings.borderThickness and self.settings.borderThickness.default) or 1,
                })
            end
            toggleDefaultButtonArt(btn, false)
        else
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(btn) end
            toggleDefaultButtonArt(btn, true)
        end

        do
            local disableBackdrop = self.db and self.db.backdropDisable
            local style = (self.db and self.db.backdropStyle) or (self.settings and self.settings.backdropStyle and self.settings.backdropStyle.default) or "blizzardBg"
            local opacity = tonumber(self.db and self.db.backdropOpacity) or 100
            local inset = tonumber(self.db and self.db.backdropInset) or 0
            local backdropTintEnabled = self.db and self.db.backdropTintEnable and type(self.db.backdropTintColor) == "table"
            local backdropTint
            if backdropTintEnabled then
                local c = self.db.backdropTintColor or {1,1,1,1}
                backdropTint = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
            end
            if disableBackdrop then
                local bg = btn and btn.SlotBackground
                if bg and bg.SetAlpha then pcall(bg.SetAlpha, bg, 0) end
            else
                if addon and addon.ApplyIconBackdropToActionButton then
                    addon.ApplyIconBackdropToActionButton(btn, style, opacity, inset, backdropTint)
                end
            end
        end

        do
            local defaultFace = (select(1, GameFontNormal:GetFont()))
            local function applyTextToFontString(fs, cfg, justify, anchorPoint, relTo)
                if not fs or not fs.SetFont then return end
                local size = tonumber(cfg.size) or 14
                local style = cfg.style or "OUTLINE"
                local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                pcall(fs.SetDrawLayer, fs, "OVERLAY", 10)
                if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, style) else fs:SetFont(face, size, style) end
                local c = cfg.color or {1,1,1,1}
                if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                if justify and fs.SetJustifyH then pcall(fs.SetJustifyH, fs, justify) end
                local ox = (cfg.offset and cfg.offset.x) or 0
                local oy = (cfg.offset and cfg.offset.y) or 0
                if (ox ~= 0 or oy ~= 0) and fs.ClearAllPoints and fs.SetPoint then
                    fs:ClearAllPoints()
                    fs:SetPoint(anchorPoint or "CENTER", relTo or btn, anchorPoint or "CENTER", ox, oy)
                end
            end

            if btn.Count then
                local cfg = self.db.textStacks or { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }
                applyTextToFontString(btn.Count, cfg, "CENTER", "CENTER", btn)
            end

            local cdOwner = btn.cooldown or btn.Cooldown or btn.CooldownFrame or nil
            local cdText
            if cdOwner then
                local function findFS(obj)
                    if not obj then return nil end
                    if obj.GetObjectType and obj:GetObjectType() == "FontString" then return obj end
                    if obj.GetRegions then
                        local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                        for i = 1, n do
                            local r = select(i, obj:GetRegions())
                            if r and r.GetObjectType and r:GetObjectType() == "FontString" then return r end
                        end
                    end
                    return nil
                end
                cdText = findFS(cdOwner)
            end
            if cdText then
                local cfg = self.db.textCooldown or { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }
                applyTextToFontString(cdText, cfg, "CENTER", "CENTER", btn)
            end

            if btn.HotKey then
                local txt = (btn.HotKey.GetText and btn.HotKey:GetText()) or nil
                local rangeIndicator = (_G and _G.RANGE_INDICATOR) or "RANGE_INDICATOR"
                local isEmpty = (txt == nil or txt == "")
                local isRange = (txt == rangeIndicator or txt == "•")
                local hiddenByUser = self.db and self.db.textHotkeyHidden
                local shouldShow = (not hiddenByUser) and (not isEmpty) and (not isRange)
                pcall(btn.HotKey.SetShown, btn.HotKey, shouldShow)
                if shouldShow then
                    local cfg = self.db.textHotkey or { size = 14, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }
                    applyTextToFontString(btn.HotKey, cfg, "RIGHT", "TOPRIGHT", btn)
                end
            end

            if btn.Name then
                local txt = (btn.Name.GetText and btn.Name:GetText()) or nil
                local isEmpty = (txt == nil or txt == "")
                local hiddenByUser = self.db and self.db.textMacroHidden
                local shouldShow = (not hiddenByUser) and (not isEmpty)
                pcall(btn.Name.SetShown, btn.Name, shouldShow)
                if shouldShow then
                    local cfg = self.db.textMacro or { size = 14, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }
                    applyTextToFontString(btn.Name, cfg, "CENTER", "BOTTOM", btn)
                end
            end
        end
    end
end

-- Micro Bar opacity and mouseover styling function
local function ApplyMicroBarStyling(self)
    local bar = _G[self.frameName]
    if not bar then return end

    -- Read opacity settings with fallbacks to defaults
    local baseOp = tonumber(self.db and self.db.barOpacity)
    if baseOp == nil and self.settings and self.settings.barOpacity then baseOp = self.settings.barOpacity.default end
    baseOp = tonumber(baseOp) or 100
    if baseOp < 1 then baseOp = 1 elseif baseOp > 100 then baseOp = 100 end

    local oocOp = tonumber(self.db and self.db.barOpacityOutOfCombat)
    if oocOp == nil and self.settings and self.settings.barOpacityOutOfCombat then oocOp = self.settings.barOpacityOutOfCombat.default end
    oocOp = tonumber(oocOp) or baseOp
    if oocOp < 1 then oocOp = 1 elseif oocOp > 100 then oocOp = 100 end

    local tgtOp = tonumber(self.db and self.db.barOpacityWithTarget)
    if tgtOp == nil and self.settings and self.settings.barOpacityWithTarget then tgtOp = self.settings.barOpacityWithTarget.default end
    tgtOp = tonumber(tgtOp) or baseOp
    if tgtOp < 1 then tgtOp = 1 elseif tgtOp > 100 then tgtOp = 100 end

    -- Determine which opacity to apply based on priority: target > combat > out of combat
    local hasTarget = (UnitExists and UnitExists("target")) and true or false
    local appliedOp = hasTarget and tgtOp or (Util.PlayerInCombat() and baseOp or oocOp)

    -- Helper to enumerate micro buttons
    local function enumerateMicroButtons()
        local buttons = {}
        -- Standard micro button names in the retail client
        local microButtonNames = {
            "CharacterMicroButton",
            "SpellbookMicroButton",
            "TalentMicroButton",
            "AchievementMicroButton",
            "QuestLogMicroButton",
            "GuildMicroButton",
            "LFDMicroButton",
            "CollectionsMicroButton",
            "EJMicroButton",
            "StoreMicroButton",
            "MainMenuMicroButton",
        }
        for _, name in ipairs(microButtonNames) do
            local btn = _G[name]
            if btn then buttons[#buttons + 1] = btn end
        end
        -- Fallback: enumerate children if standard buttons not found
        if #buttons == 0 and bar.GetChildren then
            for _, child in ipairs({ bar:GetChildren() }) do
                local t = child.GetObjectType and child:GetObjectType()
                if t == "Button" or t == "CheckButton" then
                    buttons[#buttons + 1] = child
                end
            end
        end
        return buttons
    end

    -- Mouseover Mode: when enabled, hovering the bar or any of its buttons sets opacity to 100%
    local mouseoverEnabled = self.db and self.db.mouseoverMode
    local state = getBarState(bar)
    
    if mouseoverEnabled then
        -- Store the component reference and opacity values in our separate table (NOT on the bar frame)
        state.component = self
        state.baseOpacity = appliedOp / 100

        -- Helper functions for mouseover handling (use closure to capture bar reference)
        local function onMouseEnter()
            local s = actionBarState[bar]
            if s and s.component and s.component.db and s.component.db.mouseoverMode then
                s.isMousedOver = true
                if bar.SetAlpha then pcall(bar.SetAlpha, bar, 1) end
            end
        end
        local function onMouseLeave()
            local s = actionBarState[bar]
            if s and s.component and s.component.db and s.component.db.mouseoverMode then
                -- Only restore opacity if mouse is not over the bar or any of its buttons
                local isOverBar = bar:IsMouseOver()
                if not isOverBar then
                    s.isMousedOver = false
                    local restoreOp = s.baseOpacity or 1
                    if bar.SetAlpha then pcall(bar.SetAlpha, bar, restoreOp) end
                end
            end
        end

        -- Hook the bar frame itself (for gaps between buttons)
        if not actionBarHooked[bar] then
            bar:HookScript("OnEnter", onMouseEnter)
            bar:HookScript("OnLeave", onMouseLeave)
            actionBarHooked[bar] = true
        end

        -- Hook each micro button for mouseover
        for _, btn in ipairs(enumerateMicroButtons()) do
            if not actionBarHooked[btn] then
                btn:HookScript("OnEnter", onMouseEnter)
                btn:HookScript("OnLeave", onMouseLeave)
                actionBarHooked[btn] = true
            end
        end

        -- If currently moused over, keep at 100%; otherwise use calculated opacity
        if state.isMousedOver then
            if bar.SetAlpha then pcall(bar.SetAlpha, bar, 1) end
        else
            if bar.SetAlpha then pcall(bar.SetAlpha, bar, appliedOp / 100) end
        end
    else
        -- Mouseover mode disabled - just apply the calculated opacity
        state.isMousedOver = false
        if bar.SetAlpha then pcall(bar.SetAlpha, bar, appliedOp / 100) end
    end
end

addon:RegisterComponentInitializer(function(self)
    local microBar = Component:New({
        id = "microBar",
        name = "Micro Bar",
        frameName = "MicroMenuContainer",
        settings = {
            orientation = { type = "editmode", settingId = 0, default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            direction = { type = "editmode", settingId = 1, default = "right", ui = {
                label = "Icon Direction", widget = "dropdown", values = { left = "Left", right = "Right", up = "Up", down = "Down" }, section = "Positioning", order = 2, dynamicValues = true
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 98
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 99
            }},
            menuSize = { type = "editmode", settingId = 2, default = 100, ui = {
                label = "Menu Size (Scale)", widget = "slider", min = 70, max = 200, step = 5, section = "Sizing", order = 1
            }},
            eyeSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Eye Size", widget = "slider", min = 50, max = 150, step = 5, section = "Sizing", order = 2
            }},
            -- Visibility / Opacity settings (section "Misc" renders as "Visibility" header)
            barOpacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 1
            }},
            barOpacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 2
            }},
            barOpacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            mouseoverMode = { type = "addon", default = false, ui = {
                label = "Mouseover Mode", widget = "checkbox", section = "Misc", order = 4
            }},
        },
        ApplyStyling = ApplyMicroBarStyling,
    })
    self:RegisterComponent(microBar)

    local stanceBar = Component:New({
        id = "stanceBar",
        name = "Stance Bar",
        frameName = "StanceBar",
        maxButtons = 10,
        settings = {
            orientation = { type = "editmode", default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            columns = { type = "editmode", default = 1, ui = {
                label = "# Columns/Rows", widget = "slider", min = 1, max = 4, step = 1, section = "Positioning", order = 2, dynamicLabel = true
            }},
            iconPadding = { type = "editmode", default = 2, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 3
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 98
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 99
            }},
            iconSize = { type = "editmode", default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            barOpacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 99
            }},
            barOpacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 100
            }},
            barOpacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 101
            }},
            mouseoverMode = { type = "addon", default = false, ui = {
                label = "Mouseover Mode", widget = "checkbox", section = "Misc", order = 102
            }},
        },
        ApplyStyling = ApplyActionBarStyling,
    })
    self:RegisterComponent(stanceBar)

    local function abComponent(id, name, frameName, defaultOrientation)
        return Component:New({
            id = id,
            name = name,
            frameName = frameName,
            settings = {
                orientation = { type = "editmode", settingId = 0, default = defaultOrientation, ui = {
                    label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
                }},
                columns = { type = "editmode", default = 1, ui = {
                    label = "# Columns/Rows", widget = "slider", min = 1, max = 4, step = 1, section = "Positioning", order = 2, dynamicLabel = true
                }},
                numIcons = { type = "editmode", default = 12, ui = {
                    label = "# of Icons", widget = "slider", min = 6, max = 12, step = 1, section = "Positioning", order = 3
                }},
                iconPadding = { type = "editmode", default = 2, ui = {
                    label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 4
                }},
                iconSize = { type = "editmode", default = 100, ui = {
                    label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
                }},
                borderDisableAll = { type = "addon", default = false, ui = {
                    label = "Disable All Borders", widget = "checkbox", section = "Border", order = 1
                }},
                borderEnable = { type = "addon", default = false, ui = {
                    label = "Use Custom Border", widget = "checkbox", section = "Border", order = 2
                }},
                borderTintEnable = { type = "addon", default = false, ui = {
                    label = "Border Tint", widget = "checkbox", section = "Border", order = 3
                }},
                borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                    label = "Tint Color", widget = "color", section = "Border", order = 4
                }},
                borderStyle = { type = "addon", default = "square", ui = {
                    label = "Border Style", widget = "dropdown", section = "Border", order = 5,
                    optionsProvider = function()
                        if addon.BuildIconBorderOptionsContainer then
                            return addon.BuildIconBorderOptionsContainer()
                        end
                        return {}
                    end
                }},
                borderThickness = { type = "addon", default = 1, ui = {
                    label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.2, section = "Border", order = 6
                }},
                backdropDisable = { type = "addon", default = false, ui = {
                    label = "Disable Backdrop", widget = "checkbox", section = "Backdrop", order = 1
                }},
                backdropStyle = { type = "addon", default = "blizzardBg", ui = {
                    label = "Backdrop Style", widget = "dropdown", section = "Backdrop", order = 2,
                    optionsProvider = function()
                        if addon.BuildIconBackdropOptionsContainer then
                            return addon.BuildIconBackdropOptionsContainer()
                        end
                        return {}
                    end
                }},
                backdropOpacity = { type = "addon", default = 100, ui = {
                    label = "Backdrop Opacity", widget = "slider", min = 1, max = 100, step = 1, section = "Backdrop", order = 3
                }},
                backdropTintEnable = { type = "addon", default = false, ui = {
                    label = "Backdrop Tint", widget = "checkbox", section = "Backdrop", order = 4
                }},
                backdropTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                    label = "Tint Color", widget = "color", section = "Backdrop", order = 5
                }},
                backdropInset = { type = "addon", default = 0, ui = {
                    label = "Backdrop Inset", widget = "slider", min = -4, max = 4, step = 1, section = "Backdrop", order = 6
                }},
                textStacks = { type = "addon", default = { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
                textCooldown = { type = "addon", default = { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
                textHotkeyHidden = { type = "addon", default = false, ui = {
                    label = "Hide Hotkey Text", widget = "checkbox", section = "Text", order = 10
                }},
                textHotkey = { type = "addon", default = { size = 14, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
                textMacroHidden = { type = "addon", default = false, ui = {
                    label = "Hide Macro Text", widget = "checkbox", section = "Text", order = 20
                }},
                textMacro = { type = "addon", default = { size = 14, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
                barOpacity = { type = "addon", default = 100, ui = {
                    label = "Opacity in Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 99
                }},
                barOpacityOutOfCombat = { type = "addon", default = 100, ui = {
                    label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 100
                }},
                barOpacityWithTarget = { type = "addon", default = 100, ui = {
                    label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 101
                }},
                mouseoverMode = { type = "addon", default = false, ui = {
                    label = "Mouseover Mode", widget = "checkbox", section = "Misc", order = 102
                }},
                positionX = { type = "addon", default = 0, ui = {
                    label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 98
                }},
                positionY = { type = "addon", default = 0, ui = {
                    label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 99
                }},
                supportsText = { type = "addon", default = true },
            },
            ApplyStyling = ApplyActionBarStyling,
        })
    end

    local defs = {
        { "actionBar1", "Action Bar 1", "MainActionBar",        "H", false },
        { "actionBar2", "Action Bar 2", "MultiBarBottomLeft",  "H", true },
        { "actionBar3", "Action Bar 3", "MultiBarBottomRight", "H", true },
        { "actionBar4", "Action Bar 4", "MultiBarRight",       "V", true },
        { "actionBar5", "Action Bar 5", "MultiBarLeft",        "V", true },
        { "actionBar6", "Action Bar 6", "MultiBar5",           "H", true },
        { "actionBar7", "Action Bar 7", "MultiBar6",           "H", true },
        { "actionBar8", "Action Bar 8", "MultiBar7",           "H", true },
    }

    for _, d in ipairs(defs) do
        local comp = abComponent(d[1], d[2], d[3], d[4])
        if d[5] then
            comp.settings.barVisibility = { type = "editmode", default = "always", ui = {
                label = "Bar Visible", widget = "dropdown", values = { always = "Always", combat = "In Combat", not_in_combat = "Not In Combat", hidden = "Hidden" }, section = "Misc", order = 1
            }}
            comp.settings.alwaysShowButtons = { type = "editmode", default = true, ui = {
                label = "Always Show Buttons", widget = "checkbox", section = "Misc", order = 2
            }}
        else
            comp.supportsEmptyVisibilitySection = true
            comp.settings.alwaysShowButtons = { type = "editmode", default = true, ui = {
                label = "Always Show Buttons", widget = "checkbox", section = "Misc", order = 1
            }}
            comp.settings.hideBarArt = { type = "editmode", default = false, ui = {
                label = "Hide Bar Art", widget = "checkbox", section = "Misc", order = 2
            }}
            comp.settings.hideBarScrolling = { type = "editmode", default = false, ui = {
                label = "Hide Bar Scrolling", widget = "checkbox", section = "Misc", order = 3
            }}
        end
        self:RegisterComponent(comp)
    end

    -- Pet Bar: 10 buttons, similar Edit Mode settings to Action Bars but no visibility/art/scrolling options
    local petBar = Component:New({
        id = "petBar",
        name = "Pet Bar",
        frameName = "PetActionBar",
        maxButtons = 10,
        settings = {
            orientation = { type = "editmode", settingId = 0, default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            columns = { type = "editmode", default = 1, ui = {
                label = "# Columns/Rows", widget = "slider", min = 1, max = 4, step = 1, section = "Positioning", order = 2, dynamicLabel = true
            }},
            iconPadding = { type = "editmode", default = 2, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 3
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 98
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 99
            }},
            iconSize = { type = "editmode", default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            borderDisableAll = { type = "addon", default = false, ui = {
                label = "Disable All Borders", widget = "checkbox", section = "Border", order = 1
            }},
            borderEnable = { type = "addon", default = false, ui = {
                label = "Use Custom Border", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 3
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 4
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 5,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.2, section = "Border", order = 6
            }},
            backdropDisable = { type = "addon", default = false, ui = {
                label = "Disable Backdrop", widget = "checkbox", section = "Backdrop", order = 1
            }},
            backdropStyle = { type = "addon", default = "blizzardBg", ui = {
                label = "Backdrop Style", widget = "dropdown", section = "Backdrop", order = 2,
                optionsProvider = function()
                    if addon.BuildIconBackdropOptionsContainer then
                        return addon.BuildIconBackdropOptionsContainer()
                    end
                    return {}
                end
            }},
            backdropOpacity = { type = "addon", default = 100, ui = {
                label = "Backdrop Opacity", widget = "slider", min = 1, max = 100, step = 1, section = "Backdrop", order = 3
            }},
            backdropTintEnable = { type = "addon", default = false, ui = {
                label = "Backdrop Tint", widget = "checkbox", section = "Backdrop", order = 4
            }},
            backdropTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Backdrop", order = 5
            }},
            backdropInset = { type = "addon", default = 0, ui = {
                label = "Backdrop Inset", widget = "slider", min = -4, max = 4, step = 1, section = "Backdrop", order = 6
            }},
            textStacks = { type = "addon", default = { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
            textCooldown = { type = "addon", default = { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
            textHotkeyHidden = { type = "addon", default = false, ui = {
                label = "Hide Hotkey Text", widget = "checkbox", section = "Text", order = 10
            }},
            textHotkey = { type = "addon", default = { size = 14, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
            textMacroHidden = { type = "addon", default = false, ui = {
                label = "Hide Macro Text", widget = "checkbox", section = "Text", order = 20
            }},
            textMacro = { type = "addon", default = { size = 14, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
            alwaysShowButtons = { type = "editmode", default = true, ui = {
                label = "Always Show Buttons", widget = "checkbox", section = "Misc", order = 1
            }},
            barOpacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 99
            }},
            barOpacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 100
            }},
            barOpacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 101
            }},
            mouseoverMode = { type = "addon", default = false, ui = {
                label = "Mouseover Mode", widget = "checkbox", section = "Misc", order = 102
            }},
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyActionBarStyling,
    })
    self:RegisterComponent(petBar)
end)

function addon.CopyActionBarSettings(sourceComponentId, destComponentId)
    if type(sourceComponentId) ~= "string" or type(destComponentId) ~= "string" then return end
    if sourceComponentId == destComponentId then return end
    local src = addon.Components and addon.Components[sourceComponentId]
    local dst = addon.Components and addon.Components[destComponentId]
    if not src or not dst then return end
    -- Source must be actionBar1-8; destination can be actionBar1-8 or petBar (destination-only)
    local srcValid = sourceComponentId:match("^actionBar%d$") ~= nil
    local dstValid = destComponentId:match("^actionBar%d$") or destComponentId == "petBar"
    if not (srcValid and dstValid) then return end

    if not src.db or not dst.db then return end

    local function deepcopy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, vv in pairs(v) do out[k] = deepcopy(vv) end
        return out
    end

    for key, def in pairs(dst.settings or {}) do
        if key ~= "supportsText" and key ~= "supportsEmptyVisibilitySection" then
            local srcHasSetting = src.settings and src.settings[key] ~= nil
            local srcVal = src.db and (src.db[key])
            if srcVal == nil and srcHasSetting then
                srcVal = src.settings[key] and src.settings[key].default
            end
            if srcVal ~= nil then
                dst.db[key] = deepcopy(srcVal)
            end
        end
    end

    do
        local textKeys = {
            "textStacks", "textCooldown",
            "textHotkeyHidden", "textHotkey",
            "textMacroHidden",  "textMacro",
        }
        for _, key in ipairs(textKeys) do
            if src.db[key] ~= nil then
                dst.db[key] = deepcopy(src.db[key])
            end
        end
    end

    if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
        for key, def in pairs(dst.settings or {}) do
            if type(def) == "table" and def.type == "editmode" then
                pcall(addon.EditMode.SyncComponentSettingToEditMode, dst, key)
            end
        end
    end

    if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
    -- Note: Skip RequestApplyChanges to avoid taint from opening Edit Mode panel.
    -- Edit Mode layout changes persist via SaveOnly and take effect on reload.
    addon:ApplyStyles()
end

