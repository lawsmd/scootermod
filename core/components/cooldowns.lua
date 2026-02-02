local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil

--------------------------------------------------------------------------------
-- Cooldown Manager (CDM) Component
--------------------------------------------------------------------------------
-- This module provides all CDM styling using an overlay-based approach that
-- avoids taint on Blizzard's protected CooldownViewer frames.
--
-- Key principle: We create our own frames (parented to UIParent) and position
-- them relative to CDM icons via anchoring. Hooks are safe; frame modifications
-- on Blizzard frames are not.
--
-- Supported customizations:
--   - Border styling (color, thickness, inset) via overlays
--   - Text styling (cooldown timer, charge/stack count) via overlay FontStrings
--   - TrackedBars (bar textures, icon borders, text) - direct styling is safe
--
-- See ADDONCONTEXT/Docs/COOLDOWNMANAGER.md for full documentation.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- CDM Taint Mitigation (12.0)
--------------------------------------------------------------------------------
-- In 12.0, CooldownViewer icon frames are semi-protected. We cannot style them
-- directly. However, SetAlpha on viewer CONTAINER frames is safe (verified Jan 15).
-- This enables opacity settings (in-combat, out-of-combat, with-target).
--------------------------------------------------------------------------------
addon.CDM_TAINT_DIAG = addon.CDM_TAINT_DIAG or {
    skipAllCDM = true,  -- Always true in 12.0+; overlay-based styling only
}

--------------------------------------------------------------------------------
-- CDM Viewer Mappings
--------------------------------------------------------------------------------

local CDM_VIEWERS = {
    EssentialCooldownViewer = "essentialCooldowns",
    UtilityCooldownViewer = "utilityCooldowns",
    BuffIconCooldownViewer = "trackedBuffs",
    -- Note: trackedBars (BuffBarCooldownViewer) use direct styling, not overlays
}

--------------------------------------------------------------------------------
-- Overlay System
--------------------------------------------------------------------------------

addon.CDMOverlays = addon.CDMOverlays or {}
local Overlays = addon.CDMOverlays

-- Pool of overlay frames for reuse
local overlayPool = {}
local activeOverlays = {}  -- Map from CDM icon frame to overlay frame

-- Track which icons have been sized (weak keys for GC)
-- Using a local table instead of writing to Blizzard frames avoids taint
-- that can cause allowAvailableAlert and other fields to become secret values
local sizedIcons = setmetatable({}, { __mode = "k" })

-- Track cached FontString references per cooldown frame (weak keys for GC)
-- Using a local table instead of writing _scooterFontString to Blizzard frames avoids taint
local scooterFontStrings = setmetatable({}, { __mode = "k" })

-- Track cooldown end times per icon for per-icon opacity feature (weak keys for GC)
local cooldownEndTimes = setmetatable({}, { __mode = "k" })

-- Forward declaration (defined in Icon Sizing section, used by hookProcGlowResizing)
local resizeProcGlow

-- Check if Blizzard's DebuffBorder is present and visible on a CDM icon
-- Used to avoid drawing ScooterMod borders over Blizzard's debuff-type borders
-- (Magic, Poison, Bleed, Curse, Disease) which have special colored atlases and
-- pandemic timer animations. Only affects trackedBuffs (BuffIconCooldownViewer).
local function hasBlizzardDebuffBorder(itemFrame)
    if not itemFrame then return false end
    local debuffBorder = itemFrame.DebuffBorder
    -- Check if the Texture child is shown, not the frame itself
    -- The DebuffBorder frame is always present, but Texture is only shown for harmful auras
    -- (see AuraUtil.SetAuraBorderAtlasFromAura in wow-ui-source)
    if debuffBorder and debuffBorder.Texture and debuffBorder.Texture.IsShown and debuffBorder.Texture:IsShown() then
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Overlay Frame Management
--------------------------------------------------------------------------------

local function createOverlayFrame(parent)
    -- Create a frame parented to the CDM icon
    -- This ensures proper frame level ordering with SpellActivationAlert (proc glow)
    -- Creating a child frame doesn't cause taint - only modifying protected properties does
    local overlay = CreateFrame("Frame", nil, parent or UIParent)
    overlay:EnableMouse(false)  -- Don't intercept mouse events

    -- Create border edges using BORDER layer (renders below OVERLAY where proc glow lives)
    overlay.borderEdges = {
        Top = overlay:CreateTexture(nil, "BORDER", nil, 1),
        Bottom = overlay:CreateTexture(nil, "BORDER", nil, 1),
        Left = overlay:CreateTexture(nil, "BORDER", nil, 1),
        Right = overlay:CreateTexture(nil, "BORDER", nil, 1),
    }

    -- Create atlas border texture for non-square styles
    overlay.atlasBorder = overlay:CreateTexture(nil, "BORDER", nil, 1)
    overlay.atlasBorder:Hide()

    -- Create text overlays for cooldown and charge/stack count
    -- These FontStrings are ours - styling them doesn't cause taint
    overlay.cooldownText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay.cooldownText:SetDrawLayer("OVERLAY", 7)
    overlay.cooldownText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    overlay.cooldownText:Hide()

    overlay.chargeText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay.chargeText:SetDrawLayer("OVERLAY", 7)
    overlay.chargeText:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -2, 2)
    overlay.chargeText:Hide()

    return overlay
end

local function getOverlay(parent)
    local overlay = table.remove(overlayPool)
    if not overlay then
        overlay = createOverlayFrame(parent)
    elseif parent then
        -- Re-parent pooled overlay to new parent
        overlay:SetParent(parent)
    end
    return overlay
end

local function releaseOverlay(overlay)
    if not overlay then return end
    overlay:Hide()
    overlay:ClearAllPoints()
    overlay:SetParent(UIParent)  -- Re-parent to UIParent so we don't hold CDM icon reference
    overlay:SetAlpha(1.0)  -- Reset alpha when returning to pool
    if overlay.cooldownText then
        overlay.cooldownText:SetText("")
        overlay.cooldownText:Hide()
    end
    if overlay.chargeText then
        overlay.chargeText:SetText("")
        overlay.chargeText:Hide()
    end
    table.insert(overlayPool, overlay)
end

--------------------------------------------------------------------------------
-- Border Application (on our own frames, not Blizzard's)
--------------------------------------------------------------------------------

-- Hide edge-based square border textures
local function hideEdgeBorder(overlay)
    if not overlay or not overlay.borderEdges then return end
    for _, tex in pairs(overlay.borderEdges) do
        tex:Hide()
    end
end

-- Hide atlas-based border texture
local function hideAtlasBorder(overlay)
    if not overlay or not overlay.atlasBorder then return end
    overlay.atlasBorder:Hide()
end

-- Apply square border (edges meet at corners, no gaps)
local function applySquareBorder(overlay, opts)
    if not overlay or not overlay.borderEdges then return end

    -- Hide atlas border if it was previously shown
    hideAtlasBorder(overlay)

    local edges = overlay.borderEdges
    local thickness = math.max(1, tonumber(opts.thickness) or 1)
    local col = opts.color or {0, 0, 0, 1}
    local r, g, b, a = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 1

    -- Set color on all edges
    for _, tex in pairs(edges) do
        tex:SetColorTexture(r, g, b, a)
    end

    -- Inset: positive = move border inward, negative = move outward
    local inset = (tonumber(opts.inset) or 0)

    -- Horizontal edges span full width; vertical edges trimmed to avoid corner overlap
    edges.Top:ClearAllPoints()
    edges.Top:SetPoint("TOPLEFT", overlay, "TOPLEFT", -inset, inset)
    edges.Top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", inset, inset)
    edges.Top:SetHeight(thickness)

    edges.Bottom:ClearAllPoints()
    edges.Bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -inset, -inset)
    edges.Bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", inset, -inset)
    edges.Bottom:SetHeight(thickness)

    -- Vertical edges: trimmed by thickness at top/bottom to avoid corner overlap
    edges.Left:ClearAllPoints()
    edges.Left:SetPoint("TOPLEFT", overlay, "TOPLEFT", -inset, inset - thickness)
    edges.Left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -inset, -inset + thickness)
    edges.Left:SetWidth(thickness)

    edges.Right:ClearAllPoints()
    edges.Right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", inset, inset - thickness)
    edges.Right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", inset, -inset + thickness)
    edges.Right:SetWidth(thickness)

    for _, tex in pairs(edges) do
        tex:Show()
    end
