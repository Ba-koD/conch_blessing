local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- cb test player_reset: a measurement, not a check of this mod. It records what
-- REPENTOGON's EntityPlayer:ResetPlayer() (the routine Genesis uses) puts back
-- to a fresh run's state, to decide whether shared-run benches can reset the
-- player with it instead of restarting. Every field is printed as a DIAG line
-- with fresh-run, dirtied and after-reset values; a CHECK line per field says
-- whether the reset matched the fresh run.
local TestBench = require("scripts.dev.test_bench")
local H = require("scripts.dev.item_test_support")

local GROUP = "ConchBlessingResetProbe"

local function try(fn, ...)
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return "n/a"
end

local function collectibles(player)
    local rows = {}
    for id = 1, Isaac.GetItemConfig():GetCollectibles().Size - 1 do
        local n = player:GetCollectibleNum(id, true)
        if n > 0 then rows[#rows + 1] = id .. "x" .. n end
    end
    return table.concat(rows, ",")
end

local function effects(player)
    local rows = {}
    local list = try(function() return player:GetEffects():GetEffectsList() end)
    if type(list) ~= "userdata" and type(list) ~= "table" then return tostring(list) end
    for i = 0, list.Size - 1 do
        local e = list:Get(i)
        if e and e.Item and e.Count > 0 then rows[#rows + 1] = e.Item.Type .. ":" .. e.Item.ID .. "x" .. e.Count end
    end
    table.sort(rows)
    return table.concat(rows, ",")
end

local function smelted(player)
    local rows = {}
    local list = try(function() return player:GetSmeltedTrinkets() end)
    if type(list) ~= "table" then return tostring(list) end
    for id, entry in pairs(list) do
        local normal = type(entry) == "table" and (entry.trinketAmount or entry[1]) or entry
        local gold = type(entry) == "table" and (entry.goldenTrinketAmount or entry[2]) or 0
        if (tonumber(normal) or 0) > 0 or (tonumber(gold) or 0) > 0 then rows[#rows + 1] = id .. ":" .. tostring(normal) .. "/" .. tostring(gold) end
    end
    table.sort(rows)
    return table.concat(rows, ",")
end

local function forms(player)
    local rows = {}
    for name, id in pairs(PlayerForm or {}) do
        if type(id) == "number" and name:match("^PLAYERFORM_") then
            local count = try(player.GetPlayerFormCounter, player, id)
            if player:HasPlayerForm(id) or (tonumber(count) or 0) > 0 then
                rows[#rows + 1] = name:sub(12) .. "=" .. tostring(count) .. (player:HasPlayerForm(id) and "!" or "")
            end
        end
    end
    table.sort(rows)
    return table.concat(rows, ",")
end

local function familiars(player)
    local n = 0
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        local f = e:ToFamiliar()
        if f and f.Player and GetPtrHash(f.Player) == GetPtrHash(player) then n = n + 1 end
    end
    return n
end

local function pickups()
    local n = 0
    for _, e in ipairs(Isaac.GetRoomEntities()) do if e.Type == EntityType.ENTITY_PICKUP then n = n + 1 end end
    return n
end

local FIELDS = {
    { "collectibles", collectibles },
    { "history", function(p) return try(function() return #p:GetHistory():GetCollectiblesHistory() end) end },
    { "active slots", function(p)
        local rows = {}
        for slot = 0, 3 do rows[#rows + 1] = p:GetActiveItem(slot) .. "/" .. p:GetActiveCharge(slot) end
        return table.concat(rows, " ")
    end },
    { "held trinkets", function(p) return p:GetTrinket(0) .. "," .. p:GetTrinket(1) end },
    { "smelted trinkets", smelted },
    { "innate trinket (probe group)", function(p)
        return try(p.GetInnateTrinketCount, p, TrinketType.TRINKET_PUSH_PIN, GROUP)
    end },
    { "innate collectible count", function(p)
        return try(function() return p:GetCollectibleNum(CollectibleType.COLLECTIBLE_SPOON_BENDER, false) end)
    end },
    { "pocket", function(p) return p:GetCard(0) .. "," .. p:GetPill(0) .. "," .. p:GetCard(1) .. "," .. p:GetPill(1) end },
    { "coins/bombs/keys/giga", function(p)
        return p:GetNumCoins() .. "/" .. p:GetNumBombs() .. "/" .. p:GetNumKeys() .. "/" .. tostring(try(p.GetNumGigaBombs, p))
            .. (p:HasGoldenKey() and " goldenKey" or "") .. (p:HasGoldenBomb() and " goldenBomb" or "")
    end },
    { "hearts red/max/soul/black/bone/golden/eternal/broken/rotten", function(p)
        return table.concat({ p:GetHearts(), p:GetMaxHearts(), p:GetSoulHearts(), p:GetBlackHearts(), p:GetBoneHearts(),
            p:GetGoldenHearts(), p:GetEternalHearts(), p:GetBrokenHearts(), p:GetRottenHearts() }, "/")
    end },
    { "extra lives", function(p) return p:GetExtraLives() end },
    { "stats", function(p)
        local s = H.stats(p)
        return string.format("dmg %.3f tears %.3f range %.3f luck %.3f speed %.3f shot %.3f", s.Damage, s.Tears,
            s.Range, s.Luck, s.Speed, s.ShotSpeed)
    end },
    { "tear flags / flight", function(p) return tostring(p.TearFlags) .. " fly=" .. tostring(p.CanFly) end },
    { "transformations", forms },
    { "temporary effects", effects },
    { "familiars in room", familiars },
    { "pickups in room", function() return pickups() end },
    { "player type", function(p) return p:GetPlayerType() end },
    { "player pointer", function(p) return GetPtrHash(p) end },
    { "run save present", function(p) return tostring(ConchBlessing.SaveManager.GetRunSave(p) ~= nil) end },
}

local function snapshot(player)
    local row = {}
    for _, field in ipairs(FIELDS) do row[field[1]] = tostring(field[2](player)) end
    return row
end

local function register(command, title, reset, settle)
TestBench.register({
    command = command, tag = "PlayerReset", restartCommand = "restart 0",
    duration = "a few seconds (a measurement)", cleanup = H.cleanup,
    build = function(plan)
        plan.section("player_reset / fresh run")
        plan.wait(4)
        plan.act(function(player, ctx) ctx.fresh = snapshot(player) end)
        plan.section("player_reset / dirty the player")
        plan.act(function(player)
            for _, id in ipairs({ CollectibleType.COLLECTIBLE_SAD_ONION, CollectibleType.COLLECTIBLE_BROTHER_BOBBY,
                CollectibleType.COLLECTIBLE_BFFS, CollectibleType.COLLECTIBLE_BOBS_CURSE, CollectibleType.COLLECTIBLE_IPECAC,
                CollectibleType.COLLECTIBLE_BOBS_ROTTEN_HEAD, CollectibleType.COLLECTIBLE_DEAD_CAT,
                CollectibleType.COLLECTIBLE_TRANSCENDENCE }) do
                player:AddCollectible(id, 0, true)
            end
            player:AddCollectible(CollectibleType.COLLECTIBLE_YUM_HEART, 4, true, ActiveSlot.SLOT_POCKET)
            pcall(player.AddInnateCollectible, player, CollectibleType.COLLECTIBLE_SPOON_BENDER, 1)
            player:AddTrinket(TrinketType.TRINKET_SWALLOWED_PENNY)
            pcall(player.AddSmeltedTrinket, player, TrinketType.TRINKET_PETRIFIED_POOP, false)
            pcall(player.AddInnateTrinket, player, TrinketType.TRINKET_PUSH_PIN, 1, GROUP, -1, false)
            player:SetCard(0, Card.CARD_FOOL)
            player:AddCoins(15); player:AddBombs(5); player:AddKeys(3)
            pcall(player.AddGigaBombs, player, 1)
            player:AddGoldenKey()
            player:AddMaxHearts(2); player:AddHearts(2)
            player:AddSoulHearts(4); player:AddBlackHearts(2); player:AddGoldenHearts(1)
            player:AddEternalHearts(1); player:AddBrokenHearts(1)
            player:GetEffects():AddCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE, false)
            player:AddCacheFlags(CacheFlag.CACHE_ALL); player:EvaluateItems()
        end)
        plan.wait(6)
        plan.act(function(player, ctx) ctx.dirty = snapshot(player) end)
        plan.section("player_reset / after " .. title)
        plan.act(function(player, ctx) ctx.roomsBefore = ctx.rooms; reset(player) end)
        settle(plan)
        plan.note("room loads during the reset", function(_, ctx)
            local level = Game():GetLevel()
            return string.format("%d room loads; now stage %d room %d", ctx.rooms - ctx.roomsBefore, level:GetStage(),
                level:GetCurrentRoomIndex())
        end)
        for _, field in ipairs(FIELDS) do
            local name = field[1]
            plan.note(name, function(player, ctx)
                return string.format("fresh=[%s] dirty=[%s] reset=[%s]", ctx.fresh[name], ctx.dirty[name],
                    tostring(field[2](player)))
            end)
        end
        for _, field in ipairs(FIELDS) do
            local name = field[1]
            plan.check("reset matches the fresh run: " .. name, function(player, ctx)
                local now = tostring(field[2](player))
                return now == ctx.fresh[name], "fresh=[" .. ctx.fresh[name] .. "] reset=[" .. now .. "]"
            end)
        end
    end,
})
end

register("cb test player_reset", "EntityPlayer:ResetPlayer()", function(player) player:ResetPlayer() end,
    function(plan) plan.wait(6) end)
-- Glowing Hourglass's own rewind, used from the fresh run's first room.
register("cb test player_reset hourglass", "Glowing Hourglass", function(player)
    player:UseActiveItem(CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS, UseFlag.USE_NOANIM, -1)
end, function(plan)
    plan.act(function(_, ctx) ctx.rewindWait = 0 end)
    plan.waitUntil(function(_, ctx)
        ctx.rewindWait = ctx.rewindWait + 1
        return ctx.rooms > ctx.roomsBefore or ctx.rewindWait >= 90
    end, 91, "the rewind loads a room (or three seconds pass)")
    plan.wait(10)
end)
