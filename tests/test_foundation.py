import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from validate_foundation import (ValidationError, load_bundle, read_json, validate_bundle, in_bounds,
                                 reachable_items, expo_parcels, expo_world_bounds, item_categories,
                                 supply_capacity, supply_catalog, supply_slots)
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

    def test_invalid_furnace_fuel_ratio_rejected(self):
        self.bundle['content']['balance']['furnace']['operations_per_fuel'] = 0
        self.rejects('invalid furnace balance')

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

    def test_boolean_is_not_recipe_book_order(self):
        self.bundle['content']['recipes'][0]['recipe_book_order'] = True
        self.rejects('invalid recipe book order')

    def test_unknown_item_category_rejected(self):
        self.bundle['content']['items'][0]['category'] = 'mystery'
        self.rejects('invalid item category')

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

    def ore_row(self, block):
        return next(row for row in self.bundle['world']['terrain']['ores'] if row['block'] == block)

    def test_ore_table_reaches_gold_through_the_iron_pick(self):
        validate_bundle(self.bundle)
        reachable = reachable_items(self.bundle['content'], self.bundle['world'])
        self.assertIn('gold_ore', reachable)
        self.assertIn('gold_ingot', reachable)
        gold = next(b for b in self.bundle['content']['blocks'] if b['id'] == 'gold_ore')
        self.assertEqual(gold['voxel_id'], 11)
        self.assertEqual(gold['min_pick_tier'], 3)
        depths = {row['block']: row['min_depth'] for row in self.bundle['world']['terrain']['ores']}
        self.assertLess(depths['coal_ore'], depths['iron_ore'])
        self.assertLess(depths['iron_ore'], depths['gold_ore'])
        self.assertGreaterEqual(depths['gold_ore'], 12)
        rates = {row['block']: row['cluster_per_thousand'] for row in self.bundle['world']['terrain']['ores']}
        self.assertLess(rates['gold_ore'], rates['iron_ore'])
        self.assertLess(rates['iron_ore'], rates['coal_ore'])

    def test_ore_row_preserves_p1_layout_bands(self):
        # Rows own cumulative bands of one roll in row order: iron first, then
        # coal, then gold. The P4E world (2026-09-19) raised the bands to 32/60/9
        # (owner: "ore more abundant"); older saves regenerate only untouched chunks.
        ores = self.bundle['world']['terrain']['ores']
        self.assertEqual([row['block'] for row in ores[:3]], ['iron_ore', 'coal_ore', 'gold_ore'])
        self.assertEqual([row['cluster_per_thousand'] for row in ores[:3]], [32, 60, 9])
        self.assertTrue(all(row['cluster_size'] == 2 for row in ores))

    def test_unknown_ore_block_rejected(self):
        self.ore_row('gold_ore')['block'] = 'mithril_ore'
        self.rejects('unknown ore block')

    def test_duplicate_ore_block_rejected(self):
        self.ore_row('gold_ore')['block'] = 'coal_ore'
        self.rejects('duplicate ore block')

    def test_ore_frequency_sum_must_leave_stone(self):
        self.ore_row('coal_ore')['cluster_per_thousand'] = 990
        self.rejects('stone must remain')

    def test_ore_frequency_zero_or_thousand_rejected(self):
        self.ore_row('gold_ore')['cluster_per_thousand'] = 0
        self.rejects('invalid ore frequency')
        self.ore_row('gold_ore')['cluster_per_thousand'] = 1000
        self.rejects('invalid ore frequency')

    def test_inverted_or_oversized_ore_depth_rejected(self):
        self.ore_row('iron_ore')['max_depth'] = 5
        self.rejects('invalid ore depth range')
        self.ore_row('iron_ore')['max_depth'] = self.bundle['world']['size'][1] + 1
        self.rejects('invalid ore depth range')

    def test_ore_inside_soil_layer_rejected(self):
        self.ore_row('coal_ore')['min_depth'] = 2
        self.rejects('soil cells')

    def test_missing_ore_table_rejected(self):
        del self.bundle['world']['terrain']['ores']
        self.rejects('terrain.ores')

    def test_protected_block_cannot_be_ore(self):
        self.ore_row('gold_ore')['block'] = 'bedrock'
        self.rejects('solid, unprotected and droppable')

    def test_removing_gold_ore_row_breaks_gold_progression(self):
        self.bundle['world']['terrain']['ores'] = [row for row in self.bundle['world']['terrain']['ores'] if row['block'] != 'gold_ore']
        self.rejects('unreachable progression')

    def test_unknown_generator_rejected(self):
        self.bundle['world']['generator_version'] = 'terrain_future_unknown'
        self.rejects('unsupported generator version')

    def test_invalid_entity_visual_rejected(self):
        entity = next(e for e in self.bundle['content']['entities'] if e['id'] == 'stone_stair')
        entity['visual']['parts'][0]['size'][1] = 0
        self.rejects('invalid entity visual')

    def test_stair_uses_two_half_block_steps(self):
        entity = next(e for e in self.bundle['content']['entities'] if e['id'] == 'stone_stair')
        parts = entity['visual']['parts']
        self.assertEqual(len(parts), 2)
        self.assertEqual([part['size'][2] for part in parts], [0.5, 0.5])
        self.assertEqual([part['size'][1] for part in parts], [0.5, 1.0])

    def test_duplicate_mount_socket_rejected(self):
        entity = next(e for e in self.bundle['content']['entities'] if e['id'] == 'tower_platform')
        entity['mount_sockets'].append(copy.deepcopy(entity['mount_sockets'][0]))
        self.rejects('invalid mount socket')

    def test_unknown_siege_mount_rejected(self):
        entity = next(e for e in self.bundle['content']['entities'] if e['id'] == 'ballista')
        entity['mount']['allowed'] = ['imaginary_socket']
        self.rejects('invalid entity mount')

    def test_invalid_siege_range_rejected(self):
        entity = next(e for e in self.bundle['content']['entities'] if e['id'] == 'catapult')
        entity['siege']['maximum_range'] = entity['siege']['minimum_range']
        self.rejects('invalid siege definition')

    def test_invalid_weapon_damage_rejected(self):
        item = next(i for i in self.bundle['content']['items'] if i['id'] == 'iron_sword')
        item['weapon']['damage'] = 0
        self.rejects('invalid weapon')

    def test_multicell_overlap_cannot_claim_success(self):
        case = next(c for c in self.bundle['placement_cases']['cases'] if c['id'] == 'multicell_partial_overlap')
        case['expected'] = 'OK'
        self.rejects('got OCCUPIED')

    def test_half_open_bounds_at_negative_coordinates(self):
        world = self.bundle['world']
        minimum = world['min_cell']
        maximum = [lo + size for lo, size in zip(minimum, world['size'])]
        self.assertTrue(in_bounds(minimum, world))
        self.assertTrue(in_bounds([v - 1 for v in maximum], world))
        self.assertFalse(in_bounds([maximum[0], maximum[1] - 1, maximum[2] - 1], world))
        self.assertFalse(in_bounds([minimum[0] - 1, 0, 0], world))

    def test_duplicate_json_keys_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'bad.json'
            path.write_text('{"seed":1,"seed":2}', encoding='utf-8')
            with self.assertRaisesRegex(ValidationError, 'duplicate JSON key'):
                read_json(path)

    def test_navigation_spike_is_bounded_and_capability_specific(self):
        root = Path(__file__).resolve().parents[1]
        navigation = read_json(root / 'contracts' / 'navigation_spike.json')
        runtime = read_json(root / 'game' / 'data' / 'navigation_spike.json')
        self.assertEqual(navigation, runtime)
        self.assertEqual(navigation['agent']['size_cells'], [1, 2, 1])
        self.assertEqual(navigation['benchmark']['region_size_cells'], [13, 5, 13])
        capabilities = {row['id']: row for row in navigation['capabilities']}
        self.assertIn('wood', capabilities['basic_raider']['damage_per_hit'])
        self.assertNotIn('stone', capabilities['basic_raider']['damage_per_hit'])
        self.assertIn('fortification', capabilities['siege_breaker_candidate']['damage_per_hit'])

    def test_navigation_spike_stays_a_headless_gate(self):
        # The one-click VIEW_NAVIGATION_SPIKE.cmd was retired with the root launcher cleanup
        # (2026-09-22); the P2 diagnostic itself still runs headless as a regression gate.
        root = Path(__file__).resolve().parents[1]
        app = (root / 'game' / 'scripts' / 'app' / 'app.gd').read_text(encoding='utf-8')
        self.assertIn('--p2-navigation-automation=', app)
        self.assertFalse((root / 'VIEW_NAVIGATION_SPIKE.cmd').exists())

    def test_p3c_has_one_click_exported_gameplay_and_visual_evidence(self):
        root = Path(__file__).resolve().parents[1]
        launcher = (root / 'tools' / 'runners' / 'TEST_P3C_PLAYER_DEFENSE.cmd').read_text(encoding='utf-8')
        self.assertIn('start_game.ps1" -PrepareOnly', launcher)
        self.assertIn('--p3c-player-defense-automation=phase1', launcher)
        self.assertIn('--p3c-player-defense-automation=save', launcher)
        self.assertIn('--p3c-player-defense-automation=restore', launcher)
        self.assertIn('--p3c-player-defense-automation=visual', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3c-visual-catalog.png"', launcher)
        self.assertIn('P3C_DIAGNOSTIC_NO_OPEN', launcher)

    def test_p3d_has_one_click_exported_gameplay_and_visual_evidence(self):
        root = Path(__file__).resolve().parents[1]
        launcher = (root / 'tools' / 'runners' / 'TEST_P3D_USABILITY.cmd').read_text(encoding='utf-8')
        self.assertIn('start_game.ps1" -PrepareOnly', launcher)
        self.assertIn('--p3d-usability-automation=phase1', launcher)
        self.assertIn('--p3d-usability-automation=visual', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3d-held-axe-iron-marker.png"', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3d-held-block-placement-ghost.png"', launcher)
        self.assertIn('P3D_DIAGNOSTIC_NO_OPEN', launcher)

    def test_p3e_has_one_click_exported_container_and_visual_evidence(self):
        root = Path(__file__).resolve().parents[1]
        launcher = (root / 'tools' / 'runners' / 'TEST_P3E_FURNACE.cmd').read_text(encoding='utf-8')
        self.assertIn('start_game.ps1" -PrepareOnly', launcher)
        self.assertIn('--p3e-container-automation=gate', launcher)
        self.assertIn('--p3e-container-automation=visual', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3e-furnace-container.png"', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3e-world-and-held-identity.png"', launcher)
        self.assertIn('P3E_DIAGNOSTIC_NO_OPEN', launcher)

    def test_p3f_has_one_click_exported_order_and_visual_evidence(self):
        root = Path(__file__).resolve().parents[1]
        launcher = (root / 'tools' / 'runners' / 'TEST_P3F_PRESENTATION.cmd').read_text(encoding='utf-8')
        self.assertIn('start_game.ps1" -PrepareOnly', launcher)
        self.assertIn('--p3f-presentation-automation=gate', launcher)
        self.assertIn('--p3f-presentation-automation=visual', launcher)
        self.assertIn('p3h2-held-scale-and-swing.png', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3f-held-item-contact-sheet.png"', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3f-workbench-page-1.png"', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3f-workbench-page-2.png"', launcher)
        self.assertIn('P3F_DIAGNOSTIC_NO_OPEN', launcher)

    def test_p3g_has_one_click_furnace_usability_and_visual_evidence(self):
        root = Path(__file__).resolve().parents[1]
        launcher = (root / 'tools' / 'runners' / 'TEST_P3G_FURNACE_USABILITY.cmd').read_text(encoding='utf-8')
        self.assertIn('start_game.ps1" -PrepareOnly', launcher)
        self.assertIn('--p3g-furnace-usability-automation=gate', launcher)
        self.assertIn('--p3g-furnace-usability-automation=visual', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3g-furnace-autoload-progress.png"', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3g-catapult-world-model.png"', launcher)
        self.assertIn('P3G_DIAGNOSTIC_NO_OPEN', launcher)

    def test_p3h_has_one_click_balance_and_controls_evidence(self):
        root = Path(__file__).resolve().parents[1]
        launcher = (root / 'tools' / 'runners' / 'TEST_P3H_BALANCE_CONTROLS.cmd').read_text(encoding='utf-8')
        self.assertIn('start_game.ps1" -PrepareOnly', launcher)
        self.assertIn('--p3h-balance-controls-automation=gate', launcher)
        self.assertIn('--p3h-balance-controls-automation=visual', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3h-furnace-fuel-ratio.png"', launcher)
        self.assertIn('if not exist "%VISUAL_ROOT%\\p3h-directional-controls.png"', launcher)
        self.assertIn('P3H_DIAGNOSTIC_NO_OPEN', launcher)

    def test_invalid_specialized_tool_kind_is_rejected(self):
        axe = next(item for item in self.bundle['content']['items'] if item['id'] == 'wood_axe')
        axe['tool_kind'] = 'chainsaw'
        self.rejects('invalid specialized tool')


class DevelopmentExpoTests(unittest.TestCase):
    """The Development Expo manifest rules (docs/DEVELOPMENT_EXPO.md)."""

    def setUp(self):
        self.bundle = copy.deepcopy(load_bundle())
        self.expo = self.bundle['development_expo']
        self.districts = {district['id']: district for district in self.expo['districts']}

    def rejects(self, message):
        with self.assertRaisesRegex(ValidationError, message):
            validate_bundle(self.bundle)

    def exhibit(self, exhibit_id):
        for district in self.expo['districts']:
            for exhibit in district['exhibits']:
                if exhibit['id'] == exhibit_id:
                    return exhibit
        raise AssertionError(exhibit_id)

    def test_valid_baseline_layout(self):
        validate_bundle(self.bundle)
        parcels = expo_parcels(self.expo)
        self.assertIn('plaza_core', parcels)
        minimum, size = expo_world_bounds(self.expo)
        self.assertTrue(all(value % self.expo['chunk_size'] == 0 for value in size))
        self.assertLessEqual(minimum[1], self.expo['floor_y'])

    def test_unknown_referenced_entity_rejected(self):
        self.exhibit('plaza_core')['entities'] = ['teleporter']
        self.rejects('unknown entity')

    def test_unknown_referenced_item_rejected(self):
        self.exhibit('day_one_log')['items'] = ['unobtainium']
        self.rejects('unknown item')

    def test_overlapping_districts_rejected(self):
        # The plaza grows south into the Equipment district; its corridor still
        # touches it, so only the overlap rule can catch this.
        self.districts['central_plaza']['size'][2] += 12
        self.rejects('overlaps')

    def test_district_without_touching_corridor_rejected(self):
        self.districts['equipment']['expansion_corridor']['origin'][0] += 3
        self.rejects('expansion corridor must touch')

    def test_populated_reserved_parcel_rejected(self):
        self.exhibit('equip_armour_reserved')['entities'] = ['chest']
        self.rejects('reserved parcel stays empty')

    def test_district_too_small_for_its_exhibits_rejected(self):
        self.districts['equipment']['size'] = [34, 10, 14]
        self.rejects('is full at exhibit')

    def test_new_item_without_a_category_rejected(self):
        # The growth rule's teeth since the Supply Depot stocks every classified
        # visible item: an unclassified one is named, with the file to fix.
        self.bundle['content']['items'].append(dict(self.bundle['content']['items'][0], id='mithril'))
        self.rejects("no Expo category.*mithril")

    def test_unknown_deferral_card_rejected(self):
        self.expo['deferred_items']['chest'] = 'Z'
        self.rejects('unknown card')


class SupplyDepotTests(unittest.TestCase):
    """The Supply Depot generation rules (docs/DEVELOPMENT_EXPO.md, handoff 8).

    The Python oracle here must agree with `SupplyDepot` in
    game/scripts/expo/supply_depot.gd; the runtime half is asserted by T223 in
    `--development-expo-automation=gate`.
    """

    def setUp(self):
        self.bundle = copy.deepcopy(load_bundle())
        self.expo = self.bundle['development_expo']
        self.content = self.bundle['content']
        self.catalog = supply_catalog(self.content, self.expo)

    def rejects(self, message):
        with self.assertRaisesRegex(ValidationError, message):
            validate_bundle(self.bundle)

    def visible(self):
        return [row['id'] for row in self.content['items'] if not row.get('hidden')]

    def test_every_visible_item_is_stocked_exactly_once(self):
        stocked = [item for chest in self.catalog['chests'] for item in chest['items']]
        self.assertEqual(sorted(stocked), sorted(self.visible()))
        self.assertEqual(len(stocked), len(set(stocked)))
        self.assertEqual(self.catalog['units'], 8)

    def test_hidden_items_stay_out_unless_whitelisted(self):
        stocked = {item for chest in self.catalog['chests'] for item in chest['items']}
        self.assertNotIn('enemy_core', stocked)
        self.expo['supply']['hidden_whitelist'] = ['enemy_core']
        whitelisted = supply_catalog(self.content, self.expo)
        self.assertIn('enemy_core', {item for chest in whitelisted['chests'] for item in chest['items']})

    def test_chests_respect_the_type_and_slot_budget(self):
        stacks = {row['id']: row for row in self.content['items']}
        for chest in self.catalog['chests']:
            self.assertLessEqual(len(chest['items']), 8)
            self.assertLessEqual(chest['slots'], 8, chest)
            self.assertEqual(chest['slots'], sum(supply_slots(stacks[item], 8) for item in chest['items']))
            # One category per chest: its sign's header is that category's label.
            self.assertEqual(len({chest['category']}), 1)
        # Eight picks do not stack, so such a chest carries one type, not eight.
        picks = [chest for chest in self.catalog['chests'] if chest['items'] == ['iron_pick']]
        self.assertEqual(len(picks), 1)

    def test_catalog_is_deterministic(self):
        self.assertEqual(self.catalog, supply_catalog(self.content, self.expo))

    def test_future_categories_are_signage_only(self):
        self.assertEqual([row['category'] for row in self.catalog['reserved']],
                         ['future_food', 'future_armor'])
        self.assertFalse([chest for chest in self.catalog['chests']
                          if chest['category'] in ('future_food', 'future_armor')])

    def test_category_map_classifies_every_visible_item(self):
        _order, mapping = item_categories()
        self.assertFalse([item for item in self.visible() if item not in mapping])

    def test_unclassified_item_is_reported(self):
        self.content['items'].append(dict(self.content['items'][0], id='mithril'))
        self.assertEqual(supply_catalog(self.content, self.expo)['unassigned'], ['mithril'])
        self.rejects("no Expo category.*mithril")

    def test_depot_parcel_too_small_rejected(self):
        exhibit = self.expo['districts'][1]['exhibits'][0]
        self.assertEqual(exhibit['id'], 'supply_depot_stock')
        exhibit['footprint'] = [20, 4, 4]
        self.rejects('do not fit the depot parcel')

    def test_parcel_capacity_holds_the_catalog_with_room_to_grow(self):
        _origin, size, _district = expo_parcels(self.expo)['supply_depot_stock']
        stands = len(self.catalog['chests']) + len(self.catalog['reserved'])
        self.assertLessEqual(stands, supply_capacity(size))


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
