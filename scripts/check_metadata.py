"""Fail CI before building if package and application versions disagree."""
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
fields = dict(line.split(': ', 1) for line in (root / 'control').read_text().splitlines() if ': ' in line)
version = fields['Version']
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit(f'Expected a numeric x.y.z version, got {version!r}')
info = plistlib.loads((root / 'Info.plist').read_bytes())
for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
    if info[key] != version:
        raise SystemExit(f'{key}={info[key]!r} does not match control Version={version!r}')
for path in root.rglob('*.plist'):
    if '.git' not in path.parts and '.theos' not in path.parts:
        plistlib.loads(path.read_bytes())
print(f'Validated package/app version {version} and plist files')
