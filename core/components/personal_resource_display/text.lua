--------------------------------------------------------------------------------
-- personal_resource_display/text.lua
-- Text overlay system: FontString creation, hook installation, text caching,
-- styling. Mirrors Player UF text onto PRD bars via hooks.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PRD

-- Import from core
local getHealthContainer = PRD._getHealthContainer
local getPowerBar = PRD._getPowerBar

--------------------------------------------------------------------------------
-- Text Overlay State
--------------------------------------------------------------------------------

-- Storage for text overlay state (one per bar type, not per bar instance)
local textOverlays = {
    health = { lastLeft = nil, lastRight = nil, overlay = nil, leftFS = nil, rightFS = nil },
    power = { lastLeft = nil, lastRight = nil, overlay = nil, leftFS = nil, rightFS = nil },
}

-- Promote for opacity.lua to access
PRD._textOverlays = textOverlays

-- Hook installation tracking
local textHooksInstalled = { power = false, health = false }

--------------------------------------------------------------------------------
-- Font Resolution
--------------------------------------------------------------------------------

-- Resolve font path from font name or font key.
-- Delegates to addon.ResolveFontFace which handles internal keys, LSM keys, and fallback.
local function resolveFontPath(fontName)
    if not fontName or fontName == "" then
        return "Fonts\\FRIZQT__.TTF"
    end
    -- If it looks like a file path already, use it directly
    if fontName:match("\\") or fontName:match("/") then
        return fontName
    end
    return addon.ResolveFontFace(fontName)
end

--------------------------------------------------------------------------------
-- Overlay Creation
--------------------------------------------------------------------------------

