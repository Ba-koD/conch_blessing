"""Run the shipped `conch_test kronos detail` barrier section against a fixture world.

The world below is a double: it decides when a shot touches the player and what
blocks it. It checks the bench's own sequence (wait for the absorbed barrier and
the damage cooldown, place one real projectile, follow it, report its fate),
not Isaac's collision engine.
"""
import unittest

import test_item_bench as shared


class KronosBarrierFixture(unittest.TestCase):
    run_lua = shared.BenchTests.run_lua

    def setUp(self):
        shared.BenchTests.setUp(self)
        self.run_lua(r'''
            local function autoIds(start)
                local next = start
                return setmetatable({}, {__index=function(t, k)
                    next = next + 1; rawset(t, k, next); return next
                end})
            end
            CollectibleType = autoIds(100); FamiliarVariant = autoIds(500); Card = autoIds(700)
            TrinketType = autoIds(800); UseFlag = autoIds(900); PickupVariant = autoIds(950)
            RoomType = autoIds(1100); EffectVariant = autoIds(1200); HeartSubType = autoIds(1300)
            EntityType = { ENTITY_PICKUP=5, ENTITY_PROJECTILE=9, ENTITY_FAMILIAR=3, ENTITY_FATTY=208,
                ENTITY_POOTER=14, ENTITY_EFFECT=1000 }
            ModCallbacks.MC_PRE_GAME_EXIT = 90
            Direction = { NO_DIRECTION=-1, LEFT=0, UP=1, RIGHT=2, DOWN=3 }
            ProjectileFlags = { CANT_HIT_PLAYER=1 }
            local V = {}
            V.__index = V
            Vector = setmetatable({}, {__call=function(_, x, y) return setmetatable({X=x, Y=y}, V) end})
            V.__add = function(a, b) return Vector(a.X + b.X, a.Y + b.Y) end
            V.__sub = function(a, b) return Vector(a.X - b.X, a.Y - b.Y) end
            V.__mul = function(a, b) return Vector(a.X * b, a.Y * b) end
            function V:Length() return math.sqrt(self.X * self.X + self.Y * self.Y) end
            function V:Distance(o) return (self - o):Length() end
            Vector.Zero = Vector(0, 0)

            frame = 0
            Game = function() return { GetFrameCount=function() return frame end } end
            GetPtrHash = function(e) return e.hash end
            EntityPtr = function(e)
                return setmetatable({}, {__index=function(_, k) if k == 'Ref' and e.alive then return e end end})
            end
            Isaac.GetItemIdByName = function() return 990 end

            -- Player one: holds Kronos; Kronos absorbs familiars on the next update.
            SWORN = CollectibleType.COLLECTIBLE_SWORN_PROTECTOR
            world = { owned = {}, cooldown = 0, head = Direction.DOWN, hearts = 12, shots = {},
                blockers = {}, absorbDelay = 1, pending = 0 }
            player = { Position = Vector(300, 200), hash = 1 }
            function player:GetCollectibleNum(id) return world.owned[id] or 0 end
            function player:AddCollectible(id) world.owned[id] = (world.owned[id] or 0) + 1; world.pending = world.absorbDelay end
            function player:GetDamageCooldown() return world.cooldown end
            function player:GetHeadDirection() return world.head end
            function player:GetHearts() return world.hearts end
            function player:GetSoulHearts() return 0 end
            function player:GetEffects() return { GetCollectibleEffectNum=function() return 0 end } end

            ConchBlessing.kronos = { _counters = {}, _test = { TRANSFER_TOTAL=1, VALUE_TOTAL=1 } }
            ConchBlessing.EIDDynamicTokens = { KRONOS_BLOCK=function() return '100%' end }
            local counters = ConchBlessing.kronos._counters
            local function bump(name) counters[name] = (counters[name] or 0) + 1 end

            Isaac.Spawn = function(kind, variant, subtype, position, velocity, spawner)
                assert(kind == EntityType.ENTITY_PROJECTILE, 'barrier fixture spawned a non-projectile')
                local shot = { Type=kind, Variant=variant, SubType=subtype, Position=position, Velocity=velocity,
                    spawner=spawner, alive=true, hash=1000 + #world.shots, flags=0 }
                function shot:Exists() return self.alive end
                function shot:ToProjectile() return self end
                function shot:HasProjectileFlags(f) return self.flags & f ~= 0 end
                function shot:Remove() self.alive = false end
                world.shots[#world.shots + 1] = shot
                return shot
            end

            -- One update of the double: absorption, cooldown, shot travel, the
            -- blockers standing in the room, then the player collision (radius 10 +
            -- shot 7). A hit outside the cooldown reaches Kronos's 100% barrier and
            -- pops the shot; during the cooldown, or flagged CANT_HIT_PLAYER, the shot
            -- passes through the player.
            ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
                frame = frame + 1
                if world.pending > 0 then
                    world.pending = world.pending - 1
                    if world.pending == 0 then world.owned[SWORN] = 0 end
                end
                if world.cooldown > 0 then world.cooldown = world.cooldown - 1 end
                for _, shot in ipairs(world.shots) do
                    if shot.alive then
                        shot.Position = shot.Position + shot.Velocity
                        for _, blocker in ipairs(world.blockers) do
                            if blocker(shot) then shot:Remove(); break end
                        end
                    end
                    if shot.alive and shot.Position:Distance(player.Position) < 17
                        and world.cooldown == 0 and shot.flags & ProjectileFlags.CANT_HIT_PLAYER == 0 then
                        bump('projectileBlocks'); bump('blockSparks')
                        shot:Remove()
                    end
                end
            end)

            local captured
            local register = bench.register
            bench.register = function(def) captured = def; return register(def) end
            probe = require('scripts.dev.kronos_probe')
            bench.register = register

            -- Collect the production plan, then run only its barrier section.
            local ops, current = {}, nil
            local recorder = {}
            local function add(op) op.section = current; ops[#ops + 1] = op end
            function recorder.section(title) current = title end
            function recorder.act(fn) add({kind='act', fn=fn}) end
            function recorder.note(label, fn) add({kind='note', label=label, fn=fn}) end
            function recorder.wait(n) add({kind='wait', n=n}) end
            function recorder.waitUntil(fn, n, label) add({kind='until', fn=fn, n=n, label=label}) end
            function recorder.check(label, fn) add({kind='check', label=label, fn=fn}) end
            function recorder.require(label, fn) add({kind='check', label=label, fn=fn}) end
            function recorder.eq(label, get, want)
                add({kind='check', label=label, fn=function(p, c)
                    local got = get(p, c); return got == want, 'got ' .. tostring(got) .. ', want ' .. tostring(want)
                end})
            end
            function recorder.atLeast(label, get, want)
                add({kind='check', label=label, fn=function(p, c) return get(p, c) >= want, '' end})
            end
            captured.build(recorder)
            barrierOps = {}
            for _, op in ipairs(ops) do if op.section == 'barrier' then barrierOps[#barrierOps + 1] = op end end

            function runBarrier()
                local ctx, results, notes, timedOut = {}, {}, {}, {}
                for _, op in ipairs(barrierOps) do
                    if op.kind == 'act' then op.fn(player, ctx)
                    elseif op.kind == 'wait' then for _ = 1, op.n do tick() end
                    elseif op.kind == 'until' then
                        local done = false
                        for _ = 1, op.n do tick(); if op.fn(player, ctx) then done = true; break end end
                        if not done then timedOut[#timedOut + 1] = op.label end
                    elseif op.kind == 'note' then notes[#notes + 1] = op.fn(player, ctx)
                    else
                        local ok, detail = op.fn(player, ctx)
                        results[op.label] = { ok = ok, detail = detail }
                    end
                end
                return results, table.concat(notes, '\n'), timedOut, ctx
            end
        ''')

    def test_barrier_section_is_extracted_from_the_shipped_plan(self):
        self.run_lua('''
            local labels = {}
            for _, op in ipairs(barrierOps) do if op.label then labels[#labels + 1] = op.label end end
            local all = table.concat(labels, '|')
            for _, want in ipairs({'projectile hit ignored', 'ignored hit shows its spark', 'no health lost',
                'barrier shot', 'all 20 Sworn Protectors absorbed before the shot'}) do
                assert(all:find(want, 1, true), 'missing barrier op: ' .. want .. ' in ' .. all)
            end
        ''')

    def test_one_real_projectile_reaches_the_barrier_and_is_ignored_once(self):
        self.run_lua('''
            local results, notes, timedOut = runBarrier()
            assert(#timedOut == 0, table.concat(timedOut, ', '))
            for label, r in pairs(results) do assert(r.ok, label .. ': ' .. tostring(r.detail)) end
            assert(#world.shots == 1, 'exactly one shot')
            local shot = world.shots[1]
            assert(shot.spawner == nil, 'the shot must not come from the proc-afflicted Fatty')
            assert(shot.Velocity.X == 0 and shot.Velocity.Y == 0)
            assert(notes:find('blocks=1 sparks=1', 1, true), notes)
            assert(notes:find('damage cooldown=0', 1, true), notes)
        ''')

    def test_shot_waits_for_absorption_and_the_damage_cooldown(self):
        self.run_lua('''
            world.absorbDelay = 25; world.cooldown = 60
            local results, notes = runBarrier()
            local shot = world.shots[1]
            assert(shot, 'no shot')
            assert(results['all 20 Sworn Protectors absorbed before the shot'].ok)
            assert(results['projectile hit ignored'].ok, results['projectile hit ignored'].detail)
            assert(notes:find('damage cooldown=0', 1, true), notes)
        ''')

    def test_shot_starts_inside_the_player_away_from_the_face(self):
        self.run_lua('''
            local inset = probe._test.BARRIER_SHOT_INSET
            for head, back in pairs({ [Direction.LEFT]={inset, 0}, [Direction.UP]={0, inset},
                [Direction.RIGHT]={-inset, 0}, [Direction.DOWN]={0, -inset}, [Direction.NO_DIRECTION]={0, -inset} }) do
                world.head = head
                local at = probe._test.barrierShotPosition(player)
                assert(at.X - player.Position.X == back[1] and at.Y - player.Position.Y == back[2],
                    'head ' .. head .. ' -> ' .. at.X .. ',' .. at.Y)
                assert(at:Distance(player.Position) < 10, 'shot must start inside the player collision circle')
            end
            player.GetHeadDirection = nil
            local at = probe._test.barrierShotPosition(player)
            assert(at.Y < player.Position.Y, 'without head direction the shot sits above (behind) the face')
        ''')

    def test_familiars_on_the_old_path_and_catches_in_front_do_not_intercept(self):
        self.run_lua('''
            world.head = Direction.RIGHT
            -- A blocker familiar standing 12px to the side the old shot started from,
            -- and an effect that swallows any shot in front of the face.
            world.blockers[1] = function(shot)
                return shot.Position:Distance(player.Position + Vector(16, 0)) < 13
            end
            world.blockers[2] = function(shot)
                local offset = shot.Position - player.Position
                return offset:Length() <= 120 and offset.X > 0 and math.abs(offset.Y) <= offset.X
            end
            local results, notes = runBarrier()
            assert(results['projectile hit ignored'].ok, notes)
            -- The same blockers would have swallowed the old shot (+12px, moving left).
            local old = Isaac.Spawn(EntityType.ENTITY_PROJECTILE, 0, 0, player.Position + Vector(12, 0), Vector(-4, 0), nil)
            local before = ConchBlessing.kronos._counters.projectileBlocks
            tick()
            assert(not old.alive and ConchBlessing.kronos._counters.projectileBlocks == before,
                'control: the old shot is intercepted before the player')
        ''')

    def test_a_shot_that_never_reaches_the_player_fails_with_its_fate(self):
        self.run_lua('''
            world.blockers[1] = function() return true end -- anything that eats every shot
            local results, notes, timedOut = runBarrier()
            assert(#timedOut == 0, 'bounded waits must not abort the rest of the bench')
            assert(not results['projectile hit ignored'].ok)
            assert(not results['ignored hit shows its spark'].ok)
            assert(results['no health lost'].ok)
            assert(notes:find('blocks=0 sparks=0', 1, true) and notes:find('gone after 1', 1, true), notes)
        ''')

    def test_a_shot_that_cannot_hit_the_player_is_reported(self):
        self.run_lua('''
            -- Another effect flags the shot so it passes through the player.
            world.blockers[1] = function(shot) shot.flags = ProjectileFlags.CANT_HIT_PLAYER; return false end
            local results, notes, timedOut = runBarrier()
            assert(#timedOut == 0, 'bounded waits must not abort the rest of the bench')
            assert(not results['projectile hit ignored'].ok)
            assert(notes:find('cannot hit player=true', 1, true) and notes:find('gone after nil', 1, true), notes)
        ''')


if __name__ == '__main__':
    unittest.main()
