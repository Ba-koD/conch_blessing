"""Time=Money lifecycle parameters under Lua provider doubles, not engine proof."""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class TimeMoneyContracts(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            local methods={};local mt={__index=methods}
            Vector=setmetatable({}, {__call=function(_,x,y) return setmetatable({X=x,Y=y},mt) end})
            mt.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
            function methods:Rotated() return self end
            Vector.Zero=Vector(0,0);frame=0;coins=0;saves=0
            ModCallbacks={};CacheFlag={CACHE_FAMILIARS=1};CollectibleType={COLLECTIBLE_BFFS=247}
            EntityType={ENTITY_PICKUP=5,ENTITY_FAMILIAR=3,ENTITY_EFFECT=1000}
            PickupVariant={PICKUP_COIN=20};EffectVariant={POOF_2=16}
            store={};players={}
            GetPtrHash=function(e) return e.hash end
            function makePlayer(kind)
                local p={kind=kind,count=0,checks={},Position=Vector.Zero,Luck=0,hash=#players+1}
                function p:GetPlayerType() return self.kind end
                function p:GetCollectibleNum(id) assert(id==900);return self.count end
                function p:GetCollectibleRNG(id) assert(id==900);return {RandomFloat=function() return .9 end} end
                function p:CheckFamiliar(variant,count,rng) self.checks[#self.checks+1]=count;self.live=count;assert(variant==999) end
                function p:HasCollectible() return false end
                function p:GetNumCoins() return 50 end
                players[#players+1]=p;return p
            end
            p=makePlayer(0);q=makePlayer(1)
            game={GetFrameCount=function() return frame end,GetNumPlayers=function() return #players end,
                GetPlayer=function(_,i) return players[i+1] end}
            function Game() return game end
            Isaac={FindByType=function() return {} end,Spawn=function(t)
                if t==5 then coins=coins+1 end
                return {ToEffect=function() return nil end}
            end}
            ConchBlessing={ItemData={TIME_MONEY={id=900,entity={variant=999}}},
                DamageUtils={isSelfInflictedDamage=function() return false end},printDebug=function() end,
                SaveManager={GetRunSave=function(p) store[p]=store[p] or {};return store[p] end,
                    Save=function() saves=saves+1 end}}
            require('scripts.items.familiars.time_money');M=ConchBlessing.timemoney
        ''')

    def test_stack_partial_final_removal_reacquisition_reconciles_zero_familiars(self):
        self.lua.execute('''
            for _,count in ipairs({1,2,1,0,1,0}) do
                p.count=count;M.onEvaluateCache(nil,p,1)
                assert(p.live==count,'stale familiar after inventory count '..count)
            end
            assert(#p.checks==6 and #q.checks==0,'wrong owner or missing zero call')
            M.onEvaluateCache(nil,p,2);assert(#p.checks==6)
            ConchBlessing.ItemData.TIME_MONEY.entity=nil
            M.onEvaluateCache(nil,p,1);assert(#p.checks==6)
        ''')

    def test_removed_count_is_saved_and_each_later_gain_gets_one_initial_payout(self):
        self.lua.execute('''
            local function update() M.onPlayerUpdate(nil,p) end
            p.count=1;update();assert(coins==5)
            update();assert(coins==5)
            p.count=2;update();assert(coins==10)
            p.count=1;update();assert(coins==10)
            assert(store[p].timeMoney.lastItemCount==1)
            p.count=2;update();assert(coins==15)
            p.count=0;update();assert(coins==15)
            assert(store[p].timeMoney.lastItemCount==0)
            p.count=1;update();assert(coins==20)
            local before=saves;update();assert(saves==before and coins==20)
        ''')

    def test_zero_count_never_pays_periodic_coins(self):
        self.lua.execute('''
            p.count=1;M.onPlayerUpdate(nil,p);assert(coins==5)
            p.count=0;M.onPlayerUpdate(nil,p);frame=1800;M.onPlayerUpdate(nil,p);assert(coins==5)
            M.onEvaluateCache(nil,p,1);assert(p.live==0)
        ''')

    def test_two_players_of_one_character_keep_their_own_counts(self):
        self.lua.execute('''
            q.kind=0 -- same character as p, as a second player of one character would be
            local function both() M.onPlayerUpdate(nil,p);M.onPlayerUpdate(nil,q) end
            p.count=1;q.count=2;both();assert(coins==10,'one initial payout per gain each: '..coins)
            for _=1,5 do both() end
            assert(coins==10,'copy counts flipped between same-type players: '..coins)
            assert(store[p].timeMoney.lastItemCount==1 and store[q].timeMoney.lastItemCount==2)
            assert(M.getPlayerState(p)~=M.getPlayerState(q))
            M.onPlayerUpdate(nil,nil);assert(coins==10,'missing player must be rejected')
        ''')

    def test_hit_penalty_and_payout_belong_to_the_hit_player_only(self):
        self.lua.execute('''
            q.kind=0;p.count=1;q.count=1
            M.onPlayerUpdate(nil,p);M.onPlayerUpdate(nil,q);coins=0
            M.getPlayerState(p).pendingPenalty=2
            frame=1800
            M.onPlayerUpdate(nil,p);M.onPlayerUpdate(nil,q)
            -- 5% of 50 coins = 2: p pays 2-2 -> minimum 1, q pays 2.
            assert(coins==3,'payouts '..coins)
            assert(M.getPlayerState(q).pendingPenalty==0)
        ''')

    def test_character_change_keeps_the_same_record(self):
        self.lua.execute('''
            p.count=1;M.onPlayerUpdate(nil,p);assert(coins==5)
            p.kind=8 -- Lazarus revived / Clicker: same player, new character
            for _=1,3 do M.onPlayerUpdate(nil,p) end
            assert(coins==5,'a character change paid the initial coins again')
        ''')

    def test_continue_migrates_legacy_type_records_once(self):
        self.lua.execute('''
            store[p]={timeMoney={['0']={lastItemCount=2,dropFramesRemaining=600,data={probLucky=0.5}},
                ['8']={lastItemCount=1}}}
            store[q]={timeMoney={['4']={lastItemCount=1,dropFramesRemaining=300}}}
            q.kind=1 -- q's saved record is from an earlier character
            p.count=2;q.count=1;frame=1000
            M.onGameStarted(nil,true)
            local rec=store[p].timeMoney
            assert(rec.lastItemCount==2 and rec['0']==nil and rec['8']==nil,'legacy record not adopted once')
            assert(M.data.probLucky==0.5,'probLucky not restored from the save')
            assert(store[q].timeMoney.lastItemCount==1 and store[q].timeMoney['4']==nil)
            M.onPlayerUpdate(nil,p);M.onPlayerUpdate(nil,q);assert(coins==0,'Continue repeated initial payouts')
            frame=1599;M.onPlayerUpdate(nil,p);assert(coins==0)
            frame=1600;M.onPlayerUpdate(nil,p);assert(coins==2,'saved timer not resumed: '..coins)
            frame=1300;M.onPlayerUpdate(nil,q);assert(coins==4,'q timer not resumed: '..coins)
        ''')


if __name__ == '__main__':
    unittest.main()
