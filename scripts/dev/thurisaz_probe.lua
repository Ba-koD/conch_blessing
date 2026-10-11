-- conch_test thurisaz: the Kronos rune, used for real through EntityPlayer:UseCard.
-- It devours up to three of the user's familiars for good: +2 damage each plus
-- the familiar's absorbed ability, with or without Kronos, and Kronos's loss
-- never hands them back. Fully automatic; the results land in log.txt.
local TestBench = require("scripts.dev.test_bench")
local H = require("scripts.dev.item_test_support")

local BOBBY = CollectibleType.COLLECTIBLE_BROTHER_BOBBY
local ANGEL = CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL
local ROBO = CollectibleType.COLLECTIBLE_ROBO_BABY
local HAUNT = CollectibleType.COLLECTIBLE_LIL_HAUNT
local DEVOURED = { BOBBY, ANGEL, ROBO }

local function kronosId() return ConchBlessing.ItemData.KRONOS.id end
local function cardId() return ConchBlessing.PocketData and ConchBlessing.PocketData.THURISAZ.id or -1 end
local function perFamiliar() return ConchBlessing.kronos.STATS.DAMAGE_PER_FAMILIAR end
local function damageAddition(player) return H.addition(player, "itemAdditions", kronosId(), "Damage") end

-- The player's live familiars in the room, Kronos's own stand-ins excluded.
local function ownFamiliars(player)
    local list = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, -1, -1)) do
        local fam = entity:ToFamiliar()
        if fam and fam:Exists() and fam.Player and GetPtrHash(fam.Player) == GetPtrHash(player) then
            local stand = false
            for key in pairs(fam:GetData()) do
                if type(key) == "string" and key:find("^__kronos") then stand = true end
            end
            if not stand then list[#list + 1] = fam end
        end
    end
    return list
end

local function useRune(player)
    player:UseCard(cardId(), UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
end

local function expectAddition(plan, label, copies)
    plan.check(label, function(player)
        return H.expect(damageAddition(player), copies * perFamiliar())
    end)
end

local function build(plan)
    plan.section("THURISAZ setup")
    plan.waitUntil(function(player)
        return player:Exists() and ConchBlessing.SaveManager.GetRunSave(player) ~= nil
    end, 60, "player and run save ready")
    plan.require("the rune is registered and its card ID resolves", function()
        return cardId() > 0 and type(ConchBlessing.kronos.devourWithRune) == "function",
            "card id " .. tostring(cardId())
    end)
    plan.act(function(player, ctx)
        assert(Game():GetNumPlayers() == 1 and player:GetPlayerType() == PlayerType.PLAYER_ISAAC,
            "single-player Isaac test run required")
        player.Position = Game():GetRoom():GetCenterPos()
        ctx.base = H.stats(player)
        for _, id in ipairs(DEVOURED) do player:AddCollectible(id, 0, false) end
    end)
    plan.waitUntil(function(player)
        local live = #ownFamiliars(player)
        return live == #DEVOURED, live .. " familiars"
    end, 60, "the three familiars follow the player")
    plan.act(function(player, ctx)
        H.refresh(player)
        ctx.before = H.stats(player)
    end)

    plan.section("THURISAZ / devours three familiars without Kronos",
        "a puff of smoke where each familiar was, and its icon dissolves into the player")
    plan.act(function(player) useRune(player) end)
    plan.waitUntil(function(player) return #ownFamiliars(player) == 0, #ownFamiliars(player) .. " left" end,
        30, "the devoured familiars leave the room")
    plan.check("all three familiar collectibles are gone from the inventory", function(player)
        local left = {}
        for _, id in ipairs(DEVOURED) do
            if player:GetCollectibleNum(id, true) > 0 then left[#left + 1] = tostring(id) end
        end
        return #left == 0, #left == 0 and "none left" or "still owned: " .. table.concat(left, ",")
    end)
    plan.check("the rune's ledger holds each of them once", function(player)
        local counts = {}
        for _, id in ipairs(DEVOURED) do counts[#counts + 1] = ConchBlessing.kronos.getRuneCount(player, id) end
        return ConchBlessing.kronos.getRuneTotal(player) == 3 and counts[1] == 1 and counts[2] == 1 and counts[3] == 1,
            "total " .. ConchBlessing.kronos.getRuneTotal(player) .. ", each " .. table.concat(counts, ",")
    end)
    expectAddition(plan, "+2 damage per devoured familiar in StatsAPI", 3)
    plan.check("the displayed damage rose", function(player, ctx)
        return player.Damage > ctx.before.Damage + 1, string.format("%.2f -> %.2f", ctx.before.Damage, player.Damage)
    end)
    plan.check("Brother Bobby's ability: +2 tears a second", function(player, ctx)
        local gain = H.stats(player).Tears - ctx.before.Tears
        return math.abs(gain - ConchBlessing.kronos.STATS.BROTHER_BOBBY_TEARS) < 0.05, string.format("+%.3f", gain)
    end)
    plan.check("Guardian Angel's ability: +0.3 speed", function(player, ctx)
        return H.expect(player.MoveSpeed - ctx.before.Speed, ConchBlessing.kronos.STATS.GUARDIAN_ANGEL_SPEED)
    end)
    plan.check("Robo-Baby turns into Technology", function(player)
        return player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY), "Technology owned"
    end)
    plan.check("Kronos's own ledger is untouched", function(player)
        return ConchBlessing.kronos._getAbsorbedCount(player, BOBBY) == 0, "Kronos Bobby "
            .. ConchBlessing.kronos._getAbsorbedCount(player, BOBBY)
    end)

    plan.section("THURISAZ / with no familiar left nothing changes")
    plan.act(function(player, ctx) ctx.stats = H.stats(player); useRune(player) end)
    plan.wait(10)
    plan.check("the ledger stays at three", function(player)
        return H.expect(ConchBlessing.kronos.getRuneTotal(player), 3)
    end)
    plan.check("no stat moved", function(player, ctx) return H.sameStats(player, ctx.stats) end)

    plan.section("THURISAZ / familiars with no item give the flat damage", "two blue flies vanish in smoke")
    plan.act(function(player) player:AddBlueFlies(2, player.Position, nil) end)
    plan.waitUntil(function(player) return #ownFamiliars(player) == 2, #ownFamiliars(player) .. " flies" end,
        30, "two blue flies")
    plan.act(function(player) useRune(player) end)
    plan.waitUntil(function(player) return #ownFamiliars(player) == 0, #ownFamiliars(player) .. " left" end,
        30, "the blue flies are devoured")
    plan.check("the ledger counts them as familiars with no item", function(player)
        local ledger = H.save(player).thurisaz or {}
        return ledger.generic == 2 and ConchBlessing.kronos.getRuneTotal(player) == 5,
            "generic " .. tostring(ledger.generic) .. ", total " .. ConchBlessing.kronos.getRuneTotal(player)
    end)
    expectAddition(plan, "+2 damage each, five in all", 5)

    plan.section("THURISAZ / Kronos's loss keeps the rune's familiars")
    plan.act(function(player, ctx)
        ctx.withRune = H.stats(player)
        player:AddCollectible(kronosId(), 0, false)
        player:AddCollectible(HAUNT, 0, false)
    end)
    plan.waitUntil(function(player)
        return ConchBlessing.kronos._getAbsorbedCount(player, HAUNT) == 1, "Kronos has not absorbed Lil Haunt"
    end, 60, "Kronos absorbs Lil Haunt")
    expectAddition(plan, "Kronos's familiar adds to the rune's", 6)
    plan.act(function(player) player:RemoveCollectible(kronosId()) end)
    plan.wait(10)
    plan.check("Kronos hands back its own familiar", function(player)
        return H.expect(player:GetCollectibleNum(HAUNT, true), 1)
    end)
    plan.check("the rune's familiars are not handed back", function(player)
        local back = 0
        for _, id in ipairs(DEVOURED) do back = back + player:GetCollectibleNum(id, true) end
        return back == 0 and ConchBlessing.kronos.getRuneTotal(player) == 5, back .. " returned"
    end)
    expectAddition(plan, "the rune's damage stays", 5)
    plan.check("the rune's abilities stay", function(player, ctx)
        return H.expect(player.MoveSpeed, ctx.withRune.Speed)
    end)
    plan.check("Continue keeps the rune's familiars", function()
        return nil, "needs a real save and continue, which a bench cannot perform"
    end)
end

TestBench.register({
    command = "conch_test thurisaz",
    tag = "ThurisazProbe",
    duration = "about 10 seconds",
    restartCommand = "restart 0",
    cleanup = H.cleanup,
    build = build,
})

return {}
