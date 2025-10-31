local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Lightweight theming helpers --------------------------------------------------
do
    local fonts = addon and addon.Fonts or nil
    local brandR, brandG, brandB = 0.20, 0.90, 0.30 -- Scooter green

    -- Apply Roboto + green to a FontString (idempotent)
    function panel.ApplyGreenRoboto(fs, size, flags)
        if not fs or not fs.SetFont then return end
        local face = (fonts and (fonts.ROBOTO_MED or fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
        local _, currentSize, currentFlags = fs:GetFont()
        fs:SetFont(face, size or currentSize or 12, flags or currentFlags or "")
        if fs.SetTextColor then fs:SetTextColor(brandR, brandG, brandB, 1) end
    end

    -- Apply Roboto but preserve current color
    function panel.ApplyRoboto(fs, size, flags)
        if not fs or not fs.SetFont then return end
        local face = (fonts and (fonts.ROBOTO_MED or fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
        local r, g, b, a = 1, 1, 1, 1
        if fs.GetTextColor then r, g, b, a = fs:GetTextColor() end
        local _, currentSize, currentFlags = fs:GetFont()
        fs:SetFont(face, size or currentSize or 12, flags or currentFlags or "")
        if fs.SetTextColor then fs:SetTextColor(r, g, b, a) end
    end

    -- Apply Roboto and force white
    function panel.ApplyRobotoWhite(fs, size, flags)
        if not fs then return end
        panel.ApplyRoboto(fs, size, flags)
        if fs.SetTextColor then fs:SetTextColor(1, 1, 1, 1) end
    end

    -- Desaturate/tint a button's textures to neutral gray while keeping volume
    local function tintTexture(tex, gray)
        if not tex or not tex.SetVertexColor then return end
        pcall(tex.SetDesaturated, tex, true)
        tex:SetVertexColor(gray, gray, gray)
    end

    function panel.ApplyButtonTheme(btn)
        if not btn then return end
        if btn.Text then
            local _, sz, fl = btn.Text:GetFont()
            panel.ApplyGreenRoboto(btn.Text, sz, fl)
        end
        tintTexture(btn.GetNormalTexture and btn:GetNormalTexture() or nil, 0.97)
        tintTexture(btn.GetPushedTexture and btn:GetPushedTexture() or nil, 0.93)
        do
            if btn.SetHighlightTexture then pcall(btn.SetHighlightTexture, btn, "Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD") end
            local hl = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
            if hl then hl:SetDesaturated(false); hl:SetVertexColor(1, 1, 1); hl:SetAlpha(0.45) end
        end
        tintTexture(btn.GetDisabledTexture and btn:GetDisabledTexture() or nil, 0.90)
        local regions = { btn:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.IsObjectType and r:IsObjectType("Texture") then
                tintTexture(r, 0.97)
            end
        end
    end

    local function forEachDescendant(frame, fn, depth)
        if not frame or (depth and depth <= 0) then return end
        if frame.GetRegions then
            local regions = { frame:GetRegions() }
            for i = 1, #regions do fn(regions[i]) end
        end
        if frame.GetChildren then
            local children = { frame:GetChildren() }
            for i = 1, #children do fn(children[i]); forEachDescendant(children[i], fn, (depth and depth-1) or 2) end
        end
    end

    local function isFontString(obj)
        return obj and obj.IsObjectType and obj:IsObjectType("FontString")
    end

    function panel.ApplyControlTheme(root)
        if not root then return end
        forEachDescendant(root, function(obj)
            if isFontString(obj) then
                panel.ApplyRoboto(obj)
            elseif obj and obj.IsObjectType and obj:IsObjectType("Button") then
                local function tint(tex)
                    if tex and tex.SetVertexColor then tex:SetDesaturated(true); tex:SetVertexColor(brandR, brandG, brandB) end
                end
                tint(obj.GetNormalTexture and obj:GetNormalTexture() or nil)
                tint(obj.GetPushedTexture and obj:GetPushedTexture() or nil)
                if obj.SetHighlightTexture then pcall(obj.SetHighlightTexture, obj, "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD") end
                local hl = obj.GetHighlightTexture and obj:GetHighlightTexture() or nil
                if hl then hl:SetDesaturated(false); hl:SetVertexColor(1,1,1); hl:SetAlpha(0.25) end
            end
        end, 3)
    end

    function panel.StyleDropdownLabel(dropdown, scale)
        if not dropdown or not dropdown.Text or not dropdown.Text.GetFont then return end
        local face, sz, flags = dropdown.Text:GetFont()
        if not dropdown.Text._ScooterBaseFont then
            dropdown.Text._ScooterBaseFont = { face, sz or 12, flags }
        end
        local baseSize = (dropdown.Text._ScooterBaseFont and dropdown.Text._ScooterBaseFont[2]) or (sz or 12)
        local newSize = math.floor(baseSize * (scale or 1.25) + 0.5)
        panel.ApplyRobotoWhite(dropdown.Text, newSize, flags)
    end

    if not panel._dropdownMenuHooked then
        panel._dropdownMenuHooked = true
        hooksecurefunc("ToggleDropDownMenu", function(level)
            local function styleLevel(lvl)
                local list = _G["DropDownList" .. tostring(lvl)]
                if not list or not list:IsShown() then return end
                local i = 1
                while true do
                    local btn = _G[list:GetName() .. "Button" .. i]
                    if not btn then break end
                    local fs = (btn.GetFontString and btn:GetFontString()) or btn.NormalText
                    if fs and fs.GetFont then
                        local face, sz, flags = fs:GetFont()
                        if not fs._ScooterBaseFont then
                            fs._ScooterBaseFont = { face, sz or 12, flags }
                        end
                        local baseSize = (fs._ScooterBaseFont and fs._ScooterBaseFont[2]) or (sz or 12)
                        panel.ApplyRobotoWhite(fs, math.floor(baseSize * 1.25 + 0.5), flags)
                    end
                    i = i + 1
                end
            end
            C_Timer.After(0, function() styleLevel(level or 1) end)
        end)
    end

    function panel.SkinCategoryList(categoryList)
        if not categoryList or not categoryList.ScrollBox or not categoryList.ScrollBox.ScrollTarget then return end
        local target = categoryList.ScrollBox.ScrollTarget
        local children = { target:GetChildren() }
        for i = 1, #children do
            local b = children[i]
            local fs = (b and (b.Text or b.Name or b.Label))
            if fs then
                local _, size, flags = fs:GetFont()
                local text = fs.GetText and fs:GetText() or ""
                local isHeader = (b and (b.isHeader == true or b.Header or b.HeaderText)) or text == "Profiles" or text == "Cooldown Manager" or text == "Action Bars"
                panel.ApplyGreenRoboto(fs, size, flags)
                if not isHeader and fs.SetTextColor then
                    fs:SetTextColor(1, 1, 1, 1)
                end
            end
        end
    end
end


