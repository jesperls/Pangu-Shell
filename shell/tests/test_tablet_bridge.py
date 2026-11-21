import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
import tablet_bridge as tb


SAMPLE_GETEVENT = """
add device 4: /dev/input/event7
  name:     "onyx_ts_istaric"
  events:
    ABS (0003): ABS_MT_SLOT           : value 1, min 0, max 9, fuzz 0, flat 0, resolution 0
                ABS_MT_POSITION_X     : value 0, min 0, max 1859, fuzz 0, flat 0, resolution 0
                ABS_MT_POSITION_Y     : value 0, min 0, max 2479, fuzz 0, flat 0, resolution 0
  input props:
    INPUT_PROP_DIRECT
add device 5: /dev/input/event5
  name:     "onyx_emp_istaric_pen"
  events:
    KEY (0001): BTN_DIGI              BTN_TOOL_RUBBER       BTN_TOOL_BRUSH*       BTN_TOUCH
                BTN_STYLUS            BTN_STYLUS2
    ABS (0003): ABS_X                 : value 13047, min 0, max 20832, fuzz 0, flat 0, resolution 0
                ABS_Y                 : value 8364, min 0, max 15624, fuzz 0, flat 0, resolution 0
                ABS_PRESSURE          : value 0, min 0, max 4095, fuzz 0, flat 0, resolution 0
                ABS_TILT_X            : value -12, min -90, max 90, fuzz 0, flat 0, resolution 0
                ABS_TILT_Y            : value -31, min -90, max 90, fuzz 0, flat 0, resolution 0
  input props:
    INPUT_PROP_DIRECT
"""


