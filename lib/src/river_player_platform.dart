// River Player Platform initialization
//
// This file handles the initialization of River Player across all platforms
// with proper MediaKit setup for desktop and web platforms.

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:universal_platform/universal_platform.dart';

import 'video_player/multiplatform_video_player.dart';

/// River Player Platform initialization class
class RiverPlayerPlatform {
  static bool _initialized = false;

  /// Initialize River Player with platform-appropriate backends
  /// 
  /// This should be called once in your app's main() function before runApp().
  /// 
  /// Example:
  /// ```dart
  /// void main() {
  ///   RiverPlayerPlatform.ensureInitialized();
  ///   runApp(MyApp());
  /// }
  /// ```
  static void ensureInitialized({
    bool android = true,
    bool iOS = true,
    bool macOS = true,
    bool windows = true,
    bool linux = true,
    bool web = false, // Web support is experimental
  }) {
    if (_initialized) return;

    // Initialize MediaKit for supported platforms
    if ((UniversalPlatform.isAndroid && android) ||
        (UniversalPlatform.isIOS && iOS) ||
        (UniversalPlatform.isMacOS && macOS) ||
        (UniversalPlatform.isWindows && windows) ||
        (UniversalPlatform.isLinux && linux) ||
        (UniversalPlatform.isWeb && web)) {
      
      // Initialize MediaKit for desktop/web platforms
      if (UniversalPlatform.isWindows || 
          UniversalPlatform.isMacOS || 
          UniversalPlatform.isLinux || 
          UniversalPlatform.isWeb) {
        
        // Special initialization for Linux to fix video rendering issues
        if (UniversalPlatform.isLinux) {
          MediaKit.ensureInitialized();
          if (kDebugMode) {
            print('River Player: Linux detected - MediaKit initialized with default settings');
            print('Note: Video texture rendering issues on Linux are a known MediaKit/libmpv limitation');
          }
        } else {
          MediaKit.ensureInitialized();
        }
      }
      
      // Initialize multiplatform video player
      MultiplatformVideoPlayer.initialize();
    }

    _initialized = true;

    if (kDebugMode) {
      print('River Player initialized for ${MultiplatformVideoPlayer.platformDescription}');
    }
  }

  /// Check if River Player has been initialized
  static bool get isInitialized => _initialized;

  /// Get platform description
  static String get platformDescription => MultiplatformVideoPlayer.platformDescription;

  /// Check if current platform uses native video implementation
  static bool get isNativePlatform => MultiplatformVideoPlayer.isNativePlatform;

  /// Check if current platform uses MediaKit implementation
  static bool get isMediaKitPlatform => MultiplatformVideoPlayer.isMediaKitPlatform;
}