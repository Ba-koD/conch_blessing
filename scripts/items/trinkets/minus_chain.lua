local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Evolution chain for Minus trinkets: F- -> C- -> B- -> A-
-- Evolves on new floor if the player took no damage in the previous floor

if ConchBlessing and ConchBlessing._minusChainRegistered then
	return true
end

local M = {}
ConchBlessing.minuschain = M

local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local Hits = require("scripts.lib.player_hits")
local TrinketUtils = ConchBlessing.TrinketUtils or require("scripts.lib.trinket_utils")

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

local HELD_KEYS = { { TID_F, "F_MINUS" }, { TID_C, "C_MINUS" }, { TID_B, "B_MINUS" } }

-- Whether a player was hit on this floor lives in that player's own floor save
-- (SaveManager keys it by the player's collectible RNG seed). Continue keeps an
-- earlier hit, and Jacob & Esau, Strawman or two players of one character each
-- evolve on their own.
local HIT_KEY = "minusChainHit"

-- The first MC_POST_NEW_LEVEL of a run fires before MC_POST_GAME_STARTED, while
-- SaveManager can still expose the previous run's table. A luamod reload in the
-- middle of a run never sees game start, so it opens at once.
M._runReady = type(Isaac.IsInGame) == "function" and Isaac.IsInGame() == true

-- Per-player result of the floor that just ended, keyed by GetPtrHash. Taken
-- just before SaveManager clears the floor saves for the new floor.
local endedFloor = nil

local function wasHit(player)
	local save = SaveManager.GetFloorSave(player)
	return type(save) == "table" and save[HIT_KEY] == true
end

-- True while the player has not been hit on this floor.
function M.noHit(player)
	return player ~= nil and not wasHit(player)
end

-- Bench helper: marks (noHit = false) or clears (noHit = true) this floor's hit.
function M.setNoHit(player, noHit)
	local save = player and SaveManager.GetFloorSave(player)
	if type(save) ~= "table" then return false end
	save[HIT_KEY] = (noHit == false) or nil
	return true
end

-- Mark damage taken; self-damage and Sacrifice Room spikes are not hits
-- (scripts/lib/player_hits.lua). Shows the icon of each minus trinket it affects.
Hits.register("MINUS_CHAIN", function(_, ent, amount, flags, src, countdown)
	local player = ent and ent:ToPlayer() or nil
	if not player then return end

	if not Hits.counts(flags) then
		ConchBlessing.printDebug(string.format("[MinusChain] Ignored self-inflicted damage (flags=%d)", flags or -1))
		return
	end

	local save = SaveManager.GetFloorSave(player)
	if type(save) == "table" and save[HIT_KEY] ~= true then
		save[HIT_KEY] = true
		SaveManager.Save()
		ConchBlessing.printDebug("[MinusChain] Player took damage; no evolution after this floor")
	end
	local held = {}
	for _, pair in ipairs(HELD_KEYS) do
		if pair[1] and pair[1] > 0 and player:HasTrinket(pair[1]) then held[#held + 1] = pair[2] end
	end
	return #held > 0 and held or nil
end)

local function heldCount(player, exactId)
	local n = 0
	for slot = 0, 1 do
		if player:GetTrinket(slot) == exactId then n = n + 1 end
	end
	return n
end

local function findEvolvable(player)
	for slot = 0, 1 do
		local raw = tonumber(player:GetTrinket(slot)) or 0
		if raw > 0 and CHAIN_NEXT[(TrinketUtils.baseIdOf(raw))] then return raw end
	end
	return nil
end

-- Only carried trinkets evolve (not smelted): each one is dropped on the ground
-- as the next grade, keeping its golden state. Removing slot 0 moves slot 1
-- forward, so the slots are read again after every removal.
local function evolveHeld(player)
	for attempt = 1, 2 do
		local raw = findEvolvable(player)
		if not raw then return end
		local before = heldCount(player, raw)
		player:TryRemoveTrinket(raw)
		if heldCount(player, raw) >= before then
			ConchBlessing.printError(string.format("[MinusChain] held trinket %d could not be removed for evolution", raw))
			return
		end
		local baseId, isGolden = TrinketUtils.baseIdOf(raw)
		local newId = CHAIN_NEXT[baseId] + (isGolden and TrinketUtils.GOLDEN_FLAG or 0)
		local offset = (attempt == 1) and Vector(-20, 0) or Vector(20, 0)
		Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, newId, player.Position + offset, Vector.Zero, player)
	end
end

M._test = { evolveHeld = evolveHeld }

-- SaveManager clears every floor save inside its own MC_POST_NEW_LEVEL, which
-- runs before ours; read each player's result for the ending floor first.
if SaveManager.SaveCallbacks and SaveManager.SaveCallbacks.PRE_FLOOR_DATA_RESET then
	ConchBlessing.originalMod:AddCallback(SaveManager.SaveCallbacks.PRE_FLOOR_DATA_RESET, function()
		endedFloor = nil
		if not M._runReady then return end
		local game = Game()
		local result = {}
		for i = 0, game:GetNumPlayers() - 1 do
			local p = game:GetPlayer(i)
			if p then result[GetPtrHash(p)] = not wasHit(p) end
		end
		endedFloor = result
	end)
else
	ConchBlessing.printError("[MinusChain] SaveManager has no PRE_FLOOR_DATA_RESET; minus trinkets cannot evolve")
end

ConchBlessing.originalMod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
	M._runReady = true
	endedFloor = nil
end)

ConchBlessing.originalMod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
	M._runReady = false
	endedFloor = nil
end)

-- On new level: evolve if no damage taken. A player without a result for the
-- ending floor (one that joined on this transition) does not evolve. A Glowing
-- Hourglass rewind across a floor still runs SaveManager's floor reset, so a
-- held trinket can evolve again there, as it did before the flag moved into
-- the floor save (not verified in game).
ConchBlessing.originalMod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
	local ended = endedFloor
	endedFloor = nil
	if not M._runReady or not ended then return end
	local game = Game()
	for i = 0, game:GetNumPlayers() - 1 do
		local p = game:GetPlayer(i)
		if p and ended[GetPtrHash(p)] == true then
			evolveHeld(p)
		end
	end
end)

ConchBlessing._minusChainRegistered = true
return true
