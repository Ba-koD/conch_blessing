local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Dev-only (not in the Workshop package): which module registered each of this
-- mod's callback handlers, so the profiler (callback_profiler.lua) can name
-- handlers that are local functions. Core installs it on its RegisterMod object
-- before anything registers; the label is the module the loader in main.lua is
-- running (ConchBlessingLoadingModule), or a phase core names with during().
-- It is written once per handler at registration and never read during play.
local O = {}
local origins = setmetatable({}, { __mode = "k" })
local phase = nil

ConchBlessingCallbackOrigins = origins

local function remember(fn)
    if type(fn) == "function" and origins[fn] == nil then
        origins[fn] = tostring(phase or ConchBlessingLoadingModule or "after load")
    end
end

--- Wrap the mod's AddCallback and AddPriorityCallback to note each handler.
function O.install(mod)
    local add, addPriority = mod.AddCallback, mod.AddPriorityCallback
    if type(add) == "function" then
        mod.AddCallback = function(self, id, fn, ...)
            remember(fn)
            return add(self, id, fn, ...)
        end
    end
    if type(addPriority) == "function" then
        mod.AddPriorityCallback = function(self, id, priority, fn, ...)
            remember(fn)
            return addPriority(self, id, priority, fn, ...)
        end
    end
end

--- Label registrations with `label` until during(nil).
function O.during(label) phase = label end

return O
