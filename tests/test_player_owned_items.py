"""Per-player ownership of item state, with engine and SaveManager doubles (Lua 5.3).

Every player's state follows that player: two holders (co-op, Esau, a second
player of the same character) never move each other's values, Continue brings a
holder's saved state back, a dead holder or co-op ghost does not act, and no
callback guesses player 0 for a missing player. The run save here is keyed by a
seed and stands in for the disk; these are not engine or Continue-on-disk tests.
"""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text(encoding='utf-8')


COMMON = r'''
    errors={}; players={}; runs={}; modules={}
    SM={GetRunSave=function(p) runs[p.seed]=runs[p.seed] or {}; return runs[p.seed] end,
        TryGetRunSave=function(p) return runs[p.seed] end,Save=function() end}
    modules['scripts.lib.save_manager']=SM
    ConchBlessingRequire=function(name) return assert(modules[name],'unexpected require '..tostring(name)) end
    package=nil
    EntityType={ENTITY_PICKUP=5,ENTITY_EFFECT=1000}; PickupVariant={PICKUP_COLLECTIBLE=100}; Vector={Zero={}}
    game={GetNumPlayers=function() return #players end,GetPlayer=function(_,i) return players[i+1] end}
    function Game() return game end
    Isaac={GetPlayer=function(i) return players[i+1] end,Spawn=function() return nil end}
    ConchBlessing={SaveManager=SM,printDebug=function() end,printError=function(e) errors[#errors+1]=e end,
        Locale={text=function(key,value) return '|'..key..'='..tostring(value) end}}
    function makePlayer(seed,items)
        local p={seed=seed,data={},items=items or {},Damage=3.5,MoveSpeed=1,Luck=0,evaluations=0,Position={}}
        function p:GetData() return self.data end
        function p:ToPlayer() return self end
        function p:GetCollectibleNum(id) return self.items[id] or 0 end
        function p:HasCollectible(id) return self:GetCollectibleNum(id)>0 end
        function p:AddCacheFlags() end
        players[#players+1]=p; return p
    end
'''


