local addonName, addon = ...

local Presets = addon.Presets
if not Presets or not Presets.Register then
    error("ScooterMod preset payload loaded before Presets API (core/presets.lua). Check ScooterMod.toc load order: core/presets.lua must load before core/preset_*.lua.", 2)
end

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
    editModeLayout = {
      layoutName = "ScooterUI",
      layoutType = 1,
      systems = {
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = -575,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 2,
            },
            {
              setting = 2,
              value = 12,
            },
            {
              setting = 3,
              value = 0,
            },
            {
              setting = 4,
              value = 2,
            },
            {
              setting = 6,
              value = 1,
            },
            {
              setting = 8,
              value = 1,
            },
            {
              setting = 9,
              value = 1,
            },
          },
          system = 0,
          systemIndex = 1,
        },
        {
          anchorInfo = {
            offsetX = 150,
            offsetY = -575,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 2,
            },
            {
              setting = 2,
              value = 12,
            },
            {
              setting = 3,
              value = 0,
            },
            {
              setting = 4,
              value = 2,
            },
            {
              setting = 5,
              value = 0,
            },
            {
              setting = 9,
              value = 1,
            },
          },
          system = 0,
          systemIndex = 2,
        },
        {
          anchorInfo = {
            offsetX = 300,
            offsetY = -575,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 2,
            },
            {
              setting = 2,
              value = 12,
            },
            {
              setting = 3,
              value = 0,
            },
            {
              setting = 4,
              value = 2,
            },
            {
              setting = 5,
              value = 0,
            },
            {
              setting = 9,
              value = 1,
            },
          },
          system = 0,
          systemIndex = 3,
        },
        {
          anchorInfo = {
            offsetX = -150,
            offsetY = -575,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 2,
            },
            {
              setting = 2,
              value = 12,
            },
            {
              setting = 3,
              value = 0,
            },
            {
              setting = 4,
              value = 2,
            },
            {
              setting = 5,
              value = 0,
            },
            {
              setting = 9,
              value = 1,
            },
          },
          system = 0,
          systemIndex = 4,
        },
        {
          anchorInfo = {
            offsetX = -300,
            offsetY = -575,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 2,
            },
            {
              setting = 2,
              value = 12,
            },
            {
              setting = 3,
              value = 0,
            },
            {
              setting = 4,
              value = 2,
            },
            {
              setting = 5,
              value = 0,
            },
            {
              setting = 9,
              value = 1,
            },
          },
          system = 0,
          systemIndex = 5,
        },
        {
          anchorInfo = {
            offsetX = 328,
            offsetY = -1102,
            point = "TOP",
            relativePoint = "TOP",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 2,
            },
            {
              setting = 2,
              value = 12,
            },
            {
              setting = 3,
              value = 0,
            },
            {
              setting = 4,
              value = 2,
            },
            {
              setting = 5,
              value = 0,
            },
            {
              setting = 9,
              value = 1,
            },
          },
          system = 0,
          systemIndex = 6,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = 150,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 1,
            },
            {
              setting = 2,
              value = 12,
            },
            {
              setting = 3,
              value = 5,
            },
            {
              setting = 4,
              value = 2,
            },
            {
              setting = 5,
              value = 0,
            },
            {
              setting = 9,
              value = 1,
            },
          },
          system = 0,
          systemIndex = 7,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = 200,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 1,
            },
            {
              setting = 2,
              value = 12,
            },
            {
              setting = 3,
              value = 5,
            },
            {
              setting = 4,
              value = 2,
            },
            {
              setting = 5,
              value = 0,
            },
            {
              setting = 9,
              value = 1,
            },
          },
          system = 0,
          systemIndex = 8,
        },
        {
          anchorInfo = {
            offsetX = -4,
            offsetY = 0,
            point = "BOTTOMRIGHT",
            relativePoint = "BOTTOMLEFT",
            relativeTo = "MultiBarLeft",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 1,
            },
            {
              setting = 3,
              value = 1,
            },
            {
              setting = 4,
              value = 2,
            },
          },
          system = 0,
          systemIndex = 11,
        },
        {
          anchorInfo = {
            offsetX = -5,
            offsetY = 4,
            point = "TOPRIGHT",
            relativePoint = "BOTTOMRIGHT",
            relativeTo = "PetFrame",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 1,
            },
            {
              setting = 3,
              value = 0,
            },
            {
              setting = 4,
              value = 2,
            },
            {
              setting = 9,
              value = 1,
            },
          },
          system = 0,
          systemIndex = 12,
        },
        {
          anchorInfo = {
            offsetX = 286.5,
            offsetY = 265.5,
            point = "BOTTOMLEFT",
            relativePoint = "BOTTOMLEFT",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 1,
            },
            {
              setting = 3,
              value = 5,
            },
            {
              setting = 4,
              value = 2,
            },
          },
          system = 0,
          systemIndex = 13,
        },
        {
          anchorInfo = {
            offsetX = -0,
            offsetY = -292.79998779297,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 2,
            },
            {
              setting = 1,
              value = 0,
            },
            {
              setting = 2,
              value = 0,
            },
          },
          system = 1,
        },
        {
          anchorInfo = {
            offsetX = 882.70001220703,
            offsetY = -2,
            point = "TOP",
            relativePoint = "TOP",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 0,
            },
            {
              setting = 2,
              value = 11,
            },
          },
          system = 2,
        },
        {
          anchorInfo = {
            offsetX = -413.29998779297,
            offsetY = -775.5,
            point = "TOP",
            relativePoint = "TOP",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 1,
              value = 0,
            },
            {
              setting = 16,
              value = 15,
            },
          },
          system = 3,
          systemIndex = 1,
        },
        {
          anchorInfo = {
            offsetX = 417.20001220703,
            offsetY = -775.5,
            point = "TOP",
            relativePoint = "TOP",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 2,
              value = 1,
            },
            {
              setting = 16,
              value = 15,
            },
          },
          system = 3,
          systemIndex = 2,
        },
        {
          anchorInfo = {
            offsetX = 223.60000610352,
            offsetY = 198.19999694824,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 2,
              value = 1,
            },
            {
              setting = 3,
              value = 1,
            },
            {
              setting = 16,
              value = 10,
            },
          },
          system = 3,
          systemIndex = 3,
        },
        {
          anchorInfo = {
            offsetX = 829.70001220703,
            offsetY = -913.40002441406,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 4,
              value = 1,
            },
            {
              setting = 5,
              value = 0,
            },
            {
              setting = 6,
              value = 1,
            },
            {
              setting = 10,
              value = 22,
            },
            {
              setting = 11,
              value = 24,
            },
            {
              setting = 12,
              value = 0,
            },
            {
              setting = 14,
              value = 1,
            },
            {
              setting = 16,
              value = 0,
            },
          },
          system = 3,
          systemIndex = 4,
        },
        {
          anchorInfo = {
            offsetX = 832.70001220703,
            offsetY = -917.09997558594,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 9,
              value = 0,
            },
            {
              setting = 10,
              value = 6,
            },
            {
              setting = 11,
              value = 6,
            },
            {
              setting = 12,
              value = 0,
            },
            {
              setting = 13,
              value = 0,
            },
            {
              setting = 14,
              value = 0,
            },
            {
              setting = 15,
              value = 5,
            },
          },
          system = 3,
          systemIndex = 5,
        },
        {
          anchorInfo = {
            offsetX = -604.09997558594,
            offsetY = -465,
            point = "TOPRIGHT",
            relativePoint = "TOPRIGHT",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 3,
              value = 0,
            },
            {
              setting = 7,
              value = 1,
            },
            {
              setting = 16,
              value = 0,
            },
          },
          system = 3,
          systemIndex = 6,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = 0,
            point = "RIGHT",
            relativePoint = "RIGHT",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = true,
          settings = {
            {
              setting = 10,
              value = 0,
            },
            {
              setting = 11,
              value = 0,
            },
            {
              setting = 12,
              value = 0,
            },
            {
              setting = 17,
              value = 1,
            },
          },
          system = 3,
          systemIndex = 7,
        },
        {
          anchorInfo = {
            offsetX = -35.799999237061,
            offsetY = 29.5,
            point = "TOP",
            relativePoint = "BOTTOM",
            relativeTo = "PlayerFrame",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 16,
              value = 5,
            },
          },
          system = 3,
          systemIndex = 8,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = 517.5,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
          },
          system = 4,
        },
        {
          anchorInfo = {
            offsetX = -457,
            offsetY = 402,
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
          },
          system = 5,
        },
        {
          anchorInfo = {
            offsetX = -4,
            offsetY = 0,
            point = "TOPRIGHT",
            relativePoint = "TOPLEFT",
            relativeTo = "MinimapCluster",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 0,
            },
            {
              setting = 2,
              value = 0,
            },
            {
              setting = 3,
              value = 11,
            },
            {
              setting = 5,
              value = 5,
            },
            {
              setting = 6,
              value = 15,
            },
          },
          system = 6,
          systemIndex = 1,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = -4,
            point = "TOPLEFT",
            relativePoint = "BOTTOMLEFT",
            relativeTo = "BuffFrame",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 0,
            },
            {
              setting = 2,
              value = 1,
            },
            {
              setting = 4,
              value = 10,
            },
            {
              setting = 5,
              value = 7,
            },
            {
              setting = 6,
              value = 15,
            },
          },
          system = 6,
          systemIndex = 2,
        },
        {
          anchorInfo = {
            offsetX = 223.39999389648,
            offsetY = 26.799999237061,
            point = "TOP",
            relativePoint = "BOTTOM",
            relativeTo = "FocusFrame",
          },
          isInDefaultPosition = false,
          settings = {
          },
          system = 7,
        },
        {
          anchorInfo = {
            offsetX = 35,
            offsetY = 50,
            point = "BOTTOMLEFT",
            relativePoint = "BOTTOMLEFT",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 4,
            },
            {
              setting = 1,
              value = 30,
            },
            {
              setting = 2,
              value = 1,
            },
            {
              setting = 3,
              value = 71,
            },
          },
          system = 8,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = 4,
            point = "BOTTOMLEFT",
            relativePoint = "TOPLEFT",
            relativeTo = "EncounterBar",
          },
          isInDefaultPosition = false,
          settings = {
          },
          system = 9,
        },
        {
          anchorInfo = {
            offsetX = 16,
            offsetY = -116,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = true,
          settings = {
          },
          system = 10,
        },
        {
          anchorInfo = {
            offsetX = 860.59997558594,
            offsetY = 402,
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
          },
          system = 11,
        },
        {
          anchorInfo = {
            offsetX = -904.70001220703,
            offsetY = -2,
            point = "TOP",
            relativePoint = "TOP",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 0,
            },
            {
              setting = 2,
              value = 0,
            },
          },
          system = 12,
        },
        {
          anchorInfo = {
            offsetX = 2,
            offsetY = -113.69999694824,
            point = "LEFT",
            relativePoint = "LEFT",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 1,
            },
            {
              setting = 1,
              value = 0,
            },
            {
              setting = 2,
              value = 0,
            },
            {
              setting = 3,
              value = 15,
            },
          },
          system = 13,
        },
        {
          anchorInfo = {
            offsetX = 520.5,
            offsetY = 1.5,
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 0,
            },
            {
              setting = 2,
              value = 0,
            },
          },
          system = 14,
        },
        {
          anchorInfo = {
            offsetX = -455.79998779297,
            offsetY = -2,
            point = "TOP",
            relativePoint = "TOP",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
          },
          system = 15,
          systemIndex = 1,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = 17,
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            relativeTo = "StatusTrackingBarManager",
          },
          isInDefaultPosition = true,
          settings = {
          },
          system = 15,
          systemIndex = 2,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = 0,
            point = "RIGHT",
            relativePoint = "RIGHT",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = true,
          settings = {
            {
              setting = 0,
              value = 5,
            },
          },
          system = 16,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = -100,
            point = "TOP",
            relativePoint = "TOP",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = true,
          settings = {
            {
              setting = 0,
              value = 0,
            },
          },
          system = 17,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = 0,
            point = "RIGHT",
            relativePoint = "RIGHT",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = true,
          settings = {
            {
              setting = 0,
              value = 10,
            },
          },
          system = 18,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = 0,
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = true,
          settings = {
            {
              setting = 0,
              value = 0,
            },
          },
          system = 19,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = -242.19999694824,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 12,
            },
            {
              setting = 2,
              value = 1,
            },
            {
              setting = 3,
              value = 3,
            },
            {
              setting = 4,
              value = 6,
            },
            {
              setting = 5,
              value = 50,
            },
            {
              setting = 6,
              value = 0,
            },
            {
              setting = 8,
              value = 1,
            },
            {
              setting = 9,
              value = 1,
            },
            {
              setting = 10,
              value = 1,
            },
          },
          system = 20,
          systemIndex = 1,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = -268.60000610352,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 0,
            },
            {
              setting = 1,
              value = 7,
            },
            {
              setting = 2,
              value = 1,
            },
            {
              setting = 3,
              value = 3,
            },
            {
              setting = 4,
              value = 6,
            },
            {
              setting = 5,
              value = 50,
            },
            {
              setting = 6,
              value = 0,
            },
            {
              setting = 8,
              value = 1,
            },
            {
              setting = 9,
              value = 1,
            },
            {
              setting = 10,
              value = 1,
            },
          },
          system = 20,
          systemIndex = 2,
        },
        {
          anchorInfo = {
            offsetX = 165.5,
            offsetY = 402,
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 1,
            },
            {
              setting = 1,
              value = 1,
            },
            {
              setting = 2,
              value = 0,
            },
            {
              setting = 3,
              value = 3,
            },
            {
              setting = 4,
              value = 8,
            },
            {
              setting = 5,
              value = 50,
            },
            {
              setting = 6,
              value = 0,
            },
            {
              setting = 8,
              value = 1,
            },
            {
              setting = 9,
              value = 1,
            },
            {
              setting = 10,
              value = 1,
            },
          },
          system = 20,
          systemIndex = 3,
        },
        {
          anchorInfo = {
            offsetX = 0,
            offsetY = -140,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
          },
          isInDefaultPosition = false,
          settings = {
            {
              setting = 0,
              value = 1,
            },
            {
              setting = 1,
              value = 1,
            },
            {
              setting = 2,
              value = 0,
            },
            {
              setting = 3,
              value = 5,
            },
            {
              setting = 4,
              value = 2,
            },
            {
              setting = 5,
              value = 50,
            },
            {
              setting = 6,
              value = 0,
            },
            {
              setting = 7,
              value = 2,
            },
            {
              setting = 8,
              value = 1,
            },
            {
              setting = 9,
              value = 1,
            },
            {
              setting = 10,
              value = 1,
            },
          },
          system = 20,
          systemIndex = 4,
        },
      },
    },
    editModeSha256 = "d8c5fcd341f51994d20411a59fd46e555747c9445512a36060dd327ef0ab908d",

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
