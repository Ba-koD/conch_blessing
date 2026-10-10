-- Template for upgrade animations
-- Usage: require this file and call the functions with appropriate parameters
-- Supports positive, neutral, and negative upgrade types

local Template = {}
local MorphVisuals -- Loaded lazily, after ItemData initialization.
local PickupVisual = require("scripts.lib.upgrade_pickup_visual")
Template._activeAnimations = Template._activeAnimations or {}
Template._centralUpdaterRegistered = Template._centralUpdaterRegistered or false

local function livePickup(anim)
    local pickup = anim and anim.pickupPtr and anim.pickupPtr.Ref
    if pickup and pickup:Exists() and GetPtrHash(pickup) == anim.pickupHash then return pickup end
end

local function matchesPickup(anim, pickup)
    return livePickup(anim) ~= nil and pickup ~= nil and pickup:Exists()
        and GetPtrHash(pickup) == anim.pickupHash
end

local function ensureCentralUpdater()
    if Template._centralUpdaterRegistered then
        return
    end
    if ConchBlessing and ConchBlessing.AddCallback and ModCallbacks then
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
            if Template.updateAllAnimations then
                Template.updateAllAnimations()
            end
        end)
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, function()
            Template.renderAllAnimations()
        end)
        -- RenderWater is the per-frame floor pass. pre_render_walls instead
        -- rebuilds backdrop textures and cannot host a running animation.
        if ModCallbacks.MC_PRE_BACKDROP_RENDER_WATER then
            ConchBlessing:AddCallback(ModCallbacks.MC_PRE_BACKDROP_RENDER_WATER, function()
                for _, anim in ipairs(Template._activeAnimations) do
                    if anim.morphScene and livePickup(anim) then
                        MorphVisuals.safe(MorphVisuals.renderFloor, anim.morphScene)
                    end
                end
            end)
        end
        local function clearVisuals()
            Template.clearAnimations()
        end
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, clearVisuals)
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, clearVisuals)
        ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, clearVisuals)
        Template._centralUpdaterRegistered = true
    end
end

local function getPickupColor(pickup)
    if not pickup or not pickup:Exists() then
        return nil
    end

    local highlight = ConchBlessing and ConchBlessing.UpgradeHighlight
    if highlight and highlight.StopForPickup then highlight.StopForPickup(pickup) end
    local sprite = pickup:GetSprite()
    return sprite and PickupVisual.copyColor(sprite.Color) or nil
end

local function finishAnimation(anim, sprite)
    -- A dead EntityPtr must never restore state onto a reused native address.
    if anim and not livePickup(anim) then
        anim.pickupVisual = nil
        sprite = nil
    end
    if anim then
        PickupVisual.restore(anim.pickupVisual)
        anim.pickupVisual = nil
        anim.lightSprite = nil
        anim.morphScene = nil
    end
    if sprite then
        sprite.Color = (anim and anim.originalColor) or Color(1, 1, 1, 1, 0, 0, 0)
    end
    -- SFX Stop/AdjustVolume act on a shared sound ID, not this animation's
    -- playback instance. One-shot cues finish naturally so cancelling one
    -- pedestal never silences another preview, upgrade or gameplay sound.
    if anim and anim.ownerData and anim.ownerData.upgradeAnim == anim then
        anim.ownerData.upgradeAnim = nil
    end
    return true
end

local function registerAnimation(ownerData, anim)
    if not anim then
        return
    end
    anim.ownerData = ownerData
    -- ToPickup/callbacks can return distinct Lua wrappers of the same entity.
    -- Match the live native identity, not wrapper equality or GetData.
    anim.pickupPtr = EntityPtr(anim.pickup)
    anim.pickupHash = GetPtrHash(anim.pickup)
    assert(livePickup(anim), "upgrade animation pickup reference unavailable")
    anim.totalFrames = anim.frames or 60
    anim._centralManaged = true
    if ownerData then
        ownerData.upgradeAnim = anim
    end
    local active = Template._activeAnimations
    for i = #active, 1, -1 do
        local existing = active[i]
        if existing and matchesPickup(existing, anim.pickup) then
            -- A second conversion may begin during the first one's hidden
            -- after-animation. Carry the real color, not its temporary alpha.
            anim.originalColor = existing.originalColor or anim.originalColor
            finishAnimation(existing, nil)
            table.remove(active, i)
        end
    end
    table.insert(active, anim)
    ensureCentralUpdater()
end

