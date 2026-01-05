local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

panel.UnitFramesSections = panel.UnitFramesSections or {}
local shared = panel.UnitFramesShared or {}

local sectionOrder = shared.sectionOrder or {
    "root",
    "health",
    "power",
    "classresource",
    "portrait",
    "cast",
    "buffs",
    "misc_focus",
    "visibility",
    "misc_player",
    -- ToT-specific sections (only render for ufToT)
    "tot_root",
    "tot_health",
    "tot_power",
    "tot_portrait",
    "tot_nametext",
}

local function createContext(componentId, title)
    if shared.createContext then
        return shared.createContext(componentId, title)
    end
    return {
        addon = addon,
        panel = panel,
        componentId = componentId,
        title = title,
    }
end

local function createUFRenderer(componentId, title)
    local ctx = createContext(componentId, title)
    local function render()
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then return end

        local init = {}
        for _, key in ipairs(sectionOrder) do
            local builder = panel.UnitFramesSections and panel.UnitFramesSections[key]
            if builder then builder(ctx, init) end
        end

        if right.SetTitle then
            right:SetTitle(title or componentId)
        end
        right:Display(init)
    end

    return { mode = "list", render = render, componentId = componentId }
end

function panel.RenderUFPlayer() return createUFRenderer("ufPlayer", "Player") end
function panel.RenderUFTarget() return createUFRenderer("ufTarget", "Target") end
function panel.RenderUFFocus()  return createUFRenderer("ufFocus",  "Focus")  end
function panel.RenderUFPet()    return createUFRenderer("ufPet",    "Pet")    end
function panel.RenderUFToT()    return createUFRenderer("ufToT",    "Target of Target") end
function panel.RenderUFBoss()   return createUFRenderer("ufBoss",   "Boss") end

panel.UnitFramesInit = panel.UnitFramesInit or function() end
panel.UnitFramesInit()

return createUFRenderer

