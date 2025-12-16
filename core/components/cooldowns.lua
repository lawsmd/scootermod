local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil

--------------------------------------------------------------------------------
-- Proc Glow Animation Fix
--------------------------------------------------------------------------------
-- When a proc/spell activation overlay fires, Blizzard's ActionButtonSpellAlertManager
-- creates a SpellActivationAlert frame sized to the button's current dimensions.
-- If ScooterMod has customized the icon to a non-square ratio (e.g., wider than tall),
-- the proc glow animation initially appears square until Blizzard's layout catches up (~0.5s).
--
-- This fix hooks ShowAlert and immediately resizes the ProcLoopFlipbook and
-- SpellActivationAlert frame to match ScooterMod's custom dimensions.
--------------------------------------------------------------------------------

local CDM_VIEWERS = {
    EssentialCooldownViewer = "essentialCooldowns",
    UtilityCooldownViewer = "utilityCooldowns",
    BuffIconCooldownViewer = "trackedBuffs",
}

local function GetScooterModIconDimensions(itemFrame)
    -- Determine which CDM viewer this item belongs to
    local parent = itemFrame:GetParent()
    if not parent then return nil, nil end
    
    local parentName = parent:GetName()
    local componentId = parentName and CDM_VIEWERS[parentName]
    if not componentId then return nil, nil end
    
    -- Get the component's DB settings
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return nil, nil end
    
    local width = component.db.iconWidth or (component.settings and component.settings.iconWidth and component.settings.iconWidth.default)
    local height = component.db.iconHeight or (component.settings and component.settings.iconHeight and component.settings.iconHeight.default)
    
    return width, height
end

local function UpdateProcGlowSize(itemFrame)
    local alertFrame = itemFrame.SpellActivationAlert
    if not alertFrame then return end
    
    local width, height = GetScooterModIconDimensions(itemFrame)
    if not width or not height then return end
    
    -- Resize the SpellActivationAlert frame to match ScooterMod's custom icon dimensions
    -- Blizzard uses a 1.4 multiplier for the alert frame size
    local alertWidth = width * 1.4
    local alertHeight = height * 1.4
    alertFrame:SetSize(alertWidth, alertHeight)
    
    -- Explicitly resize and reposition the ProcLoopFlipbook texture
    -- This is the key fix - the flipbook uses setAllPoints but doesn't update immediately
    if alertFrame.ProcLoopFlipbook then
        alertFrame.ProcLoopFlipbook:ClearAllPoints()
        alertFrame.ProcLoopFlipbook:SetSize(alertWidth, alertHeight)
        alertFrame.ProcLoopFlipbook:SetPoint("CENTER", alertFrame, "CENTER", 0, 0)
    end
    
    -- Also resize ProcStartFlipbook if present (the initial burst animation)
    if alertFrame.ProcStartFlipbook then
        -- ProcStartFlipbook is typically larger, using a 3x multiplier from Blizzard's template (150/50)
        local startMultiplier = 3
        alertFrame.ProcStartFlipbook:ClearAllPoints()
        alertFrame.ProcStartFlipbook:SetSize(width * startMultiplier, height * startMultiplier)
        alertFrame.ProcStartFlipbook:SetPoint("CENTER", alertFrame, "CENTER", 0, 0)
    end
end

-- Hook ActionButtonSpellAlertManager.ShowAlert to fix proc glow sizing for CDM icons
local function HookProcGlowSizing()
    if not ActionButtonSpellAlertManager then return end
    if addon._procGlowHooked then return end
    
    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, actionButton)
        -- Only process CDM item frames (they have a parent that's a CooldownViewer)
        if not actionButton then return end
        local parent = actionButton:GetParent()
        if not parent then return end
        
        local parentName = parent:GetName()
        if not parentName or not CDM_VIEWERS[parentName] then return end
        
        -- Defer slightly to ensure the alert frame has been created
        C_Timer.After(0, function()
            UpdateProcGlowSize(actionButton)
        end)
    end)
    
    addon._procGlowHooked = true
end

-- Initialize the hook when the addon loads
addon:RegisterComponentInitializer(function()
    HookProcGlowSizing()
end)

