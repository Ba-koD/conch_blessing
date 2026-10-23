local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Conch Ticket (소라 예약권): reserve the Magic Conch's next answers.
--
-- Using the card spends it and opens a picker over the user's head: the
-- shooting keys move between positive, neutral and negative and the card key
-- confirms. Confirmed answers queue in the run save and stay reserved through
-- rooms, floors and quit/Continue until ordinary Conch activations take them in
-- order. An unconfirmed picker is saved as well and reopens after Continue.
--
-- The provider's reservation (MagicConch.API.ReserveNextResult) is runtime only:
-- one global slot, wiped by the provider on every new room, floor, game start
-- and exit, and consumed by an accepted activation, which records the room's use
-- just before. So the queue lives here, its first answer is reserved again after
-- every reset (LATE lifecycle callbacks), and a reservation that vanished in the
-- same room while that room's use count went up has been used.
local View = require("scripts.lib.conch_answer_view")

local M = {}
ConchBlessing.conchTicket = M

local CARD = ConchBlessing.PocketData.CONCH_TICKET.id
local OWNER = "ConchBlessing Conch Ticket"
local KINDS = { "positive", "neutral", "negative" }
local SHOWN = 3            -- queued answers listed in the HUD before "+n"
local HEAD_OFFSET = 58     -- screen pixels from the player's feet up to the picker
local DIM = 0.45           -- colour scale of the answers not selected

local callbackPriority = rawget(_G, "CallbackPriority")
local LATE = type(callbackPriority) == "table" and tonumber(callbackPriority.LATE) or 100

local ready = false        -- closed until game start; pre-start callbacks see the previous run's save
local armed = nil          -- the provider reservation held: { token, kind, usage, room }
local pickers = {}         -- [GetPtrHash(player)] = unconfirmed tickets, mirrored for the input hook
local latches = {}         -- [GetPtrHash(player)] = { left, right, confirm } as last read
local releaseLock = {}     -- [GetPtrHash(player)] = true until the confirming card key is let go
local controllers = {}     -- [GetPtrHash(player)] = ControllerIndex while that player picks or holds releaseLock
local pickRefs = {}        -- [GetPtrHash(player)] = that player's saved picker, to settle it if they leave
local reading = false      -- our own reads pass the input hook untouched
-- Test-only key source for conch_test: Lua's Input reads cannot be faked through
-- MC_INPUT_ACTION (measured in game), so the bench holds keys here instead. It
-- feeds the same reads; cleared on every game start, exit and bench cleanup.
local testKeys = {}

-- ---------------------------------------------------------------- saved state
local function save() ConchBlessing.SaveManager.Save() end

local function runTicket(create)
    local run = ConchBlessing.SaveManager.GetRunSave(nil)
    if type(run) ~= "table" then return nil end
    if create and type(run.conchTicket) ~= "table" then run.conchTicket = { queue = {} } end
    local ticket = run.conchTicket
    if type(ticket) ~= "table" then return nil end
    if type(ticket.queue) ~= "table" then ticket.queue = {} end
    return ticket
end

--- The confirmed answers waiting for the Magic Conch, the next one first. The
--- Conch's next answer is shared by every player, so the queue is too.
function M.queue()
    local ticket = runTicket(false)
    return ticket and ticket.queue or {}
end

function M.hasQueue() return ready and #M.queue() > 0 end

