-- The global run save (SaveManager's run table with no entity), kept for the
-- game frame. SaveManager works out its lookup key on every ask, and the
-- Appraisal backends, Atropos and the Conch Ticket ask on every input action
-- and several times an update. SaveManager replaces that table only for a new
-- game (player init), a save load, a Glowing Hourglass restore and the exit;
-- each of those drops the kept table at once, so a field read through it is
-- always the live one. Only the table is kept, never a field of it.
local M = {}

local kept, keptFrame = nil, -1
-- A player's own run save the same way, keyed by the player entity and its
-- character (SaveManager keys a player's save by the character's RNG seed).
local players, playersFrame = {}, -1

function M.drop()
    kept, keptFrame = nil, -1
    players, playersFrame = {}, -1
end

-- The game frame, or nil where there is none to key on (then nothing is kept).
function M.frame()
    local game = rawget(_G, "Game") and Game()
    return game and game.GetFrameCount and game:GetFrameCount() or nil
end

-- Before SaveManager has loaded there is no table to give (it would only log
-- an error for each ask).
local function loaded(sm)
    return type(sm) == "table" and (type(sm.IsLoaded) ~= "function" or sm.IsLoaded())
end

-- The table, or nil before SaveManager has loaded. `create` asks with
-- GetRunSave instead of TryGetRunSave (the global run table always exists once
-- loaded, so both return the same table then).
function M.global(create)
    local sm = ConchBlessing.SaveManager
    if not loaded(sm) then return nil end
    local frame = M.frame()
    if frame and kept and keptFrame == frame then return kept end
    local ask = create and sm.GetRunSave or sm.TryGetRunSave
    if type(ask) ~= "function" then return nil end
    local run = ask(nil, false)
    if frame and type(run) == "table" then
        kept, keptFrame = run, frame
    else
        kept, keptFrame = nil, -1
    end
    return run
end

-- A player's run save, or nil (before load, or no save yet and `create` not
-- set). Only a found table is kept, so a later ask with `create` still makes one.
function M.player(player, create)
    local sm = ConchBlessing.SaveManager
    if not (player and loaded(sm)) then return nil end
    local frame = M.frame()
    if not frame then
        -- No frame to keep it for: ask SaveManager directly.
        local save = create and type(sm.GetRunSave) == "function" and sm.GetRunSave(player) or nil
        if save == nil and type(sm.TryGetRunSave) == "function" then save = sm.TryGetRunSave(player) end
        return save
    end
    if playersFrame ~= frame then players, playersFrame = {}, frame end
    local key = GetPtrHash(player)
    local kind = type(player.GetPlayerType) == "function" and player:GetPlayerType() or -1
    local hit = players[key]
    if hit and hit.kind == kind then return hit.save end
    local save = create and type(sm.GetRunSave) == "function" and sm.GetRunSave(player) or nil
    if save == nil and type(sm.TryGetRunSave) == "function" then save = sm.TryGetRunSave(player) end
    if type(save) == "table" then players[key] = { kind = kind, save = save } end
    return save
end

if type(ModCallbacks) == "table" and type(ConchBlessing.AddCallback) == "function" then
    for _, id in ipairs({ "MC_POST_PLAYER_INIT", "MC_POST_GAME_STARTED", "MC_PRE_GAME_EXIT",
        "MC_POST_NEW_ROOM", "MC_POST_NEW_LEVEL" }) do
        if ModCallbacks[id] then ConchBlessing:AddCallback(ModCallbacks[id], M.drop) end
    end
end
-- SaveManager deletes a removed player's save.
if type(ModCallbacks) == "table" and ModCallbacks.MC_POST_ENTITY_REMOVE and type(EntityType) == "table"
    and type(ConchBlessing.AddCallback) == "function" then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_ENTITY_REMOVE, M.drop, EntityType.ENTITY_PLAYER)
end
local sm, mod = ConchBlessing.SaveManager, ConchBlessing.originalMod
local ids = type(sm) == "table" and sm.SaveCallbacks or nil
if mod and type(ids) == "table" then
    for _, name in ipairs({ "POST_DATA_LOAD", "PRE_GLOWING_HOURGLASS_RESET", "POST_GLOWING_HOURGLASS_RESET" }) do
        if ids[name] then mod:AddCallback(ids[name], M.drop) end
    end
end

return M
