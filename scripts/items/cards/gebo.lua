local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Gebo (ᚷ, "gift", exchange): Cereal's rune (user design 2026-11-25), the way
-- Thurisaz is Kronos's and Uruz is Tyrfing's. Its X is two strokes trading
-- places, the user's pick for a rune that swaps an item number's digits.
--
-- Used near a pedestal it may change, the item on it turns into another item
-- whose number is a rearrangement of its own digits, chosen at random among
-- the items that exist and are no hidden, quest or locked item. An item in no
-- pool counts (user request 2026-11-25: Brimstone 118 may become White Pony
-- 181, which some effects give), unlike Cereal's bowl, which only makes items
-- some pool lists. A number is read as a three-digit tag, like the 025 on
-- Cereal's box (user decision 2026-11-25; Cereal itself keeps numbers as they
-- are written): Breakfast 25 is 025 and may become 52, 205, 250, 502 or 520,
-- item 4 may become 40 or 400, and 105 may become 15 or 51 as well as 150, 501
-- and 510. Never its own number. Like
-- Cereal's grinding, only the nearest pedestal within reach that may change is
-- marked (an arrow) and changed: the user chose one pedestal over the room
-- (2026-11-25). A shop item or a deal changes too and keeps its price (user
-- decision); a rotating pedestal changes only the item on show, keeping its
-- circle; a quest item, an item the Magic Conch is upgrading and one with no
-- other arrangement stay. With nothing in reach the rune is spent like any
-- vanilla rune with no target (user decision). While anyone holds it, a
-- pedestal's EID lists every item it may become.
local Sound = require("scripts.lib.sound_volume")

ConchBlessing.gebo = ConchBlessing.gebo or {}
local M = ConchBlessing.gebo

M.data = {
    range = 80,       -- reach to the pedestal, as Cereal's grinding (Quick Pick's reach)
    markerLift = 52,  -- screen pixels from a pedestal up to its arrow
    tagDigits = 3,    -- a shorter number is read with leading zeros (25 is 025)
}

local CARD = ConchBlessing.PocketData and ConchBlessing.PocketData.GEBO and ConchBlessing.PocketData.GEBO.id or -1
local PICKUP, COLLECTIBLE = EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE
local QUEST = ItemConfig and ItemConfig.TAG_QUEST

local targets = {}       -- [GetPtrHash(player)] = EntityPtr of the pedestal a use would change now
local optionsCache = {}  -- [item] = what it may become, kept for the room (pedestals are checked every update)
local holdersFrame, holdersCache = -1, false
local arrow = nil