end

-- Apply atlas-based border style
local function applyAtlasBorder(overlay, opts, styleDef)
    if not overlay or not overlay.atlasBorder then return end

    -- Hide square border edges
    hideEdgeBorder(overlay)

    local atlasTex = overlay.atlasBorder

    -- For atlas borders: use style's default color (typically white) unless tint is enabled
    -- This lets the atlas texture show its natural colors when tint is off
    local col
    if opts.tintEnabled and opts.tintColor then
        col = opts.tintColor
    else
        col = styleDef.defaultColor or {1, 1, 1, 1}
    end
    local r, g, b, a = col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1

    -- Get the atlas name
    local atlasName = styleDef.atlas
    if not atlasName then return end

    -- Set atlas
    atlasTex:SetAtlas(atlasName, true)
    atlasTex:SetVertexColor(r, g, b, a)

    -- Calculate expansion based on style definition and inset
    local baseExpandX = styleDef.expandX or 0
    local baseExpandY = styleDef.expandY or baseExpandX
    local inset = tonumber(opts.inset) or 0
    local expandX = baseExpandX - inset
    local expandY = baseExpandY - inset

    -- Position the atlas texture
    atlasTex:ClearAllPoints()
    atlasTex:SetPoint("TOPLEFT", overlay, "TOPLEFT", -expandX, expandY)
    atlasTex:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", expandX, -expandY)
    atlasTex:Show()
end

local function applyBorderToOverlay(overlay, opts)
    if not overlay then return end

    local style = opts.style or "square"

    -- Get style definition for non-square styles
    local styleDef = nil
    if style ~= "square" and addon.IconBorders and addon.IconBorders.GetStyle then
        styleDef = addon.IconBorders.GetStyle(style)
    end

    -- Apply the appropriate border type
    if styleDef and styleDef.type == "atlas" and styleDef.atlas then
        applyAtlasBorder(overlay, opts, styleDef)
    else
        -- Default to square border (with chamfered corners)
        applySquareBorder(overlay, opts)
    end
end

local function hideBorderOnOverlay(overlay)
    hideEdgeBorder(overlay)
    hideAtlasBorder(overlay)
end

