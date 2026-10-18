#!/usr/bin/env python3
"""Generate the German "reported abuse" pack from the Bundesnetzagentur.

Germany has no telemarketing number range. The Bundesnetzagentur publishes
every number it acted against for abuse (spam calls and SMS, ping calls,
dialers, fake support pop-ups, caller ID spoofing...) as one PDF per year,
the "Maßnahmenliste Ärger mit Rufnummern". Most numbers are shut down
after the decision, but scammers keep spoofing them, so the pack
identifies ("Spam signalé") rather than blocks.

German numbers have no fixed length: the pack lists exact numbers
(`+49...` without `*`), which the app loads as single-number rules.

Needs `pdftotext` (poppler: `brew install poppler`).

Usage:
    python3 Tools/bnetza-packs/generate_bnetza_pack.py

Writes Packs/prefixes-DE.source.json (embedded in the app) and mirrors it
to dist/packs/source/de.bnetza.source.json for signing.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from datetime import date

BASE = ("https://www.bundesnetzagentur.de/SharedDocs/Downloads/DE/Sachgebiete/Telekommunikation/"
        "Verbraucher/Rufnummernmissbrauch/Massnahmenlisten/")
# Each PDF covers its year; the latest one also carries the current year.
# Older lists name numbers that have long been reassigned.
LISTS = {
    "2023": "Ma%C3%9Fnahmenliste2023.pdf",
    "2024": "Ma%C3%9Fnahmenliste2024.pdf",
    "2025": "Ma%C3%9Fnahmenliste2025.pdf",
}
MAX_RANGE = 10_000  # a larger "von ... bis ..." is a parsing error, not a decision
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# "03020200-400 bis 499": shared stem, then first and last suffix.
STEM_RANGE = re.compile(r"(?<![\d.])(0\d{4,13})-(\d{1,6}) bis (\d{1,6})(?![\d.])")
# "069870034500 bis 069870034509": two full numbers.
FULL_RANGE = re.compile(r"(?<![\d.\-])(0\d{6,15}) bis (0\d{6,15})(?![\d.\-])")
NUMBER = re.compile(r"(?<![\d.\-])(0\d{6,15})(?![\d.\-])")


def text_of(year, filename):
    url = f"{BASE}{filename}?__blob=publicationFile"
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=120) as resp, tempfile.TemporaryDirectory() as tmp:
        pdf = os.path.join(tmp, f"{year}.pdf")
        with open(pdf, "wb") as fh:
            fh.write(resp.read())
        out = subprocess.run(["pdftotext", pdf, "-"], check=True, capture_output=True, text=True)
    # Lists wrap across lines and columns: collapse whitespace so a range
    # split over two lines still reads "A bis B".
    return re.sub(r"\s+", " ", out.stdout)


def e164(national):
    """German national format to E.164: 0049/0 -> +49, 00<cc> -> +<cc>."""
    if national.startswith("00"):
        number = "+" + national[2:]
    else:
        number = "+49" + national[1:]
    return number if 8 <= len(number) - 1 <= 15 else None


def numbers_in(text):
    found = set()
    for stem, first, last in STEM_RANGE.findall(text):
        if len(first) == len(last) and 0 <= int(last) - int(first) < MAX_RANGE:
            found.update(f"{stem}{n:0{len(first)}d}" for n in range(int(first), int(last) + 1))
    text = STEM_RANGE.sub(" ", text)
    for first, last in FULL_RANGE.findall(text):
        if len(first) == len(last) and 0 <= int(last) - int(first) < MAX_RANGE:
            found.update(f"{n:0{len(first)}d}" for n in range(int(first), int(last) + 1))
    text = FULL_RANGE.sub(" ", text)
    found.update(NUMBER.findall(text))
    return found


def main():
    national = set()
    for year, filename in LISTS.items():
        year_numbers = numbers_in(text_of(year, filename))
        print(f"  {year}: {len(year_numbers)} numbers", file=sys.stderr)
        national |= year_numbers
    numbers = sorted({n for n in map(e164, national) if n})

    version = date.today().isoformat()
    manifest = {
        "id": "de.bnetza",
        "version": version,
        "country": "DE",
        "kind": "prefixes",
        "title": "Abus signalés (Bundesnetzagentur)",
        "license": "public domain (Bundesnetzagentur, Maßnahmenliste Ärger mit Rufnummern)",
        "notes": (f"Numéros visés par une mesure de la Bundesnetzagentur pour abus (appels et SMS de spam, "
                  f"ping calls, dialers, faux supports, usurpation) en {min(LISTS)}-{version[:4]}, extraits le "
                  f"{version}. La plupart sont coupés mais restent usurpés : ces appels sont identifiés, "
                  f"pas bloqués. {len(numbers)} numéros."),
        "enabledByDefault": True,
        "action": "identify",
        "label": "Spam signalé",
        "prefixes": numbers,
    }
    for folder, name in ((os.path.join(ROOT, "Packs"), "prefixes-DE.source.json"),
                         (os.path.join(ROOT, "dist", "packs", "source"), "de.bnetza.source.json")):
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, name), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    print(f"de.bnetza: {len(numbers)} numbers")


if __name__ == "__main__":
    main()
