"""Guards `game/data/item_atlas_regions.json` against the shipped atlases and content.

Pillow is not required: PNG dimensions are read from the IHDR chunk so the
check stays dependency-free like the rest of the test suite.
"""
import json
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGIONS = ROOT / 'game' / 'data' / 'item_atlas_regions.json'
CONTENT = ROOT / 'game' / 'data' / 'content.json'
UI = ROOT / 'game' / 'assets' / 'ui'


def png_size(path):
    with open(path, 'rb') as handle:
        header = handle.read(24)
    if header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError('not a PNG: %s' % path)
    return struct.unpack('>II', header[16:24])


class ItemAtlasRegionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.payload = json.loads(REGIONS.read_text(encoding='utf-8'))
        cls.content = json.loads(CONTENT.read_text(encoding='utf-8'))

    def test_schema_and_atlases_exist(self):
        self.assertEqual(self.payload['schema_version'], 1)
        for key, atlas in self.payload['atlases'].items():
            path = UI / atlas['file']
            self.assertTrue(path.exists(), 'missing atlas %s' % path)
            self.assertEqual(list(png_size(path)), atlas['size'], 'recorded size differs for %s; re-run tools/measure_item_atlas.py' % key)

    def test_every_content_item_has_a_region_inside_its_atlas(self):
        regions = self.payload['regions']
        for item in self.content['items']:
            item_id = item['id']
            self.assertIn(item_id, regions, 'unmeasured item %s; re-run tools/measure_item_atlas.py' % item_id)
            entry = regions[item_id]
            width, height = self.payload['atlases'][entry['atlas']]['size']
            x, y, w, h = entry['rect']
            self.assertGreater(w, 0)
            self.assertGreater(h, 0)
            self.assertTrue(0 <= x and 0 <= y and x + w <= width and y + h <= height, 'region for %s leaves its atlas' % item_id)

    def test_regions_within_one_atlas_do_not_overlap(self):
        regions = self.payload['regions']
        ids = sorted(regions)
        for index, a in enumerate(ids):
            for b in ids[index + 1:]:
                if regions[a]['atlas'] != regions[b]['atlas']:
                    continue
                ax, ay, aw, ah = regions[a]['rect']
                bx, by, bw, bh = regions[b]['rect']
                separated = ax + aw <= bx or bx + bw <= ax or ay + ah <= by or by + bh <= ay
                self.assertTrue(separated, 'regions overlap: %s and %s' % (a, b))

    def test_ammunition_is_isolated_from_each_other(self):
        bolt = self.payload['regions']['ballista_bolt']['rect']
        shot = self.payload['regions']['stone_shot']['rect']
        self.assertEqual(self.payload['regions']['ballista_bolt']['atlas'], 'ammunition')
        self.assertLess(bolt[0] + bolt[2], shot[0], 'bolt spearhead must end before the stone shot begins')


if __name__ == '__main__':
    unittest.main()
