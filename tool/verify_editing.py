#!/usr/bin/env python3
"""Compare edited SVGs with independent librsvg renders and a handwritten oracle."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def compare(before, after):
    """Require exactly equal PNG output at the same viewport and resource access."""
    with tempfile.TemporaryDirectory(prefix='svgkit-editing-') as temporary:
        hashes = []
        for index, source in enumerate([before, after]):
            target = Path(temporary) / f'{index}.png'
            subprocess.run(
                ['/usr/bin/rsvg-convert', '-w', '480', '-h', '360', '-o', str(target), str(source)],
                check=True, capture_output=True, timeout=60,
            )
            hashes.append(hashlib.sha256(target.read_bytes()).hexdigest())
        return {'identical': hashes[0] == hashes[1], 'reference_sha256': hashes[0], 'edited_sha256': hashes[1]}


def main():
    """Verify both semantics-preserving syntax edits and deliberately visible edits."""
    corpus = ROOT / 'test/corpus'
    entries = json.loads((corpus / 'output/editing/report.json').read_text())
    results = []
    failures = []
    for entry in entries:
        name = entry['file']
        try:
            result = compare(corpus / 'files' / name, corpus / 'output/editing' / name)
            results.append({**entry, 'render': result})
            if not result['identical']:
                failures.append(name)
        except Exception as error:
            results.append({'file': name, 'failure': str(error)})
            failures.append(name)
    reference = ROOT / 'test/fixtures/editing_expected.svg'
    authoring = compare(reference, corpus / 'output/editing/authoring.svg')
    # A no-op editor must not satisfy the visible-edit oracle.
    changed = compare(ROOT / 'test/fixtures/editing_input.svg', reference)
    if not authoring['identical'] or changed['identical']:
        failures.append('authoring scenario')
    version = subprocess.run(['/usr/bin/rsvg-convert', '--version'], check=True, capture_output=True, text=True).stdout.strip()
    report = {'renderer': version, 'files': results, 'authoring': authoring, 'input_differs_from_expected': not changed['identical'], 'failures': failures}
    destination = ROOT / 'docs/validation/editing.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + '\n')
    print(f'SVG editing: {len(entries)} corpus renders + 1 visible-edit oracle; {len(failures)} failures', flush=True)
    for failure in failures:
        print(failure, flush=True)
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
