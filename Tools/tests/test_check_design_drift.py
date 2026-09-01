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
            "PaperMenuItem(r.name, systemImage: nil) { }",   # el tipo que la app SÍ usa (review Grok r1)
            ".paperMenu(isPresented: $show, items: items)",
            "InstrumentoSectionBand(\"By sport\")",
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

    def test_comment_line_is_not_a_hit(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", [
                "// let t = InstrumentoTheme.base  (histórico, solo comentario)",
                "/* PaperMenu también vivía aquí */",
            ])
            self.assertEqual(drift.check([src], ["no-legacy-api"]), [])

    def test_file_outside_scanned_roots_is_not_walked(self):
        with tempfile.TemporaryDirectory() as tmp:
            _swift(tmp, "CenitWidgets/RestLiveActivity.swift", ["let t = InstrumentoTheme.base"])
            gated = os.path.join(tmp, "Cenit", "Screens")
            os.makedirs(gated, exist_ok=True)
            self.assertEqual(drift.check([gated], ["no-legacy-api"]), [],
                             "un archivo fuera de las raíces pasadas no se escanea (carve-out FER-219)")


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


class WidgetWatchCarveOut(unittest.TestCase):
    """FER-219: CenitWidgets/CenitWatch quedan fuera de las dos reglas nuevas EN check(), no solo
    por invocación — una corrida con raíces default no debe pintarlos de rojo."""

    def test_legacy_and_exempt_skip_widget_and_watch_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            w = _swift(tmp, "CenitWidgets/RestLiveActivity.swift",
                       ["let t = InstrumentoTheme.base", ".padding(8) // token-exempt: isla fija"])
            k = _swift(tmp, "CenitWatch/WatchFace.swift", ["let t = InstrumentoTheme.base"])
            self.assertEqual(drift.check([w, k], ["no-legacy-api", "token-exempt"]), [])


class MergeWriteRobustness(unittest.TestCase):
    def test_corrupt_json_is_refused_not_clobbered(self):
        with tempfile.TemporaryDirectory() as tmp:
            baseline = os.path.join(tmp, "baseline.json")
            with open(baseline, "w", encoding="utf-8") as fh:
                fh.write("{not json <<<<<<< HEAD")
            src = _swift(tmp, "Cenit/Screens/X.swift", ["VStack(spacing: 14) {}"])
            rc = drift.main(["--rules", "no-spacing-literal", "--write-baseline", baseline, src])
            self.assertEqual(rc, 2)
            self.assertEqual(open(baseline, encoding="utf-8").read(), "{not json <<<<<<< HEAD",
                             "un JSON corrupto se rechaza, jamás se reescribe")

    def test_partial_scan_preserves_unwalked_files_of_the_same_rule(self):
        # Como en el uso real: cwd = raíz del repo, rutas relativas (las claves del JSON lo son).
        with tempfile.TemporaryDirectory() as tmp:
            cwd = os.getcwd()
            try:
                os.chdir(tmp)
                _swift(tmp, "Cenit/Screens/A.swift", ["VStack(spacing: 14) {}"])
                _swift(tmp, "Cenit/Screens/B.swift", ["VStack(spacing: 9) {}"])
                drift.main(["--rules", "no-spacing-literal", "--write-baseline", "baseline.json",
                            "Cenit/Screens/A.swift", "Cenit/Screens/B.swift"])
                drift.main(["--rules", "no-spacing-literal", "--write-baseline", "baseline.json",
                            "Cenit/Screens/A.swift"])
                merged = json.load(open("baseline.json", encoding="utf-8"))
                self.assertIn("Cenit/Screens/B.swift", merged["no-spacing-literal"],
                              "un scan parcial no puede tirar el presupuesto de archivos no caminados")
            finally:
                os.chdir(cwd)

    def test_deleted_file_drops_out_on_rerecord(self):
        with tempfile.TemporaryDirectory() as tmp:
            cwd = os.getcwd()
            try:
                os.chdir(tmp)
                _swift(tmp, "Cenit/Screens/A.swift", ["VStack(spacing: 14) {}"])
                _swift(tmp, "Cenit/Screens/Gone.swift", ["VStack(spacing: 9) {}"])
                drift.main(["--rules", "no-spacing-literal", "--write-baseline", "baseline.json",
                            "Cenit/Screens/A.swift", "Cenit/Screens/Gone.swift"])
                os.remove("Cenit/Screens/Gone.swift")
                drift.main(["--rules", "no-spacing-literal", "--write-baseline", "baseline.json",
                            "Cenit/Screens/A.swift"])
                merged = json.load(open("baseline.json", encoding="utf-8"))
                self.assertNotIn("Cenit/Screens/Gone.swift", merged.get("no-spacing-literal", {}))
            finally:
                os.chdir(cwd)


class Ratchet(unittest.TestCase):
    def test_stale_notes_only_for_walked_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", ["Text(\"a\")"])
            baseline = {"no-spacing-literal": {"Cenit/App/NotWalked.swift": 6}}
            hits = drift.check([src], ["no-spacing-literal"])
            _over, stale = drift.apply_baseline(hits, baseline, walked={drift._key(src)})
            self.assertEqual(stale, [], "sin caminar el archivo, la nota «fewer» miente")
    def test_within_budget_passes_and_below_budget_reports_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", ["VStack(spacing: 9) {}"])
            baseline = {"no-spacing-literal": {drift._key(src): 2}}
            hits = drift.check([src], ["no-spacing-literal"])
            over, stale = drift.apply_baseline(hits, baseline)
            self.assertEqual(over, [])
            self.assertEqual(stale, [("no-spacing-literal", drift._key(src), 1)])


