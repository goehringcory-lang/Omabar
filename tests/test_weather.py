"""Checks for bin/omabar-weather. Run from the repository root:

    python3 -m unittest discover -s tests
"""
import contextlib
import datetime as dt
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error

sys.dont_write_bytecode = True
HELPER = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "bin", "omabar-weather")


def load():
    loader = importlib.machinery.SourceFileLoader("omabar_weather", HELPER)
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader("omabar_weather", loader))
    loader.exec_module(module)
    return module


def http_error(code):
    return urllib.error.HTTPError("https://api.weather.gov", code, "error", {}, io.BytesIO(b"{}"))


def make_period(name, is_day, temp, short="Sunny", detail="", start="2026-11-20T12:00:00-08:00",
                end="2026-11-20T18:00:00-08:00", precip=None, wind_dir="NW", wind_speed="5 to 10 mph",
                humidity=None, icon="", unit="F"):
    return {
        "name": name,
        "isDaytime": is_day,
        "temperature": temp,
        "temperatureUnit": unit,
        "shortForecast": short,
        "detailedForecast": detail or f"{short}, temperature around {temp}.",
        "startTime": start,
        "endTime": end,
        "probabilityOfPrecipitation": {"unitCode": "wmoUnit:percent", "value": precip},
        "relativeHumidity": {"unitCode": "wmoUnit:percent", "value": humidity},
        "windDirection": wind_dir,
        "windSpeed": wind_speed,
        "icon": icon,
    }


class CoordsAndUnits(unittest.TestCase):
    def test_parses_mapclick_and_api_urls(self):
        w = load()
        url = "https://forecast.weather.gov/MapClick.php?lon=-119.78244423866272&lat=37.67552934366611"
        self.assertEqual(w.resolve_coords(url=url), (37.6755, -119.7824))
        self.assertEqual(w.resolve_coords(), (37.6755, -119.7824))
        self.assertEqual(
            w.resolve_coords(url="https://api.weather.gov/points/40.7128,-74.0060"),
            (40.7128, -74.006),
        )
        with self.assertRaises(ValueError):
            w.resolve_coords(url="https://forecast.weather.gov/MapClick.php?foo=bar")
        with self.assertRaises(ValueError):
            w.resolve_coords(lat=99.0, lon=-120.0)

    def test_temperature_conversion(self):
        w = load()
        self.assertEqual(w.convert_temp(68, "F", "C"), 20)
        self.assertEqual(w.convert_temp(32, "F", "C"), 0)
        self.assertEqual(w.convert_temp(0, "C", "F"), 32)
        self.assertEqual(w.convert_temp(72, "F", "F"), 72)
        self.assertIsNone(w.convert_temp(None, "F", "C"))


class Conditions(unittest.TestCase):
    def test_classifies_common_nws_forecasts(self):
        w = load()
        cases = [
            ("Sunny", "", True, "sunny"),
            ("Clear", "", False, "clear-night"),
            ("Mostly Sunny", "", True, "partly-cloudy"),
            ("Mostly Clear", "", False, "partly-cloudy-night"),
            ("Partly Cloudy", "", True, "partly-cloudy"),
            ("Mostly Cloudy", "", True, "cloudy"),
            ("Areas Of Fog", "", True, "fog"),
            ("Chance Rain Showers", "", True, "rain"),
            ("Heavy Rain", "", True, "heavy-rain"),
            ("Showers And Thunderstorms Likely", "", True, "thunderstorm"),
            ("Slight Chance Snow Showers", "", False, "snow"),
            ("Heavy Snow", "", True, "heavy-snow"),
            ("Rain And Snow Likely", "", True, "sleet"),
            ("Windy", "", True, "windy"),
            ("", "https://api.weather.gov/icons/land/night/skc?size=medium", False, "clear-night"),
            ("", "https://api.weather.gov/icons/land/day/tsra_sct?size=medium", True, "thunderstorm"),
        ]
        for short, icon, is_day, expected in cases:
            with self.subTest(short=short, icon=icon, is_day=is_day):
                self.assertEqual(w.classify_condition(short, icon, is_day), expected)


