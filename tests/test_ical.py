"""Checks for bin/omabar_ical.py. Run from the repository root:

    python3 -m unittest discover -s tests
"""
import datetime as dt
import os
import sys
import unittest
from zoneinfo import ZoneInfo

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "bin"))
import omabar_ical as ical  # noqa: E402

LA = ZoneInfo("America/Los_Angeles")


def feed(*events, tz="America/Los_Angeles"):
    lines = ["BEGIN:VCALENDAR", "X-WR-CALNAME:Test", f"X-WR-TIMEZONE:{tz}"]
    for event in events:
        lines += ["BEGIN:VEVENT"] + [line.strip() for line in event.strip().splitlines()] + ["END:VEVENT"]
    return "\r\n".join(lines + ["END:VCALENDAR"])


def starts(text, first, last, local=LA):
    """ISO starts of every occurrence between two local dates."""
    window = [dt.datetime.combine(dt.date.fromisoformat(d), dt.time(), local) for d in (first, last)]
    found = ical.expand_events(ical.read_calendar(text), window[0], window[1], local)
    return sorted(ical.iso(e["start"], local) for e in found)


def spans(text, first, last, local=LA):
    window = [dt.datetime.combine(dt.date.fromisoformat(d), dt.time(), local) for d in (first, last)]
    found = ical.expand_events(ical.read_calendar(text), window[0], window[1], local)
    return sorted((ical.iso(e["start"], local), ical.iso(e["end"], local)) for e in found)


class DaylightSaving(unittest.TestCase):
    def test_weekly_meeting_keeps_its_wall_clock_time(self):
        text = feed("""
            UID:a
            SUMMARY:Standup
            DTSTART;TZID=America/Los_Angeles:20260302T090000
            DTEND;TZID=America/Los_Angeles:20260302T093000
            RRULE:FREQ=WEEKLY;BYDAY=MO
        """)
        self.assertEqual(starts(text, "2026-03-01", "2026-03-17"), [
            "2026-03-02T09:00:00-08:00", "2026-03-09T09:00:00-07:00", "2026-03-16T09:00:00-07:00"])

    def test_autumn_change(self):
        text = feed("""
            UID:a
            DTSTART;TZID=America/Los_Angeles:20261026T180000
            DURATION:PT1H
            RRULE:FREQ=WEEKLY
        """)
        self.assertEqual(spans(text, "2026-10-26", "2026-11-03"), [
            ("2026-10-26T18:00:00-07:00", "2026-10-26T19:00:00-07:00"),
            ("2026-11-02T18:00:00-08:00", "2026-11-02T19:00:00-08:00")])

    def test_event_from_another_zone(self):
        text = feed("""
            UID:a
            DTSTART;TZID=Europe/Berlin:20260320T170000
            DTEND;TZID=Europe/Berlin:20260320T180000
        """)
        # Berlin is still on winter time on 20 March, Los Angeles already on summer time.
        self.assertEqual(starts(text, "2026-03-20", "2026-03-21"), ["2026-03-20T09:00:00-07:00"])

    def test_utc_times(self):
        text = feed("UID:a\nDTSTART:20260710T160000Z\nDTEND:20260710T170000Z")
        self.assertEqual(starts(text, "2026-07-10", "2026-07-11"), ["2026-07-10T09:00:00-07:00"])

    def test_time_without_a_zone_uses_the_calendars(self):
        text = feed("UID:a\nDTSTART:20260710T090000\nDTEND:20260710T100000", tz="America/New_York")
        self.assertEqual(starts(text, "2026-07-10", "2026-07-11"), ["2026-07-10T06:00:00-07:00"])


