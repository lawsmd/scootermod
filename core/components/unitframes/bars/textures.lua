--------------------------------------------------------------------------------
-- bars/textures.lua
-- Texture application functions for unit frame status bars
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get utilities
local Utils = addon.BarsUtils

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = nil
local function ensureFS()
    if not FS then FS = addon.FrameState end
    return FS
end

local function getState(frame)
    local fs = ensureFS()
    return fs and fs.Get(frame) or nil
end

local function getProp(frame, key)
    local st = getState(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = getState(frame)
    if st then
        st[key] = value
    end
end

-- Create module namespace
addon.BarsTextures = addon.BarsTextures or {}
local Textures = addon.BarsTextures

--------------------------------------------------------------------------------
-- Mask Enforcement
--------------------------------------------------------------------------------

-- Ensure mask is properly applied to bar texture (re-apply after texture changes)
function Textures.ensureMaskOnBarTexture(bar, mask)
    if not bar or not mask or not bar.GetStatusBarTexture then return end
    local tex = bar:GetStatusBarTexture()
    if not tex or not tex.AddMaskTexture then return end
    -- Re-apply mask to the current texture instance and enforce Blizzard's texel snapping settings
    pcall(tex.AddMaskTexture, tex, mask)
    if tex.SetTexelSnappingBias then pcall(tex.SetTexelSnappingBias, tex, 0) end
    if tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
    if tex.SetHorizTile then pcall(tex.SetHorizTile, tex, false) end
    if tex.SetVertTile then pcall(tex.SetVertTile, tex, false) end
    if tex.SetTexCoord then pcall(tex.SetTexCoord, tex, 0, 1, 0, 1) end
end

--------------------------------------------------------------------------------
-- Status Bar Texture Application
--------------------------------------------------------------------------------

-- Apply texture and color to a status bar (health/power/cast)
-- @param bar: The StatusBar frame
-- @param textureKey: Texture key from settings (or "default")
-- @param colorMode: "default", "custom", "class", "texture"
-- @param tint: Color table {r, g, b, a} for custom color mode
-- @param unitForClass: Unit to get class color from
-- @param barKind: "health", "power", "altpower", or "cast"
-- @param unitForPower: Unit to get power color from
-- @param combatSafe: If true, allows application during combat (for visual-only changes)
function Textures.applyToBar(bar, textureKey, colorMode, tint, unitForClass, barKind, unitForPower, combatSafe)
    if not bar or type(bar.GetStatusBarTexture) ~= "function" then return end

    -- Combat safety: touching protected StatusBars (SetStatusBarTexture / SetVertexColor / CreateTexture)
    -- during combat can taint the execution context and later cause unrelated protected calls to be blocked.
    -- Callers should queue a post-combat reapply instead.
    --
    -- Exception: some callers (e.g., Cast Bar visual-only refresh) intentionally re-apply ONLY
    -- cosmetic texture/color changes during combat to keep styling persistent while avoiding
    -- combat-unsafe layout operations. Those callers may pass combatSafe=true.
    if not combatSafe and InCombatLockdown and InCombatLockdown() then
        return
    end
    
    -- Power bars with default texture + default color: be completely hands-off.
    -- Blizzard dynamically updates power bar texture AND vertex color when power type changes
    -- (e.g., Druid switching between Mana/Energy forms). If we touch ANYTHING here, we risk
    -- overwriting Blizzard's correctly-set state with our stale captured values. By returning
    -- early, we let Blizzard's native system handle everything.
    local isDefaultTexture = (textureKey == nil or textureKey == "" or textureKey == "default")
    local isDefaultColor = (colorMode == nil or colorMode == "" or colorMode == "default")
    if (barKind == "power" or barKind == "altpower") and isDefaultTexture and isDefaultColor then
        return
    end
    
    local tex = bar:GetStatusBarTexture()
    -- Capture original once
    if not getProp(bar, "ufOrigCaptured") then
        if tex and tex.GetAtlas then
            local ok, atlas = pcall(tex.GetAtlas, tex)
            if ok and atlas then setProp(bar, "ufOrigAtlas", atlas) end
        end
        if tex and tex.GetTexture then
            local ok, path = pcall(tex.GetTexture, tex)
            if ok and path then
                -- Some Blizzard status bars use atlases; GetAtlas may return nil while GetTexture returns the atlas token.
                -- Prefer treating such strings as atlases when possible to avoid spritesheet rendering on restore.
                local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(path) ~= nil
                if isAtlas then
                    local existingAtlas = getProp(bar, "ufOrigAtlas")
                    if not existingAtlas then setProp(bar, "ufOrigAtlas", path) end
                else
                    setProp(bar, "ufOrigPath", path)
                end
            end
        end
        if tex and tex.GetVertexColor then
            local ok, r, g, b, a = pcall(tex.GetVertexColor, tex)
            if ok then setProp(bar, "ufOrigVertex", { r or 1, g or 1, b or 1, a or 1 }) end
        end
        setProp(bar, "ufOrigCaptured", true)
    end

    local isCustom = type(textureKey) == "string" and textureKey ~= "" and textureKey ~= "default"
    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(textureKey)
    if isCustom and resolvedPath then
        if bar.SetStatusBarTexture then
            -- Mark this write so any SetStatusBarTexture hook can ignore it (avoid recursion)
            setProp(bar, "ufInternalTextureWrite", true)
            pcall(bar.SetStatusBarTexture, bar, resolvedPath)
            setProp(bar, "ufInternalTextureWrite", nil)
        end
        -- Re-fetch the current texture after swapping to ensure subsequent operations target the new texture
        tex = bar:GetStatusBarTexture()
        local r, g, b, a = 1, 1, 1, 1
        if colorMode == "custom" and type(tint) == "table" then
            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
        elseif colorMode == "class" then
            if addon.GetClassColorRGB then
                local cr, cg, cb = addon.GetClassColorRGB(unitForClass or "player")
                r, g, b, a = cr or 1, cg or 1, cb or 1, 1
            end
        elseif colorMode == "texture" then
            -- Apply white (no tint) to preserve texture's original colors
            r, g, b, a = 1, 1, 1, 1
        elseif colorMode == "default" or colorMode == "power" then
            -- When using a custom texture, "Default" should tint to the stock bar color
            -- ("power" is a legacy alias for "default" on power bars)
            if barKind == "cast" then
                -- Stock cast bar yellow from CastingBarFrame mixin.
                r, g, b, a = 1.0, 0.7, 0.0, 1
            elseif barKind == "health" and addon.GetDefaultHealthColorRGB then
                local hr, hg, hb = addon.GetDefaultHealthColorRGB()
                r, g, b, a = hr or 0, hg or 1, hb or 0, 1
            elseif (barKind == "power" or barKind == "altpower") and addon.GetPowerColorRGB then
                -- Power and Alternate Power bars both use the player's power color for Default.
                local pr, pg, pb = addon.GetPowerColorRGB(unitForPower or unitForClass or "player")
                r, g, b, a = pr or 1, pg or 1, pb or 1, 1
            else
                local ov = getProp(bar, "ufOrigVertex")
                if type(ov) == "table" then r, g, b, a = ov[1] or 1, ov[2] or 1, ov[3] or 1, ov[4] or 1 end
            end
        end
        if tex and tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
    else
        -- Default texture path. If the user selected Class/Custom color, avoid restoring
        -- Blizzard's green/colored atlas because vertex-color multiplies and distorts hues.
        -- Instead, use a neutral white fill and apply the desired color; keep the stock mask.
        local r, g, b, a = 1, 1, 1, 1
        local wantsNeutral = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class")
        if wantsNeutral then
            if colorMode == "custom" then
                r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
            elseif colorMode == "class" and addon.GetClassColorRGB then
                local cr, cg, cb = addon.GetClassColorRGB(unitForClass or "player")
                r, g, b, a = cr or 1, cg or 1, cb or 1, 1
            end
            if tex and tex.SetColorTexture then pcall(tex.SetColorTexture, tex, 1, 1, 1, 1) end
        else
            -- Default color: restore Blizzard's original fill
            -- Note: Power bars with default texture + default color already returned early above.
            if getProp(bar, "ufOrigCaptured") then
                local origAtlas = getProp(bar, "ufOrigAtlas")
                local origPath = getProp(bar, "ufOrigPath")
                if origAtlas then
                    if tex and tex.SetAtlas then
                        pcall(tex.SetAtlas, tex, origAtlas, true)
                    elseif bar.SetStatusBarTexture then
                        setProp(bar, "ufInternalTextureWrite", true)
                        pcall(bar.SetStatusBarTexture, bar, origAtlas)
                        setProp(bar, "ufInternalTextureWrite", nil)
                    end
                elseif origPath then
                    local treatAsAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(origPath) ~= nil
                    if treatAsAtlas and tex and tex.SetAtlas then
                        pcall(tex.SetAtlas, tex, origPath, true)
                    elseif bar.SetStatusBarTexture then
                        setProp(bar, "ufInternalTextureWrite", true)
                        pcall(bar.SetStatusBarTexture, bar, origPath)
                        setProp(bar, "ufInternalTextureWrite", nil)
                    end
                end
            end
            if barKind == "cast" then
                -- Use Blizzard's stock cast bar yellow as the default color.
                -- Based on Blizzard_CastingBarFrame.lua (CastingBarFrameMixin).
                r, g, b, a = 1.0, 0.7, 0.0, 1
            else
                local ov = getProp(bar, "ufOrigVertex") or {1,1,1,1}
                r, g, b, a = ov[1] or 1, ov[2] or 1, ov[3] or 1, ov[4] or 1
            end
        end
        if tex and tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
    end
end

--------------------------------------------------------------------------------
-- Background Texture Application
--------------------------------------------------------------------------------

-- Apply background texture and color to a bar
function Textures.applyBackgroundToBar(bar, backgroundTextureKey, backgroundColorMode, backgroundTint, backgroundOpacity, unit, barKind)
    if not bar then return end

    -- Combat safety: creating/modifying textures on protected frames during combat can taint.
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    
    -- Ensure we have a background texture frame at an appropriate sublevel so it appears
    -- behind the status bar fill but remains visible for cast bars.
    --
    -- For generic unit frame bars (health/power), we keep the background very low in the
    -- BACKGROUND stack (-8) so any stock art sits above it if present.
    --
    -- For CastingBarFrame-based bars (Player/Target/Focus cast bars), Blizzard defines a
    -- `Background` texture at BACKGROUND subLevel=2 (see CastingBarFrameBaseTemplate in
    -- wow-ui-source). Our earlier implementation created ScooterModBG at subLevel=-8,
    -- which meant the stock Background completely covered our overlay and made Scooter
    -- backgrounds effectively invisible even though the region existed in Framestack.
    --
    -- To keep behaviour consistent with other bars while making cast bar backgrounds
    -- visible, we render ScooterModBG above the stock Background (subLevel=3) but still
    -- on the BACKGROUND layer so the status bar fill and FX remain on top.
    if not bar.ScooterModBG then
        local layer = "BACKGROUND"
        local sublevel = -8
        if barKind == "cast" then
            sublevel = 3
        end
        bar.ScooterModBG = bar:CreateTexture(nil, layer, nil, sublevel)
        bar.ScooterModBG:SetAllPoints(bar)
    elseif barKind == "cast" then
        -- If we created ScooterModBG earlier (e.g., before cast styling was enabled),
        -- make sure it sits above the stock Background for CastingBarFrame.
        local _, currentSub = bar.ScooterModBG:GetDrawLayer()
        if currentSub == nil or currentSub < 3 then
            bar.ScooterModBG:SetDrawLayer("BACKGROUND", 3)
        end
    end
    
    -- Get opacity (default 50% based on Blizzard's dead/ghost state alpha)
    local opacity = tonumber(backgroundOpacity) or 50
    opacity = math.max(0, math.min(100, opacity)) / 100
    
    -- Check if we're using a custom background texture
    local isCustomTexture = type(backgroundTextureKey) == "string" and backgroundTextureKey ~= "" and backgroundTextureKey ~= "default"
    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(backgroundTextureKey)
    
    if isCustomTexture and resolvedPath then
        -- Apply custom texture
        pcall(bar.ScooterModBG.SetTexture, bar.ScooterModBG, resolvedPath)
        
        -- Apply color based on mode
        local r, g, b, a = 1, 1, 1, 1
        if backgroundColorMode == "custom" and type(backgroundTint) == "table" then
            r, g, b, a = backgroundTint[1] or 1, backgroundTint[2] or 1, backgroundTint[3] or 1, backgroundTint[4] or 1
        elseif backgroundColorMode == "texture" then
            -- Apply white (no tint) to preserve texture's original colors
            r, g, b, a = 1, 1, 1, 1
        elseif backgroundColorMode == "default" then
            r, g, b, a = Utils.getDefaultBackgroundColor(unit, barKind)
        end
        
        if bar.ScooterModBG.SetVertexColor then
            pcall(bar.ScooterModBG.SetVertexColor, bar.ScooterModBG, r, g, b, a)
        end
        -- Apply opacity
        if bar.ScooterModBG.SetAlpha then
            pcall(bar.ScooterModBG.SetAlpha, bar.ScooterModBG, opacity)
        end
        bar.ScooterModBG:Show()
        
        -- Hide Blizzard's stock Background texture when using a custom texture.
        -- CastingBarFrame-based bars (Player/Target/Focus cast bars) have a stock
        -- Background texture at BACKGROUND sublevel 2. Without hiding it, the stock
        -- background shows through since our ScooterModBG sits at sublevel 3.
        -- Use SetAlpha(0) instead of Hide() to avoid fighting Blizzard's internal logic.
        if bar.Background and bar.Background.SetAlpha then
            pcall(bar.Background.SetAlpha, bar.Background, 0)
        end
    else
        -- Default: always show our background with default black color
        -- We don't rely on Blizzard's stock Background texture since it's hidden by default
        pcall(bar.ScooterModBG.SetTexture, bar.ScooterModBG, nil)
        
        local r, g, b, a = Utils.getDefaultBackgroundColor(unit, barKind)
        if backgroundColorMode == "custom" and type(backgroundTint) == "table" then
            r, g, b, a = backgroundTint[1] or 1, backgroundTint[2] or 1, backgroundTint[3] or 1, backgroundTint[4] or 1
        end
        
        if bar.ScooterModBG.SetColorTexture then
            pcall(bar.ScooterModBG.SetColorTexture, bar.ScooterModBG, r, g, b, a)
        end
        -- Apply opacity
        if bar.ScooterModBG.SetAlpha then
            pcall(bar.ScooterModBG.SetAlpha, bar.ScooterModBG, opacity)
        end
        bar.ScooterModBG:Show()
        
        -- Restore Blizzard's stock Background texture visibility when using default.
        -- This ensures toggling back to "Default" restores the original look.
        if bar.Background and bar.Background.SetAlpha then
            pcall(bar.Background.SetAlpha, bar.Background, 1)
        end
    end
end

-- Expose helpers to addon namespace for other modules (Cast Bar styling, etc.)
addon._ApplyToStatusBar = Textures.applyToBar
addon._ApplyBackgroundToStatusBar = Textures.applyBackgroundToBar

return Textures