--------------------------------------------------------------------------------
-- Text Overlay Application (on our own FontStrings, not Blizzard's)
--------------------------------------------------------------------------------

local function getDefaultFontFace()
    local face = select(1, GameFontNormal:GetFont())
    return face
end

local function resolveCDMColor(cfg)
    local colorMode = cfg and cfg.colorMode
    -- Backward compat: existing custom color without mode = treat as custom if non-white
    if not colorMode then
        local c = cfg and cfg.color
        if c and (c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or (c[4] or 1) ~= 1) then
            return c
        end
        return {1, 1, 1, 1}
    end
    if colorMode == "class" then
        local cr, cg, cb = addon.GetClassColorRGB("player")
        return {cr or 1, cg or 1, cb or 1, 1}
    elseif colorMode == "custom" then
        return (cfg and cfg.color) or {1, 1, 1, 1}
    else
        return {1, 1, 1, 1}
    end
end

local function applyTextStyleToFontString(fontString, cfg, defaultSize)
    if not fontString then return end

    local size = tonumber(cfg and cfg.size) or defaultSize or 14
    local style = (cfg and cfg.style) or "OUTLINE"
    local fontFace = getDefaultFontFace()

    if cfg and cfg.fontFace and addon.ResolveFontFace then
        fontFace = addon.ResolveFontFace(cfg.fontFace) or fontFace
    end

    if addon.ApplyFontStyle then
        addon.ApplyFontStyle(fontString, fontFace, size, style)
    else
        fontString:SetFont(fontFace, size, style)
    end

    local color = resolveCDMColor(cfg)
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    fontString:SetTextColor(r, g, b, a)
end

--------------------------------------------------------------------------------
-- DIRECT TEXT STYLING (12.0 Compatible)
-- 
-- Key insight from Neph UI: You CAN modify the appearance of Blizzard's text
-- (SetFont, SetTextColor, SetShadowOffset), you just CAN'T read its content
-- (GetText returns secret values).
--
-- Approach:
-- 1. Hook CooldownFrame_Set to intercept cooldown updates (safe)
-- 2. Find the FontString inside the Cooldown frame's regions
-- 3. Apply SetFont/SetTextColor/SetShadowOffset directly (no GetText)
-- 4. Wrap in pcall and defer with C_Timer.After for combat safety
--------------------------------------------------------------------------------

local directTextStyleHooked = false
local CDM_VIEWER_NAMES = {
    ["EssentialCooldownViewer"] = "essentialCooldowns",
    ["UtilityCooldownViewer"] = "utilityCooldowns",
    ["BuffIconCooldownViewer"] = "trackedBuffs",
}

-- Find the cooldown text FontString inside a Cooldown frame
local function getCooldownFontString(cooldownFrame)
    if not cooldownFrame then return nil end
    
    -- Use cached reference if available
    if scooterFontStrings[cooldownFrame] then
        return scooterFontStrings[cooldownFrame]
    end

    -- Search regions for FontString
    if cooldownFrame.GetRegions then
        for _, region in ipairs({cooldownFrame:GetRegions()}) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                scooterFontStrings[cooldownFrame] = region
                return region
            end
        end
    end
    
    return nil
end

-- Find the charge/stack count FontString inside an icon frame
local function getChargeCountFontString(iconFrame)
    if not iconFrame then return nil end
    
    -- ChargeCount (for cooldowns with charges)
    if iconFrame.ChargeCount then
        local charge = iconFrame.ChargeCount
        -- Check for .Current or .Text child
        local fs = charge.Current or charge.Text or charge.Count
        if fs and fs.GetObjectType and fs:GetObjectType() == "FontString" then
            return fs
        end
        -- Search regions
        if charge.GetRegions then
            for _, region in ipairs({charge:GetRegions()}) do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    return region
                end
            end
        end
    end
    
    -- Applications (for buff stacks)
    if iconFrame.Applications then
        local apps = iconFrame.Applications
        if apps.GetRegions then
            for _, region in ipairs({apps:GetRegions()}) do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    return region
                end
            end
        end
    end
    
    return nil
end

-- Identify which CDM viewer a cooldown belongs to
local function identifyCooldownSource(cooldownFrame)
    if not cooldownFrame then return nil end
    
    local parent = cooldownFrame:GetParent()
    if not parent then return nil end
    
    -- parent should be the icon frame, check its parent for the viewer
    local viewerFrame = parent:GetParent()
    if viewerFrame and viewerFrame.GetName then
        local viewerName = viewerFrame:GetName()
        if viewerName and CDM_VIEWER_NAMES[viewerName] then
            return CDM_VIEWER_NAMES[viewerName]
        end
    end
    
    return nil
end

-- Get text settings for a component
local function getCooldownTextSettings(componentId)
    if not componentId then return nil end
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return nil end
    return component.db.textCooldown
end

local function getChargeTextSettings(componentId)
    if not componentId then return nil end
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return nil end
    return component.db.textStacks
end

-- Apply font styling directly to a Blizzard FontString (no GetText!)
-- opts.isChargeText: if true, uses BOTTOMRIGHT anchor; otherwise uses CENTER
-- opts.parentFrame: the frame to anchor to (defaults to fontString's parent)
local function applyFontStyleDirect(fontString, cfg, opts)
    if not fontString or not cfg then return end

    opts = opts or {}
    local size = tonumber(cfg.size) or 14
    local style = cfg.style or "OUTLINE"
    local color = resolveCDMColor(cfg)
    local fontFace = getDefaultFontFace()

    if cfg.fontFace and addon.ResolveFontFace then
        fontFace = addon.ResolveFontFace(cfg.fontFace) or fontFace
    end

    -- Apply font styling directly - this works even on protected frames!
    pcall(function()
        fontString:SetFont(fontFace, size, style)
    end)

    pcall(function()
        local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
        fontString:SetTextColor(r, g, b, a)
    end)
    
    -- Apply shadow if specified
    if cfg.shadowX or cfg.shadowY then
        pcall(function()
            fontString:SetShadowOffset(cfg.shadowX or 1, cfg.shadowY or -1)
        end)
    end
    
    -- Apply position offset if specified
    -- This repositions the FontString relative to its parent using the configured anchor and offset
    -- We always reposition if cfg.offset exists (even if values are 0) to ensure proper reset behavior
    if cfg.offset or cfg.anchor then
        local offsetX = (cfg.offset and tonumber(cfg.offset.x)) or 0
        local offsetY = (cfg.offset and tonumber(cfg.offset.y)) or 0
        local anchor = cfg.anchor
        
        -- Determine default anchor based on text type
        if not anchor then
            if opts.isChargeText then
                anchor = "BOTTOMRIGHT"  -- Default anchor for charge/stack counts
            else
                anchor = "CENTER"  -- Default anchor for cooldown text
            end
        end
        
        pcall(function()
            -- Get the parent frame to anchor to
            local parentFrame = opts.parentFrame or fontString:GetParent()
            if parentFrame then
                fontString:ClearAllPoints()
                fontString:SetPoint(anchor, parentFrame, anchor, offsetX, offsetY)
            end
        end)
    end
end

-- Apply cooldown text styling when a cooldown is set
local function applyCooldownTextStyle(cooldownFrame)
    if not cooldownFrame then return end
    if cooldownFrame.IsForbidden and cooldownFrame:IsForbidden() then return end
    
    -- Skip action bar cooldowns to avoid taint
    local parent = cooldownFrame:GetParent()
    if parent then
        local parentName = parent:GetName() or ""
        if parentName:match("ActionButton") or parentName:match("MultiBar") or
           parentName:match("PetActionButton") or parentName:match("StanceButton") then
            return
        end
    end
    
    local componentId = identifyCooldownSource(cooldownFrame)
    if not componentId then return end

    -- Style cooldown timer text (if configured)
    local cfg = getCooldownTextSettings(componentId)
    if cfg then
        -- Clear cached FontString reference to force re-scan
        scooterFontStrings[cooldownFrame] = nil

        local fontString = getCooldownFontString(cooldownFrame)
        if fontString then
            -- Cooldown text uses CENTER anchor by default
            applyFontStyleDirect(fontString, cfg, {
                isChargeText = false,
                parentFrame = cooldownFrame
            })
        end
    end

    -- Style charge/stack count text (independent of cooldown text config)
    if parent then
        local chargeCfg = getChargeTextSettings(componentId)
        if chargeCfg then
            local chargeFS = getChargeCountFontString(parent)
            if chargeFS then
                -- Charge/stack text uses BOTTOMRIGHT anchor by default
                -- Find the icon texture to anchor to (same as Neph UI approach)
                local iconTexture = parent.Icon or parent.icon
                applyFontStyleDirect(chargeFS, chargeCfg, {
                    isChargeText = true,
                    parentFrame = iconTexture or parent
                })
            end
        end
    end
end

-- Minimum cooldown duration to trigger dimming (filters out GCD)
-- GCD is typically 1.5s base, can go down to ~0.75s with haste
local MIN_COOLDOWN_FOR_DIMMING = 1.5

-- Helper to track cooldown state and update per-icon opacity
local function trackCooldownAndUpdateOpacity(cooldownFrame, start, duration, enable)
    local cdmIcon = cooldownFrame:GetParent()
    if not cdmIcon then return end

    -- Track cooldown state (only for cooldowns longer than GCD threshold)
    if enable and enable ~= 0 and start and start > 0 and duration and duration > MIN_COOLDOWN_FOR_DIMMING then
        cooldownEndTimes[cdmIcon] = start + duration
    else
        -- Don't clear if we have an existing longer cooldown still running
        -- (GCD shouldn't override a real cooldown that's already tracked)
        local existingEndTime = cooldownEndTimes[cdmIcon]
        if not existingEndTime or GetTime() >= existingEndTime then
            cooldownEndTimes[cdmIcon] = nil
        end
    end

    -- Defer opacity update to next frame for safety
    C_Timer.After(0, function()
        if cdmIcon and not (cdmIcon.IsForbidden and cdmIcon:IsForbidden()) then
            -- updateIconCooldownOpacity is defined later in the file
            if addon.RefreshCDMCooldownOpacity then
                -- Can't call the local directly since it's defined later,
                -- but we can update this icon specifically
                local componentId = nil
                local parent = cdmIcon:GetParent()
                if parent then
                    local parentName = parent.GetName and parent:GetName()
                    componentId = parentName and CDM_VIEWERS[parentName]
                end
                if componentId == "essentialCooldowns" or componentId == "utilityCooldowns" then
                    local component = addon.Components and addon.Components[componentId]
                    if component and component.db then
                        local opacitySetting = tonumber(component.db.opacityOnCooldown) or 100
                        if opacitySetting < 100 then
                            local endTime = cooldownEndTimes[cdmIcon]
                            local isOnCD = endTime and GetTime() < endTime
                            local targetAlpha = isOnCD and (opacitySetting / 100) or 1.0
                            pcall(function() cdmIcon:SetAlpha(targetAlpha) end)
                        else
                            pcall(function() cdmIcon:SetAlpha(1.0) end)
                        end
                    end
                end
            end
        end
    end)
end

-- Hook into Blizzard's cooldown system to intercept updates
local function hookCooldownTextStyling()
    if directTextStyleHooked then return end

    -- Hook CooldownFrame_Set (the main function that updates cooldowns)
    if CooldownFrame_Set then
        hooksecurefunc("CooldownFrame_Set", function(cooldownFrame, start, duration, enable, forceShowDrawEdge, modRate)
            if not cooldownFrame then return end
            if cooldownFrame.IsForbidden and cooldownFrame:IsForbidden() then return end

            -- Track cooldown state for per-icon opacity feature
            pcall(function()
                trackCooldownAndUpdateOpacity(cooldownFrame, start, duration, enable)
            end)

            -- Defer text styling to next frame for safety
            pcall(function()
                C_Timer.After(0, function()
                    if cooldownFrame and not (cooldownFrame.IsForbidden and cooldownFrame:IsForbidden()) then
                        pcall(applyCooldownTextStyle, cooldownFrame)
                    end
                end)
            end)
        end)
    end

    -- Also hook CooldownFrame_SetTimer if it exists (legacy API)
    if CooldownFrame_SetTimer then
        hooksecurefunc("CooldownFrame_SetTimer", function(cooldownFrame, start, duration, enable, forceShowDrawEdge, modRate)
            if not cooldownFrame then return end
            if cooldownFrame.IsForbidden and cooldownFrame:IsForbidden() then return end

            -- Track cooldown state for per-icon opacity feature
            pcall(function()
                trackCooldownAndUpdateOpacity(cooldownFrame, start, duration, enable)
            end)

            pcall(function()
                C_Timer.After(0, function()
                    if cooldownFrame and not (cooldownFrame.IsForbidden and cooldownFrame:IsForbidden()) then
                        pcall(applyCooldownTextStyle, cooldownFrame)
                    end
                end)
            end)
        end)
    end

    directTextStyleHooked = true
end

-- Hook ActionButtonSpellAlertManager:ShowAlert to resize proc glow on custom-sized icons.
-- The alert is created lazily on first proc, so ApplyIconSize can't catch it at init time.
local procGlowHooked = false
local function hookProcGlowResizing()
    if procGlowHooked then return end
    if not ActionButtonSpellAlertManager then return end

    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, actionButton)
        local sizeInfo = sizedIcons[actionButton]
        if not sizeInfo then return end
        -- Alert was just created by GetAlertFrame (hooksecurefunc runs after original)
        resizeProcGlow(actionButton, sizeInfo.width, sizeInfo.height)
    end)

    procGlowHooked = true
