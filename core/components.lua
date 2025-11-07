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
                    -- Use an independent container on UIParent so bar masks do not clip the border,
                    -- and keep it below our settings panel (which uses DIALOG strata).
                    containerStrata = "HIGH",
                    levelOffset = 5,
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
        local oocRaw = self.db and self.db.opacityOutOfCombat
        if oocRaw == nil and self.settings and self.settings.opacityOutOfCombat then
            oocRaw = self.settings.opacityOutOfCombat.default
        end
        local oocOpacity = ClampOpacity(oocRaw or baseOpacity, 1)
        local tgtRaw = self.db and self.db.opacityWithTarget
        if tgtRaw == nil and self.settings and self.settings.opacityWithTarget then
            tgtRaw = self.settings.opacityWithTarget.default
        end
        local tgtOpacity = ClampOpacity(tgtRaw or baseOpacity, 1)
        local hasTarget = (UnitExists and UnitExists("target")) and true or false
        local applied = hasTarget and tgtOpacity or (PlayerInCombat() and baseOpacity or oocOpacity)
        if frame.SetAlpha then pcall(frame.SetAlpha, frame, applied / 100) end
    end
end

-- Action Bars: addon-only styling (Icon Width/Height) with safe relayout nudges
-- Removed: Action Bars non-uniform icon sizing and holder styling (see ACTIONBARS.md limitation)

local function ApplyActionBarStyling(self)
	local bar = _G[self.frameName]
	if not bar then return end

	-- Apply overall bar opacity (addon-only, target > combat > out-of-combat)
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
	local appliedOp = hasTarget and tgtOp or ((PlayerInCombat and PlayerInCombat()) and baseOp or oocOp)
	if bar.SetAlpha then pcall(bar.SetAlpha, bar, appliedOp / 100) end

	local function enumerateButtons()
		local buttons = {}
		local prefix
		if self.frameName == "MainMenuBar" then
			prefix = "ActionButton"
		else
			prefix = tostring(self.frameName) .. "Button"
		end
		for i = 1, 12 do
			local btn = _G[prefix .. i]
			if btn then buttons[#buttons + 1] = btn end
		end
		-- Fallback: include any button-like direct children
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
		-- Try explicit getters first
		if button.GetNormalTexture then
			local nt = button:GetNormalTexture()
			if nt and nt.SetAlpha then pcall(nt.SetAlpha, nt, restore and 1 or 0) end
		end
		-- Scan textures by common region names
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
					-- Action Bars only: nudge inward to meet Blizzard backdrop
					expandX = -1,
					expandY = -1,
				})
				-- Additional right-side-only tighten (smallest gap on right)
				local container = btn.ScootSquareBorderContainer or btn
				local edges = (container and container.ScootSquareBorderEdges) or btn.ScootSquareBorderEdges
				if edges and edges.Right then
					edges.Right:ClearAllPoints()
					edges.Right:SetPoint("TOPRIGHT", container or btn, "TOPRIGHT", -2, -1)
					edges.Right:SetPoint("BOTTOMRIGHT", container or btn, "BOTTOMRIGHT", -2, 1)
				end
				-- Keep top/bottom endpoints flush with adjusted right edge to avoid small overhangs
				if edges and edges.Top then
					edges.Top:ClearAllPoints()
					edges.Top:SetPoint("TOPLEFT", container or btn, "TOPLEFT", 1, -1)
					edges.Top:SetPoint("TOPRIGHT", container or btn, "TOPRIGHT", -2, -1)
				end
				if edges and edges.Bottom then
					edges.Bottom:ClearAllPoints()
					edges.Bottom:SetPoint("BOTTOMLEFT", container or btn, "BOTTOMLEFT", 1, 1)
					edges.Bottom:SetPoint("BOTTOMRIGHT", container or btn, "BOTTOMRIGHT", -2, 1)
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

        -- Apply Backdrop selection
        do
            local disableBackdrop = self.db and self.db.backdropDisable
            local style = (self.db and self.db.backdropStyle) or (self.settings and self.settings.backdropStyle and self.settings.backdropStyle.default) or "blizzardBg"
            local opacity = tonumber(self.db and self.db.backdropOpacity) or 100
            local inset = tonumber(self.db and self.db.backdropInset) or 0
            local tintEnabled = self.db and self.db.backdropTintEnable and type(self.db.backdropTintColor) == "table"
            local tintColor
            if tintEnabled then
                local c = self.db.backdropTintColor or {1,1,1,1}
                tintColor = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
            end
            if disableBackdrop then
                local bg = btn and btn.SlotBackground
                if bg and bg.SetAlpha then pcall(bg.SetAlpha, bg, 0) end
            else
                if addon and addon.ApplyIconBackdropToActionButton then
                    addon.ApplyIconBackdropToActionButton(btn, style, opacity, inset, tintColor)
                end
            end
        end

		-- Text styling: Charges (Count), Cooldown numbers, Hotkey, Macro Name
		do
			local defaultFace = (select(1, GameFontNormal:GetFont()))
			local function applyTextToFontString(fs, cfg, justify, anchorPoint, relTo)
				if not fs or not fs.SetFont then return end
				local size = tonumber(cfg.size) or 14
				local style = cfg.style or "OUTLINE"
				local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
				pcall(fs.SetDrawLayer, fs, "OVERLAY", 10)
				fs:SetFont(face, size, style)
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

			-- Charges / Count
			if btn.Count then
				local cfg = self.db.textStacks or { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }
				applyTextToFontString(btn.Count, cfg, "CENTER", "CENTER", btn)
			end

			-- Cooldown numbers overlay
			local cdOwner = btn.cooldown or btn.Cooldown or btn.CooldownFrame or nil
			local cdText
			if cdOwner then
				-- Try to find a fontstring under the cooldown frame
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

			-- Hotkey text
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

			-- Macro name text
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
    opacityWithTarget = { type = "addon", default = 100, ui = {
        label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 4
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
    opacityWithTarget = { type = "addon", default = 100, ui = {
        label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 4
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
            -- Marker: enable Text section in settings UI for this component
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(trackedBars)
end

-- Micro Bar (Edit Mode only): Orientation, Order, Menu Size, Eye Size
do
    local microBar = Component:New({
        id = "microBar",
        name = "Micro Bar",
        frameName = "MicroMenuContainer",
        settings = {
            -- Positioning
            orientation = { type = "editmode", settingId = 0, default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            -- Order behaves like a direction toggle; map to directional labels for consistency
            direction = { type = "editmode", settingId = 1, default = "right", ui = {
                label = "Icon Direction", widget = "dropdown", values = { left = "Left", right = "Right", up = "Up", down = "Down" }, section = "Positioning", order = 2, dynamicValues = true
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 98
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 99
            }},
            -- Sizing
            menuSize = { type = "editmode", settingId = 2, default = 100, ui = {
                label = "Menu Size (Scale)", widget = "slider", min = 70, max = 200, step = 5, section = "Sizing", order = 1
            }},
            eyeSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Eye Size", widget = "slider", min = 50, max = 150, step = 5, section = "Sizing", order = 2
            }},
        },
        -- No addon-only styling for Micro bar currently
    })
    addon:RegisterComponent(microBar)
end

-- Stance Bar (Edit Mode only): Orientation, Rows (NumRows), Icon Padding, Icon Size
do
    local stanceBar = Component:New({
        id = "stanceBar",
        name = "Stance Bar",
        frameName = "StanceBar",
        settings = {
            -- Positioning
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
            -- Sizing
            iconSize = { type = "editmode", default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
        },
    })
    addon:RegisterComponent(stanceBar)
end

-- Action Bars (1–8): minimal components to expose Edit Mode Positioning > Orientation
do
    local function abComponent(id, name, frameName, defaultOrientation)
		return Component:New({
            id = id,
            name = name,
            frameName = frameName,
            settings = {
                -- Positioning (Edit Mode)
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
                -- Sizing
                iconSize = { type = "editmode", default = 100, ui = {
                    label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
                }},
                -- Removed addon-only per-axis sizing (see ACTIONBARS.md limitation)
				-- Border (Addon-only; applies to each button's icon area)
				borderDisableAll = { type = "addon", default = false, ui = {
					label = "Disable Border", widget = "checkbox", section = "Border", order = 1, tooltip = "Hide all button border art (stock and custom)."
				}},
				borderEnable = { type = "addon", default = false, ui = {
					label = "Use Custom Border", widget = "checkbox", section = "Border", order = 2, tooltip = ""
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
					label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Border", order = 6
				}},
                -- Backdrop (Addon-only)
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
                backdropInset = { type = "addon", default = 0, ui = {
                    label = "Backdrop Inset", widget = "slider", min = -6, max = 8, step = 1, section = "Backdrop", order = 3
                }},
                backdropTintEnable = { type = "addon", default = false, ui = {
                    label = "Backdrop Tint", widget = "checkbox", section = "Backdrop", order = 4
                }},
                backdropTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                    label = "Tint Color", widget = "color", section = "Backdrop", order = 5
                }},
                backdropOpacity = { type = "addon", default = 100, ui = {
                    label = "Backdrop Opacity", widget = "slider", min = 1, max = 100, step = 1, section = "Backdrop", order = 6
                }},
				-- Visibility (Addon-only)
				barOpacity = { type = "addon", default = 100, ui = {
					label = "Opacity", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 99
				}},
				barOpacityOutOfCombat = { type = "addon", default = 100, ui = {
					label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 100
				}},
				barOpacityWithTarget = { type = "addon", default = 100, ui = {
					label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 101
				}},
				-- Marker: enable Text section (4 tabs) in settings UI for Action Bars
				supportsText = { type = "addon", default = true },
                -- Position (addon-side; neutral defaults)
                positionX = { type = "addon", default = 0, ui = {
                    label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 98
                }},
                positionY = { type = "addon", default = 0, ui = {
                    label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 99
                }},
            },
			-- Apply icon borders on action bar buttons when enabled
			ApplyStyling = ApplyActionBarStyling,
        })
    end

    local defs = {
        { "actionBar1", "Action Bar 1", "MainMenuBar",         "H", false },
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
            -- Action Bar 1 exclusive visibility checkboxes
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
        addon:RegisterComponent(comp)
    end
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
    -- Also apply Unit Frame text visibility toggles
    if addon.ApplyAllUnitFrameHealthTextVisibility then
        addon.ApplyAllUnitFrameHealthTextVisibility()
    end
    if addon.ApplyAllUnitFramePowerTextVisibility then
        addon.ApplyAllUnitFramePowerTextVisibility()
    end
    -- Apply Unit Frame bar textures (Health/Power) if configured
    if addon.ApplyAllUnitFrameBarTextures then
        addon.ApplyAllUnitFrameBarTextures()
    end
end

-- Copy all settings from one Action Bar to another (both Edit Mode and addon-only)
-- Skips keys that do not exist on the destination bar (handles AB1-only and AB2-8-only options)
function addon.CopyActionBarSettings(sourceComponentId, destComponentId)
    if type(sourceComponentId) ~= "string" or type(destComponentId) ~= "string" then return end
    if sourceComponentId == destComponentId then return end
    local src = addon.Components and addon.Components[sourceComponentId]
    local dst = addon.Components and addon.Components[destComponentId]
    if not src or not dst then return end
    if not (sourceComponentId:match("^actionBar%d$") and destComponentId:match("^actionBar%d$")) then return end

    -- Defensive: ensure DB links exist
    if not src.db or not dst.db then return end

    -- Helper to deep-copy simple tables (e.g., color arrays, offset tables)
    local function deepcopy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, vv in pairs(v) do out[k] = deepcopy(vv) end
        return out
    end

    -- 1) Copy values into destination DB (only keys the destination knows about)
    for key, def in pairs(dst.settings or {}) do
        -- Skip marker keys that are not real settings
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

    -- 1b) Copy Action Bar text styling keys that are stored only in DB (not declared under settings)
    do
        local textKeys = {
            "textStacks", "textCooldown",
            "textHotkeyHidden", "textHotkey",
            "textMacroHidden",  "textMacro",
        }
        for _, k in ipairs(textKeys) do
            if src.db[k] ~= nil then
                dst.db[k] = deepcopy(src.db[k])
            else
                -- Explicitly clear to revert to defaults when source uses defaults
                dst.db[k] = nil
            end
        end
    end

    -- 2) Push Edit Mode–managed settings to the game for the destination bar
    if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
        for key, setting in pairs(dst.settings or {}) do
            if setting and setting.type == "editmode" then
                pcall(addon.EditMode.SyncComponentSettingToEditMode, dst, key)
            end
        end
    end

    -- 3) Persist and coalesce apply; then re-style locally
    if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
    if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
    addon:ApplyStyles()
