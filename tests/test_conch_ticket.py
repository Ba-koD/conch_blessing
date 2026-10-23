"""Conch Ticket: production Lua with engine and Magic Conch provider doubles.

The provider double mirrors Magic Conch 1.14's reservation contract
(magic_conch_api.lua): one global owner-scoped slot, wiped by every room,
floor, game start and exit, and consumed by an accepted activation, which
records the room use first. These checks do not prove the picker's look, the
engine's input path or a real save and Continue; the in-game bench covers those.
"""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class ConchTicketTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r"""
            package.path = root .. '/?.lua;' .. package.path
            local function enum(names) local t = {} for i, n in ipairs(names) do t[n] = i end return t end
            ModCallbacks = enum({'MC_USE_CARD','MC_POST_UPDATE','MC_POST_RENDER','MC_INPUT_ACTION','MC_POST_GAME_STARTED',
                'MC_POST_NEW_ROOM','MC_POST_NEW_LEVEL','MC_PRE_GAME_EXIT','MC_PRE_MOD_UNLOAD'})
            ButtonAction = enum({'ACTION_SHOOTLEFT','ACTION_SHOOTRIGHT','ACTION_SHOOTUP','ACTION_SHOOTDOWN','ACTION_PILLCARD','ACTION_LEFT'})
            InputHook = { IS_ACTION_PRESSED = 0, IS_ACTION_TRIGGERED = 1, GET_ACTION_VALUE = 2 }
            SoundEffect = { SOUND_PAPER_IN = 17, SOUND_MENU_FLIP_LIGHT = 569 }
            CallbackPriority = { LATE = 1000 }
            sounds = {}
            function SFXManager() return { Play = function(_, id) sounds[#sounds + 1] = id end } end
            function GetPtrHash(e) return e.hash end
            function Vector(x, y) return { X = x, Y = y } end
            function KColor() return {} end
            function Font() error('no font in the offline harness') end
            drawn = {}
            room = { stage = 1, index = 84 }
            paused = false
            Isaac = {
                WorldToScreen = function(p) return Vector(p.X, p.Y) end,
                GetTextWidth = function(s) return #s * 5 end,
                RenderText = function(s) drawn[#drawn + 1] = s end,
                GetScreenWidth = function() return 480 end, GetScreenHeight = function() return 270 end,
            }
            keys = {}
            Input = { IsActionPressed = function(action, controller) return keys[controller .. ':' .. action] == true end }
            function press(player, action, down) keys[player.ControllerIndex .. ':' .. action] = down end
            local function makePlayer(hash, controller)
                local p = { hash = hash, ControllerIndex = controller, Position = Vector(200, 150), cards = {} }
                function p:ToPlayer() return self end
                function p:AddCard(id) self.cards[#self.cards + 1] = id end
                return p
            end
            players = { makePlayer(1, 0) }
            local level = {
                GetStage = function() return room.stage end, GetStageType = function() return 0 end,
                GetCurrentRoomIndex = function() return room.index end,
            }
            local game = { GetNumPlayers = function() return #players end, GetPlayer = function(_, i) return players[i + 1] end,
                GetLevel = function() return level end, GetHUD = function() return { IsVisible = function() return true end } end,
                IsPaused = function() return paused end }
            function Game() return game end

            -- Magic Conch 1.14's reservation contract.
            provider = { slot = nil, serial = 0, usage = 0, results = {}, ready = true }
            local api = {}
            function api.IsReady() return provider.ready end
            function api.ReserveNextResult(owner, options, isValid)
                if provider.slot and provider.slot.owner ~= owner then return false, 'RESERVED_BY_OTHER_MOD' end
                provider.serial = provider.serial + 1
                provider.slot = { owner = owner, options = { type = options.type }, isValid = isValid, token = provider.serial }
                return true, provider.serial
            end
            function api.GetNextResultReservation(owner)
                local s = provider.slot
                if not s or (owner and s.owner ~= owner) then return nil end
                return { owner = s.owner, token = s.token, options = { type = s.options.type } }
            end
            function api.ClearNextResultReservation(owner)
                if provider.slot and provider.slot.owner == owner then provider.slot = nil; return true end
                return false
            end
            function api.GetCurrentRoomUsage() return provider.usage end
            function provider.activate()
                local s = provider.slot
                if s and s.isValid and not s.isValid() then s = nil; provider.slot = nil end
                local kind = s and s.options.type or 'random'
                provider.usage = provider.usage + 1
                if s then provider.slot = nil end
                provider.results[#provider.results + 1] = kind
                return kind
            end
            function provider.reset() provider.slot = nil end
            MagicConch = { API = api, Config = { enabled = true, iconX = 430, iconY = 265, attemptsPerRoom = 0 } }

            runSave, playerSaves, saves = {}, {}, 0
            callbacks = {}
            ConchBlessing = {
                PocketData = { CONCH_TICKET = { id = 88 } },
                SaveManager = {
                    GetRunSave = function(p)
                        if not p then return runSave end
                        playerSaves[p.hash] = playerSaves[p.hash] or {}
                        return playerSaves[p.hash]
                    end,
                    Save = function() saves = saves + 1 end,
                },
                Locale = {
                    textIn = function(_, key, ...)
                        local args = { ... }
                        return key .. (#args > 0 and (':' .. table.concat(args, '|')) or '')
                    end,
                },
                printDebug = function() end,
                printError = function(message) errors[#errors + 1] = message end,
                arglasses = { cancelled = 0, cancel = function() ConchBlessing.arglasses.cancelled = ConchBlessing.arglasses.cancelled + 1 end },
            }
            ConchBlessing.Locale.text = function(key, ...) return ConchBlessing.Locale.textIn('en', key, ...) end
            errors = {}
            function ConchBlessing:AddCallback(id, fn, filter) callbacks[id] = { fn = fn, filter = filter } end
            function ConchBlessing:AddPriorityCallback(id, priority, fn) callbacks[id] = { fn = fn, priority = priority } end
            function fire(id, ...) return callbacks[id].fn(nil, ...) end
            T = require('scripts.items.cards.conch_ticket')
            P1 = players[1]
            function useTicket(player)
                press(player, ButtonAction.ACTION_PILLCARD, true) -- the card key that used it is still down
                fire(ModCallbacks.MC_USE_CARD, 88, player or P1)
            end
            function tap(player, action)
                press(player, action, true); fire(ModCallbacks.MC_POST_UPDATE)
                press(player, action, false); fire(ModCallbacks.MC_POST_UPDATE)
            end
            function start() fire(ModCallbacks.MC_POST_GAME_STARTED, false) end
            function newRoom(index)
                provider.reset(); room.index = index; provider.usage = 0
                fire(ModCallbacks.MC_POST_NEW_ROOM)
            end
            function reserved() local s = provider.slot; return s and s.owner == 'ConchBlessing Conch Ticket' and s.options.type end
        """)

    def run_lua(self, script):
        self.lua.execute(script)

    def test_pick_with_the_shooting_keys_and_confirm_with_the_card_key(self):
        self.run_lua("""
            start(); useTicket(P1)
            assert(T.picking(P1), 'the picker opens')
            fire(ModCallbacks.MC_POST_UPDATE)
            assert(T.picking(P1) and #T.queue() == 0, 'the key that used the card does not confirm it')
            press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            assert(playerSaves[1].conchTicketPick.index == 2, 'neutral is preselected')
            tap(P1, ButtonAction.ACTION_SHOOTRIGHT)
            assert(playerSaves[1].conchTicketPick.index == 3)
            tap(P1, ButtonAction.ACTION_SHOOTRIGHT)
            assert(playerSaves[1].conchTicketPick.index == 1, 'right wraps round to positive')
            tap(P1, ButtonAction.ACTION_SHOOTLEFT)
            assert(playerSaves[1].conchTicketPick.index == 3, 'left wraps back to negative')
            press(P1, ButtonAction.ACTION_SHOOTLEFT, true); fire(ModCallbacks.MC_POST_UPDATE); fire(ModCallbacks.MC_POST_UPDATE)
            assert(playerSaves[1].conchTicketPick.index == 2, 'a held key moves once')
            press(P1, ButtonAction.ACTION_SHOOTLEFT, false)
            press(P1, ButtonAction.ACTION_PILLCARD, true); fire(ModCallbacks.MC_POST_UPDATE)
            assert(not T.picking(P1), 'Q confirms')
            assert(#T.queue() == 1 and T.queue()[1] == 'neutral')
            assert(reserved() == 'neutral', 'the next Conch answer is reserved at once')
        """)

    def test_the_picker_owns_shooting_and_the_card_key_until_released(self):
        self.run_lua("""
            start()
            local function blocked(action, hook)
                return fire(ModCallbacks.MC_INPUT_ACTION, P1, hook or InputHook.IS_ACTION_TRIGGERED, action)
            end
            assert(blocked(ButtonAction.ACTION_SHOOTRIGHT) == nil, 'nothing is blocked before a ticket')
            useTicket(P1)
            for _, action in ipairs({ButtonAction.ACTION_SHOOTLEFT, ButtonAction.ACTION_SHOOTRIGHT,
                ButtonAction.ACTION_SHOOTUP, ButtonAction.ACTION_SHOOTDOWN, ButtonAction.ACTION_PILLCARD}) do
                assert(blocked(action) == false and blocked(action, InputHook.IS_ACTION_PRESSED) == false)
                assert(blocked(action, InputHook.GET_ACTION_VALUE) == 0)
            end
            assert(blocked(ButtonAction.ACTION_LEFT) == nil, 'walking stays free')
            assert(fire(ModCallbacks.MC_INPUT_ACTION, nil, InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_PILLCARD) == nil,
                'our own reads pass')
            press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            press(P1, ButtonAction.ACTION_PILLCARD, true); fire(ModCallbacks.MC_POST_UPDATE)
            assert(not T.picking(P1))
            assert(blocked(ButtonAction.ACTION_PILLCARD) == false, 'the confirming press cannot use the next card')
            assert(blocked(ButtonAction.ACTION_SHOOTRIGHT) == nil, 'shooting is back at once')
            press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            assert(blocked(ButtonAction.ACTION_PILLCARD) == nil, 'released, the card key is free again')
        """)

    def test_the_reservation_survives_rooms_floors_and_continue_until_used(self):
        self.run_lua("""
            start(); useTicket(P1); press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            tap(P1, ButtonAction.ACTION_SHOOTRIGHT); tap(P1, ButtonAction.ACTION_PILLCARD)
            assert(reserved() == 'negative')
            newRoom(85); assert(reserved() == 'negative', 'the provider wiped it; the ticket put it back')
            provider.reset(); room.stage = 2; fire(ModCallbacks.MC_POST_NEW_LEVEL)
            assert(reserved() == 'negative', 'a new floor too')
            fire(ModCallbacks.MC_PRE_GAME_EXIT); provider.reset()
            start(); assert(reserved() == 'negative', 'and quitting and continuing')
            for _ = 1, 3 do fire(ModCallbacks.MC_POST_UPDATE) end
            assert(#T.queue() == 1, 'nothing used yet')
            assert(provider.activate() == 'negative', 'the next Conch gives the reserved answer')
            fire(ModCallbacks.MC_POST_UPDATE)
            assert(#T.queue() == 0 and reserved() == nil, 'and the ticket is spent')
            assert(provider.activate() == 'random', 'the one after is the Conch\\'s own again')
        """)

    def test_several_tickets_queue_in_the_order_chosen(self):
        self.run_lua("""
            start(); useTicket(P1); useTicket(P1)
            assert(playerSaves[1].conchTicketPick.open == 2)
            press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            tap(P1, ButtonAction.ACTION_SHOOTLEFT); tap(P1, ButtonAction.ACTION_PILLCARD)
            assert(T.picking(P1), 'the second ticket is still waiting')
            assert(playerSaves[1].conchTicketPick.index == 1, 'it opens on the last choice')
            tap(P1, ButtonAction.ACTION_SHOOTRIGHT); tap(P1, ButtonAction.ACTION_SHOOTRIGHT); tap(P1, ButtonAction.ACTION_PILLCARD)
            assert(not T.picking(P1))
            assert(T.queue()[1] == 'positive' and T.queue()[2] == 'negative' and #T.queue() == 2)
            assert(reserved() == 'positive', 'the first answer is the one reserved')
            assert(provider.activate() == 'positive'); fire(ModCallbacks.MC_POST_UPDATE)
            assert(reserved() == 'negative', 'then the second one')
            newRoom(90); assert(provider.activate() == 'negative'); fire(ModCallbacks.MC_POST_UPDATE)
            assert(#T.queue() == 0)
        """)

    def test_an_unconfirmed_picker_reopens_after_continue(self):
        self.run_lua("""
            start(); useTicket(P1); press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            tap(P1, ButtonAction.ACTION_SHOOTLEFT)
            fire(ModCallbacks.MC_PRE_GAME_EXIT)
            assert(not T.picking(P1))
            players[1] = { hash = 7, ControllerIndex = 0, Position = Vector(0, 0), cards = {}, ToPlayer = function(s) return s end }
            playerSaves[7] = playerSaves[1]                      -- the same player's save after Continue
            P1 = players[1]
            start()
            assert(T.picking(P1) and playerSaves[7].conchTicketPick.index == 1, 'it reopens on the same choice')
            newRoom(86); assert(T.picking(P1), 'and stays open into the next room')
        """)

    def test_a_reset_without_a_use_never_spends_an_answer(self):
        self.run_lua("""
            start(); useTicket(P1); press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            tap(P1, ButtonAction.ACTION_PILLCARD)
            provider.reset(); fire(ModCallbacks.MC_POST_UPDATE)
            assert(#T.queue() == 1 and reserved() == 'neutral', 'wiped without a use: reserved again')
            provider.reset(); room.index = 99; provider.usage = 5; fire(ModCallbacks.MC_POST_UPDATE)
            assert(#T.queue() == 1, 'another room\\'s use count is not a use of this reservation')
        """)

    def test_the_queue_changing_under_the_reservation_replaces_it(self):
        self.run_lua("""
            start(); useTicket(P1); press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            tap(P1, ButtonAction.ACTION_PILLCARD)
            runSave.conchTicket.queue[1] = 'positive'          -- e.g. a Glowing Hourglass rewind
            fire(ModCallbacks.MC_POST_UPDATE)
            assert(reserved() == 'positive')
            runSave.conchTicket.queue = {}
            fire(ModCallbacks.MC_POST_UPDATE)
            assert(provider.slot == nil, 'an empty queue holds nothing')
        """)

    def test_ar_glasses_step_aside_and_another_mods_slot_is_respected(self):
        self.run_lua("""
            start()
            provider.slot = { owner = 'Some Other Mod', options = { type = 'positive' }, token = 99 }
            useTicket(P1); press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            tap(P1, ButtonAction.ACTION_PILLCARD)
            assert(provider.slot.owner == 'Some Other Mod', 'another mod is never overwritten')
            assert(#errors == 1, 'reported once')
            fire(ModCallbacks.MC_POST_UPDATE); assert(#errors == 1)
            provider.slot = nil; fire(ModCallbacks.MC_POST_UPDATE)
            assert(reserved() == 'neutral', 'reserved as soon as the slot is free')
            assert(ConchBlessing.arglasses.cancelled > 0, 'AR Glasses gives up its own choice')
        """)

    def test_without_the_conch_the_ticket_is_given_back(self):
        self.run_lua("""
            start(); provider.ready = false
            useTicket(P1)
            assert(not T.picking(P1) and P1.cards[1] == 88, 'refunded')
        """)

    def test_nothing_runs_before_the_game_has_started(self):
        self.run_lua("""
            runSave.conchTicket = { queue = { 'negative' } }   -- the previous run's table
            fire(ModCallbacks.MC_POST_NEW_ROOM); fire(ModCallbacks.MC_POST_UPDATE); useTicket(P1)
            assert(provider.slot == nil and not T.picking(P1) and #runSave.conchTicket.queue == 1)
            assert(not T.hasQueue())
        """)

    def test_co_op_players_pick_on_their_own_controllers(self):
        self.run_lua("""
            players[2] = { hash = 2, ControllerIndex = 1, Position = Vector(0, 0), cards = {}, ToPlayer = function(s) return s end }
            P2 = players[2]
            start(); useTicket(P2)
            assert(T.picking(P2) and not T.picking(P1))
            assert(fire(ModCallbacks.MC_INPUT_ACTION, P1, InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT) == nil)
            press(P2, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            tap(P1, ButtonAction.ACTION_SHOOTRIGHT); tap(P1, ButtonAction.ACTION_PILLCARD)
            assert(T.picking(P2) and #T.queue() == 0, "player one's keys do not drive player two's picker")
            tap(P2, ButtonAction.ACTION_SHOOTRIGHT); tap(P2, ButtonAction.ACTION_PILLCARD)
            assert(T.queue()[1] == 'negative', 'the shared queue takes player two\\'s answer')
        """)

    def test_a_second_player_on_the_pickers_controller_is_withheld_for_the_same_window(self):
        self.run_lua("""
            players[2] = { hash = 2, ControllerIndex = 0, Position = Vector(0, 0), cards = {}, ToPlayer = function(s) return s end }
            players[3] = { hash = 3, ControllerIndex = 1, Position = Vector(0, 0), cards = {}, ToPlayer = function(s) return s end }
            P2, P3 = players[2], players[3]
            local function blocked(player, action, hook)
                return fire(ModCallbacks.MC_INPUT_ACTION, player, hook or InputHook.IS_ACTION_TRIGGERED, action)
            end
            start(); useTicket(P1)
            for _, action in ipairs({ButtonAction.ACTION_SHOOTLEFT, ButtonAction.ACTION_SHOOTRIGHT,
                ButtonAction.ACTION_SHOOTUP, ButtonAction.ACTION_SHOOTDOWN, ButtonAction.ACTION_PILLCARD}) do
                assert(blocked(P2, action) == false and blocked(P2, action, InputHook.GET_ACTION_VALUE) == 0,
                    'a same-controller player cannot shoot or use a card while the picker is open')
                assert(blocked(P3, action) == nil, 'another controller is untouched')
            end
            assert(blocked(P2, ButtonAction.ACTION_LEFT) == nil, 'walking stays free')
            press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            press(P1, ButtonAction.ACTION_PILLCARD, true); fire(ModCallbacks.MC_POST_UPDATE)
            assert(not T.picking(P1) and not T.picking(P2) and #T.queue() == 1, 'only the picker confirms')
            assert(blocked(P2, ButtonAction.ACTION_PILLCARD) == false,
                "the confirming press cannot use the second player's pocket item")
            assert(blocked(P2, ButtonAction.ACTION_SHOOTRIGHT) == nil, 'their shooting is back with the picker')
            press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            assert(blocked(P2, ButtonAction.ACTION_PILLCARD) == nil and blocked(P1, ButtonAction.ACTION_PILLCARD) == nil,
                'released, the card key is free for both')
        """)

    def test_a_picker_whose_player_leaves_is_handed_back_and_never_counts_twice(self):
        self.run_lua("""
            players[2] = { hash = 2, ControllerIndex = 1, Position = Vector(0, 0), cards = {}, ToPlayer = function(s) return s end }
            players[3] = { hash = 3, ControllerIndex = 0, Position = Vector(0, 0), cards = {}, ToPlayer = function(s) return s end }
            P2, P3 = players[2], players[3]
            start(); useTicket(P3); useTicket(P3)
            assert(T.picking(P3) and playerSaves[3].conchTicketPick.open == 2)
            table.remove(players, 3)                              -- the extra player leaves the run
            local before = saves
            fire(ModCallbacks.MC_POST_UPDATE)
            assert(not T.picking(P3) and next(T._test.pickers()) == nil, 'the departed picker is closed')
            assert(#P1.cards == 2 and P1.cards[1] == 88 and #P2.cards == 0,
                'both open tickets go back to the remaining player on the same controller')
            assert(playerSaves[3].conchTicketPick.open == 0 and saves > before, 'their saved picker cannot reopen')
            assert(fire(ModCallbacks.MC_INPUT_ACTION, P1, InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT) == nil,
                'the departed picker no longer withholds that controller')
            fire(ModCallbacks.MC_POST_UPDATE); assert(#P1.cards == 2, 'handed back once')
            players[3] = P3; fire(ModCallbacks.MC_PRE_GAME_EXIT); start()
            assert(not T.picking(P3), 'a returning player does not reopen the handed-back tickets')
        """)

    def test_a_departed_picker_with_no_same_controller_player_goes_to_anyone_left(self):
        self.run_lua("""
            players[2] = { hash = 2, ControllerIndex = 1, Position = Vector(0, 0), cards = {}, ToPlayer = function(s) return s end }
            P2 = players[2]
            start(); useTicket(P2)
            table.remove(players, 2); fire(ModCallbacks.MC_POST_UPDATE)
            assert(#P1.cards == 1 and P1.cards[1] == 88 and not T.picking(P2))
        """)

    def test_the_bench_key_source_drives_the_same_picker_and_never_outlives_a_run(self):
        self.run_lua("""
            start(); useTicket(P1); press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            T._test.hold(ButtonAction.ACTION_SHOOTRIGHT, true); fire(ModCallbacks.MC_POST_UPDATE)
            T._test.hold(ButtonAction.ACTION_SHOOTRIGHT, false); fire(ModCallbacks.MC_POST_UPDATE)
            assert(playerSaves[1].conchTicketPick.index == 3, 'held keys feed the same reads')
            T._test.hold(ButtonAction.ACTION_PILLCARD, true); fire(ModCallbacks.MC_POST_UPDATE)
            assert(T.queue()[1] == 'negative' and reserved() == 'negative')
            fire(ModCallbacks.MC_PRE_GAME_EXIT); start()
            useTicket(P1); press(P1, ButtonAction.ACTION_PILLCARD, false); fire(ModCallbacks.MC_POST_UPDATE)
            fire(ModCallbacks.MC_POST_UPDATE)
            assert(T.picking(P1), 'a held bench key does not survive into the next run')
        """)

    def test_the_picker_and_the_reserved_answers_are_drawn(self):
        self.run_lua("""
            start(); useTicket(P1); press(P1, ButtonAction.ACTION_PILLCARD, false)
            drawn = {}; fire(ModCallbacks.MC_POST_RENDER)
            local text = table.concat(drawn, '|')
            assert(text:find('[ui.conch_mode.flags.neutral]', 1, true), text)
            assert(text:find('ui.conch_ticket.hint', 1, true), text)
            tap(P1, ButtonAction.ACTION_PILLCARD)
            drawn = {}; fire(ModCallbacks.MC_POST_RENDER)
            text = table.concat(drawn, '|')
            assert(not text:find('ui.conch_ticket.hint', 1, true), 'the picker closed')
            assert(text:find('ui.conch_ticket.reserved:ui.conch_mode.flags.neutral', 1, true), text)
            for _, message in ipairs(errors) do
                assert(message:find('FONT_FALLBACK', 1, true), message) -- the harness has no font
            end
        """)


if __name__ == '__main__':
    unittest.main()
