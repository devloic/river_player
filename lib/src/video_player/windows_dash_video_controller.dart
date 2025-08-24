// Windows DASH video controller using VideoWin
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:videowin/videowin.dart';
import 'package:universal_platform/universal_platform.dart';
import '../configuration/better_player_buffering_configuration.dart';
import 'video_player.dart' as river;

/// A video controller specifically for Windows DASH streaming using VideoWin
class WindowsDashVideoController extends river.VideoPlayerController {
  vp.VideoPlayerController? _videoController;
  vp.VideoPlayerController? _audioController;
  Timer? _syncTimer;
  bool _isDualPlayback = false;
  
  WindowsDashVideoController({
    BetterPlayerBufferingConfiguration? bufferingConfiguration,
  }) : super(
          bufferingConfiguration:
              bufferingConfiguration ?? const BetterPlayerBufferingConfiguration(),
        );

  /// Sets up DASH streaming with the given manifest URL
  Future<void> setupDashStream(String manifestUrl, {
    int targetResolution = 720,
    bool includeAudio = true,
  }) async {
    try {
      // Initialize VideoWin DASH helper
      await DashStreamHelper.initialize();

      // Parse DASH manifest and get video/audio controllers
      final result = await DashStreamHelper.playDashStream(
        manifestUrl: manifestUrl,
        targetResolution: targetResolution,
        includeAudio: includeAudio,
      );

      if (result.hasError) {
        throw Exception(result.error);
      }

      _videoController = result.videoController;
      _audioController = result.audioController;
      _isDualPlayback = result.isDualPlayback;

      // Set up event listeners
      if (_videoController != null) {
        _videoController!.addListener(_onControllerUpdate);
        
        // Wait for initialization
        if (!_videoController!.value.isInitialized) {
          await _videoController!.initialize();
        }
      }

      if (_audioController != null) {
        _audioController!.addListener(_onControllerUpdate);
        
        if (!_audioController!.value.isInitialized) {
          await _audioController!.initialize();
        }
      }

      // Start sync monitoring if needed
      if (_isDualPlayback && _videoController != null && _audioController != null) {
        _syncTimer = DashStreamHelper.startSyncMonitoring(
          _videoController!,
          _audioController!,
        );
      }

      // Update our value to match the video controller
      if (_videoController != null) {
        // Use a simple approach - just mark as initialized
        // The actual video display will be handled by the widget
      }

    } catch (e) {
      // Handle error by throwing, will be caught by caller
      rethrow;
    }
  }

  void _onControllerUpdate() {
    // Controller updates will be handled by listeners in the widget
  }

  @override
  Future<void> play() async {
    if (_videoController != null) {
      await _videoController!.play();
    }
    
    if (_audioController != null) {
      await _audioController!.play();
      
      // Synchronize after play if dual playback
      if (_videoController != null) {
        await DashStreamHelper.synchronizePlayback(
          _videoController!,
          _audioController!,
        );
      }
    }
  }

  @override
  Future<void> pause() async {
    await _videoController?.pause();
    await _audioController?.pause();
  }

  @override
  Future<void> seekTo(Duration? position) async {
    if (position == null) return;
    
    await _videoController?.seekTo(position);
    
    if (_audioController != null) {
      await _audioController!.seekTo(position);
      
      // Re-synchronize after seeking if dual playback
      if (_videoController != null) {
        await DashStreamHelper.synchronizePlayback(
          _videoController!,
          _audioController!,
        );
      }
    }
  }

  @override
  Future<void> setLooping(bool looping) async {
    await _videoController?.setLooping(looping);
    await _audioController?.setLooping(looping);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _videoController?.setVolume(volume);
    await _audioController?.setVolume(volume);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _videoController?.setPlaybackSpeed(speed);
    await _audioController?.setPlaybackSpeed(speed);
  }

  @override
  Future<Duration?> get position async {
    return _videoController?.value.position ?? Duration.zero;
  }

  @override
  Future<void> dispose() async {
    _syncTimer?.cancel();
    
    if (_videoController != null) {
      _videoController!.removeListener(_onControllerUpdate);
      await _videoController!.dispose();
    }
    
    if (_audioController != null) {
      _audioController!.removeListener(_onControllerUpdate);
      await _audioController!.dispose();
    }
    
    await super.dispose();
  }

  /// Get the video controller for building the video widget
  vp.VideoPlayerController? get videoController => _videoController;

  /// Check if this is a dual playback setup
  bool get isDualPlayback => _isDualPlayback;

  /// Factory method to create a Windows DASH controller from a URL
  static WindowsDashVideoController fromUrl(String url) {
    return WindowsDashVideoController();
  }

  /// Determines if a URL is likely a DASH stream
  static bool isDashUrl(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.mpd') || 
           lowerUrl.contains('manifest') && lowerUrl.contains('dash');
  }
}

/// Widget that displays a Windows DASH video
class WindowsDashVideoPlayer extends StatefulWidget {
  final WindowsDashVideoController controller;
  
  const WindowsDashVideoPlayer({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  _WindowsDashVideoPlayerState createState() => _WindowsDashVideoPlayerState();
}

class _WindowsDashVideoPlayerState extends State<WindowsDashVideoPlayer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final videoController = controller.videoController;
    
    if (videoController == null || !videoController.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (videoController.value.hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Error: ${videoController.value.errorDescription}',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: videoController.value.aspectRatio,
      child: vp.VideoPlayer(videoController),
    );
  }
}