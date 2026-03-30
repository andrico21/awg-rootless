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
| SRT (live stream) | 9000, 9001 | Good | OBS Studio, FFmpeg, Haivision live streaming. UDP-based, encrypted payload expected, large packets normal. Growing fast in broadcast/streaming. |
| MPEG-TS over UDP | 1234, 5000-5999 | Good | Classic IPTV delivery, live TV. Very high traffic volume on carrier/ISP networks. Distinctive 0x47 sync byte every 188 bytes. |
| RTCP | 5005, odd ports | Fair | RTP Control Protocol, always paired with RTP on the next port. Small packets, low frequency - best combined with RTP on adjacent port. |
| TURN | 3478 | Good | STUN-based relay traversal (RFC 5766). Same magic cookie as STUN but Allocate request type. Common where direct P2P fails. |
| RTP Video (H.264) | 16384-32767 | Good | Video call media stream with dynamic PT 96. Marker bit set signals end-of-frame. Very high volume during calls, large packets. Indistinguishable from Zoom/Teams/Meet media. |
| RTP Audio (Opus) | 16384-32767 | Good | Audio call stream, PT 111 (Opus codec). Standard in all WebRTC - Discord, Telegram, WhatsApp, browser calls. Small frequent packets (~50/sec). |
| RTP Audio (G.711) | 16384-32767 | Good | Classic telephony audio, PT 0 (PCMU/G.711). Standard on SIP phones, PBX systems, enterprise VoIP. Fixed 160-byte payload at 50pps. |
| SRTP/SRTCP | 16384-32767 | Good | Encrypted RTP/RTCP (RFC 3711). Same header as RTP but with 10-byte HMAC auth tag appended. Used by all modern WebRTC (Chrome, Firefox, Safari). DPI cannot distinguish from plain RTP by header. |
| ZRTP | 5004, 5060 | Good | End-to-end VoIP key exchange (RFC 6189). Precedes SRTP session. Used by Signal, Opal, Ozone. Distinctive `0x505a` preamble + `ZRTP` magic cookie. |
| SIP INVITE | 5060 | Good | VoIP call initiation (vs REGISTER for login). ASCII-based, extremely common on enterprise and carrier networks. |
| Zoom media | 8801-8810 | Fair | Zoom uses RTP internally on ports 8801-8810. Proprietary framing, but outer header looks like standard RTP. Use RTP Video signature on these ports. |
| WebRTC bundle | 443, 3478 | Excellent | Modern video calls multiplex STUN+DTLS+SRTP on a single port. Sending STUN then DTLS as i1+i2 perfectly mimics a real WebRTC session setup. Best stealth for video call cover. |
| Steam A2S Query | 27015-27050 | Good | Valve Source Engine server query. Extremely common - CS2, Dota 2, TF2, Rust, ARK. Distinctive `0xFFFFFFFF54` header. High traffic on gaming networks. |
| ENet (game netcode) | 7777-7790 | Good | Used by Minecraft (Bedrock), Factorio, many Unity/Unreal games. Lightweight reliable UDP. Ubiquitous in multiplayer gaming. |
| BT UDP Tracker | 6881, 80, 1337 | Good | BitTorrent UDP tracker connect handshake (BEP 15). Magic constant `0x41727101980`. Massive worldwide traffic volume - one of the most common UDP protocols on the internet. |
| BT DHT (KRPC) | 6881, dynamic | Good | BitTorrent Distributed Hash Table (BEP 5). Bencoded dictionaries over UDP. Enormous traffic volume from all torrent clients. |
| uTP (BitTorrent) | dynamic | Good | Micro Transport Protocol (BEP 29). UDP-based transport used by qBittorrent, Transmission, Deluge. Delay-based congestion control. Very high traffic volume. |
| Yandex Telemost | 443, 3478 | Good | Uses standard WebRTC internally (STUN+DTLS+SRTP). Use WebRTC bundle signature on port 443. |
| VK Calls / MAX | 443, 3478 | Good | Uses standard WebRTC internally. Use WebRTC bundle signature. Same applies to Telegram calls, WhatsApp calls, Discord voice. |
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
| SRT (live stream) | 9000 | `<b 0x80000000><r 4><t><b 0x00000000><b 0x00000004><r 4><r 100>` | `<b 0x80000000><r 4><t><b 0x00000000><b 0x00000005><r 4><r 80>` | | | |
| MPEG-TS / IPTV | 1234, 5000 | `<b 0x471fff10><r 184><b 0x471fff10><r 184><b 0x471fff10><r 184>` | | | | |
| RTCP | 5005 | `<b 0x80c9><r 2><r 4><r 60>` | | | | |
| TURN (relay) | 3478 | `<b 0x000300002112a442><r 12><r 100>` | | | | |
| RTP Video (H.264) | 16384-32767 | `<b 0x80e0><r 2><t><r 4><r 400>` | `<b 0x8060><r 2><t><r 4><r 800>` | | | |
| RTP Audio (Opus) | 16384-32767 | `<b 0x80ef><r 2><t><r 4><r 80>` | `<b 0x806f><r 2><t><r 4><r 80>` | | | |
| RTP Audio (G.711) | 16384-32767 | `<b 0x8080><r 2><t><r 4><r 160>` | `<b 0x8000><r 2><t><r 4><r 160>` | | | |
| SRTP (encrypted) | 16384-32767 | `<b 0x80e0><r 2><t><r 4><r 400><r 10>` | `<b 0x8060><r 2><t><r 4><r 800><r 10>` | | | |
| ZRTP (key exchange) | 5004 | `<b 0x10005a525450><r 2><r 4><b 0x48656c6c6f202020><r 76>` | | | | |
| SIP INVITE | 5060 | `<b 0x494e5649544520736970><rc 12><b 0x3a><rd 4><b 0x20534950><r 80>` | | | | |
| WebRTC bundle | 443, 3478 | `<b 0x000100002112a442><r 12><r 50>` | `<b 0x16fefd0000000000000000><r 2><b 0x01><r 3><b 0xfefd><r 32><b 0x00><rc 4><r 100>` | `<b 0x80e0><r 2><t><r 4><r 200>` | | |
| Steam A2S Query | 27015 | `<b 0xffffffff54536f7572636520456e67696e6520517565727900><r 50>` | | | | |
| ENet connect | 7777 | `<b 0xffff0000><t><b 0x0c><b 0x02><r 2><b 0x00><r 1><r 2><r 2><b 0xffff><r 4><r 4><r 100>` | | | | |
| BT UDP Tracker | 6881, 1337 | `<b 0x0000041727101980><b 0x00000000><r 4><r 50>` | | | | |
| BT DHT ping | 6881 | `<b 0x64313a6164323a696432303a><r 20><b 0x65313a71343a70696e67313a74323a><r 2><b 0x313a79313a7165>` | | | | |
| uTP SYN | dynamic | `<b 0x41000000><r 2><t><r 4><r 4><r 2><r 50>` | | | | |

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
| SRT | `0x80000000` | Bit 0 = 1 (control packet), Control Type = `0x0000` (Handshake), Subtype = `0x0000`. Followed by 4-byte type-specific info, 4-byte timestamp, 4-byte Destination Socket ID (0x00000000 for induction). Then CIF with version=4 (`0x00000004`, UDT-compatible) or version=5 (`0x00000005`, SRT-native). |
| MPEG-TS | `0x47` | Sync byte, always `0x47` at the start of every 188-byte Transport Stream packet. `0x1fff` = null PID (padding/stuffing). `0x10` = has payload, no adaptation field. Multiple TS packets per UDP datagram (typically 7 = 1316 bytes). |
| RTCP | `0x80c9` | `0x80` = V=2, no padding, Reception Report count=0. `0xc9` = Packet Type 201 (Receiver Report). Alternative: `0x80c8` for Sender Report (PT=200). |
| TURN | `0x000300002112a442` | `0x0003` = Allocate Request (RFC 5766), `0x0000` = msg length, `0x2112a442` = same STUN magic cookie. Structurally identical to STUN but different message type. |
| RTP Video (H.264) | `0x80e0` / `0x8060` | `0x80` = V=2, no Padding/Extension/CSRC. `0xe0` = Marker bit set + PT 96 (end of video frame). `0x60` = no Marker + PT 96 (mid-frame packet). Followed by 2-byte seq, 4-byte timestamp, 4-byte SSRC. |
| RTP Audio (Opus) | `0x80ef` / `0x806f` | Same RTP V2 header. `0xef` = Marker + PT 111 (Opus, standard WebRTC audio). `0x6f` = no Marker + PT 111. |
| RTP Audio (G.711) | `0x8080` / `0x8000` | Same RTP V2 header. `0x80` = Marker + PT 0 (PCMU/G.711). `0x00` = no Marker + PT 0. Classic telephony. Payload is always 160 bytes (20ms at 8kHz). |
| SRTP | Same as RTP | Identical RTP header. DPI cannot distinguish from plain RTP by header alone. Difference: 10-byte HMAC-SHA1 authentication tag appended after payload. Signature = RTP header + larger payload to account for auth tag. |
| ZRTP | `0x10005a525450` | `0x1000` = RTP extension bit pattern (not real RTP). `0x5a525450` = ASCII "ZRTP" magic cookie (RFC 6189). Followed by 2-byte length, 4-byte SSRC, then message type (e.g., `Hello   ` = `0x48656c6c6f202020`). |
| SIP INVITE | `0x494e5649544520736970` | ASCII for `INVITE sip` - call initiation request. Same structure as SIP REGISTER but different method verb. |
| WebRTC bundle | STUN + DTLS + RTP | Not a single protocol - a multiplexed sequence. Real WebRTC starts with STUN Binding (connectivity check), then DTLS handshake (key exchange), then SRTP media. Use i1=STUN, i2=DTLS, i3=RTP to mimic this exact sequence. First byte distinguishes: `0x00`-`0x03` = STUN, `0x14`-`0x19` = DTLS, `0x80`-`0xFF` = RTP/RTCP. |
| Steam A2S | `0xffffffff54` | `0xffffffff` = single-packet header (-1 as int32), `0x54` = 'T' byte (A2S_INFO request type). Followed by null-terminated string "Source Engine Query". All Valve Source games (CS2, Dota 2, TF2, Rust, etc.) respond to this. |
| ENet | `0xffff0000...0c02` | First 2 bytes = peerID (`0xffff` for connect). Next 2 bytes = sent time. Then command header: `0x0c` = CONNECT command (reliable + needs ack flags). `0x02` = channel. Followed by seq number, data, MTU, window size, etc. |
| BT UDP Tracker | `0x0000041727101980` | 8-byte magic constant (BEP 15). Every BitTorrent UDP tracker connect starts with this. Followed by 4-byte action (`0x00000000` = connect) and 4-byte random transaction ID. |
| BT DHT (KRPC) | `0x64313a61` | ASCII for `d1:a` - start of a bencoded dictionary. All DHT queries are bencoded dicts starting with `d`. A ping query is `d1:ad2:id20:<20 random bytes>e1:q4:ping1:t2:<2 bytes>1:y1:qe`. |
| uTP | `0x41` | First byte = (type << 4) OR version. `0x41` = ST_SYN (type=4) + version 1. uTP SYN initiates a connection. Followed by extension byte, connection ID, timestamp, timestamp diff, window size, seq number. |

