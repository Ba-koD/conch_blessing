local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 시리얼 (Cereal), the Magic Conch's positive answer to Breakfast (user design
-- 2026-11-24). Breakfast's icon is a milk carton; this is what goes in the milk.
-- A zero-charge active:
--   * used while an item is held up after touching its pedestal, that item is
--     not kept: the queue is emptied and the item's number falls to the floor
--     as number cereal, real pickups, digit for digit as the number is written
--     (item 4 is one cereal, 4). A Breakfast breaks into three random digits.
--   * used near a pedestal it can grind (marked with an arrow while in reach,
--     checked the way Quick Pick checks what it may pick up), the item on it
--     is ground the same way without being taken, actives included.
--   * used otherwise, it opens a bowl Isaac holds over his head: the shooting
--     keys choose cereal to put in, the key that used it confirms and the drop
--     key or Esc closes. The digits put in (never starting with 0) make the
--     item with that number for one milk: a passive or familiar is held up and
--     taken, an active stands on a pedestal nearby. A number no item has, or
--     one no item pool lists, is cancelled with nothing spent.
--   * while anyone living holds it, every item pool draw turns into Breakfast
--     (one milk) with chance 1/2 x 1/2 ^ (milk held), answered before the draw
--     so the pool loses nothing.
-- Cereal and milk are shared like coins (the global run save `cereal`).
local M = {}
ConchBlessing.cereal = M
local View = require("scripts.lib.conch_answer_view")
local Sound = require("scripts.lib.sound_volume")
local RunSaveCache = require("scripts.lib.run_save_cache")
local isc = require("scripts.lib.isaacscript-common")

local ID = Isaac.GetItemIdByName("Cereal")
local BREAKFAST = CollectibleType and CollectibleType.COLLECTIBLE_BREAKFAST or 25
local VARIANT = Isaac.GetEntityVariantByName("Conch Blessing Cereal 0")
if type(VARIANT) ~= "number" or VARIANT < 0 then
    ConchBlessing.printError("[Cereal] the number cereal pickup is not registered (entities2.xml)")
    VARIANT = nil
end

