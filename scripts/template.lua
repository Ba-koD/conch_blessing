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
    
    -- single Holy Light strike at the pedestal to finalize (안전한 enum 처리)
    local crackTheSkyVariant = EffectVariant.CRACK_THE_SKY or 0
    -- Spawn owned effect so damage is attributed to player and can be tuned
    local player = Game():GetNearestPlayer(upgradePos)
    local eff = Isaac.Spawn(EntityType.ENTITY_EFFECT, crackTheSkyVariant, 0, upgradePos, Vector.Zero, player)
    local efx = eff and eff:ToEffect() or nil
    if efx then
        -- Remove damage by making it a cosmetic only if supported; otherwise set harmless flags
        pcall(function()
            efx:SetDamageSource(EntityRef(player))
            efx.CollisionDamage = 0
        end)
    end
    
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
    
    -- -- 먼지 구름 효과와 스파클 이펙트 추가 (안전한 enum 처리)
    -- local dustCloudVariant = EffectVariant.DUST_CLOUD or 0
    -- local sparkleVariant = EffectVariant.SPARKLE or 0
    -- Isaac.Spawn(EntityType.ENTITY_EFFECT, dustCloudVariant, 0, upgradePos, Vector.Zero, nil)
    -- Isaac.Spawn(EntityType.ENTITY_EFFECT, sparkleVariant, 0, upgradePos, Vector.Zero, nil)
    
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
    
    -- ensure sprite starts at gray after morph (like positive does)
    local sprite = pickup and pickup:GetSprite() or nil
    if sprite then
        sprite.Color = Color(0.3, 0.3, 0.3, 1.0, upgradeAnim.maxAdd * 0.5, upgradeAnim.maxAdd * 0.5, upgradeAnim.maxAdd * 0.5)
    end
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
    
    -- -- 먼지 구름 효과와 어두운 폭발 이펙트 (안전한 enum 처리)
    -- local dustCloudVariant = EffectVariant.DUST_CLOUD or 0
    -- local burstVariant = EffectVariant.BURST or 0
    -- Isaac.Spawn(EntityType.ENTITY_EFFECT, dustCloudVariant, 0, upgradePos, Vector.Zero, nil)
    -- Isaac.Spawn(EntityType.ENTITY_EFFECT, burstVariant, 0, upgradePos, Vector.Zero, nil)
    
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
    
    -- ensure sprite starts at dark after morph (like positive does)
    local sprite = pickup and pickup:GetSprite() or nil
    if sprite then
        sprite.Color = Color(0.2, 0.2, 0.2, 1.0, upgradeAnim.maxAdd * 0.6, 0, 0)
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
                -- Neutral: 원래색 → 회색 → 원래색
                if anim.phase == "before" then
                    local add = (anim.maxAdd or 0.6) * progress
                    -- 원래색에서 회색으로 점진적 변화
                    local gray = 1.0 - add * 0.7  -- 1.0(원래색)에서 0.3(회색)으로
                    sprite.Color = Color(gray, gray, gray, 1.0, 0, 0, 0)
                elseif anim.phase == "after" then
                    local add = (anim.maxAdd or 0.6) * progress
                    -- 회색에서 원래색으로 점진적 복원 (progress가 0에서 1로 증가)
                    local brightness = 0.3 + add * 0.7  -- 0.3(회색)에서 1.0(원래색)으로
                    sprite.Color = Color(brightness, brightness, brightness, 1.0, 0, 0, 0)
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
                    local add = (anim.maxAdd or 0.7) * progress
                    -- 붉은 검은색에서 원래색으로 점진적 복원 (progress가 0에서 1로 증가)
                    local brightness = 0.2 + add * 0.8  -- 0.2(어두움)에서 1.0(원래색)으로
                    local redTint = add * 0.5            -- 빨간색 톤 감소
                    sprite.Color = Color(brightness + redTint, brightness, brightness, 1.0, 0, 0, 0)
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
            
            -- 색상을 자연스럽게 복원 (강제 설정하지 않음)
            if sprite then
                -- 애니메이션의 마지막 색상을 유지하거나 자연스럽게 복원
                if anim.type == "neutral" then
                    -- neutral의 경우 회색에서 원래색으로 점진적 복원 완료
                    sprite.Color = Color(1, 1, 1, 1, 0, 0, 0)
                elseif anim.type == "positive" then
                    -- positive의 경우 밝은 색상에서 원래색으로 복원 완료
                    sprite.Color = Color(1, 1, 1, 1, 0, 0, 0)
                elseif anim.type == "negative" then
                    -- negative의 경우 어두운 색상에서 원래색으로 복원 완료
                    sprite.Color = Color(1, 1, 1, 1, 0, 0, 0)
                else
                    -- 기본 복원
                    sprite.Color = Color(1, 1, 1, 1, 0, 0, 0)
                end
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