### Ready-to-Use Configuration Sets

Nine complete parameter sets. All H ranges are non-overlapping within each set. Copy as-is for both client and server.

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

| Parameter | Set D: SRT (live streaming) | Set E: MPEG-TS (IPTV) |
|-----------|---------------------------|----------------------|
| Jc | 4 | 3 |
| Jmin | 60 | 100 |
| Jmax | 600 | 1000 |
| S1 | 72 | 80 |
| S2 | 130 | 140 |
| S3 | 28 | 20 |
| S4 | 16 | 20 |
| H1 | 1500000000-1500000300 | 2000000000-2000000200 |
| H2 | 1600000000-1600000300 | 2100000000-2100000200 |
| H3 | 1700000000-1700000010 | 2200000000-2200000010 |
| H4 | 1800000000-1900000000 | 2300000000-2400000000 |
| i1 | `<b 0x80000000><r 4><t><b 0x00000000><b 0x00000004><r 4><r 100>` | `<b 0x471fff10><r 184><b 0x471fff10><r 184><b 0x471fff10><r 184>` |
| i2 | `<b 0x80000000><r 4><t><b 0x00000000><b 0x00000005><r 4><r 80>` | |
| i3 | | |
| i4 | | |
| i5 | | |
| Server port | 9000 or 9001 | 1234 or 5000 |

