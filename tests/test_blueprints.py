"""Guards the castle blueprint catalogue produced by tools/generate_blueprints.py."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / 'contracts' / 'blueprints.json'
RUNTIME = ROOT / 'game' / 'data' / 'blueprints.json'
CONTENT = ROOT / 'contracts' / 'content.json'


class BlueprintCatalogueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalogue = json.loads(CONTRACT.read_text(encoding='utf-8'))
        cls.content = json.loads(CONTENT.read_text(encoding='utf-8'))
        cls.placeable_blocks = {item['places_block'] for item in cls.content['items'] if 'places_block' in item}
        cls.block_ids = {block['id']: block['voxel_id'] for block in cls.content['blocks']}

    def test_runtime_mirror_matches_contract(self):
        self.assertEqual(self.catalogue, json.loads(RUNTIME.read_text(encoding='utf-8')), 'game/data/blueprints.json must mirror contracts/blueprints.json; re-run tools/generate_blueprints.py')

    def test_schema_and_ids(self):
        self.assertEqual(self.catalogue['schema_version'], 1)
        ids = [entry['id'] for entry in self.catalogue['blueprints']]
        self.assertEqual(len(ids), len(set(ids)), 'duplicate blueprint id')
        for required in ('foundation_4', 'tower_segment_4', 'cap_4', 'cap_6', 'cap_8', 'wall_4'):
            self.assertIn(required, ids)

    def test_blocks_are_placeable_and_inside_the_footprint(self):
        for entry in self.catalogue['blueprints']:
            size = entry['size']
            seen = set()
            for block in entry['blocks']:
                offset = tuple(block['offset'])
                self.assertNotIn(offset, seen, '%s repeats offset %s' % (entry['id'], offset))
                seen.add(offset)
                for axis in range(3):
                    self.assertTrue(0 <= offset[axis] < size[axis], '%s offset %s leaves size %s' % (entry['id'], offset, size))
                self.assertIn(block['block'], self.block_ids, '%s uses unknown block %s' % (entry['id'], block['block']))
                self.assertIn(self.block_ids[block['block']], self.placeable_blocks, '%s uses a block no item can place: %s' % (entry['id'], block['block']))

    def test_sockets_sit_on_the_footprint_boundary(self):
        for entry in self.catalogue['blueprints']:
            size = entry['size']
            for socket in entry['sockets']:
                offset = socket['offset']
                self.assertIn(socket['type'], ('top', 'side'))
                if socket['type'] == 'top':
                    self.assertEqual(offset[1], size[1])
                else:
                    outside = offset[0] in (-1, size[0]) or offset[2] in (-1, size[2])
                    self.assertTrue(outside, '%s side socket %s is not adjacent to the footprint' % (entry['id'], socket['id']))

    def test_cap_sizes_follow_the_owner_rule(self):
        caps = {entry['id']: entry for entry in self.catalogue['blueprints'] if entry['id'].startswith('cap_')}
        self.assertEqual(caps['cap_8']['size'][0], 8)
        interior = sum(1 for block in caps['cap_8']['blocks'] if block['block'] == 'planks')
        self.assertEqual(interior, 36, 'an 8x8 cap has a 6x6 interior floor for a catapult and a ballista')


if __name__ == '__main__':
    unittest.main()
