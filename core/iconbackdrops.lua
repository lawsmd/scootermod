local addonName, addon = ...

addon.IconBackdrops = addon.IconBackdrops or {}
local IconBackdrops = addon.IconBackdrops

-- Definitions intentionally exclude any ABE-branded assets. We only reference Blizzard atlases.
local ICON_BACKDROP_DEFINITIONS = {
    { key = "blizzardBg",        label = "Default Blizzard Backdrop",    type = "atlas", atlas = "UI-HUD-ActionBar-IconFrame-Background", order = 10 },
    { key = "blizzardSlot",      label = "Default Blizzard Slot Art",    type = "atlas", atlas = "UI-HUD-ActionBar-IconFrame-Slot",       order = 20 },
    { key = "cdmShadow",         label = "Cooldown Manager Shadow",      type = "atlas", atlas = "UI-CooldownManager-OORshadow",            order = 30 },

    { key = "blankColor",        label = "Blank Color",                  type = "atlas", atlas = "UI-Frame-IconMask",                        order = 100 },
    { key = "blankSquare",       label = "Blank Color Square",           type = "atlas", atlas = "SquareMask",                               order = 110, inset = 2 },

    { key = "plunderstormBg",    label = "Plunderstorm",                 type = "atlas", atlas = "plunderstorm-actionbar-slot-background",  order = 200 },
    { key = "forgeBg",           label = "Forge",                        type = "atlas", atlas = "Forge-ColorSwatchBackground",             order = 210 },
    { key = "rewardBg",          label = "Reward",                       type = "atlas", atlas = "UI_bg_npcreward",                          order = 220 },
    { key = "relicforgeBg",      label = "Relicforge",                   type = "atlas", atlas = "Relicforge-Slot-background",              order = 230 },

    { key = "metal",             label = "Metal Style",                  type = "atlas", atlas = "FontStyle_Metal",                          order = 300, inset = 2 },
    { key = "parchment",         label = "Parchment Style",              type = "atlas", atlas = "FontStyle_Parchment",                      order = 310, inset = 2 },
    { key = "legion",            label = "Legion Style",                 type = "atlas", atlas = "FontStyle_Legion",                         order = 320, inset = 2 },
    { key = "ironhorde",         label = "IronHorde Style",              type = "atlas", atlas = "FontStyle_IronHordeMetal",                 order = 330, inset = 2 },
    { key = "blueGradient",      label = "Blue Gradient Style",          type = "atlas", atlas = "FontStyle_BlueGradient",                   order = 340, inset = 2 },
    { key = "shipFollower",      label = "Ship Follower",                type = "atlas", atlas = "ShipMission_ShipFollower-EquipmentBG",     order = 350 },
}

local STYLE_MAP = {}
for _, def in ipairs(ICON_BACKDROP_DEFINITIONS) do
    STYLE_MAP[def.key] = def
end

local function resolveStyleKey(key)
    if not key or key == "" then return "blizzardBg" end
    if STYLE_MAP[key] then return key end
    -- Legacy passthrough: allow specifying atlas:<name>
    if type(key) == "string" then
        local atlas = key:match("^atlas:(.+)")
        if atlas and atlas ~= "" then
            local alias = "atlas_" .. atlas
            if not STYLE_MAP[alias] then
                STYLE_MAP[alias] = { key = alias, label = atlas, type = "atlas", atlas = atlas, order = 999 }
            end
            return alias
        end
    end
    return key
end

function IconBackdrops.GetStyle(key)
    return STYLE_MAP[resolveStyleKey(key)]
end

function IconBackdrops.GetDropdownEntries()
    local entries = {}
    for _, def in ipairs(ICON_BACKDROP_DEFINITIONS) do
        entries[#entries + 1] = { value = def.key, text = def.label, order = def.order or 500 }
    end
    table.sort(entries, function(a, b)
        local oa = a.order or 500; local ob = b.order or 500
        if oa == ob then return (a.text or "") < (b.text or "") end
        return oa < ob
    end)

    if Settings and Settings.CreateControlTextContainer then
        local c = Settings.CreateControlTextContainer()
        for _, e in ipairs(entries) do c:Add(e.value, e.text) end
        return c:GetData()
    end
    return entries
end

-- Apply the chosen backdrop to an Action Button. Operates on the stock SlotBackground region when present.
function addon.ApplyIconBackdropToActionButton(button, styleKey, opacity, extraInset, tintColor)
    if not button then return end
    local bg = button.SlotBackground
    if not bg then
        -- Fallback: try to find a region with a common name
        if button.GetRegions then
            for _, r in ipairs({ button:GetRegions() }) do
                local n = r and r.GetName and r:GetName() or ""
                if r and r.GetObjectType and r:GetObjectType() == "Texture" and n:find("SlotBackground", 1, true) then
                    bg = r; break
                end
            end
        end
    end
    if not bg or not bg.SetAtlas then return end

    local def = IconBackdrops.GetStyle(styleKey) or IconBackdrops.GetStyle("blizzardBg")
    if def and def.type == "atlas" and def.atlas then
        pcall(bg.SetAtlas, bg, def.atlas)
    end

    -- Re-anchor with optional insets to shrink the visual a few pixels inside the button
    local inset = 0
    if def and def.inset then
        if type(def.inset) == "number" then
            inset = def.inset
        elseif type(def.inset) == "table" then
            -- If a table was provided, prefer uniform number when present; otherwise use left/right/top/bottom
            inset = tonumber(def.inset.uniform) or 0
        end
    end
    inset = inset + (tonumber(extraInset) or 0)
    if inset > 8 then inset = 8 elseif inset < -8 then inset = -8 end
    local left  = inset
    local right = -inset
    local top   = -inset
    local bottom= inset
    if def and type(def.inset) == "table" and not def.inset.uniform then
        left   = tonumber(def.inset.left)   or left
        right  = -(tonumber(def.inset.right) or (-right))
        top    = -(tonumber(def.inset.top)  or (-top))
        bottom = tonumber(def.inset.bottom) or bottom
    end
    if bg.ClearAllPoints and bg.SetPoint then
        pcall(bg.ClearAllPoints, bg)
        pcall(bg.SetPoint, bg, "TOPLEFT", button, "TOPLEFT", left, top)
        pcall(bg.SetPoint, bg, "BOTTOMRIGHT", button, "BOTTOMRIGHT", right, bottom)
    end

    local a = tonumber(opacity) or 100
    if a < 1 then a = 1 elseif a > 100 then a = 100 end
    if bg.SetAlpha then pcall(bg.SetAlpha, bg, a / 100) end
    if bg.SetDesaturated then pcall(bg.SetDesaturated, bg, false) end
    do
        local r, g, b = 1, 1, 1
        if type(tintColor) == "table" then
            r = tonumber(tintColor[1]) or 1
            g = tonumber(tintColor[2]) or 1
            b = tonumber(tintColor[3]) or 1
        end
        if bg.SetVertexColor then pcall(bg.SetVertexColor, bg, r, g, b) end
    end
    if bg.Show then pcall(bg.Show, bg) end
end

function addon.BuildIconBackdropOptionsContainer()
    if addon.IconBackdrops and addon.IconBackdrops.GetDropdownEntries then
        return addon.IconBackdrops.GetDropdownEntries()
    end
    local create = Settings and Settings.CreateControlTextContainer
    if create then
        local c = create(); c:Add("blizzardBg", "Default Blizzard Backdrop"); return c:GetData()
    end
    return { { value = "blizzardBg", text = "Default Blizzard Backdrop" } }
end


