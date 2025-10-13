ConchBlessing.moneytear = {}

local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")

ConchBlessing.moneytear.data = {
    spsPerCoin = 0.066
}

local function getItemId()
    return ConchBlessing.ItemData.MONEY_TEAR and ConchBlessing.ItemData.MONEY_TEAR.id
end

local function getPlayerKey(player)
    return tostring(player:GetPlayerType())
end

local function ensureState()
    ConchBlessing.moneytear.state = ConchBlessing.moneytear.state or { perPlayer = {} }
    return ConchBlessing.moneytear.state
end

local function getPlayerState(player)
    local s = ensureState()
    local key = getPlayerKey(player)
    s.perPlayer[key] = s.perPlayer[key] or {
        lastCoins = nil
    }
    return s.perPlayer[key]
end

local function saveToSave(player)
    local save = SaveManager.GetRunSave(player)
    if not save then return end
    save.moneyTear = save.moneyTear or {}
    local key = getPlayerKey(player)
    local ps = getPlayerState(player)
    save.moneyTear[key] = save.moneyTear[key] or {}
    local rec = save.moneyTear[key]
    rec.lastCoins = ps.lastCoins
    SaveManager.Save()
end

local function loadFromSave(player)
    local save = SaveManager.GetRunSave(player)
    if not save then return end
    save.moneyTear = save.moneyTear or {}
    local key = getPlayerKey(player)
    local rec = save.moneyTear[key]
    if rec then
        local ps = getPlayerState(player)
        ps.lastCoins = tonumber(rec.lastCoins) or nil
    end
end

local function applyForPlayer(player)
    local id = getItemId()
    if not id then return end
    local ps = getPlayerState(player)
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if not um then return end

    local count = player:GetCollectibleNum(id)
    if count and count > 0 then
        local coins = player:GetNumCoins()
        if ps.lastCoins == nil or ps.lastCoins ~= coins then
            local per = ConchBlessing.moneytear.data.spsPerCoin or 0
            local addSps = per * coins
            um:RemoveItemAddition(player, id, "Tears")
            um:SetItemAddition(player, id, "Tears", addSps, "Money = Tear")
            ps.lastCoins = coins
            ConchBlessing.printDebug(string.format("[Money=Tear] coins=%d, per=%.4f, addSps=%+.4f", coins, per, addSps))
            saveToSave(player)
        end
    else
        um:RemoveItemAddition(player, id, "Tears")
        if ps.lastCoins ~= nil then
            ps.lastCoins = nil
            saveToSave(player)
        end
    end
end

function ConchBlessing.moneytear.onGameStarted(_, isContinued)
    local game = Game()
    local num = game:GetNumPlayers()
    for i = 0, num - 1 do
        local p = game:GetPlayer(i)
        if isContinued then
            loadFromSave(p)
        else
            local ps = getPlayerState(p)
            ps.lastCoins = p:GetNumCoins()
            saveToSave(p)
        end
        applyForPlayer(p)
    end
end

function ConchBlessing.moneytear.onUpdate(_)
    local game = Game()
    local num = game:GetNumPlayers()
    for i = 0, num - 1 do
        local p = game:GetPlayer(i)
        applyForPlayer(p)
    end
end
