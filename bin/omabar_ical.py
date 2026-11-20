"""Read iCalendar (.ics) feeds for omabar-gcal, with only the standard library.

Covers what calendar feeds such as Google's "secret address in iCal format"
contain: all-day and timed events, time zones by IANA name, durations, and
repeating events (RRULE with FREQ, INTERVAL, COUNT, UNTIL, WKST, BYDAY,
BYMONTHDAY, BYMONTH, BYSETPOS, plus RDATE), with EXDATE exceptions and
RECURRENCE-ID overrides.
"""
import datetime as dt
import re

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover - Python < 3.9
    ZoneInfo = None

WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
MAX_STEPS = 20000


# ── lines and properties ──────────────────────────────────────────────────

def unfold(text):
    lines = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        elif raw:
            lines.append(raw)
    return lines


def split_property(line):
    """'NAME;P=V;Q="a:b":value' -> (NAME, {P: V, Q: a:b}, value)."""
    quoted, cut = False, -1
    for i, ch in enumerate(line):
        if ch == '"':
            quoted = not quoted
        elif ch == ":" and not quoted:
            cut = i
            break
    if cut < 0:
        return line.upper(), {}, ""
    head, value = line[:cut], line[cut + 1:]
    parts = head.split(";")
    params = {}
    for part in parts[1:]:
        if "=" in part:
            key, val = part.split("=", 1)
            params[key.upper()] = val.strip('"')
    return parts[0].upper(), params, value


