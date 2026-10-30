"""Keep HTML approval labels aligned with the runtime morph catalog."""
import argparse
import base64
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
VANILLA = ROOT.parent.parent / 'extracted_resources/resources'


def synchronize(check=False):
    catalog = (ROOT / 'scripts/upgrade_visual_catalog.lua').read_text(encoding='utf-8')
    entries = dict(re.findall(r'\{ key = "([A-Z_]+)"([^}]+)\}', catalog))
    statuses = {key: 'effect =' in rest for key, rest in entries.items()}
    path = ROOT / 'docs/previews/item-upgrade-player.html'
    html = path.read_text(encoding='utf-8')
    pattern = r'(<script[^>]*id="upgrade-data"[^>]*>)(.*?)(</script>)'
    match = re.search(pattern, html, re.S)
    rows = json.loads(match[2])
    assert [row['key'] for row in rows] == list(statuses), 'HTML/catalog order mismatch'
    for row in rows:
        row['applied'] = statuses[row['key']]
        anchor = [re.search(r'anchor' + axis + r'\s*=\s*([\d.]+)', entries[row['key']]) for axis in ('X', 'Y')]
        assert all(anchor) or not any(anchor), 'Effect anchors require both X and Y'
        if all(anchor):
            row['effectAnchor'] = [float(value[1]) for value in anchor]
        else:
            row.pop('effectAnchor', None)
        # Item icons are the shipped runtime PNGs, so a redrawn icon never
        # leaves a stale copy in the preview.
        name = row['key'].lower() + '.png'
        icon = next((p for p in (ROOT / 'resources/gfx/items/collectibles' / name,
                                 ROOT / 'resources/gfx/items/trinkets' / name) if p.exists()), None)
        assert icon, 'missing runtime icon for ' + row['key']
        row['icon'] = 'data:image/png;base64,' + base64.b64encode(icon.read_bytes()).decode('ascii')
        # Both renderers read the impact and scene length from the catalog.
        for field in ('impact', 'duration'):
            value = re.search(field + r'\s*=\s*(\d+)', entries[row['key']])
            if value:
                row[field] = int(value[1])
            else:
                row.pop(field, None)
    data = json.dumps(rows, ensure_ascii=False, separators=(',', ':'))
    updated = html[:match.start(2)] + data + html[match.end(2):]
    # Reuse authored runtime art and ANM2 geometry in the standalone preview.
    def read_data(key):
        return json.loads(re.search(r'id="' + key + r'"[^>]*>(.*?)</script>', updated, re.S)[1])
    assets, animations = read_data('room-assets'), read_data('effect-animations')
    # The retired Kronos mouth no longer ships; drop its embedded copies.
    assets.pop('mawJaw', None)
    for key in ('maw_all', 'maw_upper', 'maw_lower', 'maw_sides'):
        animations.pop(key, None)
    def frames(node):
        return [{k: (v == 'true' if v in ('true', 'false') else float(v))
                 for k, v in frame.attrib.items()} for frame in node.findall('Frame')]
    assets['clockArt'] = 'data:image/png;base64,' + base64.b64encode(
        (ROOT / 'resources/gfx/effects/conch_upgrade_clock.png').read_bytes()).decode('ascii')
    assets['spotlight'] = 'data:image/png;base64,' + base64.b64encode(
        (ROOT / 'resources/gfx/effects/conch_upgrade_spotlight.png').read_bytes()).decode('ascii')
    # Native textures/audio stay references in the game; the offline HTML embeds
    # the same extracted samples, as it already does for the other native FX.
    for key, relative in [('halo', 'gfx/items/collectibles/collectibles_101_thehalo.png'),
                          ('glint', 'gfx/effects/UltraGreedBling.png'),
                          ('targetSheet0', 'gfx/effects/effect_000_target.png'),
                          ('targetSheet1', 'gfx/effects/effect_000_target_line.png')]:
        assets[key] = 'data:image/png;base64,' + base64.b64encode((VANILLA / relative).read_bytes()).decode('ascii')
    definitions = [(f'clock_{p}', ROOT / f'resources/gfx/effects/conch_upgrade_clock_{p}.anm2', 'clockArt', None)
                    for p in ('rim', 'minute', 'hour')]
    definitions += [('spotlight', ROOT / 'resources/gfx/effects/conch_upgrade_spotlight.anm2', 'spotlight', None),
                    ('halo', ROOT / 'resources/gfx/effects/conch_upgrade_halo.anm2', 'halo', None),
                    ('glint', VANILLA / 'gfx/1000.103_ultragreedbling.anm2', 'glint', 'Bling1')]
    for key, file, sheet, name in definitions:
        tree = ET.parse(file)
        animation = tree.find(f'./Animations/Animation[@Name="{name}"]' if name else './Animations/Animation')
        animations[key] = {'frames': int(animation.get('FrameNum')), 'fps': int(tree.find('Info').get('Fps')),
            'root': frames(animation.find('RootAnimation')),
            'layers': [{'sheet': sheet, 'frames': frames(layer)}
                       for layer in animation.findall('./LayerAnimations/LayerAnimation')]}
    sounds = read_data('effect-audio')
    sounds.pop('mawInhale', None)
    # Embed every sample of the SoundEffect the game plays; the engine picks
    # one of several at random, and the preview does the same.
    registry = (VANILLA / 'sounds.xml').read_text(encoding='utf-8')

    def sample(relative):
        folder, name = (VANILLA / 'sfx' / relative).parent, Path(relative).name
        match = [entry for entry in folder.iterdir() if entry.name.lower() == name.lower()]
        assert len(match) == 1, 'missing vanilla sample ' + relative
        return 'data:audio/wav;base64,' + base64.b64encode(match[0].read_bytes()).decode('ascii')
    for key, sound_id in [('lock', 855), ('wing', 275), ('holy', 54), ('bite', 462), ('thunder', 472),
                          ('candle', 471), ('flame', 483), ('freeze', 496), ('launch', 537),
                          ('impact', 587), ('inhale', 957),
                          # The neutral and negative default animations (scripts/template.lua).
                          ('spewer', 132),
                          # Kronos concept comparison (HTML only until one is chosen).
                          ('scythes', 695), ('swing', 538), ('plant', 463), ('spin', 636),
                          ('gulp', 157), ('summon', 265), ('holeOpen', 947), ('holeExit', 948)]:
        entry = re.search(r'<sound id="%d">(.*?)</sound>' % sound_id, registry, re.S)
        samples = [sample(relative) for relative in re.findall(r'path="([^"]+)"', entry[1])]
        sounds[key] = samples[0] if len(samples) == 1 else samples
    sounds.pop('shine', None)
    # The game plays these exact single samples through content/sounds.xml.
    for key, name in [('lightning', 'thunder_strike'), ('rain', 'rain'), ('tick', 'clock_tick'), ('tock', 'clock_tock'), ('bell', 'clock_bell')]:
        sounds[key] = 'data:audio/wav;base64,' + base64.b64encode(
            (ROOT / f'resources/sfx/conch_upgrade_{name}.wav').read_bytes()).decode('ascii')
    for key, value in [('room-assets', assets), ('effect-animations', animations), ('effect-audio', sounds)]:
        updated = re.sub(r'(id="' + key + r'"[^>]*>)(.*?)(</script>)',
                         lambda m: m[1] + json.dumps(value, ensure_ascii=False, separators=(',', ':')) + m[3],
                         updated, flags=re.S)
    for name, count in [('applied', sum(statuses.values())), ('pending', len(statuses)-sum(statuses.values()))]:
        updated = re.sub(r'(id="filter-' + name + r'"[^>]*>[^<]*?)\d+(</button>)',
                         lambda m: m[1] + str(count) + m[2], updated)
    if check:
        assert updated == html, 'Run python sync_upgrade_preview.py'
    else:
        path.write_text(updated, encoding='utf-8')
    print(f'Preview catalog: {sum(statuses.values())} applied / {len(statuses)} total')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    synchronize(parser.parse_args().check)
