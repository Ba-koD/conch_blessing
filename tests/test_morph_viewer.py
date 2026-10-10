"""Shipped Lua visual lifecycle/input checks, not evidence of engine rendering."""
import json
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class MorphVisualTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().repo = ROOT.as_posix()
        self.lua.execute('''
            package.path=repo..'/?.lua;'..package.path
            callbacks={}; errors={}; messages={}; drawings={}; sounds={}; paused=false; pressed={}
            ModCallbacks={MC_POST_UPDATE=1,MC_POST_RENDER=2,MC_POST_NEW_ROOM=3,MC_POST_GAME_STARTED=4,
                MC_PRE_GAME_EXIT=5,MC_EXECUTE_CMD=6,MC_INPUT_ACTION=7,MC_POST_BACKDROP_PRE_RENDER_WALLS=8}
            InputHook={GET_ACTION_VALUE=2,IS_ACTION_PRESSED=0,IS_ACTION_TRIGGERED=1}
            ButtonAction={ACTION_RESTART=16,ACTION_SHOOTLEFT=4,ACTION_SHOOTRIGHT=5,
                ACTION_LEFT=0,ACTION_RIGHT=1,ACTION_UP=2,ACTION_DOWN=3,ACTION_SHOOTUP=6,ACTION_SHOOTDOWN=7}
            Keyboard={KEY_R=82,KEY_LEFT=263,KEY_RIGHT=262,KEY_UP=265,KEY_DOWN=264,KEY_BACKSPACE=259}
            Input={IsButtonTriggered=function(k) local p=pressed[k]; pressed[k]=nil; return p end}
            PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_TRINKET=350}
            SoundEffect={SOUND_HOLY=1,SOUND_REDLIGHTNING_ZAP=2,SOUND_ROCKET_BLAST_DEATH=3,SOUND_BOSS1_EXPLOSIONS=4}
            function Vector(x,y) return {X=x,Y=y} end
            function Color(r,g,b,a,...) return {R=r,G=g,B=b,A=a} end
            function SFXManager() return {Play=function(_,id) sounds[#sounds+1]=id end,
                Stop=function() end,AdjustVolume=function() end} end
            room={GetCenterPos=function() return Vector(320,180) end,
                GetBottomRightPos=function() return Vector(600,320) end,
                GetGridSize=function() return 9 end,
                GetGridPosition=function(_,i) return Vector(240+i%3*40,140+math.floor(i/3)*40) end,
                IsPositionInRoom=function() return true end}
            game={GetRoom=function() return room end,IsPaused=function() return paused end,
                GetNumPlayers=function() return 1 end,ShakeScreen=function() shakes=(shakes or 0)+1 end}
            function Game() return game end
            config={GetCollectible=function(_,id) return {GfxFileName='c'..id..'.png'} end,
                GetTrinket=function(_,id) return {GfxFileName='t'..id..'.png'} end}
            Isaac={GetItemConfig=function() return config end,WorldToScreen=function(p) return p end,
                GetItemIdByName=function() return 401 end,GetTrinketIdByName=function() return 42 end,
                GetScreenWidth=function() return 640 end,GetScreenHeight=function() return 360 end,
                RenderText=function(...) end,GetTextWidth=function(s) return #s*5 end,
                ConsoleOutput=function(s) messages[#messages+1]=s end,DebugString=function() end,
                Spawn=function() error('cosmetics cannot spawn entities') end,
                ExecuteCommand=function() error('cosmetics cannot change runs') end}
            Sprite=setmetatable({}, {__call=function()
                local s={Color=Color(1,1,1,1)}
                function s:Load(path) self.path=path; if missing and path:find(missing,1,true) then error('missing asset') end end
                function s:IsLoaded() return true end
                function s:LoadGraphics() end
                function s:ReplaceSpritesheet(_,path) self.sheet=path end
                function s:SetFrame(animation,f) self.animation=animation; self.frame=f end
                function s:Play(animation) self.animation=animation end
                function s:Update() self.frame=(self.frame or 0)+1 end
                function s:IsFinished() return false end
                function s:Render(p)
                    if drawFails then error('render failure') end
                    assert(p.X==p.X and p.Y==p.Y)
                    if self.Scale then assert(self.Scale.X==self.Scale.X and self.Scale.Y==self.Scale.Y) end
                    drawings[#drawings+1]={sheet=self.sheet,path=self.path,frame=self.frame,pos=p,alpha=self.Color.A}
                end
                return s
            end})
            ConchBlessing={ItemData={},AddCallback=function(_,id,fn)
                callbacks[id]=callbacks[id] or {}; table.insert(callbacks[id],fn)
            end,printError=function(s) errors[#errors+1]=s end}
            function event(id,...)
                local result
                for _,f in ipairs(callbacks[id] or {}) do local r=f(nil,...); if r~=nil then result=r end end
                return result
            end
            V=require('scripts.lib.upgrade_visuals')
            for i,row in ipairs(V.catalog) do
                ConchBlessing.ItemData[row.key]={id=1000+i,type=i>=23 and 'trinket' or 'passive',
                    flag='positive',origin={id=i,type=i>=23 and 'trinket' or 'collectible'}}
            end
            function pickup(id)
                local p={Position=Vector(320,180),Variant=100,SubType=id or 1,alive=true,sprite=Sprite()}
                p.sprite.Color={original=true,A=0.8}
                function p:Exists() return self.alive end
                function p:GetSprite() return self.sprite end
                return p
            end
            T=require('scripts.template'); ConchBlessing.template=T
        ''')

    def test_all_31_profiles_render_every_tick_without_entities_or_run_commands(self):
        self.lua.execute('''
            local applied=0
            for _,row in ipairs(V.catalog) do
                if V.isApplied(row.key) then applied=applied+1 end
                local s=V.create(row.key,Vector(320,180))
                for f=0,s.duration do
                    s.frame=f; V.renderFloor(s); V.render(s)
                end
            end
            assert(applied==16 and #errors==0 and #drawings>1000)
        ''')

    def test_hidden_source_holds_until_commit_then_restores_exact_color(self):
        self.lua.execute('''
            p=pickup(); state={}; custom=T.forItem('DRAGON','positive')
            assert(custom.onBeforeChange(p.Position,p,state)==45 and p.sprite.Color.A==0)
            for i=1,70 do T.updateAllAnimations(); T.renderAllAnimations() end
            assert(state.morphScene.frame==44 and p.sprite.Color.A==0 and #T._activeAnimations==1)
            T.cancelForPickup(p); assert(p.sprite.Color.original)
            p.SubType=456
            assert(custom.onAfterChange(p.Position,p,state)==57)
            assert(state.morphScene.frame==45 and state.morphScene.after.sheet=='c456.png')
            for i=1,57 do T.updateAllAnimations() end
            assert(#T._activeAnimations==0 and p.sprite.Color.original and p.sprite.Color.A==0.8)
        ''')

    def test_conversion_chain_does_not_inherit_invisible_color(self):
        self.lua.execute('''
            p=pickup(); a={}; b={}; c=T.forItem('FIRE_BREATH','positive')
            c.onBeforeChange(p.Position,p,a); T.cancelForPickup(p); c.onAfterChange(p.Position,p,a)
            assert(p.sprite.Color.A==0)
            c.onBeforeChange(p.Position,p,b); T.cancelForPickup(p)
            assert(p.sprite.Color.original and p.sprite.Color.A==0.8)
        ''')

    def test_reroll_during_after_animation_releases_the_changed_pickup(self):
        self.lua.execute('''
            p=pickup(); a={}; c=T.forItem('DRAGON','positive')
            c.onBeforeChange(p.Position,p,a); T.cancelForPickup(p); c.onAfterChange(p.Position,p,a)
            p.SubType=999; T.updateAllAnimations()
            assert(p.sprite.Color.original and #T._activeAnimations==0)
        ''')

    def test_concurrent_pickup_cancellation_and_all_boundaries(self):
        for boundary in (3, 4, 5):
            self.lua.execute(f'''
                p=pickup(); q=pickup(); a={{}}; b={{}}; c=T.forItem('ICE_BREATH','positive')
                c.onBeforeChange(p.Position,p,a); c.onBeforeChange(q.Position,q,b)
                T.cancelForPickup(p); assert(p.sprite.Color.original and q.sprite.Color.A==0)
                event({boundary}); assert(q.sprite.Color.original and #T._activeAnimations==0)
            ''')

    def test_missing_assets_fall_back_and_render_failure_unhides(self):
        self.lua.execute('''
            p=pickup(); state={}; missing='conch_upgrade_ice'
            local custom=T.forItem('ICE_BREATH','positive')
            assert(custom.onBeforeChange(p.Position,p,state)==60 and state.morphFallback and #errors==1)
            T.cancelForPickup(p); missing=nil; state={}
            custom.onBeforeChange(p.Position,p,state); drawFails=true
            T.renderAllAnimations(); T.updateAllAnimations()
            assert(p.sprite.Color.original and #T._activeAnimations==0 and #errors==2)
        ''')

    def test_cues_only_advance_on_updates_and_missile_shakes_once(self):
        self.lua.execute('''
            local s=V.create('SOFLAM',Vector(320,180))
            for i=1,10 do V.render(s) end
            assert(#sounds==0 and s.frame==0)
            for i=1,102 do V.update(s) end
            assert(#sounds==2 and shakes==1)
            local after=V.create('SOFLAM',Vector(320,180),100,1,53)
            V.update(after); V.update(after); assert(shakes==2)
        ''')

    def test_correct_origin_type_golden_normalization_and_aliases(self):
        self.lua.execute('''
            local s=V.create('TIME_TEAR',Vector(320,180),350,32768+39)
            assert(s.before.sheet=='t39.png' and s.sourceVariant==350)
            assert(V.resolveKey('liveeye')=='LIVE_EYE' and V.resolveKey('live_eye')=='LIVE_EYE')
            assert(V.resolveKey('liveeye trailing')==nil)
            assert(T.forItem('KRONOS','positive')==T.positive)
        ''')

    def viewer(self):
        self.lua.execute("W=require('scripts.dev.morph_viewer')")

    def test_viewer_selection_replay_wrapping_unknown_and_stop(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','liveeye'); assert(W.isRunning() and W.index==1)
            pressed[263]=true; event(2); assert(W.index==31)
            pressed[262]=true; event(2); assert(W.index==1)
            pressed[82]=true; event(2); assert(W.index==1 and W.isRunning())
            event(6,'conch_morph','liveeye trailing'); assert(W.index==1)
            event(6,'conch_morph','stop'); assert(not W.isRunning())
            event(6,'conch_morph','soflam'); assert(W.index==16)
            pressed[259]=true; event(2); assert(not W.isRunning())
        ''')

    def test_viewer_input_scope_pause_and_transitions(self):
        self.viewer()
        self.lua.execute('''
            assert(event(7,nil,0,16)==nil)
            event(6,'conch_morph',''); assert(event(7,nil,0,16)==false)
            assert(event(7,nil,2,16)==0 and event(7,nil,1,4)==false)
            assert(event(7,nil,0,99)==nil)
            paused=true; pressed[262]=true; event(2); assert(W.index==1)
            pressed={}; paused=false; event(3); assert(not W.isRunning())
            assert(event(7,nil,0,16)==nil)
            event(6,'conch_morph',''); event(4); assert(not W.isRunning())
            event(6,'conch_morph',''); event(5); assert(not W.isRunning())
        ''')

    def test_viewer_releases_capture_on_errors_and_test_suite(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph',''); drawFails=true; event(2)
            assert(not W.isRunning() and event(7,nil,0,16)==nil)
            drawFails=false; event(6,'conch_morph','')
            package.loaded['scripts.dev.test_bench']={isRunning=function() return true end}
            event(1); assert(not W.isRunning())
            event(6,'conch_morph',''); assert(not W.isRunning())
        ''')

    def test_no_repentogon_floor_hook_still_runs(self):
        self.lua.execute('ModCallbacks.MC_POST_BACKDROP_PRE_RENDER_WALLS=nil')
        self.viewer()
        self.lua.execute("event(6,'conch_morph','moneytear'); event(1); event(2); assert(W.isRunning() and #errors==0)")

    def test_localized_font_hud_and_hud_failure_release_input(self):
        self.lua.execute('''
            hudText={}
            package.loaded['scripts.conch_blessing_config']={GetCurrentLanguage=function() return 'kr' end}
            function KColor(...) return {...} end
            Font=setmetatable({}, {__call=function() return {
                Load=function() end,IsLoaded=function() return true end,
                GetStringWidthUTF8=function(_,s) return #s*3 end,
                DrawStringScaledUTF8=function(_,s)
                    if hudFailure then error('HUD failure') end
                    hudText[#hudText+1]=s
                end} end})
        ''')
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','soflam'); event(2)
            assert(W.isRunning() and #hudText>0)
            local found=false
            for _,s in ipairs(hudText) do if s=='인게임 적용' then found=true end end
            assert(found)
            hudFailure=true; event(2); assert(not W.isRunning() and event(7,nil,0,16)==nil)
        ''')

    def test_html_approval_list_exactly_matches_runtime_catalog(self):
        html = (ROOT/'docs/previews/item-upgrade-player.html').read_text(encoding='utf-8')
        rows = json.loads(re.search(r'id="upgrade-data"[^>]*>(.*?)</script>', html, re.S)[1])
        catalog = self.lua.globals().V.catalog
        for index, row in enumerate(rows, 1):
            self.assertEqual(row['key'], catalog[index].key)
            self.assertEqual(row['applied'], bool(catalog[index].effect))
        self.assertEqual(sum(row['applied'] for row in rows), 16)
        self.assertIn('id="filter-applied"', html)
        self.assertIn('id="filter-pending"', html)

    def test_runtime_assets_have_bounded_frames_and_resolvable_sheets(self):
        # Missing vanilla extraction is a limitation, never an engine-render PASS.
        vanilla = ROOT.parent.parent/'extracted_resources/resources'
        for path in (ROOT/'resources/gfx/effects').glob('conch_upgrade_*.anm2'):
            tree = ET.parse(path)
            for sheet in tree.findall('.//Spritesheet'):
                local = (path.parent/sheet.get('Path')).resolve()
                relative = Path('gfx/effects')/sheet.get('Path')
                self.assertTrue(local.exists() or (vanilla/relative).exists(), str(relative))
            for frame in tree.findall('.//LayerAnimation/Frame'):
                self.assertGreater(int(frame.get('Width')), 0)
                self.assertGreater(int(frame.get('Height')), 0)


if __name__ == '__main__':
    unittest.main()
