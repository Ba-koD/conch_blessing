-- Template for upgrade animations
-- Usage: require this file and call the functions with appropriate parameters
-- Supports positive, neutral, and negative upgrade types

local Template = {}

-- Positive upgrade animation (bright white fade with Holy Light)
Template.positive = {}

Template.positive.onBeforeChange = function(upgradePos, pickup, itemData, soundId)
    -- fade the pedestal item to bright white over 2 seconds (60 ticks)
    local upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 60,
        phase = "before",
        maxAdd = 0.8,
        soundId = soundId or SoundEffect.SOUND_HOLY,
        type = "positive"
    }
    
    -- start charging sound at low volume (loop)
    local sfx = SFXManager()
    sfx:Stop(upgradeAnim.soundId)
    sfx:Play(upgradeAnim.soundId, 0.05, 0, true, 1.0, 0)
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    return 60
end

Template.positive.onAfterChange = function(upgradePos, pickup, itemData, soundId)
    -- single Holy Light strike at the pedestal to finalize
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.CRACK_THE_SKY, 0, upgradePos, Vector.Zero, nil)
    
    -- fade back from white to normal over 2 seconds (60 ticks)
    local upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 60,
        phase = "after",
        maxAdd = 0.8,
        soundId = soundId or SoundEffect.SOUND_HOLY,
        type = "positive"
    }
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    -- ensure sprite starts at white after morph
    local sprite = pickup and pickup:GetSprite() or nil
    if sprite then
        sprite.Color = Color(1, 1, 1, 1, upgradeAnim.maxAdd, upgradeAnim.maxAdd, upgradeAnim.maxAdd)
    end
end

-- Neutral upgrade animation (subtle gray tone)
Template.neutral = {}

Template.neutral.onBeforeChange = function(upgradePos, pickup, itemData, soundId)
    -- 더 극적인 회색 톤 애니메이션 (2초, 60틱)
    local upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 60,
        phase = "before",
        maxAdd = 0.6,  -- 더 큰 값으로 회색 효과 강화
        soundId = soundId or SoundEffect.SOUND_POWERUP_SPEWER,
        type = "neutral"
    }
    
    -- start subtle sound at low volume (loop)
    local sfx = SFXManager()
    sfx:Stop(upgradeAnim.soundId)
    sfx:Play(upgradeAnim.soundId, 0.03, 0, true, 1.0, 0)
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    return 60
end

Template.neutral.onAfterChange = function(upgradePos, pickup, itemData, soundId)
    -- 짙은 회색 스파클 이펙트 (CRACK_THE_SKY 대신)
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.SPARKLE, 0, upgradePos, Vector.Zero, nil)
    
    -- fade back from gray to normal over 2 seconds (60 ticks)
    local upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 60,
        phase = "after",
        maxAdd = 0.6,  -- 더 큰 값으로 회색 효과 강화
        soundId = soundId or SoundEffect.SOUND_POWERUP_SPEWER,
        type = "neutral"
    }
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    -- ensure sprite starts at gray after morph
    local sprite = pickup and pickup:GetSprite() or nil
    if sprite then
        sprite.Color = Color(0.3, 0.3, 0.3, 1.0, 0, 0, 0)  -- 더 어두운 회색으로 시작
    end
end

-- Negative upgrade animation (dark black with dust gathering effect)
Template.negative = {}

Template.negative.onBeforeChange = function(upgradePos, pickup, itemData, soundId)
    -- dark black with dust gathering animation over 2 seconds (60 ticks)
    local upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 60,
        phase = "before",
        maxAdd = 0.7,
        soundId = soundId or SoundEffect.SOUND_POWERUP_SPEWER,
        type = "negative"
    }
    
    -- start ominous sound at low volume (loop)
    local sfx = SFXManager()
    sfx:Stop(upgradeAnim.soundId)
    sfx:Play(upgradeAnim.soundId, 0.04, 0, true, 1.0, 0)
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    return 60
end

Template.negative.onAfterChange = function(upgradePos, pickup, itemData, soundId)
    -- dark dust burst effect
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BURST, 0, upgradePos, Vector.Zero, nil)
    
    -- fade back from dark to normal over 2 seconds (60 ticks)
    local upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 60,
        phase = "after",
        maxAdd = 0.7,
        soundId = soundId or SoundEffect.SOUND_POWERUP_SPEWER,
        type = "negative"
    }
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    -- ensure sprite starts at dark after morph
    local sprite = pickup and pickup:GetSprite() or nil
    if sprite then
        sprite.Color = Color(0.4, 0.4, 0.4, 1.0, 0, 0, 0)
    end