| Parameter | Set F: WebRTC video call (best stealth) | Set G: VoIP / SIP call |
|-----------|----------------------------------------|----------------------|
| Jc | 5 | 4 |
| Jmin | 50 | 40 |
| Jmax | 600 | 400 |
| S1 | 64 | 52 |
| S2 | 140 | 110 |
| S3 | 30 | 20 |
| S4 | 12 | 8 |
| H1 | 2500000000-2500000400 | 2800000000-2800000300 |
| H2 | 2600000000-2600000400 | 2900000000-2900000300 |
| H3 | 2700000000-2700000010 | 3000000000-3000000010 |
| H4 | 3100000000-3200000000 | 3300000000-3400000000 |
| i1 | `<b 0x000100002112a442><r 12><r 50>` | `<b 0x494e5649544520736970><rc 12><b 0x3a><rd 4><b 0x20534950><r 80>` |
| i2 | `<b 0x16fefd0000000000000000><r 2><b 0x01><r 3><b 0xfefd><r 32><b 0x00><rc 4><r 100>` | `<b 0x80ef><r 2><t><r 4><r 80>` |
| i3 | `<b 0x80e0><r 2><t><r 4><r 200>` | `<b 0x80c8><r 2><r 4><r 40>` |
| i4 | | |
| i5 | | |
| Server port | 443 or 3478 | 5060 |