end

-- Exposed function to refresh text styling (called when settings change)
function addon.RefreshCDMTextStyling()
    -- Apply to all existing cooldowns in CDM viewers
    for viewerName, componentId in pairs(CDM_VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer and viewer.IsShown and viewer:IsShown() then
            local children = {viewer:GetChildren()}
            for _, child in ipairs(children) do
                if child and child.Cooldown then
                    pcall(applyCooldownTextStyle, child.Cooldown)
                end
            end
        end
    end
end

-- Legacy stub functions (kept for compatibility but no longer used)
local function applyCooldownTextToOverlay(overlay, cdmIcon, cfg)
    -- Overlay text approach replaced by direct styling
    if overlay and overlay.cooldownText then
        overlay.cooldownText:Hide()
    end
end

local function applyChargeTextToOverlay(overlay, cdmIcon, cfg)
    -- Overlay text approach replaced by direct styling
    if overlay and overlay.chargeText then
        overlay.chargeText:Hide()
    end
end

local function hideTextOnOverlay(overlay)
    if not overlay then return end
    if overlay.cooldownText then overlay.cooldownText:Hide() end
    if overlay.chargeText then overlay.chargeText:Hide() end
end

--------------------------------------------------------------------------------
-- Frame Validation
--------------------------------------------------------------------------------

local function isValidCDMItemFrame(frame)
    if not frame then return false end
    if frame.Icon or frame.Cooldown or frame.ChargeCount or frame.Applications then
        return true
    end
    if frame.GetIconTexture then
        return true
    end
    return false
end

local function isFrameVisible(frame)
    if not frame then return false end
    if frame.IsShown and not frame:IsShown() then
        return false
    end
    if frame.IsVisible and not frame:IsVisible() then
        return false
    end
    if frame.GetWidth and frame.GetHeight then
        local w, h = frame:GetWidth(), frame:GetHeight()
        if (w or 0) < 5 or (h or 0) < 5 then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Public Overlay API
--------------------------------------------------------------------------------

function Overlays.GetOrCreateForIcon(cdmIcon)
    if not cdmIcon then return nil end
    if not isValidCDMItemFrame(cdmIcon) then
        return nil
    end

    local existing = activeOverlays[cdmIcon]
    if existing then
        return existing
    end

    -- Create overlay as child of CDM icon - this ensures proper layering
    -- with SpellActivationAlert (proc glow). Creating a child frame is safe.
    local overlay = getOverlay(cdmIcon)
    activeOverlays[cdmIcon] = overlay

    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", cdmIcon, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", cdmIcon, "BOTTOMRIGHT", 0, 0)

    -- Set frame level just above the icon but below SpellActivationAlert
    -- SpellActivationAlert is typically at iconLevel + 5 or higher
    local iconLevel = cdmIcon:GetFrameLevel()
    overlay:SetFrameLevel(iconLevel + 1)

    overlay:Show()
    return overlay
end

function Overlays.ReleaseForIcon(cdmIcon)
    if not cdmIcon then return end
    local overlay = activeOverlays[cdmIcon]
    if overlay then
        activeOverlays[cdmIcon] = nil
        releaseOverlay(overlay)
    end
end

function Overlays.ApplyBorder(cdmIcon, opts)
    if not cdmIcon then return end
    
    if not isFrameVisible(cdmIcon) then
        Overlays.HideOverlay(cdmIcon)
        return
    end
    
    local overlay = Overlays.GetOrCreateForIcon(cdmIcon)
    if not overlay then return end
    
    if opts and opts.enable then
        applyBorderToOverlay(overlay, opts)
        overlay:Show()
    else
        hideBorderOnOverlay(overlay)
        overlay:Hide()
    end
end

function Overlays.HideBorder(cdmIcon)
    if not cdmIcon then return end
    local overlay = activeOverlays[cdmIcon]
    if overlay then
        hideBorderOnOverlay(overlay)
    end
end

function Overlays.ApplyText(cdmIcon, opts)
    if not cdmIcon then return end
    
    if not isFrameVisible(cdmIcon) then
        local overlay = activeOverlays[cdmIcon]
        if overlay then hideTextOnOverlay(overlay) end
        return
    end
    
    local overlay = Overlays.GetOrCreateForIcon(cdmIcon)
    if not overlay then return end
    
    if opts then
        applyCooldownTextToOverlay(overlay, cdmIcon, opts.cooldown)
        applyChargeTextToOverlay(overlay, cdmIcon, opts.stacks)
        overlay:Show()
    else
        hideTextOnOverlay(overlay)
    end
end

function Overlays.HideText(cdmIcon)
    if not cdmIcon then return end
    local overlay = activeOverlays[cdmIcon]
    if overlay then
        hideTextOnOverlay(overlay)
    end
end

function Overlays.RefreshText(cdmIcon, opts)
    if not cdmIcon then return end
    local overlay = activeOverlays[cdmIcon]
    if not overlay then return end
    
    if not isFrameVisible(cdmIcon) then
        hideTextOnOverlay(overlay)
        return
    end
    
    if opts then
        applyCooldownTextToOverlay(overlay, cdmIcon, opts.cooldown)
        applyChargeTextToOverlay(overlay, cdmIcon, opts.stacks)
    end
end

function Overlays.HideAll()
    for cdmIcon, overlay in pairs(activeOverlays) do
        releaseOverlay(overlay)
    end
    activeOverlays = {}
end

function Overlays.HideOverlay(cdmIcon)
    if not cdmIcon then return end
    local overlay = activeOverlays[cdmIcon]
    if overlay then
        overlay:Hide()
    end
end