class LiveEyeOwnership(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(COMMON + r'''
            CacheFlag={CACHE_DAMAGE=1}; CollectibleType={COLLECTIBLE_ROCK_BOTTOM=562}
            WeaponType={WEAPON_TEARS=1,WEAPON_MONSTROS_LUNGS=6,WEAPON_FETUS=9,NUM_WEAPON_TYPES=16}
            Isaac.GetItemIdByName=function() return 50 end
            ConchBlessing.stats={damage={applyMultiplier=function(p,m) p.Damage=p.Damage*m end},
                multiplierDisplay={ShowDetailedMultipliers=function() end}}
            function eye(seed)
                local p=makePlayer(seed,{[50]=1}); p.roll=0.99
                function p:HasWeaponType(t) return t==1 end
                function p:GetCollectibleRNG() return {RandomFloat=function() return p.roll end} end
                function p:EvaluateItems() self.evaluations=self.evaluations+1; self.Damage=3.5; L.onEvaluateCache(nil,self,1) end
                return p
            end
            function loadEye() load(eyeSource,'live_eye')(); L=ConchBlessing.liveeye end
            function near(a,b) assert(math.abs(a-b)<1e-9,tostring(a)..' ~= '..tostring(b)) end
        ''')
        self.lua.globals().eyeSource = source('scripts/items/collectibles/live_eye.lua')
        self.lua.execute('loadEye()')

    def test_each_holder_moves_and_refreshes_only_its_own_multiplier(self):
        self.lua.execute(r'''
            -- b plays the same character on the same controller; only the seed differs.
            local a,b=eye(1),eye(2)
            for _=1,3 do L.handleHit(a) end
            near(L.getMultiplier(a),1.3); near(L.getMultiplier(b),1.0)
            assert(b.evaluations==0,'a hit refreshed the other holder')
            near(a.Damage,3.5*1.3)
            L.handleMiss(b); near(L.getMultiplier(b),0.85); near(L.getMultiplier(a),1.3)
            b.roll=0; L.handleMiss(b); near(L.getMultiplier(b),0.85) -- forgiven by b's own roll
            assert(a.evaluations==3)
        ''')

    def test_missing_owner_is_rejected_without_guessing_player_zero(self):
        self.lua.execute(r'''
            local a=eye(1); L.handleHit(nil); L.handleMiss(nil)
            near(L.getMultiplier(a),1.0); assert(L._counters.misses==0 and a.evaluations==0)
        ''')

    def test_continue_keeps_each_holders_multiplier_and_a_new_run_starts_fresh(self):
        self.lua.execute(r'''
            local a,b=eye(1),eye(2)
            L.handleHit(a); L.handleHit(a); L.handleMiss(b)
            -- Continue: a new process and empty entity data, the saved run save.
            for _,p in ipairs(players) do p.data={} end
            loadEye(); L.onGameStarted(nil,true)
            near(a.Damage,3.5*1.2); near(b.Damage,3.5*0.85)
            runs={}; L.onGameStarted(nil,false); near(a.Damage,3.5); near(b.Damage,3.5)
        ''')

    def test_set_multiplier_clamps_and_reports_a_missing_save(self):
        self.lua.execute(r'''
            local a=eye(1); near(L.setMultiplier(a,10),3.0); near(L.setMultiplier(a,-1),0.75)
            local get=SM.GetRunSave; SM.GetRunSave=function() return nil end
            assert(L.setMultiplier(a,2)==nil); L.handleHit(a); assert(#errors==1)
            SM.GetRunSave=get; near(L.getMultiplier(a),0.75)
        ''')


class KillAndCurseHolders(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(COMMON + r'''
            CacheFlag={CACHE_DAMAGE=1,CACHE_FIREDELAY=2,CACHE_SPEED=4}
            LevelCurse={CURSE_OF_DARKNESS=1,CURSE_OF_THE_LOST=4}
            modules['scripts.lib.enemy_utils']={isMonsterKind=function(n) return n.monster==true end}
            modules['scripts.lib.player_hits']={register=function() end,counts=function() return true end}
            modules['scripts.lib.sound_volume']={volume=function(v) return v end}
            Isaac.GetItemIdByName=function(name) return ({['Eternal Flame']=20,['Sealed Demon Sword']=21,Tyrfing=22})[name] end
            ConchBlessing.stats={damage={applyAddition=function(p,x) p.Damage=p.Damage+x end},
                tears={applyAddition=function(p,x) p.Tears=p.Tears+x end},
                speed={applyAddition=function(p,x) p.MoveSpeed=p.MoveSpeed+x end}}
            curses=0
            level={GetCurses=function() return curses end,RemoveCurses=function(_,mask) curses=curses&(~mask) end}
            roomClear=false
            game.GetLevel=function() return level end
            game.GetRoom=function() return {IsClear=function() return roomClear end} end
            function holder(seed,items,state)
                local p=makePlayer(seed,items); p.Tears=3; p.hearts=0; p.uses=0
                function p:IsDead() return state=='dead' end
                if state=='ghost' then function p:IsCoopGhost() return true end end
                function p:AddEternalHearts(n) self.hearts=self.hearts+n end
                function p:UseActiveItem() self.uses=self.uses+1 end
                function p:EvaluateItems()
                    self.evaluations=self.evaluations+1; self.Damage=3.5; self.Tears=3; self.MoveSpeed=1
                    for _,flag in ipairs({1,2,4}) do
                        for _,m in pairs({F=F,S=S,T=T}) do m.onEvaluateCache(nil,self,flag) end
                    end
                end
                return p
            end
            function loadModule(path,field) load(sources[path],path)(); return ConchBlessing[field] end
        ''')
        self.lua.globals().sources = self.lua.table_from({
            p: source('scripts/items/collectibles/%s.lua' % p)
            for p in ('eternal_flame', 'sealed_demon_sword', 'tyrfing')})

    def test_eternal_flame_dead_or_ghost_holders_neither_run_nor_earn_the_removal(self):
        self.lua.execute(r'''
            F=loadModule('eternal_flame','eternalflame')
            local dead=holder(1,{[20]=1},'dead'); local ghost=holder(2,{[20]=1},'ghost'); local live=holder(3,{[20]=2})
            F.onGameStarted(); curses=5; for _=1,32 do F.onUpdate() end
            assert(curses==0,'the living holder burns the curses away')
            assert(runs[3].eternalFlame.earnedUnits==4,'the living holder earns its own copies')
            for _,p in ipairs({dead,ghost}) do
                local saved=runs[p.seed].eternalFlame
                assert(saved==nil or saved.earnedUnits==0,'a dead or ghost holder earned a removal')
            end
            live.items[20]=0; curses=1; for _=1,40 do F.onUpdate() end
            assert(curses==1,'nobody living holds it: the curse stays')
        ''')

    def test_eternal_flame_new_room_resets_detection_for_a_second_player_holder(self):
        self.lua.execute(r'''
            F=loadModule('eternal_flame','eternalflame')
            holder(1,{}); holder(2,{[20]=1}); F.onGameStarted()
            curses=1; F.onUpdate(); assert(F.data.pendingCurses==1)
            F.onNewRoom(); assert(F.data.pendingCurses==nil and F.data.curseRemovalTimer==nil)
            F.onUpdate(); F.onNewLevel(); assert(F.data.pendingCurses==nil)
        ''')

    def test_tyrfing_kills_pay_only_living_holders_and_game_start_refreshes_all(self):
        self.lua.execute(r'''
            T=loadModule('tyrfing','tyrfing')
            local dead=holder(1,{[22]=1},'dead'); local ghost=holder(2,{[22]=1},'ghost'); local live=holder(3,{[22]=2})
            T.onNPCDeath(nil,{monster=true})
            assert(math.abs(runs[3].tyrfing.accumulatedDamage-0.1)<1e-9)
            for _,p in ipairs({dead,ghost}) do
                local saved=runs[p.seed] and runs[p.seed].tyrfing
                assert(not saved or (saved.accumulatedDamage or 0)==0,'a dead or ghost holder earned a kill')
            end
            for _,p in ipairs(players) do p.evaluations=0 end
            T.onGameStarted(); for _,p in ipairs(players) do assert(p.evaluations==1,'game start skipped a holder') end
        ''')

    def test_sealed_sword_dead_holder_neither_counts_kills_nor_cleaves(self):
        self.lua.execute(r'''
            REPENTOGON=nil; CollectibleType={COLLECTIBLE_MEAT_CLEAVER=631}; UseFlag={USE_NOANIM=1,USE_NOCOSTUME=2}
            S=loadModule('sealed_demon_sword','sealeddemonsword')
            local dead=holder(1,{[21]=1},'dead'); local live=holder(2,{})
            S.onNPCDeath(nil,{monster=true}); assert(runs[1]==nil or runs[1].sealedDemonSword==nil or runs[1].sealedDemonSword.killCount==0)
            S.onNewRoom(); assert(dead.uses==0,'a dead holder cleaved the room')
            live.items[21]=1; S.onNPCDeath(nil,{monster=true}); assert(runs[2].sealedDemonSword.killCount==1)
            S.onNewRoom(); assert(live.uses==1 and dead.uses==0)
            -- The flat speed penalty goes through StatsAPI's speed helper, once for any copy count.
            live.items[21]=4; live:EvaluateItems(); assert(math.abs(live.MoveSpeed-0.8)<1e-9)
            live.items[21]=0; live:EvaluateItems(); assert(live.MoveSpeed==1)
        ''')


class DescriptionReaders(unittest.TestCase):
    """EID's live lines read the player EID chose (Item Reminder, else nearest)."""

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().sources = self.lua.table_from({
            p: source('scripts/items/collectibles/%s.lua' % p)
            for p in ('sealed_demon_sword', 'tyrfing', 'utility_belt', 'void_dagger')})
        self.lua.execute(COMMON + r'''
            CacheFlag={CACHE_DAMAGE=1,CACHE_SPEED=4}; ActiveSlot={SLOT_PRIMARY=0,SLOT_POCKET=2}
            CollectibleType={}; SoundEffect={}
            modules['scripts.lib.enemy_utils']={}
            modules['scripts.lib.player_hits']={register=function() end}
            modules['scripts.lib.isaacscript-common']={}
            modules['scripts.lib.damage_provenance']={registerCallbacks=function() end}
            Isaac.GetItemIdByName=function(name) return ({['Sealed Demon Sword']=21,Tyrfing=22,['Utility Belt']=23,['Void Dagger']=24})[name] end
            ConchBlessing.Locale.formatPercent=function(v) return v..'%' end
            mods={}
            EID={addDescriptionModifier=function(_,name,fn) mods[#mods+1]=fn end,
                ClosestPlayerTo=function(_,entity) return entity and entity.nearest end}
            for _,path in ipairs({'sealed_demon_sword','tyrfing','utility_belt','void_dagger'}) do
                load(sources[path],path)()
            end
            function describe(id,nearest)
                local d={ObjType=5,ObjVariant=100,ObjSubType=id,Description='',Entity={nearest=nearest}}
                for _,fn in ipairs(mods) do d=fn(d) end
                return d.Description
            end
            function seat(seed,primary,pocket,delay)
                local p=makePlayer(seed); p.MaxFireDelay=delay or 10; p.Luck=0
                function p:GetActiveItem(slot) return slot==0 and primary or pocket end
                return p
            end
        ''')

    def test_each_line_shows_the_reader_eid_chose_not_player_zero(self):
        self.lua.execute(r'''
            local first=seat(1,0,7,10); local second=seat(2,105,0,1)
            runs[1]={sealedDemonSword={killCount=10},tyrfing={accumulatedDamage=1}}
            runs[2]={sealedDemonSword={killCount=250},tyrfing={accumulatedDamage=4.5}}
            assert(describe(21,second):find('remaining_kills=50',1,true))
            assert(describe(22,second):find('accumulated_damage=4.50',1,true))
            assert(describe(23,second):find('will_move={{Collectible105}}',1,true))
            assert(describe(23,first):find('pocket_full',1,true))
            assert(describe(24,second)~=describe(24,first),'the proc chance follows the reader\'s fire rate')
            assert(describe(21,first):find('remaining_kills=290',1,true))
        ''')

    def test_without_a_reader_no_one_elses_values_are_shown(self):
        self.lua.execute(r'''
            seat(1,105,0); runs[1]={sealedDemonSword={killCount=10},tyrfing={accumulatedDamage=1}}
            EID.ClosestPlayerTo=nil
            assert(describe(21,nil):find('remaining_kills=300',1,true))
            assert(describe(22,nil):find('accumulated_damage=0.00',1,true))
            assert(describe(23,nil)=='' and describe(24,nil)=='')
        ''')


class AngelsCrownGoldenHolder(unittest.TestCase):
    """The blessed roll reads real golden copies through the shared trinket helper."""

    def test_two_plain_crowns_are_not_golden_and_a_golden_one_is(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().utils = source('scripts/lib/trinket_utils.lua')
        lua.globals().crown = source('scripts/items/trinkets/angels_crown.lua')
        lua.execute(COMMON + r'''
            CollectibleType={COLLECTIBLE_MOMS_BOX=439}; TrinketType={TRINKET_GOLDEN_FLAG=32768}
            EffectVariant={POOF01=1}; BackdropType={CATHEDRAL=1}
            RoomType={ROOM_SECRET=7,ROOM_SUPERSECRET=8,ROOM_ULTRASECRET=29}
            ConchBlessing.TrinketUtils=load(utils,'trinket_utils')()
            ConchBlessing.ItemData={ANGELS_CROWN={id=9}}
            load(crown,'angels_crown')(); local A=ConchBlessing.angelscrown._test
            -- The engine's multiplier: +1 per plain copy, +2 per golden copy, +1 for Mom's Box.
            function crowned(slots,box)
                local p=makePlayer(#players+1,{[439]=box and 1 or 0})
                function p:GetTrinket(slot) return slots[slot+1] or 0 end
                function p:GetTrinketMultiplier(id)
                    local n=box and 1 or 0
                    for _,raw in ipairs(slots) do if raw%32768==id then n=n+(raw>=32768 and 2 or 1) end end
                    return n
                end
                return p
            end
            crowned({9,9}); local golden,box=A.findBestHolder()
            assert(golden==0 and box==false,'two plain crowns read as golden')
            players={}; crowned({9+32768}); golden=A.findBestHolder(); assert(golden==1)
            players={}; crowned({9},true); golden,box=A.findBestHolder(); assert(golden==0 and box==true)
            players={}; crowned({}); assert(A.findBestHolder()==nil)
        ''')


class RegistryContracts(unittest.TestCase):
    # Every cache name the vanilla items.xml uses.
    VALID_CACHE = {'all', 'color', 'damage', 'familiars', 'firedelay', 'flying', 'luck',
                   'pickupvision', 'range', 'shotspeed', 'size', 'speed', 'tearcolor',
                   'tearflag', 'weapon'}

    def test_generated_cache_attributes_use_only_engine_cache_names(self):
        tree = ET.parse(ROOT / 'content/items.xml')
        for item in tree.getroot():
            tokens = (item.get('cache') or '').split()
            unknown = [t for t in tokens if t not in self.VALID_CACHE]
            self.assertFalse(unknown, '%s: %s' % (item.get('name'), unknown))

    def test_registry_sources_use_only_engine_cache_names(self):
        registry = source('scripts/conch_blessing_items.lua')
        for value in re.findall(r'\bcache\s*=\s*"([^"]*)"', registry):
            unknown = [t for t in value.split() if t not in self.VALID_CACHE]
            self.assertFalse(unknown, value)

    def test_no_dead_pickup_init_hooks_on_these_items(self):
        # `pickup` maps to MC_POST_PICKUP_INIT filtered by the item ID as a
        # pickup variant, so it never fires for an acquisition.
        registry = source('scripts/conch_blessing_items.lua')
        for key in ('LIVE_EYE', 'ETERNAL_FLAME', 'SEALED_DEMON_SWORD', 'TYRFING'):
            row = re.search(r'\n    %s = \{(.*?)\n    \},' % key, registry, re.S).group(1)
            self.assertNotRegex(row, r'\bpickup\s*=', key)


if __name__ == '__main__':
    unittest.main()
