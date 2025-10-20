local addonName, addon = ...

function addon:OnInitialize()
    C_AddOns.LoadAddOn("Blizzard_Settings")
    -- 1. Define components and populate self.Components
    self:InitializeComponents()

    -- 2. Create the database, using the component list to build defaults
    self.db = LibStub("AceDB-3.0"):New("ScooterModDB", self:GetDefaults(), true)

    -- 3. Now that DB exists, link components to their DB tables
    self:LinkComponentsToDB()

    -- 4. Register for events
    self:RegisterEvents()
end

function addon:GetDefaults()
    local defaults = {
        profile = {
            components = {}
        }
    }

    for id, component in pairs(self.Components) do
        defaults.profile.components[id] = {}
        for settingId, setting in pairs(component.settings) do
            defaults.profile.components[id][settingId] = setting.default
        end
    end

    return defaults
end

function addon:RegisterEvents()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
end

function addon:PLAYER_ENTERING_WORLD(event, isInitialLogin, isReloadingUi)
    addon.EditMode.LoadLayouts()
    self:SyncAllEditModeSettings()
    self:ApplyStyles()
end

function addon:EDIT_MODE_LAYOUTS_UPDATED()
    addon.EditMode.LoadLayouts()
    self:SyncAllEditModeSettings()
    self:ApplyStyles()
end
