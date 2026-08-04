#!/usr/bin/env bash
set -uo pipefail
cd /app/packages/desktop

OUTPUT_PATH=""
if [ "${1:-}" = "--output_path" ]; then
  OUTPUT_PATH="$2"; shift 2
fi
MODE="${1:-new}"

UNIT_OUT="/tmp/unit-results.xml"
E2E_OUT="/tmp/e2e-results.xml"


SPLIT_VIEW_GREP="Split View"

case "$MODE" in
  base)
    # Existing unit regression suite, minus the new spec file.
    npx vitest run test/unit \
      --exclude "**/preferences-view-modes.spec.ts" \
      --reporter=junit --outputFile="$UNIT_OUT"

    # Existing e2e regression suite:
    #  - skip the fully-new view-modes.spec.ts entirely
    #  - within menu-sanity.spec.ts, run everything EXCEPT the new
    #    Split-View assertions (old behavior must still pass unchanged)
    npx playwright test test/e2e \
      --ignore-snapshots \
      --grep-invert "$SPLIT_VIEW_GREP" \
      --testIgnore="**/view-modes.spec.ts" \
      --reporter=junit
    cp test-results/junit.xml "$E2E_OUT" 2>/dev/null || true
    ;;
  new)
    # Only the fully-new unit spec.
    npx vitest run test/unit/specs/preferences-view-modes.spec.ts \
      --reporter=junit --outputFile="$UNIT_OUT"

    # The fully-new e2e spec, plus the new Split-View assertions inside
    # the otherwise-existing menu-sanity.spec.ts.
    npx playwright test test/e2e/view-modes.spec.ts \
      --grep "$SPLIT_VIEW_GREP" \
      --reporter=junit
    cp test-results/junit.xml "$E2E_OUT" 2>/dev/null || true
    ;;
esac

# Merge the two JUnit XML outputs into one file at $OUTPUT_PATH.
node -e "
const fs = require('fs');
function suites(path) {
  if (!fs.existsSync(path)) return '';
  const xml = fs.readFileSync(path, 'utf8');
  const m = xml.match(/<testsuites[^>]*>([\s\S]*)<\/testsuites>/);
  return m ? m[1] : xml.replace(/<\?xml[^>]*\?>/, '');
}
const merged = '<?xml version=\"1.0\" encoding=\"UTF-8\"?><testsuites>'
  + suites('$UNIT_OUT') + suites('$E2E_OUT') + '</testsuites>';
fs.writeFileSync('$OUTPUT_PATH', merged);
"
