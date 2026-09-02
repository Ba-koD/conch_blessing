ConchBlessing.moneytear = {}

ConchBlessing.moneytear.data = {
    spsPerCoin = 0.066
}

local STAT_TYPE = "Tears"
local EPSILON = 0.0001

local function getItemId()
    return ConchBlessing.ItemData.MONEY_TEAR and ConchBlessing.ItemData.MONEY_TEAR.id
end

-- Key by the same identity StatsAPI uses (player.InitSeed based). Keying by
-- PlayerType instead would collide in co-op / Jacob & Esau and would survive
-- character-entity swaps that already dropped the StatsAPI-side entry.
local function getPlayerKey(player)
    if ConchBlessing.getUnifiedPlayerKey then
        local key = ConchBlessing.getUnifiedPlayerKey(player)
        if key ~= nil then return tostring(key) end
    end
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
        lastCoins = nil,
        lastCount = nil
    }
    return s.perPlayer[key]
end

-- Read back what StatsAPI actually holds for this item so a wiped/reloaded
-- provider state is detected instead of being masked by our own cache.
local function getStoredAddition(um, player)
    local id = getItemId()
    if not id then return nil end
    local perPlayer = ConchBlessing.getUnifiedMultiplierState
        and ConchBlessing.getUnifiedMultiplierState(player, um)
        or nil
    local perItem = perPlayer and perPlayer.itemAdditions and perPlayer.itemAdditions[id] or nil
    local entry = perItem and perItem[STAT_TYPE] or nil
    if type(entry) == "table" and type(entry.cumulative) == "number" then
        return entry.cumulative
    end
    return nil
end

local function applyForPlayer(player)
    local id = getItemId()
    if not id then return end
    local ps = getPlayerState(player)
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if not um then return end

    local count = player:GetCollectibleNum(id)
    local stored = getStoredAddition(um, player)

    if count and count > 0 then
        local coins = player:GetNumCoins()
        local basePer = ConchBlessing.moneytear.data.spsPerCoin or 0
        local effectivePer = basePer * count
        local addSps = effectivePer * coins

        local inputsChanged = (ps.lastCoins ~= coins) or (ps.lastCount ~= count)
        local providerDrifted = (stored == nil) or (math.abs(stored - addSps) > EPSILON)
        if inputsChanged or providerDrifted then
            um:RemoveItemAddition(player, id, STAT_TYPE)
            um:SetItemAddition(player, id, STAT_TYPE, addSps, "Money = Tear")
            if um.QueueCacheUpdate then
                um:QueueCacheUpdate(player, STAT_TYPE)
            end
            -- Persist through StatsAPI so a continued run reloads the bonus.
            if um.SaveToSaveManager then
                um:SaveToSaveManager(player)
            end
            ps.lastCoins = coins
            ps.lastCount = count
            ConchBlessing.printDebug(string.format(
                "[Money=Tear] coins=%d, items=%d, basePer=%.4f, effPer=%.4f, addSps=%+.4f (inputsChanged=%s, drift=%s)",
                coins, count, basePer, effectivePer, addSps,
                tostring(inputsChanged), tostring(providerDrifted)
            ))
        end
    else
        if stored ~= nil or ps.lastCoins ~= nil or ps.lastCount ~= nil then
            um:RemoveItemAddition(player, id, STAT_TYPE)
            if um.QueueCacheUpdate then
                um:QueueCacheUpdate(player, STAT_TYPE)
            end
            if um.SaveToSaveManager then
                um:SaveToSaveManager(player)
            end
            ps.lastCoins = nil
            ps.lastCount = nil
            ConchBlessing.printDebug("[Money=Tear] effect removed: no items owned")
        end
    end
end

function ConchBlessing.moneytear.onGameStarted(_, isContinued)
    local game = Game()
    local num = game:GetNumPlayers()
    -- Never pre-seed lastCoins/lastCount here: doing so makes the very first
    -- applyForPlayer() a no-op when the run already starts with the item, and
    -- on a continued run it hides the fact that the provider state was reset.
    for i = 0, num - 1 do
        local p = game:GetPlayer(i)
        local ps = getPlayerState(p)
        ps.lastCoins = nil
        ps.lastCount = nil
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
