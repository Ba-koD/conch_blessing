-- Thurisaz (ᚦ, "giant"): the Kronos rune. Using it devours up to three random
-- familiars of the user's, the way Kronos does, and keeps them for good: each
-- one gives +2 damage and its absorbed ability whether or not Kronos is held.
-- The ledger and the abilities are Kronos's (ConchBlessing.kronos.devourWithRune).
ConchBlessing.thurisaz = ConchBlessing.thurisaz or {}
ConchBlessing.thurisaz.data = {
    devour = 3, -- familiars taken per use
}

local CARD = ConchBlessing.PocketData.THURISAZ.id

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
    ConchBlessing.printDebug(string.format("[Thurisaz] devoured %d familiar(s)", taken))
end

ConchBlessing:AddCallback(ModCallbacks.MC_USE_CARD, ConchBlessing.thurisaz.onUseCard, CARD)
