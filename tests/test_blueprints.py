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
        cls.entity_ids = {entity['id'] for entity in cls.content['entities']}
        cls.placeable_entities = {item['places_entity'] for item in cls.content['items'] if 'places_entity' in item}

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

    def test_entity_cells_are_placeable_and_do_not_collide_with_blocks(self):
        """Defence sets: a kit blueprint may also stamp one-cell castle-kit
        entities. They must be real placeable entities, sit inside the
        footprint and never share a cell with a block of the same piece."""
        for entry in self.catalogue['blueprints']:
            size = entry['size']
            self.assertIn('entities', entry, '%s has no entities list' % entry['id'])
            blocks = {tuple(block['offset']) for block in entry['blocks']}
            seen = set()
            for piece in entry['entities']:
                offset = tuple(piece['offset'])
                self.assertNotIn(offset, seen, '%s repeats entity offset %s' % (entry['id'], offset))
                self.assertNotIn(offset, blocks, '%s stamps an entity into a block cell %s' % (entry['id'], offset))
                seen.add(offset)
                for axis in range(3):
                    self.assertTrue(0 <= offset[axis] < size[axis], '%s entity offset %s leaves size %s' % (entry['id'], offset, size))
                self.assertIn(piece['entity'], self.entity_ids, '%s uses unknown entity %s' % (entry['id'], piece['entity']))
                self.assertIn(piece['entity'], self.placeable_entities, '%s uses an entity no item can place: %s' % (entry['id'], piece['entity']))
                self.assertIn(piece['rotation'], (0, 1, 2, 3), '%s entity rotation must be a quarter turn' % entry['id'])

    def test_the_wall_kit_is_a_complete_section(self):
        """The card's contract: base course, walkway, crenellations and a
        stair up at each end."""
        kit = next(entry for entry in self.catalogue['blueprints'] if entry['id'] == 'wall_kit_8')
        self.assertEqual(sum(1 for block in kit['blocks'] if block['block'] == 'castle_stone'), 16)
        counts = {}
        for piece in kit['entities']:
            counts[piece['entity']] = counts.get(piece['entity'], 0) + 1
        self.assertEqual(counts, {'wall_walk_slab': 8, 'parapet_merlon': 4, 'stone_stair': 4})
        ends = {tuple(p['offset'])[0] for p in kit['entities'] if p['entity'] == 'stone_stair'}
        self.assertEqual(ends, {0, 7}, 'the stairs climb at both ends of the section')

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
