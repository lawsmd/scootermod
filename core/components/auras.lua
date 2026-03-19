local addonName, addon = ...
local Util = addon.ComponentsUtil
local CleanupIconBorderAttachments = Util.CleanupIconBorderAttachments
local ClampOpacity = Util.ClampOpacity
local ToggleDefaultIconOverlay = Util.ToggleDefaultIconOverlay
local PlayerInCombat = Util.PlayerInCombat

-- Weak-key lookup tables to avoid writing properties to Blizzard frames
-- (which would taint them and cause secret value errors during Edit Mode operations)
local auraState = setmetatable({}, { __mode = "k" })  -- frame/fs/tex/border -> state table

-- Config version tracking: skip re-styling auras when config hasn't changed (OPT-01)
local configVersions = {}  -- componentId -> integer

-- Atlas lookup for debuff border overlays (matches AuraUtil.GetDebuffDisplayInfoTable)
local DEBUFF_BORDER_ATLASES = {
    ["Magic"]   = { basic = "ui-debuff-border-magic-noicon",   dispel = "ui-debuff-border-magic-icon" },
    ["Curse"]   = { basic = "ui-debuff-border-curse-noicon",   dispel = "ui-debuff-border-curse-icon" },
    ["Disease"] = { basic = "ui-debuff-border-disease-noicon", dispel = "ui-debuff-border-disease-icon" },
    ["Poison"]  = { basic = "ui-debuff-border-poison-noicon",  dispel = "ui-debuff-border-poison-icon" },
    ["Bleed"]   = { basic = "ui-debuff-border-bleed-noicon",   dispel = "ui-debuff-border-bleed-icon" },
    ["None"]    = { basic = "ui-debuff-border-default-noicon" },
}

-- Cache debuff type per aura button (weak-key, populated by AuraUtil.SetAuraBorderAtlas hook)
local debuffTypeCache = setmetatable({}, { __mode = "k" })

function addon.BumpAuraConfigVersion(componentId)
    configVersions[componentId] = (configVersions[componentId] or 0) + 1
end

-- Helper to get or create state for a frame/object
local function getState(obj)
    if not obj then return nil end
    if not auraState[obj] then
        auraState[obj] = {}
    end
    return auraState[obj]
end

local function setRegionVisible(region, visible)
    if not region then return end
    if visible then
        if region.Show then region:Show() end
        if region.SetAlpha then region:SetAlpha(1) end
    else
        if region.Hide then region:Hide() end
        if region.SetAlpha then region:SetAlpha(0) end
    end
end

-- Creates an addon-owned overlay texture on the aura button (C-level, no Lua table taint).
-- Stores in auraState[aura][stateKey] for reuse.
local function ensureOverlayTexture(aura, stateKey, drawLayer, sublevel)
    local state = getState(aura)
    if not state then return nil end
    if state[stateKey] then return state[stateKey] end
    local ok, tex = pcall(aura.CreateTexture, aura, nil, drawLayer or "OVERLAY", nil, sublevel or 1)
    if not ok or not tex then return nil end
    state[stateKey] = tex
    return tex
end

-- Sizes and positions the debuff border overlay to match the non-square icon shape.
-- Uses cached dispel type from AuraUtil.SetAuraBorderAtlas hook to select the correct atlas.
local function updateDebuffBorderOverlay(aura, state, iconWidth, iconHeight)
    if not state or not state.debuffBorderOverlay then return end
    local overlay = state.debuffBorderOverlay
    -- DebuffBorder XML: 40x40 for 30x30 icon
    local bw = iconWidth * (40 / 30)
    local bh = iconHeight * (40 / 30)
    overlay:SetSize(bw, bh)
    overlay:ClearAllPoints()
    local icon = aura.Icon or aura.icon or aura.IconTexture
    overlay:SetPoint("CENTER", icon or aura, "CENTER")
    -- Apply atlas from cached debuff type (prefer actual atlas captured from Blizzard)
    local cached = debuffTypeCache[aura]
    local atlas = cached and cached.actualAtlas
    if not atlas then
        local dt = cached and cached.dispelType or "None"
        local sd = cached and cached.showDispelType
        local entry = DEBUFF_BORDER_ATLASES[dt] or DEBUFF_BORDER_ATLASES["None"]
        atlas = (sd and entry.dispel) or entry.basic
    end
    if atlas then
        pcall(overlay.SetAtlas, overlay, atlas, false)
    end
    overlay:Show()
