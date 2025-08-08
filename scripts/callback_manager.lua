-- Callback Manager for Conch's Blessing
-- Handles automatic callback registration for items

ConchBlessing.CallbackManager = {}
ConchBlessing.CallbackManager._didRegisterThisRun = false

-- Callback mapping table
-- Left side: callback abbreviation in ItemData
-- Right side: actual ModCallbacks enum and function path
ConchBlessing.CallbackManager.callbackMapping = {
    -- Item-specific callbacks (require item ID)
    pickup = { callback = ModCallbacks.MC_POST_PICKUP_INIT, needsId = true },
    use = { callback = ModCallbacks.MC_USE_ITEM, needsId = true },
    
    -- Global callbacks (no item ID needed)
    tearInit = { callback = ModCallbacks.MC_POST_TEAR_INIT, needsId = false },
    tearUpdate = { callback = ModCallbacks.MC_POST_TEAR_UPDATE, needsId = false },
    fireTear = { callback = ModCallbacks.MC_POST_FIRE_TEAR, needsId = false },
    tearCollision = { callback = ModCallbacks.MC_PRE_TEAR_COLLISION, needsId = false },
    tearRemoved = { callback = ModCallbacks.MC_POST_ENTITY_REMOVE, needsId = false },
    gameStarted = { callback = ModCallbacks.MC_POST_GAME_STARTED, needsId = false },
    update = { callback = ModCallbacks.MC_POST_UPDATE, needsId = false },
    
    -- All ModCallbacks from Isaac API
    npcUpdate = { callback = ModCallbacks.MC_NPC_UPDATE, needsId = false },
    postUpdate = { callback = ModCallbacks.MC_POST_UPDATE, needsId = false },
    postRender = { callback = ModCallbacks.MC_POST_RENDER, needsId = false },
    useItem = { callback = ModCallbacks.MC_USE_ITEM, needsId = true },
    postPEffectUpdate = { callback = ModCallbacks.MC_POST_PEFFECT_UPDATE, needsId = false },
    useCard = { callback = ModCallbacks.MC_USE_CARD, needsId = false },
    familiarUpdate = { callback = ModCallbacks.MC_FAMILIAR_UPDATE, needsId = false },
    familiarInit = { callback = ModCallbacks.MC_FAMILIAR_INIT, needsId = false },
    evaluateCache = { callback = ModCallbacks.MC_EVALUATE_CACHE, needsId = false },
    postPlayerInit = { callback = ModCallbacks.MC_POST_PLAYER_INIT, needsId = false },
    usePill = { callback = ModCallbacks.MC_USE_PILL, needsId = false },
    entityTakeDmg = { callback = ModCallbacks.MC_ENTITY_TAKE_DMG, needsId = false },
    postCurseEval = { callback = ModCallbacks.MC_POST_CURSE_EVAL, needsId = false },
    inputAction = { callback = ModCallbacks.MC_INPUT_ACTION, needsId = false },
    levelGenerator = { callback = ModCallbacks.MC_LEVEL_GENERATOR, needsId = false },
    postGameStarted = { callback = ModCallbacks.MC_POST_GAME_STARTED, needsId = false },
    postGameEnd = { callback = ModCallbacks.MC_POST_GAME_END, needsId = false },
    preGameExit = { callback = ModCallbacks.MC_PRE_GAME_EXIT, needsId = false },
    postNewLevel = { callback = ModCallbacks.MC_POST_NEW_LEVEL, needsId = false },
    postNewRoom = { callback = ModCallbacks.MC_POST_NEW_ROOM, needsId = false },
    getCard = { callback = ModCallbacks.MC_GET_CARD, needsId = false },
    getShaderParams = { callback = ModCallbacks.MC_GET_SHADER_PARAMS, needsId = false },
    executeCmd = { callback = ModCallbacks.MC_EXECUTE_CMD, needsId = false },
    preUseItem = { callback = ModCallbacks.MC_PRE_USE_ITEM, needsId = true },
    preEntitySpawn = { callback = ModCallbacks.MC_PRE_ENTITY_SPAWN, needsId = false },
    postFamiliarRender = { callback = ModCallbacks.MC_POST_FAMILIAR_RENDER, needsId = false },
    preFamiliarCollision = { callback = ModCallbacks.MC_PRE_FAMILIAR_COLLISION, needsId = false },
    postNPCInit = { callback = ModCallbacks.MC_POST_NPC_INIT, needsId = false },
    postNPCRender = { callback = ModCallbacks.MC_POST_NPC_RENDER, needsId = false },
    postNPCDeath = { callback = ModCallbacks.MC_POST_NPC_DEATH, needsId = false },
    preNPCCollision = { callback = ModCallbacks.MC_PRE_NPC_COLLISION, needsId = false },
    postPlayerUpdate = { callback = ModCallbacks.MC_POST_PLAYER_UPDATE, needsId = false },
    postPlayerRender = { callback = ModCallbacks.MC_POST_PLAYER_RENDER, needsId = false },
    prePlayerCollision = { callback = ModCallbacks.MC_PRE_PLAYER_COLLISION, needsId = false },
    postPickupInit = { callback = ModCallbacks.MC_POST_PICKUP_INIT, needsId = false },
    postPickupUpdate = { callback = ModCallbacks.MC_POST_PICKUP_UPDATE, needsId = false },
    postPickupRender = { callback = ModCallbacks.MC_POST_PICKUP_RENDER, needsId = false },
    postPickupSelection = { callback = ModCallbacks.MC_POST_PICKUP_SELECTION, needsId = false },
    prePickupCollision = { callback = ModCallbacks.MC_PRE_PICKUP_COLLISION, needsId = false },
    postTearInit = { callback = ModCallbacks.MC_POST_TEAR_INIT, needsId = false },
    postTearUpdate = { callback = ModCallbacks.MC_POST_TEAR_UPDATE, needsId = false },
    postTearRender = { callback = ModCallbacks.MC_POST_TEAR_RENDER, needsId = false },
    preTearCollision = { callback = ModCallbacks.MC_PRE_TEAR_COLLISION, needsId = false },
    postProjectileInit = { callback = ModCallbacks.MC_POST_PROJECTILE_INIT, needsId = false },
    postProjectileUpdate = { callback = ModCallbacks.MC_POST_PROJECTILE_UPDATE, needsId = false },
    postProjectileRender = { callback = ModCallbacks.MC_POST_PROJECTILE_RENDER, needsId = false },
    preProjectileCollision = { callback = ModCallbacks.MC_PRE_PROJECTILE_COLLISION, needsId = false },
    postLaserInit = { callback = ModCallbacks.MC_POST_LASER_INIT, needsId = false },
    postLaserUpdate = { callback = ModCallbacks.MC_POST_LASER_UPDATE, needsId = false },
    postLaserRender = { callback = ModCallbacks.MC_POST_LASER_RENDER, needsId = false },
    postKnifeInit = { callback = ModCallbacks.MC_POST_KNIFE_INIT, needsId = false },
    postKnifeUpdate = { callback = ModCallbacks.MC_POST_KNIFE_UPDATE, needsId = false },
    postKnifeRender = { callback = ModCallbacks.MC_POST_KNIFE_RENDER, needsId = false },
    preKnifeCollision = { callback = ModCallbacks.MC_PRE_KNIFE_COLLISION, needsId = false },
    postEffectInit = { callback = ModCallbacks.MC_POST_EFFECT_INIT, needsId = false },
    postEffectUpdate = { callback = ModCallbacks.MC_POST_EFFECT_UPDATE, needsId = false },
    postEffectRender = { callback = ModCallbacks.MC_POST_EFFECT_RENDER, needsId = false },
    postBombInit = { callback = ModCallbacks.MC_POST_BOMB_INIT, needsId = false },
    postBombUpdate = { callback = ModCallbacks.MC_POST_BOMB_UPDATE, needsId = false },
    postBombRender = { callback = ModCallbacks.MC_POST_BOMB_RENDER, needsId = false },
    preBombCollision = { callback = ModCallbacks.MC_PRE_BOMB_COLLISION, needsId = false },
    postFireTear = { callback = ModCallbacks.MC_POST_FIRE_TEAR, needsId = false },
    preGetCollectible = { callback = ModCallbacks.MC_PRE_GET_COLLECTIBLE, needsId = false },
    postGetCollectible = { callback = ModCallbacks.MC_POST_GET_COLLECTIBLE, needsId = false },
    getPillColor = { callback = ModCallbacks.MC_GET_PILL_COLOR, needsId = false },
    getPillEffect = { callback = ModCallbacks.MC_GET_PILL_EFFECT, needsId = false },
    getTrinket = { callback = ModCallbacks.MC_GET_TRINKET, needsId = false },
    postEntityRemove = { callback = ModCallbacks.MC_POST_ENTITY_REMOVE, needsId = false },
    postEntityKill = { callback = ModCallbacks.MC_POST_ENTITY_KILL, needsId = false },
    preNPCUpdate = { callback = ModCallbacks.MC_PRE_NPC_UPDATE, needsId = false },
    preSpawnCleanAward = { callback = ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, needsId = false },
    preRoomEntitySpawn = { callback = ModCallbacks.MC_PRE_ROOM_ENTITY_SPAWN, needsId = false },
    preEntityDevolve = { callback = ModCallbacks.MC_PRE_ENTITY_DEVOLVE, needsId = false },
    preModUnload = { callback = ModCallbacks.MC_PRE_MOD_UNLOAD, needsId = false }
}

