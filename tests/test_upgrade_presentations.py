"""Frame-by-frame contracts of every applied upgrade presentation.

Runs the shipped renderer through the shared template exactly like a real
conversion (before phase, commit, after phase) and checks the cue schedule,
milestones, drawn curves, debug story and the in-game bench's own oracles.
Expected values come from the approved presentation decisions, not from the
renderer's tables. This is offline evidence; conch_test morph checks the engine.
"""
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
# Import the module, not the class, so its tests are not collected twice.
import test_morph_viewer as morph_harness  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CATALOG = (ROOT / 'scripts/upgrade_visual_catalog.lua').read_text(encoding='utf-8')
ROWS = []
for line in CATALOG.splitlines():
    m = re.search(r'key = "(\w+)", effect = "(\w+)", impact = (\d+)(?:, duration = (\d+))?', line)
    if m:
        ROWS.append((m[1], m[2], int(m[3]), int(m[4] or 102)))


def expected_cues(effect, impact):
    """The approved cue schedule: (sound, scheduled frame, volume, pitch)."""
    cues = []
    if effect == 'lightning':
        cues += [('SOUND_THUNDER', 2, 1, .65), ('Conch Upgrade Thunder Strike', impact, 1, 1)]
    if effect == 'saturn':
        cues += [('SOUND_MOTHER_SPIN_START', 56, 1, 1), ('SOUND_SUMMONSOUND', impact, 1, 1)]
    if effect in ('fire', 'ice'):
        cues += [('SOUND_CANDLE_LIGHT', 5, .8, 1), ('SOUND_FLAME_BURST', impact - 7, 1, 1)]
        if effect == 'ice':
            cues.append(('SOUND_FREEZE', impact, 1, 1))
    if effect == 'missile':
        cues += [('SOUND_DR_REMOTE_WARNING', 3, 1, 1), ('SOUND_ROCKET_LAUNCH', impact - 16, .8, 1),
                 ('SOUND_ROCKET_EXPLOSION', impact, 1, 1)]
    if effect == 'purify':
        cues += [('SOUND_ANGEL_WING', 18, 1, 1), ('SOUND_HOLY', impact, 1, 1)]
    if effect == 'rain':
        cues.append(('Conch Upgrade Rain', 5, 1, 1))
    if 'clock' in effect:
        # 6:00 to 12:00: one 째깍 per minute turn, evenly from frame 0 to the
        # change: 째 (Tick) as the hand passes 6, 깍 (Tock) as it reaches 12.
        cues += [('Conch Upgrade Clock Tick' if j % 2 else 'Conch Upgrade Clock Tock', int(impact * j / 12 + .5), 1, 1)
                 for j in range(1, 13)]
        # 댕: the bell strikes 12 together with the change, after the last 깍.
        cues.append(('Conch Upgrade Clock Bell', impact, 1, 1))
    cues.sort(key=lambda c: c[1])
    return ['%s|%d|%d|%.2f|%.2f' % (s, at, at, v, p) for s, at, v, p in cues]


