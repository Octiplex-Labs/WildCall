#!/usr/bin/env python3
"""Generate the embedded French telemarketing packs from ARCEP open data.

ARCEP decision 2022-1583 reserves 20 prefixes (01 62-65, 02 70-73,
03 77-79, 04 24-28, 05 68-69, 09 48-49) for telemarketing since 1 January
2023: 20 million numbers in theory. iOS accepts fewer than 2 million
entries per Call Directory extension (measured 2026-09-01: 1 999 999 ok,
2 000 000 rejected), so we only keep the blocks ARCEP has actually
allocated to operators (MAJNUM.csv), and we split them into packs that
each fit under the ceiling.

Usage:
    curl -sL https://extranet.arcep.fr/uploads/MAJNUM.csv -o /tmp/MAJNUM.csv
    python3 Tools/arcep-packs/generate_arcep_packs.py /tmp/MAJNUM.csv

Writes Packs/prefixes-FR-arcep-<n>.source.json (embedded in the app) and
mirrors them to dist/packs/source/ for signing.
"""
import csv
import json
import os
import sys
from datetime import date

PREFIXES = ["0162", "0163", "0164", "0165", "0270", "0271", "0272", "0273",
            "0377", "0378", "0379", "0424", "0425", "0426", "0427", "0428",
            "0568", "0569", "0948", "0949"]
PACK_BUDGET = 1_900_000   # leaves headroom under the 1 999 999 ceiling for user rules
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

    packs, current, count = [], [], 0
    for pattern, n in patterns:
        if count + n > PACK_BUDGET and current:
            packs.append((current, count))
            current, count = [], 0
        current.append(pattern)
        count += n
    if current:
        packs.append((current, count))

    version = date.today().isoformat()
    for old in os.listdir(os.path.join(ROOT, "Packs")):
        if old.startswith("prefixes-FR") and old.endswith(".source.json"):
            os.remove(os.path.join(ROOT, "Packs", old))

    for index, (pats, n) in enumerate(packs, start=1):
        first, last = pats[0][3:7], pats[-1][3:7]
        manifest = {
            "id": f"fr.arcep.{index}",
            "version": version,
            "country": "FR",
            "kind": "prefixes",
            "title": f"Démarchage FR : blocs ARCEP {index}/{len(packs)} (0{first[:1]} {first[1:3]} à 0{last[:1]} {last[1:3]})",
            "license": "public domain (ARCEP MAJNUM, régulation publique)",
            "notes": (f"Blocs de numéros attribués aux opérateurs dans les tranches réservées au démarchage "
                      f"(décision ARCEP 2022-1583), extraits de MAJNUM.csv le {version}. "
                      f"{n} numéros, {len(pats)} motifs. iOS accepte moins de 2 000 000 de numéros par extension : "
                      f"seul le premier pack est activé par défaut."),
            "enabledByDefault": index == 1,
            "prefixes": pats,
        }
        if index == 1:
            manifest["supersedes"] = ["fr.arcep", "fr.arcep-extra"]
        for folder, name in ((os.path.join(ROOT, "Packs"), f"prefixes-FR-arcep-{index}.source.json"),
                             (os.path.join(ROOT, "dist", "packs", "source"), f"fr.arcep.{index}.source.json")):
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, name), "w", encoding="utf-8") as fh:
                json.dump(manifest, fh, ensure_ascii=False, indent=2)
                fh.write("\n")
        print(f"fr.arcep.{index}: {n:>9} numbers, {len(pats):>4} patterns")
    print(f"total {total} numbers in {len(packs)} packs")


if __name__ == "__main__":
    main()
