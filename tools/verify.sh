#!/usr/bin/env bash
# verify.sh — cheap local sanity checks before pushing.
#
#   1. every shell script parses                      (bash -n)
#   2. every workflow is valid YAML with a jobs map   (needs python3 + PyYAML)
#   3. every relative Markdown link resolves          (perl)
#
# PyYAML is optional: if it is missing, the workflow check is skipped with a warning.
set -euo pipefail

cd "$(dirname "$0")/.."
fail=0

echo "== shell syntax =="
while IFS= read -r -d '' f; do
    if bash -n "$f" 2>/dev/null; then
        :
    else
        echo "FAIL $f"
        bash -n "$f" || true
        fail=1
    fi
done < <(find . -name '*.sh' -not -path './.git/*' -print0; printf '%s\0' ./scripts/download-firmware)
echo "done"

echo
echo "== workflow YAML =="
if python3 -c 'import yaml' 2>/dev/null; then
    if ! python3 - <<'PY'
import glob, sys, yaml
ok = True
for f in sorted(glob.glob('.github/workflows/*.yml')):
    try:
        with open(f, encoding='utf-8') as fh:
            d = yaml.safe_load(fh)
        assert isinstance(d, dict), 'top level is not a mapping'
        jobs = d.get('jobs') or {}
        assert jobs, 'no jobs'
        for name, job in jobs.items():
            assert isinstance(job, dict), f'job {name} is not a mapping'
            assert 'uses' in job or 'steps' in job, f'job {name} has neither uses nor steps'
        print(f"OK   {f}  name={d.get('name')!r} jobs={len(jobs)}")
    except Exception as e:
        ok = False
        print(f"FAIL {f}: {e}")
sys.exit(0 if ok else 1)
PY
    then
        fail=1
    fi
else
    echo "SKIP: python3 + PyYAML not available (pip install pyyaml in a venv, or skip)"
fi

echo
echo "== documentation links =="
if command -v perl >/dev/null 2>&1; then
    perl tools/check-links.pl . || fail=1
else
    echo "SKIP: perl not available"
fi

echo
if [ "$fail" -ne 0 ]; then
    echo "RESULT: FAIL"
    exit 1
fi
echo "RESULT: PASS"
