"""Conch Pearl's production pool filter and dust visual with engine doubles.

The pool double fires the module's MC_POST_GET_COLLECTIBLE handler for every
draw, the way the engine does, so nested redraws run through the real guard.
No in-game image or real pool weights are claimed here.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class ConchPearlTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            errors,debugs={}, {}
            RoomType={ROOM_SHOP=2,ROOM_TREASURE=4,ROOM_BOSS=5,ROOM_SECRET=7,ROOM_SUPERSECRET=8,
                ROOM_CURSE=10,ROOM_LIBRARY=12,ROOM_DEVIL=14,ROOM_ANGEL=15,ROOM_PLANETARIUM=24,ROOM_ULTRASECRET=29}
            ItemPoolType={POOL_TREASURE=0,POOL_SHOP=1,POOL_BOSS=2,POOL_DEVIL=3,POOL_ANGEL=4,POOL_SECRET=5,
                POOL_LIBRARY=6,POOL_CURSE=12,POOL_ULTRA_SECRET=24,POOL_PLANETARIUM=26}
            ItemConfig={TAG_QUEST=1<<15}
            PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_HEART=10}
            LevelCurse={CURSE_OF_BLIND=64}
            StageType={STAGETYPE_ORIGINAL=0,STAGETYPE_REPENTANCE=4,STAGETYPE_REPENTANCE_B=5}
            -- Vanilla qualities: 1-2 low, 3 is quality 2, 4/5 high, 6 a quality 0 quest item.
            qualities={[1]=0,[2]=1,[3]=2,[4]=3,[5]=4,[6]=0,[7]=2,
                [900]=4,[901]=4,[902]=4,[903]=4,[904]=4,[905]=4,[906]=0,[907]=0,[908]=4,[909]=0}
            quests={[6]=true}
            config={GetCollectible=function(_,id)
                local q=qualities[id]
                if q==nil then return nil end
                return {Quality=q,GfxFileName='gfx/items/'..id..'.png',
                    HasTags=function(_,tag) return tag==ItemConfig.TAG_QUEST and quests[id]==true end}
            end}
            local function player(items)
                local p={items=items or {},dead=false,ghost=false}
                function p:HasCollectible(id) return (self.items[id] or 0)>0 end
                function p:IsDead() return self.dead end
                function p:IsCoopGhost() return self.ghost end
                return p
            end
            newPlayer=player
            players={player({[900]=1})}
            -- The engine's draw: pick the scripted ID, then run POST_GET_COLLECTIBLE.
            script,defaultDraw,poolCalls,removed,nested={},5,{}, {}, {}
            poolError=nil
            pool={
                GetCollectible=function(_,poolType,decrease,seed)
                    if poolError then error(poolError) end
                    local id=table.remove(script,1) or defaultDraw
                    poolCalls[#poolCalls+1]={poolType=poolType,decrease=decrease,seed=seed,id=id}
                    nested[#nested+1]=M.onPostGetCollectible(nil,id,poolType,decrease,seed)
                    return nested[#nested] or id
                end,
                RemoveCollectible=function(_,id) removed[#removed+1]=id end,
            }
            curses,stageType,roomType=0,0,1
            level={GetCurses=function() return curses end,GetStageType=function() return stageType end}
            room={GetType=function() return roomType end}
            game={GetNumPlayers=function() return #players end,GetItemPool=function() return pool end,
                GetLevel=function() return level end,GetRoom=function() return room end}
            Game=function() return game end
            Isaac={GetItemIdByName=function(name) assert(name=='Conch Pearl'); return 900 end,
                GetItemConfig=function() return config end,
                GetPlayer=function(i) return players[i+1] end,
                WorldToScreen=function(v) return v end}
            Vector=setmetatable({}, {__call=function(_,x,y) return {X=x,Y=y} end})
            Vector.One={X=1,Y=1}
            Color=function(...) return {...} end
            EntityPtr=function(e) return {Ref=e} end
            renders=0
            Sprite=setmetatable({}, {__call=function() return {Load=function() end,ReplaceSpritesheet=function() end,
                LoadGraphics=function() end,SetFrame=function() end,Render=function() renders=renders+1 end} end})
            -- The engine's RNG: xorshift right-left-right with shift index 35's
            -- (5, 9, 7), returning each new state, so its first value after
            -- SetSeed shows the same small-seed bias measured in game. Forced
            -- values come first so a test can choose a roll.
            forcedFloats,forcedInts={}, {}
            RNG=setmetatable({}, {__call=function()
                local r={state=1}
                function r:SetSeed(seed,shift) assert(seed~=0 and shift==35); self.state=seed & 0xffffffff end
                function r:Next()
                    local x=self.state
                    x=x ~ (x>>5); x=(x ~ (x<<9)) & 0xffffffff; x=x ~ (x>>7)
                    self.state=x
                    return x
                end
                function r:RandomFloat()
                    if #forcedFloats>0 then return table.remove(forcedFloats,1) end
                    return self:Next()/4294967296
                end
                function r:RandomInt(n)
                    if #forcedInts>0 then return table.remove(forcedInts,1) end
                    return self:Next()%n
                end
                return r
            end})
            ConchBlessing={Config={debugMode=false},
                printError=function(e) errors[#errors+1]=tostring(e) end,
                printDebug=function(e) debugs[#debugs+1]=e end,
                ItemData={
                    CONCH_PEARL={type='passive',id=900,pool={RoomType.ROOM_ANGEL,RoomType.ROOM_SECRET}},
                    KRONOS={type='passive',id=901,pool={RoomType.ROOM_TREASURE,RoomType.ROOM_DEVIL}},
                    DRAGON={type='passive',id=902,stackable=true,pool={RoomType.ROOM_TREASURE,RoomType.ROOM_PLANETARIUM}},
                    POWER_TRAINING={type='active',id=903,pool={RoomType.ROOM_ANGEL,RoomType.ROOM_SHOP}},
                    VOID_DAGGER={type='passive',id=904,pool={RoomType.ROOM_DEVIL}},
                    TYRFING={type='passive',id=905,hidden=true,pool={}},
                    INF_D6={type='active',id=906,hidden=true,console=true},
                    OX={type='passive',id=907,hidden=true,WorkingNow=true},
                    TIME_MONEY={type='familiar',id=908,stackable=true,pool={{RoomType.ROOM_SHOP,weight=1.0}}},
                    SEALED_DEMON_SWORD={type='passive',id=909,stackable=true,pool={RoomType.ROOM_DEVIL,RoomType.ROOM_CURSE}},
                    TIME_POWER={type='trinket',id=50},
                }}
            hostLoaded=package and package.loaded or hostLoaded; package=nil
            M=require('scripts.items.collectibles.conch_pearl')
            function draw(selected,poolType,decrease,seed)
                return M.onPostGetCollectible(nil,selected,poolType,decrease==true,seed or 12345)
            end
        ''')

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_only_a_living_holder_turns_it_on(self):
        self.run_lua('''
            forcedFloats={0}
            assert(draw(3,ItemPoolType.POOL_TREASURE)~=nil,'holder converts at roll 0')
            players[1].items[900]=0
            assert(not M.isActive() and draw(1,ItemPoolType.POOL_TREASURE)==nil and #poolCalls==0)
            players[1].items[900]=2
            players[1].dead=true; assert(not M.isActive(),'a dead holder does not act')
            players[1].dead=false; players[1].ghost=true; assert(not M.isActive(),'a co-op ghost does not act')
            players[1].ghost=false; players[1].items[900]=0
            players[2]=newPlayer({[900]=1}); assert(M.isActive(),'a second player holder counts')
        ''')

    def test_high_quality_quest_own_and_unknown_draws_stay(self):
        self.run_lua('''
            for _,id in ipairs({4,5,6,901,909,999}) do
                assert(draw(id,ItemPoolType.POOL_TREASURE,true)==nil,'kept '..id)
            end
            assert(#poolCalls==0 and #removed==0 and #M._test.pending()==0)
        ''')

    def test_low_quality_redraws_from_the_same_pool_until_it_may_appear(self):
        self.run_lua('''
            script={2,1,4}
            local result=draw(1,ItemPoolType.POOL_BOSS,true,777)
            assert(result==4,'quality 3 redraw appears: '..tostring(result))
            assert(#poolCalls==3)
            for _,call in ipairs(poolCalls) do
                assert(call.poolType==ItemPoolType.POOL_BOSS and call.decrease==true and call.seed~=0)
            end
            for _,value in ipairs(nested) do assert(value==nil,'nested draws pass through the guard') end
            assert(poolCalls[1].seed~=poolCalls[2].seed,'each redraw has its own seed')
            assert(M._test.evidence().redraws==1 and M._test.evidence().conversions==0)
            -- The guard is released: an ordinary draw is filtered again.
            script={4}
            assert(draw(2,ItemPoolType.POOL_BOSS,false)==4)
        ''')

    def test_redrawn_quality_two_rolls_and_shows_the_redrawn_item(self):
        self.run_lua('''
            script={3}
            forcedFloats={0.05}
            forcedInts={0}
            local result=draw(1,ItemPoolType.POOL_DEVIL,true)
            assert(result==901,'first devil candidate: '..tostring(result))
            local entry=M._test.pending()[1]
            assert(entry.id==901 and entry.replaced==3,'dust shows the quality 2 it replaced')
            assert(removed[1]==901 and #removed==1,'a drawn item leaves the natural pools')
        ''')

    def test_quality_two_converts_below_ten_percent_only(self):
        self.run_lua('''
            assert(M.data.convertChance==0.10)
            assert(M._test.converts(0.0999999) and not M._test.converts(0.1) and not M._test.converts(0.5))
            forcedFloats={0.1}
            assert(draw(3,ItemPoolType.POOL_TREASURE,true)==nil and #removed==0)
            forcedFloats={0.0999}
            local result=draw(3,ItemPoolType.POOL_TREASURE,true)
            assert(result==901 or result==902,'treasure candidate: '..tostring(result))
            assert(#poolCalls==0,'quality 2 is not redrawn')
        ''')

    def test_preview_draws_do_not_touch_the_pools(self):
        self.run_lua('''
            forcedFloats={0}
            assert(draw(3,ItemPoolType.POOL_TREASURE,false)~=nil and #removed==0)
        ''')

    def test_fallback_after_the_pool_keeps_giving_low_quality(self):
        self.run_lua('''
            defaultDraw=2
            local result=draw(1,ItemPoolType.POOL_BOSS,true)
            assert(#poolCalls==M.data.maxRedraws,'bounded redraws: '..#poolCalls)
            assert(result~=nil and result>=901,'one of ours appears instead: '..tostring(result))
            assert(M._test.evidence().fallbacks==1 and M._test.pending()[1].replaced==1)
            -- With every candidate held and unstackable, the pool's choice stays.
            poolCalls={}
            for _,id in ipairs({901,902,903,904,908,909}) do players[1].items[id]=1 end
            local ids={}
            for _,id in ipairs(M.candidatesFor(ItemPoolType.POOL_BOSS)) do ids[#ids+1]=id end
            assert(table.concat(ids,',')=='902,908,909','only stackable items remain: '..table.concat(ids,','))
            ConchBlessing.ItemData.DRAGON.stackable=nil
            ConchBlessing.ItemData.TIME_MONEY.stackable=nil
            ConchBlessing.ItemData.SEALED_DEMON_SWORD.stackable=nil
            M._test.resetRegistry()
            assert(#M.candidatesFor(ItemPoolType.POOL_BOSS)==0)
            assert(draw(1,ItemPoolType.POOL_BOSS,true)==nil,'no candidate: the draw is left alone')
        ''')

    def test_candidates_prefer_the_pool_and_skip_held_singles_and_actives(self):
        self.run_lua('''
            local function ids(poolType)
                local list={}
                for _,id in ipairs(M.candidatesFor(poolType)) do list[#list+1]=id end
                return table.concat(list,',')
            end
            -- The holder's own Conch Pearl is never offered while held.
            assert(ids(ItemPoolType.POOL_DEVIL)=='901,904,909','devil: '..ids(ItemPoolType.POOL_DEVIL))
            assert(ids(ItemPoolType.POOL_SHOP)=='903,908','shop with a { room, weight } entry: '..ids(ItemPoolType.POOL_SHOP))
            assert(ids(ItemPoolType.POOL_ANGEL)=='903','angel: '..ids(ItemPoolType.POOL_ANGEL))
            assert(ids(ItemPoolType.POOL_BOSS)=='901,902,903,904,908,909','no ours in boss: any released one')
            assert(ids(nil)=='901,902,903,904,908,909')
            players[1].items[901]=1 -- Kronos: copies add nothing
            players[1].items[903]=1 -- Power Training: an active
            players[1].items[902]=3 -- Dragon: copies stack
            assert(ids(ItemPoolType.POOL_BOSS)=='902,904,908,909','held singles and actives skipped')
            assert(ids(ItemPoolType.POOL_ANGEL)=='902,904,908,909','held angel active: fall back to any')
            players[2]=newPlayer({[904]=1})
            assert(ids(ItemPoolType.POOL_DEVIL)=='909','another player holding counts too')
            players[2].dead=true
            assert(ids(ItemPoolType.POOL_DEVIL)=='909','a dead player still holds the item')
        ''')

    def test_sequential_small_seeds_still_convert_at_ten_percent(self):
        # In game the bench's seeds 7919*i+13 (up to ~3.2M) converted 25% before the
        # seed mix; these seeds stay in that range.
        self.run_lua('''
            local function rate(useMix)
                local hits,n=0,4000
                for i=1,n do
                    local r=RNG()
                    local seed=i*797+13
                    r:SetSeed(useMix and M._test.mixSeed(seed) or seed,35)
                    if M._test.converts(r:RandomFloat()) then hits=hits+1 end
                end
                return hits/n
            end
            local raw,mixed=rate(false),rate(true)
            assert(raw>0.2,'the double reproduces the raw-seed bias: '..raw)
            assert(math.abs(mixed-0.1)<=3*math.sqrt(0.09/4000),'mixed seeds roll 10%: '..mixed)
            local converted=0
            for i=1,4000 do if draw(3,ItemPoolType.POOL_TREASURE,false,i*797+13) then converted=converted+1 end end
            local shipped=converted/4000
            assert(math.abs(shipped-0.1)<=3*math.sqrt(0.09/4000),'the shipped draw path converts 10%: '..shipped)
            assert(M._test.mixSeed(0)~=0 and M._test.mixSeed(-1)~=0,'every seed maps to a usable RNG seed')
        ''')

    def test_same_seed_gives_the_same_answer(self):
        self.run_lua('''
            local a,b={}, {}
            for seed=1,200 do a[seed]=draw(3,ItemPoolType.POOL_TREASURE,false,seed) or 0 end
            for seed=1,200 do b[seed]=draw(3,ItemPoolType.POOL_TREASURE,false,seed) or 0 end
            local converted=0
            for seed=1,200 do assert(a[seed]==b[seed]); if a[seed]~=0 then converted=converted+1 end end
            assert(converted>0 and converted<200,'some but not all convert: '..converted)
            assert(draw(3,ItemPoolType.POOL_TREASURE,false,0)==draw(3,ItemPoolType.POOL_TREASURE,false,0),'seed 0 is usable')
        ''')

    def test_dust_attaches_only_to_the_pedestal_drawn_for(self):
        self.run_lua('''
            local function pedestal(subtype,variant)
                return {Variant=variant or PickupVariant.PICKUP_COLLECTIBLE,SubType=subtype,InitSeed=4242,
                    Position={X=320,Y=280},Touched=false,Exists=function() return true end}
            end
            forcedFloats={0}; forcedInts={0}
            assert(draw(3,ItemPoolType.POOL_DEVIL,true)==901)
            M.onPickupInit(nil,pedestal(901,PickupVariant.PICKUP_HEART))
            assert(#M._test.pending()==1,'another pickup kind leaves the record alone')
            M.onPickupInit(nil,pedestal(5))
            assert(#M._test.pending()==0 and #M._test.effects()==0,'a different pedestal shows nothing')
            forcedFloats={0}; forcedInts={0}
            draw(3,ItemPoolType.POOL_DEVIL,true)
            M.onPickupInit(nil,pedestal(901))
            local effect=M._test.effects()[1]
            assert(effect and #effect.icons==1 and effect.icons[1].itemId==3,'the replaced icon rises')
            forcedFloats={0}; forcedInts={0}
            draw(3,ItemPoolType.POOL_DEVIL,true)
            M.onUpdate()
            assert(#M._test.pending()==0,'an unclaimed conversion is dropped at the next update')
        ''')

    def test_blind_pedestals_show_nothing(self):
        self.run_lua('''
            local p={Variant=PickupVariant.PICKUP_COLLECTIBLE,SubType=901,InitSeed=1,Position={X=0,Y=0},Touched=false}
            curses=LevelCurse.CURSE_OF_BLIND
            forcedFloats={0}; forcedInts={0}; draw(3,ItemPoolType.POOL_DEVIL,true); M.onPickupInit(nil,p)
            assert(#M._test.effects()==0,'Curse of the Blind')
            curses=0; roomType=RoomType.ROOM_TREASURE; stageType=StageType.STAGETYPE_REPENTANCE
            forcedFloats={0}; forcedInts={0}; draw(3,ItemPoolType.POOL_DEVIL,true); M.onPickupInit(nil,p)
            assert(#M._test.effects()==0,'alternate-path treasure room')
            roomType=1
            forcedFloats={0}; forcedInts={0}; draw(3,ItemPoolType.POOL_DEVIL,true); M.onPickupInit(nil,p)
            assert(#M._test.effects()==1)
        ''')

    def test_dust_freezes_without_updates_and_ends(self):
        self.run_lua('''
            local alive=true
            local p={Variant=PickupVariant.PICKUP_COLLECTIBLE,SubType=901,InitSeed=9,Position={X=10,Y=200},
                Touched=false,Exists=function() return alive end}
            forcedFloats={0}; forcedInts={0}; draw(3,ItemPoolType.POOL_DEVIL,true); M.onPickupInit(nil,p)
            local effect=M._test.effects()[1]
            M.onRender(); M.onRender()
            assert(effect.tick==0,'rendering alone (a paused game) does not advance it')
            local D=M._test.DUST
            for _=1,D.APPEAR+D.HOLD+1 do M.onUpdate() end
            renders=0; M.onRender()
            assert(renders>=(D.ICON_SIZE//D.GRAIN)^2/2,'crumbling draws grains: '..renders)
            alive=false; M.onRender()
            assert(effect.x==10 and effect.y==200,'keeps the last pedestal position')
            for _=1,D.TOTAL do M.onUpdate() end
            assert(#M._test.effects()==0,'ends after its timeline')
            forcedFloats={0}; forcedInts={0}; draw(3,ItemPoolType.POOL_DEVIL,true); M.onPickupInit(nil,p)
            M.reset()
            assert(#M._test.effects()==0 and #M._test.pending()==0,'room/game/unload reset')
        ''')

    def test_a_new_room_keeps_its_own_pedestals_dust(self):
        self.run_lua('''
            local function pedestal(alive)
                local p={Variant=PickupVariant.PICKUP_COLLECTIBLE,SubType=901,InitSeed=3,Position={X=0,Y=0},
                    Touched=false,alive=alive}
                p.Exists=function() return p.alive end
                return p
            end
            local old=pedestal(true)
            forcedFloats={0}; forcedInts={0}; draw(3,ItemPoolType.POOL_DEVIL,true); M.onPickupInit(nil,old)
            -- The next room loads: the old pedestal is gone and the new one is drawn
            -- and initialised before MC_POST_NEW_ROOM.
            old.alive=false
            local fresh=pedestal(true)
            forcedFloats={0}; forcedInts={0}; draw(3,ItemPoolType.POOL_DEVIL,true); M.onPickupInit(nil,fresh)
            forcedFloats={0}; forcedInts={0}; draw(3,ItemPoolType.POOL_DEVIL,true) -- an orphan conversion
            M.onNewRoom()
            local effects=M._test.effects()
            assert(#effects==1 and effects[1].ref.Ref==fresh,'only the new room pedestal keeps its dust')
            assert(#M._test.pending()==0,'orphans are dropped')
        ''')

    def test_missing_quest_tag_capability_leaves_draws_unchanged(self):
        self.run_lua('''
            ItemConfig.TAG_QUEST=nil
            assert(draw(1,ItemPoolType.POOL_TREASURE,true)==nil and draw(3,ItemPoolType.POOL_TREASURE,true)==nil)
            assert(#errors==1 and errors[1]:find('QUEST_TAG_UNAVAILABLE'),'reported once: '..tostring(errors[1]))
        ''')

    def test_a_failing_redraw_releases_the_guard(self):
        self.run_lua('''
            poolError='pool exploded'
            assert(draw(1,ItemPoolType.POOL_TREASURE,true)~=nil,'falls back to ours after the failed redraw')
            assert(#errors==1 and errors[1]:find('REDRAW_FAILED'))
            poolError=nil; script={4}
            assert(draw(1,ItemPoolType.POOL_TREASURE,true)==4,'later draws are filtered again')
        ''')


if __name__ == '__main__':
    unittest.main()
