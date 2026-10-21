"""Production functions: the shared player-hit rule, its dispatcher and the hit icon.

Engine doubles only; which flags the engine really sets for each damage source is
measured in game by `conch_test two_faced_penny hit_kinds`.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class PlayerHitsTests(unittest.TestCase):
    def setUp(self, applied=True):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().source = (ROOT / 'scripts/lib/player_hits.lua').read_text(encoding='utf-8')
        self.lua.execute('''
            package=nil
            DamageFlag={DAMAGE_NOKILL=1,DAMAGE_EXPLOSION=4,DAMAGE_RED_HEARTS=32,DAMAGE_SPIKES=128,
                DAMAGE_DEVIL=1024,DAMAGE_INVINCIBLE=8192,DAMAGE_CURSED_DOOR=65536,DAMAGE_IV_BAG=262144,
                DAMAGE_FAKE=2097152,DAMAGE_NO_MODIFIERS=33554432,DAMAGE_NO_PENALTIES=268435456}
            RoomType={ROOM_DEFAULT=1,ROOM_SACRIFICE=13}; roomType=1
            EntityType={ENTITY_PLAYER=1}
            ModCallbacks={MC_ENTITY_TAKE_DMG=11,MC_POST_PLAYER_RENDER=32,MC_POST_NEW_ROOM=19,
                MC_PRE_GAME_EXIT=17,MC_POST_GAME_STARTED=15}
            frame=100; reflect=false; draws={}; errors={}; registered={}
            RenderMode={RENDER_WATER_REFLECT=2}
            function Game() return {GetFrameCount=function() return frame end,
                GetRoom=function() return {GetType=function() return roomType end,
                    GetRenderMode=function() return reflect and 2 or 1 end} end} end
            local V={}; V.__index=V
            V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
            function Vector(x,y) return setmetatable({X=x,Y=y},V) end
            function Color(...) return {...} end
            function GetPtrHash(e) return e.hash end
            art={[7]='gfx/items/collectibles/seven.png',[8]='gfx/items/trinkets/eight.png'}
            Isaac={WorldToScreen=function(v) return Vector(v.X,v.Y) end,
                GetItemConfig=function() return {
                    GetCollectible=function(_,id) return art[id] and {GfxFileName=art[id]} end,
                    GetTrinket=function(_,id) return art[id] and {GfxFileName=art[id]} end} end}
            function Sprite()
                local s={}
                function s:Load() end; function s:ReplaceSpritesheet(_,path) self.path=path end
                function s:LoadGraphics() end; function s:SetFrame() end
                function s:IsLoaded() return true end
                function s:RenderLayer(layer,pos) draws[#draws+1]={path=self.path,layer=layer,x=pos.X,y=pos.Y,alpha=self.Color[4]} end
                return s
            end
            ConchBlessing={ItemData={SEVEN={id=7,type='passive'},EIGHT={id=8,type='trinket'},NOART={id=9,type='passive'}},
                printError=function(e) errors[#errors+1]=e end}
            function ConchBlessing:AddCallback(id,fn,param) registered[#registered+1]={id=id,fn=fn,param=param} end
            function makePlayer(hash)
                local p={hash=hash,Position=Vector(100,200),PositionOffset=Vector(0,0),SpriteScale=Vector(1,1)}
                function p:ToPlayer() return self end
                return p
            end
            player=makePlayer(1)
        ''')
        if applied:
            self.lua.execute('ModCallbacks.MC_POST_ENTITY_TAKE_DMG=1006')
        self.lua.execute('Hits=load(source,"player_hits")()')

    def test_every_damage_counts_except_self_damage_and_sacrifice_spikes(self):
        self.lua.execute('''
            local F=DamageFlag
            for _,flags in ipairs({0, 0.0, F.DAMAGE_EXPLOSION, F.DAMAGE_SPIKES, F.DAMAGE_NOKILL, F.DAMAGE_INVINCIBLE}) do
                assert(Hits.counts(flags),'should be a hit: '..tostring(flags))
            end
            for _,flags in ipairs({F.DAMAGE_NO_PENALTIES, F.DAMAGE_FAKE, F.DAMAGE_IV_BAG, F.DAMAGE_RED_HEARTS,
                F.DAMAGE_DEVIL, F.DAMAGE_CURSED_DOOR, F.DAMAGE_RED_HEARTS|F.DAMAGE_INVINCIBLE|F.DAMAGE_NOKILL,
                F.DAMAGE_EXPLOSION|F.DAMAGE_NO_PENALTIES}) do
                assert(not Hits.counts(flags),'self-damage counted: '..flags)
            end
            roomType=RoomType.ROOM_SACRIFICE
            assert(not Hits.counts(F.DAMAGE_SPIKES),'Sacrifice Room spikes counted')
            assert(Hits.counts(F.DAMAGE_EXPLOSION),'a bomb in a Sacrifice Room is a hit')
            assert(Hits.counts(F.DAMAGE_SPIKES,RoomType.ROOM_DEFAULT),'explicit room type ignored')
        ''')

    def test_dispatch_runs_every_handler_in_order_and_shows_what_counted(self):
        self.lua.execute('''
            calls={}
            Hits.register('SEVEN',function(_,e,_,flags) calls[#calls+1]='seven'; return Hits.counts(flags) end)
            Hits.register('BROKEN',function() calls[#calls+1]='broken'; error('boom') end)
            Hits.register('CHAIN',function() calls[#calls+1]='chain'; return {'EIGHT','SEVEN'} end)
            Hits.register('QUIET',function() calls[#calls+1]='quiet' end)
            Hits._test.dispatch(player,1,0)
            assert(table.concat(calls,',')=='seven,broken,chain,quiet')
            assert(#errors==1 and errors[1]:find('BROKEN',1,true))
            assert(table.concat(Hits._test.shown(player),',')=='SEVEN,EIGHT','duplicate or missing icon')
            calls={}; Hits._test.dispatch({ToPlayer=function() return nil end},1,0)
            assert(#calls==0,'non-player damage reached the items')
        ''')

    def test_registering_a_key_again_replaces_its_handler(self):
        self.lua.execute('''
            Hits.register('SEVEN',function() return false end)
            Hits.register('SEVEN',function() return true end)
            assert(#Hits.order==1)
            Hits._test.dispatch(player,1,0); assert(Hits._test.shown(player)[1]=='SEVEN')
        ''')

    def test_icon_lasts_one_second_merges_one_update_and_clears_on_room_change(self):
        self.lua.execute('''
            Hits.show(player,{'SEVEN'}); Hits.show(player,{'EIGHT','SEVEN'})
            assert(table.concat(Hits._test.shown(player),',')=='SEVEN,EIGHT')
            frame=frame+1; Hits.show(player,{'EIGHT'})
            assert(table.concat(Hits._test.shown(player),',')=='EIGHT','a later hit did not restart the icon')
            frame=frame+29; assert(Hits._test.shown(player)); frame=frame+1
            assert(Hits._test.shown(player)==nil,'icon outlived its second')
            Hits.show(player,{'SEVEN'}); Hits.clearEffects(); assert(Hits._test.shown(player)==nil)
            local other=makePlayer(2); Hits.show(other,{'EIGHT'})
            assert(Hits._test.shown(player)==nil and Hits._test.shown(other)[1]=='EIGHT','players share icons')
            Hits.show(player,{})
            assert(Hits._test.shown(player)==nil,'empty hit raised an icon')
        ''')

    def test_render_draws_small_icons_above_the_head_and_fades(self):
        self.lua.execute('''
            Hits.show(player,{'SEVEN','EIGHT'})
            Hits.onPlayerRender(nil,player)
            assert(#draws==2 and draws[1].path==art[7] and draws[2].path==art[8] and draws[1].layer==1)
            assert(draws[1].y<200-30 and draws[1].x<100 and draws[2].x>100,'icons not above the head or not centred')
            draws={}; reflect=true; Hits.onPlayerRender(nil,player); assert(#draws==0,'drawn into the water reflection')
            reflect=false; frame=frame+25; Hits.onPlayerRender(nil,player)
            assert(draws[1].alpha<1 and draws[1].alpha>0,'icon does not fade out')
            draws={}; frame=frame+5; Hits.onPlayerRender(nil,player); assert(#draws==0)
        ''')

    def test_missing_art_reports_once_and_draws_the_rest(self):
        self.lua.execute('''
            Hits.show(player,{'NOART','SEVEN','NOART'}); Hits.onPlayerRender(nil,player); Hits.onPlayerRender(nil,player)
            assert(#errors==1,'missing art reported '..#errors..' times')
            assert(#draws==2 and draws[1].path==art[7])
        ''')

    def test_applied_damage_callback_is_used_when_available(self):
        self.lua.execute('''
            local ids={}; for _,r in ipairs(registered) do ids[r.id]=r end
            assert(ids[1006] and not ids[11],'base pre-damage callback also registered')
            assert(ids[32] and ids[19] and ids[17] and ids[15])
        ''')

    def test_base_damage_callback_is_the_fallback(self):
        self.setUp(applied=False)
        self.lua.execute('''
            local ids={}; for _,r in ipairs(registered) do ids[r.id]=r end
            assert(ids[11] and ids[11].param==EntityType.ENTITY_PLAYER and not ids[1006])
        ''')


if __name__ == '__main__':
    unittest.main()
