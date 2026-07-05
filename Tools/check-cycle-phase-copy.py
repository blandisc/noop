#!/usr/bin/env python3
"""Copy guard for the Cycle-phase experiment (FER-672).

The feature's risk lives in its words. This checks the shipped strings (English key + every
localization) for the claim frame agreed with /pm and /cso:

  1. Forbidden concepts (fertility, ovulation, contraception, safe days, diagnosis, pregnancy) may
     appear ONLY inside an explicit negation — never as an affirmation.
  2. The phase read-out always carries a hedge ("probably" / "aproximada").
  3. No string implies real-time phase detection (the signal is retrospective, H3).

Run: python3 Tools/check-cycle-phase-copy.py  → exits non-zero on any violation.
"""
import json
import sys
import re

CATALOG = "Cenit/Resources/Localizable.xcstrings"

# The exact user-facing keys this feature adds (kept in sync with CyclePhaseView.swift / AjustesView).
FEATURE_KEYS = {
    "EXPERIMENT", "Cycle phase",
    "This is a self-knowledge tool: it looks for a pattern in your own body's temperature while you sleep. Before turning it on, read calmly what it does and what it doesn't.",
    "Everything is computed on your iPhone and stays here. You can turn this experiment off whenever you like; nothing is lost. This is not medical advice.",
    "I understand this is a rough estimate to know myself better, not a contraceptive method or a medical tool.",
    "Turn on experiment", "Not now", "What it does",
    "With several weeks of nights, it learns the rhythm of your temperature and estimates which phase of your cycle you're probably in: follicular or luteal.",
    "The reading is approximate and always comes with a «probably». Temperature confirms the phase one to three days after it changes, so this looks backward, not at this moment.",
    "What it doesn't do",
    "It is not a contraceptive method.",
    "It doesn't predict your fertile days or your ovulation.",
    "It doesn't diagnose pregnancy or any health condition.",
    "It doesn't tell you which day your next period starts.",
    "What is this?", "Turn off experiment",
    "I'll stop estimating your phase. Your temperature data and everything else stay the same.",
    "Turn off", "NO BAND SIGNAL", "This reading needs your band.",
    "The phase is estimated from the temperature your band measures while you sleep. When you sync nights with the band again, I'll pick the reading back up.",
    "NO CLEAR PATTERN", "I don't see a clear pattern in your data.",
    "Your night-time temperature doesn't show a rhythm I can read with confidence. This is common and doesn't mean anything is wrong with you or your band. I'll keep watching in case it appears.",
    "LEARNING", "I'm learning your pattern.",
    "I need several weeks of nights with your band on to read the rhythm of your temperature. Still watching.",
    "%lld of ~%lld nights", "The more nights you sleep with the band, the sooner I see it.",
    "You're probably in the luteal phase.", "You're probably in the follicular phase.",
    "Low confidence · it's a faint signal.", "Moderate confidence.", "Solid confidence for an estimate.",
    "Temperature confirms the phase one to three days after the change, so this reflects your recent nights, not this instant.",
    "Based on your band's night-time temperature.", "APPROXIMATE READING",
    "%lld of ~%lld nights learned",
    "Experiments", "Experiment · on", "Experiment · off",
}

FORBIDDEN = ["fertil", "fértil", "ovulac", "ovulat", "anticoncep", "contracept",
             "día seguro", "dia seguro", "safe day", "diagnos", "diagnóst",
             "embaraz", "pregnan"]
NEGATION = ["no ", "not ", "n't", "nunca", " ni ", "doesn", "don't", "isn't",
            "it is not", "no es", "no te", "no predice", "no diagnostica"]
HEDGE = ["probabl", "aproximad", "approximate"]
REALTIME = ["tiempo real", "real time", "real-time", "cambiando ahora", "changing now",
            "right now", "en este momento"]


def values_for(entry):
    out = []
    for loc in entry.get("localizations", {}).values():
        v = loc.get("stringUnit", {}).get("value")
        if v:
            out.append(v)
    return out


def main():
    with open(CATALOG, encoding="utf-8") as f:
        cat = json.load(f)
    strings = cat["strings"]

    errors = []
    for key in sorted(FEATURE_KEYS):
        if key not in strings:
            errors.append(f"MISSING key in catalog: {key!r}")
            continue
        texts = [key] + values_for(strings[key])   # English key + all localizations
        for t in texts:
            low = t.lower()
            for term in FORBIDDEN:
                if term in low and not any(n in low for n in NEGATION):
                    errors.append(f"forbidden term {term!r} NOT negated in: {t!r}")
            for term in REALTIME:
                if term in low:
                    errors.append(f"real-time phrasing {term!r} in: {t!r}")

    # The two phase read-outs must always hedge.
    for key in ["You're probably in the luteal phase.", "You're probably in the follicular phase."]:
        texts = [key] + values_for(strings.get(key, {}))
        for t in texts:
            if not any(h in t.lower() for h in HEDGE):
                errors.append(f"phase read-out missing a hedge: {t!r}")

    if errors:
        print("Cycle-phase copy guard FAILED:")
        for e in errors:
            print("  -", e)
        return 1
    print(f"Cycle-phase copy guard OK — {len(FEATURE_KEYS)} keys, claim frame intact.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