-- Helper function to find functions by dot notation
ConchBlessing.CallbackManager.getFunctionByPath = function(path)
    local parts = {}
    for part in path:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    
    local current = ConchBlessing
    for _, part in ipairs(parts) do
        if current and current[part] then
            current = current[part]
        else
            return nil
        end
    end
    return current
end

-- Register callbacks for a single item
ConchBlessing.CallbackManager.registerItemCallbacks = function(itemKey, itemData)
    ConchBlessing.printDebug("Registering callbacks for: " .. itemKey)
    
    if not itemData.callbacks then
        ConchBlessing.printDebug("  No callbacks defined for " .. itemKey)
        return
    end
    
    local itemId = itemData.id
    
    -- Check if item ID is valid for ID-required callbacks
    if itemId == -1 or itemId == nil then
        ConchBlessing.printError("  Warning: " .. itemKey .. " has an invalid item ID (" .. tostring(itemId) .. "). Skipping ID-required callbacks.")
        ConchBlessing.printError("  Check if the item is properly registered in the XML file.")
    else
        ConchBlessing.printDebug("  Item ID check: " .. itemKey .. " = " .. itemId)
    end
    
    -- Register each callback
    for callbackKey, functionPath in pairs(itemData.callbacks) do
        local callbackInfo = ConchBlessing.CallbackManager.callbackMapping[callbackKey]
        
        if not callbackInfo then
            ConchBlessing.printError("  Warning: Unknown callback type '" .. callbackKey .. "' for " .. itemKey)
            goto continue
        end
        
        -- Check if callback needs valid item ID
        if callbackInfo.needsId and (itemId == -1 or itemId == nil) then
            ConchBlessing.printError("  Warning: Skipping " .. callbackKey .. " callback for " .. itemKey .. " - invalid item ID")
            goto continue
        end
        
        -- Find the actual function
        local func = ConchBlessing.CallbackManager.getFunctionByPath(functionPath)
        if not func then
            ConchBlessing.printError("  Warning: " .. tostring(functionPath) .. " function is not defined for " .. itemKey)
            goto continue
        end
        
        -- Register the callback
        if callbackInfo.needsId then
            ConchBlessing:AddCallback(callbackInfo.callback, func, itemId)
            ConchBlessing.printDebug("  " .. callbackKey .. " callback registered (ID: " .. itemId .. ")")
        else
            ConchBlessing:AddCallback(callbackInfo.callback, func)
            ConchBlessing.printDebug("  " .. callbackKey .. " callback registered")
        end
        
        ::continue::
    end
end

-- Register callbacks for all items
ConchBlessing.CallbackManager.registerAllCallbacks = function()
    if ConchBlessing.CallbackManager._didRegisterThisRun then
        ConchBlessing.printDebug("Callbacks already registered for this run; skipping.")
        return
    end
    ConchBlessing.printDebug("Registering callbacks for all items...")
    
    for itemKey, itemData in pairs(ConchBlessing.ItemData) do
        ConchBlessing.CallbackManager.registerItemCallbacks(itemKey, itemData)
    end
    
    ConchBlessing.CallbackManager._didRegisterThisRun = true
    ConchBlessing.printDebug("All callbacks registered successfully!")
end

-- Auto-register when mod loads
ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    ConchBlessing.CallbackManager.registerAllCallbacks()
end) 