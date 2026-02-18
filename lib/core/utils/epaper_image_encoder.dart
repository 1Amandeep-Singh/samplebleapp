import 'dart:typed_data';
import 'package:image/image.dart' as img;

class EpaperImageEncoder {
  static const int width = 272;   // Corrected: 272×782 tri-color screen
  static const int height = 782;

  /// Encode image to tri-color format (black + red planes).
  /// Returns concatenated: [blackPlane (27 KB) + redPlane (27 KB)] = 54 KB total
  static Uint8List encodeTriColor(Uint8List pngBytes) {
    final img.Image? input = img.decodeImage(pngBytes);
    if (input == null) {
      throw Exception('Failed to decode image');
    }

    final img.Image resized = img.copyResize(
      input,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );

    const int totalPixels = width * height;
    final int bytesPerPlane = (totalPixels / 8).ceil();
    
    final Uint8List blackPlane = Uint8List(bytesPerPlane);
    final Uint8List redPlane = Uint8List(bytesPerPlane);

    int bitIndex = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final img.Pixel pixel = resized.getPixel(x, y);

        final int r = pixel.r.toInt();
        final int g = pixel.g.toInt();
        final int b = pixel.b.toInt();

        // Detect color of pixel
        // Black: low luminance
        // Red: high R, low G, low B
        // White: high luminance

        final int luminance = ((r * 299) + (g * 587) + (b * 114)) ~/ 1000;
        final bool isBlack = luminance < 85;  // Dark pixels → black
        final bool isRed = r > 150 && g < 100 && b < 100;  // Red-ish pixels → red

        final int byteIndex = bitIndex >> 3;
        final int bitPos = 7 - (bitIndex & 0x7);

        // Set black plane if pixel is black
        if (isBlack) {
          blackPlane[byteIndex] |= (1 << bitPos);
        }

        // Set red plane if pixel is red
        if (isRed) {
          redPlane[byteIndex] |= (1 << bitPos);
        }

        bitIndex++;
      }
    }

    // Concatenate: black plane first, then red plane
    final Uint8List result = Uint8List(bytesPerPlane * 2);
    result.setRange(0, bytesPerPlane, blackPlane);
    result.setRange(bytesPerPlane, bytesPerPlane * 2, redPlane);
    
    return result;
  }

  /// Legacy single-plane encoder (kept for reference)
  @Deprecated('Use encodeTriColor instead')
  static Uint8List encodeBlackWhite(Uint8List pngBytes) {
    return encodeTriColor(pngBytes);
  }
}
