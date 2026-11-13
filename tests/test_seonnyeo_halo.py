"""scripts/items/familiars/seonnyeo.lua: the halo Kronos keeps under the
player follows the player in a room whose camera scrolls (user report
2026-11-13: it stood still on screen once the camera moved)."""
import pathlib
import unittest

from lupa.lua53 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parents[1]


class SeonnyeoHaloTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().source = (ROOT / 'scripts/items/familiars/seonnyeo.lua').read_text(encoding='utf-8')
        self.lua.execute(r'''
            local V={}; V.__index=V
            V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
            V.__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
            Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
            Vector.Zero=Vector(0,0)
            ModCallbacks={MC_PRE_PLAYER_RENDER=1}
            RenderMode={RENDER_NORMAL=1,RENDER_WATER_REFLECT=2}
            CollectibleType={COLLECTIBLE_BFFS=247}
            callbacks={}; draws={}; frame=1
            scroll=Vector(0,0)   -- the camera's scroll, part of the render offset
            Isaac={GetItemIdByName=function() return 1020 end,
                WorldToRenderPosition=function(p) return Vector(p.X*0.65,p.Y*0.65) end}
            -- what the engine shows: the render position moved by the scroll
            Isaac.WorldToScreen=function(p) return Isaac.WorldToRenderPosition(p)+scroll end
            function Game() return {GetFrameCount=function() return frame end,
                GetRoom=function() return {GetRenderMode=function() return RenderMode.RENDER_NORMAL end} end} end
            function GetPtrHash(e) return e.hash end
            function Sprite()
                local s={}
                function s:Load() end; function s:SetFrame() end
                function s:RenderLayer(layer,pos) draws[#draws+1]={layer=layer,pos=pos} end
                return s
            end
            ConchBlessing={ItemData={},kronos={_getEffectCount=function() return 2 end}}
            function ConchBlessing:AddCallback(id,fn) callbacks[id]=fn end
            M=load(source,'seonnyeo')()
            player={hash=1,Position=Vector(0,0)}
            function player:HasCollectible() return false end
        ''')

    def test_the_kept_halo_is_drawn_where_the_player_is_shown(self):
        self.lua.execute(r'''
            for _,case in ipairs({{x=200,sx=0},{x=700,sx=-160},{x=1000,sx=-320}}) do
                player.Position=Vector(case.x,280); scroll=Vector(case.sx,0); draws={}; frame=frame+1
                callbacks[ModCallbacks.MC_PRE_PLAYER_RENDER](nil,player,scroll)
                local shown=Isaac.WorldToScreen(player.Position)
                assert(#draws==2,'one halo draw per kept light')
                for _,d in ipairs(draws) do
                    assert(d.layer==1 and math.abs(d.pos.X-shown.X)<1e-9 and math.abs(d.pos.Y-shown.Y)<1e-9,
                        string.format('halo at (%.1f,%.1f), player shown at (%.1f,%.1f), scroll %d',
                            d.pos.X,d.pos.Y,shown.X,shown.Y,case.sx))
                end
            end
        ''')


if __name__ == '__main__':
    unittest.main()
