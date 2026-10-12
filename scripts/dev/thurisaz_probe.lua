-- conch_test thurisaz [CASE | list | give [N] | spawn | familiars | ledger]
-- The Kronos rune, used for real through EntityPlayer:UseCard (and Clear Rune,
-- and a real pocket drop). Each use devours one of the user's familiars for
-- good: +2 damage each plus the familiar's absorbed ability, with or without
-- Kronos, and Kronos's loss never hands them back. Every case starts from a
-- clean run and is fully automatic; results land in log.txt. The manual helpers
-- set up a live run for hands-on checks (Continue, the drop motion, the HUD).
local TestBench = require("scripts.dev.test_bench")
local H = require("scripts.dev.item_test_support")

local C = CollectibleType
local BOBBY, ANGEL, ROBO = C.COLLECTIBLE_BROTHER_BOBBY, C.COLLECTIBLE_GUARDIAN_ANGEL, C.COLLECTIBLE_ROBO_BABY
local TAG = "ThurisazProbe"

local Probe = { cases = {}, order = {} }

local function out(line)
    Isaac.ConsoleOutput(tostring(line) .. "\n")
    Isaac.DebugString("[" .. TAG .. "] " .. tostring(line))
end

local function K() return ConchBlessing.kronos end
local function kronosId() return ConchBlessing.ItemData.KRONOS.id end
local function cardId() return ConchBlessing.PocketData and ConchBlessing.PocketData.THURISAZ.id or -1 end
local function perFamiliar() return K().STATS.DAMAGE_PER_FAMILIAR end
local function damageAddition(player) return H.addition(player, "itemAdditions", kronosId(), "Damage") end
local function runeTotal(player) return K().getRuneTotal(player) end
local function runeCount(player, id) return K().getRuneCount(player, id) end
local function owned(player, id) return player:GetCollectibleNum(id, true) end

local function isStandIn(fam)
    for key in pairs(fam:GetData()) do
        if type(key) == "string" and key:find("^__kronos") then return true end
    end
    return false
end

-- The player's live familiars in the room, Kronos's own stand-ins excluded.
local function ownFamiliars(player)
    local list = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, -1, -1)) do
        local fam = entity:ToFamiliar()
        if fam and fam:Exists() and fam.Player and GetPtrHash(fam.Player) == GetPtrHash(player)
            and not isStandIn(fam) then
            list[#list + 1] = fam
        end
    end
    return list
end

local function standIns(player, variant, marker)
    local n = 0
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, variant, -1)) do
        local fam = entity:ToFamiliar()
        if fam and fam:Exists() and fam.Player and GetPtrHash(fam.Player) == GetPtrHash(player)
            and fam:GetData()[marker] then
            n = n + 1
        end
    end
    return n
end

