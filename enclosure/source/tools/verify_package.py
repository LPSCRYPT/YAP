"""Standard-library package integrity and source portability checks; no CAD run."""
import ast
import hashlib
import json
from pathlib import Path
import sys


def verify(enclosure):
    enclosure = Path(enclosure).resolve()
    source = enclosure / 'source'
    package = json.loads((enclosure / 'manifest.json').read_text(encoding='utf-8'))
    manifest = json.loads((source / 'source-manifest.json').read_text(encoding='utf-8'))
    errors = []

    def required(root, relative):
        path = (root / relative).resolve()
        if root not in path.parents:
            errors.append('Path escapes package root: ' + relative)
            return None
        if not path.is_file():
            errors.append('Missing file: ' + str(path))
            return None
        return path

    for item in package['artifact_inventory']:
        path = required(enclosure, item['path'])
        if path is None:
            continue
        if path.stat().st_size != item['bytes']:
            errors.append('Size mismatch: ' + item['path'])
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        if digest.hexdigest() != item['sha256']:
            errors.append('SHA256 mismatch: ' + item['path'])
    for original, item in manifest['sources'].items():
        required(source, item['path'])
        for dependency in item.get('source_dependencies', []):
            if dependency not in manifest['sources']:
                errors.append(original + ': unregistered dependency ' + dependency)
    for group in ('additional_shared_sources', 'additional_design_sources', 'tools'):
        for relative in manifest.get(group, []):
            required(source, relative)
    for relative in list(manifest['documents'].values()) + manifest.get('artifact_dependencies', []) + manifest.get('external_component_inputs', []):
        required(enclosure, relative)
    for path in source.rglob('*'):
        if path.suffix not in ('.py', '.FCMacro', '.json'):
            continue
        text = path.read_text(encoding='utf-8')
        # Construct the workstation prefix so this verifier is not itself a hit.
        if ('/' + 'Users' + '/' + 'bot' + '/') in text:
            errors.append('Workstation-specific runtime/source path: ' + str(path.relative_to(source)))
        if path.suffix in ('.py', '.FCMacro'):
            try:
                ast.parse(text, filename=str(path))
            except SyntaxError as error:
                errors.append(str(error))
        if path.name == 'profile.json':
            profile = json.loads(text)
            required(path.parent, profile['custom_module'])
            required(enclosure, profile['source_image'])
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print('PASS: %d artifact digests, %d inventoried sources, packaged dependencies, profile links, source syntax and portable paths' % (len(package['artifact_inventory']), len(manifest['sources'])))
    print('This does not validate CAD geometry, physical fit, or historical verification claims.')
    return 0


if __name__ == '__main__':
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
    raise SystemExit(verify(root))
