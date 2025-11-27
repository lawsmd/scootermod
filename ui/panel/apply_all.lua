local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
local _G = _G
local format = string.format
local CreateFrame = _G and _G.CreateFrame
local ReloadUI = _G and _G.ReloadUI
local CloseDropDownMenus = _G and _G.CloseDropDownMenus
local StaticPopup_Show = _G and _G.StaticPopup_Show
local dateHelper = _G and _G.date
local POPUP_YES_LABEL = (_G and (_G.YES or _G.OKAY)) or "Yes"
local POPUP_NO_LABEL = (_G and (_G.NO or _G.CANCEL)) or "No"
local APPLY_BUTTON_LABEL = (_G and (_G.APPLY or _G.OKAY)) or "Apply"

local function EnsureCallbackContainer(frame)
    if not frame then return end
    if not frame.cbrHandles then
        if Settings and Settings.CreateCallbackHandleContainer then
            frame.cbrHandles = Settings.CreateCallbackHandleContainer()
        else
            frame.cbrHandles = {
                Unregister = function() end,
                RegisterCallback = function() end,
                AddHandle = function() end,
                SetOnValueChangedCallback = function() end,
                IsEmpty = function() return true end,
            }
        end
    end
end

local function formatFailureMessage(kind, reason)
    local friendly = {
        noProfile = "Profile database unavailable.",
        noSelection = "Select an option before applying.",
        noChanges = "All entries already use that selection.",
    }
    local detail = friendly[reason] or tostring(reason or "Unknown error.")
    return format("Apply All (%s) aborted: %s", kind, detail)
end