-- Each player's own picker: { open = unconfirmed tickets, index = 1..3 }.
local function pickSave(player, create)
    local run = ConchBlessing.SaveManager.GetRunSave(player)
    if type(run) ~= "table" then return nil end
    if create and type(run.conchTicketPick) ~= "table" then run.conchTicketPick = { open = 0, index = 2 } end
    local pick = run.conchTicketPick
    if type(pick) ~= "table" then return nil end
    pick.open = math.max(0, math.floor(tonumber(pick.open) or 0))
    local index = math.floor(tonumber(pick.index) or 2)
    pick.index = (index >= 1 and index <= #KINDS) and index or 2
    return pick
end

function M.picking(player)
    return player ~= nil and pickers[GetPtrHash(player)] ~= nil
end

-- Remember whose controller a picker or release lock belongs to, or forget it
-- once neither is left.
local function track(player, key, pick)
    if pickers[key] or releaseLock[key] then
        controllers[key] = player.ControllerIndex
        if pick then pickRefs[key] = pick end
    else
        controllers[key], pickRefs[key] = nil, nil
    end
end

local function refreshPickers()
    for key in pairs(pickers) do pickers[key] = nil end
    controllers, pickRefs = {}, {}
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        local pick = player and pickSave(player, false)
        if pick and pick.open > 0 then
            local key = GetPtrHash(player)
            pickers[key] = pick.open
            track(player, key, pick)
        end
    end
end

-- ---------------------------------------------------------------- the provider
local function api()
    local provider = rawget(_G, "MagicConch")
    local a = provider and provider.API
    if type(a) ~= "table" or type(a.ReserveNextResult) ~= "function" or type(a.GetNextResultReservation) ~= "function"
        or type(a.ClearNextResultReservation) ~= "function" or type(a.IsReady) ~= "function" then
        return nil, "API_UNAVAILABLE"
    end
    local ok, isReady = pcall(a.IsReady)
    if not (ok and isReady) then return nil, "API_NOT_READY" end
    return a
end

local function roomKey()
    local level = Game():GetLevel()
    local dimension = type(level.GetDimension) == "function" and level:GetDimension() or 0
    return string.format("%d:%d:%d:%d", level:GetStage(), level:GetStageType(), level:GetCurrentRoomIndex(), dimension)
end

local function release(a)
    if armed and a then pcall(a.ClearNextResultReservation, OWNER) end
    armed = nil
end

local function arm(a, kind)
    -- AR Glasses keeps its choice in the same provider slot under its own owner;
    -- a ticket the player paid for wins over it.
    local ar = ConchBlessing.arglasses
    if ar and type(ar.cancel) == "function" then pcall(ar.cancel) end
    local ok, accepted, token = pcall(a.ReserveNextResult, OWNER, { type = kind },
        function() return ready and M.queue()[1] == kind end)
    if not ok or accepted ~= true then
        View.warn("TICKET_RESERVE_FAILED", ok and token or accepted)
        return false
    end
    armed = { token = token, kind = kind, usage = View.usage(a), room = roomKey() }
    ConchBlessing.printDebug(string.format("[ConchTicket] reserved %s for the next Conch (token %s)", kind, tostring(token)))
    return true
end

--- Keep exactly the first queued answer reserved with the provider, and drop it
--- from the queue once an activation has used it.
function M.sync()
    if not ready then return end
    local queue = M.queue()
    local a = api()
    if #queue == 0 then release(a); return end
    if not a then armed = nil; return end
    if armed then
        local ok, current = pcall(a.GetNextResultReservation, OWNER)
        local held = ok and type(current) == "table" and current.token == armed.token
        if held and armed.kind == queue[1] then return end
        if held then
            -- The queue changed under the reservation (Glowing Hourglass): replace it.
            pcall(a.ClearNextResultReservation, OWNER)
        else
            local now = View.usage(a)
            if armed.room == roomKey() and armed.usage and now and now > armed.usage and queue[1] == armed.kind then
                table.remove(queue, 1)
                save()
                ConchBlessing.printDebug(string.format("[ConchTicket] the Conch used %s; %d left", armed.kind, #queue))
            end
        end
        armed = nil
        if #queue == 0 then return end
    end
    arm(a, queue[1])
end

-- ---------------------------------------------------------------- input
local function pressed(player, action)
    if testKeys[action] then return true end
    reading = true
    local ok, value = pcall(Input.IsActionPressed, action, player.ControllerIndex)
    reading = false
    return ok and value == true
end

local function readInputs(player)
    return {
        left = pressed(player, ButtonAction.ACTION_SHOOTLEFT),
        right = pressed(player, ButtonAction.ACTION_SHOOTRIGHT),
        confirm = pressed(player, ButtonAction.ACTION_PILLCARD),
    }
end

local function sfx(id, volume)
    if id then SFXManager():Play(id, require("scripts.lib.sound_volume").volume(volume), 0, false, 1) end
end

-- Rising edges from update and render alike, so a tap between updates counts
-- and a held key never repeats.
local function step(player)
    local key = GetPtrHash(player)
    if not pickers[key] and not releaseLock[key] then latches[key] = nil; track(player, key); return end
    local now = readInputs(player)
    local last = latches[key] or now
    latches[key] = now
    if releaseLock[key] and not now.confirm then releaseLock[key] = nil end
    track(player, key)
    if not pickers[key] or Game():IsPaused() then return end
    local pick = pickSave(player, false)
    if not pick or pick.open <= 0 then pickers[key] = nil; track(player, key); return end
    track(player, key, pick)
    if now.confirm and not last.confirm then
        local ticket = runTicket(true)
        ticket.queue[#ticket.queue + 1] = KINDS[pick.index]
        pick.open = pick.open - 1
        pickers[key] = pick.open > 0 and pick.open or nil
        releaseLock[key] = true
        track(player, key)
        save()
        sfx(SoundEffect.SOUND_PAPER_IN, 0.9)
        M.sync()
        return
    end
    local moved = false
    if now.left and not last.left then pick.index = pick.index == 1 and #KINDS or pick.index - 1; moved = true end
    if now.right and not last.right then pick.index = pick.index % #KINDS + 1; moved = true end
    if moved then
        save()
        sfx(SoundEffect.SOUND_MENU_FLIP_LIGHT, 0.7)
    end
end

-- While a player is choosing, their shooting keys and card key belong to the
-- picker; the card key stays theirs until let go, so the confirming press
-- cannot also use the next pocket item. The same keys drive every player on
-- that controller (a second player added on the picker's controller), so the
-- game is denied them for all of those players for the same window.
local BLOCKED = {
    [ButtonAction.ACTION_SHOOTLEFT] = true, [ButtonAction.ACTION_SHOOTRIGHT] = true,
    [ButtonAction.ACTION_SHOOTUP] = true, [ButtonAction.ACTION_SHOOTDOWN] = true,
    [ButtonAction.ACTION_PILLCARD] = true,
}

local function withheld(key, controller, action)
    if pickers[key] or (action == ButtonAction.ACTION_PILLCARD and releaseLock[key]) then return true end
    for other, owner in pairs(controllers) do
        if owner == controller
            and (pickers[other] or (action == ButtonAction.ACTION_PILLCARD and releaseLock[other])) then
            return true
        end
    end
    return false
end

function M.onInputAction(_, entity, hook, action)
    if reading or not ready or not BLOCKED[action] or next(controllers) == nil then return end
    local player = entity and entity:ToPlayer()
    if not player then return end
    if not withheld(GetPtrHash(player), player.ControllerIndex, action) then return end
    if hook == InputHook.GET_ACTION_VALUE then return 0.0 end
    if hook == InputHook.IS_ACTION_PRESSED or hook == InputHook.IS_ACTION_TRIGGERED then return false end
end

-- ---------------------------------------------------------------- drawing
local function drawPicker(player, count)
    local pick = pickSave(player, false)
    if not pick then return end
    local foot = Isaac.WorldToScreen(player.Position)
    local scale, gap = 0.6, 8
    local labels, widths, total = {}, {}, 0
    for i, kind in ipairs(KINDS) do
        local label = View.text("ui.conch_mode.flags." .. kind)
        if i == pick.index then label = "[" .. label .. "]" end
        labels[i], widths[i] = label, View.width(label, scale)
        total = total + widths[i] + (i > 1 and gap or 0)
    end
    local x, y = foot.X - total / 2, foot.Y - HEAD_OFFSET
    for i, kind in ipairs(KINDS) do
        local c = View.colors[kind]
        View.drawAt(labels[i], x, y, scale, i == pick.index and c or { c[1] * DIM, c[2] * DIM, c[3] * DIM })
        x = x + widths[i] + gap
    end
    local hint = View.text("ui.conch_ticket.hint")
    if count > 1 then hint = hint .. "   " .. View.text("ui.conch_ticket.waiting", count) end
    View.drawAt(hint, foot.X - View.width(hint, 0.5) / 2, y + 12, 0.5, { 0.95, 0.92, 0.85 })
end

local function drawQueue()
    local queue = M.queue()
    if #queue == 0 then return end
    local names = {}
    for i = 1, math.min(#queue, SHOWN) do names[i] = View.text("ui.conch_mode.flags." .. queue[i]) end
    local text = table.concat(names, View.text("ui.conch_ticket.separator"))
    if #queue > SHOWN then text = text .. " +" .. (#queue - SHOWN) end
    View.render({ { text = View.text("ui.conch_ticket.reserved", text), kind = queue[1] } })
end

-- ---------------------------------------------------------------- callbacks
function M.onUseCard(_, card, player)
    if card ~= CARD or not player or not ready then return end
    if not api() then
        -- Without the Magic Conch there is nothing to reserve: hand the ticket back.
        player:AddCard(CARD)
        View.warn("TICKET_REFUNDED", "the Magic Conch API is unavailable; the ticket was given back")
        return
    end
    local pick = pickSave(player, true)
    if not pick then return end
    pick.open = pick.open + 1
    save()
    local key = GetPtrHash(player)
    pickers[key] = pick.open
    track(player, key, pick)
    latches[key] = readInputs(player) -- the key that used the card is still down
end

local function live(player)
    return player ~= nil and (type(player.Exists) ~= "function" or player:Exists())
end

-- A picking player can leave the run before confirming (a co-op drop-out, a
-- removed extra player). Their saved picker leaves with them, so each open
-- ticket goes back to a remaining live player, one on the same controller
-- first, and that player's saved picker is closed so it cannot reopen and
-- count twice if they return. Their locks go too, freeing that controller.
local function settleDeparted(present, players)
    for key, controller in pairs(controllers) do
        if not present[key] then
            local count, pick = pickers[key], pickRefs[key]
            pickers[key], latches[key], releaseLock[key] = nil, nil, nil
            controllers[key], pickRefs[key] = nil, nil
            if count and count > 0 then
                local heir
                for _, player in ipairs(players) do
                    if player.ControllerIndex == controller then heir = player; break end
                end
                heir = heir or players[1]
                if pick then pick.open = 0 end
                if heir then
                    for _ = 1, count do heir:AddCard(CARD) end
                    ConchBlessing.printDebug(string.format(
                        "[ConchTicket] %d unconfirmed ticket(s) of a player who left went back to controller %s",
                        count, tostring(heir.ControllerIndex)))
                end
                save()
            end
        end
    end
end

function M.onUpdate()
    if not ready then return end
    local game = Game()
    local present, players = {}, {}
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if live(player) then
            present[GetPtrHash(player)] = true
            players[#players + 1] = player
            step(player)
        end
    end
    settleDeparted(present, players)
    M.sync()
end

function M.onRender()
    if not ready then return end
    local ok, err = pcall(function()
        local hud = Game():GetHUD()
        local visible = not (hud and type(hud.IsVisible) == "function" and not hud:IsVisible())
        local game = Game()
        for i = 0, game:GetNumPlayers() - 1 do
            local player = game:GetPlayer(i)
            if player then
                step(player)
                local count = pickers[GetPtrHash(player)]
                if count and visible then drawPicker(player, count) end
            end
        end
        drawQueue()
    end)
    if not ok then View.warn("TICKET_RENDER_FAILED", err) end
end

function M.onGameStarted()
    for key in pairs(testKeys) do testKeys[key] = nil end
    ready = true
    armed = nil
    latches, releaseLock = {}, {}
    refreshPickers()
    M.sync()
end

-- New room or floor: the provider has just wiped its reservation.
function M.onLifecycle()
    if not ready then return end
    armed = nil
    M.sync()
end

function M.onPreGameExit()
    for key in pairs(testKeys) do testKeys[key] = nil end
    ready = false
    armed = nil
    pickers, latches, releaseLock = {}, {}, {}
    controllers, pickRefs = {}, {}
end

function M.onUnload(_, mod)
    if mod ~= ConchBlessing and mod ~= ConchBlessing.originalMod then return end
    release(api())
    ready = false
end

M._test = {
    kinds = KINDS,
    owner = OWNER,
    armed = function() return armed end,
    pickers = function() return pickers end,
    hold = function(action, down) testKeys[action] = down and true or nil end,
    releaseAll = function() for key in pairs(testKeys) do testKeys[key] = nil end end,
}

ConchBlessing:AddCallback(ModCallbacks.MC_USE_CARD, M.onUseCard, CARD)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, M.onUpdate)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, M.onRender)
ConchBlessing:AddCallback(ModCallbacks.MC_INPUT_ACTION, M.onInputAction)
ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_GAME_STARTED, LATE, M.onGameStarted)
ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_NEW_ROOM, LATE, M.onLifecycle)
ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_NEW_LEVEL, LATE, M.onLifecycle)
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, M.onPreGameExit)
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, M.onUnload)

return M
