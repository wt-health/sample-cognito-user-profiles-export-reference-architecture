#!/bin/bash
# update-and-audit.sh
#
# Iterates over every subfolder under ./source that contains a package.json and:
#   1. Installs dependencies from the lockfile (npm ci)
#   2. Updates all packages to their latest allowed versions and saves them (npm update --save)
#   3. Audits the updated dependencies for known vulnerabilities (npm audit)
#
# Usage:
#   ./update-and-audit.sh
#
# Run from the repository root. No arguments are required.
#
# Exit codes:
#   0 - All folders processed with no vulnerabilities found
#   1 - One or more folders have vulnerabilities; affected folders are listed at the end
#
# Requirements:
#   - Node.js 24.x (22.x also supported)
#   - npm available in PATH

set -e

SOURCE_DIR="$(dirname "$0")/source"
FAILED=()

for dir in "$SOURCE_DIR"/*/; do
  [[ -f "$dir/package.json" ]] || continue

  echo "==> Processing: $dir"

  npm ci --prefix "$dir"
  npm update --save --prefix "$dir"

  if ! npm audit --prefix "$dir"; then
    echo "[WARN] Vulnerabilities found in $dir"
    FAILED+=("$dir")
  fi

  echo ""
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "Vulnerabilities detected in:"
  printf '  - %s\n' "${FAILED[@]}"
  exit 1
else
  echo "All folders passed audit."
fi
