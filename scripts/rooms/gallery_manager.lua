-- New visits use native Death Certificate rooms. Existing version-9 StageAPI
-- saves keep their exact journals and graph until that floor has been settled.
-- Each backend owns its callbacks, but only the selected backend may act.
ConchBlessing.GalleryManager = {}
local M = ConchBlessing.GalleryManager
local native
local legacy
local gameStarted = false
local initializing = false
local reconciledBackend

local function selectedBackend()
    local saveManager = ConchBlessing.SaveManager
    local run = saveManager and type(saveManager.TryGetRunSave) == "function"
        and saveManager.TryGetRunSave(nil, false) or nil
    local session = run and run.appraisalGallerySession
    if type(session) == "table" and session.version == 9
        and session.mode == "appraisal_trinkets_stageapi" then
        return legacy
    end
    return native
end

function M.isBackendActive(backend, starting)
    local selected = selectedBackend()
    if starting then
        gameStarted = true
        reconciledBackend = selected
    end
    -- A continued virtual session may finish its cross-floor settlement from
    -- an update instead of the new-level callback. Open the native lifecycle
    -- only after the old ledger has actually been cleared.
    if not starting and gameStarted and selected == native
        and reconciledBackend == legacy and not initializing then
        reconciledBackend = native
        initializing = true
        native.onGameStarted(nil, true)
        initializing = false
    end
    return backend == selected
end

setmetatable(M, {
    __index = function(_, key)
        local backend = selectedBackend()
        return backend and backend[key]
    end,
})

ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    gameStarted = false
    reconciledBackend = nil
end)

native = require("scripts.rooms.native_gallery_manager")
legacy = require("scripts.rooms.legacy_stageapi_gallery_manager")
-- Register old door metadata before provider persistence restores a continued
-- floor. Registration is harmless on new runs; gameplay remains dispatched.
legacy.bootstrapStageAPI()

return M
