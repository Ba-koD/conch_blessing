-- Shared answer to "is this NPC a monster?"
--
-- Entity:IsEnemy() says yes to a lot of room furniture as well - fires, shopkeepers,
-- machines, beggars, wall fixtures - so anything that acts on enemies or pays the player
-- per enemy needs a stricter answer than that flag on its own. Two items in this mod
-- learned that the hard way: one cleaved the furniture in half, the other counted a
-- stomped fire as a kill.

local M = {}

-- NPC types that answer IsEnemy() with true while being furniture rather than monsters.
-- Looked up by name so a constant an older API version lacks is skipped instead of
-- raising a nil table index while this file loads.
local NON_MONSTER_TYPE_NAMES = {
    "ENTITY_SLOT",                   -- machines and beggars
    "ENTITY_SHOPKEEPER",
    "ENTITY_FIREPLACE",
    "ENTITY_MOVABLE_TNT",
    "ENTITY_GENERIC_PROP",
    "ENTITY_DUMMY",
    "ENTITY_MINECART",
    "ENTITY_STONEHEAD",              -- wall fixtures: they cannot be moved or displaced
    "ENTITY_CONSTANT_STONE_SHOOTER",
    "ENTITY_BRIMSTONE_HEAD",
    "ENTITY_GAPING_MAW",
    "ENTITY_BROKEN_GAPING_MAW",
    "ENTITY_QUAKE_GRIMACE",
    "ENTITY_BOMB_GRIMACE",
}

local NON_MONSTER_TYPES = {}
for _, name in ipairs(NON_MONSTER_TYPE_NAMES) do
    local value = EntityType[name]
    if type(value) == "number" then
        NON_MONSTER_TYPES[value] = true
    end
end

M.NON_MONSTER_TYPES = NON_MONSTER_TYPES

---True when this NPC is a monster rather than furniture or an ally.
---Nothing here reads the NPC's current state, so the answer still holds in a death
---callback, where a corpse reports itself as neither active nor damageable.
---@param npc EntityNPC|nil
---@return boolean
function M.isMonsterKind(npc)
    if not npc then return false end
    if npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return false end
    if NON_MONSTER_TYPES[npc.Type] then return false end
    return npc:IsEnemy()
end

---True when this NPC is a monster that is alive and can be fought right now.
---IsActiveEnemy is the engine's own "does this hold the room open" answer and
---IsVulnerableEnemy its "can this be hurt" answer.
---@param npc EntityNPC|nil
---@return boolean
function M.isLiveMonster(npc)
    if not M.isMonsterKind(npc) then return false end
    if npc:IsDead() then return false end
    if not npc:IsVulnerableEnemy() then return false end
    return npc:IsActiveEnemy(false)
end

return M
