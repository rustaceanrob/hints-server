#!/usr/bin/env bash

# This script generates UTXO hint files using bitcoin-cli generatetxohints.
# The output filename includes the current chain name, block height, and a
# suffix of the best block hash obtained from getblockchaininfo, allowing
# versioned hint files to be kept for historical reference.
#
# The script can optionally generate multiple output formats: raw, gzip,
# xz, zstd, or zip. Each format is written to its own directory under
# ~/hints/<format>/.
#
# For each generated file, the script updates symlinks pointing to the
# latest versioned file (e.g., main.hints.gzip -> main_900000_deadbeef.hints.gzip).
# For the main chain, an additional bitcoin.* symlink is also created
# (e.g., bitcoin.hints.gzip -> main_900000_deadbeef.hints.gzip).
#
# This script can be used together with a systemd service and a periodically
# systemd timer to automatically regenerate and publish updated hint files.

set -euo pipefail
umask 022

BITCOINCLI="$HOME/dev/bitcoin/build/bin/bitcoin-cli"
# Final hints directory. Files here are intended to be exposed for download
# (e.g., via HTTP). Each compression format lives in its own subdirectory.
HINT_DIR="$HOME/hints"
# Temporary workspace where generatetxohints writes the raw hints file
# before it is copied/compressed into HINT_DIR.
NEW_HINT_DIR="$HOME/hints_new"

usage() {
  echo "Usage: $0 [raw gzip xz zstd zip]"
  echo
  echo "Examples:"
  echo "  $0 raw"
  echo "      -> generates raw only, e.g.:"
  echo "        ~/hints/raw"
  echo "        ├── main_100_deadbeef.hints"
  echo "        ├── main.hints -> main_100_deadbeef.hints"
  echo "        └── bitcoin.hints -> main_100_deadbeef.hints"
  echo
  echo "  $0 gzip"
  echo "      -> generates gzip only, e.g.:"
  echo "        ~/hints/gzip"
  echo "        ├── main_100_deadbeef.hints.gzip"
  echo "        ├── main.hints.gzip -> main_100_deadbeef.hints.gzip"
  echo "        └── bitcoin.hints.gzip -> main_100_deadbeef.hints.gzip"
  echo
  echo "  $0 raw gzip xz"
  echo "      -> generates raw, gzip and xz, e.g.:"
  echo "        ~/hints/raw"
  echo "        ├── main_100_deadbeef.hints"
  echo "        ├── main.hints -> main_100_deadbeef.hints"
  echo "        └── bitcoin.hints -> main_100_deadbeef.hints"
  echo "        ~/hints/gzip"
  echo "        ├── main_100_deadbeef.hints.gzip"
  echo "        ├── main.hints.gzip -> main_100_deadbeef.hints.gzip"
  echo "        └── bitcoin.hints.gzip -> main_100_deadbeef.hints.gzip"
  echo "        ~/hints/xz"
  echo "        ├── main_100_deadbeef.hints.xz"
  echo "        ├── main.hints.xz -> main_100_deadbeef.hints.xz"
  echo "        └── bitcoin.hints.xz -> main_100_deadbeef.hints.xz"
  echo
  echo "Output layout:"
  echo "  ~/hints/raw/<chain>.hints"
  echo "  ~/hints/gzip/<chain>.hints.gzip"
  echo "  ~/hints/xz/<chain>.hints.xz"
  echo "  ~/hints/zstd/<chain>.hints.zst"
  echo "  ~/hints/zip/<chain>.hints.zip"
}

parse_args() {
  if [ $# -eq 0 ]; then
    METHODS=("raw")
    return
  fi
  for arg in "$@"; do
    case "$arg" in
      raw|gzip|xz|zstd|zip)
        METHODS+=("$arg")
        ;;
      help|-h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unsupported option: $arg" >&2
        usage
        exit 1
        ;;
    esac
  done
}

get_blockchain_info() {
  BLOCKCHAININFO_OUTPUT=$("$BITCOINCLI" getblockchaininfo 2>&1) || {
    echo "ERROR: bitcoind not reachable via RPC" >&2
      exit 1
    }

  CHAIN_NAME=$(echo "$BLOCKCHAININFO_OUTPUT"          | grep '"chain"'         | sed 's/.*"chain": *"\([^"]*\)".*/\1/')
  LATEST_BLOCK_HEIGHT=$(echo "$BLOCKCHAININFO_OUTPUT" | grep '"blocks"'        | sed 's/.*"blocks": *\([0-9]*\).*/\1/')
  BEST_BLOCK_HASH=$(echo "$BLOCKCHAININFO_OUTPUT"     | grep '"bestblockhash"' | sed 's/.*"bestblockhash": *"\([^"]*\)".*/\1/')

  # Use latest block height minus 10 to avoid stale blocks
  BLOCK_HEIGHT=$((LATEST_BLOCK_HEIGHT - 10))
  HASH_SUFFIX="${BEST_BLOCK_HASH: -8}"

  # Generate a unique hintfile name, e.g.: main_101_deadbeef
  VERSION_TAG="${CHAIN_NAME}_${BLOCK_HEIGHT}_${HASH_SUFFIX}"
}

