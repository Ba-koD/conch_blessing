"""A top-level local function called above its definition is a global there.

Lua binds `local function f` only from that line down, so a call written
earlier in the file looks up a global `f` and fails at run time with "attempt
to call a nil value", which no load-time check reports (축's furrow marks were
lost to this on 2026-10-31). Every runtime script is scanned for a call above
the definition that has neither a forward `local f` declaration nor a
parameter of the same name.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFINITION = re.compile(r'local function ([A-Za-z_]\w*)\s*\(')
FORWARD = re.compile(r'local\s+([A-Za-z_][\w, ]*?)\s*(?:=|$)')
SIGNATURE = re.compile(r'function[\w.:\s]*\(([^)]*)\)')


def early_calls(text):
    lines = text.splitlines()
    defined = {}
    for i, line in enumerate(lines):
        match = DEFINITION.match(line)
        if match and match.group(1) not in defined:
            defined[match.group(1)] = i
    forward, params = {}, {}
    for i, line in enumerate(lines):
        code = line.split('--')[0]
        match = FORWARD.match(code)
        if match and not code.startswith('local function'):
            for name in match.group(1).split(','):
                forward.setdefault(name.strip(), i)
        for match in SIGNATURE.finditer(code):
            for name in match.group(1).split(','):
                params.setdefault(name.strip(), i)
    found = []
    for name, at in defined.items():
        if forward.get(name, at) < at:
            continue
        call = re.compile(r'(?<![\w.:])' + re.escape(name) + r'\s*\(')
        for i in range(at):
            if call.search(lines[i].split('--')[0]) and params.get(name, i + 1) > i:
                found.append((i + 1, name, at + 1))
                break
    return found


class LocalOrderTests(unittest.TestCase):
    def test_runtime_scripts_define_locals_before_calling_them(self):
        problems = []
        for path in sorted((ROOT / 'scripts').rglob('*.lua')):
            if path.name == 'isaacscript-common.lua':
                continue
            for line, name, at in early_calls(path.read_text(encoding='utf-8')):
                problems.append(f'{path.relative_to(ROOT)}:{line} calls {name}, defined at line {at}')
        self.assertEqual(problems, [])

    def test_the_scan_catches_a_call_above_the_definition(self):
        late = 'function M.onUpdate()\n    sync(1)\nend\n\nlocal function sync(n)\nend\n'
        self.assertEqual(early_calls(late), [(2, 'sync', 5)])
        declared = 'local sync\nfunction M.onUpdate()\n    sync(1)\nend\n\nlocal function sync(n)\nend\n'
        self.assertEqual(early_calls(declared), [])
        parameter = 'local function run(sync)\n    sync(1)\nend\n\nlocal function sync(n)\nend\n'
        self.assertEqual(early_calls(parameter), [])


if __name__ == '__main__':
    unittest.main()
