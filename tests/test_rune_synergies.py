"""Runes that share an item's EID synergy lines: Thurisaz shows Kronos's.

Production scripts/lib/pocket_synergies.lua, Thurisaz's line rule and the locale
loader, with doubles for the players' pocket slots and the frame counter. EID's
own rendering of the lines stays an in-game check (`conch_test locale`).
"""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

import test_thurisaz as thurisaz_tests

ROOT = Path(__file__).resolve().parents[1]


class PocketSynergiesTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r"""
            package.path=root..'/?.lua;'..package.path
            frame=1; reads=0
            Isaac={GetFrameCount=function() return frame end}
            -- A player double: `cards` holds its pocket slots 0..3.
            function makePlayer(cards)
                local p={cards=cards or {}}
                function p:GetCard(slot) reads=reads+1; return self.cards[slot] or 0 end
                return p
            end
            players={makePlayer(),makePlayer()}
            gameCalls=0
            function Game()
                gameCalls=gameCalls+1
                return {GetNumPlayers=function() return #players end,
                        GetPlayer=function(_,i) return players[i+1] end}
            end
            rule=function() return true end
            ConchBlessing={
                ItemData={KRONOS={id=500,type='passive'}},
                PocketData={
                    THURISAZ={id=77,synergyItem='KRONOS',synergyLine=function(id,isTrinket) return rule(id,isTrinket) end},
                    CONCH_TICKET={id=78},
                    LOST={id=79,synergyItem='NOT_AN_ITEM'},
                },
            }
            P=require('scripts.lib.pocket_synergies')
            function heldKeys()
                local keys={}
                for i,row in ipairs(P.held()) do keys[i]=row.id end
                return table.concat(keys,',')
            end
        """)

    def test_only_runes_naming_a_real_item_share_and_are_found_by_card(self):
        self.lua.execute("""
            assert(P.byCard(77)==ConchBlessing.PocketData.THURISAZ)
            assert(P.byCard(78)==nil,'a card without synergyItem shares nothing')
            assert(P.byCard(79)==nil,'a rune naming no ItemData row shares nothing')
            assert(P.item(P.byCard(77))==ConchBlessing.ItemData.KRONOS)
            assert(P.icon(P.byCard(77))=='{{Card77}}')
        """)

    def test_held_in_any_pocket_slot_of_any_player(self):
        self.lua.execute("""
            assert(heldKeys()=='', 'empty pockets hold nothing')
            frame=2; players[1].cards[0]=78
            assert(heldKeys()=='', 'another card is not the rune')
            frame=3; players[2].cards[3]=77
            assert(heldKeys()=='77', "the second player's last slot counts")
        """)

    def test_slots_are_read_once_per_render_frame(self):
        self.lua.execute("""
            players[1].cards[1]=77
            assert(heldKeys()=='77')
            local first=reads
            assert(first==8,'four slots of two players, read '..first)
            players[1].cards[1]=0
            assert(heldKeys()=='77','the same frame keeps its answer')
            assert(reads==first,'and reads nothing again')
            frame=frame+1
            assert(heldKeys()=='','the next frame reads the slots again')
        """)

    def test_without_sharing_runes_no_player_is_read(self):
        self.lua.execute("""
            ConchBlessing.PocketData={CONCH_TICKET={id=78}}
            P.reset()
            assert(heldKeys()=='' and gameCalls==0 and reads==0)
        """)

    def test_the_rune_rule_picks_shared_own_or_no_text(self):
        self.lua.execute("""
            local rune=P.byCard(77)
            local shared={en='Kronos line'}
            assert(P.text(rune,1,false,shared)==shared,'true shares the item text')
            local seen
            rule=function(id,isTrinket) seen={id,isTrinket}; return false end
            assert(P.text(rune,5,nil,shared)==nil,'false shows nothing')
            assert(seen[1]==5 and seen[2]==false,'isTrinket reaches the rule as a boolean')
            local own={en='own'}
            rule=function() return own end
            assert(P.text(rune,5,true,shared)==own,'a table is the rune line')
            rune.synergyLine=nil
            assert(P.text(rune,5,true,shared)==shared,'no rule shares everything')
        """)


class ThurisazLineRuleTests(unittest.TestCase):
    """Thurisaz's rule over Kronos's lines, with the Kronos module loaded."""

    def setUp(self):
        thurisaz_tests.ThurisazTests.setUp(self)
        self.lua.execute("""
            ConchBlessing.PocketData={THURISAZ={id=77,synergies={not_absorbed={en='Cannot be absorbed by Thurisaz.'}}}}
            ConchBlessing.printDebug=function() end
            require('scripts.items.cards.thurisaz')
            rune=ConchBlessing.PocketData.THURISAZ
        """)

    def test_shares_kronos_lines(self):
        self.lua.execute("""
            assert(rune.synergyItem=='KRONOS')
            for _,name in ipairs({'BOBS_BRAIN','ROBO_BABY','SUCCUBUS','MONGO_BABY','BUDDY_IN_A_BOX'}) do
                assert(rune.synergyLine(CollectibleType['COLLECTIBLE_'..name],false)==true,name)
            end
        """)

    def test_kronos_only_sources_show_nothing(self):
        self.lua.execute("""
            for _,name in ipairs({'GB_BUG','BOX_OF_FRIENDS','MONSTER_MANUAL','SACRIFICIAL_ALTAR'}) do
                assert(rune.synergyLine(CollectibleType['COLLECTIBLE_'..name],false)==false,name)
            end
            assert(rune.synergyLine(TrinketType.TRINKET_THE_TWINS,true)==false,'The Twins trinket')
            assert(rune.synergyLine(TrinketType.TRINKET_THE_TWINS,false)==true,
                'a collectible with The Twins trinket number is another item')
        """)

    def test_familiars_it_never_devours_read_its_own_line(self):
        self.lua.execute("""
            local blacklist=ConchBlessing.kronos.data.blacklist
            local count=0
            for id in pairs(blacklist) do
                count=count+1
                assert(rune.synergyLine(id,false)==rune.synergies.not_absorbed,'blacklisted '..id)
                assert(rune.synergyLine(id,true)==true,'a trinket with that number is not blacklisted')
            end
            assert(count==10,'Kronos blacklists ten familiars, '..count)
        """)


class RuneLocaleTests(unittest.TestCase):
    def test_the_loader_fills_the_runes_own_lines_in_every_language(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().root = ROOT.as_posix()
        lua.execute(r"""
            package.path=root..'/?.lua;'..package.path
            CollectibleType={}; TrinketType={}; Card={}
            ConchBlessing={printError=function(message) error(message) end}
            Locale=require('scripts.locale.init')
            pockets={THURISAZ={},CONCH_TICKET={}}
            Locale.applyPocketData(pockets)
            local line=pockets.THURISAZ.synergies.not_absorbed
            assert(line.en=='Cannot be absorbed by Thurisaz.',line.en)
            assert(line.kr=='투리사즈에 흡수되지 않습니다.',line.kr)
            assert(line.urimal=='투리사즈에 삼켜지지 않습니다.',line.urimal)
            assert(pockets.CONCH_TICKET.synergies==nil,'a card without lines gets none')
        """)


if __name__ == "__main__":
    unittest.main()
