#!/usr/bin/env python3
"""Generate the US "reported spam" pack from FTC and FCC complaint data.

The US has no telemarketing number range, so the pack lists exact numbers
that consumers reported at least MIN_REPORTS times over the last WINDOW_DAYS
days, summed across two public-domain sources:

- FTC Do Not Call reported calls (api.ftc.gov, needs a free api.data.gov
  key in FTC_API_KEY; DEMO_KEY works for a smoke test but allows 10
  requests per hour),
- FCC consumer complaints, "caller_id_number" column (opendata.fcc.gov,
  no key).

Reports are unverified and spam often spoofs real numbers, so the pack
identifies ("Spam signalé") instead of blocking: a false positive still
rings.

Usage:
    FTC_API_KEY=... python3 Tools/us-packs/generate_us_complaints_pack.py
    python3 Tools/us-packs/generate_us_complaints_pack.py --fcc-only

FTC pages are cached per day in build/us-complaints-cache/ (gitignored),
so later runs only fetch the days they have not seen. Writes
Packs/prefixes-US.source.json (embedded in the app) and mirrors it to
dist/packs/source/us.complaints.source.json for signing.
"""
import argparse
import collections
import itertools
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta

WINDOW_DAYS = 90
MIN_REPORTS = 2
FTC_URL = "https://api.ftc.gov/v0/dnc-complaints"
FTC_PAGE = 50  # the API ignores larger values
# The API answers 429 to concurrent requests even with quota left.
FTC_WORKERS = 1
MAX_REQUESTS = 15_000
# The FTC answers OVER_RATE_LIMIT well before the 20 000/hour api.data.gov
# quota its headers announce (observed: about 1 000/hour). Stay near 750.
REQUEST_PAUSE = 3.5
FTC_SETTLED_DAYS = 7
# The API stops returning rows past this offset: windows that reach it are
# split in half until each one fits.
FTC_MAX_OFFSET = 10_000
FCC_URL = "https://opendata.fcc.gov/resource/3xyp-aqkj.json"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(ROOT, "build", "us-complaints-cache")


REQUESTS = itertools.count(1)