--------------------------------------------------------------------------------
-- Icon Sizing (12.0 Compatible)
--------------------------------------------------------------------------------
-- NephUI reference: Direct SetSize() on CDM icons works if we:
--   1. Set values directly from settings (don't read current size)
--   2. Wrap in pcall for safety
--   3. Adjust texture coordinates to prevent stretching
--------------------------------------------------------------------------------

-- Resize SpellActivationAlert and its ProcStartFlipbook to match custom icon dimensions.
-- ProcStartFlipbook defaults to a fixed 150x150 square (per template XML), which causes
-- the intro animation to appear as a small/large square instead of matching the icon.
resizeProcGlow = function(cdmIcon, iconWidth, iconHeight)
    if not cdmIcon.SpellActivationAlert then return end
    pcall(function()
        local alert = cdmIcon.SpellActivationAlert
        alert:SetSize(iconWidth * 1.4, iconHeight * 1.4)
        if alert.ProcStartFlipbook then
            alert.ProcStartFlipbook:ClearAllPoints()
            alert.ProcStartFlipbook:SetAllPoints(alert)
        end
    end)
end

function Overlays.ApplyIconSize(cdmIcon, opts)
    if not cdmIcon then return end
    if not opts then return end
    if cdmIcon.IsForbidden and cdmIcon:IsForbidden() then return end

    local iconWidth = tonumber(opts.width)
    local iconHeight = tonumber(opts.height)
    if not iconWidth or not iconHeight then return end
    if iconWidth <= 0 or iconHeight <= 0 then return end

    -- Find the icon texture (handle both .icon and .Icon for compatibility)
    local iconTexture = cdmIcon.icon or cdmIcon.Icon
    if not iconTexture then return end

    -- Apply size change via pcall to catch any issues
    local ok = pcall(function()
        cdmIcon:SetWidth(iconWidth)
        cdmIcon:SetHeight(iconHeight)
        cdmIcon:SetSize(iconWidth, iconHeight)
    end)

    if not ok then return end

    -- Calculate texture coordinates to crop instead of stretch
    -- This prevents the icon from looking distorted with non-square dimensions
    local aspectRatio = iconWidth / iconHeight
    local left, right, top, bottom = 0, 1, 0, 1

    if aspectRatio > 1.0 then
        -- Wider than tall - crop top/bottom
        local cropAmount = 1.0 - (1.0 / aspectRatio)
        local offset = cropAmount / 2.0
        top = offset
        bottom = 1.0 - offset
    elseif aspectRatio < 1.0 then
        -- Taller than wide - crop left/right
        local cropAmount = 1.0 - aspectRatio
        local offset = cropAmount / 2.0
        left = offset
        right = 1.0 - offset
    end

    -- Apply texture coordinates
    pcall(function()
        iconTexture:SetTexCoord(left, right, top, bottom)
    end)

    -- Reposition internal elements to match new size
    local padding = 0

    -- Cooldown swipe
    if cdmIcon.Cooldown then
        pcall(function()
            cdmIcon.Cooldown:ClearAllPoints()
            cdmIcon.Cooldown:SetPoint("TOPLEFT", cdmIcon, "TOPLEFT", padding, -padding)
            cdmIcon.Cooldown:SetPoint("BOTTOMRIGHT", cdmIcon, "BOTTOMRIGHT", -padding, padding)
        end)
    end

    -- Cooldown flash
    if cdmIcon.CooldownFlash then
        pcall(function()
            cdmIcon.CooldownFlash:ClearAllPoints()
            cdmIcon.CooldownFlash:SetPoint("TOPLEFT", cdmIcon, "TOPLEFT", padding, -padding)
            cdmIcon.CooldownFlash:SetPoint("BOTTOMRIGHT", cdmIcon, "BOTTOMRIGHT", -padding, padding)
        end)
    end

    -- Icon texture itself
    pcall(function()
        iconTexture:ClearAllPoints()
        iconTexture:SetPoint("TOPLEFT", cdmIcon, "TOPLEFT", padding, -padding)
        iconTexture:SetPoint("BOTTOMRIGHT", cdmIcon, "BOTTOMRIGHT", -padding, padding)
    end)

    -- Fix proc glow if alert already exists (handles re-sizing after first proc)
    resizeProcGlow(cdmIcon, iconWidth, iconHeight)

    -- Store dimensions so the ShowAlert hook can resize on first proc too
    sizedIcons[cdmIcon] = { width = iconWidth, height = iconHeight }
end

function Overlays.ResetIconSize(cdmIcon)
    if not cdmIcon then return end

    -- Reset texture coordinates to default
    local iconTexture = cdmIcon.icon or cdmIcon.Icon
    if iconTexture then
        pcall(function()
            iconTexture:SetTexCoord(0, 1, 0, 1)
        end)
    end

    sizedIcons[cdmIcon] = nil
end

--------------------------------------------------------------------------------
-- Viewer Integration
--------------------------------------------------------------------------------

function Overlays.ApplyToViewer(viewerFrameName, componentId)
    local viewer = _G[viewerFrameName]
    if not viewer then return end
    
    if viewer.IsVisible and not viewer:IsVisible() then
        for _, child in ipairs({ viewer:GetChildren() }) do
            Overlays.HideOverlay(child)
        end
        return
    end
    
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return end
    
    local db = component.db
    local borderEnabled = db.borderEnable
    local hasTextConfig = db.textCooldown or db.textStacks

    -- Check if icon sizing is configured via ratio
    local ratio = tonumber(db.tallWideRatio) or 0
    local hasCustomSize = ratio ~= 0
    local iconWidth, iconHeight
    if hasCustomSize and addon.IconRatio then
        iconWidth, iconHeight = addon.IconRatio.GetDimensionsForComponent(componentId, ratio)
    end

    for _, child in ipairs({ viewer:GetChildren() }) do
        if isValidCDMItemFrame(child) then
            if not isFrameVisible(child) then
                Overlays.HideOverlay(child)
            else
                -- Apply icon sizing if configured
                if hasCustomSize and iconWidth and iconHeight then
                    Overlays.ApplyIconSize(child, {
                        width = iconWidth,
                        height = iconHeight,
                    })
                elseif sizedIcons[child] then
                    -- Reset if previously sized but no longer configured
                    Overlays.ResetIconSize(child)
                end

                if borderEnabled and not hasBlizzardDebuffBorder(child) then
                    Overlays.ApplyBorder(child, {
                        enable = true,
                        style = db.borderStyle or "square",
                        thickness = tonumber(db.borderThickness) or 1,
                        inset = tonumber(db.borderInset) or -1,
                        color = db.borderTintEnable and db.borderTintColor or {0, 0, 0, 1},
                        tintEnabled = db.borderTintEnable,
                        tintColor = db.borderTintColor,
                    })
                elseif hasBlizzardDebuffBorder(child) then
                    -- Hide ScooterMod border when Blizzard's DebuffBorder is visible
                    Overlays.HideBorder(child)
                else
                    Overlays.HideBorder(child)
                end
                
                if hasTextConfig then
                    Overlays.ApplyText(child, {
                        cooldown = db.textCooldown,
                        stacks = db.textStacks,
                    })
                else
                    Overlays.HideText(child)
                end
                
                local overlay = activeOverlays[child]
                if overlay then
                    if borderEnabled or hasTextConfig then
                        overlay:Show()
                    else
                        overlay:Hide()
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Hook Registration
--------------------------------------------------------------------------------

local hookedViewers = {}

function Overlays.HookViewer(viewerFrameName, componentId)
    if hookedViewers[viewerFrameName] then return true end
    
    local viewer = _G[viewerFrameName]
    if not viewer then return false end
    
    if viewer.OnAcquireItemFrame then
        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if not isValidCDMItemFrame(itemFrame) then return end
                    if not isFrameVisible(itemFrame) then return end

                    local component = addon.Components and addon.Components[componentId]
                    if not component or not component.db then return end

                    -- Apply icon sizing if configured via ratio
                    local ratio = tonumber(component.db.tallWideRatio) or 0
                    if ratio ~= 0 and addon.IconRatio then
                        local iconWidth, iconHeight = addon.IconRatio.GetDimensionsForComponent(componentId, ratio)
                        if iconWidth and iconHeight then
                            Overlays.ApplyIconSize(itemFrame, {
                                width = iconWidth,
                                height = iconHeight,
                            })
                        end
                    end

                    if component.db.borderEnable and not hasBlizzardDebuffBorder(itemFrame) then
                        Overlays.ApplyBorder(itemFrame, {
                            enable = true,
                            style = component.db.borderStyle or "square",
                            thickness = tonumber(component.db.borderThickness) or 1,
                            inset = tonumber(component.db.borderInset) or -1,
                            color = component.db.borderTintEnable and component.db.borderTintColor or {0, 0, 0, 1},
                            tintEnabled = component.db.borderTintEnable,
                            tintColor = component.db.borderTintColor,
                        })
                    elseif hasBlizzardDebuffBorder(itemFrame) then
                        -- Hide ScooterMod border when Blizzard's DebuffBorder is visible
                        Overlays.HideBorder(itemFrame)
                    end

                    local hasTextConfig = component.db.textCooldown or component.db.textStacks
                    if hasTextConfig then
                        Overlays.ApplyText(itemFrame, {
                            cooldown = component.db.textCooldown,
                            stacks = component.db.textStacks,
                        })
                    end
                end)
            end
        end)
    end
    
    if viewer.OnReleaseItemFrame then
        hooksecurefunc(viewer, "OnReleaseItemFrame", function(_, itemFrame)
            -- Defer cleanup to break Blizzard's call stack and avoid taint propagation
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    Overlays.HideOverlay(itemFrame)
                    Overlays.ResetIconSize(itemFrame)
                end)
            else
                Overlays.HideOverlay(itemFrame)
                Overlays.ResetIconSize(itemFrame)
            end
        end)
    end
    
    if viewer.RefreshLayout then
        hooksecurefunc(viewer, "RefreshLayout", function()
            if InCombatLockdown and InCombatLockdown() then return end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    Overlays.ApplyToViewer(viewerFrameName, componentId)
                end)
            end
        end)
    end
    
    hookedViewers[viewerFrameName] = true
    return true
