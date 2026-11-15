local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 오답노트 (Wrong Answer Note): the Magic Conch's neutral answer to Perfection
-- (user design 2026-11-09). Perfection breaks on the first hit; the note learns
-- from every hit instead.
--
-- Each hit the holder takes writes down the kind of enemy (its type and
-- variant) that dealt it, and the holder's attacks then deal +50% damage to
-- that kind, more with every further hit from it. A floor passed without a hit
-- adds +25% damage against every enemy. Each step is worth what the trinket
-- multiplier makes it at that moment (golden or Mom's Box: 100% / 50%, both:
-- 150% / 75%; more copies add the same way) and keeps that worth: a note made
-- golden later makes only the later steps bigger, and losing the golden copy
-- shrinks none (user rule 2026-11-15). What was written down stays with the
-- player for the run and works while they hold (or have smelted) a note.
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
-- While a living player holds a note, every enemy of a written-down kind shows
-- its kind's bonus in red above it, and a holder with an all-enemy bonus shows
-- it in gold above themselves, the whole time (user request 2026-11-15; they
-- used to pop up for a moment). A number pops in when it appears or grows. The
-- markers are cosmetic, drawn with the vanilla font.
local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local RunSaveCache = require("scripts.lib.run_save_cache")
local Hits = require("scripts.lib.player_hits")
local TrinketUtils = ConchBlessing.TrinketUtils or require("scripts.lib.trinket_utils")
local DamageProvenance = require("scripts.lib.damage_provenance")
local EnemyUtils = require("scripts.lib.enemy_utils")

ConchBlessing.wronganswernote = ConchBlessing.wronganswernote or {}
local M = ConchBlessing.wronganswernote

local SAVE_KEY = "wrongAnswerNote"
-- 2: kinds and `all` hold the bonus each step was worth when it was written
-- (before 2026-11-15 kinds held hit counts, scaled by the multiplier of the
-- moment they were read).
local VERSION = 2

M.data = {
    kindStep = 0.5,     -- +50% per hit from a kind, per trinket multiplier
    floorStep = 0.25,   -- +25% against all enemies per no-hit floor, per multiplier
    -- A monster's number sits `gap` px above the top of what the engine draws
    -- for it (REPENTOGON's frame data: Hush's face reaches 96 px above its
    -- position, while its size 100 put the number 162 px up, off the screen;
    -- user report 2026-11-15). A holder's number, and a monster's without that
    -- data, has its top (lift + Size x sizeLift) x SpriteScale.Y px above the
    -- feet: clear of a gaper's or Isaac's head (about 33 px tall), checked in a
    -- preview drawn with the vanilla font and sprites (2026-11-09).
    gap = 2,
    lift = 32,
    sizeLift = 1.3,
    -- a number never leaves the screen: it keeps this far from its edges
    edge = 4,
    lineHeight = 9,     -- the vanilla mini font's line, when it cannot say
    popFrames = 6,
    -- a holder's gold number moves up this far while player_hits' icons show
    -- over their head, and back down after
    iconRaise = 14,
}

local started = false
local tracked = {}      -- [GetPtrHash(npc)] = { ref = EntityPtr, key, text, age }: monsters in the room
local heads = {}        -- [GetPtrHash(player)] = { text, age, raise }: holders' gold numbers
local view = { frame = nil, kinds = {}, any = false, holders = {} }
local endedFloor = nil  -- [GetPtrHash(player)] = multiplier, when the ending floor had no hit
local font = nil
local reported = {}

local evidence
local function resetEvidence()
    evidence = { noted = 0, boosted = 0, floors = 0, lastGain = 0, lastBonus = 0, lastAmount = 0, lastDamage = 0 }
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

-- An older note kept hit counts; each becomes the bonus it showed then, at
-- the multiplier held now (at least one copy's worth).
local function normalize(note, player)
    note.kinds = type(note.kinds) == "table" and note.kinds or {}
    note.floors = tonumber(note.floors) or 0
    if note.v ~= VERSION then
        local mult = math.max(1, M.multiplier(player))
        for key, hits in pairs(note.kinds) do
            note.kinds[key] = (tonumber(hits) or 0) * M.data.kindStep * mult
        end
        note.all = note.floors * M.data.floorStep * mult
        note.v = VERSION
    end
    note.all = tonumber(note.all) or 0
    return note
end

--- The player's note for the run: { kinds = { ["type.variant"] = bonus },
--- all = bonus, floors = clean floors, v = 2 }, bonuses as fractions (0.5 =
--- +50%). Without `create` false, a player with no note gets an empty one.
function M.ledger(player, create)
    local save = RunSaveCache.player(player, create ~= false)
    if type(save) ~= "table" then return nil end
    local note = save[SAVE_KEY]
    if type(note) ~= "table" then
        if create == false then return nil end
        note = { kinds = {}, floors = 0, all = 0, v = VERSION }
        save[SAVE_KEY] = note
    end
    return normalize(note, player)
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
    if M.multiplier(player) <= 0 then return 0 end
    local note = M.ledger(player, false)
    if not note then return 0 end
    local kind = npc and note.kinds[M.kindKey(npc.Type, npc.Variant)] or 0
    return kind + note.all