def get_json(url, retries=10):
    # A run that misreads the API must not burn the key's hourly quota
    # (20 000 requests): stop well before it.
    if next(REQUESTS) > MAX_REQUESTS:
        raise RuntimeError(f"more than {MAX_REQUESTS} requests in this run, stopping")
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=120) as resp:
                data = json.load(resp)
            time.sleep(REQUEST_PAUSE)
            return data
        except (OSError, json.JSONDecodeError) as error:  # URLError, resets, timeouts, cut bodies
            # Once over the limit, every retry counts against it too: wait
            # long enough for the window to slide.
            transient = not isinstance(error, urllib.error.HTTPError) or error.code in (429, 500, 502, 503, 504)
            if transient and attempt < retries - 1:
                wait = 600 if getattr(error, "code", None) == 429 else min(15 * 2 ** attempt, 600)
                print(f"  {error}, waiting {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            raise
    raise RuntimeError(f"giving up on {url}")


def nanp(raw):
    """Return the 10-digit NANP number, or None for anything not dialable."""
    digits = re.sub(r"\D", "", raw or "")
    if len(digits) == 11 and digits[0] == "1":
        digits = digits[1:]
    if len(digits) != 10:
        return None
    area, exchange = digits[:3], digits[3:6]
    if area[0] in "01" or exchange[0] in "01":
        return None
    if area[1:] == "11" or exchange[1:] == "11":  # N11 service codes
        return None
    if exchange == "555" and digits[6:8] == "01":  # reserved for fiction
        return None
    if len(set(digits)) == 1:
        return None
    return digits


def ftc_window(key, start, end):
    """Yield FTC complaints created in [start, end], splitting when needed."""
    rows = []
    offset = 0
    while True:
        query = urllib.parse.urlencode({
            "api_key": key,
            "items_per_page": FTC_PAGE,
            "offset": offset,
            "created_date_from": f'"{start:%Y-%m-%d %H:%M:%S}"',
            "created_date_to": f'"{end:%Y-%m-%d %H:%M:%S}"',
        }, quote_via=urllib.parse.quote)  # the API reads "+" literally, not as a space
        # The API sorts on created-date only, so complaints sharing a second
        # can straddle pages and show up twice: ftc_day deduplicates them.
        # The offset always advances, so this loop cannot spin in place.
        page = get_json(f"{FTC_URL}?{query}").get("data", [])
        rows.extend(page)
        if len(page) < FTC_PAGE:
            return rows
        offset += FTC_PAGE
        if offset >= FTC_MAX_OFFSET:
            middle = start + (end - start) / 2
            return (ftc_window(key, start, middle)
                    + ftc_window(key, middle + timedelta(seconds=1), end))


def ftc_day(key, day):
    """Distinct complaints for one day as {dedup key: number}, cached once settled."""
    path = os.path.join(CACHE, f"ftc-{day.isoformat()}.json")
    if os.path.exists(path):
        with open(path) as fh:
            return json.load(fh)
    start = datetime.combine(day, datetime.min.time())
    # About 20 000 complaints a day at 50 per page and ~2 s per request:
    # fetch the 24 hours in parallel.
    hours = [(start + timedelta(hours=h), start + timedelta(hours=h + 1, seconds=-1)) for h in range(24)]
    with ThreadPoolExecutor(max_workers=FTC_WORKERS) as pool:
        rows = [row for chunk in pool.map(lambda w: ftc_window(key, *w), hours) for row in chunk]
    # Consumers often submit the same call twice: count a number once per
    # identical (call time, consumer area, subject) report.
    reports = {}
    for row in rows:
        a = row["attributes"]
        dedup = "|".join(str(a.get(k)) for k in (
            "company-phone-number", "violation-date", "consumer-area-code", "consumer-state", "subject"))
        reports[dedup] = a.get("company-phone-number")
    # The FTC publishes with a few days of lag: only cache settled days.
    if day < date.today() - timedelta(days=FTC_SETTLED_DAYS):
        os.makedirs(CACHE, exist_ok=True)
        with open(path, "w") as fh:
            json.dump(reports, fh)
    return reports


def ftc_counts(key, first, last):
    counts = collections.Counter()
    day = first
    while day <= last:
        reports = ftc_day(key, day)
        print(f"  FTC {day}: {len(reports)} complaints", file=sys.stderr)
        for raw in reports.values():
            number = nanp(raw)
            if number:
                counts[number] += 1
        day += timedelta(days=1)
    return counts


def fcc_counts(first, last):
    query = urllib.parse.urlencode({
        "$select": "caller_id_number, count(*) as n",
        "$where": (f"caller_id_number IS NOT NULL AND ticket_created >= '{first.isoformat()}' "
                   f"AND ticket_created < '{(last + timedelta(days=1)).isoformat()}'"),
        "$group": "caller_id_number",
        "$limit": 1_000_000,
    })
    counts = collections.Counter()
    for row in get_json(f"{FCC_URL}?{query}"):
        number = nanp(row["caller_id_number"])
        if number:
            counts[number] += int(row["n"])
    print(f"  FCC: {sum(counts.values())} complaints", file=sys.stderr)
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fcc-only", action="store_true", help="skip the FTC source (no API key needed)")
    args = parser.parse_args()
    key = os.environ.get("FTC_API_KEY")
    if not key and not args.fcc_only:
        sys.exit("FTC_API_KEY is not set (free key: https://api.data.gov/signup/), or pass --fcc-only")

    last = date.today() - timedelta(days=1)
    first = last - timedelta(days=WINDOW_DAYS - 1)
    counts = fcc_counts(first, last)
    sources = ["FCC"]
    if not args.fcc_only:
        counts += ftc_counts(key, first, last)
        sources.insert(0, "FTC")

    numbers = sorted(n for n, c in counts.items() if c >= MIN_REPORTS)
    version = date.today().isoformat()
    manifest = {
        "id": "us.complaints",
        "version": version,
        "country": "US",
        "kind": "prefixes",
        "title": "Spam signalé (FTC, FCC)",
        "license": "public domain (FTC Do Not Call reported calls, FCC consumer complaints)",
        "notes": (f"Numéros signalés au moins {MIN_REPORTS} fois du {first.isoformat()} au {last.isoformat()} "
                  f"auprès de la {' et de la '.join(sources)}. Les signalements ne sont pas vérifiés et les "
                  f"spammeurs usurpent souvent de vrais numéros : ces appels sont identifiés, pas bloqués. "
                  f"{len(numbers)} numéros."),
        "enabledByDefault": True,
        "action": "identify",
        "label": "Spam signalé",
        "prefixes": [f"+1{n}*" for n in numbers],
    }
    for folder, name in ((os.path.join(ROOT, "Packs"), "prefixes-US.source.json"),
                         (os.path.join(ROOT, "dist", "packs", "source"), "us.complaints.source.json")):
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, name), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    print(f"us.complaints: {len(numbers)} numbers ({', '.join(sources)})")


if __name__ == "__main__":
    main()