end

--------------------------------------------------------------------------------
-- Periodic Cleanup and Text Refresh
--------------------------------------------------------------------------------

local cleanupTicker = nil
local textRefreshTicker = nil

local function runOverlayCleanup()
    for cdmIcon, overlay in pairs(activeOverlays) do
        if not isFrameVisible(cdmIcon) then
            overlay:Hide()
        end
    end
end

local function runTextRefresh()
    for cdmIcon, overlay in pairs(activeOverlays) do
        if isFrameVisible(cdmIcon) and overlay:IsShown() then
            local parent = cdmIcon:GetParent()
            local parentName = parent and parent:GetName()
            local componentId = parentName and CDM_VIEWERS[parentName]
            
            if componentId then
                local component = addon.Components and addon.Components[componentId]
                if component and component.db then
                    local hasTextConfig = component.db.textCooldown or component.db.textStacks
                    if hasTextConfig then
                        Overlays.RefreshText(cdmIcon, {
                            cooldown = component.db.textCooldown,
                            stacks = component.db.textStacks,
                        })
                    end
                end
            end
        end
    end
end

-- Combined cleanup function that runs both overlay cleanup and cooldown expiration checks
local function runCombinedCleanup()
    runOverlayCleanup()
    -- Check for expired cooldowns and restore full opacity
    -- checkCooldownExpirations is defined later, so we inline the logic here
    local now = GetTime()
    for cdmIcon, endTime in pairs(cooldownEndTimes) do
        if now >= endTime then
            cooldownEndTimes[cdmIcon] = nil
            -- Restore full opacity
            pcall(function()
                if cdmIcon and not (cdmIcon.IsForbidden and cdmIcon:IsForbidden()) then
                    cdmIcon:SetAlpha(1.0)
                end
            end)
        end
    end
end

local function startCleanupTicker()
    if cleanupTicker then return end
    if C_Timer and C_Timer.NewTicker then
        -- Ticker is a fallback safety net; SPELL_UPDATE_COOLDOWN handles immediate response
        cleanupTicker = C_Timer.NewTicker(0.5, runCombinedCleanup)
    end
end

local function startTextRefreshTicker()
    -- Text refresh ticker disabled: text overlays don't work in 12.0
    -- GetText() returns secret values that can't be compared or used
    return
end

--------------------------------------------------------------------------------
-- Overlay Initialization
--------------------------------------------------------------------------------

local pendingViewers = {}
local initRetryCount = 0
local MAX_INIT_RETRIES = 10

function Overlays.Initialize()
    pendingViewers = {}
    for viewerName, componentId in pairs(CDM_VIEWERS) do
        local hooked = Overlays.HookViewer(viewerName, componentId)
        if hooked then
            Overlays.ApplyToViewer(viewerName, componentId)
        else
            pendingViewers[viewerName] = componentId
        end
    end
    
    if next(pendingViewers) then
        Overlays.ScheduleRetry()
    end
    
    startCleanupTicker()
    
    -- Initialize direct text styling (12.0 compatible approach)
    -- This hooks CooldownFrame_Set to style text directly on Blizzard's FontStrings
    hookCooldownTextStyling()
    hookProcGlowResizing()
end

function Overlays.ScheduleRetry()
    initRetryCount = initRetryCount + 1
    if initRetryCount > MAX_INIT_RETRIES then
        pendingViewers = {}
        return
    end
    
    C_Timer.After(1.0, function()
        local stillPending = {}
        for viewerName, componentId in pairs(pendingViewers) do
            local hooked = Overlays.HookViewer(viewerName, componentId)
            if hooked then
                Overlays.ApplyToViewer(viewerName, componentId)
            else
                stillPending[viewerName] = componentId
            end
        end
        pendingViewers = stillPending
        
        if next(pendingViewers) then
            Overlays.ScheduleRetry()
        end
    end)
end

--------------------------------------------------------------------------------
-- Viewer-Level Opacity System (12.0 Safe)
--------------------------------------------------------------------------------
-- SetAlpha on viewer container frames (not individual icons) is safe in 12.0.
-- Verified Jan 15 2026: No taint errors in combat with viewer-level SetAlpha.
--
-- This system implements the opacity settings from each CDM component:
--   - opacity: Alpha when in combat (from Edit Mode, stored as 50-100)
--   - opacityOutOfCombat: Alpha when not in combat
--   - opacityWithTarget: Alpha when player has a target
--------------------------------------------------------------------------------

-- All viewers that support opacity (including trackedBars)
local CDM_OPACITY_VIEWERS = {
    EssentialCooldownViewer = "essentialCooldowns",
    UtilityCooldownViewer = "utilityCooldowns",
    BuffIconCooldownViewer = "trackedBuffs",
    BuffBarCooldownViewer = "trackedBars",
}

-- Get the appropriate opacity value based on current game state
local function getViewerOpacityForState(componentId)
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return 1.0 end
    
    local db = component.db
    local inCombat = InCombatLockdown and InCombatLockdown()
    local hasTarget = UnitExists("target")
    
    -- Priority: combat > target > out-of-combat
    local opacityValue
    if inCombat then
        -- In combat: use combat opacity (Edit Mode setting, stored as 50-100)
        opacityValue = tonumber(db.opacity) or 100
    elseif hasTarget then
        -- Has target: use target opacity
        opacityValue = tonumber(db.opacityWithTarget) or 100
    else
        -- Out of combat, no target: use out-of-combat opacity
        opacityValue = tonumber(db.opacityOutOfCombat) or 100
    end
    
    -- Convert from percentage (1-100) to alpha (0.0-1.0)
    return math.max(0.01, math.min(1.0, opacityValue / 100))
end

-- Apply opacity to a single viewer frame and its overlays
local function applyViewerOpacity(viewerName, componentId)
    local viewer = _G[viewerName]
    if not viewer then return end
    
    if viewer.IsForbidden and viewer:IsForbidden() then return end
    
    local alpha = getViewerOpacityForState(componentId)
    
    -- Apply to viewer frame
    -- Overlays are parented to CDM icons (children of the viewer), so they
    -- automatically inherit the viewer's alpha through the parent chain.
    -- No need to explicitly set overlay alpha - doing so would double-reduce it.
    pcall(function()
        viewer:SetAlpha(alpha)
    end)
end

-- Update all CDM viewer opacities based on current state
local function updateAllViewerOpacities()
    for viewerName, componentId in pairs(CDM_OPACITY_VIEWERS) do
        applyViewerOpacity(viewerName, componentId)
    end
end

-- Exposed function for settings changes
function addon.RefreshCDMViewerOpacity(componentId)
    if componentId then
        -- Refresh specific component
        for viewerName, cid in pairs(CDM_OPACITY_VIEWERS) do
            if cid == componentId then
                applyViewerOpacity(viewerName, componentId)
                break
            end
        end
    else
        -- Refresh all
        updateAllViewerOpacities()
    end
end