local function ensureFontPopup()
    _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
    local dialogs = _G.StaticPopupDialogs
    if dialogs["SCOOTERMOD_APPLYALL_FONTS"] then
        return
    end
    dialogs["SCOOTERMOD_APPLYALL_FONTS"] = {
        text = "This will overwrite every ScooterMod font with |cFF00FF00%s|r and immediately reload your UI.\n\nThis cannot be undone automatically. Continue?",
        button1 = POPUP_YES_LABEL,
        button2 = POPUP_NO_LABEL,
        OnAccept = function(self, data)
            if not data or not data.fontKey then return end
            if not addon.ApplyAll or not addon.ApplyAll.ApplyFonts then return end
            local result = addon.ApplyAll:ApplyFonts(data.fontKey, { updatePending = true })
            if result and result.ok and result.changed and result.changed > 0 then
                ReloadUI()
            else
                local reason = result and result.reason or "Unknown"
                addon:Print(formatFailureMessage("Fonts", reason))
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

local function ensureTexturePopup()
    _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
    local dialogs = _G.StaticPopupDialogs
    if dialogs["SCOOTERMOD_APPLYALL_TEXTURES"] then
        return
    end
    dialogs["SCOOTERMOD_APPLYALL_TEXTURES"] = {
        text = "This will overwrite every ScooterMod bar texture with |cFF00FF00%s|r (foreground and background) and immediately reload your UI.\n\nThis cannot be undone automatically. Continue?",
        button1 = POPUP_YES_LABEL,
        button2 = POPUP_NO_LABEL,
        OnAccept = function(self, data)
            if not data or not data.textureKey then return end
            if not addon.ApplyAll or not addon.ApplyAll.ApplyBarTextures then return end
            local result = addon.ApplyAll:ApplyBarTextures(data.textureKey, { updatePending = true })
            if result and result.ok and result.changed and result.changed > 0 then
                ReloadUI()
            else
                local reason = result and result.reason or "Unknown"
                addon:Print(formatFailureMessage("Bar Textures", reason))
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

local function createInfoRow(message)
    local row = Settings.CreateElementInitializer("SettingsListElementTemplate")
    row.GetExtent = function() return 96 end
    row.InitFrame = function(self, frame)
        EnsureCallbackContainer(frame)
        if frame.Text then frame.Text:Hide() end
        if frame.ButtonContainer then frame.ButtonContainer:Hide(); frame.ButtonContainer:SetAlpha(0); frame.ButtonContainer:EnableMouse(false) end
        if frame.InfoText then frame.InfoText:Hide() end
        if not frame.ApplyAllInfoText then
            local info = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            info:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -6)
            info:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
            info:SetJustifyH("LEFT")
            info:SetJustifyV("TOP")
            info:SetWordWrap(true)
            if panel.ApplyRobotoWhite then
                panel.ApplyRobotoWhite(info, 16, "")
            end
            frame.ApplyAllInfoText = info
        end
        frame.ApplyAllInfoText:SetText(message or "")
        frame.ApplyAllInfoText:Show()
        local textHeight = frame.ApplyAllInfoText:GetStringHeight() or 0
        frame:SetHeight(math.max(70, textHeight + 32))
    end
    return row
end

local function createApplyRow(categoryKey, optionsProvider, getPending, setPending, triggerPopup, opts)
    local row = Settings.CreateElementInitializer("ScooterActiveListElementTemplate")
    row.GetExtent = function() return 220 end
    row.InitFrame = function(self, frame)
        EnsureCallbackContainer(frame)
        if frame.Text then frame.Text:Hide() end
        if frame.InfoText then frame.InfoText:Hide() end
        if frame.ButtonContainer then frame.ButtonContainer:Hide() end
        if frame.MessageText then frame.MessageText:Hide() end
        if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end

        local function ensureDropdown()
            if frame.SelectionDropdown then
                local setting = frame.SelectionDropdownSetting
                local current = getPending() or ""
                if setting and setting.GetValue and setting:GetValue() ~= current then
                    setting:SetValue(current)
                end
                return
            end

            local setting = CreateLocalSetting("ApplyAll" .. categoryKey .. "Selection", "string",
                function()
                    return getPending() or ""
                end,
                function(value)
                    if not value or value == "" then return end
                    if value == (getPending() or "") then return end
                    setPending(value)
                end,
                getPending() or "")
            frame.SelectionDropdownSetting = setting

            local initializer = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                name = "",
                setting = setting,
                options = optionsProvider,
            })
            local dropdown = CreateFrame("Frame", nil, frame, "SettingsDropdownControlTemplate")
            dropdown.GetElementData = function() return initializer end
            dropdown:SetPoint("TOP", frame, "TOP", 0, -12)
            dropdown:SetPoint("CENTER", frame, "CENTER", 0, 24)
            dropdown:SetScale(1.3)
            dropdown:SetWidth(360)
            initializer:InitFrame(dropdown)
            if dropdown.Text then dropdown.Text:Hide() end
            if dropdown.LeftMargin then dropdown.LeftMargin:SetWidth(0) end
            local control = dropdown.Control
            if control then
                control:ClearAllPoints()
                control:SetPoint("CENTER", dropdown, "CENTER", 0, -6)
                control:SetWidth(300)
                if panel.ApplyControlTheme then
                    panel.ApplyControlTheme(control)
                end
            end
            if control and control.Dropdown and opts and opts.applyFontPreview and addon.InitFontDropdown then
                addon.InitFontDropdown(control.Dropdown, setting, optionsProvider)
            end
            frame.SelectionDropdown = dropdown
        end

        ensureDropdown()

        if not frame.ApplyButton then
            local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            btn:SetSize(200, 40)
            btn:SetPoint("TOP", frame.SelectionDropdown, "BOTTOM", 0, -40)
            btn:SetText(APPLY_BUTTON_LABEL)
            if btn.Text and btn.Text.SetFont then
                local face, size, flags = btn.Text:GetFont()
                if size then
                    btn.Text:SetFont(face, math.floor(size * 1.3 + 0.5), flags or "")
                end
            end
            btn:SetMotionScriptsWhileDisabled(true)
            btn:SetScript("OnClick", function()
                CloseDropDownMenus()
                triggerPopup()
            end)
            if panel.ApplyButtonTheme then
                panel.ApplyButtonTheme(btn)
            end
            frame.ApplyButton = btn
        else
            frame.ApplyButton:SetSize(200, 40)
            frame.ApplyButton:ClearAllPoints()
            frame.ApplyButton:SetPoint("TOP", frame.SelectionDropdown, "BOTTOM", 0, -40)
            if frame.ApplyButton.Text and frame.ApplyButton.Text.SetFont then
                local face, size, flags = frame.ApplyButton.Text:GetFont()
                if size then
            frame.ApplyButton.Text:SetFont(face, math.floor(size * 1.3 + 0.5), flags or "")
                end
            end
        end
    end
    return row
