// VideoWin-based video player implementation for Windows DASH streaming
import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:videowin/videowin.dart';
import 'video_player_platform_interface.dart';
import '../configuration/better_player_buffering_configuration.dart';

/// VideoWin implementation of [VideoPlayerPlatform] for Windows DASH streaming.
class VideoWinVideoPlayer extends VideoPlayerPlatform {
  final _controllers = HashMap<int, _VideoWinController>();
  final _streamControllers = HashMap<int, StreamController<VideoEvent>>();

  static int _nextTextureId = 1;

  /// Initializes the platform interface.
  @override
  Future<void> init() async {
    await DashStreamHelper.initialize();

    for (final textureId in _controllers.keys.toList()) {
      await dispose(textureId);
    }

    _controllers.clear();
    _streamControllers.clear();
  }

  /// Clears one video.
  @override
  Future<void> dispose(int? textureId) async {
    if (textureId == null) return;

    final controller = _controllers[textureId];
    if (controller != null) {
      await controller.dispose();
      _controllers.remove(textureId);
    }

    await _streamControllers[textureId]?.close();
    _streamControllers.remove(textureId);
  }

  /// Creates an instance of a video player and returns its textureId.
  @override
  Future<int?> create({BetterPlayerBufferingConfiguration? bufferingConfiguration}) async {
    final textureId = _nextTextureId++;
    final streamController = StreamController<VideoEvent>();
    final controller = _VideoWinController(textureId, streamController);

    _controllers[textureId] = controller;
    _streamControllers[textureId] = streamController;

    return textureId;
  }

  /// Set data source of video.
  @override
  Future<void> setDataSource(int? textureId, DataSource dataSource) async {
    if (textureId == null) return;

    final controller = _controllers[textureId];
    if (controller == null) return;

    await controller.setDataSource(dataSource);
  }

  /// Returns a Stream of [VideoEventType]s.
  @override
  Stream<VideoEvent> videoEventsFor(int? textureId) {
    if (textureId == null || _streamControllers[textureId] == null) {
      throw StateError(
          'VideoPlayer for textureId $textureId is not found, Check if its disposed.');
    }
    return _streamControllers[textureId]!.stream;
  }

  /// Sets the looping attribute of the video.
  @override
  Future<void> setLooping(int? textureId, bool looping) async {
    final controller = _controllers[textureId];
    if (controller == null) return;

    controller.setLooping(looping);
  }

  /// Starts the video playback.
  @override
  Future<void> play(int? textureId) async {
    final controller = _controllers[textureId];
    if (controller == null) return;

    await controller.play();
  }

  /// Stops the video playback.
  @override
  Future<void> pause(int? textureId) async {
    final controller = _controllers[textureId];
    if (controller == null) return;

    await controller.pause();
  }

  /// Sets the volume to a range between 0.0 and 1.0.
  @override
  Future<void> setVolume(int? textureId, double volume) async {
    final controller = _controllers[textureId];
    if (controller == null) return;

    await controller.setVolume(volume);
  }

  /// Sets the video speed to a range between 0.0 and 2.0
  @override
  Future<void> setSpeed(int? textureId, double speed) async {
    final controller = _controllers[textureId];
    if (controller == null) return;

    await controller.setSpeed(speed);
  }

  /// Sets the video track parameters (used to select quality of the video)
  @override
  Future<void> setTrackParameters(int? textureId, int? width, int? height, int? bitrate) async {
    // Track parameters are handled during DASH parsing
  }

  /// Sets the video position to a [Duration] from the start.
  @override
  Future<void> seekTo(int? textureId, Duration? position) async {
    if (position == null) return;
    
    final controller = _controllers[textureId];
    if (controller == null) return;

    await controller.seekTo(position);
  }

  /// Gets the video position as [Duration] from the start.
  @override
  Future<Duration> getPosition(int? textureId) async {
    final controller = _controllers[textureId];
    if (controller == null) return Duration.zero;

    return controller.getPosition();
  }

  /// Gets the video position as [DateTime].
  @override
  Future<DateTime?> getAbsolutePosition(int? textureId) async {
    // Not supported
    return null;
  }

