"""축 (Ox): production Lua with engine doubles.

The pure rules (the bonus on the line and the rice's hold, the room route, the ground the ox may
walk, the plough's line and stamping each quarter of it once) and the room graph over
fake descriptors run here. How the
oxen walk, break rocks, open the secret wall and grow the holder's real stats
needs the engine: `conch_test ox` covers those in game.
"""
from pathlib import Path
import re
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
ModCallbacks={MC_PRE_BACKDROP_RENDER_WATER=1300}
RoomShape={ROOMSHAPE_1x1=1,ROOMSHAPE_IH=2,ROOMSHAPE_IV=3,ROOMSHAPE_1x2=4,ROOMSHAPE_IIV=5,ROOMSHAPE_2x1=6,
    ROOMSHAPE_IIH=7,ROOMSHAPE_2x2=8,ROOMSHAPE_LTL=9,ROOMSHAPE_LTR=10,ROOMSHAPE_LBL=11,ROOMSHAPE_LBR=12}
RoomType={ROOM_DEFAULT=1,ROOM_SHOP=2,ROOM_TREASURE=4,ROOM_BOSS=5,ROOM_SECRET=7,ROOM_SUPERSECRET=8,ROOM_ULTRASECRET=29}
GridEntityType={GRID_ROCK=2,GRID_ROCKB=3,GRID_ROCKT=4,GRID_ROCK_BOMB=5,GRID_ROCK_ALT=6,GRID_PIT=7,GRID_SPIDERWEB=10,
    GRID_LOCK=11,GRID_TNT=12,GRID_POOP=14,GRID_WALL=15,GRID_DOOR=16,GRID_TRAPDOOR=17,GRID_STAIRS=18,GRID_STATUE=21,
    GRID_ROCK_SS=22,GRID_TELEPORTER=23,GRID_PILLAR=24,GRID_ROCK_SPIKED=25,GRID_ROCK_ALT2=26,GRID_ROCK_GOLD=27}
GridCollisionClass={COLLISION_NONE=0}
CacheFlag={CACHE_FIREDELAY=2}
LevelCurse={CURSE_OF_DARKNESS=1,CURSE_OF_THE_LOST=4}
ButtonAction={ACTION_LEFT=0,ACTION_RIGHT=1,ACTION_UP=2,ACTION_DOWN=3,ACTION_SHOOTLEFT=4,ACTION_SHOOTRIGHT=5,
    ACTION_SHOOTUP=6,ACTION_SHOOTDOWN=7,ACTION_BOMB=8,ACTION_ITEM=9,ACTION_PILLCARD=10,ACTION_DROP=11,ACTION_MAP=13}