function addon.ApplyTrackedBarVisualsForChild(component, child)
    if not component or not child then return end
    if component.id ~= "trackedBars" then return end
    local barFrame = (child.GetBarFrame and child:GetBarFrame()) or child.Bar
    local iconFrame = (child.GetIconFrame and child:GetIconFrame()) or child.Icon
    if not barFrame or not iconFrame then return end

    local function getSettingValue(key)
        if not component then return nil end
        if component.db and component.db[key] ~= nil then return component.db[key] end
        if component.settings and component.settings[key] then return component.settings[key].default end
        return nil
    end

    local iconWidth = tonumber(getSettingValue("iconWidth"))
    local iconHeight = tonumber(getSettingValue("iconHeight"))
    if iconWidth and iconHeight and iconFrame.SetSize then
        iconWidth = math.max(8, math.min(32, iconWidth))
        iconHeight = math.max(8, math.min(32, iconHeight))
        if component.db then
            component.db.iconWidth = iconWidth
            component.db.iconHeight = iconHeight
        end
        iconFrame:SetSize(iconWidth, iconHeight)
        local tex = iconFrame.Icon or (child.GetIconTexture and child:GetIconTexture())
        if tex and tex.SetAllPoints then tex:SetAllPoints(iconFrame) end
        local mask = iconFrame.Mask or iconFrame.IconMask
        if mask and mask.SetAllPoints then mask:SetAllPoints(iconFrame) end
    end

    local isActive = (child.IsActive and child:IsActive()) or child.isActive

    local desiredPad = tonumber(component.db and component.db.iconBarPadding) or (component.settings.iconBarPadding and component.settings.iconBarPadding.default) or 0
    desiredPad = tonumber(desiredPad) or 0
    local desiredWidthOverride = tonumber(component.db and component.db.barWidth)

    local currentWidth = (barFrame.GetWidth and barFrame:GetWidth()) or nil
    local currentGap
    if barFrame.GetLeft and iconFrame.GetRight then
        local bl = barFrame:GetLeft()
        local ir = iconFrame:GetRight()
        if bl and ir then currentGap = bl - ir end
    end

    local deltaPad = (currentGap and (desiredPad - currentGap)) or 0
    local deltaWidth = 0
    if desiredWidthOverride and desiredWidthOverride > 0 and currentWidth then
        deltaWidth = desiredWidthOverride - currentWidth
    end

    if barFrame.ClearAllPoints and barFrame.SetPoint then
        local rightPoint, rightRelTo, rightRelPoint, rx, ry
        if barFrame.GetNumPoints and barFrame.GetPoint then
            local n = barFrame:GetNumPoints()
            for i = 1, n do
                local p, rt, rp, ox, oy = barFrame:GetPoint(i)
                if p == "RIGHT" then rightPoint, rightRelTo, rightRelPoint, rx, ry = p, rt, rp, ox, oy break end
            end
        end
        barFrame:ClearAllPoints()
        if rightPoint and rightRelTo then
            barFrame:SetPoint("RIGHT", rightRelTo, rightRelPoint or "RIGHT", (rx or 0) + deltaPad + deltaWidth, ry or 0)
        else
            barFrame:SetPoint("RIGHT", child, "RIGHT", deltaPad + deltaWidth, 0)
        end
        local anchorLeftTo, anchorLeftPoint, anchorLeftRelPoint = iconFrame, "RIGHT", "RIGHT"
        if iconFrame.IsShown and not iconFrame:IsShown() then
            anchorLeftTo, anchorLeftPoint, anchorLeftRelPoint = child, "LEFT", "LEFT"
        end
        barFrame:SetPoint("LEFT", anchorLeftTo, anchorLeftPoint, desiredPad, 0)
    end

    if addon.Media and addon.Media.ApplyBarTexturesToBarFrame then
        local useCustom = (component.db and component.db.styleEnableCustom) ~= false
        if useCustom then
            local fg = component.db and component.db.styleForegroundTexture or (component.settings.styleForegroundTexture and component.settings.styleForegroundTexture.default)
            local bg = component.db and component.db.styleBackgroundTexture or (component.settings.styleBackgroundTexture and component.settings.styleBackgroundTexture.default)
            local bgOpacity = component.db and component.db.styleBackgroundOpacity or (component.settings.styleBackgroundOpacity and component.settings.styleBackgroundOpacity.default) or 50
            addon.Media.ApplyBarTexturesToBarFrame(barFrame, fg, bg, bgOpacity)
            local fgColorMode = (component.db and component.db.styleForegroundColorMode) or "default"
            local fgTint = (component.db and component.db.styleForegroundTint) or {1,1,1,1}
            local tex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
            if tex and tex.SetVertexColor then
                local r, g, b, a = 1, 1, 1, 1
                if fgColorMode == "custom" and type(fgTint) == "table" then
                    r, g, b, a = fgTint[1] or 1, fgTint[2] or 1, fgTint[3] or 1, fgTint[4] or 1
                elseif fgColorMode == "texture" then
                    r, g, b, a = 1, 1, 1, 1
                elseif fgColorMode == "default" then
                    r, g, b, a = 1.0, 0.5, 0.25, 1.0
                end
                pcall(tex.SetVertexColor, tex, r, g, b, a)
            end
            local bgColorMode = (component.db and component.db.styleBackgroundColorMode) or "default"
            local bgTint = (component.db and component.db.styleBackgroundTint) or {0,0,0,1}
            if barFrame.ScooterModBG then
                local r, g, b, a = 0, 0, 0, 1
                if bgColorMode == "custom" and type(bgTint) == "table" then
                    r, g, b, a = bgTint[1] or 0, bgTint[2] or 0, bgTint[3] or 0, bgTint[4] or 1
                elseif bgColorMode == "texture" then
                    r, g, b, a = 1, 1, 1, 1
                elseif bgColorMode == "default" then
                    r, g, b, a = 0, 0, 0, 1
                end
                if barFrame.ScooterModBG.SetVertexColor then
                    pcall(barFrame.ScooterModBG.SetVertexColor, barFrame.ScooterModBG, r, g, b, 1.0)
                end
                if barFrame.ScooterModBG.SetAlpha then
                    local opacity = tonumber(bgOpacity) or 50
                    opacity = math.max(0, math.min(100, opacity)) / 100
                    pcall(barFrame.ScooterModBG.SetAlpha, barFrame.ScooterModBG, opacity)
                end
            end
        else
            if barFrame.ScooterModBG then barFrame.ScooterModBG:Hide() end
            local tex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
            if tex and tex.SetAtlas then pcall(tex.SetAtlas, tex, "UI-HUD-CoolDownManager-Bar", true) end
            if barFrame.SetStatusBarAtlas then pcall(barFrame.SetStatusBarAtlas, barFrame, "UI-HUD-CoolDownManager-Bar") end
            if tex then
                if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, 1.0, 0.5, 0.25, 1.0) end
                if tex.SetAlpha then pcall(tex.SetAlpha, tex, 1.0) end
                if tex.SetTexCoord then pcall(tex.SetTexCoord, tex, 0, 1, 0, 1) end
            end
            for _, region in ipairs({ barFrame:GetRegions() }) do
                if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                    pcall(region.SetAlpha, region, 1.0)
                end
            end
            Util.HideDefaultBarTextures(barFrame, true)
        end
    end

    local wantBorder = component.db and component.db.borderEnable
    local styleKey = component.db and component.db.borderStyle or "square"
    if wantBorder then
        local thickness = tonumber(component.db.borderThickness) or 1
        if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
        local tintEnabled = component.db.borderTintEnable and type(component.db.borderTintColor) == "table"
        local color
        if tintEnabled then
            local c = component.db.borderTintColor
            color = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
        else
            if styleDef then
                color = {1, 1, 1, 1}
            else
                color = {0, 0, 0, 1}
            end
        end

        local handled = false
        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
            handled = addon.BarBorders.ApplyToBarFrame(barFrame, styleKey, {
                color = color,
                thickness = thickness,
                component = component,
            })
        end

        if handled then
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(barFrame) end
            Util.HideDefaultBarTextures(barFrame)
        else
            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(barFrame) end
            if addon.Borders and addon.Borders.ApplySquare then
                -- Use levelOffset to elevate the border above bar content, but don't set
                -- containerStrata so it inherits parent's strata and stays below Blizzard menus
                addon.Borders.ApplySquare(barFrame, {
                    size = thickness,
                    color = color,
                    layer = "OVERLAY",
                    layerSublevel = 7,
                    levelOffset = 5,
                    containerParent = barFrame,
                    expandX = 1,
                    expandY = 2,
                })
            end
            Util.HideDefaultBarTextures(barFrame, true)
        end
    else
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(barFrame) end
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(barFrame) end
        Util.HideDefaultBarTextures(barFrame, true)
    end

    local function shouldShowIconBorder()
        local mode = tostring(getSettingValue("displayMode") or "both")
        if mode == "name" then return false end
        if iconFrame.IsShown and not iconFrame:IsShown() then return false end
        return true
    end

    local iconBorderEnabled = not not getSettingValue("iconBorderEnable")
    local iconStyle = tostring(getSettingValue("iconBorderStyle") or "square")
    if iconStyle == "none" then
        iconStyle = "square"
        if component.db then component.db.iconBorderStyle = iconStyle end
    end
    local iconThickness = tonumber(getSettingValue("iconBorderThickness")) or 1
    iconThickness = math.max(1, math.min(16, iconThickness))
    local iconTintEnabled = not not getSettingValue("iconBorderTintEnable")
    local tintRaw = getSettingValue("iconBorderTintColor")
    local tintColor = {1, 1, 1, 1}
    if type(tintRaw) == "table" then
        tintColor = { tintRaw[1] or 1, tintRaw[2] or 1, tintRaw[3] or 1, tintRaw[4] or 1 }
    end

    if iconBorderEnabled and shouldShowIconBorder() then
        Util.ToggleDefaultIconOverlay(iconFrame, false)
        addon.ApplyIconBorderStyle(iconFrame, iconStyle, {
            thickness = iconThickness,
            color = iconTintEnabled and tintColor or nil,
            tintEnabled = iconTintEnabled,
            db = component.db,
            thicknessKey = "iconBorderThickness",
            tintColorKey = "iconBorderTintColor",
            defaultThickness = component.settings and component.settings.iconBorderThickness and component.settings.iconBorderThickness.default or 1,
        })
    else
        Util.ToggleDefaultIconOverlay(iconFrame, true)
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(iconFrame) end
    end

    local function promoteFontLayer(font)
        if font and font.SetDrawLayer then
            font:SetDrawLayer("OVERLAY", 5)
        end
    end
    promoteFontLayer((child.GetNameLabel and child:GetNameLabel()) or child.Name or child.Text or child.Label)
    promoteFontLayer((child.GetDurationLabel and child:GetDurationLabel()) or child.Duration or child.DurationText or child.Timer or child.TimerText)
