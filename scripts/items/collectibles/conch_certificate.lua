local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
local RunSaveCache = require("scripts.lib.run_save_cache")
-- 소라 증명서 (Conch Certificate), console only (user design 2026-11-11). A use
-- calls the real Death Certificate, so the engine generates and owns the rooms,
-- their layouts and the way home. Only the pedestals change: starting from the
-- first one, they hold this mod's collectibles and then its trinkets in ID
-- order, and the pedestals left over are removed, so nobody has to walk past
-- every vanilla item to reach ours.
--
-- Pedestal order is the Death Certificate layout's own: rooms in the order the
-- engine generated them (descriptor ListIndex, as Appraisal Certificate uses)
-- and, in a room, its layout's spawn order. Each converted room keeps the item
-- the engine had put on every pedestal (`original`), which the in-game bench
-- compares with that order. Nothing here registers rooms, changes descriptors
-- or touches Appraisal Certificate's own session.
local DCRooms = require("scripts.rooms.death_certificate_gallery_rooms")
local isc = require("scripts.lib.isaacscript-common")

ConchBlessing.conchCertificate = ConchBlessing.conchCertificate or {}
local M = ConchBlessing.conchCertificate

local callbackPriority = rawget(_G, "CallbackPriority")
local CALLBACK_PRIORITY_EARLY = type(callbackPriority) == "table"
    and tonumber(callbackPriority.EARLY) or -100

local SAVE_KEY = "conchCertificate"
local LEDGER_VERSION = 1
local DC_DIMENSION = 2
local COLLECTIBLE = "collectible"
local TRINKET = "trinket"

M._ready = M._ready == true -- opened by game start (or a mid-run luamod)

local function itemId()
    local row = ConchBlessing.ItemData and ConchBlessing.ItemData.CONCH_CERTIFICATE
    return row and row.id
end

local function repentogon()
    local rgon = rawget(_G, "REPENTOGON")
    return type(rgon) == "table" and rgon.Real == true
end

