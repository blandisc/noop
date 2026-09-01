#!/usr/bin/env python3
"""Tests for Tools/check-baseline-monotony.py (FER-264). Los 5 casos del diseño técnico."""
import importlib.util
import json
import os
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "check_baseline_monotony", os.path.join(_HERE, "..", "check-baseline-monotony.py"))
mono = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mono)


def _run(base, pr, extra=None):
    with tempfile.TemporaryDirectory() as tmp:
        bp, pp = os.path.join(tmp, "base.json"), os.path.join(tmp, "pr.json")
        json.dump(base, open(bp, "w"))
        json.dump(pr, open(pp, "w"))
        return mono.main([bp, pp] + (extra or []))


BASE = {"no-spacing-literal": {"A.swift": 3}, "token-exempt": {"B.swift": 2}}


class Monotony(unittest.TestCase):
    def test_1_sube_falla(self):
        pr = {"no-spacing-literal": {"A.swift": 4}, "token-exempt": {"B.swift": 2}}
        self.assertEqual(_run(BASE, pr), 1)

    def test_2_igual_pasa(self):
        self.assertEqual(_run(BASE, BASE), 0)

    def test_3_baja_y_clave_desaparecida_pasan(self):
        pr = {"no-spacing-literal": {"A.swift": 1}}
        self.assertEqual(_run(BASE, pr), 0)

    def test_4_bypass_ok_label_y_diff_solo_baseline_docs(self):
        pr = {"no-spacing-literal": {"A.swift": 9}, "token-exempt": {"B.swift": 2}}
        rc = _run(BASE, pr, ["--labels", "baseline-alta,otra",
                             "--diff-files", "Tools/design-drift-baseline.json,docs/design-system/CONTRATO.md"])
        self.assertEqual(rc, 0)

    def test_5_bypass_con_swift_en_el_diff_falla_aunque_haya_label(self):
        pr = {"no-spacing-literal": {"A.swift": 9}}
        rc = _run(BASE, pr, ["--labels", "baseline-alta",
                             "--diff-files", "Tools/design-drift-baseline.json,Cenit/Screens/X.swift"])
        self.assertEqual(rc, 1, "un PR con código no puede bendecirse solo")

    def test_extra_clave_nueva_con_conteo_es_subida(self):
        pr = {"no-spacing-literal": {"A.swift": 3, "Nuevo.swift": 1}, "token-exempt": {"B.swift": 2}}
        self.assertEqual(_run(BASE, pr), 1)

    def test_extra_regla_nueva_completa_es_alta_estructural_legal(self):
        # FER-276: estrenar un gate congela deuda vieja bajo una clave nueva — no es subida.
        pr = {"no-spacing-literal": {"A.swift": 3}, "token-exempt": {"B.swift": 2},
              "no-raw-color": {"X.swift": 6}}
        self.assertEqual(_run(BASE, pr), 0)

    def test_extra_label_sin_diff_files_no_bypassa(self):
        pr = {"no-spacing-literal": {"A.swift": 9}}
        self.assertEqual(_run(BASE, pr, ["--labels", "baseline-alta"]), 1)


if __name__ == "__main__":
    unittest.main()
