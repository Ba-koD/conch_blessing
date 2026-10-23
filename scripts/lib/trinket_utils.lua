local M = {}

local GOLDEN_FLAG = (TrinketType and TrinketType.TRINKET_GOLDEN_FLAG) or 32768

local function baseIdOf(raw)
	if raw >= GOLDEN_FLAG then return raw - GOLDEN_FLAG, true end
	return raw, false
end

-- The engine's own effect count for a trinket (EntityPlayer:GetTrinketMultiplier):
-- +1 per normal copy held or smelted, +2 per golden copy, and +1 once for
-- Mom's Box, which does not stack with the number of copies.
function M.getMultiplier(player, trinketId)
	if not player or not trinketId then return 0 end
	local ok, n = pcall(function()
		return player:GetTrinketMultiplier(trinketId)
	end)
	n = ok and tonumber(n) or 0
	return n > 0 and n or 0
end

-- Smelted normal and golden copies of a trinket from REPENTOGON's
-- GetSmeltedTrinkets, or nil without it: the base API cannot tell a smelted
-- golden copy from two smelted normal ones.
local function getSmeltedCounts(player, trinketId)
	if not player or not trinketId or type(player.GetSmeltedTrinkets) ~= "function" then return nil end
	local ok, smelted = pcall(function() return player:GetSmeltedTrinkets() end)
	if not ok or type(smelted) ~= "table" then return nil end
	local entry = smelted[trinketId]
	if type(entry) ~= "table" then return 0, 0 end
	return math.max(0, tonumber(entry.trinketAmount) or 0), math.max(0, tonumber(entry.goldenTrinketAmount) or 0)
end
M.getSmeltedCounts = getSmeltedCounts

-- Returns normalCount, goldenCount, hasMomsBox for a given trinket ID, so that
-- normal + 2 * golden (+1 for Mom's Box) equals GetTrinketMultiplier. Held
-- copies come from the exact slot IDs; smelted ones from REPENTOGON when it is
-- present. Whatever else the multiplier counts (smelted copies without
-- REPENTOGON, innate trinkets) is reported as normal copies.
function M.getTrinketCounts(player, trinketId)
	if not player or not trinketId then return 0, 0, false end

	local hasMomsBox = player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_BOX)
	local total = M.getMultiplier(player, trinketId)
	if total <= 0 then return 0, 0, hasMomsBox end

	local normalCount, goldenCount = 0, 0
	for slot = 0, 1 do
		local raw = tonumber(player:GetTrinket(slot)) or 0
		if raw > 0 then
			local baseId, isGolden = baseIdOf(raw)
			if baseId == trinketId then
				if isGolden then goldenCount = goldenCount + 1 else normalCount = normalCount + 1 end
			end
		end
	end
	local smeltedNormal, smeltedGolden = getSmeltedCounts(player, trinketId)
	if smeltedNormal then
		normalCount = normalCount + smeltedNormal
		goldenCount = goldenCount + smeltedGolden
	end

	local rest = total - (hasMomsBox and 1 or 0) - normalCount - 2 * goldenCount
	if rest > 0 then normalCount = normalCount + rest end

	return normalCount, goldenCount, hasMomsBox
end

M.GOLDEN_FLAG = GOLDEN_FLAG
M.baseIdOf = baseIdOf

-- Older saves kept a record under the player's PlayerType ("0", "8", ...)
-- inside that player's own run save. Removes those records from `container`
-- and returns them as { type = "8", rec = {...} } sorted by type, so the caller
-- can fold them into the flat per-player record once.
function M.popPlayerTypeRecords(container)
	local legacy = {}
	if type(container) ~= "table" then return legacy end
	for key, rec in pairs(container) do
		if type(key) == "string" and key:match("^%-?%d+$") and type(rec) == "table" then
			legacy[#legacy + 1] = { type = key, rec = rec }
		end
	end
	table.sort(legacy, function(a, b) return tonumber(a.type) < tonumber(b.type) end)
	for _, entry in ipairs(legacy) do container[entry.type] = nil end
	return legacy
end

-- Folds the legacy PlayerType records of a Time trinket into its flat record.
-- The record of the player's current type keeps the held bonus and the pause;
-- what was earned under an earlier type (Lazarus, Clicker) stays earned, as a
-- permanent bonus. Returns true when anything was migrated.
function M.migrateTimeRecord(container, currentType, bonusField, keepOnDrop)
	local legacy = M.popPlayerTypeRecords(container)
	if #legacy == 0 then return false end
	local current
	for _, entry in ipairs(legacy) do
		if entry.type == tostring(currentType) then current = entry.rec end
	end
	local permanent = tonumber(container.permanentBonus) or 0
	for _, entry in ipairs(legacy) do
		local rec = entry.rec
		permanent = permanent + (tonumber(rec.permanentBonus) or 0)
		if rec ~= current and keepOnDrop ~= false then
			permanent = permanent + (tonumber(rec[bonusField]) or 0)
		end
	end
	container.permanentBonus = permanent
	container[bonusField] = (tonumber(container[bonusField]) or 0) + (current and tonumber(current[bonusField]) or 0)
	local source = current or legacy[1].rec
	if container.pauseFramesRemaining == nil and current then
		container.pauseFramesRemaining = tonumber(current.pauseFramesRemaining)
	end
	if container.lastApplied == nil and current then container.lastApplied = current.lastApplied end
	if container.data == nil and type(source.data) == "table" then container.data = source.data end
	return true
end

return M
