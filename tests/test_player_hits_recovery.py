"""scripts/lib/player_hits.lua: the green recovery icon (user request
2026-11-13). Floor watches broken by a counted hit play it on the next floor
for whoever still holds them; Time = items call it when their pause ends; the
recovery draws the hit's own animation backwards in green."""
import pathlib
import unittest

from lupa.lua53 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parents[1]


class PlayerHitsRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().source = (ROOT / 'scripts/lib/player_hits.lua').read_text(encoding='utf-8')
        self.lua.execute(r'''
            frame=0; paused=false
            ModCallbacks={MC_POST_ENTITY_TAKE_DMG=1,MC_POST_PLAYER_RENDER=2,MC_POST_NEW_ROOM=3,
                MC_POST_NEW_LEVEL=4,MC_POST_UPDATE=5,MC_PRE_GAME_EXIT=6,MC_POST_GAME_STARTED=7}
            DamageFlag={DAMAGE_NO_PENALTIES=1,DAMAGE_RED_HEARTS=2,DAMAGE_SPIKES=4}
            RoomType={ROOM_SACRIFICE=13}
            callbacks={}
            ConchBlessing={ItemData={
                    TWO_FACED_PENNY={type='passive',id=900},
                    F_MINUS={type='trinket',id=50},
                    TIME_TEAR={type='trinket',id=51},
                },
                printError=function(m) error(m) end}
            function ConchBlessing:AddCallback(id,fn) callbacks[id]=fn end
            players={}
            function GetPtrHash(e) return e.hash end
            function EntityPtr(e) return {Ref=e} end
            Isaac={GetPlayer=function(i) return players[i+1] end}
            function Game() return {GetFrameCount=function() return frame end,
                GetNumPlayers=function() return #players end,IsPaused=function() return paused end,
                GetRoom=function() return {GetRoomType=function() return 1 end} end} end
            function makePlayer(hash)
                local p={hash=hash,items={},trinkets={}}
                function p:ToPlayer() return self end
                function p:Exists() return true end
                function p:HasCollectible(id) return self.items[id]==true end
                function p:GetTrinketMultiplier(id) return self.trinkets[id] and 1 or 0 end
                function p:HasTrinket(id) return self.trinkets[id]==true end
                return p
            end
            Hits=load(source,'player_hits')()
            Hits.watchFloor('TWO_FACED_PENNY'); Hits.watchFloor('F_MINUS')
            hit=function(p,flags) callbacks[ModCallbacks.MC_POST_ENTITY_TAKE_DMG](nil,p,1,flags or 0) end
            newFloor=function()
                callbacks[ModCallbacks.MC_POST_NEW_ROOM](); callbacks[ModCallbacks.MC_POST_NEW_LEVEL]()
                frame=frame+1; callbacks[ModCallbacks.MC_POST_UPDATE]()
            end
            function same(a,b) table.sort(a); table.sort(b); return table.concat(a,',')==table.concat(b,',') end
        ''')

    def test_a_broken_floor_watch_recovers_on_the_next_floor_for_what_is_still_held(self):
        self.lua.execute(r'''
            local a,b=makePlayer(1),makePlayer(2); players={a,b}
            a.items[900]=true; a.trinkets[50]=true; b.trinkets[50]=true
            hit(a)                       -- a breaks both watches
            hit(b,DamageFlag.DAMAGE_RED_HEARTS) -- self-damage breaks nothing
            assert(Hits._test.broken(a).TWO_FACED_PENNY and Hits._test.broken(a).F_MINUS)
            assert(Hits._test.broken(b)==nil,'self-damage broke a watch')
            a.trinkets[50]=nil           -- dropped before the floor ended
            newFloor()
            assert(same(Hits._test.recovering(a),{'TWO_FACED_PENNY'}),'wrong recovery: '..table.concat(Hits._test.recovering(a) or {},','))
            assert(Hits._test.recovering(b)==nil,'a player without a hit recovered')
            frame=frame+30; assert(Hits._test.recovering(a)==nil,'recovery outlived its second')
            newFloor(); assert(Hits._test.recovering(a)==nil,'an unbroken floor recovered again')
        ''')

    def test_a_watch_not_held_when_hit_never_recovers(self):
        self.lua.execute(r'''
            local a=makePlayer(1); players={a}
            hit(a)
            a.items[900]=true
            newFloor()
            assert(Hits._test.recovering(a)==nil,'picked up after the hit, yet recovered')
        ''')

    def test_a_continued_floor_reports_its_break_and_exit_forgets(self):
        self.lua.execute(r'''
            local a=makePlayer(1); players={a}; a.items[900]=true
            Hits.markBroken(a,{'TWO_FACED_PENNY','NOT_WATCHED'})
            assert(Hits._test.broken(a).TWO_FACED_PENNY and not Hits._test.broken(a).NOT_WATCHED)
            callbacks[ModCallbacks.MC_POST_GAME_STARTED]()
            assert(Hits._test.broken(a).TWO_FACED_PENNY,'game start dropped the continued record')
            callbacks[ModCallbacks.MC_PRE_GAME_EXIT]()
            assert(Hits._test.broken(a)==nil,'exit kept the record')
        ''')

    def test_time_items_recover_on_demand_and_waits_while_paused(self):
        self.lua.execute(r'''
            local a=makePlayer(1); players={a}; a.trinkets[50]=true
            hit(a); paused=true
            callbacks[ModCallbacks.MC_POST_NEW_ROOM](); callbacks[ModCallbacks.MC_POST_NEW_LEVEL]()
            callbacks[ModCallbacks.MC_POST_UPDATE]()
            assert(Hits._test.recovering(a)==nil,'shown while paused')
            paused=false; callbacks[ModCallbacks.MC_POST_UPDATE]()
            assert(same(Hits._test.recovering(a),{'F_MINUS'}))
            Hits.recover(a,{'TIME_TEAR'})
            assert(same(Hits._test.recovering(a),{'F_MINUS','TIME_TEAR'}),'recoveries in one update share a row')
            frame=frame+1; Hits.recover(a,{'TIME_TEAR'})
            assert(same(Hits._test.recovering(a),{'TIME_TEAR'}),'a later recovery did not start its own row')
        ''')

    def test_the_recovery_draws_the_hit_backwards_in_green(self):
        self.lua.execute(r'''
            Vector=setmetatable({}, {__call=function(_,x,y) return {X=x,Y=y} end})
            Color=function(r,g,b,a,ro,go,bo) return {R=r,G=g,B=b,A=a,RO=ro,GO=go,BO=bo} end
            function Sprite()
                local s={}
                function s:Load() end; function s:ReplaceSpritesheet() end; function s:LoadGraphics() end
                function s:SetFrame() end; function s:IsLoaded() return true end
                function s:RenderLayer(_,pos) draws[#draws+1]={y=pos.Y,scale=self.Scale.X,color=self.Color} end
                return s
            end
            Isaac.GetItemConfig=function() return {GetCollectible=function() return {GfxFileName='x.png'} end,
                GetTrinket=function() return {GfxFileName='x.png'} end} end
            Isaac.WorldToScreen=function(v) return v end
            local a=makePlayer(1); players={a}
            a.Position=Vector(0,100); a.PositionOffset=Vector(0,0); a.SpriteScale=Vector(1,1)
            a.Position.__add=nil
            setmetatable(a.Position,{__add=function(p,q) return Vector(p.X+q.X,p.Y+q.Y) end})
            local hitRows, backRows = {}, {}
            frame=100; Hits.show(a,{'F_MINUS'})
            for age=0,29 do
                draws={}; frame=100+age
                callbacks[ModCallbacks.MC_POST_PLAYER_RENDER](nil,a); hitRows[age]=draws[1]
            end
            Hits.clearEffects()
            frame=200; Hits.recover(a,{'F_MINUS'})
            for age=0,29 do
                draws={}; frame=200+age
                callbacks[ModCallbacks.MC_POST_PLAYER_RENDER](nil,a); backRows[age]=draws[1]
            end
            for age=0,29 do
                local h,b=hitRows[age],backRows[29-age]
                assert(math.abs(h.y-b.y)<1e-9 and math.abs(h.scale-b.scale)<1e-9 and math.abs(h.color.A-b.color.A)<1e-9,
                    'not the same frame backwards at '..age)
                assert(b.color.G==1 and b.color.GO>0 and b.color.R<1,'recovery not green at '..age)
                assert(h.color.R==1 and h.color.GO==0,'hit turned green at '..age)
            end
            assert(backRows[0].y<backRows[29].y,'the recovery does not come down')
        ''')


if __name__ == '__main__':
    unittest.main()
