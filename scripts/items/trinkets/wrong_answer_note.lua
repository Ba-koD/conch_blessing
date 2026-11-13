local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 오답노트 (Wrong Answer Note): the Magic Conch's neutral answer to Perfection
-- (user design 2026-11-09). Perfection breaks on the first hit; the note learns
-- from every hit instead.
--
-- Each hit the holder takes writes down the kind of enemy (its type and
-- variant) that dealt it, and the holder's attacks then deal +50% damage to
-- that kind, more with every further hit from it. A floor passed without a hit
-- adds +25% damage against every enemy. Both steps scale with the trinket
-- multiplier (golden or Mom's Box: 100% / 50%, both: 150% / 75%; more copies
-- add the same way). What was written down stays with the player for the run
-- and works while they hold (or have smelted) a note.
--
-- A hit is what scripts/lib/player_hits.lua counts. The enemy behind it is the
-- hitting NPC itself, or whoever spawned or parents the projectile, creep or
-- laser that hit; a hit with no enemy behind it (spikes, the player's own
-- bomb) is not written down. The extra damage multiplies the hit as it lands,
-- in REPENTOGON's MC_ENTITY_TAKE_DMG at LATE priority returning
-- { Damage = ... }, so it applies after other mods have set the amount and only
-- once; the base API cannot change a hit's damage, so without REPENTOGON the
-- note does nothing (its EID says so).
--
-- When an enemy of a written-down kind appears, a small red "+N%" (its kind's
-- bonus) pops above it for a moment; when a no-hit floor grows the all-enemy
-- bonus, a gold "+N%" pops above the holder once. The markers are cosmetic,
-- drawn with the vanilla font, and freeze while the game is paused.
local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local Hits = require("scripts.lib.player_hits")
local TrinketUtils = ConchBlessing.TrinketUtils or require("scripts.lib.trinket_utils")
local DamageProvenance = require("scripts.lib.damage_provenance")
local EnemyUtils = require("scripts.lib.enemy_utils")

ConchBlessing.wronganswernote = ConchBlessing.wronganswernote or {}
local M = ConchBlessing.wronganswernote

local SAVE_KEY = "wrongAnswerNote"

M.data = {
    kindStep = 0.5,     -- +50% per hit from a kind, per trinket multiplier
    floorStep = 0.25,   -- +25% against all enemies per no-hit floor, per multiplier
    markerFrames = 80,  -- render frames a marker stays (pop, hold, fade)
    -- the marker's top sits (lift + Size x sizeLift) x SpriteScale.Y px above the
    -- feet: clear of a gaper's or Isaac's head (about 33 px tall), checked in a
    -- preview drawn with the vanilla font and sprites (2026-11-09)
    lift = 32,
    sizeLift = 1.3,
    popFrames = 6,
    fadeFrames = 24,
}

local started = false
local markers = {}      -- { ref = EntityPtr, text, color, age }
local endedFloor = nil  -- [GetPtrHash(player)] = true when the ending floor had no hit
local font = nil
local reported = {}

local evidence
local function resetEvidence()
    evidence = { noted = 0, boosted = 0, floors = 0, markers = 0, lastBonus = 0, lastAmount = 0, lastDamage = 0 }
end
resetEvidence()

local function reportOnce(key, message)
    if reported[key] then return end
    reported[key] = true
    ConchBlessing.printError("[Wrong Answer Note] " .. message)
end

local function trinketId()
    local row = ConchBlessing.ItemData and ConchBlessing.ItemData.WRONG_ANSWER_NOTE
    return row and row.id or -1
end

