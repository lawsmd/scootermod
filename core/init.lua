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
    
    -- Apply dropdown stepper fixes
    self:ApplyDropdownStepperFixes()
end

function addon:ApplyDropdownStepperFixes()
    -- Ensure dropdown steppers (left/right arrows) refresh enable/disable state after selection changes
    do
        local mixin = _G.SettingsDropdownControlMixin
        if mixin and type(mixin.OnSettingValueChanged) == "function" and not addon._dropdownReinitPatched then
            local original = mixin.OnSettingValueChanged
            mixin.OnSettingValueChanged = function(self, setting, value)
                if original then pcall(original, self, setting, value) end
                -- Reinitialize dropdown so steppers recalc based on current selection and options order
                if self and type(self.InitDropdown) == "function" then
                    pcall(self.InitDropdown, self)
                end
                -- Immediately refresh stepper enabled state and again next frame to catch async updates
                if self and self.Control and type(self.Control.UpdateSteppers) == "function" then
                    pcall(self.Control.UpdateSteppers, self.Control)
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            pcall(self.Control.UpdateSteppers, self.Control)
                        end)
                    end
                end
            end
            addon._dropdownReinitPatched = true
        end
    end

    -- Also force stepper refresh immediately after arrow clicks by extending DropdownWithSteppersMixin
    do
        local mixin = _G.DropdownWithSteppersMixin
        if mixin and not addon._dropdownStepperPatched then
            local origInc = mixin.Increment
            local origDec = mixin.Decrement
            mixin.Increment = function(self, ...)
                if origInc then pcall(origInc, self, ...) end
                if self and self.Dropdown and type(self.Dropdown.Update) == "function" then
                    pcall(self.Dropdown.Update, self.Dropdown)
                end
                if type(self.UpdateSteppers) == "function" then
                    pcall(self.UpdateSteppers, self)
                end
            end
            mixin.Decrement = function(self, ...)
                if origDec then pcall(origDec, self, ...) end
                if self and self.Dropdown and type(self.Dropdown.Update) == "function" then
                    pcall(self.Dropdown.Update, self.Dropdown)
                end
                if type(self.UpdateSteppers) == "function" then
                    pcall(self.UpdateSteppers, self)
                end
            end
            addon._dropdownStepperPatched = true
        end
    end

    -- Ensure dropdown emits an OnUpdate after selection via arrows so steppers reflect edges immediately
    do
        local mixin = _G.DropdownButtonMixin
        if mixin and type(mixin.Pick) == "function" and not addon._dropdownSignalUpdatePatched then
            local originalPick = mixin.Pick
            mixin.Pick = function(self, description, ...)
                local responded = false
                if originalPick then
                    responded = originalPick(self, description, ...)
                end
                -- After a selection is picked, explicitly signal an update so steppers recompute
                if self and type(self.SignalUpdate) == "function" then
                    pcall(self.SignalUpdate, self)
                end
                return responded
            end
            addon._dropdownSignalUpdatePatched = true
        end
    end
end

function addon:PLAYER_ENTERING_WORLD(event, isInitialLogin, isReloadingUi)
    -- Initialize Edit Mode integration
    addon.EditMode.Initialize()
    
    -- Use centralized sync function
    addon.EditMode.RefreshSyncAndNotify("PLAYER_ENTERING_WORLD")
    self:ApplyStyles()
end

function addon:EDIT_MODE_LAYOUTS_UPDATED()
    -- Use centralized sync function
    addon.EditMode.RefreshSyncAndNotify("EDIT_MODE_LAYOUTS_UPDATED")
    self:ApplyStyles()
end
