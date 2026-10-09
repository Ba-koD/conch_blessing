-- A clock for deadline-based item timers. Normal play always reads the engine.
-- The dev bench may freeze/advance only this clock; it never runs item callbacks
-- itself or changes growth rates, durations, rewards, or the engine frame count.
local Clock = {}
local lease
local rebases = {}

function Clock.now()
    return lease and lease.frame or Game():GetFrameCount()
end

function Clock.onRebase(key, fn) rebases[key] = fn end

function Clock.begin(owner)
    assert(owner and not lease, "timer clock already leased")
    lease = { owner = owner, frame = Game():GetFrameCount() }
    return lease.frame
end

function Clock.advance(owner, frame)
    assert(lease and lease.owner == owner, "timer clock lease mismatch")
    assert(type(frame) == "number" and frame >= lease.frame and frame < math.huge,
        "test clock must advance monotonically")
    lease.frame = math.floor(frame)
end

function Clock.release(owner)
    if not lease or (owner and owner ~= lease.owner) then return end
    local delta = Game():GetFrameCount() - lease.frame
    lease = nil
    -- Preserve remaining deadlines when returning to real time, even if a
    -- cancelled test is saved before its final restart. Never persist a lease.
    local failure
    for _, rebase in pairs(rebases) do
        local ok, err = pcall(rebase, delta)
        if not ok then failure = failure or err end
    end
    if failure then error(failure) end
end

local function releaseAtBoundary()
    local ok, err = pcall(Clock.release)
    if not ok then ConchBlessing.printError("Timer clock cleanup failed: " .. tostring(err)) end
end
for _, name in ipairs({ "MC_PRE_GAME_EXIT", "MC_POST_GAME_STARTED", "MC_PRE_MOD_UNLOAD" }) do
    local id = ModCallbacks[name]
    if id then
        local callback = name == "MC_PRE_MOD_UNLOAD" and function(_, mod)
            if mod == ConchBlessing or mod == ConchBlessing.originalMod then releaseAtBoundary() end
        end or releaseAtBoundary
        if type(ConchBlessing.AddPriorityCallback) == "function" then
            ConchBlessing:AddPriorityCallback(id, -1000, callback)
        else ConchBlessing:AddCallback(id, callback) end
    end
end

return Clock
