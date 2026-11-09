-- Conch's Blessing - Loader
--
-- `luamod conch_blessing` reruns only this file, and the game's require keeps
-- every module for the whole session: modules loaded through it come back
-- without running, so a reload would leave this mod with no callbacks
-- (measured 2026-10-18). Each file of this mod therefore loads through
-- ConchBlessingRequire. include runs the file again, and the cache below lasts
-- one load only, so a reload runs every module once more. Modules that are not
-- this mod's (the game's json) still come from the game's require.
local gameRequire = require
local modules = {}
local LOADING = {}

function ConchBlessingRequire(name)
    if type(name) ~= "string" or not name:find("^scripts[%./]") then
        return gameRequire(name)
    end
    local key = name:gsub("/", ".")
    local cached = modules[key]
    if cached == LOADING then
        error("Conch's Blessing module " .. key .. " requires itself while it loads", 2)
    elseif cached ~= nil then
        return cached
    end
    modules[key] = LOADING
    -- the module whose code is running, so the dev profiler can name the -- dev-only
    -- handlers it registers (scripts/dev/callback_origins.lua) -- dev-only
    local outer = ConchBlessingLoadingModule -- dev-only
    ConchBlessingLoadingModule = key -- dev-only
    local ok, result = pcall(include, (key:gsub("%.", "/")))
    ConchBlessingLoadingModule = outer -- dev-only
    -- include raises on syntax and runtime errors, but for a missing file it
    -- returns the search's "no file" list instead (measured 2026-10-18).
    if ok and type(result) == "string" and result:find("no file '", 1, true) then
        ok, result = false, "module '" .. name .. "' not found:" .. result
    end
    if not ok then
        modules[key] = nil
        error(result, 0)
    end
    -- Like require: a module that returns nothing is still loaded.
    if result == nil then result = true end
    modules[key] = result
    return result
end

-- dev-only:begin
-- A module that may be absent: the Workshop package leaves scripts/dev out,
-- along with this function and every other line marked dev-only
-- (.github/scripts/release_lua.py). Returns nil when that very module's file
-- is missing; any other error in it, or in a module it loads, is raised.
function ConchBlessingOptionalRequire(name)
    local ok, result = pcall(ConchBlessingRequire, name)
    if ok then return result end
    if tostring(result):find("module '" .. name .. "' not found:", 1, true) == 1 then return nil end
    error(result, 0)
end
-- dev-only:end

ConchBlessingRequire("scripts.conch_blessing_core")
-----------------------------------------------------------
----=         Conch's Blessing Mod               =----
----=    Enhanced Items for Isaac           =----
----=        Version managed in conch_blessing_config.lua       =----
-----------------------------------------------------------

-- Version information will be displayed in console messages
-- RegisterMod is handled in conch_blessing_core.lua
