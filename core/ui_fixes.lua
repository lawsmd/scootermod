local addonName, addon = ...

-- Blizzard UI workarounds for dropdown stepper behavior.
-- These hooks fix issues with dropdown stepper (left/right arrow) buttons not
-- properly updating their enabled/disabled state after selections change.

addon.UIFixes = addon.UIFixes or {}

function addon.UIFixes.ApplyDropdownStepperFixes()
    -- IMPORTANT: Use hooksecurefunc instead of direct method replacement to avoid taint.
    -- Direct replacement of Blizzard mixin methods spreads taint to any code path that
    -- calls those methods, causing "blocked from an action" errors for protected functions
    -- like FocusUnit(), ClearFocus(), etc.
    --
    -- CRITICAL: All hook actions are deferred via C_Timer.After(0, ...) to break the
    -- execution context chain. Without this deferral, taint can propagate to unrelated
    -- Blizzard UI systems (e.g., Spell Book) causing "blocked from an action" errors
    -- on protected functions like Frame:SetWidth(). See DEBUG.md for details.

    -- Ensure dropdown steppers (left/right arrows) refresh enable/disable state after selection changes
    do
        local mixin = _G.SettingsDropdownControlMixin
        if mixin and type(mixin.OnSettingValueChanged) == "function" and not addon._dropdownReinitPatched then
            hooksecurefunc(mixin, "OnSettingValueChanged", function(self, setting, value)
                -- Capture references for deferred execution
                local dropdown = self
                local control = self and self.Control
                -- Defer all actions to break taint propagation chain
                C_Timer.After(0, function()
                    -- Reinitialize dropdown so steppers recalc based on current selection and options order
                    if dropdown and type(dropdown.InitDropdown) == "function" then
                        pcall(dropdown.InitDropdown, dropdown)
                    end
                    -- Refresh stepper enabled state
                    if control and type(control.UpdateSteppers) == "function" then
                        pcall(control.UpdateSteppers, control)
                        -- Second refresh next frame to catch async updates
                        C_Timer.After(0, function()
                            if control and type(control.UpdateSteppers) == "function" then
                                pcall(control.UpdateSteppers, control)
                            end
                        end)
                    end
                end)
            end)
            addon._dropdownReinitPatched = true
        end
    end

    -- Also force stepper refresh immediately after arrow clicks by extending DropdownWithSteppersMixin
    do
        local mixin = _G.DropdownWithSteppersMixin
        if mixin and not addon._dropdownStepperPatched then
            if type(mixin.Increment) == "function" then
                hooksecurefunc(mixin, "Increment", function(self, ...)
                    -- Capture references for deferred execution
                    local stepper = self
                    local dropdown = self and self.Dropdown
                    -- Defer to break taint propagation chain
                    C_Timer.After(0, function()
                        if dropdown and type(dropdown.Update) == "function" then
                            pcall(dropdown.Update, dropdown)
                        end
                        if stepper and type(stepper.UpdateSteppers) == "function" then
                            pcall(stepper.UpdateSteppers, stepper)
                        end
                    end)
                end)
            end
            if type(mixin.Decrement) == "function" then
                hooksecurefunc(mixin, "Decrement", function(self, ...)
                    -- Capture references for deferred execution
                    local stepper = self
                    local dropdown = self and self.Dropdown
                    -- Defer to break taint propagation chain
                    C_Timer.After(0, function()
                        if dropdown and type(dropdown.Update) == "function" then
                            pcall(dropdown.Update, dropdown)
                        end
                        if stepper and type(stepper.UpdateSteppers) == "function" then
                            pcall(stepper.UpdateSteppers, stepper)
                        end
                    end)
                end)
            end
            addon._dropdownStepperPatched = true
        end
    end

    -- Ensure dropdown emits an OnUpdate after selection via arrows so steppers reflect edges immediately
    do
        local mixin = _G.DropdownButtonMixin
        if mixin and type(mixin.Pick) == "function" and not addon._dropdownSignalUpdatePatched then
            hooksecurefunc(mixin, "Pick", function(self, description, ...)
                -- Capture reference for deferred execution
                local button = self
                -- Defer to break taint propagation chain
                C_Timer.After(0, function()
                    -- After a selection is picked, explicitly signal an update so steppers recompute
                    if button and type(button.SignalUpdate) == "function" then
                        pcall(button.SignalUpdate, button)
                    end
                end)
            end)
            addon._dropdownSignalUpdatePatched = true
        end
    end
end