class TabletBridgeTest(unittest.TestCase):
    def test_parse_adb_devices(self):
        out = (
            "* daemon started successfully\n"
            "List of devices attached\n"
            "4e982bb5               device usb:1-2 product:NoteAir6C model:NoteAir6C device:NoteAir6C\n"
            "192.168.1.50:5555      unauthorized transport_id:2\n"
        )
        devices = tb.parse_adb_devices(out)
        self.assertEqual(len(devices), 2)
        self.assertEqual(devices[0], {"serial": "4e982bb5", "state": "device", "model": "NoteAir6C"})
        self.assertEqual(devices[1], {"serial": "192.168.1.50:5555", "state": "unauthorized", "model": ""})
        self.assertFalse(tb.is_wireless_serial("4e982bb5"))
        self.assertTrue(tb.is_wireless_serial("192.168.1.50:5555"))

    def test_parse_wifi_ip(self):
        out = (
            "1: lo    inet 127.0.0.1/8 scope host lo\\       valid_lft forever preferred_lft forever\n"
            "15: wlan0    inet 192.168.50.182/24 brd 192.168.50.255 scope global wlan0\\       valid_lft forever preferred_lft forever\n"
        )
        self.assertEqual(tb.parse_wifi_ip(out), "192.168.50.182")

    def test_select_pen_device_from_getevent(self):
        devices = tb.parse_getevent_devices(SAMPLE_GETEVENT)
        self.assertEqual(len(devices), 2)
        pen = tb.select_pen_device(devices)
        self.assertIsNotNone(pen)
        self.assertEqual(pen["path"], "/dev/input/event5")
        self.assertEqual(pen["name"], "onyx_emp_istaric_pen")
        self.assertIn("BTN_TOOL_BRUSH", pen["keys"])
        self.assertEqual(pen["abs"]["ABS_X"]["max"], 20832)
        self.assertEqual(pen["abs"]["ABS_Y"]["max"], 15624)
        self.assertEqual(pen["abs"]["ABS_PRESSURE"]["max"], 4095)
        self.assertEqual(pen["abs"]["ABS_TILT_X"]["min"], -90)
        touch = tb.select_touch_device(devices, pen["path"])
        self.assertIsNotNone(touch)
        self.assertEqual(touch["path"], "/dev/input/event7")
        self.assertEqual(touch["name"], "onyx_ts_istaric")

    def test_active_rect_fit_tablet_crops_4_3_for_16_9(self):
        u0, v0, u1, v1 = tb.compute_active_rect(
            20832, 15624, 0, 1.0, 0.0, 0.0, "fit-tablet", 2560 / 1440
        )
        self.assertAlmostEqual(u0, 0.0, places=5)
        self.assertAlmostEqual(u1, 1.0, places=5)
        self.assertAlmostEqual(v1 - v0, 0.75, places=5)
        self.assertAlmostEqual(v0, 0.125, places=5)
        self.assertAlmostEqual(v1, 0.875, places=5)

    def test_active_rect_scale_and_offset_clamping(self):
        u0, v0, u1, v1 = tb.compute_active_rect(
            20832, 15624, 0, 0.5, 0.5, -0.5, "stretch", 1.0
        )
        self.assertAlmostEqual(u0, 0.5, places=5)
        self.assertAlmostEqual(u1, 1.0, places=5)
        self.assertAlmostEqual(v0, 0.0, places=5)
        self.assertAlmostEqual(v1, 0.5, places=5)

    def test_rotation_and_flips(self):
        self.assertEqual(tb.rotate_normalized(0.2, 0.8, 0, False, False), (0.2, 0.8))
        u, v = tb.rotate_normalized(0.2, 0.8, 90, False, False)
        self.assertAlmostEqual(u, 0.2, places=5)
        self.assertAlmostEqual(v, 0.2, places=5)
        u, v = tb.rotate_normalized(0.2, 0.8, 180, False, False)
        self.assertAlmostEqual(u, 0.8, places=5)
        self.assertAlmostEqual(v, 0.2, places=5)
        u, v = tb.rotate_normalized(0.2, 0.8, 0, True, False)
        self.assertAlmostEqual(u, 0.8, places=5)
        self.assertAlmostEqual(v, 0.8, places=5)
        self.assertEqual(tb.rotate_tilt(10, -20, 90, False, False), (20, 10))
        self.assertEqual(tb.rotate_tilt(10, -20, 180, False, False), (-10, 20))
        self.assertEqual(tb.rotate_tilt(10, -20, 0, True, True), (-10, 20))

    def test_pressure_curve(self):
        self.assertEqual(tb.apply_pressure_curve(200, 4095, True, 1.0, 0.1, 1.0), 0)
        self.assertEqual(tb.apply_pressure_curve(4095, 4095, True, 1.0, 0.0, 1.0), 4095)
        soft = tb.apply_pressure_curve(2048, 4095, True, 0.5, 0.0, 1.0)
        linear = tb.apply_pressure_curve(2048, 4095, True, 1.0, 0.0, 1.0)
        firm = tb.apply_pressure_curve(2048, 4095, True, 2.0, 0.0, 1.0)
        self.assertGreater(soft, linear)
        self.assertGreater(linear, firm)
        sat = tb.apply_pressure_curve(2048, 4095, True, 1.0, 0.0, 0.5)
        self.assertEqual(sat, 4095)
        flat = tb.apply_pressure_curve(10, 4095, False, 2.0, 0.2, 1.0, touching=True)
        self.assertEqual(flat, 4095)

    def test_config_loader_normalizes_and_reloads(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "tablet.json"
            path.write_text(json.dumps({
                "rotation": 90,
                "areaScale": 0.1,
                "pressureGamma": 10.0,
                "pressureMin": 0.4,
                "pressureMax": 0.42,
                "wirelessAddress": " 192.168.50.182:5555 ",
                "wirelessAutoConnect": False,
                "suppressPen": False,
                "suppressTouch": True,
                "keepAwake": False,
            }))
            loader = tb.ConfigLoader(str(path))
            self.assertEqual(loader.config["rotation"], 90)
            self.assertEqual(loader.config["areaScale"], 0.25)
            self.assertEqual(loader.config["pressureGamma"], 3.0)
            self.assertAlmostEqual(loader.config["pressureMax"] - loader.config["pressureMin"], 0.05, places=5)
            self.assertEqual(loader.config["wirelessAddress"], "192.168.50.182:5555")
            self.assertFalse(loader.config["wirelessAutoConnect"])
            self.assertFalse(loader.config["suppressPen"])
            self.assertTrue(loader.config["suppressTouch"])
            self.assertFalse(loader.config["keepAwake"])

    def test_keep_awake_interval(self):
        self.assertEqual(tb.compute_keep_awake_interval(300000), 45.0)
        self.assertAlmostEqual(tb.compute_keep_awake_interval(30000), 13.5, places=5)
        self.assertEqual(tb.compute_keep_awake_interval(15000), 10.0)
        self.assertEqual(tb.compute_keep_awake_interval(0), 30.0)

    def test_sensor_orientation_and_touchpad_rotation(self):
        sample = (
            "  Device 8: onyx_ts_istaric\n"
            "    Touch Input Mapper (mode - DIRECT):\n"
            "      Parameters:\n"
            "        Orientation: Rotation0\n"
            "  Device 7: onyx_emp_istaric_pen\n"
            "    Touch Input Mapper (mode - DIRECT):\n"
            "      Parameters:\n"
            "        Orientation: Rotation270\n"
        )
        orients = tb.parse_sensor_orientations(sample)
        self.assertEqual(orients["onyx_ts_istaric"], 0)
        self.assertEqual(orients["onyx_emp_istaric_pen"], 270)
        devices = tb.parse_getevent_devices(SAMPLE_GETEVENT)
        pen = tb.select_pen_device(devices)
        touch = tb.select_touch_device(devices, pen["path"])
        self.assertEqual(tb.resolve_touchpad_rotation("auto", 0, orients, pen, touch), 90)
        self.assertEqual(tb.resolve_touchpad_rotation("auto", 90, orients, pen, touch), 180)
        self.assertEqual(tb.resolve_touchpad_rotation("270", 0, orients, pen, touch), 270)

    def test_touchpad_mapper_multitouch_and_palm_rejection(self):
        class FakeE:
            EV_SYN = 0
            EV_KEY = 1
            EV_ABS = 3
            SYN_REPORT = 0
            ABS_X = 0
            ABS_Y = 1
            ABS_MT_SLOT = 47
            ABS_MT_POSITION_X = 53
            ABS_MT_POSITION_Y = 54
            ABS_MT_TRACKING_ID = 57
            BTN_TOUCH = 330
            BTN_TOOL_FINGER = 325
            BTN_TOOL_DOUBLETAP = 333
            BTN_TOOL_TRIPLETAP = 334
            BTN_TOOL_QUADTAP = 335
            BTN_TOOL_QUINTTAP = 328

        class FakeUI:
            def __init__(self):
                self.events = []
                self.syns = 0

            def write(self, etype, code, val):
                self.events.append((etype, code, val))

            def syn(self):
                self.syns += 1

        orig_e = tb.e
        tb.e = FakeE
        try:
            devices = tb.parse_getevent_devices(SAMPLE_GETEVENT)
            pen = tb.select_pen_device(devices)
            touch = tb.select_touch_device(devices, pen["path"])
            ui = FakeUI()
            mapper = tb.TouchpadMapper(ui, touch, 9, 6000)

            # 2-finger touch down
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_SLOT, 0, False, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_TRACKING_ID, 10, False, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_POSITION_X, 930, False, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_POSITION_Y, 1240, False, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_SLOT, 1, False, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_TRACKING_ID, 11, False, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_POSITION_X, 1100, False, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_POSITION_Y, 1400, False, 90, False, False, 1.0)
            self.assertTrue(mapper.feed_event(FakeE.EV_SYN, FakeE.SYN_REPORT, 0, False, 90, False, False, 1.0))
            self.assertEqual(len(mapper.last_fingers), 2)
            self.assertTrue(mapper.emitted_touch)
            self.assertEqual(mapper.emitted_tool, FakeE.BTN_TOOL_DOUBLETAP)

            # Palm rejection mutes & releases all slots cleanly
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_SLOT, 0, True, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_POSITION_X, 940, True, 90, False, False, 1.0)
            self.assertTrue(mapper.feed_event(FakeE.EV_SYN, FakeE.SYN_REPORT, 0, True, 90, False, False, 1.0))
            self.assertFalse(mapper.emitted_touch)
            self.assertIsNone(mapper.emitted_tool)
            self.assertEqual(mapper.emitted_slots, {})
            # Resting palm stays ignored even after unmuting until lifted
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_POSITION_X, 945, False, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_SYN, FakeE.SYN_REPORT, 0, False, 90, False, False, 1.0)
            self.assertFalse(mapper.emitted_touch)
            # Fresh touch reusing slot 0 without an intervening -1 must clear suppression and work
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_TRACKING_ID, 25, False, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_POSITION_X, 960, False, 90, False, False, 1.0)
            mapper.feed_event(FakeE.EV_ABS, FakeE.ABS_MT_POSITION_Y, 1260, False, 90, False, False, 1.0)
            self.assertTrue(mapper.feed_event(FakeE.EV_SYN, FakeE.SYN_REPORT, 0, False, 90, False, False, 1.0))
            self.assertTrue(mapper.emitted_touch)
            self.assertEqual(mapper.emitted_tool, FakeE.BTN_TOOL_FINGER)
        finally:
            tb.e = orig_e


if __name__ == "__main__":
    unittest.main()
