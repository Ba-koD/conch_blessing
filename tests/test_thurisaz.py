"""Thurisaz, the Kronos rune: production Lua with engine/provider doubles.

The rune devours up to three of the user's familiars for good, giving each one's
+2 damage and absorbed ability with or without Kronos, and Kronos's loss never
hands them back. These doubles do not prove native familiar removal, the card's
use animation or the pocket-slot art; the in-game bench covers those.
"""
import contextlib
import io
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from PIL import Image

import generate_pocket_assets
import generate_xml
import lua_data
import test_kronos_room_effects as kronos_tests

ROOT = Path(__file__).resolve().parents[1]


class ThurisazTests(unittest.TestCase):
    def setUp(self):
        kronos_tests.KronosRoomEffectsTests.setUp(self)
        self.lua.execute(r"""
            spawned={}
            Isaac.Spawn=function(kind,variant,subtype,position) spawned[#spawned+1]={kind=kind,variant=variant} end
            function player:Exists() return true end
            function player:ToPlayer() return self end
            function player:GetCollectibleRNG()
                return {Next=function() return 123 end,RandomFloat=function() return 0.999 end}
            end
            function effects:GetCollectibleEffectNum(id) return self[id] or 0 end
            function effects:RemoveCollectibleEffect(id,count) self[id]=math.max(0,(self[id] or 0)-count) end
            other={hash=2,inventory={},data={}}
            -- A live familiar of `owner`; item=nil has no collectible behind it,
            -- noConfig drops REPENTOGON's lookup entirely.
            function familiar(item,options)
                options=options or {}
                local f={Player=options.owner or player,data={},hash=#familiars+100,alive=true,Position=Vector(4,5)}
                function f:GetData() return self.data end
                function f:ToFamiliar() return self end
                function f:Exists() return self.alive end
                function f:IsDead() return false end
                function f:Remove() self.alive=false end
                if not options.noConfig then
                    function f:GetItemConfig()
                        if item then return {ID=item,Type=options.type or ItemType.ITEM_FAMILIAR} end
                    end
                end
                familiars[#familiars+1]=f
                return f
            end
            -- An owned familiar collectible: the item and its live familiar.
            function owned(name)
                local id=CollectibleType['COLLECTIBLE_'..name]
                player:AddCollectible(id)
                return id,familiar(id)
            end
            function first(n) return 0 end
            function ledger() return per.thurisaz end
            function dropKronos() player.inventory[9999]=nil end
        """)

    def test_devours_three_owned_familiars_for_good_without_kronos(self):
        self.lua.execute("""
            dropKronos()
            local bobby=owned('BROTHER_BOBBY'); local angel=owned('GUARDIAN_ANGEL')
            local sack=owned('SACK_OF_PENNIES'); local fly=owned('LIL_HAUNT')
            assert(K.devourWithRune(player,3,first)==3)
            assert(player:GetCollectibleNum(bobby)==0 and player:GetCollectibleNum(angel)==0)
            assert(player:GetCollectibleNum(sack)==0 and player:GetCollectibleNum(fly)==1,
                'only three of four were devoured')
            assert(ledger().absorbed['fam_'..bobby]==1 and K.getRuneTotal(player)==3)
            near(damageBonus(),6)
            player:EvaluateItems()
            near(player.Tears,30/11+2); near(player.MoveSpeed,1.3)
            assert(run.kronos.totalAbsorbed==0,'Kronos ledger untouched')
            assert(#spawned==3,'one poof per devoured familiar')
        """)

    def test_takes_what_there_is_and_nothing_from_nothing(self):
        self.lua.execute("""
            dropKronos()
            assert(K.devourWithRune(player,3,first)==0 and ledger()==nil,'no familiar, no ledger')
            local bobby=owned('BROTHER_BOBBY')
            assert(K.devourWithRune(player,3,first)==1)
            assert(K.getRuneTotal(player)==1); near(damageBonus(),2)
        """)

    def test_only_the_users_own_familiars_and_never_kronos_stand_ins(self):
        self.lua.execute("""
            dropKronos()
            familiar(CollectibleType.COLLECTIBLE_BROTHER_BOBBY,{owner=other})
            local anchor=familiar(CollectibleType.COLLECTIBLE_INCUBUS); anchor.data.__kronosIncubus=true
            local mini=familiar(nil); mini.data.__kronosMongoMinisaac=true
            assert(K.devourWithRune(player,3,first)==0)
            assert(familiars[1]:Exists() and anchor:Exists() and mini:Exists())
        """)

    def test_familiars_with_no_collectible_give_flat_damage(self):
        self.lua.execute("""
            dropKronos()
            local fly=familiar(nil)                      -- a blue fly
            local wisp=familiar(55,{type='active'})   -- an item wisp
            assert(K.devourWithRune(player,3,first)==2)
            assert(not fly:Exists() and not wisp:Exists())
            assert(ledger().generic==2 and next(ledger().absorbed)==nil)
            near(damageBonus(),4)
        """)

    def test_a_temporary_copy_goes_before_an_owned_one(self):
        self.lua.execute("""
            dropKronos()
            local bobby,owner=owned('BROTHER_BOBBY')
            effects[bobby]=1; local temp=familiar(bobby)
            assert(K.devourWithRune(player,1,function(n) return n-1 end)==1)
            assert(effects[bobby]==0 and not temp:Exists(),'the temporary copy was devoured')
            assert(player:GetCollectibleNum(bobby)==1,'the owned copy stays')
            assert(ledger().absorbed['fam_'..bobby]==1)
        """)

    def test_kronos_loss_never_returns_rune_familiars(self):
        self.lua.execute("""
            local bobby=absorb('BROTHER_BOBBY',1)        -- Kronos's own absorption
            local angel=owned('GUARDIAN_ANGEL')
            assert(K.devourWithRune(player,3,first)==1)
            near(damageBonus(),4)
            player:RemoveCollectible(9999); K._revertAll(player)
            assert(player:GetCollectibleNum(bobby)==1,'Kronos handed back its own')
            assert(player:GetCollectibleNum(angel)==0,'the rune keeps its familiar')
            near(damageBonus(),2)
            player:EvaluateItems(); near(player.MoveSpeed,1.3); near(player.Tears,30/11)
            K.onGameStarted(); near(damageBonus(),2)
        """)

    def test_conversion_items_follow_kronos_limits_and_stay(self):
        self.lua.execute("""
            dropKronos()
            local tech=CollectibleType.COLLECTIBLE_TECHNOLOGY
            local ipecac=CollectibleType.COLLECTIBLE_IPECAC
            owned('ROBO_BABY'); owned('ROBO_BABY')
            owned('BOBS_BRAIN'); owned('BOBS_BRAIN')
            assert(K.devourWithRune(player,4,first)==4)
            assert(player:GetCollectibleNum(tech)==2,'Robo-Baby grants Technology each time')
            assert(player:GetCollectibleNum(ipecac)==1,"Bob's Brain grants Ipecac once")
            K._revertAll(player)
            assert(player:GetCollectibleNum(tech)==2 and player:GetCollectibleNum(ipecac)==1)
        """)

    def test_box_of_friends_doubles_rune_damage_only_under_kronos(self):
        self.lua.execute("""
            dropKronos(); owned('BROTHER_BOBBY'); K.devourWithRune(player,3,first)
            useBox(); near(damageBonus(),2)
            player:AddCollectible(9999); useBox(); K._syncAbsorbedDamage(player)
            near(damageBonus(),4)
            K.onNewRoom(); near(damageBonus(),2)
        """)

    def test_paschal_earnings_outlive_kronos_only_for_the_rune(self):
        self.lua.execute("""
            dropKronos(); owned('PASCHAL_CANDLE'); K.devourWithRune(player,3,first)
            K.onRoomClear(nil,nil,Vector.Zero)
            assert(run.kronos.paschalHundredths==3)
            K._revertAll(player)
            assert(run.kronos.paschalHundredths==3,'the rune still owns Paschal Candle')
            player:EvaluateItems(); near(player.Tears,30/11+0.03)
        """)

    def test_base_api_fallback_devours_owned_familiar_collectibles(self):
        self.lua.execute("""
            dropKronos()
            local bobby=CollectibleType.COLLECTIBLE_BROTHER_BOBBY
            Isaac.GetItemConfig=function()
                return {GetCollectible=function(_,id) if id==bobby then return {ID=id,Type=ItemType.ITEM_FAMILIAR} end end}
            end
            player:AddCollectible(bobby); player:AddCollectible(bobby)
            familiar(bobby,{noConfig=true}); familiar(bobby,{noConfig=true}); familiar(nil,{noConfig=true})
            assert(K.devourWithRune(player,3,first)==2,'only the owned copies count')
            assert(player:GetCollectibleNum(bobby)==0 and familiars[3]:Exists())
        """)

    def test_card_callback_uses_the_card_rng_and_three_picks(self):
        self.lua.execute("""
            dropKronos()
            ConchBlessing.PocketData={THURISAZ={id=77}}
            ConchBlessing.printDebug=function() end
            require('scripts.items.cards.thurisaz')
            local draws={}
            function player:GetCardRNG(card)
                assert(card==77)
                return {RandomInt=function(_,n) draws[#draws+1]=n; return 0 end}
            end
            owned('BROTHER_BOBBY'); owned('GUARDIAN_ANGEL'); owned('SACK_OF_PENNIES'); owned('LIL_HAUNT')
            local use=callbacks[ModCallbacks.MC_USE_CARD][77]
            use(nil,76,player); assert(#draws==0,'another card does nothing')
            use(nil,77,player)
            assert(#draws==3 and draws[1]==4 and draws[2]==3 and draws[3]==2)
            assert(K.getRuneTotal(player)==3)
        """)