class AllDay(unittest.TestCase):
    def test_single_day(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20261120\nDTEND;VALUE=DATE:20261121")
        self.assertEqual(spans(text, "2026-11-01", "2026-12-01"), [("2026-11-20", "2026-11-21")])
        self.assertEqual(spans(text, "2026-11-21", "2026-12-01"), [])

    def test_multi_day_reaches_into_the_window(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20261128\nDTEND;VALUE=DATE:20261203")
        self.assertEqual(spans(text, "2026-12-01", "2027-01-01"), [("2026-11-28", "2026-12-03")])

    def test_no_end_is_one_day(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20261120")
        self.assertEqual(spans(text, "2026-11-01", "2026-12-01"), [("2026-11-20", "2026-11-21")])

    def test_yearly_birthday(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:19900704\nRRULE:FREQ=YEARLY")
        self.assertEqual(starts(text, "2026-01-01", "2028-01-01"), ["2026-07-04", "2027-07-04"])

    def test_leap_day_birthday_only_in_leap_years(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20000229\nRRULE:FREQ=YEARLY")
        self.assertEqual(starts(text, "2026-01-01", "2029-01-01"), ["2028-02-29"])

    def test_timed_event_over_midnight(self):
        text = feed("""
            UID:a
            DTSTART;TZID=America/Los_Angeles:20261120T220000
            DTEND;TZID=America/Los_Angeles:20261121T010000
        """)
        self.assertEqual(spans(text, "2026-11-21", "2026-11-22"),
                         [("2026-11-20T22:00:00-08:00", "2026-11-21T01:00:00-08:00")])


class Repeating(unittest.TestCase):
    def test_count_and_until(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20261102\nRRULE:FREQ=DAILY;COUNT=3")
        self.assertEqual(starts(text, "2026-11-01", "2026-12-01"), ["2026-11-02", "2026-11-03", "2026-11-04"])
        text = feed("""
            UID:a
            DTSTART;TZID=America/Los_Angeles:20261102T090000
            RRULE:FREQ=DAILY;UNTIL=20261104T170000Z
        """)
        self.assertEqual(len(starts(text, "2026-11-01", "2026-12-01")), 3)

    def test_count_is_counted_from_the_first_occurrence(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20260105\nRRULE:FREQ=WEEKLY;COUNT=4")
        self.assertEqual(starts(text, "2026-01-20", "2026-12-01"), ["2026-01-26"])

    def test_daily_event_from_long_ago_still_shows(self):
        text = feed("UID:a\nDTSTART;TZID=America/Los_Angeles:20050101T080000\nRRULE:FREQ=DAILY")
        self.assertEqual(starts(text, "2026-11-20", "2026-11-22"),
                         ["2026-11-20T08:00:00-08:00", "2026-11-21T08:00:00-08:00"])

    def test_every_other_week_with_sunday_week_start(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20260107\nRRULE:FREQ=WEEKLY;WKST=SU;INTERVAL=2;BYDAY=SU,WE")
        self.assertEqual(starts(text, "2026-01-01", "2026-01-25"), ["2026-01-07", "2026-01-18", "2026-01-21"])

    def test_last_friday_and_last_weekday(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20260130\nRRULE:FREQ=MONTHLY;BYDAY=-1FR")
        self.assertEqual(starts(text, "2026-02-01", "2026-04-01"), ["2026-02-27", "2026-03-27"])
        text = feed("UID:a\nDTSTART;VALUE=DATE:20260130\nRRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1")
        self.assertEqual(starts(text, "2026-02-01", "2026-06-01"),
                         ["2026-02-27", "2026-03-31", "2026-04-30", "2026-05-29"])

    def test_31st_skips_short_months(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20260131\nRRULE:FREQ=MONTHLY")
        self.assertEqual(starts(text, "2026-02-01", "2026-06-01"), ["2026-03-31", "2026-05-31"])

    def test_yearly_in_several_months(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20260315\nRRULE:FREQ=YEARLY;BYMONTH=3,9")
        self.assertEqual(starts(text, "2026-01-01", "2027-01-01"), ["2026-03-15", "2026-09-15"])

    def test_removed_and_moved_occurrences(self):
        text = feed("""
            UID:a
            SUMMARY:Class
            DTSTART;TZID=America/Los_Angeles:20261102T090000
            DTEND;TZID=America/Los_Angeles:20261102T100000
            RRULE:FREQ=WEEKLY;COUNT=4
            EXDATE;TZID=America/Los_Angeles:20261109T090000
        """, """
            UID:a
            SUMMARY:Class (moved)
            RECURRENCE-ID;TZID=America/Los_Angeles:20261116T090000
            DTSTART;TZID=America/Los_Angeles:20261117T140000
            DTEND;TZID=America/Los_Angeles:20261117T150000
        """)
        self.assertEqual(starts(text, "2026-11-01", "2026-12-01"), [
            "2026-11-02T09:00:00-08:00", "2026-11-17T14:00:00-08:00", "2026-11-23T09:00:00-08:00"])

    def test_cancelled_occurrence(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20261102\nRRULE:FREQ=DAILY;COUNT=2", """
            UID:a
            RECURRENCE-ID;VALUE=DATE:20261103
            DTSTART;VALUE=DATE:20261103
            STATUS:CANCELLED
        """)
        self.assertEqual(starts(text, "2026-11-01", "2026-12-01"), ["2026-11-02"])

    def test_extra_dates(self):
        text = feed("UID:a\nDTSTART;VALUE=DATE:20261102\nRDATE;VALUE=DATE:20261110,20261112")
        self.assertEqual(starts(text, "2026-11-01", "2026-12-01"), ["2026-11-02", "2026-11-10", "2026-11-12"])


class BadInput(unittest.TestCase):
    def test_one_bad_event_does_not_hide_the_rest(self):
        text = feed("UID:a\nDTSTART:not-a-date", "UID:b\nDTSTART;VALUE=DATE:20261120",
                    "UID:c\nDTSTART;VALUE=DATE:20261121\nRRULE:FREQ=MONTHLY;BYMONTHDAY=x;INTERVAL=abc",
                    "UID:d\nSUMMARY:no start")
        self.assertEqual(starts(text, "2026-11-01", "2026-12-01"), ["2026-11-20", "2026-11-21"])

    def test_not_a_calendar(self):
        self.assertEqual(ical.read_calendar("<html>Sign in</html>")["events"], [])

    def test_alarm_inside_event_is_ignored(self):
        text = feed("UID:a\nSUMMARY:Real\nDTSTART;VALUE=DATE:20261120\nBEGIN:VALARM\nSUMMARY:Alarm\nEND:VALARM")
        calendar = ical.read_calendar(text)
        window = [dt.datetime(2026, 11, 1, tzinfo=LA), dt.datetime(2026, 12, 1, tzinfo=LA)]
        self.assertEqual([e["title"] for e in ical.expand_events(calendar, window[0], window[1], LA)], ["Real"])


if __name__ == "__main__":
    unittest.main()
