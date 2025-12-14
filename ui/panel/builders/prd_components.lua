local addonName, addon = ...
addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

local createComponentRenderer = panel.builders and panel.builders.createComponentRenderer

local function isPRDEnabled()
    return addon.FeatureToggles and addon.FeatureToggles.enablePRD
end

local function renderPRDComponent(componentId)
    if isPRDEnabled() then
        return createComponentRenderer(componentId)()
    end
    return { mode = "list", render = function() end, componentId = componentId }
end

function panel.RenderPRDGlobal()        return renderPRDComponent("prdGlobal") end
function panel.RenderPRDHealth()        return renderPRDComponent("prdHealth") end
function panel.RenderPRDPower()         return renderPRDComponent("prdPower") end
function panel.RenderPRDClassResource() return renderPRDComponent("prdClassResource") end
