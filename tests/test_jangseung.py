"""장승 (Jangseung): production Lua with engine doubles.

The pure rules run here: which doors get a pair (every door into a room that is
not ordinary, plus the Red Key's wall toward the ultra secret room), where the
pair stands at each wall (천하대장군 left or above, just outside the frame), which
frame and flips draw it against each wall as the room's camera sees it, what lies
inside the village's half circle, and the floor graph's red route. The statues in a real
room, the earth and the guard on real enemies need the engine:
`conch_test jangseung` covers those in game.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
RoomShape={ROOMSHAPE_1x1=1,ROOMSHAPE_IH=2,ROOMSHAPE_IV=3,ROOMSHAPE_1x2=4,ROOMSHAPE_IIV=5,ROOMSHAPE_2x1=6,
    ROOMSHAPE_IIH=7,ROOMSHAPE_2x2=8,ROOMSHAPE_LTL=9,ROOMSHAPE_LTR=10,ROOMSHAPE_LBL=11,ROOMSHAPE_LBR=12}
TrinketType={TRINKET_DOOR_STOP=124}
RoomType={ROOM_DEFAULT=1,ROOM_SHOP=2,ROOM_TREASURE=4,ROOM_BOSS=5,ROOM_SECRET=7,ROOM_SUPERSECRET=8,ROOM_ULTRASECRET=29}
errors={}
Isaac={GetItemIdByName=function(name) return name=='Jangseung' and 961 or -1 end,
    GetEntityTypeByName=function() return 1000 end,
    GetEntityVariantByName=function(name) return ({['Conch Blessing Jangseung']=7786,
        ['Conch Blessing Jangseung Ground']=7787})[name] or -1 end}
ConchBlessing={printError=function(e) errors[#errors+1]=e end,printDebug=function() end}
local loaded={}
require=function(name)
    if loaded[name]==nil then loaded[name]=dofile(root..'/'..name:gsub('%.','/')..'.lua') end
    return loaded[name]
end
M=dofile(root..'/scripts/items/collectibles/jangseung.lua')
T=M._test
LR=require('scripts.lib.level_rooms')

function level(rooms)
    for idx,r in pairs(rooms) do
        r.SafeGridIndex=idx; r.GridIndex=idx; r.ListIndex=idx
        r.Data={Shape=RoomShape.ROOMSHAPE_1x1,Doors=r.doors or 15,Type=r.type or RoomType.ROOM_DEFAULT}
    end
    return {GetRoomByIdx=function(_,i) return rooms[i] end,
        GetRooms=function()
            local list={}
            for _,r in pairs(rooms) do list[#list+1]=r end
            return {Size=#list,Get=function(_,i) return list[i+1] end}
        end}
end
"""


class JangseungTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = str(ROOT).replace('\\', '/')
        self.lua.execute(HARNESS)

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_effects_resolve_and_nothing_is_reported(self):
        self.run_lua("""
            assert(T.statueVariant()==7786 and T.groundVariant()==7787)
            assert(#errors==0, errors[1])
        """)

    def test_every_door_into_a_room_that_is_not_ordinary_gets_a_pair(self):
        self.run_lua("""
            local D=RoomType.ROOM_DEFAULT
            local list=T.chooseMarkers({[0]=D,[1]=RoomType.ROOM_TREASURE,[3]=RoomType.ROOM_SECRET},D,nil)
            assert(#list==2 and list[1].slot==1 and list[2].slot==3 and not list[1].red)
            list=T.chooseMarkers({[0]=D},D,2)
            assert(#list==1 and list[1].slot==2 and list[1].red,'the red route wall gets a red pair')
            list=T.chooseMarkers({[2]=RoomType.ROOM_SHOP},D,2)
            assert(#list==1 and not list[1].red,'no red pair where a door already stands')
        """)

    def test_door_stop_adds_a_pair_at_the_door_come_in_by(self):
        self.run_lua("""
            local D=RoomType.ROOM_DEFAULT
            local list=T.chooseMarkers({[0]=D,[1]=RoomType.ROOM_TREASURE},D,nil,0)
            assert(#list==2 and list[2].slot==0 and list[2].entry and not list[2].red,'the ordinary door come in by gets a pair')
            list=T.chooseMarkers({[0]=D,[1]=RoomType.ROOM_TREASURE},D,nil,1)
            assert(#list==1 and list[1].slot==1 and not list[1].entry,'a special door come in by keeps its one pair')
            list=T.chooseMarkers({[0]=D},D,nil,nil)
            assert(#list==0,'without Door Stop the door come in by stays bare')
            list=T.chooseMarkers({[0]=D},D,nil,3)
            assert(#list==0,'no pair at a slot with no door')
        """)

    def test_the_pair_flanks_each_wall_with_cheonha_left_or_above(self):
        self.run_lua("""
            local d=M.data
            -- every wall the same: just outside the frame, the foot on the floor
            local ax,ay,bx,by=T.pairPlaces(320,120,0,1)
            assert(ax==320-d.spread and bx==320+d.spread and ay==120+d.stand and by==ay,'top: left first')
            ax,ay,bx,by=T.pairPlaces(320,440,0,-1)
            assert(ax==320-d.spread and ay==440-d.stand and by==ay,'bottom: left first')
            ax,ay,bx,by=T.pairPlaces(40,280,1,0)
            assert(ax==40+d.stand and bx==ax and ay==280-d.spread and by==280+d.spread,'left: the upper one first')
            ax,ay,bx,by=T.pairPlaces(600,280,-1,0)
            assert(ax==600-d.stand and ay==280-d.spread and by==280+d.spread,'right: the upper one first')
        """)

    def test_each_wall_draws_the_pair_as_the_room_camera_sees_it(self):
        self.run_lua("""
            local function frame(ix,iy)
                local view,fx,fy=T.frameOf(ix,iy)
                return view..(fx and 'X' or '')..(fy and 'Y' or '')
            end
            assert(frame(0,1)=='Top','top wall: as drawn, the cap toward the wall')
            assert(frame(0,-1)=='TopY','bottom wall: the same picture upside down')
            assert(frame(-1,0)=='Side','right wall: on its side, the cap to the right')
            assert(frame(1,0)=='SideX','left wall: the side picture mirrored')
        """)
        anm2 = (ROOT / 'resources/gfx/effects/conch_jangseung.anm2').read_text(encoding='utf-8')
        for who in ('Cheonha', 'Jiha'):
            for view in ('Top', 'Side'):
                for red in ('', 'Red'):
                    self.assertIn(f'Animation Name="{who}{view}{red}"', anm2)
        self.assertNotIn('Animation Name="Cheonha"', anm2)
        self.assertNotIn('Back', anm2)

    def test_the_april_fools_set_is_a_drop_in_for_the_shipped_frames(self):
        # the raw 3D render kept for April Fools (user request 2026-11-10):
        # the same animations, so swapping the sheet needs no code change
        import re
        shipped = (ROOT / 'resources/gfx/effects/conch_jangseung.anm2').read_text(encoding='utf-8')
        april = ROOT / 'resources/gfx/effects/notused/conch_jangseung_aprilfools.anm2'
        kept = april.read_text(encoding='utf-8')
        names = lambda text: re.findall(r'Animation Name="(\w+)"', text)
        self.assertEqual(names(kept), names(shipped))
        sheet = re.search(r'Spritesheet Id="0" Path="([^"]+)"', kept).group(1)
        self.assertTrue((april.parent / sheet).exists(), sheet)

    def test_the_village_is_the_half_circle_in_front_of_the_door(self):
        self.run_lua("""
            local r=M.data.radius
            assert(r==80,'two tiles')
            assert(T.inside(0,40,0,1,r),'in front of a top door')
            assert(not T.inside(0,90,0,1,r),'beyond two tiles')
            assert(not T.inside(0,-30,0,1,r),'behind the wall')
            assert(T.inside(60,10,0,1,r),'to the side but inside the half circle')
            assert(T.inside(40,0,1,0,r) and not T.inside(-30,0,1,0,r),'a left door faces right')
            local x,y=T.inwardOf(0); assert(x==1 and y==0)
            x,y=T.inwardOf(5); assert(x==0 and y==1)
            x,y=T.inwardOf(6); assert(x==-1 and y==0)
            x,y=T.inwardOf(7); assert(x==0 and y==-1)
        """)

    def test_the_red_route_digs_where_one_red_room_reaches_the_ultra_secret_room(self):
        self.run_lua("""
            -- 40 and 41 are rooms; 43 is the ultra secret room, two cells right of 41
            local L=level({[40]={doors=15},[41]={doors=15},[43]={type=RoomType.ROOM_ULTRASECRET,doors=0}})
            local nextRoom,slot,digs=LR.redStep(L,41,43,nil)
            assert(nextRoom==42 and slot==2,'dig right from 41 into the empty cell beside the ultra room')
            nextRoom,slot=LR.redStep(L,40,43,nil)
            assert(nextRoom==41 and slot==nil,'from 40 walk to 41 first')
            assert(LR.redStep(L,43,43,nil)==false,'already there')
        """)


if __name__ == '__main__':
    unittest.main()
