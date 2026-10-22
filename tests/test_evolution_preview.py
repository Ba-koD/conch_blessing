"""Evolution preview contracts: production Lua with engine doubles.

The branch tree (scripts/lib/upgrade_branch_preview.lua) and its range/hop
lifecycle (scripts/conch_blessing_highlight.lua). These checks prove layout,
timing, ownership and cleanup; the in-game look stays a user-reviewed LOOK
check (conch_test evolution).
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class EvolutionPreviewTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            callbacks={}; errors={}; renders={}; texts={}
            ModCallbacks={MC_POST_UPDATE=1,MC_POST_RENDER=2,MC_POST_NEW_ROOM=3,MC_POST_GAME_STARTED=4,
                MC_PRE_GAME_EXIT=5,MC_POST_NEW_LEVEL=6,MC_POST_PICKUP_INIT=7,MC_POST_PICKUP_UPDATE=8,MC_PRE_MOD_UNLOAD=9}
            PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_TRINKET=350}
            EntityType={ENTITY_PICKUP=5}
            RoomType={ROOM_DEFAULT=1,ROOM_TREASURE=4}
            StageType={STAGETYPE_ORIGINAL=0,STAGETYPE_REPENTANCE=4,STAGETYPE_REPENTANCE_B=5}
            LevelCurse={CURSE_OF_BLIND=64}
            function Vector(x,y) return {X=x,Y=y} end
            function Color(r,g,b,a,ro,go,bo) return {R=r,G=g,B=b,A=a or 1,RO=ro or 0,GO=go or 0,BO=bo or 0} end
            function KColor(r,g,b,a) return {R=r,G=g,B=b,A=a} end
            function GetPtrHash(e) return e.hash end
            EntityPtr=setmetatable({}, {__call=function(_,e)
                local generation=e.generation
                return setmetatable({}, {__index=function(_,k)
                    if k=='Ref' and e:Exists() and e.generation==generation then return e end
                end})
            end})
            curses,stageType,roomType,frame,hudVisible=0,0,1,0,true
            players={}
            local level={GetCurses=function() return curses end,GetStageType=function() return stageType end}
            local room={GetType=function() return roomType end}
            game={GetFrameCount=function() return frame end,GetLevel=function() return level end,
                GetRoom=function() return room end,GetNumPlayers=function() return #players end,
                GetHUD=function() return {IsVisible=function() return hudVisible end} end}
            function Game() return game end
            missingArt={}
            config={GetCollectible=function(_,id) if missingArt[id] then return nil end return {GfxFileName='c'..id..'.png'} end,
                GetTrinket=function(_,id) return {GfxFileName='t'..id..'.png'} end}
            entities={}
            Isaac={GetItemConfig=function() return config end,WorldToScreen=function(p) return Vector(p.X,p.Y) end,
                GetPlayer=function(i) return players[i+1] end,GetFrameCount=function() return frame end,
                GetRoomEntities=function()
                    local live={}
                    for _,e in ipairs(entities) do if e:Exists() then live[#live+1]=e end end
                    return live
                end,
                Spawn=function() error('cosmetics cannot spawn entities') end,
                GetTextWidth=function(s) return #s*6 end,RenderText=function() error('needs the scalable font') end}
            math.random=function() error('cosmetics cannot consume RNG') end
            -- One render record per Sprite:Render; colour is copied by value.
            function newSprite()
                local s={Scale=Vector(1,1),Rotation=0,Color=Color(1,1,1,1)}
                function s:Load(path) self.path=path end
                function s:ReplaceSpritesheet(_,sheet) self.sheet=sheet end
                function s:LoadGraphics() end
                function s:SetFrame() end
                function s:IsLoaded() return true end
                function s:Render(p)
                    local c=self.Color
                    renders[#renders+1]={path=self.path,sheet=self.sheet,x=p.X,y=p.Y,sx=self.Scale.X,sy=self.Scale.Y,
                        color={c.R,c.G,c.B,c.A,c.RO,c.GO,c.BO}}
                end
                return s
            end
            Sprite=setmetatable({}, {__call=function() return newSprite() end})
            fontMissing=false
            Font=setmetatable({}, {__call=function() return {
                Load=function() if fontMissing then error('font missing') end end,IsLoaded=function() return true end,
                GetLineHeight=function() return 12 end,
                GetStringWidthUTF8=function(_,t) return utf8.len(t)*8 end,
                DrawStringScaledUTF8=function(_,t,x,y,sx,sy,c) texts[#texts+1]={text=t,x=x,y=y,scale=sx,r=c.R,g=c.G,b=c.B,a=c.A} end} end})
            local kr=require('scripts.locale.kr'); local en=require('scripts.locale.en')
            local function textIn(lang,path,...)
                local v=lang=='kr' and kr or en
                for key in path:gmatch('[^.]+') do v=v[key] end
                return string.format(v,...)
            end
            ConchBlessing={printError=function(s) errors[#errors+1]=s end,
                AddCallback=function(_,id,fn) callbacks[id]=callbacks[id] or {}; table.insert(callbacks[id],fn) end,
                Locale={textIn=textIn,text=function(path,...) return textIn('kr',path,...) end}}
            function event(id,...) for _,f in ipairs(callbacks[id] or {}) do f(nil,...) end end
            -- Libra (304) has all three answers, Dead Eye (373) one, Perfection (T145) two.
            local function m(flag,id,kind) return {upgradeId=id,flag=flag,itemData={type=kind or 'passive'}} end
            ConchBlessing.ItemMaps={
                ['C:304']={positive=m('positive',801),neutral=m('neutral',802),negative=m('negative',803)},
                ['C:373']={positive=m('positive',804)},
                ['T:145']={positive=m('positive',91,'trinket'),negative=m('negative',92,'trinket')},
            }
            nextHash=1
            -- A native pickup: its own sprite with a settable item layer.
            function spawn(variant,id,x,y)
                local p={Type=5,Variant=variant,SubType=id,Position=Vector(x or 320,y or 200),SpriteOffset=Vector(0,0),
                    InitSeed=700+nextHash,hash=nextHash,generation=0,alive=true,Touched=false}
                nextHash=nextHash+1
                local layers={}
                p.sprite={Color=Color(1,1,1,1),Offset=Vector(0,0),animation='Idle'}
                function p.sprite:GetAnimation() return self.animation end
                function p.sprite:GetLayer(name)
                    if noLayerApi then return {GetPos=function() return Vector(0,0) end} end
                    layers[name]=layers[name] or {pos=Vector(0,0),size=Vector(1,1),name=name,writes=0}
                    local l=layers[name]
                    function l:GetPos() return self.pos end
                    function l:GetSize() return self.size end
                    function l:SetPos(v) self.pos=Vector(v.X,v.Y); self.writes=self.writes+1 end
                    function l:SetSize(v) self.size=Vector(v.X,v.Y); self.writes=self.writes+1 end
                    return l
                end
                p.layers=layers
                function p:Exists() return self.alive end
                function p:ToPickup() return self end
                function p:GetSprite() return self.sprite end
                function p:Remove() self.alive=false end
                entities[#entities+1]=p
                return p
            end
            function layer(p) return p.sprite:GetLayer(p.Variant==100 and 'head' or 'body') end
            function player(x,y) local pl={Position=Vector(x,y)}; players[#players+1]=pl; return pl end
            function tick(n) for _=1,n or 1 do frame=frame+1; event(1) end end
            hostLoaded=package.loaded; package=nil
            P=require('scripts.lib.upgrade_branch_preview')
            View=require('scripts.lib.conch_answer_view')
            H=require('scripts.conch_blessing_highlight')
        ''')

    # ------------------------------------------------------------- layout
    def test_plain_tree_is_centred_axis_aligned_in_answer_order(self):
        self.lua.execute('''
            local function layoutOf(flags)
                local results={}
                for i,f in ipairs(flags) do results[i]={flag=f,id=800+i} end
                return P.layout({{results=results}},false)
            end
            local expect={[1]={0},[2]={-13,13},[3]={-26,0,26}}
            local ends={[1]=15,[2]=17,[3]=19}
            local sets={{'neutral'},{'positive','negative'},{'positive','neutral','negative'}}
            for n,flags in ipairs(sets) do
                local L=layoutOf(flags)
                assert(#L.icons==n and L.openEnd==ends[n], n)
                for i,icon in ipairs(L.icons) do
                    assert(icon.x==expect[n][i] and icon.y==-21, n..':'..icon.x)
                    assert(icon.label==flags[i] and icon.rgb==View.colors[flags[i]])
                    -- Its own answer-coloured stem ends exactly under it.
                    local stem
                    for _,l in ipairs(L.lines) do if l.x==icon.x and l.dy==-1 and l.rgb==icon.rgb then stem=l end end
                    assert(stem and stem.y-stem.length==icon.y+icon.half, 'stem meets icon')
                end
                for _,l in ipairs(L.lines) do
                    assert((l.dx==0)~=(l.dy==0), 'only straight segments')
                    assert(l.x==math.floor(l.x) and l.y==math.floor(l.y) and l.length==math.floor(l.length), 'whole pixels')
                end
            end
        ''')

    def test_rotating_tree_hangs_each_choice_over_its_own_results(self):
        self.lua.execute('''
            local L=P.layout({
                {source={id=373},results={{flag='positive',id=804}}},
                {source={id=304},results={{flag='positive',id=801},{flag='neutral',id=802},{flag='negative',id=803}}},
            },true)
            local sources,results={},{}
            for _,icon in ipairs(L.icons) do
                if icon.label then results[#results+1]=icon else sources[#sources+1]=icon end
            end
            assert(#sources==2 and #results==4 and L.openEnd==31)
            assert(sources[1].x==-42 and sources[2].x==16 and sources[1].id==373 and sources[2].id==304)
            assert(results[1].x==-42 and results[2].x==-10 and results[3].x==16 and results[4].x==42)
            for i=1,#results do
                assert(results[i].y==-45 and results[i].y+results[i].half<sources[1].y-sources[1].half, 'results above choices')
                for j=i+1,#results do assert(math.abs(results[i].x-results[j].x)>=24, 'result icons never overlap') end
            end
            for _,l in ipairs(L.lines) do assert((l.dx==0)~=(l.dy==0)) end
        ''')

    def test_render_draws_only_grown_parts_borders_first(self):
        self.lua.execute('''
            local L=P.layout({{results={{flag='positive',id=801},{flag='neutral',id=802},{flag='negative',id=803}}}},false)
            renders={}; texts={}
            local d=P.render(L,100,100,0)
            assert(#renders==0 and #texts==0 and d.icons==0)
            d=P.render(L,100,100,L.openEnd)
            assert(d.icons==3 and d.labels==3 and d.lines==#L.lines)
            -- Every border rectangle precedes every core rectangle.
            local lastBorder,firstCore=0,math.huge
            for i,r in ipairs(renders) do
                if r.path:find('pixel') then
                    if r.color[1]==0 and r.color[4]==0.6 then lastBorder=i else firstCore=math.min(firstCore,i) end
                end
            end
            assert(lastBorder<firstCore)
            -- Four flat answer-coloured copies, then the icon itself.
            local icons={}
            for _,r in ipairs(renders) do if r.sheet then icons[#icons+1]=r end end
            assert(#icons==15)
            for k=0,2 do
                local flag=({'positive','neutral','negative'})[k+1]
                for j=1,4 do
                    local c=icons[k*5+j].color
                    assert(c[1]==0 and c[5]==View.colors[flag][1] and c[6]==View.colors[flag][2] and c[7]==View.colors[flag][3])
                end
                assert(icons[k*5+5].color[1]==1 and icons[k*5+5].sx==0.75)
            end
            assert(texts[1].text=='긍정' and texts[3].text=='중립' and texts[5].text=='부정', texts[1].text)
            -- Partway open: the trunk only, no icon yet.
            renders={}; texts={}
            d=P.render(L,100,100,2)
            assert(d.icons==0 and d.lines==1 and #texts==0)
            assert(#errors==0, table.concat(errors,'; '))
        ''')

    def test_missing_art_or_font_degrades_without_hiding_the_tree(self):
        self.lua.execute('''
            missingArt[802]=true
            local L=P.layout({{results={{flag='positive',id=801},{flag='neutral',id=802}}}},false)
            for _=1,3 do P.render(L,0,0,L.openEnd) end
            assert(#errors==1 and errors[1]:find('ICON_UNAVAILABLE'), tostring(errors[1]))
            local d=P.render(L,0,0,L.openEnd)
            assert(d.icons==1 and d.lines==#L.lines)
        ''')
        self.lua.execute('''
            errors={}; fontMissing=true; package=nil
            hostLoaded['scripts.lib.conch_answer_view']=nil
            hostLoaded['scripts.lib.upgrade_branch_preview']=nil
            local V2=require('scripts.lib.conch_answer_view')
            local P2=require('scripts.lib.upgrade_branch_preview')
            local L=P2.layout({{results={{flag='positive',id=801}}}},false)
            texts={}
            local d=P2.render(L,0,0,L.openEnd)
            assert(d.icons==1 and d.labels==0 and #texts==0, 'no unscaled fallback text over the room')
        ''')

    # ---------------------------------------------------------- lifecycle
    def test_range_opens_holds_and_closes_with_hysteresis(self):
        self.lua.execute('''
            local p=spawn(100,304,320,200); local pl=player(320,400)
            H.ScanRoom(frame)
            local rec=assert(H.previewFor(p))
            tick(40); assert(rec.t==0 and not rec.open)
            pl.Position=Vector(320,260)               -- 60 away: open
            tick(1); assert(rec.open and rec.t==1)
            tick(400); assert(rec.open and rec.t==rec.layout.openEnd, 'stays open while near')
            pl.Position=Vector(320,275)               -- 75: inside the closing distance
            tick(30); assert(rec.open)
            pl.Position=Vector(320,290)               -- 90: closes
            tick(1); assert(not rec.open)
            tick(20); assert(rec.t==0)
            pl.Position=Vector(320,250); tick(1)
            assert(rec.opens==2 and H.previewFor(p)==rec)
            -- Rendering follows the open state only.
            renders={}; event(2); assert(#renders>0)
            pl.Position=Vector(320,400); tick(30); renders={}; event(2); assert(#renders==0)
            -- A co-op partner standing near opens it too.
            player(330,230); tick(1); assert(rec.open)
            assert(#errors==0, table.concat(errors,'; '))
        ''')

    def test_hop_borrows_only_the_item_layer_and_restores_it_exactly(self):
        self.lua.execute('''
            local p=spawn(100,304); player(320,600)
            local l=layer(p); l.pos=Vector(0.5,-1); l.size=Vector(1.1,0.9)
            local spriteColor,offset=p.sprite.Color,p.SpriteOffset
            H.ScanRoom(frame)
            local seen={}
            for _=1,200 do
                tick(1)
                seen[#seen+1]=l.pos.Y
                assert(l.pos.X==0.5, 'the hop is vertical only')
            end
            local moved=0
            for _,y in ipairs(seen) do if y~=-1 then moved=moved+1 end end
            -- Two hops (7px, then 5px), a rest as long, and again with no limit; whole pixels.
            assert(moved>40, moved)
            local rec=H.previewFor(p)
            assert(rec.hops>=5, 'hops '..rec.hops)
            local lowest=0
            for _,y in ipairs(seen) do lowest=math.min(lowest,y+1); assert(y==math.floor(y), 'whole pixels') end
            assert(lowest==-7)
            assert(p.sprite.Color==spriteColor and p.SpriteOffset==offset, 'pedestal and colour untouched')
            -- Mid-hop boundaries restore the exact layer.
            for _,ev in ipairs({5,3,9,4}) do
                H.ScanRoom(frame)
                local rec=assert(H.previewFor(p))
                repeat tick(1) until rec.hop and l.pos.Y~=-1
                event(ev,ConchBlessing)
                assert(l.pos.X==0.5 and l.pos.Y==-1 and l.size.X==1.1 and l.size.Y==0.9, 'event '..ev)
            end
            assert(#errors==0, table.concat(errors,'; '))
        ''')

    def test_hop_stays_in_place_whichever_side_the_player_is_on(self):
        self.lua.execute('''
            local p=spawn(100,304,320,200); local pl=player(450,320)
            local l=layer(p); l.rot=10
            function l:GetRotation() return self.rot end
            function l:SetRotation(v) self.rot=v end
            H.ScanRoom(frame)
            for _,x in ipairs({450,190,322}) do
                pl.Position=Vector(x,320)
                local high=0
                for _=1,70 do
                    tick(1); high=math.min(high,l.pos.Y)
                    assert(l.pos.X==0 and l.rot==10, 'no step or tilt toward x='..x)
                end
                assert(high==-7, 'it still hops 7px')
            end
        ''')

    def test_open_tree_sends_a_spark_to_each_result_and_pops_it(self):
        self.lua.execute('''
            local L=P.layout({{results={{flag='positive',id=801},{flag='neutral',id=802},{flag='negative',id=803}}}},false)
            local every=P._test.SPARK_EVERY
            local reached={}
            for clock=0,3*every-1 do
                local m=P.idle(L,clock)
                local target=L.icons[math.floor(clock/every)%3+1]
                if m.spark then
                    assert(m.spark.rgb==target.rgb, 'spark takes its result colour')
                    -- Always on the drawn branches: the trunk, the bar or that stem.
                    local x,y=m.spark.x,m.spark.y
                    assert((x==0 and y<=0 and y>=-5) or (y==-5 and math.abs(x)<=26) or (x==target.x and y<=-5 and y>=-9),
                        x..','..y)
                    if x==target.x and y==-9 then reached[target]=true end
                end
                if m.pop then assert(m.pop.icon==target and m.pop.scale>1 and m.pop.flash>0) end
            end
            for i=1,3 do assert(reached[L.icons[i]], 'the spark reaches result '..i) end
            -- Drawing: the white core over its coloured halo, a bigger brighter icon on a pop.
            renders={}
            local d=P.render(L,100,100,L.openEnd,1)
            assert(d.sparks==1)
            local white=false
            for _,r in ipairs(renders) do if r.path:find('pixel') and r.sx==1 and r.color[1]==1 and r.color[2]==1 then white=true end end
            assert(white)
            local popClock
            for c=0,every-1 do if P.idle(L,c).pop then popClock=c; break end end
            renders={}
            d=P.render(L,100,100,L.openEnd,popClock+3)
            assert(d.pops==1)
            local big=false
            for _,r in ipairs(renders) do if r.sheet=='c801.png' and r.sx>0.75 and r.color[1]==1 and r.color[5]>0 then big=true end end
            assert(big, 'the reached result pops and flashes')
            -- Not while still growing, and not without a clock.
            assert(next(P.idle(L,nil))==nil)
            renders={}; d=P.render(L,100,100,L.openEnd-1,1); assert(d.sparks==0 and d.pops==0)
        ''')

    def test_a_native_turn_seen_mid_init_neither_ends_nor_restarts_the_tree(self):
        self.lua.execute('''
            player(320,240)
            local p=spawn(100,7,320,200)
            local queue={373,304}
            function p:GetCollectibleCycle() return queue end
            H.ScanRoom(frame); tick(40)
            local rec=assert(H.previewFor(p)); assert(rec.layout.tree and rec.t==rec.layout.openEnd)
            -- Inside the turn's init callback the head has moved on but the
            -- queue has not, then it is briefly empty.
            p.generation=p.generation+1; p.SubType=373
            event(7,p); assert(H.previewFor(p)==rec)
            queue={}; event(7,p); assert(H.previewFor(p)==rec)
            queue={304,7}; event(8,p); tick(1)
            assert(H.previewFor(p)==rec and rec.opens==1 and rec.t==rec.layout.openEnd, 'one tree through the turn')
            -- A real change is still caught after the update.
            p.SubType=25; queue={}; tick(1)
            assert(not H.previewFor(p))
            p.SubType=304; tick(1); event(8,p)
            assert(H.previewFor(p) and H.previewFor(p).identity=='C:304')
        ''')

    def test_no_hop_while_open_or_without_the_layer_api(self):
        self.lua.execute('''
            local p=spawn(100,304); local pl=player(320,230)
            H.ScanRoom(frame); tick(200)
            assert(layer(p).writes==0, 'an open tree never hops')
            noLayerApi=true
            local q=spawn(100,373,600,200); pl.Position=Vector(320,900)
            H.ScanRoom(frame); tick(200)
            assert(H.previewFor(q) and #errors==0)
        ''')

    def test_upgrade_ends_the_tree_and_restores_the_layer_first(self):
        self.lua.execute('''
            local p=spawn(100,304); player(320,600)
            local l=layer(p)
            H.ScanRoom(frame)
            local rec=H.previewFor(p)
            repeat tick(1) until rec.hop and l.pos.Y~=0
            -- The queue calls StopForPickup before any template snapshot.
            H.StopForPickup(p)
            assert(not H.previewFor(p) and l.pos.Y==0 and l.size.X==1 and l.size.Y==1)
            local morphing=true
            ConchBlessing.upgrade={isAnimatingPickup=function(x) return x==p and morphing end}
            H.ScanRoom(frame); event(8,p); tick(120)
            assert(not H.previewFor(p) and l.pos.Y==0, 'nothing while the upgrade runs')
            -- The committed result (Ceil) is not an origin; a chained one is.
            p.SubType=801; morphing=false; H.ScanRoom(frame); assert(not H.previewFor(p))
            p.SubType=373; H.ScanRoom(frame); assert(H.previewFor(p).identity=='C:373')
            -- A preview already running ends when an upgrade starts.
            local q=spawn(100,304,500,200); H.ScanRoom(frame)
            local r=H.previewFor(q); repeat tick(1) until r.hop and layer(q).pos.Y~=0
            ConchBlessing.upgrade.isAnimatingPickup=function(x) return x==q end
            tick(1); assert(not H.previewFor(q) and layer(q).pos.Y==0)
            local ended
            for _,e in ipairs(H.previewEvents()) do if e.event=='END' and e.hash==tostring(q.hash) then ended=e.detail end end
            assert(ended=='upgrade', tostring(ended))
        ''')

    def test_hidden_pickups_never_reveal_their_results(self):
        self.lua.execute('''
            player(320,230)
            curses=64
            local p=spawn(100,304); H.ScanRoom(frame); assert(not H.previewFor(p), 'Curse of the Blind')
            p.Touched=true; H.ScanRoom(frame); assert(H.previewFor(p), 'a dropped item is seen')
            local t=spawn(350,145,500,200); H.ScanRoom(frame); assert(H.previewFor(t), 'trinkets are never blind')
            curses=0
            -- Without IsBlind an alternate-path treasure room shows nothing.
            roomType,stageType=4,4
            local q=spawn(100,373,600,200); H.ScanRoom(frame); assert(not H.previewFor(q))
            roomType,stageType=1,0
            -- With IsBlind the engine answers, and a pedestal turning blind ends its tree.
            local blind=false
            local r=spawn(100,373,700,200); function r:IsBlind() return blind end
            H.ScanRoom(frame); assert(H.previewFor(r))
            roomType,stageType=4,4; tick(1); assert(H.previewFor(r), 'IsBlind outranks the room guess')
            blind=true; tick(1); assert(not H.previewFor(r))
            renders={}; texts={}; event(2)
            for _,d in ipairs(renders) do assert(d.sheet~='c804.png', 'Live Eye leaked') end
        ''')

    def test_rotating_pedestal_keeps_one_tree_through_turns(self):
        self.lua.execute('''
            local pl=player(320,240)
            local p=spawn(100,7,320,200)
            local circle={7,373,304,373}
            local head=1
            function p:GetCollectibleCycle()
                local q={}
                for i=1,#circle-1 do q[i]=circle[(head+i-1)%#circle+1] end
                return q
            end
            local function turn() head=head%#circle+1; p.SubType=circle[head] end
            H.ScanRoom(frame)
            local rec=assert(H.previewFor(p))
            assert(rec.layout.tree and #rec.groups==2, 'one group per evolvable choice')
            assert(rec.groups[1].source.id==373 and rec.groups[2].source.id==304, 'canonical circle order, each choice once')
            tick(10)
            for _=1,8 do
                turn(); event(8,p); tick(4)
                assert(H.previewFor(p)==rec and rec.opens==1, 'a turn neither restarts nor reopens')
            end
            -- A turn that renews the entity (expired EntityPtr) is followed.
            pl.Position=Vector(320,900); tick(40)
            repeat tick(1) until rec.hop and layer(p).pos.Y~=0
            p.generation=p.generation+1; turn()
            tick(1); assert(H.previewFor(p)==rec)
            event(8,p)
            assert(H.previewFor(p)==rec and layer(p).pos.Y==0, 'a borrowed hop is put back on rebinding')
            tick(200); assert(H.previewFor(p)==rec)
            -- Without the cycle API it is read as the shown choice.
            p.GetCollectibleCycle=nil; p.SubType=304; tick(1)
            assert(not H.previewFor(p) or H.previewFor(p).identity=='C:304')
        ''')

    def test_reroll_and_removal_end_the_old_tree(self):
        self.lua.execute('''
            player(320,230)
            local p=spawn(100,304); H.ScanRoom(frame); local rec=H.previewFor(p)
            tick(30); p.SubType=25; tick(1)
            assert(not H.previewFor(p))
            p.SubType=373; event(8,p)
            local next=H.previewFor(p); assert(next and next~=rec and next.identity=='C:373' and next.t==0)
            p:Remove(); tick(1)
            renders={}; event(2); assert(#renders==0)
            assert(#errors==0, table.concat(errors,'; '))
        ''')

    def test_viewer_fixtures_are_left_to_the_viewer(self):
        self.lua.execute('''
            player(320,230)
            local p=spawn(100,304)
            ConchBlessing.morphViewer={ownsPickup=function(x) return x==p end}
            H.ScanRoom(frame); event(8,p); tick(100)
            assert(not H.previewFor(p) and layer(p).writes==0)
        ''')

    def test_bench_registers_one_command_and_builds_every_stage(self):
        self.lua.execute('''
            local defs={}
            hostLoaded['scripts.dev.test_bench']={register=function(def) defs[#defs+1]=def end}
            hostLoaded['scripts.lib.upgrade_visuals']={origin=function(item)
                return item.type=='trinket' and 350 or 100, item.originId end}
            ConchBlessing.ItemData={CEIL={id=801,flag='positive',type='passive',origin={},originId=304},
                LIVE_EYE={id=804,flag='positive',type='passive',origin={},originId=373},
                TIME_LUCK={id=91,flag='positive',type='trinket',origin={},originId=145}}
            local probe=require('scripts.dev.evolution_probe')
            assert(#defs==1 and defs[1].command=='conch_test evolution' and defs[1].cleanup)
            local sections,ops={},0
            local plan=setmetatable({}, {__index=function(_,kind)
                return function(a,b) ops=ops+1; if kind=='section' then sections[#sections+1]=a end end
            end})
            defs[1].build(plan)
            assert(#sections==6 and ops>60, #sections..' sections, '..ops..' steps')
            -- The oracle reads ItemData declarations, in answer order.
            ConchBlessing.ItemData.ROUND={id=802,flag='neutral',type='passive',origin={},originId=304}
            local list=probe.expectedResults(100,304)
            assert(#list==2 and list[1].id==801 and list[2].id==802)
        ''')

    def test_hidden_hud_draws_nothing(self):
        self.lua.execute('''
            player(320,230); local p=spawn(100,304); H.ScanRoom(frame); tick(40)
            hudVisible=false; renders={}; event(2); assert(#renders==0)
            hudVisible=true; event(2); assert(#renders>0)
        ''')


if __name__ == '__main__':
    unittest.main()