def unescape(value):
    return re.sub(r"\\([nN,;\\])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), value)


# ── times ─────────────────────────────────────────────────────────────────

def zone(name):
    if not name or ZoneInfo is None:
        return None
    try:
        return ZoneInfo(name)
    except Exception:
        return None


class When:
    """A start or end: a date (all day), or a wall-clock time in a zone
    (tz None means the viewer's local time)."""

    __slots__ = ("value", "tz")

    def __init__(self, value, tz=None):
        self.value, self.tz = value, tz

    @property
    def all_day(self):
        return not isinstance(self.value, dt.datetime)

    def instant(self, local):
        """An aware datetime (all-day: local midnight)."""
        if self.all_day:
            return dt.datetime.combine(self.value, dt.time(), local)
        return self.value.replace(tzinfo=self.tz or local)


def parse_when(value, params, default_tz):
    value = value.strip()
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        return When(dt.datetime.strptime(value[:8], "%Y%m%d").date())
    utc = value.endswith("Z")
    stamp = dt.datetime.strptime(value.rstrip("Z")[:15], "%Y%m%dT%H%M%S")
    if utc:
        return When(stamp, dt.timezone.utc)
    return When(stamp, zone(params.get("TZID")) or default_tz)


def in_zone_of(when, ref):
    """`when` expressed the way `ref` is (date, or wall clock in ref's zone),
    so the two compare directly."""
    if ref.all_day:
        return when.value if when.all_day else when.value.date()
    if when.all_day:
        return dt.datetime.combine(when.value, dt.time())
    if when.tz is None or ref.tz is None or when.tz == ref.tz:
        return when.value
    return when.value.replace(tzinfo=when.tz).astimezone(ref.tz).replace(tzinfo=None)


def parse_duration(text):
    match = re.fullmatch(r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", text.strip())
    if not match:
        return None
    sign = -1 if match.group(1) == "-" else 1
    weeks, days, hours, minutes, seconds = (int(g or 0) for g in match.groups()[1:])
    return sign * dt.timedelta(weeks=weeks, days=days, hours=hours, minutes=minutes, seconds=seconds)


# ── repeating events ──────────────────────────────────────────────────────

def parse_rule(text):
    rule = {}
    for part in text.split(";"):
        if "=" in part:
            key, val = part.split("=", 1)
            rule[key.upper()] = val
    return rule


def month_days(year, month):
    nxt = dt.date(year + (month == 12), month % 12 + 1, 1)
    return (nxt - dt.timedelta(days=1)).day


def integers(text):
    return [int(t) for t in text.split(",") if re.fullmatch(r"\s*[+-]?\d+\s*", t)]


def days_in_month(year, month, rule, default_day):
    """The days of one month a MONTHLY or YEARLY rule picks."""
    last = month_days(year, month)
    by_date = by_weekday = None
    if integers(rule.get("BYMONTHDAY", "")):
        by_date = set()
        for n in integers(rule["BYMONTHDAY"]):
            day = n if n > 0 else last + 1 + n
            if 1 <= day <= last:
                by_date.add(day)
    if re.search(r"(MO|TU|WE|TH|FR|SA|SU)", rule.get("BYDAY", "").upper()):
        by_weekday = set()
        for token in rule["BYDAY"].split(","):
            match = re.fullmatch(r"([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)", token.strip().upper())
            if not match:
                continue
            weekday = WEEKDAYS.index(match.group(2))
            matches = [d for d in range(1, last + 1) if dt.date(year, month, d).weekday() == weekday]
            if match.group(1):
                n = int(match.group(1))
                if -len(matches) <= n <= len(matches) and n != 0:
                    by_weekday.add(matches[n - 1] if n > 0 else matches[n])
            else:
                by_weekday.update(matches)
    if by_date is not None and by_weekday is not None:
        picked = by_date & by_weekday      # e.g. Friday the 13th
    elif by_date is not None:
        picked = by_date
    elif by_weekday is not None:
        picked = by_weekday
    else:
        picked = {default_day} if default_day <= last else set()
    picked = sorted(picked)
    positions = integers(rule.get("BYSETPOS", ""))
    if positions:                          # e.g. the last weekday of the month
        picked = sorted({picked[n - 1] if n > 0 else picked[n]
                         for n in positions if n != 0 and -len(picked) <= n <= len(picked)})
    return picked


def occurrences(start, rule, window_end, window_start=None):
    """Start values (date, or naive wall-clock datetime) of a repeating
    event, from its first through the window's end, COUNT or UNTIL. With a
    window_start, a rule without COUNT skips ahead to it rather than walking
    every occurrence since the event began."""
    base = start.value
    is_dt = isinstance(base, dt.datetime)
    first_day = base.date() if is_dt else base
    clock = base.time() if is_dt else None

    def at(day):
        return dt.datetime.combine(day, clock) if is_dt else day

    freq = rule.get("FREQ", "").upper()
    if freq not in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY"):
        yield base
        return
    interval = max(1, int(rule["INTERVAL"])) if rule.get("INTERVAL", "").isdigit() else 1
    count = int(rule["COUNT"]) if rule.get("COUNT", "").isdigit() else None
    until = None
    if rule.get("UNTIL"):
        try:
            last = parse_when(rule["UNTIL"], {}, start.tz)
            until = in_zone_of(last, start)
            if last.all_day and is_dt:     # a bare date means through that day
                until = dt.datetime.combine(last.value, dt.time.max)
        except ValueError:
            until = None
    months = [m for m in integers(rule.get("BYMONTH", "")) if 1 <= m <= 12]
    weekdays = sorted({WEEKDAYS.index(t.strip().upper()[-2:]) for t in rule.get("BYDAY", "").split(",")
                       if t.strip().upper()[-2:] in WEEKDAYS})
    week_start = WEEKDAYS.index(rule["WKST"].upper()) if rule.get("WKST", "").upper() in WEEKDAYS else 0
    # The first day of the week the event starts in, by the rule's own week.
    week_anchor = first_day - dt.timedelta(days=(first_day.weekday() - week_start) % 7)

    k = 0
    if count is None and window_start is not None:
        from_day = window_start.date() if isinstance(window_start, dt.datetime) else window_start
        gap = (from_day - first_day).days
        if gap > 0:
            month_gap = (from_day.year - first_day.year) * 12 + from_day.month - first_day.month
            k = {"DAILY": gap // interval, "WEEKLY": gap // (7 * interval),
                 "MONTHLY": month_gap // interval, "YEARLY": month_gap // (12 * interval)}[freq]
            k = max(0, k - 1)

    emitted = 0
    for k in range(k, k + MAX_STEPS):
        try:
            if freq == "DAILY":
                period = first_day + dt.timedelta(days=k * interval)
                days = [period] if not weekdays or period.weekday() in weekdays else []
            elif freq == "WEEKLY":
                period = week_anchor + dt.timedelta(weeks=k * interval)
                days = sorted(period + dt.timedelta(days=(w - week_start) % 7)
                              for w in (weekdays or [first_day.weekday()]))
            elif freq == "MONTHLY":
                index = first_day.month - 1 + k * interval
                year, month = first_day.year + index // 12, index % 12 + 1
                period = dt.date(year, month, 1)
                days = [dt.date(year, month, d) for d in days_in_month(year, month, rule, first_day.day)]
            else:
                year = first_day.year + k * interval
                period = dt.date(year, 1, 1)
                days = []
                for month in (months or [first_day.month]):
                    days += [dt.date(year, month, d) for d in days_in_month(year, month, rule, first_day.day)]
                days.sort()
        except (OverflowError, ValueError):   # walked past year 9999
            return
        if at(period) > window_end:
            return
        if months:
            days = [day for day in days if day.month in months]
        for day in days:
            if day < first_day:
                continue
            value = at(day)
            if until is not None and value > until:
                return
            if count is not None and emitted >= count:
                return
            emitted += 1
            yield value
        if days and at(days[-1]) > window_end:
            return


# ── events ────────────────────────────────────────────────────────────────

def read_calendar(text):
    """{name, tz, events: [raw event dicts]} from an .ics feed."""
    name, tzname, events = "", "", []
    current, depth = None, 0
    for line in unfold(text):
        key, params, value = split_property(line)
        if key == "BEGIN":
            if value.upper() == "VEVENT" and current is None:
                current, depth = {}, 0
            elif current is not None:
                depth += 1
            continue
        if key == "END":
            if current is not None:
                if depth == 0 and value.upper() == "VEVENT":
                    events.append(current)
                    current = None
                else:
                    depth -= 1
            continue
        if current is None:
            if key == "X-WR-CALNAME":
                name = unescape(value)
            elif key == "X-WR-TIMEZONE":
                tzname = value.strip()
            continue
        if depth:
            continue  # inside a VALARM
        current.setdefault(key, []).append((params, value))
    return {"name": name, "tz": tzname, "events": events}


def first(raw, key):
    values = raw.get(key)
    return values[0] if values else ({}, "")


def expand_events(calendar, window_start, window_end, local):
    """Each occurrence overlapping [window_start, window_end) as
    {title, start: When, end: When, location}. `local` is the viewer's zone;
    times with no zone of their own are read in the calendar's, else in it."""
    default_tz = zone(calendar.get("tz")) or local
    overrides, masters = {}, []
    for raw in calendar["events"]:
        if "RECURRENCE-ID" in raw:
            overrides.setdefault(first(raw, "UID")[1], []).append(raw)
        else:
            masters.append(raw)

    def build(raw):
        params, value = first(raw, "DTSTART")
        if not value:
            return None
        try:
            start = parse_when(value, params, default_tz)
            end_params, end_value = first(raw, "DTEND")
            end = parse_when(end_value, end_params, default_tz) if end_value else None
        except ValueError:
            return None                    # a date this reader can't make sense of
        length = None
        if end is not None and end.all_day == start.all_day:
            length = end.instant(local) - start.instant(local)
        elif "DURATION" in raw:
            length = parse_duration(first(raw, "DURATION")[1])
        if length is None or length < dt.timedelta(0):
            length = dt.timedelta(days=1) if start.all_day else dt.timedelta(0)
        if start.all_day:                  # whole days only, and at least one
            length = dt.timedelta(days=max(1, length.days))
        return start, length

    def wall(instant, start):
        """An instant the way `start` is written: its date, or the wall clock in its zone."""
        if start.all_day:
            return instant.astimezone(local).date()
        return instant.astimezone(start.tz or local).replace(tzinfo=None)

    def emit(raw, start, length, out):
        if first(raw, "STATUS")[1].upper() == "CANCELLED":
            return
        try:
            begins = start.instant(local)
            ends = begins + length
            end_value = start.value + length
        except (OverflowError, ValueError):
            return
        if ends <= window_start and not (length == dt.timedelta(0) and begins >= window_start):
            return
        if begins >= window_end:
            return
        out.append({
            "title": unescape(first(raw, "SUMMARY")[1]).strip() or "(No title)",
            "start": start,
            "end": When(end_value, start.tz),
            "location": unescape(first(raw, "LOCATION")[1]).strip(),
        })

    def same_kind(when, start):
        """`when` as an occurrence value of an event starting at `start`, or
        None when one is a date and the other a time."""
        if when.all_day != start.all_day:
            return None
        return in_zone_of(when, start)

    out = []
    for raw in masters:
        built = build(raw)
        if not built:
            continue
        start, length = built
        uid = first(raw, "UID")[1]
        rrule = first(raw, "RRULE")[1]
        extra = raw.get("RDATE", [])
        if not rrule and not extra:
            emit(raw, start, length, out)
            continue
        skipped, skipped_days = set(), set()
        exceptions = [(params, token) for params, value in raw.get("EXDATE", []) for token in value.split(",")]
        exceptions += [first(over, "RECURRENCE-ID") for over in overrides.get(uid, [])]
        for params, token in exceptions:
            try:
                when = parse_when(token, params, start.tz)
            except ValueError:
                continue
            if when.all_day and not start.all_day:
                skipped_days.add(when.value)  # a date cancels that day's occurrence
            else:
                skipped.add(in_zone_of(when, start))
        values = []
        try:
            if rrule:
                values = list(occurrences(start, parse_rule(rrule), wall(window_end, start),
                                          wall(window_start - length, start) - dt.timedelta(days=1)))
            else:
                values = [start.value]
        except (ValueError, OverflowError):
            values = [start.value]            # a rule this reader can't follow: show the first
        for params, value in extra:
            for token in value.split(","):
                try:
                    value_when = same_kind(parse_when(token.split("/")[0], params, start.tz), start)
                except ValueError:
                    continue
                if value_when is not None:
                    values.append(value_when)
        for value in sorted(set(values)):
            if value in skipped or (skipped_days and not start.all_day and value.date() in skipped_days):
                continue
            emit(raw, When(value, start.tz), length, out)
    for group in overrides.values():
        for raw in group:
            built = build(raw)
            if built:
                emit(raw, built[0], built[1], out)
    return out


def iso(when, local):
    if when.all_day:
        return when.value.isoformat()
    return when.instant(local).astimezone(local).isoformat()
