local M = {}

local function convertEntityTypeToHumanReadableKey(entityType)
	local key = ""

	if entityType == 1 then
		key = "Player"
	elseif entityType == 2 then
		key = "Tears"
	elseif entityType == 3 then
		key = "Familiars"
	elseif entityType == 4 then
		key = "Bomb Drops"
	elseif entityType == 5 then
		key = "Pickups"
	elseif entityType == 7 then
		key = "Lasers"
	elseif entityType == 9 then
		key = "Blood Projectiles"
	elseif entityType >= 10 and entityType <= 970 then
		key = "Enemies"
	end

	return key
end

local function isExcludedFlag(flag)
	return flag == 2097184
		or flag == 1342177284
		or flag == 269484032
		or flag == 33826849
		or flag == 268443649
end

function M.isSelfInflictedDamage(flags, source)
	local flag = flags or 0
	local entityTypeMapKey = ""
	if source and source.Type then
		entityTypeMapKey = convertEntityTypeToHumanReadableKey(source.Type)
	end

	local roomType = nil
	local game = Game()
	if game then
		local room = game:GetRoom()
		if room then
			roomType = room:GetType()
		end
	end

	local isSpike = (flag & DamageFlag.DAMAGE_SPIKES) ~= 0
	local isAcid = (flag & DamageFlag.DAMAGE_ACID) ~= 0
	local isExplosion = (flag & DamageFlag.DAMAGE_EXPLOSION) ~= 0
	local isTnt = (flag & DamageFlag.DAMAGE_TNT) ~= 0
	local isLittleHorns = flag == 524288

	local counted = entityTypeMapKey ~= ""
		or (isSpike and roomType ~= RoomType.ROOM_SACRIFICE)
		or isAcid
		or isExplosion
		or isTnt
		or isLittleHorns

	if not counted then
		return true
	end

	if isExcludedFlag(flag) then
		return true
	end

	return false
end

return M
