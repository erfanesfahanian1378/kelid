#!/bin/sh
# Fails if any networking symbol appears in app/extension/package source.
# Kelid never uses the network (PLAN.md D-11, C15, rule 5.1.13). Enforced
# here rather than trusted to review, so a slip is caught at `make lint`.
set -eu

PATTERN='URLSession|NWConnection|NWPathMonitor|import Network|NSURLConnection|CFStream|WKWebView'
DIRS="App Keyboard ShareExtension Packages/KelidKit/Sources"

found=0
for dir in $DIRS; do
    if [ -d "$dir" ]; then
        if grep -rEn "$PATTERN" "$dir" --include='*.swift' 2>/dev/null; then
            found=1
        fi
    fi
done

if [ "$found" -ne 0 ]; then
    echo "lint-no-network: forbidden networking symbol found (see matches above)." >&2
    exit 1
fi

echo "lint-no-network: OK — no networking symbols found."
