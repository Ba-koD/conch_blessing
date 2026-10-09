"""Dragon's shipped vortex expiry logic with Lua doubles; real HP remains in-game."""
import unittest
import test_breath_contracts as breath_tests


class DragonVortexContracts(unittest.TestCase):
    def setUp(self):
        breath_tests.BreathContracts.setUp(self)
        self.lua.execute(r'''
            EntityFlag.FLAG_FRIENDLY=1;EntityFlag.FLAG_ATTRACTED=2
            DamageFlag={DAMAGE_EXPLOSION=4,DAMAGE_IGNORE_ARMOR=8,DAMAGE_FIRE=16}
            p.InitSeed=123;p.Damage=3.5
            game={GetFrameCount=function() return frame end,GetRoom=function() return nil end,
                GetNumPlayers=function() return 1 end,ShakeScreen=function() shakes=(shakes or 0)+1 end}
            function Game() return game end
            require('scripts.items.collectibles.dragon');D=ConchBlessing.dragon
            function victim(x)
                local n=target(0);n.Position=Vector(x,0);n.HitPoints=1000
                function n:IsDead() return self.dead==true end
                function n:HasEntityFlags(flag) return self.flags&flag~=0 end
                function n:TakeDamage(amount,flags,source)
                    self.damage[#self.damage+1]={amount=amount,flags=flags,source=source.Entity}
                    self.HitPoints=self.HitPoints-amount
                end
                return n
            end
            function pool(age)
                local e=makeEntity(1000,Vector.Zero,Vector.Zero,p);e.SpriteScale=Vector(.6,.6)
                e.Data.__ConchDragonWhirlpool={age=age or 58,life=60,ownerInitSeed=123,
                    pullRadius=220,pullStrength=.9,touchRadius=72,touchDamage=1,touchTick=1,
                    touchedAt={},nextParticleSpawnAge=999,explodeRadius=180}
                return e
            end
        ''')

    def test_natural_expiry_hits_exact_radius_once_and_uses_current_damage(self):
        self.lua.execute('''
            for _,damage in ipairs({3.5,9.25,3.5}) do
                p.Damage=damage;local near,edge,far=victim(120),victim(180),victim(181)
                targets={near,edge,far};local e=pool();D.onPostEffectUpdate(nil,e)
                assert(not e.removed and #near.damage==0 and #edge.damage==0)
                D.onPostEffectUpdate(nil,e)
                assert(e.removed and #near.damage==1 and #edge.damage==1 and #far.damage==0)
                almost(near.damage[1].amount,damage*25)
                assert(near.damage[1].flags==12 and near.damage[1].source==p)
                D.onPostEffectUpdate(nil,e)
                assert(#near.damage==1 and #edge.damage==1,'expiry explosion repeated')
            end
        ''')

    def test_expiry_ignores_dead_allied_or_invulnerable_targets(self):
        self.lua.execute('''
            local dead,ally,immune=victim(100),victim(110),victim(120)
            dead.dead=true;ally.flags=1;function immune:IsVulnerableEnemy() return false end
            targets={dead,ally,immune};D.onPostEffectUpdate(nil,pool(59))
            assert(#dead.damage==0 and #ally.damage==0 and #immune.damage==0)
        ''')

    def test_pull_requires_radius_and_eligible_target_and_preserves_owner_snapshot_fallback(self):
        self.lua.execute('''
            local near,far=victim(120),victim(230);targets={near,far};local e=pool(1)
            D.onPostEffectUpdate(nil,e)
            assert(near.Velocity.X<0 and far.Velocity.X==0 and #near.damage==0)
            p.InitSeed=456;e.Data.__ConchDragonWhirlpool.age=59
            e.Data.__ConchDragonWhirlpool.explosionDamage=99
            D.onPostEffectUpdate(nil,e);assert(#near.damage==1 and near.damage[1].amount==99)
        ''')


if __name__ == '__main__':
    unittest.main()
