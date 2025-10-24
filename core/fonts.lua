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
    local function Inserter(rootDescription, isSelected, setSelected)
        local optionData = type(optionsProvider) == 'function' and optionsProvider() or optionsProvider
        for _, option in ipairs(optionData) do
            local optionDescription = rootDescription:CreateTemplate("SettingsDropdownButtonTemplate")
            _G.Settings.CreateDropdownButton(optionDescription, option, isSelected, setSelected)
            optionDescription:AddInitializer(function(button)
                local value = option.value
                local face = addon.ResolveFontFace(value)
                if face and button and button.Text and button.Text.GetFont then
                    local _, sz, flags = button.Text:GetFont()
                    button.Text:SetFont(face, sz or 12, flags or "")
                end
            end)
        end
    end
    local initTooltip = _G.Settings.CreateOptionsInitTooltip(setting, setting and setting:GetName() or "Font", nil, optionsProvider)
    _G.Settings.InitDropdown(dropdown, setting, Inserter, initTooltip)
    -- Force a deferred redraw to ensure all option initializers have run before first open
    if dropdown and dropdown.Update then
        C_Timer.After(0, function()
            if dropdown and dropdown.Update then pcall(dropdown.Update, dropdown) end
        end)
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


