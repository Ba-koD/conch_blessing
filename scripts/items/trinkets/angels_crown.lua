-- Angel's Crown - the positive Magic Conch upgrade of vanilla Devil's Crown (t146).
--
-- Devil's Crown turns every unvisited Treasure Room into a Red Treasure Room whose
-- item comes from the Devil Room pool and is bought with heart containers. Angel's
-- Crown keeps that shape and swaps both halves: the item comes from the Angel Room
-- pool and is bought with coins at its own shop price.
--
-- The engine owns Devil's Crown through RoomDescriptorFlag.DEVIL_TREASURE and there
-- is no angel counterpart, so the conversion is done here, once, on the first visit
-- to a Treasure Room - the same "unvisited rooms only" boundary the vanilla trinket
-- uses.
--
-- Two save scopes carry the result. The room save remembers that a room was already
-- converted and whether its blessed roll landed; each converted pedestal additionally
-- carries a reroll-persistent pickup flag, which is the store SaveManager also keeps
-- alive across the Ascent. The deal terms are reasserted from that flag on every
-- visit, so a re-entry, a D6 reroll, a continue or an Ascent revisit can never leave
-- an angel item lying around for free.

ConchBlessing.angelscrown = {}

local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local TrinketUtils = ConchBlessing.TrinketUtils or require("scripts.lib.trinket_utils")

ConchBlessing.angelscrown.data = {
    -- Coins asked for an item whose ItemConfig exposes no usable shop price.
    defaultShopPrice = 15,
    -- Blessed-room chance with a golden Angel's Crown OR Mom's Box.
    blessedChanceGolden = 0.25,
    -- Blessed-room chance with a golden Angel's Crown AND Mom's Box.
    blessedChanceBoth = 0.33,
    -- Extra Angel Room pedestals a blessed room receives.
    blessedExtraItems = 1,
}

local ROOM_SAVE_KEY = "angelsCrown"
local PICKUP_SAVE_KEY = "angelsCrownDeal"
local RNG_SHIFT_INDEX = 35

-- MC_POST_NEW_ROOM can fire before MC_POST_GAME_STARTED while SaveManager still holds
-- the previous session's floor tables, so the room handler stays inert until this run
-- has actually started.
local ready = false

-- ---------------------------------------------------------------- pure helpers

---Blessed-room chance for a holder's golden/Mom's Box state.
---Mirrors vanilla golden Devil's Crown: one modifier upgrades the room 25% of the
---time, both modifiers 33%.
---@param goldenCount integer @number of golden copies held
---@param hasMomsBox boolean
---@return number @probability in [0, 1]
local function getBlessedChance(goldenCount, hasMomsBox)
    local d = ConchBlessing.angelscrown.data
    local golden = (tonumber(goldenCount) or 0) > 0
    if golden and hasMomsBox then return d.blessedChanceBoth end
    if golden or hasMomsBox then return d.blessedChanceGolden end
    return 0
end

---Roll the blessed-room upgrade for one Treasure Room.
---@param rng RNG @seeded from the room, so the result survives a re-entry
---@param goldenCount integer
---@param hasMomsBox boolean
---@return boolean
local function rollBlessed(rng, goldenCount, hasMomsBox)
    local chance = getBlessedChance(goldenCount, hasMomsBox)
    if chance <= 0 then return false end
    return rng:RandomFloat() < chance
end

-- ------------------------------------------------------------------- utilities

local function getTrinketId()
    local itemData = ConchBlessing.ItemData and ConchBlessing.ItemData.ANGELS_CROWN
    local id = itemData and itemData.id
    if type(id) == "number" and id > 0 then return id end
    return nil
end

---Coin price for one collectible: its own shop price, exactly like a shop deal.
local function resolveShopPrice(collectibleType)
    local fallback = ConchBlessing.angelscrown.data.defaultShopPrice
    if type(collectibleType) ~= "number" or collectibleType <= 0 then return fallback end
    local config = Isaac.GetItemConfig()
    local item = config and config:GetCollectible(collectibleType)
    local price = item and item.ShopPrice
    if type(price) == "number" and price > 0 then return math.floor(price) end
    return fallback
end

---The holder whose golden/Mom's Box state decides this room's blessed roll.
---Any player's crown converts the room, so the most upgraded copy in the party wins.
---@return integer|nil goldenCount, boolean hasMomsBox
local function findBestHolder()
    local id = getTrinketId()
    if not id then return nil, false end

    local game = Game()
    local found, bestGolden, bestBox = false, 0, false
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player then
            local normalCount, goldenCount, hasMomsBox = TrinketUtils.getTrinketCounts(player, id)
            if (normalCount + goldenCount) > 0 then
                found = true
                if getBlessedChance(goldenCount, hasMomsBox) > getBlessedChance(bestGolden, bestBox) then
                    bestGolden, bestBox = goldenCount, hasMomsBox
                end
            end
        end
    end

    if not found then return nil, false end
    return bestGolden, bestBox
