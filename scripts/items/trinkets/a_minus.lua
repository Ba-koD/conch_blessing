ConchBlessing.aminus = {}

-- Centralized data container for A- (config + per-player state)
ConchBlessing.aminus.data = ConchBlessing.aminus.data or {
	config = {
		totalMultSum = 4.0, 	-- total sum of multipliers across selected stats
		minPerStat = 0.8, 	-- minimum multiplier per stat
		stats = { "Tears", "Damage", "Luck" }, -- affected stats (order used for RNG split)
		baseLuckAdd = 2.0, 	-- base luck addition for A- (no scaling)
		baseDamageAdd = 4.0, 	-- base flat damage addition for A- (scales with trinket multiplier)
		baseTearsAdd = 4.0 	-- base fixed SPS addition for A- (scales with trinket multiplier)
	},
	player = {} 			-- per-player runtime state (by controller index)
}

local function getTrinketIdByName(name)
	local ok, id = pcall(function()
		return Isaac.GetTrinketIdByName(name)
	end)
	return ok and id or nil
end

local TID = getTrinketIdByName("A -")

-- Get trinket total effective count (includes golden and Mom's Box)
local function getCount(player, baseId)
	if not player or not baseId then return 0 end
	local ok, n = pcall(function()
		return player:GetTrinketMultiplier(baseId) or 0
	end)
	return ok and n or 0
end

-- Determine if player has the trinket effect (includes smelted and golden counts)
local function hasTrinketEffect(player, baseId)
    if not player or not baseId then return false end
    local ok, count = pcall(function()
        return player:GetTrinketMultiplier(baseId) or 0
    end)
    return ok and count > 0
end

-- Compute a random partition of TOTAL_BUDGET into 4 non-negative parts and return per-stat portions
local function computeRandomSplit(player)
	local rng = RNG()
	local startSeed = Game():GetSeeds():GetStartSeed()
	local pseed = (player and player.InitSeed) or 0
	local seed = startSeed + pseed + (TID or 0)
	rng:SetSeed(seed, 0)

	local cfg = ConchBlessing.aminus.data.config or {}
	local stats = cfg.stats or { "Tears", "Damage", "Luck" }
	local count = #stats
	if count <= 0 then return {} end

	-- Generate 'count' positive weights and normalize
	local weights = {}
	local sum = 0
	for i = 1, count do
		local w = math.max(1e-6, rng:RandomFloat())
		weights[i] = w
		sum = sum + w
	end

	-- Allocate remaining after guaranteeing minimum per stat
	local minPer = cfg.minPerStat or 0.8
	local totalSum = cfg.totalMultSum or 4.0
	local minTotal = minPer * count
	local remaining = math.max(0, totalSum - minTotal)
	local scale = (sum ~= 0) and (remaining / sum) or 0

	local result = {}
	for i = 1, count do
		result[stats[i]] = minPer + weights[i] * scale
	end

	return result
end

-- Apply or remove unified multipliers based on trinket presence
local function updatePlayerMultipliers(player)
	if not player or not ConchBlessing or not ConchBlessing.stats or not ConchBlessing.stats.unifiedMultipliers then return end
	if not TID or TID <= 0 then return end

    local hasAny = hasTrinketEffect(player, TID)
	local pdata = ConchBlessing.aminus.data
	local idx = player.ControllerIndex or 0
	pdata.player[idx] = pdata.player[idx] or {}
	local pstate = pdata.player[idx]

    if hasAny then
        -- Ensure split exists and is stable across smelting and reloads by saving to SaveManager
        if not pstate.split then
            local sm = require("scripts.lib.save_manager")
            local rs = sm.GetRunSave(player) or {}
            rs.aMinus = rs.aMinus or {}
            if rs.aMinus.split and type(rs.aMinus.split) == "table" then
                pstate.split = rs.aMinus.split
                ConchBlessing.printDebug("[A-] Loaded split from SaveManager")
            else
                pstate.split = computeRandomSplit(player)
                rs.aMinus.split = pstate.split
                sm.Save()
                ConchBlessing.printDebug("[A-] Generated and saved new split to SaveManager")
            end
            -- Debug: summarize split values
            local s = pstate.split
            local cfg = ConchBlessing.aminus.data.config or {}
            local sumCheck = 0
            for stat, val in pairs(s) do sumCheck = sumCheck + (val or 0) end
            ConchBlessing.printDebug(string.format("[A-] Split multipliers sum=%.3f (target=%.3f, min=%.3f each)",
                sumCheck, cfg.totalMultSum or 4.0, cfg.minPerStat or 0.8))
            ConchBlessing.printDebug(string.format("[A-] Final multipliers -> Tears=x%.3f, Damage=x%.3f, Luck=x%.3f",
                s.Tears or 1.0, s.Damage or 1.0, s.Luck or 1.0))
        end

        -- Apply as first-use multipliers (xV) then allow future changes as additive-mult style deltas
        local um = ConchBlessing.stats.unifiedMultipliers
        local s = pstate.split
        if s.Tears then um:SetItemMultiplier(player, TID, "Tears", s.Tears, "A- Split (Tears)") end
        if s.Damage then um:SetItemMultiplier(player, TID, "Damage", s.Damage, "A- Split (Damage)") end
        if s.Luck then um:SetItemMultiplier(player, TID, "Luck", s.Luck, "A- Split (Luck)") end
        -- If moms box/golden increase trinket count, ensure multipliers persist; additions scale via evaluateCache
        -- Persist unified multipliers so they are applied on load
        um:SaveToSaveManager(player)
	else
		-- Remove multipliers when trinket effect is not present
		local um = ConchBlessing.stats.unifiedMultipliers
		um:RemoveItemMultiplier(player, TID, "Tears")
		um:RemoveItemMultiplier(player, TID, "Damage")
		um:RemoveItemMultiplier(player, TID, "Luck")
		pstate.split = nil
	end
end

function ConchBlessing.aminus.onPostPEffectUpdate(_, player)
	if not player or not TID or TID <= 0 then return end
	local pstore = (ConchBlessing.aminus.data and ConchBlessing.aminus.data.player) or {}
	local idx = player.ControllerIndex or 0
	local hadBefore = (pstore[idx] and pstore[idx].split ~= nil) or false
	updatePlayerMultipliers(player)
    local hasAny = hasTrinketEffect(player, TID)
	if hasAny or hadBefore then
		player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_LUCK)
		player:EvaluateItems()
	end
