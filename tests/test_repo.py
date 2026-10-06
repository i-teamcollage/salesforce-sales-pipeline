"""Repository hygiene: no invisible characters, no secrets, no prices, the same footer as the other samples."""

import re

from sfmeta import ROOT

SKIP = {".git", ".venv", ".sf", ".sfdx", "node_modules", "__pycache__", ".pytest_cache", ".ruff_cache", "raw"}
TEXT_SUFFIXES = {".md", ".py", ".js", ".gs", ".json", ".toml", ".xml", ".cls", ".trigger", ".html", ".yml", ""}
FOOTER = """Built by [I-Team Collage](https://iteamcollage.com): workflow automation for finance, operations and
support teams in Europe, accepted only when it passes a test your own people wrote.
[Book a free 30-minute call](https://calendly.com/dorsa-maskouki/i-team-collage).

Licensed under the [MIT License](LICENSE)."""


def text_files():
    for path in ROOT.rglob("*"):
        if path.is_file() and not SKIP & set(path.relative_to(ROOT).parts) and path.suffix in TEXT_SUFFIXES:
            yield path


def test_no_invisible_or_non_breaking_whitespace():
    codes = [0xA0, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF, *range(0x2000, 0x2010)]
    bad = re.compile("[" + "".join(chr(code) for code in codes) + "]")
    offenders = [str(p.relative_to(ROOT)) for p in text_files() if bad.search(p.read_text(encoding="utf-8"))]
    assert offenders == []


def test_no_secrets_in_the_repository():
    patterns = re.compile(r"(00D[A-Za-z0-9]{12,15}![A-Za-z0-9._]{20,}|sk-[A-Za-z0-9]{20,}|"
                          r"BEGIN (RSA|OPENSSH) PRIVATE KEY|client_secret\s*[:=]\s*['\"][A-Za-z0-9]{16,})")
    offenders = [str(p.relative_to(ROOT)) for p in text_files() if patterns.search(p.read_text(encoding="utf-8"))]
    assert offenders == []
    assert not list(ROOT.glob(".env*"))


def test_no_fixed_price_wording():
    offenders = [str(p.relative_to(ROOT)) for p in text_files()
                 if "fixed price" in p.read_text(encoding="utf-8").lower() and p.name != "test_repo.py"]
    assert offenders == []


def test_readme_ends_with_the_shared_footer():
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert readme.rstrip().endswith(FOOTER)
    assert "github.com/i-teamcollage/salesforce-sales-pipeline" in readme