# Clear NEW_HINT_DIR because generatetxohints fails if an .incomplete
# file from a previous run exists in the directory.
prepare_workspace() {
  rm -rf "$NEW_HINT_DIR"
  mkdir -p "$NEW_HINT_DIR"
  mkdir -p "$HINT_DIR"
}

generate_raw_hints() {
  local final_hint="$NEW_HINT_DIR/${VERSION_TAG}.hints"
  "$BITCOINCLI" --rpcclienttimeout=0 generatetxohints "$final_hint" "$BLOCK_HEIGHT" >/dev/null
  echo "$final_hint"
}

publish_raw() {
  local src="$1"
  local dir="$HINT_DIR/raw"
  local versioned="${VERSION_TAG}.hints"

  mkdir -p "$dir"
  cp "$src" "$dir/$versioned"
  ln -sf "$versioned" "$dir/${CHAIN_NAME}.hints"

  if [ "$CHAIN_NAME" = "main" ]; then
    ln -sf "$versioned" "$dir/bitcoin.hints"
  fi
}

publish_gzip() {
  local src="$1"
  local dir="$HINT_DIR/gzip"
  local versioned="${VERSION_TAG}.hints.gzip"

  mkdir -p "$dir"
  gzip -c "$src" > "$dir/$versioned"
  ln -sf "$versioned" "$dir/${CHAIN_NAME}.hints.gzip"

  if [ "$CHAIN_NAME" = "main" ]; then
    ln -sf "$versioned" "$dir/bitcoin.hints.gzip"
  fi
}

publish_xz() {
  local src="$1"
  local dir="$HINT_DIR/xz"
  local versioned="${VERSION_TAG}.hints.xz"

  mkdir -p "$dir"
  xz -c "$src" > "$dir/$versioned"
  ln -sf "$versioned" "$dir/${CHAIN_NAME}.hints.xz"

  if [ "$CHAIN_NAME" = "main" ]; then
    ln -sf "$versioned" "$dir/bitcoin.hints.xz"
  fi
}

publish_zstd() {
  local src="$1"
  local dir="$HINT_DIR/zstd"
  local versioned="${VERSION_TAG}.hints.zst"

  mkdir -p "$dir"
  zstd -q -c "$src" > "$dir/$versioned"
  ln -sf "$versioned" "$dir/${CHAIN_NAME}.hints.zst"

  if [ "$CHAIN_NAME" = "main" ]; then
    ln -sf "$versioned" "$dir/bitcoin.hints.zst"
  fi
}

publish_zip() {
  local src="$1"
  local dir="$HINT_DIR/zip"
  local versioned="${VERSION_TAG}.hints.zip"

  mkdir -p "$dir"
  tmp="$NEW_HINT_DIR/tmp.zip"
  (cd "$NEW_HINT_DIR" && zip -q "$tmp" "$(basename "$src")")
  mv "$tmp" "$dir/$versioned"

  ln -sf "$versioned" "$dir/${CHAIN_NAME}.hints.zip"

  if [ "$CHAIN_NAME" = "main" ]; then
    ln -sf "$versioned" "$dir/bitcoin.hints.zip"
  fi
}

publish_method() {
  local method="$1"
  local src="$2"

  case "$method" in
    raw)  publish_raw "$src" ;;
    gzip) publish_gzip "$src" ;;
    xz)   publish_xz "$src" ;;
    zstd) publish_zstd "$src" ;;
    zip)  publish_zip "$src" ;;
  esac
}

main() {
  METHODS=()
  parse_args "$@"

  echo "=== $(date) starting generatetxohints ==="

  prepare_workspace
  get_blockchain_info

  echo "Chain: $CHAIN_NAME | Latest block: $LATEST_BLOCK_HEIGHT | Hint block: $BLOCK_HEIGHT | Hash suffix: $HASH_SUFFIX"
  echo "Selected methods: ${METHODS[*]}"

  RAW_FILE=$(generate_raw_hints)

  for method in "${METHODS[@]}"; do
    publish_method "$method" "$RAW_FILE"
  done

  echo "=== $(date) finished ==="
}

main "$@"