Template.cancelForPickup = function(pickup)
    if not pickup then
        return
    end

    local active = Template._activeAnimations
    for i = #active, 1, -1 do
        local anim = active[i]
        if anim and matchesPickup(anim, pickup) then
            local sprite = pickup:Exists() and pickup:GetSprite() or nil
            finishAnimation(anim, sprite)
            table.remove(active, i)
        end
    end
end

function Template.isAnimatingPickup(pickup)
    for _, anim in ipairs(Template._activeAnimations) do
        if matchesPickup(anim, pickup) then return true end
    end
    return false
end

-- Positive upgrade animation (bright white fade with Holy Light)
Template.positive = {}

local function createCosmeticLight()
    -- CRACK_THE_SKY has native attack logic even when CollisionDamage is zero.
    -- Play only its vanilla art: no entity, collision, Hit event, or proc source.
    local ok, sprite = pcall(function()
        local visual = Sprite()
        for _, method in ipairs({ "Load", "Play", "Update", "Render", "IsFinished" }) do
            assert(type(visual[method]) == "function", "Sprite:" .. method .. " unavailable")
        end
        visual:Load("gfx/1000.019_crack the sky.anm2", true)
        if type(visual.IsLoaded) == "function" then
            assert(visual:IsLoaded(), "Holy Light animation could not load")
        end
        visual:Play("Spotlight", true)
        return visual
    end)
    if ok then
        return sprite
    end
    if ConchBlessing and ConchBlessing.printError then
        ConchBlessing.printError("[Upgrade] Cosmetic Holy Light unavailable: " .. tostring(sprite))
    end
    return nil
end

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
        type = "positive",
        originalColor = getPickupColor(pickup),
    }
    
    -- One-shot cue; never stop or adjust the shared sound channel.
    local sfx = SFXManager()
    sfx:Play(upgradeAnim.soundId, 0.25, 0, false, 1.0, 0)
    
    registerAnimation(itemData, upgradeAnim)
    
    return 60
end

Template.positive.onAfterChange = function(upgradePos, pickup, itemData, soundId)
    -- Debug: print function call
    if ConchBlessing and ConchBlessing.printDebug then
        ConchBlessing.printDebug("Template.positive.onAfterChange called")
    end
    
    -- fade back from white to normal over 2 seconds (60 ticks)
    local upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 60,
        phase = "after",
        maxAdd = 0.8,
        soundId = soundId or SoundEffect.SOUND_HOLY,
        type = "positive",
        originalColor = getPickupColor(pickup),
        lightSprite = createCosmeticLight(),
    }
    
    registerAnimation(itemData, upgradeAnim)
    
    -- ensure sprite starts at white after morph
    local sprite = pickup and pickup:GetSprite() or nil
    if sprite then
        sprite.Color = Color(1, 1, 1, 1, upgradeAnim.maxAdd, upgradeAnim.maxAdd, upgradeAnim.maxAdd)
    end

    return upgradeAnim.frames
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
        type = "neutral",
        originalColor = getPickupColor(pickup),
    }
    
    -- One-shot cue; never stop or adjust the shared sound channel.
    local sfx = SFXManager()
    sfx:Play(upgradeAnim.soundId, 0.2, 0, false, 1.0, 0)
    
    registerAnimation(itemData, upgradeAnim)
    
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
        type = "neutral",
        originalColor = getPickupColor(pickup),
    }
    
    registerAnimation(itemData, upgradeAnim)
    
    -- ensure sprite starts at gray after morph (like positive does)
    local sprite = pickup and pickup:GetSprite() or nil
    if sprite then
        sprite.Color = Color(0.3, 0.3, 0.3, 1.0, upgradeAnim.maxAdd * 0.5, upgradeAnim.maxAdd * 0.5, upgradeAnim.maxAdd * 0.5)
    end

    return upgradeAnim.frames
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
        type = "negative",
        originalColor = getPickupColor(pickup),
    }
    
    -- One-shot cue; never stop or adjust the shared sound channel.
    local sfx = SFXManager()
    sfx:Play(upgradeAnim.soundId, 0.2, 0, false, 1.0, 0)
    
    registerAnimation(itemData, upgradeAnim)
    
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
        type = "negative",
        originalColor = getPickupColor(pickup),
    }
    
    registerAnimation(itemData, upgradeAnim)
    
    -- ensure sprite starts at dark after morph (like positive does)
    local sprite = pickup and pickup:GetSprite() or nil
    if sprite then
        sprite.Color = Color(0.2, 0.2, 0.2, 1.0, upgradeAnim.maxAdd * 0.6, 0, 0)
    end

    return upgradeAnim.frames
