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

Overseas departments have their own telemarketing tranches (09 475 to
09 479, one per territory) shipped as a separate pack, fr.arcep.dom.

Writes Packs/prefixes-FR.source.json and Packs/prefixes-FR-DOM.source.json
(embedded in the app) and mirrors them to dist/packs/source/ for signing.
"""
import csv
import json
import os
import sys
from datetime import date

PREFIXES = ["0162", "0163", "0164", "0165", "0270", "0271", "0272", "0273",
            "0377", "0378", "0379", "0424", "0425", "0426", "0427", "0428",
            "0568", "0569", "0948", "0949"]
DOM_PREFIX = "0947"
# MAJNUM `Territoire` -> E.164 calling code (libphonenumber: GP/MF/BL 590,
# GF 594, MQ 596, RE/YT 262).
DOM_CALLING_CODES = {
    "Guadeloupe, St Martin et St Barthélemy": "590",
    "Guyane": "594",
    "Martinique": "596",
    "Mayotte": "262",
    "La Réunion - Océan indien": "262",
    "La Réunion": "262",
}
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def blocks(path):
    """Yield (start, end) national numbers (with trunk 0) for allocated blocks."""
    with open(path, encoding="latin-1") as fh:
        for row in csv.DictReader(fh, delimiter=";"):
            start, end = row["Tranche_Debut"], row["Tranche_Fin"]
            if any(start.startswith(p) for p in PREFIXES):
                yield int(start), int(end)


def dom_blocks(path):
    """Group the overseas telemarketing blocks (09 475-479) by E.164 calling code."""
    out = {}
    with open(path, encoding="latin-1") as fh:
        for row in csv.DictReader(fh, delimiter=";"):
            start, end = row["Tranche_Debut"], row["Tranche_Fin"]
            if start.startswith(DOM_PREFIX):
                code = DOM_CALLING_CODES[row["Territoire"]]
                out.setdefault(code, []).append((int(start), int(end)))
    return out


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


def write_pack(manifest, packs_name, dist_name):
    dist_source = os.path.join(ROOT, "dist", "packs", "source")
    for folder, name in ((os.path.join(ROOT, "Packs"), packs_name), (dist_source, dist_name)):
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, name), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, ensure_ascii=False, indent=2)
            fh.write("\n")


def remove_previous():
    for old in os.listdir(os.path.join(ROOT, "Packs")):
        if old.startswith("prefixes-FR") and old.endswith(".source.json"):
            os.remove(os.path.join(ROOT, "Packs", old))
    dist_source = os.path.join(ROOT, "dist", "packs", "source")
    if os.path.isdir(dist_source):
        for old in os.listdir(dist_source):
            if old.startswith("fr.arcep") and old.endswith(".source.json"):
                os.remove(os.path.join(dist_source, old))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    merged = merge(blocks(sys.argv[1]))
    patterns = [p for r in merged for p in to_patterns(*r)]
    total = sum(n for _, n in patterns)

    dom_merged = {code: merge(ranges) for code, ranges in dom_blocks(sys.argv[1]).items()}
    dom_patterns = []
    for code, ranges in sorted(dom_merged.items()):
        for r in ranges:
            for pattern, size in to_patterns(*r):
                # The same number reaches the iPhone as +590 9475... on an
                # overseas SIM and as +33 9475... when a metropolitan network
                # presents it in national format: block both forms.
                dom_patterns.append((pattern.replace("+33", f"+{code}", 1), size))
                dom_patterns.append((pattern, size))
    dom_total = sum(n for _, n in dom_patterns)

    version = date.today().isoformat()
    remove_previous()

    write_pack({
        "id": "fr.arcep",
        "version": version,
        "country": "FR",
        "kind": "prefixes",
        "title": "Démarchage téléphonique (ARCEP)",
        "license": "public domain (ARCEP MAJNUM, régulation publique)",
        "notes": (f"Blocs de numéros attribués aux opérateurs dans les 20 tranches réservées au démarchage "
                  f"téléphonique (décision ARCEP 2022-1583 : 01 62-65, 02 70-73, 03 77-79, 04 24-28, "
                  f"05 68-69, 09 48-49), extraits de MAJNUM.csv le {version}. {total} numéros, {len(patterns)} motifs. "
                  f"L'app répartit les plages sur ses extensions (iOS accepte moins de 2 000 000 de numéros par extension)."),
        "enabledByDefault": True,
        "supersedes": ["fr.arcep.1", "fr.arcep.2", "fr.arcep.3", "fr.arcep.4", "fr.arcep-extra"],
        "prefixes": [p for p, _ in patterns],
    }, "prefixes-FR.source.json", "fr.arcep.source.json")
    print(f"fr.arcep: {total} numbers, {len(patterns)} patterns")

    write_pack({
        "id": "fr.arcep.dom",
        "version": version,
        "country": "FR",
        "kind": "prefixes",
        "title": "Démarchage téléphonique Outre-mer (ARCEP)",
        "license": "public domain (ARCEP MAJNUM, régulation publique)",
        "notes": (f"Blocs de numéros attribués aux opérateurs dans les tranches 09 475 à 09 479 réservées au "
                  f"démarchage téléphonique en Guadeloupe, Saint-Martin, Saint-Barthélemy, Guyane, Martinique, "
                  f"Mayotte et à La Réunion (décision ARCEP 2022-1583), extraits de MAJNUM.csv le {version}. "
                  f"Chaque bloc est présent sous l'indicatif du territoire (+590, +594, +596, +262) et sous +33. "
                  f"{dom_total} numéros, {len(dom_patterns)} motifs."),
        "enabledByDefault": True,
        "prefixes": [p for p, _ in dom_patterns],
    }, "prefixes-FR-DOM.source.json", "fr.arcep.dom.source.json")
    print(f"fr.arcep.dom: {dom_total} numbers, {len(dom_patterns)} patterns")


if __name__ == "__main__":
    main()