--- How strongly this player holds notes: the engine's trinket multiplier
--- (+1 a copy, +2 a golden one, +1 for Mom's Box; held or smelted).
function M.multiplier(player)
    local id = trinketId()
    if not player or id <= 0 then return 0 end
    return TrinketUtils.getMultiplier(player, id)
end

local function alive(player)
    if not player or not player:Exists() or player:IsDead() then return false end
    return not (type(player.IsCoopGhost) == "function" and player:IsCoopGhost())
end

--- The player's note for the run: { kinds = { ["type.variant"] = hits }, floors = n }.
function M.ledger(player)
    local save = SaveManager and SaveManager.GetRunSave(player)
    if type(save) ~= "table" then return nil end
    local note = save[SAVE_KEY]
    if type(note) ~= "table" then
        note = { kinds = {}, floors = 0 }
        save[SAVE_KEY] = note
    end
    note.kinds = type(note.kinds) == "table" and note.kinds or {}
    note.floors = tonumber(note.floors) or 0
    return note
end

function M.kindKey(entityType, variant)
    return string.format("%d.%d", entityType, variant or 0)
end

--- The enemy behind a hit: the hitting NPC, or the one that spawned or parents
--- the projectile, creep or laser. A source whose entity is gone (the enemy died
--- as its shot landed) still names its spawner's type.
function M.enemyKind(source)
    if not source then return nil end
    local entity = source.Entity
    if entity then
        for _ = 1, 12 do
            if not entity then break end
            local npc = entity.ToNPC and entity:ToNPC()
            if npc and EnemyUtils.isMonsterKind(npc) then return M.kindKey(npc.Type, npc.Variant) end
            if entity.ToPlayer and entity:ToPlayer() then return nil end -- the player's own bomb or laser
            entity = entity.SpawnerEntity or entity.Parent
        end
        return nil
    end
    for _, pair in ipairs({ { source.SpawnerType, source.SpawnerVariant }, { source.Type, source.Variant } }) do
        local entityType = tonumber(pair[1]) or 0
        if entityType >= 10 and entityType < 1000 and not EnemyUtils.NON_MONSTER_TYPES[entityType] then
            return M.kindKey(entityType, tonumber(pair[2]) or 0)
        end
    end
    return nil
end

--- The extra damage (a fraction: 0.5 = +50%) this player's attacks deal to `npc`.
function M.bonus(player, npc)
    local mult = M.multiplier(player)
    if mult <= 0 then return 0 end
    local note = M.ledger(player)
    if not note then return 0 end
    local hits = npc and note.kinds[M.kindKey(npc.Type, npc.Variant)] or 0
    return (hits * M.data.kindStep + note.floors * M.data.floorStep) * mult
end

local function kindBonus(player, key)
    local note = M.ledger(player)
    local hits = note and note.kinds[key] or 0
    return hits * M.data.kindStep * M.multiplier(player)
end

local function players()
    local list, game = {}, Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then list[#list + 1] = player end
    end
    return list
end

local function percent(fraction)
    return string.format("+%d%%", math.floor(fraction * 100 + 0.5))
end

local RED = { 1, 0.28, 0.25 }
local GOLD = { 1, 0.82, 0.3 }

local function addMarker(entity, text, color)
    if not entity or not entity:Exists() then return end
    local hash = GetPtrHash(entity)
    for _, marker in ipairs(markers) do
        if marker.hash == hash and marker.color == color then
            marker.text, marker.age = text, 0
            return
        end
    end
    markers[#markers + 1] = { ref = EntityPtr(entity), hash = hash, text = text, color = color, age = 0 }
    evidence.markers = evidence.markers + 1
end

-- The highest kind bonus any living holder has against this enemy.
local function shownKindBonus(npc)
    local key, best = M.kindKey(npc.Type, npc.Variant), 0
    for _, player in ipairs(players()) do
        if alive(player) then best = math.max(best, kindBonus(player, key)) end
    end
    return best
end

local function markEnemy(npc)
    local bonus = shownKindBonus(npc)
    if bonus > 0 then addMarker(npc, percent(bonus), RED) end
end

-- Its clean-floor bonus breaks on any hit; on the next floor it watches again.
Hits.watchFloor("WRONG_ANSWER_NOTE")

-- A hit is written down under the kind of enemy behind it.
Hits.register("WRONG_ANSWER_NOTE", function(_, entity, amount, flags, source)
    local player = entity and entity:ToPlayer()
    if not started or not player or not Hits.counts(flags) then return end
    if M.multiplier(player) <= 0 then return end
    local key = M.enemyKind(source)
    if not key then return end
    local note = M.ledger(player)
    if not note then return end
    note.kinds[key] = (note.kinds[key] or 0) + 1
    evidence.noted = evidence.noted + 1
    -- the grown number shows over that kind's enemies in the room
    for _, other in ipairs(Isaac.GetRoomEntities()) do
        local npc = other:ToNPC()
        if npc and M.kindKey(npc.Type, npc.Variant) == key and EnemyUtils.isMonsterKind(npc) and not npc:IsDead() then
            markEnemy(npc)
        end
    end
    return true
end)

-- MC_ENTITY_TAKE_DMG at LATE priority (REPENTOGON): the holder's attacks hit
-- noted kinds harder. Scaling `amount` keeps every earlier callback's change.
function M.onTakeDamageLate(_, entity, amount, flags, source, countdown, extraSource)
    if not started or not entity or (tonumber(amount) or 0) <= 0 then return end
    local npc = entity:ToNPC()
    if not npc or not EnemyUtils.isMonsterKind(npc) then return end
    local attack = DamageProvenance.getSourceEntity(source, extraSource)
    local player = attack and DamageProvenance.getPlayerOwner(attack)
    if not player or not alive(player) then return end
    local bonus = M.bonus(player, npc)
    if bonus <= 0 then return end
    evidence.boosted = evidence.boosted + 1
    evidence.lastBonus, evidence.lastAmount, evidence.lastDamage = bonus, amount, amount * (1 + bonus)
    return { Damage = amount * (1 + bonus) }
end

-- An enemy of a noted kind appears: its number pops above it.
function M.onNpcInit(_, npc)
    if not started or not npc or not EnemyUtils.isMonsterKind(npc) then return end
    markEnemy(npc)
end

-- A floor passed without a hit, while holding a note, adds to the all-enemy
-- bonus. Read just before SaveManager clears the floor saves (the floor's hit
-- flag is minus_chain's, set for every counted hit).
function M.onFloorEnding()
    endedFloor = nil
    if not started then return end
    local chain = ConchBlessing.minuschain
    if not (chain and type(chain.noHit) == "function") then
        reportOnce("chain", "the floor hit record is missing; no-hit floors cannot count")
        return
    end
    local result = {}
    for _, player in ipairs(players()) do
        if alive(player) and M.multiplier(player) > 0 and chain.noHit(player) then
            result[GetPtrHash(player)] = true
        end
    end
    endedFloor = result
end

function M.onNewLevel()
    local ended = endedFloor
    endedFloor = nil
    if not started or not ended then return end
    for _, player in ipairs(players()) do
        if ended[GetPtrHash(player)] then
            local note = M.ledger(player)
            if note then
                note.floors = note.floors + 1
                evidence.floors = evidence.floors + 1
                addMarker(player, percent(note.floors * M.data.floorStep * M.multiplier(player)), GOLD)
            end
        end
    end
end

local function loadFont()
    if font then return font end
    font = Font()
    font:Load("font/luaminioutlined.fnt")
    if not font:IsLoaded() then
        reportOnce("font", "the vanilla font did not load; markers are not drawn")
    end
    return font
end

function M.onRender()
    if #markers == 0 then return end
    local game = Game()
    local paused = game:IsPaused()
    local f = loadFont()
    local kept = {}
    for _, marker in ipairs(markers) do
        local entity = marker.ref.Ref
        if entity and entity:Exists() and marker.age < M.data.markerFrames then
            if not paused then marker.age = marker.age + 1 end
            kept[#kept + 1] = marker
            if f:IsLoaded() then
                -- pop: drop 6 px into place, clear of the head, and fade in at
                -- whole-pixel size (a fractional scale smears the pixel font),
                -- hold, then fade out
                local age, data = marker.age, M.data
                local alpha = age > data.markerFrames - data.fadeFrames
                    and (data.markerFrames - age) / data.fadeFrames
                    or age < data.popFrames and 0.35 + 0.65 * age / data.popFrames or 1
                local rise = age < data.popFrames and (data.popFrames - age) or 0
                local scale = 1
                local height = (data.lift + (entity.Size or 10) * data.sizeLift)
                    * (entity.SpriteScale and entity.SpriteScale.Y or 1)
                local at = Isaac.WorldToScreen(entity.Position + entity.PositionOffset)
                local c = marker.color
                local width = f:GetStringWidth(marker.text) * scale
                f:DrawStringScaled(marker.text, at.X - width / 2, at.Y - height - rise, scale, scale,
                    KColor(c[1], c[2], c[3], alpha), 0, false)
            end
        end
    end
    markers = kept
end

function M.onNewRoom()
    markers = {}
end

function M.onGameStarted()
    started = true
    markers, endedFloor = {}, nil
end

function M.onGameExit()
    started = false
    markers, endedFloor = {}, nil
end

M._test = {
    started = function() return started end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    markers = function() return markers end,
    kindKey = M.kindKey,
}

-- Registered here rather than through ItemData: a LATE-priority damage
-- callback, the SaveManager floor reset and a mid-run luamod start.
do
    local mod = ConchBlessing.originalMod or ConchBlessing
    local priority = rawget(_G, "CallbackPriority")
    local LATE = type(priority) == "table" and tonumber(priority.LATE) or 100
    if rawget(_G, "REPENTOGON") and ModCallbacks and ModCallbacks.MC_ENTITY_TAKE_DMG then
        if type(ConchBlessing.AddPriorityCallback) == "function" then
            ConchBlessing:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, LATE, M.onTakeDamageLate)
        else
            ConchBlessing:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, M.onTakeDamageLate)
        end
    end
    local sm = SaveManager
    if sm and mod and mod.__SAVEMANAGER_UNIQUE_KEY and sm.SaveCallbacks then
        if sm.SaveCallbacks.PRE_FLOOR_DATA_RESET then
            mod:AddCallback(sm.SaveCallbacks.PRE_FLOOR_DATA_RESET, M.onFloorEnding)
        end
        if sm.SaveCallbacks.POST_DATA_LOAD then
            -- a luamod reload in the middle of a run never sees game start
            mod:AddCallback(sm.SaveCallbacks.POST_DATA_LOAD, function(_, _, isLuamod)
                if isLuamod then M.onGameStarted() end
            end)
        end
    end
end

return M
