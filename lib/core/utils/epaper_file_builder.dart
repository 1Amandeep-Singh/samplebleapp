import 'dart:typed_data';

class EpaperFileBuilder {
  /// Build file-transfer packets (first header packet + N data packets)
  /// ready to send to 0x7b12ff03.
  static List<Uint8List> buildPackets(Uint8List fileData) {
    const int payloadSize = 200; // bytes per data packet (tune later)

    final int fileLength = fileData.length;
    final int packetCount =
        (fileLength / payloadSize).ceil(); // number of data packets

    // ---- Build first packet (header) ----
    final header = Uint8List(14);
    final b = header.buffer.asByteData();

    // 0: operation type
    b.setUint8(0, 0x00); // regular image submission

    // 1: screen-flooding type
    b.setUint8(1, 0x00); // A side

    // 2-5: number of packets (exclude this header)
    b.setUint32(2, packetCount, Endian.big);

    // 6-9: length of data before encryption
    b.setUint32(6, fileLength, Endian.big);

    // 10: encrypt? (0 = no)
    b.setUint8(10, 0);

    // 11: compress? (0 = no, 1 = yes)
    // NOTE: Set to 0 because we are NOT compressing the data
    b.setUint8(11, 0);

    // 12: meeting room (0 for now)
    b.setUint8(12, 0);

    // 13: group (0 for now)
    b.setUint8(13, 0);

    // ---- Build data packets 1..N ----
    final packets = <Uint8List>[header];
    int offset = 0;
    while (offset < fileLength) {
      final end = (offset + payloadSize).clamp(0, fileLength);
      packets.add(fileData.sublist(offset, end));
      offset = end;
    }

    return packets;
  }
}
