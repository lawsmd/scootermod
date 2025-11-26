--[[
    Info Icon Module for ScooterMod
    
    Provides reusable info icon buttons with tooltips, styled with ScooterMod's green branding.
    Based on Blizzard's help-i icon from their Options menu.
    
    Usage Examples:
    
    1. Create an info icon next to a label:
       local label = frame.Label
       local infoIcon = panel.CreateInfoIconForLabel(label, "This setting controls...")
    
    2. Create an info icon with custom positioning:
       local infoIcon = panel.CreateInfoIcon(parentFrame, "Tooltip text here", "RIGHT", "LEFT", 10, 0, 20)
    
    3. Access the icon properties:
       infoIcon.TooltipText  -- The tooltip text
       infoIcon.Texture      -- The texture object (for color modifications, etc.)
]]

local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- ScooterMod brand green color
local brandR, brandG, brandB = 0.20, 0.90, 0.30

-- Helper function to apply Roboto + White styling to GameTooltip
local function styleTooltip()
    if panel and panel.ApplyRobotoWhite then
        local regions = { GameTooltip:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                panel.ApplyRobotoWhite(region)
            end
        end
    end
end

-- Creates a reusable info icon button with tooltip support
-- Parameters:
--   parent: The parent frame to attach the icon to
--   tooltipText: The text to display in the tooltip (required)
--   anchorPoint: Anchor point relative to parent (default: "RIGHT")
--   relativePoint: Relative point on parent (default: "LEFT")
--   offsetX: X offset (default: 5)
--   offsetY: Y offset (default: 0)
--   size: Icon size (default: 16)
-- Returns: The info icon button frame
function panel.CreateInfoIcon(parent, tooltipText, anchorPoint, relativePoint, offsetX, offsetY, size)
    if not parent then
        error("CreateInfoIcon: parent frame is required")
    end
    if not tooltipText or tooltipText == "" then
        error("CreateInfoIcon: tooltipText is required")
    end

    -- Default parameters
    anchorPoint = anchorPoint or "RIGHT"
    relativePoint = relativePoint or "LEFT"
    offsetX = offsetX or 5
    offsetY = offsetY or 0
    size = size or 16

    -- Create the button frame
    local icon = CreateFrame("Button", nil, parent)
    icon:SetSize(size, size)
    icon:SetPoint(anchorPoint, parent, relativePoint, offsetX, offsetY)
    icon:EnableMouse(true)
    -- Set higher frame level to ensure icon is above row overlays and receives mouse input
    local parentLevel = parent:GetFrameLevel() or 1
    icon:SetFrameLevel(parentLevel + 10)

    -- Create the 'i' texture using Blizzard's help-i icon
    local texture = icon:CreateTexture(nil, "ARTWORK")
    texture:SetTexture("Interface\\common\\help-i")
    texture:SetAllPoints(icon)
    
    -- Tint the icon green to match ScooterMod branding
    texture:SetVertexColor(brandR, brandG, brandB, 1)

    -- Store reference to texture for potential future modifications
    icon.Texture = texture
    icon.TooltipText = tooltipText

    -- Add a subtle highlight on hover
    local highlight = icon:CreateTexture(nil, "OVERLAY")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetAllPoints(icon)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0)
    
    -- Set up tooltip and highlight behavior
    icon:SetScript("OnEnter", function(self)
        highlight:SetAlpha(0.3)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -22, -22)
        GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
        styleTooltip()
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function(self)
        highlight:SetAlpha(0)
        GameTooltip:Hide()
    end)

    return icon
end

-- Convenience function to create an info icon next to a label
-- This is the most common use case: an info icon next to a FontString label
-- Parameters:
--   label: The FontString label to attach the icon to
--   tooltipText: The text to display in the tooltip (required)
--   offsetX: X offset from label (default: 5)
--   offsetY: Y offset from label (default: 0)
--   size: Icon size (default: 16)
-- Returns: The info icon button frame
function panel.CreateInfoIconForLabel(label, tooltipText, offsetX, offsetY, size)
    if not label then
        error("CreateInfoIconForLabel: label FontString is required")
    end
    local parent = label:GetParent()
    if not parent then
        error("CreateInfoIconForLabel: label must have a parent frame")
    end
    
    -- Create the icon anchored to the parent (required for SetPoint)
    local icon = CreateFrame("Button", nil, parent)
    local iconSize = size or 16
    icon:SetSize(iconSize, iconSize)
    icon:EnableMouse(true)
    -- Set higher frame level to ensure icon is above row overlays and receives mouse input
    local parentLevel = parent:GetFrameLevel() or 1
    icon:SetFrameLevel(parentLevel + 10)
    
    -- Anchor to the right of the label, vertically centered
    icon:SetPoint("LEFT", label, "RIGHT", offsetX or 5, offsetY or 0)
    
    -- Create the 'i' texture using Blizzard's help-i icon
    local texture = icon:CreateTexture(nil, "ARTWORK")
    texture:SetTexture("Interface\\common\\help-i")
    texture:SetAllPoints(icon)
    
    -- Tint the icon green to match ScooterMod branding
    texture:SetVertexColor(brandR, brandG, brandB, 1)
    
    -- Store reference to texture for potential future modifications
    icon.Texture = texture
    icon.TooltipText = tooltipText
    
    -- Add a subtle highlight on hover
    local highlight = icon:CreateTexture(nil, "OVERLAY")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetAllPoints(icon)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0)
    
    -- Set up tooltip and highlight behavior
    icon:SetScript("OnEnter", function(self)
        highlight:SetAlpha(0.3)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -22, -22)
        GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
        styleTooltip()
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function(self)
        highlight:SetAlpha(0)
        GameTooltip:Hide()
    end)
    
    return icon
end

