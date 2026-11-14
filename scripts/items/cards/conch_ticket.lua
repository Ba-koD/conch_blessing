local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
local RunSaveCache = require("scripts.lib.run_save_cache")
-- Conch Ticket (소라 예약권): reserve the Magic Conch's next answers.
--
-- Using the card spends it and opens a picker over the user's head: the
-- shooting keys move between positive, neutral and negative and the card key
-- confirms. AR Glasses opens the same picker from its active use and confirms
-- with the active-item key instead (M.open). Confirmed answers queue in the run
-- save and stay reserved through rooms, floors and quit/Continue until ordinary
-- Conch activations take them in order. An unconfirmed picker is saved as well
-- and reopens after Continue.
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

-- What opens a picker and the key that confirms it. Each source counts its own
-- unconfirmed pickers in the player's saved picker (`field`); the shooting keys
-- and the selection are shared.
local SOURCES = {
    { name = "card", field = "open", action = ButtonAction.ACTION_PILLCARD, label = "ui.conch_ticket.confirm_card" },
    { name = "glasses", field = "glasses", action = ButtonAction.ACTION_ITEM, label = "ui.conch_ticket.confirm_glasses" },
}
local SOURCE = {}          -- [name] = source
local CONFIRM = {}         -- [ButtonAction] = source name
for _, source in ipairs(SOURCES) do SOURCE[source.name], CONFIRM[source.action] = source, source.name end

local callbackPriority = rawget(_G, "CallbackPriority")
local LATE = type(callbackPriority) == "table" and tonumber(callbackPriority.LATE) or 100

local ready = false        -- closed until game start; pre-start callbacks see the previous run's save
local armed = nil          -- the provider reservation held: { token, kind, usage, room }
local pickers = {}         -- [GetPtrHash(player)] = { [source name] = unconfirmed pickers }, mirrored for the input hook
local latches = {}         -- [GetPtrHash(player)] = { left, right, [source name] } as last read
local releaseLock = {}     -- [GetPtrHash(player)] = { [source name] = true } until that confirming key is let go
local controllers = {}     -- [GetPtrHash(player)] = ControllerIndex while that player picks or holds releaseLock
local pickRefs = {}        -- [GetPtrHash(player)] = that player's saved picker, to settle it if they leave
local reading = false      -- our own reads pass the input hook untouched
-- Test-only key source for cb test: Lua's Input reads cannot be faked through
-- MC_INPUT_ACTION (measured in game), so the bench holds keys here instead. It
-- feeds the same reads; cleared on every game start, exit and bench cleanup.
local testKeys = {}

-- ---------------------------------------------------------------- saved state
local function save() ConchBlessing.SaveManager.Save() end

local function runTicket(create)
    local run = RunSaveCache.global(true)
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

