// Multiplatform video player implementation for River Player
//
// This file provides a unified interface for video playback across all platforms
// using platform-appropriate implementations:
// - Android/iOS: Native implementation via method channels
// - Desktop/Web: MediaKit implementation

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:universal_platform/universal_platform.dart';

import 'video_player_platform_interface.dart';
import 'method_channel_video_player.dart';
import 'media_kit_video_player.dart';

/// Multiplatform video player that automatically chooses the appropriate
/// implementation based on the current platform.
class MultiplatformVideoPlayer {
  
  /// Initializes the appropriate video player implementation for the current platform
  static void initialize() {
    // Initialize MediaKit for desktop/web platforms
    if (UniversalPlatform.isWindows || 
        UniversalPlatform.isMacOS || 
        UniversalPlatform.isLinux || 
        UniversalPlatform.isWeb) {
      MediaKitVideoPlayer.ensureInitialized();
    }
  }

  /// Gets the platform-appropriate video player implementation
  static VideoPlayerPlatform get instance => VideoPlayerPlatform.instance;

  /// Returns true if the current platform supports native video playback
  static bool get isNativePlatform => 
      UniversalPlatform.isAndroid || UniversalPlatform.isIOS;

  /// Returns true if the current platform uses MediaKit for video playback
  static bool get isMediaKitPlatform => 
      UniversalPlatform.isWindows || 
      UniversalPlatform.isMacOS || 
      UniversalPlatform.isLinux || 
      UniversalPlatform.isWeb;

  /// Returns a string description of the current platform's video implementation
  static String get platformDescription {
    if (isNativePlatform) {
      return 'Native (${UniversalPlatform.operatingSystem})';
    } else if (isMediaKitPlatform) {
      return 'MediaKit (${UniversalPlatform.operatingSystem})';
    } else {
      return 'Unknown platform (${UniversalPlatform.operatingSystem})';
    }
  }
}