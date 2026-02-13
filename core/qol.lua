-- qol.lua - Quality of Life automation (Loot & Vendors)
local addonName, addon = ...

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
-- Merchant Handler (Auto Repair + Sell Grey Items)
--------------------------------------------------------------------------------

local function onMerchantShow()
    local qol = getQoL()
    if not qol then return end

    -- Sell grey items
    if qol.sellGreyItems then
        for bag = 0, 4 do
            local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bag)
            if ok and numSlots then
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                        C_Container.UseContainerItem(bag, slot)
                    end
                end
            end
        end
    end

    -- Auto repair
    if qol.autoRepairMode and qol.autoRepairMode ~= "off" then
        if CanMerchantRepair() then
            local cost, canRepair = GetRepairAllCost()
            if canRepair and cost > 0 then
                local useGuild = (qol.autoRepairMode == "guild")
                if useGuild then
                    -- Try guild repair first, fall back to personal
                    local guildOk = pcall(RepairAllItems, true)
                    if not guildOk then
                        pcall(RepairAllItems, false)
                    end
                else
                    pcall(RepairAllItems, false)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Loot Handler (Faster Auto Loot)
--------------------------------------------------------------------------------

local function onLootReady(autoLoot)
    local qol = getQoL()
    if not qol or not qol.quickLoot then return end

    -- Ensure auto loot CVar is enabled
    if C_CVar and C_CVar.GetCVar then
        local current = C_CVar.GetCVar("autoLootDefault")
        if current ~= "1" then
            pcall(C_CVar.SetCVar, "autoLootDefault", "1")
        end
    end

    -- Loot all items
    local numItems = GetNumLootItems()
    if numItems and numItems > 0 then
        for i = numItems, 1, -1 do
            pcall(LootSlot, i)
        end
    end

    -- Retry once after 100ms to catch any items missed on first pass
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            local count = GetNumLootItems()
            if count and count > 0 then
                for i = count, 1, -1 do
                    pcall(LootSlot, i)
                end
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------

local qolEventFrame = CreateFrame("Frame")
qolEventFrame:RegisterEvent("MERCHANT_SHOW")
qolEventFrame:RegisterEvent("LOOT_READY")

qolEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        onMerchantShow()
    elseif event == "LOOT_READY" then
        onLootReady(...)
    end
end)