end

local function getRoomRecord(create, listIndex)
    local save
    if create then
        save = SaveManager.GetRoomSave(nil, false, listIndex)
    else
        save = SaveManager.TryGetRoomSave(nil, false, listIndex)
    end
    if type(save) ~= "table" then return nil end
    if create and type(save[ROOM_SAVE_KEY]) ~= "table" then
        save[ROOM_SAVE_KEY] = { converted = false, blessed = false }
    end
    return save[ROOM_SAVE_KEY]
end

---Mark one pedestal as an Angel's Crown deal. The reroll-persistent pickup save carries
---it through a D6 and is the scope SaveManager also restores on the Ascent.
---The marker names one pedestal and one quoted item instead of being a bare flag. The
---pickup save is indexed by pointer while the game runs, so a slot the engine later hands
---to a different pedestal must not inherit a deal, and the quoted item is what later
---proves whether the pedestal still holds what was actually for sale.
local function markDeal(pickup)
    local save = SaveManager.GetRerollPickupSave(pickup, false)
    if type(save) ~= "table" then
        ConchBlessing.printError("[Angel's Crown] pickup save unavailable; deal will not survive a re-entry")
        return false
    end
    save[PICKUP_SAVE_KEY] = { seed = pickup.InitSeed, item = pickup.SubType }
    return true
end

---The live deal on this pedestal, or nil when there is none. The table handed back is the
---saved one, so writing `item` on it updates the quote.
local function dealMarkerFor(pickup)
    local save = SaveManager.TryGetRerollPickupSave(pickup, false)
    if type(save) ~= "table" then return nil end
    local marker = save[PICKUP_SAVE_KEY]
    if marker == nil then return nil end
    if marker == true then
        -- Saved by a run from before the marker carried an identity. The quoted item is
        -- left unknown on purpose: a pedestal that was already bought out must read as
        -- settled rather than adopt the buyer's own item as the thing for sale.
        marker = { seed = pickup.InitSeed }
        save[PICKUP_SAVE_KEY] = marker
    end
    if type(marker) ~= "table" then return nil end
    -- A reroll keeps the pedestal's seed, so the identity holds across a D6, while a
    -- pedestal some other item dropped into the room carries a seed of its own.
    if marker.seed ~= pickup.InitSeed then return nil end
    return marker
end

local function isMarkedDeal(pickup)
    return dealMarkerFor(pickup) ~= nil
end

---Drop the marker for good. Used once a deal is settled, so that no later visit, Ascent
---restore or reroll can put a price back on that pedestal.
local function clearDeal(pickup)
    local save = SaveManager.TryGetRerollPickupSave(pickup, false)
    if type(save) == "table" then
        save[PICKUP_SAVE_KEY] = nil
    end
end

