local addonName, addon = ...
local Util = addon.ComponentsUtil
local CleanupIconBorderAttachments = Util.CleanupIconBorderAttachments
local ClampOpacity = Util.ClampOpacity
local ToggleDefaultIconOverlay = Util.ToggleDefaultIconOverlay
local PlayerInCombat = Util.PlayerInCombat

function addon.ApplyAuraFrameVisualsFor(component)
    if not component or (component.id ~= "buffs" and component.id ~= "debuffs") then return end

    local frameName = component.frameName
    if not frameName or type(frameName) ~= "string" then return end

    local frame = _G[frameName]
    if not frame or not frame.AuraContainer then return end

    local db = component.db or {}
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

    local function enforceTextColor(fs, key)
        if not fs or fs._ScooterColorApplying then return end
        local cfg = db[key]
        if type(cfg) ~= "table" then return end
        local color = cfg.color
        if type(color) ~= "table" or not fs.SetTextColor then return end
        fs._ScooterColorApplying = true
        fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        fs._ScooterColorApplying = nil
    end

    local function ensureTextHooks(fs, key)
        if not fs or not hooksecurefunc then return end
        fs._ScooterTextHooks = fs._ScooterTextHooks or {}
        local function hookMethod(method)
            if fs._ScooterTextHooks[method] or type(fs[method]) ~= "function" then return end
            fs._ScooterTextHooks[method] = true
            hooksecurefunc(fs, method, function()
                if fs._ScooterColorApplying then return end
                enforceTextColor(fs, key)
            end)
        end
        hookMethod("SetTextColor")
        hookMethod("SetVertexColor")
        hookMethod("SetFontObject")
        hookMethod("SetFont")
        hookMethod("SetFormattedText")
        hookMethod("SetText")
    end

    local function ensureDefaultColor(cfg, fs)
        if cfg.color ~= nil or not (fs and fs.GetTextColor) then return end
        local r, g, b, a = fs:GetTextColor()
        local alpha = a
        if alpha == nil and fs.GetAlpha then
            alpha = fs:GetAlpha()
        end
        cfg.color = { r or 1, g or 1, b or 1, alpha or 1 }
    end

    local function captureDefaultAnchor(fs, fallbackRelTo)
        if not fs then return nil end
        if not fs._ScooterDefaultAnchor then
            local point, relTo, relPoint, x, y = fs:GetPoint(1)
            if not point then
                point, relPoint, x, y = "CENTER", "CENTER", 0, 0
            end
            if relTo == nil then relTo = fallbackRelTo end
            fs._ScooterDefaultAnchor = {
                point = point or "CENTER",
                relTo = relTo,
                relPoint = relPoint or point or "CENTER",
                x = x or 0,
                y = y or 0,
            }
        end
        return fs._ScooterDefaultAnchor
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
        local color = cfg.color
        if color and fs.SetTextColor then
            fs._ScooterColorApplying = true
            fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
            fs._ScooterColorApplying = nil
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
        enforceTextColor(fs, key)
    end

    local function resolveSettingValue(key)
        if db[key] ~= nil then return db[key] end
        local meta = settings[key]
        if type(meta) == "table" then
            return meta.default
        end
        return nil
    end

    local componentId = component and component.id

    local function applyCollapseButtonVisibility()
        if componentId ~= "buffs" then return end

        local collapseButton = frame.CollapseAndExpandButton
        if not collapseButton then return end

        local hideTextures = not not resolveSettingValue("hideCollapseButton")
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
                if hideTextures then
                    if tex._ScooterOriginalAlpha == nil then
                        local alpha = tex:GetAlpha()
                        tex._ScooterOriginalAlpha = alpha ~= nil and alpha or 1
                    end
                    tex:SetAlpha(0)
                else
                    local alpha = tex._ScooterOriginalAlpha
                    tex:SetAlpha(alpha ~= nil and alpha or 1)
                    tex._ScooterOriginalAlpha = nil
                end
            end
        end
    end

    applyCollapseButtonVisibility()

    if componentId == "buffs" then
        local collapseButton = frame.CollapseAndExpandButton
        if collapseButton and not collapseButton._ScooterHideTexturesHooked then
            collapseButton._ScooterHideTexturesHooked = true
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

    local width = tonumber(resolveSettingValue("iconWidth"))
    local height = tonumber(resolveSettingValue("iconHeight"))

    local borderEnabled = not not resolveSettingValue("borderEnable")
    local borderStyle = tostring(resolveSettingValue("borderStyle") or "square")
    if borderStyle == "none" then
        borderStyle = "square"
        if db then db.borderStyle = borderStyle end
    end
    local borderThickness = tonumber(resolveSettingValue("borderThickness")) or 1
    if borderThickness < 1 then borderThickness = 1 elseif borderThickness > 8 then borderThickness = 8 end
    local borderTintEnabled = not not resolveSettingValue("borderTintEnable")
    local borderTintColor = resolveSettingValue("borderTintColor")
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
        local targets = { aura.IconBorder, aura.Border, aura.DebuffBorder }
        for _, region in ipairs(targets) do
            if region then
                if visible then
                    if region.Show then region:Show() end
                    if region.SetAlpha then region:SetAlpha(1) end
                else
                    if region.Hide then region:Hide() end
                    if region.SetAlpha then region:SetAlpha(0) end
                end
            end
        end
    end

    local function clearCustomBorder(icon)
        if not icon then return end
        CleanupIconBorderAttachments(icon)
    end

    local function captureDebuffBorderDefaults(aura, icon)
        if componentId ~= "debuffs" or not aura or not icon then return end
        local border = aura.DebuffBorder
        if not border then return end

        if not icon._ScooterDebuffBaseWidth then
            local w = icon:GetWidth()
            if w and w > 0 then
                icon._ScooterDebuffBaseWidth = w
            end
        end
        if not icon._ScooterDebuffBaseHeight then
            local h = icon:GetHeight()
            if h and h > 0 then
                icon._ScooterDebuffBaseHeight = h
            end
        end
        if not border._ScooterDebuffBaseWidth then
            local bw = border:GetWidth()
            if bw and bw > 0 then
                border._ScooterDebuffBaseWidth = bw
            end
        end
        if not border._ScooterDebuffBaseHeight then
            local bh = border:GetHeight()
            if bh and bh > 0 then
                border._ScooterDebuffBaseHeight = bh
            end
        end
    end

    local function resizeDebuffBorder(aura, icon, targetWidth, targetHeight)
        if componentId ~= "debuffs" or not aura or not icon then return end
        local border = aura.DebuffBorder
        if not border or not border.SetSize then return end

        local baseIconWidth = icon._ScooterDebuffBaseWidth
        local baseIconHeight = icon._ScooterDebuffBaseHeight
        local baseBorderWidth = border._ScooterDebuffBaseWidth
        local baseBorderHeight = border._ScooterDebuffBaseHeight

        local width = targetWidth or icon:GetWidth()
        local height = targetHeight or icon:GetHeight()

        if baseIconWidth and baseIconWidth > 0 and baseBorderWidth then
            border:SetWidth(baseBorderWidth * (width / baseIconWidth))
        end
        if baseIconHeight and baseIconHeight > 0 and baseBorderHeight then
            border:SetHeight(baseBorderHeight * (height / baseIconHeight))
        end

        if border.ClearAllPoints and border.SetPoint and not border._ScooterDebuffAnchorLocked then
            border:ClearAllPoints()
            border:SetPoint("CENTER", icon, "CENTER")
            border._ScooterDebuffAnchorLocked = true
        end
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

    local processed = {}
    for _, collection in ipairs(auraCollections) do
        for _, aura in ipairs(collection) do
            if aura and not processed[aura] then
                processed[aura] = true
                local icon = aura.Icon or aura.icon or aura.IconTexture
                if icon then
                    captureDebuffBorderDefaults(aura, icon)
                end
                if icon and icon.SetSize and width and height then
                    icon:SetSize(width, height)
                end
                if icon then
                    resizeDebuffBorder(aura, icon, width, height)
                end
                if icon then
                    if borderEnabled then
                        setDefaultAuraBorderVisible(aura, false)
                        addon.ApplyIconBorderStyle(icon, borderStyle, {
                            thickness = borderThickness,
                            color = tintColor,
                            tintEnabled = borderTintEnabled,
                            db = db,
                            thicknessKey = "borderThickness",
                            tintColorKey = "borderTintColor",
                            defaultThickness = settings.borderThickness and settings.borderThickness.default or 1,
                        })
                    else
                        setDefaultAuraBorderVisible(aura, true)
                        clearCustomBorder(icon)
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
            end
        end
    end