class UpgradePresentationTests(unittest.TestCase):
    def setUp(self):
        morph_harness.MorphVisualTests.setUp(self)
        self.lua.execute('''
            updates=0; started={}; playMode=nil
            SoundEffect.SOUND_POWERUP_SPEWER=23
            local baseSFX=SFXManager
            SFXManager=function()
                local m=baseSFX(); local play=m.Play
                m.Play=function(self,id,...) play(self,id,...); started[id]=updates end
                if playMode then
                    m.IsPlaying=function(_,id)
                        if playMode=='now' then return started[id]~=nil end
                        if playMode=='next' then return started[id]~=nil and started[id]<updates end
                        return false
                    end
                end
                return m
            end
            -- Drive one real conversion: before phase, commit, after phase,
            -- two renders per update like the 60 Hz render loop.
            function runFull(key, debug, each)
                logs={}
                ConchBlessing.printDebug=function(t) logs[#logs+1]=t end
                ConchBlessing.Config={debugMode=debug==true}
                local p=pickup(); local state={}
                local custom=T.forItem(key,'positive')
                local before=custom.onBeforeChange(p.Position,p,state)
                local scene=state.morphScene
                local function tick()
                    updates=updates+1; T.updateAllAnimations()
                    for _,floor in ipairs(callbacks[ModCallbacks.MC_PRE_BACKDROP_RENDER_WATER] or {}) do floor() end
                    T.renderAllAnimations(); T.renderAllAnimations()
                    if each then each(scene,p) end
                end
                for i=1,before do tick() end
                p.SubType=999
                local after=custom.onAfterChange(p.Position,p,state)
                for i=1,after do tick() end
                ConchBlessing.Config=nil
                return scene,p,before,after
            end
            function cueList(scene)
                local out={}
                for _,c in ipairs(scene.cues) do
                    out[#out+1]=string.format('%s|%d|%d|%.2f|%.2f',V.cueName(c),c.at,c.frame,c.volume,c.pitch)
                end
                return table.concat(out,';')
            end
            function logsMatching(text)
                local n=0
                for _,line in ipairs(logs) do if line:find(text,1,true) then n=n+1 end end
                return n
            end
        ''')

    def run_key(self, key, debug=False):
        self.lua.execute("scene,p,before,after=runFull('%s',%s)" % (key, 'true' if debug else 'false'))

    def test_catalog_rows_parsed(self):
        self.assertEqual(len(ROWS), 13)

    def test_neglect_darkens_only_the_left_half_and_returns_gradually(self):
        self.lua.execute('''
            coverage={}
            scene=runFull('HEMISPATIAL_NEGLECT',false,function(s)
                local right,left=0,0
                for _,d in ipairs(drawings) do
                    if d.path and d.path:find('conch_upgrade_pixel',1,true) and d.color.A>0 and d.color.R==0 then
                        right=math.max(right,d.pos.X+d.scale.X)
                        if d.pos.X==0 then left=math.max(left,d.color.A) end
                    end
                end
                coverage[s.frame]={right,left}; drawings={}
            end)''')
        dark = self.lua.eval('scene.samples.neglect')
        for f in range(1, 7):
            self.assertEqual(dark[f], 0)
        steps = [dark[f] - dark[f - 1] for f in range(7, 43)]
        self.assertTrue(all(0 <= s <= .08 for s in steps), max(steps))
        for f in range(42, 67):
            self.assertEqual(dark[f], 1, 'black through the change (frame %d)' % f)
        back = [dark[f - 1] - dark[f] for f in range(67, 112)]
        self.assertTrue(all(0 <= s <= .05 for s in back), max(back))
        for f in range(111, 127):
            self.assertEqual(dark[f], 0)
        coverage = self.lua.eval('coverage')
        # The darkness never crosses the soft edge past the middle (640 px wide screen).
        for f in range(1, 127):
            if coverage[f][1] > 0:
                self.assertLessEqual(coverage[f][1], 320 + 12)
        self.assertEqual(coverage[50][2], 1, 'the left half is fully black')
        self.assertEqual(self.lua.eval('scene.neglectMid'), 320)
        self.assertEqual(self.lua.eval('#scene.cues'), 0)

    def test_every_time_item_shares_one_plain_clock(self):
        clocks = [(key, effect, impact, duration) for key, effect, impact, duration in ROWS if key.startswith('TIME_')]
        self.assertEqual(clocks, [(k, 'clock', 96, 150) for k in ('TIME_MONEY', 'TIME_POWER', 'TIME_TEAR', 'TIME_LUCK')])
        for key, *_ in clocks:
            with self.subTest(key=key):
                # Only the item and the three clock parts are ever drawn: no coins, no power bar.
                self.lua.execute('''
                    extra={}
                    local s=V.create('%s',Vector(320,180))
                    for f=0,s.duration do
                        s.frame=f; drawings={}; V.render(s)
                        for _,d in ipairs(drawings) do
                            local clockPart=d.path and d.path:find('conch_upgrade_clock_',1,true)
                            local item=d.sheet==s.before.sheet or d.sheet==s.after.sheet
                            if not clockPart and not item then extra[#extra+1]=f..':'..tostring(d.path) end
                        end
                    end''' % key)
                self.assertEqual(self.lua.eval('#extra'), 0, self.lua.eval('table.concat(extra," ")'))

    def test_clock_runs_six_hours_at_constant_speed_with_one_tick_tock_per_turn(self):
        for key, effect, impact, duration in ROWS:
            if 'clock' not in effect:
                continue
            with self.subTest(key=key):
                self.assertEqual((impact, duration), (96, 150), 'every time item takes Time = Tears timing')
                self.run_key(key)
                beats = self.lua.eval('(function() local t={} for _,c in ipairs(scene.cues) do '
                                      't[#t+1]=V.cueName(c):sub(-4)..c.frame end return table.concat(t,",") end)()')
                # Continuous 째깍 every 8 frames, 째 (Tick) first, the last 깍 on the
                # change, and the bell (댕) striking 12 with it.
                want = ['%s%d' % ('Tick' if j % 2 else 'Tock', 8 * j) for j in range(1, 13)] + ['Bell96']
                self.assertEqual(beats.split(','), want)
                minute = self.lua.eval('scene.samples.minute')
                hour = self.lua.eval('scene.samples.hour')
                for j in range(1, 13):
                    f = 8 * j
                    self.assertAlmostEqual(minute[f], 180 * j, places=6, msg='째 at 6, 깍 at 12 (beat %d)' % j)
                    self.assertAlmostEqual(hour[f], 180 + 15 * j, places=6)
                steps = [minute[f] - minute[f - 1] for f in range(2, 97)]
                self.assertTrue(all(abs(step - 22.5) < 1e-9 for step in steps), 'one constant speed: 22.5 degrees per frame')
                self.assertAlmostEqual(minute[1], 22.5, places=9, msg="moving from 6 o'clock at the start")
                self.assertEqual(minute[duration], 2160)
                self.assertEqual(hour[duration] % 360, 0, '12 o\'clock at the end')

    def test_time_tear_has_a_clock_and_no_rain(self):
        self.run_key('TIME_TEAR')
        self.assertEqual(self.lua.eval('scene.profile.effect'), 'clock')
        self.assertEqual(self.lua.eval('#scene.floorCells'), 0)
        self.assertIsNone(self.lua.eval('scene.drops'))
        self.assertIsNone(self.lua.eval('scene.samples.wet'))
        self.assertEqual(self.lua.eval('logsMatching("Conch Upgrade Rain")'), 0)
        self.assertNotIn('Conch Upgrade Rain', self.lua.eval('cueList(scene)'))
        tint = self.lua.eval('scene.samples.tint')
        self.assertTrue(all(list(tint[f].values()) == [1, 1, 1, 1, 0, 0, 0] for f in range(1, 151)), 'item never tinted')

    def test_every_presentation_plays_its_exact_cue_schedule_once(self):
        for key, effect, impact, _ in ROWS:
            with self.subTest(key=key):
                self.lua.execute("sounds={}")
                self.run_key(key)
                got = self.lua.eval('cueList(scene)')
                want = ';'.join(expected_cues(effect, impact))
                self.assertEqual(got, want)
                # Each cue reached SFXManager exactly once, in schedule order.
                self.assertTrue(self.lua.eval('''(function()
                    if #sounds~=#scene.cues then return false end
                    for i,c in ipairs(scene.cues) do if sounds[i]~=c.id then return false end end
                    return true end)()'''))
                self.assertEqual(self.lua.eval('#errors'), 0)

    def test_every_presentation_reaches_and_draws_its_last_frame(self):
        for key, effect, impact, duration in ROWS:
            with self.subTest(key=key):
                self.run_key(key)
                self.assertEqual(self.lua.eval('scene.endReason'), 'after:complete')
                self.assertEqual(self.lua.eval('scene.endFrame'), duration)
                self.assertEqual(self.lua.eval('before'), impact)
                self.assertEqual(self.lua.eval('after'), duration - impact + 2)
                missing = self.lua.eval('''(function() local m={}
                    for f=1,scene.duration do if not scene.rendered[f] then m[#m+1]=f end end
                    return table.concat(m,',') end)()''')
                self.assertEqual(missing, '', 'frames never drawn')
                self.assertEqual(self.lua.eval('#T._activeAnimations'), 0)
                self.assertTrue(self.lua.eval('p.sprite.Color.original and p.sprite:GetLayer(1):IsVisible()'))

    def test_every_milestone_is_marked_exactly_on_its_frame(self):
        for key, effect, impact, duration in ROWS:
            with self.subTest(key=key):
                self.run_key(key)
                late = self.lua.eval('''(function() local bad={}
                    for _,m in ipairs(V.milestones(scene)) do
                        if scene.marks[m.name]~=m.frame then bad[#bad+1]=m.name..'@'..tostring(scene.marks[m.name]) end
                    end return table.concat(bad,' ') end)()''')
                self.assertEqual(late, '')
                self.assertEqual(self.lua.eval('scene.marks.commit'), impact)
                self.assertEqual(self.lua.eval('scene.marks["end"]'), duration)

    def test_late_commit_never_replays_any_lead_in_cue(self):
        for key, effect, impact, _ in ROWS:
            with self.subTest(key=key):
                self.lua.execute('''
                    sounds={}
                    local s=V.create('%s',Vector(320,180),100,1,%d); s.holdFrame=true
                    for i=1,s.duration do V.update(s) end
                    late=cueList(s)''' % (key, impact))
                # Only the cues scheduled on the change itself may play.
                want = ';'.join(c for c in expected_cues(effect, impact) if int(c.split('|')[1]) >= impact)
                self.assertEqual(self.lua.eval('late'), want)

    def test_kronos_darkens_to_black_late_and_regains_colour_gradually(self):
        self.lua.execute('''
            tints={}
            scene,p=runFull('KRONOS',false,function(s,p)
                for _,d in ipairs(drawings) do
                    if d.native==p.sprite then tints[s.frame]=d.color end
                end
                drawings={}
            end)''')
        black = self.lua.eval('scene.samples.black')
        for f in range(1, 71):
            self.assertEqual(black[f], 0, 'dark too early at %d' % f)
        for f in range(71, 120):
            self.assertGreater(black[f], black[f - 1] - 1e-12)
        self.assertGreaterEqual(black[119], .95)
        self.assertEqual(black[120], 1)
        steps = [black[f - 1] - black[f] for f in range(121, 166)]
        self.assertTrue(all(-1e-12 <= s <= .05 for s in steps), max(steps))
        self.assertLess(max(steps), .04, 'colour return should be spread over 45 frames')
        for f in range(165, 171):
            self.assertLess(black[f], 1e-9)
        # The item is actually drawn with that tint: scaled toward black, nothing added.
        for f in (100, 119, 120, 130, 142, 160):
            color = self.lua.eval('tints[%d]' % f)
            self.assertAlmostEqual(color['RO'], 0, places=6)
            self.assertAlmostEqual(color['R'], 1 - black[f], places=6)
            self.assertAlmostEqual(color['A'], .8, places=6)

    def test_kronos_pets_appear_already_riding_the_orbit(self):
        self.lua.execute("scene=runFull('KRONOS')")
        self.assertEqual(self.lua.eval('#scene.pets'), 3)
        for born in (4, 12, 20):
            # The ring has turned before each pet's first visible frame and keeps turning.
            turn = self.lua.eval('require("scripts.lib.upgrade_devour").ring(scene,%d,0,0,function(a,b,x) '
                                 'local p=math.max(0,math.min(1,(x-a)/(b-a))) return p*p*(3-2*p) end).turn' % born)
            nxt = self.lua.eval('require("scripts.lib.upgrade_devour").ring(scene,%d,0,0,function(a,b,x) '
                                'local p=math.max(0,math.min(1,(x-a)/(b-a))) return p*p*(3-2*p) end).turn' % (born + 1))
            self.assertGreater(turn, 0)
            self.assertGreater(nxt, turn)

    def test_dragon_darkness_rises_holds_and_clears_on_the_strike(self):
        self.run_key('DRAGON')
        dark = self.lua.eval('scene.samples.darkness')
        for f in range(1, 3):
            self.assertEqual(dark[f], 0)
        for f in range(3, 18):
            self.assertGreater(dark[f], dark[f - 1])
        for f in range(18, 70):
            self.assertAlmostEqual(dark[f], .88, places=9)
        for f in range(70, 128):
            self.assertEqual(dark[f], 0)
        self.assertTrue(self.lua.eval('scene.pickupVisual.released'), 'native result shows from the commit')

    def test_rain_drops_land_on_schedule_and_soak_then_dry(self):
        for key in ('MONEY_TEAR',):
            with self.subTest(key=key):
                self.run_key(key)
                lands = [self.lua.eval('scene.marks["drop%d-lands"]' % k) for k in range(1, 6)]
                self.assertEqual(lands, [24, 40, 56, 72, 88])
                wet = self.lua.eval('scene.samples.wet')
                for f in range(1, 24):
                    self.assertEqual(wet[f], 0)
                for f in range(25, 96):
                    self.assertGreaterEqual(wet[f], wet[f - 1] - 1e-12)
                self.assertAlmostEqual(wet[95], 1, places=9)
                # No snap at the change: the result starts wet and dries over 45 frames.
                self.assertAlmostEqual(wet[96], 1, places=9)
                steps = [wet[f - 1] - wet[f] for f in range(97, 142)]
                self.assertTrue(all(-1e-12 <= x <= .04 for x in steps), max(steps))
                for f in range(141, 175):
                    self.assertEqual(wet[f], 0)

    def test_void_motes_keep_density_then_vanish_within_three_frames(self):
        self.lua.execute('''
            smokeCounts={}
            scene=runFull('VOID_DAGGER',false,function(s)
                local n=0
                for _,d in ipairs(drawings) do if d.path and d.path:find('smoke',1,true) then n=n+1 end end
                smokeCounts[s.frame]=n; drawings={}
            end)''')
        vanish = self.lua.eval('scene.samples.vanish')
        for f in range(1, 52):
            self.assertEqual(vanish[f], 0)
        self.assertAlmostEqual(vanish[52], 1 / 3)
        self.assertEqual(vanish[54], 1)
        counts = self.lua.eval('smokeCounts')
        # All 18 motes stay drawn (2 renders each) right up to the change.
        for f in range(45, 51):
            self.assertEqual(counts[f], 36, 'frame %d' % f)
        self.assertEqual(counts[54], 0)

    def test_flames_conceal_the_change_and_reveal_the_result(self):
        for key in ('ICE_BREATH', 'FIRE_BREATH'):
            with self.subTest(key=key):
                self.run_key(key)
                alpha = self.lua.eval('scene.samples.itemAlpha')
                for f in range(1, 25):
                    self.assertEqual(alpha[f], 1)
                self.assertLess(alpha[44], .01)
                self.assertEqual(alpha[45], 0)
                for f in range(68, 103):
                    self.assertEqual(alpha[f], 1)

    def test_crown_whitens_fully_then_returns_before_the_end(self):
        self.run_key('ANGELS_CROWN')
        white = self.lua.eval('scene.samples.white')
        for f in range(38, 50):
            self.assertAlmostEqual(white[f], 1, places=9)
        for f in range(94, 103):
            self.assertAlmostEqual(white[f], 0, places=9)

    def test_every_presentation_colour_eases_and_ends_on_the_items_own_colour(self):
        for key, effect, impact, duration in ROWS:
            with self.subTest(key=key):
                self.run_key(key)
                tint = self.lua.eval('scene.samples.tint')
                worst = 0
                for f in range(2, duration + 1):
                    worst = max(worst, max(abs(tint[f][i] - tint[f - 1][i]) for i in range(1, 8)))
                self.assertLessEqual(worst, .08, 'colour snapped')
                self.assertEqual([tint[duration][i] for i in range(1, 8)], [1, 1, 1, 1, 0, 0, 0])
                # The native pedestal ends on its own (semi-transparent) colour.
                self.assertTrue(self.lua.eval('p.sprite.Color.original and p.sprite.Color.A==.8'))

    def test_default_animations_hold_through_the_commit_and_ease_back(self):
        for flag in ('positive', 'neutral', 'negative'):
            with self.subTest(flag=flag):
                self.lua.execute('''
                    local p=pickup(); local s=borrowSpriteProperties(p.sprite)
                    s.Color=Color(.9,.8,.7,.6,.05,.04,.03)
                    local original=Color.Lerp(s.Color,s.Color,0)
                    local state={}; trail={}
                    local function sample() local c=s.Color; trail[#trail+1]={c.R,c.G,c.B,c.A,c.RO,c.GO,c.BO} end
                    local before=T.%(flag)s.onBeforeChange(p.Position,p,state); sample()
                    -- The template may finish counting before the transaction commits.
                    for i=1,before+5 do T.updateAllAnimations(); sample() end
                    held={trail[#trail][1],trail[#trail][2],trail[#trail][3],trail[#trail][5]}
                    heldActive=#T._activeAnimations
                    T.cancelForPickup(p,true)
                    p.SubType=456
                    local after=T.%(flag)s.onAfterChange(p.Position,p,state); sample()
                    for i=1,after+1 do T.updateAllAnimations(); sample() end
                    finalSame=(s.Color==original)
                    activeAfter=#T._activeAnimations''' % {'flag': flag})
                trail = list(self.lua.eval('trail').values())
                worst = max(max(abs(trail[k][i] - trail[k - 1][i]) for i in range(1, 8)) for k in range(1, len(trail)))
                self.assertLessEqual(worst, .08, 'default colour snapped')
                self.assertEqual(self.lua.eval('heldActive'), 1, 'the before tint holds until the commit')
                self.assertNotAlmostEqual(trail[0][1], trail[61][1] if flag != 'neutral' else trail[61][2], places=3)
                self.assertTrue(self.lua.eval('finalSame'), 'ends exactly on the pedestal colour')
                self.assertEqual(self.lua.eval('activeAfter'), 0)

    def test_default_hold_is_bounded_without_a_commit(self):
        self.lua.execute('''
            p=pickup(); local state={}
            T.neutral.onBeforeChange(p.Position,p,state)
            for i=1,60+89 do T.updateAllAnimations() end
            stillHeld=#T._activeAnimations
            T.updateAllAnimations(); T.updateAllAnimations()
            released=#T._activeAnimations''')
        self.assertEqual(self.lua.eval('stillHeld'), 1)
        self.assertEqual(self.lua.eval('released'), 0)
        self.assertTrue(self.lua.eval('p.sprite.Color.original'))

    def test_debug_off_writes_no_presentation_lines(self):
        self.lua.execute("playMode='now'")
        self.run_key('KRONOS')
        self.assertEqual(self.lua.eval('logsMatching("[ConchMorph]")'), 0)
        self.assertEqual(self.lua.eval('logsMatching("[Upgrade] RESTORE")'), 0)

    def test_debug_on_tells_the_whole_story_once(self):
        self.lua.execute("playMode='now'")
        for key, effect, impact, duration in ROWS:
            with self.subTest(key=key):
                self.run_key(key, debug=True)
                count = lambda text: self.lua.eval('logsMatching(%r)' % text)
                self.assertEqual(count('[ConchMorph] SCENE %s ' % key), 1)
                self.assertEqual(count('[ConchMorph] BEGIN %s ' % key), 1)
                self.assertEqual(count('[ConchMorph] COMMIT %s ' % key), 1)
                milestones = self.lua.eval('#V.milestones(scene)')
                self.assertEqual(count('[ConchMorph] MARK %s ' % key), milestones)
                cues = len(expected_cues(effect, impact))
                self.assertEqual(count('[ConchMorph] SOUND %s ' % key), cues)
                self.assertEqual(count('playing=true/'), cues)
                summary = [line for line in self.lua.eval('logs').values() if '[ConchMorph] SUMMARY %s ' % key in line]
                self.assertEqual(len(summary), 1)
                self.assertIn('reason=after:complete cues=%d heard=%d' % (cues, cues), summary[0])
                self.assertIn('missing=none', summary[0])
                self.assertIn('marks=%d/%d' % (milestones, milestones), summary[0])
                self.assertEqual(count('[Upgrade] RESTORE type=custom phase=after'), 1)

    def test_kronos_debug_marks_record_the_colour_return(self):
        self.run_key('KRONOS', debug=True)
        lines = list(self.lua.eval('logs').values())
        marks = {m[1]: m[2] for line in lines for m in [re.search(r'MARK KRONOS frame=\d+/170 (\S+) at=\d+ black=([\d.]+)', line)] if m}
        self.assertEqual(marks['commit'], '1.00')
        self.assertTrue(.5 < float(marks['colour+15']) < 1)
        self.assertTrue(0 < float(marks['colour+30']) < .5)
        self.assertEqual(marks['colour+45'], '0.00')

    def test_cue_heard_is_rechecked_on_the_next_update(self):
        self.lua.execute("playMode='next'")
        self.run_key('SOFLAM', debug=True)
        self.assertTrue(self.lua.eval('(function() for _,c in ipairs(scene.cues) do '
                                      'if c.now~=false or c.next~=true or not c.heard then return false end end return true end)()'))
        self.assertEqual(self.lua.eval('logsMatching("playing=false/true")'), 3)
        self.lua.execute("playMode='never'")
        self.run_key('SOFLAM', debug=True)
        self.assertTrue(self.lua.eval('(function() for _,c in ipairs(scene.cues) do '
                                      'if c.heard then return false end end return true end)()'))
        self.assertEqual(self.lua.eval('logsMatching("playing=false/false")'), 3)
        self.assertEqual(self.lua.eval('logsMatching("heard=0")'), 1)

    def test_cancel_and_render_failure_each_write_one_summary(self):
        self.lua.execute('''
            logs={}; ConchBlessing.printDebug=function(t) logs[#logs+1]=t end
            ConchBlessing.Config={debugMode=true}
            local p=pickup(); local state={}; local custom=T.forItem('DRAGON','positive')
            custom.onBeforeChange(p.Position,p,state)
            for i=1,10 do T.updateAllAnimations(); T.renderAllAnimations() end
            T.cancelForPickup(p); T.cancelForPickup(p)
            cancelSummaries=logsMatching('SUMMARY DRAGON frame=10/127 reason=before:cancelled')
            logs={}
            local q=pickup(); state={}; custom.onBeforeChange(q.Position,q,state)
            T.updateAllAnimations(); drawFails=true; T.renderAllAnimations(); drawFails=false
            for i=1,3 do T.updateAllAnimations(); T.renderAllAnimations() end
            failSummaries=logsMatching('SUMMARY DRAGON')
            failReason=logsMatching('reason=before:render-failed')
            ConchBlessing.Config=nil''')
        self.assertEqual(self.lua.eval('cancelSummaries'), 1)
        self.assertEqual(self.lua.eval('failSummaries'), 1)
        self.assertEqual(self.lua.eval('failReason'), 1)

    def test_real_transaction_commit_does_not_end_the_scene_early(self):
        # The queue retires the before phase at its commit; the scene continues.
        morph_harness.MorphVisualTests.viewer(self)
        self.lua.execute('''
            logs={}; ConchBlessing.printDebug=function(t) logs[#logs+1]=t end
            ConchBlessing.Config={debugMode=true}
            event(6,'conch_morph','void_dagger')
            for tick=1,200 do event(1); event(2) end
            ConchBlessing.Config=nil''')
        self.assertEqual(self.lua.eval('logsMatching("SUMMARY VOID_DAGGER")'), 1)
        self.assertEqual(self.lua.eval('logsMatching("reason=after:complete")'), 1)
        self.assertEqual(self.lua.eval('logsMatching("before:cancelled")'), 0)
        self.assertEqual(self.lua.eval('logsMatching("COMMIT VOID_DAGGER")'), 1)

    def test_chained_before_to_after_phase_is_one_scene(self):
        self.run_key('KRONOS', debug=True)
        self.assertEqual(self.lua.eval('logsMatching("SUMMARY KRONOS")'), 1)
        self.assertEqual(self.lua.eval('logsMatching("reason=replaced")'), 0)


