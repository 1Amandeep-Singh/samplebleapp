import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleCharacteristics {
  static final espaperUuid = Uuid.parse("6b12ff00-4413-49c1-a307-74997b8b5941");

  static final connectionServiceUuid = Uuid.parse("7b12ff00-4413-49c1-a307-74997b8b5941");
  // Example characteristic UUIDs
  static final clearScreenUuid = Uuid.parse("7b12ff12-4413-49c1-a307-74997b8b5941");

  static final statusChar      = Uuid.parse("0000ffe2-0000-1000-8000-00805f9b34fb");
  static final basicInfoChar   = Uuid.parse("7b12ff01-4413-49c1-a307-74997b8b5941");
}