end

-- Unit Frames: Toggle Health % (LeftText) and Value (RightText) visibility per unit
do
    local function getUnitFrameFor(unit)
        local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
			-- Fallback for environments where Edit Mode indices aren't available
			if unit == "Pet" then return _G.PetFrame end
			return nil
		end
		local idx = nil
		if EM then
			idx = (unit == "Player" and EM.Player)
				or (unit == "Target" and EM.Target)
				or (unit == "Focus" and EM.Focus)
				or (unit == "Pet" and EM.Pet)
		end
		if idx then
			return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
		end
		-- If no index was resolved (older builds lacking EM.Pet), try known globals
		if unit == "Pet" then return _G.PetFrame end
		return nil
    end

    local function findFontStringByNameHint(root, hint)
        if not root then return nil end
        local target
        local function scan(obj)
            if not obj or target then return end
            if obj.GetObjectType and obj:GetObjectType() == "FontString" then
                local nm = obj.GetName and obj:GetName() or (obj.GetDebugName and obj:GetDebugName()) or ""
                if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                    target = obj; return
                end
            end
            if obj.GetRegions then
                local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                for i = 1, n do
                    local r = select(i, obj:GetRegions())
                    if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                        local nm = r.GetName and r:GetName() or (r.GetDebugName and r:GetDebugName()) or ""
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

    local function applyForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        db.unitFrames[unit] = db.unitFrames[unit] or {}
        local cfg = db.unitFrames[unit]
        local frame = getUnitFrameFor(unit)
        if not frame then return end
		local leftFS
		local rightFS
		if unit == "Pet" then
			leftFS = _G.PetFrameHealthBarTextLeft or (frame.HealthBarsContainer and frame.HealthBarsContainer.LeftText)
			rightFS = _G.PetFrameHealthBarTextRight or (frame.HealthBarsContainer and frame.HealthBarsContainer.RightText)
		end
		leftFS = leftFS or (frame.HealthBarsContainer and frame.HealthBarsContainer.LeftText) or findFontStringByNameHint(frame, "HealthBarsContainer.LeftText") or findFontStringByNameHint(frame, ".LeftText") or findFontStringByNameHint(frame, "HealthBarTextLeft")
		rightFS = rightFS or (frame.HealthBarsContainer and frame.HealthBarsContainer.RightText) or findFontStringByNameHint(frame, "HealthBarsContainer.RightText") or findFontStringByNameHint(frame, ".RightText") or findFontStringByNameHint(frame, "HealthBarTextRight")
        if leftFS and leftFS.SetShown then pcall(leftFS.SetShown, leftFS, not not (not cfg.healthPercentHidden)) end
        if rightFS and rightFS.SetShown then pcall(rightFS.SetShown, rightFS, not not (not cfg.healthValueHidden)) end

        -- Apply styling (font/size/style/color/offset) with stable baseline anchoring
        addon._ufTextBaselines = addon._ufTextBaselines or {}
        local function ensureBaseline(fs, key)
            addon._ufTextBaselines[key] = addon._ufTextBaselines[key] or {}
            local b = addon._ufTextBaselines[key]
            if b.point == nil then
                if fs and fs.GetPoint then
                    local p, relTo, rp, x, y = fs:GetPoint(1)
                    b.point = p or "CENTER"
                    b.relTo = relTo or (fs.GetParent and fs:GetParent()) or frame
                    b.relPoint = rp or b.point
                    b.x = tonumber(x) or 0
                    b.y = tonumber(y) or 0
                else
                    b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or frame, "CENTER", 0, 0
                end
            end
            return b
        end

        local function applyTextStyle(fs, styleCfg, baselineKey)
            if not fs or not styleCfg then return end
            local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
            local size = tonumber(styleCfg.size) or 14
            local outline = tostring(styleCfg.style or "OUTLINE")
            if fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
            local c = styleCfg.color or {1,1,1,1}
            if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
            -- Offset relative to a stable baseline anchor captured at first apply this session
            local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
            local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
            if fs.ClearAllPoints and fs.SetPoint then
                local b = ensureBaseline(fs, baselineKey)
                fs:ClearAllPoints()
                fs:SetPoint(b.point or "CENTER", b.relTo or (fs.GetParent and fs:GetParent()) or frame, b.relPoint or b.point or "CENTER", (b.x or 0) + ox, (b.y or 0) + oy)
            end
        end

        if leftFS then applyTextStyle(leftFS, cfg.textHealthPercent or {}, unit .. ":left") end
        if rightFS then applyTextStyle(rightFS, cfg.textHealthValue or {}, unit .. ":right") end
    end

    function addon.ApplyUnitFrameHealthTextVisibilityFor(unit)
        applyForUnit(unit)
    end

	function addon.ApplyAllUnitFrameHealthTextVisibility()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
	end

    -- Copy addon-only Unit Frame text settings from source unit to destination unit
    function addon.CopyUnitFrameTextSettings(sourceUnit, destUnit)
        local db = addon and addon.db and addon.db.profile
        if not db then return false end
        db.unitFrames = db.unitFrames or {}
        local src = db.unitFrames[sourceUnit]
        if not src then return false end
        db.unitFrames[destUnit] = db.unitFrames[destUnit] or {}
        local dst = db.unitFrames[destUnit]
        local function deepcopy(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for k, vv in pairs(v) do out[k] = deepcopy(vv) end
            return out
        end
        local keys = {
            "healthPercentHidden",
            "healthValueHidden",
            "textHealthPercent",
            "textHealthValue",
        }
        for _, k in ipairs(keys) do
            if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
        end
        if addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(destUnit) end
        return true
    end
end

-- Unit Frames: Toggle Power % (LeftText when present) and Value (RightText) visibility per unit
do
	local function getUnitFrameFor(unit)
		local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
			if unit == "Pet" then return _G.PetFrame end
			return nil
		end
		local idx = nil
		if EM then
			idx = (unit == "Player" and EM.Player)
				or (unit == "Target" and EM.Target)
				or (unit == "Focus" and EM.Focus)
				or (unit == "Pet" and EM.Pet)
		end
		if idx then
			return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
		end
		if unit == "Pet" then return _G.PetFrame end
		return nil
	end

	local function findFontStringByNameHint(root, hint)
		if not root then return nil end
		local target
		local function scan(obj)
			if not obj or target then return end
			if obj.GetObjectType and obj:GetObjectType() == "FontString" then
				local nm = obj.GetName and obj:GetName() or (obj.GetDebugName and obj:GetDebugName()) or ""
				if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
					target = obj; return
				end
			end
			if obj.GetRegions then
				local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
				for i = 1, n do
					local r = select(i, obj:GetRegions())
					if r and r.GetObjectType and r:GetObjectType() == "FontString" then
						local nm = r.GetName and r:GetName() or (r.GetDebugName and r:GetDebugName()) or ""
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

	local function applyForUnit(unit)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		local cfg = db.unitFrames[unit]
		local frame = getUnitFrameFor(unit)
		if not frame then return end

		-- Attempt to resolve power bar text regions
		local leftFS
		local rightFS
		if unit == "Pet" then
			-- Pet uses standalone globals more often
			leftFS = _G.PetFrameManaBarTextLeft
			rightFS = _G.PetFrameManaBarTextRight
		end
		-- Common names on Player: ManaBar.LeftText / ManaBar.RightText; on Target/Focus, ManaBar.LeftText/RightText as children under content
		leftFS = leftFS
			or (frame.ManaBar and frame.ManaBar.LeftText)
			or findFontStringByNameHint(frame, "ManaBar.LeftText")
			or findFontStringByNameHint(frame, ".LeftText")
			or findFontStringByNameHint(frame, "ManaBarTextLeft")
		rightFS = rightFS
			or (frame.ManaBar and frame.ManaBar.RightText)
			or findFontStringByNameHint(frame, "ManaBar.RightText")
			or findFontStringByNameHint(frame, ".RightText")
			or findFontStringByNameHint(frame, "ManaBarTextRight")

		-- Visibility: tolerate missing LeftText on some classes/specs (no-op)
		if leftFS and leftFS.SetShown then pcall(leftFS.SetShown, leftFS, not not (not cfg.powerPercentHidden)) end
		if rightFS and rightFS.SetShown then pcall(rightFS.SetShown, rightFS, not not (not cfg.powerValueHidden)) end

		-- Styling
		addon._ufPowerTextBaselines = addon._ufPowerTextBaselines or {}
		local function ensureBaseline(fs, key)
			addon._ufPowerTextBaselines[key] = addon._ufPowerTextBaselines[key] or {}
			local b = addon._ufPowerTextBaselines[key]
			if b.point == nil then
				if fs and fs.GetPoint then
					local p, relTo, rp, x, y = fs:GetPoint(1)
					b.point = p or "CENTER"
					b.relTo = relTo or (fs.GetParent and fs:GetParent()) or frame
					b.relPoint = rp or b.point
					b.x = tonumber(x) or 0
					b.y = tonumber(y) or 0
				else
					b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or frame, "CENTER", 0, 0
				end
			end
			return b
		end

		local function applyTextStyle(fs, styleCfg, baselineKey)
			if not fs or not styleCfg then return end
			local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
			local size = tonumber(styleCfg.size) or 14
			local outline = tostring(styleCfg.style or "OUTLINE")
			if fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
			local c = styleCfg.color or {1,1,1,1}
			if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
			local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
			local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
			if fs.ClearAllPoints and fs.SetPoint then
				local b = ensureBaseline(fs, baselineKey)
				fs:ClearAllPoints()
				fs:SetPoint(b.point or "CENTER", b.relTo or (fs.GetParent and fs:GetParent()) or frame, b.relPoint or b.point or "CENTER", (b.x or 0) + ox, (b.y or 0) + oy)
			end
		end

		if leftFS then applyTextStyle(leftFS, cfg.textPowerPercent or {}, unit .. ":power-left") end
		if rightFS then applyTextStyle(rightFS, cfg.textPowerValue or {}, unit .. ":power-right") end
	end

	function addon.ApplyUnitFramePowerTextVisibilityFor(unit)
		applyForUnit(unit)
	end

	function addon.ApplyAllUnitFramePowerTextVisibility()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
	end

	-- Optional helper mirroring health text settings copy (no-op if missing)
	function addon.CopyUnitFramePowerTextSettings(sourceUnit, destUnit)
		local db = addon and addon.db and addon.db.profile
		if not db then return false end
		db.unitFrames = db.unitFrames or {}
		local src = db.unitFrames[sourceUnit]
		if not src then return false end
		db.unitFrames[destUnit] = db.unitFrames[destUnit] or {}
		local dst = db.unitFrames[destUnit]
		local function deepcopy(v)
			if type(v) ~= "table" then return v end
			local out = {}
			for k, vv in pairs(v) do out[k] = deepcopy(vv) end
			return out
		end
		local keys = {
			"powerPercentHidden",
			"powerValueHidden",
			"textPowerPercent",
			"textPowerValue",
		}
		for _, k in ipairs(keys) do
			if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
		end
		if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(destUnit) end
		return true
	end
end

-- Unit Frames: Copy Health/Power Bar Style settings (texture, color mode, tint)
do
    function addon.CopyUnitFrameBarStyleSettings(sourceUnit, destUnit)
        local db = addon and addon.db and addon.db.profile
        if not db then return false end
        db.unitFrames = db.unitFrames or {}
        local src = db.unitFrames[sourceUnit]
        if not src then return false end
        db.unitFrames[destUnit] = db.unitFrames[destUnit] or {}
        local dst = db.unitFrames[destUnit]

        local function deepcopy(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for k, vv in pairs(v) do out[k] = deepcopy(vv) end
            return out
        end

        local keys = {
            "healthBarTexture",
            "healthBarColorMode",
            "healthBarTint",
            "powerBarTexture",
            "powerBarColorMode",
            "powerBarTint",
        }
        for _, k in ipairs(keys) do
            if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
        end

        if addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor(destUnit) end
        return true
    end
end

-- Unit Frames: Apply custom bar textures (Health/Power) with optional tint per unit
do
    local function getUnitFrameFor(unit)
        local mgr = _G.EditModeManagerFrame
        local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
        local EMSys = _G.Enum and _G.Enum.EditModeSystem
        if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
            if unit == "Pet" then return _G.PetFrame end
            return nil
        end
        local idx = nil
        if EM then
            idx = (unit == "Player" and EM.Player)
                or (unit == "Target" and EM.Target)
                or (unit == "Focus" and EM.Focus)
                or (unit == "Pet" and EM.Pet)
        end
        if idx then
            return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
        end
        if unit == "Pet" then return _G.PetFrame end
        return nil
    end

    local function findStatusBarByHints(root, hintsTbl, excludesTbl)
        if not root then return nil end
        local hints = hintsTbl or {}
        local excludes = excludesTbl or {}
        local found
        local function matchesName(obj)
            local nm = (obj and obj.GetName and obj:GetName()) or (obj and obj.GetDebugName and obj:GetDebugName()) or ""
            if type(nm) ~= "string" then return false end
            local lnm = string.lower(nm)
            for _, ex in ipairs(excludes) do
                if ex and string.find(lnm, string.lower(ex), 1, true) then
                    return false
                end
            end
            for _, h in ipairs(hints) do
                if h and string.find(lnm, string.lower(h), 1, true) then
                    return true
                end
            end
            return false
        end
        local function scan(obj)
            if not obj or found then return end
            if obj.GetObjectType and obj:GetObjectType() == "StatusBar" then
                if matchesName(obj) then
                    found = obj; return
                end
            end
            if obj.GetChildren then
                local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
                for i = 1, m do
                    local c = select(i, obj:GetChildren())
                    scan(c)
                    if found then return end
                end
            end
        end
        scan(root)
        return found
    end

    local function getNested(root, ...)
        local cur = root
        for i = 1, select('#', ...) do
            local key = select(i, ...)
            if not cur or type(cur) ~= "table" then return nil end
            cur = cur[key]
        end
        return cur
    end

    local function resolveHealthBar(frame, unit)
        -- Deterministic paths from Framestack findings; fallback to conservative search only if missing
        if unit == "Pet" then return _G.PetFrameHealthBar end
        if unit == "Player" then
            local root = _G.PlayerFrame
            local hb = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer", "HealthBar")
            if hb then return hb end
        elseif unit == "Target" then
            local root = _G.TargetFrame
            local hb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
            if hb then return hb end
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            local hb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
            if hb then return hb end
        end
        -- Fallbacks
        if frame and frame.HealthBarsContainer and frame.HealthBarsContainer.HealthBar then return frame.HealthBarsContainer.HealthBar end
        return findStatusBarByHints(frame, {"HealthBarsContainer.HealthBar", ".HealthBar", "HealthBar"}, {"Prediction", "Absorb", "Mana"})
    end

    -- Raise unit frame text layers so they always appear above any custom borders
    local function raiseUnitTextLayers(unit, targetLevel)
        local function safeSetDrawLayer(fs, layer, sub)
            if fs and fs.SetDrawLayer then pcall(fs.SetDrawLayer, fs, layer, sub) end
        end
        local function safeRaiseFrameLevel(frame, baseLevel, bump)
            if not frame then return end
            local cur = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
            local target = math.max(cur, (tonumber(baseLevel) or 0) + (tonumber(bump) or 0))
            if targetLevel and type(targetLevel) == "number" then
                if target < targetLevel then target = targetLevel end
            end
            if frame.SetFrameLevel then pcall(frame.SetFrameLevel, frame, target) end
        end
        if unit == "Pet" then
            safeSetDrawLayer(_G.PetFrameHealthBarText, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameHealthBarTextLeft, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameHealthBarTextRight, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameManaBarText, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameManaBarTextLeft, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameManaBarTextRight, "OVERLAY", 6)
            -- Bump parent levels above any border holder
            local hb = _G.PetFrameHealthBar
            local mb = _G.PetFrameManaBar
            local base = (hb and hb.GetFrameLevel and hb:GetFrameLevel()) or 0
            safeRaiseFrameLevel(hb, base, 12)
            safeRaiseFrameLevel(mb, base, 12)
            return
        end
        local root = (unit == "Player" and _G.PlayerFrame)
            or (unit == "Target" and _G.TargetFrame)
            or (unit == "Focus" and _G.FocusFrame) or nil
        if not root then return end
        -- Health texts
        local hbContainer = (unit == "Player" and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer)
            or (root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer)
        if hbContainer then
            safeSetDrawLayer(hbContainer.HealthBarText, "OVERLAY", 6)
            safeSetDrawLayer(hbContainer.LeftText, "OVERLAY", 6)
            safeSetDrawLayer(hbContainer.RightText, "OVERLAY", 6)
            local base = (hbContainer.GetFrameLevel and hbContainer:GetFrameLevel()) or ((root.GetFrameLevel and root:GetFrameLevel()) or 0)
            safeRaiseFrameLevel(hbContainer, base, 12)
        end
        -- Mana texts
        local mana
        if unit == "Player" then
            mana = root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
        else
            mana = root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.ManaBar
        end
        if mana then
            safeSetDrawLayer(mana.ManaBarText, "OVERLAY", 6)
            safeSetDrawLayer(mana.LeftText, "OVERLAY", 6)
            safeSetDrawLayer(mana.RightText, "OVERLAY", 6)
            local base = (mana.GetFrameLevel and mana:GetFrameLevel()) or ((root.GetFrameLevel and root:GetFrameLevel()) or 0)
            safeRaiseFrameLevel(mana, base, 12)
        end
    end

    -- (moved ensureTextAndBorderOrdering below resolver functions)

	-- Parent container that holds both Health and Power areas (content main)
	local function resolveUFContentMain(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Pet" then
			return _G.PetFrame
		end
		return nil
	end

    local function resolveHealthContainer(frame, unit)
        if unit == "Pet" then return _G.PetFrame and _G.PetFrame.HealthBarContainer end
        if unit == "Player" then
            local root = _G.PlayerFrame
            local c = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer")
            if c then return c end
        elseif unit == "Target" then
            local root = _G.TargetFrame
            local c = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer")
            if c then return c end
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            local c = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer")
            if c then return c end
        end
        return frame and frame.HealthBarsContainer or nil
    end

    local function resolvePowerBar(frame, unit)
        if unit == "Pet" then return _G.PetFrameManaBar end
        if unit == "Player" then
            local root = _G.PlayerFrame
            local mb = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar")
            if mb then return mb end
        elseif unit == "Target" then
            local root = _G.TargetFrame
            local mb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
            if mb then return mb end
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            local mb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
            if mb then return mb end
        end
        if frame and frame.ManaBar then return frame.ManaBar end
        return findStatusBarByHints(frame, {"ManaBar", ".ManaBar", "PowerBar"}, {"Prediction"})
    end

    -- Resolve mask textures per unit and bar type to ensure proper shaping after texture swaps
    local function resolveHealthMask(unit)
        if unit == "Player" then
            local root = _G.PlayerFrame
            return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBarMask
        elseif unit == "Target" then
            local root = _G.TargetFrame
            return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarMask
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarMask
        elseif unit == "Pet" then
            return _G.PetFrameHealthBarMask
        end
        return nil
    end

    local function resolvePowerMask(unit)
        if unit == "Player" then
            local root = _G.PlayerFrame
            return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
                and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
                and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
                and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.ManaBarMask
        elseif unit == "Target" then
            local root = _G.TargetFrame
            return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarMask
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarMask
        elseif unit == "Pet" then
            return _G.PetFrameManaBarMask
        end
        return nil
    end

    -- Compute border holder level below current text and enforce ordering deterministically
    local function ensureTextAndBorderOrdering(unit)
        local root = (unit == "Player" and _G.PlayerFrame)
            or (unit == "Target" and _G.TargetFrame)
            or (unit == "Focus" and _G.FocusFrame)
            or (unit == "Pet" and _G.PetFrame) or nil
        if not root then return end
        local hb = resolveHealthBar(root, unit) or nil
        local hbContainer = resolveHealthContainer(root, unit) or nil
        local pb = resolvePowerBar(root, unit) or nil
        local manaContainer
        if unit == "Player" then
            manaContainer = root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar or nil
        else
            manaContainer = root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.ManaBar or nil
        end
        -- Determine bar level and desired ordering: bar < holder < text
        local barLevel = (hb and hb.GetFrameLevel and hb:GetFrameLevel()) or 0
        if pb and pb.GetFrameLevel then
            local pbl = pb:GetFrameLevel() or 0
            if pbl > barLevel then barLevel = pbl end
        end
        local curTextLevel = 0
        if hbContainer and hbContainer.GetFrameLevel then curTextLevel = math.max(curTextLevel, hbContainer:GetFrameLevel() or 0) end
        if manaContainer and manaContainer.GetFrameLevel then curTextLevel = math.max(curTextLevel, manaContainer:GetFrameLevel() or 0) end
        local desiredTextLevel = math.max(curTextLevel, barLevel + 2)
        -- Raise text containers above holder
        if hbContainer and hbContainer.SetFrameLevel then pcall(hbContainer.SetFrameLevel, hbContainer, desiredTextLevel) end
        if manaContainer and manaContainer.SetFrameLevel then pcall(manaContainer.SetFrameLevel, manaContainer, desiredTextLevel) end
        -- Keep text FontStrings at high overlay sublevel
        raiseUnitTextLayers(unit, desiredTextLevel)
        -- Place the textured border holder between bar and text
        do
            local holderLevel = math.max(1, desiredTextLevel - 1, barLevel + 1)
            local hHolder = hb and hb.ScooterStyledBorder or nil
            if hHolder and hHolder.SetFrameLevel then
                -- Lock desired level so internal size hooks won't raise it above text later
                hb._ScooterBorderFixedLevel = holderLevel
                pcall(hHolder.SetFrameLevel, hHolder, holderLevel)
            end
            -- Match holder strata to the text container's strata so frame level ordering decides (bar < holder < text)
            if hHolder and hHolder.SetFrameStrata then
                local s = (hbContainer and hbContainer.GetFrameStrata and hbContainer:GetFrameStrata())
                    or (hb and hb.GetFrameStrata and hb:GetFrameStrata())
                    or (root and root.GetFrameStrata and root:GetFrameStrata())
                    or "MEDIUM"
                pcall(hHolder.SetFrameStrata, hHolder, s)
            end
            local pHolder = pb and pb.ScooterStyledBorder or nil
            if pHolder and pHolder.SetFrameLevel then
                pb._ScooterBorderFixedLevel = holderLevel
                pcall(pHolder.SetFrameLevel, pHolder, holderLevel)
            end
            if pHolder and pHolder.SetFrameStrata then
                local s2 = (manaContainer and manaContainer.GetFrameStrata and manaContainer:GetFrameStrata())
                    or (pb and pb.GetFrameStrata and pb:GetFrameStrata())
                    or (root and root.GetFrameStrata and root:GetFrameStrata())
                    or "MEDIUM"
                pcall(pHolder.SetFrameStrata, pHolder, s2)
            end
            -- No overlay frame creation: respect stock-frame reuse policy
        end
        -- (experimental text reparent/strata bump removed; see HOLDING.md 2025-11-07)
    end

    -- Resolve the stock unit frame frame art (the large atlas that includes the health bar border)
    local function resolveUnitFrameFrameTexture(unit)
        if unit == "Player" then
            local root = _G.PlayerFrame
            return root and root.PlayerFrameContainer and root.PlayerFrameContainer.FrameTexture or nil
        elseif unit == "Target" then
            local root = _G.TargetFrame
            return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
        elseif unit == "Pet" then
            return _G.PetFrameTexture
        end
        return nil
    end

    local function ensureMaskOnBarTexture(bar, mask)
        if not bar or not mask or not bar.GetStatusBarTexture then return end
        local tex = bar:GetStatusBarTexture()
        if not tex or not tex.AddMaskTexture then return end
        -- Re-apply mask to the current texture instance and enforce Blizzard's texel snapping settings
        pcall(tex.AddMaskTexture, tex, mask)
        if tex.SetTexelSnappingBias then pcall(tex.SetTexelSnappingBias, tex, 0) end
        if tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
        if tex.SetHorizTile then pcall(tex.SetHorizTile, tex, false) end
        if tex.SetVertTile then pcall(tex.SetVertTile, tex, false) end
        if tex.SetTexCoord then pcall(tex.SetTexCoord, tex, 0, 1, 0, 1) end
    end

    local function applyToBar(bar, textureKey, colorMode, tint, unitForClass, barKind, unitForPower)
        if not bar or type(bar.GetStatusBarTexture) ~= "function" then return end
        local tex = bar:GetStatusBarTexture()
        -- Capture original once
        if not bar._ScootUFOrigCaptured then
            if tex and tex.GetAtlas then
                local ok, atlas = pcall(tex.GetAtlas, tex)
                if ok and atlas then bar._ScootUFOrigAtlas = atlas end
            end
			if tex and tex.GetTexture then
				local ok, path = pcall(tex.GetTexture, tex)
				if ok and path then
					-- Some Blizzard status bars use atlases; GetAtlas may return nil while GetTexture returns the atlas token.
					-- Prefer treating such strings as atlases when possible to avoid spritesheet rendering on restore.
					local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(path) ~= nil
					if isAtlas then
						bar._ScootUFOrigAtlas = bar._ScootUFOrigAtlas or path
					else
						bar._ScootUFOrigPath = path
					end
				end
			end
            if tex and tex.GetVertexColor then
                local ok, r, g, b, a = pcall(tex.GetVertexColor, tex)
                if ok then bar._ScootUFOrigVertex = { r or 1, g or 1, b or 1, a or 1 } end
            end
            bar._ScootUFOrigCaptured = true
        end

        local isCustom = type(textureKey) == "string" and textureKey ~= "" and textureKey ~= "default"
        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(textureKey)
        if isCustom and resolvedPath then
            if bar.SetStatusBarTexture then pcall(bar.SetStatusBarTexture, bar, resolvedPath) end
            -- Re-fetch the current texture after swapping to ensure subsequent operations target the new texture
            tex = bar:GetStatusBarTexture()
            local r, g, b, a = 1, 1, 1, 1
            if colorMode == "custom" and type(tint) == "table" then
                r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
            elseif colorMode == "class" then
                if addon.GetClassColorRGB then
                    local cr, cg, cb = addon.GetClassColorRGB(unitForClass or "player")
                    r, g, b, a = cr or 1, cg or 1, cb or 1, 1
                end
            elseif colorMode == "default" then
                -- When using a custom texture, "Default" should tint to the stock bar color
                if barKind == "health" and addon.GetDefaultHealthColorRGB then
                    local hr, hg, hb = addon.GetDefaultHealthColorRGB()
                    r, g, b, a = hr or 0, hg or 1, hb or 0, 1
                elseif barKind == "power" and addon.GetPowerColorRGB then
                    local pr, pg, pb = addon.GetPowerColorRGB(unitForPower or unitForClass or "player")
                    r, g, b, a = pr or 1, pg or 1, pb or 1, 1
                else
                    local ov = bar._ScootUFOrigVertex
                    if type(ov) == "table" then r, g, b, a = ov[1] or 1, ov[2] or 1, ov[3] or 1, ov[4] or 1 end
                end
            end
            if tex and tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
        else
            -- Default texture path. If the user selected Class/Custom color, avoid restoring
            -- Blizzard's green/colored atlas because vertex-color multiplies and distorts hues.
            -- Instead, use a neutral white fill and apply the desired color; keep the stock mask.
            local r, g, b, a = 1, 1, 1, 1
            local wantsNeutral = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class")
            if wantsNeutral then
                if colorMode == "custom" then
                    r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
                elseif colorMode == "class" and addon.GetClassColorRGB then
                    local cr, cg, cb = addon.GetClassColorRGB(unitForClass or "player")
                    r, g, b, a = cr or 1, cg or 1, cb or 1, 1
                end
                if tex and tex.SetColorTexture then pcall(tex.SetColorTexture, tex, 1, 1, 1, 1) end
            else
                -- Default color: restore Blizzard's original fill
                if bar._ScootUFOrigCaptured then
                    if bar._ScootUFOrigAtlas then
                        if tex and tex.SetAtlas then
                            pcall(tex.SetAtlas, tex, bar._ScootUFOrigAtlas, true)
                        elseif bar.SetStatusBarTexture then
                            pcall(bar.SetStatusBarTexture, bar, bar._ScootUFOrigAtlas)
                        end
                    elseif bar._ScootUFOrigPath then
                        local treatAsAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(bar._ScootUFOrigPath) ~= nil
                        if treatAsAtlas and tex and tex.SetAtlas then
                            pcall(tex.SetAtlas, tex, bar._ScootUFOrigPath, true)
                        elseif bar.SetStatusBarTexture then
                            pcall(bar.SetStatusBarTexture, bar, bar._ScootUFOrigPath)
                        end
                    end
                end
                local ov = bar._ScootUFOrigVertex or {1,1,1,1}
                r, g, b, a = ov[1] or 1, ov[2] or 1, ov[3] or 1, ov[4] or 1
            end
            if tex and tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
            if bar.ScooterModBG and bar.ScooterModBG.Hide then pcall(bar.ScooterModBG.Hide, bar.ScooterModBG) end
        end
    end

    local function applyForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        local cfg = db.unitFrames[unit] or {}
        local frame = getUnitFrameFor(unit)
        if not frame then return end
        local _didResize = false

        local hb = resolveHealthBar(frame, unit)
        if hb then
            local colorModeHB = (cfg.healthBarColorMode == "class" and "class") or (cfg.healthBarColorMode == "custom" and "custom") or "default"
            local texKeyHB = cfg.healthBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or "player"
            applyToBar(hb, texKeyHB, colorModeHB, cfg.healthBarTint, "player", "health", unitId)
            -- If restoring default texture and we lack a captured original, restore to the known stock atlas for this unit
            local isDefaultHB = (texKeyHB == "default" or not addon.Media.ResolveBarTexturePath(texKeyHB))
            if isDefaultHB and not hb._ScootUFOrigAtlas and not hb._ScootUFOrigPath then
				local stockAtlas
				if unit == "Player" then
					stockAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
				elseif unit == "Target" then
					stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health"
				elseif unit == "Focus" then
					stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health" -- Focus reuses Target visuals
				elseif unit == "Pet" then
					stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- Pet frame shares party atlas
				end
                if stockAtlas then
                    local hbTex = hb.GetStatusBarTexture and hb:GetStatusBarTexture()
                    if hbTex and hbTex.SetAtlas then pcall(hbTex.SetAtlas, hbTex, stockAtlas, true) end
					-- Best-effort: ensure the mask uses the matching atlas
					local mask = resolveHealthMask(unit)
					if mask and mask.SetAtlas then
						local maskAtlas
						if unit == "Player" then
							maskAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask"
						elseif unit == "Target" or unit == "Focus" then
							maskAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask"
						elseif unit == "Pet" then
							maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask"
						end
						if maskAtlas then pcall(mask.SetAtlas, mask, maskAtlas) end
					end
				end
			end
			ensureMaskOnBarTexture(hb, resolveHealthMask(unit))
			-- Experimental: Health Bar Width scaling (texture/mask only), Player/Target/Focus
            do
				if unit ~= "Pet" then
				local pct = tonumber(cfg.healthBarWidthPct) or 100
					local tex = hb.GetStatusBarTexture and hb:GetStatusBarTexture()
					local mask = resolveHealthMask(unit)
					-- Reverted width behavior: do not modify parent containers; operate only on the bar/texture/mask
					local container = nil
					local main = nil
					-- Capture originals once
					if tex and not tex._ScootUFOrigCapturedWidth then
						if tex.GetScale then
							local ok, sc = pcall(tex.GetScale, tex)
							if ok and sc then tex._ScootUFOrigScale = sc end
						end
						if tex.GetWidth then
							local ok, w = pcall(tex.GetWidth, tex)
							if ok and w then tex._ScootUFOrigWidth = w end
						end
						tex._ScootUFOrigCapturedWidth = true
					end
					if mask and not mask._ScootUFOrigCapturedWidth then
						if mask.GetScale then
							local ok, sc = pcall(mask.GetScale, mask)
							if ok and sc then mask._ScootUFOrigScale = sc end
						end
						if mask.GetWidth then
							local ok, w = pcall(mask.GetWidth, mask)
							if ok and w then mask._ScootUFOrigWidth = w end
						end
						mask._ScootUFOrigCapturedWidth = true
					end

                    -- Ensure original anchor points captured for re-anchoring (width/height adjustments)
					if hb and not hb._ScootUFOrigPoints then
						local pts = {}
						local n = (hb.GetNumPoints and hb:GetNumPoints()) or 0
						for i = 1, n do
							local p, rel, rp, x, y = hb:GetPoint(i)
							table.insert(pts, { p, rel, rp, x or 0, y or 0 })
						end
						hb._ScootUFOrigPoints = pts
					end
                    if container and not container._ScootUFOrigPoints then
                        local pts = {}
                        local n = (container.GetNumPoints and container:GetNumPoints()) or 0
                        for i = 1, n do
                            local p, rel, rp, x, y = container:GetPoint(i)
                            table.insert(pts, { p, rel, rp, x or 0, y or 0 })
                        end
                        container._ScootUFOrigPoints = pts
                    end
					if main and not main._ScootUFOrigPoints then
						local pts = {}
						local n = (main.GetNumPoints and main:GetNumPoints()) or 0
						for i = 1, n do
							local p, rel, rp, x, y = main:GetPoint(i)
							table.insert(pts, { p, rel, rp, x or 0, y or 0 })
						end
						main._ScootUFOrigPoints = pts
					end
					local function reapplyPointsWithRightOffset(dx)
						-- Positive dx moves RIGHT/CENTER anchors outward to the right
						local pts = hb and hb._ScootUFOrigPoints
						if not (hb and pts and hb.ClearAllPoints and hb.SetPoint) then return end
						pcall(hb.ClearAllPoints, hb)
						for _, pt in ipairs(pts) do
							local p, rel, rp, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
							local xx = x or 0
							local anchor = tostring(p or "")
							local relp = tostring(rp or "")
							if string.find(anchor, "RIGHT", 1, true) or string.find(relp, "RIGHT", 1, true) then
								xx = (x or 0) + (dx or 0)
							elseif string.find(anchor, "CENTER", 1, true) or string.find(relp, "CENTER", 1, true) then
								xx = (x or 0) + ((dx or 0) * 0.5)
							end
							pcall(hb.SetPoint, hb, p or "LEFT", rel, rp or p or "LEFT", xx or 0, y or 0)
						end
					end
                    local function reapplyContainerPointsWithRightOffset(dx)
                        if not container then return end
                        local pts = container._ScootUFOrigPoints
                        if not (pts and container.ClearAllPoints and container.SetPoint) then return end
                        pcall(container.ClearAllPoints, container)
                        for _, pt in ipairs(pts) do
                            local p, rel, rp, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
                            local xx = x or 0
                            local anchor = tostring(p or "")
                            local relp = tostring(rp or "")
                            if string.find(anchor, "RIGHT", 1, true) or string.find(relp, "RIGHT", 1, true) then
                                xx = (x or 0) + (dx or 0)
                            elseif string.find(anchor, "CENTER", 1, true) or string.find(relp, "CENTER", 1, true) then
                                xx = (x or 0) + ((dx or 0) * 0.5)
                            end
                            pcall(container.SetPoint, container, p or "LEFT", rel, rp or p or "LEFT", xx or 0, y or 0)
                        end
                    end
					local function reapplyMainPointsWithRightOffset(dx)
						if not main then return end
						local pts = main._ScootUFOrigPoints
						if not (pts and main.ClearAllPoints and main.SetPoint) then return end
						pcall(main.ClearAllPoints, main)
						for _, pt in ipairs(pts) do
							local p, rel, rp, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
							local xx = x or 0
							local anchor = tostring(p or "")
							local relp = tostring(rp or "")
							if string.find(anchor, "RIGHT", 1, true) or string.find(relp, "RIGHT", 1, true) then
								xx = (x or 0) + (dx or 0)
							elseif string.find(anchor, "CENTER", 1, true) or string.find(relp, "CENTER", 1, true) then
								xx = (x or 0) + ((dx or 0) * 0.5)
							end
							pcall(main.SetPoint, main, p or "LEFT", rel, rp or p or "LEFT", xx or 0, y or 0)
						end
					end
					local scaleX = math.max(1, pct / 100)
					local scaleY = 1
					-- Capture original HealthBar width once (frame width, not value)
					if hb and not hb._ScootUFOrigWidth then
						if hb.GetWidth then
							local ok, w = pcall(hb.GetWidth, hb)
							if ok and w then hb._ScootUFOrigWidth = w end
						end
					end
                    if container and not container._ScootUFOrigWidth then
                        if container.GetWidth then
                            local ok, w = pcall(container.GetWidth, container)
                            if ok and w then container._ScootUFOrigWidth = w end
                        end
                    end
					if main and not main._ScootUFOrigWidth then
						if main.GetWidth then
							local ok, w = pcall(main.GetWidth, main)
							if ok and w then main._ScootUFOrigWidth = w end
						end
					end
                    if pct > 100 then
						-- Prefer scaling; fall back to widening if scale not available
						if tex and tex.SetScale then pcall(tex.SetScale, tex, scaleX) end
						if mask and mask.SetScale then pcall(mask.SetScale, mask, scaleX) end
						if tex and (not tex.SetScale) and tex.SetWidth and tex._ScootUFOrigWidth then
							pcall(tex.SetWidth, tex, tex._ScootUFOrigWidth * scaleX)
						end
						if mask and (not mask.SetScale) and mask.SetWidth and mask._ScootUFOrigWidth then
							pcall(mask.SetWidth, mask, mask._ScootUFOrigWidth * scaleX)
						end
						-- Ensure the status bar frame itself widens
						if hb and hb.SetWidth and hb._ScootUFOrigWidth then
							pcall(hb.SetWidth, hb, hb._ScootUFOrigWidth * scaleX)
						end
                        -- Also widen the container to avoid capping/clipping at container edges
                        if container and container.SetWidth and container._ScootUFOrigWidth then
                            pcall(container.SetWidth, container, container._ScootUFOrigWidth * scaleX)
                        end
						-- And widen the content main to move the unified right boundary
						if main and main.SetWidth and main._ScootUFOrigWidth then
							pcall(main.SetWidth, main, main._ScootUFOrigWidth * scaleX)
						end
						-- Disable clipping on parents so overflow is visible
						if container and container.SetClipsChildren then pcall(container.SetClipsChildren, container, false) end
						if main and main.SetClipsChildren then pcall(main.SetClipsChildren, main, false) end
						-- Grow frame to the right by re-anchoring RIGHT/CENTER points outward (keeps left edge fixed)
						if hb and hb._ScootUFOrigWidth then
							local dx = (hb._ScootUFOrigWidth * (scaleX - 1))
							if dx and dx ~= 0 then reapplyPointsWithRightOffset(dx) end
						end
                        if container and container._ScootUFOrigWidth then
                            local dx = (container._ScootUFOrigWidth * (scaleX - 1))
                            if dx and dx ~= 0 then reapplyContainerPointsWithRightOffset(dx) end
                        end
						if main and main._ScootUFOrigWidth then
							local dx = (main._ScootUFOrigWidth * (scaleX - 1))
							if dx and dx ~= 0 then reapplyMainPointsWithRightOffset(dx) end
						end
                        _didResize = true
					else
						-- Restore
						if tex then
							if tex._ScootUFOrigScale and tex.SetScale then pcall(tex.SetScale, tex, tex._ScootUFOrigScale) end
							if tex._ScootUFOrigWidth and tex.SetWidth then pcall(tex.SetWidth, tex, tex._ScootUFOrigWidth) end
						end
						if mask then
							if mask._ScootUFOrigScale and mask.SetScale then pcall(mask.SetScale, mask, mask._ScootUFOrigScale) end
							if mask._ScootUFOrigWidth and mask.SetWidth then pcall(mask.SetWidth, mask, mask._ScootUFOrigWidth) end
						end
						if hb and hb._ScootUFOrigWidth and hb.SetWidth then
							pcall(hb.SetWidth, hb, hb._ScootUFOrigWidth)
						end
                        if container and container._ScootUFOrigWidth and container.SetWidth then
                            pcall(container.SetWidth, container, container._ScootUFOrigWidth)
                        end
						if main and main._ScootUFOrigWidth and main.SetWidth then
							pcall(main.SetWidth, main, main._ScootUFOrigWidth)
						end
						if hb and hb._ScootUFOrigPoints and hb.ClearAllPoints and hb.SetPoint then
							pcall(hb.ClearAllPoints, hb)
							for _, pt in ipairs(hb._ScootUFOrigPoints) do
								pcall(hb.SetPoint, hb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
							end
						end
                        if container and container._ScootUFOrigPoints and container.ClearAllPoints and container.SetPoint then
                            pcall(container.ClearAllPoints, container)
                            for _, pt in ipairs(container._ScootUFOrigPoints) do
                                pcall(container.SetPoint, container, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
                            end
                        end
						if main and main._ScootUFOrigPoints and main.ClearAllPoints and main.SetPoint then
							pcall(main.ClearAllPoints, main)
							for _, pt in ipairs(main._ScootUFOrigPoints) do
								pcall(main.SetPoint, main, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
							end
						end
					end
					-- (Reverted) Height scaling removed
				end
			end
            -- Health Bar custom border (Health Bar only)
            do
				local styleKey = cfg.healthBarBorderStyle
				local tintEnabled = not not cfg.healthBarBorderTintEnable
				local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
					cfg.healthBarBorderTintColor[1] or 1,
					cfg.healthBarBorderTintColor[2] or 1,
					cfg.healthBarBorderTintColor[3] or 1,
					cfg.healthBarBorderTintColor[4] or 1,
				} or {1, 1, 1, 1}
                local thickness = tonumber(cfg.healthBarBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                local inset = tonumber(cfg.healthBarBorderInset) or 0
				-- Only draw custom border when Use Custom Borders is enabled
				if hb then
					if cfg.useCustomBorders then
						-- Handle style = "none" to explicitly clear any custom border
						if styleKey == "none" or styleKey == nil then
							if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
							if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(hb) end
						else
							-- Match Tracked Bars: when tint is disabled use white for textured styles,
							-- and black only for the pixel fallback case.
							local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
							local color
							if tintEnabled then
								color = tintColor
							else
								if styleDef then
									color = {1, 1, 1, 1}
								else
									color = {0, 0, 0, 1}
								end
							end
                            local handled = false
                            if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
								-- Clear any prior holder/state to avoid stale tinting when toggling
								if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                handled = addon.BarBorders.ApplyToBarFrame(hb, styleKey, {
                                    color = color,
                                    thickness = thickness,
                                    levelOffset = 1, -- just above bar fill; text will be raised above holder
                                    containerParent = (hb and hb:GetParent()) or nil,
                                    inset = inset,
                                })
							end
                            if not handled then
								-- Fallback: pixel (square) border drawn with our lightweight helper
								if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                if addon.Borders and addon.Borders.ApplySquare then
									local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                    local baseY = (thickness <= 1) and 0 or 1
                                    local baseX = 1
                                    local expandY = baseY - inset
                                    local expandX = baseX - inset
                                    if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                    if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                    addon.Borders.ApplySquare(hb, {
										size = thickness,
										color = sqColor,
                                        layer = "OVERLAY",
                                        layerSublevel = 3,
										expandX = expandX,
										expandY = expandY,
									})
                                end
							end
                            -- Deterministically place border below text and ensure text wins
                            ensureTextAndBorderOrdering(unit)
                            -- Light hook: keep ordering stable on bar resize
                            if hb and not hb._ScootUFZOrderHooked and hb.HookScript then
                                hb:HookScript("OnSizeChanged", function() ensureTextAndBorderOrdering(unit) end)
                                hb._ScootUFZOrderHooked = true
                            end
						end
					else
						-- Custom borders disabled -> ensure cleared
						if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
						if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(hb) end
					end
				end
            end
		end

        local pb = resolvePowerBar(frame, unit)
        if pb then
            local colorModePB = (cfg.powerBarColorMode == "class" and "class") or (cfg.powerBarColorMode == "custom" and "custom") or "default"
            local texKeyPB = cfg.powerBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or "player"
            applyToBar(pb, texKeyPB, colorModePB, cfg.powerBarTint, "player", "power", unitId)
            ensureMaskOnBarTexture(pb, resolvePowerMask(unit))

            -- Power Bar custom border (mirrors Health Bar border settings; supports power-specific overrides)
            do
                local styleKey = cfg.powerBarBorderStyle or cfg.healthBarBorderStyle
                local tintEnabled
                if cfg.powerBarBorderTintEnable ~= nil then
                    tintEnabled = not not cfg.powerBarBorderTintEnable
                else
                    tintEnabled = not not cfg.healthBarBorderTintEnable
                end
                local baseTint = type(cfg.powerBarBorderTintColor) == "table" and cfg.powerBarBorderTintColor or cfg.healthBarBorderTintColor
                local tintColor = type(baseTint) == "table" and {
                    baseTint[1] or 1,
                    baseTint[2] or 1,
                    baseTint[3] or 1,
                    baseTint[4] or 1,
                } or {1, 1, 1, 1}
                local thickness = tonumber(cfg.powerBarBorderThickness) or tonumber(cfg.healthBarBorderThickness) or 1
                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                local inset = (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInset) or 0
                if cfg.useCustomBorders then
                    if styleKey == "none" or styleKey == nil then
                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                    else
                        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                        local color
                        if tintEnabled then
                            color = tintColor
                        else
                            if styleDef then
                                color = {1, 1, 1, 1}
                            else
                                color = {0, 0, 0, 1}
                            end
                        end
                        local handled = false
                        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                            if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                            handled = addon.BarBorders.ApplyToBarFrame(pb, styleKey, {
                                color = color,
                                thickness = thickness,
                                levelOffset = 1,
                                containerParent = (pb and pb:GetParent()) or nil,
                                inset = inset,
                            })
                        end
                        if not handled then
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                            if addon.Borders and addon.Borders.ApplySquare then
                                local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                local baseY = (thickness <= 1) and 0 or 1
                                local baseX = 1
                                local expandY = baseY - inset
                                local expandX = baseX - inset
                                if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                addon.Borders.ApplySquare(pb, {
                                    size = thickness,
                                    color = sqColor,
                                    layer = "OVERLAY",
                                    layerSublevel = 3,
                                    expandX = expandX,
                                    expandY = expandY,
                                })
                            end
                        end
                        -- Keep ordering stable for power bar borders as well
                        ensureTextAndBorderOrdering(unit)
                        if pb and not pb._ScootUFZOrderHooked and pb.HookScript then
                            pb:HookScript("OnSizeChanged", function() ensureTextAndBorderOrdering(unit) end)
                            pb._ScootUFZOrderHooked = true
                        end
                    end
                else
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                end
            end
        end

        -- Nudge Blizzard to re-evaluate atlases/masks immediately after restoration
        local function refresh(unitKey)
            if unitKey == "Player" then
                if _G.PlayerFrame_Update then pcall(_G.PlayerFrame_Update) end
            elseif unitKey == "Target" then
                if _G.TargetFrame_Update then pcall(_G.TargetFrame_Update, _G.TargetFrame) end
            elseif unitKey == "Focus" then
                if _G.FocusFrame_Update then pcall(_G.FocusFrame_Update, _G.FocusFrame) end
            elseif unitKey == "Pet" then
                if _G.PetFrame_Update then pcall(_G.PetFrame_Update, _G.PetFrame) end
            end
        end

        -- Experimental: optionally hide the stock frame art (which includes the health bar border)
        do
            local ft = resolveUnitFrameFrameTexture(unit)
            if ft and ft.SetShown then
                local hide = not not (cfg.useCustomBorders or cfg.healthBarHideBorder)
                pcall(ft.SetShown, ft, not hide)
            end
        end
        refresh(unit)
    end

    function addon.ApplyUnitFrameBarTexturesFor(unit)
        applyForUnit(unit)
    end

    function addon.ApplyAllUnitFrameBarTextures()
        applyForUnit("Player")
        applyForUnit("Target")
        applyForUnit("Focus")
        applyForUnit("Pet")
    end

    -- Install stable hooks to re-assert z-order after Blizzard refreshers
    local function installUFZOrderHooks()
        local function defer(unit)
            if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, function() ensureTextAndBorderOrdering(unit) end) else ensureTextAndBorderOrdering(unit) end
        end
        if _G.PlayerFrame and _G.PlayerFrame.UpdateSystem then
            _G.hooksecurefunc(_G.PlayerFrame, "UpdateSystem", function() defer("Player") end)
        end
        if type(_G.TargetFrame_Update) == "function" then
            _G.hooksecurefunc("TargetFrame_Update", function() defer("Target") end)
        end
        if type(_G.FocusFrame_Update) == "function" then
            _G.hooksecurefunc("FocusFrame_Update", function() defer("Focus") end)
        end
        if type(_G.PetFrame_Update) == "function" then
            _G.hooksecurefunc("PetFrame_Update", function() defer("Pet") end)
        end
    end

    if not addon._UFZOrderHooksInstalled then
        addon._UFZOrderHooksInstalled = true
        if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, installUFZOrderHooks) else installUFZOrderHooks() end
    end

end

-- (Reverted) No additional hooks for reapplying experimental sizing; rely on normal refresh

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