  /// Pre-caches a video.
  @override
  Future<void> preCache(DataSource dataSource, int preCacheSize) async {
    // Pre-caching not supported
  }

  /// Pre-caches a video.
  @override
  Future<void> stopPreCache(String url, String? cacheKey) async {
    // Pre-caching not supported
  }

  /// Enables PiP mode.
  @override
  Future<void> enablePictureInPicture(int? textureId, double? top, double? left, double? width, double? height) async {
    // PiP not supported
  }

  /// Disables PiP mode.
  @override
  Future<void> disablePictureInPicture(int? textureId) async {
    // PiP not supported
  }

  @override
  Future<bool?> isPictureInPictureEnabled(int? textureId) async {
    return false;
  }

  @override
  Future<void> setAudioTrack(int? textureId, String? name, int? index) async {
    // Audio track selection handled by VideoWin
  }

  @override
  Future<void> setMixWithOthers(int? textureId, bool mixWithOthers) async {
    // Audio mixing handled by VideoWin
  }

  @override
  Future<void> clearCache() async {
    // Cache clearing not needed
  }

  /// Returns a widget displaying the video with a given textureId.
  @override
  Widget buildView(int? textureId) {
    if (textureId == null || _controllers[textureId] == null) {
      throw StateError(
          'VideoPlayer for textureId $textureId is not found, Check if its disposed.');
    }

    final controller = _controllers[textureId]!;
    return controller.buildView();
  }
}

/// Internal controller for managing VideoWin video/audio playback
class _VideoWinController {
  final int textureId;
  final StreamController<VideoEvent> eventStream;

  vp.VideoPlayerController? _videoController;
  vp.VideoPlayerController? _audioController;
  Timer? _syncTimer;
  bool _isLooping = false;
  bool _isInitialized = false;
  String? _currentUrl;
  bool _isDashStream = false;

  _VideoWinController(this.textureId, this.eventStream);

  bool get isInitialized => _isInitialized;
  
  Future<void> setDataSource(DataSource dataSource) async {
    try {
      if (dataSource.sourceType != DataSourceType.network) {
        throw UnsupportedError('VideoWin only supports network data sources');
      }

      _currentUrl = dataSource.uri;
      if (_currentUrl == null) {
        throw ArgumentError('URI must not be null for network data source');
      }

      // Check if this is a DASH stream by looking for .mpd extension or manifest indicators
      _isDashStream = _currentUrl!.contains('.mpd') || 
                     _currentUrl!.contains('manifest') ||
                     _currentUrl!.contains('dash');

      if (_isDashStream) {
        // Use VideoWin for DASH streaming
        await _initializeDashStream();
      } else {
        // Use regular video player for non-DASH content
        await _initializeRegularStream();
      }

    } catch (e) {
      _dispatchError(PlatformException(
        code: 'VIDEOWIN_ERROR',
        message: 'Failed to set data source: $e',
      ));
    }
  }

  Future<void> _initializeDashStream() async {
    try {
      final result = await DashStreamHelper.playDashStream(
        manifestUrl: _currentUrl!,
        targetResolution: 720,
        includeAudio: true,
      );

      if (result.hasError) {
        throw Exception(result.error);
      }

      _videoController = result.videoController;
      _audioController = result.audioController;

      // Set up event listeners for video controller
      if (_videoController != null) {
        _videoController!.addListener(_onVideoControllerChange);
      }

      // Set up event listeners for audio controller
      if (_audioController != null) {
        _audioController!.addListener(_onAudioControllerChange);
      }

      // Start synchronization if dual playback
      if (result.isDualPlayback && _videoController != null && _audioController != null) {
        _syncTimer = DashStreamHelper.startSyncMonitoring(
          _videoController!,
          _audioController!,
        );
      }

      _isInitialized = true;
      
      // Wait for video controller to be fully initialized
      if (_videoController != null && !_videoController!.value.isInitialized) {
        await _videoController!.initialize();
      }

      _dispatchInitialized();

    } catch (e) {
      throw Exception('Failed to initialize DASH stream: $e');
    }
  }

