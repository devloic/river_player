// Web plugin registration file for river_player
// This file is required for web platform support

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web implementation of RiverPlayerPlugin
class RiverPlayerPlugin {
  /// Registers this plugin with the Flutter web plugin system
  static void registerWith(Registrar registrar) {
    // For web platform, MediaKit handles the video playback
    // No additional plugin registration needed as MediaKit already provides web support
  }
}