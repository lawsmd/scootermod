local addonName, addon = ...

LibStub("AceAddon-3.0"):NewAddon(addon, "ScooterMod", "AceEvent-3.0")

local function PrintScootMessage(text)
    if not text or text == "" then return end
    local prefix = "|cff00ff00[SCOOT]|r"
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s: %s", prefix, text))
    end
end

function addon:Print(message)
    PrintScootMessage(message)
end

SLASH_SCOOTERMOD1 = "/scoot"
function SlashCmdList.SCOOTERMOD(msg, editBox)
    if addon.SettingsPanel and addon.SettingsPanel.Toggle then
        addon.SettingsPanel:Toggle()
    end
end

function addon:OnEnable()
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "HandleCombatStarted")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "HandleCombatEnded")
end

function addon:OnDisable()
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

function addon:HandleCombatStarted()
    if self.ApplyStyles then
        self:ApplyStyles()
    end

    local panel = self.SettingsPanel
    if not panel then return end

    panel._combatLocked = true
    if panel.frame and panel.frame:IsShown() then
        panel._shouldReopenAfterCombat = true
        panel.frame:Hide()
        self:Print("ScooterMod will reopen once combat ends.")
    end
end

function addon:HandleCombatEnded()
    if self.ApplyStyles then
        self:ApplyStyles()
    end

    local panel = self.SettingsPanel
    if not panel then return end

    panel._combatLocked = false
    local shouldReopen = panel._shouldReopenAfterCombat
    panel._shouldReopenAfterCombat = false
    if shouldReopen and panel.Open then
        panel:Open()
    end
end
