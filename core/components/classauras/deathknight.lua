-- classauras/deathknight.lua - Death Knight class aura definitions
local addonName, addon = ...

local CA = addon.ClassAuras

--------------------------------------------------------------------------------
-- Unholy DoTs: shared state and helpers
--------------------------------------------------------------------------------

local VIRULENT_PLAGUE_ID = 191587
local DREAD_PLAGUE_ID    = 1240996
local EXCLAMATION_PATH   = "Interface\\AddOns\\Scoot\\media\\animations\\Exclamation"
local WHITE8X8           = "Interface\\BUTTONS\\WHITE8X8"

local DOT_COLORS = {
    virulentPlague = {0.0, 0.8, 0.2, 1.0},
    dreadPlague    = {0.8, 0.1, 0.1, 1.0},
}

-- Per-icon visual state (indexed by auraId)
local iconState = {}  -- [auraId] = { swipeFrame, cooldown, excFrame, excAnim, borderEdges, isSquare }

-- Alert suppression: prevent exclamation for 2s after combat start or target change
local alertSuppressed = false

-- Forward declaration
local ApplyDotIconStyle, ApplyDotIconSize, UpdateSwipeTexture

--------------------------------------------------------------------------------
-- Icon construction helpers
--------------------------------------------------------------------------------

local function CreateSquareBorders(parent, size)
    local edges = {}
    local thickness = 2
    local r, g, b, a = 0, 0, 0, 1

    edges.Top = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    edges.Top:SetColorTexture(r, g, b, a)
    edges.Top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    edges.Top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    edges.Top:SetHeight(thickness)

    edges.Bottom = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    edges.Bottom:SetColorTexture(r, g, b, a)
    edges.Bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    edges.Bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    edges.Bottom:SetHeight(thickness)

    edges.Left = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    edges.Left:SetColorTexture(r, g, b, a)
    edges.Left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -thickness)
    edges.Left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, thickness)
    edges.Left:SetWidth(thickness)

    edges.Right = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    edges.Right:SetColorTexture(r, g, b, a)
    edges.Right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -thickness)
    edges.Right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, thickness)
    edges.Right:SetWidth(thickness)

    return edges
end

local function ShowBorders(edges)
    if not edges then return end
    for _, tex in pairs(edges) do tex:Show() end
end

local function HideBorders(edges)
    if not edges then return end
    for _, tex in pairs(edges) do tex:Hide() end
end

local function CreateCooldownSwipe(container)
    local swipeFrame = CreateFrame("Frame", nil, container)
    swipeFrame:SetAllPoints(container)
    swipeFrame:SetFrameLevel(container:GetFrameLevel() + 2)

    local cooldown = CreateFrame("Cooldown", nil, swipeFrame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(swipeFrame)
    cooldown:SetReverse(true)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetSwipeColor(0, 0, 0, 1.0)

    return swipeFrame, cooldown
end

local function CreateExclamation(container)
    local excFrame = CreateFrame("Frame", nil, container)
    excFrame:SetFrameLevel(container:GetFrameLevel() + 5)
    excFrame:SetSize(16, 16)
    excFrame:Hide()

    local tex = excFrame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(EXCLAMATION_PATH)
    tex:SetAllPoints(excFrame)

    local ag = tex:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1.0)
    fade:SetToAlpha(0.0)
    fade:SetDuration(0.5)

    return excFrame, ag
end

local function PositionExclamation(excFrame, container, position)
    if not excFrame then return end
    excFrame:ClearAllPoints()
    if position == "LEFT" then
        excFrame:SetPoint("RIGHT", container, "LEFT", -2, 0)
    elseif position == "RIGHT" then
        excFrame:SetPoint("LEFT", container, "RIGHT", 2, 0)
    elseif position == "TOP" then
        excFrame:SetPoint("BOTTOM", container, "TOP", 0, 2)
    elseif position == "BOTTOM" then
        excFrame:SetPoint("TOP", container, "BOTTOM", 0, -2)
    else -- "ON"
        excFrame:SetPoint("CENTER", container, "CENTER", 0, 0)
    end
end

--------------------------------------------------------------------------------
-- Icon style application
--------------------------------------------------------------------------------

