local addonName, addon = ...

addon.Components = {}

local Component = {}

local function HideDefaultBarTextures(barFrame, restore)
    if not barFrame or not barFrame.GetRegions then return end
    local function matchesDefaultTexture(region)
        if not region or not region.GetObjectType or region:GetObjectType() ~= "Texture" then return false end
        local tex = region.GetTexture and region:GetTexture()
        if type(tex) == "string" and tex:find("UI%-HUD%-CoolDownManager") then
            return true
        end
        if region.GetAtlas then
            local atlas = region:GetAtlas()
            if type(atlas) == "string" and atlas:find("UI%-HUD%-CoolDownManager") then
                return true
            end
        end
        return false
    end
    for _, region in ipairs({ barFrame:GetRegions() }) do
        if region and region ~= barFrame.ScooterModBG and region ~= barFrame.ScooterStyledBorder and region ~= (barFrame.ScooterStyledBorder and barFrame.ScooterStyledBorder.Texture) then
            if region.GetObjectType and region:GetObjectType() == "Texture" then
                local layer = region:GetDrawLayer()
                if layer == "OVERLAY" or layer == "ARTWORK" or layer == "BORDER" then
                    if matchesDefaultTexture(region) then
                        region:SetAlpha(restore and 1 or 0)
                    end
                end
            end
        end
    end
end

