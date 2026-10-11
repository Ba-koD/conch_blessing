"""Upgrade cues must be audible in game and identical in the HTML preview.

A cue that is fine in a quiet browser can vanish under gameplay audio, and
SFXManager is not relied on to amplify above volume 1. Measure each sample's
own loudness and require volume * loudness to reach an audible level.
"""
import math
from pathlib import Path
import re
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
VANILLA = ROOT.parent.parent / 'extracted_resources/resources'
ENUMS = ROOT.parent.parent / 'resources/scripts/enums.lua'
# Loudest 50 ms of the sample, scaled by the cue volume. Kronos's first cues
# measured -19 to -20 dB this way and could not be heard over gameplay.
QUIETEST_DB = -18.0
# HTML cue key -> the sound the game plays for it.
PREVIEW_SOUNDS = {
    'thunder': 'SOUND_THUNDER', 'lightning': 'Conch Upgrade Thunder Strike',
    'candle': 'SOUND_CANDLE_LIGHT', 'flame': 'SOUND_FLAME_BURST', 'freeze': 'SOUND_FREEZE',
    'lock': 'SOUND_DR_REMOTE_WARNING', 'launch': 'SOUND_ROCKET_LAUNCH', 'impact': 'SOUND_ROCKET_EXPLOSION',
    'wing': 'SOUND_ANGEL_WING', 'holy': 'SOUND_HOLY',
    'spin': 'SOUND_MOTHER_SPIN_START', 'summon': 'SOUND_SUMMONSOUND',
    'tick': 'Conch Upgrade Clock Tick', 'tock': 'Conch Upgrade Clock Tock', 'bell': 'Conch Upgrade Clock Bell',
    'rain': 'Conch Upgrade Rain',
}


def loudest_db(path):
    with wave.open(str(path)) as w:
        width, channels, rate = w.getsampwidth(), w.getnchannels(), w.getframerate()
        raw = w.readframes(w.getnframes())
    if width == 1:
        values = [(b - 128) / 128 for b in raw]
    else:
        values = [int.from_bytes(raw[i:i + 2], 'little', signed=True) / 32768 for i in range(0, len(raw), 2)]
    mono = [sum(values[i:i + channels]) / channels for i in range(0, len(values), channels)]
    window = max(1, int(rate * .05))
    best, energy = 0.0, 0.0
    for i, v in enumerate(mono):
        energy += v * v
        if i >= window:
            energy -= mono[i - window] ** 2
        # Always average over the full 50 ms: a short click must not be judged
        # by its first few samples alone.
        best = max(best, energy / window)
    return 10 * math.log10(max(best, 1e-12))


class UpgradeSoundLevelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (VANILLA / 'sounds.xml').exists() or not ENUMS.exists():
            raise unittest.SkipTest('extracted vanilla resources are unavailable')
        cls.enums = {m[1]: int(m[2]) for m in re.finditer(r'\b(SOUND_[A-Z0-9_]+)\s*=\s*(\d+)', ENUMS.read_text(encoding='utf-8'))}
        cls.registry = (VANILLA / 'sounds.xml').read_text(encoding='utf-8')
        custom = (ROOT / 'content/sounds.xml').read_text(encoding='utf-8')
        cls.custom = {name: ROOT / 'resources/sfx' / path
                      for name, path in re.findall(r'<sound name="([^"]+)">\s*<sample [^>]*path="([^"]+)"', custom)}
        cls.lua = (ROOT / 'scripts/lib/upgrade_visuals.lua').read_text(encoding='utf-8')

    def samples(self, sound):
        if sound in self.custom:
            return [self.custom[sound]]
        entry = re.search(r'<sound id="%d">(.*?)</sound>' % self.enums[sound], self.registry, re.S)
        found = []
        for relative in re.findall(r'path="([^"]+)"', entry[1]):
            target = VANILLA / 'sfx' / relative
            found.append(next(p for p in target.parent.iterdir() if p.name.lower() == target.name.lower()))
        return found

    def cues(self):
        aliases = dict(re.findall(r'local (\w+) = customSound\("([^"]+)"\)', self.lua))
        result = []
        for sound, volume, pitch in re.findall(
                r'soundOnce\(scene, ([^,]+), [^,]+, ([0-9.]+)(?:, ([^)]+))?\)', self.lua):
            custom = re.match(r'customSound\("([^"]+)"\)', sound)
            name = custom[1] if custom else aliases.get(sound) or sound.strip('"')
            result.append((name, float(volume), pitch.strip() if pitch else '1'))
        return result

    def test_every_game_cue_is_audible_without_amplification(self):
        cues = self.cues()
        self.assertGreater(len(cues), 10)
        template = (ROOT / 'scripts/template.lua').read_text(encoding='utf-8')
        for block in re.split(r'\nTemplate\.(?=positive|neutral|negative)', template)[1:]:
            sound = re.search(r'soundId or SoundEffect\.(SOUND_\w+)', block)
            play = re.search(r'sfx:Play\(upgradeAnim\.soundId, ([0-9.]+)', block)
            if sound and play:
                cues.append((sound[1], float(play[1]), '1'))
        for sound, volume, _ in cues:
            with self.subTest(sound=sound, volume=volume):
                self.assertLessEqual(volume, 1.0, 'volume above 1 is not a reliable boost')
                quietest = min(loudest_db(path) for path in self.samples(sound))
                self.assertGreaterEqual(quietest + 20 * math.log10(volume), QUIETEST_DB,
                                        f'{sound} at {volume} would be buried under gameplay audio')

    def test_preview_plays_the_same_sounds_at_the_same_levels(self):
        html = (ROOT / 'docs/previews/item-upgrade-player.html').read_text(encoding='utf-8')
        body = html[html.index('function soundCues(){'):html.index('async function cue(')]
        # Kronos's other concepts (sickle, dust, pit) are HTML-only previews.
        body = '\n'.join(line for line in body.splitlines() if "if(s==='" not in line)
        game = {(name, volume, pitch.replace(' ', '')) for name, volume, pitch in self.cues()}
        checked = 0
        for key, volume, pitch in re.findall(r"'(\w+)',([.\d]+),([^\]]+)\]", body):
            if key not in PREVIEW_SOUNDS:
                continue  # HTML-only Kronos concepts are not applied in game
            checked += 1
            sound, volume = PREVIEW_SOUNDS[key], float(volume)
            pitches = {p for n, v, p in game if n == sound and abs(v - volume) < 1e-9}
            with self.subTest(key=key):
                self.assertTrue(pitches, f'{key}: the game never plays {sound} at {volume}')
        self.assertGreaterEqual(checked, 12)
        sync = (ROOT / 'sync_upgrade_preview.py').read_text(encoding='utf-8')
        for key, sound_id in re.findall(r"\('(\w+)', (\d+)\)", sync):
            if key in PREVIEW_SOUNDS and PREVIEW_SOUNDS[key].startswith('SOUND_'):
                with self.subTest(embedded=key):
                    self.assertEqual(int(sound_id), self.enums[PREVIEW_SOUNDS[key]],
                                     f'the preview embeds a different sample for {key}')


if __name__ == '__main__':
    unittest.main()