end

local function players()
    local list, game = {}, Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then list[#list + 1] = player end
    end
    return list
end

local texts = {}
local function percent(fraction)
    local text = texts[fraction]
    if not text then
        text = string.format("+%d%%", math.floor(fraction * 100 + 0.5))
        texts[fraction] = text
    end
    return text
end

local RED = { 1, 0.28, 0.25 }
local GOLD = { 1, 0.82, 0.3 }

-- What the markers show, worked out once a game frame (and again after a hit
-- or a floor changes a note): each written-down kind's highest bonus among the
-- living holders, and each holder's all-enemy bonus.
local function currentView()
    local frame = Game():GetFrameCount()
    if view.frame == frame then return view end
    local kinds, holders, any = {}, {}, false
    for _, player in ipairs(players()) do
        if alive(player) and M.multiplier(player) > 0 then
            local note = M.ledger(player, false)
            if note then
                for key, bonus in pairs(note.kinds) do
                    if bonus > (kinds[key] or 0) then kinds[key], any = bonus, true end
                end
                if note.all > 0 then holders[#holders + 1] = { player = player, bonus = note.all } end
            end
        end
    end
    view = { frame = frame, kinds = kinds, any = any, holders = holders }
    return view
end

local function changed() view.frame = nil end

local function track(npc)
    if not npc or not EnemyUtils.isMonsterKind(npc) then return end
    local hash = GetPtrHash(npc)
    if tracked[hash] then return end
    tracked[hash] = { ref = EntityPtr(npc), key = M.kindKey(npc.Type, npc.Variant), age = 0 }
end

local function trackRoom()
    tracked = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if npc then track(npc) end
    end
end

-- Its clean-floor bonus breaks on any hit; on the next floor it watches again.
Hits.watchFloor("WRONG_ANSWER_NOTE")

-- A hit is written down under the kind of enemy behind it, worth what the
-- holder's multiplier makes it now.
Hits.register("WRONG_ANSWER_NOTE", function(_, entity, amount, flags, source)
    local player = entity and entity:ToPlayer()
    if not started or not player or not Hits.counts(flags) then return end
    local mult = M.multiplier(player)
    if mult <= 0 then return end
    local key = M.enemyKind(source)
    if not key then return end
    local note = M.ledger(player)
    if not note then return end
    local gain = M.data.kindStep * mult
    note.kinds[key] = (note.kinds[key] or 0) + gain
    evidence.noted, evidence.lastGain = evidence.noted + 1, gain
    changed()
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

-- A monster appears: its marker shows whenever its kind is written down.
function M.onNpcInit(_, npc)
    if not started then return end
    track(npc)
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
        local mult = alive(player) and M.multiplier(player) or 0
        if mult > 0 and chain.noHit(player) then result[GetPtrHash(player)] = mult end
    end
    endedFloor = result
end

function M.onNewLevel()
    local ended = endedFloor
    endedFloor = nil
    if not started or not ended then return end
    for _, player in ipairs(players()) do
        local mult = ended[GetPtrHash(player)]
        if mult then
            local note = M.ledger(player)
            if note then
                note.floors = note.floors + 1
                note.all = note.all + M.data.floorStep * mult
                evidence.floors = evidence.floors + 1
                changed()
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

-- The top of what the engine draws for `npc` this frame, in pixels above its
-- render point before SpriteScale: the highest visible layer frame of its
-- current animation (REPENTOGON's frame data), or nil without that data.
-- Rotated layers are taken as upright.
local function spriteTop(npc)
    local sprite = npc:GetSprite()
    if not (sprite and sprite.GetLayerCount and sprite.GetLayer and sprite.GetLayerFrameData) then return nil end
    local top
    for id = 0, sprite:GetLayerCount() - 1 do
        local layer = sprite:GetLayer(id)
        local frame = layer and (not layer.IsVisible or layer:IsVisible()) and sprite:GetLayerFrameData(id)
        if frame and (not frame.IsVisible or frame:IsVisible()) and frame:GetHeight() > 0 then
            local pos, pivot, scale = frame:GetPos(), frame:GetPivot(), frame:GetScale()
            local size, shift = layer:GetSize(), layer:GetPos()
            local y = (pos.Y - pivot.Y * scale.Y) * size.Y + shift.Y
            if not top or y < top then top = y end
        end
    end
    return top and -top or nil
end

-- How far above an entity's render point a number's top sits: just over the
-- monster's drawn top, worked out once a game frame and eased so a hop or an
-- attack pose does not jerk it; else the size rule.
local function heightOf(entity, mark, f, isPlayer)
    local data = M.data
    local scaleY = entity.SpriteScale and entity.SpriteScale.Y or 1
    local frame = Game():GetFrameCount()
    if not isPlayer and mark.topFrame ~= frame then
        mark.topFrame = frame
        local ok, top = pcall(spriteTop, entity)
        if ok and top then
            local line = f.GetLineHeight and f:GetLineHeight() or data.lineHeight
            local want = top * scaleY + data.gap + line
            mark.height = mark.height and mark.height + (want - mark.height) * 0.35 or want
        else
            mark.height = nil
        end
    end
    if not isPlayer and mark.height then return mark.height end
    return (data.lift + (entity.Size or 10) * data.sizeLift) * scaleY
end

-- Where a number's top-left goes on the screen, kept inside it.
local function placeText(entity, height, width, line)
    local data = M.data
    local offset = entity.SpriteOffset
    local at = Isaac.WorldToScreen(entity.Position + entity.PositionOffset)
    local x = at.X + (offset and offset.X or 0) - width / 2
    local y = at.Y + (offset and offset.Y or 0) - height
    local w = type(Isaac.GetScreenWidth) == "function" and Isaac.GetScreenWidth() or nil
    local h = type(Isaac.GetScreenHeight) == "function" and Isaac.GetScreenHeight() or nil
    if w then x = math.max(data.edge, math.min(w - data.edge - width, x)) end
    if h then y = math.min(h - data.edge - line, y) end
    return x, math.max(data.edge, y)
end

-- One marker: it pops in (drops 6 px into place and fades in at whole-pixel
-- size: a fractional scale smears the pixel font) whenever its number changes,
-- then stays.
local function drawMarker(f, entity, mark, text, color, paused, raise, isPlayer)
    if mark.text ~= text then mark.text, mark.age = text, 0 end
    local data = M.data
    if not paused and mark.age < data.popFrames then mark.age = mark.age + 1 end
    local age = mark.age
    local alpha = age < data.popFrames and 0.35 + 0.65 * age / data.popFrames or 1
    local rise = age < data.popFrames and (data.popFrames - age) or 0
    local line = f.GetLineHeight and f:GetLineHeight() or data.lineHeight
    local width = f:GetStringWidth(text)
    local x, y = placeText(entity, heightOf(entity, mark, f, isPlayer) + (raise or 0) + rise, width, line)
    mark.x, mark.y, mark.line = x, y, line
    f:DrawStringScaled(text, x, y, 1, 1, KColor(color[1], color[2], color[3], alpha), 0, false)
end

local function iconsShowing(player)
    return type(Hits.iconsShowing) == "function" and Hits.iconsShowing(player) or false
end

function M.onRender()
    if not started then return end
    local v = currentView()
    if not v.any and #v.holders == 0 then return end
    local f = loadFont()
    if not f:IsLoaded() then return end
    local paused = Game():IsPaused()
    if v.any then
        for hash, mark in pairs(tracked) do
            local npc = mark.ref.Ref
            if not (npc and npc:Exists()) or npc:IsDead() then
                tracked[hash] = nil
            else
                local bonus = v.kinds[mark.key]
                if bonus and bonus > 0 and npc.Visible ~= false and EnemyUtils.isMonsterKind(npc) then
                    drawMarker(f, npc, mark, percent(bonus), RED, paused, 0)
                else
                    mark.text = nil
                end
            end
        end
    end
    for _, holder in ipairs(v.holders) do
        local player = holder.player
        local hash = GetPtrHash(player)
        local mark = heads[hash]
        if not mark then
            mark = { age = 0, raise = 0 }
            heads[hash] = mark
        end
        local target = iconsShowing(player) and M.data.iconRaise or 0
        if not paused and mark.raise ~= target then
            mark.raise = mark.raise < target and math.min(target, mark.raise + 2) or math.max(target, mark.raise - 2)
        end
        drawMarker(f, player, mark, percent(holder.bonus), GOLD, paused, mark.raise, true)
    end
end

function M.onNewRoom()
    if not started then return end
    heads = {}
    trackRoom()
end

function M.onGameStarted()
    started = true
    endedFloor, heads = nil, {}
    changed()
    trackRoom()
end

function M.onGameExit()
    started = false
    tracked, heads, endedFloor = {}, {}, nil
    changed()
end

-- The text a marker over `entity` shows now, or nil.
local function shownText(entity)
    local v = currentView()
    local player = entity and entity.ToPlayer and entity:ToPlayer()
    if player then
        for _, holder in ipairs(v.holders) do
            if GetPtrHash(holder.player) == GetPtrHash(player) then return percent(holder.bonus) end
        end
        return nil
    end
    local mark = entity and tracked[GetPtrHash(entity)]
    local bonus = mark and v.kinds[mark.key]
    return bonus and bonus > 0 and percent(bonus) or nil
end

M._test = {
    started = function() return started end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    tracked = function() return tracked end,
    heads = function() return heads end,
    spriteTop = spriteTop,
    shownText = shownText,
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