local function collectiblePedestals()
    local out = {}
    local entities = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1, false, false)
    for _, entity in ipairs(entities) do
        local pickup = entity:ToPickup()
        if pickup and pickup.SubType > 0 then
            out[#out + 1] = pickup
        end
    end
    return out
end

---Turn one pedestal into a coin-priced angel deal.
---The option group is cleared for good: like Devil's Crown, an Angel Treasure Room
---sells each item separately instead of forcing an either/or choice.
local function applyDealTerms(pickup)
    pickup.Price = resolveShopPrice(pickup.SubType)
    pickup.AutoUpdatePrice = false
    -- -1 keeps the engine from treating this as a shop slot (which rerolls into
    -- hearts) while still enforcing the coin cost on collision.
    pickup.ShopItemId = -1
    pickup.OptionsPickupIndex = 0
end

-- ---------------------------------------------------------------- room visuals

-- Vanilla Devil's Crown re-skins the Treasure Room door by swapping that door's own
-- spritesheet for a devil-coloured copy - same ANM2, same frames, same crown/horn
-- silhouette. This does the angel half of that: the ANM2 stays vanilla's and only its
-- spritesheet is swapped, so every open/closed/key/coin/broken frame keeps working and
-- the door still reads as the Treasure Room door instead of a foreign one.
-- The sheet is built from vanilla's own pair: every pixel the devil sheet recolours is
-- recoloured here too, and every pixel it leaves alone is left alone, so the angel door
-- covers the same states - closed, open, key lock, coin lock, golden key, broken. The
-- gold lock/key icon set is deliberately kept gold so a coin or golden-key lock still
-- reads differently from a plain one.
local ANGEL_DOOR_PNG = "gfx/grid/door_02_treasureroomdoor_angel.png"
-- Dropping Devil's Crown puts an unvisited Red Treasure Room's door back, so the angel
-- door has to be able to go back to vanilla's sheet the same way.
local VANILLA_DOOR_PNG = "gfx/grid/door_02_treasureroomdoor.png"

-- Devil's Crown puffs dust at the moment it flips a room. Which effect the engine uses
-- for that is not readable from Lua, so this uses POOF01: the tan rising puff the game
-- plays when something is swapped out, and the one this mod's Magic Conch delete path
-- already uses. It is a single named constant so a closer match is a one-line change.
local PUFF_VARIANT = EffectVariant.POOF01

local function spawnPuff(position)
    if not position then return end
    Isaac.Spawn(EntityType.ENTITY_EFFECT, PUFF_VARIANT, 0, position, Vector.Zero, nil)
end

-- The flip replays the door's own `Open` animation, so it swings open again already
-- wearing its new colour. A door the engine is holding shut - enemies in the room, a
-- lock - is left exactly as it is and only gets the puff.
local function playDoorFlipMotion(door)
    if not door or not door:IsOpen() then return end
    local sprite = door:GetSprite()
    if not sprite then return end
    sprite:Play("Open", true)
end

-- `Sprite:ReplaceSpritesheet` takes a LAYER id, not a spritesheet id. These vanilla
-- ANM2s draw one shared sheet across several layers, so every layer has to be
-- replaced or the visible art keeps the original sheet.
--   door_02_treasureroomdoor.anm2: Background, Door1, Door2, Frame, Key
--   grid_rock.anm2:                layer0, top
local DOOR_LAYER_COUNT = 5
local ROCK_LAYER_COUNT = 2

local function replaceAllLayers(sprite, layerCount, png)
    for layer = 0, layerCount - 1 do
        sprite:ReplaceSpritesheet(layer, png)
    end
end

local SECRET_ROOM_TYPES = {
    [RoomType.ROOM_SECRET] = true,
    [RoomType.ROOM_SUPERSECRET] = true,
    [RoomType.ROOM_ULTRASECRET] = true,
}

---Only the Treasure Room door may be re-skinned. A Treasure Room can also hold a
---secret-room hole in its wall, and that door uses a different sheet entirely.
---The engine's exact filename spelling is not something to assume, so this matches on
---the distinctive part of the name and falls back to the door's own room types when
---`Sprite:GetFilename` is unavailable.
local function isTreasureDoor(sprite, door)
    local ok, filename = pcall(function() return sprite:GetFilename() end)
    if ok and type(filename) == "string" and filename ~= "" then
        if string.find(string.lower(filename), "treasureroomdoor", 1, true) then
            return true, filename
        end
        return false, filename
    end
    local allowed = not SECRET_ROOM_TYPES[door.TargetRoomType]
        and not SECRET_ROOM_TYPES[door.CurrentRoomType]
    return allowed, nil
end

---@param png string @ANGEL_DOOR_PNG or VANILLA_DOOR_PNG
---@return boolean applied
local function applyDoorSheet(door, png)
    if not door then return false end
    local sprite = door:GetSprite()
    if not sprite then return false end

    local isTreasure, filename = isTreasureDoor(sprite, door)
    if not isTreasure then
        -- A recognised non-treasure door (a secret room's hole in the wall, say) is an
        -- ordinary skip; only report one this code could not classify.
        if filename == nil then
            ConchBlessing.printDebug(string.format(
                "[Angel's Crown] door skipped, unidentified: target=%s current=%s",
                tostring(door.TargetRoomType), tostring(door.CurrentRoomType)))
        end
        return false
    end

    -- Only the spritesheet is swapped. Re-loading the ANM2 first would reset the sprite,
    -- and the engine only calls Play on a door state change - so a door that was already
    -- Closed never gets told to close again and stays visually stuck open. Leaving the
    -- animation untouched keeps every open/closed/locked state exactly as the engine
    -- drives it, which is also how the vanilla devil re-skin behaves.
    replaceAllLayers(sprite, DOOR_LAYER_COUNT, png)
    sprite:LoadGraphics()
    return true
end

-- Angel Rooms have no backdrop of their own in BackdropType; they use the Cathedral
-- one, which is also what dresses the room's props. Devil's Crown gets its skulls the
-- same way - the Red Treasure Room's backdrop is what turns urns into skulls, so a
-- single backdrop swap covers both the floor/walls and the decoration.
local ANGEL_BACKDROP = BackdropType.CATHEDRAL
local CHANGE_DECORATION = 1

-- Every stage shares one `grid_rock.anm2` and swaps only its spritesheet, which is
-- the `rocks` entry of the backdrop. Replacing that sheet keeps tinted rocks, bomb
-- rocks and urns/skulls behaving exactly as before - only the art changes.
local ANGEL_ROCKS_PNG = "gfx/grid/rocks_cathedral.png"

-- Pits carry two sheets: the pit itself on 0 and the bridge on 1. Both are backdrop
-- entries (`pit` and `bridge`), not part of `grid_pit.anm2`'s own defaults.
local ANGEL_PIT_PNG = "gfx/grid/grid_pit_cathedral.png"
local ANGEL_BRIDGE_PNG = "gfx/grid/grid_bridge_cathedral.png"

---Re-skin the room's rocks and pits explicitly. The backdrop swap already asks the
---engine for this, so on REPENTOGON it is usually a no-op; doing it here covers grid
---entities that were already built when the room loaded, and gives the base game this
---half of the look even without REPENTOGON.
local function applyAngelGridLook()
    local room = Game():GetRoom()
    local reskinned = 0
    for index = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(index)
        local sprite = grid and grid:GetSprite()
        if sprite then
            if grid:ToRock() then
                replaceAllLayers(sprite, ROCK_LAYER_COUNT, ANGEL_ROCKS_PNG)
                sprite:LoadGraphics()
                reskinned = reskinned + 1
            elseif grid:ToPit() then
                -- grid_pit.anm2 is the exception: its two layers already carry two
                -- different sheets (layer 0 the pit, layer 1 the bridge).
                sprite:ReplaceSpritesheet(0, ANGEL_PIT_PNG)
                sprite:ReplaceSpritesheet(1, ANGEL_BRIDGE_PNG)
                sprite:LoadGraphics()
                reskinned = reskinned + 1
            end
        end
    end
    return reskinned
end

-- Fire Places come in two physics families plus coal, and entities2.xml shows the
-- difference clearly:
--   static  (0 plain, 1 red, 2 blue, 3 purple, 4 white)  hp 5, mass 100, friction 0.5,
--                                                        no grid collision
--   movable (10 plain, 12 blue, 13 purple)               hp 5, mass 1000, friction 1,
--                                                        grid collision "walls", 6 points
--   coal    (11)                                         hp 15, mass 5, 12 points, and a
--                                                        completely different ANM2 family
--
-- Within a family every variant carries identical stats and differs only by ANM2, so a
-- swap there is a pure re-skin. Crossing families is not: a movable fire is a puzzle
-- element the room was built around, and coal is not a fire at all.
--
-- So each fire moves to the holy-coded member of its own family, and the ones that are
-- already cool-toned stay put rather than being flattened into white. Absent keys are
-- deliberate no-ops: 2 blue, 4 white and 12 movable blue already fit, and 11 coal must
-- never be touched.
local ANGEL_FIREPLACE_VARIANTS = {
    [0] = 4,    -- Fire Place        -> White Fire Place
    [1] = 4,    -- Red Fire Place    -> White Fire Place
    [3] = 2,    -- Purple Fire Place -> Blue Fire Place
    [10] = 12,  -- Moveable          -> Moveable Blue (no white movable exists)
    [13] = 12,  -- Moveable Purple   -> Moveable Blue
}

local function applyAngelFireplaces()
    local converted = 0
    local fires = Isaac.FindByType(EntityType.ENTITY_FIREPLACE, -1, -1, false, false)
    for _, entity in ipairs(fires) do
        local target = ANGEL_FIREPLACE_VARIANTS[entity.Variant]
        local npc = target and entity:ToNPC() or nil
        if npc then
            local ok = pcall(function()
                npc:Morph(EntityType.ENTITY_FIREPLACE, target, entity.SubType, -1)
            end)
            if ok then converted = converted + 1 end
        end
    end
    return converted
end

-- No minimap icon. MiniMAPI re-derives every Treasure Room's `PermanentIcons` from the
-- room type on every rendered frame - that is how it keeps Devil's Crown's red icon in
-- sync - so a third-party value written there never survives to the draw. The only
-- slots that do survive are unsuitable: `VisitedIcons` appears alongside the treasure
-- icon and only after entry, and `NoUpdate` stops the wipe but also freezes the room's
-- Visited, Clear, DisplayFlags and ItemIcons updates. The re-skinned door is the map's
-- stand-in cue.

---Repaint the room the player is standing in. Doors are base API; the backdrop and
---its decorations need REPENTOGON's Room:SetBackdropType, so without it the effect
---degrades to the door alone.
local function applyAngelRoomLook()
    local room = Game():GetRoom()
    local doors, seen = 0, 0
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        if door then
            seen = seen + 1
            if applyDoorSheet(door, ANGEL_DOOR_PNG) then doors = doors + 1 end
        end
    end

    local backdropChanged = false
    if type(room.SetBackdropType) == "function" then
        -- The second argument is Backdrop::Init's changeDecoration flag: it is what
        -- re-dresses the room's props to match, so it must stay set.
        backdropChanged = pcall(function()
            room:SetBackdropType(ANGEL_BACKDROP, CHANGE_DECORATION)
        end)
    end

    local grids = applyAngelGridLook()
    local fires = applyAngelFireplaces()
    ConchBlessing.printDebug(string.format(
        "[Angel's Crown] room look applied: doors=%d/%d grids=%d fires=%d backdrop=%s",
        doors, seen, grids, fires,
        backdropChanged and "yes" or "no (REPENTOGON unavailable)"))
end

---True when the Treasure Room behind this door is, or is about to become, an Angel
---Treasure Room - so its door reads angelic from the outside the way a Red Treasure
---Room's does, before the player has ever stepped in.
---Which sheet a Treasure Room door seen from the outside should be wearing.
---Devil's Crown flips an unvisited Treasure Room's door the moment it is picked up and
---flips it back when dropped, so both directions are answered here.
---@return string|nil png @nil when this door is none of our business
local function treasureDoorSheetFor(door, holderPresent)
    if not door or door.TargetRoomType ~= RoomType.ROOM_TREASURE then return nil end

    local descriptor = Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex)
    if not descriptor then return nil end
    -- Devil's Crown owns this room; its door is not ours to paint in either direction.
    if descriptor.Flags and (descriptor.Flags & RoomDescriptor.FLAG_DEVIL_TREASURE) ~= 0 then
        return nil
    end

    local record = getRoomRecord(false, descriptor.ListIndex)
    if type(record) == "table" and record.converted then return ANGEL_DOOR_PNG end

    if (descriptor.VisitedCount or 0) > 0 then return nil end

    -- Never entered: holding the crown means it converts the moment it is opened, and
    -- dropping the crown puts the door back.
    return holderPresent and ANGEL_DOOR_PNG or VANILLA_DOOR_PNG
end

---@param withPuff boolean @true only on the frame the crown was picked up or dropped
local function applyAngelDoorsFromOutside(holderPresent, withPuff)
    local room = Game():GetRoom()
    local angel = 0
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        local png = treasureDoorSheetFor(door, holderPresent)
        if png and applyDoorSheet(door, png) then
            if png == ANGEL_DOOR_PNG then angel = angel + 1 end
            if withPuff then
                -- Sheet first, so the door already wears its new colour as it swings.
                spawnPuff(door.Position)
                playDoorFlipMotion(door)
            end
        end
    end
    if angel > 0 then
        ConchBlessing.printDebug("[Angel's Crown] angel doors re-skinned from outside: " .. tostring(angel))
    end
end

-- The engine finishes building door sprites and MiniMAPI finishes rebuilding its level
-- after MC_POST_NEW_ROOM has already run, so anything written to either during that
-- callback is discarded. There is no readiness event for "the room is fully built", so
-- the door pass is repeated for a small, bounded number of update frames
-- after each room load and then stops. Everything else (items, backdrop, grids, fires)
-- survives the room callback and is not repeated here.
local LOOK_RETRY_FRAMES = 3
local pendingLookFrames = 0

-- Picking the crown up does not change rooms, so nothing would repaint the door of the
-- Treasure Room next door - yet that is exactly when Devil's Crown flips its door red.
-- The base API has no trinket add/remove event, so holding it is polled the same way
-- this mod's other trinkets poll theirs, and a change requests a fresh door pass.
local hadHolderLastFrame = false

local function requestDoorPass()
    pendingLookFrames = LOOK_RETRY_FRAMES
end

-- --------------------------------------------------------------- room handling

local function spawnAngelPedestal(position, seed)
    local pool = Game():GetItemPool()
    local collectibleType = pool:GetCollectible(ItemPoolType.POOL_ANGEL, true, seed)
    if type(collectibleType) ~= "number" or collectibleType <= 0 then
        return nil
    end

    local entity = Game():Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
        position, Vector.Zero, nil, collectibleType, seed)
    local pickup = entity and entity:ToPickup()
    if not pickup then return nil end

    applyDealTerms(pickup)
    return pickup
