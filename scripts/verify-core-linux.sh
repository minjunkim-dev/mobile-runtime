#!/usr/bin/env bash
# Core must not depend on Apple frameworks. Linux has none, so compiling Core
# there IS the boundary — CoreImportDisciplineTests is only the fast local echo
# of this check. Run before merging anything that touches Sources/Core.
set -euo pipefail

image="${SWIFT_IMAGE:-swift:6.3-noble}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Separate scratch path: the host's .build holds macOS artifacts.
docker run --rm \
    --user "$(id -u):$(id -g)" \
    --env HOME=/tmp \
    --volume "$root:/workspace" \
    --workdir /workspace \
    "$image" \
    swift build --scratch-path .build-linux --target Core --force-resolved-versions "$@"
