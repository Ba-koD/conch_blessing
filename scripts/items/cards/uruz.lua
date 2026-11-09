local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Uruz (ᚢ, "aurochs", strength): Tyrfing's rune (user design 2026-11-09).
--
-- For the rest of the room it is used in, every monster that dies there gives
-- the user +0.05 damage for good: Tyrfing's kill reward, counted the way
-- Tyrfing counts it (every monster death, whoever dealt the blow). Unlike
-- Tyrfing's total, a hit never takes any of it away. Each further use in the
-- same room adds the reward once more, as another Tyrfing copy would; leaving
-- the room ends it, like any room card (its EID reads like The Magician's and
-- does not spell that out). What was earned lives in the user's own run save,
-- so Continue keeps it and a co-op partner earns nothing from it.
local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local EnemyUtils = require("scripts.lib.enemy_utils")

ConchBlessing.uruz = ConchBlessing.uruz or {}
local M = ConchBlessing.uruz

M.data = {
    damagePerKill = 0.05, -- Tyrfing's reward a kill
}

local SAVE_KEY = "uruz"
local CARD = ConchBlessing.PocketData and ConchBlessing.PocketData.URUZ and ConchBlessing.PocketData.URUZ.id or -1

local active = {} -- [GetPtrHash(player)] = { ref = EntityPtr(player), uses = n }: this room only
local started = false

local evidence
local function resetEvidence()
    evidence = { uses = 0, kills = 0, rewards = 0 }
end
resetEvidence()

local function acting(player)
    if not player or not player:Exists() or player:IsDead() then return false end
    return not (type(player.IsCoopGhost) == "function" and player:IsCoopGhost())
end

local function saveReady()
    return started and SaveManager and (type(SaveManager.IsLoaded) ~= "function" or SaveManager.IsLoaded())
end

--- What this player has earned, or nil before any Uruz kill (never creates it).
function M.earned(player)
    if not saveReady() then return nil end
    local save = SaveManager.GetRunSave(player)
    local data = type(save) == "table" and save[SAVE_KEY]
    return type(data) == "table" and data or nil
end

local function ledger(player)
    if not saveReady() then return nil end
    local save = SaveManager.GetRunSave(player)
    if type(save) ~= "table" then return nil end
    local data = save[SAVE_KEY]
    if type(data) ~= "table" then
        data = { damage = 0, kills = 0 }
        save[SAVE_KEY] = data
    end
    data.damage = tonumber(data.damage) or 0
    data.kills = tonumber(data.kills) or 0
    return data
end

--- How many times this player used Uruz in the current room (0 when none).
function M.uses(player)
    local entry = player and active[GetPtrHash(player)]
    return entry and entry.uses or 0
end

-- MC_USE_CARD runs for a copy from Blank Card or Clear Rune too, with the
-- triggering player.
function M.onUseCard(_, card, player)
    if card ~= CARD or not player then return end
    local key = GetPtrHash(player)
    local entry = active[key]
    if entry and entry.ref.Ref then
        entry.uses = entry.uses + 1
    else
        active[key] = { ref = EntityPtr(player), uses = 1 }
    end
    evidence.uses = evidence.uses + 1
end

-- A monster dies in the room: every user of this room's Uruz earns the reward.
function M.onNpcDeath(_, npc)
    if next(active) == nil or not npc or not EnemyUtils.isMonsterKind(npc) then return end
    evidence.kills = evidence.kills + 1
    for key, entry in pairs(active) do
        local player = entry.ref.Ref and entry.ref.Ref:ToPlayer()
        if not player then
            active[key] = nil
        elseif acting(player) then
            local data = ledger(player)
            if data then
                data.damage = data.damage + M.data.damagePerKill * entry.uses
                data.kills = data.kills + 1
                evidence.rewards = evidence.rewards + 1
                player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
                player:EvaluateItems()
            end
        end
    end
end

function M.onEvaluateCache(_, player, flag)
    if flag ~= CacheFlag.CACHE_DAMAGE then return end
    local data = M.earned(player)
    local damage = data and tonumber(data.damage) or 0
    if damage > 0 then ConchBlessing.stats.damage.applyAddition(player, damage, nil) end
end

function M.onNewRoom()
    active = {}
end

function M.onGameStarted()
    started = true
    active = {}
    -- the first cache pass of a Continue ran before the run save was readable
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and M.earned(player) then
            player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
            player:EvaluateItems()
        end
    end
end

function M.onGameExit()
    started = false
    active = {}
end

M._test = {
    started = function() return started end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    active = function() return active end,
    card = function() return CARD end,
}

if CARD > 0 then
    ConchBlessing:AddCallback(ModCallbacks.MC_USE_CARD, M.onUseCard, CARD)
end
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, M.onNpcDeath)
ConchBlessing:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, M.onEvaluateCache, CacheFlag.CACHE_DAMAGE)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, M.onNewRoom)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, M.onGameStarted)
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, M.onGameExit)
do
    local sm, mod = SaveManager, ConchBlessing.originalMod
    if sm and mod and mod.__SAVEMANAGER_UNIQUE_KEY and sm.SaveCallbacks and sm.SaveCallbacks.POST_DATA_LOAD then
        -- a luamod reload in the middle of a run never sees game start
        mod:AddCallback(sm.SaveCallbacks.POST_DATA_LOAD, function(_, _, isLuamod)
            if isLuamod then M.onGameStarted() end
        end)
    end
end

return M
