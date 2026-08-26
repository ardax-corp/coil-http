#!/usr/bin/env bash
# Materialize git deps from coil.lock into .spool/deps.
# Prefers `spool install` when that CLI exists. Otherwise honors the lock with git.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if command -v spool >/dev/null 2>&1; then
  exec spool install
fi

if [ ! -f coil.lock ]; then
  echo "coil.lock missing" >&2
  exit 1
fi

field() {
  local key="$1"
  local block="$2"
  printf '%s\n' "$block" | sed -n "s/^${key} = '\\(.*\\)'$/\\1/p" | head -n 1
}

block=""
flush_pkg() {
  local name giturl rev hash dest tree
  name="$(field name "$block")"
  giturl="$(field git "$block")"
  rev="$(field rev "$block")"
  hash="$(field content_hash "$block")"
  if [ -z "$name" ] || [ -z "$giturl" ] || [ -z "$rev" ]; then
    return 0
  fi
  dest=".spool/deps/${name}"
  rm -rf "$dest"
  mkdir -p .spool/deps
  git clone "$giturl" "$dest"
  git -C "$dest" fetch --depth 1 origin "$rev"
  git -C "$dest" checkout --detach "$rev"
  if [ -n "$hash" ]; then
    tree="$(git -C "$dest" rev-parse 'HEAD^{tree}')"
    if [ "$tree" != "$hash" ]; then
      echo "coil.lock content_hash mismatch for ${name}: want ${hash} got ${tree}" >&2
      exit 1
    fi
  fi
}

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    "[[package]]")
      flush_pkg
      block=""
      ;;
    *)
      block="${block}${line}"$'\n'
      ;;
  esac
done < coil.lock
flush_pkg