  Future<void> _initializeRegularStream() async {
    try {
      _videoController = vp.VideoPlayerController.networkUrl(Uri.parse(_currentUrl!));
      await _videoController!.initialize();

      _videoController!.addListener(_onVideoControllerChange);
      
      _isInitialized = true;
      _dispatchInitialized();

    } catch (e) {
      throw Exception('Failed to initialize regular stream: $e');
    }
  }

  void _onVideoControllerChange() {
    if (_videoController == null) return;

    final value = _videoController!.value;
    
    if (value.hasError) {
      _dispatchError(PlatformException(
        code: 'VIDEOWIN_ERROR',
        message: value.errorDescription ?? 'Unknown video error',
      ));
      return;
    }

    // Handle play/pause events
    if (value.isPlaying) {
      _dispatchEvent(VideoEvent(
        eventType: VideoEventType.play,
        key: textureId.toString(),
      ));
    } else {
      _dispatchEvent(VideoEvent(
        eventType: VideoEventType.pause,
        key: textureId.toString(),
      ));
    }

    // Handle completion
    if (value.position >= value.duration && value.duration > Duration.zero) {
      _dispatchEvent(VideoEvent(
        eventType: VideoEventType.completed,
        key: textureId.toString(),
      ));
    }

    // Handle buffering
    if (value.isBuffering) {
      _dispatchEvent(VideoEvent(
        eventType: VideoEventType.bufferingStart,
        key: textureId.toString(),
      ));
    } else {
      _dispatchEvent(VideoEvent(
        eventType: VideoEventType.bufferingEnd,
        key: textureId.toString(),
      ));
    }
  }

  void _onAudioControllerChange() {
    // Audio controller changes are handled through video controller
    // This method is here for potential future use
  }

  void _dispatchInitialized() {
    if (_videoController == null) return;

    final value = _videoController!.value;
    final size = value.size;
    final duration = value.duration;

    _dispatchEvent(VideoEvent(
      eventType: VideoEventType.initialized,
      key: textureId.toString(),
      size: size,
      duration: duration,
      isLiveStream: duration == Duration.zero,
    ));
  }

  void _dispatchEvent(VideoEvent event) {
    if (!eventStream.isClosed) {
      eventStream.add(event);
    }
  }

  void _dispatchError(PlatformException error) {
    if (!eventStream.isClosed) {
      eventStream.addError(error);
    }
  }

  void setLooping(bool looping) {
    _isLooping = looping;
    _videoController?.setLooping(looping);
    _audioController?.setLooping(looping);
  }

  Future<void> play() async {
    if (_videoController != null) {
      await _videoController!.play();
    }
    
    if (_audioController != null) {
      await _audioController!.play();
      
      // Synchronize playback if both controllers exist
      if (_videoController != null) {
        await DashStreamHelper.synchronizePlayback(
          _videoController!,
          _audioController!,
        );
      }
    }
  }

  Future<void> pause() async {
    await _videoController?.pause();
    await _audioController?.pause();
  }

  Future<void> setVolume(double volume) async {
    await _videoController?.setVolume(volume);
    await _audioController?.setVolume(volume);
  }

  Future<void> setSpeed(double speed) async {
    await _videoController?.setPlaybackSpeed(speed);
    await _audioController?.setPlaybackSpeed(speed);
  }

  Future<void> seekTo(Duration position) async {
    await _videoController?.seekTo(position);
    
    if (_audioController != null) {
      await _audioController!.seekTo(position);
      
      // Re-synchronize after seeking
      if (_videoController != null) {
        await DashStreamHelper.synchronizePlayback(
          _videoController!,
          _audioController!,
        );
      }
    }
  }

  Duration getPosition() {
    return _videoController?.value.position ?? Duration.zero;
  }

  Widget buildView() {
    if (!_isInitialized || _videoController == null || !_videoController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: vp.VideoPlayer(_videoController!),
    );
  }

  Future<void> dispose() async {
    _syncTimer?.cancel();
    
    if (_videoController != null) {
      _videoController!.removeListener(_onVideoControllerChange);
      await _videoController!.dispose();
    }
    
    if (_audioController != null) {
      _audioController!.removeListener(_onAudioControllerChange);
      await _audioController!.dispose();
    }
  }
}