-- What the certificate shows: every registered collectible of this mod except
-- the certificate itself (console items and WIP previews included), then every
-- registered trinket, each group by its engine ID (user decision 2026-11-11).
-- Pure: the bench and the offline tests call it with their own registry.
function M.buildCatalog(itemData, selfKey)
    local collectibles, trinkets = {}, {}
    for key, row in pairs(itemData or {}) do
        if type(row) == "table" and type(row.type) == "string" and key ~= selfKey
            and type(row.id) == "number" and row.id > 0 then
            if row.type == "trinket" then
                trinkets[#trinkets + 1] = row.id
            else
                collectibles[#collectibles + 1] = row.id
            end
        end
    end
    table.sort(collectibles)
    table.sort(trinkets)
    local catalog = {}
    for _, id in ipairs(collectibles) do catalog[#catalog + 1] = { kind = COLLECTIBLE, id = id } end
    for _, id in ipairs(trinkets) do catalog[#catalog + 1] = { kind = TRINKET, id = id } end
    return catalog
end

-- The catalog entry a room's slot holds, or nil for a pedestal past the
-- catalog (removed). Slots past the room's share are nil too.
function M.entryFor(catalog, manifest, slot)
    if type(catalog) ~= "table" or type(manifest) ~= "table" then return nil end
    local count = tonumber(manifest.slotCount) or 0
    if slot < 1 or slot > count then return nil end
    return catalog[(tonumber(manifest.catalogStart) or 1) + slot - 1]
end

-- A spawn seed that depends only on the ledger seed, the room and the slot, so
-- a pickup created again for the same slot gets the same seed.
function M.slotSeed(seed, listIndex, slot)
    return ((math.abs(tonumber(seed) or 1) + (tonumber(listIndex) or 0) * 104729
        + slot * 8191) % 2147483646) + 1
end

-- The global run save, kept for the frame (scripts/lib/run_save_cache.lua).
local function getRunSave(create)
    return RunSaveCache.global(create)
end

local function currentDimension()
    local level = Game():GetLevel()
    if not level or type(level.GetDimension) ~= "function" then return nil end
    local ok, dimension = pcall(level.GetDimension, level)
    return ok and dimension or nil
end

local function transitionMode()
    local transition = rawget(_G, "RoomTransition")
    if type(transition) ~= "table" or type(transition.GetTransitionMode) ~= "function" then return nil end
    local ok, mode = pcall(transition.GetTransitionMode)
    return ok and tonumber(mode) or nil
end

local function floorIdentity()
    local level = Game():GetLevel()
    local placement
    if type(level.GetDungeonPlacementSeed) == "function" then
        local ok, value = pcall(level.GetDungeonPlacementSeed, level)
        if ok then placement = tonumber(value) end
    end
    return { stage = level:GetStage(), stageType = level:GetStageType(), placementSeed = placement }
end

local function sameFloor(ledger)
    local floor = type(ledger) == "table" and ledger.floor
    local now = floorIdentity()
    return type(floor) == "table" and floor.stage == now.stage and floor.stageType == now.stageType
        and floor.placementSeed == now.placementSeed
end

-- This floor's ledger, or nil. A ledger from another floor is dropped: the
-- Death Certificate rooms it describes no longer exist.
local function getLedger()
    local run = getRunSave(false)
    local ledger = run and run[SAVE_KEY]
    if type(ledger) ~= "table" then return nil end
    if ledger.version ~= LEDGER_VERSION or not sameFloor(ledger) then
        run[SAVE_KEY] = nil
        return nil
    end
    return ledger
end

local function newLedger()
    local run = getRunSave(true)
    if not run then return nil end
    local floor = floorIdentity()
    local start = Game():GetSeeds():GetStartSeed()
    run[SAVE_KEY] = {
        version = LEDGER_VERSION,
        floor = floor,
        seed = ((math.abs(start) + floor.stage * 7919 + floor.stageType * 131) % 2147483646) + 1,
        catalog = M.buildCatalog(ConchBlessing.ItemData, "CONCH_CERTIFICATE"),
        rooms = {},
        taken = {},
        visiting = false,
    }
    return run[SAVE_KEY]
end

-- A catalog entry the player took ("c<id>" or "t<id>").
local function takenKey(entry) return (entry.kind == TRINKET and "t" or "c") .. tostring(entry.id) end

-- Whether a collectible of the catalog can still be on a pedestal of this
-- floor's certificate rooms. Taking one is the only way home (the engine's
-- Death Certificate return), so a visit with none left would strand the player.
function M.hasCollectibleLeft(ledger)
    for _, entry in ipairs(ledger.catalog or {}) do
        if entry.kind == COLLECTIBLE and not (ledger.taken and ledger.taken[takenKey(entry)]) then
            return true
        end
    end
    return false
end

local function stageAPIExtraRoom()
    local stageAPI = rawget(_G, "StageAPI")
    if type(stageAPI) ~= "table" then return false end
    if stageAPI.DoingExtraRoomTransition == true then return true end
    if type(stageAPI.InOrTransitioningToExtraRoom) == "function" then
        local ok, inside = pcall(stageAPI.InOrTransitioningToExtraRoom)
        return ok and inside == true
    end
    return false
end

-- Why a use must not start now, or nil.
function M.blockReason(player)
    if M._ready ~= true then return "run_not_ready" end
    if not repentogon() or not DCRooms.isAvailable() or transitionMode() == nil then return "repentogon" end
    if not player or not getRunSave(true) then return "save_unavailable" end
    if currentDimension() == DC_DIMENSION then return "inside" end
    if transitionMode() ~= 0 then return "transition_busy" end
    if stageAPIExtraRoom() then return "stageapi_extra_room" end
    local gallery = ConchBlessing.GalleryManager
    if gallery and type(gallery.isVisitActive) == "function" and gallery.isVisitActive() then
        return "appraisal_visit"
    end
    local ledger = getLedger()
    if ledger then
        if not M.hasCollectibleLeft(ledger) then return "empty" end
        if ledger.graph then
            local ok, runtime, reason = pcall(DCRooms.rebind, ledger.graph, #ledger.catalog)
            if not ok or not runtime then return "rooms_changed:" .. tostring(reason or runtime) end
        end
    else
        local catalog = M.buildCatalog(ConchBlessing.ItemData, "CONCH_CERTIFICATE")
        local hasCollectible = false
        for _, entry in ipairs(catalog) do hasCollectible = hasCollectible or entry.kind == COLLECTIBLE end
        if not hasCollectible then return "empty" end
        -- A Death Certificate area already generated on this floor is reused by
        -- the engine; refuse one this module could not adopt before the use.
        local empty = DCRooms.isDimensionEmpty()
        if empty == nil then return "repentogon" end
        if not empty then
            local ok, graph, reason = pcall(DCRooms.capture, catalog, 1)
            if not ok or not graph then return "foreign_rooms:" .. tostring(reason or graph) end
        end
    end
    return nil
end

local function report(reason)
    if reason == "run_not_ready" then return end
    if reason == "inside" then
        ConchBlessing.print("[Conch Certificate] Already in the Death Certificate area.")
    elseif reason == "transition_busy" then
        ConchBlessing.print("[Conch Certificate] Wait for the room transition to end.")
    elseif reason == "appraisal_visit" then
        ConchBlessing.print("[Conch Certificate] An Appraisal Certificate visit is still open.")
    elseif reason == "stageapi_extra_room" then
        ConchBlessing.print("[Conch Certificate] Cannot be used in a StageAPI extra room.")
    elseif reason == "empty" then
        ConchBlessing.print("[Conch Certificate] Every item of this floor's certificate has been taken.")
    elseif reason == "repentogon" then
        ConchBlessing.printError("Conch Certificate requires a compatible REPENTOGON version.")
    else
        ConchBlessing.printError("Conch Certificate use was blocked: " .. tostring(reason))
    end
end

function M.onPreUseItem(_, _, _, player)
    local reason = M.blockReason(player)
    if not reason then return end
    report(reason)
    if repentogon() then return { Discharge = false } end
    return true
end

-- The canonical call keeps Death Certificate's own hold-up, sound and room
-- transition; only its costume, announcer and HUD name are left out, and the
-- held sprite is then swapped to the certificate (as Appraisal does).
local function deathCertificateFlags()
    local flags = 0
    for _, key in ipairs({ "USE_NOCOSTUME", "USE_NOANNOUNCER", "USE_NOHUD", "USE_ALLOWNONMAIN" }) do
        flags = flags | (tonumber(UseFlag[key]) or 0)
    end
    return flags
end

function M.onUseItem(_, _, _, player)
    local ledger = getLedger() or newLedger()
    if not ledger or not player then
        ConchBlessing.printError("Conch Certificate could not open its floor record.")
        return { Discharge = false, Remove = false, ShowAnim = false }
    end
    ledger.visiting = true
    local ok, err = pcall(function()
        player:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, deathCertificateFlags(), -1)
    end)
    if ok and type(player.AnimateCollectible) == "function" and itemId() then
        pcall(player.AnimateCollectible, player, itemId(), "UseItem", "PlayerPickup")
    end
    if currentDimension() ~= DC_DIMENSION and transitionMode() == 0 then
        ledger.visiting = false
        ConchBlessing.printError("Conch Certificate: Death Certificate did not start its transition: "
            .. tostring(err or "no transition"))
    end
    return { Discharge = false, Remove = false, ShowAnim = false }
end

local function roomPickups(variant)
    local list = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, variant, -1, false, false)) do
        local pickup = entity:ToPickup()
        if pickup and pickup:Exists() then list[#list + 1] = pickup end
    end
    return list
end

local function spawnAt(variant, id, position, seed)
    local entity = Game():Spawn(EntityType.ENTITY_PICKUP, variant, position, Vector.Zero, nil, id, seed)
    local pickup = entity and entity:ToPickup()
    if pickup then pickup.Price = 0 end
    return pickup
end

-- First time in a room: every engine pedestal on a slot becomes the slot's
-- catalog item (the same entity, Morphed, keeping its seed) or, for a trinket
-- or a slot past the catalog, is removed; a trinket goes where its pedestal
-- stood. A slot whose pedestal is already gone (taken on an earlier vanilla
-- Death Certificate visit) gets a new one. Any other collectible goes too.
local function convertRoom(ledger, manifest)
    local room = Game():GetRoom()
    local width = room:GetGridWidth()
    local slotAt = {}
    for slot, position in ipairs(manifest.pedestalPositions or {}) do
        slotAt[position.x + position.y * width] = slot
    end
    local onSlot, strays = {}, {}
    for _, pickup in ipairs(roomPickups(PickupVariant.PICKUP_COLLECTIBLE)) do
        local slot = slotAt[room:GetGridIndex(pickup.Position)]
        if slot and not onSlot[slot] then onSlot[slot] = pickup else strays[#strays + 1] = pickup end
    end
    local state = { seeds = {}, original = {} }
    for slot = 1, tonumber(manifest.capacity) or 0 do
        local pickup = onSlot[slot]
        state.original[slot] = pickup and pickup.SubType or 0
        local entry = M.entryFor(ledger.catalog, manifest, slot)
        local position = DCRooms.getSlotWorldPosition(room, manifest, slot)
        if entry and entry.kind == COLLECTIBLE then
            if pickup then
                local seed = pickup.InitSeed
                pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, entry.id, true, true, true)
                pickup.Price = 0
                state.seeds[slot] = seed
            else
                local spawned = position and spawnAt(PickupVariant.PICKUP_COLLECTIBLE, entry.id, position,
                    M.slotSeed(ledger.seed, manifest.listIndex, slot))
                state.seeds[slot] = spawned and spawned.InitSeed or 0
            end
        else
            if pickup then pickup:Remove() end
            if entry and entry.kind == TRINKET then
                local spawned = position and spawnAt(PickupVariant.PICKUP_TRINKET, entry.id, position,
                    M.slotSeed(ledger.seed, manifest.listIndex, slot))
                state.seeds[slot] = spawned and spawned.InitSeed or 0
            end
        end
    end
    for _, pickup in ipairs(strays) do pickup:Remove() end
    ledger.rooms[manifest.key] = state
    ConchBlessing.printDebug("[Conch Certificate] room %s converted: catalog %d..%d, %d of %d pedestals",
        tostring(manifest.listIndex), manifest.catalogStart, manifest.catalogStart + manifest.slotCount - 1,
        manifest.slotCount, manifest.capacity)
end

-- A room converted before: the engine restored it from its own room save. A
-- collectible that is not one of the certificate's (by seed) goes. Only what
-- the player took stays gone: the engine empties the room an item was taken
-- from (measured 2026-11-13 with `conch_test conch_certificate dc_revisit`,
-- vanilla Death Certificate used twice: 18 pedestals, then 0, while a room
-- merely looked into kept all of its own), so every other entry of ours that
-- is missing is put back on its slot with its own seed.
local function revisitRoom(ledger, manifest, state)
    local ours = {}
    state.seeds = state.seeds or {}
    for slot = 1, tonumber(manifest.slotCount) or 0 do
        local seed = state.seeds[slot]
        if seed and seed ~= 0 then ours[seed] = slot end
    end
    local present = {}
    for _, pickup in ipairs(roomPickups(PickupVariant.PICKUP_COLLECTIBLE)) do
        local slot = ours[pickup.InitSeed]
        if slot then present[slot] = true else pickup:Remove() end
    end
    -- A trinket that is not ours (one a player dropped) stays where it is.
    for _, pickup in ipairs(roomPickups(PickupVariant.PICKUP_TRINKET)) do
        local slot = ours[pickup.InitSeed]
        if slot then present[slot] = true end
    end
    local room, restored = Game():GetRoom(), 0
    for slot = 1, tonumber(manifest.slotCount) or 0 do
        local entry = M.entryFor(ledger.catalog, manifest, slot)
        if entry and not present[slot] and not ledger.taken[takenKey(entry)] then
            local position = DCRooms.getSlotWorldPosition(room, manifest, slot)
            local seed = state.seeds[slot]
            if not seed or seed == 0 then seed = M.slotSeed(ledger.seed, manifest.listIndex, slot) end
            local variant = entry.kind == TRINKET and PickupVariant.PICKUP_TRINKET or PickupVariant.PICKUP_COLLECTIBLE
            local spawned = position and spawnAt(variant, entry.id, position, seed)
            if spawned then
                state.seeds[slot] = spawned.InitSeed
                restored = restored + 1
            end
        end
    end
    if restored > 0 then
        ConchBlessing.printDebug("[Conch Certificate] room %s revisited: %d entries put back",
            tostring(manifest.listIndex), restored)
    end
end

local function prepareRoom(ledger)
    if not ledger.graph then
        local ok, graph, reason = pcall(DCRooms.capture, ledger.catalog, ledger.seed)
        if not ok or not graph then
            ledger.visiting = false
            ConchBlessing.printError("Conch Certificate could not adopt the Death Certificate rooms: "
                .. tostring(reason or graph))
            return false
        end
        ledger.graph = graph
    end
    local ok, runtime, reason = pcall(DCRooms.rebind, ledger.graph, #ledger.catalog)
    if not ok or not runtime then
        ledger.visiting = false
        ConchBlessing.printError("Conch Certificate lost its Death Certificate rooms: " .. tostring(reason or runtime))
        return false
    end
    local found, manifest = pcall(DCRooms.getCurrentManifest, ledger.graph, runtime)
    if not found or type(manifest) ~= "table" or manifest.kind ~= "stock" then return true end
    ledger.rooms = ledger.rooms or {}
    ledger.taken = ledger.taken or {}
    local state = ledger.rooms[manifest.key]
    if state then revisitRoom(ledger, manifest, state) else convertRoom(ledger, manifest) end
    return true
end

-- Early, so other room-entry work (Atropos's one-choice rooms, among others)
-- already sees the certificate's pedestals.
function M.onPostNewRoom()
    if M._ready ~= true then return end
    local ledger = getLedger()
    if not ledger or ledger.visiting ~= true then return end
    if currentDimension() ~= DC_DIMENSION then
        ledger.visiting = false -- home again, or out by other means
        return
    end
    prepareRoom(ledger)
end

-- Taking a catalog collectible in the area ends the visit the vanilla way, and
-- a catalog trinket can be picked up on the way. The ledger notes either, so a
-- revisit never puts it back and a later use knows whether anything is left.
local GOLDEN_TRINKET = 32768
function M.onPostItemPickup(_, _, picking)
    if M._ready ~= true or type(picking) ~= "table" or type(picking.subType) ~= "number" then return end
    local trinket = picking.itemType == ItemType.ITEM_TRINKET
    local id = trinket and picking.subType & ~GOLDEN_TRINKET or picking.subType
    local ledger = getLedger()
    if not ledger or ledger.visiting ~= true or currentDimension() ~= DC_DIMENSION then return end
    for _, entry in ipairs(ledger.catalog or {}) do
        if (entry.kind == TRINKET) == trinket and entry.id == id then
            ledger.taken = ledger.taken or {}
            ledger.taken[takenKey(entry)] = true
            return
        end
    end
end

function M.onGameStarted(_, isContinued)
    M._ready = true
    local ledger = getLedger()
    if not ledger or ledger.visiting ~= true then return end
    -- The room callback of a continued run came before game start.
    if isContinued and currentDimension() == DC_DIMENSION then
        prepareRoom(ledger)
    else
        ledger.visiting = currentDimension() == DC_DIMENSION
    end
end

function M.onPreGameExit()
    M._ready = false
end

function M.onPostNewLevel()
    if M._ready ~= true then return end
    getLedger() -- drops a ledger whose floor is gone
end

ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_NEW_ROOM, CALLBACK_PRIORITY_EARLY, M.onPostNewRoom)
do
    if isc and isc.ModCallbackCustom and isc.ModCallbackCustom.POST_ITEM_PICKUP then
        ConchBlessing:AddCallbackCustom(isc.ModCallbackCustom.POST_ITEM_PICKUP, M.onPostItemPickup)
    end
    -- A mid-run luamod never sees game start; SaveManager reports it instead.
    local sm = ConchBlessing.SaveManager
    local mod = ConchBlessing.originalMod
    if sm and mod and sm.SaveCallbacks and sm.SaveCallbacks.POST_DATA_LOAD then
        mod:AddCallback(sm.SaveCallbacks.POST_DATA_LOAD, function(_, _, isLuamod)
            if isLuamod then M._ready = true end
        end)
    end
end

-- Bench and offline test hooks (stripped from the Workshop package).
M._test = {
    ledger = getLedger,
    saveKey = SAVE_KEY,
    prepareRoom = prepareRoom,
}

return M
