"""Keep HTML approval labels aligned with the runtime morph catalog."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent


def synchronize(check=False):
    catalog = (ROOT / 'scripts/upgrade_visual_catalog.lua').read_text(encoding='utf-8')
    statuses = {key: 'effect =' in rest for key, rest in
                re.findall(r'\{ key = "([A-Z_]+)"([^}]+)\}', catalog)}
    path = ROOT / 'docs/previews/item-upgrade-player.html'
    html = path.read_text(encoding='utf-8')
    pattern = r'(<script[^>]*id="upgrade-data"[^>]*>)(.*?)(</script>)'
    match = re.search(pattern, html, re.S)
    rows = json.loads(match[2])
    assert [row['key'] for row in rows] == list(statuses), 'HTML/catalog order mismatch'
    for row in rows:
        row['applied'] = statuses[row['key']]
    data = json.dumps(rows, ensure_ascii=False, separators=(',', ':'))
    updated = html[:match.start(2)] + data + html[match.end(2):]
    if check:
        assert updated == html, 'Run python sync_upgrade_preview.py'
    else:
        path.write_text(updated, encoding='utf-8')
    print(f'Preview catalog: {sum(statuses.values())} applied / {len(statuses)} total')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    synchronize(parser.parse_args().check)