-- Create overlay FontStrings on a PRD bar (one overlay per bar type)
local function ensureTextOverlay(bar, overlayType)
    if not bar then return nil, nil end

    local storage = textOverlays[overlayType]
    if not storage then return nil, nil end

    -- Already created
    if storage.overlay then
        -- Re-anchor in case the bar was recreated
        pcall(storage.overlay.SetPoint, storage.overlay, "TOPLEFT", bar, "TOPLEFT", 0, 0)
        pcall(storage.overlay.SetPoint, storage.overlay, "BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        return storage.leftFS, storage.rightFS
    end

    -- Create overlay frame parented to UIParent, anchored to PRD bar
    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    overlay:SetFrameStrata("HIGH")
    overlay:SetFrameLevel(100)
    overlay:Show()

    local leftText = overlay:CreateFontString(nil, "OVERLAY")
    leftText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    leftText:SetPoint("LEFT", overlay, "LEFT", 4, 0)
    leftText:SetJustifyH("LEFT")
    leftText:SetTextColor(1, 1, 1, 1)
    leftText:Show()

    local rightText = overlay:CreateFontString(nil, "OVERLAY")
    rightText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    rightText:SetPoint("RIGHT", overlay, "RIGHT", -4, 0)
    rightText:SetJustifyH("RIGHT")
    rightText:SetTextColor(1, 1, 1, 1)
    rightText:Show()

    storage.overlay = overlay
    storage.leftFS = leftText
    storage.rightFS = rightText

    return leftText, rightText
end

--------------------------------------------------------------------------------
-- Text Styling
--------------------------------------------------------------------------------

-- Apply text alignment by re-anchoring a FontString within the overlay
local function applyTextAlignment(fs, overlay, alignment)
    if not fs or not overlay then return end
    pcall(fs.ClearAllPoints, fs)
    if alignment == "LEFT" then
        pcall(fs.SetPoint, fs, "LEFT", overlay, "LEFT", 4, 0)
    elseif alignment == "CENTER" then
        pcall(fs.SetPoint, fs, "CENTER", overlay, "CENTER", 0, 0)
    else -- "RIGHT"
        pcall(fs.SetPoint, fs, "RIGHT", overlay, "RIGHT", -4, 0)
    end
end

-- Check if text should be visible for the current Druid shapeshift form.
-- Returns true for non-Druids or when no per-form restrictions are set.
-- Storage is per-spec: valueTextDruidForms[specIndex][formID] = false to hide.
local function isDruidTextVisible(db, textType)
    local _, playerClass = UnitClass("player")
    if playerClass ~= "DRUID" then return true end

    local allSpecs = (textType == "value") and db.valueTextDruidForms or db.percentTextDruidForms
    if not allSpecs or not next(allSpecs) then return true end

    local specIndex = GetSpecialization and GetSpecialization() or 1
    local forms = allSpecs[specIndex]
    if not forms or not next(forms) then return true end

    local formID = GetShapeshiftFormID and GetShapeshiftFormID() or 0
    -- Normalize moonkin talent variant to base moonkin ID
    if formID == 35 then formID = 31 end

    return forms[formID] ~= false
end

-- Apply text styling from component settings (per-text independent settings)
local function resolveColorMode(colorMode, rawColor, overlayType)
    -- Backward compat: existing custom color without mode = treat as custom
    if not colorMode then
        local c = rawColor
        if c and (c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or (c[4] or 1) ~= 1) then
            colorMode = "custom"
        else
            colorMode = "default"
        end
    end

    if colorMode == "class" then
        local cr, cg, cb = addon.GetClassColorRGB("player")
        return {cr or 1, cg or 1, cb or 1, 1}
    elseif colorMode == "classPower" and overlayType == "power" then
        local pr, pg, pb = addon.GetPowerColorRGB("player")
        return {pr or 1, pg or 1, pb or 1, 1}
    elseif colorMode == "dkSpec" and overlayType == "power" then
        local dr, dg, db = addon.GetDKSpecColorRGB()
        return {dr or 1, dg or 1, db or 1, 1}
    elseif colorMode == "custom" then
        return rawColor or {1, 1, 1, 1}
    else
        return {1, 1, 1, 1}
    end
end

local function applyTextStyle(leftText, rightText, component, overlayType)
    if not component or not component.db then return end

    local db = component.db
    local storage = textOverlays[overlayType]

    -- Left = percent text
    if leftText then
        local font = db.percentTextFont or "Friz Quadrata TT"
        local size = tonumber(db.percentTextFontSize) or 10
        local flags = db.percentTextFontFlags or "OUTLINE"
        local effectivePercentMode = addon.ReadColorMode(
            function() return db.percentTextColorMode end,
            function() return db.percentTextColorModeDK end
        )
        local color = resolveColorMode(effectivePercentMode, db.percentTextColor, overlayType)
        local align = db.percentTextAlignment or "LEFT"
        local path = resolveFontPath(font)
        addon.ApplyFontStyle(leftText, path, size, flags)
        pcall(leftText.SetTextColor, leftText, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        pcall(leftText.SetJustifyH, leftText, align)
        if storage then
            applyTextAlignment(leftText, storage.overlay, align)
        end
    end

    -- Right = value text
    if rightText then
        local font = db.valueTextFont or "Friz Quadrata TT"
        local size = tonumber(db.valueTextFontSize) or 10
        local flags = db.valueTextFontFlags or "OUTLINE"
        local effectiveValueMode = addon.ReadColorMode(
            function() return db.valueTextColorMode end,
            function() return db.valueTextColorModeDK end
        )
        local color = resolveColorMode(effectiveValueMode, db.valueTextColor, overlayType)
        local align = db.valueTextAlignment or "RIGHT"
        local path = resolveFontPath(font)
        addon.ApplyFontStyle(rightText, path, size, flags)
        pcall(rightText.SetTextColor, rightText, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        pcall(rightText.SetJustifyH, rightText, align)
        if storage then
            applyTextAlignment(rightText, storage.overlay, align)
        end
    end
end

--------------------------------------------------------------------------------
-- Cached Text Application
--------------------------------------------------------------------------------

-- Apply cached text values after overlay creation based on per-text show flags
-- Note: cached values may be secret values. SetText(secret) is allowed.
local function applyCachedText(overlayType, db)
    local storage = textOverlays[overlayType]
    if not storage then return end
    if db.percentTextShow and storage.leftFS then
        pcall(storage.leftFS.SetText, storage.leftFS, storage.lastLeft)
    end
    if db.valueTextShow and storage.rightFS then
        pcall(storage.rightFS.SetText, storage.rightFS, storage.lastRight)
    end
end

-- Hide text overlay
local function hideTextOverlay(overlayType)
    local storage = textOverlays[overlayType]
    if not storage or not storage.overlay then return end
    pcall(storage.overlay.Hide, storage.overlay)
end

-- Show text overlay
local function showTextOverlay(overlayType)
    local storage = textOverlays[overlayType]
    if not storage or not storage.overlay then return end
    pcall(storage.overlay.Show, storage.overlay)
end

--------------------------------------------------------------------------------
-- Hook Callbacks
--------------------------------------------------------------------------------

-- Helper: update a single overlay FontString from a hook callback
local function onSourceTextChanged(overlayType, side, text)
    local storage = textOverlays[overlayType]
    if not storage then return end

    if side == "left" then
        storage.lastLeft = text
    else
        storage.lastRight = text
    end

    -- Get the component to check per-text show settings
    local compId = (overlayType == "power") and "prdPower" or "prdHealth"
    local comp = addon.Components and addon.Components[compId]
    if not comp or not comp.db then return end

    local fs = (side == "left") and storage.leftFS or storage.rightFS
    if not fs then return end

    -- text may be a secret value; SetText(secret) is allowed and renders it
    if side == "left" then
        if comp.db.percentTextShow and isDruidTextVisible(comp.db, "percent") then
            pcall(fs.SetText, fs, text)
        end
    else
        if comp.db.valueTextShow and isDruidTextVisible(comp.db, "value") then
            pcall(fs.SetText, fs, text)
        end
    end
end

--------------------------------------------------------------------------------
-- Hook Installation
--------------------------------------------------------------------------------

-- Install hooks on Player UF Power Bar text (ManaBar.LeftText / .RightText)
local function installPowerTextHooks()
    if textHooksInstalled.power then return end

    local manaBar = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
    if not manaBar then return end

    local leftSource = manaBar.LeftText
    local rightSource = manaBar.RightText

    if leftSource then
        hooksecurefunc(leftSource, "SetText", function(self, text)
            onSourceTextChanged("power", "left", text)
        end)
        if leftSource.SetFormattedText then
            hooksecurefunc(leftSource, "SetFormattedText", function(self, ...)
                local ok, text = pcall(self.GetText, self)
                if ok then onSourceTextChanged("power", "left", text) end
            end)
        end
        -- Capture initial value (may be secret value; SetText(secret) is allowed)
        local ok, text = pcall(leftSource.GetText, leftSource)
        if ok then
            textOverlays.power.lastLeft = text
        end
    end

    if rightSource then
        hooksecurefunc(rightSource, "SetText", function(self, text)
            onSourceTextChanged("power", "right", text)
        end)
        if rightSource.SetFormattedText then
            hooksecurefunc(rightSource, "SetFormattedText", function(self, ...)
                local ok, text = pcall(self.GetText, self)
                if ok then onSourceTextChanged("power", "right", text) end
            end)
        end
        local ok, text = pcall(rightSource.GetText, rightSource)
        if ok then
            textOverlays.power.lastRight = text
        end
    end

    textHooksInstalled.power = true
end

-- Install hooks on Player UF Health Bar text (HealthBar.LeftText / .RightText)
local function installHealthTextHooks()
    if textHooksInstalled.health then return end

    local healthBar = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
    if not healthBar then return end

    local leftSource = healthBar.LeftText
    local rightSource = healthBar.RightText

    if leftSource then
        hooksecurefunc(leftSource, "SetText", function(self, text)
            onSourceTextChanged("health", "left", text)
        end)
        if leftSource.SetFormattedText then
            hooksecurefunc(leftSource, "SetFormattedText", function(self, ...)
                local ok, text = pcall(self.GetText, self)
                if ok then onSourceTextChanged("health", "left", text) end
            end)
        end
        local ok, text = pcall(leftSource.GetText, leftSource)
        if ok then
            textOverlays.health.lastLeft = text
        end
    end

    if rightSource then
        hooksecurefunc(rightSource, "SetText", function(self, text)
            onSourceTextChanged("health", "right", text)
        end)
        if rightSource.SetFormattedText then
            hooksecurefunc(rightSource, "SetFormattedText", function(self, ...)
                local ok, text = pcall(self.GetText, self)
                if ok then onSourceTextChanged("health", "right", text) end
            end)
        end
        local ok, text = pcall(rightSource.GetText, rightSource)
        if ok then
            textOverlays.health.lastRight = text
        end
    end

    textHooksInstalled.health = true
end

--------------------------------------------------------------------------------
-- Entry Points
--------------------------------------------------------------------------------

-- Apply text overlay for power bar (called from power.ApplyStyling)
local function applyPowerTextOverlay(comp)
    if not comp or not comp.db then return end

    local db = comp.db
    local showValue = db.valueTextShow
    local showPercent = db.percentTextShow

    -- Druid per-form override: hide text in specific shapeshift forms
    if showValue then showValue = isDruidTextVisible(db, "value") end
    if showPercent then showPercent = isDruidTextVisible(db, "percent") end

    if (not showValue and not showPercent) or db.hideBar then
        hideTextOverlay("power")
        return
    end

    -- Target: PRD Power Bar
    local prdPowerBar = PersonalResourceDisplayFrame and PersonalResourceDisplayFrame.PowerBar
    if not prdPowerBar then return end

    -- Install hooks on Player UF ManaBar text
    installPowerTextHooks()

    -- Create/get overlay FontStrings anchored to PRD Power Bar
    local leftText, rightText = ensureTextOverlay(prdPowerBar, "power")
    if not leftText and not rightText then return end

    showTextOverlay("power")
    applyTextStyle(leftText, rightText, comp, "power")

    -- Show/hide individual FontStrings
    if showPercent then pcall(leftText.Show, leftText) else pcall(leftText.Hide, leftText) end
    if showValue then pcall(rightText.Show, rightText) else pcall(rightText.Hide, rightText) end

    applyCachedText("power", db)
end

-- Apply text overlay for health bar (called from health.ApplyStyling)
local function applyHealthTextOverlay(comp)
    if not comp or not comp.db then return end

    local db = comp.db
    local showValue = db.valueTextShow
    local showPercent = db.percentTextShow

    if (not showValue and not showPercent) or db.hideBar then
        hideTextOverlay("health")
        return
    end

    -- Target: PRD Health Bar
    local prdHealthBar = PersonalResourceDisplayFrame
        and PersonalResourceDisplayFrame.HealthBarsContainer
        and PersonalResourceDisplayFrame.HealthBarsContainer.healthBar
    if not prdHealthBar then return end

    -- Install hooks on Player UF HealthBar text
    installHealthTextHooks()

    -- Create/get overlay FontStrings anchored to PRD Health Bar
    local leftText, rightText = ensureTextOverlay(prdHealthBar, "health")
    if not leftText and not rightText then return end

    showTextOverlay("health")
    applyTextStyle(leftText, rightText, comp, "health")

    -- Show/hide individual FontStrings
    if showPercent then pcall(leftText.Show, leftText) else pcall(leftText.Hide, leftText) end
    if showValue then pcall(rightText.Show, rightText) else pcall(rightText.Hide, rightText) end

    applyCachedText("health", db)
end

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

PRD._applyHealthTextOverlay = applyHealthTextOverlay
PRD._applyPowerTextOverlay = applyPowerTextOverlay
PRD._hideTextOverlay = hideTextOverlay
