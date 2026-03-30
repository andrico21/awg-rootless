# AmneziaWG 2.0 - Configuration Parameters Reference

## Version History Context

AmneziaWG is an obfuscated fork of WireGuard. Version lineage:

- **1.0** - Original. Introduced `Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `H1`-`H4` (fixed values only).
- **1.5** - Added `I1`-`I5` signature packets and `j1`-`j3`, `itime`.
- **2.0** - Added `S3`, `S4`. Made `H1`-`H4` support ranges. Removed `j1`-`j3` and `itime` (deemed redundant). Retained `I1`-`I5` from 1.5.

Parameters introduced or changed in 2.0 compared to 1.0: `S3`, `S4`, `H1`-`H4` (range syntax), `I1`-`I5` (carried from 1.5 but core to 2.0).

Parameters removed in 2.0 (vs 1.5): `j1`, `j2`, `j3`, `itime`.

---

## Retained Parameters (from 1.0, unchanged)

These exist in both 1.0 and 2.0. Listed for completeness since they must coexist with the new ones.

### Jc - Junk Packet Count

- **Type:** Integer
- **Description:** Number of junk (garbage) packets sent before each WireGuard handshake.
- **Example:** `Jc = 7`

### Jmin - Junk Packet Minimum Size

- **Type:** Integer (bytes)
- **Description:** Minimum size of each junk packet in bytes.
- **Example:** `Jmin = 50`

### Jmax - Junk Packet Maximum Size

- **Type:** Integer (bytes)
- **Constraint:** Must be >= Jmin.
- **Description:** Maximum size of each junk packet in bytes. Actual size is random between Jmin and Jmax.
- **Example:** `Jmax = 1000`

### S1 - Handshake Initiation Padding

- **Type:** Integer (bytes)
- **Description:** Random padding bytes appended to Handshake Initiation packets (Type 1). Base handshake init payload is 148 bytes (4-byte header + 144 bytes body).
- **Example:** `S1 = 68`

### S2 - Handshake Response Padding

- **Type:** Integer (bytes)
- **Description:** Random padding bytes appended to Handshake Response packets (Type 2). Base handshake response payload is 92 bytes (4-byte header + 88 bytes body).
- **Example:** `S2 = 149`

---

## New Parameters in 2.0

### S3 - Cookie Reply Padding

- **Type:** Integer (bytes)
- **Default:** 0 (no padding)
- **Description:** Random padding bytes appended to Cookie Reply packets (Type 3). Standard Cookie Reply is exactly 64 bytes - a very distinctive fingerprint for DPI. S3 breaks this fingerprint.
- **When active:** Only when the server is under load and sends a Cookie Reply (DoS protection mechanism). This is a rare event in normal operation.
- **Example:** `S3 = 32` - adds 32 random bytes to the 64-byte Cookie Reply.

### S4 - Transport Data Padding

- **Type:** Integer (bytes)
- **Default:** 0 (no padding)
- **Description:** Random padding bytes appended to every encrypted transport data packet (Type 4). These are the packets carrying actual user traffic (websites, video, files, etc.).
- **When active:** Constantly, for ALL data packets. This is the most impactful parameter because transport data constitutes the vast majority of traffic.
- **Performance impact:** Higher values = more overhead per packet = lower throughput. This is the primary speed vs. obfuscation tradeoff. Start low and increase only if needed.
- **Example:** `S4 = 16` - adds up to 16 random bytes to every data packet.

### H1-H4 - Range-Based Header Values (Changed Behavior)

In 1.0, H1-H4 accepted a single fixed 32-bit unsigned integer that replaced the WireGuard packet type header. In 2.0, they accept either a single value OR a range.

- **Type:** Integer OR Integer range in format `MIN-MAX`
- **Value domain:** 32-bit unsigned integer (0 to 4294967295)
- **Single value syntax:** `H1 = 471800590` (backwards-compatible with 1.0)
- **Range syntax:** `H1 = 471800590-471800690`

**Mapping to WireGuard packet types:**

| Parameter | WireGuard Packet Type | Standard Type Value |
|-----------|----------------------|---------------------|
| H1 | Handshake Initiation | 1 |
| H2 | Handshake Response | 2 |
| H3 | Cookie Reply | 3 |
| H4 | Transport Data | 4 |

**Range behavior:**

- On send: a random value from the range `[MIN, MAX]` (inclusive) is selected for each packet.
- On receive: any value within the configured range is accepted as valid.
- Each packet gets a unique header value, making pattern-based DPI detection much harder.

**Critical constraint - ranges MUST NOT overlap between H1, H2, H3, and H4.** If ranges overlap, the receiver cannot determine the packet type. This will break the connection.

**Validation rules:**

1. MIN <= MAX (for range syntax)
2. All four values/ranges must be non-overlapping. For ranges: `H1.MAX < H2.MIN` or `H2.MAX < H1.MIN` (and so on for all pairs).
3. Values must fit in uint32 (0 to 4294967295).
4. H1-H4 must all be present and must match between client and server.

**Valid example:**

```ini
H1 = 471800590-471800690
H2 = 1246894907-1246895000
H3 = 923637689-923637690
H4 = 1769581055-1869581055
```

**Invalid example (overlapping):**

```ini
H1 = 1000-2000
H2 = 1500-2500  # INVALID: overlaps with H1 in range 1500-2000
```

### I1-I5 - Signature Packets (CPS Format)

Signature packets are sent before each WireGuard handshake to make the connection look like legitimate traffic of another protocol (DNS, QUIC, SIP, etc.). Introduced in 1.5, carried forward as a core feature of 2.0.

- **Type:** String in CPS (Custom Protocol Signature) format
- **Default:** Empty/unset (no signature packets sent)
- **Count:** Up to 5 packets (I1 through I5)
- **When sent:** Before every WireGuard handshake (handshake occurs approximately every 2 minutes)
- **Backward compatibility:** If I1 is not set, no signature packets are sent (compatible with 1.0 behavior).
- **Client/server symmetry:** In AWG 2.0, I1-I5 can be set on the server side and all generated client configs inherit them. In AWG 1.0 (Legacy), they can only be set per-client.

**Recommended signature packet size:** 100-1200 bytes total. Packets under 100 bytes look suspicious. Packets over 1200 bytes risk MTU fragmentation issues. Optimal range is 100-500 bytes.

---

## CPS (Custom Protocol Signature) Format

CPS is a domain-specific language for constructing fake protocol packets. It consists of tags concatenated together, each producing a segment of the final packet.

### Available Tags

| Tag | Name | Output | Description |
|-----|------|--------|-------------|
| `<b 0xHEX>` | Binary bytes | Exact bytes from hex | Inserts the literal bytes specified in hexadecimal. This is the "skeleton" - the magic bytes that identify a protocol. |
| `<t>` | Timestamp | 4 bytes | Inserts current Unix timestamp as 4 bytes. Adds per-handshake uniqueness. |
| `<r N>` | Random bytes | N bytes (binary) | Inserts N cryptographically random bytes. Used for padding and entropy. |
| `<rc N>` | Random chars | N bytes (ASCII) | Inserts N random alphanumeric characters from set `[A-Za-z0-9]`. Used for text-based protocol fields like domain names, connection IDs. |
| `<rd N>` | Random digits | N bytes (ASCII) | Inserts N random digits from set `[0-9]`. Used for numeric fields like ports, sequence numbers. |

### CPS Syntax Rules

1. Tags are concatenated without separators: `<b 0xc700000001><rc 8><t><r 50>`
2. The `<b>` tag requires `0x` prefix on the hex data.
3. Hex data in `<b>` must be an even number of hex characters (complete bytes).
4. `N` in `<r>`, `<rc>`, `<rd>` is a positive integer representing byte count.
5. A CPS string produces a single UDP packet.
6. The entire value of `I1`-`I5` is one CPS expression per parameter.

### CPS Validation Checklist

For an AI agent validating a CPS string:

1. Must contain at least one tag.
2. Every tag must be properly opened with `<` and closed with `>`.
3. `<b ...>` content must start with `0x` followed by valid hex characters `[0-9a-fA-F]`, even length.
4. `<r N>`, `<rc N>`, `<rd N>` - N must be a positive integer.
5. `<t>` takes no arguments.
6. No text allowed outside of tags.
7. Total output size should be 100-1200 bytes (recommended, not hard limit).

### CPS Examples

**QUIC mimicry (simple):**

```
<b 0xc700000001><rc 8><t><r 50>
```

Breakdown:
- `<b 0xc700000001>` - QUIC Initial packet header (0xc7 = packet type, 0x00000001 = QUIC v1)
- `<rc 8>` - random 8-char Connection ID
- `<t>` - timestamp
- `<r 50>` - 50 random bytes as payload

**Two-packet QUIC mimicry:**

```
i1 = <b 0xc700000001><rc 8><t><r 100>
i2 = <b 0xf6ab3267fa><t><rc 20><r 80>
```

**Static binary blob (entire captured packet as-is):**

```
i1 = <b 0xc70000000108ce1bf31eec7d93...long hex...>
```

This is a raw packet captured from Wireshark, wrapped in a single `<b>` tag. No dynamic elements - same bytes every time. Simple but less varied.

---

## Protocol Suitability for Mimicry

**Good choices** (UDP-based, common, high traffic volume):

- DNS - universal, works everywhere
- QUIC - modern HTTP/3, growing popularity
- SIP - VoIP calls, lots of legitimate traffic
- STUN - WebRTC, video calls

**Bad choices:**

- TCP-based protocols (HTTP/1.1, SMTP, FTP) - AmneziaWG is UDP-only
- Exotic/rare protocols - low traffic volume makes them suspicious
- Very short packets (< 32 bytes) - too small to be credible

---

## Packet Send Order

When a connection is established or re-keyed (every ~2 minutes):

```
1. I1 -> I2 -> I3 -> I4 -> I5  (signature packets, only if configured)
2. Junk packets x Jc             (garbage packets, random size Jmin..Jmax)
3. [S1 padding | H1(random from range) | Handshake Initiation 148 bytes]
4. [S2 padding | H2(random from range) | Handshake Response 92 bytes]
```

Under server load (rare):

```
5. [S3 padding | H3(random from range) | Cookie Reply 64 bytes]
```

All data traffic (continuous):

```
6. [S4 padding | H4(random from range) | Transport Data]
   ...repeats for every packet...
