"""Read iCalendar (.ics) feeds for omabar-gcal, with only the standard library.

Covers what calendar feeds such as Google's "secret address in iCal format"
contain: all-day and timed events, time zones by IANA name, durations, and
repeating events (RRULE with FREQ, INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY,
BYMONTH), with EXDATE exceptions and RECURRENCE-ID overrides.
"""
import datetime as dt
import re

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover - Python < 3.9
    ZoneInfo = None

WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
MAX_STEPS = 5000


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


def days_in_month(year, month, rule, default_day):
    """The days of one month a MONTHLY or YEARLY rule picks."""
    last = month_days(year, month)
    picked = set()
    if "BYMONTHDAY" in rule:
        for token in rule["BYMONTHDAY"].split(","):
            n = int(token)
            day = n if n > 0 else last + 1 + n
            if 1 <= day <= last:
                picked.add(day)
    elif "BYDAY" in rule:
        for token in rule["BYDAY"].split(","):
            match = re.fullmatch(r"([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)", token.strip())
            if not match:
                continue
            weekday = WEEKDAYS.index(match.group(2))
            matches = [d for d in range(1, last + 1) if dt.date(year, month, d).weekday() == weekday]
            if match.group(1):
                n = int(match.group(1))
                if -len(matches) <= n <= len(matches) and n != 0:
                    picked.add(matches[n - 1] if n > 0 else matches[n])
            else:
                picked.update(matches)
    elif default_day <= last:
        picked.add(default_day)
    return sorted(picked)


def occurrences(start, rule, window_end):
    """Start values (date, or naive wall-clock datetime) of a repeating
    event, from its first through the window's end, COUNT or UNTIL."""
    base = start.value
    is_dt = isinstance(base, dt.datetime)
    first_day = base.date() if is_dt else base
    clock = base.time() if is_dt else None

    def at(day):
        return dt.datetime.combine(day, clock) if is_dt else day

    freq = rule.get("FREQ", "").upper()
    interval = max(1, int(rule.get("INTERVAL", "1") or 1))
    count = int(rule["COUNT"]) if rule.get("COUNT", "").isdigit() else None
    until = None
    if rule.get("UNTIL"):
        try:
            until = in_zone_of(parse_when(rule["UNTIL"], {}, start.tz), start)
        except ValueError:
            until = None
    months = [int(m) for m in rule.get("BYMONTH", "").split(",") if m.strip().isdigit()]

    emitted = 0
    for k in range(MAX_STEPS):
        if freq == "DAILY":
            days = [first_day + dt.timedelta(days=k * interval)]
            if months and days[0].month not in months:
                days = []
        elif freq == "WEEKLY":
            monday = first_day - dt.timedelta(days=first_day.weekday()) + dt.timedelta(weeks=k * interval)
            wanted = [WEEKDAYS.index(t.strip()[-2:]) for t in rule.get("BYDAY", "").split(",") if t.strip()[-2:] in WEEKDAYS]
            days = sorted(monday + dt.timedelta(days=w) for w in (wanted or [first_day.weekday()]))
        elif freq == "MONTHLY":
            index = first_day.month - 1 + k * interval
            year, month = first_day.year + index // 12, index % 12 + 1
            days = [] if months and month not in months else \
                [dt.date(year, month, d) for d in days_in_month(year, month, rule, first_day.day)]
        elif freq == "YEARLY":
            year = first_day.year + k * interval
            days = []
            for month in (months or [first_day.month]):
                if "BYDAY" in rule or "BYMONTHDAY" in rule or month == first_day.month:
                    days += [dt.date(year, month, d) for d in days_in_month(year, month, rule, first_day.day)]
            days.sort()
        else:
            yield base
            return
        if not days and k * interval > 0 and freq == "DAILY":
            continue
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
        if not days and freq in ("MONTHLY", "YEARLY", "WEEKLY"):
            # Keep walking: a rule can skip whole periods (e.g. 31st of short months).
            last_day = first_day
            if freq == "YEARLY":
                last_day = dt.date(first_day.year + k * interval, 12, 31)
            if at(last_day) > window_end and freq == "YEARLY":
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
    {title, start: When, end: When, location}."""
    default_tz = zone(calendar.get("tz"))
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
        start = parse_when(value, params, default_tz)
        end_params, end_value = first(raw, "DTEND")
        if end_value:
            end = parse_when(end_value, end_params, default_tz)
            length = end.instant(local) - start.instant(local)
        else:
            length = parse_duration(first(raw, "DURATION")[1]) if "DURATION" in raw else None
            if length is None:
                length = dt.timedelta(days=1) if start.all_day else dt.timedelta(0)
        return start, length

    def emit(raw, start, length, out):
        if first(raw, "STATUS")[1].upper() == "CANCELLED":
            return
        begins = start.instant(local)
        ends = begins + length
        if ends <= window_start and not (length == dt.timedelta(0) and begins >= window_start):
            return
        if begins >= window_end:
            return
        end_when = When(start.value + length, start.tz) if not start.all_day else When(start.value + length)
        out.append({
            "title": unescape(first(raw, "SUMMARY")[1]) or "(No title)",
            "start": start,
            "end": end_when,
            "location": unescape(first(raw, "LOCATION")[1]),
        })

    out = []
    for raw in masters:
        built = build(raw)
        if not built:
            continue
        start, length = built
        uid = first(raw, "UID")[1]
        rrule = first(raw, "RRULE")[1]
        if not rrule:
            emit(raw, start, length, out)
            continue
        skipped = set()
        for params, value in raw.get("EXDATE", []):
            for token in value.split(","):
                try:
                    skipped.add(in_zone_of(parse_when(token, params, start.tz), start))
                except ValueError:
                    pass
        for over in overrides.get(uid, []):
            params, value = first(over, "RECURRENCE-ID")
            try:
                skipped.add(in_zone_of(parse_when(value, params, start.tz), start))
            except ValueError:
                pass
        limit = in_zone_of(When(window_end.replace(tzinfo=None) if start.tz is None else
                                window_end.astimezone(start.tz).replace(tzinfo=None), start.tz), start) \
            if not start.all_day else window_end.date()
        for value in occurrences(start, parse_rule(rrule), limit):
            if value in skipped:
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