--------------------------------------------------------------------------------
-- Per-Icon Cooldown Opacity System (12.0 Compatible)
--------------------------------------------------------------------------------
-- This system dims individual icons when their ability is on cooldown.
-- Uses SetAlpha on CDM icons (verified safe Jan 2026).
-- Per-icon alpha multiplies with viewer-level alpha via WoW's alpha inheritance.
--------------------------------------------------------------------------------

-- Check if an icon is currently on cooldown
local function isIconOnCooldown(cdmIcon)
    local endTime = cooldownEndTimes[cdmIcon]
    if not endTime then return false end
    return GetTime() < endTime
end

-- Get component ID from a CDM icon frame
local function getIconComponentId(cdmIcon)
    if not cdmIcon then return nil end
    local parent = cdmIcon:GetParent()
    if not parent then return nil end
    local parentName = parent.GetName and parent:GetName()
    return parentName and CDM_VIEWERS[parentName]
end

-- Update opacity for a single icon based on its cooldown state
local function updateIconCooldownOpacity(cdmIcon)
    if not cdmIcon then return end
    if cdmIcon.IsForbidden and cdmIcon:IsForbidden() then return end

    local componentId = getIconComponentId(cdmIcon)
    if not componentId then return end

    -- Only Essential and Utility cooldowns support this feature
    if componentId ~= "essentialCooldowns" and componentId ~= "utilityCooldowns" then
        return
    end

    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return end

    local opacitySetting = tonumber(component.db.opacityOnCooldown) or 100
    -- If setting is 100%, feature is disabled (no dimming)
    if opacitySetting >= 100 then
        pcall(function() cdmIcon:SetAlpha(1.0) end)
        return
    end

    local isOnCD = isIconOnCooldown(cdmIcon)
    local targetAlpha = isOnCD and (opacitySetting / 100) or 1.0

    pcall(function()
        cdmIcon:SetAlpha(targetAlpha)
    end)
end

-- Check for expired cooldowns and restore full opacity
local function checkCooldownExpirations()
    local now = GetTime()
    for cdmIcon, endTime in pairs(cooldownEndTimes) do
        if now >= endTime then
            cooldownEndTimes[cdmIcon] = nil
            updateIconCooldownOpacity(cdmIcon)  -- Restore full opacity
        end
    end
end

-- Exposed function for settings changes
function addon.RefreshCDMCooldownOpacity(componentId)
    -- Iterate tracked icons and update their cooldown opacity
    for cdmIcon, _ in pairs(cooldownEndTimes) do
        if componentId then
            local iconComponentId = getIconComponentId(cdmIcon)
            if iconComponentId == componentId then
                updateIconCooldownOpacity(cdmIcon)
            end
        else
            updateIconCooldownOpacity(cdmIcon)
        end
    end

    -- Also refresh any visible icons in the viewers that may not be tracked yet
    if componentId then
        local viewerName
        for vn, cid in pairs(CDM_VIEWERS) do
            if cid == componentId then
                viewerName = vn
                break
            end
        end
        if viewerName then
            local viewer = _G[viewerName]
            if viewer and viewer.GetChildren then
                for _, child in ipairs({viewer:GetChildren()}) do
                    if child and child.Cooldown then
                        updateIconCooldownOpacity(child)
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Combat start
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Combat end

local lastRefreshTime = {}
local REFRESH_THROTTLE = 0.1

local function throttledRefresh(viewerName, componentId)
    local now = GetTime()
    local lastTime = lastRefreshTime[viewerName] or 0
    if now - lastTime < REFRESH_THROTTLE then
        return
    end
    lastRefreshTime[viewerName] = now

    C_Timer.After(0.05, function()
        Overlays.ApplyToViewer(viewerName, componentId)
    end)
end

eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        initRetryCount = 0
        C_Timer.After(1.0, function()
            for viewerName, componentId in pairs(CDM_VIEWERS) do
                if not hookedViewers[viewerName] then
                    local hooked = Overlays.HookViewer(viewerName, componentId)
                    if hooked then
                        Overlays.ApplyToViewer(viewerName, componentId)
                    end
                else
                    Overlays.ApplyToViewer(viewerName, componentId)
                end
            end
            startCleanupTicker()
            hookCooldownTextStyling()
            hookProcGlowResizing()

            -- Apply initial viewer opacity based on current state
            updateAllViewerOpacities()
        end)
        
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat started: update viewer opacities to combat values
        updateAllViewerOpacities()
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: update viewer opacities to out-of-combat values
        updateAllViewerOpacities()
        
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            throttledRefresh("BuffIconCooldownViewer", "trackedBuffs")
        end
        
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Update opacity for target state change
        updateAllViewerOpacities()

        for viewerName, componentId in pairs(CDM_VIEWERS) do
            throttledRefresh(viewerName, componentId)
        end
        
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        throttledRefresh("EssentialCooldownViewer", "essentialCooldowns")
        throttledRefresh("UtilityCooldownViewer", "utilityCooldowns")

        -- Immediately check for expired cooldowns and restore opacity
        -- This provides faster response than waiting for the ticker
        local now = GetTime()
        for cdmIcon, endTime in pairs(cooldownEndTimes) do
            if now >= endTime then
                cooldownEndTimes[cdmIcon] = nil
                pcall(function()
                    if cdmIcon and not (cdmIcon.IsForbidden and cdmIcon:IsForbidden()) then
                        cdmIcon:SetAlpha(1.0)
                    end
                end)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Settings Change Handler
--------------------------------------------------------------------------------

function Overlays.OnSettingsChanged(componentId)
    for viewerName, cid in pairs(CDM_VIEWERS) do
        if cid == componentId then
            Overlays.ApplyToViewer(viewerName, componentId)
            break
        end
    end
end

addon.RefreshCDMOverlays = function(componentId)
    if componentId then
        Overlays.OnSettingsChanged(componentId)
    else
        for viewerName, cid in pairs(CDM_VIEWERS) do
            Overlays.ApplyToViewer(viewerName, cid)
        end
    end
    
    -- Also refresh direct text styling (12.0 compatible approach)
    if addon.RefreshCDMTextStyling then
        C_Timer.After(0.1, function()
            addon.RefreshCDMTextStyling()
        end)
    end
    
    -- Refresh viewer opacity when settings change
    if addon.RefreshCDMViewerOpacity then
        addon.RefreshCDMViewerOpacity(componentId)
    end
end