end

---A blessed room gets one more angel deal and an Eternal Heart, mirroring the extra
---deals and Black Hearts that golden Devil's Crown's upgraded room hands out.
local function applyBlessing(rng)
    local room = Game():GetRoom()
    local extras = math.max(0, math.floor(ConchBlessing.angelscrown.data.blessedExtraItems or 0))

    for _ = 1, extras do
        local seed = rng:Next()
        if seed == 0 then seed = 1 end
        local position = room:FindFreePickupSpawnPosition(room:GetCenterPos(), 40, true)
        local pickup = spawnAngelPedestal(position, seed)
        if pickup then
            markDeal(pickup)
            ConchBlessing.printDebug(string.format(
                "[Angel's Crown] blessed extra pedestal: item=%d price=%d seed=%d",
                pickup.SubType, pickup.Price, pickup.InitSeed))
        end
    end

    local heartSeed = rng:Next()
    if heartSeed == 0 then heartSeed = 1 end
    local heartPosition = room:FindFreePickupSpawnPosition(room:GetCenterPos(), 60, true)
    Game():Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_HEART, heartPosition,
        Vector.Zero, nil, HeartSubType.HEART_ETERNAL, heartSeed)

    local sfx = SFXManager and SFXManager()
    if sfx and SoundEffect and SoundEffect.SOUND_CHOIR_UNLOCK then
        sfx:Play(SoundEffect.SOUND_CHOIR_UNLOCK)
    end
