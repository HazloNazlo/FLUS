#!/usr/bin/env python3
"""Materialize CI signing secrets without echoing their values."""
import base64
import json
import os
from pathlib import Path

root = Path(__file__).resolve().parents[1]
key = os.environ.get('FLUS_KEYSTORE_BASE64', '')
settings = os.environ.get('FLUS_SIGNING_JSON', '')
if not key or not settings:
    raise SystemExit('Configure FLUS_KEYSTORE_BASE64 and FLUS_SIGNING_JSON repository secrets.')
values = json.loads(settings)
for name in ['storePassword', 'keyPassword', 'keyAlias']:
    if not isinstance(values.get(name), str) or not values[name] or any(c in values[name] for c in '\n\r'):
        raise SystemExit('Invalid signing configuration.')
os.umask(0o077)
(root / 'android/release-key.jks').write_bytes(base64.b64decode(key, validate=True))
# java.util.Properties escaping; paths are relative to android/app.
def escaped(value):
    return value.replace('\\', '\\\\').replace(' ', '\\ ').replace(':', '\\:').replace('=', '\\=')
text = 'storeFile=../release-key.jks\n'
text += ''.join(name + '=' + escaped(values[name]) + '\n' for name in ['storePassword', 'keyPassword', 'keyAlias'])
(root / 'android/key.properties').write_text(text)
print('FLUS signing configured (secret values hidden).')
