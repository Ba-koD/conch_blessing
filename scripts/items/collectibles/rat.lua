local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 자 (Rat), 손톱 먹은 쥐.
--
-- In the folktale a rat eats a fingernail someone threw away and turns into
-- that person, so alike that nobody can tell the two apart. Here every copy
-- held feeds one rat a nail: it becomes a fake of the holder, the same
-- character with the holder's passive items as they are at that moment (later
-- gains and losses do not reach it), driven by the same controller, with the
-- holder's health as it is at that moment, every kind of heart (user decision
-- 2026-10-24; it began with a single heart). A fake that falls (after any revive it
-- carries, judged by the engine's own rules) turns back into a rat and runs
-- off; that copy's rat transforms again on the next floor. When the holder
-- really dies, their fakes fall with them.
--
-- A fake is a real player made the way the engine makes Strawman's Keeper:
-- REPENTOGON's PlayerManager.SpawnCoPlayer2 with Parent set to the holder, as
-- Epiphany's First Page does. The engine's helper rules then decide what it
-- may pick up (no cards, pills, trinkets or actives), keep its health off the
-- main HUD, do not let it keep the run alive, and save and restore it on
-- Continue. PlayerManager.RemoveCoPlayer is the only safe way to take a player
-- away again, so the item needs REPENTOGON; elsewhere it does nothing and says
-- so once.
--
-- Saved state: the holder's floor save `rat` = { fallen = fakes of theirs that
-- fell this floor, copies = copies last seen }, and each fake's own run save
-- `ratFake` = { owner = the holder's save index, group = its group } so fakes
-- and their owners are found again after Continue, Glowing Hourglass or a Lua
-- reload. A fake is never taken away inside the engine's death handling: the
-- death callback only marks it, and the next update removes it.
--
-- Whenever a fake goes, a puff of smoke leaves a small grey rat with the
-- fingernail in its mouth, which scurries off away from the holder and fades.
-- It is a drawing only (no entity, no gameplay RNG), frozen while the game is
-- paused and gone with the room.

local M = {}
ConchBlessing.rat = M

local RAT_ID = Isaac.GetItemIdByName("Rat")
local FLOOR_KEY = "rat"
local MARK_KEY = "ratFake"

local callbackPriority = rawget(_G, "CallbackPriority")
local LATE = type(callbackPriority) == "table" and tonumber(callbackPriority.LATE) or 100

M.data = {
    fakesPerCopy = 1,        -- 자 is first of the twelve: one fake for each copy
    maxPlayers = 8,          -- REPENTOGON's HUD knows eight player slots; no fake beyond them
    regather = 80,           -- a fake this far from its holder on room entry is brought back to them
    ratSpeed = 3,            -- the fleeing rat's pixels per update
    ratLife = 45,            -- it runs a second and a half...
    ratFade = 12,            -- ...fading out over the last of it
    ratFrames = 4,           -- conch_rat_run.anm2: four run frames...
    ratFrameDelay = 3,       -- ...of three updates each
    ratDrift = 0.35,         -- how far off the horizontal it may run
}

local RAT_ANM2 = "gfx/effects/conch_rat_run.anm2"

local ready = type(Isaac.IsInGame) == "function" and Isaac.IsInGame() == true
local built = false          -- runtime rebuilt from the saved marks since the last start, room or reload
local dirty = true           -- copies or floors changed: reconcile on the next update
local fakes = {}             -- [GetPtrHash(fake)] = { ref = EntityPtr, owner = save index, group = group id }
local pending = {}           -- [GetPtrHash(fake)] = "fell" | "holder" | "stale", settled on the next update
local removing = {}          -- [GetPtrHash(fake)] = true while this module removes it
local lastCopies = {}        -- [GetPtrHash(holder)] = copies seen
local lastRemoval = nil      -- { by = "module" | "engine", reason, count } for diagnostics
local trace = nil            -- test-only: called with (stage, body) while a fake is made
local runners = {}           -- fleeing rats, drawn only: { pos, dir, age }
local ratSprite = nil        -- loaded on first use; false once loading failed
local reported = {}

local function reportOnce(key, message)
    if reported[key] then return end
    reported[key] = true
    ConchBlessing.printError("[Rat] " .. message)
end

local function debugLog(format, ...)
    ConchBlessing.printDebug("[Rat] " .. string.format(format, ...))
end

-- ------------------------------------------------------------------ pure rules
-- Kept free of engine state so the offline tests can call them directly.

-- Losing copies takes away empty (fallen) places first: two copies with one
-- fallen fake, minus a copy, still leave the live fake in place.
local function settleFallen(fallen, previous, copies)
    copies = math.max(0, math.floor(tonumber(copies) or 0))
    fallen = math.max(0, math.floor(tonumber(fallen) or 0))
    previous = tonumber(previous)
    if previous and copies < previous then fallen = math.max(0, fallen - (previous - copies)) end
    return math.min(fallen, copies * M.data.fakesPerCopy)
end

local function wantedFakes(copies, fallen)
    return math.max(0, math.max(0, math.floor(tonumber(copies) or 0)) * M.data.fakesPerCopy
        - math.max(0, math.floor(tonumber(fallen) or 0)))
end

-- The passives a fake receives: every collectible the holder really carries,
-- as many times as held, except actives and Rat itself (a fake feeds no rats
-- of its own). Sorted so every run grants them in the same order.
local function passivesToCopy(counts, isActive, excluded)
    local ids = {}
    for id, n in pairs(counts or {}) do
        id, n = tonumber(id), math.floor(tonumber(n) or 0)
        if id and id > 0 and n > 0 and id ~= excluded and not isActive(id) then ids[#ids + 1] = { id = id, n = n } end
    end
    table.sort(ids, function(a, b) return a.id < b.id end)
    local list = {}
    for _, row in ipairs(ids) do
        for _ = 1, row.n do list[#list + 1] = row.id end
    end
    return list
end

-- Cosmetic hash for the rat's path, never gameplay RNG.
local function hash(i)
    local x = math.sin((tonumber(i) or 0) * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end

-- The rat runs mostly sideways (it is drawn side-on), away from the holder,
-- drifting a little up or down. Returns a unit direction.
local function fleeDirection(fromX, holderX, seed)
    local side = (holderX and fromX ~= holderX) and (fromX > holderX and 1 or -1)
        or (hash(seed) < 0.5 and -1 or 1)
    local drift = (hash((tonumber(seed) or 0) + 7) * 2 - 1) * M.data.ratDrift
    local length = math.sqrt(1 + drift * drift)
    return side / length, drift / length
end

-- Frame within the looping run (anm2 frames count updates) and fade.
local function runnerFrame(age)
    local d = M.data
    return math.floor(math.max(0, age)) % (d.ratFrames * d.ratFrameDelay)
end

local function runnerAlpha(age)
    local d = M.data
    local left = d.ratLife - age
    if left >= d.ratFade then return 1 end
    return math.max(0, left / d.ratFade)
end

-- ------------------------------------------------------------------ engine glue
local function playerManager() return rawget(_G, "PlayerManager") end

--- Whether this runtime can make and remove fakes; the second value names what is missing.
function M.supported()
    local pm = playerManager()
    local missing = {}
    if type(pm) ~= "table" or type(pm.SpawnCoPlayer2) ~= "function" then missing[#missing + 1] = "PlayerManager.SpawnCoPlayer2" end
    if type(pm) ~= "table" or type(pm.RemoveCoPlayer) ~= "function" then missing[#missing + 1] = "PlayerManager.RemoveCoPlayer" end
    if not ModCallbacks.MC_TRIGGER_PLAYER_DEATH_POST_CHECK_REVIVES then missing[#missing + 1] = "MC_TRIGGER_PLAYER_DEATH_POST_CHECK_REVIVES" end
    if #missing > 0 then return false, "requires REPENTOGON (" .. table.concat(missing, ", ") .. ")" end
    return true, "REPENTOGON co-player API"
end

local function saveManager() return ConchBlessing.SaveManager end

local function saveLoaded()
    local sm = saveManager()
    return sm ~= nil and (type(sm.IsLoaded) ~= "function" or sm.IsLoaded() == true)
end

local function saveIndex(player)
    local sm = saveManager()
    return sm and sm.Utility and sm.Utility.GetSaveIndex(player) or nil
end

local function players()
    local list, game = {}, Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local p = game:GetPlayer(i)
        if p and p:Exists() then list[#list + 1] = p end
    end
    return list
end

local function isGhost(player)
    return type(player.IsCoopGhost) == "function" and player:IsCoopGhost() == true
end

local function live(player)
    return player ~= nil and player:Exists() and not player:IsDead() and not isGhost(player)
end

local function entryPlayer(entry)
    local ref = entry and entry.ref and entry.ref.Ref
    local player = ref and ref:ToPlayer()
    if player and player:Exists() then return player end
end

--- Whether a player is a fake made by Rat.
function M.isFake(player)
    return player ~= nil and fakes[GetPtrHash(player)] ~= nil
end

-- A holder is a main character: no fake, and no other helper (Strawman's
-- Keeper and the like carry a Parent) feeds rats of its own.
local function canHold(player)
    return player.Parent == nil and not M.isFake(player)
end

local function ownerOf(entry)
    for _, p in ipairs(players()) do
        if canHold(p) and saveIndex(p) == entry.owner then return p end
    end
end

local function floorState(holder, create)
    local sm = saveManager()
    local floor = create and sm.GetFloorSave(holder) or sm.TryGetFloorSave(holder)
    if type(floor) ~= "table" then return nil end
    if type(floor[FLOOR_KEY]) ~= "table" then
        if not create then return nil end
        floor[FLOOR_KEY] = { fallen = 0 }
    end
    return floor[FLOOR_KEY]
end

-- Rebuild the runtime list from the marks each fake carries in its own run
-- save. The engine restores fakes on Continue and Glowing Hourglass; this is how
-- they are recognised again, and how a Lua reload finds them.
local function rebuild()
    if not saveLoaded() then return false end
    local sm = saveManager()
    local found = {}
    for _, p in ipairs(players()) do
        local run = sm.TryGetRunSave(p)
        local mark = type(run) == "table" and run[MARK_KEY] or nil
        if type(mark) == "table" and type(mark.owner) == "string" then
            local hash = GetPtrHash(p)
            found[hash] = { ref = EntityPtr(p), owner = mark.owner, group = tostring(mark.group or mark.owner) }
        end
    end
    fakes = found
    for hash in pairs(pending) do
        if not fakes[hash] then pending[hash] = nil end
    end
    built = true
    return true
end

local function assignHuds()
    local hud = Game():GetHUD()
    if hud and type(hud.AssignPlayerHUDs) == "function" then pcall(hud.AssignPlayerHUDs, hud) end
end

-- The rat's moment: a puff of smoke where the fake stands (cosmetic only).
local function puff(position, seed)
    if not position then return end
    pcall(function()
        Game():Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, position, Vector.Zero, nil, 0,
            math.max(1, math.floor(tonumber(seed) or 1)))
    end)
end

-- ...and the rat it was, running off.
local function release(position, holderPosition, seed)
    if not position then return end
    local dx, dy = fleeDirection(position.X, holderPosition and holderPosition.X, seed)
    runners[#runners + 1] = { pos = Vector(position.X, position.Y), dir = Vector(dx, dy), age = 0 }
end

local function advanceRunners()
    if #runners == 0 then return end
    local room = Game():GetRoom()
    for i = #runners, 1, -1 do
        local r = runners[i]
        r.age = r.age + 1
        if r.age >= M.data.ratLife then
            table.remove(runners, i)
        else
            local nextPos = r.pos + r.dir * M.data.ratSpeed
            if room and type(room.GetClampedPosition) == "function" then nextPos = room:GetClampedPosition(nextPos, 0) end
            r.pos = nextPos
        end
    end
end

-- Every live group of fakes per owner, in spawn order (player index order).
local function groupsByOwner()
    local byOwner = {}
    for index, p in ipairs(players()) do
        local entry = fakes[GetPtrHash(p)]
        if entry then
            local list = byOwner[entry.owner] or {}
            byOwner[entry.owner] = list
            local group = list[entry.group]
            if not group then
                group = { id = entry.group, members = {}, first = index, live = true, settling = false }
                list[entry.group] = group
                list[#list + 1] = group
            end
            group.members[#group.members + 1] = p
            if not live(p) then group.live = false end
            if pending[GetPtrHash(p)] then group.settling = true end
        end
    end
    return byOwner
end

-- The groups that hold a place: alive, or dying while the engine still decides
-- on a revive. A group already marked to fall holds none.
local function placedGroups(byOwner, owner)
    local list = {}
    for _, group in ipairs(byOwner[owner] or {}) do
        if not group.settling then list[#list + 1] = group end
    end
    return list
end

local function removeMembers(members, reason, holderPosition)
    local pm = playerManager()
    local at
    for _, p in ipairs(members) do
        local hash = GetPtrHash(p)
        at = at or p.Position
        fakes[hash], pending[hash] = nil, nil
        if p:Exists() then
            removing[hash] = true
            local ok, err = pcall(pm.RemoveCoPlayer, p)
            removing[hash] = nil
            if not ok then ConchBlessing.printError("[Rat] RemoveCoPlayer failed: " .. tostring(err)) end
        end
    end
    puff(at, members[1] and members[1].InitSeed)
    release(at, holderPosition, members[1] and members[1].InitSeed)
    assignHuds()
    lastRemoval = { by = "module", reason = tostring(reason), count = #members }
    debugLog("removed a fake group of %d (%s)", #members, tostring(reason))
end

-- A fallen group turns back into a rat; its holder's place stays empty until
-- the next floor. Item loss and lost owners remove a group without a fall.
local function fall(owner, members, reason)
    if owner and reason ~= "lost" and reason ~= "orphan" and reason ~= "stale" then
        local state = floorState(owner, true)
        if state then state.fallen = (tonumber(state.fallen) or 0) + 1 end
    end
    removeMembers(members, reason, owner and owner.Position)
end

local function membersOf(group)
    local list = {}
    for _, p in ipairs(players()) do
        local entry = fakes[GetPtrHash(p)]
        if entry and entry.group == group then list[#list + 1] = p end
    end
    return list
end

-- Strip what the engine gave the new character, so the fake carries only the
-- holder's passives: actives (pocket ones too), starting passives, trinkets,
-- cards and pills, and whatever those starting items had already switched on
-- (a spawned Eve can be born low enough for her Whore of Babylon, whose effect
-- outlives the item for the room).
local function strip(player)
    local removed = {}
    for _, slot in ipairs({ ActiveSlot.SLOT_POCKET, ActiveSlot.SLOT_SECONDARY, ActiveSlot.SLOT_PRIMARY }) do
        local id = player:GetActiveItem(slot)
        if id and id > 0 then
            player:RemoveCollectible(id, false, slot)
            removed[id] = true
        end
    end
    for id, n in pairs(player:GetCollectiblesList()) do
        id, n = tonumber(id), math.floor(tonumber(n) or 0)
        if id and id > 0 then
            for _ = 1, n do player:RemoveCollectible(id) end
            if n > 0 then removed[id] = true end
        end
    end
    local effects = player:GetEffects()
    for id in pairs(removed) do
        local left = effects:GetCollectibleEffectNum(id)
        if left > 0 then effects:RemoveCollectibleEffect(id, left) end
    end
    for slot = 1, 0, -1 do
        local trinket = player:GetTrinket(slot)
        if trinket and trinket > 0 then player:TryRemoveTrinket(trinket) end
    end
    for slot = 3, 0, -1 do
        pcall(player.SetCard, player, slot, 0)
        pcall(player.SetPill, player, slot, 0)
    end
end

local function isActive(id)
    local config = Isaac.GetItemConfig():GetCollectible(id)
    return config ~= nil and config.Type == ItemType.ITEM_ACTIVE
end

local function copyPassives(source, player)
    local list = passivesToCopy(source:GetCollectiblesList(), isActive, RAT_ID)
    -- Not a first pickup: no pickups, hearts or other one-time bonuses come with them.
    for _, id in ipairs(list) do player:AddCollectible(id, 0, false) end
    return #list
end

-- The holder's hearts as they are now, every kind: containers, red (rotten
-- included), soul and black in their order, bone, golden, eternal and broken.
-- The Forgotten's Soul keeps its own hearts on the sub-player, copied alike.
--
-- Only by differences, never through an empty body: what is missing is added
-- first and what is extra taken away last, so the fake never drops below the
-- health it ends with. Low-health effects, including a character's innate ones
-- (Eve's Whore of Babylon is innate and invisible to the item list), then see
-- only the final health. Some characters heal by more than they are given
-- (Tainted Magdalene's red hearts count double), so the counts finally settle
-- on the exact amounts.
local function soulOrder(p)
    local order, black = {}, p:GetBlackHearts()
    for i = 1, p:GetSoulHearts() do order[i] = black & (1 << ((i - 1) // 2)) ~= 0 end
    return order
end

local settleHealth
function settleHealth(source, player)
    for _ = 1, 4 do
        local max, bone = source:GetMaxHearts() - player:GetMaxHearts(), source:GetBoneHearts() - player:GetBoneHearts()
        local red, soul = source:GetHearts() - player:GetHearts(), source:GetSoulHearts() - player:GetSoulHearts()
        if max == 0 and bone == 0 and red == 0 and soul == 0 then break end
        if max > 0 then player:AddMaxHearts(max) end
        if bone > 0 then player:AddBoneHearts(bone) end
        red = source:GetHearts() - player:GetHearts()
        if red ~= 0 then player:AddHearts(red) end
        if soul ~= 0 then player:AddSoulHearts(soul) end
        if bone < 0 then player:AddBoneHearts(bone) end
        if max < 0 then player:AddMaxHearts(max) end
    end
    local from = type(source.GetSubPlayer) == "function" and source:GetSubPlayer() or nil
    local to = type(player.GetSubPlayer) == "function" and player:GetSubPlayer() or nil
    if from and to and GetPtrHash(from) ~= GetPtrHash(source) then settleHealth(from, to) end
end

local copyHealth
function copyHealth(source, player)
    -- Up first: containers, bone hearts, then fill red.
    local max = source:GetMaxHearts() - player:GetMaxHearts()
    if max > 0 then player:AddMaxHearts(max) end
    local bone = source:GetBoneHearts() - player:GetBoneHearts()
    if bone > 0 then player:AddBoneHearts(bone) end
    local red = source:GetHearts() - player:GetHearts()
    if red > 0 then player:AddHearts(red) end
    -- Soul and black hearts in the holder's order: keep the shared start, swap the rest.
    local want, have = soulOrder(source), soulOrder(player)
    local keep = 0
    while keep < #want and keep < #have and want[keep + 1] == have[keep + 1] do keep = keep + 1 end
    if #have > keep then player:AddSoulHearts(keep - #have) end
    for i = keep + 1, #want do
        if want[i] then player:AddBlackHearts(1) else player:AddSoulHearts(1) end
    end
    -- Then down: extra red, bone hearts and containers.
    red = source:GetHearts() - player:GetHearts()
    if red < 0 then player:AddHearts(red) end
    bone = source:GetBoneHearts() - player:GetBoneHearts()
    if bone < 0 then player:AddBoneHearts(bone) end
    max = source:GetMaxHearts() - player:GetMaxHearts()
    if max < 0 then player:AddMaxHearts(max) end
    -- The rest by their differences.
    local rotten = source:GetRottenHearts() - player:GetRottenHearts()
    if rotten ~= 0 then player:AddRottenHearts(rotten) end
    local golden = source:GetGoldenHearts() - player:GetGoldenHearts()
    if golden ~= 0 then player:AddGoldenHearts(golden) end
    local eternal = source:GetEternalHearts() - player:GetEternalHearts()
    if eternal ~= 0 then player:AddEternalHearts(eternal) end
    local broken = source:GetBrokenHearts() - player:GetBrokenHearts()
    if broken ~= 0 then player:AddBrokenHearts(broken) end
    local from = type(source.GetSubPlayer) == "function" and source:GetSubPlayer() or nil
    local to = type(player.GetSubPlayer) == "function" and player:GetSubPlayer() or nil
    if from and to and GetPtrHash(from) ~= GetPtrHash(source) then copyHealth(from, to) end
    settleHealth(source, player)
end

-- Eden and Tainted Eden roll their base stats per player; the fake takes the
-- source's rolls (REPENTOGON's Eden getters/setters; other characters' are 0).
local EDEN_STATS = { "Damage", "FireDelay", "Luck", "Range", "ShotSpeed", "Speed" }
local function copyEdenStats(source, player)
    local changed = false
    for _, stat in ipairs(EDEN_STATS) do
        local get, set = source["GetEden" .. stat], player["SetEden" .. stat]
        if type(get) == "function" and type(set) == "function" then
            local value = get(source)
            if player["GetEden" .. stat](player) ~= value then
                set(player, value)
                changed = true
            end
        end
    end
    if changed then
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
    end
    return changed
end

-- The holder's twin of the same type (Esau for a fake Esau), else the holder.
local function sourceFor(holder, member)
    if member:GetPlayerType() ~= holder:GetPlayerType() and type(holder.GetOtherTwin) == "function" then
        local twin = holder:GetOtherTwin()
        if twin and twin:GetPlayerType() == member:GetPlayerType() then return twin end
    end
    return holder
end

-- Make one body of a fake: the holder's character as the engine spawned it,
-- then Parent, controller, the holder's passives (from the same character's
-- original, so a fake Esau copies Esau), Eden's rolls and that original's health.
local function dress(p, holder, owner, group, at)
    -- Characters with their own weapon (Azazel, Lilith, the Forgotten) get it
    -- in the post-level init; finish it first if the spawn did not, before
    -- the starting loadout it grants is stripped.
    if trace then trace("spawned", p) end
    if type(p.IsPostLevelInitFinished) == "function" and not p:IsPostLevelInitFinished()
        and type(p.InitPostLevelInitStats) == "function" then
        p:InitPostLevelInitStats()
        if trace then trace("post-level init", p) end
    end
    p.Parent = holder
    p:SetControllerIndex(holder.ControllerIndex)
    strip(p)
    if trace then trace("stripped", p) end
    local source = sourceFor(holder, p)
    -- Health first; then the passives (some add containers), and a last
    -- settle by differences.
    copyHealth(source, p)
    if trace then trace("health copied", p) end
    local copied = copyPassives(source, p)
    if trace then trace("passives copied", p) end
    copyEdenStats(source, p)
    settleHealth(source, p)
    if trace then trace("settled", p) end
    p.Position = Isaac.GetFreeNearPosition(at or holder.Position, 20)
    p.Velocity = Vector.Zero
    if type(p.AnimateAppear) == "function" then p:AnimateAppear() end
    saveManager().GetRunSave(p)[MARK_KEY] = { owner = owner, group = group }
    fakes[GetPtrHash(p)] = { ref = EntityPtr(p), owner = owner, group = group }
    debugLog("fake %s of %s: type %d, controller %d, %d passives", tostring(saveIndex(p)), tostring(owner),
        p:GetPlayerType(), p.ControllerIndex, copied)
end

-- SaveManager keys players by seed; a body sharing a key with anyone would write
-- its mark into that player's save, and one without a save could not be found
-- again after Continue.
local function separateSave(p, indices)
    local index = saveIndex(p)
    if not index or indices[index] or type(saveManager().GetRunSave(p)) ~= "table" then return false, index end
    indices[index] = true
    return true, index
end

-- Every listed player's save key, except `skip`'s own.
local function saveIndices(skip)
    local indices = {}
    for _, q in ipairs(players()) do
        if not skip or GetPtrHash(q) ~= GetPtrHash(skip) then indices[saveIndex(q) or ""] = true end
    end
    return indices
end

-- One rat eats one nail: a new fake group (Jacob comes with his Esau).
local function transform(holder)
    local pm = playerManager()
    local game = Game()
    if game:GetNumPlayers() >= M.data.maxPlayers then
        debugLog("no room for another player (%d)", game:GetNumPlayers())
        return false
    end
    -- SpawnCoPlayer2 takes no controller; without a way to hand over the
    -- holder's, the fake could not move with them.
    if type(holder.SetControllerIndex) ~= "function" then
        reportOnce("controller", "EntityPlayer:SetControllerIndex is missing; Rat makes no fakes")
        return false
    end
    local before, indices = {}, saveIndices()
    for _, p in ipairs(players()) do before[GetPtrHash(p)] = true end
    -- Joining characters can bring starting pickups into the shared pool; a
    -- rat brings none, so the shared counts are put back as they were.
    local coins, bombs, keys = holder:GetNumCoins(), holder:GetNumBombs(), holder:GetNumKeys()
    local ok, spawned = pcall(pm.SpawnCoPlayer2, holder:GetPlayerType())
    local members = {}
    for _, p in ipairs(players()) do
        if not before[GetPtrHash(p)] then members[#members + 1] = p end
    end
    if #members == 0 and ok and spawned and spawned:Exists() then members[1] = spawned end
    if #members == 0 then
        ConchBlessing.printError("[Rat] SpawnCoPlayer2 made no player: " .. tostring(ok and "nil" or spawned))
        return false
    end
    -- Fail closed on a shared or missing save identity.
    for _, p in ipairs(members) do
        local separate, index = separateSave(p, indices)
        if not separate then
            for _, q in ipairs(members) do pcall(pm.RemoveCoPlayer, q) end
            assignHuds()
            ConchBlessing.printError("[Rat] no separate save for the fake (" .. tostring(index) .. "); transformation cancelled")
            return false
        end
    end
    local owner = saveIndex(holder)
    local group = saveIndex(members[1])
    for _, p in ipairs(members) do dress(p, holder, owner, group) end
    holder:AddCoins(coins - holder:GetNumCoins())
    holder:AddBombs(bombs - holder:GetNumBombs())
    holder:AddKeys(keys - holder:GetNumKeys())
    puff(members[1].Position, members[1].InitSeed)
    assignHuds()
    return true
end

-- A two-body character's fake (Jacob and Esau, Tainted Forgotten and its Soul)
-- gets its second body from the engine, which may list it only after the spawn
-- returns. A listed player whose twin is a fake is that fake's other body.
local function adoptTwins()
    local adopted = false
    for _, p in ipairs(players()) do
        local twin = not fakes[GetPtrHash(p)] and type(p.GetOtherTwin) == "function" and p:GetOtherTwin() or nil
        local entry = twin and fakes[GetPtrHash(twin)]
        local holder = entry and ownerOf(entry)
        if holder and GetPtrHash(p) ~= GetPtrHash(holder) then
            local separate, index = separateSave(p, saveIndices(p))
            if separate then
                dress(p, holder, entry.owner, entry.group, twin.Position)
                adopted = true
            else
                pcall(playerManager().RemoveCoPlayer, p)
                ConchBlessing.printError("[Rat] no separate save for a fake's twin (" .. tostring(index) .. "); removed")
            end
        end
    end
    if adopted then assignHuds() end
    return adopted
end

-- Bring the number of each holder's live fakes in line with their copies and
-- this floor's falls; remove fakes whose holder is gone.
local function reconcile()
    local byOwner = groupsByOwner()
    local owners = {}
    for _, holder in ipairs(players()) do
        if canHold(holder) then
            local owner = saveIndex(holder)
            owners[owner] = true
            local copies = holder:GetCollectibleNum(RAT_ID)
            local groups = placedGroups(byOwner, owner)
            local state = floorState(holder, copies > 0 or #groups > 0)
            if state then
                state.fallen = settleFallen(state.fallen, state.copies, copies)
                state.copies = copies
                local want = wantedFakes(copies, state.fallen)
                while #groups > want do
                    local group = table.remove(groups)
                    fall(holder, group.members, "lost")
                end
                if #groups < want and live(holder) then
                    local ok = M.supported()
                    if not ok then
                        reportOnce("unsupported", select(2, M.supported()) .. "; Rat makes no fakes")
                    else
                        for _ = #groups + 1, want do
                            if not transform(holder) then break end
                        end
                    end
                end
            end
        end
    end
    for owner, list in pairs(byOwner) do
        if not owners[owner] then
            for _, group in ipairs(list) do fall(nil, group.members, "orphan") end
        end
    end
end

-- ------------------------------------------------------------------ callbacks
function M.onUpdate()
    advanceRunners()
    if not ready then return end
    if not built then
        if not rebuild() then return end
        dirty = true
    end
    if next(fakes) ~= nil then adoptTwins() end
    -- Falls the death callback marked, settled outside the engine's death code.
    local settle = {}
    for hash, reason in pairs(pending) do settle[#settle + 1] = { hash = hash, reason = reason } end
    for _, row in ipairs(settle) do
        local entry = fakes[row.hash]
        local p = entryPlayer(entry)
        if not p then
            pending[row.hash] = nil
        elseif row.reason == "fell" and live(p) then
            pending[row.hash] = nil          -- a later revive saved it after all
        elseif row.reason == "holder" and live(ownerOf(entry)) then
            pending[row.hash] = nil          -- so was the holder
        else
            fall(ownerOf(entry), membersOf(entry.group), row.reason)
            dirty = true
        end
    end
    for _, p in ipairs(players()) do
        local hash = GetPtrHash(p)
        local entry = fakes[hash]
        if entry then
            if isGhost(p) then pending[hash] = pending[hash] or "fell"; dirty = true end
        elseif canHold(p) then
            -- A holder who became a co-op ghost has really died: their fakes go too.
            if isGhost(p) then
                local owner = saveIndex(p)
                for h, e in pairs(fakes) do
                    if e.owner == owner and not pending[h] then pending[h] = "holder"; dirty = true end
                end
            end
            local copies = p:GetCollectibleNum(RAT_ID)
            if lastCopies[hash] ~= copies then lastCopies[hash] = copies; dirty = true end
        end
    end
    if dirty and next(pending) == nil then
        dirty = false
        reconcile()
    end
end

-- After the engine's own revives (1UP, Dead Cat, REPENTOGON revive tags) are
-- spent: a fake that stays dead has fallen, and a holder who stays dead takes
-- their fakes along. LATE, so other mods' revives come first.
function M.onDeathAfterRevives(_, player)
    if not ready or not player or not player:IsDead() then return end
    local hash = GetPtrHash(player)
    if fakes[hash] then
        pending[hash] = "fell"
        return
    end
    if not canHold(player) then return end
    local owner = saveIndex(player)
    for h, entry in pairs(fakes) do
        if entry.owner == owner then pending[h] = "holder" end
    end
end

function M.onEntityRemove(_, entity)
    if not ready or not entity or entity.Type ~= EntityType.ENTITY_PLAYER then return end
    local hash = GetPtrHash(entity)
    local entry = fakes[hash]
    if not entry then
        dirty = true         -- a holder may have left the run: their fakes go on the next update
        return
    end
    if removing[hash] then return end
    -- The engine took a fake away itself (its own death handling): that is a fall.
    fakes[hash], pending[hash] = nil, nil
    local player = entity:ToPlayer()
    lastRemoval = { by = "engine", reason = player and player:IsDead() and "dead" or "alive", count = 1 }
    if player and player:IsDead() then
        local owner = ownerOf(entry)
        local state = owner and floorState(owner, true)
        if state and not membersOf(entry.group)[1] then state.fallen = (tonumber(state.fallen) or 0) + 1 end
        puff(entity.Position, entity.InitSeed)
        release(entity.Position, owner and owner.Position, entity.InitSeed)
    end
    dirty = true
end

function M.onNewRoom()
    runners = {}
    if not ready then return end
    built = false            -- Glowing Hourglass may have restored or dropped players
    dirty = true
    for _, entry in pairs(fakes) do
        local p = entryPlayer(entry)
        local holder = p and live(p) and ownerOf(entry)
        if holder and p.Position:Distance(holder.Position) > M.data.regather then
            p.Position = Isaac.GetFreeNearPosition(holder.Position, 20)
            p.Velocity = Vector.Zero
        end
    end
end

function M.onNewLevel()
    if not ready then return end
    -- A fake still lying dead when the floor changes was never settled by the
    -- engine's death handling. It does not follow to the new floor, and as it
    -- never fell there, the new floor's rat makes a fresh one in its place.
    for hash, entry in pairs(fakes) do
        local p = entryPlayer(entry)
        if p and not live(p) and not pending[hash] then pending[hash] = "stale" end
    end
    dirty = true
end

local function clearRuntime()
    fakes, pending, removing, lastCopies, runners = {}, {}, {}, {}, {}
    built, dirty = false, true
end

function M.onGameStarted()
    clearRuntime()
    ready = true
end

function M.onPreGameExit()
    ready = false
    clearRuntime()
end

-- Fakes are players and stay in the run; a reloaded module finds them again
-- through their marks.
function M.onUnload(_, mod)
    if mod ~= ConchBlessing and mod ~= ConchBlessing.originalMod then return end
    clearRuntime()
end

-- REPENTOGON draws this after the room's entities and before the HUD.
function M.onRoomRender()
    if #runners == 0 then return end
    if ratSprite == nil then
        local ok, sprite = pcall(function()
            local s = Sprite()
            s:Load(RAT_ANM2, true)
            if s.IsLoaded and not s:IsLoaded() then error(RAT_ANM2 .. " did not load") end
            return s
        end)
        ratSprite = ok and sprite or false
        if not ok then reportOnce("sprite", "rat art unavailable: " .. tostring(sprite)) end
    end
    if not ratSprite then return end
    for _, r in ipairs(runners) do
        ratSprite:SetFrame("Run", runnerFrame(r.age))
        ratSprite.FlipX = r.dir.X < 0
        ratSprite.Color = Color(1, 1, 1, runnerAlpha(r.age))
        ratSprite:Render(Isaac.WorldToScreen(r.pos))
    end
    ratSprite.FlipX = false
    ratSprite.Color = Color(1, 1, 1, 1)
end

--- The live fakes of a holder, in spawn order.
function M.fakesOf(holder)
    local list = {}
    if not holder then return list end
    local owner = saveIndex(holder)
    for _, p in ipairs(players()) do
        local entry = fakes[GetPtrHash(p)]
        if entry and entry.owner == owner and live(p) then list[#list + 1] = p end
    end
    return list
end

--- Remove every fake without counting a fall (test cleanup).
function M.removeAll(reason)
    local members = {}
    for _, p in ipairs(players()) do
        if fakes[GetPtrHash(p)] then members[#members + 1] = p end
    end
    if #members > 0 then removeMembers(members, reason or "removeAll") end
    return #members
end

--- This floor's falls for a holder.
function M.fallen(holder)
    local state = holder and floorState(holder, false)
    return state and tonumber(state.fallen) or 0
end

M._test = {
    settleFallen = settleFallen,
    wantedFakes = wantedFakes,
    passivesToCopy = passivesToCopy,
    copyHealth = copyHealth,
    settleHealth = settleHealth,
    setTrace = function(fn) trace = fn end,
    pending = function() return pending end,
    fakes = function() return fakes end,
    ready = function() return ready end,
    lastRemoval = function() return lastRemoval end,
    copyEdenStats = copyEdenStats,
    adoptTwins = adoptTwins,
    fleeDirection = fleeDirection,
    runnerFrame = runnerFrame,
    runnerAlpha = runnerAlpha,
    runners = function() return runners end,
    markKey = MARK_KEY,
    floorKey = FLOOR_KEY,
}

if ModCallbacks.MC_TRIGGER_PLAYER_DEATH_POST_CHECK_REVIVES then
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_TRIGGER_PLAYER_DEATH_POST_CHECK_REVIVES, LATE,
        M.onDeathAfterRevives)
end

return M
