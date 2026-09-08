#!/usr/bin/env bash
set -euo pipefail

PROFILE="$HOME/work/argonauts-dev/.argonauts_profile"
LINE="source \"$PROFILE\""

if [[ ! -f "$PROFILE" ]]; then
  echo "Missing profile: $PROFILE" >&2
  exit 1
fi

append_source() {
  local rcfile="$1"
  mkdir -p "$(dirname "$rcfile")"
  touch "$rcfile"
  if grep -Fqx "$LINE" "$rcfile"; then
    echo "Already present in $rcfile"
    return
  fi
  echo "$LINE" >> "$rcfile"
  echo "Added to $rcfile"
}

case "${SHELL##*/}" in
  zsh)
    append_source "$HOME/.zshrc"
    ;;
  bash)
    append_source "$HOME/.bashrc"
    ;;
  *)
    if command -v zsh >/dev/null 2>&1; then
      append_source "$HOME/.zshrc"
    elif command -v bash >/dev/null 2>&1; then
      append_source "$HOME/.bashrc"
    else
      echo "Neither zsh nor bash found" >&2
      exit 1
    fi
    ;;
esac