-- Template for upgrade animations
-- Usage: require this file and call the functions with appropriate parameters
-- Supports positive, neutral, and negative upgrade types

local Template = {}

-- Positive upgrade animation (bright white fade with Holy Light)
Template.positive = {}

Template.positive.onBeforeChange = function(upgradePos, pickup, itemData, soundId)
    -- Debug: print function call
    if ConchBlessing and ConchBlessing.printDebug then
        ConchBlessing.printDebug("Template.positive.onBeforeChange called")
    end
    
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
    
    -- start charging sound at low volume (no loop)
    local sfx = SFXManager()
    sfx:Stop(upgradeAnim.soundId)
    sfx:Play(upgradeAnim.soundId, 0.05, 0, false, 1.0, 0)
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    return 60
end

Template.positive.onAfterChange = function(upgradePos, pickup, itemData, soundId)
    -- Debug: print function call
    if ConchBlessing and ConchBlessing.printDebug then
        ConchBlessing.printDebug("Template.positive.onAfterChange called")
    end
    
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
    -- Debug: print function call
    if ConchBlessing and ConchBlessing.printDebug then
        ConchBlessing.printDebug("Template.neutral.onBeforeChange called")
    end
    
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
    
    -- start subtle sound at low volume (no loop)
    local sfx = SFXManager()
    sfx:Stop(upgradeAnim.soundId)
    sfx:Play(upgradeAnim.soundId, 0.03, 0, false, 1.0, 0)
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    return 60
end

Template.neutral.onAfterChange = function(upgradePos, pickup, itemData, soundId)
    -- Debug: print function call
    if ConchBlessing and ConchBlessing.printDebug then
        ConchBlessing.printDebug("Template.neutral.onAfterChange called")
    end
    
    -- 짙은 회색 스파클 이펙트 (CRACK_THE_SKY 대신)
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.SPARKLE, 0, upgradePos, Vector.Zero, nil)
    
    -- before 페이즈의 마지막 색상 저장 (회색)
    local sprite = pickup and pickup:GetSprite() or nil
    local beforeColor = { r = 0.3, g = 0.3, b = 0.3, a = 1.0, ro = 0, go = 0, bo = 0 }
    if sprite then
        beforeColor = {
            r = sprite.Color.Red,
            g = sprite.Color.Green,
            b = sprite.Color.Blue,
            a = sprite.Color.Alpha,
            ro = sprite.Color.RedOffset,
            go = sprite.Color.GreenOffset,
            bo = sprite.Color.BlueOffset
        }
    end
    
    -- fade back from gray to normal over 2 seconds (60 ticks)
    local upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 60,
        phase = "after",
        maxAdd = 0.6,  -- 더 큰 값으로 회색 효과 강화
        soundId = soundId or SoundEffect.SOUND_POWERUP_SPEWER,
        type = "neutral",
        beforeColor = beforeColor  -- before 페이즈의 마지막 색상 저장
    }
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    -- 스프라이트 색상을 즉시 설정하지 않음 - 애니메이션에서 점진적 복원
end

-- Negative upgrade animation (dark black with dust gathering effect)
Template.negative = {}

Template.negative.onBeforeChange = function(upgradePos, pickup, itemData, soundId)
    -- Debug: print function call
    if ConchBlessing and ConchBlessing.printDebug then
        ConchBlessing.printDebug("Template.negative.onBeforeChange called")
    end
    
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
    
    -- start ominous sound at low volume (no loop)
    local sfx = SFXManager()
    sfx:Stop(upgradeAnim.soundId)
    sfx:Play(upgradeAnim.soundId, 0.04, 0, false, 1.0, 0)
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    return 60
end