-- ---------------------------------------------------------------- plan pieces
local function give(plan, ids, label)
    plan.act(function(player)
        for _, id in ipairs(ids) do player:AddCollectible(id, 0, false) end
    end)
    plan.waitUntil(function(player)
        local live = #ownFamiliars(player)
        return live == #ids, live .. " familiars"
    end, 60, label or (#ids .. " familiars follow the player"))
end

local function useRune(plan, leftAfter, label)
    plan.act(function(player, ctx)
        ctx.before = H.stats(player)
        ctx.beforeTotal = runeTotal(player)
        player:UseCard(cardId(), UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
    end)
    plan.waitUntil(function(player)
        local live = #ownFamiliars(player)
        return live == leftAfter, live .. " left"
    end, 30, label or ("the devoured familiars leave the room (" .. leftAfter .. " left)"))
    plan.wait(4)
end

local function roomEntry(plan)
    plan.act(function(_, ctx)
        ctx.beforeRooms = ctx.rooms
        Game():StartRoomTransition(Game():GetLevel():GetCurrentRoomIndex(), Direction.NO_DIRECTION,
            RoomTransitionAnim.FADE)
    end)
    plan.waitUntil(function(_, ctx) return ctx.rooms > ctx.beforeRooms end, 150, "a real room entry")
    plan.wait(6)
end

local function expectAddition(plan, label, copies)
    plan.check(label, function(player) return H.expect(damageAddition(player), copies * perFamiliar()) end)
end

local function expectTotal(plan, label, total)
    plan.check(label, function(player) return H.expect(runeTotal(player), total) end)
end

-- Brother Bobby's absorbed ability: tears a second per counted copy, over the
-- run's starting tears.
local function expectBobbyTears(plan, label, copies)
    plan.check(label, function(player, ctx)
        local gain = copies * K().STATS.BROTHER_BOBBY_TEARS
        local actual = H.stats(player).Tears - ctx.base.Tears
        return math.abs(actual - gain) < 0.05, string.format("+%.3f, want +%.3f", actual, gain)
    end)
end

-- ---------------------------------------------------------------- cases
local function case(name, title, build)
    local command = "conch_test thurisaz " .. name
    Probe.cases[name] = command
    Probe.order[#Probe.order + 1] = name
    TestBench.register({
        command = command, tag = TAG, duration = "a few seconds", restartCommand = "restart 0", cleanup = H.cleanup,
        build = function(plan)
            plan.section("THURISAZ " .. name .. ": setup")
            plan.waitUntil(function(player)
                return player:Exists() and ConchBlessing.SaveManager.GetRunSave(player) ~= nil
            end, 60, "player and run save ready")
            plan.require("the rune is registered and its card ID resolves", function()
                return cardId() > 0 and type(K().devourWithRune) == "function", "card id " .. tostring(cardId())
            end)
            plan.act(function(player, ctx)
                assert(Game():GetNumPlayers() == 1 and player:GetPlayerType() == PlayerType.PLAYER_ISAAC,
                    "single-player Isaac test run required")
                player.Position = Game():GetRoom():GetCenterPos()
                H.refresh(player)
                ctx.base = H.stats(player)
            end)
            plan.section("THURISAZ " .. name .. ": " .. title)
            build(plan)
        end,
    })
end

case("basic", "one familiar a use, without Kronos", function(plan)
    give(plan, { BOBBY })
    useRune(plan, 0)
    plan.check("Brother Bobby's collectible is gone", function(player)
        return owned(player, BOBBY) == 0, "Bobby owned " .. owned(player, BOBBY)
    end)
    plan.check("the rune's ledger holds it once", function(player)
        return runeTotal(player) == 1 and runeCount(player, BOBBY) == 1, "total " .. runeTotal(player)
    end)
    expectAddition(plan, "+2 damage for the devoured familiar in StatsAPI", 1)
    plan.check("the displayed damage rose", function(player, ctx)
        return player.Damage > ctx.base.Damage + 1, string.format("%.2f -> %.2f", ctx.base.Damage, player.Damage)
    end)
    expectBobbyTears(plan, "Brother Bobby's ability: +2 tears a second", 1)
    plan.check("Kronos's own ledger is untouched", function(player)
        return K()._getAbsorbedCount(player, BOBBY) == 0, "Kronos Bobby " .. K()._getAbsorbedCount(player, BOBBY)
    end)
    plan.section("THURISAZ basic: Guardian Angel, then Robo-Baby, one use each")
    give(plan, { ANGEL })
    useRune(plan, 0)
    plan.check("Guardian Angel's ability: +0.3 speed", function(player, ctx)
        return H.expect(player.MoveSpeed - ctx.base.Speed, K().STATS.GUARDIAN_ANGEL_SPEED)
    end)
    give(plan, { ROBO })
    useRune(plan, 0)
    plan.check("Robo-Baby turns into Technology", function(player)
        return player:HasCollectible(C.COLLECTIBLE_TECHNOLOGY), "Technology owned"
    end)
    expectTotal(plan, "three uses, three familiars", 3)
    expectAddition(plan, "+6 damage for three", 3)
    plan.section("THURISAZ basic: with no familiar left nothing changes")
    useRune(plan, 0)
    expectTotal(plan, "the ledger stays at three", 3)
    plan.check("no stat moved", function(player, ctx) return H.sameStats(player, ctx.before) end)
    plan.section("THURISAZ basic: a new room keeps everything")
    roomEntry(plan)
    expectAddition(plan, "damage stays after the room change", 3)
    expectBobbyTears(plan, "Bobby's tears stay after the room change", 1)
end)

case("more", "with three familiars it takes exactly one a use", function(plan)
    local three = { BOBBY, ANGEL, ROBO }
    give(plan, three)
    useRune(plan, 2)
    plan.check("one of the three collectibles is gone", function(player)
        local left = 0
        for _, id in ipairs(three) do left = left + owned(player, id) end
        return left == 2, left .. " still owned"
    end)
    plan.check("the ledger holds exactly the one that went", function(player)
        local taken = 0
        for _, id in ipairs(three) do taken = taken + runeCount(player, id) end
        return taken == 1 and runeTotal(player) == 1, "ledger " .. taken .. ", total " .. runeTotal(player)
    end)
    expectAddition(plan, "+2 damage for one", 1)
    plan.section("THURISAZ more: two more uses take the other two, one each")
    useRune(plan, 1)
    expectTotal(plan, "two after the second use", 2)
    useRune(plan, 0)
    expectTotal(plan, "all three are the rune's now", 3)
    expectAddition(plan, "+6 damage for three", 3)
    plan.section("THURISAZ more: two uses in the same moment take two different familiars")
    local pair = { C.COLLECTIBLE_SACK_OF_PENNIES, C.COLLECTIBLE_LIL_HAUNT }
    give(plan, pair)
    plan.act(function(player)
        player:UseCard(cardId(), UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
        player:UseCard(cardId(), UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
    end)
    plan.waitUntil(function(player) return #ownFamiliars(player) == 0, #ownFamiliars(player) .. " left" end,
        30, "both familiars leave the room")
    plan.wait(4)
    plan.check("each is in the ledger once, none twice", function(player)
        return runeCount(player, pair[1]) == 1 and runeCount(player, pair[2]) == 1 and runeTotal(player) == 5,
            string.format("sack %d, haunt %d, total %d", runeCount(player, pair[1]), runeCount(player, pair[2]),
                runeTotal(player))
    end)
end)

case("flies", "familiars with no item give the flat damage", function(plan)
    plan.act(function(player) player:AddBlueFlies(2, player.Position, nil) end)
    plan.waitUntil(function(player) return #ownFamiliars(player) == 2, #ownFamiliars(player) .. " flies" end,
        30, "two blue flies")
    useRune(plan, 1)
    plan.check("the ledger counts one as a familiar with no item", function(player)
        local ledger = H.save(player).thurisaz or {}
        return ledger.generic == 1 and runeTotal(player) == 1,
            "generic " .. tostring(ledger.generic) .. ", total " .. runeTotal(player)
    end)
    expectAddition(plan, "+2 damage for it", 1)
    useRune(plan, 0)
    plan.check("the second fly too", function(player)
        local ledger = H.save(player).thurisaz or {}
        return ledger.generic == 2 and runeTotal(player) == 2, "generic " .. tostring(ledger.generic)
    end)
    expectAddition(plan, "+2 damage each", 2)
    plan.check("no other stat changes", function(player, ctx)
        local now = H.stats(player)
        return H.near(now.Tears, ctx.base.Tears) and H.near(now.Speed, ctx.base.Speed), "tears/speed unchanged"
    end)
end)

case("temporary", "a Box of Friends copy goes first and is kept for good", function(plan)
    give(plan, { BOBBY })
    plan.act(function(player) player:UseActiveItem(C.COLLECTIBLE_BOX_OF_FRIENDS, UseFlag.USE_NOANIM, -1) end)
    plan.waitUntil(function(player) return #ownFamiliars(player) == 2, #ownFamiliars(player) .. " Bobbies" end,
        30, "Box of Friends doubles Brother Bobby")
    useRune(plan, 1)
    plan.check("the temporary copy is taken before the owned one", function(player)
        local effect = player:GetEffects():GetCollectibleEffectNum(BOBBY)
        return owned(player, BOBBY) == 1 and effect == 0 and runeCount(player, BOBBY) == 1,
            string.format("owned %d, effect %d, ledger %d", owned(player, BOBBY), effect, runeCount(player, BOBBY))
    end)
    expectAddition(plan, "+2 damage for it", 1)
    plan.section("THURISAZ temporary: the next use takes the owned copy")
    useRune(plan, 0)
    plan.check("both Bobbies are the rune's", function(player)
        return owned(player, BOBBY) == 0 and runeCount(player, BOBBY) == 2,
            string.format("owned %d, ledger %d", owned(player, BOBBY), runeCount(player, BOBBY))
    end)
    expectAddition(plan, "+2 damage for each Bobby", 2)
    expectBobbyTears(plan, "two Bobbies' tears", 2)
    plan.section("THURISAZ temporary: the temporary copy outlives its room")
    roomEntry(plan)
    plan.check("no Bobby comes back in the new room", function(player)
        return #ownFamiliars(player) == 0, #ownFamiliars(player) .. " familiars"
    end)
    expectTotal(plan, "the ledger still holds both", 2)
    expectAddition(plan, "damage stays", 2)
    expectBobbyTears(plan, "tears stay", 2)
end)

case("kronos", "the rune and Kronos together", function(plan)
    give(plan, { BOBBY })
    useRune(plan, 0)
    expectAddition(plan, "the rune's Bobby: +2 damage", 1)
    plan.section("THURISAZ kronos: picking up Kronos later")
    plan.act(function(player) player:AddCollectible(kronosId(), 0, false); player:AddCollectible(ANGEL, 0, false) end)
    plan.waitUntil(function(player) return K()._getAbsorbedCount(player, ANGEL) == 1, "Angel not absorbed yet" end,
        60, "Kronos absorbs Guardian Angel")
    plan.wait(4)
    plan.check("Kronos takes only its own familiar; the rune keeps Bobby", function(player)
        return runeCount(player, BOBBY) == 1 and K()._getAbsorbedCount(player, BOBBY) == 0
            and runeCount(player, ANGEL) == 0,
            string.format("rune Bobby %d, Kronos Bobby %d", runeCount(player, BOBBY), K()._getAbsorbedCount(player, BOBBY))
    end)
    expectAddition(plan, "both count: +4 damage", 2)
    plan.check("Kronos's Angel speed is on", function(player, ctx)
        return H.expect(player.MoveSpeed - ctx.base.Speed, K().STATS.GUARDIAN_ANGEL_SPEED)
    end)
    plan.section("THURISAZ kronos: Box of Friends doubles both under Kronos")
    plan.act(function(player) player:UseActiveItem(C.COLLECTIBLE_BOX_OF_FRIENDS, UseFlag.USE_NOANIM, -1) end)
    plan.wait(6)
    expectAddition(plan, "the room doubles every absorbed familiar", 4)
    expectBobbyTears(plan, "the rune's Bobby counts twice", 2)
    roomEntry(plan)
    expectAddition(plan, "the next room ends the doubling", 2)
    expectBobbyTears(plan, "one Bobby again", 1)
    plan.section("THURISAZ kronos: losing Kronos")
    plan.act(function(player) player:RemoveCollectible(kronosId()) end)
    plan.waitUntil(function(player) return owned(player, ANGEL) == 1, "Angel not back" end, 30,
        "Kronos hands back Guardian Angel")
    plan.wait(6)
    plan.check("the rune's Bobby is not handed back", function(player)
        return owned(player, BOBBY) == 0 and runeCount(player, BOBBY) == 1, "Bobby owned " .. owned(player, BOBBY)
    end)
    expectAddition(plan, "only the rune's damage is left", 1)
    expectBobbyTears(plan, "Bobby's tears stay without Kronos", 1)
    plan.check("Kronos's Angel speed is gone", function(player, ctx) return H.expect(player.MoveSpeed, ctx.base.Speed) end)
    plan.section("THURISAZ kronos: picking Kronos up again")
    plan.act(function(player) player:AddCollectible(kronosId(), 0, false) end)
    plan.waitUntil(function(player) return K()._getAbsorbedCount(player, ANGEL) == 1, "Angel not absorbed" end,
        60, "Kronos absorbs Guardian Angel again")
    plan.wait(4)
    expectAddition(plan, "both count again", 2)
    expectTotal(plan, "the rune's ledger never moved", 1)
end)

case("stand_ins", "an ability that needs a stand-in works without Kronos", function(plan)
    give(plan, { C.COLLECTIBLE_INCUBUS })
    plan.act(function(player, ctx)
        ctx.before = H.stats(player)
        player:UseCard(cardId(), UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
    end)
    plan.waitUntil(function(player)
        return #ownFamiliars(player) == 0 and standIns(player, FamiliarVariant.INCUBUS, "__kronosIncubus") == 1,
            #ownFamiliars(player) .. " familiars, " .. standIns(player, FamiliarVariant.INCUBUS, "__kronosIncubus") .. " stand-ins"
    end, 60, "the Incubus is devoured and its hidden stand-in follows the player")
    plan.check("Incubus is the rune's", function(player)
        return owned(player, C.COLLECTIBLE_INCUBUS) == 0 and runeCount(player, C.COLLECTIBLE_INCUBUS) == 1, "ledger"
    end)
    plan.section("THURISAZ stand_ins: a second rune never eats the stand-in",
        "an invisible Incubus keeps firing tears beside the player")
    plan.act(function(player) player:UseCard(cardId(), UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER) end)
    plan.wait(10)
    plan.check("the stand-in is still there and the ledger did not grow", function(player)
        return standIns(player, FamiliarVariant.INCUBUS, "__kronosIncubus") == 1 and runeTotal(player) == 1,
            "stand-ins " .. standIns(player, FamiliarVariant.INCUBUS, "__kronosIncubus") .. ", total " .. runeTotal(player)
    end)
    roomEntry(plan)
    plan.check("the stand-in follows into the next room", function(player)
        return standIns(player, FamiliarVariant.INCUBUS, "__kronosIncubus") == 1,
            standIns(player, FamiliarVariant.INCUBUS, "__kronosIncubus") .. " stand-ins"
    end)
end)

case("exclusions", "familiars Kronos never absorbs are left alone", function(plan)
    give(plan, { C.COLLECTIBLE_ISAACS_HEART, BOBBY })
    useRune(plan, 1)
    plan.check("Isaac's Heart stays, Bobby goes", function(player)
        return owned(player, C.COLLECTIBLE_ISAACS_HEART) == 1 and owned(player, BOBBY) == 0
            and runeCount(player, C.COLLECTIBLE_ISAACS_HEART) == 0,
            string.format("heart %d, Bobby %d", owned(player, C.COLLECTIBLE_ISAACS_HEART), owned(player, BOBBY))
    end)
    expectTotal(plan, "only Bobby is in the ledger", 1)
end)

case("conversion", "conversion items keep Kronos's limits", function(plan)
    local brain = C.COLLECTIBLE_BOBS_BRAIN
    give(plan, { brain, brain, ROBO })
    useRune(plan, 2)
    useRune(plan, 1)
    useRune(plan, 0)
    plan.check("two Bob's Brains give Ipecac once", function(player)
        return H.expect(owned(player, C.COLLECTIBLE_IPECAC), 1)
    end)
    plan.check("Robo-Baby gives Technology", function(player)
        return H.expect(owned(player, C.COLLECTIBLE_TECHNOLOGY), 1)
    end)
    plan.section("THURISAZ conversion: each further Robo-Baby gives another Technology")
    give(plan, { ROBO })
    useRune(plan, 0)
    plan.check("a second Technology", function(player) return H.expect(owned(player, C.COLLECTIBLE_TECHNOLOGY), 2) end)
    plan.check("still only one Ipecac", function(player) return H.expect(owned(player, C.COLLECTIBLE_IPECAC), 1) end)
    expectAddition(plan, "+2 damage for each of the four", 4)
end)

case("gb_bug", "GB Bug is just another familiar to the rune", function(plan)
    give(plan, { C.COLLECTIBLE_GB_BUG, BOBBY, ANGEL })
    useRune(plan, 2)
    useRune(plan, 1)
    useRune(plan, 0)
    plan.wait(10)
    plan.check("nothing is handed back", function(player)
        local back = owned(player, C.COLLECTIBLE_GB_BUG) + owned(player, BOBBY) + owned(player, ANGEL)
        return back == 0 and #ownFamiliars(player) == 0, back .. " returned"
    end)
    expectTotal(plan, "all three are the rune's", 3)
    expectAddition(plan, "+6 damage", 3)
end)

case("clear_rune", "Clear Rune copies Thurisaz from the pocket", function(plan)
    plan.act(function(player) player:AddCard(cardId()) end)
    plan.require("Thurisaz sits in the pocket", function(player)
        return player:GetCard(0) == cardId(), "pocket card " .. tostring(player:GetCard(0))
    end)
    give(plan, { BOBBY })
    plan.act(function(player) player:UseActiveItem(C.COLLECTIBLE_CLEAR_RUNE, UseFlag.USE_NOANIM, -1) end)
    plan.waitUntil(function(player) return #ownFamiliars(player) == 0, #ownFamiliars(player) .. " left" end,
        30, "Clear Rune's copy devours Bobby")
    expectTotal(plan, "the copy fed the ledger", 1)
    plan.check("the rune itself stays in the pocket", function(player)
        return player:GetCard(0) == cardId(), "pocket card " .. tostring(player:GetCard(0))
    end)
end)

case("card", "the card is registered as a rune", function(plan)
    plan.check("pocketitems.xml entry", function()
        local config = Isaac.GetItemConfig():GetCard(cardId())
        if not config then return false, "no card config" end
        return config.Name == "Thurisaz" and config.Description == "Devour" and config.MimicCharge == 6
            and config.PickupSubtype == 7781 and config.HudAnim == "Thurisaz",
            string.format("name=%s desc=%s charge=%s pickup=%s hud=%s", tostring(config.Name),
                tostring(config.Description), tostring(config.MimicCharge), tostring(config.PickupSubtype),
                tostring(config.HudAnim))
    end)
    plan.check("its card type is rune", function()
        local config = Isaac.GetItemConfig():GetCard(cardId())
        if not (config and type(config.CardType) == "number" and ItemConfig and type(ItemConfig.CARDTYPE_RUNE) == "number") then
            return nil, "this build exposes no card type"
        end
        return config.CardType == ItemConfig.CARDTYPE_RUNE, "CardType " .. tostring(config.CardType)
    end)
    plan.section("THURISAZ card: in the pocket", "the pocket slot shows the dark stone with the gold sign and its name")
    plan.act(function(player) player:AddCard(cardId()) end)
    plan.wait(30)
    plan.check("the pocket holds Thurisaz", function(player)
        return player:GetCard(0) == cardId(), "pocket card " .. tostring(player:GetCard(0))
    end)
end)

case("drop", "dropping it from the pocket", function(plan)
    plan.act(function(player, ctx)
        player:AddCard(cardId())
        ctx.dropAt = Game():GetRoom():FindFreePickupSpawnPosition(player.Position + Vector(100, 0), 0, true)
    end)
    plan.wait(4)
    plan.section("THURISAZ drop: the toss",
        "it springs up from the floor, tumbles, lands squashed with a thud, rebounds once and its red glow lights as it lands")
    plan.act(function(player, ctx)
        ctx.animations = {}
        player:DropPocketItem(0, ctx.dropAt)
    end)
    plan.waitUntil(function(_, ctx)
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, cardId())) do
            ctx.pickup = entity:ToPickup()
        end
        return ctx.pickup ~= nil, "no Thurisaz pickup yet"
    end, 30, "the dropped rune lies in the room")
    plan.waitUntil(function(_, ctx)
        local sprite = ctx.pickup:GetSprite()
        for _, name in ipairs({ "Appear", "Idle" }) do
            if sprite:IsPlaying(name) then ctx.animations[name] = true end
        end
        return ctx.animations.Idle == true, "not idle yet"
    end, 90, "the dropped rune settles into Idle")
    plan.check("it uses the rune's own animation file", function(_, ctx)
        local name = ctx.pickup:GetSprite():GetFilename()
        return tostring(name):lower():find("005.300_thurisaz.anm2", 1, true) ~= nil, tostring(name)
    end)
    plan.note("animations seen", function(_, ctx)
        return "Appear=" .. tostring(ctx.animations.Appear == true) .. " Idle=" .. tostring(ctx.animations.Idle == true)
    end)
    plan.act(function(_, ctx) if ctx.pickup and ctx.pickup:Exists() then ctx.pickup:Remove() end end)
end)


-- Natural drops: the game's own random card draws, which room rewards, chests
-- and rune drops use. A share above zero means it is in the pool.
case("pool", "it turns up among the game's random runes", function(plan)
    local ROLLS = 4000
    plan.check("random rune draws can give Thurisaz", function()
        local pool, hits = Game():GetItemPool(), 0
        for seed = 1, ROLLS do
            if pool:GetCard(seed, false, true, true) == cardId() then hits = hits + 1 end
        end
        return hits > 0, string.format("%d of %d rolls", hits, ROLLS)
    end)
    plan.check("ordinary card drops can give it too", function()
        local pool, hits = Game():GetItemPool(), 0
        for seed = 1, ROLLS do
            if pool:GetCard(seed, true, true, false) == cardId() then hits = hits + 1 end
        end
        return hits > 0, string.format("%d of %d rolls", hits, ROLLS)
    end)
end)

-- ---------------------------------------------------------------- manual helpers
local HELPERS = {
    give = function(words, player)
        local n = math.max(1, math.min(4, math.floor(tonumber(words[3]) or 1)))
        for _ = 1, n do player:AddCard(cardId()) end
        out(string.format("Gave %d Thurisaz (card %d) to the pocket.", n, cardId()))
    end,
    spawn = function(_, player)
        local at = Game():GetRoom():FindFreePickupSpawnPosition(player.Position + Vector(80, 0), 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, cardId(), at, Vector.Zero, nil)
        out("Spawned a Thurisaz rune beside the player.")
    end,
    familiars = function(_, player)
        for _, id in ipairs({ BOBBY, ANGEL, ROBO, C.COLLECTIBLE_INCUBUS }) do player:AddCollectible(id, 0, false) end
        player:AddBlueFlies(2, player.Position, nil)
        out("Gave Brother Bobby, Guardian Angel, Robo-Baby, Incubus and two blue flies.")
    end,
    ledger = function()
        local game = Game()
        for i = 0, game:GetNumPlayers() - 1 do
            local player = game:GetPlayer(i)
            local ledger = ConchBlessing.SaveManager.GetRunSave(player).thurisaz
            local kinds = {}
            for key, count in pairs(ledger and ledger.absorbed or {}) do kinds[#kinds + 1] = key .. "=" .. tostring(count) end
            table.sort(kinds)
            local grants = {}
            for key, count in pairs(ledger and ledger.grants or {}) do grants[#grants + 1] = key .. "=" .. tostring(count) end
            table.sort(grants)
            out(string.format("Player %d: rune total %d, generic %s, familiars {%s}, grants {%s}, Kronos %s, damage +%.2f",
                i + 1, runeTotal(player), tostring(ledger and ledger.generic or 0), table.concat(kinds, ", "),
                table.concat(grants, ", "), tostring(player:HasCollectible(kronosId())), damageAddition(player)))
        end
    end,
}

function Probe.commands()
    local list = {}
    for _, name in ipairs(Probe.order) do list[#list + 1] = Probe.cases[name] end
    return list
end

function Probe.commandFor(name) return Probe.cases[name] end

function Probe.isHelper(name) return HELPERS[name] ~= nil end

--- Runs a manual helper; words are the lower-case console words after conch_test.
function Probe.helper(name, words, player)
    if not player then out("Start a run first.") return end
    HELPERS[name](words, player)
end

function Probe.list()
    local lines = { "conch_test thurisaz  -> every case below, each from a clean run" }
    for _, name in ipairs(Probe.order) do lines[#lines + 1] = "  " .. Probe.cases[name] end
    lines[#lines + 1] = "Manual helpers on the current run: conch_test thurisaz give [N] | spawn | familiars | ledger"
    lines[#lines + 1] = "Continue check: devour, save and quit, continue, then conch_test thurisaz ledger"
    return lines
end

return Probe
