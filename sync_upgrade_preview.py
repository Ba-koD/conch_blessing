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
    data = json.dumps(rows, ensure_ascii=False, separators=(',', ':'))
    updated = html[:match.start(2)] + data + html[match.end(2):]
    # Reuse authored runtime art and ANM2 geometry in the standalone preview.
    def read_data(key):
        return json.loads(re.search(r'id="' + key + r'"[^>]*>(.*?)</script>', updated, re.S)[1])
    assets, animations = read_data('room-assets'), read_data('effect-animations')
    assets['mawJaw'] = 'data:image/png;base64,' + base64.b64encode(
        (ROOT / 'resources/gfx/effects/conch_upgrade_maw.png').read_bytes()).decode('ascii')
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
    definitions = [(f'maw_{p}', ROOT / f'resources/gfx/effects/conch_upgrade_maw_{p}.anm2', 'mawJaw', None)
                   for p in ('all', 'upper', 'lower', 'sides')]
    definitions += [(f'clock_{p}', ROOT / f'resources/gfx/effects/conch_upgrade_clock_{p}.anm2', 'clockArt', None)
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
    for key, relative in [('lock', 'sfx/feedback/beep.wav'), ('wing', 'sfx/v2/angel_wing1.wav'),
                          ('holy', 'sfx/feedback/holy!.wav'), ('bite', 'sfx/Bone Snap.wav'),
                          ('thunder', 'sfx/thunder1.wav'), ('lightning', 'sfx/V2/light_bolt_02.wav')]:
        sounds[key] = 'data:audio/wav;base64,' + base64.b64encode((VANILLA / relative).read_bytes()).decode('ascii')
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
