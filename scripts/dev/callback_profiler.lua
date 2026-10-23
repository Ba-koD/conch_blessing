local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Dev-only: times this mod's own callback handlers for a while.
--
-- REPENTOGON keeps every registered callback as a Lua entry { Mod, Function,
-- Priority, Param } returned by Isaac.GetCallbacks. start() swaps the Function
-- of this mod's entries for a timing wrapper and stop() puts every original
-- back, so other mods are never touched and nothing stays wrapped. Used only by
-- conch_test benches; it does nothing on runtimes without Isaac.GetCallbacks.

local P = {}
local wrapped = nil          -- list of { entry, original }
local totals = {}            -- [label] = { time = seconds, calls = n }

local function clock()
    if type(os) == "table" and type(os.clock) == "function" then return os.clock(), "os.clock" end
    return Isaac.GetTime() / 1000, "Isaac.GetTime"
end

function P.available()
    return type(Isaac.GetCallbacks) == "function"
end

-- A readable name for a handler: ConchBlessing.<namespace>.<name> when the
-- function is published there, else the callback's name and position.
local function names()
    local found = {}
    for ns, tbl in pairs(ConchBlessing) do
        if type(tbl) == "table" and ns ~= "ItemData" and ns ~= "PocketData" then
            for key, value in pairs(tbl) do
                if type(value) == "function" and not found[value] then found[value] = ns .. "." .. tostring(key) end
            end
        end
    end
    return found
end

local function callbackName(id)
    for name, value in pairs(ModCallbacks) do
        if value == id then return name end
    end
    return tostring(id)
end

local function ours(mod)
    return mod == ConchBlessing or mod == ConchBlessing.originalMod
end

function P.start()
    assert(P.available(), "Isaac.GetCallbacks unavailable")
    P.stop()
    wrapped, totals = {}, {}
    local named = names()
    for _, id in pairs(ModCallbacks) do
        if type(id) == "number" then
            local entries = Isaac.GetCallbacks(id, false)
            for index, entry in ipairs(entries or {}) do
                if ours(entry.Mod) and type(entry.Function) == "function" then
                    local original = entry.Function
                    local where = nil
                    if not named[original] and type(debug) == "table" and type(debug.getinfo) == "function" then
                        local ok, info = pcall(debug.getinfo, original, "S")
                        if ok and info and info.short_src then
                            where = tostring(info.short_src):match("([^/\\]+)$") .. ":" .. tostring(info.linedefined)
                        end
                    end
                    local label = (named[original] or where or ("#" .. index)) .. " @" .. callbackName(id)
                    entry.Function = function(...)
                        local t0 = clock()
                        local a, b, c = original(...)
                        local row = totals[label]
                        if not row then row = { time = 0, calls = 0 }; totals[label] = row end
                        row.time = row.time + (clock() - t0)
                        row.calls = row.calls + 1
                        return a, b, c
                    end
                    wrapped[#wrapped + 1] = { entry = entry, original = original }
                end
            end
        end
    end
    return #wrapped
end

function P.stop()
    for _, row in ipairs(wrapped or {}) do row.entry.Function = row.original end
    wrapped = nil
end

-- The heaviest handlers first: { label, ms, calls }.
function P.report(limit)
    local list = {}
    for label, row in pairs(totals) do list[#list + 1] = { label = label, ms = row.time * 1000, calls = row.calls } end
    table.sort(list, function(a, b) return a.ms > b.ms end)
    local total = 0
    for _, row in ipairs(list) do total = total + row.ms end
    local top = {}
    for i = 1, math.min(limit or #list, #list) do top[i] = list[i] end
    return top, total, select(2, clock())
end

return P
