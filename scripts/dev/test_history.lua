-- Developer-only retry ledger. Separate from gameplay/run saves so a test's
-- restart cannot discard unresolved failures. The engine cannot read log.txt;
-- seed the first invocation from the reviewed 2026-10-09 full-suite result.
local M = {}
local KEY = "conchTestFailuresV1"
local seed = {
    "cb test kronos guardian_angel", "cb test kronos twisted_pair",
    "cb test kronos bum_friend", "cb test kronos lil_chest",
    "cb test kronos mystery_sack", "cb test kronos paschal_candle",
    "cb test kronos relic", "cb test kronos rune_bag",
    "cb test ice_breath lifecycle", "cb test ice_breath status_conditions",
    "cb test kronos box_of_friends", "cb test sealed_demon_sword lifecycle",
    "cb test tyrfing lifecycle",
}
local memory
local observingManager, confirmedRevision

local function persist(manager,data)
    local event=manager.SaveCallbacks and manager.SaveCallbacks.POST_DATA_SAVE
    local mod=ConchBlessing.originalMod
    assert(event and mod and type(mod.AddCallback)=="function", "test history save confirmation unavailable; kept in memory")
    if observingManager~=manager then
        mod:AddCallback(event,function(_,saved)
            local row=saved and saved.file and saved.file.other and saved.file.other[KEY]
            if row then confirmedRevision=row.revision end
        end)
        observingManager=manager
    end
    confirmedRevision=nil
    manager.Save()
    assert(confirmedRevision==data.revision,"test history disk write not confirmed; kept in memory")
end

local function state()
    local manager = ConchBlessing.SaveManager
    local save = manager and type(manager.GetPersistentSave)=="function" and manager.GetPersistentSave()
    if save and save[KEY] then
        assert(save[KEY].version==1 and type(save[KEY].pending)=="table", "invalid test failure ledger")
        memory=save[KEY]
        -- Failures recorded before conch_test became `cb test` (2026-11-14).
        local renamed={}
        for command,reason in pairs(memory.pending) do
            local rest=command:match("^conch_test(.*)$")
            if rest then renamed[#renamed+1]={command,"cb test"..rest,reason} end
        end
        for _,r in ipairs(renamed) do memory.pending[r[1]]=nil; memory.pending[r[2]]=r[3] end
    elseif not memory then
        memory={version=1,source="reviewed log 2026-10-09: 28 failures / 13 scenarios",pending={}}
        for _,command in ipairs(seed) do memory.pending[command]="reviewed log failure" end
    end
    if save then save[KEY]=memory end
    return memory, manager, save
end

function M.commands(get)
    local data=state()
    local list={}
    for command in pairs(data.pending) do
        assert(get(command), "unregistered failed test: "..command.."; failure retained")
        list[#list+1]=command
    end
    table.sort(list,function(a,b)
        local ga,gb=get(a).reuseGroup or "~",get(b).reuseGroup or "~"
        if ga~=gb then return ga<gb end
        return a<b
    end)
    return list,data.source
end

function M.record(run)
    local data,manager,save=state()
    -- Only a completed, unskipped plan can retire a failure. Cancellation and
    -- missing capabilities must not turn an unverified case into a success.
    if not run.cancelled and run.results.pass>0 and run.results.fail==0 and run.results.skip==0 then
        data.pending[run.def.command]=nil
        for _,command in ipairs(run.def.retryMembers or {}) do data.pending[command]=nil end
    end
    for command in pairs(run.ctx.completedRetryCommands or {}) do
        local result=(run.results.retryOutcomes or {})[command]
        if result and result.pass>0 and result.fail==0 and result.skip==0 then data.pending[command]=nil end
    end
    for command,detail in pairs(run.results.retryFailures or {}) do data.pending[command]=detail end
    data.source="recorded tests; unresolved failures retained until a complete PASS"
    data.revision=(tonumber(data.revision) or 0)+1
    if save and type(manager.Save)=="function" then
        persist(manager,data)
    end
end

return M
