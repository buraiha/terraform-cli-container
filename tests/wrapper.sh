#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/runtime" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TFBOX_TEST_LOG"
MOCK
chmod +x "$tmp/runtime"
export TFBOX_RUNTIME="$tmp/runtime" TFBOX_TEST_LOG="$tmp/args"
"$root/bin/tfbox" tf plan '-out=plan with spaces.tfplan'
grep -Fx -- "$PWD:/work" "$tmp/args"
grep -Fx -- '-out=plan with spaces.tfplan' "$tmp/args"
if grep -Fx -- --tty "$tmp/args"; then exit 1; fi
"$root/bin/tfbox" az account show
if grep -Fx -- "$PWD:/work" "$tmp/args"; then exit 1; fi
TFBOX_SSH_PUBLIC_KEY=/missing.pub "$root/bin/tfbox" tf validate 2>/dev/null && exit 1
"$root/bin/tfbox" build
grep -Fx -- "$root/Containerfile" "$tmp/args"
touch "$tmp/key with spaces.pub"
TFBOX_SSH_PUBLIC_KEY="$tmp/key with spaces.pub" "$root/bin/tfbox" tf validate
grep -Fx -- "$tmp/key with spaces.pub:$tmp/key with spaces.pub:ro" "$tmp/args"
ARM_SUBSCRIPTION_ID=test-subscription "$root/bin/tfbox" tf validate
grep -Fx -- ARM_SUBSCRIPTION_ID "$tmp/args"
if grep -F -- test-subscription "$tmp/args"; then exit 1; fi
if "$root/bin/tfbox" unknown 2>/dev/null; then exit 1; fi
echo 'Wrapper checks passed'