end

local function createRenderer(cfg)
    local function render()
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then
            return
        end
        if right.SetTitle then
            right:SetTitle(cfg.title or "Apply All")
        end

        local init = {}
        if cfg.disclaimer then
            table.insert(init, createInfoRow(cfg.disclaimer))
        end
        table.insert(init, createApplyRow(cfg.key, cfg.optionsProvider, cfg.getPending, cfg.setPending, cfg.popup, cfg))

        right:Display(init)
    end

    return { mode = "list", render = render, componentId = cfg.componentId or cfg.key }
end

function panel.RenderApplyAllFonts()
    ensureFontPopup()
    return createRenderer({
        key = "fonts",
        componentId = "applyAllFonts",
        title = "Apply All: Fonts",
        disclaimer = "Applying fonts overwrites every ScooterMod font face across all components and forces a /reload. Sizes, colors, offsets, and outline styles are not changed.",
        optionsProvider = function()
            return addon.BuildFontOptionsContainer and addon.BuildFontOptionsContainer() or {}
        end,
        getPending = function()
            return addon.ApplyAll and addon.ApplyAll:GetPendingFont() or "FRIZQT__"
        end,
        setPending = function(value)
            if addon.ApplyAll and addon.ApplyAll.SetPendingFont then
                addon.ApplyAll:SetPendingFont(value)
            end
        end,
        popup = function()
            ensureFontPopup()
            local pending = addon.ApplyAll and addon.ApplyAll:GetPendingFont()
            if not pending or pending == "" then
                addon:Print("Select a font before applying.")
                return
            end
            StaticPopup_Show("SCOOTERMOD_APPLYALL_FONTS", pending, nil, { fontKey = pending })
        end,
    })
end

function panel.RenderApplyAllTextures()
    ensureTexturePopup()
    return createRenderer({
        key = "textures",
        componentId = "applyAllTextures",
        title = "Apply All: Bar Textures",
        disclaimer = "Applying bar textures overwrites every ScooterMod bar foreground/background texture and forces a /reload. Tint, opacity, and color selections remain untouched.",
        optionsProvider = function()
            return addon.BuildBarTextureOptionsContainer and addon.BuildBarTextureOptionsContainer() or {}
        end,
        getPending = function()
            return addon.ApplyAll and addon.ApplyAll:GetPendingBarTexture() or "default"
        end,
        setPending = function(value)
            if addon.ApplyAll and addon.ApplyAll.SetPendingBarTexture then
                addon.ApplyAll:SetPendingBarTexture(value)
            end
        end,
        popup = function()
            ensureTexturePopup()
            local pending = addon.ApplyAll and addon.ApplyAll:GetPendingBarTexture()
            if not pending or pending == "" then
                addon:Print("Select a texture before applying.")
                return
            end
            local label = addon.Media and addon.Media.GetBarTextureDisplayName and addon.Media.GetBarTextureDisplayName(pending) or pending
            StaticPopup_Show("SCOOTERMOD_APPLYALL_TEXTURES", label or pending, nil, { textureKey = pending })
        end,
    })
end

