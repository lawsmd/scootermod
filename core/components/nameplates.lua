local addonName, addon = ...

local Component = addon.ComponentPrototype

local plateAddHookInstalled = false
local updateNameHookInstalled = false

local function isDefaultWhiteColor(color)
    if type(color) ~= "table" then
        return false
    end
    local r = tonumber(color[1]) or 0
    local g = tonumber(color[2]) or 0
    local b = tonumber(color[3]) or 0
    local a = tonumber(color[4])
    if a == nil then
        a = 1
    end
    return r == 1 and g == 1 and b == 1 and a == 1
end

local function migrateNameTextSettings(component)
    if not component or not component.db or component.db._nameplatesTextMigrated then
        return
    end
    local cfg = component.db.textName
    if cfg and isDefaultWhiteColor(cfg.color) then
        cfg.color = nil
    end
    if cfg and cfg.offset then
        cfg.offset = nil
    end
    component.db._nameplatesTextMigrated = true
end

local function copyDefault(default)
    if type(default) ~= "table" then
        return default
    end
    local out = {}
    for k, v in pairs(default) do
        out[k] = copyDefault(v)
    end
    return out
end

local function isPersonalPlate(namePlate)
    if not namePlate then
        return false
    end
    local uf = namePlate.UnitFrame
    if not uf then
        return false
    end
    if uf.data then
        if uf.data.isPersonal or uf.data.unit == "player" or uf.data.unit == "vehicle" then
            return true
        end
    end
    local unitToken = namePlate.namePlateUnitToken or uf.unit
    if unitToken == "player" or unitToken == "vehicle" then
        return true
    end
    if uf.UnitFrameType and tostring(uf.UnitFrameType):lower() == "personal" then
        return true
    end
    return false
end

local function resolveNameFontString(namePlate)
    local uf = namePlate and namePlate.UnitFrame
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then
        return nil
    end
    if uf.name then
        return uf.name
    end
    if uf.Name then
        return uf.Name
    end
    if uf.NameText then
        return uf.NameText
    end
    if uf.GetRegions then
        local count = uf.GetNumRegions and uf:GetNumRegions() or 0
        if count > 0 then
            for i = 1, count do
                local region = select(i, uf:GetRegions())
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    local regionName = (region.GetName and region:GetName()) or (region.GetDebugName and region:GetDebugName()) or ""
                    if type(regionName) == "string" and regionName:lower():find("name", 1, true) then
                        return region
                    end
                end
            end
        end
    end
    if uf.GetChildren then
        local children = uf.GetNumChildren and uf:GetNumChildren() or 0
        for i = 1, children do
            local child = select(i, uf:GetChildren())
            if child and child.GetRegions then
                local regCount = child.GetNumRegions and child:GetNumRegions() or 0
                for j = 1, regCount do
                    local region = select(j, child:GetRegions())
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        local regionName = (region.GetName and region:GetName()) or (region.GetDebugName and region:GetDebugName()) or ""
                        if type(regionName) == "string" and regionName:lower():find("name", 1, true) then
                            return region
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function applyFontSettings(component, fontString)
    if not component or not fontString then
        return
    end
    local cfg = component.db and component.db.textName
    if not cfg then
        local setting = component.settings and component.settings.textName
        if setting and setting.default then
            if component.db then
                component.db.textName = copyDefault(setting.default)
                cfg = component.db.textName
            else
                cfg = copyDefault(setting.default)
            end
        else
            cfg = { fontFace = "FRIZQT__", size = 14, style = "OUTLINE" }
        end
    end

    migrateNameTextSettings(component)
    cfg = component.db and component.db.textName or cfg

    -- Apply font face, size, and style only - do NOT touch positioning
    -- Blizzard repositions nameplate text on target/combat; we must not override that
    local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
    local size = tonumber(cfg.size) or 14
    local style = cfg.style or "OUTLINE"
    if fontString.SetFont then
        pcall(fontString.SetFont, fontString, face, size, style)
    end
    
    -- Apply color if configured
    local color = cfg and cfg.color
    if fontString.SetTextColor and type(color) == "table" then
        pcall(fontString.SetTextColor, fontString, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    
    -- Promote draw layer to ensure visibility above healthbar
    if fontString.SetDrawLayer then
        pcall(fontString.SetDrawLayer, fontString, "OVERLAY", 5)
    end
    
    -- NOTE: We intentionally do NOT modify the FontString's anchor/position.
    -- Blizzard dynamically repositions nameplate name text based on targeting,
    -- combat state, and other factors. Any attempt to cache or override the
    -- position will conflict with Blizzard's updates and cause visual glitches.
end

local function applyToNamePlate(component, namePlate)
    if not component or not namePlate or (namePlate.IsForbidden and namePlate:IsForbidden()) then
        return
    end
    if isPersonalPlate(namePlate) then
        return
    end
    local fontString = resolveNameFontString(namePlate)
    if not fontString then
        return
    end
    applyFontSettings(component, fontString)
end

local function applyToAllActive(component)
    local namePlateApi = _G.C_NamePlate
    if not component or not namePlateApi or not namePlateApi.GetNamePlates then
        return
    end
    local ok, plates = pcall(namePlateApi.GetNamePlates)
    if not ok or type(plates) ~= "table" then
        return
    end
    for _, plate in ipairs(plates) do
        applyToNamePlate(component, plate)
    end
end

local function restyleFromHook(namePlate)
    -- CRITICAL: Defer to avoid tainting Blizzard's nameplate setup chain.
    -- Accessing addon.Components taints execution; if we run synchronously,
    -- protected functions like SetTargetClampingInsets() will be blocked.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local component = addon.Components and addon.Components.nameplatesUnit
            if component and component.db then
                applyToNamePlate(component, namePlate)
            end
        end)
    else
        local component = addon.Components and addon.Components.nameplatesUnit
        if component and component.db then
            applyToNamePlate(component, namePlate)
        end
    end
