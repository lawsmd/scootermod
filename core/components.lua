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

local function ResetIconBorderTarget(target)
    if not target then return end
    if addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(target)
    end

    local function wipeTexture(tex)
        if not tex then return end
        tex:Hide()
        if tex.SetTexture then pcall(tex.SetTexture, tex, nil) end
        if tex.SetAtlas then pcall(tex.SetAtlas, tex, nil, true) end
        if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, 1, 1, 1, 0) end
        if tex.SetAlpha then pcall(tex.SetAlpha, tex, 0) end
    end

    wipeTexture(target.ScootAtlasBorder)
    wipeTexture(target.ScootTextureBorder)
    wipeTexture(target.ScootAtlasBorderTintOverlay)
    wipeTexture(target.ScootTextureBorderTintOverlay)

    if target.ScootSquareBorderEdges then
        for _, edge in pairs(target.ScootSquareBorderEdges) do
            if edge then edge:Hide() end
        end
    end

    if target.ScootSquareBorder and target.ScootSquareBorder.edges then
        for _, tex in pairs(target.ScootSquareBorder.edges) do
            if tex and tex.Hide then tex:Hide() end
        end
    end
    if target.ScootSquareBorderContainer and target.ScootSquareBorderContainer.Hide then
        target.ScootSquareBorderContainer:Hide()
    end
end