```

---

## Full Configuration Validation Rules

An AI agent validating an AmneziaWG 2.0 configuration must check:

### Mandatory Matching

All obfuscation parameters **must be identical** on client and server:

- `Jc`, `Jmin`, `Jmax`
- `S1`, `S2`, `S3`, `S4`
- `H1`, `H2`, `H3`, `H4`
- `I1`, `I2`, `I3`, `I4`, `I5`

A mismatch on any of these will cause connection failure.

### Type and Range Constraints

| Parameter | Type | Min | Max | Required |
|-----------|------|-----|-----|----------|
| Jc | uint | 0 | - | Yes |
| Jmin | uint | 0 | - | Yes |
| Jmax | uint | Jmin | - | Yes |
| S1 | uint | 0 | - | Yes |
| S2 | uint | 0 | - | Yes |
| S3 | uint | 0 | - | Yes (new) |
| S4 | uint | 0 | - | Yes (new) |
| H1 | uint or uint-uint | 0 | 4294967295 | Yes |
| H2 | uint or uint-uint | 0 | 4294967295 | Yes |
| H3 | uint or uint-uint | 0 | 4294967295 | Yes |
| H4 | uint or uint-uint | 0 | 4294967295 | Yes |
| I1 | CPS string | - | - | No |
| I2 | CPS string | - | - | No |
| I3 | CPS string | - | - | No |
| I4 | CPS string | - | - | No |
| I5 | CPS string | - | - | No |

### H1-H4 Non-Overlap Validation

For each pair `(Hi, Hj)` where `i != j`:

- If both are single values: `Hi != Hj`
- If one or both are ranges: the ranges must not overlap. Given `Hi = [a, b]` and `Hj = [c, d]`, require `b < c` OR `d < a`.

### Removed Parameters (must NOT be present in 2.0 configs)

- `j1`, `j2`, `j3` - removed, redundant
- `itime` - removed, redundant

If these appear in a config, it is likely an AWG 1.5 config, not 2.0.

---

## Example: Complete Valid 2.0 Configuration

```ini
[Interface]
Address = 10.8.1.2/24
PrivateKey = YOUR_PRIVATE_KEY
DNS = 1.1.1.1, 1.0.0.1