end

local function convertRoom(record, goldenCount, hasMomsBox)
    local roomDescriptor = Game():GetLevel():GetCurrentRoomDesc()
    local seed = roomDescriptor and roomDescriptor.SpawnSeed or 0
    if seed == 0 then seed = Game():GetRoom():GetSpawnSeed() end
    if seed == 0 then seed = 1 end

    local rng = RNG()
    rng:SetSeed(seed, RNG_SHIFT_INDEX)

    local pool = Game():GetItemPool()
    local converted = 0
    for _, pickup in ipairs(collectiblePedestals()) do
        local pedestalSeed = pickup.InitSeed
        if pedestalSeed == 0 then pedestalSeed = rng:Next() end
        if pedestalSeed == 0 then pedestalSeed = 1 end

        local collectibleType = pool:GetCollectible(ItemPoolType.POOL_ANGEL, true, pedestalSeed)
        if type(collectibleType) == "number" and collectibleType > 0 then
            -- KeepPrice is false on purpose: replacing the deal contract is the whole
            -- effect, so the treasure pedestal's free/shop terms must not be carried
            -- over. KeepSeed is true so the identity SaveManager keys the pickup save
            -- by survives the morph.
            pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
                collectibleType, false, true, false)
            applyDealTerms(pickup)
            markDeal(pickup)
            -- The player is standing here watching the pedestal change, so it gets the
            -- same puff the door flip does.
            spawnPuff(pickup.Position)
            converted = converted + 1
            ConchBlessing.printDebug(string.format(
                "[Angel's Crown] converted pedestal: item=%d price=%d seed=%d",
                pickup.SubType, pickup.Price, pickup.InitSeed))
        end
    end

    record.blessed = rollBlessed(rng, goldenCount, hasMomsBox)
    record.converted = true
    if record.blessed then
        applyBlessing(rng)
    end

    ConchBlessing.printDebug(string.format(
        "[Angel's Crown] room converted: pedestals=%d blessed=%s chance=%.2f (golden=%d momsBox=%s)",
        converted, tostring(record.blessed), getBlessedChance(goldenCount, hasMomsBox),
        goldenCount or 0, tostring(hasMomsBox)))
