local ConchBlessing_Config = {}

local Version = "1.0.0"
ConchBlessing_Config.Version = Version

local DefaultConfig = {
    debugMode = true,
}

-- JSON library for saving and loading config
local json = nil
pcall(function() json = require("json") end)
if not json then
    json = {
        encode = function(data) return tostring(data) end,
        decode = function(str) return {} end,
    }
end

-- Initialize the config table
---@param mod table
---@return table
function ConchBlessing_Config.Init(mod)
    mod.Config = {}
    for k, v in pairs(DefaultConfig) do
        if mod.Config[k] == nil then
            mod.Config[k] = v
        end
    end
    mod.Config.Version = Version
    return mod.Config
end

-- Load the config
---@param mod table
---@return boolean
function ConchBlessing_Config.Load(mod)
    if mod:HasData() then
        local ok, data = pcall(function() return json.decode(Isaac.LoadModData(mod)) end)
        if ok and type(data) == "table" then
            for k, v in pairs(DefaultConfig) do
                if data[k] ~= nil then
                    mod.Config[k] = data[k]
                end
            end
            return true
        end
    end
    return false
end

-- Save the config
function ConchBlessing_Config.Save(mod)
    Isaac.SaveModData(mod, json.encode(mod.Config))
end

-- Reset the config
function ConchBlessing_Config.Reset(mod)
    for k, v in pairs(DefaultConfig) do
        mod.Config[k] = v
    end
    ConchBlessing_Config.Save(mod)
end

return ConchBlessing_Config