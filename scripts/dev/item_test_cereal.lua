local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 시리얼 (Cereal): the lifecycle contract and its cases. Items are taken from
-- real pedestals (the player walks onto them), the bowl is opened through the
-- engine (`UseActiveItem` from its real slot), keys the module reads are held
-- through its test key source (a mod's own key reads ignore MC_INPUT_ACTION),
-- and every check reads the engine: the inventory, the item queue, the
-- cereal pickups in the room and the item pool's own answers. The expected
-- behaviour is the user's design (2026-11-24): the use key while an item is
-- held up breaks it into its number's cereal (as it is written; Breakfast three
-- random ones), walking onto cereal takes it, a Breakfast taken is one milk,
-- the bowl makes the item of the number put in for milk, one for quality 0-2
-- and two for 3-4 (an active on a pedestal), a number with no item is
-- cancelled with nothing spent, and every draw becomes Breakfast with chance
-- 1/2 x 1/2 ^ milk.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function M() return ConchBlessing.cereal end
-- Enum values are read when a plan is built, never as the file loads.
local function brimstone() return CollectibleType.COLLECTIBLE_BRIMSTONE end
local function breakfast() return CollectibleType.COLLECTIBLE_BREAKFAST end

local function requireModule(plan)
    plan.require("Cereal module ready", function()
        return M() and M()._test and M()._test.variant() and true or nil, "module or pickup missing"
    end)
end

