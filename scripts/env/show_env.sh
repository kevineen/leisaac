#!/usr/bin/env bash
# Print resolved machine env (loads .env.local).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/env/load_env.sh" --force --verbose
