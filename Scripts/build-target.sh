# Sourced from the project root. Explicit targets never share the native release staging area.
arch=${PACKPIER_ARCH:-$(uname -m)}
case "$arch" in arm64|x86_64) ;; *) echo "Unsupported macOS architecture: $arch" >&2; exit 1 ;; esac
out="build${PACKPIER_ARCH:+/$arch}"
export MACOSX_DEPLOYMENT_TARGET=14.0
swift_target="$arch-apple-macos$MACOSX_DEPLOYMENT_TARGET"
