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

## Protocol Signatures Reference

### Protocol Suitability

Only UDP-based protocols are valid targets (AmneziaWG runs over UDP). Avoid TCP-based (HTTP/1.1, SMTP, FTP), exotic/rare protocols, and packets shorter than 32 bytes.

| Protocol | Port(s) | Suitability | Why |
|----------|---------|-------------|-----|
| QUIC v1/v2 | 443 | Excellent | HTTP/3 backbone, massive traffic volume, encrypted by design so random payload looks natural |
| DNS | 53 | Excellent | Universal, never blocked, present on every network |
| STUN | 3478, 19302 | Good | WebRTC/video calls, common in corporate and consumer networks |
| DTLS 1.2 | 443, 4433 | Good | Encrypted UDP (used by WebRTC, IoT), growing adoption |
| SIP | 5060, 5061 | Good | VoIP calls, lots of legitimate traffic especially in enterprise |
| RTP | 5004, 16384-32767 | Good | Real-time media (audio/video streams), high volume during calls, large packets normal |
| IKEv2 | 500 | Good | IPsec key exchange, common in corporate VPNs, always allowed through enterprise firewalls |
| GTP-U | 2152 | Fair | Mobile/cellular tunneling, very common on mobile carrier networks, less so on Wi-Fi |
| NTP v4 | 123 | Fair | Time sync, ubiquitous but fixed 48-byte packets and low frequency - small signature |
| CoAP | 5683 | Fair | IoT protocol, growing but still niche - best in IoT-heavy environments |
| RADIUS | 1812 | Fair | Authentication protocol, common in enterprise but rare on consumer networks |
| OpenVPN UDP | 1194 | Poor | Defeats the purpose - still a VPN signature |

### Protocol Signature Packets (i1-i5 values)

Ready-to-use CPS values per protocol. Empty cells = not needed (leave parameter unset).

| Protocol | Best Port | i1 | i2 | i3 | i4 | i5 |
|----------|-----------|----|----|----|----|-----|
| QUIC v1 | 443 | `<b 0xc700000001><rc 8><t><r 100>` | `<b 0xc700000001><rc 8><t><r 300>` | | | |
| QUIC v2 | 443 | `<b 0xd7709a50c4><rc 8><t><r 100>` | `<b 0xd7709a50c4><rc 8><t><r 300>` | | | |
| DNS | 53, 5353 | `<b 0x0100000100000000000003777777076578616d706c6503636f6d00000100><t><r 50>` | `<b 0x0100000100000000000006676f6f676c6503636f6d0000010001><t><r 40>` | | | |
| STUN | 3478, 19302 | `<b 0x000100002112a442><r 12><r 100>` | | | | |
| DTLS 1.2 | 443, 4433 | `<b 0x16fefd0000000000000000><r 2><b 0x01><r 3><b 0xfefd><r 32><b 0x00><rc 4><r 100>` | | | | |
| SIP | 5060 | `<b 0x524547495354455220736970><rc 12><b 0x3a><rd 4><b 0x20534950><r 80>` | | | | |
| NTP v4 | 123 | `<b 0x23000a00><r 40><t>` | | | | |
| RTP (media) | 5004, 16384-32767 | `<b 0x8060><r 2><t><r 4><r 100>` | `<b 0x8060><r 2><t><r 4><r 200>` | | | |
| IKEv2 (IPsec) | 500 | `<r 8><b 0x00000000000000002120220800000000><r 4><r 200>` | | | | |
| GTP-U (mobile) | 2152 | `<b 0x30ff><r 2><r 4><r 100>` | | | | |
| CoAP (IoT) | 5683 | `<b 0x4001><r 2><rc 4><r 50>` | | | | |
| RADIUS | 1812 | `<b 0x01><r 1><b 0x0032><r 16><r 30>` | | | | |

### Magic Bytes Cheat Sheet

What makes DPI classify each packet:

| Protocol | Key hex bytes | Meaning |
|----------|--------------|---------|
| QUIC v1 | `0xc700000001` | `0xc7` = Long Header + Initial type, `0x00000001` = QUIC version 1 |
| QUIC v2 | `0xd7709a50c4` | `0xd7` = Long Header + Initial type (v2 bit layout), `0x709a50c4` = QUIC version 2 (RFC 9369) |
| DNS | `0x0100000100000000000003777777...` | Transaction ID + flags `0x0100` (standard query, recursion desired) + 1 question + QNAME in label format |
| STUN | `0x000100002112a442` | `0x0001` = Binding Request, `0x0000` = msg length, `0x2112a442` = STUN magic cookie (RFC 5389, always fixed) |
| DTLS 1.2 | `0x16fefd` | `0x16` = Handshake content type, `0xfefd` = DTLS 1.2 version (inverted numbering) |
| SIP | `0x524547495354455220736970` | ASCII for `REGISTER sip` |
| NTP v4 | `0x23` | `0x23` = LI=0 (no warning), VN=4 (version 4), Mode=3 (client). Fixed 48-byte packet. |
| RTP | `0x8060` | `0x80` = V=2, no Padding/Extension/CSRC. `0x60` = PT 96 (dynamic payload, typical for video/audio). |
| IKEv2 | `0x00000000000000002120220800000000` | 8-byte zero Responder SPI (initial exchange), `0x21` = Next Payload: SA, `0x20` = IKEv2, `0x22` = IKE_SA_INIT, `0x08` = Initiator flag |
| GTP-U | `0x30ff` | `0x30` = Version 1, Protocol Type=1, no extensions. `0xff` = G-PDU message type (encapsulated user data). |
| CoAP | `0x4001` | `0x40` = Ver=1, Type=CON (confirmable), TKL=0. `0x01` = Code 0.01 (GET method). |
| RADIUS | `0x01` | `0x01` = Code: Access-Request. Followed by 1-byte ID, 2-byte length, 16-byte authenticator. |

### Ready-to-Use Configuration Sets

Three complete parameter sets. All H ranges are non-overlapping. Copy as-is for both client and server.

| Parameter | Set A: QUIC (recommended) | Set B: DNS (max compat) | Set C: STUN (video cover) |
|-----------|--------------------------|------------------------|--------------------------|
| Jc | 5 | 3 | 4 |
| Jmin | 50 | 40 | 60 |
| Jmax | 500 | 250 | 800 |
| S1 | 68 | 40 | 56 |
| S2 | 149 | 80 | 120 |
| S3 | 32 | 16 | 24 |
| S4 | 8 | 4 | 12 |
| H1 | 471800590-471800690 | 100000000-100000200 | 700000000-700000500 |
| H2 | 1246894907-1246895000 | 200000000-200000200 | 800000000-800000500 |
| H3 | 923637689-923637690 | 300000000-300000050 | 900000000-900000010 |
| H4 | 1769581055-1869581055 | 400000000-500000000 | 1000000000-1100000000 |
| i1 | `<b 0xc700000001><rc 8><t><r 100>` | `<b 0x0100000100000000000003777777076578616d706c6503636f6d00000100><t><r 50>` | `<b 0x000100002112a442><r 12><r 100>` |
| i2 | `<b 0xc700000001><rc 8><t><r 300>` | | |
| i3 | | | |
| i4 | | | |
| i5 | | | |
| Server port | 443 | 53 or 5353 | 3478 or 19302 |

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