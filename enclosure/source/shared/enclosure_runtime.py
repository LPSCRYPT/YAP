"""Relocatable source, immutable packaged inputs, and per-run FreeCAD documents."""
import json
from pathlib import Path
import shutil

SOURCE = Path(__file__).resolve().parents[1]
ENCLOSURE = SOURCE.parent
_OUTPUT = None
_DOCUMENTS = {}
_MANIFEST = None


def manifest():
    global _MANIFEST
    if _MANIFEST is None:
        with (SOURCE / 'source-manifest.json').open(encoding='utf-8') as stream:
            _MANIFEST = json.load(stream)
    return _MANIFEST


def configure(output):
    global _OUTPUT
    target = Path(output).expanduser().resolve()
    if target == ENCLOSURE or ENCLOSURE in target.parents:
        raise ValueError('Build output must be outside the packaged enclosure tree')
    if target.exists() and any(target.iterdir()):
        raise ValueError('Use a new or empty output directory for each build')
    target.mkdir(parents=True, exist_ok=True)
    _OUTPUT = target
    _DOCUMENTS.clear()
    return target


def output_dir(family):
    if _OUTPUT is None:
        raise RuntimeError('Invoke source/tools/build.py build(..., output=...) first')
    path = _OUTPUT / family
    path.mkdir(parents=True, exist_ok=True)
    return str(path)


def source_path(original_name):
    """Resolve an inventoried source identifier, never a workstation path."""
    return str(SOURCE / manifest()['sources'][original_name]['path'])


def artifact_path(relative):
    path = ENCLOSURE / 'builds' / relative
    if not path.is_file():
        raise FileNotFoundError('Missing packaged build input: ' + str(path))
    return str(path)


def document(alias):
    """Return our actual document object; filenames and Name may differ.

    Never borrow an unrelated live tab. Opening a private copy also makes legacy
    save() calls safe. Register returned objects rather than renaming documents:
    FreeCAD can choose a different internal Name when a tab already exists.
    """
    import FreeCAD as App
    if alias in _DOCUMENTS:
        return _DOCUMENTS[alias]
    relative = manifest()['documents'].get(alias)
    if relative is None:
        raise KeyError('No packaged document or generated document registered for ' + alias)
    source = ENCLOSURE / relative
    if not source.is_file():
        raise FileNotFoundError('Missing packaged document for ' + alias + ': ' + str(source))
    if _OUTPUT is None:
        raise RuntimeError('Configure an isolated output before loading CAD')
    private = _OUTPUT / '.inputs' / (alias + '.FCStd')
    private.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, private)
    doc = App.openDocument(str(private))
    if doc is None:
        raise RuntimeError('FreeCAD could not open ' + str(private))
    _DOCUMENTS[alias] = doc
    return doc


def new_document(alias):
    import FreeCAD as App
    if alias in _DOCUMENTS:
        raise ValueError('Document already generated or loaded in this run: ' + alias)
    doc = App.newDocument(alias)
    _DOCUMENTS[alias] = doc
    return doc


def load_profile(path):
    path = Path(path).resolve()
    with path.open(encoding='utf-8') as stream:
        style = json.load(stream)
    style['custom_module'] = str(path.parent / style['custom_module'])
    return style
