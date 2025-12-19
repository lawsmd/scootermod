local addonName, addon = ...

addon.Presets = addon.Presets or {}
local Presets = addon.Presets

local registry = {}
local order = {}

local function deepCopy(tbl)
    if not tbl then return nil end
    return CopyTable(tbl)
end

local function normalizeId(id)
    if type(id) ~= "string" then return nil end
    id = id:lower():gsub("%s+", "_")
    return id
end

function Presets:Register(data)
    if type(data) ~= "table" then
        error("Preset data must be a table", 2)
    end
    local id = normalizeId(data.id or data.name)
    if not id or id == "" then
        error("Preset requires an id or name", 2)
    end
    if registry[id] then
        error("Preset '" .. id .. "' already registered", 2)
    end

    local entry = deepCopy(data)
    entry.id = id
    entry.name = data.name or id
    entry.version = data.version or "PENDING"
    entry.wowBuild = tostring(data.wowBuild or "")
    entry.description = data.description or ""
    entry.previewTexture = data.previewTexture or "Interface\\AddOns\\ScooterMod\\Scooter"
    entry.previewThumbnail = data.previewThumbnail or entry.previewTexture
    entry.tags = data.tags or {}
    entry.comingSoon = not not data.comingSoon
    entry.requiresConsolePort = not not data.requiresConsolePort
    entry.recommendedInput = data.recommendedInput or (entry.requiresConsolePort and "ConsolePort" or "Mouse + Keyboard")
    entry.screenClass = data.screenClass or "desktop"
    entry.lastUpdated = data.lastUpdated or date("%Y-%m-%d")
    entry.editModeExport = data.editModeExport
    entry.editModeSha256 = data.editModeSha256
    entry.sourceLayoutName = data.sourceLayoutName
    entry.scooterProfile = data.scooterProfile
    entry.profileSha256 = data.profileSha256
    entry.consolePortProfile = data.consolePortProfile
    entry.consolePortSha256 = data.consolePortSha256
    entry.notes = data.notes
    entry.designedFor = data.designedFor or {}
    entry.recommends = data.recommends or {}

    registry[id] = entry
    table.insert(order, id)
    -- Preserve registration order (ScooterUI first, then ScooterDeck)
end