end

-- Update function for handling all upgrade animations
Template.onUpdate = function(itemData)
    local anim = itemData and itemData.upgradeAnim or nil
    if anim and anim.frames and anim.frames > 0 and anim.pickup and anim.pickup:Exists() then
        anim.frames = anim.frames - 1
        local base = 60.0
        local progress = 1.0 - (anim.frames / base)
        local sprite = anim.pickup:GetSprite()
        
        if sprite then
            if anim.type == "positive" then
                -- Positive: white fade with enhanced brightness and saturation
                if anim.phase == "before" then
                    local add = (anim.maxAdd or 0.8) * progress
                    -- 밝기와 채도를 점진적으로 증가, 투명도는 100%
                    local brightness = 1.0 + add * 0.5  -- 1.0에서 1.5로 밝기 증가
                    local saturation = add * 0.3         -- 채도 효과
                    sprite.Color = Color(brightness, brightness, brightness, 1.0, saturation, saturation, saturation)
                elseif anim.phase == "after" then
                    local add = (anim.maxAdd or 0.8) * (1.0 - progress)
                    local brightness = 1.0 + add * 0.5
                    local saturation = add * 0.3
                    sprite.Color = Color(brightness, brightness, brightness, 1.0, saturation, saturation, saturation)
                end
            elseif anim.type == "neutral" then
                -- Neutral: 원래색 → 회색 → 원래색 (더 부드럽게)
                if anim.phase == "before" then
                    local add = (anim.maxAdd or 0.6) * progress
                    -- 원래색에서 회색으로 점진적 변화
                    local gray = 1.0 - add * 0.7  -- 1.0(원래색)에서 0.3(회색)으로
                    sprite.Color = Color(gray, gray, gray, 1.0, 0, 0, 0)
                elseif anim.phase == "after" then
                    local add = (anim.maxAdd or 0.6) * (1.0 - progress)
                    -- 회색에서 원래색으로 점진적 복원 (더 부드럽게, easing 적용)
                    local easedProgress = add * add * (3.0 - 2.0 * add)  -- smoothstep easing
                    local gray = 0.3 + easedProgress * 0.7  -- 0.3(회색)에서 1.0(원래색)으로
                    sprite.Color = Color(gray, gray, gray, 1.0, 0, 0, 0)
                end
            elseif anim.type == "negative" then
                -- Negative: 원래색 → 붉은 검은색 → 원래색
                if anim.phase == "before" then
                    local add = (anim.maxAdd or 0.7) * progress
                    -- 원래색에서 붉은 검은색으로 점진적 변화
                    local dark = 1.0 - add * 0.8  -- 1.0(원래색)에서 0.2(어두움)으로
                    local redTint = add * 0.5      -- 빨간색 톤 추가
                    sprite.Color = Color(dark + redTint, dark, dark, 1.0, 0, 0, 0)
                elseif anim.phase == "after" then
                    local add = (anim.maxAdd or 0.7) * (1.0 - progress)
                    -- 붉은 검은색에서 원래색으로 점진적 복원
                    local dark = 0.2 + add * 0.8  -- 0.2(어두움)에서 1.0(원래색)으로
                    local redTint = add * 0.5
                    sprite.Color = Color(dark + redTint, dark, dark, 1.0, 0, 0, 0)
                end
            end
        end
        
        -- fade sound volume
        if anim.soundId then
            local vol = 0.0
            if anim.phase == "before" then
                vol = 0.03 + 0.47 * progress
            else
                vol = 0.5 * (1.0 - progress)
            end
            SFXManager():AdjustVolume(anim.soundId, vol)
        end
        
        if anim.frames <= 0 then
            -- reset color to default
            if sprite then
                sprite.Color = Color(1, 1, 1, 1, 0, 0, 0)
            end
            -- stop sound at end
            if anim.soundId then
                SFXManager():Stop(anim.soundId)
            end
            if itemData then
                itemData.upgradeAnim = nil
            end
        end
    end
end

-- Legacy functions for backward compatibility (default to positive)
Template.onBeforeChange = function(upgradePos, pickup, itemData, soundId)
    return Template.positive.onBeforeChange(upgradePos, pickup, itemData, soundId)
end

Template.onAfterChange = function(upgradePos, pickup, itemData, soundId)
    Template.positive.onAfterChange(upgradePos, pickup, itemData, soundId)
end

return Template 