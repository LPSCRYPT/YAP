"""Circuit Cabochon: physical channels from the original jewelry treatment."""
import runpy
from enclosure_runtime import source_path

def make_envelope(style):
    treatment = runpy.run_path(source_path('JewelryEnvelopeGeometry.py'))
    parameters = dict(style)
    parameters.pop('custom_module', None)
    return treatment['make_envelope'](parameters)
