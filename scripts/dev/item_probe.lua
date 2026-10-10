-- conch_test [all|synergies|conditions|damage|list|status|stop|ITEM_KEY [CASE]]
-- One public console command; item and scenario names are parameters.
local TestBench = require("scripts.dev.test_bench")
local H = require("scripts.dev.item_test_support")
local Dynamic = require("scripts.dev.item_test_dynamic")
local Isolation = require("scripts.dev.test_isolation")
local Scenarios = require("scripts.dev.item_scenarios")
for _, module in ipairs({"synergies","conditions","damage","kronos_synergies","kronos_batches","kronos_sources","pools","real_eyes","eye_upgrades"}) do
    require("scripts.dev.item_test_" .. module)
end
local contracts = {}
for _, module in ipairs({ "stats", "combat", "special" }) do
    for key, contract in pairs(require("scripts.dev.item_test_" .. module)) do
        assert(not contracts[key], "duplicate item contract: " .. key)
        contracts[key] = contract
    end
end

local GOLDEN = TrinketType.TRINKET_GOLDEN_FLAG
local keys, commands = {}, {}
local deep = { KRONOS = "conch_test kronos detail", LIVE_EYE = "conch_test live_eye detail", APPRAISAL_CERTIFICATE = "conch_test appraisal detail" }
for key, item in pairs(ConchBlessing.ItemData) do
    if type(item) == "table" and item.type then keys[#keys + 1] = key end
end
table.sort(keys)

local function out(line)
    Isaac.ConsoleOutput(line .. "\n")
    Isaac.DebugString("[ConchTest] " .. line)
end

local function count(player, item)
    if item.type ~= "trinket" then return player:GetCollectibleNum(item.id, true) end
    local total = 0
    for slot = 0, 1 do
        local id = player:GetTrinket(slot)
        if id == item.id or id == item.id + GOLDEN then total = total + 1 end
    end
    return total
end

local function change(player, item, previous, wanted)
    if wanted > previous then
        if item.type == "trinket" then
            player:AddTrinket(item.id + (wanted == 2 and GOLDEN or 0), false)
        else
            local slot = item.type == "active" and wanted == 2 and ActiveSlot.SLOT_SECONDARY or ActiveSlot.SLOT_PRIMARY
            player:AddCollectible(item.id, 0, true, slot)
        end
    else
        if item.type == "trinket" then
            assert(player:TryRemoveTrinket(item.id + (previous == 2 and GOLDEN or 0)), "held trinket removal failed")
        else
            local slot = item.type == "active" and previous == 2 and ActiveSlot.SLOT_SECONDARY or ActiveSlot.SLOT_PRIMARY
            player:RemoveCollectible(item.id, true, slot)
        end
    end
end

local function buildItem(plan, key, item)
    if item.WorkingNow == true then
        plan.section(key)
        plan.act(function(_,ctx) ctx.canReuse=true end) -- coverage-only; no gameplay mutation
        plan.check("implementation coverage", function() return nil, "unfinished ItemData row; excluded from generated game content" end)
        return
    end
    local contract = assert(contracts[key], "no behavior contract for released item " .. key)
    assert(type(item.id) == "number" and item.id > 0, "unresolved item ID: " .. key)
    if Isolation.supports(key) then Isolation.begin(plan,key=="KRONOS") end
    plan.section(key .. " setup")
    plan.wait(20)
    plan.act(function(player, ctx)
        assert(Game():GetNumPlayers() == 1, "single-player test run required")
        assert(player:GetPlayerType() == PlayerType.PLAYER_ISAAC, "bench restart must select Isaac")
        assert(count(player, item) == 0, "test item already present in starting inventory")
        local active = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
        if active > 0 then player:RemoveCollectible(active, true, ActiveSlot.SLOT_PRIMARY) end
        for slot = 0, 1 do
            local trinket = player:GetTrinket(slot)
            if trinket > 0 then player:TryRemoveTrinket(trinket) end
        end
        if item.type == "active" then player:AddCollectible(CollectibleType.COLLECTIBLE_SCHOOLBAG, 0, false) end
        if item.type == "trinket" then player:AddCollectible(CollectibleType.COLLECTIBLE_MOMS_PURSE, 0, false) end
        player.Position = Game():GetRoom():GetCenterPos()
        ctx.uses = 0
    end)
    if contract.prepare then contract.prepare(plan, item.id) end
    plan.wait(20)
    Dynamic.prepare(plan, key)
    plan.act(function(player, ctx)
        H.refresh(player)
        ctx.base = H.stats(player)
        ctx.baseFly = player.CanFly
        ctx.baseSpectral = player.TearFlags & TearFlags.TEAR_SPECTRAL ~= 0
    end)
    local stages = { 1, 2, 1, 0, 1, 0 }
    local labels = { "first copy", "stacked copies", "partial removal", "final removal", "reacquisition", "second final removal" }
    for index, n in ipairs(stages) do
        local previous = stages[index - 1] or 0
        plan.section(key .. " / " .. labels[index])
        plan.act(function(player, ctx)
            if contract.beforeChange then contract.beforeChange(player, ctx, n) end
            change(player, item, previous, n)
        end)
        -- Let the production update/cache callbacks react before checking them.
        -- Do not repair stale effects with a test-side cache update here.
        plan.wait(4)
        plan.check("inventory has expected copies", function(player) return H.expect(count(player, item), n) end)
        contract.stage(plan, item.id, n, index)
        if index == 1 then Dynamic.build(plan, key, item.id, n, contract) end
        if n == 0 and not contract.permanent then
            plan.check("all temporary stat changes withdrawn", function(player, ctx) return H.sameStats(player, ctx.base) end)
        end
        if not contract.permanent then
            plan.act(function(player, ctx)
                ctx.beforeRefresh = H.stats(player)
                for _ = 1, 3 do H.refresh(player) end
            end)
            plan.wait(2)
            plan.check("repeated cache evaluation does not compound effects", function(player, ctx)
                return H.sameStats(player, ctx.beforeRefresh)
            end)
        end
    end
    if contract.finish then contract.finish(plan, item.id) end
    if Isolation.supports(key) then Isolation.finish(plan, key, item.id) end
end

for _, key in ipairs(keys) do
    local item = ConchBlessing.ItemData[key]
    local command = "conch_test " .. string.lower(key) .. " lifecycle"
    commands[key] = command
    TestBench.register({ command = command, tag = "ItemTest:" .. key,
        reuseGroup = (Isolation.supports(key) or item.WorkingNow == true) and Isolation.group(key) or nil,
        duration = "automatic acquisition/stack/removal matrix", restartCommand = "restart 0",
        build = function(plan) buildItem(plan, key, item) end, cleanup = H.cleanup })
end

local function suiteCommands(selected)
    local list,seen = {},{}
    local function append(command)
        assert(TestBench.get(command),"missing detailed bench " .. command)
        if not seen[command] then list[#list+1]=command; seen[command]=true end
    end
    for _, key in ipairs(selected) do
        append(commands[key])
        if deep[key] then
            -- Detailed probes traverse native rooms, temporary source ledgers,
            -- pool rewards and animations. They cannot inherit a stat-only lease.
            local detail=assert(TestBench.get(deep[key]),"missing detailed bench "..deep[key])
            detail.resetReason="detailed probe changes native room/session, source and reward state"
            append(deep[key])
        end
        for _,command in ipairs(Scenarios.commands(key)) do append(command) end
    end
    -- Keep the audited reversible cases adjacent so their verified clean state
    -- can be reused. Other cases retain their original order and full isolation.
    local grouped,rest={},{}
    for _,command in ipairs(list) do
        local target=TestBench.get(command).reuseGroup and grouped or rest
        target[#target+1]=command
    end
    -- Group by the actual compatibility domain, not just reusable/non-reusable.
    -- Otherwise an intervening unrelated item would restart between Kronos groups.
    table.sort(grouped,function(a,b)
        local ga,gb=TestBench.get(a).reuseGroup,TestBench.get(b).reuseGroup
        if ga~=gb then return ga<gb end
        return a<b
    end)
    for _,command in ipairs(rest) do grouped[#grouped+1]=command end
    return grouped
end

local function listItem(key)
    local prefix = "conch_test " .. string.lower(key)
    out(prefix .. (ConchBlessing.ItemData[key].WorkingNow == true and " [unfinished: SKIP]" or " [all item tests]"))
    out("  " .. commands[key])
    if deep[key] then out("  " .. prefix .. " detail") end
    for _, row in ipairs(Scenarios.rows) do
        if row.key == key then out("  " .. prefix .. " " .. row.name
            .. (row.bundledInto and " [included in " .. row.bundledInto .. "]" or "")) end
    end
end

ConchBlessing:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, command, params)
    if string.lower(tostring(command)) ~= "conch_test" then return end
    local words = {}
    for word in tostring(params or ""):gmatch("%S+") do words[#words + 1] = string.lower(word) end
    local action, case = words[1] or "all", words[2]
    if action == "rng" or action == "rounding" then
        if TestBench.isRunning() then out("A test is already running; use conch_test stop first."); return end
        local player = Isaac.GetPlayer(0)
        if not player then out("Start a test run first."); return end
        local ok, err = pcall(function()
            local params=table.concat(words," ",2)
            if action=="rng" then require("scripts.dev.rng_probe").run(params)
            else require("scripts.dev.stat_rounding_probe").execute(params) end
        end)
        if not ok then out("FAIL "..action.." probe: "..tostring(err)) end
        return
    end
    if action == "locale" then
        if case then out("Usage: conch_test locale"); return end
        TestBench.start("conch_test locale",true); return
    end
    if action == "latest" then
        if #words>2 or (case and case~="list") then out("Usage: conch_test latest [list]");return end
        if TestBench.isRunning() then out("A test is already running; use conch_test stop first.");return end
        local ok,list,source=pcall(TestBench.latestCommands)
        if not ok then out("FAIL latest selection: "..tostring(list));return end
        out("Latest unresolved failures: "..#list.." scenarios ("..source..").")
        if #list==0 then out("No failed scenarios remain; no run restarted.");return end
        if case=="list" then for i,name in ipairs(list) do out(i..". "..name) end;return end
        if Game():GetNumPlayers()~=1 then out("Start a single-player test run first.");return end
        local started,err=pcall(TestBench.startSuite,"conch_test latest",list)
        if not started then out("FAIL latest setup: "..tostring(err)) end
        return
    end
    local aliases = { appraisal="appraisal_certificate", liveeye="live_eye", belt="utility_belt", realeyes="real_eyes", ar="ar_glasses", neglect="hemispatial_neglect" }
    action = aliases[action] or action
    if case == "detail" and #words > 2 then
        local def = deep[string.upper(action)] and TestBench.get(deep[string.upper(action)])
        if def and words[3]=="help" and #words==3 and def.help then def.help(); return end
        if not (def and def.handle) then out("Unknown detailed helper; use conch_test ITEM list."); return end
        if TestBench.isRunning() then out("A test is already running; use conch_test stop first."); return end
        local args = {}; for i=3,#words do args[#args+1]=words[i] end
        local player=Isaac.GetPlayer(0)
        if not player then out("Start a test run first."); return end
        if not def.handle(args[1],args,player) then out("Unknown detailed helper: "..args[1]) end
        return
    end
    if #words > 2 then out("Usage: conch_test ITEM [CASE]; use conch_test ITEM list."); return end
    if case and (action == "all" or action == "status" or action == "stop"
        or action == "synergies" or action == "conditions" or action == "damage") then
        out("Unexpected parameter: " .. case .. "; use conch_test list."); return
    end
    if action == "status" then out(TestBench.status()); return end
    if action == "stop" then if not TestBench.stop() then out("No test is running.") end; return end
    if action == "list" or action == "help" then
        out("conch_test [all|latest [list]|ITEM [CASE]|synergies|conditions|damage|list|status|stop]; verified compatible cases share a run. See docs/item_testing.md.")
        if case then
            local key = string.upper(case)
            if not commands[key] then out("Unknown item: " .. case); return end
            listItem(key); return
        end
        for _, key in ipairs(keys) do
            local pending = ConchBlessing.ItemData[key].WorkingNow == true
            out("conch_test " .. string.lower(key) .. (pending and " [unfinished: SKIP]" or ""))
        end
        out("For individual cases: conch_test ITEM list (example: conch_test kronos list).")
        out("Short names: conch_test appraisal, conch_test belt. Shared checks: conch_test locale, conch_test rng [samples] [luck N].")
        out("Stat math: conch_test rounding [multiplier | sweep [stacks]] [pN].")
        return
    end
    local key = string.upper(action)
    if commands[key] and (case == "list" or case == "help") then listItem(key); return end
    if Game():GetNumPlayers() ~= 1 then out("Start a single-player test run first."); return end
    if action=="synergies" or action=="conditions" or action=="damage" then
        local list,seen={},{}
        local function append(command) if not seen[command] then list[#list+1]=command; seen[command]=true end end
        local damageKeys={"FIRE_BREATH","ICE_BREATH","DRAGON","VOID_DAGGER","SOFLAM","KRONOS"}
        local conditionKeys={"MONEY_TEAR","ETERNAL_FLAME","SEALED_DEMON_SWORD","TYRFING","LIVE_EYE"}
        if action~="synergies" then
            for _,key in ipairs(action=="damage" and damageKeys or conditionKeys) do append(commands[key]) end
        end
        for _,command in ipairs(Scenarios.commands(nil,action)) do append(command) end
        local ok,err=pcall(TestBench.startSuite,"conch_test " .. action,list)
        if not ok then out("FAIL suite setup: " .. tostring(err)) end
        return
    end
    local selected = action == "all" and keys or { key }
    if #selected == 1 and not commands[selected[1]] then out("Unknown item: " .. action .. "; use conch_test list."); return end
    if case then
        local target = case == "lifecycle" and commands[key] or case == "detail" and deep[key] or Scenarios.find(key, case)
        if not target then out("Unknown case: " .. case .. "; use conch_test " .. action .. " list."); return end
        local ok, err = pcall(TestBench.start, target, true)
        if not ok then out("FAIL case setup: " .. tostring(err)) end
        return
    end
    local label = action == "all" and "conch_test" or "conch_test " .. action
    local ok, err = pcall(function() TestBench.startSuite(label, suiteCommands(selected)) end)
    if not ok then out("FAIL suite setup: " .. tostring(err)) end
end)

-- Optional console discovery. The commands still work without REPENTOGON.
if Console and type(Console.RegisterCommand) == "function" then
    pcall(Console.RegisterCommand, "conch_test", "Conch item test (restarts run)",
        "conch_test ITEM [CASE]; conch_test ITEM list for cases.", false)
end

return { keys = keys, commands = commands, contracts = contracts, scenarios = Scenarios, suiteCommands = suiteCommands }
