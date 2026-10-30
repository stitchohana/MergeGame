"""Verify the new workbook using both real converters, in an isolated config copy."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "config"))
from golden_finger_table import read_golden_finger, validate_cultivation
from openpyxl import load_workbook


def main():
    config = ROOT / "config"
    expected = json.loads((config / "json_output/golden_finger.json").read_text(encoding="utf-8"))
    stages = json.loads((config / "json_output/cultivation.json").read_text(encoding="utf-8"))["stages"]
    assert read_golden_finger(load_workbook(config / "xlsx/golden_finger.xlsx", data_only=True)) == expected
    validate_cultivation(expected, stages)
    for kind in ("unlock", "coverage"):
        invalid = copy.deepcopy(expected)
        if kind == "unlock":
            invalid["artifacts"][0]["unlock_level"] = 1
        else:
            invalid["realms"][-1]["cultivation_max"] = len(stages) - 1
        try:
            validate_cultivation(invalid, stages)
        except ValueError:
            pass
        else:
            raise AssertionError(f"invalid {kind} was accepted")
    temporary_root = ROOT / ".codex_tmp"
    temporary_root.mkdir(exist_ok=True)
    isolated = temporary_root / "golden-config-roundtrip" / "config"
    # Keep this reusable test workspace for diagnostics; do not overwrite source tables.
    shutil.copytree(config, isolated, dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__"))
    for script in ("json_to_xlsx.py", "xlsx_to_json.py"):
        result = subprocess.run([sys.executable, str(isolated / script)], cwd=isolated,
                                capture_output=True, text=True, encoding="utf-8", errors="replace")
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
    actual = json.loads((isolated / "json_output/golden_finger.json").read_text(encoding="utf-8"))
    assert actual == expected, "full conversion changed golden-finger settings"
    print("GOLDEN_FINGER_CONFIG_SMOKE_OK workbook full-converter-roundtrip unlock coverage")


if __name__ == "__main__":
    main()
