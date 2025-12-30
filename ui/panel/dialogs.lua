-- ScooterMod Custom Dialog System
-- Replaces StaticPopupDialogs usage to avoid tainting Blizzard's global table,
-- which can block protected functions like ForceQuit(), Logout(), etc.
local addonName, addon = ...

addon.Dialogs = addon.Dialogs or {}
local Dialogs = addon.Dialogs

-- Registry of dialog definitions (local to avoid taint)
local dialogRegistry = {}

-- The reusable dialog frame
local dialogFrame

--------------------------------------------------------------------------------
-- Internal Theming Helpers (use SettingsPanel helpers when available)
--------------------------------------------------------------------------------

local function GetRobotoFont()
    local fonts = addon and addon.Fonts or nil
    return (fonts and (fonts.ROBOTO_MED or fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
end

local function ApplyDialogRobotoWhite(fs, size, flags)
    if not fs or not fs.SetFont then return end
    local face = GetRobotoFont()
    local _, currentSize, currentFlags = fs:GetFont()
    fs:SetFont(face, size or currentSize or 12, flags or currentFlags or "")
    if fs.SetTextColor then fs:SetTextColor(1, 1, 1, 1) end
end

local function ApplyDialogButtonTheme(btn)
    if not btn then return end
    local brandR, brandG, brandB = 0.20, 0.90, 0.30 -- Scooter green

    -- Apply Roboto green to button text
    if btn.Text then
        local face = GetRobotoFont()
        local _, sz, fl = btn.Text:GetFont()
        btn.Text:SetFont(face, sz or 12, fl or "")
        btn.Text:SetTextColor(brandR, brandG, brandB, 1)
    end

    -- Desaturate and tint button textures to neutral gray
    local function tintTexture(tex, gray)
        if not tex or not tex.SetVertexColor then return end
        pcall(tex.SetDesaturated, tex, true)
        tex:SetVertexColor(gray, gray, gray)
    end

    tintTexture(btn.GetNormalTexture and btn:GetNormalTexture() or nil, 0.97)
    tintTexture(btn.GetPushedTexture and btn:GetPushedTexture() or nil, 0.93)

    -- Highlight texture
    if btn.SetHighlightTexture then
        pcall(btn.SetHighlightTexture, btn, "Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
    end
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
    if hl then
        hl:SetDesaturated(false)
        hl:SetVertexColor(1, 1, 1)
        hl:SetAlpha(0.45)
    end

    tintTexture(btn.GetDisabledTexture and btn:GetDisabledTexture() or nil, 0.90)

    -- Tint any remaining texture regions
    local regions = { btn:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r and r.IsObjectType and r:IsObjectType("Texture") then
            tintTexture(r, 0.97)
        end
    end
end

local function ApplyDialogCloseButtonTheme(closeBtn)
    if not closeBtn then return end
    local brandR, brandG, brandB = 0.20, 0.90, 0.30 -- Scooter green

    local function tintGreen(tex)
        if tex and tex.SetVertexColor then
            pcall(tex.SetDesaturated, tex, true)
            tex:SetVertexColor(brandR, brandG, brandB)
        end
    end

    tintGreen(closeBtn.GetNormalTexture and closeBtn:GetNormalTexture() or nil)
    tintGreen(closeBtn.GetPushedTexture and closeBtn:GetPushedTexture() or nil)

    -- Highlight
    if closeBtn.SetHighlightTexture then
        pcall(closeBtn.SetHighlightTexture, closeBtn, "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    end
    local hl = closeBtn.GetHighlightTexture and closeBtn:GetHighlightTexture() or nil
    if hl then
        hl:SetDesaturated(false)
        hl:SetVertexColor(1, 1, 1)
        hl:SetAlpha(0.25)
    end
end

--------------------------------------------------------------------------------
-- Dialog Frame Creation
--------------------------------------------------------------------------------

local function CreateDialogFrame()
    if dialogFrame then
        return dialogFrame
    end

    local f = CreateFrame("Frame", "ScooterModDialog", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(340, 140)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Title (use TitleText if available, otherwise create one)
    if f.TitleText then
        f.TitleText:SetText("ScooterMod")
    else
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", f, "TOP", 0, -5)
        title:SetText("ScooterMod")
        f.TitleText = title
    end
    -- Apply Roboto white styling to title
    ApplyDialogRobotoWhite(f.TitleText, 14, "")

    -- Message text
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("TOP", f, "TOP", 0, -35)
    text:SetPoint("LEFT", f, "LEFT", 20, 0)
    text:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(true)
    f.Text = text
    -- Apply Roboto white styling to message text
    ApplyDialogRobotoWhite(f.Text, 13, "")

    -- Edit box (for input dialogs, hidden by default)
    local editBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    editBox:SetSize(260, 24)
    editBox:SetPoint("TOP", f.Text, "BOTTOM", 0, -10)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(32)
    editBox:Hide()
    f.EditBox = editBox
    -- Apply Roboto white styling to edit box text
    ApplyDialogRobotoWhite(editBox, 12, "")

    -- Accept button (primary action)
    local acceptBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    acceptBtn:SetSize(100, 24)
    acceptBtn:SetText(YES or "Yes")
    f.AcceptButton = acceptBtn
    -- Apply Scooter button theming
    ApplyDialogButtonTheme(acceptBtn)

    -- Cancel button (secondary action)
    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 24)
    cancelBtn:SetText(NO or "No")
    f.CancelButton = cancelBtn
    -- Apply Scooter button theming
    ApplyDialogButtonTheme(cancelBtn)

    -- Close button behavior and theming
    if f.CloseButton then
        ApplyDialogCloseButtonTheme(f.CloseButton)
        f.CloseButton:SetScript("OnClick", function()
            f:Hide()
            if f._onCancel then
                f._onCancel(f._data)
            end
        end)
    end

    -- Escape to close
    --
    -- IMPORTANT (taint): Frame:SetPropagateKeyboardInput() is a protected API and can
    -- trigger ADDON_ACTION_BLOCKED (most commonly during combat lockdown). We avoid
    -- calling it entirely; it's not required for our dialog behavior.
    f:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then
            return
        end
        self:Hide()
        if self._onCancel then
            self._onCancel(self._data)
        end
    end)

    dialogFrame = f
    return f
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Register a dialog definition (call once at load time)
-- Example:
--   Dialogs:Register("DELETE_RULE", {
--       text = "Are you sure you want to delete this rule?",
--       acceptText = "Delete",
--       cancelText = "Cancel",
--   })
function Dialogs:Register(name, definition)
    if not name or not definition then
        return
    end
    dialogRegistry[name] = definition
end

-- Show a registered dialog
-- Example:
--   Dialogs:Show("DELETE_RULE", {
--       onAccept = function() deleteTheRule() end,
--       onCancel = function() print("cancelled") end,
--       data = { ruleId = 123 },
--       formatArgs = { "arg1", "arg2" }, -- For %s placeholders in text
--       infoOnly = true, -- If true, only show OK button (no cancel)
--       hasEditBox = true, -- If true, show an edit box for text input
--       editBoxText = "default text", -- Default text for edit box
--       maxLetters = 32, -- Max characters for edit box
--   })
function Dialogs:Show(name, options)
    options = options or {}
    local def = dialogRegistry[name]
    if not def then
        -- Fallback: treat name as text if not registered
        def = { text = name }
    end

    local f = CreateDialogFrame()

    local locked = options.locked or def.locked

    -- Persist default behaviors on first use so we can safely toggle "locked" dialogs
    -- without breaking subsequent dialogs (the frame is reused).
    if not f._scootDefaultsCaptured then
        f._scootDefaultsCaptured = true
        f._scootDefaultCloseOnClick = f.CloseButton and f.CloseButton:GetScript("OnClick") or nil
        f._scootDefaultOnKeyDown = f:GetScript("OnKeyDown")
    end

    -- Set text (with optional format arguments)
    local displayText = options.text or def.text or "Are you sure?"
    local formatArgs = options.formatArgs or def.formatArgs
    if formatArgs and type(formatArgs) == "table" and #formatArgs > 0 then
        displayText = string.format(displayText, unpack(formatArgs))
    end
    f.Text:SetText(displayText)
    -- Reapply Roboto white styling after text change
    ApplyDialogRobotoWhite(f.Text, 13, "")

    -- Always reset the Text anchors for each show call. The dialog frame is reused and
    -- some dialog types (non-editbox) add a bottom anchor to prevent overlap with buttons.
    f.Text:ClearAllPoints()
    f.Text:SetPoint("TOP", f, "TOP", 0, -35)
    f.Text:SetPoint("LEFT", f, "LEFT", 20, 0)
    f.Text:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    f.Text:SetJustifyH("CENTER")
    f.Text:SetWordWrap(true)
    ApplyDialogRobotoWhite(f.Text, 13, "")

    -- Handle edit box
    local hasEditBox = options.hasEditBox or def.hasEditBox
    if hasEditBox then
        f.EditBox:Show()
        f.EditBox:SetText(options.editBoxText or def.editBoxText or "")
        f.EditBox:SetMaxLetters(options.maxLetters or def.maxLetters or 32)
        f.EditBox:HighlightText()
        f.EditBox:SetFocus()
        -- Adjust dialog height for edit box
        f:SetHeight(170)
    else
        f.EditBox:Hide()
        f.EditBox:SetText("")
        f:SetHeight(140)
    end

    -- Optional height override (used for longer informational dialogs)
    local desiredHeight = options.height or def.height
    if desiredHeight then
        f:SetHeight(desiredHeight)
    end

    -- Determine if this is info-only (just OK, no cancel)
    local infoOnly = locked and true or (options.infoOnly or def.infoOnly)

    -- Set button text
    local acceptText = options.acceptText or def.acceptText or (infoOnly and (OKAY or "OK")) or YES or "Yes"
    local cancelText = options.cancelText or def.cancelText or NO or "No"
    f.AcceptButton:SetText(acceptText)
    f.CancelButton:SetText(cancelText)
    -- Reapply button theming after text change (ensures Roboto green text)
    ApplyDialogButtonTheme(f.AcceptButton)
    ApplyDialogButtonTheme(f.CancelButton)

    -- Apply custom button widths if specified
    local acceptWidth = options.acceptWidth or def.acceptWidth or 100
    local cancelWidth = options.cancelWidth or def.cancelWidth or 100
    f.AcceptButton:SetSize(acceptWidth, 24)
    f.CancelButton:SetSize(cancelWidth, 24)

    -- Position buttons based on dialog type
    f.AcceptButton:ClearAllPoints()
    f.CancelButton:ClearAllPoints()
    
    if infoOnly then
        -- Single centered OK button
        f.AcceptButton:SetPoint("BOTTOM", f, "BOTTOM", 0, 15)
        f.CancelButton:Hide()
    else
        -- Two buttons side by side
        local buttonGap = 10
        local totalWidth = acceptWidth + cancelWidth + buttonGap
        f.AcceptButton:SetPoint("BOTTOMLEFT", f, "BOTTOM", -totalWidth/2, 15)
        f.CancelButton:SetPoint("BOTTOMLEFT", f.AcceptButton, "BOTTOMRIGHT", buttonGap, 0)
        f.CancelButton:Show()
    end

    -- Layout: keep content above the button row.
    if hasEditBox then
        -- Edit box sits above buttons; text wraps above edit box.
        f.EditBox:ClearAllPoints()
        f.EditBox:SetPoint("LEFT", f, "LEFT", 40, 0)
        f.EditBox:SetPoint("RIGHT", f, "RIGHT", -40, 0)
        f.EditBox:SetPoint("BOTTOM", f.AcceptButton, "TOP", 0, 14)
        f.Text:SetPoint("BOTTOM", f.EditBox, "TOP", 0, 12)
    else
        -- No edit box: text wraps above the button row.
        f.Text:SetPoint("BOTTOM", f.AcceptButton, "TOP", 0, 12)
    end

    -- Lockdown behavior: prevent dismissing without choosing the primary action.
    if locked then
        if f.CloseButton then
            f.CloseButton:Hide()
            f.CloseButton:SetScript("OnClick", nil)
        end
        f:SetScript("OnKeyDown", function(self, key)
            -- Ignore ESC; locked dialogs must not be dismissible via keyboard.
            -- Do not call SetPropagateKeyboardInput() here; it can be protected/taint.
            if key == "ESCAPE" then
                return
            end
        end)
    else
        -- Restore close/ESC behavior for normal dialogs (frame is reused).
        if f.CloseButton then
            f.CloseButton:Show()
            ApplyDialogCloseButtonTheme(f.CloseButton)
            if f._scootDefaultCloseOnClick then
                f.CloseButton:SetScript("OnClick", f._scootDefaultCloseOnClick)
            end
        end
        if f._scootDefaultOnKeyDown then
            f:SetScript("OnKeyDown", f._scootDefaultOnKeyDown)
        end
    end

    -- Store callbacks and data
    f._onAccept = options.onAccept
    f._onCancel = options.onCancel
    f._data = options.data
    f._hasEditBox = hasEditBox

    -- Helper to get edit box text for callbacks
    local function getEditBoxText()
        return hasEditBox and f.EditBox:GetText() or nil
    end

    -- Wire up buttons
    f.AcceptButton:SetScript("OnClick", function()
        local editText = getEditBoxText()
        f:Hide()
        if f._onAccept then
            f._onAccept(f._data, editText)
        end
    end)

    f.CancelButton:SetScript("OnClick", function()
        f:Hide()
        if f._onCancel then
            f._onCancel(f._data)
        end
    end)

    -- Wire up Enter key in edit box
    if hasEditBox then
        f.EditBox:SetScript("OnEnterPressed", function()
            local editText = f.EditBox:GetText()
            f:Hide()
            if f._onAccept then
                f._onAccept(f._data, editText)
            end
        end)
        f.EditBox:SetScript("OnEscapePressed", function()
            f:Hide()
            if f._onCancel then
                f._onCancel(f._data)
            end
        end)
    end

    -- Show the dialog
    f:Show()
    f:Raise()

    return f
end

-- Hide any open dialog
function Dialogs:Hide()
    if dialogFrame and dialogFrame:IsShown() then
        dialogFrame:Hide()
    end
end

-- Quick confirmation dialog (no registration needed)
-- Example:
--   Dialogs:Confirm("Delete this item?", function() doDelete() end)
function Dialogs:Confirm(message, onAccept, onCancel)
    return self:Show(nil, {
        text = message,
        onAccept = onAccept,
        onCancel = onCancel,
    })
end

-- Quick info dialog (just OK button, no registration needed)
-- Example:
--   Dialogs:Info("Operation completed successfully")
function Dialogs:Info(message, onDismiss)
    return self:Show(nil, {
        text = message,
        onAccept = onDismiss,
        infoOnly = true,
    })
end

--------------------------------------------------------------------------------
-- Pre-register common ScooterMod dialogs
--------------------------------------------------------------------------------

Dialogs:Register("SCOOTERMOD_DELETE_RULE", {
    text = "Are you sure you want to delete this rule?",
    acceptText = YES or "Yes",
    cancelText = NO or "No",
})

Dialogs:Register("SCOOTERMOD_RESET_DEFAULTS", {
    text = "Are you sure you want to reset %s to all default settings and location?",
    acceptText = YES or "Yes",
    cancelText = CANCEL or "Cancel",
})

Dialogs:Register("SCOOTERMOD_COPY_UF_CONFIRM", {
    text = "Copy supported Unit Frame settings from %s to %s?",
    acceptText = "Copy",
    cancelText = CANCEL or "Cancel",
})

Dialogs:Register("SCOOTERMOD_COPY_UF_ERROR", {
    text = "%s",
    infoOnly = true,
})

Dialogs:Register("SCOOTERMOD_COPY_ACTIONBAR_CONFIRM", {
    text = "Copy settings from %s to %s?\nThis will overwrite all settings on the destination.",
    acceptText = "Copy",
    cancelText = CANCEL or "Cancel",
})

Dialogs:Register("SCOOTERMOD_COMBAT_FONT_RESTART", {
    text = "In order for Combat Font changes to take effect, you'll need to fully exit and re-open World of Warcraft.",
    infoOnly = true,
})

Dialogs:Register("SCOOTERMOD_DELETE_LAYOUT", {
    text = "Delete layout '%s'?",
    acceptText = OKAY or "OK",
    cancelText = CANCEL or "Cancel",
})

--------------------------------------------------------------------------------
-- Profile/Layout Management Dialogs (migrated from StaticPopupDialogs to avoid taint)
--------------------------------------------------------------------------------

Dialogs:Register("SCOOTERMOD_CLONE_PRESET", {
    text = "Enter a name for the new layout based on %s:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Dialogs:Register("SCOOTERMOD_RENAME_LAYOUT", {
    text = "Rename layout:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Dialogs:Register("SCOOTERMOD_COPY_LAYOUT", {
    text = "Copy layout %s:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Dialogs:Register("SCOOTERMOD_CREATE_LAYOUT", {
    text = "Create layout:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Dialogs:Register("SCOOTERMOD_SPEC_PROFILE_RELOAD", {
    text = "Switching profiles for a spec change requires a UI reload so Blizzard can rebuild a clean baseline.\n\nReload now?",
    acceptText = "Reload",
    cancelText = CANCEL or "Cancel",
    height = 200,
})

Dialogs:Register("SCOOTERMOD_APPLY_PRESET", {
    text = "Enter a name for the new profile/layout based on %s:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = "Create",
    cancelText = CANCEL or "Cancel",
})

--------------------------------------------------------------------------------
-- Preset Target Selection Dialogs (Cross-Machine Sync)
--------------------------------------------------------------------------------

Dialogs:Register("SCOOTERMOD_PRESET_TARGET_CHOICE", {
    text = "How would you like to apply the %s preset?",
    acceptText = "Create New Profile",
    cancelText = "Apply to Existing",
    acceptWidth = 140,
    cancelWidth = 140,
    height = 160,
})

Dialogs:Register("SCOOTERMOD_PRESET_OVERWRITE_CONFIRM", {
    text = "This will overwrite both the Edit Mode layout settings AND the ScooterMod profile for '%s'.\n\nAll existing customizations will be replaced with %s preset data.\n\nContinue?",
    acceptText = "Overwrite",
    cancelText = CANCEL or "Cancel",
    height = 200,
})

Dialogs:Register("SCOOTERMOD_IMPORT_CONSOLEPORT", {
    text = "This preset includes a ConsolePort profile.\n\nImport it too?\n\n(If you select Yes, your current ConsolePort profile/settings may be overwritten.)",
    acceptText = YES or "Yes",
    cancelText = NO or "No",
    height = 210,
})