-- Each player's own picker: { open = unconfirmed tickets, glasses = unconfirmed
-- AR Glasses uses, index = 1..3 }.
local function pickSave(player, create)
    local run = ConchBlessing.SaveManager.GetRunSave(player)
    if type(run) ~= "table" then return nil end
    if create and type(run.conchTicketPick) ~= "table" then run.conchTicketPick = { open = 0, glasses = 0, index = 2 } end
    local pick = run.conchTicketPick
    if type(pick) ~= "table" then return nil end
    for _, source in ipairs(SOURCES) do
        pick[source.field] = math.max(0, math.floor(tonumber(pick[source.field]) or 0))
    end
    local index = math.floor(tonumber(pick.index) or 2)
    pick.index = (index >= 1 and index <= #KINDS) and index or 2
    return pick
end

-- The open pickers by source name (nil when none is open) and their total.
local function openCounts(pick)
    local counts, total = nil, 0
    for _, source in ipairs(SOURCES) do
        local n = pick[source.field]
        if n > 0 then
            counts = counts or {}
            counts[source.name], total = n, total + n
        end
    end
    return counts, total
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
        local counts = pick and openCounts(pick)
        if counts then
            local key = GetPtrHash(player)
            pickers[key] = counts
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
    local ok, accepted, token = pcall(a.ReserveNextResult, OWNER, { type = kind },
        function() return ready and M.queue()[1] == kind end)
    if not ok or accepted ~= true then
        View.warn("TICKET_RESERVE_FAILED", ok and token or accepted)
        return false
    end
    armed = { token = token, kind = kind, usage = View.usage(a), room = roomKey() }
    ConchBlessing.printDebug("[ConchTicket] reserved %s for the next Conch (token %s)", kind, tostring(token))
    return true
end

--- Keep exactly the first queued answer reserved with the provider, and drop it
--- from the queue once an activation has used it.
function M.sync()
    if not ready then return end
    local queue = M.queue()
    -- Nothing waiting (the usual case): only a reservation still held needs
    -- the provider, so it is not asked every update for nothing.
    if #queue == 0 then
        if armed then release(api()) end
        return
    end
    local a = api()
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
                ConchBlessing.printDebug("[ConchTicket] the Conch used %s; %d left", armed.kind, #queue)
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
    local now = {
        left = pressed(player, ButtonAction.ACTION_SHOOTLEFT),
        right = pressed(player, ButtonAction.ACTION_SHOOTRIGHT),
    }
    for _, source in ipairs(SOURCES) do now[source.name] = pressed(player, source.action) end
    return now
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
    local locks = releaseLock[key]
    if locks then
        for name in pairs(locks) do if not now[name] then locks[name] = nil end end
        if next(locks) == nil then releaseLock[key] = nil end
    end
    track(player, key)
    if not pickers[key] or Game():IsPaused() then return end
    local pick = pickSave(player, false)
    local counts = pick and openCounts(pick)
    if not counts then pickers[key] = nil; track(player, key); return end
    pickers[key] = counts
    track(player, key, pick)
    -- Each source confirms only with its own key: the card key a ticket, the
    -- active-item key an AR Glasses use.
    local confirmed = false
    for _, source in ipairs(SOURCES) do
        if counts[source.name] and now[source.name] and not last[source.name] then
            local ticket = runTicket(true)
            ticket.queue[#ticket.queue + 1] = KINDS[pick.index]
            pick[source.field] = pick[source.field] - 1
            releaseLock[key] = releaseLock[key] or {}
            releaseLock[key][source.name] = true
            confirmed = true
        end
    end
    if confirmed then
        pickers[key] = openCounts(pick)
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

-- While a player is choosing, their shooting keys and the confirming key of
-- each open source belong to the picker; a confirming key stays theirs until
-- let go, so the confirming press cannot also use the next pocket item or the
-- active item. The same keys drive every player on that controller (a second
-- player added on the picker's controller), so the game is denied them for all
-- of those players for the same window.
local SHOOTING = {
    [ButtonAction.ACTION_SHOOTLEFT] = true, [ButtonAction.ACTION_SHOOTRIGHT] = true,
    [ButtonAction.ACTION_SHOOTUP] = true, [ButtonAction.ACTION_SHOOTDOWN] = true,
}

local function holds(key, action)
    local open = pickers[key]
    if open and SHOOTING[action] then return true end
    local name = CONFIRM[action]
    if not name then return false end
    local locks = releaseLock[key]
    return (open ~= nil and open[name] ~= nil) or (locks ~= nil and locks[name] == true)
end

local function withheld(key, controller, action)
    if holds(key, action) then return true end
    for other, owner in pairs(controllers) do
        if owner == controller and holds(other, action) then return true end
    end
    return false
end

function M.onInputAction(_, entity, hook, action)
    if reading or not ready or not (SHOOTING[action] or CONFIRM[action]) or next(controllers) == nil then return end
    local player = entity and entity:ToPlayer()
    if not player then return end
    if not withheld(GetPtrHash(player), player.ControllerIndex, action) then return end
    if hook == InputHook.GET_ACTION_VALUE then return 0.0 end
    if hook == InputHook.IS_ACTION_PRESSED or hook == InputHook.IS_ACTION_TRIGGERED then return false end
end

-- ---------------------------------------------------------------- drawing
local function drawPicker(player, counts)
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
    local keys, count = {}, 0
    for _, source in ipairs(SOURCES) do
        if counts[source.name] then
            keys[#keys + 1] = View.text(source.label)
            count = count + counts[source.name]
        end
    end
    local hint = View.text("ui.conch_ticket.hint", table.concat(keys, "/"))
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
--- Open one picker over the player's head for a source: "card" (the Conch
--- Ticket, confirmed with the card key) or "glasses" (AR Glasses, confirmed
--- with the active-item key). Returns true, or false and a reason when nothing
--- can be reserved; the caller then gives back what opened it.
function M.open(player, sourceName)
    local source = SOURCE[sourceName]
    if not source then return false, "UNKNOWN_SOURCE" end
    if not player or not ready then return false, "NOT_READY" end
    local a, reason = api()
    if not a then return false, reason end
    local pick = pickSave(player, true)
    if not pick then return false, "NO_SAVE" end
    pick[source.field] = pick[source.field] + 1
    save()
    local key = GetPtrHash(player)
    pickers[key] = openCounts(pick)
    track(player, key, pick)
    latches[key] = readInputs(player) -- the key that used it is still down
    return true
end

function M.onUseCard(_, card, player)
    if card ~= CARD or not player or not ready then return end
    local opened, reason = M.open(player, "card")
    if not opened and (reason == "API_UNAVAILABLE" or reason == "API_NOT_READY") then
        -- Without the Magic Conch there is nothing to reserve: hand the ticket back.
        player:AddCard(CARD)
        View.warn("TICKET_REFUNDED", "the Magic Conch API is unavailable; the ticket was given back")
    end
end

local function live(player)
    return player ~= nil and (type(player.Exists) ~= "function" or player:Exists())
end

-- A picking player can leave the run before confirming (a co-op drop-out, a
-- removed extra player). Their saved picker leaves with them, so each open
-- picker goes to a remaining live player, one on the same controller first: a
-- ticket goes back as a card, and an AR Glasses use, already paid for in
-- charge, opens on that player to confirm with their own active-item key. The
-- departed player's saved picker is closed so it cannot reopen and count twice
-- if they return. Their locks go too, freeing that controller.
local function settleDeparted(present, players)
    local departed = {}
    for key, controller in pairs(controllers) do
        if not present[key] then departed[#departed + 1] = { key = key, controller = controller } end
    end
    for _, gone in ipairs(departed) do
        local key = gone.key
        local counts, pick = pickers[key], pickRefs[key]
        pickers[key], latches[key], releaseLock[key] = nil, nil, nil
        controllers[key], pickRefs[key] = nil, nil
        if counts then
            local heir
            for _, player in ipairs(players) do
                if player.ControllerIndex == gone.controller then heir = player; break end
            end
            heir = heir or players[1]
            if pick then for _, source in ipairs(SOURCES) do pick[source.field] = 0 end end
            if heir then
                for _ = 1, counts.card or 0 do heir:AddCard(CARD) end
                local heirPick = counts.glasses and pickSave(heir, true)
                if heirPick then
                    heirPick.glasses = heirPick.glasses + counts.glasses
                    local heirKey = GetPtrHash(heir)
                    pickers[heirKey] = openCounts(heirPick)
                    track(heir, heirKey, heirPick)
                    latches[heirKey] = readInputs(heir)
                end
                ConchBlessing.printDebug(
                    "[ConchTicket] %d ticket(s) and %d AR Glasses picker(s) of a player who left went to controller %s",
                    counts.card or 0, counts.glasses or 0, tostring(heir.ControllerIndex))
            end
            save()
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

local function renderAll()
    local hud = Game():GetHUD()
    local visible = not (hud and type(hud.IsVisible) == "function" and not hud:IsVisible())
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player then
            step(player)
            local counts = pickers[GetPtrHash(player)]
            if counts and visible then drawPicker(player, counts) end
        end
    end
    drawQueue()
end

function M.onRender()
    if not ready then return end
    local ok, err = pcall(renderAll)
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
    -- Bench cleanup: close every open picker and drop the queued answers.
    clearAll = function()
        for key in pairs(testKeys) do testKeys[key] = nil end
        local ticket = runTicket(false)
        if ticket then ticket.queue = {} end
        local game = Game()
        for i = 0, game:GetNumPlayers() - 1 do
            local pick = pickSave(game:GetPlayer(i), false)
            if pick then for _, source in ipairs(SOURCES) do pick[source.field] = 0 end end
        end
        pickers, latches, releaseLock = {}, {}, {}
        controllers, pickRefs = {}, {}
        save()
        M.sync()
    end,
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
