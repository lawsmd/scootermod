local addonName, addon = ...
addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

local createComponentRenderer = panel.builders and panel.builders.createComponentRenderer

local function renderPRDComponent(componentId)
    return createComponentRenderer(componentId)()
end

function panel.RenderPRDGlobal()        return renderPRDComponent("prdGlobal") end
function panel.RenderPRDHealth()        return renderPRDComponent("prdHealth") end
function panel.RenderPRDPower()         return renderPRDComponent("prdPower") end
function panel.RenderPRDClassResource() return renderPRDComponent("prdClassResource") end