end

local function ensureNamePlateHooks()
    local secureHook = _G.hooksecurefunc
    if secureHook then
        local driver = _G.NamePlateDriverFrame
        if not plateAddHookInstalled and driver and driver.OnNamePlateAdded then
            plateAddHookInstalled = true
            secureHook(driver, "OnNamePlateAdded", function(_, namePlate)
                restyleFromHook(namePlate)
            end)
        end
        if not updateNameHookInstalled and _G.CompactUnitFrame_UpdateName then
            updateNameHookInstalled = true
            secureHook("CompactUnitFrame_UpdateName", function(frame)
                -- CRITICAL: Defer check to avoid tainting execution context.
                -- The actual styling is already deferred inside restyleFromHook.
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if not frame or not frame.unit or not string.find(frame.unit, "nameplate", 1, true) then
                            return
                        end
                        local parent = frame:GetParent()
                        if parent and parent.UnitFrame == frame then
                            restyleFromHook(parent)
                        end
                    end)
                else
                    if not frame or not frame.unit or not string.find(frame.unit, "nameplate", 1, true) then
                        return
                    end
                    local parent = frame:GetParent()
                    if parent and parent.UnitFrame == frame then
                        restyleFromHook(parent)
                    end
                end
            end)
        end
    end
    if (not plateAddHookInstalled) and _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(1, ensureNamePlateHooks)
    end
end

local function ApplyNameplateStyling(self)
    ensureNamePlateHooks()
    applyToAllActive(self)
end

addon:RegisterComponentInitializer(function(self)
    local nameplatesComponent = Component:New({
        id = "nameplatesUnit",
        name = "Unit Nameplates",
        settings = {
            textName = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 14,
                style = "OUTLINE",
            }, ui = { hidden = true }},
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyNameplateStyling,
    })

    self:RegisterComponent(nameplatesComponent)
end)

