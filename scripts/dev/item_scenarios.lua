local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Isolated behavior scenarios appended to cb test's lifecycle matrix.
local Bench = require("scripts.dev.test_bench")
local H = require("scripts.dev.item_test_support")
local Isolation = require("scripts.dev.test_isolation")
local S = { rows = {}, coverage = {} }

function S.add(key, name, groups, build, synergyNames)
    local parameter = name:gsub("^synergy_", "")
    local command = "cb test " .. string.lower(key) .. " " .. parameter
    local row = { key = key, name = parameter, command = command, groups = groups, build = build }
    local reusable,resetReason = Isolation.scenario(key,parameter)
    S.rows[#S.rows + 1] = row
    for _, synergy in ipairs(synergyNames or {}) do
        S.coverage[key] = S.coverage[key] or {}
        S.coverage[key][synergy] = command
    end
    Bench.register({ command = command, tag = "ItemTest:" .. key,
        reuseGroup = reusable and Isolation.group(key) or nil, resetReason=resetReason,
        restartCommand = "restart 0", cleanup = H.cleanup, build = function(plan)
            if reusable then Isolation.begin(plan,key=="KRONOS") end
            plan.section(key .. " / " .. name)
            plan.waitUntil(function(player)
                return player:Exists() and ConchBlessing.SaveManager.GetRunSave(player) ~= nil
            end, 60, "player and run save ready")
            plan.act(function(player, ctx)
                assert(Game():GetNumPlayers() == 1 and player:GetPlayerType() == PlayerType.PLAYER_ISAAC,
                    "single-player Isaac test run required")
                local active = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
                if active > 0 then player:RemoveCollectible(active, true, ActiveSlot.SLOT_PRIMARY) end
                for slot = 0, 1 do
                    local trinket = player:GetTrinket(slot)
                    if trinket > 0 then player:TryRemoveTrinket(trinket) end
                end
                player.Position = Game():GetRoom():GetCenterPos()
                ctx.base = H.stats(player)
            end)
            build(plan, ConchBlessing.ItemData[key].id)
            if reusable then Isolation.finish(plan,key,ConchBlessing.ItemData[key].id) end
        end })
    return command
end

function S.commands(key, group)
    local list, seen = {}, {}
    for _, row in ipairs(S.rows) do
        -- A manual row (a measurement, not a check) runs only when named.
        if (not key or row.key == key) and (not group or row.groups[group]) and not row.manual then
            local command = row.bundledInto or row.command
            if not seen[command] then list[#list + 1] = command; seen[command] = true end
        end
    end
    table.sort(list,function(a,b)
        local aReuse,bReuse=Bench.get(a).reuseGroup~=nil,Bench.get(b).reuseGroup~=nil
        if aReuse~=bReuse then return aReuse end
        if aReuse and Bench.get(a).reuseGroup~=Bench.get(b).reuseGroup then
            return Bench.get(a).reuseGroup<Bench.get(b).reuseGroup
        end
        return a<b
    end)
    return list
end

-- A bundle exercises its members together in one isolated run. Original cases
-- remain directly callable for diagnosis but never repeat in the default suite.
function S.bundle(key, name, groups, build, members)
    local command = S.add(key, name, groups, build)
    Bench.get(command).retryMembers={}
    for _, member in ipairs(members) do
        local found
        for _, row in ipairs(S.rows) do
            if row.key == key and row.name == member then
                assert(not row.bundledInto, "scenario already bundled: " .. member)
                for group, enabled in pairs(row.groups) do
                    if enabled then assert(groups[group], "bundle drops group " .. group) end
                end
                row.bundledInto, found = command, true
                table.insert(Bench.get(command).retryMembers,row.command)
            end
        end
        assert(found, "unknown bundle member: " .. member)
    end
    return command
end

-- One run, separate contexts, and explicit production cleanup between cases.
-- The supplied boundary must abort on an un-restored baseline; never hide a
-- failed cleanup by deleting item saves or overwriting provider stat tables.
function S.sequenceBundle(key, name, groups, members, before, after)
    local builders = {}
    for _, member in ipairs(members) do
        for _, row in ipairs(S.rows) do
            if row.key==key and row.name==member then builders[#builders+1]={name=member,build=row.build}; break end
        end
    end
    assert(#builders==#members,"missing sequential bundle member")
    return S.bundle(key,name,groups,function(plan,id)
        for index, child in ipairs(builders) do
            plan.act(function(_,ctx)
                ctx.retryCommand="cb test "..string.lower(key).." "..child.name
                -- ctx.rooms stays live (a case waits on it growing); `bundle`
                -- is the shared run's own context, where S.resetPlayer keeps
                -- the baseline every case starts from.
                local parent=ctx
                ctx.caseCtx=setmetatable({cleanupFns={},bundle=parent},{__index=function(_,field)
                    if field=="rooms" then return parent.rooms end
                end})
                ctx.bundleRemaining={}
                for i=index+1,#builders do ctx.bundleRemaining[#ctx.bundleRemaining+1]=key.." / "..builders[i].name end
            end)
            local scoped={}
            for _,method in ipairs({"act","note","wait","waitUntil","section","check","require","eq","atLeast"}) do
                if type(plan[method])=="function" then
                    local operation=plan[method]
                    scoped[method]=function(...)
                        local args={...}
                        for i,arg in ipairs(args) do
                            if type(arg)=="function" then
                                local body=arg
                                args[i]=function(player,ctx) return body(player,ctx.caseCtx) end
                            end
                        end
                        return operation(table.unpack(args))
                    end
                end
            end
            scoped.section(key.." / "..child.name)
            if before then before(scoped,id) end
            child.build(scoped,id)
            if after then after(scoped,id) end
            plan.act(function(_,ctx)
                H.cleanup(ctx.caseCtx);ctx.caseCtx=nil
                ctx.completedRetryCommands=ctx.completedRetryCommands or {}
                ctx.completedRetryCommands[ctx.retryCommand]=true
                ctx.retryCommand=nil
            end)
        end
    end,members)
end

-- ---------------------------------------------------------------- shared runs
-- There is no engine call that puts a run or a player back the way a restart
-- does (measured 2026-11-19 with cb test player_reset: REPENTOGON's
-- EntityPlayer:ResetPlayer() only re-applies the starting loadout, and Glowing
-- Hourglass from a run's first room goes to Home and restores no inventory).
-- So a shared run puts the player back between cases through the engine's own
-- removal calls, which run every item's real loss callbacks, and then proves
-- the result against what the run held when the shared run began.

local function heldCollectibles(player)
    local rows = {}
    for id = 1, Isaac.GetItemConfig():GetCollectibles().Size - 1 do
        local n = player:GetCollectibleNum(id, true)
        if n > 0 then rows[id] = n end
    end
    return rows
end

local function smeltedList(player)
    local rows = {}
    if type(player.GetSmeltedTrinkets) ~= "function" then return rows end
    local ok, list = pcall(player.GetSmeltedTrinkets, player)
    if not ok or type(list) ~= "table" then return rows end
    for id, entry in pairs(list) do
        if type(entry) == "table" then
            local normal, gold = tonumber(entry.trinketAmount) or 0, tonumber(entry.goldenTrinketAmount) or 0
            if normal > 0 or gold > 0 then rows[#rows + 1] = { id = id, normal = normal, gold = gold } end
        end
    end
    return rows
end

local function effectCount(player)
    local effects = player:GetEffects()
    if type(effects.GetEffectsList) ~= "function" then return 0 end
    local list, n = effects:GetEffectsList(), 0
    for i = 0, list.Size - 1 do
        local e = list:Get(i)
        if e and e.Count > 0 then n = n + 1 end
    end
    return n
end

local function ownFamiliars(player)
    local n = 0
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local fam = entity:ToFamiliar()
        if fam and fam:Exists() and fam.Player and GetPtrHash(fam.Player) == GetPtrHash(player) then n = n + 1 end
    end
    return n
end

local function playerState(player)
    return { counts = heldCollectibles(player), coins = player:GetNumCoins(), bombs = player:GetNumBombs(),
        keys = player:GetNumKeys(), maxHearts = player:GetMaxHearts(), stats = H.stats(player) }
end

-- Why the player is not back at `base`, or nil when it is.
local function baselineGap(player, base)
    local now = heldCollectibles(player)
    for id, n in pairs(now) do
        if base.counts[id] ~= n then return string.format("collectible %d held %d, baseline %d", id, n, base.counts[id] or 0) end
    end
    for id, n in pairs(base.counts) do
        if now[id] ~= n then return string.format("collectible %d held %d, baseline %d", id, now[id] or 0, n) end
    end
    for slot = 0, 1 do
        if player:GetTrinket(slot) ~= 0 then return "trinket " .. player:GetTrinket(slot) .. " in hand" end
    end
    local smelted = smeltedList(player)[1]
    if smelted then return string.format("smelted trinket %d (%d/%d)", smelted.id, smelted.normal, smelted.gold) end
    for slot = 0, 3 do
        if player:GetCard(slot) ~= 0 or player:GetPill(slot) ~= 0 then return "pocket item in slot " .. slot end
    end
    if player:GetNumCoins() ~= base.coins or player:GetNumBombs() ~= base.bombs or player:GetNumKeys() ~= base.keys then
        return string.format("coins/bombs/keys %d/%d/%d, baseline %d/%d/%d", player:GetNumCoins(), player:GetNumBombs(),
            player:GetNumKeys(), base.coins, base.bombs, base.keys)
    end
    if player:GetMaxHearts() ~= base.maxHearts or player:GetHearts() ~= base.maxHearts or player:GetSoulHearts() ~= 0
        or player:GetBoneHearts() ~= 0 or player:GetGoldenHearts() ~= 0 or player:GetEternalHearts() ~= 0
        or player:GetBrokenHearts() ~= 0 or player:GetRottenHearts() ~= 0 then
        return string.format("hearts red %d/%d soul %d bone %d golden %d eternal %d broken %d rotten %d, baseline %d full red",
            player:GetHearts(), player:GetMaxHearts(), player:GetSoulHearts(), player:GetBoneHearts(),
            player:GetGoldenHearts(), player:GetEternalHearts(), player:GetBrokenHearts(), player:GetRottenHearts(),
            base.maxHearts)
    end
    if player:GetExtraLives() ~= 0 then return "extra lives " .. player:GetExtraLives() end
    if effectCount(player) ~= 0 then return effectCount(player) .. " temporary effects remain" end
    if ownFamiliars(player) ~= 0 then return ownFamiliars(player) .. " familiars remain" end
    local same, detail = H.sameStats(player, base.stats)
    if not same then return "stats: " .. detail end
    if player:IsDead() then return "player dead" end
    if not player:IsItemQueueEmpty() then return "item queue not empty" end
end

-- Puts the player back between the cases of a shared run (the `before` of
-- S.sequenceBundle), then requires the proof. The first call records the
-- baseline: it runs right after S.add's preamble on a fresh run. `extra(player,
-- ctx)` removes what the file's cases leave that this does not know about (its
-- own entities, its item's floor pickups); `ready(player, ctx)` may add a
-- file-specific condition (returns ok, detail). ctx.base is set again for the
-- case, as S.add's preamble does.
function S.resetPlayer(plan, extra, ready)
    plan.act(function(player, ctx)
        local shared = ctx.bundle or ctx
        H.stopShooting()
        if not shared.sharedBase then shared.sharedBase = playerState(player) end
        local base = shared.sharedBase
        player.Velocity = Vector.Zero
        for id, n in pairs(heldCollectibles(player)) do
            for _ = (base.counts[id] or 0) + 1, n do player:RemoveCollectible(id) end
        end
        for slot = 0, 1 do
            local t = player:GetTrinket(slot)
            if t ~= 0 then player:TryRemoveTrinket(t) end
        end
        for _, row in ipairs(smeltedList(player)) do
            for _ = 1, row.normal do player:TryRemoveSmeltedTrinket(row.id) end
            for _ = 1, row.gold do player:TryRemoveSmeltedTrinket(row.id | TrinketType.TRINKET_GOLDEN_FLAG) end
        end
        for slot = 0, 3 do
            if player:GetCard(slot) ~= 0 then player:SetCard(slot, Card.CARD_NULL) end
            if player:GetPill(slot) ~= 0 then player:SetPill(slot, PillColor.PILL_NULL) end
        end
        if extra then extra(player, ctx) end
    end)
    plan.wait(2) -- the items' own loss callbacks run first
    plan.act(function(player, ctx)
        local base = (ctx.bundle or ctx).sharedBase
        player:GetEffects():ClearEffects()
        player:AddCoins(base.coins - player:GetNumCoins())
        player:AddBombs(base.bombs - player:GetNumBombs())
        player:AddKeys(base.keys - player:GetNumKeys())
        player:AddBrokenHearts(-player:GetBrokenHearts())
        player:AddGoldenHearts(-player:GetGoldenHearts())
        player:AddEternalHearts(-player:GetEternalHearts())
        player:AddRottenHearts(-player:GetRottenHearts())
        player:AddBoneHearts(-player:GetBoneHearts())
        player:AddSoulHearts(-player:GetSoulHearts())
        player:AddMaxHearts(base.maxHearts - player:GetMaxHearts(), false)
        player:AddHearts(player:GetMaxHearts() - player:GetHearts())
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local t = entity.Type
            if t == EntityType.ENTITY_PICKUP or t == EntityType.ENTITY_TEAR or t == EntityType.ENTITY_PROJECTILE
                or t == EntityType.ENTITY_BOMB or t == EntityType.ENTITY_LASER or (entity:IsEnemy() and not entity:ToPlayer()) then
                entity:Remove()
            end
        end
        player.Position = Game():GetRoom():GetCenterPos()
        player.Velocity = Vector.Zero
        -- a fresh run starts with no invincibility frames left over
        if type(player.ResetDamageCooldown) == "function" then player:ResetDamageCooldown() end
        H.refresh(player)
    end)
    plan.act(function(_, ctx) ctx.resetWait = 0 end)
    plan.waitUntil(function(player, ctx)
        ctx.resetWait = ctx.resetWait + 1
        local gap = baselineGap(player, (ctx.bundle or ctx).sharedBase)
        if not gap and ready then
            local ok, detail = ready(player, ctx)
            if not ok then gap = detail or "file-specific baseline not ready" end
        end
        ctx.resetGap = gap
        return gap == nil or ctx.resetWait >= 90, gap
    end, 91, "the player settles back at the shared-run baseline")
    plan.require("player back at the shared-run baseline (else the shared run stops here)", function(_, ctx)
        return ctx.resetGap == nil, ctx.resetGap or "inventory, pockets, resources, hearts, effects, familiars and stats restored"
    end)
    plan.act(function(player, ctx) ctx.base = H.stats(player) end)
end

-- Registers a case on its own (`cb test <item> <name>`, its own fresh run)
-- and lists it in `list` for a shared run.
function S.caseIn(list, key, groups)
    return function(name, build, synergyNames)
        S.add(key, name, groups, build, synergyNames)
        list[#list + 1] = name
    end
end

-- Moves `name` to the end of a shared-run list: a case that leaves what no
-- reset undoes (another room, a placed rock, a stat earned for good) closes
-- its run, and the run's closing restart clears it.
function S.last(list, name)
    for i, member in ipairs(list) do
        if member == name then table.insert(list, table.remove(list, i)); return end
    end
    error("not in the shared run: " .. tostring(name))
end

function S.link(key,command,groups,synergyNames)
    S.rows[#S.rows+1]={key=key,name=synergyNames[1],command=command,groups=groups,external=true}
    for _,name in ipairs(synergyNames) do
        S.coverage[key]=S.coverage[key] or {}
        S.coverage[key][name]=command
    end
end

function S.find(key, name)
    for _, row in ipairs(S.rows) do
        if row.key == key and row.name == name then return row.command end
    end
end

function S.newFloor(plan, stage)
    plan.act(function(_, ctx)
        ctx.previousStage = Game():GetLevel():GetStage()
        Isaac.ExecuteCommand("stage " .. stage)
    end)
    plan.waitUntil(function() return Game():GetLevel():GetStage() == stage end, 180, "real new floor")
    plan.wait(4)
end

function S.collectible(player, id, wanted)
    assert(type(id) == "number" and id > 0, "unresolved fixture collectible")
    local current = player:GetCollectibleNum(id, true)
    for _ = current + 1, wanted do player:AddCollectible(id, 0, false) end
    for _ = wanted + 1, current do player:RemoveCollectible(id) end
end

return S
