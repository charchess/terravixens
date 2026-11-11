#!/usr/bin/env python3
import json
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "terraform/contracts/talos-image-factory.json"
REQUIRED_EXTENSION = "siderolabs/iscsi-tools"
def load_contract(path):
    data = json.loads(path.read_text())
    if data.get("version") != 1: raise ValueError("contract version must be 1")
    if data.get("scope") != "production": raise ValueError("contract scope must be production")
    required = data.get("required_extensions")
    if not isinstance(required, list) or REQUIRED_EXTENSION not in required: raise ValueError(f"required extension missing: {REQUIRED_EXTENSION}")
    template = data.get("installer_image_template")
    if template != "https://factory.talos.dev/installer/{schematic_id}:{talos_version}": raise ValueError("installer_image_template must use the reviewed factory metal-installer form")
    return data
def derive_installer_image(contract, schematic_id, talos_version):
    if not schematic_id or "/" in schematic_id or not talos_version.startswith("v"): raise ValueError("invalid image-factory derivation input")
    return contract["installer_image_template"].format(schematic_id=schematic_id, talos_version=talos_version)
def expect_rejected_without_iscsi():
    with tempfile.TemporaryDirectory() as tmp:
        mutated = Path(tmp) / "contract.json"; data = json.loads(CONTRACT.read_text()); data["required_extensions"] = []; mutated.write_text(json.dumps(data))
        try: load_contract(mutated)
        except ValueError as error:
            if REQUIRED_EXTENSION not in str(error): raise
        else: raise AssertionError("contract without iscsi-tools was accepted")
contract = load_contract(CONTRACT)
assert derive_installer_image(contract, "8f50deadbeef", "v1.11.5") == "https://factory.talos.dev/installer/8f50deadbeef:v1.11.5"
expect_rejected_without_iscsi()
print("PASS: Talos image-factory iSCSI contract rejects removal and derives metal-installer images")
