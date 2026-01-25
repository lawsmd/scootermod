local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

--------------------------------------------------------------------------------
-- Damage Meters Builder Module (Minimal Test Version)
--------------------------------------------------------------------------------

-- Helper: Get component DB
local function ensureDMDB()
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    db.components = db.components or {}
    db.components.damageMeter = db.components.damageMeter or {}
    return db.components.damageMeter
end

-- Helper: Apply styles after changes
local function applyNow()
    if addon and addon.ApplyStyles then addon:ApplyStyles() end
end

--------------------------------------------------------------------------------
-- Damage Meters Renderer
--------------------------------------------------------------------------------

function panel.RenderDamageMeter()
    local componentId = "damageMeter"

    local render = function()
        local init = {}

        --------------------------------------------------------------------------------
        -- Parent-level Style dropdown (copied from groupframes pattern)
        --------------------------------------------------------------------------------
        do
            local label = "Style"

            local function styleOptions()
                local container = Settings.CreateControlTextContainer()
                container:Add(0, "Default")
                container:Add(1, "Bordered")
                container:Add(2, "Thin")
                return container:GetData()
            end

            local function getter()
                local db = ensureDMDB() or {}
                return db.style or 0
            end

            local function setter(v)
                C_Timer.After(0, function()
                    local db = ensureDMDB()
                    if not db then return end
                    db.style = tonumber(v) or 0
                    applyNow()
                end)
            end

            local setting = CreateLocalSetting(label, "number", getter, setter, getter())
            local dropInit = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", {
                name = label,
                setting = setting,
                options = styleOptions,
            })
            dropInit.GetExtent = function() return 34 end

            do
                local baseInitFrame = dropInit.InitFrame
                dropInit.InitFrame = function(self, frame)
                    if baseInitFrame then baseInitFrame(self, frame) end
                    if panel and panel.ApplyRobotoWhite then
                        local lbl = frame.Text or frame.Label
                        if lbl then panel.ApplyRobotoWhite(lbl) end
                    end
                    if frame.Control and panel and panel.ThemeDropdownWithSteppers then
                        panel.ThemeDropdownWithSteppers(frame.Control)
                    end
                end
            end

            table.insert(init, dropInit)
        end

        --------------------------------------------------------------------------------
        -- Layout Section Header (just the header, no content)
        --------------------------------------------------------------------------------
        do
            local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                name = "Layout",
                sectionKey = "Layout",
                componentId = componentId,
                expanded = panel:IsSectionExpanded(componentId, "Layout"),
            })
            expInitializer.GetExtent = function() return 30 end
            table.insert(init, expInitializer)
        end

        -- Display the content
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then return end

        if right.SetTitle then
            right:SetTitle("Damage Meters")
        end
        right:Display(init)
    end

    return {
        mode = "list",
        render = render,
        componentId = componentId,
    }
end
