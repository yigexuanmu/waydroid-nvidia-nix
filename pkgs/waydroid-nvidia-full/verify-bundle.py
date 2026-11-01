import hashlib, json, pathlib, sys

lib, tag = pathlib.Path(sys.argv[1]), sys.argv[2]
bundle = lib / 'native' / 'release'
record = json.loads((bundle / 'BUILD-RECORD.json').read_text())
if record.get('format') != 2:
    sys.exit(f'BUILD-RECORD.json is format {record.get("format")}, expected 2')
if record.get('release') != tag:
    sys.exit(f'BUILD-RECORD.json is release {record.get("release")!r}, expected {tag!r}')

# same two checks install-native.sh runs before staging: every payload/ and gate/ file, and the
# glibc-shim tree, must be exactly the files BUILD-RECORD.json lists, byte for byte
for tops, key in ((('payload', 'gate'), 'files'), (('glibc-shim',), 'glibc_shim_files')):
    want = record.get(key) or {}
    have = {str(p.relative_to(bundle)) for top in tops
            for p in (bundle / top).rglob('*') if p.is_file()}
    if have != set(want):
        sys.exit(f'{key}: bundle differs from BUILD-RECORD.json: {sorted(have ^ set(want))[:5]}')
    bad = [r for r, d in want.items()
           if hashlib.sha256((bundle / r).read_bytes()).hexdigest() != d]
    if bad:
        sys.exit(f'{key}: {len(bad)} files fail their sha256 (first {bad[0]})')

# the vendor image must be the one its OTA channel names (waydroid's own check: sha256 = id)
(channel,) = json.loads(
    (lib / 'vendor' / f'waydroid-nvidia-vendor-ota-{tag}.json').read_text())['response']
image = lib / 'vendor' / channel['filename']
if not image.is_file():
    sys.exit(f'vendor image {image} is missing')
digest = hashlib.sha256()
with open(image, 'rb') as f:
    for block in iter(lambda: f.read(1 << 20), b''):
        digest.update(block)
if digest.hexdigest() != channel['id']:
    sys.exit(f'vendor image {image} does not match its channel id')

print(f'verified: {len(record["files"])} bundle files + '
      f'{len(record["glibc_shim_files"])} glibc-shim files, vendor image {channel["filename"]}')
