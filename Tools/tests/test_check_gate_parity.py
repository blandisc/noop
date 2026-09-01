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
                    '"no-token-arithmetic"]', '"no-token-arithmetic", "no-regla-nueva"]')
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

    def test_5_senuelo_en_comentario_no_satisface(self):
        # Review Grok FER-265 caso C: invocación canónica en comentario + una débil ejecutable.
        with tempfile.TemporaryDirectory() as tmp:
            _copy_tree(tmp)
            _mutate(tmp, "Tools/verify.sh",
                    "python3 Tools/check-design-drift.py --rules no-spacing-literal \\",
                    "# python3 Tools/check-design-drift.py --rules no-spacing-literal --baseline Tools/design-drift-baseline.json Cenit/Screens Cenit/Onboarding Cenit/System Cenit/App\n"
                    "      python3 Tools/check-design-drift.py --rules no-spacing-literal \\")
            _mutate(tmp, "Tools/verify.sh",
                    "--baseline Tools/design-drift-baseline.json Cenit/Screens Cenit/Onboarding Cenit/System Cenit/App || ok=1",
                    "--baseline Tools/design-drift-baseline.json Cenit/Screens || ok=1")
            problems = parity.check(tmp)
            self.assertTrue(any("no-spacing-literal" in p and "verify-quick" in p for p in problems),
                            f"el señuelo comentado no debe contar: {problems}")

    def test_6_if_false_y_continue_on_error_prohibidos(self):
        with tempfile.TemporaryDirectory() as tmp:
            _copy_tree(tmp)
            _mutate(tmp, ".github/workflows/design-lint.yml",
                    "      - name: Design-drift linter — no raw hex (all roots)",
                    "      - name: Design-drift linter — no raw hex (all roots)\n        if: false\n        continue-on-error: true")
            problems = parity.check(tmp)
            self.assertTrue(any("continue-on-error" in p for p in problems), problems)
            self.assertTrue(any("if:" in p for p in problems), problems)

    def test_7_duplicado_debil_junto_al_canonico_falla(self):
        # Caso A: el canónico se queda pero se agrega una invocación más débil de la misma regla.
        with tempfile.TemporaryDirectory() as tmp:
            _copy_tree(tmp)
            _mutate(tmp, ".github/workflows/design-lint.yml",
                    "      - name: Sin vidrio dentro de una hoja (papel opaco)",
                    "      - name: spacing débil\n        run: python3 Tools/check-design-drift.py --rules no-spacing-literal Cenit/Screens\n      - name: Sin vidrio dentro de una hoja (papel opaco)")
            problems = parity.check(tmp)
            self.assertTrue(any("no-spacing-literal" in p and "design-lint" in p for p in problems), problems)

    def test_8_formas_con_igual_se_parsean_como_el_linter(self):
        invs = parity.parse_invocations(
            "python3 Tools/check-design-drift.py --rules=no-hex --baseline=Tools/x.json Cenit/App")
        self.assertEqual(invs, [(["no-hex"], "Tools/x.json", ["Cenit/App"], False)])

    def test_10_senuelo_en_name_de_yaml_ya_no_existe_para_el_parser(self):
        # FER-272: el YAML se parsea como YAML — un name: con la invocación canónica no es run:.
        with tempfile.TemporaryDirectory() as tmp:
            _copy_tree(tmp)
            _mutate(tmp, ".github/workflows/design-lint.yml",
                    "run: python3 Tools/check-design-drift.py --rules no-raw-shadow Cenit/Screens",
                    "run: python3 Tools/check-design-drift.py --rules no-raw-shadow Cenit/Onboarding")
            _mutate(tmp, ".github/workflows/design-lint.yml",
                    "      - name: Design-drift linter — no raw shadow, use StrandElevation (migrated screens)",
                    "      - name: python3 Tools/check-design-drift.py --rules no-raw-shadow Cenit/Screens")
            problems = parity.check(tmp)
            self.assertTrue(any("no-raw-shadow" in p for p in problems),
                            f"el name-señuelo no debe satisfacer la raíz declarada: {problems}")

    def test_11_yaml_roto_falla_cerrado(self):
        with tempfile.TemporaryDirectory() as tmp:
            _copy_tree(tmp)
            p = os.path.join(tmp, ".github/workflows/design-lint.yml")
            open(p, "a", encoding="utf-8").write("\n\t- esto: [no cierra\n")
            problems = parity.check(tmp)
            self.assertTrue(any("fail-closed" in p2 for p2 in problems), problems)

    def test_9_all_rules_no_literal_falla_cerrado(self):
        with tempfile.TemporaryDirectory() as tmp:
            _copy_tree(tmp)
            _mutate(tmp, "Tools/check-design-drift.py", "ALL_RULES = [", "ALL_RULES = tuple([")
            problems = parity.check(tmp)
            self.assertTrue(any("lista literal" in p for p in problems), problems)

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