local function cereals()
    local out = {}
    local variant = M()._test.variant()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == variant then out[#out + 1] = entity:ToPickup() end
    end
    table.sort(out, function(a, b) return a.InitSeed < b.InitSeed end)
    return out
end

local function subtypes()
    local out = {}
    for _, pickup in ipairs(cereals()) do out[#out + 1] = pickup.SubType end
    table.sort(out)
    local text = {}
    for i, d in ipairs(out) do text[i] = tostring(d) end
    return table.concat(text, ",")
end

local function stock()
    local text = {}
    for d = 0, 9 do text[#text + 1] = tostring(M().count(d)) end
    return table.concat(text, "") .. " milk " .. M().milk()
end

local function clearStock()
    local run = ConchBlessing.SaveManager and ConchBlessing.SaveManager.GetRunSave and ConchBlessing.SaveManager.GetRunSave(nil, false)
    if type(run) == "table" then run.cereal = nil end
end

local function cleanup(plan)
    plan.act(function(_, ctx)
        if ctx.cerealCleanup then return end
        ctx.cerealCleanup = true
        clearStock()
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
            if M() then M()._test.reset() end
            clearStock()
            for _, pickup in ipairs(cereals()) do pickup:Remove() end
        end
    end)
end

local function pedestals(id)
    local out = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE
            and (not id or entity.SubType == id) then
            out[#out + 1] = entity:ToPickup()
        end
    end
    return out
end

local function holdCereal(plan, id)
    plan.act(function(player) S.collectible(player, id, 1) end)
    plan.require("Cereal is in the active slot", function(player)
        return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == id or nil,
            "slot holds " .. tostring(player:GetActiveItem(ActiveSlot.SLOT_PRIMARY))
    end)
end

-- Spawn a pedestal of `item` a little below the player and walk onto it, then
-- wait until the item is held up (queued, not yet added).
local function liftFrom(plan, item)
    plan.act(function(player, ctx)
        local id = item()
        local room = Game():GetRoom()
        local pos = room:FindFreePickupSpawnPosition(player.Position + Vector(0, 80), 0, true)
        local pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, pos, Vector.Zero, nil)
        ctx.pedestal = EntityPtr(pickup)
        ctx.lifted = id
    end)
    plan.wait(2)
    plan.act(function(player, ctx)
        local pedestal = ctx.pedestal and ctx.pedestal.Ref and ctx.pedestal.Ref:ToPickup()
        if pedestal then
            pedestal.Wait = 0
            player.Position = pedestal.Position
        end
    end)
    plan.waitUntil(function(player)
        return not player:IsItemQueueEmpty()
    end, 60, "the item is held up")
end

-- Count every MC_USE_ITEM of Cereal, as a use counter would see them: an open
-- or a close of the bowl is none, a made or broken item one each.
local function observeUses(plan, id)
    plan.act(function(_, ctx)
        ctx.useEvents = 0
        local fn = function(_, used) if used == id then ctx.useEvents = ctx.useEvents + 1 end end
        ConchBlessing:AddCallback(ModCallbacks.MC_USE_ITEM, fn)
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function() ConchBlessing:RemoveCallback(ModCallbacks.MC_USE_ITEM, fn) end
    end)
end

local function expectUses(plan, label, n)
    plan.check(label, function(_, ctx)
        return ctx.useEvents == n, "MC_USE_ITEM of Cereal: " .. tostring(ctx.useEvents)
    end)
end

-- Press a key the module reads for a couple of updates, then let it go.
local function press(plan, name)
    plan.act(function() M()._test.hold(ButtonAction[name], true) end)
    plan.wait(2)
    plan.act(function() M()._test.hold(ButtonAction[name], false) end)
    plan.wait(2)
end

local function use(plan, id)
    plan.act(function(player) H.use(player, id) end)
    plan.wait(2)
end

-- Sample, every render frame from here on, how the player is drawn: hidden,
-- see-through (entity or sprite colour) or with a body/head layer switched off
-- (user report 2026-11-24: the body went see-through while breaking).
local function watchLook(plan)
    plan.act(function(player, ctx)
        local look = { frames = 0, worst = nil, anims = {} }
        ctx.look = look
        local ptr = GetPtrHash(player)
        local fn = function(_, p)
            if GetPtrHash(p) ~= ptr then return end
            look.frames = look.frames + 1
            local sprite = p:GetSprite()
            local problems = {}
            if not p.Visible then problems[#problems + 1] = "Visible=false" end
            if p.Color.A < 0.99 then problems[#problems + 1] = string.format("entity alpha %.2f", p.Color.A) end
            if sprite.Color.A < 0.99 then problems[#problems + 1] = string.format("sprite alpha %.2f", sprite.Color.A) end
            if type(sprite.GetAllLayers) == "function" then
                local okLayers, layers = pcall(sprite.GetAllLayers, sprite)
                if okLayers and type(layers) == "table" then
                    for _, layer in ipairs(layers) do
                        local name = layer:GetName()
                        if (name == "body" or name == "head") and not layer:IsVisible() then
                            problems[#problems + 1] = name .. " layer hidden"
                        end
                    end
                end
            end
            local anim = sprite:GetAnimation()
            look.anims[anim] = true
            if #problems > 0 and not look.worst then
                look.worst = string.format("render %d anim %s: %s", look.frames, anim, table.concat(problems, ", "))
            end
        end
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_PLAYER_RENDER, fn)
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function() ConchBlessing:RemoveCallback(ModCallbacks.MC_POST_PLAYER_RENDER, fn) end
    end)
end

local function expectVisible(plan, label)
    plan.check(label, function(_, ctx)
        local look = ctx.look
        local anims = {}
        for name in pairs(look.anims) do anims[#anims + 1] = name end
        table.sort(anims)
        return look.frames > 0 and look.worst == nil, string.format("%d renders, %s; animations %s",
            look.frames, look.worst or "always drawn whole", table.concat(anims, " "))
    end)
end

-- Walk onto every cereal on the floor, one at a time.
local function takeAll(plan)
    plan.wait(12)
    for _ = 1, 6 do
        plan.act(function(player)
            local list = cereals()
            if list[1] then player.Position = list[1].Position end
        end)
        plan.wait(3)
    end
end

-- The lifecycle: with a copy and a milk, a use opens the bowl and spends
-- nothing until something is made; closing it spends nothing.
C.CEREAL = { stage = function(plan, id, n)
    requireModule(plan)
    cleanup(plan)
    if n > 0 then
        plan.act(function() M().addMilk(1) end)
        plan.act(function(player, ctx) ctx.slotItem = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) end)
        use(plan, id)
        plan.check("a use with milk opens the bowl", function(player, ctx)
            return M().picking(player) == true or ctx.slotItem ~= id,
                string.format("picking=%s slot=%s milk=%d", tostring(M().picking(player)), tostring(ctx.slotItem), M().milk())
        end)
        plan.act(function(player) M()._test.close(player) end)
        plan.check("closing spends nothing", function()
            return M().milk() == 1, stock()
        end)
        plan.act(function() clearStock() end)
    end
    plan.check("no bowl stays open between stages", function(player)
        return not M().picking(player), "copies=" .. n
    end)
end }

-- The use key while an item is held up: the item is not taken and its number
-- falls as cereal (Brimstone is 118: 1, 1, 8). Walking onto them takes them.
S.add("CEREAL", "break", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    observeUses(plan, id)
    liftFrom(plan, brimstone)
    plan.act(function(player, ctx) ctx.tearsBefore = H.stats(player).Tears end)
    watchLook(plan)
    press(plan, "ACTION_ITEM")
    plan.wait(30)
    expectVisible(plan, "the player stays drawn whole while breaking")
    plan.note("the player after the break", function(player)
        return string.format("queue empty=%s extra anim finished=%s anim=%s holding=%s",
            tostring(player:IsItemQueueEmpty()), tostring(player:IsExtraAnimationFinished()),
            player:GetSprite():GetAnimation(),
            type(player.IsHoldingItem) == "function" and tostring(player:IsHoldingItem()) or "n/a")
    end)
    expectUses(plan, "breaking the item counts as one use", 1)
    plan.check("the item is not taken and its number falls as cereal", function(player)
        local ok = player:IsItemQueueEmpty() and player:GetCollectibleNum(brimstone(), true) == 0
            and subtypes() == "1,1,8"
        return ok, string.format("queue empty=%s brimstone=%d cereal=%s", tostring(player:IsItemQueueEmpty()),
            player:GetCollectibleNum(brimstone(), true), subtypes())
    end)
    plan.check("its tears never came", function(player, ctx)
        return H.expect(H.stats(player).Tears, ctx.tearsBefore)
    end)
    plan.check("the cereal lie in a row in the number's order, not scattered", function()
        local list = cereals()
        table.sort(list, function(a, b) return a.Position.X < b.Position.X end)
        local order, ys = {}, {}
        for i, pickup in ipairs(list) do
            order[i] = tostring(pickup.SubType)
            ys[i] = pickup.Position.Y
        end
        local level = #ys == 3 and math.abs(ys[1] - ys[2]) < 2 and math.abs(ys[2] - ys[3]) < 2
        return table.concat(order, ",") == "1,1,8" and level, table.concat(order, ",") .. string.format(
            " y %.1f %.1f %.1f", ys[1] or -1, ys[2] or -1, ys[3] or -1)
    end)
    takeAll(plan)
    plan.check("walking onto the cereal takes it", function()
        return #cereals() == 0 and M().count(1) == 2 and M().count(8) == 1, stock() .. " left " .. #cereals()
    end)
    -- (user report 2026-11-24: after a break no other item of the room could
    -- be taken) Another pedestal in the same room is held up and kept.
    plan.act(function(_, ctx) ctx.roomBefore = Game():GetLevel():GetCurrentRoomIndex() end)
    liftFrom(plan, function() return CollectibleType.COLLECTIBLE_SAD_ONION end)
    plan.waitUntil(function(player) return player:IsItemQueueEmpty() end, 90, "the next item is added")
    plan.check("another item in the same room is taken afterwards", function(player, ctx)
        local n = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SAD_ONION, true)
        return n == 1 and Game():GetLevel():GetCurrentRoomIndex() == ctx.roomBefore,
            string.format("Sad Onion=%d same room=%s", n, tostring(Game():GetLevel():GetCurrentRoomIndex() == ctx.roomBefore))
    end)
    expectVisible(plan, "the player stays drawn whole through the next pickup")
end)

-- Breakfast breaks into three random digits, and is no milk.
S.add("CEREAL", "breakfast_break", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    liftFrom(plan, breakfast)
    press(plan, "ACTION_ITEM")
    plan.wait(30)
    plan.check("three cereal fall, no Breakfast and no milk", function(player)
        local list = cereals()
        return #list == 3 and player:GetCollectibleNum(breakfast(), true) == 0 and M().milk() == 0,
            string.format("cereal=%s breakfast=%d milk=%d", subtypes(), player:GetCollectibleNum(breakfast(), true), M().milk())
    end)
    plan.note("the digits Breakfast broke into", function() return subtypes() end)
end, { "breakfast" }) -- the Breakfast synergy line: three random number cereal

-- A Breakfast taken normally is kept (its health up comes) and is one milk.
S.add("CEREAL", "milk", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    liftFrom(plan, breakfast)
    plan.waitUntil(function(player) return player:IsItemQueueEmpty() end, 120, "the Breakfast is taken")
    plan.check("a Breakfast taken is one milk", function(player)
        return player:GetCollectibleNum(breakfast(), true) == 1 and M().milk() == 1,
            string.format("breakfast=%d %s", player:GetCollectibleNum(breakfast(), true), stock())
    end)
end)

-- The bowl makes a passive for milk by its quality (user decision 2026-11-25:
-- one for quality 0-2, two for 3-4). With one milk Brimstone (1, 1, 8,
-- quality 4) is refused with nothing spent; with three it is made, held up and
-- taken for two, and The Compass (2, 1, quality 1) for the last one.
S.add("CEREAL", "craft", { conditions = true }, function(plan, id)
    local compass = CollectibleType.COLLECTIBLE_COMPASS
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    observeUses(plan, id)
    plan.require("Brimstone is quality 3-4 and The Compass 0-2 and makeable", function()
        local config = Isaac.GetItemConfig()
        local b, c = config:GetCollectible(brimstone()), config:GetCollectible(compass)
        local ok = b and c and b.Quality >= 3 and c.Quality <= 2 and c:IsAvailable()
        return ok or nil, string.format("Brimstone quality %s, The Compass quality %s available %s",
            tostring(b and b.Quality), tostring(c and c.Quality), tostring(c and c:IsAvailable()))
    end)
    plan.act(function() M().addMilk(1); M().addDigit(1, 3); M().addDigit(8, 1); M().addDigit(2, 1); M().addDigit(4, 1) end)
    use(plan, id)
    plan.require("the bowl is open", function(player) return M().picking(player) or nil, "closed" end)
    plan.require("1, 1, 8 go in", function(player) return M()._test.type(player, { 1, 1, 8 }) or nil, "refused" end)
    plan.note("the line above the bowl", function()
        local line, enough = M()._test.resultLine({ 1, 1, 8 })
        return tostring(line) .. " enough=" .. tostring(enough)
    end)
    plan.check("the line names Brimstone's quality and two milk, red with one milk", function()
        local line, enough = M()._test.resultLine({ 1, 1, 8 })
        local quality = tostring(Isaac.GetItemConfig():GetCollectible(brimstone()).Quality)
        local ok = type(line) == "string" and line:find("118", 1, true) ~= nil and line:find(quality, 4, true) ~= nil
            and line:find("2", 4, true) ~= nil and enough == false
        return ok, tostring(line) .. " enough=" .. tostring(enough)
    end)
    press(plan, "ACTION_ITEM")
    plan.check("with one milk Brimstone is refused, nothing spent and the bowl stays open", function(player)
        local toast = M()._test.toast(player)
        return M().picking(player) and M().milk() == 1 and M().count(1) == 3 and M().count(8) == 1
            and player:GetCollectibleNum(brimstone(), true) == 0 and player:IsItemQueueEmpty() and toast ~= nil,
            stock() .. " toast " .. tostring(toast)
    end)
    press(plan, "ACTION_DROP")
    plan.act(function() M().addMilk(2) end)
    use(plan, id)
    plan.require("the bowl is open again", function(player) return M().picking(player) or nil, "closed" end)
    plan.require("1, 1, 8 go in again", function(player) return M()._test.type(player, { 1, 1, 8 }) or nil, "refused" end)
    press(plan, "ACTION_ITEM")
    plan.waitUntil(function(player)
        return player:GetCollectibleNum(brimstone(), true) == 1 and player:IsItemQueueEmpty()
    end, 120, "Brimstone is taken")
    expectUses(plan, "opening the bowl and the refusal were no use, making Brimstone one", 1)
    plan.check("Brimstone is made for three cereal and two milk", function(player)
        return M().count(1) == 1 and M().count(8) == 0 and M().count(2) == 1 and M().count(4) == 1 and M().milk() == 1
            and player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == id, stock()
    end)
    use(plan, id)
    plan.require("2, 1 go in", function(player) return M()._test.type(player, { 2, 1 }) or nil, "refused" end)
    press(plan, "ACTION_ITEM")
    plan.waitUntil(function(player)
        return player:GetCollectibleNum(compass, true) == 1 and player:IsItemQueueEmpty()
    end, 120, "The Compass is taken")
    expectUses(plan, "making The Compass is one more use", 2)
    plan.check("The Compass is made for two cereal and the last milk", function()
        return M().count(1) == 0 and M().count(2) == 0 and M().count(4) == 1 and M().milk() == 0, stock()
    end)
end)

-- An active is set down on a pedestal nearby: 1, 0, 5 is The D6 (quality 4,
-- two milk).
S.add("CEREAL", "craft_active", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    plan.act(function() M().addMilk(2); M().addDigit(1, 1); M().addDigit(0, 1); M().addDigit(5, 1) end)
    use(plan, id)
    plan.require("1, 0, 5 go in", function(player) return M()._test.type(player, { 1, 0, 5 }) or nil, "refused" end)
    press(plan, "ACTION_ITEM")
    plan.wait(4)
    plan.check("The D6 stands on a pedestal nearby and Cereal stays in the slot", function(player)
        local list = pedestals(CollectibleType.COLLECTIBLE_D6)
        local away = list[1] and list[1].Position:Distance(player.Position) or 0
        return #list == 1 and away >= 30 and player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == id and M().milk() == 0,
            string.format("pedestals=%d distance=%.1f slot=%d %s", #list, away,
                player:GetActiveItem(ActiveSlot.SLOT_PRIMARY), stock())
    end)
end)

-- A number with no item (000, 666) is cancelled: nothing spent, nothing made.
S.add("CEREAL", "invalid", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    plan.act(function() M().addMilk(1); M().addDigit(0, 3); M().addDigit(6, 3) end)
    use(plan, id)
    plan.check("0 cannot go in first (a number never starts with 0)", function(player)
        local refused = M()._test.type(player, { 0 }) == false
        return refused and #M()._test.picker(player).entered == 0, "refused=" .. tostring(refused)
    end)
    press(plan, "ACTION_DROP")
    for _, digits in ipairs({ { 6, 6, 6 } }) do
        use(plan, id)
        plan.require(table.concat(digits) .. " goes in", function(player)
            return M()._test.type(player, digits) or nil, "refused"
        end)
        press(plan, "ACTION_ITEM")
        plan.check(table.concat(digits) .. " is cancelled with nothing spent", function(player)
            return not M().picking(player) and M().milk() == 1 and M().count(0) == 3 and M().count(6) == 3
                and #pedestals() == 0 and M()._test.toast(player) ~= nil, stock() .. " toast " .. tostring(M()._test.toast(player))
        end)
        plan.wait(4)
    end
end)

-- While the bowl is open its keys are kept from the game and walking is not;
-- the drop key closes it with nothing spent.
S.add("CEREAL", "keys", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    plan.act(function() M().addMilk(1); M().addDigit(2, 1) end)
    use(plan, id)
    plan.check("the bowl's keys are kept from the game, walking is not", function(player)
        local t = M()._test
        local kept = t.withheld(player, ButtonAction.ACTION_SHOOTLEFT) and t.withheld(player, ButtonAction.ACTION_SHOOTUP)
            and t.withheld(player, ButtonAction.ACTION_ITEM) and t.withheld(player, ButtonAction.ACTION_DROP)
            and t.withheld(player, ButtonAction.ACTION_PAUSE)
        local free = not t.withheld(player, ButtonAction.ACTION_LEFT) and not t.withheld(player, ButtonAction.ACTION_BOMB)
        return kept and free, string.format("kept=%s free=%s", tostring(kept), tostring(free))
    end)
    plan.act(function(player, ctx) ctx.sel = M()._test.picker(player).sel end)
    press(plan, "ACTION_SHOOTRIGHT")
    plan.check("right moves to the next digit", function(player, ctx)
        local picker = M()._test.picker(player)
        return picker ~= nil and picker.sel == (ctx.sel + 1) % 10, tostring(picker and picker.sel)
    end)
    press(plan, "ACTION_DROP")
    plan.check("closed with nothing spent and nothing kept", function(player)
        local t = M()._test
        return not M().picking(player) and M().milk() == 1 and not t.withheld(player, ButtonAction.ACTION_SHOOTLEFT),
            stock()
    end)
    -- Esc closes it too (user request 2026-11-24).
    use(plan, id)
    press(plan, "ACTION_PAUSE")
    plan.check("Esc closes the bowl with nothing spent", function(player)
        return not M().picking(player) and M().milk() == 1, stock()
    end)
end)

-- Without milk the bowl still opens, to look at the cereal held (user request
-- 2026-11-24); the use key on the empty bowl closes it with nothing spent.
S.add("CEREAL", "look", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    observeUses(plan, id)
    plan.act(function() M().addDigit(7, 2) end)
    use(plan, id)
    plan.check("the bowl opens without milk", function(player)
        return M().picking(player) == true, stock()
    end)
    press(plan, "ACTION_ITEM")
    plan.check("the use key on the empty bowl closes it, nothing spent", function(player)
        return not M().picking(player) and M().count(7) == 2 and M().milk() == 0, stock()
    end)
    plan.wait(2)
    expectUses(plan, "opening and closing the bowl counts as no use", 0)
end)

-- Leaving the room closes the bowl with nothing spent.
S.add("CEREAL", "room", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    plan.act(function() M().addMilk(1) end)
    use(plan, id)
    plan.require("the bowl is open", function(player) return M().picking(player) or nil, "closed" end)
    -- An ordinary room when the start room has one, else any open door but a
    -- curse room's (a start room may lead only to special rooms).
    H.walkThroughDoor(plan, "walk into the next room", function()
        local room, fallback = Game():GetRoom(), nil
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door:IsOpen() then
                if door.TargetRoomType == RoomType.ROOM_DEFAULT then return slot end
                if not fallback and door.TargetRoomType ~= RoomType.ROOM_CURSE then fallback = slot end
            end
        end
        return fallback
    end)
    plan.check("a new room closes the bowl and spends nothing", function(player)
        return not M().picking(player) and M().milk() == 1, stock()
    end)
end)

-- A pedestal set down `dy` below the player (`price` for a shop item, `group`
-- for a choice); the room's update then marks or leaves it.
local function placePedestal(plan, name, id, dy, extra)
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        local pos = room:FindFreePickupSpawnPosition(player.Position + Vector(0, dy), 0, true)
        local pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id(), pos, Vector.Zero, nil):ToPickup()
        pickup.Wait = 60 -- nobody walks into it during the case
        for key, value in pairs(extra or {}) do pickup[key] = value end
        ctx[name] = EntityPtr(pickup)
    end)
    plan.wait(3)
end

local function ref(ctx, name)
    local ptr = ctx[name]
    return ptr and ptr.Ref and ptr.Ref:ToPickup()
end

-- User decision 2026-11-24 (B): a use near a pedestal Cereal may grind grinds
-- it where it stands, actives included; the pedestal is marked first, stays
-- empty, the number lies beside it, no bowl opens and it is one use.
S.add("CEREAL", "grind", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    observeUses(plan, id)
    placePedestal(plan, "d6", function() return CollectibleType.COLLECTIBLE_D6 end, 60)
    plan.check("the pedestal in reach is marked", function(player, ctx)
        local target = M()._test.target(player)
        return target ~= nil and GetPtrHash(target) == GetPtrHash(ref(ctx, "d6")), "target " .. tostring(target and target.SubType)
    end)
    use(plan, id)
    plan.wait(20)
    plan.check("The D6 is ground into 1, 0, 5 beside its pedestal and not taken", function(player, ctx)
        local pedestal = ref(ctx, "d6")
        local ok = pedestal and pedestal.SubType == 0 and subtypes() == "0,1,5"
            and player:GetCollectibleNum(CollectibleType.COLLECTIBLE_D6, true) == 0
            and player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == id and not M().picking(player)
        return ok, string.format("pedestal=%s cereal=%s d6 held=%d slot=%d bowl=%s", tostring(pedestal and pedestal.SubType),
            subtypes(), player:GetCollectibleNum(CollectibleType.COLLECTIBLE_D6, true),
            player:GetActiveItem(ActiveSlot.SLOT_PRIMARY), tostring(M().picking(player)))
    end)
    expectUses(plan, "grinding counts as one use", 1)
end)

-- Like Quick Pick, only what may be ground is marked: an item for sale has to
-- be paid for and one out of reach is not; then a use opens the bowl.
S.add("CEREAL", "grind_not", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    placePedestal(plan, "shop", brimstone, 60, { Price = 15, AutoUpdatePrice = false })
    placePedestal(plan, "far", function() return CollectibleType.COLLECTIBLE_SAD_ONION end, 200)
    plan.check("neither the shop item nor the far one is marked", function(player)
        local target = M()._test.target(player)
        return target == nil, "target " .. tostring(target and target.SubType)
    end)
    plan.act(function() M().addMilk(1) end)
    use(plan, id)
    plan.check("a use opens the bowl and both items stay", function(player, ctx)
        local shop, far = ref(ctx, "shop"), ref(ctx, "far")
        return M().picking(player) == true and shop and shop.SubType == brimstone() and far
            and far.SubType == CollectibleType.COLLECTIBLE_SAD_ONION and #cereals() == 0,
            string.format("bowl=%s shop=%s far=%s", tostring(M().picking(player)), tostring(shop and shop.SubType),
                tostring(far and far.SubType))
    end)
    plan.act(function(player) M()._test.close(player) end)
end)

-- Grinding one item of a choice takes its other choices away, as taking it does.
S.add("CEREAL", "grind_choice", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    holdCereal(plan, id)
    placePedestal(plan, "near", brimstone, 50, { OptionsPickupIndex = 77 })
    placePedestal(plan, "other", function() return CollectibleType.COLLECTIBLE_SAD_ONION end, 160, { OptionsPickupIndex = 77 })
    use(plan, id)
    plan.wait(10)
    plan.check("the near choice is ground and the other is gone", function(_, ctx)
        local near, other = ref(ctx, "near"), ref(ctx, "other")
        return near and near.SubType == 0 and (other == nil or not other:Exists()) and subtypes() == "1,1,8",
            string.format("near=%s other=%s cereal=%s", tostring(near and near.SubType), tostring(other and other:Exists()), subtypes())
    end)
end)

-- Every draw becomes Breakfast with chance 1/2 x 1/2 ^ milk while Cereal is
-- held (user decision 2026-11-24: 50% with no milk);
-- the treasure pool's own answers (nothing taken out) are counted.
S.add("CEREAL", "milk_chance", { conditions = true }, function(plan, id)
    requireModule(plan)
    cleanup(plan)
    local function share()
        local pool, n, hits = Game():GetItemPool(), 400, 0
        for i = 1, n do
            if pool:GetCollectible(ItemPoolType.POOL_TREASURE, false, i * 7919 + 13) == breakfast() then hits = hits + 1 end
        end
        return hits / n
    end
    plan.check("without Cereal the treasure pool gives no Breakfast", function(_, ctx)
        ctx.without = share()
        return ctx.without < 0.02, string.format("%.3f", ctx.without)
    end)
    holdCereal(plan, id)
    for _, case in ipairs({ { 0, 0.5, 0.08 }, { 1, 0.25, 0.07 }, { 2, 0.125, 0.05 }, { 3, 0.0625, 0.04 } }) do
        local milk, want, slack = case[1], case[2], case[3]
        plan.act(function() clearStock(); if milk > 0 then M().addMilk(milk) end end)
        plan.check(string.format("with %d milk about %s%% of draws are Breakfast", milk, tostring(want * 100)), function()
            local got = share()
            return math.abs(got - want) <= slack + 1e-9, string.format("%.3f (want %.3f)", got, want)
        end)
    end
end)

return C
