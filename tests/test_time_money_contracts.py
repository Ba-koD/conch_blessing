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
            function makePlayer(kind)
                local p={kind=kind,count=0,checks={},Position=Vector.Zero,Luck=0}
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
            p.count=1;M.onPlayerUpdate();assert(coins==5)
            M.onPlayerUpdate();assert(coins==5)
            p.count=2;M.onPlayerUpdate();assert(coins==10)
            p.count=1;M.onPlayerUpdate();assert(coins==10)
            assert(store[p].timeMoney['0'].lastItemCount==1)
            p.count=2;M.onPlayerUpdate();assert(coins==15)
            p.count=0;M.onPlayerUpdate();assert(coins==15)
            assert(store[p].timeMoney['0'].lastItemCount==0)
            p.count=1;M.onPlayerUpdate();assert(coins==20)
            local before=saves;M.onPlayerUpdate();assert(saves==before and coins==20)
        ''')

    def test_zero_count_never_pays_periodic_coins(self):
        self.lua.execute('''
            p.count=1;M.onPlayerUpdate();assert(coins==5)
            p.count=0;M.onPlayerUpdate();frame=1800;M.onPlayerUpdate();assert(coins==5)
            M.onEvaluateCache(nil,p,1);assert(p.live==0)
        ''')


if __name__ == '__main__':
    unittest.main()
