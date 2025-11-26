local addonName, addon = ...

local Component = addon.ComponentPrototype

-- Track state for font change detection
local sctDamageState = {
    initialLoadComplete = false,
    lastKnownFont = nil,
}

-- Register the static popup dialog for combat font restart warning
local function ensureCombatFontPopup()
    if _G.StaticPopupDialogs and not _G.StaticPopupDialogs["SCOOTERMOD_COMBAT_FONT_RESTART"] then
        _G.StaticPopupDialogs["SCOOTERMOD_COMBAT_FONT_RESTART"] = {
            text = "In order for Combat Font changes to take effect, you'll need to fully exit and re-open World of Warcraft.",
            button1 = OKAY or "Okay",
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
    end
end

local function clampPercent(value)
    local num = tonumber(value) or 100
    if num < 50 then
        num = 50
    elseif num > 150 then
        num = 150
    end
    return math.floor(num + 0.5)
end

local function applyWorldTextStyling(self)
    if not self or not self.db then
        return
    end

    local db = self.db
    local settings = self.settings or {}

    local fontKey = db.fontFace or (settings.fontFace and settings.fontFace.default) or "FRIZQT__"
    local resolve = addon.ResolveFontFace or function(_)
        return (select(1, _G.GameFontNormal:GetFont()))
    end
    local face = resolve(fontKey)
    if not face or face == "" then
        face = (select(1, _G.GameFontNormal:GetFont()))
    end

    -- Check if font changed from user interaction (not during init)
    if sctDamageState.initialLoadComplete then
        if sctDamageState.lastKnownFont and sctDamageState.lastKnownFont ~= fontKey then
            -- Font was changed by user, show the restart popup
            ensureCombatFontPopup()
            if _G.StaticPopup_Show then
                _G.StaticPopup_Show("SCOOTERMOD_COMBAT_FONT_RESTART")
            end
        end
    end
    sctDamageState.lastKnownFont = fontKey

    local scalePercent = clampPercent(db.fontScale or (settings.fontScale and settings.fontScale.default) or 100)
    db.fontScale = scalePercent
    db.fontStyle = nil

    if type(face) == "string" and face ~= "" then
        _G.DAMAGE_TEXT_FONT = face
    end
    if addon.LogWorldTextFont then
        addon.LogWorldTextFont("applyWorldTextStyling:start", {
            face = face,
            requestedScale = scalePercent,
        })
    end

    local targets = {
        _G.CombatTextFont,
        _G.CombatTextFontOutline,
    }
    local touched = {}
    for _, fontObj in ipairs(targets) do
        if type(fontObj) == "table" and fontObj.GetFont and fontObj.SetFont and not touched[fontObj] then
            touched[fontObj] = true
            local ok, _, size, existingFlags = pcall(fontObj.GetFont, fontObj)
            if not ok then
                size = nil
                existingFlags = nil
            end
            size = tonumber(size) or 24
            pcall(fontObj.SetFont, fontObj, face, size, existingFlags)
            if addon.LogWorldTextFont then
                addon.LogWorldTextFont("applyWorldTextStyling:SetFont", {
                    target = fontObj.GetName and fontObj:GetName() or tostring(fontObj),
                    size = size,
                    flags = existingFlags,
                    face = face,
                })
            end
        end
    end

    local scalar = scalePercent / 100
    local scaledValue = string.format("%.2f", scalar)
    if _G.C_CVar and _G.C_CVar.SetCVar then
        _G.C_CVar.SetCVar("WorldTextScale", scaledValue)
    elseif _G.SetCVar then
        pcall(_G.SetCVar, "WorldTextScale", scaledValue)
    end
    if addon.LogWorldTextFont then
        addon.LogWorldTextFont("applyWorldTextStyling:WorldTextScale", { scale = scaledValue })
    end

    -- Mark initial load as complete after first styling pass
    if not sctDamageState.initialLoadComplete then
        sctDamageState.initialLoadComplete = true
    end
end

addon:RegisterComponentInitializer(function(self)
    local sctDamage = Component:New({
        id = "sctDamage",
        name = "Damage Numbers",
        frameName = nil,
        applyDuringInit = true,
        settings = {
            fontFace = { type = "addon", default = "FRIZQT__", ui = {
                label = "Font",
                widget = "dropdown",
                section = "Font",
                order = 1,
                optionsProvider = function()
                    if addon.BuildFontOptionsContainer then
                        return addon.BuildFontOptionsContainer()
                    end
                    return {}
                end,
            }},
            fontScale = { type = "addon", default = 100, ui = {
                label = "Font Scale",
                widget = "slider",
                min = 50,
                max = 150,
                step = 1,
                section = "Font",
                order = 2,
                format = "percent",
            }},
        },
        ApplyStyling = applyWorldTextStyling,
    })

    self:RegisterComponent(sctDamage)
end)


