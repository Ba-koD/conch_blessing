local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- AR Glasses: a 12-charge active that starts half full (user design 2026-11-09).
-- Using it opens the Conch Ticket's picker over the user's head: the shooting
-- keys choose positive, neutral or negative and the active-item key confirms.
-- The confirmed answer joins the ticket's queue, so it is reserved the same way
-- (kept through rooms and Continue until a Magic Conch use takes it).
local M = {}
ConchBlessing.arglasses = M
local View = require("scripts.lib.conch_answer_view")
local ID = Isaac.GetItemIdByName("AR Glasses")

-- An ItemData `use` handler receives the mod first: (_, id, rng, player, flags, slot, varData).
function M.onUseItem(_, id, _, player)
    if id ~= ID or not player then return end
    local ticket = ConchBlessing.conchTicket
    local opened, reason = false, "TICKET_UNAVAILABLE"
    if ticket and type(ticket.open) == "function" then opened, reason = ticket.open(player, "glasses") end
    if not opened then
        -- Nothing can be reserved (no Magic Conch API): keep the charge.
        View.warn("GLASSES_REFUSED", tostring(reason) .. "; the charge was kept")
        return { Discharge = false, Remove = false, ShowAnim = false }
    end
    return { Discharge = true, Remove = false, ShowAnim = true }
end

return M