end

-- Legacy item-local updater kept as a fallback for non-central animations.
Template._legacyItemLocalUpdate = function(itemData)
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
            -- 애니메이션 데이터 완전 정리
            if itemData then
                itemData.upgradeAnim = nil
            end
            anim = nil
        end
    end
end

local function updateAnimation(anim)
    if not livePickup(anim) then return finishAnimation(anim, nil) end
    if anim and anim.morphScene then
        local s = anim.pickup and anim.pickup:Exists() and anim.pickup:GetSprite() or nil
        if not s or anim.morphScene.failed then return finishAnimation(anim, s) end
        if not PickupVisual.hasFrame(anim.pickupVisual) then return finishAnimation(anim, s) end
        if anim.phase == "after" and (anim.pickup.Variant ~= anim.expectedVariant
            or anim.pickup.SubType ~= anim.expectedSubType) then
            return finishAnimation(anim, s)
        end
        anim.frames = anim.frames - 1
        local scene = anim.morphScene
        scene.pos = Vector(anim.pickup.Position.X, anim.pickup.Position.Y)
        -- The pre-morph picture holds until the transaction actually commits.
        if anim.phase ~= "before" or scene.frame < scene.impact - 1 then
            if not MorphVisuals.safe(MorphVisuals.update, scene) then return finishAnimation(anim, s) end
        end
        PickupVisual.hide(anim.pickupVisual)
        if anim.phase == "after" and anim.frames <= 0 then return finishAnimation(anim, s) end
        return false
    end
    if not (anim and anim.frames and anim.frames > 0 and anim.pickup and anim.pickup:Exists()) then
        return finishAnimation(anim, nil)
    end

    anim.frames = anim.frames - 1
    if anim.lightSprite then
        anim.lightSprite:Update()
        if anim.lightSprite:IsFinished("Spotlight") then
            anim.lightSprite = nil
        end
    end
    local base = tonumber(anim.totalFrames) or 60.0
    if base <= 0 then
        base = 60.0
    end
    local progress = 1.0 - (anim.frames / base)
    local sprite = anim.pickup:GetSprite()

    if ConchBlessing and ConchBlessing.printDebug then
        ConchBlessing.printDebug(string.format("Template: %s phase, frames=%d, progress=%.2f",
            anim.phase, anim.frames, progress))
    end

    if sprite then
        if anim.type == "positive" then
            if anim.phase == "before" then
                local add = (anim.maxAdd or 0.8) * progress
                local brightness = 1.0 + add * 0.5
                local saturation = add * 0.3
                sprite.Color = Color(brightness, brightness, brightness, 1.0, saturation, saturation, saturation)
            elseif anim.phase == "after" then
                local add = (anim.maxAdd or 0.8) * (1.0 - progress)
                local brightness = 1.0 + add * 0.5
                local saturation = add * 0.3
                sprite.Color = Color(brightness, brightness, brightness, 1.0, saturation, saturation, saturation)
            end
        elseif anim.type == "neutral" then
            if anim.phase == "before" then
                local add = (anim.maxAdd or 0.6) * progress
                local gray = 1.0 - add * 0.7
                sprite.Color = Color(gray, gray, gray, 1.0, 0, 0, 0)
            elseif anim.phase == "after" then
                local add = (anim.maxAdd or 0.6) * progress
                local brightness = 0.3 + add * 0.7
                sprite.Color = Color(brightness, brightness, brightness, 1.0, 0, 0, 0)
            end
        elseif anim.type == "negative" then
            if anim.phase == "before" then
                local add = (anim.maxAdd or 0.7) * progress
                local dark = 1.0 - add * 0.8
                local redTint = add * 0.5
                sprite.Color = Color(dark + redTint, dark, dark, 1.0, 0, 0, 0)
            elseif anim.phase == "after" then
                local add = (anim.maxAdd or 0.7) * progress
                local brightness = 0.2 + add * 0.8
                local redTint = add * 0.5
                sprite.Color = Color(brightness + redTint, brightness, brightness, 1.0, 0, 0, 0)
            end
        end
    end

    if anim.frames <= 0 then
        if ConchBlessing and ConchBlessing.printDebug then
            ConchBlessing.printDebug(string.format("Template: %s phase animation completed", anim.phase))
        end
        return finishAnimation(anim, sprite)
    end

    return false
end