ApplyDotIconStyle = function(auraId, state, spellId, color, db, isActive)
    local is = iconState[auraId]
    if not is then return end

    local texElem
    for _, elem in ipairs(state.elements) do
        if elem.type == "texture" then texElem = elem; break end
    end
    if not texElem then return end

    local isSquare = (db and db.dotIconStyle) or false

    if isSquare then
        if isActive then
            texElem.widget:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
            texElem.widget:SetDesaturated(false)
        else
            texElem.widget:SetColorTexture(0.15, 0.15, 0.15, 1.0)
        end
        ShowBorders(is.borderEdges)
        is.cooldown:SetSwipeTexture(WHITE8X8)
        is.cooldown:SetSwipeColor(0, 0, 0, 1.0)
        is.isSquare = true
    else
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
        if ok and tex then
            texElem.widget:SetTexture(tex)
            texElem.widget:SetDesaturated(not isActive)
        end
        HideBorders(is.borderEdges)
        is.cooldown:SetSwipeColor(0, 0, 0, 1.0)
        is.isSquare = false
    end
end

ApplyDotIconSize = function(auraId, state, db)
    local is = iconState[auraId]
    if not is then return end

    local size = 16
    local container = state.container
    container:SetSize(size, size)

    for _, elem in ipairs(state.elements) do
        if elem.type == "texture" then
            elem.widget:SetSize(size, size)
            elem.widget:ClearAllPoints()
            elem.widget:SetAllPoints(container)
            elem.widget:Show()
        end
    end

    is.swipeFrame:SetAllPoints(container)
    is.cooldown:SetAllPoints(is.swipeFrame)

    local excSize = tonumber(db and db.exclamationSize) or 16
    is.excFrame:SetSize(excSize, excSize)
end

UpdateSwipeTexture = function(auraId, spellId, db)
    local is = iconState[auraId]
    if not is then return end
    local isSquare = (db and db.dotIconStyle) or false
    if isSquare then
        is.cooldown:SetSwipeTexture(WHITE8X8)
        is.cooldown:SetSwipeColor(0, 0, 0, 1.0)
    else
        is.cooldown:SetSwipeColor(0, 0, 0, 1.0)
    end
end

--------------------------------------------------------------------------------
-- Lifecycle callbacks (called by core.lua hooks)
--------------------------------------------------------------------------------

local function OnContainerCreated(auraId, state)
    local container = state.container
    local swipeFrame, cooldown = CreateCooldownSwipe(container)
    local excFrame, excAnim = CreateExclamation(container)
    local borderEdges = CreateSquareBorders(container, 16)
    HideBorders(borderEdges)

    iconState[auraId] = {
        swipeFrame = swipeFrame,
        cooldown = cooldown,
        excFrame = excFrame,
        excAnim = excAnim,
        borderEdges = borderEdges,
        isSquare = false,
    }
end

local function GetDotContext(auraId)
    local auraDef = CA._registry[auraId]
    if not auraDef then return nil, nil, nil end
    local primaryId = auraDef.anchorTo or auraId
    local comp = addon.Components and addon.Components["classAura_" .. primaryId]
    local db = comp and comp.db
    if not db then
        comp = addon.Components and addon.Components["classAura_" .. auraId]
        db = comp and comp.db
    end
    local spellId = auraDef.auraSpellId
    local color = DOT_COLORS[auraId] or {1, 1, 1, 1}
    return db, spellId, color
end

local function OnAuraFound(auraId, state)
    local is = iconState[auraId]
    if not is then return end

    -- Hide exclamation
    is.excAnim:Stop()
    is.excFrame:Hide()

    -- Re-apply correct icon texture (active appearance)
    local db, spellId, color = GetDotContext(auraId)
    ApplyDotIconStyle(auraId, state, spellId, color, db, true)

    -- Update cooldown swipe from auraTracking (if enabled)
    local swipeEnabled = db and db.dotSwipeEnable
    if swipeEnabled then
        local tracked = CA._auraTracking[auraId]
        if tracked then
            local ok, durObj = pcall(C_UnitAuras.GetAuraDuration, tracked.unit, tracked.auraInstanceID)
            if ok and durObj then
                local startTime = durObj:GetStartTime()
                local totalDur = durObj:GetTotalDuration()
                pcall(is.cooldown.SetCooldown, is.cooldown, startTime, totalDur)
            end
        end
    else
        is.cooldown:Clear()
    end
end

