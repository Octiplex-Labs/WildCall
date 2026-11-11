#!/usr/bin/env python3
"""Generate the Spanish telemarketing pack (es.cnmc).

Since 17 October 2026 Spain reserves the whole 400 range for commercial
calls (Ley 10/2025 art. 16.3, numbering plan amended by BOE-A-2026-8409).
Spanish national numbers have 9 digits, so the range is 400 000 000 to
400 999 999: one pattern, 1 000 000 numbers, under the 1 999 999 entries
iOS accepts per Call Directory extension. The CNMC numbering registry
(numeracionyoperadores.cnmc.es) lists no allocated 400 block yet, so the
pack carries the full range instead of allocated blocks like fr.arcep.

Usage:
    python3 Tools/cnmc-packs/generate_cnmc_pack.py [YYYY-MM-DD]

The optional argument sets the pack version (defaults to today). Writes
Packs/prefixes-ES.source.json (embedded in the app) and mirrors it to
dist/packs/source/es.cnmc.source.json for signing.
"""
import json
import os
import sys
from datetime import date

PREFIXES = ["400"]
NATIONAL_LENGTH = 9
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    if len(sys.argv) > 2:
        sys.exit(__doc__)
    version = sys.argv[1] if len(sys.argv) == 2 else date.today().isoformat()
    date.fromisoformat(version)  # versions are ISO dates, compared lexically by PackBootstrap

    pats = [f"+34{p}*" for p in PREFIXES]
    total = sum(10 ** (NATIONAL_LENGTH - len(p)) for p in PREFIXES)
    manifest = {
        "id": "es.cnmc",
        "version": version,
        "country": "ES",
        "kind": "prefixes",
        "title": "Démarchage téléphonique en Espagne (CNMC)",
        "license": "public domain (plan national de numérotation espagnol, BOE-A-2026-8409)",
        "notes": (f"Tranche 400 réservée aux appels commerciaux en Espagne depuis le 17 octobre 2026 "
                  f"(Ley 10/2025, article 16.3, BOE-A-2026-8409). Le registre de la CNMC ne publie encore "
                  f"aucun bloc attribué : le pack couvre toute la tranche. {total} numéros, {len(pats)} motif."),
        "enabledByDefault": True,
        "prefixes": pats,
    }
    dist_source = os.path.join(ROOT, "dist", "packs", "source")
    for folder, name in ((os.path.join(ROOT, "Packs"), "prefixes-ES.source.json"),
                         (dist_source, "es.cnmc.source.json")):
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, name), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    print(f"es.cnmc: {total} numbers, {len(pats)} patterns")


if __name__ == "__main__":
    main()
