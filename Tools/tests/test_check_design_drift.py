#!/usr/bin/env python3
"""Tests for Tools/check-design-drift.py (FER-263, épico FER-261).

Run:  python3 -m unittest Tools/tests/test_check_design_drift.py  (from the repo root)
"""
import importlib.util
import json
import os
import sys
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SCRIPT = os.path.join(_HERE, "..", "check-design-drift.py")
_spec = importlib.util.spec_from_file_location("check_design_drift", _SCRIPT)
drift = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(drift)


def _swift(tmp, rel, lines):
    path = os.path.join(tmp, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    return path


class MergeWriteBaseline(unittest.TestCase):
    """--write-baseline must merge per-rule, never clobber the keys of rules that did not run."""

    def test_rerecording_one_rule_preserves_the_others(self):
        with tempfile.TemporaryDirectory() as tmp:
            baseline = os.path.join(tmp, "baseline.json")
            original = {
                "no-spacing-literal": {"Cenit/Screens/A.swift": 3},
                "no-legacy-api": {"Cenit/Screens/B.swift": 2},
            }
            with open(baseline, "w", encoding="utf-8") as fh:
                json.dump(original, fh)
            src = _swift(tmp, "Cenit/Screens/C.swift", ["VStack(spacing: 14) {}"])
            rc = drift.main(["--rules", "no-spacing-literal", "--write-baseline", baseline, src])
            self.assertEqual(rc, 0)
            merged = json.load(open(baseline, encoding="utf-8"))
            self.assertEqual(merged["no-legacy-api"], original["no-legacy-api"],
                             "keys of rules that did not run must survive byte-for-byte")
            self.assertEqual(list(merged["no-spacing-literal"].values()), [1])

    def test_rule_that_ran_clean_drops_its_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            baseline = os.path.join(tmp, "baseline.json")
            with open(baseline, "w", encoding="utf-8") as fh:
                json.dump({"no-spacing-literal": {"Cenit/Screens/A.swift": 3}}, fh)
            src = _swift(tmp, "Cenit/Screens/Clean.swift", ["Text(\"hola\")"])
            drift.main(["--rules", "no-spacing-literal", "--write-baseline", baseline, src])
            merged = json.load(open(baseline, encoding="utf-8"))
            self.assertNotIn("no-spacing-literal", merged)


class LegacyApiRule(unittest.TestCase):
    def test_matches_retired_symbols_and_modifier(self):
        for line in [
            "let theme = InstrumentoTheme.base",
            "PaperMenu { … }",
            "view.instrumentoTheme(.dia)",
            "StrandPalette.ink",
        ]:
            self.assertTrue(drift.RE_LEGACY_API.search(line), line)

    def test_does_not_match_longer_identifiers_or_liquid(self):
        for line in [
            "InstrumentoThemeEngine.shared",   # \b guard: longer identifier is a different symbol
            "LiquidColor.hierro",
            "liquidGlass(.superficieSolida)",
        ]:
            self.assertFalse(drift.RE_LEGACY_API.search(line), line)

    def test_design_package_definitions_are_not_hits(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Packages/StrandDesign/Sources/StrandDesign/Instrumento.swift",
                         ["public struct InstrumentoTheme {}"])
            hits = drift.check([src], ["no-legacy-api"])
            self.assertEqual(hits, [])

    def test_app_call_site_is_a_hit(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", ["let t = InstrumentoTheme.base"])
            hits = drift.check([src], ["no-legacy-api"])
            self.assertEqual(len(hits), 1)


class TokenExemptPseudoRule(unittest.TestCase):
    def test_counts_both_annotation_forms_and_silences_other_rules(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", [
                ".padding(14) // token-exempt: geometría de dato",
                ".padding(15) // token-exempt(dato): barras del hipnograma",
                ".padding(16)",
            ])
            hits = drift.check([src], ["no-spacing-literal", "token-exempt"])
            rules = sorted(r for _p, _i, r, _s in hits)
            self.assertEqual(rules, ["no-spacing-literal", "token-exempt", "token-exempt"])

    def test_new_exemption_over_budget_fails_with_baseline(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", [
                "Text(\"a\") // token-exempt: uno",
                "Text(\"b\") // token-exempt: dos",
            ])
            baseline = {"token-exempt": {drift._key(src): 1}}
            hits = drift.check([src], ["token-exempt"])
            over, _stale = drift.apply_baseline(hits, baseline)
            self.assertEqual(len(over), 1, "the second (new) exemption must be over budget")


class Ratchet(unittest.TestCase):
    def test_within_budget_passes_and_below_budget_reports_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", ["VStack(spacing: 9) {}"])
            baseline = {"no-spacing-literal": {drift._key(src): 2}}
            hits = drift.check([src], ["no-spacing-literal"])
            over, stale = drift.apply_baseline(hits, baseline)
            self.assertEqual(over, [])
            self.assertEqual(stale, [("no-spacing-literal", drift._key(src), 1)])


if __name__ == "__main__":
    unittest.main()
