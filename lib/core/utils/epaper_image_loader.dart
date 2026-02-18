import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

class EpaperImageLoader {
  /// Load an image file from assets as raw bytes.
  static Future<Uint8List> loadAssetImage(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }
}
