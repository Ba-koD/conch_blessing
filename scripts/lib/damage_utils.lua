local M = {}

-- Returns true if damage should be excluded from pause logic based on flags only
function M.isSelfInflictedDamage(flags)
	if flags == nil then return false end
	if (flags & DamageFlag.DAMAGE_CURSED_DOOR) ~= 0 then return true end
	if (flags & DamageFlag.DAMAGE_IV_BAG) ~= 0 then return true end
	if (flags & DamageFlag.DAMAGE_CHEST) ~= 0 then return true end
	if (flags & DamageFlag.DAMAGE_RED_HEARTS) ~= 0 then return true end
	if (flags & DamageFlag.DAMAGE_SPIKES) ~= 0 then return true end
	return false
end

return M