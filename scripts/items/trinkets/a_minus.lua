ConchBlessing.aminus = {}

-- Centralized data container for A- (config + per-player state)
ConchBlessing.aminus.data = ConchBlessing.aminus.data or {
	config = {
		totalMultSum = 4.0, 	-- total sum of multipliers across selected stats
		minPerStat = 0.8, 	-- minimum multiplier per stat
		stats = { "Tears", "Damage", "Luck" } -- affected stats (order used for RNG split)
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

-- Check if the player is actually carrying the trinket in a slot (excludes smelted)
local function isCarryingTrinket(player, baseId)
    if not player or not baseId then return false end
    for slot = 0, 1 do
        local raw = player:GetTrinket(slot)
        if raw and raw > 0 then
            local carriedBase = raw
            if raw >= 32768 then
                carriedBase = raw - 32768 -- remove golden bit
            end
            if carriedBase == baseId then
                return true
            end
        end
    end
    return false
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

	local hasAny = isCarryingTrinket(player, TID)
	local pdata = ConchBlessing.aminus.data
	local idx = player.ControllerIndex or 0
	pdata.player[idx] = pdata.player[idx] or {}
	local pstate = pdata.player[idx]

	if hasAny then
		-- Create and cache split once per player per run
		if not pstate.split then
			pstate.split = computeRandomSplit(player)
			local s = pstate.split
			-- Debug: Log calculated split and final multipliers (English comments only)
			local cfg = ConchBlessing.aminus.data.config or {}
			local sumCheck = 0
			for stat, val in pairs(s) do sumCheck = sumCheck + (val or 0) end
			ConchBlessing.printDebug(string.format("[A-] Split multipliers sum=%.3f (target=%.3f, min=%.3f each)",
				sumCheck, cfg.totalMultSum or 4.0, cfg.minPerStat or 0.8))
			ConchBlessing.printDebug(string.format("[A-] Final multipliers -> Tears=x%.3f, Damage=x%.3f, Luck=x%.3f",
				s.Tears or 1.0, s.Damage or 1.0, s.Luck or 1.0))
		end

		-- Register multipliers with unified system (apply once; not scaled by trinket count)
		local um = ConchBlessing.stats.unifiedMultipliers
		local s = pstate.split
		if s.Tears then um:SetItemMultiplier(player, TID, "Tears", s.Tears, "A- Split (Tears)") end
		if s.Damage then um:SetItemMultiplier(player, TID, "Damage", s.Damage, "A- Split (Damage)") end
		if s.Luck then um:SetItemMultiplier(player, TID, "Luck", s.Luck, "A- Split (Luck)") end
	else
		-- Remove multipliers when trinket not present
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
	local hasAny = isCarryingTrinket(player, TID)
	if hasAny or hadBefore then
		player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_LUCK)
		player:EvaluateItems()
	end
end

return true