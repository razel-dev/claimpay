#!/usr/bin/env bash
# Exporte uniquement l'ABI publique compilée du contrat utilisé par le front.
set -euo pipefail

if [[ $# -ne 1 || ( $1 != --write && $1 != --check ) ]]; then
  echo "Usage : bash scripts/claimpay-abi.sh --write|--check" >&2
  exit 2
fi

mode=$1
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
target="$root/frontend/src/contracts/abi/ClaimPay.json"
generated=$(mktemp)
trap 'rm -f -- "$generated"' EXIT

cd -- "$root/contracts"
forge build src/ClaimPay.sol
# Normaliser les clés et l'ordre des entrées, mais jamais l'ordre des paramètres.
jq -eS '
  .abi
  | if type == "array" and length > 0
    then sort_by(.type, (.name // ""), (.inputs // [] | map(.type)))
    else error("ABI compilée absente ou vide") end
' out/ClaimPay.sol/ClaimPay.json > "$generated"

if [[ $mode == --write ]]; then
  mkdir -p -- "$(dirname -- "$target")"
  cp -- "$generated" "$target"
  echo "ABI exportée : frontend/src/contracts/abi/ClaimPay.json"
else
  if [[ ! -f $target ]] || ! diff -u -- "$target" "$generated"; then
    echo "ABI manquante ou obsolète. Depuis la racine : bash scripts/claimpay-abi.sh --write" >&2
    exit 1
  fi
  echo "ABI versionnée identique à la compilation."
fi