end

-- A reroll swaps the item under a pedestal without changing rooms, so the deal terms
-- are restated on the frame the item changes: the price follows whatever the pedestal
-- now holds, and a rerolled angel item can never be left lying there for free.
local dealSubTypes = {}

local function resetDealTracking()
    dealSubTypes = {}
end

-- Buying an active while already holding one does not empty the pedestal: the engine
-- leaves the buyer's own previous active standing there, on the same pedestal entity,
-- and vanilla hands that back for free. The deal is over at that point, so the price
-- comes off and the marker goes away - otherwise the next visit would charge the player
-- coins for the item they walked in with.
--
-- Two things have to hold, and neither is enough alone. Touched is the engine's record
-- that someone took the item from this pedestal, and the item standing there no longer
-- being the quoted one proves what is left is the buyer's own. A reroll changes the item
-- without Touched, and bumping a pedestal the player cannot afford cannot change the
-- item, so neither of those reads as a settled deal.
local function isSettledDeal(pickup, marker)
    return pickup.Touched == true and marker.item ~= pickup.SubType
end

local function settleDeal(pickup)
    clearDeal(pickup)
    dealSubTypes[GetPtrHash(pickup)] = nil
    pickup.Price = 0
    pickup.AutoUpdatePrice = false
    ConchBlessing.printDebug(string.format(
        "[Angel's Crown] deal settled, pedestal released: item=%d", pickup.SubType))
    SaveManager.Save()
