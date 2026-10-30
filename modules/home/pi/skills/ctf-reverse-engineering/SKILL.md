---
name: ctf-reverse-engineering
description: "Analyze CTF binaries, protocols, and crypto."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [CTF, Reverse Engineering, Binary Analysis, Cryptography]
---

# CTF Reverse Engineering

Use when analyzing CTF binary challenges: reverse engineering PE/ELF files, network protocol discovery, cryptographic decryption, and code flow mapping.

## General Workflow

### 1. Initial Reconnaissance
1. Classify files: `file <path>`
2. Extract strings: `strings -n 8 <path>`
3. Parse binary: `objdump -h` for sections, `objdump -p` for imports
4. Extract artifacts: `zipfile` for archives, `hashlib.sha256` for verification

### 2. Static Analysis
1. Full disassembly: `objdump -d <path>` — save to spillover if large
2. Find entry points: `<main>`, `_GLOBAL__sub_I`, mangled names
3. Map call graph: grep `call` instructions
4. Find crypto: search `rc4_init`, `rc4_crypt`, `xor`, `aes`
5. Extract static data from `.rdata`/`.data` (IPs, keys, tables)

### 3. Network Protocol Discovery
1. Find server endpoint from strings or `.data`
2. Test 3+ connections for deterministic behavior
3. Analyze response type: base64, encrypted, binary, text
4. Identify cipher: RC4 first, then XOR, then custom
5. Check for handshake before flag retrieval

### 4. Cryptographic Decryption
1. Locate key: `.rdata`/`.data`, server response, or hash-computed
2. Map flow: encrypted data → key → flag output
3. Verify: flag patterns (`flag{`, `CTF{`) or printable ASCII

### 5. Code Flow Analysis
1. Trace: `main()` → retrieval → processing → output/ADS
2. Hidden mechanisms: ADS, env vars, temp dirs
3. Data dependencies: source → destination

## Pitfalls
1. **PE section parsing** — Never use Python `struct` for PE offsets; use `objdump -h`. PE alignment corrupts struct calculations.
2. **Crypto functions may not be statically called** — `rc4_init`/`rc4_crypt` may be declared but invoked dynamically. Search the full binary.
3. **Server-sent keys** — Short server response after encrypted data is often the raw key. Test plaintext first, then hashed variants (MD5, SHA256).
4. **Base64 + encryption** — Server may send base64-encoded encrypted binary. Decode base64 first, then apply crypto.
5. **Length validation mismatch** — Client `strlen` checks may not match full server payload. Investigate secondary processing paths.
6. **Deterministic servers** — CTF responses are deterministic. Repeat connections to verify.
7. **Trailing newline in keys** — Server responses as RC4 keys include `\n`. Strip before use.

## Tools
- `objdump -h` — reliable section file offsets
- `objdump -d` — full disassembly
- `objdump -p` — import/export tables
- `strings -n 8` — string extraction
- Python stdlib: `struct`, `hashlib`, `base64`, `socket`, `re`, `zipfile`