# Junk packets
Jc = 7
Jmin = 50
Jmax = 1000

# Padding (S1/S2 from 1.0, S3/S4 new in 2.0)
S1 = 68
S2 = 149
S3 = 32
S4 = 16

# Range-based headers (new range syntax in 2.0)
H1 = 471800590-471800690
H2 = 1246894907-1246895000
H3 = 923637689-923637690
H4 = 1769581055-1869581055

# Signature packets (CPS format, QUIC mimicry)
i1 = <b 0xc700000001><rc 8><t><r 100>
i2 = <b 0xf6ab3267fa><t><rc 20><r 80>

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = your-server.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

---

## Troubleshooting Notes

- If connection fails after config change, first verify all obfuscation params are identical on both sides.
- If speed is poor, reduce `S4` first - it affects every data packet.
- If blocked despite signature packets, try a different protocol signature or change the port to one below 9999.
- Standard WireGuard parameters (`PrivateKey`, `PublicKey`, `Endpoint`, `AllowedIPs`, `Address`, `DNS`, `ListenPort`, `PersistentKeepalive`) are unchanged from standard WireGuard and are not part of the obfuscation layer.
- AWG 2.0 requires AmneziaVPN client version 4.8.12.9 or higher.
- AWG 1.0 configs are not upgradeable to 2.0 - new keys and configs must be generated.