end

---Apply the deal and record what was quoted, so a later visit can tell the item that was
---for sale from whatever ends up standing on the pedestal.
local function quoteDeal(pickup, marker)
    applyDealTerms(pickup)
    marker.item = pickup.SubType
    dealSubTypes[GetPtrHash(pickup)] = pickup.SubType
end

---Re-apply the deal terms to every marked pedestal in the current room. The engine
---does not promise to keep a manually assigned price on a non-shop pedestal across a
---room reload, and a D6 style reroll changes the item behind an unchanged pickup, so
---the price is recomputed from whatever the pedestal currently holds. This runs even
---when the room record is gone (an Ascent revisit rebuilds the floor save from
---scratch) because the marker itself is what proves ownership.
local function restoreDeals()
    local restored = 0
    for _, pickup in ipairs(collectiblePedestals()) do
        local marker = dealMarkerFor(pickup)
        if marker then
            if isSettledDeal(pickup, marker) then
                settleDeal(pickup)
            else
                quoteDeal(pickup, marker)
                restored = restored + 1
            end
        end
    end
    if restored > 0 then
        ConchBlessing.printDebug("[Angel's Crown] restored angel deals: " .. tostring(restored))
    end
end

local function refreshRerolledDeals()
    for _, pickup in ipairs(collectiblePedestals()) do
        local marker = dealMarkerFor(pickup)
        if marker then
            if isSettledDeal(pickup, marker) then
                settleDeal(pickup)
            else
                -- A price the engine wiped is restated too: an unsettled deal is never
                -- free, so a non-positive price means the contract was dropped somewhere.
                if dealSubTypes[GetPtrHash(pickup)] ~= pickup.SubType or pickup.Price <= 0 then
                    quoteDeal(pickup, marker)
                    ConchBlessing.printDebug(string.format(
                        "[Angel's Crown] deal restated after a reroll: item=%d price=%d",
                        pickup.SubType, pickup.Price))
                end
            end
        end
    end
end

-- ------------------------------------------------------------------- item pool

-- Devil's Crown does not patch rerolled items, it changes which pool the room draws
-- from: RoomDescriptorFlag.DEVIL_TREASURE makes the engine answer that room's requests
-- from the Devil Room pool, so a D6 in a Red Treasure Room returns a devil item on its
-- own. There is no angel counterpart flag, so the same thing is done one step later, at
-- the point where the engine asks for a collectible: a Treasure Room pool request made
-- while the player stands in a converted room is answered from the Angel Room pool.
-- Nothing is pinned to a pedestal, so D6, D100, Dice Rooms and every other reroll agree
-- without knowing about this trinket, the treasure pool keeps the item it never handed
-- out, and Chaos still scrambles the pool underneath because the answer itself comes
-- from the engine's own GetCollectible.
local inPoolOverride = false

---@param poolType ItemPoolType
---@param decrease boolean
---@param seed integer
---@return CollectibleType|nil @nil leaves the engine's own pick alone
function ConchBlessing.angelscrown.onPreGetCollectible(_, poolType, decrease, seed)
    if not ready or inPoolOverride then return nil end
    if poolType ~= ItemPoolType.POOL_TREASURE then return nil end

    local room = Game():GetRoom()
    if room:GetType() ~= RoomType.ROOM_TREASURE then return nil end

    -- The room owns this, not the trinket: the crown can be dropped and the room keeps
    -- drawing angel items, the way a Red Treasure Room keeps its devil pool. An Ascent
    -- revisit rebuilds the floor save, so the pedestal markers stand in for the record
    -- there, exactly as they do for the deal terms.
    local record = getRoomRecord(false)
    local owned = record ~= nil and record.converted == true
    if not owned then
        for _, pickup in ipairs(collectiblePedestals()) do
            if isMarkedDeal(pickup) then
                owned = true
                break
            end
        end
    end
    if not owned then return nil end

    -- The guard is what keeps this one level deep: the angel request below re-enters
    -- this callback, and without it an answer would be asked of itself forever.
    inPoolOverride = true
    local ok, collectibleType = pcall(function()
        return Game():GetItemPool():GetCollectible(ItemPoolType.POOL_ANGEL, decrease, seed)
    end)
    inPoolOverride = false

    if ok and type(collectibleType) == "number" and collectibleType > 0 then
        ConchBlessing.printDebug(string.format(
            "[Angel's Crown] treasure request answered from the angel pool: item=%d", collectibleType))
        return collectibleType
    end

    -- An exhausted angel pool falls back to the room's own pool rather than nothing.
    return nil
