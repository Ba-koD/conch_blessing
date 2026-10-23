"""Shared-run isolation against the room's own ambience (e.g. Burning Basement embers).

The cleanup double from test_cleanup_contracts provides the player, inventory and
room entity list; these tests add effects the room keeps spawning by itself. They
check the bench's isolation rule, not which effects Isaac spawns per stage.
"""
import unittest

import test_cleanup_contracts as cleanup
import test_item_bench as shared


class RoomAmbience(unittest.TestCase):
    run_lua = shared.BenchTests.run_lua

    def setUp(self):
        cleanup.CleanupContracts.setUp(self)
        self.run_lua('''
            EffectVariant = { FALLING_EMBER=87, TINY_BUG=21, TINY_FLY=33, WALL_BUG=68, WATER_DROPLET=41,
                TADPOLE=158 }
            removedByBench = 0
            -- A new ember falls every 2 updates and each lives 100: a fresh one is on
            -- screen within the cleanup's 4-update settle even right after deleting
            -- every leftover, so no update ever shows the room without one.
            function ambience(variant, tweak)
                local serial = 0
                ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
                    if frame % 2 ~= 0 then return end
                    serial = serial + 1
                    local e = entity(5000 + serial, 1000, 9000 + serial)
                    e.Variant = variant or EffectVariant.FALLING_EMBER
                    e.SubType = 0; e.CollisionDamage = 0; e.SpawnerType = 0; e.FrameCount = 0
                    e.untilFrame = frame + 100
                    e.onRemove = function() removedByBench = removedByBench + 1 end
                    if tweak then tweak(e) end
                end)
            end
        ''')

    def test_continuous_falling_embers_do_not_block_reuse_and_are_never_deleted(self):
        self.run_lua('''
            ambience()
            scenario(function() end)
            assert(#restarts==1, output())
            assert(output():find('PASS baseline restored',1,true), output())
            assert(removedByBench==0, 'the bench deleted room ambience: ' .. removedByBench)
        ''')

    def test_every_listed_backdrop_kind_counts_as_ambience(self):
        self.run_lua('''
            for _, name in ipairs({'TINY_BUG','TINY_FLY','WALL_BUG','WATER_DROPLET','TADPOLE'}) do
                ambience(EffectVariant[name])
            end
            scenario(function() end)
            assert(#restarts==1 and removedByBench==0, output())
        ''')

    def test_control_unknown_effect_enum_keeps_embers_as_orphans(self):
        self.run_lua('''
            EffectVariant = nil -- cannot prove ambience: fail closed
            ambience(87)
            scenario(function() end)
            assert(#restarts==2, output())
            assert(output():find('orphan gameplay entity: 1000:87:0:',1,true), output())
        ''')

    def test_ember_spawned_by_an_entity_is_a_leftover(self):
        self.run_lua('''
            ambience(nil, function(e) e.SpawnerType = 1 end)
            scenario(function() end)
            assert(#restarts==2, output())
            assert(output():find('orphan gameplay entity: 1000:87:0:',1,true)
                and output():find('spawner=1',1,true), output())
        ''')

    def test_ember_with_a_live_spawner_entity_is_a_leftover(self):
        self.run_lua('''
            ambience(nil, function(e) e.SpawnerEntity = player end)
            scenario(function() end)
            assert(#restarts==2 and output():find('orphan gameplay entity: 1000:87:0:',1,true), output())
        ''')

    def test_damaging_ambient_kind_is_a_leftover(self):
        self.run_lua('''
            ambience(nil, function(e) e.CollisionDamage = 1 end)
            scenario(function() end)
            assert(#restarts==2 and output():find('orphan gameplay entity: 1000:87:0:',1,true), output())
        ''')

    def test_other_persistent_effect_is_still_an_orphan_beside_ambience(self):
        self.run_lua('''
            ambience()
            local leak
            scenario(function()
                local fixture = entity(2, 5, 200)
                fixture.onRemove = function() leak = entity(3, 1000, 300) end
            end)
            assert(leak.alive and #restarts==2, output())
            assert(output():find('orphan gameplay entity: 1000:1:2:300 ptr=3',1,true), output())
        ''')


if __name__ == '__main__':
    unittest.main()