local function OnAuraMissing(auraId, state)
    local is = iconState[auraId]
    if not is then return end

    -- Clear swipe
    is.cooldown:Clear()

    -- Apply inactive appearance
    local db, spellId, color = GetDotContext(auraId)
    ApplyDotIconStyle(auraId, state, spellId, color, db, false)

    -- Check if exclamation is enabled
    local auraDef = CA._registry[auraId]
    if not auraDef then return end

    -- Read exclamationEnable from VP's DB (primary controls both)
    local primaryId = auraDef.anchorTo or auraId
    local primaryAura = CA._registry[primaryId]
    local primaryDb
    if primaryAura then
        local comp = addon.Components and addon.Components["classAura_" .. primaryId]
        primaryDb = comp and comp.db
    end
    if not primaryDb then
        local comp = addon.Components and addon.Components["classAura_" .. auraId]
        primaryDb = comp and comp.db
    end

    local excEnabled = primaryDb and (primaryDb.exclamationEnable ~= false)
    if not excEnabled or not InCombatLockdown() or alertSuppressed then
        is.excFrame:Hide()
        is.excAnim:Stop()
        return
    end

    local position = (primaryDb and primaryDb.exclamationPosition) or "ON"
    PositionExclamation(is.excFrame, state.container, position)
    is.excFrame:Show()
    is.excAnim:Play()
end

local function OnEditModeEnter(auraId, state)
    local is = iconState[auraId]
    if not is then return end
    -- Show exclamation as static preview (no blink)
    is.excAnim:Stop()
    is.excFrame:Show()

    local auraDef = CA._registry[auraId]
    local primaryId = (auraDef and auraDef.anchorTo) or auraId
    local primaryAura = CA._registry[primaryId]
    local primaryDb
    if primaryAura then
        local comp = addon.Components and addon.Components["classAura_" .. primaryId]
        primaryDb = comp and comp.db
    end
    if not primaryDb then
        local comp = addon.Components and addon.Components["classAura_" .. auraId]
        primaryDb = comp and comp.db
    end
    local position = (primaryDb and primaryDb.exclamationPosition) or "ON"
    PositionExclamation(is.excFrame, state.container, position)
end

local function OnEditModeExit(auraId, state)
    local is = iconState[auraId]
    if not is then return end
    is.excAnim:Stop()
    is.excFrame:Hide()
end