class Fer271CommentGaps(unittest.TestCase):
    """Huecos medios del review de FER-263: los 3 deben FALLAR contra el linter pre-FER-271."""

    def test_block_comment_prefix_does_not_evade_spacing(self):
        # (a) `/* x */ .padding(99)` escapaba porque stripped.startswith('/*') saltaba la línea.
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", ["/* x */ .padding(99)"])
            hits = drift.check([src], ["no-spacing-literal"])
            self.assertEqual(len(hits), 1, hits)
            self.assertEqual(hits[0][2], "no-spacing-literal")

    def test_orphan_token_exempt_comment_counts(self):
        # (b) `// token-exempt:` en línea-comentario propia no silencia nada, pero SÍ cuenta.
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/Screens/X.swift", [
                "// token-exempt: huérfana — no hay código en esta línea",
                ".padding(1)",
            ])
            hits = drift.check([src], ["token-exempt", "no-spacing-literal"])
            rules = sorted(r for _p, _i, r, _s in hits)
            self.assertEqual(rules, ["no-spacing-literal", "token-exempt"], hits)

    def test_trailing_comment_legacy_symbol_is_not_a_hit(self):
        # (c) `import StrandDesign // InstrumentoTheme` era falso positivo de no-legacy-api.
        with tempfile.TemporaryDirectory() as tmp:
            src = _swift(tmp, "Cenit/System/RoutineDragAndDrop.swift",
                         ["import StrandDesign   // InstrumentoTheme, CenitMetrics, StrandMotion"])
            self.assertEqual(drift.check([src], ["no-legacy-api"]), [])


if __name__ == "__main__":
    unittest.main()


class AntiEvasionRules(unittest.TestCase):
    """FER-276 — las 3 reglas del colador del censo."""

    def test_raw_color_positivos_y_negativos(self):
        for line in ["Color.white", "Color.black", "Color(red: 0.1, green: 0.2, blue: 0.3)",
                     ".foregroundStyle(.white)"]:
            self.assertTrue(drift.RE_RAW_COLOR.search(line), line)
        for line in ["LiquidColor.lienzo", "Color.clear", ".foregroundStyle(.primary)",
                     "Color.whiteish"]:
            self.assertFalse(drift.RE_RAW_COLOR.search(line), line)

    def test_edgeinsets_y_aritmetica_de_token(self):
        self.assertTrue(drift.RE_EDGEINSETS.search("EdgeInsets(top: 16, leading: 10)"))
        self.assertFalse(drift.RE_EDGEINSETS.search("EdgeInsets(top: CenitMetrics.a, leading: M.b)"))
        self.assertTrue(drift.RE_TOKEN_ARITH.search(".padding(.top, CenitMetrics.space1 + 2)"))
        self.assertTrue(drift.RE_TOKEN_ARITH.search("LiquidSpace.s400 - 4"))
        self.assertFalse(drift.RE_TOKEN_ARITH.search(".padding(CenitMetrics.space1)"))

    def test_carve_outs_de_las_tres(self):
        with tempfile.TemporaryDirectory() as tmp:
            w = _swift(tmp, "CenitWidgets/X.swift", ["Color.white", "EdgeInsets(top: 1, leading: 2)",
                                                     "WidgetMetrics.hero + 2"])
            pkg = _swift(tmp, "Packages/StrandDesign/Sources/StrandDesign/Y.swift",
                         ["Color(red: 0.1, green: 0.2, blue: 0.3)", "LiquidSpace.s400 + 8"])
            rules = ["no-raw-color", "no-edgeinsets-literal", "no-token-arithmetic"]
            self.assertEqual(drift.check([w], rules), [], "Widgets/Watch: geometría de sistema")
            self.assertEqual([h for h in drift.check([pkg], rules) if h[2] != "no-edgeinsets-literal"],
                             [], "el paquete define colores y compone su escala legítimamente")


class Fase3Rules(unittest.TestCase):
    """FER-269 — movimiento y oráculo de Dynamic Type."""

    def test_motion_positivos_y_negativos(self):
        for line in ["Animation.easeInOut(0.3)", ".easeOut(duration: 0.15)",
                     ".spring(response: 0.4, dampingFraction: 0.8)"]:
            self.assertTrue(drift.RE_MOTION.search(line), line)
        for line in ["LiquidMotion.soft", ".animation(LiquidMotion.ambient(LiquidMotion.brief))",
                     ".spring()", ".easeInOut"]:
            self.assertFalse(drift.RE_MOTION.search(line), line)

    def test_dt_solo_el_cap_bendecido(self):
        self.assertTrue(drift.RE_DT_CAP.search(".dynamicTypeSize(.accessibility3)"))
        self.assertTrue(drift.RE_DT_CAP.search(".dynamicTypeSize(...DynamicTypeSize.large)"))
        self.assertFalse(drift.RE_DT_CAP.search(".dynamicTypeSize(.accessibility5)"))
