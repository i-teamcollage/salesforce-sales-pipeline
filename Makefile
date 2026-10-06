PYTHON ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
NODE ?= node
SF ?= $(if $(wildcard $(HOME)/.local/sf/bin/sf),$(HOME)/.local/sf/bin/sf,sf)
ORG ?= iteam-dev

.PHONY: setup test node-test lint traceability deploy org-test accept readme check

setup:         ## create .venv with the test tools (the Salesforce project itself needs none)
	python3 -m venv .venv && .venv/bin/pip install -q pytest==9.1.1 ruff==0.16.10

test:          ## static conformance tests on the metadata XML (no org needed)
	$(PYTHON) -m pytest -q

node-test:     ## tests of the Google Sheets transform (no packages needed)
	$(NODE) --test google-sheets/transform.test.js

lint:
	$(PYTHON) -m ruff check .

traceability:  ## regenerate docs/traceability.md: requirement -> metadata -> tests
	$(PYTHON) scripts/traceability.py

deploy:        ## deploy the project to the org (ORG=alias, default iteam-dev)
	$(SF) project deploy start --target-org $(ORG) --wait 30

org-test:      ## run the project's Apex tests in the org and store the run in reports/
	mkdir -p reports/raw
	$(SF) apex run test --target-org $(ORG) --suite-names Sales_Pipeline --code-coverage --result-format json --wait 20 > reports/raw/org-test-run.json || true
	$(PYTHON) scripts/save_org_run.py reports/raw/org-test-run.json reports/org-test-run.json

accept:        ## compute the acceptance criteria and write reports/acceptance.*
	$(PYTHON) scripts/acceptance_run.py

readme:        ## refresh the results block in README.md from reports/acceptance.json
	$(PYTHON) scripts/acceptance_run.py readme

check: lint test node-test  ## everything GitHub runs on each change (no org in CI)
	$(PYTHON) scripts/traceability.py --check
	$(PYTHON) scripts/acceptance_run.py
	$(PYTHON) scripts/acceptance_run.py readme --check
