"""scripts/version.lua mirrors metadata.xml's <version>: the mod shows it at the
top of Mod Config Menu's General tab (user request 2026-11-21: always current).
generate_xml.py rewrites it on every run and the Steam Workshop packager writes
the release version before staging, and the publish workflow commits both."""
import importlib.util
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / '.github/scripts'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(ROOT))
Packager = load('packager_version', SCRIPTS / 'prepare_steam_workshop_upload.py')
Generator = load('generate_xml_version', ROOT / 'generate_xml.py')


def metadata_version(root=ROOT):
    return re.search(r'<version>([^<]+)</version>', (root / 'metadata.xml').read_text(encoding='utf-8')).group(1)


def module_version(path):
    return LuaRuntime().execute(path.read_text(encoding='utf-8'))


class VersionModuleTests(unittest.TestCase):
    def test_the_module_matches_metadata(self):
        self.assertEqual(module_version(ROOT / 'scripts/version.lua'), metadata_version())

    def test_the_generator_and_packager_write_the_same_text(self):
        self.assertEqual(Packager.version_module_text('9.8.7'),
                         f'{Generator.VERSION_MODULE_HEADER}return "9.8.7"\n')

    def test_the_packager_writes_the_release_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            shutil.copy2(ROOT / 'metadata.xml', repo / 'metadata.xml')
            (repo / 'scripts').mkdir()
            (repo / 'scripts/version.lua').write_text('return "0.0.1"\n', encoding='utf-8')
            current = metadata_version(repo)
            major, minor, patch = (int(x) for x in current.split('.'))
            steam = f'{major}.{minor}.{patch}'          # equal: the packager bumps the patch
            metadata = Packager.apply_release_version(repo, Packager.read_metadata(repo), '', steam)
            Packager.write_version_module(repo, metadata['version'])
            expected = f'{major}.{minor}.{patch + 1}'
            self.assertEqual(metadata['version'], expected)
            self.assertEqual(metadata_version(repo), expected)
            self.assertEqual(module_version(repo / 'scripts/version.lua'), expected)

    def test_the_generator_mirrors_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            (repo / 'metadata.xml').write_text('<metadata><version>3.2.1</version></metadata>', encoding='utf-8')
            module = repo / 'version.lua'
            self.assertEqual(Generator.sync_version_module(str(repo / 'metadata.xml'), str(module)), '3.2.1')
            self.assertEqual(module_version(module), '3.2.1')
            before = module.stat().st_mtime_ns
            Generator.sync_version_module(str(repo / 'metadata.xml'), str(module))
            self.assertEqual(module.stat().st_mtime_ns, before, 'an unchanged version is not rewritten')

    def test_the_workflow_and_hook_carry_the_module(self):
        workflow = (ROOT / '.github/workflows/steam_workshop_publish.yml').read_text(encoding='utf-8')
        self.assertIn('git add metadata.xml scripts/version.lua', workflow)
        self.assertIn('git diff --quiet -- metadata.xml scripts/version.lua', workflow)
        self.assertIn('scripts/version.lua', (ROOT / '.githooks/pre-push').read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
