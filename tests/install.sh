#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_DATA_HOME="$HOME/.local/share"
mkdir -p "$HOME" "$tmp/source" "$tmp/mock" "$tmp/project"
cp -R "$root/bin" "$tmp/source/bin"
cp "$root/Containerfile" "$root/.dockerignore" "$tmp/source/"
export TFBOX_BIN_DIR="$HOME/.local/bin"
export TFBOX_RUNTIME="$tmp/mock/runtime"
# Azure accepts engine names only; Terraform also accepts an executable path.
cat > "$tmp/mock/runtime" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_ARGS"
cat > /dev/null
exit "${TEST_EXIT:-0}"
MOCK
chmod +x "$tmp/mock/runtime"
ln -s runtime "$tmp/mock/docker"
export PATH="$tmp/mock:$PATH"
export TEST_ARGS="$tmp/args"

"$tmp/source/bin/install.sh"
"$tmp/source/bin/install.sh"
for name in tfbox tf tfaz; do [[ -f "$HOME/.local/bin/$name" && ! -L "$HOME/.local/bin/$name" && -x "$HOME/.local/bin/$name" ]]; done
# Remove the entire source tree, then exercise installed commands.
rm -rf "$tmp/source"
cd "$tmp/project"
"$HOME/.local/bin/tf" version < /dev/null
grep -Fxq terraform "$TEST_ARGS"
"$HOME/.local/bin/tfaz" version < /dev/null
grep -Fxq az "$TEST_ARGS"
"$HOME/.local/bin/tfbox" build < /dev/null
grep -Fxq "$XDG_DATA_HOME/terraform-cli-container/Containerfile" "$TEST_ARGS"
[[ -f "$XDG_DATA_HOME/terraform-cli-container/.dockerignore" ]]
# Unrelated existing commands must be preserved before any replacements.
mkdir -p "$tmp/conflict"
printf keep > "$tmp/conflict/tf"
if TFBOX_BIN_DIR="$tmp/conflict" "$root/bin/install.sh" 2>/dev/null; then exit 1; fi
[[ "$(cat "$tmp/conflict/tf")" = keep ]]
[[ ! -e "$tmp/conflict/tfbox" ]]
for script in "$root"/bin/* "$root"/tests/*.sh; do bash -n "$script"; done
printf 'PASS: copy install, reinstall, source deletion, installed commands, conflict protection\n'