InputHook={IS_ACTION_PRESSED=0,IS_ACTION_TRIGGERED=1,GET_ACTION_VALUE=2}
GetPtrHash=function(e) return e.hash end
EntityType={ENTITY_EFFECT=1000}
EntityFlag={FLAG_RENDER_FLOOR=1<<58}
EffectVariant={ROCK_PARTICLE=4}
particles=0
Game=function() return {SpawnParticles=function() particles=particles+1 end} end
local VectorMeta={}
VectorMeta.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
Vector=setmetatable({Zero={X=0,Y=0}},{__call=function(_,x,y) return setmetatable({X=x,Y=y},VectorMeta) end})
EntityPtr=function(e) return {Ref=e} end
spawned={}
function spawnEffect(t,v,st,pos)
    local e={Type=t,Variant=v,SubType=st,Position=pos,flags=0}
    function e:ToEffect() return self end
    function e:GetSprite() return {SetFrame=function(_,anim,frame) e.anim,e.frame=anim,frame end,
        Play=function(_,anim) e.anim=anim end} end
    function e:AddEntityFlags(f) self.flags=self.flags|f end
    spawned[#spawned+1]=e
    return e
end
SaveManagerStub={}
OX=951
Isaac={GetItemIdByName=function(name) return name=='Ox' and OX or -1 end,Spawn=function(...) return spawnEffect(...) end,
    GetEntityTypeByName=function(name) return name:find('^Conch Blessing Ox') and 1000 or 0 end,
    GetEntityVariantByName=function(name)
        return ({['Conch Blessing Ox']=4242,['Conch Blessing Ox Furrow']=4243,['Conch Blessing Ox Rice']=4244})[name] or -1
    end}
errors,callbacks={},{}
ConchBlessing={printError=function(e) errors[#errors+1]=e end,printDebug=function() end,
    AddCallback=function(_,id,fn,filter) callbacks[#callbacks+1]={id=id,fn=fn,filter=filter} end}
local loaded={}
require=function(name)
    if name=='scripts.lib.save_manager' then return SaveManagerStub end
    if loaded[name]==nil then loaded[name]=dofile(root..'/'..name:gsub('%.','/')..'.lua') end
    return loaded[name]
end
M=dofile(root..'/scripts/items/collectibles/ox.lua')
T=M._test

-- A fake level: rooms by safe grid index; each covers its shape's cells.
function level(rooms, exact)
    local byCell={}
    for _,r in pairs(rooms) do
        r.GridIndex=r.GridIndex or r.SafeGridIndex
        for _,c in ipairs(r.cells or {r.SafeGridIndex}) do byCell[c]=r end
        r.Data={Shape=r.shape or RoomShape.ROOMSHAPE_1x1,Doors=r.doors or 255,Type=r.type or RoomType.ROOM_DEFAULT}
        r.ListIndex=r.ListIndex or r.SafeGridIndex; r.VisitedCount=r.VisitedCount or 0; r.DisplayFlags=r.DisplayFlags or 0
        if exact then r.GetNeighboringRooms=function(self)
            local out={}
            for slot,other in pairs(self.exact or {}) do out[slot]=rooms[other] end
            return out
        end end
    end
    return {GetRoomByIdx=function(_,i) return byCell[i] or {GridIndex=-1} end}
end

-- A fake room `w` cells wide and `h` high whose outer ring is wall: `paths`
-- gives a cell's grid path cost (0 by default), `rocks` the standing rocks.
function fakeRoom(w,h,paths,rocks)
    local room={paths=paths or {},rocks=rocks or {},destroyed={}}
    function room:GetGridWidth() return w end
    function room:GetGridSize() return w*h end
    function room:GetGridPosition(c) return Vector((c%w)*40,(c//w)*40) end
    function room:GetGridIndex(p) return math.floor(p.Y/40+0.5)*w+math.floor(p.X/40+0.5) end
    function room:GetCenterPos() return self:GetGridPosition((h//2)*w+w//2) end
    -- The door places of a 1x1 room: the middle of each wall.
    local places={[0]=(h//2)*w,[1]=w//2,[2]=(h//2)*w+w-1,[3]=(h-1)*w+w//2}
    function room:IsDoorSlotAllowed(slot) return places[slot]~=nil end
    function room:GetDoorSlotPosition(slot) return self:GetGridPosition(places[slot] or 0) end
    function room:IsPositionInRoom(p) local x,y=p.X/40,p.Y/40 return x>0 and x<w-1 and y>0 and y<h-1 end
    function room:GetGridPath(c) if self.rocks[c] then return 1000 end return self.paths[c] or 0 end
    function room:GetGridEntity(c)
        local kind=self.rocks[c]
        if not kind then return nil end
        return {GetType=function() return kind==true and GridEntityType.GRID_ROCK or kind end,CollisionClass=1}
    end
    function room:GetGridCollision(c) return (self.rocks[c] or (self.paths[c] or 0)>=1000) and 1 or 0 end
    function room:DestroyGrid(c) self.rocks[c]=nil; self.destroyed[#self.destroyed+1]=c; return true end
    function room:RemoveGridEntity(c) self.rocks[c]=nil; self.removed=(self.removed or 0)+1 end
    return room
end
"""


class OxTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(HARNESS)

    def run_lua(self, script):
        self.lua.execute(script)

    def test_the_bonus_is_on_only_while_standing_on_the_line(self):
        self.run_lua(r'''
            assert(M.data.damage==2 and M.data.tears==2 and M.data.width==1,'x2 damage on the furrow, x2 tears in the ditch')
            assert(M.data.stepFrames==nil and M.data.steps==nil and T.nextLevel==nil,'nothing grows or wilts (user request 2026-10-31)')
            assert(M.data.riceHold==60,'the rice lasts two seconds after stepping off')
            -- Two tiles a second at 30 updates a second.
            assert(math.abs(M.data.speed*30-80)<1e-9)
            -- StatsAPI's item multipliers, as Ox sets them.
            local set={}
            ConchBlessing.stats={unifiedMultipliers={
                SetItemMultiplier=function(_,_,id,stat,v) assert(id==OX) set[stat]=v end,
                RemoveItemMultiplier=function(_,_,id,stat) assert(id==OX) set[stat]=nil end}}
            ConchBlessing.getUnifiedMultiplierState=function()
                local row={}
                for stat,v in pairs(set) do row[stat]={value=v} end
                return {itemMultipliers={[OX]=row}}
            end
            local across=(1<<2)|(1<<3)|(1<<6)|(1<<7)
            local down=(1<<0)|(1<<1)|(1<<4)|(1<<5)
            local room=fakeRoom(15,9,{},{})
            local field={yellow={[tostring(20)]=across},black={[tostring(50)]=down}}
            local player={hash=1}
            local function at(c,dx,dy) local p=room:GetGridPosition(c) player.Position={X=p.X+(dx or 0),Y=p.Y+(dy or 0)} end
            at(20) T.grow(player,field,room)
            assert(set.Damage==2 and set.Tears==nil,'on the furrow: damage x2 at once')
            at(20,0,13) T.grow(player,field,room)
            assert(set.Damage==nil and set.Tears==nil,'a step off it: gone at once')
            at(50) T.grow(player,field,room)
            assert(set.Tears==2 and set.Damage==nil,'in the ditch: tears x2 at once')
            at(50,13,13) T.grow(player,field,room)
            assert(next(set)==nil,'a step off the ditch: gone at once')
            -- The rice gives both, and keeps them two seconds after stepping off.
            field.yellow[tostring(35)],field.black[tostring(35)]=across,down
            T.sowRice(field,room,false)
            local spot=T.rice()[35]
            player.Position={X=spot.x,Y=spot.y}
            T.grow(player,field,room)
            assert(set.Damage==2 and set.Tears==2,'in the rice: both x2')
            at(5,0,0)   -- a bare cell far from every line
            for update=1,59 do
                T.grow(player,field,room)
                assert(set.Damage==2 and set.Tears==2,'still both '..update..' updates after stepping off')
            end
            T.grow(player,field,room)
            assert(next(set)==nil and T.riceLeft()[1]==nil,'gone two seconds after stepping off')
            -- Losing the item takes the bonus away, the rice's too.
            player.Position={X=spot.x,Y=spot.y}
            T.grow(player,field,room)
            T.wither(player)
            assert(next(set)==nil and T.boosted()[1]==false and T.riceLeft()[1]==nil,'losing the item takes it away')
        ''')

    def test_route_goes_through_allowed_rooms_only(self):
        self.run_lua(r'''
            local graph={[1]={2,4},[2]={1,3},[3]={2,9},[4]={1,5},[5]={4,9},[9]={3,5}}
            local function nb(i) return graph[i] or {} end
            local all=function() return true end
            local p=T.route(1,9,nb,all)
            assert(#p==4 and p[1]==1 and p[4]==9,'shortest, first neighbours first: '..table.concat(p,'>'))
            assert(p[2]==2 and p[3]==3)
            p=T.route(1,9,nb,function(i) return i~=2 end)
            assert(table.concat(p,'>')=='1>4>5>9','avoids a room it may not pass')
            assert(T.route(1,9,nb,function(i) return false end)==nil,'no way through')
            assert(T.route(3,9,nb,function() return false end)[2]==9,'the goal itself is always allowed')
            assert(#T.route(5,5,nb,all)==1,'already there')
        ''')

    def test_path_ploughs_straight_lines_and_respects_the_grid(self):
        self.run_lua(r'''
            local W,S=10,80
            local open=function() return 1 end
            local function turns(p)
                local n,last=0,nil
                for i=2,#p do local d=p[i]-p[i-1]; if last and d~=last then n=n+1 end; last=d end
                return n
            end
            local p=T.findPath(W,S,11,18,open)
            assert(#p==8 and turns(p)==0,'a straight row')
            p=T.findPath(W,S,11,55,open)
            assert(#p==9 and turns(p)==1,'one corner, not a staircase: '..table.concat(p,','))
            -- A wall across column 4 with one gap at row 6.
            local wall=function(c) if c%W==4 and c//W~=6 then return nil end return 1 end
            p=T.findPath(W,S,12,16,wall)
            local through=false
            for _,c in ipairs(p) do if c%W==4 then assert(c//W==6); through=true end end
            assert(through,'goes round through the gap')
            -- Never wraps from the last column to the first of the next row.
            assert(T.findPath(W,S,9,10,function(c) return (c==9 or c==10) and 1 or nil end)==nil,
                'the last column and the next row\'s first are not neighbours')
            p=T.findPath(W,S,8,1,function(c) return (c<10) and 1 or nil end)
            assert(table.concat(p,',')=='8,7,6,5,4,3,2,1','along its own row')
            assert(T.findPath(W,S,11,18,function(c) if c==15 then return nil end return c//W==1 and 1 or nil end)==nil,
                'a blocked row with no way round')
            -- Cheaper to break through a breakable cell than go far round it.
            p=T.findPath(W,S,11,13,function(c) return c==12 and 1 or 1 end)
            assert(table.concat(p,',')=='11,12,13')
        ''')

    def test_the_ox_walks_only_on_ground_the_engine_pathfinder_walks(self):
        self.run_lua(r'''
            -- Room:GetGridPath costs: under 900 ground, 900-999 avoided, 1000 and up none.
            assert(T.groundCost(0,false)==1 and T.groundCost(899,false)==1)
            assert(T.groundCost(900,false)==2 and T.groundCost(950,false)==2 and T.groundCost(999,false)==2,
                'ground it takes only to save a step')
            assert(T.groundCost(1000,false)==nil and T.groundCost(3000,false)==nil and T.groundCost(3999,false)==nil,
                'grid entities, pits and grimaces are no ground')
            assert(T.groundCost(1000,true)==2,'a standing rock is crushed on the way')
            -- Every block a bomb breaks is crushed, TNT and bomb rocks without going off;
            -- a metal block or a pillar it walks round.
            local blocks=fakeRoom(9,5,{},{[11]=GridEntityType.GRID_TNT,[12]=GridEntityType.GRID_ROCK_BOMB,
                [13]=GridEntityType.GRID_ROCKB,[14]=GridEntityType.GRID_PILLAR,[15]=true})
            local cost=T.groundAt(blocks)
            assert(cost(11)==2 and cost(12)==2 and cost(15)==2,'TNT, a bomb rock and a rock')
            assert(cost(13)==nil and cost(14)==nil,'a metal block and a pillar are no ground')
            T.crush(blocks,11); T.crush(blocks,12); T.crush(blocks,15)
            assert(blocks.removed==2 and #blocks.destroyed==1,'TNT and the bomb rock removed quietly, the rock broken')
            assert(particles==2,'a little rubble flies from each')
            assert(blocks.rocks[11]==nil and blocks.rocks[12]==nil and blocks.rocks[15]==nil)
            T.crush(blocks,13)
            assert(blocks.rocks[13]~=nil,'a metal block is never crushed')
            assert(T.groundCost(0,false,true)==nil,'a pit that just opened collides before it has a path cost')
            -- A pit across column 5 with one gap at row 4; a rock on row 2.
            local W=11
            local paths={}
            for r=1,5 do if r~=4 then paths[r*W+5]=3000 end end
            local room=fakeRoom(W,7,paths,{[2*W+3]=true})
            local p,reached=T.findPath(W,W*7,2*W+1,2*W+9,T.cellCost(room),true)
            assert(reached,'reaches the far side')
            local crossed=false
            for _,c in ipairs(p) do
                assert(paths[c]==nil,'never on a pit: '..c)
                assert(c%W>0 and c%W<W-1 and c//W>0 and c//W<6,'never in a wall: '..c)
                if c%W==5 then assert(c//W==4); crossed=true end
            end
            assert(crossed,'crosses through the gap')
            -- The pit closes completely: it goes as near as it can and says so.
            paths[4*W+5]=3000
            p,reached=T.findPath(W,W*7,2*W+1,2*W+9,T.cellCost(room),true)
            assert(reached==false and p[#p]%W==4,'stops beside the pit: '..table.concat(p,','))
            for _,c in ipairs(p) do assert(paths[c]==nil) end
            assert(T.findPath(W,W*7,2*W+1,2*W+9,T.cellCost(room))==nil,'without partial there is no way')
            -- A goal on a pit is not walked onto either.
            p,reached=T.findPath(W,W*7,2*W+1,3*W+5,T.cellCost(room),true)
            assert(reached==false and paths[p[#p]]==nil)
        ''')

    def test_the_line_runs_round_its_turns_without_a_jump(self):
        self.run_lua(r'''
            local N,E,S,W_=1,2,4,8
            -- Pieces: straight quarters side*2+(0 edge,1 middle), arcs 8+corner*4+k.
            assert(T.quarterPiece(W_,E,0)==6 and T.quarterPiece(W_,E,1)==7)
            assert(T.quarterPiece(W_,E,2)==3 and T.quarterPiece(W_,E,3)==2,'west to east: west half, then east half')
            assert(T.quarterPiece(E,W_,0)==2 and T.quarterPiece(E,W_,3)==6,'the same halves walked the other way')
            assert(T.quarterPiece(N,E,0)==8 and T.quarterPiece(N,E,3)==11,'the north-east turn, from north')
            assert(T.quarterPiece(W_,S,0)==19 and T.quarterPiece(W_,S,3)==16,'the south-west turn walked from west')
            assert(T.quarterPiece(N,nil,1)==1 and T.quarterPiece(N,nil,2)==nil,'a way ending in the middle')
            assert(T.quarterPiece(nil,S,1)==nil and T.quarterPiece(nil,S,2)==5 and T.quarterPiece(nil,S,3)==4)
            -- In and back out the same side: the same straight half twice.
            assert(T.quarterPiece(N,N,0)==0 and T.quarterPiece(N,N,1)==1 and T.quarterPiece(N,N,2)==1 and T.quarterPiece(N,N,3)==0)
            local back={11,21,11}
            local j,x,y=T.curveAt(back,10,1,nil,nil)
            assert(j==2 and x==0 and y==0,'it turns round in the middle of the cell')
            j,x,y=T.curveAt(back,10,1.25,nil,nil)
            assert(j==2 and x==0 and y==-10,'and heads back out the side it came in by')
            local used={}
            for _,a in ipairs({N,E,S,W_,false}) do for _,b in ipairs({N,E,S,W_,false}) do
                if a~=b then for q=0,3 do
                    local piece=T.quarterPiece(a or nil,b or nil,q)
                    if piece then used[piece]=true end
                end end
            end end
            for piece=0,23 do assert(used[piece],'piece '..piece..' is used') end
            -- In from the west door, east, a turn south, and on to stop in the middle.
            local Wd=10
            local path={11,12,13,23,33}
            local j,x,y,tx,ty=T.curveAt(path,Wd,-0.5,W_,nil)
            assert(j==1 and x==-20 and y==0 and tx==1,'starts at the west doorway')
            j,x,y=T.curveAt(path,Wd,0.75,W_,nil)
            assert(j==2 and x==-10 and y==0,'a quarter of a cell into the second cell')
            -- The turn cell (13, in from the west, out to the south) is a quarter circle
            -- of radius 20 round its south-west corner.
            for p=1.5,2.5,0.05 do
                j,x,y=T.curveAt(path,Wd,p,W_,nil)
                assert(j==3 and math.abs(math.sqrt((x+20)^2+(y-20)^2)-20)<1e-6,'on the arc at '..p)
            end
            j,x,y,tx,ty=T.curveAt(path,Wd,2,W_,nil)
            assert(tx>0 and ty>0 and math.abs(tx-ty)<1e-6,'half way round it heads down and right')
            -- Walked in small steps the ox never jumps, cell to cell or round the turn.
            local function world(p)
                local j,x,y=T.curveAt(path,Wd,p,W_,nil)
                local c=path[j]
                return (c%Wd)*40+x,(c//Wd)*40+y
            end
            local px,py=world(-0.5)
            for p=-0.49,4,0.01 do
                local qx,qy=world(p)
                assert(math.sqrt((qx-px)^2+(qy-py)^2)<0.6,'a jump at '..p)
                px,py=qx,qy
            end
            j,x,y=T.curveAt(path,Wd,4,W_,nil)
            assert(j==5 and x==0 and y==0,'stops in the middle of the last cell')
            -- How far a point lies from the drawn line.
            local west=(1<<6)|(1<<7)
            assert(T.furrowDistance(west,-15,0)==0 and T.furrowDistance(west,0,5)==5)
            assert(T.furrowDistance(west,5,0)==5,'the east half is not drawn')
            assert(T.furrowDistance(1<<6,0,0)==10,'only the quarter at the edge')
            local arc=(1<<16)|(1<<17)|(1<<18)|(1<<19)
            assert(T.furrowDistance(arc,-20+20*math.cos(0.3),20-20*math.sin(0.3))<1e-6,'on the turn')
            assert(math.abs(T.furrowDistance(arc,0,0)-(math.sqrt(800)-20))<1e-6)
            assert(T.furrowDistance(0,0,0)==math.huge)
            -- The line's span: from a doorway or the middle, to a doorway or the middle.
            local a,b=T.lineSpan(path,{first=W_})
            assert(a==-0.5 and b==4)
            a,b=T.lineSpan(path,{last=S})
            assert(a==0 and b==4.5)
        ''')

    def test_each_quarter_of_the_line_is_stamped_into_the_floor_once(self):
        self.run_lua(r'''
            local room=fakeRoom(15,9,{},{})
            local state,desc={fields={}},{ListIndex=7}
            local path={1*15+2,1*15+3,1*15+4,1*15+5,2*15+5}
            local ends={first=8}
            -- The share lays quarters up to where it is, each once.
            local at=T.plough(state,desc,room,'yellow',path,ends,-0.5,0.7)
            assert(at==0.75,'stopped at '..at)
            local field=state.fields.L7.yellow
            assert(field[tostring(17)]==(1<<6)|(1<<7)|(1<<3)|(1<<2),'the first cell, from the west doorway east')
            assert(field[tostring(18)]==1<<6,'one quarter into the second cell')
            at=T.plough(state,desc,room,'yellow',path,ends,at,math.huge)
            assert(at==4)
            assert(field[tostring(20)]==(1<<16)|(1<<17)|(1<<18)|(1<<19),'the turn south')
            assert(field[tostring(35)]==(1<<0)|(1<<1),'down to the middle of the last cell')
            T.stampFurrows(state,desc,room)
            assert(#spawned==18,'one stamp a quarter: '..#spawned)
            for _,e in ipairs(spawned) do
                assert(e.Variant==4243 and e.anim=='Furrow' and e.flags&EntityFlag.FLAG_RENDER_FLOOR~=0)
                assert(e.frame%24<24 and e.frame//24<2,'a yellow piece')
            end
            -- The engine removes the stamps; walking the same way stamps nothing again.
            T.plough(state,desc,room,'yellow',path,ends,-0.5,math.huge)
            T.stampFurrows(state,desc,room)
            assert(#spawned==18)
            -- A way crossing it: only its own new quarters.
            local down={1*15+4,2*15+4,3*15+4}
            T.plough(state,desc,room,'yellow',down,{},0,math.huge)
            T.stampFurrows(state,desc,room)
            assert(#spawned==18+2+4+2,'the crossing adds the south half, a full cell and a half: '..#spawned)
            -- A cell where a rock still stands gets no furrow until it is crushed.
            room.rocks[3*15+7]=true
            T.plough(state,desc,room,'black',{3*15+6,3*15+7,3*15+8},{},0,math.huge)
            assert(state.fields.L7.black[tostring(3*15+7)]==nil and state.fields.L7.black[tostring(3*15+6)]~=nil)
            -- A new room's floor has none of them: every quarter once again.
            M.onNewRoom()
            local before=#spawned
            T.stampFurrows(state,desc,room)
            assert(#spawned-before==26+4,'stamped afresh: '..(#spawned-before))
            for mark,n in pairs(T.evidence().stamps) do assert(n==1,mark..' stamped '..n..' times') end
            -- Standing on it: within 12 of the line, here or in the cell beside.
            local function at_(c,dx,dy) local p=room:GetGridPosition(c) return {X=p.X+dx,Y=p.Y+dy} end
            local fields=state.fields.L7
            assert(T.onFurrow(fields,'yellow',room,at_(17,0,0)))
            assert(T.onFurrow(fields,'yellow',room,at_(17,5,11)),'11 below the line')
            assert(not T.onFurrow(fields,'yellow',room,at_(17,5,13)),'13 below it is off')
            assert(not T.onFurrow(fields,'yellow',room,at_(32,0,-19)),'21 below the line in the cell above is off')
            -- A line in the cell below reaches up to its edge: 5 from it, in the cell above, is on.
            local below={yellow={[tostring(3*15+2)]=(1<<0)|(1<<1)}}
            assert(T.onFurrow(below,'yellow',room,at_(2*15+2,0,15)),'found through the cell next to it')
            assert(not T.onFurrow(below,'yellow',room,at_(2*15+2,0,-5)))
        ''')

    def test_rice_grows_where_the_furrow_meets_the_ditch(self):
        self.run_lua(r'''
            local across=(1<<2)|(1<<3)|(1<<6)|(1<<7)   -- west to east through the middle
            local down=(1<<0)|(1<<1)|(1<<4)|(1<<5)     -- north to south through the middle
            local x,y=T.meetPoint(across,down)
            assert(x and math.abs(x)<1e-6 and math.abs(y)<1e-6,'they cross in the middle')
            -- The west half against a turn round the north-east corner: 8.3 apart, no rice.
            local west=(1<<6)|(1<<7)
            local turn=(1<<8)|(1<<9)|(1<<10)|(1<<11)
            assert(T.meetPoint(west,turn)==nil,'lines that pass 8.3 apart do not meet')
            assert(T.meetPoint(across,0)==nil and T.meetPoint(0,down)==nil)
            -- Running together over the whole cell, they meet in its middle.
            x,y=T.meetPoint(down|across,down)
            assert(math.abs(x)<1e-6 and math.abs(y)<1e-6,'the middle of where they run together: '..x..','..y)
            -- A turn round the south-west corner against the line north to south:
            -- the rice stands on the turn, within reach of the line, as near the
            -- middle as the turn comes.
            local southWest=(1<<16)|(1<<17)|(1<<18)|(1<<19)
            x,y=T.meetPoint(southWest,down)
            assert(x,'they meet')
            assert(math.abs(math.sqrt((x+20)^2+(y-20)^2)-20)<1e-6,'on the turn')
            assert(T.furrowDistance(down,x,y)<=8 and math.abs(x)<8,'within reach of the line')
            assert(x*x+y*y<20*20,'nearer the middle than where they touch at the edge')
            -- Points along the pieces: the edge, the middle, round the turn.
            local px,py=T.piecePoint(6,0)
            assert(px==-20 and py==0)
            px,py=T.piecePoint(7,1)
            assert(px==0 and py==0)
            px,py=T.piecePoint(8,0)
            assert(math.abs(px)<1e-6 and math.abs(py+20)<1e-6,'a turn starts at its first edge')
            -- Sown into a room: one plant a meeting cell, grown on coming in,
            -- growing where the oxen make them meet in sight.
            local room=fakeRoom(15,9,{},{})
            local field={yellow={[tostring(20)]=across,[tostring(21)]=west},black={[tostring(20)]=down,[tostring(21)]=turn}}
            T.sowRice(field,room,false)
            local plants=0
            for cell,spot in pairs(T.rice()) do
                plants=plants+1
                assert(cell==20 and spot.x==(20%15)*40 and spot.y==(20//15)*40,'in the middle of cell 20')
                assert(spot.ref.Ref.Variant==4244 and spot.ref.Ref.anim=='Idle' and spot.ref.Ref.DepthOffset==-10)
            end
            assert(plants==1,'only where the lines meet: '..plants)
            T.sowRice(field,room,true)
            assert(T.evidence().rice==1,'a cell gets its rice once')
            field.yellow[tostring(35)],field.black[tostring(35)]=across,down
            T.sowRice(field,room,true)
            assert(T.rice()[35].ref.Ref.anim=='Grow','a new meeting grows before the eyes')
            M.onNewRoom()
            assert(next(T.rice())==nil,'a new room has none until sown')
        ''')

    def test_a_middle_it_cannot_reach_it_sleeps_at_the_entrance(self):
        self.run_lua(r'''
            -- The middle of the room (cell 4*15+7) is ringed with pits.
            local W=15
            local paths={}
            for dy=-1,1 do for dx=-1,1 do if dx~=0 or dy~=0 then paths[(4+dy)*W+7+dx]=3000 end end end
            local room=fakeRoom(W,9,paths,{})
            local entrance=4*W+1
            local path,reached=T.wayIn(room,entrance,4*W+7,false)
            assert(#path==1 and path[1]==entrance and reached,'it stays at the entrance it came in by')
            -- Heading for a door it cannot reach, it still goes as near as it can.
            path,reached=T.wayIn(room,entrance,4*W+7,true)
            assert(not reached and #path>1,'toward a door it walks as near as it can')
            -- A middle it can reach it walks to.
            paths[3*W+7]=nil
            path,reached=T.wayIn(room,entrance,4*W+7,false)
            assert(reached and path[#path]==4*W+7)
            -- The room's cross: the rows and columns of its door places.
            local open=fakeRoom(W,9,{},{})
            local rows,columns=T.doorLines(open)
            assert(rows[4] and columns[7] and not rows[1] and not columns[1],'one row and one column through the middle')
            -- From the left door to the top one it follows the cross, not the walls.
            path,reached=T.wayIn(open,4*W+1,1*W+7,true)
            assert(reached and path[1]==4*W+1 and path[#path]==1*W+7)
            for _,c in ipairs(path) do assert(c//W==4 or c%W==7,'on the cross: '..c) end
            -- From a corner it makes first for the cross, then follows it to the door.
            path,reached=T.wayIn(open,7*W+12,4*W+13,true)
            assert(reached and path[#path]==4*W+13 and path[#path-1]==4*W+12,'reaches the cross, then along it to the door')
            for i=2,#path-1 do assert(path[i]%W==12,'straight up to the cross, not along the bottom wall: '..path[i]) end
            -- In by the bottom door, out by the right one: up the middle and along it,
            -- never along the bottom and right walls.
            path,reached=T.wayIn(open,7*W+7,4*W+13,true)
            assert(reached)
            for _,c in ipairs(path) do assert(c//W==4 or c%W==7,'on the cross: '..c) end
            -- Off the cross a cell counts one more, so it never runs along a wall to a door.
            local cost=T.cellCost(open)
            assert(cost(4*W+3)==1 and cost(2*W+7)==1 and cost(2*W+3)==2 and cost(7*W+12)==2)
        ''')

    def test_an_old_floor_save_turns_into_straight_halves(self):
        self.run_lua(r'''
            local save={ox={oxen={},fields={L3={yellow={['5']=0},black={['6']=1}}}}}
            SaveManagerStub.GetFloorSave=function() return save end
            local state=T.state()
            assert(state.pieces==true and state.bits==nil)
            assert(state.fields.L3.yellow['5']==(3<<2)|(3<<6),'along a row: the east and west halves')
            assert(state.fields.L3.black['6']==(3<<0)|(3<<4),'along a column: the north and south halves')
            state=T.state()
            assert(state.fields.L3.yellow['5']==(3<<2)|(3<<6),'only once')
            save={ox={oxen={},bits=true,fields={L4={yellow={['9']=2|4},black={}}}}}
            state=T.state()
            assert(state.fields.L4.yellow['9']==(3<<2)|(3<<4),'directions east and south: those halves')
        ''')

    def test_room_graph_from_shapes_doors_and_repentogon(self):
        self.run_lua(r'''
            -- 40 is a 2x1 room (cells 40, 41); 39 left of it, 42 right of its second cell,
            -- 28 above its second cell, 53 below its first; 52 has no door to 40's slot.
            local rooms={
                [40]={SafeGridIndex=40,shape=RoomShape.ROOMSHAPE_2x1,cells={40,41}},
                [39]={SafeGridIndex=39},[42]={SafeGridIndex=42},[28]={SafeGridIndex=28},[53]={SafeGridIndex=53},
            }
            local L=level(rooms)
            local list=T.neighborsOf(L,40)
            table.sort(list)
            assert(table.concat(list,',')=='28,39,42,53','every door cell of the 2x1: '..table.concat(list,','))
            rooms[40].Data.Doors=1|4  -- only LEFT0 and RIGHT0
            list=T.neighborsOf(L,40); table.sort(list)
            assert(table.concat(list,',')=='39,42','closed door slots lead nowhere: '..table.concat(list,','))
            -- Left of column 0 is not the previous row's last cell.
            local edge={[26]={SafeGridIndex=26},[25]={SafeGridIndex=25}}
            local E=level(edge)
            for _,i in ipairs(T.neighborsOf(E,26)) do assert(i~=25,'no wrap across the map edge') end
            -- With REPENTOGON the engine's doors decide, plus the secret room behind a hidden wall.
            local exact={
                [1]={SafeGridIndex=1,exact={[2]=2}},[2]={SafeGridIndex=2,exact={[0]=1}},
                [14]={SafeGridIndex=14,type=RoomType.ROOM_SECRET},[0]={SafeGridIndex=0},
            }
            local X=level(exact,true)
            list=T.neighborsOf(X,1); table.sort(list)
            assert(table.concat(list,',')=='2,14','engine doors plus the secret room: '..table.concat(list,','))
        ''')

    def test_doors_count_for_the_layout_room_and_the_room_they_name(self):
        self.run_lua(r'''
            -- Start room 84 with doors left (83), up (71) and right; another mod pointed the
            -- right door at the treasure room 96, but the layout puts room 85 behind it.
            local rooms={[84]={SafeGridIndex=84},[83]={SafeGridIndex=83},[71]={SafeGridIndex=71},
                [85]={SafeGridIndex=85},[96]={SafeGridIndex=96,type=RoomType.ROOM_TREASURE},
                [97]={SafeGridIndex=97,type=RoomType.ROOM_BOSS}}
            local L=level(rooms)
            local doors={[0]={TargetRoomIndex=83},[1]={TargetRoomIndex=71},[2]={TargetRoomIndex=96}}
            local room={GetDoor=function(_,slot) return doors[slot] end}
            local list,slots=T.exits(L,room,rooms[84])
            table.sort(list)
            assert(table.concat(list,',')=='71,83,85,96','layout and named rooms: '..table.concat(list,','))
            assert(slots[85]==2 and slots[96]==2 and slots[83]==0 and slots[71]==1)
            -- No door, no exit, whatever the layout says.
            doors[1]=nil
            list,slots=T.exits(L,room,rooms[84])
            assert(slots[71]==nil)
            -- The shortest way goes through any room but a secret or a boss room;
            -- a locked door does not matter, the ox goes through it.
            assert(T.passable(L)(83) and T.passable(L)(96),'an ordinary room and a treasure room')
            assert(not T.passable(L)(97) and T.passable(L,true)(97),'a boss room only when there is no other way')
            rooms[96].Data.Type=RoomType.ROOM_SECRET
            assert(not T.passable(L)(96))
            -- The next room is the first of the shortest way, through a treasure room if need be.
            local ox={goals={97},gi=1}
            rooms[96].Data.Type=RoomType.ROOM_TREASURE
            rooms[97].exact={[0]=96}; rooms[96].exact={[2]=97,[0]=84}
            local L2=level(rooms,true)
            assert(T.plan(ox,L2,84,{96,83})==96,'straight on through the treasure room')
            -- An XL floor: the last boss room 99 lies behind the first, 98.
            local xl={[84]={SafeGridIndex=84},[85]={SafeGridIndex=85},[98]={SafeGridIndex=98,type=RoomType.ROOM_BOSS},
                [99]={SafeGridIndex=99,type=RoomType.ROOM_BOSS}}
            xl[84].exact={[2]=85}; xl[85].exact={[0]=84,[3]=98}; xl[98].exact={[1]=85,[2]=99}; xl[99].exact={[0]=98}
            local LX=level(xl,true)
            local yellow={goals={99},gi=1}
            assert(T.plan(yellow,LX,84)==85 and T.plan(yellow,LX,85)==98,'through the first boss room to the last')
        ''')

    def test_unseen_oxen_walk_on_room_by_room(self):
        self.run_lua(r"""
            -- 84 > 85 > 86 > 87 (boss) in a row; the secret room 72 is above 85, the super secret 99 below 86.
            local rooms={[84]={SafeGridIndex=84},[85]={SafeGridIndex=85},[86]={SafeGridIndex=86},
                [87]={SafeGridIndex=87,type=RoomType.ROOM_BOSS},[72]={SafeGridIndex=72,type=RoomType.ROOM_SECRET},
                [99]={SafeGridIndex=99,type=RoomType.ROOM_SUPERSECRET}}
            local L=level(rooms)
            local state={oxen={},fields={},trails={},walls={}}
            local yellow={goals={87},gi=1,room=84,a={x=0,y=0},cells=0,done=false}
            local updates,order=0,{}
            while not yellow.done and updates<2000 do
                local before=yellow.room
                T.travel('yellow',yellow,state,L)
                updates=updates+1
                if yellow.room~=before then order[#order+1]=yellow.room end
            end
            assert(table.concat(order,'>')=='85>86>87','room by room: '..table.concat(order,'>'))
            -- Ten cells a room and five to the middle, at two tiles a second.
            assert(math.abs(updates-(3*150+75))<=12,'about 17.5 seconds (one planning and one arriving update a room): '..updates)
            for _,i in ipairs({85,86,87}) do assert(rooms[i].DisplayFlags&5==5,'shown on the map: '..i) end
            assert(rooms[84].DisplayFlags==0,'the room it started in is not touched')
            local trail=state.trails['L84'].yellow
            assert(#trail==1 and trail[1].ploughed==false and trail[1].b.to==85 and trail[1].a.x==0,
                'an unseen stretch waits to be ploughed')
            assert(state.trails['L87'].yellow[1].b.center==true,'it ends in the middle of the boss room')
            -- The black ox: the secret room, then the super secret room.
            local black={goals={72,99},gi=1,room=84,a={x=0,y=0},cells=0,done=false}
            local seen={}
            for _=1,3000 do
                local before=black.room
                T.travel('black',black,state,L)
                if black.room~=before then seen[#seen+1]=black.room end
                if black.done then break end
            end
            -- Unseen it walks straight through each hidden wall, on to the super secret room.
            assert(table.concat(seen,'>')=='85>72>85>86>99','the secret room, out the way it came, the super secret room: '
                ..table.concat(seen,'>'))
            assert(black.done and black.room==99 and black.gi==2,'it stays in the super secret room')
            assert(rooms[72].DisplayFlags&5==5 and rooms[99].DisplayFlags&5==5,'both show on the map')
            -- The walls it went through are opened when a player comes into either room.
            assert(#state.walls==2 and state.walls[1][1]==85 and state.walls[1][2]==72
                and state.walls[2][1]==86 and state.walls[2][2]==99,'walls to open: '..#state.walls)
            -- An ox saved before this model carries on from where it was.
            local old=T.normalize({goal=87,room=85,x=10,y=20,from=84,done=false})
            assert(old.goals[1]==87 and old.gi==1 and old.a.x==10 and old.cells==0 and old.x==nil)
        """)

    def test_out_of_a_secret_room_by_the_nearest_wall(self):
        self.run_lua(r"""
            -- The secret room 72 came in from 85 below; 73 beside it leads straight
            -- to the super secret room 60 above, while from 85 it is a long way round.
            local rooms={[72]={SafeGridIndex=72,type=RoomType.ROOM_SECRET},[85]={SafeGridIndex=85},
                [86]={SafeGridIndex=86},[73]={SafeGridIndex=73},[60]={SafeGridIndex=60,type=RoomType.ROOM_SUPERSECRET}}
            local L=level(rooms)
            local ox={goals={72,60},gi=2,room=72,from=85,a={from=85},cells=0,done=false}
            assert(T.plan(ox,L,72)==73,'out by the wall nearest the super secret room, not back the way it came')
            -- Unseen, it walks through that hidden wall too, and the wall is opened later.
            local state={oxen={},fields={},trails={},walls={}}
            for _=1,2000 do T.travel('black',ox,state,L); if ox.done then break end end
            assert(ox.done and ox.room==60,'it reaches the super secret room: '..tostring(ox.room))
            local out=false
            for _,w in ipairs(state.walls) do if w[1]==72 and w[2]==73 then out=true end end
            assert(out,'the wall out of the secret room is to be opened')
        """)

    def test_the_jealous_black_ox_digs_red_rooms_to_the_ultra_secret_room(self):
        self.run_lua(r"""
            -- 84 is an ordinary room; 71 above it is empty; the ultra secret room 58 sits above that.
            local rooms={}
            local function add(i,t)
                rooms[i]={SafeGridIndex=i,GridIndex=i,ListIndex=i,VisitedCount=0,DisplayFlags=0,
                    Data={Shape=RoomShape.ROOMSHAPE_1x1,Doors=255,Type=t or RoomType.ROOM_DEFAULT}}
            end
            add(84); add(58,RoomType.ROOM_ULTRASECRET)
            local dug,refuse={},{}
            local L={GetRoomByIdx=function(_,i) return rooms[i] or {GridIndex=-1} end,
                MakeRedRoomDoor=function(_,i,slot)
                    if refuse[i..':'..slot] then return false end
                    local cell=i+({[0]=-1,[1]=-13,[2]=1,[3]=13})[slot]
                    if not rooms[cell] then add(cell) end
                    dug[#dug+1]=i..':'..slot
                    return true
                end}
            local ox={goals={58},gi=1,room=84,a={center=true},cells=0,done=false,red=true}
            local next_,slot=T.planRed(ox,L,84)
            assert(next_==71 and slot==1,'first a red room in the empty cell above: '..tostring(next_)..' '..tostring(slot))
            local state={oxen={},fields={},trails={},walls={}}
            local order={}
            for _=1,1000 do
                local before=ox.room
                T.travel('black',ox,state,L)
                if ox.room~=before then order[#order+1]=ox.room end
                if ox.done then break end
            end
            assert(table.concat(order,'>')=='71>58','through its own red room into the ultra secret room: '..table.concat(order,'>'))
            assert(table.concat(dug,',')=='84:1,71:1','two red doors dug: '..table.concat(dug,','))
            assert(ox.done and rooms[58].DisplayFlags&5==5,'it sleeps there, and the room shows on the map')
            -- An ordinary room's own door is used rather than dug.
            rooms={}; dug={}
            add(84); add(71); add(58,RoomType.ROOM_ULTRASECRET)
            rooms[84].GetNeighboringRooms=function() return {[1]=rooms[71]} end
            ox={goals={58},gi=1,room=84,a={center=true},cells=0,done=false,red=true}
            next_,slot=T.planRed(ox,L,84)
            assert(next_==71 and slot==nil,'walks through the existing door')
            -- A refused red door is never tried again; another way is found.
            rooms={}; dug={}
            add(84); add(58,RoomType.ROOM_ULTRASECRET)
            refuse['84:1']=true
            ox={goals={58},gi=1,room=84,a={center=true},cells=0,done=false,red=true}
            for _=1,3000 do T.travel('black',ox,state,L); if ox.done then break end end
            assert(ox.blocked and ox.blocked['r84:1'],'the refused door is remembered')
            assert(ox.done and ox.room==58,'it reaches the ultra secret room another way: '..tostring(ox.room))
            -- As few red rooms as it can (the floor needs one Red Key), then as few rooms:
            -- through the boss room above when that saves a red room...
            rooms={}
            add(84); add(71,RoomType.ROOM_BOSS); add(70); add(57); add(58,RoomType.ROOM_ULTRASECRET)
            ox={goals={58},gi=1,room=84,a={center=true},cells=0,done=false,red=true}
            next_,slot=T.planRed(ox,L,84)
            assert(next_==71 and slot==nil,'one red room through the boss room, not two around it')
            -- ...but round it through ordinary rooms when that needs no more red rooms.
            rooms={}
            add(84); add(71,RoomType.ROOM_BOSS); add(85); add(72); add(59); add(58,RoomType.ROOM_ULTRASECRET)
            ox={goals={58},gi=1,room=84,a={center=true},cells=0,done=false,red=true}
            next_,slot=T.planRed(ox,L,84)
            assert(next_==85 and slot==nil,'walks the ordinary rooms to the one beside it: '..tostring(next_))
            dug={}
            for _=1,3000 do T.travel('black',ox,state,L); if ox.done then break end end
            assert(ox.done and ox.room==58 and #dug==1,'one red room door dug in all: '..table.concat(dug,','))
        """)

    def test_praise_counts_with_the_yellow_ox_alone_in_the_room(self):
        self.run_lua(r'''
            local yellow={room=84,goals={69},gi=1,a={center=true},cells=0,done=true}
            local black={room=71,goals={57},gi=1,a={center=true},cells=0,done=true}
            local save={ox={oxen={yellow=yellow,black=black},fields={},trails={},walls={},pieces=true}}
            SaveManagerStub.GetFloorSave=function() return save end
            local rooms,list,here={},{84,71,57,30},84
            local function add(i,t)
                rooms[i]={SafeGridIndex=i,GridIndex=i,ListIndex=i,DisplayFlags=0,
                    Data={Shape=RoomShape.ROOMSHAPE_1x1,Doors=255,Type=t or RoomType.ROOM_DEFAULT}}
            end
            add(84); add(71); add(57,RoomType.ROOM_SECRET); add(30,RoomType.ROOM_ULTRASECRET)
            local L={GetCurrentRoomDesc=function() return rooms[here] end,
                GetRoomByIdx=function(_,i) return rooms[i] or {GridIndex=-1} end,
                GetRooms=function() return {Size=#list,Get=function(_,k) return rooms[list[k+1]] end} end}
            local holder={HasCollectible=function(_,id) return id==OX end}
            Game=function() return {GetLevel=function() return L end,GetNumPlayers=function() return 1 end} end
            Isaac.GetPlayer=function() return holder end
            M.onGameStarted()
            local function praise(kind) M.onConchResult({type=kind or 'positive'}) end
            -- Both oxen in the player's room: the black ox hears it too, so nothing.
            yellow.room,black.room=84,84; praise()
            assert(not black.jealous,'both oxen there')
            -- The yellow ox elsewhere: nothing, wherever the black ox is.
            yellow.room,black.room=71,71; praise()
            assert(not black.jealous,'both oxen in another room')
            yellow.room,black.room=71,57; praise()
            assert(not black.jealous,'the yellow ox in another room')
            -- The yellow ox alone with the player, a negative answer: nothing.
            yellow.room,black.room=84,71; praise('negative')
            assert(not black.jealous,'only praise counts')
            -- Praise of the yellow ox alone: the black ox grows jealous and wakes.
            praise()
            assert(black.jealous and black.red and black.goals[#black.goals]==30,'the ultra secret room becomes its goal')
            assert(not black.done and black.gi==#black.goals,'it wakes and sets off')
            assert(#yellow.goals==1,'the yellow ox does nothing more')
            praise()
            assert(#black.goals==2,'once a floor')
        ''')

    def test_goals_are_the_last_boss_room_and_the_secret_room(self):
        self.run_lua(r'''
            local list={}
            local function room(i,t) local r={SafeGridIndex=i,GridIndex=i,Data={Type=t}}; list[#list+1]=r; return r end
            room(5,RoomType.ROOM_DEFAULT); room(9,RoomType.ROOM_BOSS); room(30,RoomType.ROOM_SUPERSECRET)
            room(31,RoomType.ROOM_SECRET); room(44,RoomType.ROOM_BOSS)
            local L={GetRooms=function() return {Size=#list,Get=function(_,i) return list[i+1] end} end,
                GetLastBossRoomListIndex=function() return 4 end}
            assert(T.bossRoom(L)==44,'the floor\'s last boss room')
            assert(T.secretRoom(L)==31,'the secret room before the super secret room')
            table.remove(list,4)
            L.GetLastBossRoomListIndex=function() return -1 end
            assert(T.bossRoom(L)==9 and T.secretRoom(L)==30,'falls back to any boss room and the super secret room')
            list={list[1]}
            assert(T.secretRoom(L)==nil and T.bossRoom(L)==nil)
        ''')

    def test_effect_lookup_and_floor_pass(self):
        self.run_lua(r'''
            assert(T.variant()==4242 and T.furrowVariant()==4243 and T.riceVariant()==4244,
                'the ox, furrow and rice variants come from entities2.xml by name')
            assert(#errors==0,table.concat(errors,'; '))
            -- Furrows are floor effects the engine draws; the sprouts go through ItemData.
            assert(#callbacks==0 and M.onFloorRender==nil and M.onRenderSprouts==nil and M.onEvaluateCache==nil,
                'nothing is drawn on the holder; the tears go through StatsAPI')
            assert(T.started()==false,'closed until game start without REPENTOGON to say a run is going')
        ''')

    def test_a_holder_is_never_under_curse_of_the_lost(self):
        self.run_lua(r'''
            local holds,dead,removed,shown=true,false,0,0
            local player={HasCollectible=function(_,id) return id==OX and holds end,IsDead=function() return dead end}
            local LOST,DARK=LevelCurse.CURSE_OF_THE_LOST,LevelCurse.CURSE_OF_DARKNESS
            local curses=LOST|DARK
            local lvl={GetCurses=function() return curses end,
                RemoveCurses=function(_,c) curses=curses&~c; removed=removed+1 end,
                UpdateVisibility=function() shown=shown+1 end}
            Game=function() return {GetNumPlayers=function() return 1 end,GetLevel=function() return lvl end} end
            Isaac.GetPlayer=function() return player end
            assert(M.onCurseEval(nil,LOST)==nil,'closed before game start')
            M.onGameStarted()
            assert(M.onCurseEval(nil,LOST|DARK)==DARK,'a new floor never rolls it while held; other curses stay')
            assert(M.onCurseEval(nil,DARK)==nil,'nothing to change without it')
            holds=false
            assert(M.onCurseEval(nil,LOST|DARK)==nil,'not held: the floor keeps its curses')
            holds,dead=true,true
            assert(M.onCurseEval(nil,LOST)==nil,'a dead holder does not count')
            dead=false
            assert(T.evidence().spared==1)
            T.liftLost(lvl)
            assert(curses==DARK and removed==1 and shown==1,'cast during the floor: lifted and the map shown again')
            T.liftLost(lvl)
            assert(removed==1 and T.evidence().lifted==1,'nothing to lift twice')
            M.onPreGameExit()
            assert(M.onCurseEval(nil,LOST)==nil,'closed after the game ends')
        ''')

    def test_the_rat_rider_sits_aims_and_lets_go(self):
        self.run_lua(r'''
            local R=T.ride
            -- The seat follows the ox's pose; facing the camera it is behind the head.
            local x,y,behind=R.saddle('YellowWalk',false)
            assert(x==-8 and y==-21 and not behind,'side: on the back behind the shoulders')
            x=R.saddle('YellowIdle',true)
            assert(x==8,'mirrored with the ox')
            x,y,behind=R.saddle('YellowWalkDown',false)
            assert(x==0 and y==-27 and behind,'facing the camera: behind its head')
            x,y,behind=R.saddle('YellowIdleUp',false)
            assert(x==0 and y==-22 and not behind)
            x,y=R.saddle('YellowSleep',true)
            assert(x==-6 and y==-16,'asleep it is never mirrored')
            -- Aim: the held direction is the larger axis; the values point at the enemy.
            local fire,press=R.aim(30,-40)
            assert(press=='up' and math.abs(fire.up-0.8)<1e-9 and math.abs(fire.right-0.6)<1e-9 and fire.left==0 and fire.down==0)
            fire,press=R.aim(-50,10)
            assert(press=='left' and fire.left>0.9 and fire.down>0)
            assert(R.aim(0,0)==nil,'no direction at the very same spot')
            -- A charge weapon is let go only once full.
            assert(R.charged(100,100) and R.charged(120,100))
            assert(not R.charged(99,100) and not R.charged(0,0) and not R.charged(nil,100))
            assert(R.arc(0)==0 and math.abs(R.arc(0.5)+M.data.rideArc)<1e-9 and math.abs(R.arc(1))<1e-9,'a hop rises and lands')
            -- While riding, the rider's own keys are not its own; the holder's are untouched.
            local holder,rider={hash=1},{hash=2}
            assert(M.onInputAction(nil,rider,InputHook.GET_ACTION_VALUE,ButtonAction.ACTION_LEFT)==nil,'nobody rides')
            R.rider={hash=2,fire={left=0,right=0.6,up=0.8,down=0},press='up'}
            assert(M.onInputAction(nil,rider,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_LEFT)==false)
            assert(M.onInputAction(nil,rider,InputHook.GET_ACTION_VALUE,ButtonAction.ACTION_DOWN)==0)
            assert(M.onInputAction(nil,rider,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_BOMB)==false)
            assert(M.onInputAction(nil,rider,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_SHOOTUP)==true)
            assert(M.onInputAction(nil,rider,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_SHOOTRIGHT)==false,'one held direction')
            assert(M.onInputAction(nil,rider,InputHook.GET_ACTION_VALUE,ButtonAction.ACTION_SHOOTRIGHT)==0.6)
            assert(M.onInputAction(nil,rider,InputHook.IS_ACTION_TRIGGERED,ButtonAction.ACTION_SHOOTUP)==false)
            assert(M.onInputAction(nil,rider,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_MAP)==nil,'other keys stay the engine one')
            assert(M.onInputAction(nil,holder,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_LEFT)==nil,'the holder keeps every key')
            -- On the ox it takes no damage; nobody else is shielded.
            assert(M.onRiderDamage(nil,rider)==false and M.onRiderDamage(nil,holder)==nil)
            R.rider=nil
            assert(M.onRiderDamage(nil,rider)==nil)
        ''')

    def test_registry_text_and_entity_follow_the_design(self):
        items = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        block = items[items.index('    OX = {'):]
        block = block[:block.index('\n    },')]
        self.assertNotIn('WorkingNow', block)
        self.assertIn('id = Isaac.GetItemIdByName("Ox")', block)
        self.assertIn('COLLECTIBLE_AQUARIUS', block)
        self.assertIn('flag = "positive"', block)
        self.assertIn('cache = "damage firedelay"', block)
        self.assertNotIn('stackable', block, 'one pair of oxen however many copies')
        self.assertIn('[{ type = "collectible", name = "Rat" }] = "rat"', block)
        for hook in ('postUpdate = "ox.onUpdate"', 'postCurseEval = "ox.onCurseEval"', 'postNewRoom = "ox.onNewRoom"',
                     'inputAction = "ox.onInputAction"', 'entityTakeDmg = "ox.onRiderDamage"',
                     'gameStarted = "ox.onGameStarted"', 'preGameExit = "ox.onPreGameExit"', 'preModUnload = "ox.onModUnload"'):
            self.assertIn(hook, block)
        self.assertNotIn('evaluateCache', block)
        self.assertNotIn('postRoomRenderEntities', block, 'nothing is drawn on the holder (user request 2026-10-31)')
        defs = (ROOT / 'scripts/entities/definitions.lua').read_text(encoding='utf-8')
        self.assertIn('name = "Conch Blessing Ox", id = 1000', defs)
        for path in ('effects/conch_ox.anm2', 'effects/conch_ox_furrow.anm2', 'effects/conch_ox_directions.png',
                     'effects/conch_ox_furrow.png', 'effects/conch_ox_sleep_equipped.png'):
            self.assertTrue((ROOT / 'resources/gfx' / path).is_file(), path)
        anm2 = (ROOT / 'resources/gfx/effects/conch_ox.anm2').read_text(encoding='utf-8')
        for name in ('YellowWalk', 'YellowIdle', 'BlackWalk', 'BlackIdle', 'YellowSleep', 'BlackSleep',
                     'YellowWalkUp', 'YellowWalkDown', 'YellowIdleUp', 'YellowIdleDown',
                     'BlackWalkUp', 'BlackWalkDown', 'BlackIdleUp', 'BlackIdleDown'):
            self.assertIn(f'Name="{name}"', anm2)
        furrow = (ROOT / 'resources/gfx/effects/conch_ox_furrow.anm2').read_text(encoding='utf-8')
        self.assertIn('FrameNum="96"', furrow, '24 quarters of the line, two variants a colour')
        self.assertIn('Width="26" Height="26" XPivot="13" YPivot="13"', furrow, 'one floor tile, centred on the cell')
        rice = (ROOT / 'resources/gfx/effects/conch_ox_rice.anm2').read_text(encoding='utf-8')
        self.assertIn('Name="Grow" FrameNum="20" Loop="false"', rice, 'five stages, four ticks each')
        self.assertIn('Name="Idle" FrameNum="40" Loop="true"', rice)
        self.assertIn('name = "Conch Blessing Ox Rice", id = 1000, variant = 7785', defs)
        self.assertFalse((ROOT / 'resources/gfx/effects/conch_ox_sprout.anm2').exists(), 'no sprouts on the holder')
        self.assertIn('Path="conch_ox_sleep_equipped.png"', anm2, 'the sleeping pose has its own sheet and layer')
        self.assertIn('Path="conch_ox_directions.png"', anm2)
        self.assertIn('name = "Conch Blessing Ox Furrow", id = 1000, variant = 7784', defs)
        self.assertIn('shadowSize = 0', defs[defs.index('OX_FURROW'):], 'a furrow casts no shadow')
        # The Korean text is the user's copy (2026-10-31), word for word; its
        # numbers are the module's numbers.
        kr = (ROOT / 'scripts/locale/kr.lua').read_text(encoding='utf-8')
        for line in ('"누렁소는 보스방으로, 검은소는 비밀방과 일급비밀방으로 걸어갑니다",',
                     '"#누렁소의 고랑에서는 {{Damage}}데미지, 검은소의 도랑에서는 {{Tears}}연사가 2배가 됩니다",',
                     '"#고랑과 도랑이 겹친 곳에 벼가 자라며, 밟으면 둘 다 2배가 되고 벗어나도 2초간 유지됩니다",',
                     '"#누렁소만 있는 방에서 소라고둥 긍정을 띄우면 검은소가 질투하여 빨간 비밀방을 향해 나아갑니다",',
                     '"분신이 누렁소 위에 타서 자동으로 적을 공격합니다.",'):
            self.assertIn(line, kr)
        for lang, warning in (('en', 'REPENTOGON recommended'), ('kr', 'REPENTOGON 권장'),
                              ('urimal', '덧붙임 도우미(REPENTOGON)를 쓰면 좋습니다')):
            text = (ROOT / f'scripts/locale/{lang}.lua').read_text(encoding='utf-8')
            entry = text[text.index('        OX = {'):]
            entry = entry[:entry.index('            synergies = {')]
            self.assertEqual(len(re.findall(r'^\s+"', entry, re.M)), 5, lang)
            self.assertIn(warning, entry, lang)
            self.assertNotIn('(WIP)', entry, lang)


if __name__ == '__main__':
    unittest.main()
