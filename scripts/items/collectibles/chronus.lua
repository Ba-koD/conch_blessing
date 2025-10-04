ConchBlessing.chronus = ConchBlessing.chronus or {}

-- Data: configuration and runtime state container
ConchBlessing.chronus.data = {
	-- Base config
    damagePerFamiliar = 2.0,        -- addition per absorbed familiar
	absorbAll = true,               -- if false, use blacklist to skip some familiars

	-- Sprite/visual config (path exists under game resources)
	spriteNullPath = "gfx/ui/null.png",

	-- Offsets for any potential anchored helpers (kept as data only)
	pairOffsetPixels = 2.0,
    laserEyeYOffset = -6,
	anchorDepthOffset = -10,
	-- Scan interval to re-check inventory (frames)
	scanIntervalFrames = 15,

    -- Blacklist: familiars NOT to absorb/remove (by CollectibleType)
    blacklist = {
        [CollectibleType.COLLECTIBLE_ONE_UP] = true,
        [CollectibleType.COLLECTIBLE_ISAACS_HEART] = true,
        [CollectibleType.COLLECTIBLE_DEAD_CAT] = true,
        [CollectibleType.COLLECTIBLE_KEY_PIECE_1] = true,
        [CollectibleType.COLLECTIBLE_KEY_PIECE_2] = true,
        [CollectibleType.COLLECTIBLE_KNIFE_PIECE_1] = true,
        [CollectibleType.COLLECTIBLE_KNIFE_PIECE_2] = true,
    },

	-- Absorb actions: key = familiar collectible id, value = function(player, totalAbsorbedForThisId, deltaAbsorbedNow)
	absorbActions = {
		-- Example:
		-- [CollectibleType.COLLECTIBLE_BROTHER_BOBBY] = function(player, total, delta)
		-- 	-- English comment: increase Tears slightly per absorbed copy
		-- 	ConchBlessing.stats.unifiedMultipliers:SetItemAddition(player, Isaac.GetItemIdByName("Chronus"), "Tears", 0.1 * delta, "Chronus: Brother Bobby")
		-- end,
	}
}

local CHRONUS_ID = Isaac.GetItemIdByName("Chronus")

-- Save helpers (run-scope per player)
local function getRunSave(player)
    local SaveManager = ConchBlessing.SaveManager
    local save = SaveManager and SaveManager.GetRunSave and SaveManager.GetRunSave(player) or nil
    if save then
        save.chronus = save.chronus or { absorbed = {}, totalAbsorbed = 0 }
        return save.chronus
    end
    return { absorbed = {}, totalAbsorbed = 0 }
end

-- Public registration helpers
function ConchBlessing.chronus.registerAbsorbAction(familiarCollectibleId, fn)
	if type(familiarCollectibleId) ~= "number" then return end
	if type(fn) ~= "function" then return end
	ConchBlessing.chronus.data.absorbActions[familiarCollectibleId] = fn
end

function ConchBlessing.chronus.addToBlacklist(familiarCollectibleId)
	if type(familiarCollectibleId) ~= "number" then return end
	ConchBlessing.chronus.data.blacklist[familiarCollectibleId] = true
end

-- Callbacks (kept as stubs to satisfy registrations elsewhere)
ConchBlessing.chronus.onPostGetCollectible = function(_, collectible, pool, decrease, seed)
	-- English comment: absorb immediately when a new collectible is granted
    local player = Isaac.GetPlayer(0)
	if not (player and player:HasCollectible(CHRONUS_ID)) then return end
	if type(collectible) ~= "number" then return end
    local cfg = Isaac.GetItemConfig():GetCollectible(collectible)
    if cfg and cfg.Type == ItemType.ITEM_FAMILIAR then
        local owned = player:GetCollectibleNum(collectible, true)
        if owned and owned > 0 then
            local frame = Game():GetFrameCount()
            local pdata = player:GetData()
            pdata.__chronusAbsorbFrame = frame
            local changed = ConchBlessing.chronus._absorbFamiliar(player, collectible, owned) or false
            if changed then
                ConchBlessing.chronus._finalizeAbsorb(player)
            end
        end
    end
end

ConchBlessing.chronus.onPickup = function(_, player, collectibleType, rng)
    if collectibleType ~= CHRONUS_ID then return end
    ConchBlessing.printDebug("[Chronus] Picked up - performing initial familiar sweep")
    local changed = ConchBlessing.chronus._detectAndAbsorb(player)
    if changed then
        ConchBlessing.chronus._finalizeAbsorb(player)
    end
end