class ForecastShaping(unittest.TestCase):
    def test_groups_daytime_start_into_five_days_and_handles_holidays(self):
        w = load()
        periods = [
            make_period("This Afternoon", True, 61, "Sunny", start="2026-11-20T14:00:00-08:00", precip=0),
            make_period("Tonight", False, 39, "Mostly Clear", start="2026-11-20T18:00:00-08:00", precip=10),
            make_period("Saturday", True, 64, "Partly Sunny", start="2026-11-21T06:00:00-08:00", precip=20),
            make_period("Saturday Night", False, 42, "Mostly Cloudy", start="2026-11-21T18:00:00-08:00", precip=40),
            make_period("Sunday", True, 55, "Rain Likely", start="2026-11-22T06:00:00-08:00", precip=70),
            make_period("Sunday Night", False, 36, "Chance Rain", start="2026-11-22T18:00:00-08:00", precip=30),
            make_period("Monday", True, 58, "Sunny", start="2026-11-23T06:00:00-08:00", precip=None),
            make_period("Monday Night", False, 35, "Clear", start="2026-11-23T18:00:00-08:00", precip=None),
            make_period("Thanksgiving Day", True, 60, "Mostly Sunny", start="2026-11-24T06:00:00-08:00", precip=0),
            make_period("Tuesday Night", False, 38, "Clear", start="2026-11-24T18:00:00-08:00", precip=0),
            make_period("Wednesday", True, 62, "Sunny", start="2026-11-25T06:00:00-08:00", precip=0),
        ]
        days = w.group_days(periods, 5, "F")
        self.assertEqual(len(days), 5)
        self.assertEqual([d["label"] for d in days], ["Today", "Sat", "Sun", "Mon", "Tue"])
        self.assertEqual(days[0]["high"], 61)
        self.assertEqual(days[0]["low"], 39)
        self.assertEqual(days[0]["precip"], 10)
        self.assertEqual(days[1]["precip"], 40)
        self.assertEqual(days[4]["fullLabel"], "Thanksgiving Day")
        self.assertIsNotNone(days[4]["day"])
        self.assertIsNotNone(days[4]["night"])

    def test_groups_nighttime_start_cleanly(self):
        w = load()
        periods = [
            make_period("Tonight", False, 39, "Clear", start="2026-11-20T20:00:00-08:00"),
            make_period("Saturday", True, 64, "Sunny", start="2026-11-21T06:00:00-08:00"),
            make_period("Saturday Night", False, 41, "Clear", start="2026-11-21T18:00:00-08:00"),
            make_period("Sunday", True, 62, "Partly Sunny", start="2026-11-22T06:00:00-08:00"),
            make_period("Sunday Night", False, 40, "Mostly Clear", start="2026-11-22T18:00:00-08:00"),
        ]
        days = w.group_days(periods, 5, "F")
        self.assertEqual(len(days), 3)
        self.assertEqual(days[0]["label"], "Tonight")
        self.assertIsNone(days[0]["high"])
        self.assertEqual(days[0]["low"], 39)
        self.assertIsNone(days[0]["day"])
        self.assertIsNotNone(days[0]["night"])
        self.assertEqual((days[1]["label"], days[1]["high"], days[1]["low"]), ("Sat", 64, 41))


