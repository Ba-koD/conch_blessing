-- Thurisaz (ᚦ, "giant"): the Kronos rune. Using it devours one random familiar
-- of the user's, the way Kronos does, and keeps it for good: each one gives +2
-- damage and its absorbed ability whether or not Kronos is held.
-- The ledger and the abilities are Kronos's (ConchBlessing.kronos.devourWithRune).
ConchBlessing.thurisaz = ConchBlessing.thurisaz or {}
ConchBlessing.thurisaz.data = {
    devour = 1, -- familiars taken per use (user decision 2026-10-12)
}

local POCKET = ConchBlessing.PocketData.THURISAZ
local CARD = POCKET.id

-- EID (user request 2026-11-14): while a player holds the rune, a familiar's
-- description shows the line Kronos's synergy has for it after the rune's icon,
-- and the rune's own description lists the held familiars' lines, as Kronos's
-- does (scripts/lib/pocket_synergies.lua). Only Kronos's line shows while
-- someone holds Kronos. The abilities are Kronos's, so the text is too, except:
POCKET.synergyItem = "KRONOS"
-- Kronos-only sources (AGENTS.md, Cards And Runes): the rune never does these.
-- A devoured GB Bug gives its +2 only; its release runs in Kronos's own sweep.
local KRONOS_ONLY = {
    ["c" .. CollectibleType.COLLECTIBLE_GB_BUG] = true,
    ["c" .. CollectibleType.COLLECTIBLE_BOX_OF_FRIENDS] = true,
    ["c" .. CollectibleType.COLLECTIBLE_MONSTER_MANUAL] = true,
    ["c" .. CollectibleType.COLLECTIBLE_SACRIFICIAL_ALTAR] = true,
    ["t" .. TrinketType.TRINKET_THE_TWINS] = true,
}
--- How Kronos's line about the item `id` reads for the rune: true for Kronos's
--- text, false for none, or the rune's own line (a familiar it never devours).
function POCKET.synergyLine(id, isTrinket)
    if KRONOS_ONLY[(isTrinket and "t" or "c") .. tostring(id)] then return false end
    local kronos = ConchBlessing.kronos
    local blacklist = not isTrinket and kronos and kronos.data and kronos.data.blacklist
    if blacklist and blacklist[id] then
        return POCKET.synergies and POCKET.synergies.not_absorbed or false
    end
    return true
end

-- MC_USE_CARD runs for a copy from Blank Card or Clear Rune too, with the
-- triggering player. The picks come from that player's RNG for this card.
ConchBlessing.thurisaz.onUseCard = function(_, card, player)
    if card ~= CARD or not player then return end
    local kronos = ConchBlessing.kronos
    if not (kronos and type(kronos.devourWithRune) == "function") then
        ConchBlessing.printError("[Thurisaz] Kronos is not loaded; nothing was devoured")
        return
    end
    local rng = player:GetCardRNG(card)
    local taken = kronos.devourWithRune(player, ConchBlessing.thurisaz.data.devour,
        function(n) return rng:RandomInt(n) end)
    ConchBlessing.printDebug("[Thurisaz] devoured %d familiar(s)", taken)
end

ConchBlessing:AddCallback(ModCallbacks.MC_USE_CARD, ConchBlessing.thurisaz.onUseCard, CARD)
