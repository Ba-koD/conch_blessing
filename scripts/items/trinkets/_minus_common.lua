local M = {}

local function getTrinketIdByName(name)
	local ok, id = pcall(function()
		return Isaac.GetTrinketIdByName(name)
	end)
	return ok and id or nil
end

local function getCount(player, baseId)
	if not player or not baseId then return 0 end
	local ok, n = pcall(function()
		return player:GetTrinketMultiplier(baseId) or 0
	end)
	return ok and n or 0
end

 -- cfg: { name, luckAdd, tearsAdd, damageAdd, damageMult, luckMult }
function M.registerTrinket(cfg)
	if not cfg or not cfg.name then return end
	local tid = getTrinketIdByName(cfg.name)
	if not tid or tid <= 0 then return end

	ConchBlessing.printDebug(string.format("[MinusTrinket] Register %s (id=%s)", tostring(cfg.name), tostring(tid)))

    ConchBlessing.originalMod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, cacheFlag)
        local count = getCount(player, tid)
        if count <= 0 then return end

        -- IMPORTANT: GetTrinketMultiplier already includes Golden and Mom's Box.
        -- Do NOT add extra scaling again. Use 'count' only for additive effects.

        -- Apply per-flag
        if cacheFlag == CacheFlag.CACHE_LUCK then
			local base = tonumber(cfg.luckAdd)
			if base and base ~= 0 then
                local total = base * count
				ConchBlessing.stats.luck.applyAddition(player, total, nil)
			end
            local lmult = tonumber(cfg.luckMult)
            if lmult and lmult ~= 0 and lmult ~= 1 then
                -- Apply once; unaffected by Golden/Mom's Box and count
                ConchBlessing.stats.luck.applyMultiplier(player, lmult, nil, false)
            end
		elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
			local base = tonumber(cfg.tearsAdd)
			if base and base ~= 0 then
                local total = base * count
				ConchBlessing.stats.tears.applyAddition(player, total, nil)
			end
		elseif cacheFlag == CacheFlag.CACHE_DAMAGE then
			-- additive first
			local add = tonumber(cfg.damageAdd)
			if add and add ~= 0 then
                local totalAdd = add * count
				ConchBlessing.stats.damage.applyAddition(player, totalAdd, nil)
			end
            -- then multiplicative (apply ONCE; unaffected by Golden/Mom's Box and count)
			local mult = tonumber(cfg.damageMult)
			if mult and mult ~= 0 and mult ~= 1 then
                ConchBlessing.stats.damage.applyMultiplier(player, mult, nil, false)
			end
		end
	end)

	-- Ensure cache re-evaluation when trinket state changes
	ConchBlessing.originalMod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, function(_, player)
		-- If the player has this trinket, ensure caches are evaluated
		if getCount(player, tid) > 0 then
			player:AddCacheFlags(CacheFlag.CACHE_LUCK | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_DAMAGE)
			player:EvaluateItems()
		end
	end)
end

return M

