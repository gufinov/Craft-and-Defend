import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from validate_foundation import ValidationError, load_bundle, read_json, validate_bundle, in_bounds, reachable_items
from verify_toolchain import verify_archive


class FoundationTests(unittest.TestCase):
    def setUp(self):
        self.bundle = copy.deepcopy(load_bundle())

    def rejects(self, message):
        with self.assertRaisesRegex(ValidationError, message):
            validate_bundle(self.bundle)

    def test_valid_baseline_and_tool_progression(self):
        validate_bundle(self.bundle)
        self.assertIn('iron_pick', reachable_items(self.bundle['content'], self.bundle['world']))

    def test_duplicate_voxel_identity_rejected(self):
        self.bundle['content']['blocks'][1]['voxel_id'] = 0
        self.rejects('duplicate voxel_id')

    def test_unknown_recipe_input_rejected(self):
        self.bundle['content']['recipes'][0]['inputs'] = {'unobtainium': 1}
        self.rejects('invalid recipe item/count')

    def test_free_recipe_rejected(self):
        self.bundle['content']['recipes'][0]['inputs'] = {}
        self.rejects('empty inputs')

    def test_boolean_is_not_quantity(self):
        self.bundle['content']['recipes'][0]['inputs']['log'] = True
        self.rejects('invalid recipe item/count')

    def test_progression_deadlock_rejected(self):
        self.bundle['content']['recipes'][2]['station'] = 'workbench'
        self.rejects('unreachable progression')

    def test_missing_resource_patch_blocks_progression(self):
        self.bundle['world']['patches'] = [p for p in self.bundle['world']['patches'] if p['block'] != 4]
        self.rejects('unreachable progression')

    def test_conflicting_key_rejected(self):
        self.bundle['keybinds']['actions'].append({'id':'extra','key':'E','context':'gameplay'})
        self.rejects('overlapping active key')

    def test_loss_of_escape_recovery_rejected(self):
        self.bundle['keybinds']['escape_recovery'] = False
        self.rejects('unsafe input')

    def test_nonpositive_world_size_rejected(self):
        self.bundle['world']['size'][0] = 0
        self.rejects('invalid world bounds')

    def test_layer_gap_rejected(self):
        self.bundle['world']['layers'][1]['min_y'] += 1
        self.rejects('layers gap')

    def test_invalid_p1_height_range_rejected(self):
        self.bundle['world']['terrain']['max_surface_y'] = self.bundle['world']['terrain']['min_surface_y']
        self.rejects('invalid terrain height range')

    def test_unknown_generator_rejected(self):
        self.bundle['world']['generator_version'] = 'terrain_future_unknown'
        self.rejects('unsupported generator version')

    def test_invalid_entity_visual_rejected(self):
        entity = next(e for e in self.bundle['content']['entities'] if e['id'] == 'stone_stair')
        entity['visual']['parts'][0]['size'][1] = 0
        self.rejects('invalid entity visual')

    def test_duplicate_mount_socket_rejected(self):
        entity = next(e for e in self.bundle['content']['entities'] if e['id'] == 'tower_platform')
        entity['mount_sockets'].append(copy.deepcopy(entity['mount_sockets'][0]))
        self.rejects('invalid mount socket')

    def test_multicell_overlap_cannot_claim_success(self):
        case = next(c for c in self.bundle['placement_cases']['cases'] if c['id'] == 'multicell_partial_overlap')
        case['expected'] = 'OK'
        self.rejects('got OCCUPIED')

    def test_half_open_bounds_at_negative_coordinates(self):
        world = self.bundle['world']
        self.assertTrue(in_bounds([-32,-16,-64],world))
        self.assertTrue(in_bounds([31,15,63],world))
        self.assertFalse(in_bounds([32,15,63],world))
        self.assertFalse(in_bounds([-33,0,0],world))

    def test_duplicate_json_keys_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'bad.json'
            path.write_text('{"seed":1,"seed":2}', encoding='utf-8')
            with self.assertRaisesRegex(ValidationError, 'duplicate JSON key'):
                read_json(path)


class ArchiveTests(unittest.TestCase):
    def test_valid_and_corrupt_same_size_archives(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'fixture.zip'
            path.write_bytes(b'archive fixture')
            digest = hashlib.sha256(b'archive fixture').hexdigest()
            self.assertEqual(verify_archive(path, 15, digest), digest)
            path.write_bytes(b'ARCHIVE fixture')
            with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                verify_archive(path, 15, digest)

    def test_wrong_size_and_missing_archive(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'fixture.zip'
            with self.assertRaisesRegex(ValueError, 'missing archive'):
                verify_archive(path, 1, '0' * 64)
            path.write_bytes(b'xx')
            with self.assertRaisesRegex(ValueError, 'size mismatch'):
                verify_archive(path, 1, '0' * 64)


if __name__ == '__main__':
    unittest.main()
