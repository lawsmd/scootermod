local addonName, addon = ...
addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

local createComponentRenderer = panel.builders and panel.builders.createComponentRenderer

-- Cooldown Manager / tracked components
function panel.RenderEssentialCooldowns() return createComponentRenderer("essentialCooldowns")() end
function panel.RenderUtilityCooldowns()  return createComponentRenderer("utilityCooldowns")()  end
function panel.RenderTrackedBars()       return createComponentRenderer("trackedBars")()       end
function panel.RenderTrackedBuffs()      return createComponentRenderer("trackedBuffs")()      end
function panel.RenderSCTDamage()         return createComponentRenderer("sctDamage")()         end
function panel.RenderSCTHealing()        return createComponentRenderer("sctHealing")()        end
function panel.RenderBuffs()             return createComponentRenderer("buffs")()             end
function panel.RenderDebuffs()           return createComponentRenderer("debuffs")()           end
