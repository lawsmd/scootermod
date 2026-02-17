-- LootVendorsRenderer.lua - Quality of Life: Loot & Vendors settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.QoL = addon.UI.Settings.QoL or {}
addon.UI.Settings.QoL.LootVendors = {}

local LootVendors = addon.UI.Settings.QoL.LootVendors
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

local function getQoL()
    local profile = addon and addon.db and addon.db.profile
    return profile and profile.qol
end

local function ensureQoL()
    if not (addon and addon.db and addon.db.profile) then return nil end
    addon.db.profile.qol = addon.db.profile.qol or {}
    return addon.db.profile.qol
end

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function LootVendors.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Repair mode selector
    builder:AddSelector({
        label = "Repair Automatically",
        description = "Automatically repair all gear when visiting a merchant.",
        values = {
            off = "Off",
            personal = "Personal",
            guild = "Guild Bank",
        },
        order = { "off", "personal", "guild" },
        get = function()
            local q = getQoL()
            return (q and q.autoRepairMode) or "off"
        end,
        set = function(value)
            local q = ensureQoL()
            if not q then return end
            q.autoRepairMode = value
        end,
    })

    -- Sell grey items toggle
    builder:AddToggle({
        label = "Automatically Sell Grey Items",
        description = "Sell all poor-quality (grey) items when visiting a merchant.",
        get = function()
            local q = getQoL()
            return (q and q.sellGreyItems) or false
        end,
        set = function(value)
            local q = ensureQoL()
            if not q then return end
            q.sellGreyItems = value
        end,
    })

    -- Faster auto loot toggle
    builder:AddToggle({
        label = "Faster Auto Loot",
        description = "Speed up looting by automatically picking up all items.",
        infoIcon = {
            tooltipTitle = "Faster Auto Loot",
            tooltipText = "Enables Blizzard's auto loot and adds a quick retry to pick up any items the game misses on the first pass.",
        },
        get = function()
            local q = getQoL()
            return (q and q.quickLoot) or false
        end,
        set = function(value)
            local q = ensureQoL()
            if not q then return end
            q.quickLoot = value
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("qolLootVendors", function(panel, scrollContent)
    LootVendors.Render(panel, scrollContent)
end)

return LootVendors
