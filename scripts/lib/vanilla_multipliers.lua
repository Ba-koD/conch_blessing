-- Vanilla Item Damage Multipliers Table
-- Based on Epiphany mod's collectible_damage_multipliers.lua (Repentance+ accurate)
-- This table is used to calculate bonus damage with vanilla item multipliers
-- Does NOT affect the mod's multiplier display system (stats.lua)

ConchBlessing.VanillaMultipliers = {}

-- Damage multipliers for vanilla collectibles (Rep+ accurate, from Epiphany)
ConchBlessing.VanillaMultipliers.CollectibleDamage = {
    [CollectibleType.COLLECTIBLE_MEGA_MUSH] = function(player)
        if not player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_MEGA_MUSH) then return 1 end
        return 4
    end,
    [CollectibleType.COLLECTIBLE_CRICKETS_HEAD] = 1.5,
    [CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM] = function(player)
        -- Cricket's Head/Blood of the Martyr/Magic Mushroom don't stack with each other
        if player:HasCollectible(CollectibleType.COLLECTIBLE_CRICKETS_HEAD) then return 1 end
        return 1.5
    end,
    [CollectibleType.COLLECTIBLE_BLOOD_OF_THE_MARTYR] = function(player)
        if not player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL) then return 1 end

        -- Cricket's Head/Blood of the Martyr/Magic Mushroom don't stack with each other
        if player:HasCollectible(CollectibleType.COLLECTIBLE_CRICKETS_HEAD)
            or player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM)
        then
            return 1
        end
        return 1.5
    end,
    [CollectibleType.COLLECTIBLE_POLYPHEMUS] = 2,
    [CollectibleType.COLLECTIBLE_SACRED_HEART] = 2.3,
    [CollectibleType.COLLECTIBLE_EVES_MASCARA] = 2,
    [CollectibleType.COLLECTIBLE_ODD_MUSHROOM_THIN] = 0.9,
    [CollectibleType.COLLECTIBLE_20_20] = 0.75,
    [CollectibleType.COLLECTIBLE_SOY_MILK] = function(player)
        -- Almond Milk overrides Soy Milk
        if player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK) then return 1 end
        return 0.2
    end,
    [CollectibleType.COLLECTIBLE_CROWN_OF_LIGHT] = function(player)
        if player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_CROWN_OF_LIGHT) then return 2 end
        return 1
    end,
    [CollectibleType.COLLECTIBLE_ALMOND_MILK] = 0.33,
    [CollectibleType.COLLECTIBLE_IMMACULATE_HEART] = 1.2,
}

-- Character-specific damage multipliers (Rep+ accurate, from Epiphany)
ConchBlessing.VanillaMultipliers.CharacterDamage = {
    -- Normal characters
    [PlayerType.PLAYER_ISAAC] = 1,
    [PlayerType.PLAYER_MAGDALENE] = 1,
    [PlayerType.PLAYER_CAIN] = 1.2,
    [PlayerType.PLAYER_JUDAS] = 1.35,
    [PlayerType.PLAYER_BLUEBABY] = 1.05,
    [PlayerType.PLAYER_EVE] = function(player)
        if player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_WHORE_OF_BABYLON) then return 1 end
        return 0.75
    end,
    [PlayerType.PLAYER_SAMSON] = 1,
    [PlayerType.PLAYER_AZAZEL] = 1.5,
    [PlayerType.PLAYER_LAZARUS] = 1,
    [PlayerType.PLAYER_EDEN] = 1,
    [PlayerType.PLAYER_THELOST] = 1,
    [PlayerType.PLAYER_LAZARUS2] = 1.4,
    [PlayerType.PLAYER_BLACKJUDAS] = 2,
    [PlayerType.PLAYER_LILITH] = 1,
    [PlayerType.PLAYER_KEEPER] = 1.2,
    [PlayerType.PLAYER_APOLLYON] = 1,
    [PlayerType.PLAYER_THEFORGOTTEN] = 1.5,
    [PlayerType.PLAYER_THESOUL] = 1,
    [PlayerType.PLAYER_BETHANY] = 1,
    [PlayerType.PLAYER_JACOB] = 1,
    [PlayerType.PLAYER_ESAU] = 1,

    -- Tainted characters
    [PlayerType.PLAYER_ISAAC_B] = 1,
    [PlayerType.PLAYER_MAGDALENE_B] = 0.75,
    [PlayerType.PLAYER_CAIN_B] = 1,
    [PlayerType.PLAYER_JUDAS_B] = 1,
    [PlayerType.PLAYER_BLUEBABY_B] = 1,
    [PlayerType.PLAYER_EVE_B] = 1.2,
    [PlayerType.PLAYER_SAMSON_B] = 1,
    [PlayerType.PLAYER_AZAZEL_B] = 1.5,
    [PlayerType.PLAYER_LAZARUS_B] = 1,
    [PlayerType.PLAYER_EDEN_B] = 1,
    [PlayerType.PLAYER_THELOST_B] = 1.3,
    [PlayerType.PLAYER_LILITH_B] = 1,
    [PlayerType.PLAYER_KEEPER_B] = 1,
    [PlayerType.PLAYER_APOLLYON_B] = 1,
    [PlayerType.PLAYER_THEFORGOTTEN_B] = 1.5,
    [PlayerType.PLAYER_BETHANY_B] = 1,
    [PlayerType.PLAYER_JACOB_B] = 1,
    [PlayerType.PLAYER_LAZARUS2_B] = 1.5,
}