end

-- Apply base additions (luck, fixed tears) so A- grants its flat bonuses too
function ConchBlessing.aminus.onEvaluateCache(_, player, cacheFlag)
	if not player or not TID or TID <= 0 then return end
	local count = getCount(player, TID)
	if count <= 0 then return end

	local cfg = ConchBlessing.aminus.data.config or {}
    -- Read current unified total multiplier for scaling additions so that (base + add) * total holds
    local um = ConchBlessing.stats.unifiedMultipliers
    um:InitPlayer(player)
    local pid = player:GetPlayerType()
    local statKey = (cacheFlag == CacheFlag.CACHE_DAMAGE and "Damage")
        or (cacheFlag == CacheFlag.CACHE_FIREDELAY and "Tears")
        or (cacheFlag == CacheFlag.CACHE_LUCK and "Luck")
        or nil
    local total = 1.0
    if statKey and um[pid] and um[pid].statMultipliers and um[pid].statMultipliers[statKey] and type(um[pid].statMultipliers[statKey].totalApply) == "number" then
        total = um[pid].statMultipliers[statKey].totalApply
    end

    if cacheFlag == CacheFlag.CACHE_LUCK then
        local addLuck = (cfg.baseLuckAdd or 0) * count
        if addLuck ~= 0 then
            local scaled = addLuck * total
            ConchBlessing.printDebug(string.format("[A-] Applying base luck addition: %+0.2f (count=%d, total=%.2f, scaled=%+.2f)", addLuck, count, total, scaled))
            ConchBlessing.stats.luck.applyAddition(player, scaled, nil)
        end
    elseif cacheFlag == CacheFlag.CACHE_DAMAGE then
        local addDmg = (cfg.baseDamageAdd or 0) * count
        if addDmg ~= 0 then
            local scaled = addDmg * total
            ConchBlessing.printDebug(string.format("[A-] Applying base damage addition: %+0.2f (count=%d, total=%.2f, scaled=%+.2f)", addDmg, count, total, scaled))
            ConchBlessing.stats.damage.applyAddition(player, scaled, nil)
        end
    elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
        local addSPS = (cfg.baseTearsAdd or 0) * count
        if addSPS ~= 0 then
            local scaled = addSPS * total
            ConchBlessing.printDebug(string.format("[A-] Applying base tears(SPS) addition: %+0.2f (count=%d, total=%.2f, scaled=%+.2f)", addSPS, count, total, scaled))
            ConchBlessing.stats.tears.applyAddition(player, scaled, nil)
        end
	end
end

return true