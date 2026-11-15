"""장승 (Jangseung): production Lua with engine doubles.

The pure rules run here: which doors get a pair (every door into a room that is
not ordinary, plus the Red Key's wall toward the ultra secret room), where the
pair stands at each wall (천하대장군 left or above, just outside the frame), which
frame and flips draw it against each wall as the room's camera sees it, what lies
inside the village's half circle, the floor graph's red route, the 금줄's tag
(each kind of room's minimap icon, red for a Red Key's way) and how a room's
pairs follow its doors changing mid-visit (room doubles). The statues in a real
room, the earth and the guard on real enemies need the engine:
`cb test jangseung` covers those in game.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
local VM={}
VM.__index=VM
VM.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
VM.__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
VM.__mul=function(a,k) return Vector(a.X*k,a.Y*k) end
function VM:Length() return math.sqrt(self.X*self.X+self.Y*self.Y) end
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},VM) end})
Vector.Zero=Vector(0,0)
EntityType={ENTITY_EFFECT=1000}
EntityFlag={FLAG_RENDER_FLOOR=1}
spawned={}
function EntityPtr(e) return {Ref=e} end
RoomShape={ROOMSHAPE_1x1=1,ROOMSHAPE_IH=2,ROOMSHAPE_IV=3,ROOMSHAPE_1x2=4,ROOMSHAPE_IIV=5,ROOMSHAPE_2x1=6,
    ROOMSHAPE_IIH=7,ROOMSHAPE_2x2=8,ROOMSHAPE_LTL=9,ROOMSHAPE_LTR=10,ROOMSHAPE_LBL=11,ROOMSHAPE_LBR=12}
TrinketType={TRINKET_DOOR_STOP=124}
ModCallbacks={}
DamageFlag={DAMAGE_SPIKES=16,DAMAGE_RED_HEARTS=32,DAMAGE_IV_BAG=2048,DAMAGE_CURSED_DOOR=131072,DAMAGE_FAKE=2097152,
    DAMAGE_DEVIL=8388608,DAMAGE_NO_PENALTIES=268435456}
SoundEffect={SOUND_PAPER_OUT=18}
played=0
SFXManager=function() return {Play=function() played=played+1 end} end
frame=0
players={}
curLevel,curRoom=nil,nil
Game=function() return {GetNumPlayers=function() return #players end,GetFrameCount=function() return frame end,
    GetLevel=function() return curLevel end,GetRoom=function() return curRoom end} end
GetPtrHash=function(e) return e.hash end
function Vec(x,y) return {X=x,Y=y} end
function newPlayer(hash,x,y,held)
    local p={hash=hash,Position=Vec(x,y),held=held}
    p.ToPlayer=function(self) return self end
    p.HasCollectible=function(self,id) return self.held and id==961 end
    p.Exists=function() return true end
    p.IsDead=function() return false end
    p.HasTrinket=function() return false end
    return p
end
RoomType={ROOM_DEFAULT=1,ROOM_SHOP=2,ROOM_ERROR=3,ROOM_TREASURE=4,ROOM_BOSS=5,ROOM_MINIBOSS=6,ROOM_SECRET=7,
    ROOM_SUPERSECRET=8,ROOM_ARCADE=9,ROOM_CURSE=10,ROOM_CHALLENGE=11,ROOM_LIBRARY=12,ROOM_SACRIFICE=13,ROOM_DEVIL=14,
    ROOM_ANGEL=15,ROOM_DUNGEON=16,ROOM_BOSSRUSH=17,ROOM_ISAACS=18,ROOM_BARREN=19,ROOM_CHEST=20,ROOM_DICE=21,
    ROOM_BLACK_MARKET=22,ROOM_GREED_EXIT=23,ROOM_PLANETARIUM=24,ROOM_TELEPORTER=25,ROOM_TELEPORTER_EXIT=26,
    ROOM_SECRET_EXIT=27,ROOM_BLUE=28,ROOM_ULTRASECRET=29}
errors={}
Isaac={GetPlayer=function(i) return players[i+1] end,
    GetItemIdByName=function(name) return name=='Jangseung' and 961 or -1 end,
    GetEntityTypeByName=function() return 1000 end,
    GetEntityVariantByName=function(name) return ({['Conch Blessing Jangseung']=7786,
        ['Conch Blessing Jangseung Ground']=7787,['Conch Blessing Jangseung Rope']=7791})[name] or -1 end,
    GetRoomEntities=function() return {} end,
    Spawn=function(kind,variant,subtype,position,velocity,spawner)
        local e={Type=kind,Variant=variant,SubType=subtype,Position=position,DepthOffset=0,alive=true,flags=0}
        e.sprite={}
        function e.sprite:Play(name) self.anim=name end
        function e:ToEffect() return self end
        function e:GetSprite() return self.sprite end
        function e:Exists() return self.alive end
        function e:Remove() self.alive=false end
        function e:AddEntityFlags(f) self.flags=self.flags|f end
        spawned[#spawned+1]=e
        return e
    end}
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
        r.Data={Shape=RoomShape.ROOMSHAPE_1x1,Doors=r.doors or 15,Type=r.type or RoomType.ROOM_DEFAULT,
            Subtype=r.subtype or 0}
        r.Flags=r.flags or 0
    end
    return {GetRoomByIdx=function(_,i) return rooms[i] end,
        GetCurrentRoomDesc=function(self) return rooms[self.current] end,
        GetRooms=function()
            local list={}
            for _,r in pairs(rooms) do list[#list+1]=r end
            return {Size=#list,Get=function(_,i) return list[i+1] end}
        end}
end

-- A 1x1 room whose doors lead to `targets[slot]` (a level index), at the
-- engine's door slot positions.
SLOTS={[0]=Vector(40,280),[1]=Vector(320,120),[2]=Vector(600,280),[3]=Vector(320,440)}
function room(lvl,targets)
    local r={targets=targets}
    function r:GetDoor(slot)
        local index=self.targets[slot]
        if index==nil then return nil end
        local target=lvl:GetRoomByIdx(index)
        return {TargetRoomIndex=index,TargetRoomType=target.Data.Type}
    end
    function r:GetDoorSlotPosition(slot) return SLOTS[slot] end
    return r
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
            assert(#list==2 and list[1].slot==1 and list[2].slot==3 and not list[1].route)
            list=T.chooseMarkers({[0]=D},D,2)
            assert(#list==1 and list[1].slot==2 and list[1].route,'the red route wall gets a pair')
            list=T.chooseMarkers({[2]=RoomType.ROOM_SHOP},D,2)
            assert(#list==1 and not list[1].route,'no route pair where a door already stands')
        """)

    def test_door_stop_adds_a_pair_at_the_door_come_in_by(self):
        self.run_lua("""
            local D=RoomType.ROOM_DEFAULT
            local list=T.chooseMarkers({[0]=D,[1]=RoomType.ROOM_TREASURE},D,nil,0)
            assert(#list==2 and list[2].slot==0 and list[2].entry and not list[2].route,'the ordinary door come in by gets a pair')
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
                self.assertIn(f'Animation Name="{who}{view}"', anm2)
        self.assertNotIn('Animation Name="Cheonha"', anm2)
        self.assertNotIn('Back', anm2)
        # the red cloth went on 2026-11-15: the 금줄 between the pair marks the way now
        self.assertNotIn('Red"', anm2)

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

    def test_each_kind_of_room_hangs_its_own_minimap_icon_on_the_rope(self):
        # user request 2026-11-15: a treasure room's 금줄 carries the treasure
        # room's crown, and every other special room its own icon
        self.run_lua("""
            local R=RoomType
            local function tag(kind,flags,subtype)
                local icon,red=T.tagFor(kind,flags,subtype)
                return tostring(icon)..(red and '/red' or '')
            end
            assert(tag(R.ROOM_TREASURE)=='IconTreasureRoom')
            assert(tag(R.ROOM_TREASURE,1<<11)=='IconTreasureRoomRed','Devil Crown treasure room, as the minimap shows it')
            assert(tag(R.ROOM_TREASURE,1<<10)=='IconTreasureRoom/red','a red treasure room: the same icon on a red rope')
            assert(tag(R.ROOM_SHOP,1<<10)=='IconShop/red')
            assert(tag(R.ROOM_ULTRASECRET)=='IconUltraSecretRoom/red','the ultra secret room is a Red Key way')
            assert(tag(R.ROOM_CHALLENGE,0,0)=='IconAmbushRoom' and tag(R.ROOM_CHALLENGE,0,1)=='IconBossAmbushRoom')
            for name,icon in pairs({ROOM_SHOP='IconShop',ROOM_BOSS='IconBoss',ROOM_MINIBOSS='IconMiniboss',
                    ROOM_SECRET='IconSecretRoom',ROOM_SUPERSECRET='IconSuperSecretRoom',ROOM_ARCADE='IconArcade',
                    ROOM_CURSE='IconCurseRoom',ROOM_LIBRARY='IconLibrary',ROOM_SACRIFICE='IconSacrificeRoom',
                    ROOM_DEVIL='IconDevilRoom',ROOM_ANGEL='IconAngelRoom',ROOM_DUNGEON='IconLadder',
                    ROOM_BOSSRUSH='IconBossAmbushRoom',ROOM_ISAACS='IconIsaacsRoom',ROOM_BARREN='IconBarrenRoom',
                    ROOM_CHEST='IconChestRoom',ROOM_DICE='IconDiceRoom',ROOM_PLANETARIUM='IconPlanetarium',
                    ROOM_TELEPORTER='IconTeleporterRoom',ROOM_TELEPORTER_EXIT='IconTeleporterRoom',
                    ROOM_SECRET_EXIT='IconLadder'}) do
                assert(tag(R[name])==icon,name..' -> '..tag(R[name]))
            end
            assert(tag(R.ROOM_ERROR)=='nil' and tag(R.ROOM_DEFAULT,1<<10)=='nil/red','no icon fits: no rope')
            -- the rope's SubType carries the icon and the colour, both ways
            for _,icon in ipairs(T.iconList()) do
                for _,red in ipairs({false,true}) do
                    local back,isRed=T.ropeIcon(T.ropeSubtype(icon,red))
                    assert(back==icon and isRed==red,icon)
                end
            end
            local blank,red=T.ropeIcon(T.ropeSubtype(nil,true))
            assert(blank==nil and red)
        """)
        names = self.lua.eval('T.iconList()')
        anm2 = ROOT.parents[1] / 'extracted_resources/resources/gfx/ui/minimap_icons.anm2'
        if not anm2.exists():
            self.skipTest('extracted resources are not here')
        vanilla = anm2.read_text(encoding='utf-8')
        for i in range(1, len(names) + 1):
            self.assertIn(f'Animation Name="{names[i]}"', vanilla, 'every hung icon is a vanilla minimap animation')

    def test_each_icon_hangs_by_its_measured_edge(self):
        # user request 2026-11-16: no paper behind the icon, the icon itself
        # hangs from the rope; a running game cannot read pixels, so each icon's
        # box is measured offline and must match the vanilla sheet
        import re
        from PIL import Image
        names = self.lua.eval('T.iconList()')
        boxes = self.lua.eval('T.iconBox')
        for i in range(1, len(names) + 1):
            self.assertIsNotNone(boxes[names[i]], names[i])
        vanilla = ROOT.parents[1] / 'extracted_resources/resources/gfx/ui'
        if not (vanilla / 'minimap_icons.anm2').exists():
            self.skipTest('extracted resources are not here')
        anm2 = (vanilla / 'minimap_icons.anm2').read_text(encoding='utf-8')
        sheet = Image.open(vanilla / 'minimap_icons.png').convert('RGBA')
        for i in range(1, len(names) + 1):
            name = names[i]
            m = re.search(r'Animation Name="%s".*?XPivot="0" YPivot="0" XCrop="(\d+)" YCrop="(\d+)" Width="16" '
                          r'Height="16"' % name, anm2, re.S)
            self.assertIsNotNone(m, name)
            x, y = int(m.group(1)), int(m.group(2))
            box = boxes[name]
            self.assertEqual(sheet.crop((x, y, x + 16, y + 16)).getbbox(), (box[1], box[2], box[3], box[4]), name)

    def test_the_icons_come_from_minimapi_while_it_is_loaded(self):
        # MiniMAPI blanks the vanilla minimap_icons.anm2 (its animations have no
        # frames), so the icon never showed in game until it was drawn from
        # MiniMAPI's own icon file (2026-11-16)
        self.run_lua("""
            MinimapAPI=nil
            assert(T.iconFile()=='gfx/ui/minimap_icons.anm2','vanilla without MiniMAPI')
            MinimapAPI={}
            assert(T.iconFile()=='gfx/ui/minimapapi_icons.anm2','the MiniMAPI icons with it')
            MinimapAPI=nil
        """)
        import re
        from PIL import Image
        mods = ROOT.parent
        found = [d for d in mods.iterdir() if (d / 'resources/gfx/ui/minimapapi_icons.anm2').exists()] if mods.exists() else []
        if not found:
            self.skipTest('MiniMAPI is not installed here')
        ui = found[0] / 'resources/gfx/ui'
        anm2 = (ui / 'minimapapi_icons.anm2').read_text(encoding='utf-8')
        sheet_path = re.search(r'Spritesheet Path="([^"]+)"', anm2).group(1)
        sheet = Image.open(ui / sheet_path).convert('RGBA')
        names, boxes = self.lua.eval('T.iconList()'), self.lua.eval('T.iconBox')
        for i in range(1, len(names) + 1):
            name = names[i]
            m = re.search(r'Animation Name="%s".*?XPivot="0" YPivot="0" XCrop="(\d+)" YCrop="(\d+)" Width="16" '
                          r'Height="16"' % name, anm2, re.S)
            self.assertIsNotNone(m, name + ' in the MiniMAPI icons')
            x, y = int(m.group(1)), int(m.group(2))
            box = boxes[name]
            self.assertEqual(sheet.crop((x, y, x + 16, y + 16)).getbbox(), (box[1], box[2], box[3], box[4]), name)

    def test_the_game_draws_the_icon_with_its_straw_rim_where_the_rope_hangs_it(self):
        self.run_lua("""
            renders={}
            Color=function(...) return {...} end
            Sprite=function()
                local s={}
                function s:Load() end
                function s:IsLoaded() return true end
                function s:SetFrame(name) self.frame=name end
                function s:Render(p)
                    renders[#renders+1]={frame=self.frame,x=p.X,y=p.Y,color=self.Color,rotation=self.Rotation}
                end
                return s
            end
            Isaac.WorldToScreen=function(p) return Vector(p.X,p.Y) end
            curRoom=room(level({}),{})
            local function rope(anim,fx,fy,icon)
                local e={Variant=T.ropeVariant(),SubType=T.ropeSubtype(icon,false),Position=Vector(100,50)}
                local s={FlipX=fx,FlipY=fy}
                function s:GetAnimation() return anim end
                function e:GetSprite() return s end
                return e
            end
            local function draw(anim,fx,fy,icon)
                renders={}
                T.drawHung(rope(anim,fx,fy,icon))
                return renders
            end
            -- the shop icon's box is {3,2,10,10}: it hangs by its top edge's
            -- middle pixel (6,2), turned with its wall so that pixel lands on
            -- the hook's pixel (user request 2026-11-16: upright on the top wall)
            for _,case in ipairs({{'RopeTop',false,false,0,94,48},{'RopeTopRed',false,true,180,107,52},
                    {'RopeSide',false,false,90,102,44},{'RopeSideRed',true,false,-90,98,57}}) do
                local r=draw(case[1],case[2],case[3],'IconShop')
                assert(#r==5,case[1]..': four rims and the icon, '..#r)
                local icon=r[5]
                assert(icon.frame=='IconShop' and icon.rotation==case[4] and icon.x==case[5] and icon.y==case[6],
                    case[1]..' at '..icon.x..','..icon.y..' turned '..tostring(icon.rotation))
                assert(icon.color[1]==1 and icon.color[5]==0,'the icon in its own colours')
                local seen={}
                for i=1,4 do
                    assert(r[i].color[1]==0 and math.abs(r[i].color[5]-M.data.rimR/255)<1e-9,'a straw silhouette')
                    seen[(r[i].x-icon.x)..','..(r[i].y-icon.y)]=true
                end
                assert(seen['1,0'] and seen['-1,0'] and seen['0,1'] and seen['0,-1'],'one pixel out each way')
            end
            assert(#draw('RopeTop',false,false,nil)==0,'nothing to draw without an icon')
            -- the room pass draws every live rope's icon (after the room's
            -- entities: from the rope's own render callback it never showed)
            local R=RoomType
            curLevel=level({[40]={},[41]={type=R.ROOM_TREASURE},[39]={type=R.ROOM_SHOP}})
            curLevel.current=40
            curRoom=room(curLevel,{[1]=41,[3]=39})
            players={newPlayer(1,320,280,true)}
            M.onGameStarted()
            M.onNewRoom()
            for _,e in ipairs(T.ropes()) do
                local anim=e.sprite.anim
                function e.sprite:GetAnimation() return anim end
                e.sprite.FlipX=e.sprite.FlipX or false
                e.sprite.FlipY=e.sprite.FlipY or false
            end
            renders={}
            M.onRoomRender()
            assert(#renders==10,'two ropes, each an icon and its rim: '..#renders)
            local seen={}
            for _,r in ipairs(renders) do seen[r.frame]=true end
            assert(seen.IconTreasureRoom and seen.IconShop)
            M.onGameExit()
            renders={}
            M.onRoomRender()
            assert(#renders==0,'nothing once the room is gone')
            assert(#errors==0,tostring(errors[1]))
        """)

    def test_the_icon_hangs_on_the_end_of_the_string_on_every_wall(self):
        # the rope frame flipped about its pivot as the game flips it, the icon
        # turned with its wall and placed by iconPose: its top edge's middle
        # pixel sits on the hook's pixel, right after the string's last pixel,
        # the rest of it hangs away from the rope, and its top faces the rope
        # on every wall (user request 2026-11-16)
        import importlib.util
        from PIL import Image
        spec = importlib.util.spec_from_file_location('jangseung_author', ROOT / 'docs/previews/jangseung/author.py')
        author = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(author)
        frames = dict(zip(author.ROPE_NAMES, author.ropes()[0]))
        boxes = author.icon_boxes()
        names = self.lua.eval('T.iconList()')
        pose = self.lua.eval('function(n, side, flip) return {T.iconPose(n, side, flip)} end')
        straw = {author.ROPE[k] + (255,) for k in ('l', 'm')}
        # per wall: the hook's pixel, the string's last pixel (one toward the
        # rope) and the direction from the rope into the room, all on screen
        walls = {('Top', False): ((0, 0), (0, -1), (0, 1)), ('Top', True): ((0, -1), (0, 0), (0, -1)),
                 ('Side', False): ((-1, 0), (0, 0), (-1, 0)), ('Side', True): ((0, 0), (-1, 0), (1, 0))}
        for i in range(1, len(names) + 1):
            name = names[i]
            x0, y0, x1, y1 = boxes[name]
            solid = Image.new('RGBA', (16, 16))
            for y in range(y0, y1):
                for x in range(x0, x1):
                    solid.putpixel((x, y), (255, 255, 255, 255))
            top = (x0 + (x1 - x0 - 1) // 2, y0)
            for (view, flip), (hook, end, down) in walls.items():
                lua = pose(name, view == 'Side', flip)
                self.assertEqual((lua[1], lua[2], lua[3]), author.icon_pose(boxes[name], view, flip), (name, view, flip))
                # mark the top edge's middle pixel and follow it through the turn
                marked = solid.copy()
                marked.putpixel(top, (255, 0, 0, 255))
                pixels = author.icon_pixels(marked, boxes[name], view, flip)
                self.assertEqual(pixels.get(hook), (255, 0, 0, 255), (name, view, flip, 'the top middle on the hook'))
                self.assertNotIn(end, pixels, (name, view, flip))
                reach = [x * down[0] + y * down[1] for x, y in pixels]
                self.assertEqual(min(reach), hook[0] * down[0] + hook[1] * down[1], (name, view, flip, 'it hangs away'))
                frame, (px, py) = frames['Rope' + view]
                if flip:  # the game mirrors about the pivot
                    if view == 'Top':
                        frame, py = frame.transpose(Image.FLIP_TOP_BOTTOM), frame.height - py
                    else:
                        frame, px = frame.transpose(Image.FLIP_LEFT_RIGHT), frame.width - px
                self.assertIn(frame.getpixel((px + end[0], py + end[1])), straw, (name, view, flip, 'the string ends there'))

    def test_the_pairs_follow_the_doors_changing_while_the_player_is_in_the_room(self):
        # a Red Key opening a red treasure room: its pair and red rope stand at
        # once, the treasure room's pair stays as it was, and a door that goes
        # takes its pair with it
        self.run_lua("""
            local R=RoomType
            curLevel=level({[40]={},[41]={type=R.ROOM_TREASURE},[27]={type=R.ROOM_TREASURE,flags=1<<10},
                [39]={},[26]={type=R.ROOM_ERROR}})
            curLevel.current=40
            curRoom=room(curLevel,{[2]=41,[0]=39})
            players={newPlayer(1,320,280,true)}
            M.onGameStarted()
            T.resetEvidence()
            M.onNewRoom()
            local markers=M.markers()
            assert(#markers==1 and markers[1].slot==2 and markers[1].icon=='IconTreasureRoom' and not markers[1].red)
            local ropes=T.ropes()
            assert(#ropes==1 and ropes[1].sprite.anim=='RopeSide' and not ropes[1].sprite.FlipX,'the right wall: the side frame')
            assert(ropes[1].SubType==T.ropeSubtype('IconTreasureRoom',false) and ropes[1].DepthOffset==M.data.ropeDepth)
            assert(ropes[1].Position.X==600-M.data.hangSide and ropes[1].Position.Y==280,'the hook hangs hangSide in from the wall')
            local kept=markers[1]
            local first=#spawned
            M.onUpdate()
            assert(#spawned==first and T.evidence().resurveys==0,'nothing changes while the doors do not')
            curRoom.targets[1]=27
            M.onUpdate()
            markers=M.markers()
            assert(#markers==2 and T.evidence().resurveys==1)
            local red
            for _,m in ipairs(markers) do if m.slot==1 then red=m end end
            assert(red and red.red and red.icon=='IconTreasureRoom','the red treasure room gets a red rope at once')
            assert(markers[1]==kept or markers[2]==kept,'the treasure room keeps its pair')
            assert(#spawned==first+4,'only the new pair, its rope and its earth were added: '..(#spawned-first))
            ropes=T.ropes()
            local top
            for _,r in ipairs(ropes) do if r.sprite.anim=='RopeTopRed' then top=r end end
            assert(top and top.Position.Y==120+M.data.hangTop and top.SubType==T.ropeSubtype('IconTreasureRoom',true))
            curRoom.targets[1]=nil
            M.onUpdate()
            assert(#M.markers()==1 and M.markers()[1]==kept)
            local gone=0
            for i=first+1,#spawned do if not spawned[i]:Exists() then gone=gone+1 end end
            assert(gone==3,'the gone door took its pair and rope: '..gone)
            local ropesBefore=#T.ropes()
            curRoom.targets[1]=26
            M.onUpdate()
            local errorRoom
            for _,m in ipairs(M.markers()) do if m.slot==1 then errorRoom=m end end
            assert(errorRoom and errorRoom.icon==nil,'I AM ERROR still gets its pair')
            assert(#T.ropes()==ropesBefore,'a room no icon fits gets no rope (user request 2026-11-16)')
            M.onGameExit()
        """)

    def test_the_rope_art_matches_the_lua_and_ends_its_string_at_the_pivot(self):
        # docs/previews/jangseung/author.py draws the 금줄 from jangseung.lua's
        # numbers; the shipped sheet must be what it draws now
        import importlib.util
        import re
        from PIL import Image
        spec = importlib.util.spec_from_file_location('jangseung_author', ROOT / 'docs/previews/jangseung/author.py')
        author = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(author)
        frames, sheet = author.ropes()
        shipped = Image.open(ROOT / 'resources/gfx/effects/conch_jangseung_rope.png').convert('RGBA')
        self.assertEqual(shipped.size, sheet.size)
        self.assertTrue(shipped.tobytes() == sheet.tobytes(), 'rerun docs/previews/jangseung/author.py')
        anm2 = (ROOT / 'resources/gfx/effects/conch_jangseung_rope.anm2').read_text(encoding='utf-8')
        self.assertEqual(anm2, author.rope_anm2(frames))
        self.assertEqual(re.findall(r'Animation Name="(\w+)"', anm2), ['RopeTop', 'RopeSide', 'RopeTopRed', 'RopeSideRed'])
        straw = {author.ROPE[k] + (255,) for k in ('l', 'm')}
        n = author.STRING
        for name, (frame, (px, py)) in zip(author.ROPE_NAMES, frames):
            view, red = author.rope_parts(name)
            # the string runs from the rope's outline to the pivot, and nothing of
            # the frame lies on the icon's side of it (no tag, user 2026-11-16)
            if view == 'Top':
                string = [(px, py - 1 - k) for k in range(n)]
                outline, past = (px, py - 1 - n), [(px + dx, py + dy) for dx in range(-3, 4) for dy in range(0, 4)]
            else:
                string = [(px + k, py) for k in range(n)]
                outline, past = (px + n, py), [(px - 1 - dx, py + dy) for dx in range(0, 4) for dy in range(-3, 4)]
            for at in string:
                self.assertIn(frame.getpixel(at), straw, (name, at))
            self.assertEqual(frame.getpixel(outline), (author.ROPE_RED if red else author.ROPE)['K'] + (255,), name)
            for at in past:
                inside = 0 <= at[0] < frame.width and 0 <= at[1] < frame.height
                self.assertTrue(not inside or frame.getpixel(at)[3] == 0, (name, at, 'the icon hangs clear'))

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

    def test_a_player_inside_a_village_takes_no_damage_but_self_damage(self):
        # user request 2026-11-10: invincible inside the half circle, a boss's
        # hits included; what the player does to themselves still costs
        self.run_lua("""
            local isaac=newPlayer(1,0,40,true)
            players={isaac}
            M.onGameStarted()
            M.markers()[1]={slot=1,center=Vec(0,0),inward=Vec(0,1)}
            T.resetEvidence()
            assert(M.onPlayerDamage(nil,isaac,1,0)==false,'an enemy hit inside is cancelled')
            assert(M.onPlayerDamage(nil,isaac,1,DamageFlag.DAMAGE_SPIKES)==false,'spikes too')
            assert(T.evidence().blocked==2 and played==1,'one rustle for two hits in the same update')
            local ward=T.ward(isaac)
            assert(ward.alpha==M.data.wardFade and ward.flash==M.data.wardFlash,'the 금줄 shows and flashes at once')
            for _,flag in ipairs({'DAMAGE_RED_HEARTS','DAMAGE_IV_BAG','DAMAGE_CURSED_DOOR','DAMAGE_DEVIL',
                    'DAMAGE_NO_PENALTIES','DAMAGE_FAKE'}) do
                assert(M.onPlayerDamage(nil,isaac,1,DamageFlag[flag])==nil,flag..' is self-damage and lands')
            end
            frame=M.data.wardSoundGap-1; M.onPlayerDamage(nil,isaac,1,0)
            assert(played==1,'the rustle waits a few updates')
            frame=M.data.wardSoundGap; M.onPlayerDamage(nil,isaac,1,0)
            assert(played==2)
            isaac.Position=Vec(0,120)
            assert(M.onPlayerDamage(nil,isaac,1,0)==nil,'beyond two tiles it lands')
            isaac.Position=Vec(0,-30)
            assert(M.onPlayerDamage(nil,isaac,1,0)==nil,'behind the wall is outside')
            local partner=newPlayer(2,10,30,false)
            players={isaac,partner}
            assert(M.onPlayerDamage(nil,partner,1,0)==false,'a partner inside is sheltered while the holder lives')
            isaac.held=false
            assert(M.onPlayerDamage(nil,partner,1,0)==nil,'no living holder, no shelter')
            assert(M.onPlayerDamage(nil,{ToPlayer=function() return nil end},1,0)==nil,'only players')
            M.onGameExit()
            isaac.held=true
            assert(M.onPlayerDamage(nil,partner,1,0)==nil,'nothing before game start')
        """)

    def test_the_geumjul_fades_in_inside_and_out_after_leaving(self):
        self.run_lua("""
            local isaac=newPlayer(1,0,40,true)
            players={isaac}
            M.onGameStarted()
            M.markers()[1]={slot=1,center=Vec(0,0),inward=Vec(0,1)}
            for i=1,M.data.wardFade+3 do T.tendWards(true) end
            assert(T.ward(isaac).alpha==M.data.wardFade,'fully shown after the fade')
            isaac.Position=Vec(200,200)
            T.tendWards(true)
            assert(T.ward(isaac).alpha==M.data.wardFade-1,'starts fading once outside')
            for i=1,M.data.wardFade do T.tendWards(true) end
            assert(T.ward(isaac)==nil,'gone once faded')
            isaac.Position=Vec(0,40)
            T.tendWards(true)
            assert(T.ward(isaac).alpha==1)
            T.tendWards(false)
            assert(T.ward(isaac)==nil,'fades without a holder')
            T.tendWards(true)
            assert(T.ward(isaac).alpha==1)
            isaac.held=false -- (so the new room raises no pairs in this double)
            M.onNewRoom()
            assert(next(T.wards())==nil,'a new room clears it')
        """)
        anm2 = (ROOT / 'resources/gfx/effects/conch_jangseung_ward.anm2').read_text(encoding='utf-8')
        self.assertIn('Animation Name="Idle"', anm2)
        self.assertIn('Path="conch_jangseung_ward.png"', anm2)
        self.assertTrue((ROOT / 'resources/gfx/effects/conch_jangseung_ward.png').exists())


if __name__ == '__main__':
    unittest.main()