end

local function ApplyAuraFrameStyling(self)
    local frame = _G[self.frameName]
    if not frame or not frame.AuraContainer then return end

    if hooksecurefunc and not frame._ScooterAuraHooked then
        local componentId = self.id
        hooksecurefunc(frame, "UpdateAuraButtons", function()
            if addon and addon.Components and addon.Components[componentId] and addon.ApplyAuraFrameVisualsFor then
                addon.ApplyAuraFrameVisualsFor(addon.Components[componentId])
            end
        end)
        frame._ScooterAuraHooked = true
    end

    if addon and addon.ApplyAuraFrameVisualsFor then
        addon.ApplyAuraFrameVisualsFor(self)
    end

    local container = frame.AuraContainer or frame
    if container then
        local baseRaw = self.db and self.db.opacity
        if baseRaw == nil and self.settings and self.settings.opacity then
            baseRaw = self.settings.opacity.default
        end
        local baseOpacity = ClampOpacity(baseRaw, 50)

        local oocRaw = self.db and self.db.opacityOutOfCombat
        if oocRaw == nil and self.settings and self.settings.opacityOutOfCombat then
            oocRaw = self.settings.opacityOutOfCombat.default
        end
        local oocOpacity = ClampOpacity(oocRaw or baseOpacity, 1)

        local tgtRaw = self.db and self.db.opacityWithTarget
        if tgtRaw == nil and self.settings and self.settings.opacityWithTarget then
            tgtRaw = self.settings.opacityWithTarget.default
        end
        local tgtOpacity = ClampOpacity(tgtRaw or baseOpacity, 1)

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
            iconWidth = { type = "addon", default = 30, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 48, step = 1, section = "Sizing", order = 2,
            }},
            iconHeight = { type = "addon", default = 30, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 48, step = 1, section = "Sizing", order = 3,
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
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.2, section = "Border", order = 5,
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
            iconWidth = { type = "addon", default = 30, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 48, step = 1, section = "Sizing", order = 2,
            }},
            iconHeight = { type = "addon", default = 30, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 48, step = 1, section = "Sizing", order = 3,
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
    })
    self:RegisterComponent(debuffs)
end)