M.data = {
    -- A draw becomes Breakfast with chance milkBase x milkChance ^ milk held:
    -- 50% with no milk (user decision 2026-11-24, was 100%), halved per milk.
    milkBase = 0.5,
    milkChance = 0.5,
    grindRange = 80,     -- reach to grind a pedestal (Quick Pick's default pick-up reach)
    markerLift = 52,     -- screen pixels from a pedestal up to its grind marker
    rowGap = 20,         -- world units between the cereal of a broken number, left to right
    rowDistance = 40,    -- how far from the player that row lies
    takeAfter = 8,       -- updates before a dropped cereal can be picked up
    bowlLift = 28,       -- screen pixels from the feet up to the bottom of the bowl
    -- The bowl (56x28, drawn the Isaac way, user request 2026-11-24): the
    -- cereal float on the milk just under its rim, or with no milk lie on its
    -- bottom, half hidden by the near rim; a splash shows only on milk.
    bowlHeight = 28,
    floatY = 1,          -- cereal top below the bowl's top, on the milk
    bottomY = 6,         -- the same, in an empty bowl
    milkY = 9,           -- the milk's surface below the bowl's top
    toastFrames = 45,    -- how long a short message stays over the head
    dropDistance = 60,   -- how far from the player a crafted active is set down
    -- Text sizes (LanaPixel scale), raised at the user's request (2026-11-24).
    nameScale = 0.75,    -- the item the number makes
    noteScale = 0.6,     -- an active's "set down nearby" note
    hintScale = 0.65,    -- the keys under the feet
    -- Render frames (60 a second) of the bowl's motions: a cereal put in falls
    -- from the row into the milk and splashes, one taken out jumps back up.
    -- `slide` is the share of the way a cereal in the bowl moves toward its
    -- centred place each render frame.
    fx = { fall = 14, splash = 14, out = 12, slide = 0.25 },
}

local SHOOT = {
    left = ButtonAction.ACTION_SHOOTLEFT, right = ButtonAction.ACTION_SHOOTRIGHT,
    up = ButtonAction.ACTION_SHOOTUP, down = ButtonAction.ACTION_SHOOTDOWN,
}
local SHOOTING = {}
for _, action in pairs(SHOOT) do SHOOTING[action] = true end
-- The keys that close the bowl: the drop key, and Esc / Start (user request
-- 2026-11-24), which the game asks for with no player while the bowl is open.
local CANCEL = ButtonAction.ACTION_DROP
local CLOSING = { [CANCEL] = true }
local PAUSING = {}
for _, name in ipairs({ "ACTION_PAUSE", "ACTION_MENUBACK" }) do
    local action = ButtonAction[name]
    if action then CLOSING[action], PAUSING[action] = true, true end
end
local TAKEN = "__ConchBlessingCerealTaken"
local POOL_RNG_SHIFT = 35

local pickers = {}      -- player hash -> open bowl
local watches = {}      -- player hash -> an item held up that the use key may break
local locks = {}        -- player hash -> { [action] = true }: kept from the game until let go
local owners = {}       -- player hash -> { ptr, controller }
local lastSel = {}      -- player hash -> the digit last framed
local toasts = {}       -- player hash -> { text, frames }
local bits = {}         -- cosmetic collect animations of taken cereal
local targets = {}      -- player hash -> EntityPtr of the pedestal a use would grind now
local testKeys = {}     -- bench-held keys (a mod's own reads ignore MC_INPUT_ACTION)
local reading = false
local counting = false   -- inside the one real use a made or broken item counts as
local countedUses = 0
local pendingCounts = {} -- uses to count on the next update
local maxIdCache = nil
local pooledCache = nil
local sprites = {}
local font = nil

local function sfx(id, volume)
    if id then SFXManager():Play(id, Sound.volume(volume), 0, false, 1) end
end

local function living(player)
    return player ~= nil and player:Exists() and not player:IsDead()
        and not (type(player.IsCoopGhost) == "function" and player:IsCoopGhost())
end

local function eachPlayer(fn)
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then fn(player) end
    end
end

--- Whether any living player holds Cereal.
function M.anyHolder()
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if living(player) and player:HasCollectible(ID) then return true end
    end
    return false
end

-- ------------------------------------------------------------------ store
-- The shared cereal (ten counts, digit d at index d + 1) and milk.
local function store(create)
    local run = RunSaveCache.global(create)
    if type(run) ~= "table" then return nil end
    local s = run.cereal
    if type(s) ~= "table" then
        if not create then return nil end
        s = {}
        run.cereal = s
    end
    if type(s.digits) ~= "table" then s.digits = {} end
    for i = 1, 10 do
        local n = tonumber(s.digits[i]) or 0
        if n < 0 or n ~= math.floor(n) then n = math.max(0, math.floor(n)) end
        s.digits[i] = n
    end
    local milk = tonumber(s.milk) or 0
    s.milk = math.max(0, math.floor(milk))
    return s
end

function M.count(d)
    local s = store(false)
    return s and s.digits[d + 1] or 0
end

function M.milk()
    local s = store(false)
    return s and s.milk or 0
end

function M.total()
    local s = store(false)
    if not s then return 0 end
    local total = 0
    for i = 1, 10 do total = total + s.digits[i] end
    return total
end

function M.addDigit(d, n)
    local s = store(true)
    if not s or d < 0 or d > 9 then return false end
    s.digits[d + 1] = math.max(0, s.digits[d + 1] + (n or 1))
    return true
end

function M.addMilk(n)
    local s = store(true)
    if not s then return false end
    s.milk = math.max(0, s.milk + (n or 1))
    return true
end

-- ------------------------------------------------------------------ numbers
local function maxId()
    if not maxIdCache then
        local collectibles = Isaac.GetItemConfig():GetCollectibles()
        maxIdCache = math.max(1, (collectibles and collectibles.Size or 2) - 1)
    end
    return maxIdCache
end

--- How many digits the highest item number needs: the bowl's slots.
local function maxDigits(top)
    return #tostring(math.floor(top or maxId()))
end

--- An item number written as cereal, as it is written (4 -> 4, 118 -> 1, 1, 8;
--- user request 2026-11-24: no padding to three digits).
function M.digitsOf(id)
    local out = {}
    for ch in tostring(math.floor(id)):gmatch("%d") do out[#out + 1] = tonumber(ch) end
    return out
end

-- Digit `d` goes in while the number is shorter than the longest item number;
-- a number never starts with 0.
local function canAdd(entered, limit, d)
    if #entered >= limit then return false end
    if #entered == 0 and d == 0 then return false end
    return true
end

--- Where cereal `i` of `count` sits in the bowl: its left edge, from the bowl's
--- centre, so the group is always centred (10 wide, 11 apart).
function M.centred(count, i)
    return -(count - 1) * 5.5 + (i - 1) * 11 - 5
end

local function number(entered)
    local n = 0
    for _, d in ipairs(entered) do n = n * 10 + d end
    return n
end

-- The items some item pool lists, or nil when the build cannot list pools
-- (Family Combo's rule: story items such as the shovel pieces are in none).
local function pooledItems()
    if pooledCache ~= nil then return pooledCache or nil end
    pooledCache = false
    local pool = Game():GetItemPool()
    if not pool or type(pool.GetCollectiblesFromPool) ~= "function" then return nil end
    local count = type(pool.GetNumItemPools) == "function" and pool:GetNumItemPools()
        or (ItemPoolType and ItemPoolType.NUM_ITEMPOOLS)
    if type(count) ~= "number" or count <= 0 then return nil end
    local listed = {}
    for kind = 0, count - 1 do
        local ok, entries = pcall(pool.GetCollectiblesFromPool, pool, kind)
        if ok and type(entries) == "table" then
            for _, entry in ipairs(entries) do
                if type(entry) == "table" and type(entry.itemID) == "number" then listed[entry.itemID] = true end
            end
        end
    end
    pooledCache = listed
    return listed
end

-- "ok", "nocraft" (an item the bowl may not make) or "none" (no such item).
local function craftable(id)
    local config = Isaac.GetItemConfig():GetCollectible(id)
    if not config then return "none" end
    local quest = ItemConfig and ItemConfig.TAG_QUEST
    if config.Hidden or (quest and type(config.HasTags) == "function" and config:HasTags(quest)) then
        return "nocraft", config
    end
    if type(config.IsAvailable) == "function" then
        local ok, available = pcall(config.IsAvailable, config)
        if ok and available == false then return "nocraft", config end
    end
    local listed = pooledItems()
    if listed and not listed[id] then return "nocraft", config end
    return "ok", config
end

--- What `entered` makes: "short" (nothing in yet), "none", "nocraft" or "ok",
--- with the number and the item's config.
function M.lookup(entered)
    if #entered == 0 then return "short" end
    local n = number(entered)
    if entered[1] == 0 or n <= 0 or n > maxId() then return "none", n end
    local state, config = craftable(n)
    return state, n, config
end

-- ------------------------------------------------------------------ input
local function confirmAction(slot)
    if slot == ActiveSlot.SLOT_POCKET or slot == ActiveSlot.SLOT_POCKET2 then return ButtonAction.ACTION_PILLCARD end
    return ButtonAction.ACTION_ITEM
end

-- The slot Cereal is in and the key that uses it, or nil.
local function cerealSlot(player)
    for _, slot in ipairs({ ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_POCKET }) do
        if player:GetActiveItem(slot) == ID then return slot, confirmAction(slot) end
    end
    return nil
end

local function pressed(player, action)
    if testKeys[action] then return true end
    reading = true
    local ok, value = pcall(Input.IsActionPressed, action, player.ControllerIndex)
    reading = false
    return ok and value == true
end

local function readInputs(player, picker)
    local now = { confirm = pressed(player, picker.confirm), closing = {} }
    for action in pairs(CLOSING) do
        if pressed(player, action) then
            now.cancel = true
            now.closing[#now.closing + 1] = action
        end
    end
    for name, action in pairs(SHOOT) do now[name] = pressed(player, action) end
    return now
end

local function forget(key)
    if not pickers[key] and not locks[key] and not watches[key] then owners[key] = nil end
end

local function own(key, player)
    owners[key] = owners[key] or { ptr = EntityPtr(player), controller = player.ControllerIndex }
end

local function lock(key, player, action)
    locks[key] = locks[key] or {}
    locks[key][action] = true
    own(key, player)
end

local function toast(key, text)
    if text then toasts[key] = { text = text, frames = M.data.toastFrames } end
end

-- A made or broken item counts as one use of Cereal (see "Uses" below).
local function queueCount(player, slot)
    pendingCounts[#pendingCounts + 1] = { ptr = EntityPtr(player), slot = slot }
end

-- ------------------------------------------------------------------ sprites
local function loadSprite(path, anim, sheet)
    local ok, sprite = pcall(function()
        local s = Sprite()
        s:Load(path, true)
        if sheet then s:ReplaceSpritesheet(0, sheet); s:LoadGraphics() end
        s:SetFrame(anim, 0)
        return s
    end)
    return ok and sprite or nil
end

local function ui()
    if sprites.ui == nil then sprites.ui = loadSprite("gfx/ui/conch_cereal_ui.anm2", "Digit") or false end
    return sprites.ui or nil
end

local function icon(id)
    sprites.icons = sprites.icons or {}
    if sprites.icons[id] == nil then
        local item = Isaac.GetItemConfig():GetCollectible(id)
        local gfx = item and item.GfxFileName
        sprites.icons[id] = type(gfx) == "string" and gfx ~= ""
            and loadSprite("gfx/effects/conch_upgrade_icon.anm2", "Idle", gfx) or false
    end
    return sprites.icons[id] or nil
end

local function rect(x, y, w, h, color)
    if sprites.pixel == nil then sprites.pixel = loadSprite("gfx/effects/conch_upgrade_pixel.anm2", "Idle") or false end
    local s = sprites.pixel
    if not s then return end
    s.Scale = Vector(w, h)
    s.Color = color
    s:Render(Vector(x, y))
end

local function part(name, frame, x, y, color, scale)
    local s = ui()
    if not s then return end
    s:SetFrame(name, frame or 0)
    s.Color = color or Color(1, 1, 1, 1)
    s.Scale = Vector(scale or 1, scale or 1)
    s:Render(Vector(x, y))
end

local function hudFont()
    if font == nil then
        local ok, f = pcall(function()
            local loaded = Font()
            loaded:Load("font/pftempestasevencondensed.fnt")
            return loaded:IsLoaded() and loaded or nil
        end)
        font = ok and f or false
    end
    return font or nil
end

local function digitsText(text, x, y, color, scale)
    local f = hudFont()
    if not f then return end
    scale = scale or 1
    f:DrawStringScaled(text, x, y, scale, scale, color or KColor(1, 1, 1, 1), 0, false)
end

-- The item's name in the language the player reads: this mod's from its own
-- text, any other from EID when it is there; without EID none.
local function itemName(id)
    for _, entry in pairs(ConchBlessing.ItemData or {}) do
        if type(entry) == "table" and entry.id == id and entry.type ~= "trinket" then
            local lang = ConchBlessing_Config and ConchBlessing_Config.GetCurrentLanguage and ConchBlessing_Config.GetCurrentLanguage()
            if type(entry.name) == "table" then return entry.name[lang] or entry.name.en end
            return entry.name
        end
    end
    local eid = rawget(_G, "EID")
    if eid and type(eid.getObjectName) == "function" then
        local ok, name = pcall(eid.getObjectName, eid, 5, 100, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

-- ------------------------------------------------------------------ breaking
--- The collectible `player` holds up waiting to be added, or nil.
local function queuedCollectible(player)
    if type(player.IsItemQueueEmpty) == "function" and player:IsItemQueueEmpty() then return nil end
    local queue = player.QueuedItem
    local item = queue and queue.Item
    if not item or item.Type == ItemType.ITEM_TRINKET or type(item.ID) ~= "number" or item.ID <= 0 then return nil end
    return item
end

-- The item a break is turning away, per player: the engine empties the queue
-- itself (`FlushQueueItem`, as when a hit ends a pickup) and the addition that
-- follows is refused in REPENTOGON's MC_PRE_ADD_COLLECTIBLE. Clearing the
-- queue's Item field by hand and cutting the hold-up animation short left the
-- engine's pickup unfinished: no other item of the room could be taken and
-- the body was drawn see-through (user report 2026-11-24).
local refusing = {}

function M.onPreAddCollectible(_, id, _, _, _, _, player)
    local key = player and GetPtrHash(player)
    if key and refusing[key] == id then
        refusing[key] = nil
        return false
    end
end

local function turnAway(player, id)
    if type(player.FlushQueueItem) ~= "function" then return false end
    local key = GetPtrHash(player)
    local before = player:GetCollectibleNum(id, true)
    refusing[key] = id
    local ok = pcall(player.FlushQueueItem, player)
    local refused = refusing[key] == nil
    refusing[key] = nil
    return ok and refused and player:IsItemQueueEmpty() and player:GetCollectibleNum(id, true) == before
end

-- The broken number lies in a row, left to right in its own order (user
-- request 2026-11-24: not scattered): in front of the player, else above,
-- right or left of them, wherever the whole row is on open floor.
local ROW_SIDES = { Vector(0, 1), Vector(0, -1), Vector(1, 0), Vector(-1, 0) }
local function rowSpots(origin, n)
    local room = Game():GetRoom()
    local gap, away = M.data.rowGap, M.data.rowDistance
    for _, side in ipairs(ROW_SIDES) do
        local centre = origin + side * away
        local spots = {}
        for i = 1, n do
            local pos = centre + Vector((i - (n + 1) / 2) * gap, 0)
            if not room:IsPositionInRoom(pos, 8)
                or room:GetGridCollisionAtPos(pos) ~= GridCollisionClass.COLLISION_NONE then
                spots = nil
                break
            end
            spots[i] = pos
        end
        if spots then return spots end
    end
    local spots = {}
    for i = 1, n do spots[i] = origin + Vector((i - (n + 1) / 2) * gap, 0) end
    return spots
end

local function spawnCereal(d, pos, player)
    if not VARIANT then return nil end
    return Isaac.Spawn(EntityType.ENTITY_PICKUP, VARIANT, d, pos, Vector.Zero, player)
end

--- Break the item `player` holds up into its number's cereal. Returns true,
--- the item and the digits dropped, or false.
function M.breakHeld(player)
    local item = player and queuedCollectible(player)
    if not item or item.ID == ID then return false end
    local id = item.ID
    if not turnAway(player, id) then
        ConchBlessing.printError("[Cereal] could not turn away item " .. tostring(id) .. " to break it")
        return false
    end
    -- The hold-up becomes Cereal's own use (the engine's extra animation, as
    -- an active is held up when used), so nothing still shows the item.
    if type(player.AnimateCollectible) == "function" then pcall(player.AnimateCollectible, player, ID, "UseItem") end
    local rng = player:GetCollectibleRNG(ID)
    local digits
    if id == BREAKFAST then
        digits = { rng:RandomInt(10), rng:RandomInt(10), rng:RandomInt(10) }
    else
        digits = M.digitsOf(id)
    end
    local spots = rowSpots(player.Position, #digits)
    for i, d in ipairs(digits) do spawnCereal(d, spots[i], player) end
    sfx(SoundEffect.SOUND_BONE_SNAP, 0.8)
    ConchBlessing.printDebug("[Cereal] player %d broke item %d into %s", player.ControllerIndex, id,
        table.concat(digits, ""))
    return true, id, digits
end

-- ------------------------------------------------------------------ grinding
-- A pedestal in reach is ground without being taken (user decision
-- 2026-11-24, so actives can be ground too: touching an active pedestal swaps
-- Cereal out of its slot before the use key could break it). Like Quick Pick,
-- each pedestal is checked for whether it may be ground now, and only one that
-- may is marked and ground: an item for sale (a shop item or a deal) has to be
-- paid for first, a quest item stays (the story needs it), an item the Magic
-- Conch is upgrading waits, and the Death Certificate area, where every item
-- of the game stands, grinds nothing.
local HOME_STAGE_ID, DEATH_CERTIFICATE_SUBTYPES, DEATH_CERTIFICATE_DIMENSION = 35, { [33] = true, [34] = true }, 2
local PRICE_FREE = PickupPrice and PickupPrice.PRICE_FREE or -1000

local function inDeathCertificateArea()
    local level = Game():GetLevel()
    local ok, data = pcall(function() return level:GetCurrentRoomDesc().Data end)
    local stage = ok and data and tonumber(data.StageID)
    if stage then
        return stage == HOME_STAGE_ID and DEATH_CERTIFICATE_SUBTYPES[tonumber(data.Subtype)] == true
    end
    if type(level.GetDimension) == "function" then
        local dimOk, dimension = pcall(level.GetDimension, level)
        return dimOk and dimension == DEATH_CERTIFICATE_DIMENSION
    end
    return false
end

local function grindable(pickup)
    if not pickup or not pickup:Exists() or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then return false end
    local id = pickup.SubType
    if id <= 0 or id == ID then return false end
    local config = Isaac.GetItemConfig():GetCollectible(id)
    if not config or config:HasTags(ItemConfig.TAG_QUEST) then return false end
    local price = pickup.Price or 0
    if price ~= 0 and price ~= PRICE_FREE then return false end
    local upgrade = ConchBlessing.upgrade
    if type(upgrade) == "table" then
        if type(upgrade.isAnimatingPickup) == "function" and upgrade.isAnimatingPickup(pickup) then return false end
        if type(upgrade.isCycleFrozen) == "function" and upgrade.isCycleFrozen(pickup) then return false end
    end
    return true
end

--- The nearest pedestal `player` may grind now, within reach, or nil.
function M.grindTarget(player)
    if not player or inDeathCertificateArea() then return nil end
    local best, bestDistance = nil, M.data.grindRange
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)) do
        local pickup = entity:ToPickup()
        local distance = pickup and pickup.Position:Distance(player.Position)
        if distance and distance <= bestDistance and grindable(pickup) then best, bestDistance = pickup, distance end
    end
    return best
end

-- The engine's own way where there is one, else IsaacScript Common's: an
-- empty pedestal is subtype 0 with nothing drawn on it.
local function emptyPedestal(pickup)
    if type(pickup.TryRemoveCollectible) == "function" then
        local ok = pcall(pickup.TryRemoveCollectible, pickup)
        if ok and pickup.SubType == 0 then return true end
    end
    local ok = pcall(isc.setCollectibleEmpty, nil, pickup)
    return ok and pickup.SubType == 0
end

--- Grind the item on `pickup` into its number's cereal, beside the pedestal.
--- Its other choices go as when it is taken. Returns true, the item and the
--- digits, or false.
function M.grindPedestal(player, pickup)
    if not player or not grindable(pickup) then return false end
    local id = pickup.SubType
    local pos = pickup.Position
    local group = pickup.OptionsPickupIndex or 0
    local rng = player:GetCollectibleRNG(ID)
    local digits
    if id == BREAKFAST then
        digits = { rng:RandomInt(10), rng:RandomInt(10), rng:RandomInt(10) }
    else
        digits = M.digitsOf(id)
    end
    -- A rotating pedestal's other choices go with the one on show, as when
    -- it is taken.
    if type(pickup.RemoveCollectibleCycle) == "function" then pcall(pickup.RemoveCollectibleCycle, pickup) end
    if not emptyPedestal(pickup) then
        ConchBlessing.printError("[Cereal] could not empty the pedestal of item " .. tostring(id) .. " to grind it")
        return false
    end
    if group ~= 0 then
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
            local other = entity:ToPickup()
            if other and GetPtrHash(other) ~= GetPtrHash(pickup) and other.OptionsPickupIndex == group then
                Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, other.Position, Vector.Zero, nil)
                other:Remove()
            end
        end
    end
    local spots = rowSpots(pos, #digits)
    for i, d in ipairs(digits) do spawnCereal(d, spots[i], player) end
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, pos, Vector.Zero, nil)
    sfx(SoundEffect.SOUND_BONE_SNAP, 0.8)
    if type(player.AnimateCollectible) == "function" then pcall(player.AnimateCollectible, player, ID, "UseItem") end
    ConchBlessing.printDebug("[Cereal] player %d ground item %d into %s", player.ControllerIndex, id,
        table.concat(digits, ""))
    return true, id, digits
end

-- Which pedestal each player holding Cereal in reach of the use key would
-- grind now; worked out once an update and drawn every render frame.
local function updateTargets()
    local seen = {}
    eachPlayer(function(player)
        local key = GetPtrHash(player)
        if not living(player) or pickers[key] or queuedCollectible(player) or not cerealSlot(player) then return end
        local pickup = M.grindTarget(player)
        if pickup then
            targets[key] = EntityPtr(pickup)
            seen[key] = true
        end
    end)
    for key in pairs(targets) do
        if not seen[key] then targets[key] = nil end
    end
end

local function liveTarget(key)
    local ptr = targets[key]
    local pickup = ptr and ptr.Ref and ptr.Ref:ToPickup()
    if pickup and grindable(pickup) then return pickup end
    return nil
end

-- A gold arrow bobbing over the item that would be ground.
local function drawTargets()
    local drawn = {}
    for key in pairs(targets) do
        local pickup = liveTarget(key)
        local hash = pickup and GetPtrHash(pickup)
        if pickup and not drawn[hash] then
            drawn[hash] = true
            local at = Isaac.WorldToScreen(pickup.Position + pickup.PositionOffset)
            local bob = math.floor(math.sin(Isaac.GetFrameCount() / 9) * 2 + 0.5)
            part("ArrowDown", 0, at.X - 4, at.Y - M.data.markerLift + bob, Color(1, 0.85, 0.35, 1))
        end
    end
end

-- ------------------------------------------------------------------ the bowl
local function lift(player, up)
    local s = loadSprite("gfx/ui/conch_cereal_ui.anm2", "Empty")
    if not s or type(player.AnimatePickup) ~= "function" then return false end
    return pcall(player.AnimatePickup, player, s, true, up and "LiftItem" or "HideItem") == true
end

local function close(key, player, picker)
    pickers[key] = nil
    if picker then lastSel[key] = picker.sel end
    if player and picker and picker.lifted then lift(player, false) end
    forget(key)
end

-- A spot a little away from the player for an active's pedestal.
local OFFSETS = { Vector(0, 1), Vector(1, 0), Vector(-1, 0), Vector(0, -1) }
local function dropSpot(player)
    local room = Game():GetRoom()
    local d = M.data.dropDistance
    for _, dir in ipairs(OFFSETS) do
        local pos = player.Position + dir * d
        if room:IsPositionInRoom(pos, 0) and room:GetGridCollisionAtPos(pos) == GridCollisionClass.COLLISION_NONE then
            local spot = room:FindFreePickupSpawnPosition(pos, 0, true)
            if spot:Distance(player.Position) >= d / 2 then return spot end
        end
    end
    return room:FindFreePickupSpawnPosition(player.Position, 40, true)
end

local function showName(player, config)
    local hud = Game():GetHUD()
    if hud and type(hud.ShowItemText) == "function" then pcall(hud.ShowItemText, hud, player, config) end
end

-- Confirm what is in the bowl: the item is made, or the bowl is cancelled
-- with nothing spent. An empty bowl just closes (user request 2026-11-24: the
-- bowl doubles as the way to look at the cereal held), and without milk
-- nothing is made and the bowl stays open.
local function confirm(key, player, picker)
    if #picker.entered == 0 then
        close(key, player, picker)
        sfx(SoundEffect.SOUND_MENU_FLIP_DARK or SoundEffect.SOUND_MENU_FLIP_LIGHT, 0.7)
        return false, "CLOSED"
    end
    local state, n, config = M.lookup(picker.entered)
    if state == "short" then
        picker.shake = 8
        sfx(SoundEffect.SOUND_BOSS2INTRO_ERRORBUZZ, 0.5)
        return false
    end
    if state == "ok" and M.milk() < 1 then
        picker.shake = 8
        toast(key, View.text("ui.cereal.no_milk"))
        sfx(SoundEffect.SOUND_BOSS2INTRO_ERRORBUZZ, 0.6)
        return false, "NO_MILK"
    end
    close(key, player, picker)
    if state ~= "ok" then
        local text = state == "nocraft" and View.text("ui.cereal.cancel_nocraft", tostring(n))
            or View.text("ui.cereal.cancel_none", table.concat(picker.entered, ""))
        toast(key, text)
        sfx(SoundEffect.SOUND_BOSS2INTRO_ERRORBUZZ, 0.6)
        return false, state
    end
    local s = store(true)
    if not s or s.milk < 1 then return false, "NO_MILK" end
    local need = {}
    for _, d in ipairs(picker.entered) do need[d] = (need[d] or 0) + 1 end
    for d, k in pairs(need) do
        if s.digits[d + 1] < k then return false, "NO_CEREAL" end
    end
    for d, k in pairs(need) do s.digits[d + 1] = s.digits[d + 1] - k end
    s.milk = s.milk - 1
    sfx(SoundEffect.SOUND_VAMP_GULP, 0.8)
    queueCount(player, picker.slot)
    if config.Type == ItemType.ITEM_ACTIVE then
        local seed = player:GetCollectibleRNG(ID):Next()
        if seed == 0 then seed = 1 end
        Game():Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, dropSpot(player), Vector.Zero,
            player, n, seed)
    else
        if type(player.AnimateCollectible) == "function" then
            pcall(player.AnimateCollectible, player, n, "Pickup", "PlayerPickupSparkle")
        end
        player:QueueItem(config, config.InitCharge or 0, false, false, 0)
        showName(player, config)
    end
    ConchBlessing.printDebug("[Cereal] player %d made item %d", player.ControllerIndex, n)
    return true, n
end

local function available(picker, d)
    local s = store(false)
    local have = s and s.digits[d + 1] or 0
    for _, v in ipairs(picker.entered) do if v == d then have = have - 1 end end
    return have
end

-- Whether the bowl may stay open: the player is there and alive, Cereal is
-- still in its slot and no item is being picked up.
local function stillOpen(player, picker)
    if not living(player) then return false end
    local slot = picker.slot
    if type(slot) == "number" and slot >= 0 and player:GetActiveItem(slot) ~= ID then return false end
    return queuedCollectible(player) == nil
end

-- ------------------------------------------------------------------ steps
-- Rising edges from update and render alike, so a tap between updates counts
-- and a held key never repeats.
local function step(key, player)
    local held = locks[key]
    if held then
        for action in pairs(held) do if not pressed(player, action) then held[action] = nil end end
        if next(held) == nil then locks[key] = nil end
    end
    local watch, picker = watches[key], pickers[key]
    if not watch and not picker then forget(key); return end
    if Game():IsPaused() then return end
    if watch then
        local now = pressed(player, watch.action)
        local was = watch.last
        watch.last = now
        if not queuedCollectible(player) or player:GetActiveItem(watch.slot) ~= ID then
            watches[key] = nil
            if now then lock(key, player, watch.action) end
            forget(key)
            return
        end
        if now and not was then
            watches[key] = nil
            lock(key, player, watch.action)
            if M.breakHeld(player) then queueCount(player, watch.slot) end
        end
        return
    end
    local now = readInputs(player, picker)
    local last = picker.last or now
    picker.last = now
    if not stillOpen(player, picker) then close(key, player, picker); return end
    if now.cancel and not last.cancel then
        for _, action in ipairs(now.closing) do lock(key, player, action) end
        close(key, player, picker)
        sfx(SoundEffect.SOUND_MENU_FLIP_DARK or SoundEffect.SOUND_MENU_FLIP_LIGHT, 0.7)
        return
    end
    if now.confirm and not last.confirm then
        lock(key, player, picker.confirm)
        confirm(key, player, picker)
        return
    end
    if now.left and not last.left then picker.sel = (picker.sel + 9) % 10; sfx(SoundEffect.SOUND_MENU_FLIP_LIGHT, 0.5) end
    if now.right and not last.right then picker.sel = (picker.sel + 1) % 10; sfx(SoundEffect.SOUND_MENU_FLIP_LIGHT, 0.5) end
    -- Down drops the framed cereal into the milk, up takes the last one put in
    -- back out (user request 2026-11-24); each shows as a motion (`picker.fx`).
    if now.down and not last.down then
        if available(picker, picker.sel) > 0 and canAdd(picker.entered, picker.limit, picker.sel) then
            picker.entered[#picker.entered + 1] = picker.sel
            picker.fx[#picker.fx + 1] = { kind = "in", d = picker.sel, slot = #picker.entered, start = Isaac.GetFrameCount() }
            sfx(SoundEffect.SOUND_MENU_FLIP_LIGHT, 0.4)
        else
            picker.shake = 6
            sfx(SoundEffect.SOUND_BOSS2INTRO_ERRORBUZZ, 0.35)
        end
    end
    if now.up and not last.up and #picker.entered > 0 then
        local slot = #picker.entered
        local d = picker.entered[slot]
        picker.entered[slot] = nil
        for i = #picker.fx, 1, -1 do
            if picker.fx[i].kind == "in" and picker.fx[i].slot == slot then table.remove(picker.fx, i) end
        end
        picker.fx[#picker.fx + 1] = { kind = "out", d = d, slot = slot, start = Isaac.GetFrameCount(),
            off = picker.xs[slot] }
        sfx(SoundEffect.SOUND_MENU_FLIP_LIGHT, 0.4)
    end
end

-- An item held up by a player whose use key reaches Cereal is watched: that
-- key is the bowl's until the queue empties, and a press breaks the item.
local function watchQueues()
    eachPlayer(function(player)
        if not living(player) then return end
        local key = GetPtrHash(player)
        if watches[key] or pickers[key] then return end
        local slot, action = cerealSlot(player)
        if not slot or not queuedCollectible(player) then return end
        watches[key] = { slot = slot, action = action, last = pressed(player, action) }
        own(key, player)
    end)
end

-- While a bowl is open its keys are its own (the shooting keys, the key that
-- confirms and the drop key); while an item is watched, the use key is. A
-- confirming or closing key stays the bowl's until let go. The same keys drive
-- every player on that controller, so the game is denied them for all of them.
local function holds(key, action)
    local picker = pickers[key]
    if picker and (SHOOTING[action] or action == picker.confirm or CLOSING[action]) then return true end
    local watch = watches[key]
    if watch and action == watch.action then return true end
    local held = locks[key]
    return held ~= nil and held[action] == true
end

-- Pause (Esc / Start) is asked for with no player: kept from the game while
-- any bowl is open, and after closing one until the key is let go.
local function anyHolds(action)
    for key in pairs(owners) do
        if holds(key, action) then return true end
    end
    return false
end

local function withheld(key, controller, action)
    if holds(key, action) then return true end
    for other, owner in pairs(owners) do
        if other ~= key and owner.controller == controller and holds(other, action) then return true end
    end
    return false
end

function M.onInputAction(_, entity, hook, action)
    if reading or next(owners) == nil then return end
    local player = entity and entity:ToPlayer()
    local kept
    if player then
        kept = withheld(GetPtrHash(player), player.ControllerIndex, action)
    else
        kept = PAUSING[action] == true and anyHolds(action)
    end
    if not kept then return end
    if hook == InputHook.GET_ACTION_VALUE then return 0.0 end
    if hook == InputHook.IS_ACTION_PRESSED or hook == InputHook.IS_ACTION_TRIGGERED then return false end
end

--- Open the bowl over `player`'s head for a use from `slot`; it opens with or
--- without milk, so the cereal held can always be looked at. Returns true, or
--- false and a reason.
function M.open(player, slot)
    if not player then return false, "NO_PLAYER" end
    local key = GetPtrHash(player)
    if pickers[key] then return true end
    local picker = { slot = slot, confirm = confirmAction(slot), entered = {}, sel = lastSel[key] or 0,
        limit = maxDigits(), shake = 0, fx = {}, xs = {} }
    pickers[key] = picker
    own(key, player)
    picker.last = readInputs(player, picker) -- the key that used it is still down
    picker.lifted = lift(player, true)
    sfx(SoundEffect.SOUND_PLOP, 0.8)
    return true
end

function M.picking(player)
    return player ~= nil and pickers[GetPtrHash(player)] ~= nil
end

-- Uses. Opening and closing the bowl are no item use (user request
-- 2026-11-24: a cancelled use must not count on active-use counters), so the
-- engine's use is cancelled in MC_PRE_USE_ITEM: nothing counts it and nothing
-- that answers a use (Book of Virtues, Car Battery) fires. Making an item or
-- breaking one is a use: one real use is issued on the next update
-- (`queueCount`, never from inside a use callback), which every counter sees
-- and which does nothing more here.
local function issueCounts()
    local list = pendingCounts
    pendingCounts = {}
    for _, entry in ipairs(list) do
        local player = entry.ptr and entry.ptr.Ref and entry.ptr.Ref:ToPlayer()
        if player and type(player.UseActiveItem) == "function" then
            counting = true
            local ok, err = pcall(player.UseActiveItem, player, ID, UseFlag.USE_NOANIM,
                type(entry.slot) == "number" and entry.slot or -1)
            counting = false
            if not ok then ConchBlessing.printError("[Cereal] could not count a use: " .. tostring(err)) end
        end
    end
end

-- What a press of the use key does: break the item held up, else open the
-- bowl. Returns true when an item was broken.
local function act(player, slot)
    local key = GetPtrHash(player)
    if queuedCollectible(player) then
        lock(key, player, confirmAction(slot))
        return M.breakHeld(player) == true
    end
    if not pickers[key] then
        local pickup = M.grindTarget(player)
        if pickup then
            targets[key] = nil
            return M.grindPedestal(player, pickup) == true
        end
    end
    if not pickers[key] and not M.open(player, slot) then sfx(SoundEffect.SOUND_BOSS2INTRO_ERRORBUZZ, 0.6) end
    return false
end

-- MC_PRE_USE_ITEM(id, rng, player, flags, slot): true cancels the engine's use.
function M.onPreUseItem(_, id, _, player, flags, slot)
    if id ~= ID or not player or counting then return nil end
    if flags and flags & UseFlag.USE_CARBATTERY ~= 0 then return true end
    if act(player, slot) then queueCount(player, slot) end
    return true
end

-- An ItemData `use` handler receives the mod first: (_, id, rng, player, flags, slot, varData).
-- It runs for the counted uses, and (should MC_PRE_USE_ITEM not have run) as
-- the fallback that still opens the bowl or breaks the item.
function M.onUseItem(_, id, _, player, flags, slot)
    if id ~= ID or not player then return end
    if counting then
        -- Return nothing: a returned table ends the MC_USE_ITEM chain, and the
        -- callbacks after this one (a use counter) would never see the use
        -- (measured 2026-11-24). USE_NOANIM keeps it from showing.
        countedUses = countedUses + 1
        return nil
    end
    local result = { Discharge = false, Remove = false, ShowAnim = false }
    if flags and flags & UseFlag.USE_CARBATTERY ~= 0 then return result end
    act(player, slot)
    return result
end

-- ------------------------------------------------------------------ drawing
local NAME_RGB = { 1, 0.93, 0.7 }
local BAD_RGB = { 1, 0.55, 0.48 }
local HINT_RGB = { 0.92, 0.9, 0.84 }
local NOTE_RGB = { 0.94, 0.75, 0.38 }
local WHITE, BLACK = Color(1, 1, 1, 1), Color(0, 0, 0, 1)
local DIM = Color(1, 1, 1, 0.3)
local COUNT = KColor and KColor(1, 1, 1, 1)
local COUNT_DIM = KColor and KColor(0.5, 0.5, 0.5, 1)

local function keyLabel(action)
    if action == ButtonAction.ACTION_PILLCARD then return View.text("ui.cereal.key_card") end
    return View.text("ui.cereal.key_item")
end

local function centered(text, x, y, scale, rgb)
    View.drawAt(text, x - View.width(text, scale) / 2, y, scale, rgb)
end

-- The keys under the feet, the shooting keys as arrow pictures (letters such as
-- "<>", "^" and "v" did not read as arrows, user screenshot 2026-11-24).
local ARROWS = { ArrowLR = 13, ArrowUp = 9, ArrowDown = 9 }
local function hintParts(picker)
    return {
        { icon = "ArrowLR" }, { text = View.text("ui.cereal.hint_choose") }, { gap = 7 },
        { icon = "ArrowDown" }, { text = View.text("ui.cereal.hint_add") }, { gap = 7 },
        { icon = "ArrowUp" }, { text = View.text("ui.cereal.hint_remove") }, { gap = 7 },
        { text = View.text("ui.cereal.hint_confirm", keyLabel(picker.confirm)) }, { gap = 7 },
        { text = View.text("ui.cereal.hint_close", View.text("ui.cereal.key_drop")) },
    }
end

local function drawHint(cx, y, picker)
    local scale = M.data.hintScale
    local parts = hintParts(picker)
    local total = 0
    for _, p in ipairs(parts) do
        p.width = p.icon and ARROWS[p.icon] + 2 or p.gap or View.width(p.text, scale)
        total = total + p.width
    end
    local x = math.floor(cx - total / 2)
    local arrowY = y + math.floor((View.lineHeight(scale) - 9) / 2)
    for _, p in ipairs(parts) do
        if p.icon then part(p.icon, 0, x, arrowY) elseif p.text then View.drawAt(p.text, x, y, scale, HINT_RGB) end
        x = x + p.width
    end
end

local function countHeight()
    local f = hudFont()
    local ok, h = pcall(function() return f and f:GetLineHeight() end)
    return ok and type(h) == "number" and h > 0 and h or 9
end

local function countWidth(text)
    local f = hudFont()
    local ok, w = pcall(function() return f and f:GetStringWidth(text) end)
    return ok and type(w) == "number" and w or #text * 5
end

--- Where each row of the bowl's picker goes (screen y), every row clear of the
--- next: above the bowl from the bottom up, the counts, the cereal row (12
--- tall, the framed one 4 higher), the item (a 24px icon), its name and, for an
--- active, the note. When that does not fit under the top of the screen it
--- all goes under the feet instead, in the same order downwards.
function M.layout(footY, bowlTop, active, nameH, noteH, countH)
    local L = { bowlTop = bowlTop }
    L.countsY = bowlTop - 4 - countH          -- clear of the bowl's rim and the cereal in it
    L.digitsTop = L.countsY - 13
    L.iconY = L.digitsTop - 18                -- icon centre: its bottom 2 above the framed digit
    L.nameY = L.iconY - 14 - nameH
    L.noteY = L.nameY - noteH
    L.above = (active and L.noteY or L.nameY) >= 2
    if L.above then
        L.hintY = footY + 10
        return L
    end
    L.digitsTop = footY + 16
    L.countsY = L.digitsTop + 13
    L.iconY = L.countsY + countH + 14
    L.nameY = L.iconY + 14
    L.noteY = L.nameY + nameH
    L.hintY = (active and L.noteY + noteH or L.nameY + nameH) + 2
    return L
end

local function draw(player, picker)
    local foot = Isaac.WorldToScreen(player.Position)
    local shake = picker.shake > 0 and math.floor(math.sin(picker.shake * 2.2) * 2 + 0.5) or 0
    local cx = math.floor(foot.X) + shake
    local bowlTop = math.floor(foot.Y - M.data.bowlLift - M.data.bowlHeight)
    local nameScale, noteScale = M.data.nameScale, M.data.noteScale
    local state, n, config = M.lookup(picker.entered)
    local active = state == "ok" and config ~= nil and config.Type == ItemType.ITEM_ACTIVE
    local L = M.layout(math.floor(foot.Y), bowlTop, active, View.lineHeight(nameScale), View.lineHeight(noteScale),
        countHeight())
    local digitsTop, countsY, iconY = L.digitsTop, L.countsY, L.iconY
    -- digit row: the cereal are 10x12
    for d = 0, 9 do
        local x = cx - 60 + d * 12 + 1
        local have = available(picker, d)
        local y = digitsTop - (d == picker.sel and 2 or 0)
        if d == picker.sel then
            rect(x - 2, y - 2, 14, 16, BLACK)
            rect(x - 1, y - 1, 12, 14, WHITE)
            rect(x, y, 10, 12, BLACK)
        end
        part("Digit", d, x, y, have > 0 and WHITE or DIM)
        local text = tostring(have)
        digitsText(text, x + 5 - #text * 2.5, countsY, have > 0 and COUNT or COUNT_DIM)
    end
    -- the bowl, the cereal in it, then its near rim over the cereal
    local left = cx - 28
    local milky = M.milk() > 0
    part("BowlBack", 0, left, bowlTop)
    if milky then part("Milk", 0, left, bowlTop) end
    local bob = math.floor(Game():GetFrameCount() / 12)
    local frame, fx = Isaac.GetFrameCount(), M.data.fx
    -- The cereal in the bowl stay centred (user request 2026-11-24): each eases
    -- toward its place for the current count, so the others slide aside when one
    -- goes in or comes out. Offsets are kept from the bowl's centre.
    local count, xs = #picker.entered, picker.xs
    for i = 1, count do
        local target = M.centred(count, i)
        local cur = xs[i] or target
        cur = cur + (target - cur) * fx.slide
        if math.abs(target - cur) < 0.25 then cur = target end
        xs[i] = cur
    end
    for i = #xs, count + 1, -1 do xs[i] = nil end
    local function slotX(i) return math.floor(cx + (xs[i] or M.centred(count, i)) + 0.5) end
    local function rowX(d) return cx - 60 + d * 12 + 1 end
    for i = #picker.fx, 1, -1 do
        local f = picker.fx[i]
        local age = frame - f.start
        if (f.kind == "in" and age > fx.fall + fx.splash) or (f.kind == "out" and age > fx.out) then
            table.remove(picker.fx, i)
        end
    end
    local falling = {}
    for _, f in ipairs(picker.fx) do
        if f.kind == "in" and frame - f.start < fx.fall then falling[f.slot] = f end
    end
    local restY = bowlTop + (milky and M.data.floatY or M.data.bottomY)
    for i = 1, count do
        local x = slotX(i)
        local d = picker.entered[i]
        local f = falling[i]
        if f and f.d == d then
            -- dropping from its place in the row into the milk, faster as it falls
            local k = (frame - f.start) / fx.fall
            local e = k * k
            local fromX = rowX(d)
            part("Digit", d, math.floor(fromX + (x - fromX) * e), math.floor(digitsTop + (restY - digitsTop) * e))
        else
            part("Digit", d, x, restY + ((bob + i) % 2))
        end
    end
    part("BowlFront", 0, left, bowlTop)
    -- a splash where a cereal landed, and the one taken out jumping back up
    for _, f in ipairs(picker.fx) do
        local age = frame - f.start
        if f.kind == "in" and age >= fx.fall then
            if not f.splashed then
                f.splashed = true
                sfx(SoundEffect.SOUND_PLOP, milky and 0.6 or 0.3)
            end
            if milky then
                local k = (age - fx.fall) / fx.splash
                local sx, sy = slotX(f.slot) + 5, bowlTop + M.data.milkY
                local drop = Color(0.98, 0.98, 0.96, 1 - k)
                for j, dx in ipairs({ -5, -2, 2, 5 }) do
                    local h = j % 2 == 0 and 7 or 5
                    rect(math.floor(sx + dx * (0.6 + k * 0.7)), math.floor(sy - math.sin(math.pi * k) * h), 1, 1, drop)
                end
            end
        elseif f.kind == "out" then
            local k = age / fx.out
            local x = math.floor(cx + (f.off or M.centred(count + 1, f.slot)) + 0.5)
            part("Digit", f.d, x, math.floor(restY - 18 * (1 - (1 - k) * (1 - k))), Color(1, 1, 1, 1 - k))
        end
    end
    -- what the number makes
    local typed = table.concat(picker.entered, "")
    local nameY = L.nameY
    if state == "ok" or state == "nocraft" then
        local s = icon(n)
        if s then
            s.Scale = Vector(0.75, 0.75)
            s.Color = state == "ok" and WHITE or DIM
            s:Render(Vector(cx, iconY))
        end
        local name = itemName(n) or ""
        if state == "ok" then
            centered(View.text("ui.cereal.result", typed, name), cx, nameY, nameScale, NAME_RGB)
            if active then centered(View.text("ui.cereal.active"), cx, L.noteY, noteScale, NOTE_RGB) end
        else
            centered(View.text("ui.cereal.nocraft", typed, name), cx, nameY, nameScale, BAD_RGB)
        end
    elseif state == "none" then
        part("Unknown", 0, cx - 10, iconY - 10)
        centered(View.text("ui.cereal.none", typed), cx, nameY, nameScale, BAD_RGB)
    end
    -- Until a digit is in nothing is written above the bowl (user
    -- request 2026-11-24: no "put in 3 digits" prompt).
    drawHint(cx, L.hintY, picker)
end

local function drawToast(player, entry)
    local foot = Isaac.WorldToScreen(player.Position)
    local a = math.min(1, entry.frames / 10)
    centered(entry.text, foot.X, foot.Y - 52, 0.55, { 1, 0.9 * a + 0.1, 0.8 * a + 0.2 })
end

-- ------------------------------------------------------------------ pickups
local function digitOf(pickup)
    local d = pickup.SubType
    if type(d) ~= "number" or d < 0 or d > 9 then return nil end
    return d
end

-- A cereal appears with a hop when it is dropped, and lies still when the
-- room it was left in is entered again.
function M.onPickupInit(_, pickup)
    if not digitOf(pickup) then return end
    local sprite = pickup:GetSprite()
    if Game():GetRoom():GetFrameCount() > 1 then sprite:Play("Appear", true) else sprite:Play("Idle", true) end
end

function M.onPickupUpdate(_, pickup)
    local sprite = pickup:GetSprite()
    if sprite:IsFinished("Appear") then sprite:Play("Idle", true) end
end

-- Taken on touch by any living player, like a coin: the cereal joins the
-- shared bowl stock, the pickup leaves at once (so leaving the room cannot
-- keep it) and its Collect animation plays as a picture where it lay.
function M.onPickupCollision(_, pickup, collider)
    local d = digitOf(pickup)
    local player = collider and collider:ToPlayer()
    if not d or not living(player) then return nil end
    local data = pickup:GetData()
    if data[TAKEN] then return true end
    if pickup.FrameCount < M.data.takeAfter then return nil end
    if not M.addDigit(d, 1) then return nil end
    data[TAKEN] = true
    local s = loadSprite("gfx/005.7792_conch_cereal_" .. d .. ".anm2", "Collect")
    if s then
        s:Play("Collect", true)
        bits[#bits + 1] = { sprite = s, pos = pickup.Position + pickup.PositionOffset }
    end
    pickup.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    pickup:Remove()
    sfx(SoundEffect.SOUND_PLOP, 0.7)
    return true
end

-- ------------------------------------------------------------------ milk
-- MC_PRE_GET_COLLECTIBLE(poolType, decrease, seed): Breakfast, or nil to leave
-- the draw alone. Nothing is taken out of the pool.
local function nested()
    local underdog, pearl = ConchBlessing.underdog, ConchBlessing.conchpearl
    if type(underdog) == "table" and type(underdog.isPeeking) == "function" and underdog.isPeeking() then return true end
    if type(pearl) == "table" and type(pearl.isRedrawing) == "function" and pearl.isRedrawing() then return true end
    return false
end

--- The chance that a draw becomes Breakfast with `milk` held.
function M.milkChance(milk)
    return M.data.milkBase * M.data.milkChance ^ math.max(0, math.floor(milk or 0))
end

-- EID: below Cereal's description, above the REPENTOGON line, the chance a
-- draw becomes Breakfast now (user request 2026-11-24). Milk is shared by the
-- whole run, so the line holds for every player reading it.
function M.chanceText(milk)
    local shown = string.format("%.2f", M.milkChance(milk) * 100):gsub("0+$", ""):gsub("%.$", "")
    local Locale = ConchBlessing.Locale
    local percent = type(Locale) == "table" and type(Locale.formatPercent) == "function"
        and Locale.formatPercent(shown) or (shown .. "%")
    return View.text("ui.cereal.chance", percent)
end

function M.describe(descObj)
    local ok, line = pcall(M.chanceText, M.milk())
    if not ok or type(line) ~= "string" then return descObj end
    local desc = descObj.Description or ""
    local at = desc:find("#{{Warning}}", 1, true)
    if at then
        descObj.Description = desc:sub(1, at - 1) .. line .. desc:sub(at)
    else
        descObj.Description = desc .. line
    end
    return descObj
end

if type(EID) == "table" and type(EID.addDescriptionModifier) == "function" and ID and ID > 0 then
    EID:addDescriptionModifier("ConchBlessing_CerealBreakfastChance", function(descObj)
        return descObj.ObjType == EntityType.ENTITY_PICKUP and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE
            and descObj.ObjSubType == ID
    end, M.describe)
end

-- Draw seeds often follow each other closely, and the first number an RNG
-- gives after such seeds leans one way (measured 2026-11-24: with seeds a fixed
-- step apart, one milk turned every draw into Breakfast). The seed is hashed
-- first, as Underdog's is.
local function mixSeed(seed)
    local h = math.floor(tonumber(seed) or 0) & 0xffffffff
    h = ((h ~ (h >> 16)) * 0x85ebca6b) & 0xffffffff
    h = ((h ~ (h >> 13)) * 0xc2b2ae35) & 0xffffffff
    h = h ~ (h >> 16)
    if h == 0 then h = 1 end
    return h
end

function M.onPreGetCollectible(_, poolType, decrease, seed)
    if nested() or not M.anyHolder() then return nil end
    local rng = RNG()
    rng:SetSeed(mixSeed(seed), POOL_RNG_SHIFT)
    if rng:RandomFloat() < M.milkChance(M.milk()) then
        ConchBlessing.printDebug("[Cereal] pool %s draw became Breakfast (milk %d)", tostring(poolType), M.milk())
        return BREAKFAST
    end
    return nil
end

-- A Breakfast taken (not broken) while anyone holds Cereal is one milk.
function M.onAddBreakfast(_, kind, _, firstTime)
    if kind ~= BREAKFAST or firstTime == false then return end
    if M.anyHolder() then M.addMilk(1) end
end

-- ------------------------------------------------------------------ HUD
-- The milk held, as "x5" on the icon's upper right, the way the HUD writes a
-- count beside a heart (user request 2026-11-24). The cereal held is no HUD
-- count: the bowl shows each digit's, and opens and closes for free.
-- `right` is where the text ends, from the slot's HUD position.
M.hud = { right = 31, top = 0 }
function M.onHudActive(_, player, slot, offset, alpha, scale)
    if slot ~= ActiveSlot.SLOT_PRIMARY and slot ~= ActiveSlot.SLOT_POCKET then return end
    if not offset then return end
    local s, a = scale or 1, alpha or 1
    local text = "x" .. tostring(M.milk())
    digitsText(text, offset.X + M.hud.right * s - countWidth(text) * s, offset.Y + M.hud.top * s,
        KColor(1, 1, 1, a), s)
end

-- ------------------------------------------------------------------ callbacks
local function each(fn)
    for key, owner in pairs(owners) do
        local player = owner.ptr and owner.ptr.Ref and owner.ptr.Ref:ToPlayer()
        if player then fn(key, player)
        else pickers[key], locks[key], watches[key] = nil, nil, nil; owners[key] = nil end
    end
end

function M.onUpdate()
    if #pendingCounts > 0 then issueCounts() end
    watchQueues()
    updateTargets()
    if next(owners) ~= nil then each(step) end
    for key, entry in pairs(toasts) do
        entry.frames = entry.frames - 1
        if entry.frames <= 0 then toasts[key] = nil end
    end
    for _, picker in pairs(pickers) do
        if picker.shake > 0 then picker.shake = picker.shake - 1 end
    end
    for i = #bits, 1, -1 do
        local bit = bits[i]
        bit.sprite:Update()
        if bit.sprite:IsFinished("Collect") then table.remove(bits, i) end
    end
end

function M.onRender()
    for _, bit in ipairs(bits) do bit.sprite:Render(Isaac.WorldToScreen(bit.pos)) end
    if next(targets) ~= nil then drawTargets() end
    if next(owners) ~= nil then
        each(function(key, player)
            step(key, player)
            local picker = pickers[key]
            if picker then draw(player, picker) end
        end)
    end
    if next(toasts) ~= nil then
        eachPlayer(function(player)
            local entry = toasts[GetPtrHash(player)]
            if entry then drawToast(player, entry) end
        end)
    end
end

-- A new room closes every bowl (nothing was spent) and drops the pictures.
function M.onNewRoom()
    each(function(key, player)
        local picker = pickers[key]
        if picker then close(key, player, picker) end
        watches[key] = nil
        forget(key)
    end)
    bits, targets = {}, {}
end

function M.reset()
    pickers, watches, locks, owners, toasts, bits, testKeys, targets = {}, {}, {}, {}, {}, {}, {}, {}
    pendingCounts, counting = {}, false
    pooledCache = nil
end

M._test = {
    digitsOf = M.digitsOf,
    canAdd = canAdd,
    maxDigits = maxDigits,
    number = number,
    confirmAction = confirmAction,
    setMaxId = function(n) maxIdCache = n end,
    resetCaches = function() maxIdCache, pooledCache = nil, nil end,
    picker = function(player) return player and pickers[GetPtrHash(player)] end,
    watch = function(player) return player and watches[GetPtrHash(player)] end,
    toast = function(player) local t = player and toasts[GetPtrHash(player)]; return t and t.text end,
    countedUses = function() return countedUses end,
    countNow = function(player, slot) queueCount(player, slot); issueCounts() end,
    pendingCounts = function() return #pendingCounts end,
    type = function(player, digits)
        local picker = player and pickers[GetPtrHash(player)]
        if not picker then return false end
        for _, d in ipairs(digits) do
            if available(picker, d) <= 0 or not canAdd(picker.entered, picker.limit, d) then return false end
            picker.entered[#picker.entered + 1] = d
        end
        return true
    end,
    confirm = function(player)
        local key = player and GetPtrHash(player)
        local picker = key and pickers[key]
        if not picker then return false, "NOT_OPEN" end
        return confirm(key, player, picker)
    end,
    close = function(player)
        local key = player and GetPtrHash(player)
        if key and pickers[key] then close(key, player, pickers[key]) end
    end,
    hold = function(action, down) testKeys[action] = down and true or nil end,
    clearKeys = function() testKeys = {} end,
    withheld = function(player, action) return withheld(GetPtrHash(player), player.ControllerIndex, action) end,
    variant = function() return VARIANT end,
    target = function(player) local ptr = player and targets[GetPtrHash(player)]; return ptr and ptr.Ref end,
    bits = function() return #bits end,
    reset = M.reset,
}

-- Callbacks that take their own filter: the pickup by its variant, the
-- pre-use hook EARLY by item, the draw hook EARLY (it answers before
-- Underdog's LATE weighting and default-priority redirects), Breakfast's
-- addition and the active slot's HUD by item.
do
    local priority = rawget(_G, "CallbackPriority")
    local EARLY = type(priority) == "table" and tonumber(priority.EARLY) or -100
    local mod = ConchBlessing
    if VARIANT then
        mod:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, M.onPickupInit, VARIANT)
        mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, M.onPickupUpdate, VARIANT)
        mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, M.onPickupCollision, VARIANT)
    end
    -- EARLY, so a use-counting callback after it never sees an open or a close.
    if ModCallbacks.MC_PRE_USE_ITEM and ID and ID > 0 then
        if type(mod.AddPriorityCallback) == "function" then
            mod:AddPriorityCallback(ModCallbacks.MC_PRE_USE_ITEM, EARLY, M.onPreUseItem, ID)
        else
            mod:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, M.onPreUseItem, ID)
        end
    end
    if ModCallbacks.MC_PRE_GET_COLLECTIBLE then
        if type(mod.AddPriorityCallback) == "function" then
            mod:AddPriorityCallback(ModCallbacks.MC_PRE_GET_COLLECTIBLE, EARLY, M.onPreGetCollectible)
        else
            mod:AddCallback(ModCallbacks.MC_PRE_GET_COLLECTIBLE, M.onPreGetCollectible)
        end
    end
    if ModCallbacks.MC_POST_ADD_COLLECTIBLE then
        mod:AddCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE, M.onAddBreakfast, BREAKFAST)
    end
    -- IMPORTANT, so a broken item is refused before any other mod sees it
    -- being added (a transform or a copy of it would otherwise slip through).
    if ModCallbacks.MC_PRE_ADD_COLLECTIBLE then
        local IMPORTANT = type(priority) == "table" and tonumber(priority.IMPORTANT) or -200
        if type(mod.AddPriorityCallback) == "function" then
            mod:AddPriorityCallback(ModCallbacks.MC_PRE_ADD_COLLECTIBLE, IMPORTANT, M.onPreAddCollectible)
        else
            mod:AddCallback(ModCallbacks.MC_PRE_ADD_COLLECTIBLE, M.onPreAddCollectible)
        end
    end
    if ModCallbacks.MC_POST_PLAYERHUD_RENDER_ACTIVE_ITEM and ID and ID > 0 then
        mod:AddCallback(ModCallbacks.MC_POST_PLAYERHUD_RENDER_ACTIVE_ITEM, M.onHudActive, ID)
    end
end

return M
