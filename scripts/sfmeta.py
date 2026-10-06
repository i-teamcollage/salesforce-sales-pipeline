"""Read the Salesforce DX source in force-app/ (standard library only).

Shared by the static conformance tests (tests/), the traceability script and the acceptance script.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FORCE_APP = ROOT / "force-app" / "main" / "default"
OPPORTUNITY = FORCE_APP / "objects" / "Opportunity"
CLASSES = FORCE_APP / "classes"
SHEETS = ROOT / "google-sheets"

_NS = re.compile(r"^\{[^}]*\}")


def _strip(element: ET.Element) -> ET.Element:
    for node in element.iter():
        node.tag = _NS.sub("", node.tag)
    return element


def read(path: str | Path) -> ET.Element:
    """Parse a metadata file and drop the XML namespace from every tag."""
    return _strip(ET.parse(path).getroot())


def text(element: ET.Element, tag: str, default: str = "") -> str:
    found = element.find(tag)
    return found.text.strip() if found is not None and found.text else default


def texts(element: ET.Element, path: str) -> list[str]:
    return [node.text.strip() for node in element.findall(path) if node.text]


def field(name: str, obj: str = "Opportunity") -> ET.Element:
    return read(FORCE_APP / "objects" / obj / "fields" / f"{name}.field-meta.xml")


def field_names(obj: str = "Opportunity") -> list[str]:
    folder = FORCE_APP / "objects" / obj / "fields"
    return sorted(path.name.split(".")[0] for path in folder.glob("*.field-meta.xml"))


def picklist_values(name: str, obj: str = "Opportunity") -> list[str]:
    """Values of a picklist field, following a global value set when it uses one."""
    element = field(name, obj)
    value_set = text(element, "valueSet/valueSetName")
    if value_set:
        gvs = read(FORCE_APP / "globalValueSets" / f"{value_set}.globalValueSet-meta.xml")
        return texts(gvs, "customValue/fullName")
    return texts(element, "valueSet/valueSetDefinition/value/fullName")


def business_process(name: str) -> list[str]:
    root = read(OPPORTUNITY / "businessProcesses" / f"{name}.businessProcess-meta.xml")
    return texts(root, "values/fullName")


def validation_rules(obj: str = "Opportunity") -> dict[str, ET.Element]:
    folder = FORCE_APP / "objects" / obj / "validationRules"
    return {path.name.split(".")[0]: read(path) for path in sorted(folder.glob("*.validationRule-meta.xml"))}


def permission_set(name: str) -> ET.Element:
    return read(FORCE_APP / "permissionsets" / f"{name}.permissionset-meta.xml")


def apex_string_constant(source: str, start: str = "// export-query:start", end: str = "// export-query:end") -> str:
    """Join the string literals between two markers, the way Apex or JavaScript would concatenate them."""
    block = source.split(start, 1)[1].split(end, 1)[0]
    parts = re.findall(r"'((?:\\'|[^'])*)'|\"((?:\\\"|[^\"])*)\"", block)
    return "".join((single or double).replace("\\'", "'").replace('\\"', '"') for single, double in parts)
