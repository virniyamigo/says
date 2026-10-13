#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Official image pinned to the manifest digest verified during development.
image='swift@sha256:6e43114610e161e38ad41636ebcafd6940dc67dfab355eace3a0ca100b2263db'
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/project" -w /project "$image" \
    swift test --scratch-path /project/.build/linux-core