class ThurisazContentTests(unittest.TestCase):
    def test_registry_text_and_art_agree(self):
        pockets = generate_xml.load_pockets()
        self.assertEqual(list(pockets), ['THURISAZ', 'CONCH_TICKET'])
        rune = pockets['THURISAZ']
        self.assertEqual((rune['name'], rune['type'], rune['hud']), ('Thurisaz', 'rune', 'Thurisaz'))
        for lang in ('en', 'kr', 'urimal'):
            entry = lua_data.load(f'scripts/locale/{lang}.lua')['pockets']['THURISAZ']
            # User-designated copy: three random familiars, then the reward, then the note.
            self.assertEqual(len(entry['eid']), 3, lang)
            self.assertFalse(entry['eid'][0].startswith('#'), lang)
            self.assertIn('3', entry['eid'][0], lang)
            self.assertNotIn('{own:KRONOS}', ''.join(entry['eid']), lang)
        kr = lua_data.load('scripts/locale/kr.lua')['pockets']['THURISAZ']['eid']
        self.assertEqual(kr[0], '랜덤 펫 3마리를 흡수합니다.')
        self.assertNotIn('적으면', ''.join(kr))
        sheet = Image.open(ROOT / 'resources/gfx' / rune['gfx']).convert('RGBA')
        self.assertEqual(sheet.size, (96, 32))
        body = sheet.crop((0, 0, 32, 32))
        pocket = sheet.crop((64, 0, 96, 32))
        self.assertEqual(pocket.getbbox()[:2], body.getbbox()[:2], 'the pocket art is the stone')
        self.assertGreater(pocket.getbbox()[2], body.getbbox()[2], 'with a drop shadow')

    def test_generated_files_are_stable_and_well_formed(self):
        pockets = generate_xml.load_pockets()
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()):
            items_path = Path(folder) / 'pocketitems.xml'
            fronts = Path(folder) / 'gfx/ui_cardfronts.anm2'
            entities = Path(folder) / 'entities2.xml'
            generate_xml.create_pocketitems_xml(pockets, str(items_path))
            generate_xml.create_card_fronts_anm2(pockets, str(fronts))
            generate_xml.create_entities2_xml({}, str(entities), {}, pockets)
            outputs = [path.read_bytes() for path in (items_path, fronts, entities)]
            generate_xml.create_pocketitems_xml(pockets, str(items_path))
            generate_xml.create_card_fronts_anm2(pockets, str(fronts))
            generate_xml.create_entities2_xml({}, str(entities), {}, pockets)
            self.assertEqual(outputs, [path.read_bytes() for path in (items_path, fronts, entities)])
            rune = ET.parse(items_path).getroot().find('rune')
            self.assertEqual(rune.attrib, {'type': 'rune', 'name': 'Thurisaz', 'description': 'Devour',
                                           'hud': 'Thurisaz', 'pickup': '7781', 'mimiccharge': '6'})
            row = ET.parse(entities).getroot().find('entity')
            self.assertEqual((row.get('id'), row.get('variant'), row.get('subtype')), ('5', '300', '7781'))
            self.assertEqual(row.get('anm2path'), '005.300_thurisaz.anm2')
            sheet = ET.parse(fronts).getroot().find('Content/Spritesheets/Spritesheet')
            self.assertEqual(sheet.get('Path'), '../../resources/gfx/items/pick ups/pickup_thurisaz.png')
            frame = ET.parse(fronts).getroot().find(".//Animation[@Name='Thurisaz']//LayerAnimation/Frame")
            self.assertEqual((frame.get('XCrop'), frame.get('Width')), ('64', '32'))

    def test_rejects_definitions_the_game_would_misread(self):
        good = lua_data.load('scripts/items/cards/definitions.lua')['THURISAZ']
        bad = [dict(good, type='trinket'), dict(good, pickup=300), dict(good, mimiccharge=-1),
               dict(good, gfx='../escape.png'), dict(good, extra=1)]
        original = lua_data.load
        for definition in bad:
            def fake(path, definition=definition):
                return {'THURISAZ': definition} if path.endswith('definitions.lua') else original(path)
            lua_data.load = fake
            try:
                with self.assertRaises(ValueError):
                    generate_xml.load_pockets()
            finally:
                lua_data.load = original

    def test_a_dropped_rune_is_tossed_from_the_floor_and_settles_into_idle(self):
        def tracks(name):
            anim = next(a for a in ET.parse(ROOT / 'resources/gfx/005.300_thurisaz.anm2').getroot().iter('Animation')
                        if a.get('Name') == name)
            return {la.get('LayerId'): list(la) for la in anim.find('LayerAnimations')}
        def at(frames, t):
            start = 0
            for frame in frames:
                if t < start + int(frame.get('Delay')):
                    return frame
                start += int(frame.get('Delay'))
        appear, idle = tracks('Appear'), tracks('Idle')
        body = appear['0']
        shown = [f for f in body if f.get('Visible') == 'true']
        self.assertEqual(float(shown[0].get('YPosition')), 0, 'it springs out of the floor, never materializes mid-air')
        self.assertLessEqual(min(float(f.get('YPosition')) for f in shown), -15, 'a real arc')
        landing = at(body, generate_pocket_assets.THURISAZ_LAND)
        self.assertGreater(float(landing.get('XScale')), float(landing.get('YScale')), 'squashed as it lands')
        self.assertLessEqual(abs(float(landing.get('YPosition'))), 1)
        for layer in ('0', '1'):
            last, first = appear[layer][-1], idle[layer][0]
            for attr in ('YPosition', 'XScale', 'YScale', 'RedTint', 'AlphaTint', 'Rotation'):
                self.assertEqual(last.get(attr), first.get(attr), f"layer {layer} {attr}: Appear ends on Idle's first pose")
            loop_end = idle[layer][-1]
            for attr in ('YPosition', 'XScale', 'YScale', 'RedTint', 'AlphaTint'):
                self.assertEqual(loop_end.get(attr), first.get(attr), f'layer {layer} {attr}: Idle loops without a seam')

    def test_pickup_animation_has_every_animation_the_engine_plays(self):
        root = ET.parse(ROOT / 'resources/gfx/005.300_thurisaz.anm2').getroot()
        names = [a.get('Name') for a in root.iter('Animation')]
        self.assertEqual(names, ['Idle', 'Appear', 'Collect', 'Sparkle', 'HUD', 'HUDSmall'])
        appear = root.find(".//Animation[@Name='Appear']")
        self.assertEqual(appear.find('Triggers/Trigger').get('AtFrame'), str(generate_pocket_assets.THURISAZ_LAND))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'again.anm2'
            generate_pocket_assets.write_anm2(path, generate_pocket_assets.THURISAZ_SHEET,
                                              generate_pocket_assets.THURISAZ_ANIMATIONS)
            self.assertEqual(path.read_bytes(), (ROOT / 'resources/gfx/005.300_thurisaz.anm2').read_bytes())


if __name__ == '__main__':
    unittest.main()