end

function ConchBlessing.angelscrown.onGameStarted()
    ready = true
    hadHolderLastFrame = false
    -- A continue lands straight in the saved room, and its MC_POST_NEW_ROOM already
    -- ran behind the closed gate, so reconcile that room here.
    ConchBlessing.angelscrown.onPostNewRoom()
end

function ConchBlessing.angelscrown.onPreGameExit()
    ready = false
    pendingLookFrames = 0
    hadHolderLastFrame = false
    resetDealTracking()
end

---Runs the deferred half of the look: the door sheet, which the engine overwrites if
---it is set during MC_POST_NEW_ROOM, plus the pickup/drop repaint.
function ConchBlessing.angelscrown.onPostUpdate()
    if not ready then return end

    -- A reroll lands mid-room, with no room change behind it to restore the deal.
    if Game():GetRoom():GetType() == RoomType.ROOM_TREASURE then
        local dealRecord = getRoomRecord(false)
        if dealRecord and dealRecord.converted then refreshRerolledDeals() end
    end

    local holderPresent = findBestHolder() ~= nil
    local holderChanged = holderPresent ~= hadHolderLastFrame
    if holderChanged then
        hadHolderLastFrame = holderPresent
        requestDoorPass()
    end

    if pendingLookFrames <= 0 then return end
    pendingLookFrames = pendingLookFrames - 1

    local room = Game():GetRoom()
    if room:GetType() ~= RoomType.ROOM_TREASURE then
        -- The puff belongs to the flip itself, so it fires on the frame the crown
        -- changed hands and not on the retry frames behind it.
        applyAngelDoorsFromOutside(holderPresent, holderChanged)
        return
    end

    local record = getRoomRecord(false)
    if not (record and record.converted) then return end

    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        applyDoorSheet(room:GetDoor(slot), ANGEL_DOOR_PNG)
    end
end

function ConchBlessing.angelscrown.onPostNewRoom()
    if not ready then return end

    local goldenCount, hasMomsBox = findBestHolder()
    local room = Game():GetRoom()
    requestDoorPass()
    resetDealTracking()

    if room:GetType() ~= RoomType.ROOM_TREASURE then
        -- Outside a Treasure Room the only thing to do is re-skin its door. This runs
        -- even with no holder so an already converted room keeps its angel door after
        -- the crown is dropped; the slot scan returns on TargetRoomType immediately.
        applyAngelDoorsFromOutside(goldenCount ~= nil, false)
        return
    end

    restoreDeals()

    local record = getRoomRecord(false)
    if record and record.converted then
        applyAngelRoomLook()
        return
    end

    -- Greed Mode's silver Treasure Rooms are outside Devil's Crown's contract too.
    if Game():IsGreedMode() then return end

    local level = Game():GetLevel()
    -- Devil's Crown does not convert Treasure Rooms revisited on the Ascent, and those
    -- rooms already carry whatever this trinket did to them on the way down.
    if level:IsAscent() then return end

    local roomDescriptor = level:GetCurrentRoomDesc()
    if not roomDescriptor then return end

    -- Devil's Crown already claimed this room; the engine's Red Treasure Room wins.
    if roomDescriptor.Flags and (roomDescriptor.Flags & RoomDescriptor.FLAG_DEVIL_TREASURE) ~= 0 then
        return
    end

    -- Same boundary as Devil's Crown: only rooms that have never been entered.
    if not room:IsFirstVisit() then return end

    if goldenCount == nil then return end

    record = getRoomRecord(true)
    if not record then
        ConchBlessing.printError("[Angel's Crown] room save unavailable; skipping conversion")
        return
    end

    convertRoom(record, goldenCount, hasMomsBox)
    applyAngelRoomLook()
    SaveManager.Save()
end

-- Exposed for scripts/dev/rng_probe.lua only; see docs/rng_testing.md.
ConchBlessing.angelscrown._test = {
    getBlessedChance = getBlessedChance,
    rollBlessed = rollBlessed,
}