local function CleanupIconBorderAttachments(icon)
    if not icon then return end
    local seen = {}
    local function cleanup(target)
        if target and not seen[target] then
            seen[target] = true
            ResetIconBorderTarget(target)
        end
    end

    cleanup(icon)
    cleanup(icon.ScooterIconBorderContainer)
    cleanup(icon.ScooterAtlasBorderContainer)
    cleanup(icon.ScooterTextureBorderContainer)
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

    -- Always wipe any lingering Scooter border attachments before choosing the
    -- target frame for the new style. This mirrors the Unit Frame Cast Bar fix
    -- where legacy atlas borders could remain visible behind the square style.
    CleanupIconBorderAttachments(frame)

    -- For Texture targets (e.g., Unit Frame cast bar icons), create/reuse a small
    -- wrapper Frame that matches the texture's bounds so the border helpers, which
    -- expect Frames, have a valid anchor to DrawLayer against.
    local targetFrame = frame
    if frame.GetObjectType and frame:GetObjectType() == "Texture" then
        local parent = frame:GetParent() or UIParent
        local container = frame.ScooterIconBorderContainer
        if not container then
            container = CreateFrame("Frame", nil, parent)
            frame.ScooterIconBorderContainer = container
            container:EnableMouse(false)
        end
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        -- Keep container at a predictable strata/level above its parent; let border
        -- helpers choose DrawLayer/sublevel for the actual textures.
        local strata = parent.GetFrameStrata and parent:GetFrameStrata() or "HIGH"
        container:SetFrameStrata(strata)
        local baseLevel = parent.GetFrameLevel and parent:GetFrameLevel() or 0
        container:SetFrameLevel(baseLevel + 5)
        targetFrame = container
    end

    -- Always clear any previous ScooterMod border textures and tint overlays for this
    -- target before applying a new style to avoid layering multiple styles.
    ResetIconBorderTarget(targetFrame)
    if targetFrame ~= frame then
        ResetIconBorderTarget(frame)
    end

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
            addon.Borders.ApplySquare(targetFrame, {
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
        addon.Borders.ApplyAtlas(targetFrame, {
            atlas = styleDef.atlas,
            color = baseApplyColor,
            tintColor = baseApplyColor,
            expandX = expandX,
            expandY = expandY,
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
        })
        appliedTexture = targetFrame.ScootAtlasBorder
    elseif styleDef.type == "texture" then
        addon.Borders.ApplyTexture(targetFrame, {
            texture = styleDef.texture,
            color = baseApplyColor,
            tintColor = baseApplyColor,
            expandX = expandX,
            expandY = expandY,
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
        })
        appliedTexture = targetFrame.ScootTextureBorder
    else
        addon.Borders.ApplySquare(targetFrame, {
            size = thickness,
            color = baseApplyColor or {0, 0, 0, 1},
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
        })
        local container = targetFrame.ScootSquareBorderContainer or targetFrame
        local edges = (container and container.ScootSquareBorderEdges) or targetFrame.ScootSquareBorderEdges
        if edges then
            for _, edge in pairs(edges) do
                if edge and edge.SetColorTexture then
                    edge:SetColorTexture(baseApplyColor[1] or 0, baseApplyColor[2] or 0, baseApplyColor[3] or 0, (baseApplyColor[4] == nil and 1) or baseApplyColor[4])
                end
            end
        end
        if targetFrame.ScootAtlasBorderTintOverlay then targetFrame.ScootAtlasBorderTintOverlay:Hide() end
        if targetFrame.ScootTextureBorderTintOverlay then targetFrame.ScootTextureBorderTintOverlay:Hide() end
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
            overlay = targetFrame.ScootAtlasBorderTintOverlay
        elseif styleDef.type == "texture" then
            overlay = targetFrame.ScootTextureBorderTintOverlay
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
            local tex = targetFrame:CreateTexture(nil, layer)
            tex:SetDrawLayer(layer, sublevel or 0)
            tex:SetAllPoints(appliedTexture)
            tex:SetVertexColor(1, 1, 1, 1)
            tex:Hide()
            if styleDef.type == "atlas" then
                targetFrame.ScootAtlasBorderTintOverlay = tex
            else
                targetFrame.ScootTextureBorderTintOverlay = tex
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
            local bgOpacity = component.db and component.db.styleBackgroundOpacity or (component.settings.styleBackgroundOpacity and component.settings.styleBackgroundOpacity.default) or 50
            addon.Media.ApplyBarTexturesToBarFrame(barFrame, fg, bg, bgOpacity)
            -- Apply foreground color based on mode
            local fgColorMode = (component.db and component.db.styleForegroundColorMode) or "default"
            local fgTint = (component.db and component.db.styleForegroundTint) or {1,1,1,1}
            local tex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
            if tex and tex.SetVertexColor then
                local r, g, b, a = 1, 1, 1, 1
                if fgColorMode == "custom" and type(fgTint) == "table" then
                    r, g, b, a = fgTint[1] or 1, fgTint[2] or 1, fgTint[3] or 1, fgTint[4] or 1
                elseif fgColorMode == "texture" then
                    -- Apply white (no tint) to preserve texture's original colors
                    r, g, b, a = 1, 1, 1, 1
                elseif fgColorMode == "default" then
                    -- Default: use Blizzard's default Tracked Bars color (orange-ish: 1.0, 0.5, 0.25)
                    -- This matches the color used when reverting to stock texture (line 486)
                    r, g, b, a = 1.0, 0.5, 0.25, 1.0
                end
                pcall(tex.SetVertexColor, tex, r, g, b, a)
            end
            -- Apply background color based on mode
            local bgColorMode = (component.db and component.db.styleBackgroundColorMode) or "default"
            local bgTint = (component.db and component.db.styleBackgroundTint) or {0,0,0,1}
            if barFrame.ScooterModBG then
                local r, g, b, a = 0, 0, 0, 1
                if bgColorMode == "custom" and type(bgTint) == "table" then
                    r, g, b, a = bgTint[1] or 0, bgTint[2] or 0, bgTint[3] or 0, bgTint[4] or 1
                elseif bgColorMode == "texture" then
                    -- Apply white (no tint) to preserve texture's original colors
                    r, g, b, a = 1, 1, 1, 1
                elseif bgColorMode == "default" then
                    -- Default: black background
                    r, g, b, a = 0, 0, 0, 1
                end
                -- Apply color (RGB only, not alpha)
                if barFrame.ScooterModBG.SetVertexColor then
                    pcall(barFrame.ScooterModBG.SetVertexColor, barFrame.ScooterModBG, r, g, b, 1.0)
                end
                -- Re-apply opacity after vertex color to ensure it's not overridden
                if barFrame.ScooterModBG.SetAlpha then
                    local opacity = tonumber(bgOpacity) or 50
                    opacity = math.max(0, math.min(100, opacity)) / 100
                    pcall(barFrame.ScooterModBG.SetAlpha, barFrame.ScooterModBG, opacity)
                end
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
        -- Only process well-formed setting tables. Some components include
        -- boolean marker flags (e.g., supportsEmptyBorderSection) in their
        -- settings table; these are not real settings and must be ignored
        -- by the Edit Mode sync path.
        if type(setting) == "table" and setting.type == "editmode" then
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

-- Public helper: apply Buffs/Debuffs aura icon sizing to all aura buttons for a given component
function addon.ApplyAuraFrameVisualsFor(component)
    if not component or (component.id ~= "buffs" and component.id ~= "debuffs") then return end

    local frameName = component.frameName
    if not frameName or type(frameName) ~= "string" then return end

    local frame = _G[frameName]
    if not frame or not frame.AuraContainer then return end

    local db = component.db or {}
    local settings = component.settings or {}

    -- Backwards compatibility: reuse any legacy cooldown text settings as duration defaults
    if type(db.textDuration) ~= "table" and type(db.textCooldown) == "table" then
        local src = db.textCooldown
        local copy = {}
        if type(src.fontFace) == "string" then copy.fontFace = src.fontFace end
        if src.size ~= nil then copy.size = src.size end
        if type(src.style) == "string" then copy.style = src.style end
        if type(src.color) == "table" then
            copy.color = { src.color[1], src.color[2], src.color[3], src.color[4] }
        end
        if type(src.offset) == "table" then
            copy.offset = { x = src.offset.x, y = src.offset.y }
        end
        if next(copy) ~= nil then
            db.textDuration = copy
        end
    end

    local defaultFace = (select(1, GameFontNormal:GetFont()))

    local function ensureTextConfig(key)
        local cfg = db[key]
        if type(cfg) ~= "table" then
            cfg = {}
            db[key] = cfg
        end
        cfg.offset = cfg.offset or {}
        return cfg
    end

    local function enforceTextColor(fs, key)
        if not fs or fs._ScooterColorApplying then return end
        local cfg = db[key]
        if type(cfg) ~= "table" then return end
        local color = cfg.color
        if type(color) ~= "table" or not fs.SetTextColor then return end
        fs._ScooterColorApplying = true
        fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        fs._ScooterColorApplying = nil
    end

    local function ensureTextHooks(fs, key)
        if not fs or not hooksecurefunc then return end
        fs._ScooterTextHooks = fs._ScooterTextHooks or {}
        local function hookMethod(method)
            if fs._ScooterTextHooks[method] or type(fs[method]) ~= "function" then return end
            fs._ScooterTextHooks[method] = true
            hooksecurefunc(fs, method, function()
                if fs._ScooterColorApplying then return end
                enforceTextColor(fs, key)
            end)
        end
        hookMethod("SetTextColor")
        hookMethod("SetVertexColor")
        hookMethod("SetFontObject")
        hookMethod("SetFont")
        hookMethod("SetFormattedText")
        hookMethod("SetText")
    end

    local function ensureDefaultColor(cfg, fs)
        if cfg.color ~= nil or not (fs and fs.GetTextColor) then return end
        local r, g, b, a = fs:GetTextColor()
        local alpha = a
        if alpha == nil and fs.GetAlpha then
            alpha = fs:GetAlpha()
        end
        cfg.color = { r or 1, g or 1, b or 1, alpha or 1 }
    end

    local function captureDefaultAnchor(fs, fallbackRelTo)
        if not fs then return nil end
        if not fs._ScooterDefaultAnchor then
            local point, relTo, relPoint, x, y = fs:GetPoint(1)
            if not point then
                point, relPoint, x, y = "CENTER", "CENTER", 0, 0
            end
            if relTo == nil then relTo = fallbackRelTo end
            fs._ScooterDefaultAnchor = {
                point = point or "CENTER",
                relTo = relTo,
                relPoint = relPoint or point or "CENTER",
                x = x or 0,
                y = y or 0,
            }
        end
        return fs._ScooterDefaultAnchor
    end

    local function applyAuraText(fs, key, defaultSize, fallbackRelTo)
        if not fs or not fs.SetFont then return end
        local cfg = ensureTextConfig(key)
        ensureDefaultColor(cfg, fs)
        ensureTextHooks(fs, key)
        local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
        local size = tonumber(cfg.size) or defaultSize
        local style = cfg.style or "OUTLINE"
        pcall(fs.SetDrawLayer, fs, "OVERLAY", 10)
        fs:SetFont(face, size, style)
        local color = cfg.color
        if color and fs.SetTextColor then
            fs._ScooterColorApplying = true
            fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
            fs._ScooterColorApplying = nil
        end
        local anchor = captureDefaultAnchor(fs, fallbackRelTo)
        if anchor and fs.ClearAllPoints and fs.SetPoint then
            local ox = tonumber(cfg.offset.x) or 0
            local oy = tonumber(cfg.offset.y) or 0
            fs:ClearAllPoints()
            fs:SetPoint(
                anchor.point or "CENTER",
                anchor.relTo or fallbackRelTo,
                anchor.relPoint or anchor.point or "CENTER",
                (anchor.x or 0) + ox,
                (anchor.y or 0) + oy
            )
        end
        enforceTextColor(fs, key)
    end

    local function resolveSettingValue(key)
        if db[key] ~= nil then return db[key] end
        local meta = settings[key]
        if type(meta) == "table" then
            return meta.default
        end
        return nil
    end

    local componentId = component and component.id

    local function applyCollapseButtonVisibility()
        if componentId ~= "buffs" then return end

        local collapseButton = frame.CollapseAndExpandButton
        if not collapseButton then return end

        local hideTextures = not not resolveSettingValue("hideCollapseButton")
        local unique = {}
        local textures = {}

        local function addTexture(tex)
            if tex and not unique[tex] then
                unique[tex] = true
                table.insert(textures, tex)
            end
        end

        addTexture(collapseButton.NormalTexture)
        addTexture(collapseButton.HighlightTexture)
        if collapseButton.GetNormalTexture then
            addTexture(collapseButton:GetNormalTexture())
        end
        if collapseButton.GetHighlightTexture then
            addTexture(collapseButton:GetHighlightTexture())
        end

        for _, tex in ipairs(textures) do
            if tex and tex.SetAlpha then
                if hideTextures then
                    if tex._ScooterOriginalAlpha == nil then
                        local alpha = tex:GetAlpha()
                        tex._ScooterOriginalAlpha = alpha ~= nil and alpha or 1
                    end
                    tex:SetAlpha(0)
                else
                    local alpha = tex._ScooterOriginalAlpha
                    tex:SetAlpha(alpha ~= nil and alpha or 1)
                    tex._ScooterOriginalAlpha = nil
                end
            end
        end
    end

    applyCollapseButtonVisibility()

    if componentId == "buffs" then
        local collapseButton = frame.CollapseAndExpandButton
        if collapseButton and not collapseButton._ScooterHideTexturesHooked then
            collapseButton._ScooterHideTexturesHooked = true
            local function refreshCollapseButton()
                applyCollapseButtonVisibility()
            end
            if hooksecurefunc then
                if collapseButton.SetNormalTexture then
                    hooksecurefunc(collapseButton, "SetNormalTexture", refreshCollapseButton)
                end
                if collapseButton.SetNormalAtlas then
                    hooksecurefunc(collapseButton, "SetNormalAtlas", refreshCollapseButton)
                end
                if collapseButton.SetHighlightTexture then
                    hooksecurefunc(collapseButton, "SetHighlightTexture", refreshCollapseButton)
                end
                if collapseButton.SetHighlightAtlas then
                    hooksecurefunc(collapseButton, "SetHighlightAtlas", refreshCollapseButton)
                end
            end
            if collapseButton.HookScript then
                collapseButton:HookScript("OnShow", refreshCollapseButton)
            end
        end
    end

    local width = tonumber(resolveSettingValue("iconWidth"))
    local height = tonumber(resolveSettingValue("iconHeight"))

    local borderEnabled = not not resolveSettingValue("borderEnable")
    local borderStyle = tostring(resolveSettingValue("borderStyle") or "square")
    if borderStyle == "none" then
        borderStyle = "square"
        if db then db.borderStyle = borderStyle end
    end
    local borderThickness = tonumber(resolveSettingValue("borderThickness")) or 1
    if borderThickness < 1 then borderThickness = 1 elseif borderThickness > 16 then borderThickness = 16 end
    local borderTintEnabled = not not resolveSettingValue("borderTintEnable")
    local borderTintColor = resolveSettingValue("borderTintColor")
    local tintColor
    if borderTintEnabled and type(borderTintColor) == "table" then
        tintColor = {
            borderTintColor[1] or 1,
            borderTintColor[2] or 1,
            borderTintColor[3] or 1,
            borderTintColor[4] or 1,
        }
    end

    local function setDefaultAuraBorderVisible(aura, visible)
        if not aura then return end
        local targets = { aura.IconBorder, aura.Border, aura.DebuffBorder }
        for _, region in ipairs(targets) do
            if region then
                if visible then
                    if region.Show then region:Show() end
                    if region.SetAlpha then region:SetAlpha(1) end
                else
                    if region.Hide then region:Hide() end
                    if region.SetAlpha then region:SetAlpha(0) end
                end
            end
        end
    end

    local function clearCustomBorder(icon)
        if not icon then return end
        CleanupIconBorderAttachments(icon)
    end

    local function captureDebuffBorderDefaults(aura, icon)
        if componentId ~= "debuffs" or not aura or not icon then return end
        local border = aura.DebuffBorder
        if not border then return end

        if not icon._ScooterDebuffBaseWidth then
            local w = icon:GetWidth()
            if w and w > 0 then
                icon._ScooterDebuffBaseWidth = w
            end
        end
        if not icon._ScooterDebuffBaseHeight then
            local h = icon:GetHeight()
            if h and h > 0 then
                icon._ScooterDebuffBaseHeight = h
            end
        end
        if not border._ScooterDebuffBaseWidth then
            local bw = border:GetWidth()
            if bw and bw > 0 then
                border._ScooterDebuffBaseWidth = bw
            end
        end
        if not border._ScooterDebuffBaseHeight then
            local bh = border:GetHeight()
            if bh and bh > 0 then
                border._ScooterDebuffBaseHeight = bh
            end
        end
    end

    local function resizeDebuffBorder(aura, icon, targetWidth, targetHeight)
        if componentId ~= "debuffs" or not aura or not icon then return end
        local border = aura.DebuffBorder
        if not border or not border.SetSize then return end

        local baseIconWidth = icon._ScooterDebuffBaseWidth
        local baseIconHeight = icon._ScooterDebuffBaseHeight
        local baseBorderWidth = border._ScooterDebuffBaseWidth
        local baseBorderHeight = border._ScooterDebuffBaseHeight

        local width = targetWidth or icon:GetWidth()
        local height = targetHeight or icon:GetHeight()

        if baseIconWidth and baseIconWidth > 0 and baseBorderWidth then
            border:SetWidth(baseBorderWidth * (width / baseIconWidth))
        end
        if baseIconHeight and baseIconHeight > 0 and baseBorderHeight then
            border:SetHeight(baseBorderHeight * (height / baseIconHeight))
        end

        if border.ClearAllPoints and border.SetPoint and not border._ScooterDebuffAnchorLocked then
            border:ClearAllPoints()
            border:SetPoint("CENTER", icon, "CENTER")
            border._ScooterDebuffAnchorLocked = true
        end
    end

    local auraCollections = {}
    local function addCollection(list)
        if type(list) == "table" then
            table.insert(auraCollections, list)
        end
    end

    addCollection(frame.auraFrames)
    if frame.AuraContainer and type(frame.AuraContainer.auraFrames) == "table" then
        addCollection(frame.AuraContainer.auraFrames)
    end
    if type(frame.tempEnchantFrames) == "table" then
        addCollection(frame.tempEnchantFrames)
    end
    if frame.TempEnchantContainer and type(frame.TempEnchantContainer.auraFrames) == "table" then
        addCollection(frame.TempEnchantContainer.auraFrames)
    end
    if type(frame.privateAuraAnchors) == "table" then
        for _, anchor in pairs(frame.privateAuraAnchors) do
            if anchor then
                if type(anchor.auraFrames) == "table" then
                    addCollection(anchor.auraFrames)
                end
                if anchor.AuraContainer and type(anchor.AuraContainer.auraFrames) == "table" then
                    addCollection(anchor.AuraContainer.auraFrames)
                end
            end
        end
    end

    local processed = {}
    for _, collection in ipairs(auraCollections) do
        for _, aura in ipairs(collection) do
            if aura and not processed[aura] then
                processed[aura] = true
                local icon = aura.Icon or aura.icon or aura.IconTexture
                if icon then
                    captureDebuffBorderDefaults(aura, icon)
                end
                if icon and icon.SetSize and width and height then
                    icon:SetSize(width, height)
                end
                if icon then
                    resizeDebuffBorder(aura, icon, width, height)
                end
                if icon then
                    if borderEnabled then
                        setDefaultAuraBorderVisible(aura, false)
                        addon.ApplyIconBorderStyle(icon, borderStyle, {
                            thickness = borderThickness,
                            color = tintColor,
                            tintEnabled = borderTintEnabled,
                            db = db,
                            thicknessKey = "borderThickness",
                            tintColorKey = "borderTintColor",
                            defaultThickness = settings.borderThickness and settings.borderThickness.default or 1,
                        })
                    else
                        setDefaultAuraBorderVisible(aura, true)
                        clearCustomBorder(icon)
                    end
                end

                -- Text styling: stacks/applications and remaining duration
                local stacksFS = aura.Count or aura.count or aura.Applications
                if stacksFS and stacksFS.GetObjectType and stacksFS:GetObjectType() == "FontString" then
                    applyAuraText(stacksFS, "textStacks", 16, aura)
                end

                local durationFS = aura.Duration
                if durationFS and durationFS.GetObjectType and durationFS:GetObjectType() == "FontString" then
                    applyAuraText(durationFS, "textDuration", 16, aura)
                end
            end
        end
    end
end

local function ApplyAuraFrameStyling(self)
    local frame = _G[self.frameName]
    if not frame or not frame.AuraContainer then return end

    -- Ensure we stay up to date when Blizzard rebuilds aura buttons
    if hooksecurefunc and not frame._ScooterAuraHooked then
        local componentId = self.id
        hooksecurefunc(frame, "UpdateAuraButtons", function()
            if addon and addon.Components and addon.Components[componentId] and addon.ApplyAuraFrameVisualsFor then
                addon.ApplyAuraFrameVisualsFor(addon.Components[componentId])
            end
        end)
        frame._ScooterAuraHooked = true
    end

    if addon and addon.ApplyAuraFrameVisualsFor then
        addon.ApplyAuraFrameVisualsFor(self)
    end

    -- Opacity priority (With Target > In Combat > Out of Combat), mirroring Cooldown Manager semantics
    local container = frame.AuraContainer or frame
    if container then
        local baseRaw = self.db and self.db.opacity
        if baseRaw == nil and self.settings and self.settings.opacity then
            baseRaw = self.settings.opacity.default
        end
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
        local appliedOpacity = hasTarget and tgtOpacity or (PlayerInCombat() and baseOpacity or oocOpacity)
        if container.SetAlpha then
            pcall(container.SetAlpha, container, appliedOpacity / 100)
        end
    end
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
            -- Marker: enable Text section in settings UI for this component
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(trackedBuffs)

    -- Player Buffs/Debuffs (Aura Frame system). These are separate from the Cooldown Viewer "Tracked Buffs"
    -- component and operate on BuffFrame / DebuffFrame directly.
    local buffs = Component:New({
        id = "buffs",
        name = "Buffs",
        frameName = "BuffFrame",
        settings = {
            -- Positioning (Edit Mode-backed)
            orientation = { type = "editmode", default = "H", ui = {
                label = "Orientation", widget = "dropdown",
                values = { H = "Horizontal", V = "Vertical" },
                section = "Positioning", order = 1,
            }},
            iconWrap = { type = "editmode", default = "down", ui = {
                label = "Icon Wrap", widget = "dropdown",
                values = { down = "Down", up = "Up" },
                section = "Positioning", order = 2, dynamicValues = true,
            }},
            direction = { type = "editmode", default = "left", ui = {
                label = "Icon Direction", widget = "dropdown",
                values = { left = "Left", right = "Right" },
                section = "Positioning", order = 3, dynamicValues = true,
            }},
            iconPadding = { type = "editmode", default = 10, ui = {
                label = "Icon Padding", widget = "slider",
                min = 5, max = 15, step = 1,
                section = "Positioning", order = 4,
            }},
            iconLimit = { type = "editmode", default = 11, ui = {
                label = "Icon Limit", widget = "slider",
                min = 2, max = 32, step = 1,
                section = "Positioning", order = 5,
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider",
                min = -1000, max = 1000, step = 1,
                section = "Positioning", order = 6,
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider",
                min = -1000, max = 1000, step = 1,
                section = "Positioning", order = 7,
            }},
            -- Sizing (Edit Mode-backed scale + addon-only width/height)
            iconSize = { type = "editmode", default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1,
            }},
            iconWidth = { type = "addon", default = 30, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 48, step = 1, section = "Sizing", order = 2,
            }},
            iconHeight = { type = "addon", default = 30, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 48, step = 1, section = "Sizing", order = 3,
            }},
            -- Border
            borderEnable = { type = "addon", default = false, ui = {
                label = "Use Custom Border", widget = "checkbox", section = "Border", order = 1,
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2,
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3,
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 4,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Border", order = 5,
            }},
            -- Visibility (addon-only opacity controls; matches Cooldown Manager priority order)
            opacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 1,
            }},
            opacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 2,
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3,
            }},
            hideCollapseButton = { type = "addon", default = false, ui = {
                label = "Hide Expand/Collapse Button", widget = "checkbox", section = "Misc", order = 10,
            }},
            -- Marker: enable Text section (Stacks / Duration tabs) in settings UI
            supportsText = { type = "addon", default = true },
        },
        -- Marker: Visibility section will be filled in later
        supportsEmptyVisibilitySection = true,
        ApplyStyling = ApplyAuraFrameStyling,
    })
    self:RegisterComponent(buffs)

    local debuffs = Component:New({
        id = "debuffs",
        name = "Debuffs",
        frameName = "DebuffFrame",
        settings = {
            -- Positioning (Edit Mode-backed)
            orientation = { type = "editmode", default = "H", ui = {
                label = "Orientation", widget = "dropdown",
                values = { H = "Horizontal", V = "Vertical" },
                section = "Positioning", order = 1,
            }},
            iconWrap = { type = "editmode", default = "down", ui = {
                label = "Icon Wrap", widget = "dropdown",
                values = { down = "Down", up = "Up" },
                section = "Positioning", order = 2, dynamicValues = true,
            }},
            direction = { type = "editmode", default = "left", ui = {
                label = "Icon Direction", widget = "dropdown",
                values = { left = "Left", right = "Right" },
                section = "Positioning", order = 3, dynamicValues = true,
            }},
            iconPadding = { type = "editmode", default = 10, ui = {
                label = "Icon Padding", widget = "slider",
                min = 5, max = 15, step = 1,
                section = "Positioning", order = 4,
            }},
            iconLimit = { type = "editmode", default = 8, ui = {
                label = "Icon Limit", widget = "slider",
                min = 1, max = 16, step = 1,
                section = "Positioning", order = 5,
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider",
                min = -1000, max = 1000, step = 1,
                section = "Positioning", order = 6,
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider",
                min = -1000, max = 1000, step = 1,
                section = "Positioning", order = 7,
            }},
            -- Sizing (Edit Mode-backed scale + addon-only width/height)
            iconSize = { type = "editmode", default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1,
            }},
            iconWidth = { type = "addon", default = 30, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 48, step = 1, section = "Sizing", order = 2,
            }},
            iconHeight = { type = "addon", default = 30, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 48, step = 1, section = "Sizing", order = 3,
            }},
            -- Visibility (addon-only opacity controls; matches Cooldown Manager priority order)
            opacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 1,
            }},
            opacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 2,
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3,
            }},
            supportsText = { type = "addon", default = true },
        },
        -- Marker: Visibility section will be filled in later
        supportsEmptyVisibilitySection = true,
        ApplyStyling = ApplyAuraFrameStyling,
    })
    self:RegisterComponent(debuffs)

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
					label = "Opacity in Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 99
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
    if addon.ApplyAllUnitFrameNameLevelText then
        addon.ApplyAllUnitFrameNameLevelText()
    end
    -- Apply Unit Frame bar textures (Health/Power) if configured
    if addon.ApplyAllUnitFrameBarTextures then
        addon.ApplyAllUnitFrameBarTextures()
    end
    -- Apply Unit Frame portrait positioning if configured
    if addon.ApplyAllUnitFramePortraits then
        addon.ApplyAllUnitFramePortraits()
    end
    -- Apply Unit Frame Cast Bar positioning (Target/Focus) if configured
    if addon.ApplyAllUnitFrameCastBars then
        addon.ApplyAllUnitFrameCastBars()
    end
    -- Apply Unit Frame Buffs & Debuffs positioning/sizing (Target/Focus) if configured
    if addon.ApplyAllUnitFrameBuffsDebuffs then
        addon.ApplyAllUnitFrameBuffsDebuffs()
    end
    -- Apply Unit Frame overall visibility (opacity) per unit if configured
    if addon.ApplyAllUnitFrameVisibility then
        addon.ApplyAllUnitFrameVisibility()
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
    -- Cache for resolved health text fontstrings per unit so combat-time hooks stay cheap.
    addon._ufHealthTextFonts = addon._ufHealthTextFonts or {}

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

    -- Resolve health bar for this unit
    local function resolveHealthBarForVisibility(frame, unit)
        if unit == "Pet" then return _G.PetFrameHealthBar end
        if frame and frame.HealthBarsContainer and frame.HealthBarsContainer.HealthBar then
            return frame.HealthBarsContainer.HealthBar
        end
        -- Try direct paths
        if unit == "Player" then
            local root = _G.PlayerFrame
            if root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar then
                return root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
            end
        elseif unit == "Target" then
            local root = _G.TargetFrame
            if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar then
                return root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            end
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar then
                return root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            end
        end
        return nil
    end

    -- Helper: determine whether the current player's spec uses an Alternate Power Bar.
    -- We intentionally key off spec IDs so the check is cheap and future‑proof.
    -- Specs covered (per user guidance):
    --   - Balance Druid      (specID = 102, class = DRUID)
    --   - Shadow Priest      (specID = 258, class = PRIEST)
    --   - Brewmaster Monk    (specID = 268, class = MONK)
    --   - Elemental Shaman   (specID = 262, class = SHAMAN)
    local function playerHasAlternatePowerBar()
        if not UnitClass or not GetSpecialization or not GetSpecializationInfo then
            return false
        end
        local _, classToken = UnitClass("player")
        if not classToken then
            return false
        end
        local specIndex = GetSpecialization()
        if not specIndex then
            return false
        end
        local specID = select(1, GetSpecializationInfo(specIndex))
        if not specID then
            return false
        end

        -- Map of class -> set of specIDs that use the global AlternatePowerBar.
        local altSpecsByClass = {
            DRUID  = { [102] = true },  -- Balance
            PRIEST = { [258] = true },  -- Shadow
            MONK   = { [268] = true },  -- Brewmaster
            SHAMAN = { [262] = true },  -- Elemental
        }

        local classSpecs = altSpecsByClass[classToken]
        return classSpecs and classSpecs[specID] or false
    end

    -- Expose for UI modules (builders.lua) to gate the Alternate Power Bar section.
    addon.UnitFrames_PlayerHasAlternatePowerBar = playerHasAlternatePowerBar

    -- Hook UpdateTextString to reapply visibility after Blizzard's updates.
    -- IMPORTANT: Use hooksecurefunc so we don't replace the method and taint
    -- secure StatusBar instances used by Blizzard (Combat Log, unit frames, etc.).
    local function hookHealthBarUpdateTextString(bar, unit)
        if not bar or bar._ScooterHealthTextVisibilityHooked then return end
        bar._ScooterHealthTextVisibilityHooked = true
        if _G.hooksecurefunc then
            _G.hooksecurefunc(bar, "UpdateTextString", function(self, ...)
                if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then
                    addon.ApplyUnitFrameHealthTextVisibilityFor(unit)
                end
            end)
        end
    end

    local function applyForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        db.unitFrames[unit] = db.unitFrames[unit] or {}
        local cfg = db.unitFrames[unit]
        local frame = getUnitFrameFor(unit)
        if not frame then return end
        
        -- Resolve health bar and hook its UpdateTextString if not already hooked
        local hb = resolveHealthBarForVisibility(frame, unit)
        if hb then
            hookHealthBarUpdateTextString(hb, unit)
        end
        
		local leftFS
		local rightFS
		if unit == "Pet" then
			leftFS = _G.PetFrameHealthBarTextLeft or (frame.HealthBarsContainer and frame.HealthBarsContainer.LeftText)
			rightFS = _G.PetFrameHealthBarTextRight or (frame.HealthBarsContainer and frame.HealthBarsContainer.RightText)
		end
        -- Full resolution path (may scan children/regions). This should only run during
        -- explicit styling passes (ApplyStyles), not on every health text update.
		leftFS = leftFS
            or (frame.HealthBarsContainer and frame.HealthBarsContainer.LeftText)
            or findFontStringByNameHint(frame, "HealthBarsContainer.LeftText")
            or findFontStringByNameHint(frame, ".LeftText")
            or findFontStringByNameHint(frame, "HealthBarTextLeft")
		rightFS = rightFS
            or (frame.HealthBarsContainer and frame.HealthBarsContainer.RightText)
            or findFontStringByNameHint(frame, "HealthBarsContainer.RightText")
            or findFontStringByNameHint(frame, ".RightText")
            or findFontStringByNameHint(frame, "HealthBarTextRight")

        -- Cache resolved fontstrings so combat-time hooks can avoid expensive scans.
        addon._ufHealthTextFonts[unit] = {
            leftFS = leftFS,
            rightFS = rightFS,
        }

        -- Apply current visibility once as part of the styling pass.
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

    -- Lightweight visibility-only function used by UpdateTextString hooks.
    function addon.ApplyUnitFrameHealthTextVisibilityFor(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        db.unitFrames[unit] = db.unitFrames[unit] or {}
        local cfg = db.unitFrames[unit]

        local cache = addon._ufHealthTextFonts and addon._ufHealthTextFonts[unit]
        if not cache then
            -- If we haven't resolved fonts yet this session, skip work here.
            -- They will be resolved during the next ApplyStyles() pass.
            return
        end

        local leftFS = cache.leftFS
        local rightFS = cache.rightFS

        if leftFS and leftFS.SetShown then
            pcall(leftFS.SetShown, leftFS, not not (not cfg.healthPercentHidden))
        end
        if rightFS and rightFS.SetShown then
            pcall(rightFS.SetShown, rightFS, not not (not cfg.healthValueHidden))
        end
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
    -- Cache for resolved power text fontstrings per unit so combat-time hooks stay cheap.
    addon._ufPowerTextFonts = addon._ufPowerTextFonts or {}

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

	-- Resolve the content main frame for anchoring name backdrop
	local function resolveUFContentMain_NLT(unit)
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

	-- Resolve the Health Bar status bar for anchoring name backdrop
	local function resolveHealthBar_NLT(unit)
		if unit == "Pet" then return _G.PetFrameHealthBar end
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root
				and root.PlayerFrameContent
				and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		end
		return nil
	end

	-- Resolve power bar for this unit
	local function resolvePowerBarForVisibility(frame, unit)
		if unit == "Pet" then return _G.PetFrameManaBar end
		if frame and frame.ManaBar then return frame.ManaBar end
		-- Try direct paths
		if unit == "Player" then
			local root = _G.PlayerFrame
			if root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
				and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar then
				return root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
			end
		elseif unit == "Target" then
			local root = _G.TargetFrame
			if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.ManaBar then
				return root.TargetFrameContent.TargetFrameContentMain.ManaBar
			end
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.ManaBar then
				return root.TargetFrameContent.TargetFrameContentMain.ManaBar
			end
		end
		return nil
	end

	-- Hook UpdateTextString to reapply visibility after Blizzard's updates.
	-- Use hooksecurefunc so we don't replace the method and taint secure StatusBars.
	local function hookPowerBarUpdateTextString(bar, unit)
		if not bar or bar._ScooterPowerTextVisibilityHooked then return end
		bar._ScooterPowerTextVisibilityHooked = true
		if _G.hooksecurefunc then
			_G.hooksecurefunc(bar, "UpdateTextString", function(self, ...)
				if addon and addon.ApplyUnitFramePowerTextVisibilityFor then
					addon.ApplyUnitFramePowerTextVisibilityFor(unit)
				end
			end)
		end
	end

	local function applyForUnit(unit)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		local cfg = db.unitFrames[unit]
		local frame = getUnitFrameFor(unit)
		if not frame then return end

		-- Resolve power bar and hook its UpdateTextString if not already hooked
		local pb = resolvePowerBarForVisibility(frame, unit)
		if pb then
			hookPowerBarUpdateTextString(pb, unit)
		end

		-- Attempt to resolve power bar text regions
		local leftFS
		local rightFS
		if unit == "Pet" then
			-- Pet uses standalone globals more often
			leftFS = _G.PetFrameManaBarTextLeft
			rightFS = _G.PetFrameManaBarTextRight
		end

        -- Full resolution path (may scan children/regions). This should only run during
        -- explicit styling passes (ApplyStyles), not on every power text update.
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

        -- Cache resolved fontstrings so combat-time hooks can avoid expensive scans.
        addon._ufPowerTextFonts[unit] = {
            leftFS = leftFS,
            rightFS = rightFS,
        }

		-- Visibility: tolerate missing LeftText on some classes/specs (no-op)
		local powerBarHidden = (cfg.powerBarHidden == true)
		if leftFS and leftFS.SetShown then
			-- When the entire Power Bar is hidden, force all power texts hidden regardless of individual toggles.
			pcall(leftFS.SetShown, leftFS, (not powerBarHidden) and not not (not cfg.powerPercentHidden))
		end
		if rightFS and rightFS.SetShown then
			pcall(rightFS.SetShown, rightFS, (not powerBarHidden) and not not (not cfg.powerValueHidden))
		end

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

    -- Lightweight visibility-only function used by UpdateTextString hooks.
	function addon.ApplyUnitFramePowerTextVisibilityFor(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        db.unitFrames[unit] = db.unitFrames[unit] or {}
        local cfg = db.unitFrames[unit]

        local cache = addon._ufPowerTextFonts and addon._ufPowerTextFonts[unit]
        if not cache then
            -- If we haven't resolved fonts yet this session, skip work here.
            -- They will be resolved during the next ApplyStyles() pass.
            return
        end

        local leftFS = cache.leftFS
        local rightFS = cache.rightFS

		local powerBarHidden = (cfg.powerBarHidden == true)

        -- Visibility: tolerate missing LeftText on some classes/specs (no-op)
        if leftFS and leftFS.SetShown then
            pcall(leftFS.SetShown, leftFS, (not powerBarHidden) and not not (not cfg.powerPercentHidden))
        end
        if rightFS and rightFS.SetShown then
            pcall(rightFS.SetShown, rightFS, (not powerBarHidden) and not not (not cfg.powerValueHidden))
        end
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

--- Unit Frames: Apply Name & Level Text styling (visibility, font, size, style, color, offset)
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
		if unit == "Player" then idx = EM.Player
		elseif unit == "Target" then idx = EM.Target
		elseif unit == "Focus" then idx = EM.Focus
		elseif unit == "Pet" then idx = EM.Pet
		end
		if not idx then return nil end
		return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
	end

	-- Local resolvers for this block (backdrop anchoring helpers)
	local function resolveUFContentMain_NLT(unit)
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

	local function resolveHealthBar_NLT(unit)
		if unit == "Pet" then return _G.PetFrameHealthBar end
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root
				and root.PlayerFrameContent
				and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		end
		return nil
	end

	local function findFontStringByNameHint(root, hint)
		if not (root and hint) then return nil end
		local target = nil
		local function scan(obj)
			if not obj then return end
			if target then return end
			if obj.IsObjectType and obj:IsObjectType("FontString") then
				local nm = obj.GetName and obj:GetName() or ""
				if type(nm) == "string" and string.find(nm, hint, 1, true) then
					target = obj
					return
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

		-- Resolve Name and Level FontStrings
		local nameFS, levelFS
		
	-- Try direct child access first (most common)
	if unit == "Player" then
		nameFS = _G.PlayerName
		levelFS = _G.PlayerLevelText
	elseif unit == "Target" then
		-- Target uses nested content structure
		local targetFrame = _G.TargetFrame
		if targetFrame and targetFrame.TargetFrameContent and targetFrame.TargetFrameContent.TargetFrameContentMain then
			nameFS = targetFrame.TargetFrameContent.TargetFrameContentMain.Name
			levelFS = targetFrame.TargetFrameContent.TargetFrameContentMain.LevelText
		end
	elseif unit == "Focus" then
		-- Focus reuses Target's content structure naming (TargetFrameContent, not FocusFrameContent!)
		local focusFrame = _G.FocusFrame
		if focusFrame and focusFrame.TargetFrameContent and focusFrame.TargetFrameContent.TargetFrameContentMain then
			nameFS = focusFrame.TargetFrameContent.TargetFrameContentMain.Name
			levelFS = focusFrame.TargetFrameContent.TargetFrameContentMain.LevelText
		end
	elseif unit == "Pet" then
		-- Pet uses global FontString names (PetName is a direct global, not nested)
		nameFS = _G.PetName
		-- Pet frame doesn't have a LevelText FontString (no level display)
		levelFS = nil
	end

		-- Fallback: search by name hints
		if not nameFS then nameFS = findFontStringByNameHint(frame, "Name") end
		if not levelFS then levelFS = findFontStringByNameHint(frame, "LevelText") end

		-- Apply visibility
		if nameFS and nameFS.SetShown then pcall(nameFS.SetShown, nameFS, not cfg.nameTextHidden) end
		if levelFS and levelFS.SetShown then pcall(levelFS.SetShown, levelFS, not cfg.levelTextHidden) end

		-- Apply styling
		addon._ufNameLevelTextBaselines = addon._ufNameLevelTextBaselines or {}
		local function ensureBaseline(fs, key)
			addon._ufNameLevelTextBaselines[key] = addon._ufNameLevelTextBaselines[key] or {}
			local b = addon._ufNameLevelTextBaselines[key]
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

		-- Optional: widen the name container for Target/Focus to reduce truncation.
		-- This adjusts the Name FontString's width and anchor so the right edge
		-- stays aligned relative to the ReputationColor strip while growing left.
		addon._ufNameContainerBaselines = addon._ufNameContainerBaselines or {}
		local function applyNameContainerWidth(unitKey, nameFSLocal)
			if not nameFSLocal then return end
			-- Only Target/Focus currently support this control; Player/Pet keep stock behavior.
			if unitKey ~= "Target" and unitKey ~= "Focus" then return end

			local unitCfg = db.unitFrames[unitKey] or {}
			local styleCfg = unitCfg.textName or {}
			local pct = tonumber(styleCfg.containerWidthPct) or 100

			-- Clamp slider semantics to [80,150] (matches UI slider).
			if pct < 80 then pct = 80 elseif pct > 150 then pct = 150 end

			local key = unitKey .. ":nameContainer"
			local baseline = addon._ufNameContainerBaselines[key]
			if not baseline then
				baseline = {}
				baseline.width = nameFSLocal.GetWidth and nameFSLocal:GetWidth() or 90
				if nameFSLocal.GetPoint then
					local p, relTo, rp, x, y = nameFSLocal:GetPoint(1)
					baseline.point = p or "TOPLEFT"
					baseline.relTo = relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame
					baseline.relPoint = rp or baseline.point
					baseline.x = tonumber(x) or 0
					baseline.y = tonumber(y) or 0
				else
					baseline.point, baseline.relTo, baseline.relPoint, baseline.x, baseline.y =
						"TOPLEFT", (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame, "TOPLEFT", 0, 0
				end
				addon._ufNameContainerBaselines[key] = baseline
			end

			-- When at 100%, restore original width/anchor and bail.
			if pct == 100 then
				if nameFSLocal.ClearAllPoints and nameFSLocal.SetPoint and baseline.width then
					nameFSLocal:SetWidth(baseline.width)
					nameFSLocal:ClearAllPoints()
					nameFSLocal:SetPoint(
						baseline.point or "TOPLEFT",
						baseline.relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame,
						baseline.relPoint or baseline.point or "TOPLEFT",
						baseline.x or 0,
						baseline.y or 0
					)
				end
				return
			end

			local baseWidth = baseline.width or (nameFSLocal.GetWidth and nameFSLocal:GetWidth()) or 90
			local newWidth = math.floor((baseWidth * pct / 100) + 0.5)

			-- Default behavior: scale the width and preserve left anchor.
			local point, relTo, relPoint, xOff, yOff =
				baseline.point, baseline.relTo, baseline.relPoint, baseline.x, baseline.y

			-- If we can find the canonical ReputationColor strip, keep right margin stable
			-- by nudging the TOPLEFT X offset leftwards as width grows.
			local main = resolveUFContentMain_NLT(unitKey)
			local rep = main and main.ReputationColor or nil
			if rep and relTo == rep and (point == "TOPLEFT" or point == "LEFT") then
				-- Right edge offset remains unchanged; only the left edge moves.
				local delta = newWidth - baseWidth
				xOff = (xOff or 0) - delta
			end

			if nameFSLocal.SetWidth then
				nameFSLocal:SetWidth(newWidth)
			end
			if nameFSLocal.ClearAllPoints and nameFSLocal.SetPoint then
				nameFSLocal:ClearAllPoints()
				nameFSLocal:SetPoint(
					point or "TOPLEFT",
					relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame,
					relPoint or point or "TOPLEFT",
					xOff or 0,
					yOff or 0
				)
			end
		end

	local function applyTextStyle(fs, styleCfg, baselineKey)
		if not fs or not styleCfg then return end
		local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
		local size = tonumber(styleCfg.size) or 14
		local outline = tostring(styleCfg.style or "OUTLINE")
		if fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
		-- Determine color based on colorMode
		local c = nil
		local colorMode = styleCfg.colorMode or "default"
		if colorMode == "class" then
			-- Class Color: use player's class color
			if addon.GetClassColorRGB then
				local unitForClass = unit == "Player" and "player" or (unit == "Target" and "target" or (unit == "Focus" and "focus" or "pet"))
				local cr, cg, cb = addon.GetClassColorRGB(unitForClass)
				c = { cr or 1, cg or 1, cb or 1, 1 }
			else
				c = {1.0, 0.82, 0.0, 1} -- fallback to default yellow
			end
		elseif colorMode == "custom" then
			-- Custom: use stored color
			c = styleCfg.color or {1.0, 0.82, 0.0, 1}
		else
			-- Default: use Blizzard's default yellow color (1.0, 0.82, 0.0) instead of white
			c = styleCfg.color or {1.0, 0.82, 0.0, 1}
		end
		if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
		local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
		local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
		if fs.ClearAllPoints and fs.SetPoint then
			local b = ensureBaseline(fs, baselineKey)
			fs:ClearAllPoints()
			fs:SetPoint(b.point or "CENTER", b.relTo or (fs.GetParent and fs:GetParent()) or frame, b.relPoint or b.point or "CENTER", (b.x or 0) + ox, (b.y or 0) + oy)
		end
	end

	if nameFS then
		applyTextStyle(nameFS, cfg.textName or {}, unit .. ":name")
		-- Apply optional name container width adjustment (Target/Focus only).
		applyNameContainerWidth(unit, nameFS)
	end
	if levelFS then 
		applyTextStyle(levelFS, cfg.textLevel or {}, unit .. ":level")
		
		-- For Player level text, Blizzard uses SetVertexColor (not SetTextColor!) which requires special handling
		-- Blizzard constantly resets the level color, so we intercept SetVertexColor calls
		if unit == "Player" and levelFS and cfg.textLevel and cfg.textLevel.color then
			-- Install a hook directly on the frame's SetVertexColor to override Blizzard's calls
			if not levelFS._scooterVertexColorHooked then
				levelFS._scooterVertexColorHooked = true
				levelFS._scooterOrigSetVertexColor = levelFS.SetVertexColor
				
				levelFS.SetVertexColor = function(self, r, g, b, a)
					-- Check if we have a custom color configured
					local db = addon and addon.db and addon.db.profile
					if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.textLevel and db.unitFrames.Player.textLevel.color then
						local c = db.unitFrames.Player.textLevel.color
						-- Use our custom color instead of Blizzard's
						levelFS._scooterOrigSetVertexColor(self, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
					else
						-- No custom color, use Blizzard's
						levelFS._scooterOrigSetVertexColor(self, r, g, b, a)
					end
				end
			end
			
		-- Apply our color immediately (use Blizzard's default yellow)
		local c = cfg.textLevel.color or {1.0,0.82,0.0,1}
			if levelFS._scooterOrigSetVertexColor then
				pcall(levelFS._scooterOrigSetVertexColor, levelFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
			end
		elseif unit == "Player" and levelFS and levelFS._scooterVertexColorHooked then
			-- Custom color disabled, restore original behavior
			if levelFS._scooterOrigSetVertexColor then
				levelFS.SetVertexColor = levelFS._scooterOrigSetVertexColor
				levelFS._scooterVertexColorHooked = nil
				levelFS._scooterOrigSetVertexColor = nil
			end
		end
	end
		-- Name Backdrop: texture strip anchored to top edge of the Health Bar at the lowest z-order
		do
			local main = resolveUFContentMain_NLT(unit)
			local hb = resolveHealthBar_NLT(unit)
			local cfg = db.unitFrames[unit] or {}
			local texKey = cfg.nameBackdropTexture or ""
			local enabledBackdrop = (cfg.nameBackdropEnabled == nil) and true or not not cfg.nameBackdropEnabled
			local colorMode = cfg.nameBackdropColorMode or "default" -- default | texture | custom
			local tint = cfg.nameBackdropTint or {1,1,1,1}
			local opacity = tonumber(cfg.nameBackdropOpacity) or 50
			if opacity < 0 then opacity = 0 elseif opacity > 100 then opacity = 100 end
			local opacityAlpha = opacity / 100
			local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
			local holderKey = "ScooterNameBackdrop_" .. tostring(unit)
			local tex = main and main[holderKey] or nil
			if main and not tex then
				tex = main:CreateTexture(nil, "BACKGROUND", nil, -8)
				main[holderKey] = tex
			end
			if tex then
				if hb and resolvedPath and enabledBackdrop then
					-- Compute a baseline width and apply user width percentage independently of Health Bar width
					local base = tonumber(cfg.nameBackdropBaseWidth)
				if not base or base <= 0 then
					local hbw = (hb.GetWidth and hb:GetWidth()) or 0
					base = hbw
					-- Persist baseline for stability across live changes
					cfg.nameBackdropBaseWidth = base
				end
					local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
					if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
					local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))
					tex:ClearAllPoints()
					-- Anchor to RIGHT edge for Target/Focus so the strip grows left from the portrait side
					if unit == "Target" or unit == "Focus" then
						tex:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
					else
						tex:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 0, 0)
					end
					tex:SetSize(desiredWidth, 16)
					tex:SetTexture(resolvedPath)
					if tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", -8) end
					if tex.SetHorizTile then tex:SetHorizTile(false) end
					if tex.SetVertTile then tex:SetVertTile(false) end
					if tex.SetTexCoord then tex:SetTexCoord(0,1,0,1) end
					-- Color behavior mirrors bar backgrounds:
					--  - texture  => preserve original colors (white vertex)
					--  - default  => use default background color (black)
					--  - custom   => use tint (including alpha)
					do
						local r, g, b = 1, 1, 1
						if colorMode == "texture" then
							r, g, b = 1, 1, 1
						elseif colorMode == "default" then
							-- Unit frame default background is black
							r, g, b = 0, 0, 0
						elseif colorMode == "custom" and type(tint) == "table" then
							r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
						end
						if tex.SetVertexColor then tex:SetVertexColor(r, g, b, 1) end
						if tex.SetAlpha then tex:SetAlpha(opacityAlpha) end
					end
					tex:Show()
				else
					tex:Hide()
				end
			end
		end
		-- Name Backdrop Border: draw a border around the same region
		do
			local main = resolveUFContentMain_NLT(unit)
			local hb = resolveHealthBar_NLT(unit)
			local cfg = db.unitFrames[unit] or {}
			local styleKey = cfg.nameBackdropBorderStyle or "square"
			local localEnabled = (cfg.nameBackdropBorderEnabled == nil) and true or not not cfg.nameBackdropBorderEnabled
			local globalEnabled = not not (cfg.useCustomBorders ~= false)
			local useBorders = localEnabled and globalEnabled
			local thickness = tonumber(cfg.nameBackdropBorderThickness) or 1
			if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
			local inset = tonumber(cfg.nameBackdropBorderInset) or 0
			if inset < -8 then inset = -8 elseif inset > 8 then inset = 8 end
			local tintEnabled = not not cfg.nameBackdropBorderTintEnable
			local tintColor = cfg.nameBackdropBorderTintColor or {1,1,1,1}

			local borderKey = "ScooterNameBackdropBorder_" .. tostring(unit)
			local borderFrame = main and main[borderKey] or nil
			if main and not borderFrame then
				local template = BackdropTemplateMixin and "BackdropTemplate" or nil
				borderFrame = CreateFrame("Frame", nil, main, template)
				main[borderKey] = borderFrame
			end
			if borderFrame and hb and useBorders then
				-- Match border width to the same baseline-derived width as backdrop
				local base = tonumber(cfg.nameBackdropBaseWidth)
				if not base or base <= 0 then
					local hbw = (hb.GetWidth and hb:GetWidth()) or 0
					base = hbw
					cfg.nameBackdropBaseWidth = base
				end
				local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
				if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
				local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))
				borderFrame:ClearAllPoints()
				-- Anchor to RIGHT edge for Target/Focus so the border grows left from the portrait side
				if unit == "Target" or unit == "Focus" then
					borderFrame:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
				else
					borderFrame:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 0, 0)
				end
				borderFrame:SetSize(desiredWidth, 16)
				local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey) or nil
				local styleTexture = styleDef and styleDef.texture or nil
				local thicknessScale = (styleDef and styleDef.thicknessScale) or 1.0
				local DEFAULT_REF = 18
				local DEFAULT_MULT = 1.35
				local h = (borderFrame.GetHeight and borderFrame:GetHeight()) or 16
				if h < 1 then h = DEFAULT_REF end
				local edgeSize = math.floor((thickness * DEFAULT_MULT * thicknessScale * (h / DEFAULT_REF)) + 0.5)
				if edgeSize < 1 then edgeSize = 1 elseif edgeSize > 48 then edgeSize = 48 end

				if styleKey == "square" or not styleTexture then
					-- Clear any previous backdrop-based border before applying square edges
					if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
					if addon.Borders and addon.Borders.ApplySquare then
						addon.Borders.ApplySquare(borderFrame, {
							size = edgeSize,
							color = tintEnabled and (tintColor or {1,1,1,1}) or {1,1,1,1},
							layer = "OVERLAY",
							layerSublevel = 7,
							expand = -(inset),
						})
					end
					borderFrame:Show()
				else
					-- Clear any previous square edges before applying a backdrop-based border
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
					local ok = false
					if borderFrame.SetBackdrop then
						local insetPx = math.max(0, math.floor(edgeSize * 0.65 + 0.5) + (tonumber(inset) or 0))
						local bd = {
							bgFile = nil,
							edgeFile = styleTexture,
							tile = false,
							edgeSize = edgeSize,
							insets = { left = insetPx, right = insetPx, top = insetPx, bottom = insetPx },
						}
						ok = pcall(borderFrame.SetBackdrop, borderFrame, bd)
					end
					if ok and borderFrame.SetBackdropBorderColor then
						local c = tintEnabled and tintColor or {1,1,1,1}
						borderFrame:SetBackdropBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
					end
					if not ok then
						borderFrame:Hide()
					else
						borderFrame:Show()
					end
				end
			elseif borderFrame then
				-- Fully clear both border types on disable
				if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
				if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
				borderFrame:Hide()
			end
		end
	end

	function addon.ApplyUnitFrameNameLevelTextFor(unit)
		applyForUnit(unit)
	end

	function addon.ApplyAllUnitFrameNameLevelText()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
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
            "healthBarBackgroundTexture",
            "healthBarBackgroundColorMode",
            "healthBarBackgroundTint",
            "healthBarBackgroundOpacity",
            "powerBarTexture",
            "powerBarColorMode",
            "powerBarTint",
            "powerBarBackgroundTexture",
            "powerBarBackgroundColorMode",
            "powerBarBackgroundTint",
            "powerBarBackgroundOpacity",
            "powerBarHidden",
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
        -- Never touch protected unit frame hierarchy during combat; doing so taints
        -- later secure operations such as TargetFrameToT:Show().
        if InCombatLockdown and InCombatLockdown() then
            return
        end
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

    -- Resolve the global Alternate Power Bar for the Player frame. This is a standalone
    -- StatusBar named "AlternatePowerBar" managed by Blizzard's AlternatePowerBarBaseMixin.
    local function resolveAlternatePowerBar()
        local bar = _G.AlternatePowerBar
        if bar and bar.GetObjectType and bar:GetObjectType() == "StatusBar" then
            return bar
        end
        return nil
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
        -- Guard against combat lockdown: raising frame levels on protected unit frames
        -- during combat will taint subsequent secure operations (see taint.log).
        if InCombatLockdown and InCombatLockdown() then
            return
        end
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

    -- Get default background color for unit frame bars (fallback when no custom color is set)
    local function getDefaultBackgroundColor(unit, barKind)
        -- Based on Blizzard source: Player frame HealthBar.Background uses BLACK_FONT_COLOR (0, 0, 0)
        -- Target/Focus/Pet don't have explicit Background textures in XML, use black as well
        -- Power bars (ManaBar) don't have Background textures in XML either, use black
        return 0, 0, 0, 1
    end

    -- Optional rectangular overlay for unit frame health bars when the portrait is hidden.
    -- This is used to visually "fill in" the right-side chip on Target/Focus when the
    -- circular portrait is hidden, without replacing the stock StatusBar frame.
    local function updateRectHealthOverlay(unit, bar)
        if not bar or not bar.ScooterRectFill then return end
        if not bar._ScootRectActive then
            bar.ScooterRectFill:Hide()
            return
        end

        local overlay = bar.ScooterRectFill
        local totalWidth = bar:GetWidth() or 0
        local minVal, maxVal = bar:GetMinMaxValues()
        local value = bar:GetValue() or minVal

        if not totalWidth or totalWidth <= 0 or not maxVal or maxVal <= minVal then
            overlay:Hide()
            return
        end

        local frac = (value - minVal) / (maxVal - minVal)
        if frac <= 0 then
            overlay:Hide()
            return
        end
        if frac > 1 then frac = 1 end

        overlay:Show()
        overlay:SetWidth(totalWidth * frac)
        overlay:ClearAllPoints()

        local reverse = not not bar._ScootRectReverseFill
        if reverse then
            overlay:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
            overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        else
            overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        end
    end

    local function ensureRectHealthOverlay(unit, bar, cfg)
        if not bar then return end

        -- Only Target/Focus use this overlay, and only when the portrait is hidden.
        if unit ~= "Target" and unit ~= "Focus" then
            if bar.ScooterRectFill then
                bar._ScootRectActive = false
                bar.ScooterRectFill:Hide()
            end
            return
        end

        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        local ufCfg = db.unitFrames[unit] or {}
        local portraitCfg = ufCfg.portrait or {}
        local hidePortrait = (portraitCfg.hidePortrait == true)

        bar._ScootRectReverseFill = not not cfg.healthBarReverseFill
        bar._ScootRectActive = hidePortrait and true or false

        if not hidePortrait then
            if bar.ScooterRectFill then
                bar.ScooterRectFill:Hide()
            end
            return
        end

        if not bar.ScooterRectFill then
            local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 2)
            overlay:SetVertTile(false)
            overlay:SetHorizTile(false)
            overlay:SetTexCoord(0, 1, 0, 1)
            bar.ScooterRectFill = overlay

            -- Drive overlay width from the health bar's own value/size changes.
            if _G.hooksecurefunc and not bar._ScootRectHooksInstalled then
                bar._ScootRectHooksInstalled = true
                _G.hooksecurefunc(bar, "SetValue", function(self)
                    updateRectHealthOverlay(unit, self)
                end)
                _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                    updateRectHealthOverlay(unit, self)
                end)
                if bar.HookScript then
                    bar:HookScript("OnSizeChanged", function(self)
                        updateRectHealthOverlay(unit, self)
                    end)
                end
            end
        end

        -- Copy the current health bar texture/tint so the overlay visually matches.
        local tex = bar:GetStatusBarTexture()
        if tex then
            local okTex, pathOrTex = pcall(tex.GetTexture, tex)
            if okTex and type(pathOrTex) == "string" and pathOrTex ~= "" then
                bar.ScooterRectFill:SetTexture(pathOrTex)
            else
                if bar.ScooterRectFill.SetColorTexture then
                    bar.ScooterRectFill:SetColorTexture(1, 1, 1, 1)
                end
            end

            if tex.GetVertexColor and bar.ScooterRectFill.SetVertexColor then
                local ok, r, g, b, a = pcall(tex.GetVertexColor, tex)
                if ok then
                    bar.ScooterRectFill:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
                else
                    bar.ScooterRectFill:SetVertexColor(1, 1, 1, 1)
                end
            end
        end

        updateRectHealthOverlay(unit, bar)
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
            if bar.SetStatusBarTexture then
                -- Mark this write so any SetStatusBarTexture hook can ignore it (avoid recursion)
                bar._ScootUFInternalTextureWrite = true
                pcall(bar.SetStatusBarTexture, bar, resolvedPath)
                bar._ScootUFInternalTextureWrite = nil
            end
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
            elseif colorMode == "texture" then
                -- Apply white (no tint) to preserve texture's original colors
                r, g, b, a = 1, 1, 1, 1
            elseif colorMode == "default" then
                -- When using a custom texture, "Default" should tint to the stock bar color
				if barKind == "cast" then
					-- Stock cast bar yellow from CastingBarFrame mixin.
					r, g, b, a = 1.0, 0.7, 0.0, 1
				elseif barKind == "health" and addon.GetDefaultHealthColorRGB then
                    local hr, hg, hb = addon.GetDefaultHealthColorRGB()
                    r, g, b, a = hr or 0, hg or 1, hb or 0, 1
                elseif (barKind == "power" or barKind == "altpower") and addon.GetPowerColorRGB then
                    -- Power and Alternate Power bars both use the player's power color for Default.
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
                            bar._ScootUFInternalTextureWrite = true
                            pcall(bar.SetStatusBarTexture, bar, bar._ScootUFOrigAtlas)
                            bar._ScootUFInternalTextureWrite = nil
                        end
                    elseif bar._ScootUFOrigPath then
                        local treatAsAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(bar._ScootUFOrigPath) ~= nil
                        if treatAsAtlas and tex and tex.SetAtlas then
                            pcall(tex.SetAtlas, tex, bar._ScootUFOrigPath, true)
                        elseif bar.SetStatusBarTexture then
                            bar._ScootUFInternalTextureWrite = true
                            pcall(bar.SetStatusBarTexture, bar, bar._ScootUFOrigPath)
                            bar._ScootUFInternalTextureWrite = nil
                        end
                    end
                end
                if barKind == "cast" then
                    -- Use Blizzard's stock cast bar yellow as the default color.
                    -- Based on Blizzard_CastingBarFrame.lua (CastingBarFrameMixin).
                    r, g, b, a = 1.0, 0.7, 0.0, 1
                else
                    local ov = bar._ScootUFOrigVertex or {1,1,1,1}
                    r, g, b, a = ov[1] or 1, ov[2] or 1, ov[3] or 1, ov[4] or 1
                end
            end
            if tex and tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
            if bar.ScooterModBG and bar.ScooterModBG.Hide then pcall(bar.ScooterModBG.Hide, bar.ScooterModBG) end
        end
    end

    -- Expose helpers for other modules (Cast Bar styling, etc.)
    addon._ApplyToStatusBar = applyToBar

    -- Apply background texture and color to a bar
    local function applyBackgroundToBar(bar, backgroundTextureKey, backgroundColorMode, backgroundTint, backgroundOpacity, unit, barKind)
        if not bar then return end
        
        -- Ensure we have a background texture frame at an appropriate sublevel so it appears
        -- behind the status bar fill but remains visible for cast bars.
        --
        -- For generic unit frame bars (health/power), we keep the background very low in the
        -- BACKGROUND stack (-8) so any stock art sits above it if present.
        --
        -- For CastingBarFrame-based bars (Player/Target/Focus cast bars), Blizzard defines a
        -- `Background` texture at BACKGROUND subLevel=2 (see CastingBarFrameBaseTemplate in
        -- wow-ui-source). Our earlier implementation created ScooterModBG at subLevel=-8,
        -- which meant the stock Background completely covered our overlay and made Scooter
        -- backgrounds effectively invisible even though the region existed in Framestack.
        --
        -- To keep behaviour consistent with other bars while making cast bar backgrounds
        -- visible, we render ScooterModBG above the stock Background (subLevel=3) but still
        -- on the BACKGROUND layer so the status bar fill and FX remain on top.
        if not bar.ScooterModBG then
            local layer = "BACKGROUND"
            local sublevel = -8
            if barKind == "cast" then
                sublevel = 3
            end
            bar.ScooterModBG = bar:CreateTexture(nil, layer, nil, sublevel)
            bar.ScooterModBG:SetAllPoints(bar)
        elseif barKind == "cast" then
            -- If we created ScooterModBG earlier (e.g., before cast styling was enabled),
            -- make sure it sits above the stock Background for CastingBarFrame.
            local _, currentSub = bar.ScooterModBG:GetDrawLayer()
            if currentSub == nil or currentSub < 3 then
                bar.ScooterModBG:SetDrawLayer("BACKGROUND", 3)
            end
        end
        
        -- Get opacity (default 50% based on Blizzard's dead/ghost state alpha)
        local opacity = tonumber(backgroundOpacity) or 50
        opacity = math.max(0, math.min(100, opacity)) / 100
        
        -- Check if we're using a custom background texture
        local isCustomTexture = type(backgroundTextureKey) == "string" and backgroundTextureKey ~= "" and backgroundTextureKey ~= "default"
        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(backgroundTextureKey)
        
        if isCustomTexture and resolvedPath then
            -- Apply custom texture
            pcall(bar.ScooterModBG.SetTexture, bar.ScooterModBG, resolvedPath)
            
            -- Apply color based on mode
            local r, g, b, a = 1, 1, 1, 1
            if backgroundColorMode == "custom" and type(backgroundTint) == "table" then
                r, g, b, a = backgroundTint[1] or 1, backgroundTint[2] or 1, backgroundTint[3] or 1, backgroundTint[4] or 1
            elseif backgroundColorMode == "texture" then
                -- Apply white (no tint) to preserve texture's original colors
                r, g, b, a = 1, 1, 1, 1
            elseif backgroundColorMode == "default" then
                r, g, b, a = getDefaultBackgroundColor(unit, barKind)
            end
            
            if bar.ScooterModBG.SetVertexColor then
                pcall(bar.ScooterModBG.SetVertexColor, bar.ScooterModBG, r, g, b, a)
            end
            -- Apply opacity
            if bar.ScooterModBG.SetAlpha then
                pcall(bar.ScooterModBG.SetAlpha, bar.ScooterModBG, opacity)
            end
            bar.ScooterModBG:Show()
        else
            -- Default: always show our background with default black color
            -- We don't rely on Blizzard's stock Background texture since it's hidden by default
            pcall(bar.ScooterModBG.SetTexture, bar.ScooterModBG, nil)
            
            local r, g, b, a = getDefaultBackgroundColor(unit, barKind)
            if backgroundColorMode == "custom" and type(backgroundTint) == "table" then
                r, g, b, a = backgroundTint[1] or 1, backgroundTint[2] or 1, backgroundTint[3] or 1, backgroundTint[4] or 1
            end
            
            if bar.ScooterModBG.SetColorTexture then
                pcall(bar.ScooterModBG.SetColorTexture, bar.ScooterModBG, r, g, b, a)
            end
            -- Apply opacity
            if bar.ScooterModBG.SetAlpha then
                pcall(bar.ScooterModBG.SetAlpha, bar.ScooterModBG, opacity)
            end
            bar.ScooterModBG:Show()
        end
    end

    addon._ApplyBackgroundToStatusBar = applyBackgroundToBar

    local function applyForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        local cfg = db.unitFrames[unit] or {}
        local frame = getUnitFrameFor(unit)
        if not frame then return end
        local hb = resolveHealthBar(frame, unit)
        if hb then
            local colorModeHB = cfg.healthBarColorMode or "default"
            local texKeyHB = cfg.healthBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or "player"
			-- Avoid applying styling to Target/Focus before they exist; Blizzard will reset sizes on first Update
			if (unit == "Target" or unit == "Focus") and _G.UnitExists and not _G.UnitExists(unitId) then
				return
			end
            applyToBar(hb, texKeyHB, colorModeHB, cfg.healthBarTint, "player", "health", unitId)
            
            -- Apply background texture and color for Health Bar
            local bgTexKeyHB = cfg.healthBarBackgroundTexture or "default"
            local bgColorModeHB = cfg.healthBarBackgroundColorMode or "default"
            local bgOpacityHB = cfg.healthBarBackgroundOpacity or 50
            applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
			-- When Target/Focus portraits are hidden, draw a rectangular overlay that fills the
			-- right-side "chip" area using the same texture/tint as the health bar.
			ensureRectHealthOverlay(unit, hb, cfg)
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
            
            -- Apply reverse fill for Target/Focus if configured
            if (unit == "Target" or unit == "Focus") and hb and hb.SetReverseFill then
                local shouldReverse = not not cfg.healthBarReverseFill
                pcall(hb.SetReverseFill, hb, shouldReverse)
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
                                hb:HookScript("OnSizeChanged", function()
                                    if InCombatLockdown and InCombatLockdown() then
                                        return
                                    end
                                    ensureTextAndBorderOrdering(unit)
                                end)
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

            -- Lightweight persistence hook for Player Health Bar color:
            -- If Blizzard later changes the bar's StatusBarColor (e.g., via class/aggro logic),
            -- re-apply the user's configured Foreground Color without re-running full styling.
            if unit == "Player" and not hb._ScootHealthColorHooked and _G.hooksecurefunc then
                hb._ScootHealthColorHooked = true
                _G.hooksecurefunc(hb, "SetStatusBarColor", function(self, ...)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    db.unitFrames = db.unitFrames or {}
                    local cfgP = db.unitFrames.Player or {}
                    local texKey = cfgP.healthBarTexture or "default"
                    local colorMode = cfgP.healthBarColorMode or "default"
                    local tint = cfgP.healthBarTint
                    local unitIdP = "player"
                    -- Only do work when the user has customized either texture or color;
                    -- default settings can safely follow Blizzard's behavior.
                    local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                    local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class")
                    if not hasCustomTexture and not hasCustomColor then
                        return
                    end
                    applyToBar(self, texKey, colorMode, tint, "player", "health", unitIdP)
                end)
            end
		end

        local pb = resolvePowerBar(frame, unit)
        if pb then
            -- Cache combat state once for this styling pass. We avoid all geometry
            -- changes (width/height/anchors/offsets) while in combat to prevent
            -- taint on protected unit frames (see taint.log: TargetFrameToT:Show()).
            local inCombat = InCombatLockdown and InCombatLockdown()
			local powerBarHidden = (cfg.powerBarHidden == true)

			-- Capture original alpha once so we can restore when the bar is un-hidden.
			if pb.GetAlpha and pb._ScootUFOrigPBAlpha == nil then
				local ok, a = pcall(pb.GetAlpha, pb)
				pb._ScootUFOrigPBAlpha = ok and (a or 1) or 1
			end

			-- When the user chooses to hide the Power Bar:
			-- - Fade the StatusBar frame to alpha 0 so the fill/background vanish.
			-- - Hide any ScooterMod-drawn borders/backgrounds associated with this bar.
			if powerBarHidden then
				if pb.SetAlpha then
					pcall(pb.SetAlpha, pb, 0)
				end
				if pb.ScooterModBG and pb.ScooterModBG.SetAlpha then
					pcall(pb.ScooterModBG.SetAlpha, pb.ScooterModBG, 0)
				end
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then
					addon.BarBorders.ClearBarFrame(pb)
				end
				if addon.Borders and addon.Borders.HideAll then
					addon.Borders.HideAll(pb)
				end
			else
				-- Restore alpha when coming back from a hidden state so the bar is visible again.
				if pb._ScootUFOrigPBAlpha and pb.SetAlpha then
					pcall(pb.SetAlpha, pb, pb._ScootUFOrigPBAlpha)
				end
			end
            local colorModePB = cfg.powerBarColorMode or "default"
            local texKeyPB = cfg.powerBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or "player"
            applyToBar(pb, texKeyPB, colorModePB, cfg.powerBarTint, "player", "power", unitId)
            
            -- Apply background texture and color for Power Bar
            local bgTexKeyPB = cfg.powerBarBackgroundTexture or "default"
            local bgColorModePB = cfg.powerBarBackgroundColorMode or "default"
            local bgOpacityPB = cfg.powerBarBackgroundOpacity or 50
            applyBackgroundToBar(pb, bgTexKeyPB, bgColorModePB, cfg.powerBarBackgroundTint, bgOpacityPB, unit, "power")
            
            ensureMaskOnBarTexture(pb, resolvePowerMask(unit))

            -- Apply reverse fill for Target/Focus if configured
            if (unit == "Target" or unit == "Focus") and pb and pb.SetReverseFill then
                local shouldReverse = not not cfg.powerBarReverseFill
                pcall(pb.SetReverseFill, pb, shouldReverse)
            end

            -- Lightweight persistence hooks for Player Power Bar:
            --  - Texture: keep custom texture applied if Blizzard swaps StatusBarTexture.
            --  - Color:   keep Foreground Color (default/class/custom) applied if Blizzard calls SetStatusBarColor.
            if unit == "Player" and _G.hooksecurefunc then
                if not pb._ScootPowerTextureHooked then
                    pb._ScootPowerTextureHooked = true
                    _G.hooksecurefunc(pb, "SetStatusBarTexture", function(self, ...)
                        -- Ignore ScooterMod's own writes to avoid recursion.
                        if self._ScootUFInternalTextureWrite then
                            return
                        end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        db.unitFrames = db.unitFrames or {}
                        local cfgP = db.unitFrames.Player or {}
                        local texKey = cfgP.powerBarTexture or "default"
                        local colorMode = cfgP.powerBarColorMode or "default"
                        local tint = cfgP.powerBarTint
                        -- Only re-apply if the user has configured a non-default texture.
                        if not (type(texKey) == "string" and texKey ~= "" and texKey ~= "default") then
                            return
                        end
                        applyToBar(self, texKey, colorMode, tint, "player", "power", "player")
                    end)
                end
                if not pb._ScootPowerColorHooked then
                    pb._ScootPowerColorHooked = true
                    _G.hooksecurefunc(pb, "SetStatusBarColor", function(self, ...)
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        db.unitFrames = db.unitFrames or {}
                        local cfgP = db.unitFrames.Player or {}
                        local texKey = cfgP.powerBarTexture or "default"
                        local colorMode = cfgP.powerBarColorMode or "default"
                        local tint = cfgP.powerBarTint
                        -- If color mode is "texture", the user wants the texture's original colors;
                        -- in that case we allow Blizzard's SetStatusBarColor to stand.
                        if colorMode == "texture" then
                            return
                        end
                        applyToBar(self, texKey, colorMode, tint, "player", "power", "player")
                    end)
                end
            end

            -- Alternate Power Bar styling (Player-only, class/spec gated)
            if unit == "Player" and addon.UnitFrames_PlayerHasAlternatePowerBar and addon.UnitFrames_PlayerHasAlternatePowerBar() then
                local apb = resolveAlternatePowerBar()
                if apb then
                    -- DB namespace for Alternate Power Bar
                    cfg.altPowerBar = cfg.altPowerBar or {}
                    local acfg = cfg.altPowerBar

                    -- Optional hide toggle
                    local altHidden = (acfg.hidden == true)
                    if apb.GetAlpha and apb._ScootUFOrigAltAlpha == nil then
                        local ok, a = pcall(apb.GetAlpha, apb)
                        apb._ScootUFOrigAltAlpha = ok and (a or 1) or 1
                    end
                    if altHidden then
                        if apb.SetAlpha then pcall(apb.SetAlpha, apb, 0) end
                    else
                        if apb._ScootUFOrigAltAlpha and apb.SetAlpha then
                            pcall(apb.SetAlpha, apb, apb._ScootUFOrigAltAlpha)
                        end
                    end

                    -- Foreground texture / color
                    local altTexKey = acfg.texture or "default"
                    local altColorMode = acfg.colorMode or "default"
                    local altTint = acfg.tint
                    applyToBar(apb, altTexKey, altColorMode, altTint, "player", "altpower", "player")

                    -- Background texture / color / opacity
                    local altBgTexKey = acfg.backgroundTexture or "default"
                    local altBgColorMode = acfg.backgroundColorMode or "default"
                    local altBgOpacity = acfg.backgroundOpacity or 50
                    applyBackgroundToBar(apb, altBgTexKey, altBgColorMode, acfg.backgroundTint, altBgOpacity, unit, "altpower")

                    -- Custom border (shares global Use Custom Borders; Alt Power has its own style/tint/thickness/inset)
                    do
                        -- Global unit-frame switch; borders only draw when this is enabled.
                        local useCustomBorders = not not cfg.useCustomBorders
                        if useCustomBorders then
                            -- Style resolution: prefer Alternate Power–specific, then Power, then Health.
                            local styleKey = acfg.borderStyle
                                or cfg.powerBarBorderStyle
                                or cfg.healthBarBorderStyle

                            -- Tint enable: prefer Alternate Power–specific, then Power, then Health.
                            local tintEnabled
                            if acfg.borderTintEnable ~= nil then
                                tintEnabled = not not acfg.borderTintEnable
                            elseif cfg.powerBarBorderTintEnable ~= nil then
                                tintEnabled = not not cfg.powerBarBorderTintEnable
                            else
                                tintEnabled = not not cfg.healthBarBorderTintEnable
                            end

                            -- Tint color: prefer Alternate Power–specific, then Power, then Health.
                            local baseTint = type(acfg.borderTintColor) == "table" and acfg.borderTintColor
                                or cfg.powerBarBorderTintColor
                                or cfg.healthBarBorderTintColor
                            local tintColor = type(baseTint) == "table" and {
                                baseTint[1] or 1,
                                baseTint[2] or 1,
                                baseTint[3] or 1,
                                baseTint[4] or 1,
                            } or { 1, 1, 1, 1 }

                            -- Thickness / inset: prefer Alternate Power–specific, then Power, then Health.
                            local thickness = tonumber(acfg.borderThickness)
                                or tonumber(cfg.powerBarBorderThickness)
                                or tonumber(cfg.healthBarBorderThickness)
                                or 1
                            if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

                            local inset
                            if acfg.borderInset ~= nil then
                                inset = tonumber(acfg.borderInset) or 0
                            elseif cfg.powerBarBorderInset ~= nil then
                                inset = tonumber(cfg.powerBarBorderInset) or 0
                            else
                                inset = tonumber(cfg.healthBarBorderInset) or 0
                            end

                            if styleKey == "none" or styleKey == nil then
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(apb) end
                            else
                                local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                local color
                                if tintEnabled then
                                    color = tintColor
                                else
                                    if styleDef then
                                        color = { 1, 1, 1, 1 }
                                    else
                                        color = { 0, 0, 0, 1 }
                                    end
                                end

                                local handled = false
                                if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                                    if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                    handled = addon.BarBorders.ApplyToBarFrame(apb, styleKey, {
                                        color = color,
                                        thickness = thickness,
                                        levelOffset = 1,
                                        containerParent = (apb and apb:GetParent()) or nil,
                                        inset = inset,
                                    })
                                end

                                if not handled then
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                    if addon.Borders and addon.Borders.ApplySquare then
                                        local sqColor = tintEnabled and tintColor or { 0, 0, 0, 1 }
                                        local baseY = (thickness <= 1) and 0 or 1
                                        local baseX = 1
                                        local expandY = baseY - inset
                                        local expandX = baseX - inset
                                        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                        addon.Borders.ApplySquare(apb, {
                                            size = thickness,
                                            color = sqColor,
                                            layer = "OVERLAY",
                                            layerSublevel = 3,
                                            expandX = expandX,
                                            expandY = expandY,
                                        })
                                    end
                                end
                            end
                        else
                            -- Global custom borders disabled: clear any previous Alternate Power border.
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(apb) end
                        end
                    end

                    -- % Text and Value Text (AlternatePowerBar.LeftText / RightText)
                    do
                        local leftFS = apb.LeftText
                        local rightFS = apb.RightText

                        -- Visibility: respect both the bar-wide hidden flag and the per-text toggles.
                        local percentHidden = (acfg.percentHidden == true)
                        local valueHidden = (acfg.valueHidden == true)

                        if leftFS and leftFS.SetShown then
                            pcall(leftFS.SetShown, leftFS, (not altHidden) and (not percentHidden))
                        end
                        if rightFS and rightFS.SetShown then
                            pcall(rightFS.SetShown, rightFS, (not altHidden) and (not valueHidden))
                        end

                        -- Styling (font/size/style/color/offset) using stable baseline anchors
                        addon._ufAltPowerTextBaselines = addon._ufAltPowerTextBaselines or {}
                        local function ensureBaseline(fs, key)
                            addon._ufAltPowerTextBaselines[key] = addon._ufAltPowerTextBaselines[key] or {}
                            local b = addon._ufAltPowerTextBaselines[key]
                            if b.point == nil then
                                if fs and fs.GetPoint then
                                    local p, relTo, rp, x, y = fs:GetPoint(1)
                                    b.point = p or "CENTER"
                                    b.relTo = relTo or (fs.GetParent and fs:GetParent()) or apb
                                    b.relPoint = rp or b.point
                                    b.x = tonumber(x) or 0
                                    b.y = tonumber(y) or 0
                                else
                                    b.point, b.relTo, b.relPoint, b.x, b.y =
                                        "CENTER", (fs and fs.GetParent and fs:GetParent()) or apb, "CENTER", 0, 0
                                end
                            end
                            return b
                        end

                        local function applyAltTextStyle(fs, styleCfg, baselineKey)
                            if not fs or not styleCfg then return end
                            local face = addon.ResolveFontFace
                                and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
                                or (select(1, _G.GameFontNormal:GetFont()))
                            local size = tonumber(styleCfg.size) or 14
                            local outline = tostring(styleCfg.style or "OUTLINE")
                            if fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
                            local c = styleCfg.color or { 1, 1, 1, 1 }
                            if fs.SetTextColor then
                                pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
                            end
                            local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
                            local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
                            if fs.ClearAllPoints and fs.SetPoint then
                                local b = ensureBaseline(fs, baselineKey)
                                fs:ClearAllPoints()
                                fs:SetPoint(
                                    b.point or "CENTER",
                                    b.relTo or (fs.GetParent and fs:GetParent()) or apb,
                                    b.relPoint or b.point or "CENTER",
                                    (b.x or 0) + ox,
                                    (b.y or 0) + oy
                                )
                            end
                        end

                        if leftFS then
                            applyAltTextStyle(leftFS, acfg.textPercent or {}, "Player:altpower-left")
                        end
                        if rightFS then
                            applyAltTextStyle(rightFS, acfg.textValue or {}, "Player:altpower-right")
                        end
                    end

                    -- Width / height scaling (simple frame SetWidth/SetHeight based on %),
                    -- plus additive X/Y offsets applied from the captured baseline points.
                    if not inCombat then
                        -- Capture originals once
                        if not apb._ScootUFOrigWidth then
                            if apb.GetWidth then
                                local ok, w = pcall(apb.GetWidth, apb)
                                if ok and w then apb._ScootUFOrigWidth = w end
                            end
                        end
                        if not apb._ScootUFOrigHeight then
                            if apb.GetHeight then
                                local ok, h = pcall(apb.GetHeight, apb)
                                if ok and h then apb._ScootUFOrigHeight = h end
                            end
                        end
                        if not apb._ScootUFOrigPoints then
                            local pts = {}
                            local n = (apb.GetNumPoints and apb:GetNumPoints()) or 0
                            for i = 1, n do
                                local p, rel, rp, x, y = apb:GetPoint(i)
                                table.insert(pts, { p, rel, rp, x or 0, y or 0 })
                            end
                            apb._ScootUFOrigPoints = pts
                        end

                        local wPct = tonumber(acfg.widthPct) or 100
                        local hPct = tonumber(acfg.heightPct) or 100
                        local scaleX = math.max(0.5, math.min(1.5, wPct / 100))
                        local scaleY = math.max(0.5, math.min(2.0, hPct / 100))

                        -- Restore baseline first
                        if apb._ScootUFOrigWidth and apb.SetWidth then
                            pcall(apb.SetWidth, apb, apb._ScootUFOrigWidth)
                        end
                        if apb._ScootUFOrigHeight and apb.SetHeight then
                            pcall(apb.SetHeight, apb, apb._ScootUFOrigHeight)
                        end
                        if apb._ScootUFOrigPoints and apb.ClearAllPoints and apb.SetPoint then
                            pcall(apb.ClearAllPoints, apb)
                            for _, pt in ipairs(apb._ScootUFOrigPoints) do
                                pcall(apb.SetPoint, apb, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", pt[4] or 0, pt[5] or 0)
                            end
                        end

                        -- Apply width/height scaling (from center)
                        if apb._ScootUFOrigWidth and apb.SetWidth then
                            pcall(apb.SetWidth, apb, apb._ScootUFOrigWidth * scaleX)
                        end
                        if apb._ScootUFOrigHeight and apb.SetHeight then
                            pcall(apb.SetHeight, apb, apb._ScootUFOrigHeight * scaleY)
                        end

                        -- Apply positioning offsets relative to the original anchor points.
                        local offsetX = tonumber(acfg.offsetX) or 0
                        local offsetY = tonumber(acfg.offsetY) or 0
                        if apb._ScootUFOrigPoints and apb.ClearAllPoints and apb.SetPoint then
                            pcall(apb.ClearAllPoints, apb)
                            for _, pt in ipairs(apb._ScootUFOrigPoints) do
                                local baseX = pt[4] or 0
                                local baseY = pt[5] or 0
                                local newX = baseX + offsetX
                                local newY = baseY + offsetY
                                pcall(apb.SetPoint, apb, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", newX, newY)
                            end
                        end
                    end
                end
            end

            -- Experimental: Power Bar Width scaling (texture/mask only)
            -- For Target/Focus: Only when reverse fill is enabled
            -- For Player/Pet: Always available
            do
                local canScale = false
                if unit == "Player" or unit == "Pet" then
                    canScale = true
                elseif (unit == "Target" or unit == "Focus") and cfg.powerBarReverseFill then
                    canScale = true
                end

                if canScale and not inCombat then
                    local pct = tonumber(cfg.powerBarWidthPct) or 100
                    local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
                    local mask = resolvePowerMask(unit)
					local isMirroredUnit = (unit == "Target" or unit == "Focus")
					local scaleX = math.min(1.5, math.max(0.5, (pct or 100) / 100))

                    -- Capture original PB width once
                    if pb and not pb._ScootUFOrigWidth then
                        if pb.GetWidth then
                            local ok, w = pcall(pb.GetWidth, pb)
                            if ok and w then pb._ScootUFOrigWidth = w end
                        end
                    end

                    -- Capture original PB anchors
                    if pb and not pb._ScootUFOrigPoints then
                        local pts = {}
                        local n = (pb.GetNumPoints and pb:GetNumPoints()) or 0
                        for i = 1, n do
                            local p, rel, rp, x, y = pb:GetPoint(i)
                            table.insert(pts, { p, rel, rp, x or 0, y or 0 })
                        end
                        pb._ScootUFOrigPoints = pts
                    end

                    -- Helper: reanchor PB to grow left
                    local function reapplyPBPointsWithLeftOffset(dx)
                        if not pb or not pb.ClearAllPoints or not pb.SetPoint or not pb._ScootUFOrigPoints then return end
                        pcall(pb.ClearAllPoints, pb)
                        for _, pt in ipairs(pb._ScootUFOrigPoints) do
                            pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", (pt[4] or 0) - dx, pt[5] or 0)
                        end
                    end

                    -- Helper: reanchor PB to grow right
                    local function reapplyPBPointsWithRightOffset(dx)
                        if not pb or not pb.ClearAllPoints or not pb.SetPoint or not pb._ScootUFOrigPoints then return end
                        pcall(pb.ClearAllPoints, pb)
                        for _, pt in ipairs(pb._ScootUFOrigPoints) do
                            pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", (pt[4] or 0) + dx, pt[5] or 0)
                        end
                    end

					-- CRITICAL: Always restore to original state FIRST before applying new width
					-- Always start from the captured baseline to avoid cumulative offsets.
					if pb and pb._ScootUFOrigWidth and pb.SetWidth then
						pcall(pb.SetWidth, pb, pb._ScootUFOrigWidth)
					end
					if pb and pb._ScootUFOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						pcall(pb.ClearAllPoints, pb)
						for _, pt in ipairs(pb._ScootUFOrigPoints) do
							pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
						end
					end

                    if pct > 100 then
                        -- Widen the status bar frame
                        if pb and pb.SetWidth and pb._ScootUFOrigWidth then
                            pcall(pb.SetWidth, pb, pb._ScootUFOrigWidth * scaleX)
                        end

                        -- Reposition the frame to control growth direction
                        if pb and pb._ScootUFOrigWidth then
                            local dx = (pb._ScootUFOrigWidth * (scaleX - 1))
                            if dx and dx ~= 0 then
                                if unit == "Target" or unit == "Focus" then
                                    reapplyPBPointsWithLeftOffset(dx)
                                else
                                    reapplyPBPointsWithRightOffset(dx)
                                end
                            end
                        end

                        -- DO NOT touch the StatusBar texture - it's managed automatically by the StatusBar widget
                        -- REMOVE the mask entirely when widening - it causes rendering artifacts
                        if tex and mask and tex.RemoveMaskTexture then
                            pcall(tex.RemoveMaskTexture, tex, mask)
                        end

                        -- Force StatusBar to refresh its texture
                        if pb and pb.GetValue and pb.SetValue then
                            local currentValue = pb:GetValue()
                            if currentValue then
                                pcall(pb.SetValue, pb, currentValue)
                            end
                        end
                    elseif pct < 100 then
						-- Narrow the status bar frame
						if pb and pb.SetWidth and pb._ScootUFOrigWidth then
							pcall(pb.SetWidth, pb, pb._ScootUFOrigWidth * scaleX)
						end
						-- Reposition so mirrored bars keep the portrait edge anchored
						if pb and pb._ScootUFOrigWidth then
							local shrinkDx = pb._ScootUFOrigWidth * (1 - scaleX)
							if shrinkDx and shrinkDx ~= 0 and isMirroredUnit then
								reapplyPBPointsWithLeftOffset(-shrinkDx)
							end
						end
						-- Ensure mask remains applied when narrowing
						if pb and mask then
							ensureMaskOnBarTexture(pb, mask)
						end
                    else
                        -- Restore power bar frame
                        if pb and pb._ScootUFOrigWidth and pb.SetWidth then
                            pcall(pb.SetWidth, pb, pb._ScootUFOrigWidth)
                        end
                        if pb and pb._ScootUFOrigPoints and pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            for _, pt in ipairs(pb._ScootUFOrigPoints) do
                                pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
                            end
                        end
                        -- Re-apply mask to texture at original dimensions
                        if pb and mask then
                            ensureMaskOnBarTexture(pb, mask)
                        end
                    end
				elseif not inCombat then
					-- Not scalable (Target/Focus with default fill): ensure we restore any prior width/anchors/mask
					local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
					local mask = resolvePowerMask(unit)
					-- Restore power bar frame
					if pb and pb._ScootUFOrigWidth and pb.SetWidth then
						pcall(pb.SetWidth, pb, pb._ScootUFOrigWidth)
					end
					if pb and pb._ScootUFOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						pcall(pb.ClearAllPoints, pb)
						for _, pt in ipairs(pb._ScootUFOrigPoints) do
							pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
						end
					end
					-- Re-apply mask to texture at original dimensions
					if pb and mask then
						ensureMaskOnBarTexture(pb, mask)
					end
							end
						end
			
			-- Power Bar Height scaling (texture/mask only)
			-- For Target/Focus: Only when reverse fill is enabled
			-- For Player/Pet: Always available
			do
                -- Skip all Power Bar height scaling while in combat; defer to the next
                -- out-of-combat styling pass instead to avoid taint.
                if not inCombat then
				    local canScale = false
				    if unit == "Player" or unit == "Pet" then
					    canScale = true
				    elseif (unit == "Target" or unit == "Focus") and cfg.powerBarReverseFill then
					    canScale = true
				    end
				
				    if canScale then
					    local pct = tonumber(cfg.powerBarHeightPct) or 100
					    local widthPct = tonumber(cfg.powerBarWidthPct) or 100
					    local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
					    local mask = resolvePowerMask(unit)
					
					    -- Capture originals once (height and anchor points)
					    if tex and not tex._ScootUFOrigCapturedHeight then
						    if tex.GetHeight then
							    local ok, h = pcall(tex.GetHeight, tex)
							    if ok and h then tex._ScootUFOrigHeight = h end
						    end
						    -- Texture anchor points already captured by width scaling
						    tex._ScootUFOrigCapturedHeight = true
					    end
					    if mask and not mask._ScootUFOrigCapturedHeight then
						    if mask.GetHeight then
							    local ok, h = pcall(mask.GetHeight, mask)
							    if ok and h then mask._ScootUFOrigHeight = h end
						    end
						    -- Mask anchor points already captured by width scaling
						    mask._ScootUFOrigCapturedHeight = true
					    end
					
					    -- Anchor points should already be captured by width scaling
					    -- If not, capture them now
					    if pb and not pb._ScootUFOrigPoints then
						    local pts = {}
						    local n = (pb.GetNumPoints and pb:GetNumPoints()) or 0
						    for i = 1, n do
							    local p, rel, rp, x, y = pb:GetPoint(i)
							    table.insert(pts, { p, rel, rp, x or 0, y or 0 })
						    end
						    pb._ScootUFOrigPoints = pts
					    end
					
					    -- Helper: reanchor PB to grow downward (keep top fixed)
					    local function reapplyPBPointsWithBottomOffset(dy)
						    -- Positive dy moves BOTTOM/CENTER anchors downward (keep top edge fixed)
						    local pts = pb and pb._ScootUFOrigPoints
						    if not (pb and pts and pb.ClearAllPoints and pb.SetPoint) then return end
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pts) do
							    local p, rel, rp, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
							    local yy = y or 0
							    local anchor = tostring(p or "")
							    local relp = tostring(rp or "")
							    if string.find(anchor, "BOTTOM", 1, true) or string.find(relp, "BOTTOM", 1, true) then
								    yy = (y or 0) - (dy or 0)
							    elseif string.find(anchor, "CENTER", 1, true) or string.find(relp, "CENTER", 1, true) then
								    yy = (y or 0) - ((dy or 0) * 0.5)
							    end
							    pcall(pb.SetPoint, pb, p or "TOP", rel, rp or p or "TOP", x or 0, yy or 0)
						    end
					    end
					
					    local scaleY = math.max(0.5, math.min(2.0, pct / 100))
					
					    -- Capture original PowerBar height once
					    if pb and not pb._ScootUFOrigHeight then
						    if pb.GetHeight then
							    local ok, h = pcall(pb.GetHeight, pb)
							    if ok and h then pb._ScootUFOrigHeight = h end
						    end
					    end
					
					    -- CRITICAL: Always restore to original state FIRST
					    if pb and pb._ScootUFOrigHeight and pb.SetHeight then
						    pcall(pb.SetHeight, pb, pb._ScootUFOrigHeight)
					    end
					    if pb and pb._ScootUFOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pb._ScootUFOrigPoints) do
							    pcall(pb.SetPoint, pb, pt[1] or "TOP", pt[2], pt[3] or pt[1] or "TOP", pt[4] or 0, pt[5] or 0)
						    end
					    end
					
					    if pct ~= 100 then
						    -- Scale the status bar frame height
						    if pb and pb.SetHeight and pb._ScootUFOrigHeight then
							    pcall(pb.SetHeight, pb, pb._ScootUFOrigHeight * scaleY)
						    end
						
						    -- Reposition the frame to grow downward (keep top fixed)
						    if pb and pb._ScootUFOrigHeight then
							    local dy = (pb._ScootUFOrigHeight * (scaleY - 1))
							    if dy and dy ~= 0 then
								    reapplyPBPointsWithBottomOffset(dy)
							    end
						    end
						
						    -- DO NOT touch the StatusBar texture - it's managed automatically by the StatusBar widget
						    -- REMOVE the mask entirely when scaling - it causes rendering artifacts
						    if tex and mask and tex.RemoveMaskTexture then
							    pcall(tex.RemoveMaskTexture, tex, mask)
						    end
						
						    -- Force StatusBar to refresh its texture
						    if pb and pb.GetValue and pb.SetValue then
							    local currentValue = pb:GetValue()
							    if currentValue then
								    pcall(pb.SetValue, pb, currentValue)
							    end
						    end
					    else
						    -- Restore (already done above in the restore-first step)
						    -- Re-apply mask ONLY if both Width and Height are at 100%
						    -- (Width scaling removes the mask, so we shouldn't re-apply it if Width is still scaled)
						    if pb and mask and widthPct == 100 then
							    ensureMaskOnBarTexture(pb, mask)
						    end
					    end
				    else
					    -- Not scalable (Target/Focus with default fill): ensure we restore any prior height/anchors
					    -- Restore power bar frame
					    if pb and pb._ScootUFOrigHeight and pb.SetHeight then
						    pcall(pb.SetHeight, pb, pb._ScootUFOrigHeight)
					    end
					    if pb and pb._ScootUFOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pb._ScootUFOrigPoints) do
							    pcall(pb.SetPoint, pb, pt[1] or "TOP", pt[2], pt[3] or pt[1] or "TOP", pt[4] or 0, pt[5] or 0)
						    end
					    end
				    end
                end
			end
						
            -- Power Bar positioning offsets
            do
                -- Do not re-anchor Power Bar while in combat; this uses ClearAllPoints/SetPoint
                -- on protected frames and can taint downstream secure operations.
                if not inCombat then
                    local offsetX = tonumber(cfg.powerBarOffsetX) or 0
                    local offsetY = tonumber(cfg.powerBarOffsetY) or 0
                
                    -- Store original points if not already stored
                    if not pb._ScootPowerBarOrigPoints then
                        pb._ScootPowerBarOrigPoints = {}
                        for i = 1, pb:GetNumPoints() do
                            local point, relativeTo, relativePoint, xOfs, yOfs = pb:GetPoint(i)
                            table.insert(pb._ScootPowerBarOrigPoints, {point, relativeTo, relativePoint, xOfs, yOfs})
                        end
				    end
						
                    -- Apply offsets if non-zero, otherwise restore original anchors
                    if offsetX ~= 0 or offsetY ~= 0 then
                        if pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            for _, pt in ipairs(pb._ScootPowerBarOrigPoints) do
                                local newX = (pt[4] or 0) + offsetX
                                local newY = (pt[5] or 0) + offsetY
                                pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", newX, newY)
                            end
                        end
                    else
                        -- Restore original points when offsets are zero
                        if pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            for _, pt in ipairs(pb._ScootPowerBarOrigPoints) do
                                pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
                            end
                        end
				    end
                end
			end

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
                            pb:HookScript("OnSizeChanged", function()
                                if InCombatLockdown and InCombatLockdown() then
                                    return
                                end
                                ensureTextAndBorderOrdering(unit)
                            end)
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
        -- Hide the Player's Alternate Power frame art when Use Custom Borders is enabled.
        -- Framestack: PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture
        if unit == "Player" and _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
            local altTex = _G.PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture
            if altTex and altTex.SetShown then
                if cfg.useCustomBorders then
                    pcall(altTex.SetShown, altTex, false)
                else
                    -- Restore the Alternate Power frame art when custom borders are disabled.
                    pcall(altTex.SetShown, altTex, true)
                end
            end
        end
        
        -- Hide static visual elements when Use Custom Borders is enabled.
        -- Rationale: These elements (ReputationColor for Target/Focus, FrameFlash for Player, Flash for Target) have
        -- fixed positions that cannot be adjusted. Since ScooterMod allows users to reposition and
        -- resize health/power bars independently, these static overlays would remain in their original
        -- positions while the bars they're meant to surround/backdrop move elsewhere. This creates
        -- visual confusion, so we disable them when custom borders are active.
        
        -- Hide ReputationColor frame for Target/Focus when Use Custom Borders is enabled
        if (unit == "Target" or unit == "Focus") and cfg.useCustomBorders then
            local frame = getUnitFrameFor(unit)
            if frame then
                local reputationColor
                if unit == "Target" and _G.TargetFrame then
                    reputationColor = _G.TargetFrame.TargetFrameContent 
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                elseif unit == "Focus" and _G.FocusFrame then
                    reputationColor = _G.FocusFrame.TargetFrameContent
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                end
                if reputationColor and reputationColor.SetShown then
                    pcall(reputationColor.SetShown, reputationColor, false)
                end
            end
        elseif (unit == "Target" or unit == "Focus") then
            -- Restore ReputationColor when Use Custom Borders is disabled
            local frame = getUnitFrameFor(unit)
            if frame then
                local reputationColor
                if unit == "Target" and _G.TargetFrame then
                    reputationColor = _G.TargetFrame.TargetFrameContent 
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                elseif unit == "Focus" and _G.FocusFrame then
                    reputationColor = _G.FocusFrame.TargetFrameContent
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                end
                if reputationColor and reputationColor.SetShown then
                    pcall(reputationColor.SetShown, reputationColor, true)
                end
            end
        end
        
        -- Hide FrameFlash (aggro/threat glow) for Player when Use Custom Borders is enabled
        if unit == "Player" then
            if _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
                local frameFlash = _G.PlayerFrame.PlayerFrameContainer.FrameFlash
                if frameFlash then
                    if cfg.useCustomBorders then
                        -- Hide and install persistent hook to keep it hidden
                        if frameFlash.SetShown then pcall(frameFlash.SetShown, frameFlash, false) end
                        if frameFlash.Hide then pcall(frameFlash.Hide, frameFlash) end
                        
                        -- Install OnShow hook to prevent Blizzard's code from showing it during combat
                        if not frameFlash._ScootHideHookInstalled then
                            frameFlash._ScootHideHookInstalled = true
                            frameFlash._ScootOrigOnShow = frameFlash:GetScript("OnShow")
                        end
                        frameFlash:SetScript("OnShow", function(self)
                            local db = addon and addon.db and addon.db.profile
                            if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.useCustomBorders then
                                -- Keep it hidden while Use Custom Borders is enabled
                                self:Hide()
                            else
                                -- Allow it to show if custom borders are disabled
                                if self._ScootOrigOnShow then
                                    self._ScootOrigOnShow(self)
                                end
                            end
                        end)
                    else
                        -- Restore FrameFlash when Use Custom Borders is disabled
                        -- Restore original OnShow handler
                        if frameFlash._ScootHideHookInstalled and frameFlash._ScootOrigOnShow then
                            frameFlash:SetScript("OnShow", frameFlash._ScootOrigOnShow)
                        else
                            frameFlash:SetScript("OnShow", nil)
                        end
                        -- Show the frame
                        if frameFlash.SetShown then pcall(frameFlash.SetShown, frameFlash, true) end
                        if frameFlash.Show then pcall(frameFlash.Show, frameFlash) end
                    end
                end
            end
        end
        
        -- Hide Flash (aggro/threat glow) for Target when Use Custom Borders is enabled
        if unit == "Target" then
            if _G.TargetFrame and _G.TargetFrame.TargetFrameContainer then
                local targetFlash = _G.TargetFrame.TargetFrameContainer.Flash
                if targetFlash then
                    if cfg.useCustomBorders then
                        -- Hide and install persistent hook to keep it hidden
                        if targetFlash.SetShown then pcall(targetFlash.SetShown, targetFlash, false) end
                        if targetFlash.Hide then pcall(targetFlash.Hide, targetFlash) end
                        
                        -- Install OnShow hook to prevent Blizzard's code from showing it during combat
                        if not targetFlash._ScootHideHookInstalled then
                            targetFlash._ScootHideHookInstalled = true
                            targetFlash._ScootOrigOnShow = targetFlash:GetScript("OnShow")
                        end
                        targetFlash:SetScript("OnShow", function(self)
                            local db = addon and addon.db and addon.db.profile
                            if db and db.unitFrames and db.unitFrames.Target and db.unitFrames.Target.useCustomBorders then
                                -- Keep it hidden while Use Custom Borders is enabled
                                self:Hide()
                            else
                                -- Allow it to show if custom borders are disabled
                                if self._ScootOrigOnShow then
                                    self._ScootOrigOnShow(self)
                                end
                            end
                        end)
                    else
                        -- Restore Flash when Use Custom Borders is disabled
                        -- Restore original OnShow handler
                        if targetFlash._ScootHideHookInstalled and targetFlash._ScootOrigOnShow then
                            targetFlash:SetScript("OnShow", targetFlash._ScootOrigOnShow)
                        else
                            targetFlash:SetScript("OnShow", nil)
                        end
                        -- Show the frame
                        if targetFlash.SetShown then pcall(targetFlash.SetShown, targetFlash, true) end
                        if targetFlash.Show then pcall(targetFlash.Show, targetFlash) end
                    end
                end
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
        -- TEMPORARY DIAGNOSTIC (2025-11-14):
        -- The hooks below re-apply bar textures and borders after Blizzard updates
        -- unit frames (Player/Target/Focus). These updates can be frequent in combat.
        -- To measure their CPU impact, we keep the z-order defers available but
        -- disable the texture re-application hooks entirely for now.

        if false and _G.PlayerFrame and _G.PlayerFrame.UpdateSystem then
            _G.hooksecurefunc(_G.PlayerFrame, "UpdateSystem", function()
                defer("Player")
                if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                    _G.C_Timer.After(0, function() addon.ApplyUnitFrameBarTexturesFor("Player") end)
                elseif addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Player")
                end
            end)
        end
        if false and type(_G.PlayerFrame_Update) == "function" then
            _G.hooksecurefunc("PlayerFrame_Update", function()
                if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                    _G.C_Timer.After(0, function() addon.ApplyUnitFrameBarTexturesFor("Player") end)
                elseif addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Player")
                end
            end)
        end
        if false and type(_G.TargetFrame_Update) == "function" then
            _G.hooksecurefunc("TargetFrame_Update", function()
                defer("Target")
                if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                    _G.C_Timer.After(0, function() addon.ApplyUnitFrameBarTexturesFor("Target") end)
                elseif addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Target")
                end
            end)
        end
        if false and type(_G.FocusFrame_Update) == "function" then
            _G.hooksecurefunc("FocusFrame_Update", function()
                defer("Focus")
                if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                    _G.C_Timer.After(0, function() addon.ApplyUnitFrameBarTexturesFor("Focus") end)
                elseif addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Focus")
                end
            end)
        end
        if type(_G.PetFrame_Update) == "function" then
            _G.hooksecurefunc("PetFrame_Update", function() defer("Pet") end)
        end
    end

    if not addon._UFZOrderHooksInstalled then
        addon._UFZOrderHooksInstalled = true
        -- Install hooks synchronously to ensure they're ready before ApplyStyles() runs
        installUFZOrderHooks()
    end

end

-- Unit Frames: Apply Portrait positioning (X/Y offsets)
do
	-- Resolve portrait frame for a given unit
	local function resolvePortraitFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContainer and root.PlayerFrameContainer.PlayerPortrait or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContainer and root.TargetFrameContainer.Portrait or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContainer and root.TargetFrameContainer.Portrait or nil
		elseif unit == "Pet" then
			return _G.PetPortrait
		end
		return nil
	end

	-- Resolve portrait mask frame for a given unit
	local function resolvePortraitMaskFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContainer and root.PlayerFrameContainer.PlayerPortraitMask or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContainer and root.TargetFrameContainer.PortraitMask or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContainer and root.TargetFrameContainer.PortraitMask or nil
		elseif unit == "Pet" then
			local root = _G.PetFrame
			return root and root.PortraitMask or nil
		end
		return nil
	end

	-- Resolve portrait corner icon frame for a given unit (Player-only)
	local function resolvePortraitCornerIconFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentContextual and root.PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon or nil
		end
		-- Target/Focus/Pet don't appear to have corner icons
		return nil
	end

	-- Resolve portrait rest loop frame for a given unit (Player-only)
	local function resolvePortraitRestLoopFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentContextual and root.PlayerFrameContent.PlayerFrameContentContextual.PlayerRestLoop or nil
		end
		-- Target/Focus/Pet don't appear to have rest loops
		return nil
	end

	-- Resolve portrait status texture frame for a given unit (Player-only)
	local function resolvePortraitStatusTextureFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.StatusTexture or nil
		end
		-- Target/Focus/Pet don't appear to have status textures
		return nil
	end

	-- Resolve damage text (HitText) frame for a given unit (Player-only)
	local function resolveDamageTextFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.HitIndicator and root.PlayerFrameContent.PlayerFrameContentMain.HitIndicator.HitText or nil
		end
		-- Target/Focus/Pet don't have damage text
		return nil
	end

	-- Store original positions (per frame, not per unit, to handle frame recreation)
	local originalPositions = {}
	-- Store original scales (per frame, not per unit, to handle frame recreation)
	local originalScales = {}
	-- Store original texture coordinates (per frame, not per unit, to handle frame recreation)
	local originalTexCoords = {}
	-- Store original alpha values (per frame, not per unit, to handle frame recreation)
	local originalAlphas = {}
	-- Store original mask atlas (per frame, not per unit, to handle frame recreation)
	local originalMaskAtlas = {}

	local function applyForUnit(unit)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		db.unitFrames[unit].portrait = db.unitFrames[unit].portrait or {}
		local ufCfg = db.unitFrames[unit]
		local cfg = ufCfg.portrait

		local portraitFrame = resolvePortraitFrame(unit)
		if not portraitFrame then return end

		local maskFrame = resolvePortraitMaskFrame(unit)
		-- Corner icon only exists for Player frame
		local cornerIconFrame = (unit == "Player") and resolvePortraitCornerIconFrame(unit) or nil
		-- Rest loop only exists for Player frame
		local restLoopFrame = (unit == "Player") and resolvePortraitRestLoopFrame(unit) or nil
		-- Status texture only exists for Player frame
		local statusTextureFrame = (unit == "Player") and resolvePortraitStatusTextureFrame(unit) or nil

		-- Capture original positions on first access
		if not originalPositions[portraitFrame] then
			local point, relativeTo, relativePoint, xOfs, yOfs = portraitFrame:GetPoint()
			if point then
				originalPositions[portraitFrame] = {
					point = point,
					relativeTo = relativeTo,
					relativePoint = relativePoint,
					xOfs = xOfs or 0,
					yOfs = yOfs or 0,
				}
			end
		end

		-- Capture mask position if it exists
		if maskFrame and not originalPositions[maskFrame] then
			local point, relativeTo, relativePoint, xOfs, yOfs = maskFrame:GetPoint()
			if point then
				originalPositions[maskFrame] = {
					point = point,
					relativeTo = relativeTo,
					relativePoint = relativePoint,
					xOfs = xOfs or 0,
					yOfs = yOfs or 0,
				}
			end
		end

		-- Capture corner icon position if it exists
		if cornerIconFrame and not originalPositions[cornerIconFrame] then
			local point, relativeTo, relativePoint, xOfs, yOfs = cornerIconFrame:GetPoint()
			if point then
				originalPositions[cornerIconFrame] = {
					point = point,
					relativeTo = relativeTo,
					relativePoint = relativePoint,
					xOfs = xOfs or 0,
					yOfs = yOfs or 0,
				}
			end
		end

		local origPortrait = originalPositions[portraitFrame]
		if not origPortrait then return end

		local origMask = maskFrame and originalPositions[maskFrame] or nil
		local origCornerIcon = cornerIconFrame and originalPositions[cornerIconFrame] or nil

		-- Capture original scales on first access
		if not originalScales[portraitFrame] then
			originalScales[portraitFrame] = portraitFrame:GetScale() or 1.0
		end
		if maskFrame and not originalScales[maskFrame] then
			originalScales[maskFrame] = maskFrame:GetScale() or 1.0
		end
		if cornerIconFrame and not originalScales[cornerIconFrame] then
			originalScales[cornerIconFrame] = cornerIconFrame:GetScale() or 1.0
		end

		local origPortraitScale = originalScales[portraitFrame] or 1.0
		local origMaskScale = maskFrame and (originalScales[maskFrame] or 1.0) or nil
		local origCornerIconScale = cornerIconFrame and (originalScales[cornerIconFrame] or 1.0) or nil

		-- Get portrait texture
		-- For unit frames, the portraitFrame IS the texture itself (not a frame containing a texture)
		-- Check if it's a Texture directly, otherwise try GetPortrait() or GetRegions()
		local portraitTexture = nil
		if portraitFrame.GetObjectType and portraitFrame:GetObjectType() == "Texture" then
			-- The frame itself is the texture (unit frame portraits)
			portraitTexture = portraitFrame
		elseif portraitFrame.GetPortrait then
			-- PortraitFrameMixin frames have GetPortrait() method
			portraitTexture = portraitFrame:GetPortrait()
		elseif portraitFrame.GetRegions then
			-- Fallback: search regions for a texture
			for _, region in ipairs({ portraitFrame:GetRegions() }) do
				if region and region.GetObjectType and region:GetObjectType() == "Texture" then
					portraitTexture = region
					break
				end
			end
		end

		-- Capture original texture coordinates on first access
		if portraitTexture and not originalTexCoords[portraitFrame] then
			-- GetTexCoord returns 8 values: ulX, ulY, blX, blY, urX, urY, brX, brY
			-- Extract bounds from corner coordinates
			local ulX, ulY, blX, blY, urX, urY, brX, brY = portraitTexture:GetTexCoord()
			-- Extract min/max from all corners to get bounding box
			local left = math.min(ulX or 0, blX or 0, urX or 0, brX or 0)
			local right = math.max(ulX or 1, blX or 1, urX or 1, brX or 1)
			local top = math.min(ulY or 0, blY or 0, urY or 0, brY or 0)
			local bottom = math.max(ulY or 1, blY or 1, urY or 1, brY or 1)
			originalTexCoords[portraitFrame] = {
				left = left,
				right = right,
				top = top,
				bottom = bottom,
			}
		end

		-- Capture original alpha on first access
		if not originalAlphas[portraitFrame] then
			originalAlphas[portraitFrame] = portraitFrame:GetAlpha() or 1.0
		end
		if maskFrame and not originalAlphas[maskFrame] then
			originalAlphas[maskFrame] = maskFrame:GetAlpha() or 1.0
		end
		if cornerIconFrame and not originalAlphas[cornerIconFrame] then
			originalAlphas[cornerIconFrame] = cornerIconFrame:GetAlpha() or 1.0
		end
		if restLoopFrame and not originalAlphas[restLoopFrame] then
			originalAlphas[restLoopFrame] = restLoopFrame:GetAlpha() or 1.0
		end
		if statusTextureFrame and not originalAlphas[statusTextureFrame] then
			originalAlphas[statusTextureFrame] = statusTextureFrame:GetAlpha() or 1.0
		end

		local origPortraitAlpha = originalAlphas[portraitFrame] or 1.0
		local origMaskAlpha = maskFrame and (originalAlphas[maskFrame] or 1.0) or nil
		local origCornerIconAlpha = cornerIconFrame and (originalAlphas[cornerIconFrame] or 1.0) or nil
		local origRestLoopAlpha = restLoopFrame and (originalAlphas[restLoopFrame] or 1.0) or nil
		local origStatusTextureAlpha = statusTextureFrame and (originalAlphas[statusTextureFrame] or 1.0) or nil

		-- Capture original mask atlas on first access (for Player only - to support full circle mask)
		if maskFrame and unit == "Player" and not originalMaskAtlas[maskFrame] then
			if maskFrame.GetAtlas then
				local ok, atlas = pcall(maskFrame.GetAtlas, maskFrame)
				if ok and atlas then
					originalMaskAtlas[maskFrame] = atlas
				else
					-- Fallback: use known default Player mask atlas
					originalMaskAtlas[maskFrame] = "UI-HUD-UnitFrame-Player-Portrait-Mask"
				end
			else
				-- Fallback: use known default Player mask atlas
				originalMaskAtlas[maskFrame] = "UI-HUD-UnitFrame-Player-Portrait-Mask"
			end
		end

		local origMaskAtlas = maskFrame and (originalMaskAtlas[maskFrame] or nil) or nil

		-- Get offsets from config
		local offsetX = tonumber(cfg.offsetX) or 0
		local offsetY = tonumber(cfg.offsetY) or 0

		-- Get scale from config (100-200%, stored as percentage)
		local scalePct = tonumber(cfg.scale) or 100
		local scaleMultiplier = scalePct / 100.0

		-- Get zoom from config (100-200%, stored as percentage)
		-- 100% = no zoom (full texture), > 100% = zoom in (crop edges)
		-- Note: Zoom out (< 100%) is not supported - portrait textures are at full bounds (0,1,0,1)
		local zoomPct = tonumber(cfg.zoom) or 100
		if zoomPct < 100 then zoomPct = 100 elseif zoomPct > 200 then zoomPct = 200 end

		-- Get visibility settings from config
		local hidePortrait = (cfg.hidePortrait == true)
		local hideRestLoop = (cfg.hideRestLoop == true)
		local hideStatusTexture = (cfg.hideStatusTexture == true)
		local hideCornerIcon = (cfg.hideCornerIcon == true)
		local opacityPct = tonumber(cfg.opacity) or 100
		if opacityPct < 1 then opacityPct = 1 elseif opacityPct > 100 then opacityPct = 100 end
		local opacityValue = opacityPct / 100.0

		-- Get full circle mask setting (Player only)
		local useFullCircleMask = (unit == "Player") and (cfg.useFullCircleMask == true) or false

		-- Apply offsets relative to original positions (portrait, mask, and corner icon together)
		-- NOTE: Pet positioning disabled - PetFrame is a managed frame; moving portrait causes entire frame to move
		local function applyPosition()
			if unit == "Pet" then
				-- Skip positioning for Pet - causes entire frame to move due to managed frame layout system
				return
			end
			if not InCombatLockdown() then
				-- Move portrait frame
				portraitFrame:ClearAllPoints()
				portraitFrame:SetPoint(origPortrait.point, origPortrait.relativeTo, origPortrait.relativePoint, origPortrait.xOfs + offsetX, origPortrait.yOfs + offsetY)

				-- Move mask frame if it exists
				-- For Target/Focus/Pet, anchor mask to portrait to keep them locked together
				-- Pet's mask is already anchored to portrait in XML, so we maintain that relationship
				-- For Player, use original anchor to maintain proper positioning
				if maskFrame and origMask then
					maskFrame:ClearAllPoints()
					if unit == "Target" or unit == "Focus" or unit == "Pet" then
						-- Anchor mask to portrait frame to prevent drift
						-- Use TOPLEFT/BOTTOMRIGHT anchoring to match XML structure (Pet) or CENTER (Target/Focus)
						if unit == "Pet" then
							-- Pet mask uses TOPLEFT and BOTTOMRIGHT anchors to match portrait bounds
							maskFrame:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
							maskFrame:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
						else
							-- Target/Focus: Use CENTER to CENTER anchoring with 0,0 offset to keep them perfectly aligned
							maskFrame:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
						end
					else
						-- Player: use original anchor
						maskFrame:SetPoint(origMask.point, origMask.relativeTo, origMask.relativePoint, origMask.xOfs + offsetX, origMask.yOfs + offsetY)
					end
				end

				-- Move corner icon frame if it exists (Player only)
				if cornerIconFrame and origCornerIcon and unit == "Player" then
					cornerIconFrame:ClearAllPoints()
					cornerIconFrame:SetPoint(origCornerIcon.point, origCornerIcon.relativeTo, origCornerIcon.relativePoint, origCornerIcon.xOfs + offsetX, origCornerIcon.yOfs + offsetY)
				end
			end
		end

		-- Apply scaling to portrait, mask, and corner icon frames
		local function applyScale()
			if not InCombatLockdown() then
				-- Scale portrait frame
				portraitFrame:SetScale(origPortraitScale * scaleMultiplier)

				-- Scale mask frame if it exists
				if maskFrame and origMaskScale then
					maskFrame:SetScale(origMaskScale * scaleMultiplier)
				end

				-- Scale corner icon frame if it exists (Player only)
				if cornerIconFrame and origCornerIconScale and unit == "Player" then
					cornerIconFrame:SetScale(origCornerIconScale * scaleMultiplier)
				end
			end
		end

		-- Apply zoom to portrait texture via SetTexCoord
		local function applyZoom()
			if not portraitTexture then 
				-- Debug: log if texture not found
				if addon.debug then
					print("ScooterMod: Portrait zoom - texture not found for", unit)
				end
				return 
			end
			
			-- Re-capture original coordinates if not stored yet (handles texture recreation)
			if not originalTexCoords[portraitFrame] then
				local ulX, ulY, blX, blY, urX, urY, brX, brY = portraitTexture:GetTexCoord()
				local left = math.min(ulX or 0, blX or 0, urX or 0, brX or 0)
				local right = math.max(ulX or 1, blX or 1, urX or 1, brX or 1)
				local top = math.min(ulY or 0, blY or 0, urY or 0, brY or 0)
				local bottom = math.max(ulY or 1, blY or 1, urY or 1, brY or 1)
				originalTexCoords[portraitFrame] = {
					left = left,
					right = right,
					top = top,
					bottom = bottom,
				}
			end
			
			local origCoords = originalTexCoords[portraitFrame]
			if not origCoords then return end

			-- Calculate zoom: 100% = no change, > 100% = zoom in (crop edges), < 100% = zoom out (limited)
			-- For zoom in: crop equal amounts from all sides
			-- For zoom out: we can't show beyond texture bounds, so we'll limit it
			local zoomFactor = zoomPct / 100.0
			
			if zoomFactor == 1.0 then
				-- No zoom: restore original coordinates
				if portraitTexture.SetTexCoord then
					portraitTexture:SetTexCoord(origCoords.left, origCoords.right, origCoords.top, origCoords.bottom)
				end
			elseif zoomFactor > 1.0 then
				-- Zoom in: crop edges (e.g., 150% = show center 66.7% = crop 16.7% from each side)
				local cropAmount = (zoomFactor - 1.0) / (2.0 * zoomFactor)
				local origWidth = origCoords.right - origCoords.left
				local origHeight = origCoords.bottom - origCoords.top
				local newLeft = origCoords.left + (origWidth * cropAmount)
				local newRight = origCoords.right - (origWidth * cropAmount)
				local newTop = origCoords.top + (origHeight * cropAmount)
				local newBottom = origCoords.bottom - (origHeight * cropAmount)
				
				if portraitTexture.SetTexCoord then
					portraitTexture:SetTexCoord(newLeft, newRight, newTop, newBottom)
					-- Debug output
					if addon.debug then
						print(string.format("ScooterMod: Portrait zoom %d%% for %s - coords: %.3f,%.3f,%.3f,%.3f", zoomPct, unit, newLeft, newRight, newTop, newBottom))
					end
				end
			else
				-- Zoom out: show more (limited by texture bounds)
				-- LIMITATION: If original coordinates are already at full bounds (0,1,0,1),
				-- we cannot zoom out because there are no additional pixels to show.
				-- The texture coordinate system is clamped to [0,1] range.
				local origWidth = origCoords.right - origCoords.left
				local origHeight = origCoords.bottom - origCoords.top
				
				-- Check if we're already at full bounds - if so, zoom out is not possible
				local isFullBounds = (origCoords.left <= 0.001 and origCoords.right >= 0.999 and 
				                      origCoords.top <= 0.001 and origCoords.bottom >= 0.999)
				
				if isFullBounds then
					-- Already at full texture bounds - zoom out has no effect
					-- Just restore original coordinates (which are already full bounds)
					if portraitTexture.SetTexCoord then
						portraitTexture:SetTexCoord(origCoords.left, origCoords.right, origCoords.top, origCoords.bottom)
					end
					-- Debug output to explain limitation
					if addon.debug then
						print(string.format("ScooterMod: Portrait zoom out %d%% for %s - limited by full texture bounds (0,1,0,1)", zoomPct, unit))
					end
				else
					-- Original coordinates are NOT at full bounds, so we can expand within available space
					local origCenterX = origCoords.left + (origWidth / 2.0)
					local origCenterY = origCoords.top + (origHeight / 2.0)
					local newWidth = origWidth / zoomFactor
					local newHeight = origHeight / zoomFactor
					local newLeft = math.max(0, origCenterX - (newWidth / 2.0))
					local newRight = math.min(1, origCenterX + (newWidth / 2.0))
					local newTop = math.max(0, origCenterY - (newHeight / 2.0))
					local newBottom = math.min(1, origCenterY + (newHeight / 2.0))
					
					if portraitTexture.SetTexCoord then
						portraitTexture:SetTexCoord(newLeft, newRight, newTop, newBottom)
						if addon.debug then
							print(string.format("ScooterMod: Portrait zoom out %d%% for %s - coords: %.3f,%.3f,%.3f,%.3f", zoomPct, unit, newLeft, newRight, newTop, newBottom))
						end
					end
				end
			end
		end

		-- Apply mask atlas change (Player only - full circle mask)
		local function applyMask()
			if maskFrame and unit == "Player" and origMaskAtlas then
				if useFullCircleMask then
					-- Change to full circle mask
					if maskFrame.SetAtlas then
						pcall(maskFrame.SetAtlas, maskFrame, "CircleMask", false)
					end
				else
					-- Restore original mask (with square corner)
					if maskFrame.SetAtlas then
						pcall(maskFrame.SetAtlas, maskFrame, origMaskAtlas, false)
					end
				end
			end
		end

		-- Apply portrait border using custom textures
		local function applyBorder()
			if not portraitFrame then return end
			
			-- Get parent frame for creating border texture (portrait is a Texture, not a Frame)
			local parentFrame = portraitFrame:GetParent()
			if not parentFrame then return end
			
			-- Use a unique key for storing border texture on parent frame
			local borderKey = "ScootPortraitBorder_" .. tostring(unit)
			local borderTexture = parentFrame[borderKey]
			
			-- Border is enabled only when the per-portrait toggle is on AND the portrait itself is not hidden.
			-- This ensures Portrait → Visibility → "Hide Portrait" also hides any custom border art.
			local borderEnabled = cfg.portraitBorderEnable and not hidePortrait
			if not borderEnabled then
				-- Hide border if disabled
				if borderTexture then
					borderTexture:Hide()
				end
				return
			end
			
			local borderStyle = cfg.portraitBorderStyle or "texture_c"
			-- Treat "default" as "texture_c" for backwards compatibility
			if borderStyle == "default" then
				borderStyle = "texture_c"
			end
			
			-- Map style keys to texture paths
			local textureMap = {
				texture_c = "Interface\\AddOns\\ScooterMod\\media\\portraitborder\\texture_c.tga",
				texture_s = "Interface\\AddOns\\ScooterMod\\media\\portraitborder\\texture_s.tga",
				rare_c = "Interface\\AddOns\\ScooterMod\\media\\portraitborder\\rare_c.tga",
				rare_s = "Interface\\AddOns\\ScooterMod\\media\\portraitborder\\rare_s.tga",
			}
			
			local texturePath = textureMap[borderStyle]
			if not texturePath then return end
			
			-- Create border texture if it doesn't exist
			if not borderTexture then
				borderTexture = parentFrame:CreateTexture(nil, "OVERLAY")
				parentFrame[borderKey] = borderTexture
			end
			
			-- Set texture
			borderTexture:SetTexture(texturePath)
			
			-- Get border thickness (1-16)
			local thickness = tonumber(cfg.portraitBorderThickness) or 1
			if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
			
			-- Calculate expand based on thickness (negative values expand outward/outset)
			-- Thickness 1 = minimal expansion, thickness 16 = maximum expansion
			-- Increased multiplier to push borders further out from portrait edge to align with portrait circle
			local baseOutset = 4.0  -- Base outset to align with portrait edge
			local expandX = -(baseOutset + (thickness * 2.0))
			local expandY = -(baseOutset + (thickness * 2.0))
			
			-- Position border to match portrait with expansion
			borderTexture:ClearAllPoints()
			borderTexture:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", expandX, -expandY)
			borderTexture:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", -expandX, expandY)
			
			-- Apply color based on color mode
			local colorMode = cfg.portraitBorderColorMode or "texture"
			local r, g, b, a = 1, 1, 1, 1
			
			if colorMode == "custom" then
				-- Custom: use tint color
				local tintColor = cfg.portraitBorderTintColor or {1, 1, 1, 1}
				r, g, b, a = tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1, tintColor[4] or 1
			elseif colorMode == "class" then
				-- Class Color: use player's class color
				if addon.GetClassColorRGB then
					local cr, cg, cb = addon.GetClassColorRGB(unit == "Player" and "player" or (unit == "Target" and "target" or (unit == "Focus" and "focus" or "pet")))
					r, g, b, a = cr or 1, cg or 1, cb or 1, 1
				else
					r, g, b, a = 1, 1, 1, 1
				end
			elseif colorMode == "texture" then
				-- Texture Original: preserve texture's original colors (white = no tint)
				r, g, b, a = 1, 1, 1, 1
			end
			
			borderTexture:SetVertexColor(r, g, b, a)
			
			-- Set draw layer to appear above portrait
			borderTexture:SetDrawLayer("OVERLAY", 7)
			
			-- Show border
			borderTexture:Show()
		end

		local function applyVisibility()
			-- If "Hide Portrait" is checked, hide everything (ignore individual flags)
			-- Otherwise, check individual flags for each element
			
			-- Portrait frame: hidden if "Hide Portrait" is checked
			local portraitHidden = hidePortrait
			local finalAlpha = portraitHidden and 0.0 or (origPortraitAlpha * opacityValue)
			
			if portraitFrame.SetAlpha then
				portraitFrame:SetAlpha(finalAlpha)
			end
			if portraitHidden and portraitFrame.Hide then
				portraitFrame:Hide()
			elseif not portraitHidden and portraitFrame.Show then
				portraitFrame:Show()
			end

			-- Mask frame: hidden if "Hide Portrait" is checked
			if maskFrame then
				local maskHidden = hidePortrait
				local maskAlpha = maskHidden and 0.0 or (origMaskAlpha * opacityValue)
				if maskFrame.SetAlpha then
					maskFrame:SetAlpha(maskAlpha)
				end
				if maskHidden and maskFrame.Hide then
					maskFrame:Hide()
				elseif not maskHidden and maskFrame.Show then
					maskFrame:Show()
				end
			end

			-- Corner icon frame: hidden if "Hide Portrait" OR "Hide Corner Icon" is checked (Player only)
			if cornerIconFrame and unit == "Player" then
				local iconHidden = hidePortrait or hideCornerIcon
				local iconAlpha = iconHidden and 0.0 or (origCornerIconAlpha * opacityValue)
				if cornerIconFrame.SetAlpha then
					cornerIconFrame:SetAlpha(iconAlpha)
				end
				if iconHidden and cornerIconFrame.Hide then
					cornerIconFrame:Hide()
				elseif not iconHidden and cornerIconFrame.Show then
					cornerIconFrame:Show()
				end
			end

			-- Rest loop frame: hidden if "Hide Portrait" OR "Hide Rest Loop/Animation" is checked (Player only)
			if restLoopFrame and unit == "Player" then
				local restHidden = hidePortrait or hideRestLoop
				local restAlpha = restHidden and 0.0 or (origRestLoopAlpha * opacityValue)
				if restLoopFrame.SetAlpha then
					restLoopFrame:SetAlpha(restAlpha)
				end
				if restHidden and restLoopFrame.Hide then
					restLoopFrame:Hide()
				elseif not restHidden and restLoopFrame.Show then
					restLoopFrame:Show()
				end
			end

			-- Status texture frame: hidden if "Hide Portrait" OR "Hide Status Texture" is checked,
			-- or when global Use Custom Borders is enabled for the Player frame.
			if statusTextureFrame and unit == "Player" then
				local useCustomBorders = ufCfg and (ufCfg.useCustomBorders == true)
				local statusHidden = hidePortrait or hideStatusTexture or useCustomBorders
				local statusAlpha = statusHidden and 0.0 or (origStatusTextureAlpha * opacityValue)
				if statusTextureFrame.SetAlpha then
					statusTextureFrame:SetAlpha(statusAlpha)
				end
				if statusHidden and statusTextureFrame.Hide then
					statusTextureFrame:Hide()
				elseif not statusHidden and statusTextureFrame.Show then
					statusTextureFrame:Show()
				end
			end
		end

		-- Apply damage text styling (Player only)
		local function applyDamageText()
			if unit ~= "Player" then return end
			local damageTextFrame = resolveDamageTextFrame(unit)
			if not damageTextFrame then return end

			local damageTextDisabled = cfg.damageTextDisabled == true
			
			-- Instead of hiding the frame (which breaks Blizzard's CombatFeedback system),
			-- set alpha to 0 to make it invisible when disabled. This prevents the feedbackStartTime nil error.
			-- We use alpha instead of SetShown because Blizzard's CombatFeedback_OnUpdate expects the frame
			-- to exist and be managed by their system.
			if damageTextDisabled then
				if damageTextFrame.SetAlpha then
					pcall(damageTextFrame.SetAlpha, damageTextFrame, 0)
				end
				-- Skip styling when disabled
				return
			end

			local damageTextCfg = cfg.damageText or {}
			
			-- Hook SetTextHeight on the frame to intercept Blizzard's calls and override with our custom size
			-- This prevents Blizzard from overriding our font size with SetTextHeight
			if not damageTextFrame._scooterSetTextHeightHooked then
				damageTextFrame._scooterSetTextHeightHooked = true
				local originalSetTextHeight = damageTextFrame.SetTextHeight
				damageTextFrame.SetTextHeight = function(self, height)
					-- Check if we have custom settings
					local db = addon and addon.db and addon.db.profile
					if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.portrait then
						local cfg = db.unitFrames.Player.portrait
						local damageTextCfg = cfg.damageText or {}
						local customSize = tonumber(damageTextCfg.size)
						if customSize then
							-- Use our custom size instead of Blizzard's height
							-- But we still need to call SetFont to set the actual font size
							local customFace = addon.ResolveFontFace and addon.ResolveFontFace(damageTextCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
							local customStyle = tostring(damageTextCfg.style or "OUTLINE")
							if self.SetFont then
								pcall(self.SetFont, self, customFace, customSize, customStyle)
							end
							-- Don't call original SetTextHeight - SetFont handles the size
							return
						end
					end
					-- No custom settings, use original behavior
					if originalSetTextHeight then
						return originalSetTextHeight(self, height)
					end
				end
			end
			
			-- Initialize baseline storage
			addon._ufDamageTextBaselines = addon._ufDamageTextBaselines or {}
			local function ensureBaseline(fs, key)
				addon._ufDamageTextBaselines[key] = addon._ufDamageTextBaselines[key] or {}
				local b = addon._ufDamageTextBaselines[key]
				if b.point == nil then
					if fs and fs.GetPoint then
						local p, relTo, rp, x, y = fs:GetPoint(1)
						b.point = p or "CENTER"
						b.relTo = relTo or (fs.GetParent and fs:GetParent()) or nil
						b.relPoint = rp or b.point
						b.x = tonumber(x) or 0
						b.y = tonumber(y) or 0
					else
						b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or nil, "CENTER", 0, 0
					end
				end
				return b
			end

			-- Apply text styling
			local face = addon.ResolveFontFace and addon.ResolveFontFace(damageTextCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
			local size = tonumber(damageTextCfg.size) or 14
			local outline = tostring(damageTextCfg.style or "OUTLINE")
			if damageTextFrame.SetFont then
				pcall(damageTextFrame.SetFont, damageTextFrame, face, size, outline)
			end

			-- Determine color based on colorMode
			local c = nil
			local colorMode = damageTextCfg.colorMode or "default"
			if colorMode == "class" then
				-- Class Color: use player's class color
				if addon.GetClassColorRGB then
					local cr, cg, cb = addon.GetClassColorRGB("player")
					c = { cr or 1, cg or 1, cb or 1, 1 }
				else
					c = {1.0, 0.82, 0.0, 1} -- fallback to default yellow
				end
			elseif colorMode == "custom" then
				-- Custom: use stored color
				c = damageTextCfg.color or {1.0, 0.82, 0.0, 1}
			else
				-- Default: use Blizzard's default yellow color (1.0, 0.82, 0.0)
				c = damageTextCfg.color or {1.0, 0.82, 0.0, 1}
			end
			if damageTextFrame.SetTextColor then
				pcall(damageTextFrame.SetTextColor, damageTextFrame, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
			end

			-- Apply offset
			local ox = (damageTextCfg.offset and tonumber(damageTextCfg.offset.x)) or 0
			local oy = (damageTextCfg.offset and tonumber(damageTextCfg.offset.y)) or 0
			if damageTextFrame.ClearAllPoints and damageTextFrame.SetPoint then
				local b = ensureBaseline(damageTextFrame, "Player:damageText")
				damageTextFrame:ClearAllPoints()
				damageTextFrame:SetPoint(b.point or "CENTER", b.relTo or (damageTextFrame.GetParent and damageTextFrame:GetParent()) or nil, b.relPoint or b.point or "CENTER", (b.x or 0) + ox, (b.y or 0) + oy)
			end
		end

		if InCombatLockdown() then
			-- Defer application until out of combat
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0.1, function()
					if not InCombatLockdown() then
						applyPosition()
						applyScale()
						applyZoom()
						applyMask()
						applyBorder()
						applyVisibility()
						applyDamageText()
					end
				end)
			end
		else
			applyPosition()
			applyScale()
			applyZoom()
			applyMask()
			applyBorder()
			applyVisibility()
			applyDamageText()
		end
	end

	function addon.ApplyUnitFramePortraitFor(unit)
		applyForUnit(unit)
	end

	function addon.ApplyAllUnitFramePortraits()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
	end

	-- Hook portrait updates to reapply zoom when Blizzard updates portraits
	-- Hook UnitFramePortrait_Update which is called when portraits need refreshing
	if _G.UnitFramePortrait_Update then
		_G.hooksecurefunc("UnitFramePortrait_Update", function(unitFrame)
			if unitFrame and unitFrame.unit then
				local unit = unitFrame.unit
				local unitKey = nil
				if unit == "player" then unitKey = "Player"
				elseif unit == "target" then unitKey = "Target"
				elseif unit == "focus" then unitKey = "Focus"
				elseif unit == "pet" then unitKey = "Pet"
				end
				if unitKey then
					-- Defer zoom reapplication to next frame to ensure texture is ready
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, function()
							applyForUnit(unitKey)
						end)
					end
				end
			end
		end)
	end

	-- Hook Blizzard's CombatFeedback system to prevent showing damage text when disabled
	-- We need to hook both OnCombatEvent (when damage happens) and OnUpdate (animation loop)
	-- CombatFeedback_OnCombatEvent receives PlayerFrame as 'self', and PlayerFrame.feedbackText is the HitText
	-- CombatFeedback_OnUpdate also receives PlayerFrame as 'self'
	if _G.CombatFeedback_OnCombatEvent then
		_G.hooksecurefunc("CombatFeedback_OnCombatEvent", function(self, event, flags, amount, type)
			-- Check if this is PlayerFrame
			local playerFrame = _G.PlayerFrame
			if self and self == playerFrame and self.feedbackText then
				local db = addon and addon.db and addon.db.profile
				if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.portrait then
					local cfg = db.unitFrames.Player.portrait
					local damageTextDisabled = cfg.damageTextDisabled == true
					
					if damageTextDisabled then
						-- Immediately set alpha to 0 if disabled, preventing it from being visible
						-- This happens after Blizzard sets feedbackStartTime, so it won't cause nil errors
						if self.feedbackText.SetAlpha then
							pcall(self.feedbackText.SetAlpha, self.feedbackText, 0)
						end
					else
						-- Override Blizzard's font size with our custom size
						-- Blizzard calls SetTextHeight(fontHeight) which sets the text region height
						-- We need to use SetFont() with our custom size instead, which sets the actual font size
						-- SetFont will properly scale the text, while SetTextHeight just scales the region (causing pixelation)
						local damageTextCfg = cfg.damageText or {}
						local customSize = tonumber(damageTextCfg.size) or 14
						local customFace = addon.ResolveFontFace and addon.ResolveFontFace(damageTextCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
						local customStyle = tostring(damageTextCfg.style or "OUTLINE")
						
						-- Use SetFont to set the actual font size (not SetTextHeight which just scales the region)
						-- This must be called after Blizzard's SetTextHeight to override it
						if self.feedbackText.SetFont then
							pcall(self.feedbackText.SetFont, self.feedbackText, customFace, customSize, customStyle)
						end
					end
				end
			end
		end)
	end

	-- Hook CombatFeedback_OnUpdate to continuously keep alpha at 0 when disabled
	-- This is critical because OnUpdate runs every frame and will override our alpha setting
	-- OnUpdate receives PlayerFrame as 'self'
	if _G.CombatFeedback_OnUpdate then
		_G.hooksecurefunc("CombatFeedback_OnUpdate", function(self, elapsed)
			-- Check if this is PlayerFrame
			local playerFrame = _G.PlayerFrame
			if self and self == playerFrame and self.feedbackText then
				local db = addon and addon.db and addon.db.profile
				if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.portrait then
					local damageTextDisabled = db.unitFrames.Player.portrait.damageTextDisabled == true
					if damageTextDisabled then
						-- Continuously force alpha to 0, overriding Blizzard's animation
						-- This runs after Blizzard's SetAlpha calls, so it will override them
						if self.feedbackText.SetAlpha then
							pcall(self.feedbackText.SetAlpha, self.feedbackText, 0)
						end
					end
				end
			end
		end)
	end
	
	-- Also hook SetPortraitTexture as a fallback
	if _G.SetPortraitTexture then
		_G.hooksecurefunc("SetPortraitTexture", function(texture, unit)
			if unit and (unit == "player" or unit == "target" or unit == "focus" or unit == "pet") then
				local unitKey = nil
				if unit == "player" then unitKey = "Player"
				elseif unit == "target" then unitKey = "Target"
				elseif unit == "focus" then unitKey = "Focus"
				elseif unit == "pet" then unitKey = "Pet"
				end
				if unitKey then
					-- Defer zoom reapplication to next frame to ensure texture is ready
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, function()
							applyForUnit(unitKey)
						end)
					end
				end
			end
		end)
	end
end

-- Unit Frames: Cast Bar positioning (Target/Focus only, addon-managed offsets)
do
	local function resolveCastBarFrame(unit)
		if unit == "Player" then
			return _G.PlayerCastingBarFrame
		end
		if unit == "Target" then
			return _G.TargetFrameSpellBar
		elseif unit == "Focus" then
			return _G.FocusFrameSpellBar
		end
		return nil
	end

	-- Store original positions per frame so offsets are always relative to stock layout
	local originalPositions = {}
	-- Store original widths per frame for width-percent scaling
	local originalWidths = {}
	-- Store original icon anchors/sizes so padding and per-axis sizing are relative to stock layout
	local originalIconAnchors = {}
	local originalIconSizes = {}
	-- Store original spark vertex colors/alpha so "Default" can restore stock spark appearance
	local originalSparkVertexColor = {}
	local originalSparkAlpha = {}
	-- Baseline anchors for Cast Time text (Player only)
	addon._ufCastTimeTextBaselines = addon._ufCastTimeTextBaselines or {}
	-- Baseline anchors for Spell Name text (Player only)
	addon._ufCastSpellNameBaselines = addon._ufCastSpellNameBaselines or {}

	local function applyCastBarForUnit(unit)
		if unit ~= "Player" and unit ~= "Target" and unit ~= "Focus" then return end

		local db = addon and addon.db and addon.db.profile
		if not db then return end

		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		db.unitFrames[unit].castBar = db.unitFrames[unit].castBar or {}
		local cfg = db.unitFrames[unit].castBar

		local frame = resolveCastBarFrame(unit)
		if not frame then return end

		local isPlayer = (unit == "Player")

		-- For the Player cast bar, read the current Edit Mode "Lock to Player Frame" setting so
		-- we only override position when the bar is locked underneath the Player frame. When the
		-- bar is unlocked and freely positioned in Edit Mode, ScooterMod should not fight that.
		local isLockedToPlayerFrame = false
		if isPlayer and addon and addon.EditMode and addon.EditMode.GetSetting then
			local mgr = _G.EditModeManagerFrame
			local EMSys = _G.Enum and _G.Enum.EditModeSystem
			local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.LockToPlayerFrame
			if mgr and EMSys and mgr.GetRegisteredSystemFrame and sid then
				local emFrame = mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
				if emFrame then
					local v = addon.EditMode.GetSetting(emFrame, sid)
					isLockedToPlayerFrame = (tonumber(v) or 0) ~= 0
				end
			end
		end

		-- Install lightweight hooks once to keep cast bar styling persistent when
		-- Blizzard updates the bar's texture/color (cast start/stop, etc.).
		if not frame._ScootCastHooksInstalled and _G.hooksecurefunc then
			frame._ScootCastHooksInstalled = true
			local hookUnit = unit
			_G.hooksecurefunc(frame, "SetStatusBarTexture", function(self, ...)
				-- Ignore ScooterMod's own internal texture writes
				if self._ScootUFInternalTextureWrite then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					-- Mark this as a visual-only refresh so we can safely reapply
					-- textures/colors in combat without re-anchoring secure frames.
					self._ScootCastVisualOnly = true
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					self._ScootCastVisualOnly = nil
				end
			end)
			_G.hooksecurefunc(frame, "SetStatusBarColor", function(self, ...)
				if addon and addon.ApplyUnitFrameCastBarFor then
					self._ScootCastVisualOnly = true
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					self._ScootCastVisualOnly = nil
				end
			end)
		end

		-- Capture baseline anchor:
		-- - Player: capture a baseline that represents the Edit Mode "under Player" layout,
		--   but avoid rebasing while ScooterMod offsets are non-zero so we don't compound
		--   offsets on every apply. This keeps slider behaviour linear.
		-- - Target/Focus: capture once so offsets remain relative to stock layout.
		if frame.GetPoint then
			local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
			if point then
				if isPlayer then
					local hasOffsets =
						(tonumber(cfg.offsetX) or 0) ~= 0 or
						(tonumber(cfg.offsetY) or 0) ~= 0
					-- When offsets are zero and the bar is locked to the Player frame, we
					-- treat the current layout as the new baseline. Otherwise, we keep the
					-- previous baseline so offset sliders remain stable.
					if (not hasOffsets and isLockedToPlayerFrame) or not originalPositions[frame] then
						originalPositions[frame] = {
							point = point,
							relativeTo = relativeTo,
							relativePoint = relativePoint,
							xOfs = xOfs or 0,
							yOfs = yOfs or 0,
						}
					end
				elseif not originalPositions[frame] then
					originalPositions[frame] = {
						point = point,
						relativeTo = relativeTo,
						relativePoint = relativePoint,
						xOfs = xOfs or 0,
						yOfs = yOfs or 0,
					}
				end
			end
		end

		local orig = originalPositions[frame]
		if not orig then return end

		-- Capture original width once
		if not originalWidths[frame] and frame.GetWidth then
			local ok, w = pcall(frame.GetWidth, frame)
			if ok and w then
				originalWidths[frame] = w
			end
		end

		local origWidth = originalWidths[frame]

		-- Capture original icon anchor/size once (per physical Icon texture)
		local iconFrame = frame.Icon
		if iconFrame then
			if not originalIconAnchors[iconFrame] and iconFrame.GetPoint then
				local p, relTo, rp, x, y = iconFrame:GetPoint(1)
				if p then
					originalIconAnchors[iconFrame] = {
						point = p,
						relativeTo = relTo,
						relativePoint = rp,
						xOfs = x or 0,
						yOfs = y or 0,
					}
				end
			end
			if not originalIconSizes[iconFrame] and iconFrame.GetWidth and iconFrame.GetHeight then
				local okW, w = pcall(iconFrame.GetWidth, iconFrame)
				local okH, h = pcall(iconFrame.GetHeight, iconFrame)
				if okW and okH and w and h then
					originalIconSizes[iconFrame] = { width = w, height = h }
				end
			end
		end

		-- Offsets:
		-- - Target/Focus always use addon-managed X/Y offsets (relative to stock layout).
		-- - Player uses offsets only when locked to the Player frame; when unlocked, Edit Mode
		--   owns the free position and ScooterMod must not re-anchor.
		local offsetX, offsetY = 0, 0
		if unit == "Target" or unit == "Focus" then
			offsetX = tonumber(cfg.offsetX) or 0
			offsetY = tonumber(cfg.offsetY) or 0
		elseif isPlayer and isLockedToPlayerFrame then
			offsetX = tonumber(cfg.offsetX) or 0
			offsetY = tonumber(cfg.offsetY) or 0
		end

		-- Width percent (50–150%; 100 = stock width)
		local widthPct = tonumber(cfg.widthPct) or 100
		if widthPct < 50 then widthPct = 50 elseif widthPct > 150 then widthPct = 150 end

		-- Icon sizing, padding, and visibility relative to bar
		local iconWidth = tonumber(cfg.iconWidth)
		local iconHeight = tonumber(cfg.iconHeight)
		local iconBarPadding = tonumber(cfg.iconBarPadding) or 0
		local iconDisabled = cfg.iconDisabled == true

		local function apply()
			-- When we are being invoked from a SetStatusBarTexture/SetStatusBarColor hook
			-- during combat, treat this as a "visual-only" refresh: apply textures/colors
			-- but avoid re-anchoring secure frames or changing layout, which can taint.
			local inCombat = InCombatLockdown and InCombatLockdown()
			local visualOnly = inCombat and frame._ScootCastVisualOnly

			-- Layout (position/size/icon) is skipped for in-combat visual-only refreshes.
			if not visualOnly then
				if frame.ClearAllPoints and frame.SetPoint then
					-- Apply width scaling relative to original width (if available)
					if origWidth and frame.SetWidth then
						local scale = widthPct / 100.0
						pcall(frame.SetWidth, frame, origWidth * scale)
					end

					-- Anchor behaviour:
					-- - Player: only override anchors when locked to the Player frame so Edit Mode retains
					--   full control when the bar is unlocked and freely positioned.
					-- - Target/Focus: always re-anchor relative to the captured baseline plus offsets.
					if isPlayer then
						if isLockedToPlayerFrame then
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								(orig.xOfs or 0) + offsetX,
								(orig.yOfs or 0) + offsetY
							)
						end
					else
						frame:ClearAllPoints()
						frame:SetPoint(
							orig.point,
							orig.relativeTo,
							orig.relativePoint,
							(orig.xOfs or 0) + offsetX,
							(orig.yOfs or 0) + offsetY
						)
					end

					-- Apply icon visibility, size, and padding before bar styling
					local icon = frame.Icon
					if icon then
						-- Visibility: when disabled, hide the icon via alpha and clear any
						-- container-based borders so only the bar remains.
						if iconDisabled then
							if icon.SetAlpha then pcall(icon.SetAlpha, icon, 0) end
							if icon.ScooterIconBorderContainer and addon.Borders and addon.Borders.HideAll then
								addon.Borders.HideAll(icon.ScooterIconBorderContainer)
							end
						else
							if icon.SetAlpha then pcall(icon.SetAlpha, icon, 1) end

							local baseSize = originalIconSizes[icon]
							if iconWidth or iconHeight then
								local w = tonumber(iconWidth) or (baseSize and baseSize.width) or (icon.GetWidth and icon:GetWidth()) or 16
								local h = tonumber(iconHeight) or (baseSize and baseSize.height) or (icon.GetHeight and icon:GetHeight()) or 16
								-- Clamp to a reasonable range for cast bar icons
								w = math.max(8, math.min(64, w))
								h = math.max(8, math.min(64, h))
								pcall(icon.SetSize, icon, w, h)
								-- Ensure contained texture follows the resized frame
								if icon.Icon and icon.Icon.SetAllPoints then
									icon.Icon:SetAllPoints(icon)
								end
								if icon.IconMask and icon.IconMask.SetAllPoints then
									icon.IconMask:SetAllPoints(icon)
								end
							end

							-- Icon/Bar padding: adjust icon X offset relative to its original anchor
							local baseAnchor = originalIconAnchors[icon]
							if baseAnchor and icon.ClearAllPoints and icon.SetPoint then
								-- Positive padding increases the gap between icon (left) and bar by moving icon further left.
								local pad = tonumber(iconBarPadding) or 0
								local baseX = baseAnchor.xOfs or 0
								local baseY = baseAnchor.yOfs or 0
								local newX = baseX - pad
								icon:ClearAllPoints()
								icon:SetPoint(
									baseAnchor.point or "LEFT",
									baseAnchor.relativeTo or frame,
									baseAnchor.relativePoint or baseAnchor.point or "LEFT",
									newX,
									baseY
								)
							end
						end
					end
				end
			end

			-- Apply foreground and background styling via shared bar helpers
			if addon._ApplyToStatusBar or addon._ApplyBackgroundToStatusBar then
				local db = addon and addon.db and addon.db.profile
				db.unitFrames = db.unitFrames or {}
				db.unitFrames[unit] = db.unitFrames[unit] or {}
				db.unitFrames[unit].castBar = db.unitFrames[unit].castBar or {}
				local cfgStyle = db.unitFrames[unit].castBar

				-- Foreground: texture + color
				if addon._ApplyToStatusBar and frame.GetStatusBarTexture then
					local texKey = cfgStyle.castBarTexture or "default"
					local colorMode = cfgStyle.castBarColorMode or "default"
					local tint = cfgStyle.castBarTint
					-- For class color, follow Health/Power bars and always use player's class
					local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or "player"
					addon._ApplyToStatusBar(frame, texKey, colorMode, tint, "player", "cast", unitId)
				end

				-- Background: texture + color + opacity
				if addon._ApplyBackgroundToStatusBar then
					local bgTexKey = cfgStyle.castBarBackgroundTexture or "default"
					local bgColorMode = cfgStyle.castBarBackgroundColorMode or "default"
					local bgOpacity = cfgStyle.castBarBackgroundOpacity or 50
					addon._ApplyBackgroundToStatusBar(frame, bgTexKey, bgColorMode, cfgStyle.castBarBackgroundTint, bgOpacity, unit, "cast")
				end
			end

			-- Spark visibility and color (per unit)
			do
				local spark = frame.Spark
				if spark then
					-- Capture the stock spark vertex color/alpha once so "Default" can restore it later.
					if not originalSparkVertexColor[spark] and spark.GetVertexColor then
						local ok, r, g, b, a = pcall(spark.GetVertexColor, spark)
						if not ok or not r or not g or not b then
							r, g, b, a = 1, 1, 1, 1
						end
						originalSparkVertexColor[spark] = { r or 1, g or 1, b or 1, a or 1 }
					end
					if not originalSparkAlpha[spark] and spark.GetAlpha then
						local ok, alpha = pcall(spark.GetAlpha, spark)
						originalSparkAlpha[spark] = (ok and alpha) or 1
					end

					local sparkHidden = cfg.castBarSparkHidden == true
					local colorMode = cfg.castBarSparkColorMode or "default"
					local tintTbl = type(cfg.castBarSparkTint) == "table" and cfg.castBarSparkTint or {1,1,1,1}

					-- Determine effective color from mode:
					-- - "default": use the stock vertex color we captured above.
					-- - "custom": apply the user tint (RGBA) on top of the spark.
					local base = originalSparkVertexColor[spark] or {1,1,1,1}
					local r, g, b, a = base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1
					if colorMode == "custom" then
						r = tintTbl[1] or r
						g = tintTbl[2] or g
						b = tintTbl[3] or b
						a = tintTbl[4] or a
					end

					if spark.SetVertexColor then
						pcall(spark.SetVertexColor, spark, r, g, b, a)
					end

					-- Visibility: hide the spark via alpha so we do not fight internal Show/Hide logic.
					if sparkHidden then
						if spark.SetAlpha then
							pcall(spark.SetAlpha, spark, 0)
						end
					else
						if spark.SetAlpha then
							local baseAlpha = originalSparkAlpha[spark] or a or 1
							pcall(spark.SetAlpha, spark, baseAlpha)
						end
					end
				end
			end

			-- Custom Cast Bar border (per unit, uses bar border system)
			do
				local enabled = not not cfg.castBarBorderEnable
				local styleKey = cfg.castBarBorderStyle or "square"
				local colorMode = cfg.castBarBorderColorMode or "default"
				local tintTbl = type(cfg.castBarBorderTintColor) == "table" and cfg.castBarBorderTintColor or {1,1,1,1}
				local tintColor = {
					tintTbl[1] or 1,
					tintTbl[2] or 1,
					tintTbl[3] or 1,
					tintTbl[4] or 1,
				}
				local thickness = tonumber(cfg.castBarBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

				-- User-controlled inset plus a small thickness-derived term; we bias the Default (square)
				-- style outward slightly, with per-unit tuning.
				local userInset = tonumber(cfg.castBarBorderInset) or 0
				if userInset < -4 then userInset = -4 elseif userInset > 4 then userInset = 4 end
				local derivedInset = math.floor((thickness - 1) * 0.5)
				local baseInset = 0
				if styleKey == "square" then
					if unit == "Player" then
						-- Player cast bar: slightly outward, then user inset pulls in to an even frame.
						baseInset = -1
					elseif unit == "Target" then
						-- Target cast bar: a bit more outward to start; side/top nudges handled separately.
						baseInset = -2
					elseif unit == "Focus" then
						-- Focus cast bar: start closer in so the default inset=1 look is tighter on all sides.
						baseInset = 0
					else
						baseInset = -2
					end
				end
				local combinedInset = baseInset + userInset + derivedInset

				-- Clear any prior border when disabled
				if not enabled or styleKey == "none" then
					if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
				else
					-- Determine effective color from mode + style
					local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
					local color
					if colorMode == "custom" then
						color = tintColor
					elseif colorMode == "texture" then
						color = {1, 1, 1, 1}
					else -- "default"
						if styleDef and styleKey ~= "square" then
							color = {1, 1, 1, 1}
						else
							color = {0, 0, 0, 1}
						end
					end

					local handled = false
					if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
						if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end

						-- Ensure cast bar borders are parented directly to the StatusBar so they
						-- inherit its visibility (hidden when no cast is active).
						frame._ScooterBorderContainerParentRef = nil

						-- Unit-specific per-side pad adjustments for Cast Bar:
						-- Player: symmetric (no extra nudges; baseInset handles feel).
						-- Target: top pulled down slightly, left/right pulled in a bit more, bottom unchanged.
						if enabled and unit == "Target" then
							frame._ScooterBorderPadAdjust = {
								left = -2,
								right = -2,
								top = -1,
								bottom = 0,
							}
						else
							frame._ScooterBorderPadAdjust = nil
						end

						handled = addon.BarBorders.ApplyToBarFrame(frame, styleKey, {
							color = color,
							thickness = thickness,
							levelOffset = 1,
							inset = combinedInset,
						})
					end

					if not handled then
						-- Fallback: pixel (square) border using generic square helper
						if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
						if addon.Borders and addon.Borders.ApplySquare then
							local sqColor = (colorMode == "custom") and tintColor or {0, 0, 0, 1}
							local baseY = (thickness <= 1) and 0 or 1
							local baseX = 1
							local expandY = baseY - combinedInset
							local expandX = baseX - combinedInset
							if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
							if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end

							-- Per-unit fine-tuning for the pixel fallback:
							-- Player: top/bottom/left are good; pull the right edge in slightly.
							-- Target: top pulled down a bit; left/right pulled in more; bottom remains aligned.
							local exLeft, exRight, exTop, exBottom = expandX, expandX, expandY, expandY
							local name = frame.GetName and frame:GetName()
							if name == "PlayerCastingBarFrame" then
								-- Reduce right-side expansion by 1px (clamped to >= 0)
								exRight = math.max(0, exRight - 1)
							elseif name == "TargetFrameSpellBar" then
								exLeft  = math.max(0, exLeft - 2)
								exRight = math.max(0, exRight - 2)
								exTop   = math.max(0, exTop - 1)
							end

							addon.Borders.ApplySquare(frame, {
								size = thickness,
								color = sqColor,
								layer = "OVERLAY",
								layerSublevel = 3,
								expandLeft = exLeft,
								expandRight = exRight,
								expandTop = exTop,
								expandBottom = exBottom,
							})
						end
					end
				end

				-- Hide Blizzard's stock cast bar border when custom borders are enabled (all units that expose .Border)
				local border = frame.Border
				if border then
					if border.SetShown then
						pcall(border.SetShown, border, not enabled)
					elseif border.SetAlpha then
						pcall(border.SetAlpha, border, enabled and 0 or 1)
					end
				end
			end

			-- Cast Bar Icon border (per unit; reuses icon border system from Cooldown Manager)
			do
				local icon = frame.Icon
				if icon then
					local iconBorderEnabled = not not cfg.iconBorderEnable
					local iconStyle = cfg.iconBorderStyle or "square"
					if iconStyle == "none" then
						iconStyle = "square"
						cfg.iconBorderStyle = iconStyle
					end
					local iconThicknessVal = tonumber(cfg.iconBorderThickness) or 1
					if iconThicknessVal < 1 then iconThicknessVal = 1 elseif iconThicknessVal > 16 then iconThicknessVal = 16 end
					local iconTintEnabled = not not cfg.iconBorderTintEnable
					local tintTbl = type(cfg.iconBorderTintColor) == "table" and cfg.iconBorderTintColor or {1,1,1,1}
					local iconTintColor = {
						tintTbl[1] or 1,
						tintTbl[2] or 1,
						tintTbl[3] or 1,
						tintTbl[4] or 1,
					}

					-- Never draw a border when the icon itself is disabled.
					if iconBorderEnabled and not iconDisabled then
						-- Defensive cleanup: if any legacy Scooter borders were drawn directly on the
						-- icon texture (pre-wrapper versions), hide them once so only the current
						-- wrapper/container-based border remains visible.
						if (icon.ScootAtlasBorder or icon.ScootTextureBorder or icon.ScootSquareBorderContainer or icon.ScootSquareBorderEdges)
							and addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon)
						end

						addon.ApplyIconBorderStyle(icon, iconStyle, {
							thickness = iconThicknessVal,
							color = iconTintEnabled and iconTintColor or nil,
							tintEnabled = iconTintEnabled,
							db = cfg,
							thicknessKey = "iconBorderThickness",
							tintColorKey = "iconBorderTintColor",
							defaultThickness = 1,
						})
					else
						-- Clear any existing icon border container when custom border is disabled
						-- or when the icon itself is disabled/hidden.
						if icon.ScooterIconBorderContainer and addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon.ScooterIconBorderContainer)
						elseif addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon)
						end
					end
				end
			end

			-- Spell Name + Cast Time Text styling (Player only; standard 6 text controls each)
			if unit == "Player" then
				-- Spell Name Text
				do
					-- CastingBarFrameBaseTemplate exposes the spell-name FontString as .Text
					local spellFS = frame.Text
					if spellFS then
						-- Capture a stable baseline anchor once per session so offsets are relative.
						-- For the cast bar, we always treat the spell name as centered within the bar,
						-- regardless of whether the bar is locked to the Player frame or free-floating.
						local function ensureSpellBaseline(fs, key)
							addon._ufCastSpellNameBaselines[key] = addon._ufCastSpellNameBaselines[key] or {}
							local b = addon._ufCastSpellNameBaselines[key]
							if b.point == nil then
								-- Force a centered baseline: center of the cast bar frame.
								local parent = (fs and fs.GetParent and fs:GetParent()) or frame
								b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", parent, "CENTER", 0, 0
							end
							return b
						end

						local disabled = not not cfg.spellNameTextDisabled

						-- Visibility: use alpha instead of Show/Hide to avoid fighting Blizzard logic
						if spellFS.SetAlpha then
							pcall(spellFS.SetAlpha, spellFS, disabled and 0 or 1)
						end

						-- Backdrop behind the spell text (Frame Attributes: PlayerCastingBarFrame.TextBorder).
						-- We hide this independently of the text visibility so players can hide the strip even
						-- when the spell name itself is disabled.
						local hideBackdrop = not not cfg.hideSpellNameBackdrop
						local backdrop = frame.TextBorder
						if backdrop and backdrop.SetAlpha then
							pcall(backdrop.SetAlpha, backdrop, hideBackdrop and 0 or 1)
						elseif backdrop and backdrop.Hide and backdrop.Show then
							if hideBackdrop then
								pcall(backdrop.Hide, backdrop)
							else
								pcall(backdrop.Show, backdrop)
							end
						end

						if not disabled then
							local styleCfg = cfg.spellNameText or {}
							-- Font / size / outline
							local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
								or (select(1, _G.GameFontNormal:GetFont()))
							local size = tonumber(styleCfg.size) or 14
							local outline = tostring(styleCfg.style or "OUTLINE")
							if spellFS.SetFont then
								pcall(spellFS.SetFont, spellFS, face, size, outline)
							end

							-- Color (simple RGBA, no mode for now)
							local c = styleCfg.color or {1, 1, 1, 1}
							if spellFS.SetTextColor then
								pcall(spellFS.SetTextColor, spellFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
							end

							-- Offsets relative to baseline (centered)
							local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
							local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
							if spellFS.ClearAllPoints and spellFS.SetPoint then
								local b = ensureSpellBaseline(spellFS, "Player:spellName")
								spellFS:ClearAllPoints()
								-- Ensure horizontal alignment is centered so long and short strings both
								-- grow outwards from the middle of the bar.
								if spellFS.SetJustifyH then
									pcall(spellFS.SetJustifyH, spellFS, "CENTER")
								end
								spellFS:SetPoint(
									b.point or "CENTER",
									b.relTo or (spellFS.GetParent and spellFS:GetParent()) or frame,
									b.relPoint or b.point or "CENTER",
									(b.x or 0) + ox,
									(b.y or 0) + oy
								)
							end
						end
					end
				end

				-- Cast Time Text
				do
					local castTimeFS = frame.CastTimeText
					if castTimeFS then
						-- Capture a stable baseline anchor once per session so offsets are relative
						local function ensureCastTimeBaseline(fs, key)
							addon._ufCastTimeTextBaselines[key] = addon._ufCastTimeTextBaselines[key] or {}
							local b = addon._ufCastTimeTextBaselines[key]
							if b.point == nil then
								if fs and fs.GetPoint then
									local p, relTo, rp, x, y = fs:GetPoint(1)
									b.point = p or "CENTER"
									b.relTo = relTo or (fs.GetParent and fs:GetParent()) or frame
									b.relPoint = rp or b.point
									b.x = tonumber(x) or 0
									b.y = tonumber(y) or 0
								else
									b.point, b.relTo, b.relPoint, b.x, b.y =
										"CENTER", (fs and fs.GetParent and fs:GetParent()) or frame, "CENTER", 0, 0
								end
							end
							return b
						end

						local styleCfg = cfg.castTimeText or {}
						-- Font / size / outline
						local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
							or (select(1, _G.GameFontNormal:GetFont()))
						local size = tonumber(styleCfg.size) or 14
						local outline = tostring(styleCfg.style or "OUTLINE")
						if castTimeFS.SetFont then
							pcall(castTimeFS.SetFont, castTimeFS, face, size, outline)
						end

						-- Color (simple RGBA, no mode for now)
						local c = styleCfg.color or {1, 1, 1, 1}
						if castTimeFS.SetTextColor then
							pcall(castTimeFS.SetTextColor, castTimeFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
						end

						-- Offsets relative to baseline
						local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
						local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
						if castTimeFS.ClearAllPoints and castTimeFS.SetPoint then
							local b = ensureCastTimeBaseline(castTimeFS, "Player:castTime")
							castTimeFS:ClearAllPoints()
							castTimeFS:SetPoint(
								b.point or "CENTER",
								b.relTo or (castTimeFS.GetParent and castTimeFS:GetParent()) or frame,
								b.relPoint or b.point or "CENTER",
								(b.x or 0) + ox,
								(b.y or 0) + oy
							)
						end
					end
				end
			end
		end

		local inCombat = InCombatLockdown and InCombatLockdown()
		-- For normal styling passes triggered by profile changes or /reload, we avoid
		-- touching secure cast bar anchors during combat and defer until combat ends.
		-- For visual-only refreshes triggered from SetStatusBarTexture/Color hooks,
		-- we allow apply() to run in combat so custom textures/colors remain active.
		if inCombat and not frame._ScootCastVisualOnly then
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0.1, function()
					if not (InCombatLockdown and InCombatLockdown()) then
						apply()
					end
				end)
			end
		else
			apply()
		end
	end

	function addon.ApplyUnitFrameCastBarFor(unit)
		applyCastBarForUnit(unit)
	end

	function addon.ApplyAllUnitFrameCastBars()
		applyCastBarForUnit("Player")
		applyCastBarForUnit("Target")
		applyCastBarForUnit("Focus")
	end
end

-- Unit Frames: Buffs & Debuffs positioning and sizing (Target/Focus)
do
	-- Store original positions per aura frame so offsets remain relative to stock layout
	local originalAuraPositions = {}
	-- Store original sizes per aura frame so we can reason about defaults if needed
	local originalAuraSizes = {}

	local function resolveUnitFrame(unit)
		local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if mgr and EM and EMSys and mgr.GetRegisteredSystemFrame then
			local idx = (unit == "Target" and EM.Target) or (unit == "Focus" and EM.Focus) or nil
			if idx then
				local frame = mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
				if frame then
					return frame
				end
			end
		end
		-- Fallback to global frames if Edit Mode lookup is unavailable
		if unit == "Target" then
			return _G.TargetFrame
		elseif unit == "Focus" then
			return _G.FocusFrame
		end
		return nil
	end

	local function applyBuffsDebuffsForUnit(unit)
		if unit ~= "Target" and unit ~= "Focus" then return end

		local db = addon and addon.db and addon.db.profile
		if not db then return end

		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		db.unitFrames[unit].buffsDebuffs = db.unitFrames[unit].buffsDebuffs or {}
		local cfg = db.unitFrames[unit].buffsDebuffs

		local frame = resolveUnitFrame(unit)
		if not frame then return end

		local offsetX = tonumber(cfg.offsetX) or 0
		local offsetY = tonumber(cfg.offsetY) or 0
		local iconWidth = tonumber(cfg.iconWidth)
		local iconHeight = tonumber(cfg.iconHeight)
		local scalePct = tonumber(cfg.iconScale) or 100
		if scalePct < 50 then scalePct = 50 elseif scalePct > 150 then scalePct = 150 end
		local scaleMultiplier = scalePct / 100.0

		local function applyToPool(pool)
			if not pool or not pool.EnumerateActive then return end

			for auraFrame in pool:EnumerateActive() do
				-- Sizing: treat Blizzard's layout as the baseline and only grow/shrink
				-- relative to the stock size. We seed cfg.iconWidth/iconHeight from the
				-- first active aura we see so default sliders match Blizzard visuals.
				if auraFrame and auraFrame.SetSize then
					if not originalAuraSizes[auraFrame] then
						originalAuraSizes[auraFrame] = {
							width = auraFrame:GetWidth() or 21,
							height = auraFrame:GetHeight() or 21,
						}
					end

					-- Seed DB defaults from the first aura frame if not already set
					if not iconWidth or not iconHeight then
						local base = originalAuraSizes[auraFrame]
						if base then
							if not iconWidth then
								cfg.iconWidth = cfg.iconWidth or base.width
								iconWidth = tonumber(cfg.iconWidth) or base.width
							end
							if not iconHeight then
								cfg.iconHeight = cfg.iconHeight or base.height
								iconHeight = tonumber(cfg.iconHeight) or base.height
							end
						end
					end

					if iconWidth and iconHeight then
						local w = iconWidth
						local h = iconHeight
						-- Defensive clamp against absurdly small values
						if w < 8 then w = 8 end
						if h < 8 then h = 8 end
						auraFrame:SetSize(w, h)

						-- Keep icon/cooldown filling the aura frame
						local icon = auraFrame.Icon
						if icon and icon.SetAllPoints then
							icon:SetAllPoints(auraFrame)
						end
						local cd = auraFrame.Cooldown
						if cd and cd.SetAllPoints then
							cd:SetAllPoints(auraFrame)
						end

						-- Grow Blizzard's default debuff border alongside the icon so it continues
						-- to frame correctly when custom borders are disabled.
						local blizzBorder = auraFrame.Border
						if blizzBorder and blizzBorder.SetSize and (not cfg.borderEnable) then
							blizzBorder:SetSize(w + 2, h + 2)
						end
					end

					-- Apply uniform scale so we can shrink/grow icons without fighting
					-- Blizzard's internal aura-row math. This affects the visual size
					-- while leaving the logical layout width/height unchanged.
					if auraFrame.SetScale then
						auraFrame:SetScale(scaleMultiplier)
					end

					-- Custom icon border styling (Essential Cooldowns-style) when enabled
					local icon = auraFrame.Icon
					local blizzBorder = auraFrame.Border
					if icon then
						if cfg.borderEnable then
							-- Hide Blizzard's default debuff border so it doesn't compete visually
							if blizzBorder and blizzBorder.Hide then
								blizzBorder:Hide()
							elseif blizzBorder and blizzBorder.SetAlpha then
								blizzBorder:SetAlpha(0)
							end

							local styleKey = cfg.borderStyle or "square"
							local thickness = tonumber(cfg.borderThickness) or 1
							if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
							local tintEnabled = cfg.borderTintEnable and type(cfg.borderTintColor) == "table"
							local tintColor
							if tintEnabled then
								local c = cfg.borderTintColor or {1,1,1,1}
								tintColor = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
							end

							-- Hard reset any existing ScooterMod borders on this icon and its wrapper
							-- before applying a new style to avoid any chance of layered leftovers.
							if addon.Borders and addon.Borders.HideAll then
								addon.Borders.HideAll(icon)
								local container = icon.ScooterIconBorderContainer
								if container then
									addon.Borders.HideAll(container)
								end
							end

							if addon.ApplyIconBorderStyle then
								addon.ApplyIconBorderStyle(icon, styleKey, {
									thickness = thickness,
									color = tintEnabled and tintColor or nil,
									tintEnabled = tintEnabled,
									db = cfg,
									thicknessKey = "borderThickness",
									tintColorKey = "borderTintColor",
									defaultThickness = 1,
								})
							end
						else
							-- Restore Blizzard's default border and hide any custom border textures
							if addon.Borders and addon.Borders.HideAll then
								addon.Borders.HideAll(icon)
								-- Also clear any borders attached to the icon's wrapper container created
								-- by ApplyIconBorderStyle when the icon is a Texture.
								local container = icon.ScooterIconBorderContainer
								if container then
									addon.Borders.HideAll(container)
								end
							end
							if blizzBorder then
								if blizzBorder.Show then
									blizzBorder:Show()
								elseif blizzBorder.SetAlpha then
									blizzBorder:SetAlpha(1)
								end
							end
						end
					end
				end
			end
		end

		if InCombatLockdown() then
			if _G.C_Timer and _G.C_Timer.After then
				local u = unit
				_G.C_Timer.After(0.1, function()
					if not InCombatLockdown() then
						applyBuffsDebuffsForUnit(u)
					end
				end)
			end
			return
		end

		-- Use Blizzard's aura pools to get the active Buff/Debuff frames.
		-- Target/Focus both inherit TargetFrameTemplate, which creates pools
		-- for "TargetBuffFrameTemplate" and "TargetDebuffFrameTemplate".
		local auraPools = frame.auraPools
		if auraPools and auraPools.GetPool then
			local buffPool = auraPools:GetPool("TargetBuffFrameTemplate")
			local debuffPool = auraPools:GetPool("TargetDebuffFrameTemplate")
			applyToPool(buffPool)
			applyToPool(debuffPool)
		end

		-- Positioning: nudge the shared Buffs/Debuffs containers so rows stay intact
		-- and all auras move together, regardless of row/column indexing.
		local contextual = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentContextual
		if contextual then
			local containers = { contextual.buffs, contextual.debuffs }
			for _, holder in ipairs(containers) do
				if holder and holder.GetPoint then
					if not originalAuraPositions[holder] then
						local p, relTo, relPoint, xOfs, yOfs = holder:GetPoint(1)
						if p then
							originalAuraPositions[holder] = {
								point = p,
								relativeTo = relTo,
								relativePoint = relPoint,
								xOfs = xOfs or 0,
								yOfs = yOfs or 0,
							}
						end
					end
					local orig = originalAuraPositions[holder]
					if orig then
						holder:ClearAllPoints()
						holder:SetPoint(
							orig.point or "CENTER",
							orig.relativeTo,
							orig.relativePoint or orig.point or "CENTER",
							(orig.xOfs or 0) + offsetX,
							(orig.yOfs or 0) + offsetY
						)
					end
				end
			end
		end
	end

	function addon.ApplyUnitFrameBuffsDebuffsFor(unit)
		applyBuffsDebuffsForUnit(unit)
	end

	function addon.ApplyAllUnitFrameBuffsDebuffs()
		applyBuffsDebuffsForUnit("Target")
		applyBuffsDebuffsForUnit("Focus")
	end

	-- Hook aura updates so ScooterMod re-applies offsets/sizing after Blizzard layouts
	if _G.TargetFrame and _G.TargetFrame.UpdateAuras and _G.hooksecurefunc then
		_G.hooksecurefunc(_G.TargetFrame, "UpdateAuras", function(self)
			if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
				addon.ApplyUnitFrameBuffsDebuffsFor("Target")
			end
		end)
	end
	if _G.FocusFrame and _G.FocusFrame.UpdateAuras and _G.hooksecurefunc then
		_G.hooksecurefunc(_G.FocusFrame, "UpdateAuras", function(self)
			if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
				addon.ApplyUnitFrameBuffsDebuffsFor("Focus")
			end
		end)
	end
end

-- Unit Frames: Overall visibility (opacity) per unit
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

    local function applyVisibilityForUnit(unit)
        local frame = getUnitFrameFor(unit)
        if not frame or not frame.SetAlpha then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        db.unitFrames = db.unitFrames or {}
        db.unitFrames[unit] = db.unitFrames[unit] or {}
        local cfg = db.unitFrames[unit]

        -- Base opacity (combat) uses the same 50–100 semantics as Cooldown Manager groups
        local baseRaw = cfg.opacity
        if baseRaw == nil then baseRaw = 100 end
        local baseOpacity = ClampOpacity(baseRaw, 50)

        -- Out-of-combat opacity; falls back to base when unset
        local oocRaw = cfg.opacityOutOfCombat
        local oocOpacity = ClampOpacity(oocRaw == nil and baseOpacity or oocRaw, 1)

        -- With-target opacity; falls back to base when unset
        local tgtRaw = cfg.opacityWithTarget
        local tgtOpacity = ClampOpacity(tgtRaw == nil and baseOpacity or tgtRaw, 1)

        local hasTarget = (UnitExists and UnitExists("target")) and true or false
        local applied = hasTarget and tgtOpacity or (PlayerInCombat() and baseOpacity or oocOpacity)

        pcall(frame.SetAlpha, frame, applied / 100)
    end

    function addon.ApplyUnitFrameVisibilityFor(unit)
        applyVisibilityForUnit(unit)
    end

    function addon.ApplyAllUnitFrameVisibility()
        applyVisibilityForUnit("Player")
        applyVisibilityForUnit("Target")
        applyVisibilityForUnit("Focus")
        applyVisibilityForUnit("Pet")
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
