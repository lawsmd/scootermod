local addonName, addon = ...

addon.Fonts = addon.Fonts or {}

-- Build a container compatible with Settings dropdown options for font faces.
-- This mirrors RIP's behavior but keeps ScooterMod self-contained. We rely on
-- stock fonts available in all clients and allow future extension via media.
function addon.BuildFontOptionsContainer()
    local create = _G.Settings and _G.Settings.CreateControlTextContainer
    local add = function(container, key, text)
        if container._seen and container._seen[key] then return end
        if create then
            container:Add(key, text)
        else
            table.insert(container, { value = key, text = text })
        end
        if container._seen then container._seen[key] = true end
    end
    local container = create and create() or {}
    container._seen = {}
    -- Always include FRIZQT__ first (stock default)
    add(container, "FRIZQT__", "FRIZQT__")
    -- Add a small curated set of common fonts present in retail
    add(container, "ARIALN", "ARIALN")
    add(container, "MORPHEUS", "MORPHEUS")
    add(container, "SKURRI", "SKURRI")
    -- Allow extension: any fonts registered in addon.Fonts map
    local keys = {}
    for k,_ in pairs(addon.Fonts or {}) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do add(container, k, k) end
    container._seen = nil
    return create and container:GetData() or container
end

-- Resolve a font face name to an actual file path for SetFont.
-- Falls back to the face of GameFontNormal if unknown.
function addon.ResolveFontFace(key)
    local face = (addon.Fonts and addon.Fonts[key or "FRIZQT__"]) or (select(1, _G.GameFontNormal:GetFont()))
    return face
end

-- Apply font preview to a Settings dropdown by rendering each option in its font
function addon.InitFontDropdown(dropdown, setting, optionsProvider)
    if not dropdown or dropdown._ScooterFontPreviewInit then return end
    -- Prefer building the menu at open-time to ensure initializers run on first open after game launch.
    if dropdown.SetupMenu then
        dropdown:SetupMenu(function(menu, root)
            local optionData = type(optionsProvider) == 'function' and optionsProvider() or optionsProvider
            for _, option in ipairs(optionData) do
                local optionDescription = root:CreateTemplate("SettingsDropdownButtonTemplate")
                _G.Settings.CreateDropdownButton(optionDescription, option,
                    function()
                        return setting and setting.GetValue and (setting:GetValue() == option.value)
                    end,
                    function()
                        if setting and setting.SetValue then setting:SetValue(option.value) end
                    end
                )
                optionDescription:AddInitializer(function(button)
                    local function applyFont()
                        local value = option.value
                        local face = addon.ResolveFontFace(value)
                        if face and button and button.Text and button.Text.GetFont then
                            local _, sz = button.Text:GetFont()
                            button.Text:SetFont(face, sz or 12, "")
                            if button.Text.SetTextColor then button.Text:SetTextColor(1, 1, 1, 1) end
                            if button.Text.SetShadowOffset then button.Text:SetShadowOffset(0, 0) end
                            if button.Text.SetShadowColor then button.Text:SetShadowColor(0, 0, 0, 0) end
                        end
                    end
                    applyFont()
                    if button and button.HookScript then
                        button:HookScript("OnShow", function() applyFont() end)
                    end
                    C_Timer.After(0, applyFont)
                    C_Timer.After(0.05, applyFont)
                end)
            end
        end)
    else
        -- Fallback for environments without SetupMenu
        local function Inserter(rootDescription, isSelected, setSelected)
            local optionData = type(optionsProvider) == 'function' and optionsProvider() or optionsProvider
            for _, option in ipairs(optionData) do
                local optionDescription = rootDescription:CreateTemplate("SettingsDropdownButtonTemplate")
                _G.Settings.CreateDropdownButton(optionDescription, option, isSelected, setSelected)
                optionDescription:AddInitializer(function(button)
                    local function applyFont()
                        local value = option.value
                        local face = addon.ResolveFontFace(value)
                        if face and button and button.Text and button.Text.GetFont then
                            local _, sz = button.Text:GetFont()
                            button.Text:SetFont(face, sz or 12, "")
                            if button.Text.SetTextColor then button.Text:SetTextColor(1, 1, 1, 1) end
                            if button.Text.SetShadowOffset then button.Text:SetShadowOffset(0, 0) end
                            if button.Text.SetShadowColor then button.Text:SetShadowColor(0, 0, 0, 0) end
                        end
                    end
                    applyFont()
                    if button and button.HookScript then
                        button:HookScript("OnShow", function() applyFont() end)
                    end
                    C_Timer.After(0, applyFont)
                    C_Timer.After(0.05, applyFont)
                end)
            end
        end
        local initTooltip = _G.Settings.CreateOptionsInitTooltip(setting, setting and setting:GetName() or "Font", nil, optionsProvider)
        _G.Settings.InitDropdown(dropdown, setting, Inserter, initTooltip)
        if dropdown and dropdown.Update then
            C_Timer.After(0, function()
                if dropdown and dropdown.Update then pcall(dropdown.Update, dropdown) end
            end)
        end
    end
    dropdown._ScooterFontPreviewInit = true
end

-- Register stock faces and bundled Roboto variants (paths are relative to the WoW root)
do
    local f = addon.Fonts
    -- Blizzard stock font aliases
    f.FRIZQT__ = "Fonts\\FRIZQT__.TTF"
    f.ARIALN   = "Fonts\\ARIALN.TTF"
    f.MORPHEUS = "Fonts\\MORPHEUS.TTF"
    f.SKURRI   = "Fonts\\SKURRI.TTF"
    -- Bundled Roboto (copied into ScooterMod/media/fonts)
    local base = "Interface\\AddOns\\ScooterMod\\media\\fonts\\"
    f.ROBOTO_REG   = base .. "Roboto-Regular.ttf"
    f.ROBOTO_MED   = base .. "Roboto-Medium.ttf"
    f.ROBOTO_BLD   = base .. "Roboto-Bold.ttf"
    f.ROBOTO_ITA   = base .. "Roboto-Italic.ttf"
    f.ROBOTO_LGT   = base .. "Roboto-Light.ttf"
    f.ROBOTO_LITA  = base .. "Roboto-LightItalic.ttf"
    f.ROBOTO_MITA  = base .. "Roboto-MediumItalic.ttf"
    f.ROBOTO_BITA  = base .. "Roboto-BoldItalic.ttf"
    f.ROBOTO_THIN  = base .. "Roboto-Thin.ttf"
    f.ROBOTO_TITA  = base .. "Roboto-ThinItalic.ttf"
    -- (Removed) Roboto Condensed variants to keep the list concise
end


-- Preload font faces once to ensure consistent first-use rendering after game launch.
-- This avoids cases where certain Roboto variants appear unstyled until a second open.
function addon.PreloadFonts()
    if addon._fontsPreloaded then return end
    addon._fontsPreloaded = true
    local holder = CreateFrame("Frame")
    holder:Hide()
    local fs = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local size = 14
    local warmup = "The quick brown fox jumps over the lazy dog 0123456789 !@#%^&*()[]{}"
    for _, path in pairs(addon.Fonts or {}) do
        if type(path) == "string" and path ~= "" then
            pcall(fs.SetFont, fs, path, size, "")
            fs:SetText(warmup)
            pcall(fs.GetStringWidth, fs)
            fs:SetText("")
        end
    end
end



