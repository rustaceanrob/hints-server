# Contrib

This directory contains helper scripts and examples for operating a hintsfile server.  
They are not required by the server itself but may be useful for automating hints generation and publication.

---

## `generate_hints.sh`

This script generates UTXO hint files using `bitcoin-cli generatetxohints`, it:

1. Queries `getblockchaininfo` to obtain the current chain, block height, and best block hash.
2. Generates a `.hints` file.
3. Optionally produces compressed variants (`raw`, `gzip`, `xz`, `zstd`, or `zip`).
4. Publishes the files into format-specific directories.
5. Updates symlinks pointing to the most recent version.

Versioned files are preserved so older hints remain available.

Example versioned file:

```
main_860000_ab12cd34.hints
```

Each format lives in its own directory:

```
~/hints/
├── raw/
├── gzip/
├── xz/
├── zstd/
└── zip/
```

Inside each directory the script keeps:

- a **versioned file**
- a **chain symlink**
- (for mainnet) a **bitcoin symlink**

Example (`gzip`):

```
~/hints/gzip
├── main_860000_ab12cd34.hints.gzip
├── main.hints.gzip -> main_860000_ab12cd34.hints.gzip
└── bitcoin.hints.gzip -> main_860000_ab12cd34.hints.gzip
```

The same layout applies to `raw`, `xz`, `zstd`, and `zip`.

---

## Requirements

- `bitcoind` running with RPC enabled
- `bitcoin-cli`
- The `generatetxohints` RPC available in your node
- Compression tools depending on the formats you want to generate:
  - `gzip`
  - `xz`
  - `zstd`
  - `zip`

---

## Running the script

Make the script executable:

```
chmod +x generate_hints.sh
```

Run with helper:

```
./generate_hints.sh --help
```

---

## Automating with systemd

A common setup is to run the script periodically using a `systemd` service and timer.

### Service

Create `/etc/systemd/system/bitcoin-hints.service`:

```
[Unit]
Description=Generate Bitcoin Hintsfile
After=bitcoind.service

[Service]
Type=oneshot
User=YOUR_LINUX_USER_HERE
ExecStart=/PATH_TO_YOUR_SCRIPT/generate_hints.sh raw gzip xz
TimeoutStartSec=800min

StandardOutput=journal
StandardError=journal
```

---

### Timer

Create `/etc/systemd/system/bitcoin-hints.timer`:

```
[Unit]
Description=Bitcoin Hintsfile Generator Timer

[Timer]
OnCalendar=Sat 20:00
Persistent=true

[Install]
WantedBy=timers.target
```

---

### Enable the timer

Reload systemd and enable the timer:

```
sudo systemctl daemon-reload
sudo systemctl enable --now bitcoin-hints.timer
```

Check status:

```
systemctl list-timers
```