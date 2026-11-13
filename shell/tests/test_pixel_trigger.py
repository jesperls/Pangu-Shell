import importlib.util
from pathlib import Path
import tempfile
import unittest

import numpy as np


SHELL = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("pixel_trigger", SHELL / "scripts/pixel_trigger.py")
pt = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pt)


def _solid(h: int, w: int, rgb: tuple[int, int, int]) -> np.ndarray:
    arr = np.empty((h, w, 3), dtype=np.uint8)
    arr[:, :] = rgb
    return arr


class PixelTriggerTest(unittest.TestCase):
    def test_ppm_and_png_roundtrip_and_hex_helpers(self):
        self.assertEqual(pt.normalize_hex_color("#f3a"), "#FF33AA")
        self.assertEqual(pt.normalize_hex_color("09bcde"), "#09BCDE")
        self.assertEqual(pt.normalize_hex_color("nope"), "")

        img = np.zeros((6, 8, 3), dtype=np.uint8)
        img[:, :, 0] = np.arange(8, dtype=np.uint8) * 30
        img[:, :, 1] = np.arange(6, dtype=np.uint8)[:, None] * 40
        img[:, :, 2] = 127

        ppm = b"P6\n# grim comment\n8 6\n255\n" + img.tobytes()
        parsed_ppm = pt.parse_ppm(ppm)
        np.testing.assert_array_equal(parsed_ppm, img)

        with tempfile.TemporaryDirectory(prefix="pangu-px-") as tmp:
            png_path = Path(tmp) / "snap.png"
            pt.write_png_atomic(png_path, img)
            parsed_png = pt.read_image_rgb(png_path)
            np.testing.assert_array_equal(parsed_png, img)

    def test_perceptual_distance_bounds_and_distinct_palette_extraction(self):
        black = np.array([[0, 0, 0]], dtype=np.uint8)
        white = np.array([[255, 255, 255]], dtype=np.uint8)
        red = np.array([[255, 0, 0]], dtype=np.uint8)
        cyan = np.array([[0, 255, 255]], dtype=np.uint8)
        self.assertAlmostEqual(float(pt.perceptual_dist_pct(black, black)[0]), 0.0, places=5)
        self.assertAlmostEqual(float(pt.perceptual_dist_pct(black, white)[0]), 100.0, places=4)
        self.assertAlmostEqual(float(pt.perceptual_dist_pct(red, cyan)[0]), 100.0, places=4)

        badge = _solid(20, 20, (20, 24, 32))
        badge[4:14, 4:14] = (52, 199, 89)
        badge[6:10, 6:10] = (255, 214, 10)
        palette = pt.extract_distinct_colors(badge, max_colors=4, min_sep_pct=12.0)
        hexes = [entry["hex"] for entry in palette]
        self.assertEqual(len(hexes), 3)
        self.assertIn("#141820", hexes)
        self.assertIn("#34C759", hexes)
        self.assertIn("#FFD60A", hexes)

    def test_pixel_color_modes_edge_hold_and_cooldown(self):
        rule = pt.compile_rule(
            {
                "id": "hp_pixel",
                "targetMode": "pixel",
                "watchMode": "color",
                "x": 120,
                "y": 40,
                "colors": ["#FF3B30", "#FF9500"],
                "colorLogic": "any",
                "colorTolerance": 12,
                "fireOnEdge": True,
                "minHoldMs": 100,
                "cooldownMs": 500,
            }
        )
        state = pt.RuleState()

        tel0, f0 = pt.evaluate_frame(rule, state, _solid(1, 1, (40, 200, 80)), 1.00)
        self.assertIsNone(f0)
        self.assertFalse(tel0["matched"])

        # Slight tint near #FF3B30 passes 12% tolerance, waits for 100ms hold, then fires once on edge.
        near_red = _solid(1, 1, (248, 65, 52))
        tel1, f1 = pt.evaluate_frame(rule, state, near_red, 1.10)
        self.assertTrue(tel1["matched"])
        self.assertIsNone(f1)

        tel2, f2 = pt.evaluate_frame(rule, state, near_red, 1.22)
        self.assertIsNotNone(f2)
        self.assertIn("#FF3B30", f2)

        # Staying red does not re-fire while fireOnEdge is True, even past cooldown.
        _, f3 = pt.evaluate_frame(rule, state, near_red, 2.00)
        self.assertIsNone(f3)

        # Returning to green re-arms; rapid return within cooldown waits until cooldown expires.
        pt.evaluate_frame(rule, state, _solid(1, 1, (40, 200, 80)), 1.40)
        pt.evaluate_frame(rule, state, near_red, 1.45)
        _, f_early = pt.evaluate_frame(rule, state, near_red, 1.56)
        self.assertIsNone(f_early)
        _, f_ready = pt.evaluate_frame(rule, state, near_red, 1.75)
        self.assertIsNotNone(f_ready)

    def test_area_color_any_all_and_none_logics(self):
        frame = _solid(10, 10, (15, 15, 20))
        frame[0:3, 0:10] = (255, 59, 48)  # 30% #FF3B30

        all_rule = pt.compile_rule(
            {
                "id": "badge_all",
                "targetMode": "area",
                "watchMode": "color",
                "width": 10,
                "height": 10,
                "colors": ["#FF3B30", "#00A8FF"],
                "colorLogic": "all",
                "colorTolerance": 10,
                "areaThreshold": 25,
                "fireOnEdge": False,
            }
        )
        st_all = pt.RuleState()
        # 30% >= 25%, but second color #00A8FF is missing -> must NOT match.
        tel_missing, fired_missing = pt.evaluate_frame(all_rule, st_all, frame, 1.0)
        self.assertFalse(tel_missing["matched"])
        self.assertIsNone(fired_missing)

        frame[3:4, 0:5] = (0, 168, 255)  # Add 5% #00A8FF -> both present, union 35% >= 25%.
        tel_both, fired_both = pt.evaluate_frame(all_rule, st_all, frame, 2.5)
        self.assertTrue(tel_both["matched"])
        self.assertIsNotNone(fired_both)

        none_rule = pt.compile_rule(
            {
                "id": "buff_gone",
                "targetMode": "area",
                "watchMode": "color",
                "width": 10,
                "height": 10,
                "colors": ["#FF3B30"],
                "colorLogic": "none",
                "colorTolerance": 10,
                "areaThreshold": 15,
            }
        )
        st_none = pt.RuleState()
        _, f_present = pt.evaluate_frame(none_rule, st_none, frame, 1.0)
        self.assertIsNone(f_present)
        _, f_gone = pt.evaluate_frame(none_rule, st_none, _solid(10, 10, (15, 15, 20)), 2.5)
        self.assertIsNotNone(f_gone)

    def test_previous_and_baseline_visual_change_detection(self):
        prev_rule = pt.compile_rule(
            {
                "id": "flash_box",
                "targetMode": "area",
                "watchMode": "change",
                "changeRef": "previous",
                "width": 10,
                "height": 10,
                "changeThreshold": 15,
                "areaThreshold": 20,
                "minHoldMs": 120,
                "cooldownMs": 500,
            }
        )
        st_prev = pt.RuleState()
        base = _solid(10, 10, (30, 30, 35))
        _, f0 = pt.evaluate_frame(prev_rule, st_prev, base, 0.0)
        self.assertIsNone(f0)

        # Minor shader noise (+4 RGB) stays below 15% pixel delta -> ignored.
        noisy = _solid(10, 10, (34, 33, 38))
        _, f_noise = pt.evaluate_frame(prev_rule, st_prev, noisy, 0.1)
        self.assertIsNone(f_noise)

        # 1-frame transient flicker resets before 120ms hold completes.
        changed = base.copy()
        changed[0:4, 0:10] = (230, 220, 80)  # 40% changed
        _, f_transient = pt.evaluate_frame(prev_rule, st_prev, changed, 0.20)
        self.assertIsNone(f_transient)
        _, f_reverted = pt.evaluate_frame(prev_rule, st_prev, base, 0.26)
        self.assertIsNone(f_reverted)

        # Persistent step change holds across 120ms and fires once, adopting new steady state.
        _, f_hold0 = pt.evaluate_frame(prev_rule, st_prev, changed, 1.00)
        self.assertIsNone(f_hold0)
        _, f_hold1 = pt.evaluate_frame(prev_rule, st_prev, changed, 1.15)
        self.assertIsNotNone(f_hold1)
        _, f_steady = pt.evaluate_frame(prev_rule, st_prev, changed, 2.00)
        self.assertIsNone(f_steady)

        with tempfile.TemporaryDirectory(prefix="pangu-px-base-") as tmp:
            bpath = Path(tmp) / "ref.png"
            pt.write_png_atomic(bpath, base)
            base_rule = pt.compile_rule(
                {
                    "id": "slot_state",
                    "targetMode": "area",
                    "watchMode": "change",
                    "changeRef": "baseline",
                    "baselinePath": str(bpath),
                    "width": 10,
                    "height": 10,
                    "changeThreshold": 15,
                    "areaThreshold": 20,
                    "fireOnEdge": True,
                }
            )
            st_base = pt.RuleState()
            _, fb0 = pt.evaluate_frame(base_rule, st_base, base, 1.0)
            self.assertIsNone(fb0)
            _, fb1 = pt.evaluate_frame(base_rule, st_base, changed, 2.5)
            self.assertIsNotNone(fb1)

    def test_capture_batching_coalesces_nearby_and_splits_distant_monitors(self):
        r1 = pt.compile_rule({"id": "a", "targetMode": "pixel", "x": 100, "y": 100})
        r2 = pt.compile_rule({"id": "b", "targetMode": "area", "x": 120, "y": 110, "width": 30, "height": 20})
        r3 = pt.compile_rule({"id": "c", "targetMode": "pixel", "x": 2200, "y": -1200})
        batches = pt.group_capture_batches([r1, r2, r3])
        self.assertEqual(len(batches), 2)
        self.assertEqual([r.id for r in batches[0][4]], ["a", "b"])
        self.assertEqual((batches[0][0], batches[0][1], batches[0][2], batches[0][3]), (100, 100, 50, 30))
        self.assertEqual([r.id for r in batches[1][4]], ["c"])


if __name__ == "__main__":
    unittest.main()
