import 'dart:typed_data';
import 'package:image/image.dart' as img;

// Change these if your encoder uses different logical size
const int epaperWidth  = 272;  // Width (corrected)
const int epaperHeight = 782;  // Height (corrected)

/// Creates a white image with black "HELLO" text.
Uint8List createHelloTextImage() {
  // 1) Create blank image
  final image = img.Image(width: epaperWidth, height: epaperHeight, paletteFormat: img.Format.uint8);

  // 2) Fill background white
  img.fill(image, color: img.ColorRgb8(255, 255, 255)); // Red channel at 255 means white in our encoder

  // 3) Draw HELLO in black using built‑ins font
  img.drawString(
    image,
    'HELLO',
    x: 50,
    y: 100,
    font: img.arial48,
    color: img.ColorRgb8(0, 0, 0),
  ); 

  // 4) Encode to PNG bytes
  return Uint8List.fromList(img.encodePng(image));
}