Template.negative.onAfterChange = function(upgradePos, pickup, itemData, soundId)
    -- Debug: print function call
    if ConchBlessing and ConchBlessing.printDebug then
        ConchBlessing.printDebug("Template.negative.onAfterChange called")
    end
    
    -- dark dust burst effect
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BURST, 0, upgradePos, Vector.Zero, nil)
    
    -- before 페이즈의 마지막 색상 저장 (어두운 색)
    local sprite = pickup and pickup:GetSprite() or nil
    local beforeColor = { r = 0.4, g = 0.4, b = 0.4, a = 1.0, ro = 0, go = 0, bo = 0 }
    if sprite then
        beforeColor = {
            r = sprite.Color.Red,
            g = sprite.Color.Green,
            b = sprite.Color.Blue,
            a = sprite.Color.Alpha,
            ro = sprite.Color.RedOffset,
            go = sprite.Color.GreenOffset,
            bo = sprite.Color.BlueOffset
        }
    end
    
    -- fade back from dark to normal over 2 seconds (60 ticks)
    local upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 60,
        phase = "after",
        maxAdd = 0.7,
        soundId = soundId or SoundEffect.SOUND_POWERUP_SPEWER,
        type = "negative",
        beforeColor = beforeColor  -- before 페이즈의 마지막 색상 저장
    }
    
    -- Store animation data in the item's data
    if itemData then
        itemData.upgradeAnim = upgradeAnim
    end
    
    -- 스프라이트 색상을 즉시 설정하지 않음 - 애니메이션에서 점진적 복원
end

-- Update function for handling all upgrade animations
Template.onUpdate = function(itemData)
    local anim = itemData and itemData.upgradeAnim or nil
    if anim and anim.frames and anim.frames > 0 and anim.pickup and anim.pickup:Exists() then
        anim.frames = anim.frames - 1
        local base = 60.0
        local progress = 1.0 - (anim.frames / base)
        local sprite = anim.pickup:GetSprite()
        
        -- Debug: print animation progress
        if ConchBlessing and ConchBlessing.printDebug then
            ConchBlessing.printDebug(string.format("Template: %s phase, frames=%d, progress=%.2f", 
                anim.phase, anim.frames, progress))
        end
        
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
                    -- 회색에서 원래색으로 점진적 복원 (beforeColor 기반)
                    local easedProgress = add * add * (3.0 - 2.0 * add)  -- smoothstep easing
                    if anim.beforeColor then
                        -- beforeColor에서 원래색(1.0, 1.0, 1.0)으로 점진적 복원
                        local r = anim.beforeColor.r + (1.0 - anim.beforeColor.r) * easedProgress
                        local g = anim.beforeColor.g + (1.0 - anim.beforeColor.g) * easedProgress
                        local b = anim.beforeColor.b + (1.0 - anim.beforeColor.b) * easedProgress
                        sprite.Color = Color(r, g, b, 1.0, 0, 0, 0)
                    else
                        -- fallback: 기본 점진적 복원
                        local gray = 0.3 + easedProgress * 0.7
                        sprite.Color = Color(gray, gray, gray, 1.0, 0, 0, 0)
                    end
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
                    -- 붉은 검은색에서 원래색으로 점진적 복원 (beforeColor 기반)
                    local easedProgress = add * add * (3.0 - 2.0 * add)  -- smoothstep easing
                    if anim.beforeColor then
                        -- beforeColor에서 원래색(1.0, 1.0, 1.0)으로 점진적 복원
                        local r = anim.beforeColor.r + (1.0 - anim.beforeColor.r) * easedProgress
                        local g = anim.beforeColor.g + (1.0 - anim.beforeColor.g) * easedProgress
                        local b = anim.beforeColor.b + (1.0 - anim.beforeColor.b) * easedProgress
                        sprite.Color = Color(r, g, b, 1.0, 0, 0, 0)
                    else
                        -- fallback: 기본 점진적 복원
                        local dark = 0.2 + add * 0.8
                        local redTint = add * 0.5
                        sprite.Color = Color(dark + redTint, dark, dark, 1.0, 0, 0, 0)
                    end
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
        
        -- 애니메이션이 끝났을 때 정리
        if anim.frames <= 0 then
            -- Debug: print animation completion
            if ConchBlessing and ConchBlessing.printDebug then
                ConchBlessing.printDebug(string.format("Template: %s phase animation completed", anim.phase))
            end
            
            -- reset color to default
            if sprite then
                sprite.Color = Color(1, 1, 1, 1, 0, 0, 0)
            end
            -- stop sound at end
            if anim.soundId then
                SFXManager():Stop(anim.soundId)
                anim.soundId = nil
            end
            -- 애니메이션 데이터 완전 정리
            if itemData then
                itemData.upgradeAnim = nil
            end
            anim = nil
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