--------------------------------------------------------------------------------
-- TrackedBars Styling (Direct - Safe for Bar Frames)
--------------------------------------------------------------------------------
-- TrackedBars (BuffBarCooldownViewer) use direct styling because bar frames
-- are not protected the same way as icon viewers. This is safe and tested.
--------------------------------------------------------------------------------

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

    -- Calculate icon dimensions from ratio
    local iconRatio = tonumber(getSettingValue("iconTallWideRatio")) or 0
    local iconWidth, iconHeight
    if addon.IconRatio then
        iconWidth, iconHeight = addon.IconRatio.GetDimensionsForComponent("trackedBars", iconRatio)
    else
        -- Fallback if IconRatio not loaded
        iconWidth, iconHeight = 30, 30
    end
    if iconWidth and iconHeight and iconFrame.SetSize then
        iconWidth = math.max(8, math.min(32, iconWidth))
        iconHeight = math.max(8, math.min(32, iconHeight))
        iconFrame:SetSize(iconWidth, iconHeight)
        local tex = iconFrame.Icon or (child.GetIconTexture and child:GetIconTexture())
        if tex and tex.SetAllPoints then tex:SetAllPoints(iconFrame) end
        local mask = iconFrame.Mask or iconFrame.IconMask
        if mask and mask.SetAllPoints then mask:SetAllPoints(iconFrame) end
    end

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
            -- Use weak-key lookup to avoid reading taint-causing properties from Blizzard frames
            local barState = addon.Media.GetBarFrameState and addon.Media.GetBarFrameState(barFrame)
            local bgTexture = barState and barState.bg
            if bgTexture then
                local r, g, b, a = 0, 0, 0, 1
                if bgColorMode == "custom" and type(bgTint) == "table" then
                    r, g, b, a = bgTint[1] or 0, bgTint[2] or 0, bgTint[3] or 0, bgTint[4] or 1
                elseif bgColorMode == "texture" then
                    r, g, b, a = 1, 1, 1, 1
                elseif bgColorMode == "default" then
                    r, g, b, a = 0, 0, 0, 1
                end
                if bgTexture.SetVertexColor then
                    pcall(bgTexture.SetVertexColor, bgTexture, r, g, b, 1.0)
                end
                if bgTexture.SetAlpha then
                    local opacity = tonumber(bgOpacity) or 50
                    opacity = math.max(0, math.min(100, opacity)) / 100
                    pcall(bgTexture.SetAlpha, bgTexture, opacity)
                end
            end
        else
            -- Use weak-key lookup for background texture
            local barState = addon.Media.GetBarFrameState and addon.Media.GetBarFrameState(barFrame)
            local bgTexture = barState and barState.bg
            if bgTexture then bgTexture:Hide() end
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
        -- DEBUG: Trace border tint values
        if addon.debugEnabled then
            print(string.format("[TrackedBars] borderTintEnable=%s, borderTintColor=%s",
                tostring(component.db.borderTintEnable),
                type(component.db.borderTintColor) == "table" and
                    string.format("{%.2f,%.2f,%.2f,%.2f}",
                        component.db.borderTintColor[1] or 0,
                        component.db.borderTintColor[2] or 0,
                        component.db.borderTintColor[3] or 0,
                        component.db.borderTintColor[4] or 0)
                    or "nil"))
        end
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
            local inset = tonumber(component.db.borderInset) or 0
            handled = addon.BarBorders.ApplyToBarFrame(barFrame, styleKey, {
                color = color,
                thickness = thickness,
                inset = inset,
            })
        end

        if handled then
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(barFrame) end
            Util.HideDefaultBarTextures(barFrame)
        else
            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(barFrame) end
            if addon.Borders and addon.Borders.ApplySquare then
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

    local defaultFace = (select(1, GameFontNormal:GetFont()))
    
    local function promoteFontLayer(font)
        if font and font.SetDrawLayer then
            font:SetDrawLayer("OVERLAY", 5)
        end
    end
    promoteFontLayer((child.GetNameLabel and child:GetNameLabel()) or child.Name or child.Text or child.Label)
    promoteFontLayer((child.GetDurationLabel and child:GetDurationLabel()) or child.Duration or child.DurationText or child.Timer or child.TimerText)

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

    local nameFS = (barFrame and barFrame.Name) or findFontStringByNameHint(barFrame or child, "Bar.Name") or findFontStringByNameHint(child, "Name")
    local durFS  = (barFrame and barFrame.Duration) or findFontStringByNameHint(barFrame or child, "Bar.Duration") or findFontStringByNameHint(child, "Duration")

    if nameFS and nameFS.SetFont then
        local cfg = component.db.textName or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
        local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
        pcall(nameFS.SetDrawLayer, nameFS, "OVERLAY", 10)
        if addon.ApplyFontStyle then addon.ApplyFontStyle(nameFS, face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") else nameFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") end
        local c = resolveCDMColor(cfg)
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
        local cfg = component.db.textDuration or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
        local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
        pcall(durFS.SetDrawLayer, durFS, "OVERLAY", 10)
        if addon.ApplyFontStyle then addon.ApplyFontStyle(durFS, face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") else durFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") end
        local c = resolveCDMColor(cfg)
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
        local cfg = component.db.textStacks or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
        local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
        pcall(stacksFS.SetDrawLayer, stacksFS, "OVERLAY", 10)
        if addon.ApplyFontStyle then addon.ApplyFontStyle(stacksFS, face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") else stacksFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE") end
        local c = resolveCDMColor(cfg)
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
end

--------------------------------------------------------------------------------
-- TrackedBars Hooks
--------------------------------------------------------------------------------

local trackedBarsHooked = false

local function hookTrackedBars(component)
    if trackedBarsHooked then return end
    
    local frame = _G[component.frameName]
    if not frame then return end
    
    if frame.OnAcquireItemFrame then
        hooksecurefunc(frame, "OnAcquireItemFrame", function(viewer, itemFrame)
            if InCombatLockdown and InCombatLockdown() then return end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if addon and addon.ApplyTrackedBarVisualsForChild then
                        addon.ApplyTrackedBarVisualsForChild(component, itemFrame)
                    end
                end)
            end
        end)
    end
    
    if frame.RefreshLayout then
        hooksecurefunc(frame, "RefreshLayout", function()
            if InCombatLockdown and InCombatLockdown() then return end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if not addon or not addon.Components or not addon.Components.trackedBars then return end
                    local f = _G[addon.Components.trackedBars.frameName]
                    if not f then return end
                    for _, child in ipairs({ f:GetChildren() }) do
                        if addon and addon.ApplyTrackedBarVisualsForChild then
                            addon.ApplyTrackedBarVisualsForChild(component, child)
                        end
                    end
                end)
            end
        end)
    end
    
    trackedBarsHooked = true
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    -- TrackedBars apply styling directly; icon-based CDM uses overlays
    local function SafeApplyStyling(component)
        if component.id == "trackedBars" then
            -- TrackedBars use direct styling (safe for bar frames)
            local frame = _G[component.frameName]
            if not frame then return end
            
            hookTrackedBars(component)
            
            for _, child in ipairs({ frame:GetChildren() }) do
                if addon and addon.ApplyTrackedBarVisualsForChild then
                    addon.ApplyTrackedBarVisualsForChild(component, child)
                end
            end
        else
            -- Icon-based CDM uses overlay system
            if addon.RefreshCDMOverlays then
                addon.RefreshCDMOverlays(component.id)
            end
        end
    end

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
                label = "Icon Padding", widget = "slider", min = 2, max = 14, step = 1, section = "Positioning", order = 4
            }},
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            tallWideRatio = { type = "addon", default = 0, ui = {
                label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Sizing", order = 2
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
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 5
            }},
            borderInset = { type = "addon", default = -1, ui = {
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
            opacityOnCooldown = { type = "addon", default = 100, ui = {
                label = "Opacity While on Cooldown", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 5
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 6
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 7
            }},
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = SafeApplyStyling,
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
                label = "Icon Padding", widget = "slider", min = 2, max = 14, step = 1, section = "Positioning", order = 4
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
            tallWideRatio = { type = "addon", default = 0, ui = {
                label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Sizing", order = 2
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
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 5
            }},
            borderInset = { type = "addon", default = -1, ui = {
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
            opacityOnCooldown = { type = "addon", default = 100, ui = {
                label = "Opacity While on Cooldown", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 5
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
        ApplyStyling = SafeApplyStyling,
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
                label = "Icon Padding", widget = "slider", min = 2, max = 14, step = 1, section = "Positioning", order = 3
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
            tallWideRatio = { type = "addon", default = 0, ui = {
                label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Sizing", order = 2
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
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 5
            }},
            borderInset = { type = "addon", default = -1, ui = {
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
        ApplyStyling = SafeApplyStyling,
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
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 5
            }},
            borderInset = { type = "addon", default = 0, ui = {
                label = "Border Inset", widget = "slider", min = -4, max = 4, step = 1, section = "Border", order = 6
            }},
            iconTallWideRatio = { type = "addon", default = 0, ui = {
                label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Icon", order = 1
            }},
            iconBorderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Icon", order = 2
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
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Icon", order = 7
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
        ApplyStyling = SafeApplyStyling,
    })
    self:RegisterComponent(trackedBars)
    
    -- Initialize overlay system after components are registered
    C_Timer.After(0.5, function()
        Overlays.Initialize()
    end)
end)