end

local function ApplyCooldownViewerStyling(self)
    local frame = _G[self.frameName]
    if not frame then return end

    local width = self.db.iconWidth or (self.settings.iconWidth and self.settings.iconWidth.default)
    local height = self.db.iconHeight or (self.settings.iconHeight and self.settings.iconHeight.default)
    local spacing = self.db.iconPadding or (self.settings.iconPadding and self.settings.iconPadding.default)

    if self.id == "trackedBars" and not frame._ScooterTBHooked then
        if hooksecurefunc then
            if frame.OnAcquireItemFrame then
                hooksecurefunc(frame, "OnAcquireItemFrame", function(viewer, itemFrame)
                    -- Guard against combat to prevent taint (see DEBUG.md)
                    if InCombatLockdown and InCombatLockdown() then return end
                    if addon and addon.ApplyTrackedBarVisualsForChild then addon.ApplyTrackedBarVisualsForChild(self, itemFrame) end
                end)
            end
            if frame.RefreshLayout then
                hooksecurefunc(frame, "RefreshLayout", function()
                    -- Guard against combat to prevent taint (see DEBUG.md)
                    if InCombatLockdown and InCombatLockdown() then return end
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            if not addon or not addon.Components or not addon.Components.trackedBars then return end
                            local f = _G[addon.Components.trackedBars.frameName]
                            if not f then return end
                            for _, child in ipairs({ f:GetChildren() }) do
                                if addon and addon.ApplyTrackedBarVisualsForChild then addon.ApplyTrackedBarVisualsForChild(self, child) end
                            end
                        end)
                    end
                end)
            end
        end
        frame._ScooterTBHooked = true
    end

    -- Hook OnAcquireItemFrame for non-bar viewers (Essential, Utility, Tracked Buffs)
    -- This ensures newly learned spells that Blizzard auto-adds to CDM get ScooterMod styling
    if self.id ~= "trackedBars" and not frame._ScooterIconHooked then
        if hooksecurefunc and frame.OnAcquireItemFrame then
            hooksecurefunc(frame, "OnAcquireItemFrame", function(viewer, itemFrame)
                -- Guard against combat to prevent taint on UtilityCooldownViewer:SetSize() etc.
                -- When this hook fires during combat, calling SetSize/ApplyStyling taints the
                -- viewer frame, causing Blizzard's LayoutFrame:Layout() to be blocked.
                -- Styling will be applied after combat via PLAYER_REGEN_ENABLED. (see DEBUG.md)
                if InCombatLockdown and InCombatLockdown() then return end
                -- Apply sizing immediately
                local w = self.db.iconWidth or (self.settings.iconWidth and self.settings.iconWidth.default)
                local h = self.db.iconHeight or (self.settings.iconHeight and self.settings.iconHeight.default)
                if w and h and itemFrame.SetSize then
                    itemFrame:SetSize(w, h)
                end
                -- Apply border if enabled
                if self.db.borderEnable then
                    local styleKey = self.db.borderStyle or "square"
                    if styleKey == "none" then styleKey = "square" end
                    local thickness = tonumber(self.db.borderThickness) or 1
                    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                    local tintEnabled = self.db.borderTintEnable and type(self.db.borderTintColor) == "table"
                    local tintColor
                    if tintEnabled then
                        tintColor = {
                            self.db.borderTintColor[1] or 1,
                            self.db.borderTintColor[2] or 1,
                            self.db.borderTintColor[3] or 1,
                            self.db.borderTintColor[4] or 1,
                        }
                    end
                    addon.ApplyIconBorderStyle(itemFrame, styleKey, {
                        thickness = thickness,
                        color = tintColor,
                        tintEnabled = tintEnabled,
                        db = self.db,
                        thicknessKey = "borderThickness",
                        tintColorKey = "borderTintColor",
                        inset = self.db.borderInset or 0,
                        defaultThickness = self.settings and self.settings.borderThickness and self.settings.borderThickness.default or 1,
                    })
                end
                -- Defer full re-style to pick up text settings after frame is fully set up
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        ApplyCooldownViewerStyling(self)
                    end)
                end
            end)
        end
        frame._ScooterIconHooked = true
    end

    if self.id == "trackedBars" then
        local mode = self.db.displayMode or (self.settings.displayMode and self.settings.displayMode.default) or "both"
        local emVal = (mode == "icon") and 1 or (mode == "name" and 2 or 0)
        if frame.SetBarContent then pcall(frame.SetBarContent, frame, emVal) end
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        if width and height and child.SetSize and self.id ~= "trackedBars" then
            child:SetSize(width, height)
            -- Update any active proc glow animation to match the new icon dimensions
            if child.SpellActivationAlert then
                UpdateProcGlowSize(child)
            end
        end
        if self.id ~= "trackedBars" then
            if self.db.borderEnable then
                local styleKey = self.db.borderStyle or "square"
                if styleKey == "none" then
                    styleKey = "square"
                    self.db.borderStyle = styleKey
                end
                local thickness = tonumber(self.db.borderThickness) or 1
                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                local tintEnabled = self.db.borderTintEnable and type(self.db.borderTintColor) == "table"
                local tintColor
                if tintEnabled then
                    tintColor = {
                        self.db.borderTintColor[1] or 1,
                        self.db.borderTintColor[2] or 1,
                        self.db.borderTintColor[3] or 1,
                        self.db.borderTintColor[4] or 1,
                    }
                end
                addon.ApplyIconBorderStyle(child, styleKey, {
                    thickness = thickness,
                    color = tintColor,
                    tintEnabled = tintEnabled,
                    db = self.db,
                    thicknessKey = "borderThickness",
                    tintColorKey = "borderTintColor",
                    inset = self.db.borderInset or 0,
                    defaultThickness = self.settings and self.settings.borderThickness and self.settings.borderThickness.default or 1,
                })
            else
                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(child) end
            end
        elseif addon and addon.ApplyTrackedBarVisualsForChild then
            addon.ApplyTrackedBarVisualsForChild(self, child)
        end

        local defaultFace = (select(1, GameFontNormal:GetFont()))
        local function findFontStringOn(obj)
            if not obj then return nil end
            if obj.GetObjectType and obj:GetObjectType() == "FontString" then return obj end
            if obj.GetRegions then
                local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                for i = 1, n do
                    local r = select(i, obj:GetRegions())
                    if r and r.GetObjectType and r:GetObjectType() == "FontString" then return r end
                end
            end
            if obj.GetChildren then
                local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
                for i = 1, m do
                    local c = select(i, obj:GetChildren())
                    local found = findFontStringOn(c)
                    if found then return found end
                end
            end
            return nil
        end
        local function findFontStringByNameHint(root, hint)
            local target = nil
            local function scan(obj)
                if not obj or target then return end
                if obj.GetObjectType and obj:GetObjectType() == "FontString" then
                    local nm = obj.GetName and obj:GetName() or ""
                    if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                        target = obj; return
                    end
                end
                if obj.GetRegions then
                    local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                    for i = 1, n do
                        local r = select(i, obj:GetRegions())
                        if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                            local nm = r.GetName and r:GetName() or ""
                            if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                                target = r; return
                            end
                        end
                    end
                end
                if obj.GetChildren then
                    local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
                    for i = 1, m do
                        local c = select(i, obj:GetChildren())
                        scan(c)
                        if target then return end
                    end
                end
            end
            scan(root)
            return target
        end

        if self.id == "trackedBars" then
            local barFrame = child.GetBarFrame and child:GetBarFrame() or child.Bar or child
            local nameFS = (barFrame and barFrame.Name) or findFontStringByNameHint(barFrame or child, "Bar.Name") or findFontStringByNameHint(child, "Name")
            local durFS  = (barFrame and barFrame.Duration) or findFontStringByNameHint(barFrame or child, "Bar.Duration") or findFontStringByNameHint(child, "Duration")
            local iconFrame = (child.GetIconFrame and child:GetIconFrame()) or child.Icon

            if nameFS and nameFS.SetFont then
                local cfg = self.db.textName or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                pcall(nameFS.SetDrawLayer, nameFS, "OVERLAY", 10)
                if addon.ApplyFontStyle then addon.ApplyFontStyle(nameFS, face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") else nameFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") end
                local c = cfg.color or {1,1,1,1}
                if nameFS.SetTextColor then nameFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, "LEFT") end
                local ox = (cfg.offset and cfg.offset.x) or 0
                local oy = (cfg.offset and cfg.offset.y) or 0
                if (ox ~= 0 or oy ~= 0) and nameFS.ClearAllPoints and nameFS.SetPoint then
                    nameFS:ClearAllPoints()
                    local anchorTo = barFrame or child
                    nameFS:SetPoint("LEFT", anchorTo, "LEFT", ox, oy)
                end
            end

            if durFS and durFS.SetFont then
                local cfg = self.db.textDuration or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                pcall(durFS.SetDrawLayer, durFS, "OVERLAY", 10)
                if addon.ApplyFontStyle then addon.ApplyFontStyle(durFS, face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") else durFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") end
                local c = cfg.color or {1,1,1,1}
                if durFS.SetTextColor then durFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                if durFS.SetJustifyH then pcall(durFS.SetJustifyH, durFS, "RIGHT") end
                local ox = (cfg.offset and cfg.offset.x) or 0
                local oy = (cfg.offset and cfg.offset.y) or 0
                if (ox ~= 0 or oy ~= 0) and durFS.ClearAllPoints and durFS.SetPoint then
                    durFS:ClearAllPoints()
                    local anchorTo = barFrame or child
                    durFS:SetPoint("RIGHT", anchorTo, "RIGHT", ox, oy)
                end
            end

            local stacksFS
            if iconFrame and iconFrame.Applications then
                if iconFrame.Applications.GetObjectType and iconFrame.Applications:GetObjectType() == "FontString" then
                    stacksFS = iconFrame.Applications
                else
                    stacksFS = findFontStringOn(iconFrame.Applications)
                end
            end
            if not stacksFS and iconFrame then
                stacksFS = findFontStringByNameHint(iconFrame, "Applications")
            end
            if not stacksFS then
                stacksFS = findFontStringByNameHint(child, "Applications")
            end

            if stacksFS and stacksFS.SetFont then
                local cfg = self.db.textStacks or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                pcall(stacksFS.SetDrawLayer, stacksFS, "OVERLAY", 10)
                if addon.ApplyFontStyle then addon.ApplyFontStyle(stacksFS, face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") else stacksFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") end
                local c = cfg.color or {1,1,1,1}
                if stacksFS.SetTextColor then stacksFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                if stacksFS.SetJustifyH then pcall(stacksFS.SetJustifyH, stacksFS, "CENTER") end
                local ox = (cfg.offset and cfg.offset.x) or 0
                local oy = (cfg.offset and cfg.offset.y) or 0
                if stacksFS.ClearAllPoints and stacksFS.SetPoint then
                    stacksFS:ClearAllPoints()
                    local anchorTo = iconFrame or child
                    stacksFS:SetPoint("CENTER", anchorTo, "CENTER", ox, oy)
                end
            end
        else
            local cdFS = (child.Cooldown and findFontStringOn(child.Cooldown)) or findFontStringByNameHint(child, "Cooldown")
            local stacksFS = (child.ChargeCount and findFontStringOn(child.ChargeCount))
                or (child.Applications and findFontStringOn(child.Applications))
                or findFontStringByNameHint(child, "Applications")

            if stacksFS and stacksFS.SetFont then
                local cfg = self.db.textStacks or { size = 16, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                pcall(stacksFS.SetDrawLayer, stacksFS, "OVERLAY", 10)
                if addon.ApplyFontStyle then addon.ApplyFontStyle(stacksFS, face, tonumber(cfg.size) or 16, cfg.style or "OUTLINE") else stacksFS:SetFont(face, tonumber(cfg.size) or 16, cfg.style or "OUTLINE") end
                local c = cfg.color or {1,1,1,1}
                if stacksFS.SetTextColor then stacksFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                if stacksFS.ClearAllPoints and stacksFS.SetPoint then
                    stacksFS:ClearAllPoints()
                    local ox = (cfg.offset and cfg.offset.x) or 0
                    local oy = (cfg.offset and cfg.offset.y) or 0
                    stacksFS:SetPoint("CENTER", child, "CENTER", ox, oy)
                end
            end

            if cdFS and cdFS.SetFont then
                local cfg = self.db.textCooldown or { size = 16, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                pcall(cdFS.SetDrawLayer, cdFS, "OVERLAY", 10)
                if addon.ApplyFontStyle then addon.ApplyFontStyle(cdFS, face, tonumber(cfg.size) or 16, cfg.style or "OUTLINE") else cdFS:SetFont(face, tonumber(cfg.size) or 16, cfg.style or "OUTLINE") end
                local c = cfg.color or {1,1,1,1}
                if cdFS.SetTextColor then cdFS.SetTextColor(cdFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                if cdFS.ClearAllPoints and cdFS.SetPoint then
                    cdFS:ClearAllPoints()
                    local ox = (cfg.offset and cfg.offset.x) or 0
                    local oy = (cfg.offset and cfg.offset.y) or 0
                    cdFS:SetPoint("CENTER", child, "CENTER", ox, oy)
                end
            end
        end

        if self.id == "trackedBars" then
            local barFrame = child.GetBarFrame and child:GetBarFrame() or child.Bar
            local iconFrame = child.GetIconFrame and child:GetIconFrame() or child.Icon

            if barFrame and not child._ScootBordersActiveHooked then
                if child.SetIsActive then
                    hooksecurefunc(child, "SetIsActive", function(f, active)
                        if not active then
                            if component and component.db and component.db.hideWhenInactive and addon.Borders and addon.Borders.HideAll then
                                local bf = (f.GetBarFrame and f:GetBarFrame()) or f.Bar
                                if bf then addon.Borders.HideAll(bf) end
                                local ic = (f.GetIconFrame and f:GetIconFrame()) or f.Icon
                                if ic then
                                    addon.Borders.HideAll(ic)
                                    Util.ToggleDefaultIconOverlay(ic, true)
                                end
                            end
                        else
                            if C_Timer and C_Timer.After then
                                C_Timer.After(0, function()
                                    if addon and addon.ApplyTrackedBarVisualsForChild then addon.ApplyTrackedBarVisualsForChild(self, f) end
                                end)
                            elseif addon and addon.ApplyTrackedBarVisualsForChild then
                                addon.ApplyTrackedBarVisualsForChild(self, f)
                            end
                        end
                    end)
                end
                if child.OnActiveStateChanged then
                    hooksecurefunc(child, "OnActiveStateChanged", function(f)
                        local active = (f.IsActive and f:IsActive()) or f.isActive
                        if not active then
                            if component and component.db and component.db.hideWhenInactive and addon.Borders and addon.Borders.HideAll then
                                local bf = (f.GetBarFrame and f:GetBarFrame()) or f.Bar
                                if bf then addon.Borders.HideAll(bf) end
                                local ic = (f.GetIconFrame and f:GetIconFrame()) or f.Icon
                                if ic then
                                    addon.Borders.HideAll(ic)
                                    Util.ToggleDefaultIconOverlay(ic, true)
                                end
                            end
                        else
                            if C_Timer and C_Timer.After then
                                C_Timer.After(0, function()
                                    if addon and addon.ApplyTrackedBarVisualsForChild then addon.ApplyTrackedBarVisualsForChild(self, f) end
                                end)
                            elseif addon and addon.ApplyTrackedBarVisualsForChild then
                                addon.ApplyTrackedBarVisualsForChild(self, f)
                            end
                        end
                    end)
                end
                child._ScootBordersActiveHooked = true
            end

            if barFrame and iconFrame then
                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(child) end
                if addon and addon.ApplyTrackedBarVisualsForChild then addon.ApplyTrackedBarVisualsForChild(self, child) end
            end
        end
    end

    do
        local ic = (frame.GetItemContainerFrame and frame:GetItemContainerFrame()) or frame
        if ic and spacing ~= nil then
            if ic.childXPadding ~= nil then ic.childXPadding = spacing end
            if ic.childYPadding ~= nil then ic.childYPadding = spacing end
            if ic.iconPadding ~= nil then ic.iconPadding = spacing end
            if type(ic.MarkDirty) == "function" then pcall(ic.MarkDirty, ic) end
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

    do
        local mode = self.db.visibilityMode or (self.settings.visibilityMode and self.settings.visibilityMode.default) or "always"
        local wantShown
        if mode == "never" then wantShown = false
        elseif mode == "combat" then wantShown = (type(UnitAffectingCombat) == "function") and UnitAffectingCombat("player") or false
        else wantShown = true end
        local wasShown = frame:IsShown() and true or false
        if frame.SetShown then pcall(frame.SetShown, frame, wantShown) end
        if wasShown and not wantShown then
            for _, child in ipairs({ frame:GetChildren() }) do
                local barFrame = child.GetBarFrame and child:GetBarFrame() or child.Bar
                if barFrame and addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(barFrame) end
            end
        end
    end

    do
        local baseRaw = self.db and self.db.opacity or (self.settings.opacity and self.settings.opacity.default) or 100
        local baseOpacity = Util.ClampOpacity(baseRaw, 50)
        local oocRaw = self.db and self.db.opacityOutOfCombat
        if oocRaw == nil and self.settings and self.settings.opacityOutOfCombat then
            oocRaw = self.settings.opacityOutOfCombat.default
        end
        local oocOpacity = Util.ClampOpacity(oocRaw or baseOpacity, 1)
        local tgtRaw = self.db and self.db.opacityWithTarget
        if tgtRaw == nil and self.settings and self.settings.opacityWithTarget then
            tgtRaw = self.settings.opacityWithTarget.default
        end
        local tgtOpacity = Util.ClampOpacity(tgtRaw or baseOpacity, 1)
        local hasTarget = (UnitExists and UnitExists("target")) and true or false
        local applied = hasTarget and tgtOpacity or (Util.PlayerInCombat() and baseOpacity or oocOpacity)
        if frame.SetAlpha then pcall(frame.SetAlpha, frame, applied / 100) end
    end
end

addon:RegisterComponentInitializer(function(self)
    local essentialCooldowns = Component:New({
        id = "essentialCooldowns",
        name = "Essential Cooldowns",
        frameName = "EssentialCooldownViewer",
        settings = {
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
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            iconWidth = { type = "addon", default = 50, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 2
            }},
            iconHeight = { type = "addon", default = 50, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 3
            }},
            borderEnable = { type = "addon", default = false, ui = {
                label = "Use Custom Border", widget = "checkbox", section = "Border", order = 1, tooltip = ""
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 4,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.2, section = "Border", order = 5
            }},
            borderInset = { type = "addon", default = 0, ui = {
                label = "Border Inset", widget = "slider", min = -4, max = 4, step = 1, section = "Border", order = 6
            }},
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            opacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 4
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 5
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 6
            }},
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(essentialCooldowns)

    local utilityCooldowns = Component:New({
        id = "utilityCooldowns",
        name = "Utility Cooldowns",
        frameName = "UtilityCooldownViewer",
        settings = {
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
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            iconWidth = { type = "addon", default = 44, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 2
            }},
            iconHeight = { type = "addon", default = 44, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 3
            }},
            borderEnable = { type = "addon", default = false, ui = {
                label = "Use Custom Border", widget = "checkbox", section = "Border", order = 1, tooltip = ""
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 4,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.2, section = "Border", order = 5
            }},
            borderInset = { type = "addon", default = 0, ui = {
                label = "Border Inset", widget = "slider", min = -4, max = 4, step = 1, section = "Border", order = 6
            }},
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            opacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 4
            }},
            hideWhenInactive = { type = "editmode", default = false, ui = {
                label = "Hide when inactive", widget = "checkbox", section = "Misc", order = 5
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 6
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 7
            }},
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(utilityCooldowns)

    local trackedBuffs = Component:New({
        id = "trackedBuffs",
        name = "Tracked Buffs",
        frameName = "BuffIconCooldownViewer",
        settings = {
            orientation = { type = "editmode", settingId = 0, default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            direction = { type = "editmode", settingId = 2, default = "right", ui = {
                label = "Icon Direction", widget = "dropdown", values = { left = "Left", right = "Right", up = "Up", down = "Down" }, section = "Positioning", order = 2, dynamicValues = true
            }},
            iconPadding = { type = "editmode", settingId = 4, default = 2, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 3
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 4
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 5
            }},
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            iconWidth = { type = "addon", default = 44, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 2
            }},
            iconHeight = { type = "addon", default = 44, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 3
            }},
            borderEnable = { type = "addon", default = false, ui = {
                label = "Use Custom Border", widget = "checkbox", section = "Border", order = 1, tooltip = ""
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 4,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.2, section = "Border", order = 5
            }},
            borderInset = { type = "addon", default = 0, ui = {
                label = "Border Inset", widget = "slider", min = -4, max = 4, step = 1, section = "Border", order = 6
            }},
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            opacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 4
            }},
            hideWhenInactive = { type = "editmode", default = false, ui = {
                label = "Hide when inactive", widget = "checkbox", section = "Misc", order = 5
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 6
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 7
            }},
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(trackedBuffs)

    local trackedBars = Component:New({
        id = "trackedBars",
        name = "Tracked Bars",
        frameName = "BuffBarCooldownViewer",
        settings = {
            iconPadding = { type = "editmode", settingId = 4, default = 3, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 1
            }},
            iconBarPadding = { type = "addon", default = 0, ui = {
                label = "Icon/Bar Padding", widget = "slider", min = -20, max = 80, step = 1, section = "Positioning", order = 2
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 3
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 4
            }},
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            barWidth = { type = "addon", default = 220, ui = {
                label = "Bar Width", widget = "slider", min = 120, max = 480, step = 2, section = "Sizing", order = 2
            }},
            styleEnableCustom = { type = "addon", default = true, ui = {
                label = "Enable Custom Textures", widget = "checkbox", section = "Style", order = 0
            }},
            styleForegroundTexture = { type = "addon", default = "bevelled", ui = {
                label = "Foreground Texture", widget = "dropdown", section = "Style", order = 1, optionsProvider = function()
                    if addon.BuildBarTextureOptionsContainer then return addon.BuildBarTextureOptionsContainer() end
                    local c = Settings.CreateControlTextContainer(); c:Add("bevelled", "Bevelled"); return c:GetData()
                end
            }},
            styleBackgroundTexture = { type = "addon", default = "bevelled", ui = {
                label = "Background Texture", widget = "dropdown", section = "Style", order = 2, optionsProvider = function()
                    if addon.BuildBarTextureOptionsContainer then return addon.BuildBarTextureOptionsContainer() end
                    local c = Settings.CreateControlTextContainer(); c:Add("bevelledGrey", "Bevelled Grey"); return c:GetData()
                end
            }},
            styleForegroundColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Foreground Color", widget = "color", section = "Style", order = 3
            }},
            styleBackgroundColor = { type = "addon", default = {1,1,1,0.9}, ui = {
                label = "Background Color", widget = "color", section = "Style", order = 4
            }},
            styleBackgroundOpacity = { type = "addon", default = 50, ui = {
                label = "Background Opacity", widget = "slider", min = 0, max = 100, step = 1, section = "Style", order = 5
            }},
            borderEnable = { type = "addon", default = false, ui = {
                label = "Use Custom Border", widget = "checkbox", section = "Border", order = 1
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 4,
                optionsProvider = function()
                    if addon.BuildBarBorderOptionsContainer then
                        return addon.BuildBarBorderOptionsContainer()
                    end
                    return {}
                end,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.2, section = "Border", order = 5
            }},
            iconWidth = { type = "addon", default = 30, ui = {
                label = "Icon Width", widget = "slider", min = 8, max = 32, step = 1, section = "Icon", order = 1
            }},
            iconHeight = { type = "addon", default = 30, ui = {
                label = "Icon Height", widget = "slider", min = 8, max = 32, step = 1, section = "Icon", order = 2
            }},
            iconBorderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Icon", order = 3
            }},
            iconBorderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Icon", order = 4
            }},
            iconBorderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Icon", order = 5
            }},
            iconBorderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Icon", order = 6,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end
            }},
            iconBorderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.2, section = "Icon", order = 7
            }},
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            opacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 4
            }},
            displayMode = { type = "editmode", default = "both", ui = {
                label = "Display Mode", widget = "dropdown", values = { both = "Icon & Name", icon = "Icon Only", name = "Name Only" }, section = "Misc", order = 5
            }},
            hideWhenInactive = { type = "editmode", default = false, ui = {
                label = "Hide when inactive", widget = "checkbox", section = "Misc", order = 6
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 7
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 8
            }},
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(trackedBars)
end)