end

-- Sizes and positions the temp enchant border overlay to match the non-square icon shape.
local function updateTempEnchantBorderOverlay(aura, state, iconWidth, iconHeight)
    if not state or not state.tempEnchantBorderOverlay then return end
    local overlay = state.tempEnchantBorderOverlay
    -- TempEnchantBorder XML: 32x32 for 30x30 icon
    local bw = iconWidth * (32 / 30)
    local bh = iconHeight * (32 / 30)
    overlay:SetSize(bw, bh)
    overlay:ClearAllPoints()
    local icon = aura.Icon or aura.icon or aura.IconTexture
    overlay:SetPoint("CENTER", icon or aura, "CENTER")
    pcall(overlay.SetTexture, overlay, "Interface\\Buttons\\UI-TempEnchant-Border")
    overlay:Show()
end

function addon.ApplyAuraFrameVisualsFor(component, forceRestyle)
    if not component or (component.id ~= "buffs" and component.id ~= "debuffs") then return end

    local frameName = component.frameName
    if not frameName or type(frameName) ~= "string" then return end

    local frame = _G[frameName]
    if not frame or not frame.AuraContainer then return end

    -- Zero-Touch: if still on proxy DB, do nothing
    if component._ScootDBProxy and component.db == component._ScootDBProxy then return end

    local db = component.db
    if not db then return end
    local settings = component.settings or {}

    if type(db.textDuration) ~= "table" and type(db.textCooldown) == "table" then
        local src = db.textCooldown
        local copy = {}
        if type(src.fontFace) == "string" then copy.fontFace = src.fontFace end
        if src.size ~= nil then copy.size = src.size end
        if type(src.style) == "string" then copy.style = src.style end
        if type(src.color) == "table" then
            copy.color = { src.color[1], src.color[2], src.color[3], src.color[4] }
        end
        if type(src.offset) == "table" then
            copy.offset = { x = src.offset.x, y = src.offset.y }
        end
        if next(copy) ~= nil then
            db.textDuration = copy
        end
    end

    local defaultFace = (select(1, GameFontNormal:GetFont()))

    local function ensureTextConfig(key)
        local cfg = db[key]
        if type(cfg) ~= "table" then
            cfg = {}
            db[key] = cfg
        end
        cfg.offset = cfg.offset or {}
        return cfg
    end

    local function enforceTextColor(fs, key, state)
        state = state or getState(fs)
        if not fs or not state or state.colorApplying then return end
        local cfg = db[key]
        if type(cfg) ~= "table" then return end
        local color = cfg.color
        if type(color) ~= "table" or not fs.SetTextColor then return end
        state.colorApplying = true
        fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        state.colorApplying = nil
    end

    local function ensureTextHooks(fs, key)
        if not fs or not hooksecurefunc then return end
        local state = getState(fs)
        if not state then return end
        if state.textHooked then return end
        state.textHooked = true

        local callback = function()
            local st = auraState[fs]
            if not st or st.colorApplying then return end
            enforceTextColor(fs, key, st)
        end

        if type(fs.SetTextColor) == "function" then hooksecurefunc(fs, "SetTextColor", callback) end
        if type(fs.SetVertexColor) == "function" then hooksecurefunc(fs, "SetVertexColor", callback) end
        if type(fs.SetFontObject) == "function" then hooksecurefunc(fs, "SetFontObject", callback) end
    end

    local function ensureDefaultColor(cfg, fs)
        if cfg.color ~= nil or not (fs and fs.GetTextColor) then return end
        local ok, r, g, b, a = pcall(fs.GetTextColor, fs)
        if not ok then return end
        if issecretvalue(r) then return end
        local alpha = a
        if alpha == nil and fs.GetAlpha then
            local ok2, alphaVal = pcall(fs.GetAlpha, fs)
            if ok2 and not issecretvalue(alphaVal) then
                alpha = alphaVal
            end
        end
        cfg.color = { r or 1, g or 1, b or 1, alpha or 1 }
    end

    local function captureDefaultAnchor(fs, fallbackRelTo)
        if not fs then return nil end
        local state = getState(fs)
        if not state then return nil end
        if not state.defaultAnchor then
            local ok, point, relTo, relPoint, x, y = pcall(fs.GetPoint, fs, 1)
            if not ok or issecretvalue(point) then
                point, relTo, relPoint, x, y = "CENTER", fallbackRelTo, "CENTER", 0, 0
            end
            if not point then
                point, relPoint, x, y = "CENTER", "CENTER", 0, 0
            end
            if relTo == nil then relTo = fallbackRelTo end
            state.defaultAnchor = {
                point = point or "CENTER",
                relTo = relTo,
                relPoint = relPoint or point or "CENTER",
                x = x or 0,
                y = y or 0,
            }
        end
        return state.defaultAnchor
    end

    local function applyAuraText(fs, key, defaultSize, fallbackRelTo)
        if not fs or not fs.SetFont then return end
        local cfg = ensureTextConfig(key)
        ensureDefaultColor(cfg, fs)
        ensureTextHooks(fs, key)
        local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
        local size = tonumber(cfg.size) or defaultSize
        local style = cfg.style or "OUTLINE"
        pcall(fs.SetDrawLayer, fs, "OVERLAY", 10)
        if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, style) else fs:SetFont(face, size, style) end
        local state = getState(fs)
        local color = cfg.color
        if color and fs.SetTextColor then
            if state then state.colorApplying = true end
            fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
            if state then state.colorApplying = nil end
        end
        local anchor = captureDefaultAnchor(fs, fallbackRelTo)
        if anchor and fs.ClearAllPoints and fs.SetPoint then
            local ox = tonumber(cfg.offset.x) or 0
            local oy = tonumber(cfg.offset.y) or 0
            fs:ClearAllPoints()
            fs:SetPoint(
                anchor.point or "CENTER",
                anchor.relTo or fallbackRelTo,
                anchor.relPoint or anchor.point or "CENTER",
                (anchor.x or 0) + ox,
                (anchor.y or 0) + oy
            )
        end
        enforceTextColor(fs, key, state)
    end

    local componentId = component and component.id

    local function applyCollapseButtonVisibility()
        if componentId ~= "buffs" then return end

        local collapseButton = frame.CollapseAndExpandButton
        if not collapseButton then return end

        local hideTextures = not not db.hideCollapseButton
        local unique = {}
        local textures = {}

        local function addTexture(tex)
            if tex and not unique[tex] then
                unique[tex] = true
                table.insert(textures, tex)
            end
        end

        addTexture(collapseButton.NormalTexture)
        addTexture(collapseButton.HighlightTexture)
        if collapseButton.GetNormalTexture then
            addTexture(collapseButton:GetNormalTexture())
        end
        if collapseButton.GetHighlightTexture then
            addTexture(collapseButton:GetHighlightTexture())
        end

        for _, tex in ipairs(textures) do
            if tex and tex.SetAlpha then
                local state = getState(tex)
                if hideTextures then
                    if state and state.originalAlpha == nil then
                        local alpha = tex:GetAlpha()
                        state.originalAlpha = alpha ~= nil and alpha or 1
                    end
                    tex:SetAlpha(0)
                else
                    local alpha = state and state.originalAlpha
                    tex:SetAlpha(alpha ~= nil and alpha or 1)
                    if state then state.originalAlpha = nil end
                end
            end
        end
    end

    applyCollapseButtonVisibility()

    if componentId == "buffs" then
        local collapseButton = frame.CollapseAndExpandButton
        local btnState = collapseButton and getState(collapseButton)
        if collapseButton and btnState and not btnState.hideTexturesHooked then
            btnState.hideTexturesHooked = true
            local function refreshCollapseButton()
                applyCollapseButtonVisibility()
            end
            if hooksecurefunc then
                if collapseButton.SetNormalTexture then
                    hooksecurefunc(collapseButton, "SetNormalTexture", refreshCollapseButton)
                end
                if collapseButton.SetNormalAtlas then
                    hooksecurefunc(collapseButton, "SetNormalAtlas", refreshCollapseButton)
                end
                if collapseButton.SetHighlightTexture then
                    hooksecurefunc(collapseButton, "SetHighlightTexture", refreshCollapseButton)
                end
                if collapseButton.SetHighlightAtlas then
                    hooksecurefunc(collapseButton, "SetHighlightAtlas", refreshCollapseButton)
                end
            end
            if collapseButton.HookScript then
                collapseButton:HookScript("OnShow", refreshCollapseButton)
            end
        end
    end

    -- Calculate icon dimensions from ratio
    local ratio = tonumber(db.tallWideRatio) or 0
    local width, height
    if addon.IconRatio then
        width, height = addon.IconRatio.GetDimensionsForComponent(componentId, ratio)
    else
        -- Fallback if IconRatio not loaded
        width, height = 30, 30
    end

    local borderEnabled = not not db.borderEnable
    local borderStyle = tostring(db.borderStyle or "square")
    if borderStyle == "none" then
        borderStyle = "square"
        if db then db.borderStyle = borderStyle end
    end
    local borderThickness = tonumber(db.borderThickness) or 1
    if borderThickness < 1 then borderThickness = 1 elseif borderThickness > 8 then borderThickness = 8 end
    local borderTintEnabled = not not db.borderTintEnable
    local borderTintColor = db.borderTintColor
    local tintColor
    if borderTintEnabled and type(borderTintColor) == "table" then
        tintColor = {
            borderTintColor[1] or 1,
            borderTintColor[2] or 1,
            borderTintColor[3] or 1,
            borderTintColor[4] or 1,
        }
    end

    local function setDefaultAuraBorderVisible(aura, visible)
        if not aura then return end
        setRegionVisible(aura.IconBorder, visible)
        setRegionVisible(aura.Border, visible)
        setRegionVisible(aura.DebuffBorder, visible)
        setRegionVisible(aura.TempEnchantBorder, visible)
    end

    local function clearCustomBorder(icon)
        if not icon then return end
        CleanupIconBorderAttachments(icon)
    end

    local auraCollections = {}
    local function addCollection(list)
        if type(list) == "table" then
            table.insert(auraCollections, list)
        end
    end

    addCollection(frame.auraFrames)
    if frame.AuraContainer and type(frame.AuraContainer.auraFrames) == "table" then
        addCollection(frame.AuraContainer.auraFrames)
    end
    if type(frame.tempEnchantFrames) == "table" then
        addCollection(frame.tempEnchantFrames)
    end
    if frame.TempEnchantContainer and type(frame.TempEnchantContainer.auraFrames) == "table" then
        addCollection(frame.TempEnchantContainer.auraFrames)
    end
    if type(frame.privateAuraAnchors) == "table" then
        for _, anchor in pairs(frame.privateAuraAnchors) do
            if anchor then
                if type(anchor.auraFrames) == "table" then
                    addCollection(anchor.auraFrames)
                end
                if anchor.AuraContainer and type(anchor.AuraContainer.auraFrames) == "table" then
                    addCollection(anchor.AuraContainer.auraFrames)
                end
            end
        end
    end

    local currentVersion = configVersions[componentId] or 0

    local processed = {}
    for _, collection in ipairs(auraCollections) do
        for _, aura in ipairs(collection) do
            if aura and not processed[aura] then
                processed[aura] = true
                local icon = aura.Icon or aura.icon or aura.IconTexture

                -- OPT-01: Skip auras already styled for the current config version
                local auraVState = getState(aura)
                if forceRestyle or not auraVState or auraVState.lastStyledVersion ~= currentVersion then

                    if icon and icon.SetSize and width and height then
                        icon:SetSize(width, height)
                        -- Calculate texture coordinates to crop instead of stretch
                        local aspectRatio = width / height
                        local left, right, top, bottom = 0, 1, 0, 1
                        if aspectRatio > 1.0 then
                            -- Wider than tall - crop top/bottom
                            local cropAmount = 1.0 - (1.0 / aspectRatio)
                            local cropOffset = cropAmount / 2.0
                            top = cropOffset
                            bottom = 1.0 - cropOffset
                        elseif aspectRatio < 1.0 then
                            -- Taller than wide - crop left/right
                            local cropAmount = 1.0 - aspectRatio
                            local cropOffset = cropAmount / 2.0
                            left = cropOffset
                            right = 1.0 - cropOffset
                        end
                        if icon.SetTexCoord then
                            pcall(icon.SetTexCoord, icon, left, right, top, bottom)
                        end
                    end
                    if icon then
                        -- OPT-01 Opt3: Border param cache — skip ApplyIconBorderStyle when params match
                        if borderEnabled then
                            setDefaultAuraBorderVisible(aura, false)
                            local iconState = getState(icon)
                            local lb = iconState and iconState.lastBorder
                            local defaultThick = settings.borderThickness and settings.borderThickness.default or 1
                            if not lb
                                or lb.style ~= borderStyle
                                or lb.thickness ~= borderThickness
                                or lb.tintEnabled ~= borderTintEnabled
                                or lb.version ~= currentVersion
                                or (borderTintEnabled and tintColor and (
                                    not lb.tintR or lb.tintR ~= tintColor[1]
                                    or lb.tintG ~= tintColor[2]
                                    or lb.tintB ~= tintColor[3]
                                    or lb.tintA ~= tintColor[4]
                                ))
                            then
                                addon.ApplyIconBorderStyle(icon, borderStyle, {
                                    thickness = borderThickness,
                                    color = tintColor,
                                    tintEnabled = borderTintEnabled,
                                    db = db,
                                    thicknessKey = "borderThickness",
                                    tintColorKey = "borderTintColor",
                                    defaultThickness = defaultThick,
                                })
                                if iconState then
                                    iconState.lastBorder = {
                                        style = borderStyle,
                                        thickness = borderThickness,
                                        tintEnabled = borderTintEnabled,
                                        tintR = tintColor and tintColor[1],
                                        tintG = tintColor and tintColor[2],
                                        tintB = tintColor and tintColor[3],
                                        tintA = tintColor and tintColor[4],
                                        version = currentVersion,
                                    }
                                end
                            end
                        else
                            setRegionVisible(aura.IconBorder, true)
                            setRegionVisible(aura.Border, true)
                            if componentId ~= "debuffs" then
                                setRegionVisible(aura.DebuffBorder, true)
                                setRegionVisible(aura.TempEnchantBorder, true)
                            end
                            clearCustomBorder(icon)
                            local iconState = getState(icon)
                            if iconState then iconState.lastBorder = nil end
                        end
                    end

                    -- Debuff/TempEnchant border overlay management
                    -- Runs after the border section to have final say on border visibility
                    if componentId == "debuffs" and icon then
                        local auraSt = getState(aura)
                        -- Skip private aura anchors — borders managed by game client
                        local isPrivateAnchor = false
                        local okAnc, isAnc = pcall(function() return aura.isAuraAnchor end)
                        if okAnc and isAnc and not issecretvalue(isAnc) then
                            isPrivateAnchor = true
                        end

                        if isPrivateAnchor then
                            -- Private aura anchor: don't create overlays, hide any stale ones
                            if auraSt and auraSt.debuffBorderOverlay then auraSt.debuffBorderOverlay:Hide() end
                            if auraSt and auraSt.tempEnchantBorderOverlay then auraSt.tempEnchantBorderOverlay:Hide() end
                        elseif ratio ~= 0 and not borderEnabled then
                            -- Hide BOTH Blizzard borders — we're replacing with a properly-sized overlay
                            setRegionVisible(aura.DebuffBorder, false)
                            setRegionVisible(aura.TempEnchantBorder, false)

                            -- Detect which border type via aura.auraType (set by Blizzard's UpdateAuraType)
                            local isTempEnchant = false
                            local okType, aType = pcall(function() return aura.auraType end)
                            if okType and aType and not issecretvalue(aType) and aType == "TempEnchant" then
                                isTempEnchant = true
                            end

                            if isTempEnchant then
                                -- Temp enchant aura: overlay TempEnchantBorder
                                ensureOverlayTexture(aura, "tempEnchantBorderOverlay", "OVERLAY", 1)
                                updateTempEnchantBorderOverlay(aura, auraSt, width, height)
                                if auraSt and auraSt.debuffBorderOverlay then auraSt.debuffBorderOverlay:Hide() end
                            else
                                -- Regular debuff: overlay DebuffBorder
                                ensureOverlayTexture(aura, "debuffBorderOverlay", "OVERLAY", 1)
                                updateDebuffBorderOverlay(aura, auraSt, width, height)
                                if auraSt and auraSt.tempEnchantBorderOverlay then auraSt.tempEnchantBorderOverlay:Hide() end
                            end
                        else
                            -- Square icons or custom border active: restore Blizzard borders, hide overlays
                            if not borderEnabled then
                                setRegionVisible(aura.DebuffBorder, true)
                                setRegionVisible(aura.TempEnchantBorder, true)
                            end
                            if auraSt and auraSt.debuffBorderOverlay then auraSt.debuffBorderOverlay:Hide() end
                            if auraSt and auraSt.tempEnchantBorderOverlay then auraSt.tempEnchantBorderOverlay:Hide() end
                        end
                    end

                    local stacksFS = aura.Count or aura.count or aura.Applications
                    if stacksFS and stacksFS.GetObjectType and stacksFS:GetObjectType() == "FontString" then
                        applyAuraText(stacksFS, "textStacks", 16, aura)
                    end

                    local durationFS = aura.Duration
                    if durationFS and durationFS.GetObjectType and durationFS:GetObjectType() == "FontString" then
                        applyAuraText(durationFS, "textDuration", 16, aura)
                    end

                    if auraVState then
                        auraVState.lastStyledVersion = currentVersion
                    end

                end -- version check
            end
        end
    end
end

-- OPT-15: Lightweight opacity-only refresh for RefreshOpacityState dispatch.
-- Avoids full ApplyAuraFrameStyling (icon iteration, borders, text, version bump)
-- when only the container alpha needs updating.
local function RefreshAuraOpacity(self)
    local frame = _G[self.frameName]
    if not frame then return end
    local container = frame.AuraContainer or frame
    if not container or not container.SetAlpha then return end

    local baseOpacity = ClampOpacity(self.db.opacity, 50)
    local oocOpacity = ClampOpacity(self.db.opacityOutOfCombat or baseOpacity, 1)
    local tgtOpacity = ClampOpacity(self.db.opacityWithTarget or baseOpacity, 1)
    local hasTarget = (UnitExists and UnitExists("target")) and true or false
    local appliedOpacity = hasTarget and tgtOpacity or (PlayerInCombat() and baseOpacity or oocOpacity)
    pcall(container.SetAlpha, container, appliedOpacity / 100)
end

local function ApplyAuraFrameStyling(self)
    local frame = _G[self.frameName]
    if not frame or not frame.AuraContainer then return end

    local frameState = getState(frame)
    if hooksecurefunc and frameState and not frameState.auraHooked then
        local componentId = self.id
        hooksecurefunc(frame, "UpdateAuraButtons", function()
            if addon and addon.Components and addon.Components[componentId] and addon.ApplyAuraFrameVisualsFor then
                addon.ApplyAuraFrameVisualsFor(addon.Components[componentId], true)
            end
        end)
        frameState.auraHooked = true
    end

    -- Install global hook on AuraUtil.SetAuraBorderAtlas for debuff type tracking
    if not addon._DebuffBorderAtlasHookInstalled then
        addon._DebuffBorderAtlasHookInstalled = true
        if hooksecurefunc and AuraUtil and AuraUtil.SetAuraBorderAtlas then
            hooksecurefunc(AuraUtil, "SetAuraBorderAtlas", function(borderRegion, dispelType, showDispelType)
                pcall(function()
                    if not borderRegion or not borderRegion.GetParent then return end
                    local aura = borderRegion:GetParent()
                    if not aura then return end

                    -- Secret-safe: guard dispelType and showDispelType
                    local dt = "None"
                    if dispelType and not issecretvalue(dispelType) and type(dispelType) == "string" then
                        dt = dispelType
                    end
                    local sd = false
                    if showDispelType and not issecretvalue(showDispelType) then
                        sd = not not showDispelType
                    end

                    local cacheEntry = { dispelType = dt, showDispelType = sd }

                    -- Capture the actual atlas Blizzard set on the border region
                    local okAtlas, actualAtlas = pcall(borderRegion.GetAtlas, borderRegion)
                    if okAtlas and actualAtlas and not issecretvalue(actualAtlas) and type(actualAtlas) == "string" then
                        cacheEntry.actualAtlas = actualAtlas
                    end

                    debuffTypeCache[aura] = cacheEntry

                    -- Immediately update overlay atlas if it exists and is shown
                    local auraSt = auraState[aura]
                    if auraSt and auraSt.debuffBorderOverlay then
                        local okShown, shown = pcall(auraSt.debuffBorderOverlay.IsShown, auraSt.debuffBorderOverlay)
                        if okShown and shown then
                            local hookAtlas = cacheEntry.actualAtlas
                            if not hookAtlas then
                                local entry = DEBUFF_BORDER_ATLASES[dt] or DEBUFF_BORDER_ATLASES["None"]
                                hookAtlas = (sd and entry.dispel) or entry.basic
                            end
                            if hookAtlas then
                                pcall(auraSt.debuffBorderOverlay.SetAtlas, auraSt.debuffBorderOverlay, hookAtlas, false)
                            end
                        end
                        -- Per-button safety: hide Blizzard's border immediately when overlay is active
                        pcall(borderRegion.Hide, borderRegion)
                        pcall(borderRegion.SetAlpha, borderRegion, 0)
                    end
                end)
            end)
        end
    end

    -- OPT-01: Bump config version so ApplyStyling (profile switch, etc.) forces full re-style
    addon.BumpAuraConfigVersion(self.id)

    if addon and addon.ApplyAuraFrameVisualsFor then
        addon.ApplyAuraFrameVisualsFor(self)
    end

    local container = frame.AuraContainer or frame
    if container then
        local baseOpacity = ClampOpacity(self.db.opacity, 50)

        local oocOpacity = ClampOpacity(self.db.opacityOutOfCombat or baseOpacity, 1)

        local tgtOpacity = ClampOpacity(self.db.opacityWithTarget or baseOpacity, 1)

        local hasTarget = (UnitExists and UnitExists("target")) and true or false
        local appliedOpacity = hasTarget and tgtOpacity or (PlayerInCombat() and baseOpacity or oocOpacity)
        if container.SetAlpha then
            pcall(container.SetAlpha, container, appliedOpacity / 100)
        end
    end
end

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local buffs = Component:New({
        id = "buffs",
        name = "Buffs",
        frameName = "BuffFrame",
        settings = {
            orientation = { type = "editmode", default = "H", ui = {
                label = "Orientation", widget = "dropdown",
                values = { H = "Horizontal", V = "Vertical" },
                section = "Positioning", order = 1,
            }},
            iconWrap = { type = "editmode", default = "down", ui = {
                label = "Icon Wrap", widget = "dropdown",
                values = { down = "Down", up = "Up" },
                section = "Positioning", order = 2, dynamicValues = true,
            }},
            direction = { type = "editmode", default = "left", ui = {
                label = "Icon Direction", widget = "dropdown",
                values = { left = "Left", right = "Right" },
                section = "Positioning", order = 3, dynamicValues = true,
            }},
            iconPadding = { type = "editmode", default = 10, ui = {
                label = "Icon Padding", widget = "slider",
                min = 5, max = 15, step = 1,
                section = "Positioning", order = 4,
            }},
            iconLimit = { type = "editmode", default = 11, ui = {
                label = "Icon Limit", widget = "slider",
                min = 2, max = 32, step = 1,
                section = "Positioning", order = 5,
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider",
                min = -1000, max = 1000, step = 1,
                section = "Positioning", order = 6,
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider",
                min = -1000, max = 1000, step = 1,
                section = "Positioning", order = 7,
            }},
            iconSize = { type = "editmode", default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1,
            }},
            tallWideRatio = { type = "addon", default = 0, ui = {
                label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Sizing", order = 2,
                minLabel = "Wide", maxLabel = "Tall",
            }},
            borderEnable = { type = "addon", default = false, ui = {
                label = "Use Custom Border", widget = "checkbox", section = "Border", order = 1,
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2,
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3,
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 4,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 5,
            }},
            opacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 1,
            }},
            opacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 2,
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3,
            }},
            hideCollapseButton = { type = "addon", default = false, ui = {
                label = "Hide Expand/Collapse Button", widget = "checkbox", section = "Misc", order = 10,
            }},
            supportsText = { type = "addon", default = true },
        },
        supportsEmptyVisibilitySection = true,
        ApplyStyling = ApplyAuraFrameStyling,
        RefreshOpacity = RefreshAuraOpacity,
    })
    self:RegisterComponent(buffs)

    local debuffs = Component:New({
        id = "debuffs",
        name = "Debuffs",
        frameName = "DebuffFrame",
        settings = {
            orientation = { type = "editmode", default = "H", ui = {
                label = "Orientation", widget = "dropdown",
                values = { H = "Horizontal", V = "Vertical" },
                section = "Positioning", order = 1,
            }},
            iconWrap = { type = "editmode", default = "down", ui = {
                label = "Icon Wrap", widget = "dropdown",
                values = { down = "Down", up = "Up" },
                section = "Positioning", order = 2, dynamicValues = true,
            }},
            direction = { type = "editmode", default = "left", ui = {
                label = "Icon Direction", widget = "dropdown",
                values = { left = "Left", right = "Right" },
                section = "Positioning", order = 3, dynamicValues = true,
            }},
            iconPadding = { type = "editmode", default = 10, ui = {
                label = "Icon Padding", widget = "slider",
                min = 5, max = 15, step = 1,
                section = "Positioning", order = 4,
            }},
            iconLimit = { type = "editmode", default = 8, ui = {
                label = "Icon Limit", widget = "slider",
                min = 1, max = 16, step = 1,
                section = "Positioning", order = 5,
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider",
                min = -1000, max = 1000, step = 1,
                section = "Positioning", order = 6,
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider",
                min = -1000, max = 1000, step = 1,
                section = "Positioning", order = 7,
            }},
            iconSize = { type = "editmode", default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1,
            }},
            tallWideRatio = { type = "addon", default = 0, ui = {
                label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Sizing", order = 2,
                minLabel = "Wide", maxLabel = "Tall",
            }},
            opacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 1,
            }},
            opacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 2,
            }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 1, max = 100, step = 1, section = "Misc", order = 3,
            }},
            supportsText = { type = "addon", default = true },
        },
        supportsEmptyVisibilitySection = true,
        ApplyStyling = ApplyAuraFrameStyling,
        RefreshOpacity = RefreshAuraOpacity,
    })
    self:RegisterComponent(debuffs)
end)

