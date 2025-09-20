local M = {}

-- Returns normalCount, goldenCount, hasMomsBox for a given trinket ID
function M.getTrinketCounts(player, trinketId)
	if not player or not trinketId then return 0, 0, false end

	local hasMomsBox = player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_BOX)
	local rawMult = player:GetTrinketMultiplier(trinketId) or 0
	local goldenId = trinketId + 32768
	local goldenRaw = player:GetTrinketMultiplier(goldenId) or 0

	-- Mom's Box adds +1 effective stack; remove it before deriving counts
	local momsBoxStack = hasMomsBox and 1 or 0
	local goldenStacks = goldenRaw - momsBoxStack
	if goldenStacks < 0 then goldenStacks = 0 end
	local goldenCount = math.floor(goldenStacks / 2)

	local normalCount = rawMult - (2 * goldenCount) - momsBoxStack
	if normalCount < 0 then normalCount = 0 end

	return normalCount, goldenCount, hasMomsBox
end

return M