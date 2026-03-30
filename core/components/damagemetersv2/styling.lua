local _, addon = ...
local DM2 = addon.DamageMetersV2

--------------------------------------------------------------------------------
-- JiberishIcons helpers (reuse V1's addon-level exports)
--------------------------------------------------------------------------------

local function GetJiberishIcons()
    local JIGlobal = _G.ElvUI_JiberishIcons
    if not JIGlobal or type(JIGlobal) ~= "table" then return nil end
    local JI = JIGlobal[1]
    if not JI then return nil end
    if not JI.dataHelper or not JI.dataHelper.class then return nil end
    if not JI.mergedStylePacks or not JI.mergedStylePacks.class then return nil end
    return JI
end

--------------------------------------------------------------------------------
-- Apply Icon to a bar row
--------------------------------------------------------------------------------

local function ApplyIcon(row, player, db)
    local icon = row.icon
    if not icon then return end

    -- Hide icons entirely if disabled
    if db.showIcons == false then
        icon:SetTexture(nil)
        return
    end

    local iconStyle = db.iconStyle or "default"

    -- JiberishIcons: any non-"default" style is a JI style key
    if iconStyle ~= "default" then
        local JI = GetJiberishIcons()
        if JI and player.classFilename then
            local classData = JI.dataHelper.class[player.classFilename]
            if classData and classData.texCoords then
                local styleData = JI.mergedStylePacks.class.styles and JI.mergedStylePacks.class.styles[iconStyle]
                if styleData then
                    local basePath = styleData.path or JI.mergedStylePacks.class.path or ""
                    icon:SetTexture(basePath .. iconStyle)
                    icon:SetTexCoord(unpack(classData.texCoords))
                    return
                end
            end
        end
    end

    -- Default: spec icon if available
    if player.specIconID and player.specIconID ~= 0 then
        icon:SetTexture(player.specIconID)
        icon:SetTexCoord(0, 1, 0, 1)
        return
    end

    -- Class atlas fallback
    if player.classFilename and player.classFilename ~= "" then
        local atlas = GetClassAtlas and GetClassAtlas(player.classFilename)
        if atlas then
            icon:SetAtlas(atlas)
            return
        end
    end

    -- Ultimate fallback
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetTexCoord(0, 1, 0, 1)
end

--------------------------------------------------------------------------------
-- Apply text styling to a FontString
--------------------------------------------------------------------------------

local function ApplyTextStyle(fs, textSettings)
    if not fs or not textSettings then return end
    local face = addon.ResolveFontFace(textSettings.fontFace or "FRIZQT__")
    local size = textSettings.fontSize or 12
    local style = textSettings.fontStyle or "OUTLINE"
    addon.ApplyFontStyle(fs, face, size, style)

    if textSettings.colorMode == "custom" and textSettings.color then
        local c = textSettings.color
        fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
end

--------------------------------------------------------------------------------
-- Apply bar texture to a column cell
--------------------------------------------------------------------------------

local function ApplyBarTexture(cell, db)
    if not cell or not cell.bar then return end
    local path = addon.Media and addon.Media.ResolveBarTexturePath(db.barTexture or "default")
    if path then
        pcall(cell.bar.SetStatusBarTexture, cell.bar, path)
    else
        cell.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    end

    -- Background color
    local bgc = db.barBackgroundColor or { 0.1, 0.1, 0.1, 0.8 }
    cell.barBg:SetColorTexture(bgc[1] or 0.1, bgc[2] or 0.1, bgc[3] or 0.1, bgc[4] or 0.8)
end

--------------------------------------------------------------------------------
-- Get bar color for a player
--------------------------------------------------------------------------------

function DM2._GetBarColor(player, db)
    if db.barForegroundColorMode == "custom" then
        local c = db.barCustomColor or { 0.8, 0.7, 0.2, 1 }
        return c[1] or 0.8, c[2] or 0.7, c[3] or 0.2
    end
    -- Class color (default)
    local classColor = addon.ClassColors and addon.ClassColors[player.classFilename]
    if classColor then
        return classColor.r or 0.6, classColor.g or 0.6, classColor.b or 0.6
    end
    return 0.6, 0.6, 0.6
end

--------------------------------------------------------------------------------
-- Full styling pass for a window
--------------------------------------------------------------------------------

function DM2._ApplyFullStyling(windowIndex, comp)
    local win = DM2._windows[windowIndex]
    if not win then return end
    local db = comp.db

    -- Window backdrop
    if db.showBackdrop == false then
        win.background:SetColorTexture(0, 0, 0, 0)
    else
        local bc = db.windowBackdropColor or { 0.06, 0.06, 0.08, 0.95 }
        win.background:SetColorTexture(bc[1] or 0.06, bc[2] or 0.06, bc[3] or 0.08, bc[4] or 0.95)
    end

    -- Frame size and scale (per-window, falls back to shared)
    local cfg = DM2._GetWindowConfig(windowIndex)
    local fw = tonumber(cfg and cfg.frameWidth or db.frameWidth) or 350
    local fh = tonumber(cfg and cfg.frameHeight or db.frameHeight) or 250
    win.frame:SetSize(fw, fh)
    win.frame:SetScale(tonumber(cfg and cfg.windowScale or db.windowScale) or 1.0)

    -- Title bar backdrop
    if win.header and win.header._bg then
        if db.showTitleBarBackdrop == false then
            win.header._bg:SetColorTexture(0, 0, 0, 0)
        else
            win.header._bg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
        end
    end

    -- Title and timer text styling (separate settings)
    if win.titleText then ApplyTextStyle(win.titleText, db.textTitle) end
    if win.timerText then ApplyTextStyle(win.timerText, db.textTimer or db.textTitle) end

    -- Vertical title positioning — tacked on OUTSIDE the frame's left edge
    if win.verticalTitle then
        ApplyTextStyle(win.verticalTitle, db.textTitle)
        if db.verticalTitleMode then
            win.verticalTitle:ClearAllPoints()
            win.verticalTitle:SetPoint("TOPRIGHT", win.frame, "TOPLEFT", -4, -(DM2.HEADER_HEIGHT or 24) - 4)
            win.verticalTitle:SetJustifyH("CENTER")
            -- No scroll area shift — content stays in place
        else
            win.verticalTitle:Hide()
        end
    end

    -- In vertical mode, timer moves left (adjacent to gear)
    if db.verticalTitleMode and win.timerText and win.gearBtn then
        win.timerText:ClearAllPoints()
        win.timerText:SetPoint("LEFT", win.gearBtn, "RIGHT", 4, 0)
    elseif win.timerText and win.titleText then
        win.timerText:ClearAllPoints()
        win.timerText:SetPoint("LEFT", win.titleText, "RIGHT", 4, 0)
    end

    -- Column header styling
    for c = 1, DM2.MAX_COLUMNS do
        ApplyTextStyle(win.columnHeaders[c], db.textHeaders)
    end

    -- Apply text styling to all bar rows in the pool
    local barTexPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(db.barTexture or "default") or nil
    for r = 1, DM2.MAX_POOL do
        local row = win.barRows[r]
        ApplyTextStyle(row.nameText, db.textNames)
        -- Single full-width bar texture
        if row.bar and barTexPath then
            pcall(row.bar.SetStatusBarTexture, row.bar, barTexPath)
        end
        -- Value texts
        for c = 1, DM2.MAX_COLUMNS do
            local vt = row.valueTexts and row.valueTexts[c]
            if vt then ApplyTextStyle(vt, db.textValues) end
        end
    end

    -- Pinned row styling
    local pinnedRow = win.pinnedRow
    ApplyTextStyle(pinnedRow.nameText, db.textNames)
    if pinnedRow.bar and barTexPath then
        pcall(pinnedRow.bar.SetStatusBarTexture, pinnedRow.bar, barTexPath)
    end
    for c = 1, DM2.MAX_COLUMNS do
        local vt = pinnedRow.valueTexts and pinnedRow.valueTexts[c]
        if vt then ApplyTextStyle(vt, db.textValues) end
    end

    -- Recalculate layout
    DM2._CalculateColumnWidths(windowIndex, comp)
    DM2._LayoutBarRows(windowIndex, comp)
end

--------------------------------------------------------------------------------
-- Apply icon + color to a populated bar row (called during refresh)
--------------------------------------------------------------------------------

function DM2._StyleBarRow(row, player, db)
    ApplyIcon(row, player, db)
end

--------------------------------------------------------------------------------
-- Visibility management
--------------------------------------------------------------------------------

function DM2._UpdateVisibility(windowIndex, comp)
    local win = DM2._windows[windowIndex]
    if not win then return end
    local cfg = DM2._GetWindowConfig(windowIndex)
    if not cfg or not cfg.enabled then
        win.frame:Hide()
        return
    end

    local db = comp.db
    local vis = db.visibility or "always"

    if vis == "hidden" then
        win.frame:Hide()
    elseif vis == "incombat" then
        if InCombatLockdown() then
            win.frame:Show()
        else
            win.frame:Hide()
        end
    else -- "always"
        win.frame:Show()
    end
end

--------------------------------------------------------------------------------
-- Session header text
--------------------------------------------------------------------------------

function DM2._UpdateSessionHeader(windowIndex, comp)
    local win = DM2._windows[windowIndex]
    if not win then return end
    local cfg = DM2._GetWindowConfig(windowIndex)
    if not cfg then return end
    local db = comp.db

    local label
    if db.titleMode == "custom" and db.customTitle and db.customTitle ~= "" then
        label = db.customTitle
    else
        label = DM2._GetSessionLabel(cfg.sessionType)
    end

    -- Timer is handled separately by _UpdateTimerText
    win._sessionLabel = label
end
