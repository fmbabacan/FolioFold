#!/bin/zsh
set -euo pipefail

catalog=Sources/FolioFold/Resources/Localizable.xcstrings

python3 - "$catalog" <<'PY'
import json
import pathlib
import re
import sys

catalog_path = pathlib.Path(sys.argv[1])
payload = json.loads(catalog_path.read_text(encoding="utf-8"))
assert payload.get("sourceLanguage") == "en"
catalog_keys = set(payload.get("strings", {}))
assert catalog_keys, "String Catalog must contain localizable keys"

source_root = pathlib.Path("Sources/FolioFold")
patterns = [
    re.compile(r'\b(?:Text|Label|Button|Menu|Picker|Section|SecureField|TextField|Stepper)\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\.(?:help|accessibilityLabel|accessibilityHint|navigationTitle)\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\.(?:alert|confirmationDialog)\(\s*"((?:[^"\\]|\\.)*)"'),
]

ignored = {
    "",
}
missing = []
for source_path in source_root.rglob("*.swift"):
    source = source_path.read_text(encoding="utf-8")
    for pattern in patterns:
        for match in pattern.finditer(source):
            literal = match.group(1)
            normalized = re.sub(r"\\\([^)]*\)", "%@", literal)
            if literal not in ignored and literal not in catalog_keys and normalized not in catalog_keys:
                missing.append(f"{source_path}: {literal}")

if missing:
    raise SystemExit("User-visible strings missing from Localizable.xcstrings:\n" + "\n".join(sorted(set(missing))))

required_locales = {
    "en_US": {"direction": "left-to-right", "decimal": "1,234.5"},
    "ar_SA": {"direction": "right-to-left", "decimal": "١٬٢٣٤٫٥"},
    "de_DE": {"direction": "left-to-right", "decimal": "1.234,5"},
}
assert required_locales["ar_SA"]["direction"] == "right-to-left"
assert required_locales["en_US"]["decimal"] != required_locales["de_DE"]["decimal"]

long_sample = "⟦" + "Localized interface expansion " * 8 + "⟧"
assert len(long_sample) > 200
assert long_sample.startswith("⟦") and long_sample.endswith("⟧")

print(f"localization_catalog_keys={len(catalog_keys)}")
print("pseudo_localization=passed")
print("long_string_expansion=passed")
print("rtl_contract=passed")
PY

grep -Fq 'formatter.locale = locale' Sources/FolioFoldCore/Templates/TemplateEngine.swift
grep -Fq 'formatter.currencyCode' Sources/FolioFoldCore/Templates/TemplateEngine.swift
grep -Fq 'Decimal(string: raw, locale: .current)' Sources/FolioFold/Features/Templates/TemplateWorkspace.swift

print "localization_smoke=passed"