local function ToggleDefaultIconOverlay(iconFrame, restore)
    if not iconFrame or not iconFrame.GetRegions then return end
    for _, region in ipairs({ iconFrame:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            if region.GetAtlas and region:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
                region:SetAlpha(restore and 1 or 0)
            end
        end
    end
end

local function PlayerInCombat()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return true
    end
    if type(UnitAffectingCombat) == "function" then
        local inCombat = UnitAffectingCombat("player")
        if inCombat then return true end
    end
    return false
end

local function ClampOpacity(value, minValue)
    local v = tonumber(value) or 100
    local minClamp = tonumber(minValue) or 50
    if v < minClamp then
        v = minClamp
    elseif v > 100 then
        v = 100
    end
    return v
end

function addon.ApplyIconBorderStyle(frame, styleKey, opts)
    if not frame then return "none" end

    local key = styleKey or "square"

    local styleDef = addon.IconBorders and addon.IconBorders.GetStyle(key)
    local tintEnabled = opts and opts.tintEnabled
    local requestedColor = opts and opts.color
    local dbTable = opts and opts.db
    local thicknessKey = opts and opts.thicknessKey
    local tintColorKey = opts and opts.tintColorKey
    local defaultThicknessSetting = opts and opts.defaultThickness or 1
    local thickness = tonumber(opts and opts.thickness) or defaultThicknessSetting
    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

    if not styleDef then
        if addon.Borders and addon.Borders.ApplySquare then
            addon.Borders.ApplySquare(frame, {
                size = thickness,
                color = tintEnabled and requestedColor or {0, 0, 0, 1},
                layer = "OVERLAY",
                layerSublevel = 7,
            })
        end
        return "square"
    end

    if styleDef.type == "none" then
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
        return "none"
    end

    if styleDef.allowThicknessInset and dbTable and thicknessKey then
        local stored = tonumber(dbTable[thicknessKey])
        if stored then
            thickness = stored
        end
        if styleDef.defaultThickness and styleDef.defaultThickness ~= defaultThicknessSetting then
            if not stored or stored == defaultThicknessSetting then
                thickness = styleDef.defaultThickness
                dbTable[thicknessKey] = thickness
            end
        end
    elseif dbTable and thicknessKey then
        dbTable[thicknessKey] = thickness
    end

    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

    if dbTable and thicknessKey then
        dbTable[thicknessKey] = thickness
    end

    local function copyColor(color)
        if type(color) ~= "table" then
            return {1, 1, 1, 1}
        end
        return { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
    end

    local defaultColor = copyColor(styleDef.defaultColor or (styleDef.type == "square" and {0, 0, 0, 1}) or {1, 1, 1, 1})
    if type(requestedColor) ~= "table" then
        if dbTable and tintColorKey and type(dbTable[tintColorKey]) == "table" then
            requestedColor = dbTable[tintColorKey]
        else
            requestedColor = defaultColor
        end
    end

    local baseColor = copyColor(defaultColor)
    local tintColor = copyColor(requestedColor)
    local baseApplyColor = copyColor(baseColor)
    if styleDef.type == "square" then
        baseApplyColor = tintEnabled and tintColor or baseColor
    end

    local function clamp(val, min, max)
        if val < min then return min end
        if val > max then return max end
        return val
    end

    local baseExpandX = styleDef.expandX or 0
    local baseExpandY = styleDef.expandY or baseExpandX
    local insetAdjust = 0
    if styleDef.allowThicknessInset then
        local step = styleDef.insetStep or 0.2
        local centre = styleDef.insetCenter or (styleDef.defaultThickness or 1)
        local defaultThickness = styleDef.defaultThickness or 1
        insetAdjust = (thickness - centre) * step
        local defaultAdjust = (defaultThickness - centre) * step
        insetAdjust = insetAdjust - defaultAdjust
    end
    local expandX = clamp(baseExpandX + insetAdjust, -8, 8)
    local expandY = clamp(baseExpandY + insetAdjust, -8, 8)

    local appliedTexture

    if styleDef.type == "atlas" then
        addon.Borders.ApplyAtlas(frame, {
            atlas = styleDef.atlas,
            color = baseApplyColor,
            tintColor = baseApplyColor,
            expandX = expandX,
            expandY = expandY,
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
        })
        appliedTexture = frame.ScootAtlasBorder
    elseif styleDef.type == "texture" then
        addon.Borders.ApplyTexture(frame, {
            texture = styleDef.texture,
            color = baseApplyColor,
            tintColor = baseApplyColor,
            expandX = expandX,
            expandY = expandY,
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
        })
        appliedTexture = frame.ScootTextureBorder
    else
        addon.Borders.ApplySquare(frame, {
            size = thickness,
            color = baseApplyColor or {0, 0, 0, 1},
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
        })
        local container = frame.ScootSquareBorderContainer or frame
        local edges = (container and container.ScootSquareBorderEdges) or frame.ScootSquareBorderEdges
        if edges then
            for _, edge in pairs(edges) do
                if edge and edge.SetColorTexture then
                    edge:SetColorTexture(baseApplyColor[1] or 0, baseApplyColor[2] or 0, baseApplyColor[3] or 0, (baseApplyColor[4] == nil and 1) or baseApplyColor[4])
                end
            end
        end
        if frame.ScootAtlasBorderTintOverlay then frame.ScootAtlasBorderTintOverlay:Hide() end
        if frame.ScootTextureBorderTintOverlay then frame.ScootTextureBorderTintOverlay:Hide() end
    end

    if appliedTexture then
        if styleDef.type == "square" and baseApplyColor then
            appliedTexture:SetVertexColor(baseApplyColor[1] or 0, baseApplyColor[2] or 0, baseApplyColor[3] or 0, baseApplyColor[4] or 1)
        else
            appliedTexture:SetVertexColor(baseColor[1] or 1, baseColor[2] or 1, baseColor[3] or 1, baseColor[4] or 1)
        end
        appliedTexture:SetAlpha(baseColor[4] or 1)
        if appliedTexture.SetDesaturated then pcall(appliedTexture.SetDesaturated, appliedTexture, false) end
        if appliedTexture.SetBlendMode then pcall(appliedTexture.SetBlendMode, appliedTexture, styleDef.baseBlendMode or styleDef.layerBlendMode or "BLEND") end

        local overlay
        if styleDef.type == "atlas" then
            overlay = frame.ScootAtlasBorderTintOverlay
        elseif styleDef.type == "texture" then
            overlay = frame.ScootTextureBorderTintOverlay
        end

        local function clampSublevel(val)
            if val == nil then return nil end
            if val > 7 then return 7 end
            if val < -8 then return -8 end
            return val
        end

        local function ensureOverlay()
            if overlay and overlay:IsObjectType("Texture") then return overlay end
            local layer, sublevel = appliedTexture:GetDrawLayer()
            layer = layer or (styleDef.layer or "OVERLAY")
            sublevel = clampSublevel((sublevel or (styleDef.layerSublevel or 7)) + 1) or clampSublevel((styleDef.layerSublevel or 7))
            local tex = frame:CreateTexture(nil, layer)
            tex:SetDrawLayer(layer, sublevel or 0)
            tex:SetAllPoints(appliedTexture)
            tex:SetVertexColor(1, 1, 1, 1)
            tex:Hide()
            if styleDef.type == "atlas" then
                frame.ScootAtlasBorderTintOverlay = tex
            else
                frame.ScootTextureBorderTintOverlay = tex
            end
            return tex
        end

        if tintEnabled then
            -- Tint approach:
            --  - Render the SAME border art (atlas/texture) on a separate overlay and vertex-tint it.
            --  - Earlier attempts used ALPHAKEY and then a mask+solid fill; ALPHAKEY produced a white "cross"
            --    artifact on some assets and mask+fill drew a full-rect overlay because normal atlases aren't
            --    valid masks. This approach keeps the source shape and makes white visible without artifacts.
            overlay = ensureOverlay()
            local layer, sublevel = appliedTexture:GetDrawLayer()
            local desiredSub = clampSublevel((sublevel or 0) + 1)
            if layer then overlay:SetDrawLayer(layer, desiredSub or clampSublevel(sublevel) or 0) end
            overlay:ClearAllPoints()
            overlay:SetAllPoints(appliedTexture)
            -- Revert to rendering the same border art on the overlay, tinted and blended
            local r = tintColor[1] or 1
            local g = tintColor[2] or 1
            local b = tintColor[3] or 1
            local a = tintColor[4] or 1
            if styleDef.type == "atlas" and styleDef.atlas then
                overlay:SetAtlas(styleDef.atlas, true)
            elseif styleDef.type == "texture" and styleDef.texture then
                overlay:SetTexture(styleDef.texture)
            end
            -- Choose a blend mode that keeps colors vivid and makes white visible
            local avg = (r + g + b) / 3
            local blend = styleDef.tintBlendMode or ((avg >= 0.85) and "ADD" or "BLEND")
            if overlay.SetBlendMode then pcall(overlay.SetBlendMode, overlay, blend) end
            -- For near-white, push a tiny bit above grey by desaturating first
            if overlay.SetDesaturated then pcall(overlay.SetDesaturated, overlay, (avg >= 0.85)) end
            overlay:SetVertexColor(r, g, b, a)
            overlay:SetAlpha(a)
            overlay:Show()
            appliedTexture:SetAlpha(0)
        else
            -- Reset approach when tint is disabled:
            --  - Overlays can remain attached due to Settings list recycling, so hide+clear both overlays.
            --  - Then aggressively drop all ScooterMod border textures and re-apply the base style art.
            --    This guarantees the stock/default colors return immediately and persist across reloads.
            -- Ensure both possible overlay textures are fully hidden and cleared to avoid lingering tints
            local overlays = {
                frame.ScootAtlasBorderTintOverlay,
                frame.ScootTextureBorderTintOverlay,
            }
            for _, ov in ipairs(overlays) do
                if ov then
                    ov:Hide()
                    if ov.SetTexture then pcall(ov.SetTexture, ov, nil) end
                    if ov.SetAtlas then pcall(ov.SetAtlas, ov, nil) end
                    if ov.SetVertexColor then pcall(ov.SetVertexColor, ov, 1, 1, 1, 0) end
                    if ov.SetBlendMode then pcall(ov.SetBlendMode, ov, styleDef.baseBlendMode or styleDef.layerBlendMode or "BLEND") end
                end
            end

            -- Aggressive reset: fully clear any custom border textures and rebuild the base art fresh
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end

            if styleDef.type == "atlas" and styleDef.atlas then
                addon.Borders.ApplyAtlas(frame, {
                    atlas = styleDef.atlas,
                    color = baseColor,
                    tintColor = baseColor,
                    expandX = expandX,
                    expandY = expandY,
                    layer = styleDef.layer or "OVERLAY",
                    layerSublevel = styleDef.layerSublevel or 7,
                })
                appliedTexture = frame.ScootAtlasBorder
            elseif styleDef.type == "texture" and styleDef.texture then
                addon.Borders.ApplyTexture(frame, {
                    texture = styleDef.texture,
                    color = baseColor,
                    tintColor = baseColor,
                    expandX = expandX,
                    expandY = expandY,
                    layer = styleDef.layer or "OVERLAY",
                    layerSublevel = styleDef.layerSublevel or 7,
                })
                appliedTexture = frame.ScootTextureBorder
            else
                addon.Borders.ApplySquare(frame, {
                    size = thickness,
                    color = baseColor or {0, 0, 0, 1},
                    layer = styleDef.layer or "OVERLAY",
                    layerSublevel = styleDef.layerSublevel or 7,
                })
            end

            if appliedTexture then
                appliedTexture:SetAlpha(baseColor[4] or 1)
                if appliedTexture.SetDesaturated then pcall(appliedTexture.SetDesaturated, appliedTexture, false) end
                if appliedTexture.SetBlendMode then pcall(appliedTexture.SetBlendMode, appliedTexture, styleDef.baseBlendMode or styleDef.layerBlendMode or "BLEND") end
                appliedTexture:SetVertexColor(baseColor[1] or 1, baseColor[2] or 1, baseColor[3] or 1, baseColor[4] or 1)
            end
        end
    end

    return styleDef.type
end

-- Public helper: apply Tracked Bar visuals to a single item frame (icon/bar gap, bar width, textures)
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

    -- Apply icon sizing overrides before measuring spacing
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
        -- Ensure contained texture/mask follow the resized frame
        local tex = iconFrame.Icon or (child.GetIconTexture and child:GetIconTexture())
        if tex and tex.SetAllPoints then tex:SetAllPoints(iconFrame) end
        local mask = iconFrame.Mask or iconFrame.IconMask
        if mask and mask.SetAllPoints then mask:SetAllPoints(iconFrame) end
    end

    local isActive = (child.IsActive and child:IsActive()) or child.isActive

    -- Compute desired gap between icon and bar, and optional width override
    local desiredPad = tonumber(component.db and component.db.iconBarPadding) or (component.settings.iconBarPadding and component.settings.iconBarPadding.default) or 0
    desiredPad = tonumber(desiredPad) or 0
    local desiredWidthOverride = tonumber(component.db and component.db.barWidth)

    -- Measure current state
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

    -- Re-anchor bar: keep RIGHT anchored, adjust by pad+width delta
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
        -- LEFT anchor depends on display mode: if icon is hidden (Name Only), anchor to the item itself
        local anchorLeftTo, anchorLeftPoint, anchorLeftRelPoint = iconFrame, "RIGHT", "RIGHT"
        if iconFrame.IsShown and not iconFrame:IsShown() then
            anchorLeftTo, anchorLeftPoint, anchorLeftRelPoint = child, "LEFT", "LEFT"
        end
        barFrame:SetPoint("LEFT", anchorLeftTo, anchorLeftPoint, desiredPad, 0)
    end

    -- Apply ScooterMod bar textures and tints if enabled
    if addon.Media and addon.Media.ApplyBarTexturesToBarFrame then
        local useCustom = (component.db and component.db.styleEnableCustom) ~= false
        if useCustom then
            local fg = component.db and component.db.styleForegroundTexture or (component.settings.styleForegroundTexture and component.settings.styleForegroundTexture.default)
            local bg = component.db and component.db.styleBackgroundTexture or (component.settings.styleBackgroundTexture and component.settings.styleBackgroundTexture.default)
            addon.Media.ApplyBarTexturesToBarFrame(barFrame, fg, bg)
            local fgCol = (component.db and component.db.styleForegroundColor) or {1,1,1,1}
            local tex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
            if tex and tex.SetVertexColor then pcall(tex.SetVertexColor, tex, fgCol[1] or 1, fgCol[2] or 1, fgCol[3] or 1, fgCol[4] or 1) end
            local bgCol = (component.db and component.db.styleBackgroundColor) or {1,1,1,0.9}
            if barFrame.ScooterModBG and barFrame.ScooterModBG.SetVertexColor then
                pcall(barFrame.ScooterModBG.SetVertexColor, barFrame.ScooterModBG, bgCol[1] or 1, bgCol[2] or 1, bgCol[3] or 1, bgCol[4] or 1)
            end
        else
            -- Revert to Blizzard defaults
            if barFrame.ScooterModBG then barFrame.ScooterModBG:Hide() end
            local tex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
            if tex and tex.SetAtlas then pcall(tex.SetAtlas, tex, "UI-HUD-CoolDownManager-Bar", true) end
            if barFrame.SetStatusBarAtlas then pcall(barFrame.SetStatusBarAtlas, barFrame, "UI-HUD-CoolDownManager-Bar") end
            if tex then
                if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, 1.0, 0.5, 0.25, 1.0) end
                if tex.SetAlpha then pcall(tex.SetAlpha, tex, 1.0) end
                if tex.SetTexCoord then pcall(tex.SetTexCoord, tex, 0, 1, 0, 1) end
            end
            -- Restore stock background/overlay alphas
            for _, region in ipairs({ barFrame:GetRegions() }) do
                if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                    pcall(region.SetAlpha, region, 1.0)
                end
            end
            HideDefaultBarTextures(barFrame, true)
        end
    end

    -- Apply or hide bar border (uses a high strata container to sit above the bar fill)
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
            HideDefaultBarTextures(barFrame)
        else
            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(barFrame) end
            if addon.Borders and addon.Borders.ApplySquare then
                addon.Borders.ApplySquare(barFrame, {
                    size = thickness,
                    color = color,
                    layer = "OVERLAY",
                    layerSublevel = 7,
                    containerStrata = "TOOLTIP",
                    levelOffset = 1000,
                    containerParent = barFrame,
                    expandX = 1,
                    expandY = 2,
                })
            end
            HideDefaultBarTextures(barFrame, true)
        end
    else
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(barFrame) end
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(barFrame) end
        HideDefaultBarTextures(barFrame, true)
    end

    -- Icon border styling (independent from bar border)
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
        ToggleDefaultIconOverlay(iconFrame, false)
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
        ToggleDefaultIconOverlay(iconFrame, true)
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

-- Shared styling for Cooldown Viewer-style components (icons, borders, text, padding, visibility, opacity)
local function ApplyCooldownViewerStyling(self)
    local frame = _G[self.frameName]
    if not frame then return end

    local width = self.db.iconWidth or (self.settings.iconWidth and self.settings.iconWidth.default)
    local height = self.db.iconHeight or (self.settings.iconHeight and self.settings.iconHeight.default)
    local spacing = self.db.iconPadding or (self.settings.iconPadding and self.settings.iconPadding.default)

    -- For Tracked Bars, hook viewer lifecycle once so new/relayout items also get styled immediately (handles "always on" buffs on reload)
    if self.id == "trackedBars" and not frame._ScooterTBHooked then
        if hooksecurefunc then
            -- When the viewer acquires an item, apply visuals to that child right away
            if frame.OnAcquireItemFrame then
                hooksecurefunc(frame, "OnAcquireItemFrame", function(viewer, itemFrame)
                    if addon and addon.ApplyTrackedBarVisualsForChild then addon.ApplyTrackedBarVisualsForChild(self, itemFrame) end
                end)
            end
            -- After a relayout, apply visuals to all current children
            if frame.RefreshLayout then
                hooksecurefunc(frame, "RefreshLayout", function()
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

    -- Tracked Bars: also set display mode at the viewer level so icon/name visibility updates immediately
    if self.id == "trackedBars" then
        local mode = self.db.displayMode or (self.settings.displayMode and self.settings.displayMode.default) or "both"
        local emVal = (mode == "icon") and 1 or (mode == "name" and 2 or 0)
        if frame.SetBarContent then pcall(frame.SetBarContent, frame, emVal) end
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        if width and height and child.SetSize and self.id ~= "trackedBars" then child:SetSize(width, height) end
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
                    defaultThickness = self.settings and self.settings.borderThickness and self.settings.borderThickness.default or 1,
                })
            else
                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(child) end
            end
        elseif addon and addon.ApplyTrackedBarVisualsForChild then
            addon.ApplyTrackedBarVisualsForChild(self, child)
        end

        -- Text styling (Charges/Cooldowns for icon viewers; Name/Duration for bar viewers)
        do
            local defaultFace = (select(1, GameFontNormal:GetFont()))
            local function findFontStringOn(obj)
                if not obj then return nil end
                if obj.GetObjectType and obj:GetObjectType() == "FontString" then return obj end
                if obj.GetRegions then
                    local n = (obj.GetNumRegions and obj.GetNumRegions(obj)) or 0
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
                -- Bars: style Name and Duration font strings
                local barFrame = child.GetBarFrame and child:GetBarFrame() or child.Bar or child
                local nameFS = (barFrame and barFrame.Name) or findFontStringByNameHint(barFrame or child, "Bar.Name") or findFontStringByNameHint(child, "Name")
                local durFS  = (barFrame and barFrame.Duration) or findFontStringByNameHint(barFrame or child, "Bar.Duration") or findFontStringByNameHint(child, "Duration")

                if nameFS and nameFS.SetFont then
                    local cfg = self.db.textName or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                    local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                    pcall(nameFS.SetDrawLayer, nameFS, "OVERLAY", 10)
                    nameFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE")
                    local c = cfg.color or {1,1,1,1}
                    if nameFS.SetTextColor then nameFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                    if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, "LEFT") end
                    local ox = (cfg.offset and cfg.offset.x) or 0
                    local oy = (cfg.offset and cfg.offset.y) or 0
                    -- Only override positioning when a non-zero offset is requested; preserve stock anchors at 0,0
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
                    durFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE")
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
            else
                -- Icon viewers: style stacks/applications and cooldown
                local cdFS = (child.Cooldown and findFontStringOn(child.Cooldown)) or findFontStringByNameHint(child, "Cooldown")
                local stacksFS = (child.ChargeCount and findFontStringOn(child.ChargeCount))
                    or (child.Applications and findFontStringOn(child.Applications))
                    or findFontStringByNameHint(child, "Applications")

                if stacksFS and stacksFS.SetFont then
                    local cfg = self.db.textStacks or { size = 16, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                    local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                    pcall(stacksFS.SetDrawLayer, stacksFS, "OVERLAY", 10)
                    stacksFS:SetFont(face, tonumber(cfg.size) or 16, cfg.style or "OUTLINE")
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
                    cdFS:SetFont(face, tonumber(cfg.size) or 16, cfg.style or "OUTLINE")
                    local c = cfg.color or {1,1,1,1}
                    if cdFS.SetTextColor then cdFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                    if cdFS.ClearAllPoints and cdFS.SetPoint then
                        cdFS:ClearAllPoints()
                        local ox = (cfg.offset and cfg.offset.x) or 0
                        local oy = (cfg.offset and cfg.offset.y) or 0
                        cdFS:SetPoint("CENTER", child, "CENTER", ox, oy)
                    end
                end
            end
        end

        -- Tracked Bars: apply exploratory sizing/spacing (bar width and icon/bar padding)
        if self.id == "trackedBars" then
            local barFrame = child.GetBarFrame and child:GetBarFrame() or child.Bar
            local iconFrame = child.GetIconFrame and child:GetIconFrame() or child.Icon

            -- Hook active-state changes so borders respond immediately to active transitions
            if barFrame and not child._ScootBordersActiveHooked then
                if child.SetIsActive then
                    hooksecurefunc(child, "SetIsActive", function(f, active)
                        if not active then
                            -- Only hide borders on deactivate when user wants bars hidden while inactive
                            if component and component.db and component.db.hideWhenInactive and addon.Borders and addon.Borders.HideAll then
                                local bf = (f.GetBarFrame and f:GetBarFrame()) or f.Bar
                                if bf then addon.Borders.HideAll(bf) end
                                local ic = (f.GetIconFrame and f:GetIconFrame()) or f.Icon
                                if ic then
                                    addon.Borders.HideAll(ic)
                                    ToggleDefaultIconOverlay(ic, true)
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
                        local isActive = (f.IsActive and f:IsActive()) or f.isActive
                        if not isActive then
                            if component and component.db and component.db.hideWhenInactive and addon.Borders and addon.Borders.HideAll then
                                local bf = (f.GetBarFrame and f:GetBarFrame()) or f.Bar
                                if bf then addon.Borders.HideAll(bf) end
                                local ic = (f.GetIconFrame and f:GetIconFrame()) or f.Icon
                                if ic then
                                    addon.Borders.HideAll(ic)
                                    ToggleDefaultIconOverlay(ic, true)
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
                -- Ensure any legacy item-level borders are hidden so only the bar border is shown
                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(child) end
                -- Delegate to shared helper so we can also call it from viewer hooks
                if addon and addon.ApplyTrackedBarVisualsForChild then addon.ApplyTrackedBarVisualsForChild(self, child) end
            end
        end
    end

    -- Padding adjustments on the item container
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

    -- Visibility (mode only) with border cleanup when viewer hides
    do
        local mode = self.db.visibilityMode or (self.settings.visibilityMode and self.settings.visibilityMode.default) or "always"
        local wantShown
        if mode == "never" then wantShown = false
        elseif mode == "combat" then wantShown = (type(UnitAffectingCombat) == "function") and UnitAffectingCombat("player") or false
        else wantShown = true end
        local wasShown = frame:IsShown() and true or false
        if frame.SetShown then pcall(frame.SetShown, frame, wantShown) end
        -- If we just hid the viewer, proactively hide any lingering bar borders
        if wasShown and not wantShown then
            for _, child in ipairs({ frame:GetChildren() }) do
                local barFrame = child.GetBarFrame and child:GetBarFrame() or child.Bar
                if barFrame and addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(barFrame) end
            end
        end
    end

    -- Opacity immediate local visual update
    do
        local baseRaw = self.db and self.db.opacity or (self.settings.opacity and self.settings.opacity.default) or 100
        local baseOpacity = ClampOpacity(baseRaw, 50)
        local overrideRaw = self.db and self.db.opacityOutOfCombat
        if overrideRaw == nil and self.settings and self.settings.opacityOutOfCombat then
            overrideRaw = self.settings.opacityOutOfCombat.default
        end
        local overrideOpacity = ClampOpacity(overrideRaw or baseOpacity, 1)
        local applied = PlayerInCombat() and baseOpacity or overrideOpacity
        if frame.SetAlpha then pcall(frame.SetAlpha, frame, applied / 100) end
    end
end

function Component:New(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Component:SyncEditModeSettings()
    local frame = _G[self.frameName]
    if not frame then return end

    local changed = false
    for settingId, setting in pairs(self.settings) do
        if setting.type == "editmode" then
            if addon.EditMode.SyncEditModeSettingToComponent(self, settingId) then
                changed = true
            end
        end
    end

    return changed
end

function addon:RegisterComponent(component)
    self.Components[component.id] = component
end

function addon:InitializeComponents()
    local essentialCooldowns = Component:New({
        id = "essentialCooldowns",
        name = "Essential Cooldowns",
        frameName = "EssentialCooldownViewer",
        settings = {
            -- Positioning
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
            -- Sizing
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            iconWidth = { type = "addon", default = 50, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 2
            }},
            iconHeight = { type = "addon", default = 50, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 3
            }},
            -- Border
            borderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Border", order = 1, tooltip = ""
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
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Border", order = 5
            }},
            -- Visibility (Edit Mode synced)
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 4
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 5
            }},
            -- Marker: enable Text section in settings UI for this component
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
            -- Positioning
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
            -- Sizing (Utility defaults slightly smaller: keep same ranges; visual default can reuse Essential's 100)
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            iconWidth = { type = "addon", default = 44, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 2
            }},
            iconHeight = { type = "addon", default = 44, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 3
            }},
            -- Border
            borderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Border", order = 1, tooltip = ""
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
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Border", order = 5
            }},
            -- Visibility / Misc
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 4
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 5
            }},
            -- Marker: enable Text section in settings UI for this component
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
            -- Positioning
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
            -- Sizing
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            iconWidth = { type = "addon", default = 44, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 2
            }},
            iconHeight = { type = "addon", default = 44, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 3
            }},
            -- Border
            borderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Border", order = 1, tooltip = ""
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
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Border", order = 5
            }},
            -- Visibility (Edit Mode synced)
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            hideWhenInactive = { type = "editmode", default = false, ui = {
                label = "Hide when inactive", widget = "checkbox", section = "Misc", order = 4
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 5
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 6
            }},
            -- Marker: enable Text section in settings UI for this component
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
            -- Positioning
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
            -- Sizing
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            barWidth = { type = "addon", default = 220, ui = {
                label = "Bar Width", widget = "slider", min = 120, max = 480, step = 2, section = "Sizing", order = 2
            }},
            -- NOTE: Bar Height (exploratory) temporarily removed from UI; border didn't scale with fill reliably.
            -- We'll revisit when we can safely resize the full framed bar (including border) without seams.
            --[[
            barHeight = { type = "addon", default = 14, ui = {
                label = "Bar Height", widget = "slider", min = 8, max = 36, step = 1, section = "Sizing", order = 3
            }},
            ]]
            -- Style (foreground/background bar textures)
            styleEnableCustom = { type = "addon", default = true, ui = {
                label = "Enable Custom Textures", widget = "checkbox", section = "Style", order = 0
            }},
            styleForegroundTexture = { type = "addon", default = "bevelled", ui = {
                label = "Foreground Texture", widget = "dropdown", section = "Style", order = 1, optionsProvider = function()
                    if addon.BuildBarTextureOptionsContainer then return addon.BuildBarTextureOptionsContainer() end
                    local c = Settings.CreateControlTextContainer(); c:Add("bevelled", "Bevelled"); return c:GetData()
                end
            }},
            styleBackgroundTexture = { type = "addon", default = "bevelledGrey", ui = {
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
            -- Bar Border
            borderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Border", order = 1
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
                    -- Only the default option is available until new bar border assets are wired up.
                    if addon.BuildBarBorderOptionsContainer then
                        return addon.BuildBarBorderOptionsContainer()
                    end
                    return {}
                end,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Border", order = 5
            }},
            -- Icon
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
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Icon", order = 7
            }},
            -- Visibility / Misc (Edit Mode)
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3
            }},
            displayMode = { type = "editmode", default = "both", ui = {
                label = "Display Mode", widget = "dropdown", values = { both = "Icon & Name", icon = "Icon Only", name = "Name Only" }, section = "Misc", order = 4
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
            -- Marker: enable Text section in settings UI for this component
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(trackedBars)
end

function addon:LinkComponentsToDB()
    for id, component in pairs(self.Components) do
        if not self.db.profile.components[id] then
            self.db.profile.components[id] = {}
        end
        component.db = self.db.profile.components[id]
    end
end

function addon:ApplyStyles()
    for id, component in pairs(self.Components) do
        if component.ApplyStyling then
            component:ApplyStyling()
        end
    end
end

function addon:SyncAllEditModeSettings()
    local anyChanged = false
    for id, component in pairs(self.Components) do
        if component.SyncEditModeSettings then
            if component:SyncEditModeSettings() then
                anyChanged = true
            end
        end
        if addon.EditMode.SyncComponentPositionFromEditMode then
            if addon.EditMode.SyncComponentPositionFromEditMode(component) then
                anyChanged = true
            end
        end
    end

    return anyChanged
end