| Parameter | Set H: BitTorrent (P2P cover) | Set I: Gaming (Steam/ENet) |
|-----------|------------------------------|---------------------------|
| Jc | 4 | 5 |
| Jmin | 50 | 40 |
| Jmax | 800 | 600 |
| S1 | 60 | 52 |
| S2 | 120 | 100 |
| S3 | 24 | 20 |
| S4 | 10 | 8 |
| H1 | 3500000000-3500000400 | 3700000000-3700000500 |
| H2 | 3550000000-3550000400 | 3800000000-3800000500 |
| H3 | 3600000000-3600000010 | 3900000000-3900000010 |
| H4 | 3650000000-3750000000 | 4000000000-4100000000 |
| i1 | `<b 0x0000041727101980><b 0x00000000><r 4><r 50>` | `<b 0xffffffff54536f7572636520456e67696e6520517565727900><r 50>` |
| i2 | `<b 0x41000000><r 2><t><r 4><r 4><r 2><r 50>` | `<b 0xffff0000><t><b 0x0c><b 0x02><r 2><b 0x00><r 1><r 2><r 2><b 0xffff><r 4><r 4><r 100>` |
| i3 | | |
| i4 | | |
| i5 | | |
| Server port | 6881 or 1337 | 27015 or 7777 |

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