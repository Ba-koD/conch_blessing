local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
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
	-- Per-player runtime state keyed by the player entity (GetPtrHash) and
	-- rebuilt every session. The split itself lives in the player's own run
	-- save, so two holders of one controller (Jacob & Esau, Strawman, a second
	-- player of the same character) each get their own multipliers.
	player = {}
}

local function getTrinketIdByName(name)
	local ok, id = pcall(function()
		return Isaac.GetTrinketIdByName(name)
	end)
	return ok and id or nil
end

local TID = getTrinketIdByName("A -")
local TID_B = getTrinketIdByName("B -")
local Hits = require("scripts.lib.player_hits")
local TrinketUtils = ConchBlessing.TrinketUtils or require("scripts.lib.trinket_utils")

-- Get trinket total effective count (includes golden and Mom's Box)
local function getCount(player, baseId)
	return TrinketUtils.getMultiplier(player, baseId)
end

-- Determine if player has the trinket effect (includes smelted and golden counts)
local function hasTrinketEffect(player, baseId)
	return getCount(player, baseId) > 0
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

local function getPlayerState(player)
	local store = ConchBlessing.aminus.data.player
	local key = GetPtrHash(player)
	store[key] = store[key] or {}
	return store[key]
end

-- Apply or remove unified multipliers when the trinket effect starts or ends.
-- Returns true when the player's stats need a new evaluation.
local function updatePlayerMultipliers(player)
	if not player or not ConchBlessing or not ConchBlessing.stats or not ConchBlessing.stats.unifiedMultipliers then return false end
	if not TID or TID <= 0 then return false end

	local count = getCount(player, TID)
	local pstate = getPlayerState(player)
	-- The flat additions scale with the multiplier (golden, Mom's Box, smelted).
	local changed = pstate.count ~= nil and pstate.count ~= count
	pstate.count = count

	if count > 0 then
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

		-- Apply as first-use multipliers (xV) only once per run unless split changes
		if not pstate.applied then
			local um = ConchBlessing.stats.unifiedMultipliers
			local s = pstate.split
			if s.Tears then um:SetItemMultiplier(player, TID, "Tears", s.Tears, "A- Split (Tears)") end
			if s.Damage then um:SetItemMultiplier(player, TID, "Damage", s.Damage, "A- Split (Damage)") end
			if s.Luck then um:SetItemMultiplier(player, TID, "Luck", s.Luck, "A- Split (Luck)") end
			-- Persist unified multipliers so they are applied on load
			um:SaveToSaveManager(player)
			pstate.applied = true
			changed = true
		end
	elseif pstate.applied or not pstate.cleared then
		-- Remove multipliers once when the trinket effect ends (and once per
		-- session, in case a saved multiplier outlived its trinket).
		local um = ConchBlessing.stats.unifiedMultipliers
		um:RemoveItemMultiplier(player, TID, "Tears")
		um:RemoveItemMultiplier(player, TID, "Damage")
		um:RemoveItemMultiplier(player, TID, "Luck")
		changed = changed or pstate.applied == true
		pstate.split = nil
		pstate.applied = nil
		pstate.cleared = true
	end
	if count > 0 then pstate.cleared = nil end
	return changed
end

function ConchBlessing.aminus.onPostPEffectUpdate(_, player)
	if not player or not TID or TID <= 0 then return end
	if updatePlayerMultipliers(player) then
		player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_LUCK)
		player:EvaluateItems()
	end
end

-- Entity hashes from an earlier session mean nothing now.
function ConchBlessing.aminus.onGameStarted()
	ConchBlessing.aminus.data.player = {}
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
    local statKey = (cacheFlag == CacheFlag.CACHE_DAMAGE and "Damage")
        or (cacheFlag == CacheFlag.CACHE_FIREDELAY and "Tears")
        or (cacheFlag == CacheFlag.CACHE_LUCK and "Luck")
        or nil
    local total = ConchBlessing.getUnifiedStatTotal(player, statKey, 1.0, um)

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

local function heldCount(player, exactId)
	local n = 0
	for slot = 0, 1 do
		if player:GetTrinket(slot) == exactId then n = n + 1 end
	end
	return n
end

local function findHeldA(player)
	for slot = 0, 1 do
		local raw = tonumber(player:GetTrinket(slot)) or 0
		if raw > 0 and TrinketUtils.baseIdOf(raw) == TID then return raw end
	end
	return nil
end

-- Carried copies drop to the ground as B-, keeping their golden state.
-- Removing slot 0 moves slot 1 forward, so the slots are read again each time.
local function demoteHeld(player)
	local demoted = 0
	for attempt = 1, 2 do
		local raw = findHeldA(player)
		if not raw then break end
		local before = heldCount(player, raw)
		player:TryRemoveTrinket(raw)
		if heldCount(player, raw) >= before then
			ConchBlessing.printError(string.format("[A-] held trinket %d could not be removed for demotion", raw))
			break
		end
		local _, isGolden = TrinketUtils.baseIdOf(raw)
		local newId = TID_B + (isGolden and TrinketUtils.GOLDEN_FLAG or 0)
		local offset = (attempt == 1) and Vector(-20, 0) or Vector(20, 0)
		Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, newId, player.Position + offset, Vector.Zero, player)
		demoted = demoted + 1
	end
	return demoted
end

-- A real hit demotes a carried A- to B- (self-damage and Sacrifice Room spikes
-- are not hits, scripts/lib/player_hits.lua). A smelted A- is fixed for good and
-- keeps its effect (user rule, 2026-10-23).
Hits.register("A_MINUS", function(_, ent, amount, flags, src, countdown)
	local player = ent and ent:ToPlayer() or nil
	if not player then return end
	if not Hits.counts(flags) then
		return
	end
	if not TID or TID <= 0 then return end
	if not TID_B or TID_B <= 0 then return end
	if not hasTrinketEffect(player, TID) then return end

	return demoteHeld(player) > 0
end)

-- Test hooks for scripts/dev/rng_probe.lua. Pure helpers, no gameplay use.
ConchBlessing.aminus._test = { computeRandomSplit = computeRandomSplit, demoteHeld = demoteHeld,
	updatePlayerMultipliers = updatePlayerMultipliers }
return true
