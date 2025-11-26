local addonName, addon = ...

local Component = addon.ComponentPrototype

local function clampPercent(value)
    local num = tonumber(value) or 100
    if num < 50 then
        num = 50
    elseif num > 150 then
        num = 150
    end
    return math.floor(num + 0.5)
end

local function buildFontStyleOptions()
    local Settings = _G.Settings
    if Settings and Settings.CreateControlTextContainer then
        local container = Settings.CreateControlTextContainer()
        container:Add("NONE", "Regular")
        container:Add("OUTLINE", "Outline")
        container:Add("THICKOUTLINE", "Thick Outline")
        return container:GetData()
    end
    return {
        { value = "NONE", text = "Regular" },
        { value = "OUTLINE", text = "Outline" },
        { value = "THICKOUTLINE", text = "Thick Outline" },
    }
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

    local style = db.fontStyle or (settings.fontStyle and settings.fontStyle.default) or "OUTLINE"
    if style == "NONE" or style == "Regular" then
        style = ""
    end

    local scalePercent = clampPercent(db.fontScale or (settings.fontScale and settings.fontScale.default) or 100)
    db.fontScale = scalePercent

    if type(face) == "string" and face ~= "" then
        _G.DAMAGE_TEXT_FONT = face
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
            local flags = style ~= "" and style or (existingFlags or "")
            pcall(fontObj.SetFont, fontObj, face, size, flags)
        end
    end

    local scalar = scalePercent / 100
    local scaledValue = string.format("%.2f", scalar)
    if _G.C_CVar and _G.C_CVar.SetCVar then
        _G.C_CVar.SetCVar("WorldTextScale", scaledValue)
    elseif _G.SetCVar then
        pcall(_G.SetCVar, "WorldTextScale", scaledValue)
    end
end

addon:RegisterComponentInitializer(function(self)
    local sctDamage = Component:New({
        id = "sctDamage",
        name = "Damage Numbers",
        frameName = nil,
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
            fontStyle = { type = "addon", default = "OUTLINE", ui = {
                label = "Font Style",
                widget = "dropdown",
                section = "Font",
                order = 2,
                optionsProvider = buildFontStyleOptions,
            }},
            fontScale = { type = "addon", default = 100, ui = {
                label = "Font Scale",
                widget = "slider",
                min = 50,
                max = 150,
                step = 1,
                section = "Font",
                order = 3,
                format = "percent",
            }},
        },
        ApplyStyling = applyWorldTextStyling,
    })

    self:RegisterComponent(sctDamage)
end)


