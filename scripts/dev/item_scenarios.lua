-- Isolated behavior scenarios appended to conch_test's lifecycle matrix.
local Bench = require("scripts.dev.test_bench")
local H = require("scripts.dev.item_test_support")
local Isolation = require("scripts.dev.test_isolation")
local S = { rows = {}, coverage = {} }

function S.add(key, name, groups, build, synergyNames)
    local parameter = name:gsub("^synergy_", "")
    local command = "conch_test " .. string.lower(key) .. " " .. parameter
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
        if (not key or row.key == key) and (not group or row.groups[group]) then
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
                ctx.retryCommand="conch_test "..string.lower(key).." "..child.name
                ctx.caseCtx={rooms=ctx.rooms,cleanupFns={}}
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
