local addonName, addon = ...

LibStub("AceAddon-3.0"):NewAddon(addon, "ScooterMod", "AceEvent-3.0")
_G.ScooterModAddon = addon
_G.ScooterMod = addon

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
    local function trim(s)
        if type(s) ~= "string" then return "" end
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local function parseQuotedArgs(s)
        local args = {}
        s = s or ""
        local i = 1
        while i <= #s do
            local c = s:sub(i, i)
            if c == '"' then
                local j = i + 1
                while j <= #s and s:sub(j, j) ~= '"' do j = j + 1 end
                table.insert(args, s:sub(i + 1, j - 1))
                i = (j < #s) and (j + 2) or (j + 1)
            else
                local j = i
                while j <= #s and not s:sub(j, j):match("%s") do j = j + 1 end
                table.insert(args, s:sub(i, j - 1))
                i = j + 1
            end
        end
        return args
    end

    msg = trim(msg)
    if msg == "" then
        if addon.SettingsPanel and addon.SettingsPanel.Toggle then
            addon.SettingsPanel:Toggle()
        end
        return
    end

    local args = parseQuotedArgs(msg)
    local cmd = string.lower(args[1] or "")

    -- /scoot del "Layout Name"
    if cmd == "del" or cmd == "delete" then
        local target = args[2]
        if not target or target == "" then addon:Print("Usage: /scoot del \"Layout Name\"") return end
        if InCombatLockdown and InCombatLockdown() then addon:Print("Cannot delete during combat.") return end
        local LEO = LibStub and LibStub("LibEditModeOverride-1.0")
        if not (LEO and LEO.IsReady and LEO:IsReady()) then addon:Print("Edit Mode not ready.") return end
        if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
        if not (LEO.DoesLayoutExist and LEO:DoesLayoutExist(target)) then addon:Print("Layout not found: "..target) return end
        local ok, err = pcall(LEO.DeleteLayout, LEO, target)
        if not ok then addon:Print("Delete failed: "..tostring(err)) return end
        if LEO.SaveOnly then pcall(LEO.SaveOnly, LEO) end
        if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
        if LEO.DoesLayoutExist and LEO:DoesLayoutExist(target) then
            addon:Print("Delete did not persist (still exists): "..target)
        else
            addon:Print("Deleted layout: "..target)
        end
        return
    end

    -- /scoot copy "Source Name" "New Name"
    if cmd == "copy" then
        local src = args[2]
        local dest = args[3]
        if not src or not dest then addon:Print("Usage: /scoot copy \"Source Name\" \"New Name\"") return end
        if InCombatLockdown and InCombatLockdown() then addon:Print("Cannot copy during combat.") return end
        C_AddOns.LoadAddOn("Blizzard_EditMode")
        local layouts = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
        if not (EditModeManagerFrame and layouts and layouts.layouts) then addon:Print("Edit Mode not ready.") return end
        local source
        for _, layout in ipairs(layouts.layouts) do
            if layout.layoutName == src then source = CopyTable(layout) break end
        end
        if not source then addon:Print("Source layout not found: "..src) return end
        if C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(dest) then addon:Print("Invalid new name.") return end
            if EditModeManagerFrame.MakeNewLayout then
            EditModeManagerFrame:MakeNewLayout(source, source.layoutType or Enum.EditModeLayoutType.Character, dest, false)
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            addon:Print("Copied layout '"..src.."' -> '"..dest.."'")
        else
            addon:Print("Copy failed: manager unavailable.")
        end
        return
    end

    -- Fallback: open settings
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
        self:Print("ScooterMod will open once combat ends.")
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