function Presets:GetList()
    local list = {}
    for _, id in ipairs(order) do
        list[#list + 1] = registry[id]
    end
    return list
end

function Presets:GetPreset(id)
    if not id then return nil end
    return registry[normalizeId(id)] or registry[id]
end

function Presets:HasConsolePort()
    return _G.ConsolePort ~= nil
end

function Presets:CheckDependencies(preset)
    if not preset then
        return false, "Preset not found."
    end
    if preset.requiresConsolePort and not self:HasConsolePort() then
        return false, "ConsolePort must be installed to import this preset."
    end
    return true
end

function Presets:IsPayloadReady(preset)
    if not preset then return false end
    if not preset.scooterProfile then
        return false
    end
    local hasEditMode = (type(preset.editModeLayout) == "table")
        or (type(preset.sourceLayoutName) == "string" and preset.sourceLayoutName ~= "")
    if not hasEditMode then
        return false
    end
    return true
end

function Presets:ApplyPreset(id, opts)
    local preset = self:GetPreset(id)
    if not preset then
        return false, "Preset not found."
    end
    local ok, depErr = self:CheckDependencies(preset)
    if not ok then
        return false, depErr
    end
    if not self:IsPayloadReady(preset) then
        return false, "Preset payload has not shipped yet."
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, "Cannot import presets during combat."
    end
    if not addon.EditMode or not addon.EditMode.ImportPresetLayout then
        return false, "Preset import helper is not available."
    end
    return addon.EditMode:ImportPresetLayout(preset, opts or {})
end

function Presets:GetDefaultPresetId()
    return order[1]
end

-- -------------------------------------------------------------------------
-- Built-in registry entries (payloads pending)
-- -------------------------------------------------------------------------

Presets:Register({
    id = "ScooterUI",
    name = "ScooterUI",
    description = "Author's flagship desktop layout showcasing ScooterMod styling for raiding and Mythic+.",
    wowBuild = "11.2.5",
    version = "2025.12.19",
    screenClass = "desktop",
    recommendedInput = "Mouse + Keyboard",
    tags = { "Desktop", "Mythic+", "Raiding" },
    previewTexture = "Interface\\AddOns\\ScooterMod\\Scooter",
    previewThumbnail = "Interface\\AddOns\\ScooterMod\\Scooter",
    designedFor = { "Optimized for 4k 16:9 monitors", "Competitive PvE content, M+ and Raid" },
    recommends = { "Chattynator", "Platynator" },
    lastUpdated = "2025-12-19",

    -- Edit Mode layout payload (raw layoutInfo table).
    -- Capture/update via: /scoot debug editmode export "ScooterUI"
    -- NOTE: We intentionally do NOT ship the Blizzard Share string because there is no import API.
    editModeLayout = nil,
    editModeSha256 = "",

    -- ScooterMod profile snapshot (captured from authoring machine).
    profileSha256 = "2e6b9a4d9aa9cb1f4de7c523451f181235b6f1cd77fe9a22af32c32ac43d74dc",
    scooterProfile = {
        ["groupFrames"] = {
            ["raid"] = {
                ["textPlayerName"] = {
                    ["offset"] = {
                        ["y"] = 0,
                        ["x"] = 0,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_REG",
                    ["style"] = "OUTLINE",
                    ["color"] = {
                        1,
                        1,
                        1,
                        1,
                    },
                    ["size"] = 8,
                },
                ["healthBarBackgroundTexture"] = "a3",
                ["healthBarTexture"] = "a3",
            },
        },
        ["rules"] = {
            {
                ["enabled"] = true,
                ["action"] = {
                    ["value"] = true,
                },
                ["displayIndex"] = 1,
                ["trigger"] = {
                    ["specIds"] = {
                        63,
                    },
                    ["type"] = "specialization",
                },
                ["id"] = "rule-0001",
            },
            {
                ["enabled"] = true,
                ["action"] = {
                    ["value"] = true,
                    ["id"] = "ufTargetFocus.levelTextHidden",
                },
                ["displayIndex"] = 2,
                ["trigger"] = {
                    ["level"] = 80,
                    ["type"] = "playerLevel",
                },
                ["id"] = "rule-0003",
            },
            {
                ["enabled"] = true,
                ["action"] = {
                    ["value"] = true,
                    ["id"] = "ufPlayerClassResource.hide",
                },
                ["displayIndex"] = 3,
                ["trigger"] = {
                    ["specIds"] = {
                        262,
                        263,
                        264,
                    },
                    ["type"] = "specialization",
                },
                ["id"] = "rule-0004",
            },
        },
        ["applyAll"] = {
            ["fontPending"] = "default",
            ["lastFontApplied"] = {
                ["value"] = "ROBOTO_SEMICOND_BLACK",
                ["changed"] = 102,
                ["timestamp"] = 1764607972,
            },
        },
        ["rulesState"] = {
            ["nextId"] = 5,
        },
        ["ruleBaselines"] = {
            ["ufTargetFocus.levelTextHidden"] = true,
            ["ufPlayerClassResource.hide"] = false,
            ["prdPower.hideBar"] = false,
        },
        ["unitFrames"] = {
            ["Player"] = {
                ["scaleMult"] = 1,
                ["portrait"] = {
                    ["hidePortrait"] = true,
                    ["damageTextDisabled"] = true,
                    ["damageText"] = {
                        ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    },
                },
                ["healthBarBorderTintEnable"] = true,
                ["castBar"] = {
                    ["castBarBackgroundTexture"] = "a1",
                    ["castTimeText"] = {
                        ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    },
                    ["castBarBorderThickness"] = 2,
                    ["castBarBorderEnable"] = true,
                    ["castBarColorMode"] = "class",
                    ["widthPct"] = 100,
                    ["castBarSparkHidden"] = true,
                    ["hideTextBorder"] = true,
                    ["hideChannelingShadow"] = true,
                    ["castBarBackgroundOpacity"] = 70,
                    ["spellNameText"] = {
                        ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                        ["style"] = "SHADOWTHICKOUTLINE",
                        ["size"] = 12,
                    },
                    ["castBarTexture"] = "a1",
                },
                ["textLevel"] = {
                    ["offset"] = {
                        ["y"] = 1,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        1,
                        1,
                        1,
                    },
                    ["colorMode"] = "custom",
                    ["size"] = 10,
                },
                ["classResource"] = {
                    ["hide"] = true,
                    ["offsetX"] = 0,
                    ["classResourcePosX"] = 0,
                    ["scale"] = 50,
                    ["offsetY"] = 0,
                    ["classResourceCustomPositionEnabled"] = true,
                    ["classResourcePosY"] = -145,
                },
                ["useCustomBorders"] = true,
                ["powerBarHidden"] = false,
                ["powerBarBorderThickness"] = 1,
                ["opacityOutOfCombat"] = 25,
                ["healthBarBorderThickness"] = 1,
                ["altPowerBar"] = {
                    ["textPercent"] = {
                        ["offset"] = {
                            ["x"] = 0,
                        },
                        ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                        ["alignment"] = "CENTER",
                        ["style"] = "SHADOWOUTLINE",
                        ["size"] = 6,
                    },
                    ["borderThickness"] = 1,
                    ["widthPct"] = 50,
                    ["offsetX"] = 32,
                    ["valueHidden"] = true,
                    ["textValue"] = {
                        ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                        ["style"] = "SHADOWOUTLINE",
                        ["size"] = 6,
                    },
                    ["offsetY"] = 8,
                    ["backgroundTexture"] = "a1",
                    ["texture"] = "a1",
                },
                ["healthBarBackgroundTexture"] = "a2",
                ["healthBarTexture"] = "a2",
                ["powerBarHideSpark"] = true,
                ["powerBarWidthPct"] = 80,
                ["powerBarTexture"] = "a1",
                ["powerBarCustomPositionEnabled"] = true,
                ["textPowerValue"] = {
                    ["alignment"] = "CENTER",
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["size"] = 8,
                },
                ["healthBarHideBorder"] = false,
                ["powerBarBackgroundTexture"] = "a1",
                ["powerBarOffsetY"] = 0,
                ["powerBarHeightPct"] = 100,
                ["levelTextHidden"] = true,
                ["powerBarHideFullSpikes"] = true,
                ["textName"] = {
                    ["offset"] = {
                        ["y"] = 2,
                        ["x"] = -2,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["colorMode"] = "class",
                    ["size"] = 12,
                },
                ["healthBarColorMode"] = "default",
                ["powerBarPosY"] = -65,
                ["healthBarBorderTintColor"] = {
                    0,
                    0,
                    0,
                    1,
                },
                ["healthBarBorderStyle"] = "square",
                ["textHealthValue"] = {
                    ["offset"] = {
                        ["x"] = 5,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["alignment"] = "LEFT",
                    ["color"] = {
                        1,
                        1,
                        1,
                        0.8116318583488464,
                    },
                    ["style"] = "SHADOWTHICKOUTLINE",
                    ["size"] = 8,
                },
                ["healthBarHideOverAbsorbGlow"] = true,
                ["textHealthPercent"] = {
                    ["offset"] = {
                        ["x"] = -3,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        1,
                        1,
                        0.8203125,
                    },
                    ["alignment"] = "RIGHT",
                    ["size"] = 8,
                },
                ["powerBarOffsetX"] = 10,
                ["powerPercentHidden"] = true,
                ["powerBarPosX"] = 0,
                ["misc"] = {
                    ["hideGroupNumber"] = true,
                    ["hideRoleIcon"] = true,
                },
                ["textPowerPercent"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
            },
            ["Focus"] = {
                ["scaleMult"] = 1.200000047683716,
                ["portrait"] = {
                    ["hidePortrait"] = true,
                },
                ["textPowerValue"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["castBar"] = {
                    ["iconBorderThickness"] = 1,
                    ["castBarBackgroundTexture"] = "a1",
                    ["spellNameText"] = {
                        ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                        ["style"] = "SHADOWOUTLINE",
                        ["size"] = 6,
                    },
                    ["anchorMode"] = "healthBottom",
                    ["castBarBorderEnable"] = true,
                    ["castBarSparkHidden"] = true,
                    ["iconBarPadding"] = 2,
                    ["castBarBorderInset"] = 0,
                    ["iconBorderEnable"] = true,
                    ["iconDisabled"] = true,
                    ["iconWidth"] = 21,
                    ["castBarBorderThickness"] = 1,
                    ["widthPct"] = 55,
                    ["castTimeText"] = {
                        ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    },
                    ["offsetY"] = -5,
                    ["iconHeight"] = 12,
                    ["hideSpellNameBorder"] = true,
                    ["castBarBackgroundOpacity"] = 60,
                    ["castBarTexture"] = "a1",
                    ["castBarScale"] = 125,
                },
                ["textLevel"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        1,
                        1,
                        1,
                    },
                    ["colorMode"] = "custom",
                    ["size"] = 10,
                },
                ["textHealthPercent"] = {
                    ["offset"] = {
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        1,
                        1,
                        0.8203125,
                    },
                    ["alignment"] = "LEFT",
                    ["size"] = 8,
                },
                ["buffsDebuffs"] = {
                    ["borderEnable"] = true,
                    ["borderThickness"] = 2,
                    ["iconScale"] = 50,
                    ["iconHeight"] = 24,
                    ["iconWidth"] = 32,
                    ["hideBuffsDebuffs"] = true,
                },
                ["useCustomBorders"] = true,
                ["textName"] = {
                    ["offset"] = {
                        ["y"] = 0,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["alignment"] = "RIGHT",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["colorMode"] = "default",
                    ["containerWidthPct"] = 100,
                    ["size"] = 10,
                },
                ["misc"] = {
                },
                ["powerBarHidden"] = true,
                ["healthBarBorderThickness"] = 1,
                ["levelTextHidden"] = true,
                ["healthBarBackgroundTexture"] = "a1",
                ["textHealthValue"] = {
                    ["offset"] = {
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["alignment"] = "RIGHT",
                    ["color"] = {
                        1,
                        1,
                        1,
                        0.8116318583488464,
                    },
                    ["style"] = "SHADOWTHICKOUTLINE",
                    ["size"] = 8,
                },
                ["healthBarBorderStyle"] = "square",
                ["healthBarTexture"] = "a1",
                ["textPowerPercent"] = {
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
            },
            ["Target"] = {
                ["scaleMult"] = 1,
                ["portrait"] = {
                    ["hidePortrait"] = true,
                },
                ["textPowerValue"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["castBar"] = {
                    ["iconBorderThickness"] = 1,
                    ["castBarBackgroundTexture"] = "a1",
                    ["spellNameText"] = {
                        ["offset"] = {
                            ["y"] = 0,
                        },
                        ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                        ["style"] = "SHADOWOUTLINE",
                        ["size"] = 8,
                    },
                    ["anchorMode"] = "healthBottom",
                    ["castBarTexture"] = "a1",
                    ["castBarSparkHidden"] = true,
                    ["offsetX"] = 0,
                    ["iconBarPadding"] = 2,
                    ["castBarBorderInset"] = 1,
                    ["iconBorderEnable"] = true,
                    ["iconDisabled"] = true,
                    ["iconWidth"] = 21,
                    ["castBarBorderThickness"] = 1,
                    ["widthPct"] = 70,
                    ["castBarScale"] = 90,
                    ["iconHeight"] = 12,
                    ["castBarBackgroundOpacity"] = 60,
                    ["hideSpellNameBorder"] = true,
                    ["offsetY"] = -5,
                    ["castBarBorderEnable"] = true,
                },
                ["textLevel"] = {
                    ["offset"] = {
                        ["y"] = 1,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        1,
                        1,
                        1,
                    },
                    ["colorMode"] = "custom",
                    ["size"] = 10,
                },
                ["textHealthPercent"] = {
                    ["offset"] = {
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        1,
                        1,
                        0.8203125,
                    },
                    ["alignment"] = "LEFT",
                    ["size"] = 8,
                },
                ["buffsDebuffs"] = {
                    ["borderEnable"] = true,
                    ["borderThickness"] = 2,
                    ["iconScale"] = 50,
                    ["iconWidth"] = 32,
                    ["iconHeight"] = 21.00000381469727,
                    ["hideBuffsDebuffs"] = false,
                },
                ["healthBarReverseFill"] = true,
                ["useCustomBorders"] = true,
                ["textName"] = {
                    ["offset"] = {
                        ["y"] = 0,
                        ["x"] = 3,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["alignment"] = "RIGHT",
                    ["color"] = {
                        1,
                        1,
                        1,
                        1,
                    },
                    ["colorMode"] = "custom",
                    ["containerWidthPct"] = 100,
                    ["size"] = 10,
                },
                ["healthBarColorMode"] = "default",
                ["misc"] = {
                    ["hideThreatMeter"] = true,
                },
                ["powerBarHidden"] = true,
                ["healthBarBorderThickness"] = 1,
                ["textHealthValue"] = {
                    ["offset"] = {
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["alignment"] = "RIGHT",
                    ["color"] = {
                        1,
                        1,
                        1,
                        0.8116318583488464,
                    },
                    ["style"] = "SHADOWTHICKOUTLINE",
                    ["size"] = 8,
                },
                ["healthBarBackgroundTexture"] = "a2",
                ["levelTextHidden"] = true,
                ["healthBarBorderStyle"] = "square",
                ["healthBarTexture"] = "a2",
                ["textPowerPercent"] = {
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
            },
            ["Pet"] = {
                ["healthValueHidden"] = true,
                ["scaleMult"] = 1.200000047683716,
                ["portrait"] = {
                    ["hidePortrait"] = true,
                    ["damageTextDisabled"] = true,
                },
                ["textPowerValue"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textLevel"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["levelTextHidden"] = true,
                ["useCustomBorders"] = true,
                ["powerBarHidden"] = true,
                ["textHealthPercent"] = {
                    ["offset"] = {
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        1,
                        1,
                        0.8203125,
                    },
                    ["alignment"] = "RIGHT",
                    ["size"] = 6,
                },
                ["opacityOutOfCombat"] = 25,
                ["healthBarBorderThickness"] = 1,
                ["textName"] = {
                    ["offset"] = {
                        ["y"] = 0,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["colorMode"] = "default",
                    ["size"] = 8,
                },
                ["healthBarBackgroundTexture"] = "a1",
                ["textHealthValue"] = {
                    ["offset"] = {
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["alignment"] = "LEFT",
                    ["color"] = {
                        1,
                        1,
                        1,
                        0.8116318583488464,
                    },
                    ["style"] = "SHADOWTHICKOUTLINE",
                },
                ["healthBarBorderStyle"] = "square",
                ["healthBarTexture"] = "a1",
                ["textPowerPercent"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["size"] = 8,
                },
            },
            ["TargetOfTarget"] = {
                ["powerBarHidden"] = true,
                ["portrait"] = {
                    ["hidePortrait"] = true,
                },
                ["scale"] = 0.6000000238418579,
                ["textName"] = {
                    ["style"] = "SHADOWOUTLINE",
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["alignment"] = "CENTER",
                    ["size"] = 10,
                },
                ["healthBarBorderThickness"] = 1,
                ["offsetX"] = -35,
                ["healthBarBackgroundTexture"] = "a2",
                ["healthBarBorderStyle"] = "default",
                ["offsetY"] = 50,
                ["healthBarTexture"] = "a2",
                ["useCustomBorders"] = true,
            },
        },
        ["components"] = {
            ["nameplatesUnit"] = {
                ["_nameplatesColorMigrated"] = true,
                ["textName"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "THICKOUTLINE",
                    ["size"] = 8,
                },
                ["_nameplatesTextMigrated"] = true,
            },
            ["actionBar7"] = {
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["positionY"] = 150,
                ["textStacks"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textHotkey"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textMacro"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
            },
            ["actionBar1"] = {
                ["borderThickness"] = 2,
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["positionY"] = -575,
                ["borderEnable"] = true,
                ["barOpacityWithTarget"] = 10,
                ["barOpacityOutOfCombat"] = 10,
                ["textMacro"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["hideBarArt"] = true,
                ["iconSize"] = 50,
                ["columns"] = 2,
                ["textStacks"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["hideBarScrolling"] = true,
                ["barOpacity"] = 10,
                ["mouseoverMode"] = true,
                ["textHotkey"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
            },
            ["actionBar4"] = {
                ["borderThickness"] = 2,
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["positionY"] = -575,
                ["borderEnable"] = true,
                ["barOpacityWithTarget"] = 10,
                ["positionX"] = -150,
                ["textMacro"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["iconSize"] = 50,
                ["columns"] = 2,
                ["textStacks"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["barOpacity"] = 10,
                ["mouseoverMode"] = true,
                ["orientation"] = "H",
                ["textHotkey"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["barOpacityOutOfCombat"] = 10,
            },
            ["actionBar6"] = {
                ["borderThickness"] = 2,
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["positionY"] = -525,
                ["mouseoverMode"] = true,
                ["positionX"] = 328,
                ["textMacro"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["iconSize"] = 50,
                ["columns"] = 2,
                ["textStacks"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["textHotkey"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["borderEnable"] = true,
                ["barOpacityOutOfCombat"] = 10,
            },
            ["actionBar5"] = {
                ["borderThickness"] = 2,
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["positionY"] = -575,
                ["borderEnable"] = true,
                ["barOpacityWithTarget"] = 10,
                ["positionX"] = -300,
                ["textMacro"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["iconSize"] = 50,
                ["columns"] = 2,
                ["textStacks"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["barOpacity"] = 10,
                ["mouseoverMode"] = true,
                ["orientation"] = "H",
                ["textHotkey"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["barOpacityOutOfCombat"] = 10,
            },
            ["trackedBars"] = {
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["positionY"] = -140,
                ["iconBarPadding"] = 5,
                ["borderEnable"] = true,
                ["iconWidth"] = 32,
                ["iconPadding"] = 2,
                ["textDuration"] = {
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["iconHeight"] = 20,
                ["styleBackgroundTexture"] = "a1",
                ["textStacks"] = {
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["displayMode"] = "name",
                ["iconBorderEnable"] = true,
                ["textName"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["size"] = 12,
                },
                ["textCharges"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["iconBorderThickness"] = 2,
                ["borderThickness"] = 2,
                ["styleForegroundTexture"] = "a1",
                ["hideWhenInactive"] = true,
                ["barWidth"] = 170,
            },
            ["petBar"] = {
                ["textMacro"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["borderThickness"] = 3,
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["positionY"] = -398,
                ["iconSize"] = 50,
                ["mouseoverMode"] = true,
                ["columns"] = 2,
                ["textHotkey"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["borderEnable"] = true,
                ["barOpacityWithTarget"] = 10,
                ["positionX"] = -444,
                ["textStacks"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["barOpacityOutOfCombat"] = 10,
            },
            ["essentialCooldowns"] = {
                ["borderThickness"] = 3,
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["size"] = 24,
                },
                ["positionY"] = -242,
                ["iconSize"] = 80,
                ["borderEnable"] = true,
                ["textName"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["iconWidth"] = 48,
                ["iconPadding"] = 6,
                ["textCharges"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["opacityOutOfCombat"] = 25,
                ["iconHeight"] = 32,
                ["textStacks"] = {
                    ["offset"] = {
                        ["y"] = 28,
                        ["x"] = 12,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        0,
                        0,
                        1,
                    },
                    ["size"] = 20,
                },
                ["textDuration"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
            },
            ["tooltip"] = {
                ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                ["textLine2"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textLine6"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textLine3"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textTitle"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "THICKOUTLINE",
                    ["size"] = 20,
                },
                ["textEverythingElse"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textLine7"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textComparison"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["hideHealthBar"] = true,
                ["textLine4"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textLine5"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
            },
            ["debuffs"] = {
                ["direction"] = "right",
                ["positionY"] = 363,
                ["iconSize"] = 120,
                ["textCount"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["iconWidth"] = 35,
                ["iconPadding"] = 15,
                ["textDuration"] = {
                    ["color"] = {
                        1,
                        0.8235294818878174,
                        0,
                        1,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["offset"] = {
                    },
                },
                ["positionX"] = 457,
                ["iconHeight"] = 24,
                ["textStacks"] = {
                    ["offset"] = {
                    },
                    ["color"] = {
                        1,
                        1,
                        1,
                        1,
                    },
                },
            },
            ["actionBar2"] = {
                ["borderThickness"] = 2,
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["positionY"] = -575,
                ["borderEnable"] = true,
                ["barOpacityWithTarget"] = 10,
                ["positionX"] = 150,
                ["textMacro"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["iconSize"] = 50,
                ["mouseoverMode"] = true,
                ["columns"] = 2,
                ["textStacks"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["barOpacity"] = 10,
                ["textHotkey"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["barOpacityOutOfCombat"] = 10,
            },
            ["trackedBuffs"] = {
                ["direction"] = "down",
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["size"] = 18,
                },
                ["positionY"] = -121,
                ["iconSize"] = 80,
                ["textStacks"] = {
                    ["color"] = {
                        1,
                        0,
                        0,
                        1,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["offset"] = {
                        ["x"] = -35,
                    },
                },
                ["borderEnable"] = true,
                ["textName"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["iconWidth"] = 48,
                ["iconPadding"] = 8,
                ["textCharges"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["opacityOutOfCombat"] = 50,
                ["positionX"] = 165,
                ["iconHeight"] = 32,
                ["orientation"] = "V",
                ["borderThickness"] = 3,
                ["hideWhenInactive"] = true,
                ["textDuration"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
            },
            ["buffs"] = {
                ["borderThickness"] = 2,
                ["positionY"] = 516,
                ["textCount"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["borderEnable"] = true,
                ["iconWidth"] = 36,
                ["iconPadding"] = 15,
                ["textDuration"] = {
                    ["offset"] = {
                        ["y"] = -2,
                        ["x"] = 2,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "SHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        0.8235294818878174,
                        0,
                        1,
                    },
                    ["size"] = 12,
                },
                ["hideCollapseButton"] = true,
                ["positionX"] = 442,
                ["iconHeight"] = 24,
                ["textStacks"] = {
                    ["offset"] = {
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        1,
                        1,
                        1,
                    },
                    ["size"] = 14,
                },
            },
            ["sctDamage"] = {
                ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                ["fontScale"] = 60,
            },
            ["utilityCooldowns"] = {
                ["textStacks"] = {
                    ["offset"] = {
                        ["y"] = 4,
                        ["x"] = 10,
                    },
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                    ["color"] = {
                        1,
                        0,
                        0,
                        1,
                    },
                    ["size"] = 14,
                },
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["positionY"] = -269,
                ["iconSize"] = 80,
                ["borderThickness"] = 2,
                ["borderEnable"] = true,
                ["textName"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["columns"] = 7,
                ["iconWidth"] = 36,
                ["iconPadding"] = 6,
                ["textCharges"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["opacityOutOfCombat"] = 25,
                ["iconHeight"] = 24,
                ["hideWhenInactive"] = true,
                ["textDuration"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
            },
            ["microBar"] = {
                ["mouseoverMode"] = true,
                ["direction"] = "up",
                ["barOpacity"] = 1,
                ["positionY"] = -114,
                ["positionX"] = -1037,
                ["barOpacityWithTarget"] = 1,
                ["orientation"] = "V",
                ["menuSize"] = 70,
                ["barOpacityOutOfCombat"] = 20,
                ["eyeSize"] = 125,
            },
            ["stanceBar"] = {
                ["mouseoverMode"] = true,
                ["barOpacity"] = 20,
                ["barOpacityWithTarget"] = 20,
                ["positionX"] = -469,
                ["iconSize"] = 60,
                ["positionY"] = -589,
                ["barOpacityOutOfCombat"] = 10,
            },
            ["actionBar8"] = {
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["positionY"] = 200,
                ["textStacks"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textHotkey"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["textMacro"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
            },
            ["actionBar3"] = {
                ["borderThickness"] = 2,
                ["textCooldown"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["positionY"] = -575,
                ["borderEnable"] = true,
                ["barOpacityWithTarget"] = 10,
                ["positionX"] = 300,
                ["textMacro"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["iconSize"] = 50,
                ["mouseoverMode"] = true,
                ["columns"] = 2,
                ["textStacks"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                    ["style"] = "HEAVYSHADOWTHICKOUTLINE",
                },
                ["barOpacity"] = 10,
                ["textHotkey"] = {
                    ["fontFace"] = "ROBOTO_SEMICOND_BLACK",
                },
                ["barOpacityOutOfCombat"] = 10,
            },
        },
        ["minimap"] = {
            ["minimapPos"] = 162.4444425305019,
        },
    },
})

Presets:Register({
    id = "ScooterDeck",
    name = "ScooterDeck",
    description = "Steam Deck / controller-focused layout with enlarged text and ConsolePort bindings.",
    wowBuild = "11.2.5",
    version = "PENDING",
    screenClass = "handheld",
    recommendedInput = "ConsolePort",
    tags = { "Handheld", "ConsolePort", "Steam Deck" },
    previewTexture = "Interface\\AddOns\\ScooterMod\\Scooter",
    previewThumbnail = "Interface\\AddOns\\ScooterMod\\Scooter",
    designedFor = { "Steam Deck / handheld displays", "Controller gameplay" },
    recommends = { "ConsolePort (required)" },
    requiresConsolePort = true,
    comingSoon = true,
})

return Presets