-- Get total damage multiplier from vanilla items for a player
---@param player EntityPlayer
---@return number totalMultiplier
function ConchBlessing.VanillaMultipliers:GetPlayerDamageMultiplier(player)
    if not player then return 1.0 end
    
    -- Start with character multiplier
    local charMult = self.CharacterDamage[player:GetPlayerType()]
    local totalMultiplier = 1.0
    
    if charMult then
        if type(charMult) == "function" then
            totalMultiplier = charMult(player)
        else
            totalMultiplier = charMult
        end
    end
    
    -- Apply collectible multipliers
    local effects = player:GetEffects()
    for itemID, mult in pairs(self.CollectibleDamage) do
        if player:HasCollectible(itemID) or effects:HasCollectibleEffect(itemID) then
            local actualMult = mult
            if type(mult) == "function" then
                actualMult = mult(player)
            end
            totalMultiplier = totalMultiplier * actualMult
        end
    end
    
    return totalMultiplier
end

-- Get total fire rate multiplier from vanilla items (Rep+ accurate)
---@param player EntityPlayer
---@return number totalMultiplier
function ConchBlessing.VanillaMultipliers:GetPlayerFireRateMultiplier(player)
    if not player then return 1.0 end
    
    local multi = 1.0
    local playerType = player:GetPlayerType()
    
    -- Character-specific fire rate multipliers
    if playerType == PlayerType.PLAYER_THEFORGOTTEN or playerType == PlayerType.PLAYER_THEFORGOTTEN_B then
        multi = multi * 0.5
    end
    -- T.Eve has no fire rate multiplier
    
    -- Soy Milk / Almond Milk
    if player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK) then
        multi = multi * 4
    elseif player:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK) then
        multi = multi * 5.5
    end
    
    -- Polyphemus
    if player:HasCollectible(CollectibleType.COLLECTIBLE_POLYPHEMUS) then
        multi = multi * 0.42
    end
    
    -- Eve's Mascara (0.66x, not 0.5x)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_EVES_MASCARA) then
        multi = multi * 0.66
    end
    
    -- Monstro's Lung
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) then
        multi = multi * 0.23
    end
    
    -- Brimstone
    if player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        multi = multi * 0.33
    end
    
    -- Chocolate Milk has no fire rate multiplier (charge-based)
    
    return multi
end

-- Apply bonus damage with vanilla multiplier consideration
---@param player EntityPlayer
---@param bonusDamage number The bonus damage to add
---@return number actualBonus The actual bonus applied (with multiplier)
function ConchBlessing.VanillaMultipliers:ApplyBonusDamage(player, bonusDamage)
    if not player or type(bonusDamage) ~= "number" then return 0 end
    
    local multiplier = self:GetPlayerDamageMultiplier(player)
    local actualBonus = bonusDamage * multiplier
    
    player.Damage = player.Damage + actualBonus
    
    ConchBlessing.printDebug(string.format("[VanillaMultipliers] Applied bonus damage: %.2f * %.2fx = %.2f", 
        bonusDamage, multiplier, actualBonus))
    
    return actualBonus
end

-- Check if a specific item affects damage multiplier
---@param itemID CollectibleType
---@return boolean
function ConchBlessing.VanillaMultipliers:HasDamageMultiplier(itemID)
    return self.CollectibleDamage[itemID] ~= nil
end

-- Get the damage multiplier for a specific item
---@param player EntityPlayer
---@param itemID CollectibleType
---@return number
function ConchBlessing.VanillaMultipliers:GetItemDamageMultiplier(player, itemID)
    local mult = self.CollectibleDamage[itemID]
    if not mult then return 1.0 end
    
    if type(mult) == "function" then
        return mult(player)
    end
    return mult
end

ConchBlessing.printDebug("Vanilla Multipliers table loaded successfully! (Rep+ accurate from Epiphany)")