--------------------------------------------------------------------------------
-- Full styling pass (called from customRenderer's set handlers and init)
--------------------------------------------------------------------------------

local function ApplyFullDotStyling(auraId, spellId, color)
    local state = CA._activeAuras[auraId]
    if not state then return end
    local auraDef = CA._registry[auraId]
    if not auraDef then return end

    -- Read DB from primary aura (VP) for shared settings
    local primaryId = auraDef.anchorTo or auraId
    local primaryAura = CA._registry[primaryId]
    local db
    if primaryAura then
        local comp = addon.Components and addon.Components["classAura_" .. primaryId]
        db = comp and comp.db
    end
    if not db then
        local comp = addon.Components and addon.Components["classAura_" .. auraId]
        db = comp and comp.db
    end

    local isActive = CA._auraTracking[auraId] ~= nil
    ApplyDotIconStyle(auraId, state, spellId, color, db, isActive)
    ApplyDotIconSize(auraId, state, db)
    UpdateSwipeTexture(auraId, spellId, db)

    -- Position exclamation
    local is = iconState[auraId]
    if is then
        local position = (db and db.exclamationPosition) or "ON"
        PositionExclamation(is.excFrame, state.container, position)
    end
end

-- Re-apply styling for both VP and DP
local function RefreshBothDots()
    ApplyFullDotStyling("virulentPlague", VIRULENT_PLAGUE_ID, {0.0, 0.8, 0.2, 1.0})
    ApplyFullDotStyling("dreadPlague", DREAD_PLAGUE_ID, {0.8, 0.1, 0.1, 1.0})
end

--------------------------------------------------------------------------------
-- Custom Settings Renderer for Virulent Plague (controls both dots)
--------------------------------------------------------------------------------

local function DotCustomRenderer(contentFrame, inner, h, getSetting, componentId, builder)
    -- Enable toggle
    inner:AddToggle({
        key = "enabled",
        label = "Enable Unholy DoTs Tracker",
        description = "Track Virulent Plague and Dread Plague on your target with dual icons, cooldown swipes, and missing-debuff alerts.",
        emphasized = true,
        get = function() return getSetting("enabled") or false end,
        set = function(val)
            h.setAndApply("enabled", val)
            -- Sync DP enable state
            local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
            if dpComp and dpComp.db then
                dpComp.db.enabled = val
                local dpAura = CA._registry["dreadPlague"]
                if dpAura then
                    local dpState = CA._activeAuras["dreadPlague"]
                    if dpState then
                        if val then
                            dpState.container:Show()
                        else
                            dpState.container:Hide()
                        end
                    end
                    CA.ScanAura(dpAura)
                end
            end
            RefreshBothDots()
        end,
    })

    -- Tabbed section
    local tabs = {}
    local buildContent = {}

    -- Tab 1: Icons
    table.insert(tabs, { key = "icons", label = "Icons" })
    buildContent.icons = function(tabContent, tabBuilder)
        tabBuilder:AddToggle({
            label = "Squares",
            description = "Show colored squares instead of spell icons.",
            get = function() return getSetting("dotIconStyle") or false end,
            set = function(v)
                h.setAndApply("dotIconStyle", v)
                RefreshBothDots()
                builder:DeferredRefreshAll()
            end,
        })

        tabBuilder:AddToggle({
            label = "Cooldown Swipe",
            description = "Show a cooldown swipe animation over the icon as the debuff expires.",
            get = function() return getSetting("dotSwipeEnable") or false end,
            set = function(v)
                h.setAndApply("dotSwipeEnable", v)
                RefreshBothDots()
            end,
        })

        tabBuilder:Finalize()
    end

    -- Tab 2: Layout
    table.insert(tabs, { key = "layout", label = "Layout" })
    buildContent.layout = function(tabContent, tabBuilder)
        tabBuilder:AddSelector({
            label = "Orientation",
            values = { horizontal = "Horizontal", vertical = "Vertical" },
            order = { "horizontal", "vertical" },
            get = function() return getSetting("dotOrientation") or "horizontal" end,
            set = function(v)
                h.setAndApply("dotOrientation", v)
                -- Re-apply anchor linkage
                local dpAura = CA._registry["dreadPlague"]
                if dpAura then
                    local dpState = CA._activeAuras["dreadPlague"]
                    if dpState then
                        dpState.container:ClearAllPoints()
                        local padding = tonumber(getSetting("dotPadding")) or 4
                        local vpState = CA._activeAuras["virulentPlague"]
                        if vpState then
                            if v == "vertical" then
                                dpState.container:SetPoint("BOTTOM", vpState.container, "TOP", 0, padding)
                            else
                                dpState.container:SetPoint("RIGHT", vpState.container, "LEFT", -padding, 0)
                            end
                        end
                    end
                end
            end,
        })

        tabBuilder:AddSlider({
            label = "Padding",
            description = "Gap between the two icons.",
            min = 0, max = 20, step = 1,
            get = function() return getSetting("dotPadding") or 4 end,
            set = function(v)
                h.setAndApply("dotPadding", v)
                -- Re-apply anchor linkage
                local dpAura = CA._registry["dreadPlague"]
                if dpAura then
                    local dpState = CA._activeAuras["dreadPlague"]
                    if dpState then
                        dpState.container:ClearAllPoints()
                        local orientation = getSetting("dotOrientation") or "horizontal"
                        local vpState = CA._activeAuras["virulentPlague"]
                        if vpState then
                            if orientation == "vertical" then
                                dpState.container:SetPoint("BOTTOM", vpState.container, "TOP", 0, v)
                            else
                                dpState.container:SetPoint("RIGHT", vpState.container, "LEFT", -v, 0)
                            end
                        end
                    end
                end
            end,
            minLabel = "0", maxLabel = "20",
        })

        tabBuilder:Finalize()
    end

    -- Tab 3: Alert
    table.insert(tabs, { key = "alert", label = "Alert" })
    buildContent.alert = function(tabContent, tabBuilder)
        tabBuilder:AddToggle({
            label = "Exclamation Alert",
            description = "Show a blinking exclamation mark when a DoT is missing from the target.",
            get = function() return getSetting("exclamationEnable") ~= false end,
            set = function(val)
                h.setAndApply("exclamationEnable", val)
                RefreshBothDots()
            end,
        })

        tabBuilder:AddSelector({
            label = "Position",
            description = "Where the exclamation appears relative to each icon.",
            values = { ON = "On Icon", LEFT = "Left", RIGHT = "Right", TOP = "Top", BOTTOM = "Bottom" },
            order = { "ON", "LEFT", "RIGHT", "TOP", "BOTTOM" },
            get = function() return getSetting("exclamationPosition") or "ON" end,
            set = function(v)
                h.setAndApply("exclamationPosition", v)
                RefreshBothDots()
            end,
        })

        tabBuilder:AddSlider({
            label = "Alert Size",
            description = "Size of the exclamation mark icon.",
            min = 8, max = 48, step = 1,
            get = function() return getSetting("exclamationSize") or 16 end,
            set = function(v)
                h.setAndApply("exclamationSize", v)
                RefreshBothDots()
            end,
            minLabel = "8", maxLabel = "48",
        })

        tabBuilder:Finalize()
    end

    -- Tab 4: Sizing
    table.insert(tabs, { key = "sizing", label = "Sizing" })
    buildContent.sizing = function(tabContent, tabBuilder)
        tabBuilder:AddSlider({
            label = "Scale",
            description = "Overall scale of the aura frame (25-200%).",
            min = 25, max = 200, step = 5,
            get = function() return getSetting("scale") or 100 end,
            set = function(v)
                h.setAndApply("scale", v)
                -- Sync DP scale
                local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
                if dpComp and dpComp.db then
                    dpComp.db.scale = v
                end
                local dpAura = CA._registry["dreadPlague"]
                if dpAura then
                    local dpState = CA._activeAuras["dreadPlague"]
                    if dpState then
                        dpState.container:SetScale(math.max(v / 100, 0.25))
                    end
                end
            end,
            minLabel = "25%", maxLabel = "200%",
        })

        tabBuilder:Finalize()
    end

    -- Tab 5: Visibility
    table.insert(tabs, { key = "visibility", label = "Visibility" })
    buildContent.visibility = function(tabContent, tabBuilder)
        tabBuilder:AddDescription(
            "Priority: With Target > In Combat > Out of Combat",
            { color = {1, 0.82, 0}, fontSize = 13, topPadding = 4, bottomPadding = 2 }
        )

        tabBuilder:AddSlider({
            label = "Opacity With Target",
            min = 0, max = 100, step = 1,
            get = function() return getSetting("opacityWithTarget") or 100 end,
            set = function(v)
                h.setAndApply("opacityWithTarget", v)
                local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
                if dpComp and dpComp.db then dpComp.db.opacityWithTarget = v end
            end,
            minLabel = "Hidden", maxLabel = "100%",
        })

        tabBuilder:AddSlider({
            label = "Opacity in Combat",
            min = 0, max = 100, step = 1,
            get = function() return getSetting("opacityInCombat") or 100 end,
            set = function(v)
                h.setAndApply("opacityInCombat", v)
                local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
                if dpComp and dpComp.db then dpComp.db.opacityInCombat = v end
            end,
            minLabel = "Hidden", maxLabel = "100%",
        })

        tabBuilder:AddSlider({
            label = "Opacity Out of Combat",
            min = 0, max = 100, step = 1,
            get = function() return getSetting("opacityOutOfCombat") or 100 end,
            set = function(v)
                h.setAndApply("opacityOutOfCombat", v)
                local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
                if dpComp and dpComp.db then dpComp.db.opacityOutOfCombat = v end
            end,
            minLabel = "Hidden", maxLabel = "100%",
        })

        tabBuilder:Finalize()
    end

    inner:AddTabbedSection({
        tabs = tabs,
        componentId = componentId,
        sectionKey = "dotTabs",
        buildContent = buildContent,
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Aura Registration
--------------------------------------------------------------------------------

CA.RegisterAuras("DEATHKNIGHT", {
    -- Lesser Ghoul Stacks (existing)
    {
        id = "lesserGhoulStacks",
        label = "Lesser Ghoul Stacks",
        auraSpellId = 1254252,
        cdmSpellId = 1254252,
        cdmBorrow = true,
        unit = "player",
        filter = "HELPFUL|PLAYER",
        enableLabel = "Enable Lesser Ghoul Stacks Tracker",
        enableDescription = "Show your Lesser Ghoul stacks as a dedicated, customizable aura.",
        editModeName = "Lesser Ghoul Stacks",
        defaultPosition = { point = "CENTER", x = 0, y = -200 },
        defaultBarColor = { 0.0, 0.8, 0.2, 1.0 },  -- unholy green
        elements = {
            { type = "text",    key = "stacks", source = "applications", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",   customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelZombie", defaultSize = { 32, 32 } },
            { type = "bar",     key = "stackBar", source = "applications", maxValue = 8, fillMode = "fill", defaultSize = { 120, 12 } },
        },
        settings = CA.DefaultSettings({
            textColor = { 0.0, 0.8, 0.2, 1.0 },
            barForegroundTint = { 0.0, 0.8, 0.2, 1.0 },
        }),
    },

    -- Virulent Plague (primary Unholy DoT)
    {
        id = "virulentPlague",
        label = "Unholy DoTs",
        auraSpellId = VIRULENT_PLAGUE_ID,
        cdmBorrow = true,
        unit = "target",
        filter = "HARMFUL|PLAYER",
        keepVisible = true,
        enableLabel = "Enable Unholy DoTs Tracker",
        enableDescription = "Track Virulent Plague and Dread Plague as dual icons with cooldown swipes and missing-debuff alerts.",
        editModeName = "Unholy DoTs",
        defaultPosition = { point = "CENTER", x = 10, y = -200 },
        elements = {
            { type = "texture", key = "icon", defaultSize = { 16, 16 } },
        },
        customIconHandling = true,
        onContainerCreated = OnContainerCreated,
        onAuraFound = OnAuraFound,
        onAuraMissing = OnAuraMissing,
        onEditModeEnter = OnEditModeEnter,
        onEditModeExit = OnEditModeExit,
        customRenderer = DotCustomRenderer,
        settings = CA.DefaultSettings({
            -- Novel settings for the dual-dot system
            dotOrientation      = { type = "addon", default = "horizontal" },
            dotPadding          = { type = "addon", default = 4 },
            dotIconStyle        = { type = "addon", default = false },
            dotSwipeEnable      = { type = "addon", default = false },
            exclamationEnable   = { type = "addon", default = true },
            exclamationPosition = { type = "addon", default = "ON" },
            exclamationSize     = { type = "addon", default = 16 },
        }),
    },

    -- Dread Plague (secondary Unholy DoT, anchored to VP)
    {
        id = "dreadPlague",
        label = "Dread Plague",
        auraSpellId = DREAD_PLAGUE_ID,
        cdmBorrow = true,
        unit = "target",
        filter = "HARMFUL|PLAYER",
        keepVisible = true,
        anchorTo = "virulentPlague",
        skipEditMode = true,
        hideFromSettings = true,
        defaultPosition = { point = "CENTER", x = -10, y = -200 },
        elements = {
            { type = "texture", key = "icon", defaultSize = { 16, 16 } },
        },
        customIconHandling = true,
        onContainerCreated = OnContainerCreated,
        onAuraFound = OnAuraFound,
        onAuraMissing = OnAuraMissing,
        onEditModeEnter = OnEditModeEnter,
        onEditModeExit = OnEditModeExit,
        settings = CA.DefaultSettings({}),
    },
})

--------------------------------------------------------------------------------
-- Deferred initialization: apply dot visuals after containers are created
--------------------------------------------------------------------------------

local function HideAllExclamations()
    for _, auraId in ipairs({"virulentPlague", "dreadPlague"}) do
        local is = iconState[auraId]
        if is then
            is.excAnim:Stop()
            is.excFrame:Hide()
        end
    end
end

local function RescanBothDots()
    local vpAura = CA._registry["virulentPlague"]
    local dpAura = CA._registry["dreadPlague"]
    if vpAura then CA.ScanAura(vpAura) end
    if dpAura then CA.ScanAura(dpAura) end
end

local function SuppressAlerts()
    alertSuppressed = true
    HideAllExclamations()
    C_Timer.After(2, function()
        alertSuppressed = false
        if InCombatLockdown() then
            RescanBothDots()
        end
    end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- Defer to run after core.lua's InitializeContainers + RebuildAll (0.5s timer)
        C_Timer.After(0.8, function()
            -- Ensure DP mirrors VP's enabled state
            local vpComp = addon.Components and addon.Components["classAura_virulentPlague"]
            local dpComp = addon.Components and addon.Components["classAura_dreadPlague"]
            if vpComp and vpComp.db and dpComp and dpComp.db then
                dpComp.db.enabled = vpComp.db.enabled

            end

            RefreshBothDots()
            RescanBothDots()
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: suppress alerts for 2s, then rescan
        SuppressAlerts()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: immediately hide all exclamation alerts
        alertSuppressed = false
        HideAllExclamations()
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- New target: suppress alerts for 2s, then rescan
        if InCombatLockdown() then
            SuppressAlerts()
        end
    end
end)
