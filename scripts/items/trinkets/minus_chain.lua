local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Evolution chain for Minus trinkets: F- -> C- -> B- -> A-
-- Evolves on new floor if the player took no damage in the previous floor

local M = {}

if ConchBlessing and ConchBlessing._minusChainRegistered then
	return true
end

local Hits = require("scripts.lib.player_hits")

local function idByName(name)
	local ok, id = pcall(function()
		return Isaac.GetTrinketIdByName(name)
	end)
	return ok and id or -1
end

local TID_F = idByName("F -")
local TID_C = idByName("C -")
local TID_B = idByName("B -")
local TID_A = idByName("A -")

local CHAIN_NEXT = {}
if TID_F and TID_F > 0 and TID_C and TID_C > 0 then CHAIN_NEXT[TID_F] = TID_C end
if TID_C and TID_C > 0 and TID_B and TID_B > 0 then CHAIN_NEXT[TID_C] = TID_B end
if TID_B and TID_B > 0 and TID_A and TID_A > 0 then CHAIN_NEXT[TID_B] = TID_A end

ConchBlessing._minusNoHit = ConchBlessing._minusNoHit or {}

local HELD_KEYS = { { TID_F, "F_MINUS" }, { TID_C, "C_MINUS" }, { TID_B, "B_MINUS" } }

-- Mark damage taken; self-damage and Sacrifice Room spikes are not hits
-- (scripts/lib/player_hits.lua). Shows the icon of each minus trinket it affects.
Hits.register("MINUS_CHAIN", function(_, ent, amount, flags, src, countdown)
	local player = ent and ent:ToPlayer() or nil
	if not player then return end
	
	if not Hits.counts(flags) then
		ConchBlessing.printDebug(string.format("[MinusChain] Ignored self-inflicted damage (flags=%d)", flags or -1))
		return
	end
	
	local idx = player.ControllerIndex or 0
	ConchBlessing._minusNoHit[idx] = false
	ConchBlessing.printDebug(string.format("[MinusChain] Player took damage, noHit[%d] = false", idx))
	local held = {}
	for _, pair in ipairs(HELD_KEYS) do
		if pair[1] and pair[1] > 0 and player:HasTrinket(pair[1]) then held[#held + 1] = pair[2] end
	end
	return #held > 0 and held or nil
end)

-- Initialize flag at game start
ConchBlessing.originalMod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
	local game = Game()
	for i = 0, game:GetNumPlayers() - 1 do
		local p = game:GetPlayer(i)
		if p then
			ConchBlessing._minusNoHit[p.ControllerIndex or i] = true
		end
	end
end)

-- On new level: evolve if no damage taken
ConchBlessing.originalMod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local p = game:GetPlayer(i)
        if p then
            local idx = p.ControllerIndex or i
            local noHit = ConchBlessing._minusNoHit[idx]
            -- Reset for next floor early
            ConchBlessing._minusNoHit[idx] = true
            if not noHit then goto continue end

            -- Only evolve carried trinkets (not smelted): drop on ground and evolve, keep golden state
            for slot = 0, 1 do
                local raw = p:GetTrinket(slot)
                if raw and raw > 0 then
                    local baseId = raw
                    local isGolden = false
                    if raw >= 32768 then
                        baseId = raw - 32768
                        isGolden = true
                    end
                    local toId = CHAIN_NEXT[baseId]
                    if toId then
                        -- remove the carried instance in this slot
                        p:TryRemoveTrinket(raw)
                        -- spawn evolved trinket on the ground near player
                        local offset = (slot == 0) and Vector(-20, 0) or Vector(20, 0)
                        local newId = toId + (isGolden and 32768 or 0)
                        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, newId, p.Position + offset, Vector.Zero, p)
                    end
                end
            end
        end
        ::continue::
    end
end)

ConchBlessing._minusChainRegistered = true
return true