class MorphBenchOracleTests(unittest.TestCase):
    """conch_test morph's checks pass on correct runs and catch each defect."""

    def setUp(self):
        UpgradePresentationTests.setUp(self)
        self.lua.execute('''
            benches={}
            testModules['scripts.dev.test_bench'].register=function(def) benches[def.command]=def end
            Probe=require('scripts.dev.morph_probe')
            function checksFor(command)
                local checks,order={},{}
                local plan=setmetatable({check=function(label,fn) checks[label]=fn; order[#order+1]=label end},
                    {__index=function() return function() end end})
                benches[command].build(plan)
                return checks,order
            end
            function contextFor(key, scene, p)
                local item=ConchBlessing.ItemData[key]
                p.Variant=item.type=='trinket' and PickupVariant.PICKUP_TRINKET or PickupVariant.PICKUP_COLLECTIBLE
                p.SubType=item.id; p.Visible=true
                p.ToPickup=function(self) return self end
                return {scene=scene, job={status='complete',templateState={}},
                    fixture={ptr=EntityPtr(p),hash=GetPtrHash(p)}, originalColor={1,1,1,.8,0,0,0}}
            end
            function runChecks(key, mutate)
                local scene,p=runFull(key)
                local ctx=contextFor(key,scene,p)
                if mutate then mutate(ctx,scene,p) end
                local checks,order=checksFor('conch_test morph '..string.lower(key))
                local failed={}; checked=0; skipped=0
                for _,label in ipairs(order) do
                    if label:find(key..':',1,true)==1 then
                        local ok,detail=checks[label](nil,ctx)
                        checked=checked+1
                        if ok==nil then skipped=skipped+1 end
                        if ok==false then failed[#failed+1]=label..' ('..tostring(detail)..')' end
                    end
                end
                return table.concat(failed,' | ')
            end
            playMode='now'
        ''')

    def test_registers_all_and_per_item_commands(self):
        commands = set(self.lua.eval('benches').keys())
        self.assertIn('conch_test morph', commands)
        self.assertIn('conch_test morph default', commands)
        for key, *_ in ROWS:
            self.assertIn('conch_test morph ' + key.lower(), commands)
        self.assertEqual(self.lua.eval('Probe.commandFor("kronos")'), 'conch_test morph kronos')
        self.assertEqual(self.lua.eval('Probe.commandFor("angels crown")'), 'conch_test morph angels_crown')
        self.assertIsNone(self.lua.eval('Probe.commandFor("live_eye")'), 'pending items have no applied bench')

    def test_rotating_pedestal_stage_passes_a_correct_wheel_and_catches_each_defect(self):
        self.assertIn('conch_test morph cycle', set(self.lua.eval('benches').keys()))
        self.assertEqual(self.lua.eval('Probe.commandFor("cycle")'), 'conch_test morph cycle')
        self.lua.execute('''
            function cycleRun(mutate)
                local checks,order={},{}
                benches['conch_test morph cycle'].build(setmetatable({
                    check=function(label,fn) checks[label]=fn; order[#order+1]=label end},
                    {__index=function() return function() end end}))
                local source,target=7,ConchBlessing.ItemData.LIVE_EYE.id
                local wheel={entity={SubType=1,cycle={2,target}}, source={source,1,2}, target={target,1,2}, turns={}}
                function wheel.entity:GetCollectibleCycle() return self.cycle end
                local function turn(committed, t)
                    t=t or {}
                    wheel.turns[#wheel.turns+1]={ptr=t.ptr~=false, data=t.data~=false, seed=true, morphs=t.morphs or 0,
                        circle=t.circle~=false, committed=committed, locked=t.locked}
                end
                for i=1,3 do turn(false) end
                local ctx={wheel=wheel, turnsBefore=3, job={status='complete',committed=true,endReason='complete'},
                    offShow={jobs=0, shown=1, kept=true, now='1,2,7'}}
                turn(false,{locked=true}); turn(true); turn(true)
                if mutate then mutate(ctx,wheel,turn) end
                local failed,skipped={},{}
                for _,label in ipairs(order) do
                    local ok,detail=checks[label](nil,ctx)
                    if ok==false then failed[#failed+1]=label end
                    if ok==nil then skipped[#skipped+1]=label end
                end
                return table.concat(failed,' | '), table.concat(skipped,' | '), #order
            end
        ''')
        failed, skipped, count = self.lua.eval('cycleRun()')
        self.assertEqual((failed, skipped), ('', ''))
        self.assertGreaterEqual(count, 7)
        defects = {
            'native turns keep the same circle': 'function(c,w) w.turns[2].circle=false end',
            'arrives as a Morph': 'function(c,w) w.turns[1].ptr=false end',
            'commits while the pedestal turns':
                "function(c) c.job.status='cancelled'; c.job.committed=false; c.job.endReason='expired' end",
            'stayed locked': 'function(c,w) w.turns[4].locked=false end',
            'another choice shows': 'function(c) c.offShow.jobs=1 end',
            'every other choice stayed': 'function(c,w) w.entity.cycle={7,2} end',
            'turns through the new circle': 'function(c,w) w.turns[6].circle=false end',
        }
        for label, mutate in defects.items():
            with self.subTest(defect=label):
                failed, _, _ = self.lua.eval('cycleRun(%s)' % mutate)
                self.assertIn(label, failed)
                self.assertEqual(len(failed.split(' | ')), 1, failed)
        # A re-initializing turn that raised the Morph callback is followable.
        failed, _, _ = self.lua.eval("cycleRun(function(c,w) w.turns[1].ptr=false; w.turns[1].data=false; w.turns[1].morphs=1 end)")
        self.assertEqual(failed, '')
        # No native turn before the change cannot prove anything: SKIP, not PASS.
        _, skipped, _ = self.lua.eval("cycleRun(function(c,w) table.remove(w.turns,4) end)")
        self.assertIn('turned before the change', skipped)

    def test_bench_cue_oracle_matches_the_approved_schedule(self):
        for key, effect, impact, _ in ROWS:
            with self.subTest(key=key):
                got = self.lua.eval('''(function() local out={}
                    for _,c in ipairs(Probe.expectedCues('%s',%d)) do
                        out[#out+1]=string.format('%%s|%%d|%%d|%%.2f|%%.2f',c.sound,c.at,c.at,c.volume,c.pitch)
                    end return table.concat(out,';') end)()''' % (effect, impact))
                self.assertEqual(got, ';'.join(expected_cues(effect, impact)))

    def test_every_check_passes_on_a_correct_run(self):
        for key, effect, *_ in ROWS:
            with self.subTest(key=key):
                self.assertEqual(self.lua.eval("runChecks('%s')" % key), '')
                # 3 common + 4 timing/cue checks, plus the effect's own checks.
                # 3 common + 4 timing/cue + 1 colour checks, plus the effect's own.
                self.assertGreaterEqual(self.lua.eval('checked'), 8)
                self.assertEqual(self.lua.eval('skipped'), 0)

    def test_every_registered_bench_builds_a_plan(self):
        sizes = self.lua.eval('''(function() local out={}
            for command,def in pairs(benches) do
                local n=0
                def.build(setmetatable({}, {__index=function() return function() n=n+1 end end}))
                out[command]=n
            end return out end)()''')
        for command, n in sizes.items():
            self.assertGreater(n, 5, command)
        self.assertGreater(sizes['conch_test morph'], sizes['conch_test morph kronos'] * 10)

    def test_default_flag_stage_checks_pass_on_the_shipped_templates(self):
        self.lua.execute("SoundEffect.SOUND_POWERUP_SPEWER=23")
        for flag, key in (('positive', 'LIVE_EYE'), ('neutral', 'ROUND'), ('negative', 'FLOOR')):
            with self.subTest(flag=flag):
                result = self.lua.eval('''(function()
                    local checks,waits={},{}
                    benches['conch_test morph default'].build(setmetatable({
                        check=function(label,fn) checks[label]=fn end,
                        waitUntil=function(fn,_,label) waits[label]=fn end},
                        {__index=function() return function() end end}))
                    local p=pickup(); local state={}
                    local ctx=contextFor('%(key)s',{},p)
                    ctx.job={status='queued',templateState=state}
                    local item=ConchBlessing.ItemData['%(key)s']
                    local variant,subType=p.Variant,p.SubType
                    p.Variant=100; p.SubType=1
                    local before=T['%(flag)s'].onBeforeChange(p.Position,p,state)
                    local failed={}
                    local function run(fn,label)
                        if not fn then failed[#failed+1]='missing '..label; return end
                        local ok,detail=fn(nil,ctx)
                        if ok~=true then failed[#failed+1]=label..' ('..tostring(detail)..')' end
                    end
                    run(waits['%(key)s: default animation starts'],'starts')
                    run(checks['%(key)s: uses the flag animation, not an applied presentation'],'flag animation')
                    for label,fn in pairs(waits) do
                        if label:find('%(key)s:',1,true)==1 and label:find('cue is playing',1,true) then run(fn,label) end
                    end
                    trailDuringRun={}
                    local function record() local c=p.sprite.Color; trailDuringRun[#trailDuringRun+1]={c.R,c.G,c.B,c.A,c.RO,c.GO,c.BO} end
                    for i=1,before do T.updateAllAnimations(); record() end
                    T.cancelForPickup(p,true)
                    p.Variant,p.SubType=variant,subType
                    local after=T['%(flag)s'].onAfterChange(p.Position,p,state); record()
                    for i=1,(after or 60)+1 do T.updateAllAnimations(); record() end
                    ctx.job.status='complete'
                    -- The bench samples the real sprite colour every update.
                    ctx.colorTrail={}
                    local function sample() local c=p.sprite.Color; ctx.colorTrail[#ctx.colorTrail+1]={c.R,c.G,c.B,c.A,c.RO,c.GO,c.BO} end
                    for _,c in ipairs(trailDuringRun) do ctx.colorTrail[#ctx.colorTrail+1]=c end
                    sample()
                    for label,fn in pairs(checks) do
                        if label:find('%(key)s:',1,true)==1 and not label:find('flag animation',1,true) then run(fn,label) end
                    end
                    local ease=checks['%(key)s: the colour eases in, holds through the change and eases back']
                    local good=ctx.colorTrail
                    ctx.colorTrail={}
                    for i,c in ipairs(good) do ctx.colorTrail[i]=c end
                    ctx.colorTrail[60]={1,1,1,.8,0,0,0}
                    if ease(nil,ctx) ~= false then failed[#failed+1]='a mid-run snap was not caught' end
                    ctx.colorTrail={}
                    for i,c in ipairs(good) do ctx.colorTrail[i]=c end
                    ctx.colorTrail[#ctx.colorTrail]=ctx.colorTrail[#ctx.colorTrail-1]
                    ctx.colorTrail[#ctx.colorTrail]={1.2,1.2,1.2,.8,.2,.2,.2}
                    if ease(nil,ctx) ~= false then failed[#failed+1]='a tinted ending was not caught' end
                    return table.concat(failed,' | ')
                end)()''' % {'key': key, 'flag': flag})
                self.assertEqual(result, '')

    def test_stage_cleanup_never_lends_evidence_to_the_next_stage(self):
        self.lua.execute('''
            local p=pickup(); p.ToPickup=function(self) return self end
            p.Remove=function(self) self.alive=false end
            stageCtx={job={status='complete'},scene={},defaultAnim={},defaultHeard=true,
                fixture={ptr=EntityPtr(p),hash=GetPtrHash(p)},fixturePos=Vector(1,2)}
            Probe._removeFixture(stageCtx)
            removedPickup=not p:Exists()''')
        for field in ('job', 'scene', 'fixture', 'defaultAnim', 'defaultHeard'):
            self.assertIsNone(self.lua.eval('stageCtx.%s' % field), field)
        self.assertIsNotNone(self.lua.eval('stageCtx.fixturePos'), 'the shared spawn position is kept')
        self.assertTrue(self.lua.eval('removedPickup'))

    def test_checks_catch_each_defect(self):
        cases = {
            'instant colour return': ("KRONOS", "function(_,s) s.samples.black[121]=0 end", 'colour returns gradually'),
            'missing cue': ("KRONOS", "function(_,s) table.remove(s.cues,1) end", 'every cue played once'),
            'cue on the wrong frame': ("SOFLAM", "function(_,s) s.cues[1].frame=4 end", 'every cue played once'),
            'quiet cue': ("SOFLAM", "function(_,s) s.cues[2].volume=.2 end", 'every cue played once'),
            'unheard cue': ("DRAGON", "function(_,s) s.cues[2].heard=false end", 'engine started every cue'),
            'scene cut short': ("VOID_DAGGER", "function(_,s) s.endFrame=101 end", 'ran to its last frame'),
            'skipped frame': ("ICE_BREATH", "function(_,s) s.rendered[30]=nil end", 'every frame from 1'),
            'late milestone': ("TIME_LUCK", "function(_,s) s.marks.hour10=63 end", 'every milestone'),
            'minute hand misses 12 on a tick': ("TIME_POWER", "function(_,s) s.samples.minute[36]=700 end", '6:00 to 12:00'),
            'minute hand changes speed': ("TIME_MONEY", "function(_,s) s.samples.minute[50]=s.samples.minute[50]+6 end", '6:00 to 12:00'),
            'clock never reaches 12': ("TIME_TEAR", "function(_,s) s.samples.hour[96]=330 end", '6:00 to 12:00'),
            'darkness lifted early': ("DRAGON", "function(_,s) s.samples.darkness[60]=.5 end", 'darkness rises'),
            'item not released': ("DRAGON", "function(_,s) s.pickupVisual.released=false end", 'native result'),
            'wet after change': ("MONEY_TEAR", "function(_,s) s.samples.wet[97]=.4 end", 'soaks blue'),
            'motes fade early': ("VOID_DAGGER", "function(_,s) s.samples.vanish[40]=.3 end", 'keep their density'),
            'flame never hides': ("FIRE_BREATH", "function(_,s) s.samples.itemAlpha[44]=.6 end", 'conceals the item'),
            'crown stays white': ("ANGELS_CROWN", "function(_,s) s.samples.white[100]=.4 end", 'returns to its colours'),
            'colour left on pedestal': ("SOFLAM", "function(_,_,p) p.sprite.Color=Color(1,1,1,.8,.5,.5,.5) end", 'original colour'),
            'layer left hidden': ("TIME_MONEY", "function(_,_,p) p.sprite:GetLayer(p.Variant==PickupVariant.PICKUP_COLLECTIBLE and 1 or 0):SetVisible(false) end", 'item layer'),
            'flood never drawn': ("MONEY_TEAR", "function(_,s) s.floorRenders=0 end", 'flood overlay'),
            'wrong target': ("TIME_POWER", "function(_,_,p) p.SubType=1 end", 'converts the pedestal'),
            'pets missing': ("KRONOS", "function(_,s) s.pets={} end", 'stand-in pets'),
            'left half snaps back': ("HEMISPATIAL_NEGLECT", "function(_,s) s.samples.neglect[68]=0 end", 'returns gradually'),
            'left half never black': ("HEMISPATIAL_NEGLECT", "function(_,s) s.samples.neglect[50]=.6 end", 'returns gradually'),
            'darkness off-centre': ("HEMISPATIAL_NEGLECT", "function(_,s) s.neglectMid=400 end", 'only the left half'),
            'no bell at 12': ("TIME_LUCK", "function(_,s) table.remove(s.cues) end", 'every cue played once'),
            'colour snaps at the change': ("KRONOS", "function(_,s) s.samples.tint[121]={1,1,1,1,0,0,0} end", 'changes gradually'),
            'rain dries at once': ("MONEY_TEAR", "function(_,s) s.samples.wet[97]=0 end", 'dries gradually'),
            'item left tinted': ("ANGELS_CROWN", "function(_,s) s.samples.tint[102]={.5,.5,.5,1,.5,.5,.5} end", 'ends on its own colour'),
        }
        for name, (key, mutate, label) in cases.items():
            with self.subTest(defect=name):
                failed = self.lua.eval("runChecks('%s',%s)" % (key, mutate))
                self.assertIn(label, failed)


if __name__ == '__main__':
    unittest.main()
