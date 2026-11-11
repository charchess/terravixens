#!/usr/bin/env python3
"""Hermetic behavioral checks for OpenBao bootstrap token validation."""
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "terraform/modules/argocd/main.tf"
STABLE_MESSAGE = "OpenBao bootstrap input is missing or invalid"


def run(command, cwd):
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True)


def assert_source_contract():
    source = SOURCE.read_text()
    assert 'openbao_bootstrap_token = try(' in source
    assert 'token = local.openbao_bootstrap_token' in source
    assert 'condition     = local.openbao_bootstrap_token != ""' in source


def write_fixture(root: Path):
    (root / "main.tf").write_text(f"""terraform {{ required_version = ">= 1.4.0" }}
variable "openbao_bootstrap_token_path" {{ type = string }}
locals {{
  openbao_bootstrap_token = try(
    trimspace(yamldecode(file(var.openbao_bootstrap_token_path)).stringData.token),
    "",
  )
}}
resource "terraform_data" "openbao_contract" {{
  lifecycle {{
    precondition {{
      condition     = local.openbao_bootstrap_token != ""
      error_message = "{STABLE_MESSAGE}"
    }}
  }}
}}
""")


def expect_case(name: str, content: str | None, should_pass: bool):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        token_path = root / "openbao-token.yaml"
        if content is not None:
            token_path.write_text(content)
        write_fixture(root)
        init = run(["terraform", "init", "-backend=false", "-input=false", "-no-color"], root)
        assert init.returncode == 0, init.stderr
        plan = run(["terraform", "plan", "-input=false", "-lock=false", "-no-color", f"-var=openbao_bootstrap_token_path={token_path}"], root)
        if should_pass:
            assert plan.returncode == 0, f"{name}: {plan.stderr}"
        else:
            assert plan.returncode != 0, f"{name}: invalid fixture unexpectedly passed"
            assert STABLE_MESSAGE in plan.stderr, f"{name}: stable contract message absent"
            assert "synthetic-token" not in plan.stdout + plan.stderr


assert_source_contract()
expect_case("missing", None, False)
expect_case("invalid-yaml", "stringData: [", False)
expect_case("missing-stringData", "metadata: {}\n", False)
expect_case("missing-token", "stringData: {}\n", False)
expect_case("empty-token", "stringData:\n  token: '   '\n", False)
expect_case("valid-token", "stringData:\n  token: synthetic-token\n", True)
print("PASS: OpenBao bootstrap contract handles all synthetic input cases")