ConchBlessing.chronus.onPlayerUpdate = function(_)
	local game = Game()
	local frame = game:GetFrameCount()
	local numPlayers = game:GetNumPlayers()
    for i = 0, numPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player and player:HasCollectible(CHRONUS_ID) then
            local pdata = player:GetData()
            -- Skip scan on the same frame as absorb to avoid double application
            if pdata.__chronusAbsorbFrame == frame then goto continue_player end
			local interval = tonumber(ConchBlessing.chronus.data.scanIntervalFrames) or 15
			pdata.__chronusNextScan = pdata.__chronusNextScan or 0
            if frame >= pdata.__chronusNextScan then
                pdata.__chronusNextScan = frame + interval
                local changed = ConchBlessing.chronus._detectAndAbsorb(player)
                if changed then
                    ConchBlessing.chronus._finalizeAbsorb(player)
                end
            end

			-- Ensure/update Incubus pairs for absorbed Twisted Pair
			ConchBlessing.chronus._ensureIncubusPairs(player)
			ConchBlessing.chronus._updateIncubusAnchors(player)
            ::continue_player::
        end
    end
end

ConchBlessing.chronus.onEvaluateCache = function(_, player, cacheFlag)
	-- Intentionally left empty (data-driven behavior only)
end

ConchBlessing.chronus.onGameStarted = function(_)
	-- English comment: Debug current configuration values (no hardcoded numbers)
	local d = ConchBlessing.chronus.data
	if ConchBlessing and ConchBlessing.Config and ConchBlessing.Config.debugMode then
		local blacklistCount = 0
		for _ in pairs(d.blacklist or {}) do blacklistCount = blacklistCount + 1 end
		local actionsCount = 0
		for _ in pairs(d.absorbActions or {}) do actionsCount = actionsCount + 1 end
		ConchBlessing.printDebug(string.format(
			"[Chronus] Config loaded: dmgPerFam=%.3f absorbAll=%s blacklist=%d actions=%d offset=%.2f eyeY=%d null='%s'",
			tonumber(d.damagePerFamiliar) or 0,
			tostring(d.absorbAll),
			blacklistCount,
			actionsCount,
			tonumber(d.pairOffsetPixels) or 0,
			tonumber(d.laserEyeYOffset) or 0,
			tostring(d.spriteNullPath or "")))
	end
end

-- Internal: gather familiar-type collectibles currently owned
function ConchBlessing.chronus._getFamiliarCounts(player)
	local cfg = Isaac.GetItemConfig()
	local counts = {}
	local list = cfg:GetCollectibles()
	for id = 1, list.Size - 1 do
		local item = cfg:GetCollectible(id)
		if item and item.Type == ItemType.ITEM_FAMILIAR then
			local owned = player:GetCollectibleNum(id, true)
			if owned and owned > 0 then
				counts[id] = owned
			end
        end
    end
	return counts
end

-- Internal: absorb a delta amount for a specific familiar collectible id
function ConchBlessing.chronus._absorbFamiliar(player, famId, delta)
	if not (player and type(famId) == "number" and type(delta) == "number") then return end
	if delta <= 0 then return end
	local data = ConchBlessing.chronus.data
	-- Respect blacklist
    if (data.blacklist and data.blacklist[famId]) then
        return false
	end
	-- Remove collectibles
    for i = 1, delta do
		player:RemoveCollectible(famId)
	end
	-- Save progress
	local save = getRunSave and getRunSave(player) or nil
	if save then
		save.absorbed[famId] = (save.absorbed[famId] or 0) + delta
		save.totalAbsorbed = (save.totalAbsorbed or 0) + delta
	end
	-- Apply base damage per familiar
	local addDamage = (tonumber(data.damagePerFamiliar) or 0) * delta
	if addDamage ~= 0 then
		ConchBlessing.stats.unifiedMultipliers:SetItemAddition(player, CHRONUS_ID, "Damage", addDamage, "Chronus: Base per familiar")
	end
	-- Run custom action if registered
	local action = data.absorbActions and data.absorbActions[famId]
	if type(action) == "function" then
		local total = save and save.absorbed[famId] or delta
		action(player, total, delta)
	end
	-- Debug: log absorb event
    if ConchBlessing and ConchBlessing.Config and ConchBlessing.Config.debugMode then
		ConchBlessing.printDebug(string.format("[Chronus] Absorbed familiar id=%d delta=%d (+%.3f damage)", famId, delta, addDamage))
	end
    return true
end

-- Internal: scan and absorb all owned familiar-type collectibles
function ConchBlessing.chronus._detectAndAbsorb(player)
    if not player then return false end
    local changed = false
    local counts = ConchBlessing.chronus._getFamiliarCounts(player)
    for famId, owned in pairs(counts) do
        if owned and owned > 0 then
            local absorbed = ConchBlessing.chronus._absorbFamiliar(player, famId, owned)
            changed = absorbed or changed
        end
    end
    return changed
