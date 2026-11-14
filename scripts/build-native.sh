#!/bin/bash
set -euo pipefail
bridge_package="$(cd -- "$(dirname -- "$0")/.." && pwd)"
bridge_build="$(mktemp -d "${TMPDIR:-/tmp}/cursor-bridge-build.XXXXXX")"
trap 'rm -rf -- "$bridge_build"' EXIT

PLATFORM="$(uname -s)"
ARCH="$(uname -m)"

if [ "$PLATFORM" = Darwin ]; then
  if [ "$ARCH" != arm64 ] && [ "$ARCH" != x86_64 ]; then
    echo "Unsupported macOS architecture: $ARCH" >&2
    exit 1
  fi
elif [ "$PLATFORM" = Linux ]; then
  if [ "$ARCH" != x86_64 ] && [ "$ARCH" != aarch64 ]; then
    echo "Unsupported Linux architecture: $ARCH" >&2
    exit 1
  fi
else
  echo "Unsupported platform: $PLATFORM" >&2
  exit 1
fi

BYOK_REPO="${CURSOR_BYOK_REPO:-https://github.com/leookun/cursor-byok.git}"
git clone --branch v1.0.1 --depth 1 "$BYOK_REPO" "$bridge_build/source"
[ "$(git -C "$bridge_build/source" rev-parse HEAD)" = 2068ab20513288e6a0289d33febe872a30608610 ]
git -C "$bridge_build/source" apply "$bridge_package/source.patch"
CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}" cargo build --manifest-path "$bridge_build/source/Cargo.toml" --release --locked -p cursor-server --bin cursor-magpie-bridge
mkdir -p "$bridge_package/bin"
BIN_NAME="cursor-magpie-bridge"
cp "$bridge_build/source/target/release/cursor-magpie-bridge" "$bridge_package/bin/${BIN_NAME}.new"
chmod 755 "$bridge_package/bin/${BIN_NAME}.new"
if command -v strip >/dev/null 2>&1; then
  echo "Stripping binary symbols to optimize binary size..."
  strip "$bridge_package/bin/${BIN_NAME}.new" || true
fi
mv "$bridge_package/bin/${BIN_NAME}.new" "$bridge_package/bin/${BIN_NAME}"
python3 - "$bridge_package" <<'PY'
import hashlib,json,pathlib,subprocess,sys,platform
p=pathlib.Path(sys.argv[1])
v=json.loads((p/'package.json').read_text())['version']
b=p/'bin/cursor-magpie-bridge'
existing=json.loads((p/'integrity.json').read_text()) if (p/'integrity.json').exists() else {}
engine_ver=subprocess.check_output([str(b),'--version'],text=True).strip()
pinned_ver=existing.get('engine_version','0.3.0')
assert engine_ver==pinned_ver, f"Expected engine version {pinned_ver}, got {engine_ver}"
arch_map={'x86_64':'x64','aarch64':'arm64','AMD64':'x64','arm64':'arm64'}
arch=arch_map.get(platform.machine(),platform.machine())
os_name=platform.system().lower()
key=f'engine_{os_name}_{arch}'
digest=hashlib.sha256(b.read_bytes()).hexdigest()
existing.update({'version':v,'engine_version':engine_ver,key:digest,'engine':digest})
(p/'integrity.json').write_text(json.dumps(existing,indent=2)+'\n')
PY