-- ------------------------------------------------------------------ numbers
--- Every other number written with the same digits as `id` read as a
--- three-digit tag (25 is 025, so 250 and 502 count; a zero moved to the front
--- shortens the number: 105 gives 15), for which `allowed(n)` holds, in
--- ascending order.
function M.rearrangements(id, allowed)
    local digits = {}
    local tag = string.format("%0" .. M.data.tagDigits .. "d", math.floor(id))
    for ch in tag:gmatch("%d") do digits[#digits + 1] = ch end
    local seen, out = {}, {}
    local used, current = {}, {}
    local function walk(depth)
        if depth > #digits then
            local n = tonumber(table.concat(current))
            if n > 0 and n ~= id and not seen[n] then
                seen[n] = true
                if not allowed or allowed(n) then out[#out + 1] = n end
            end
            return
        end
        for i = 1, #digits do
            if not used[i] then
                used[i] = true
                current[depth] = digits[i]
                walk(depth + 1)
                used[i] = false
            end
        end
        current[depth] = nil
    end
    walk(1)
    table.sort(out)
    return out
end

-- A number the rune may turn an item into: an item that exists and is no
-- hidden, quest or locked item. Being in an item pool does not matter (user
-- request 2026-11-25: White Pony 181 is in none, yet it can be had).
local function makes(n)
    local config = Isaac.GetItemConfig():GetCollectible(n)
    if not config or config.Hidden then return false end
    if QUEST and type(config.HasTags) == "function" and config:HasTags(QUEST) then return false end
    if type(config.IsAvailable) == "function" then
        local ok, available = pcall(config.IsAvailable, config)
        if ok and available == false then return false end
    end
    return true
end

--- The items the item `id` may become.
function M.options(id)
    if type(id) ~= "number" or id <= 0 then return {} end
    local cached = optionsCache[id]
    if not cached then
        cached = M.rearrangements(id, makes)
        optionsCache[id] = cached
    end
    return cached
end

-- ------------------------------------------------------------------ pedestals
local function living(player)
    if not player or not player:Exists() or player:IsDead() then return false end
    return not (type(player.IsCoopGhost) == "function" and player:IsCoopGhost())
end

--- Whether the item on `pickup` may change now (and what it may become).
function M.changeable(pickup)
    if not pickup or not pickup:Exists() or pickup.Type ~= PICKUP or pickup.Variant ~= COLLECTIBLE then return false end
    local id = pickup.SubType
    if type(id) ~= "number" or id <= 0 then return false end
    local config = Isaac.GetItemConfig():GetCollectible(id)
    if not config then return false end
    if QUEST and type(config.HasTags) == "function" and config:HasTags(QUEST) then return false end
    local upgrade = ConchBlessing.upgrade
    if type(upgrade) == "table" then
        if type(upgrade.isAnimatingPickup) == "function" and upgrade.isAnimatingPickup(pickup) then return false end
        if type(upgrade.isCycleFrozen) == "function" and upgrade.isCycleFrozen(pickup) then return false end
    end
    local options = M.options(id)
    if #options == 0 then return false end
    return true, options
end

--- The nearest pedestal within reach of `player` that may change, or nil.
function M.target(player)
    if not player then return nil end
    local best, bestDistance = nil, M.data.range
    for _, entity in ipairs(Isaac.FindByType(PICKUP, COLLECTIBLE)) do
        local pickup = entity:ToPickup()
        local distance = pickup and pickup.Position:Distance(player.Position)
        if distance and distance <= bestDistance and M.changeable(pickup) then best, bestDistance = pickup, distance end
    end
    return best
end

-- The circle of a rotating pedestal behind the item on show (REPENTOGON), or nil.
local function cycleTail(pickup)
    if type(pickup.GetCollectibleCycle) ~= "function" then return nil end
    local ok, tail = pcall(pickup.GetCollectibleCycle, pickup)
    if not ok or type(tail) ~= "table" or #tail == 0 then return nil end
    local copy = {}
    for i, id in ipairs(tail) do copy[i] = id end
    return copy
end

--- Change the item on `pickup` into one of its rearrangements (chosen with
--- `rng`). Returns true, the old and the new item, or false.
function M.change(pickup, rng)
    local ok, options = M.changeable(pickup)
    if not ok then return false end
    local old = pickup.SubType
    local new = options[rng:RandomInt(#options) + 1]
    local saved = {
        price = pickup.Price, shopId = pickup.ShopItemId, autoUpdate = pickup.AutoUpdatePrice,
        options = pickup.OptionsPickupIndex, touched = pickup.Touched,
    }
    local isShop = type(pickup.IsShopItem) == "function" and pickup:IsShopItem()
    -- Only the item on show changes: the circle behind it is held and put back.
    local tail = cycleTail(pickup)
    if tail then pcall(pickup.RemoveCollectibleCycle, pickup) end
    pickup:Morph(PICKUP, COLLECTIBLE, new, true, true, true)
    if tail then
        for _, id in ipairs(tail) do pcall(pickup.AddCollectibleCycle, pickup, id) end
    end
    if isShop and type(pickup.MakeShopItem) == "function" and saved.shopId ~= nil then
        pcall(pickup.MakeShopItem, pickup, saved.shopId)
    elseif saved.shopId ~= nil then
        pickup.ShopItemId = saved.shopId
    end
    if saved.price ~= nil then pickup.Price = saved.price end
    if saved.autoUpdate ~= nil then pickup.AutoUpdatePrice = saved.autoUpdate end
    if saved.options ~= nil then pickup.OptionsPickupIndex = saved.options end
    if saved.touched ~= nil then pickup.Touched = saved.touched end
    if pickup.SubType ~= new then
        ConchBlessing.printError(string.format("[Gebo] item %d did not become %d (now %s)", old, new,
            tostring(pickup.SubType)))
        return false
    end
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, pickup.Position, Vector.Zero, nil)
    local sfx = SFXManager()
    if sfx then sfx:Play(SoundEffect.SOUND_BONE_SNAP, Sound.volume(0.6), 0, false, 1.25) end
    ConchBlessing.printDebug("[Gebo] item %d became %d (of %d choices)", old, new, #options)
    return true, old, new
end

-- MC_USE_CARD runs for a copy from Blank Card or Clear Rune too, with the
-- triggering player. With nothing in reach nothing happens; the rune is
-- spent all the same, like a vanilla rune with no target.
function M.onUseCard(_, card, player)
    if card ~= CARD or not player then return end
    targets[GetPtrHash(player)] = nil
    local pickup = M.target(player)
    if not pickup then
        ConchBlessing.printDebug("[Gebo] used with no pedestal in reach")
        return
    end
    M.change(pickup, player:GetCardRNG(CARD))
end

-- ------------------------------------------------------------------ holding
local function holds(player)
    if CARD <= 0 or not living(player) or type(player.GetCard) ~= "function" then return false end
    for slot = 0, 3 do
        local ok, card = pcall(player.GetCard, player, slot)
        if ok and card == CARD then return true end
    end
    return false
end

--- Whether any living player holds Gebo (worked out once a render frame).
function M.anyHolder()
    local frame = Isaac.GetFrameCount()
    if frame ~= holdersFrame then
        holdersFrame, holdersCache = frame, false
        for i = 0, Game():GetNumPlayers() - 1 do
            if holds(Isaac.GetPlayer(i)) then holdersCache = true break end
        end
    end
    return holdersCache
end

-- The pedestal each player would change by using the rune from the pocket
-- slot it is used from (slot 0); worked out once an update.
function M.onUpdate()
    if CARD <= 0 then return end
    local seen = {}
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if living(player) and player:GetCard(0) == CARD then
            local pickup = M.target(player)
            if pickup then
                local key = GetPtrHash(player)
                targets[key] = EntityPtr(pickup)
                seen[key] = true
            end
        end
    end
    for key in pairs(targets) do
        if not seen[key] then targets[key] = nil end
    end
end

-- A milk-white arrow bobbing over the item that would change (Cereal's gold
-- arrow marks what it would grind).
function M.onRender()
    if next(targets) == nil then return end
    if arrow == nil then
        local ok, sprite = pcall(function()
            local s = Sprite()
            s:Load("gfx/ui/conch_cereal_ui.anm2", true)
            s:SetFrame("ArrowDown", 0)
            return s
        end)
        arrow = ok and sprite or false
    end
    if not arrow then return end
    local drawn = {}
    for _, ptr in pairs(targets) do
        local pickup = ptr.Ref and ptr.Ref:ToPickup()
        local hash = pickup and GetPtrHash(pickup)
        if pickup and not drawn[hash] and M.changeable(pickup) then
            drawn[hash] = true
            local at = Isaac.WorldToScreen(pickup.Position + pickup.PositionOffset)
            local bob = math.floor(math.sin(Isaac.GetFrameCount() / 9) * 2 + 0.5)
            arrow.Color = Color(1, 0.98, 0.9, 1)
            arrow:Render(Vector(at.X - 4, at.Y - M.data.markerLift + bob))
        end
    end
end

function M.onNewRoom()
    targets, optionsCache = {}, {}
end

-- ------------------------------------------------------------------ EID
-- While anyone holds the rune, a pedestal's description ends with what it may
-- become ({{Collectible<id>}} icons), or that it cannot change.
function M.eidLine(id)
    local Locale = ConchBlessing.Locale
    if type(id) ~= "number" or id <= 0 or not Locale then return nil end
    local config = Isaac.GetItemConfig():GetCollectible(id)
    if not config or (QUEST and type(config.HasTags) == "function" and config:HasTags(QUEST)) then return nil end
    local options = M.options(id)
    if #options == 0 then return Locale.text("ui.gebo.none", tostring(CARD)) end
    local icons = {}
    for i, n in ipairs(options) do icons[i] = "{{Collectible" .. n .. "}}" end
    return Locale.text("ui.gebo.options", tostring(CARD), table.concat(icons))
end

function M.describe(descObj)
    local ok, line = pcall(M.eidLine, descObj.ObjSubType)
    if ok and type(line) == "string" then descObj.Description = (descObj.Description or "") .. line end
    return descObj
end

if type(EID) == "table" and type(EID.addDescriptionModifier) == "function" and CARD > 0 then
    EID:addDescriptionModifier("ConchBlessing_GeboRearrangements", function(descObj)
        return descObj.ObjType == PICKUP and descObj.ObjVariant == COLLECTIBLE and (descObj.ObjSubType or 0) > 0
            and M.anyHolder()
    end, M.describe)
end

M._test = {
    card = function() return CARD end,
    target = function(player) local ptr = player and targets[GetPtrHash(player)]; return ptr and ptr.Ref end,
    reset = function() targets, optionsCache, holdersFrame = {}, {}, -1 end,
}

if CARD > 0 then
    ConchBlessing:AddCallback(ModCallbacks.MC_USE_CARD, M.onUseCard, CARD)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, M.onUpdate)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, M.onRender)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, M.onNewRoom)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, M.onNewRoom)
end

return M
