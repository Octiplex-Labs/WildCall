#!/usr/bin/env python3
"""Generate the embedded French telemarketing packs from ARCEP open data.

ARCEP decision 2022-1583 reserves 20 prefixes (01 62-65, 02 70-73,
03 77-79, 04 24-28, 05 68-69, 09 48-49) for telemarketing since 1 January
2023: 20 million numbers in theory. Only the blocks ARCEP has actually
allocated to operators (MAJNUM.csv) can originate calls, so the pack
carries those: about 7.3 M numbers. iOS accepts fewer than 2 million
entries per Call Directory extension (measured 2026-09-01), which the app
handles by spreading the ranges across its four extensions.

Usage:
    curl -sL https://extranet.arcep.fr/uploads/MAJNUM.csv -o /tmp/MAJNUM.csv
    python3 Tools/arcep-packs/generate_arcep_packs.py /tmp/MAJNUM.csv

Writes Packs/prefixes-FR.source.json (embedded in the app) and mirrors it
to dist/packs/source/fr.arcep.source.json for signing.
"""
import csv
import json
import os
import sys
from datetime import date

PREFIXES = ["0162", "0163", "0164", "0165", "0270", "0271", "0272", "0273",
            "0377", "0378", "0379", "0424", "0425", "0426", "0427", "0428",
            "0568", "0569", "0948", "0949"]
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def blocks(path):
    """Yield (start, end) national numbers (with trunk 0) for allocated blocks."""
    with open(path, encoding="latin-1") as fh:
        for row in csv.DictReader(fh, delimiter=";"):
            start, end = row["Tranche_Debut"], row["Tranche_Fin"]
            if any(start.startswith(p) for p in PREFIXES):
                yield int(start), int(end)


def merge(ranges):
    out = []
    for start, end in sorted(ranges):
        if out and start <= out[-1][1] + 1:
            out[-1][1] = max(out[-1][1], end)
        else:
            out.append([start, end])
    return out


def to_patterns(start, end):
    """Split [start, end] into 10^k-aligned blocks and emit `+33<digits>*` patterns."""
    patterns = []
    cursor = start
    while cursor <= end:
        size = 1
        while cursor % (size * 10) == 0 and cursor + size * 10 - 1 <= end:
            size *= 10
        national = str(cursor).zfill(10)[1:]  # drop trunk 0 : 0162040000 -> 162040000
        width = len(str(size)) - 1          # 1000 -> 3 wildcard digits
        fixed = national[:len(national) - width]
        patterns.append((f"+33{fixed}*", size))
        cursor += size
    return patterns


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    merged = merge(blocks(sys.argv[1]))
    patterns = [p for r in merged for p in to_patterns(*r)]
    total = sum(n for _, n in patterns)

    version = date.today().isoformat()
    for old in os.listdir(os.path.join(ROOT, "Packs")):
        if old.startswith("prefixes-FR") and old.endswith(".source.json"):
            os.remove(os.path.join(ROOT, "Packs", old))
    dist_source = os.path.join(ROOT, "dist", "packs", "source")
    if os.path.isdir(dist_source):
        for old in os.listdir(dist_source):
            if old.startswith("fr.arcep") and old.endswith(".source.json"):
                os.remove(os.path.join(dist_source, old))

    pats = [p for p, _ in patterns]
    manifest = {
        "id": "fr.arcep",
        "version": version,
        "country": "FR",
        "kind": "prefixes",
        "title": "Démarchage téléphonique (ARCEP)",
        "license": "public domain (ARCEP MAJNUM, régulation publique)",
        "notes": (f"Blocs de numéros attribués aux opérateurs dans les 20 tranches réservées au démarchage "
                  f"téléphonique (décision ARCEP 2022-1583 : 01 62-65, 02 70-73, 03 77-79, 04 24-28, "
                  f"05 68-69, 09 48-49), extraits de MAJNUM.csv le {version}. {total} numéros, {len(pats)} motifs. "
                  f"L'app répartit les plages sur ses extensions (iOS accepte moins de 2 000 000 de numéros par extension)."),
        "enabledByDefault": True,
        "supersedes": ["fr.arcep.1", "fr.arcep.2", "fr.arcep.3", "fr.arcep.4", "fr.arcep-extra"],
        "prefixes": pats,
    }
    for folder, name in ((os.path.join(ROOT, "Packs"), "prefixes-FR.source.json"),
                         (dist_source, "fr.arcep.source.json")):
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, name), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    print(f"fr.arcep: {total} numbers, {len(pats)} patterns")


if __name__ == "__main__":
    main()