end

-- Internal: finalize after a batch of absorbs (trigger cache re-eval)
function ConchBlessing.chronus._finalizeAbsorb(player)
	if not player then return end
	player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_LUCK | CacheFlag.CACHE_SPEED | CacheFlag.CACHE_RANGE | CacheFlag.CACHE_SHOTSPEED | CacheFlag.CACHE_TEARCOLOR | CacheFlag.CACHE_TEARFLAG | CacheFlag.CACHE_FAMILIARS)
	player:EvaluateItems()
end

-- Internal: get total absorbed count for a specific collectible id
function ConchBlessing.chronus._getAbsorbedCount(player, collectibleId)
	local save = getRunSave and getRunSave(player) or nil
	if not (save and save.absorbed) then return 0 end
	return tonumber(save.absorbed[collectibleId] or 0) or 0
end

-- Internal: spawn an Incubus familiar and make it invisible
local function _spawnInvisibleIncubus(player, pairIndex, side)
	local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.INCUBUS, 0, player.Position, Vector.Zero, player)
	local fam = ent and ent:ToFamiliar() or nil
	if not fam then
		if ent then ent:Remove() end
		return nil
	end
	fam.Player = player
	fam:AddToFollowers()
	fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
	-- Replace sprite with null and set alpha to 0
	local spr = fam:GetSprite()
	local nullPath = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
	for i = 0, 10 do
		pcall(function() spr:ReplaceSpritesheet(i, nullPath) end)
	end
	pcall(function() spr:LoadGraphics() end)
	fam.Color = Color(1, 1, 1, 0)
	-- Tag metadata
	local fd = fam:GetData()
	fd.__chronusIncubus = true
	fd.__chronusPairIndex = tonumber(pairIndex) or 1
	fd.__chronusSide = tonumber(side) or 1
	return fam
end

-- Internal: ensure we have 2 Incubi per absorbed Twisted Pair (left/right per pair)
function ConchBlessing.chronus._ensureIncubusPairs(player)
	if not player then return end
	local absorbedPairs = ConchBlessing.chronus._getAbsorbedCount(player, CollectibleType.COLLECTIBLE_TWISTED_PAIR)
	local targetIncubi = math.max(0, absorbedPairs * 2)
	local pdata = player:GetData()
	pdata.__chronusIncubi = pdata.__chronusIncubi or {}
	-- Prune dead/foreign entries
	local kept = {}
	for _, fam in ipairs(pdata.__chronusIncubi) do
		if fam and fam:Exists() and fam:ToFamiliar() then
			local fd = fam:GetData()
			if fd and fd.__chronusIncubus then table.insert(kept, fam) end
		end
	end
	pdata.__chronusIncubi = kept
	-- Spawn missing
	local current = #pdata.__chronusIncubi
	while current < targetIncubi do
		local nextIndex = math.floor(current / 2) + 1
		local side = (current % 2 == 0) and 1 or -1
		local f = _spawnInvisibleIncubus(player, nextIndex, side)
		if not f then break end
		table.insert(pdata.__chronusIncubi, f)
		current = current + 1
	end
	-- Remove excess
	while #pdata.__chronusIncubi > targetIncubi do
		local f = table.remove(pdata.__chronusIncubi)
		if f and f:Exists() then f:Remove() end
    end
end

-- Internal: update Incubi positions to offset anchors
function ConchBlessing.chronus._updateIncubusAnchors(player)
	if not player then return end
    local pdata = player:GetData()
	local list = pdata.__chronusIncubi
	if not (list and #list > 0) then return end
	-- Compute perpendicular to aim
	local aim = player:GetShootingInput()
	if not (aim and aim:Length() > 0) then aim = player:GetAimDirection() end
	if not (aim and aim:Length() > 0) then aim = Vector(1, 0) end
	local dir = aim:Normalized()
    local perp = Vector(-dir.Y, dir.X)
    if perp:Length() > 0 then perp = perp:Normalized() end
	local baseOffset = tonumber(ConchBlessing.chronus.data.pairOffsetPixels) or 0
	local eyeY = tonumber(ConchBlessing.chronus.data.laserEyeYOffset) or 0
	local depth = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
	for _, fam in ipairs(list) do
		if fam and fam:Exists() then
			local fd = fam:GetData() or {}
			local pairIndex = tonumber(fd.__chronusPairIndex) or 1
			local side = tonumber(fd.__chronusSide) or 1
			local offset = baseOffset * pairIndex
			local anchor = player.Position + Vector(0, eyeY) + perp * (offset * side)
			fam.Position = anchor
			fam.DepthOffset = depth
		end
        end
    end