Template.updateAllAnimations = function()
    if Game and Game().IsPaused and Game():IsPaused() then return end
    local active = Template._activeAnimations
    if not active or #active == 0 then
        return
    end

    for i = #active, 1, -1 do
        if updateAnimation(active[i]) then
            table.remove(active, i)
        end
    end
end

Template.renderAllAnimations = function()
    for _, anim in ipairs(Template._activeAnimations) do
        if not livePickup(anim) then
            finishAnimation(anim, nil)
            anim.frames = 0
        elseif anim.morphScene then
            if not PickupVisual.hasFrame(anim.pickupVisual)
                or not MorphVisuals.safe(MorphVisuals.render, anim.morphScene) then
                finishAnimation(anim, anim.pickup:GetSprite())
                anim.frames = 0
            end
        elseif anim.lightSprite and anim.pickup and anim.pickup:Exists() then
            anim.lightSprite:Render(Isaac.WorldToScreen(anim.pos))
        end
    end
end

-- Only explicitly approved profiles replace the flag template. Per-pedestal
-- state belongs to the upgrade transaction, never the shared ItemData row.
Template.forItem = function(key, flag)
    MorphVisuals = MorphVisuals or require("scripts.lib.upgrade_visuals")
    if not MorphVisuals.isApplied(key) then return Template[flag] end
    local function begin(phase, pos, pickup, state)
        local scene = state.morphScene
        local bound, pickupVisual = pcall(PickupVisual.bind, pickup)
        if not bound then
            -- Older/foreign sprites without exact layer access keep the native
            -- flag animation. Never conceal the whole pedestal as a fallback.
            if not state.morphFallback then
                ConchBlessing.printError("[ConchMorph] " .. key .. ": " .. tostring(pickupVisual))
            end
            state.morphFallback = true
            return Template[flag][phase == "before" and "onBeforeChange" or "onAfterChange"](pos, pickup, state)
        end
        if phase == "before" then
            local ok, result = pcall(MorphVisuals.create, key, pos, pickup.Variant, pickup.SubType, nil, state.visualOwner)
            if not ok then
                ConchBlessing.printError("[ConchMorph] " .. key .. ": " .. tostring(result))
                state.morphFallback = true
                return Template[flag].onBeforeChange(pos, pickup, state)
            end
            scene = result
            state.morphScene = scene
        elseif state.morphFallback or not scene or scene.failed then
            return Template[flag].onAfterChange(pos, pickup, state)
        else
            scene.frame = scene.impact
            -- A rotating pedestal may commit a different visible cycle head.
            local ok, icon = pcall(MorphVisuals.icon, pickup.Variant, pickup.SubType)
            if ok then scene.after = icon; scene.targetVariant = pickup.Variant end
        end
        local frames = phase == "before" and scene.impact or scene.duration - scene.impact
        local anim = { type = "custom", phase = phase, frames = frames,
            pos = pos, pickup = pickup, originalColor = getPickupColor(pickup), morphScene = scene,
            pickupVisual = pickupVisual,
            expectedVariant = pickup.Variant, expectedSubType = pickup.SubType }
        -- A chained presentation inherits the real visibility, not the old
        -- animation's temporary hidden head. Each native Morph binds anew.
        for _, existing in ipairs(Template._activeAnimations) do
            if matchesPickup(existing, pickup) and existing.pickupVisual then
                pickupVisual.visible = existing.pickupVisual.visible
            end
        end
        registerAnimation(state, anim)
        scene.pickupVisual = pickupVisual
        if phase == "after" and scene.profile.nativeResult then
            -- The result has no item transform left to animate. Let the
            -- engine display it from the commit, while surrounding art ends.
            PickupVisual.release(pickupVisual)
        else
            PickupVisual.hide(pickupVisual)
        end
        return frames
    end
    return {
        onBeforeChange = function(pos, pickup, state) return begin("before", pos, pickup, state) end,
        onAfterChange = function(pos, pickup, state) return begin("after", pos, pickup, state) end,
    }
end

Template.clearAnimations = function()
    local active = Template._activeAnimations
    for i = #active, 1, -1 do
        local anim = active[i]
        local sprite = anim.pickup and anim.pickup:Exists() and anim.pickup:GetSprite() or nil
        finishAnimation(anim, sprite)
        active[i] = nil
    end
end

Template.onUpdate = function(itemData)
    local anim = itemData and itemData.upgradeAnim or nil
    if not anim or anim._centralManaged then
        return
    end
    if updateAnimation(anim) and itemData then
        itemData.upgradeAnim = nil
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
