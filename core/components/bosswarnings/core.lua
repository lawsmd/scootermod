-- bosswarnings/core.lua - Edit Mode helpers and text hooks for Boss Warning frames
-- Reads from one frame, writes to all 3 severity frames simultaneously.
local _, addon = ...

local WARNING_FRAMES = {
    "CriticalEncounterWarnings",
    "MediumEncounterWarnings",
    "MinorEncounterWarnings",
}

local function ensureWarningsLoaded()
    if _G[WARNING_FRAMES[1]] then return true end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterWarnings")
    end
    return _G[WARNING_FRAMES[1]] ~= nil
end

--------------------------------------------------------------------------------
-- Edit Mode Get/Set Helpers
--------------------------------------------------------------------------------

function addon.getBossWarningsSetting(settingId)
    if not ensureWarningsLoaded() then return nil end
    local frame = _G[WARNING_FRAMES[1]]
    if not frame or not addon.EditMode or not addon.EditMode.GetSetting then return nil end
    return addon.EditMode.GetSetting(frame, settingId)
end

function addon.setBossWarningsSetting(settingId, value)
    if not ensureWarningsLoaded() then return end
    if not addon.EditMode or not addon.EditMode.WriteSetting then return end

    for i, frameName in ipairs(WARNING_FRAMES) do
        local frame = _G[frameName]
        if frame then
            local isLast = (i == #WARNING_FRAMES)
            addon.EditMode.WriteSetting(frame, settingId, value, {
                skipSave = not isLast,
                suspendDuration = isLast and 0.25 or nil,
            })
        end
    end
end

--------------------------------------------------------------------------------
-- Text Styling
--------------------------------------------------------------------------------

--- Preserves Blizzard's font size (varies per severity, includes ScaleTextToFit).
local function applyTextStyling(fontString)
    if not fontString then return end
    local db = addon.db and addon.db.profile and addon.db.profile.bossWarnings
    if not db then return end

    local fontFace = db.textFontFace
    local fontStyle = db.textFontStyle
    if not fontFace and not fontStyle then return end

    local currentFace, currentSize, currentFlags = fontString:GetFont()
    if not currentSize then return end

    local newFace = fontFace and addon.ResolveFontFace(fontFace) or currentFace
    local newFlags = fontStyle or currentFlags

    local ok = pcall(fontString.SetFont, fontString, newFace, currentSize, newFlags)
    if not ok and newFace ~= currentFace then
        pcall(fontString.SetFont, fontString, currentFace, currentSize, newFlags)
    end
end

--- Find all FontStrings under a warning system frame (children → regions).
--- Edit Mode adds an overlay with its own FontString on top of View.Text.
local function findWarningFontStrings(systemFrame)
    local results = {}
    if not systemFrame or not systemFrame.GetChildren then return results end
    for _, child in ipairs({systemFrame:GetChildren()}) do
        if child.GetRegions then
            for _, region in ipairs({child:GetRegions()}) do
                if region.IsObjectType and region:IsObjectType("FontString") then
                    results[#results + 1] = region
                end
            end
        end
    end
    return results
end

--------------------------------------------------------------------------------
-- Hook Installation (Blizzard_EncounterWarnings is load-on-demand)
--------------------------------------------------------------------------------

local hooksInstalled = false

local function tryInstallHooks()
    if hooksInstalled then return end
    if not ensureWarningsLoaded() then return end

    local mixin = _G.EncounterWarningsTextElementMixin
    if not mixin then return end

    -- Hook Init for real encounter warnings (not just Edit Mode previews).
    -- Deferred: Edit Mode may re-apply SetFontObject in the same frame as Init.
    hooksecurefunc(mixin, "Init", function(self)
        C_Timer.After(0, function()
            applyTextStyling(self)
        end)
    end)
    hooksInstalled = true
end

--- Re-apply text styling to all visible warning FontStrings.
function addon.refreshBossWarningsText()
    tryInstallHooks()
    for _, frameName in ipairs(WARNING_FRAMES) do
        local frame = _G[frameName]
        if frame then
            for _, fs in ipairs(findWarningFontStrings(frame)) do
                applyTextStyling(fs)
            end
        end
    end
end

addon:RegisterComponentInitializer(function()
    tryInstallHooks()

    -- Listen for demand-load if addon isn't available yet.
    if not hooksInstalled then
        local listener = CreateFrame("Frame")
        listener:RegisterEvent("ADDON_LOADED")
        listener:SetScript("OnEvent", function(self, _, loadedAddon)
            if loadedAddon == "Blizzard_EncounterWarnings" then
                tryInstallHooks()
                self:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end

    -- Apply saved font when entering Edit Mode (deferred past layout updates).
    local mgr = _G.EditModeManagerFrame
    if mgr and type(mgr.EnterEditMode) == "function" then
        hooksecurefunc(mgr, "EnterEditMode", function()
            C_Timer.After(0, function()
                if addon.refreshBossWarningsText then
                    addon.refreshBossWarningsText()
                end
            end)
        end)
    end
end, "bossWarnings")
