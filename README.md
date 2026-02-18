Electronic Nameplate BLE Protocol – Developer Notes
Target device: 5.79" 272×792 tri‑color BLE nameplate (Model A).

1. BLE Service and Characteristics
Communication Service
UUID: 7b12ff00-4413-49c1-a307-74997b8b5941
​

Characteristics (subset relevant to image display)
7b12ff01-4413-49c1-a307-74997b8b5941 – NOTIFY

Purpose: Return basic info (EPDA, MODE, OTP, etc.).
​

7b12ff02-4413-49c1-a307-74997b8b5941 – READ

Purpose: Get firmware version string (e.g. v2.4).
​

7b12ff03-4413-49c1-a307-74997b8b5941 – WRITE / WRITE_NO_RESPONSE

Purpose: File transfer (sub-packets of display content).

Used for image upload and other large file scenarios.
​

7b12ff04-4413-49c1-a307-74997b8b5941 – NOTIFY

Purpose: File send result (1 byte):

1 – success

0 – failure

10 – image data too large
​

7b12ff10-4413-49c1-a307-74997b8b5941 – WRITE / READ

Purpose: Notify that file has been sent and poll processing result.

READ return values:

1 – success

0 – failure

2 – continue querying

10 – image data too large
​

7b12ff13-4413-49c1-a307-74997b8b5941 – WRITE

Purpose: Clear screen display.

Command: 0x0C.
​

Other UUIDs (05–09, 11, 12, 14) handle AES keys, pre-stored content, power mode, and firmware update. They are not strictly required for a basic unencrypted image push.
​

2. Broadcast Format and Size Type
During BLE advertising, the device name uses a fixed ASCII‑encoded format:
​

Fields: vendor ID, screen size type, MAC, battery level, firmware version, board info, power/charge flags, legality flag.

For screen size type (Model A):

. → 272×792 3‑color screen (Model A).
​

You can use this to identify your 272×792 tri‑color panel among other sizes.

3. File Transfer Protocol (Image Upload)
Used for “large file” operations such as pushing an image. Data is sent in packets to 7b12ff03.
​

3.1 Packet Overview
First packet (index 0) is a file header.

Packets 1..N carry actual file data.

The device concatenates data from packets 1..N into one file.
​

3.2 First Packet (Header) Layout
Bytes (positions) and meanings:
​

Byte 0 – Operation type

0x00 – Regular image submission.

0x01 – Pre‑save projection (pre‑store content).
​

Byte 1 – Screen-flooding type

0x00 – Side A content.

0x01 – Side B content.

0x02 – Sides A & B, same content.

0x03 – Sides A & B, content differs on side A.

0x04 – Sides A & B, content differs on side B.

0x05 – Pre‑store + refresh to side A.

0x06 – Pre‑store + refresh to side B.

0x07 – Pre‑store + refresh to sides A & B.
​

Bytes 2–5 – Number of data packets (UInt32, big‑endian; does not include the header packet).
​

Bytes 6–9 – File length before encryption (raw data length, UInt32).
​

Byte 10 – Encryption flag

0 – unencrypted

1 – encrypted
​

Byte 11 – Compression flag

0 – uncompressed

1 – compressed
​

Byte 12 – Meeting room ID (ASCII‑compatible value).

Byte 13 – Group ID (ASCII‑compatible value).
​

For a simple start, you can set:
Operation = 0x00 (regular), Flooding = 0x00 (side A), Encryption = 0, Compression = 0, Meeting room/Group = 0.

3.3 Data Packets 1..N
Each subsequent packet carries a segment of the file payload.
​

No explicit per-packet header is defined in the excerpt; the receiver relies on:

Packet index/order.

Total packet count (from bytes 2–5 in the header).

Total file length (bytes 6–9).
​

Application-level responsibilities:

Choose a per-packet payload size that fits your BLE MTU (e.g. 200 bytes).

Compute:

packetCount = ceil(fileLength / payloadSize).

Fill header bytes 2–5 with packetCount.

Send packets in order: header → packet 1 → packet 2 → ... → packet N.

4. File Send Completion and Result Handling
Because notification packets may be lost, the protocol defines an explicit completion and polling mechanism.
​

7b12ff04 (NOTIFY): file send result (1 byte)

1 – send success

0 – failure

10 – image too large
​

7b12ff10 (WRITE/READ):

After sending all file packets, the app writes a special “end notification” to this characteristic to indicate file completion (exact end-operation code is not detailed, but this characteristic is explicitly for “notify file sent out successfully”).
​

Then the app periodically READs the same characteristic to poll processing result:

1 – success

0 – failure

2 – continue querying

10 – image too large
​

The recommended pattern:

Send all file packets to 7b12ff03.

Trigger completion using 7b12ff10 (per vendor’s exact end command).

Poll 7b12ff10 until you get 1 or an error code.

Optionally, watch 7b12ff04 notify as an extra send‑result signal.

5. Clear Screen and Other Controls
Clear screen: write 0x0C to 7b12ff13-4413-49c1-a307-74997b8b5941.
​

Power mode / basic info / burning private data: via 7b12ff14:

WRITE:

MODE+1(0) to switch high/low power.

EPDA to request basic info.

OTP+'F'+data to burn private data.

KEY to send AES decryption key.
​

READ:

Returns 0/1 for low/high power.
​

AES key/IV management:

7b12ff05 – send IV (plaintext).

7b12ff06 – notify IV from device.

7b12ff07 – send key (simple encrypted).

7b12ff08 – send AES key (16‑byte encrypted).
​

For initial development you can keep encryption and compression disabled (header bytes 10 and 11 = 0).

6. Basic Info (EPDA) Notifies
When the device sends basic info, it uses the EPDA header:
​

EPDA followed by bytes:

01 – major firmware version

02 – minor firmware version

03 – working mode (0: low power, 1: high)

04 – battery level

05 – screen ID (matches “screen size type” from broadcast)

06 – factory ID (e.g. T for TDX)

07 – screen driver IC (0: UC8279, 1: SSD1683, 2: JD79665)

08 – MCU IC (0: CH582, 1: CH583)
​

This is useful for diagnostics and confirming you’re connected to the expected panel type.

7. Implementation Notes for Your Flutter App
For your 5.79" 272×792 3‑color screen:

Identify panel:

Use broadcast name’s size type char (. for 272×792 3‑color Model A).
​

Prepare image file:

Encode your 792×272 tri‑color image into the panel’s expected raw format (likely two 1‑bit planes: black and color).

Concatenate into a single file buffer (per vendor format) and compute fileLength.

Build header packet (first packet):

Byte 0: 0x00 (regular image).

Byte 1: e.g. 0x00 (side A).

Bytes 2–5: packetCount (number of data packets).

Bytes 6–9: fileLength.

Byte 10: 0 (no encryption).

Byte 11: 0 (no compression).

Bytes 12–13: meeting room/group (can start with 0x00, 0x00).
​

Send header + data packets to 7b12ff03 using your sendChunkedData / SendRawImage.

Signal completion + poll result using 7b12ff10 until success or error, and optionally listen to 7b12ff04 for immediate send result.
​