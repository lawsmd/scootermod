-- ChatRenderer.lua - Chat settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Chat = {}

local Chat = addon.UI.Settings.Chat
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function Chat.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Helper to get/set chat profile settings
    local function getChatSetting(key)
        local profile = addon.db and addon.db.profile
        return profile and profile.chat and profile.chat[key]
    end

    local function setChatSetting(key, value)
        if not (addon.db and addon.db.profile) then return end
        addon.db.profile.chat = addon.db.profile.chat or {}
        addon.db.profile.chat[key] = value
        -- Apply styles after setting change
        if addon and addon.ApplyStyles then
            C_Timer.After(0, function()
                if addon and addon.ApplyStyles then
                    addon:ApplyStyles()
                end
            end)
        end
    end

    builder:AddToggle({
        label = "Hide In-Game Chat",
        get = function()
            return getChatSetting("hideInGameChat") or false
        end,
        set = function(val)
            setChatSetting("hideInGameChat", val)
        end,
        infoIcon = {
            tooltipTitle = "Hide In-Game Chat",
            tooltipText = "Hides chat windows/tabs and related controls, but keeps the chat input box so you can see slash commands you run. Added for use with the ScooterDeck preset. If you want to customize your Chat frame, I recommend Chattynator. :)",
        },
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("chat", function(panel, scrollContent)
    Chat.Render(panel, scrollContent)
end)

-- Return module
--------------------------------------------------------------------------------

return Chat
