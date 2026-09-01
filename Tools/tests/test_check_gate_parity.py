#!/usr/bin/env python3
"""Tests for Tools/check-gate-parity.py (FER-265). 4 fixtures del diseño técnico."""
import importlib.util
import os
import shutil
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.abspath(os.path.join(_HERE, "..", ".."))
_spec = importlib.util.spec_from_file_location(
    "check_gate_parity", os.path.join(_HERE, "..", "check-gate-parity.py"))
parity = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(parity)

FILES = [
    "Tools/check-design-drift.py",
    "Tools/verify.sh",
    "Tools/git-hooks/pre-commit",
    ".github/workflows/design-lint.yml",
    "docs/design-system/CONTRATO.md",
]


def _copy_tree(tmp):
    for rel in FILES:
        dst = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy(os.path.join(_ROOT, rel), dst)


def _mutate(tmp, rel, old, new):
    p = os.path.join(tmp, rel)
    text = open(p, encoding="utf-8").read()
    assert old in text, f"fixture: no encontré {old!r} en {rel}"
    open(p, "w", encoding="utf-8").write(text.replace(old, new))


class GateParity(unittest.TestCase):
    def test_1_arbol_real_en_paridad(self):
        self.assertEqual(parity.check(_ROOT), [])

    def test_2_regla_nueva_sin_fila_en_matriz(self):
        with tempfile.TemporaryDirectory() as tmp:
            _copy_tree(tmp)
            _mutate(tmp, "Tools/check-design-drift.py",
                    '"token-exempt"]', '"token-exempt", "no-regla-nueva"]')
            problems = parity.check(tmp)
            self.assertTrue(any("no-regla-nueva" in p and "ALL_RULES" in p for p in problems), problems)

    def test_3_raiz_divergente_en_un_trinquete(self):
        with tempfile.TemporaryDirectory() as tmp:
            _copy_tree(tmp)
            _mutate(tmp, "Tools/verify.sh",
                    "--baseline Tools/design-drift-baseline.json Cenit/Screens Cenit/Onboarding Cenit/System Cenit/App ||",
                    "--baseline Tools/design-drift-baseline.json Cenit/Screens ||")
            problems = parity.check(tmp)
            self.assertTrue(any("no-spacing-literal" in p and "verify-quick" in p for p in problems), problems)

    def test_4_baseline_retargeteado_falla(self):
        # Review Grok FER-264 #1: apuntar --baseline a otro JSON esquiva la monotonía.
        with tempfile.TemporaryDirectory() as tmp:
            _copy_tree(tmp)
            _mutate(tmp, ".github/workflows/design-lint.yml",
                    "--rules no-spacing-literal --baseline Tools/design-drift-baseline.json",
                    "--rules no-spacing-literal --baseline Tools/design-debt.json")
            problems = parity.check(tmp)
            self.assertTrue(any("design-debt.json" in p and "canónico" in p for p in problems), problems)


if __name__ == "__main__":
    unittest.main()