class FetchAndCache(unittest.TestCase):
    def setUp(self):
        self.w = load()
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.w.CACHE_DIR = self.dir.name
        self.w.time.sleep = lambda seconds: None
        self.calls = []

    def stub_api(self, forecast_periods=None, hourly_periods=None, alerts=None, fail_all=None):
        point_resp = {
            "properties": {
                "forecast": "https://api.weather.gov/gridpoints/HNX/74,97/forecast",
                "forecastHourly": "https://api.weather.gov/gridpoints/HNX/74,97/forecast/hourly",
                "relativeLocation": {"properties": {"city": "El Portal", "state": "CA"}},
            }
        }
        if forecast_periods is None:
            forecast_periods = [
                make_period("This Afternoon", True, 61, "Sunny", start="2026-11-20T14:00:00-08:00"),
                make_period("Tonight", False, 39, "Clear", start="2026-11-20T18:00:00-08:00"),
                make_period("Saturday", True, 64, "Sunny", start="2026-11-21T06:00:00-08:00"),
                make_period("Saturday Night", False, 41, "Clear", start="2026-11-21T18:00:00-08:00"),
            ]
        if hourly_periods is None:
            hourly_periods = [
                make_period("", True, 57, "Sunny", start="2026-11-20T13:00:00-08:00",
                            end="2026-11-20T14:00:00-08:00", humidity=42),
                make_period("", True, 59, "Sunny", start="2026-11-20T14:00:00-08:00",
                            end="2026-11-20T15:00:00-08:00", humidity=38),
            ]
        alerts_resp = {"features": alerts or []}

        def api_get(url):
            self.calls.append(url)
            if fail_all is not None:
                raise fail_all
            if "/points/" in url:
                return point_resp
            if url.endswith("/forecast/hourly"):
                return {"properties": {"periods": hourly_periods}}
            if url.endswith("/forecast"):
                return {"properties": {"periods": forecast_periods}}
            if "/alerts/active" in url:
                return alerts_resp
            self.fail("unexpected url: " + url)

        self.w.api_get = api_get

    def test_fetches_caches_and_selects_active_hour(self):
        self.stub_api(alerts=[
            {"properties": {"event": "Wind Advisory", "severity": "Moderate", "headline": "Gusty winds expected"}},
            {"properties": {"event": "Wind Advisory", "severity": "Moderate", "headline": "Duplicate"}},
        ])
        now = dt.datetime(2026, 11, 20, 14, 30, tzinfo=dt.timezone(dt.timedelta(hours=-8)))
        first = self.w.fetch_forecast(37.6755, -119.7824, days_count=5, units="F", now=now)
        self.assertTrue(first["ok"])
        self.assertEqual(first["location"], "El Portal, CA")
        self.assertEqual(first["current"]["temp"], 59)
        self.assertEqual(first["current"]["humidity"], 38)
        self.assertEqual(first["current"]["high"], 61)
        self.assertEqual(first["current"]["low"], 39)
        self.assertEqual(len(first["alerts"]), 1)
        self.assertEqual(first["alerts"][0]["event"], "Wind Advisory")
        call_count = len(self.calls)

        second = self.w.fetch_forecast(37.6755, -119.7824, days_count=5, units="F", now=now)
        self.assertEqual(len(self.calls), call_count, "second call comes from cache")
        self.assertEqual(second["location"], "El Portal, CA")

        # --force bypasses the forecast cache.
        self.w.fetch_forecast(37.6755, -119.7824, days_count=5, units="F", force=True, now=now)
        self.assertGreater(len(self.calls), call_count)

    def test_offline_falls_back_to_stale_cache(self):
        self.stub_api()
        now = dt.datetime(2026, 11, 20, 14, 30, tzinfo=dt.timezone(dt.timedelta(hours=-8)))
        self.w.fetch_forecast(37.6755, -119.7824, days_count=5, units="F", now=now)

        self.stub_api(fail_all=urllib.error.URLError("offline"))
        stale = self.w.fetch_forecast(37.6755, -119.7824, days_count=5, units="F", force=True, now=now)
        self.assertTrue(stale["ok"])
        self.assertTrue(stale["stale"])
        self.assertIn("saved forecast", stale["error"])
        self.assertEqual(stale["location"], "El Portal, CA")

    def test_cli_returns_clean_json_on_error(self):
        self.stub_api(fail_all=http_error(404))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = self.w.main(["--lat", "51.5", "--lon", "-0.12"])
        self.assertEqual(rc, 0)
        got = json.loads(out.getvalue())
        self.assertFalse(got["ok"])
        self.assertIn("US", got["error"])


if __name__ == "__main__":
    unittest.main()
