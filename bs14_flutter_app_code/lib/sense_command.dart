import 'package:flutter/foundation.dart';

class SenseCommand {
  // Returns the command packet to send to Arduino for sense selection
  static List<int> getSensePacket(String sense) {
    // Arduino expects: 0 for Sense A, 1 for Sense B
    return [sense == 'A' ? 0 : 1];
  }
}
