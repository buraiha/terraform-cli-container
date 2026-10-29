#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
destination=${TFBOX_BIN_DIR:-$HOME/.local/bin}
[[ "$destination" = /* ]] || { echo 'インストール先には絶対パスを指定してください。' >&2; exit 1; }
mkdir -p "$destination"
destination=$(cd "$destination" && pwd -P)
source_root=$(cd "$script_dir/.." && pwd -P)
case "$destination/" in "$source_root/"*) echo 'インストール先はclone先の外を指定してください。' >&2; exit 1;; esac
# Preflight every destination before replacing anything.
for name in tfbox tf tfaz; do
    path="$destination/$name"
    if [[ -e "$path" || -L "$path" ]]; then
        owned=0
        if [[ -L "$path" ]]; then
            target=$(readlink "$path")
            case "$name:$target" in
                tf:tfbox|tf:"$destination/tfbox"|tf:"$script_dir/tfbox"|tfbox:"$script_dir/tfbox") owned=1 ;;
            esac
        elif [[ -f "$path" ]] && head -n 2 "$path" | grep -Fxq '# Managed by terraform-cli-container installer'; then
            owned=1
        fi
        [[ "$owned" = 1 ]] || { printf '既存ファイルを保護して中止: %s\n' "$path" >&2; exit 1; }
    fi
done
data=${TFBOX_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/terraform-cli-container}
[[ "$data" = /* ]] || { echo 'TFBOX_DATA_DIRには絶対パスを指定してください。' >&2; exit 1; }
mkdir -p "$data"
data=$(cd "$data" && pwd -P)
case "$data/" in "$source_root/"*) echo 'データ保存先はclone先の外を指定してください。' >&2; exit 1;; esac
for name in Containerfile .dockerignore; do
    path="$data/$name"
    if [[ -e "$path" || -L "$path" ]]; then
        [[ ! -L "$path" && -f "$path" ]] && head -n 1 "$path" | grep -Fxq '# Managed by terraform-cli-container installer' || {
            printf '既存データを保護して中止: %s\n' "$path" >&2; exit 1;
        }
    fi
done
stage=$(mktemp -d "$destination/.terraform-cli-container-install.XXXXXX")
trap 'rm -rf "$stage"' EXIT
for name in tfbox tfaz; do
    cp "$script_dir/$name" "$stage/$name"
    chmod 755 "$stage/$name"
done
cp "$script_dir/tf" "$stage/tf"
chmod 755 "$stage/tf"
mkdir -p "$data"
for name in Containerfile .dockerignore; do
    cp "$script_dir/../$name" "$stage/$name"
done
backup=''
for name in tfbox tf tfaz; do
    path="$destination/$name"
    if [[ -e "$path" || -L "$path" ]]; then
        if [[ -z "$backup" ]]; then backup=$(mktemp -d "$destination/.terraform-cli-container-backup.XXXXXX"); fi
        cp -Pp "$path" "$backup/$name"
    fi
done
for name in Containerfile .dockerignore; do
    if [[ -f "$data/$name" ]]; then
        if [[ -z "$backup" ]]; then backup=$(mktemp -d "$destination/.terraform-cli-container-backup.XXXXXX"); fi
        cp -p "$data/$name" "$backup/$name"
    fi
    cp "$stage/$name" "$data/$name"
done
for name in tfbox tf tfaz; do mv -f "$stage/$name" "$destination/$name"; done
printf 'インストール完了: %s（clone先は削除できます）\n' "$destination"
[[ -z "$backup" ]] || printf '変更前のバックアップ: %s\n' "$backup"
