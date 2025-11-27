--------------------------------------------------------------------------------
-- ScooterMod Title Region Reveal Animations
-- 
-- Provides pop/typewriter animations for the logo and title when navigating
-- away from the home page.
--
-- Usage:
--   panel.AnimateTitleReveal(titleRegion, logoButton, titleFontString)
--------------------------------------------------------------------------------
local addonName, addon = ...
local panel = addon.SettingsPanel or {}
addon.SettingsPanel = panel

-- Animation timing constants (in seconds)
local TOTAL_ANIMATION_DURATION = 1.0      -- Total time for the entire reveal
local LOGO_POP_DURATION = 0.35            -- Logo pop animation duration
local LOGO_START_SCALE = 0.3              -- Logo starts at 30% size
local LOGO_OVERSHOOT_SCALE = 1.08         -- Slight overshoot before settling
local TYPEWRITER_DELAY = 0.15             -- Delay before typewriter starts (after logo begins)
local TYPEWRITER_CHAR_INTERVAL = 0.065    -- Time between each character appearing

-- Animation update rate (roughly 60fps)
local ANIMATION_TICK_INTERVAL = 0.016

-- Full title text
local TITLE_TEXT = "ScooterMod"

--------------------------------------------------------------------------------
-- Easing Functions
--------------------------------------------------------------------------------

-- Ease-out cubic: decelerates smoothly
local function easeOutCubic(t)
    return 1 - math.pow(1 - t, 3)
end

-- Ease-out back: slight overshoot then settle (for pop effect)
local function easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
end

--------------------------------------------------------------------------------
-- Logo Pop Animation
--
-- Uses C_Timer for smooth, predictable scaling animation.
-- The logo starts smaller and "pops" to full size with a subtle overshoot.
--------------------------------------------------------------------------------
local function AnimateLogoPop(logoButton, onComplete)
    if not logoButton then
        if onComplete then onComplete() end
        return
    end
    
    -- Cancel any existing animation
    if logoButton._scooterPopTicker then
        logoButton._scooterPopTicker:Cancel()
        logoButton._scooterPopTicker = nil
    end
    
    local startTime = GetTime()
    local startScale = LOGO_START_SCALE
    local endScale = 1.0
    
    -- Set initial scale
    logoButton:SetScale(startScale)
    
    -- Create ticker for smooth animation
    local ticker
    ticker = C_Timer.NewTicker(ANIMATION_TICK_INTERVAL, function()
        local elapsed = GetTime() - startTime
        local progress = math.min(elapsed / LOGO_POP_DURATION, 1.0)
        
        -- Use easeOutBack for the pop effect (includes slight overshoot)
        local easedProgress = easeOutBack(progress)
        
        -- Interpolate scale
        local currentScale = startScale + (endScale - startScale) * easedProgress
        logoButton:SetScale(currentScale)
        
        -- Check if animation is complete
        if progress >= 1.0 then
            ticker:Cancel()
            logoButton._scooterPopTicker = nil
            logoButton:SetScale(1.0)  -- Ensure final scale is exactly 1.0
            if onComplete then onComplete() end
        end
    end)
    
    -- Store reference for potential cancellation
    logoButton._scooterPopTicker = ticker
end

--------------------------------------------------------------------------------
-- Typewriter Text Animation
--
-- Progressively reveals the title text character by character using C_Timer.
-- Creates a "typing" effect from left to right.
--------------------------------------------------------------------------------
local function AnimateTypewriter(titleFontString, fullText, onComplete)
    if not titleFontString then
        if onComplete then onComplete() end
        return
    end
    
    -- Cancel any existing typewriter animation
    if titleFontString._scooterTypewriterTicker then
        titleFontString._scooterTypewriterTicker:Cancel()
        titleFontString._scooterTypewriterTicker = nil
    end
    
    local textLength = #fullText
    local currentIndex = 0
    
    -- Start with empty text
    titleFontString:SetText("")
    
    -- Create the ticker that adds one character at a time
    local ticker
    ticker = C_Timer.NewTicker(TYPEWRITER_CHAR_INTERVAL, function()
        currentIndex = currentIndex + 1
        
        if currentIndex <= textLength then
            -- Reveal up to currentIndex characters
            local revealedText = string.sub(fullText, 1, currentIndex)
            titleFontString:SetText(revealedText)
        end
        
        -- Stop when all characters are revealed
        if currentIndex >= textLength then
            ticker:Cancel()
            titleFontString._scooterTypewriterTicker = nil
            if onComplete then onComplete() end
        end
    end, textLength)
    
    -- Store reference for potential cancellation
    titleFontString._scooterTypewriterTicker = ticker
end

--------------------------------------------------------------------------------
-- Combined Title Reveal Animation
--
-- Orchestrates both the logo pop and typewriter animations to run together,
-- completing in approximately 1 second total.
--
-- @param titleRegion: The parent frame containing logo and title
-- @param logoButton: The logo button to animate (pop effect)
-- @param titleFontString: The FontString to animate (typewriter effect)
-- @param fromHome: Boolean indicating if we're transitioning FROM the home page
--------------------------------------------------------------------------------
function panel.AnimateTitleReveal(titleRegion, logoButton, titleFontString, fromHome)
    -- Only animate when transitioning away from home
    if not fromHome then
        -- Just ensure everything is visible and at full scale
        if titleRegion then titleRegion:Show() end
        if logoButton then logoButton:SetScale(1.0) end
        if titleFontString then titleFontString:SetText(TITLE_TEXT) end
        return
    end
    
    -- Ensure the title region is visible
    if titleRegion then
        titleRegion:Show()
    end
    
    -- Start logo pop animation
    if logoButton then
        AnimateLogoPop(logoButton, nil)
    end
    
    -- Start typewriter animation after a short delay (so logo starts popping first)
    if titleFontString then
        -- Clear text initially
        titleFontString:SetText("")
        
        C_Timer.After(TYPEWRITER_DELAY, function()
            AnimateTypewriter(titleFontString, TITLE_TEXT, nil)
        end)
    end
end

--------------------------------------------------------------------------------
-- Stop/Reset Animation
--
-- Immediately stops any running animations and resets to final state.
-- Useful when the panel is closed mid-animation.
--------------------------------------------------------------------------------
function panel.StopTitleAnimation(logoButton, titleFontString)
    -- Stop logo animation
    if logoButton then
        if logoButton._scooterPopTicker then
            logoButton._scooterPopTicker:Cancel()
            logoButton._scooterPopTicker = nil
        end
        logoButton:SetScale(1.0)
    end
    
    -- Stop typewriter animation
    if titleFontString then
        if titleFontString._scooterTypewriterTicker then
            titleFontString._scooterTypewriterTicker:Cancel()
            titleFontString._scooterTypewriterTicker = nil
        end
        titleFontString:SetText(TITLE_TEXT)
    end
end

--------------------------------------------------------------------------------
-- Check if animation is currently running
--------------------------------------------------------------------------------
function panel.IsTitleAnimationRunning(logoButton, titleFontString)
    local logoAnimating = logoButton and logoButton._scooterPopTicker
    local typewriterAnimating = titleFontString and titleFontString._scooterTypewriterTicker
    return logoAnimating or typewriterAnimating
end

