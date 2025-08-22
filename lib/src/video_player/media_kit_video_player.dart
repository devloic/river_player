// MediaKit-based video player implementation for desktop and web platforms
import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:river_player/src/configuration/better_player_buffering_configuration.dart';
import 'video_player_platform_interface.dart';

// https://github.com/dart-lang/linter/issues/1381
// ignore_for_file: close_sinks

/// MediaKit implementation of [VideoPlayerPlatform] for desktop and web platforms.
class MediaKitVideoPlayer extends VideoPlayerPlatform {
  // The implementation uses [Player.hashCode] as texture ID.
  final _players = HashMap<int, Player>();
  final _completers = HashMap<int, Completer<void>>();
  final _videoControllers = HashMap<int, VideoController>();
  final _streamControllers = HashMap<int, StreamController<VideoEvent>>();
  final _streamSubscriptions = HashMap<int, List<StreamSubscription>>();
  final _debounceTimers = HashMap<int, Timer>(); // Track debounce timers for cleanup

  /// Initializes MediaKit
  static void ensureInitialized() {
    MediaKit.ensureInitialized();
  }

  /// Initializes the platform interface and disposes all existing players.
  ///
  /// This method is called when the plugin is first initialized and on every full restart.
  @override
  Future<void> init() async {
    // Ensure MediaKit is initialized
    ensureInitialized();
    
    for (final textureId in _players.keys) {
      await dispose(textureId);
    }

    _players.clear();
    _videoControllers.clear();
    _streamControllers.clear();
    _streamSubscriptions.clear();
    _debounceTimers.clear();
  }

  /// Clears one video.
  @override
  Future<void> dispose(int? textureId) async {
    if (textureId == null) return;
    
    await _players[textureId]?.dispose();

    // Cancel debounce timer if exists
    _debounceTimers[textureId]?.cancel();

    await _streamControllers[textureId]?.close();
    await Future.wait(
      _streamSubscriptions[textureId]?.map((e) => e.cancel()) ?? [],
    );

    _players.remove(textureId);
    _videoControllers.remove(textureId);
    _streamControllers.remove(textureId);
    _streamSubscriptions.remove(textureId);
    _debounceTimers.remove(textureId);
  }

  /// Creates an instance of a video player and returns its textureId.
  @override
  Future<int?> create({BetterPlayerBufferingConfiguration? bufferingConfiguration}) async {
    // Configure MediaKit Player with better debugging and thread safety
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'River Player',
        logLevel: MPVLogLevel.info,
      ),
    );
    final completer = Completer();
    final videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: false, // Fix for Linux video rendering
        // Additional thread safety options
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );
    // NOTE: [StreamController] without broadcast buffers events.
    final streamController = StreamController<VideoEvent>();
    final streamSubscriptions = <StreamSubscription>[];

    final textureId = player.hashCode;

    _players[textureId] = player;
    _completers[textureId] = completer;
    _videoControllers[textureId] = videoController;
    _streamControllers[textureId] = streamController;
    _streamSubscriptions[textureId] = streamSubscriptions;

    // Initialize the streams
    _initialize(textureId);

    return textureId;
  }

  /// Set data source of video.
  @override
  Future<void> setDataSource(int? textureId, DataSource dataSource) async {
    if (textureId == null) return;
    
    final player = _players[textureId];
    if (player == null) return;

    final String resource;
    final Map<String, String> httpHeaders = dataSource.headers?.cast<String, String>() ?? {};

    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        final String? asset;
        if (dataSource.package == null) {
          asset = dataSource.asset;
        } else {
          asset = 'packages/${dataSource.package}/${dataSource.asset}';
        }
        resource = 'asset:///$asset';
        break;

      case DataSourceType.network:
      case DataSourceType.file:
        if (dataSource.uri == null) {
          throw ArgumentError('uri must not be null');
        }
        resource = dataSource.uri!;
        break;

      default:
        throw UnsupportedError('${dataSource.sourceType} is not supported');
    }

    await player.open(
      Media(
        resource,
        httpHeaders: httpHeaders,
      ),
      play: false,
    );
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
    final playlistMode = looping ? PlaylistMode.single : PlaylistMode.none;
    return _players[textureId]?.setPlaylistMode(playlistMode);
  }

  /// Starts the video playback.
  @override
  Future<void> play(int? textureId) async {
    return _players[textureId]?.play();
  }

  /// Stops the video playback.
  @override
  Future<void> pause(int? textureId) async {
    return _players[textureId]?.pause();
  }

  /// Sets the volume to a range between 0.0 and 1.0.
  @override
  Future<void> setVolume(int? textureId, double volume) async {
    // NOTE: [volume] is in the range of 0.0 to 1.0 while [setVolume] expects 0.0 to 100.
    return _players[textureId]?.setVolume(volume * 100);
  }

  /// Sets the video speed to a range between 0.0 and 2.0
  @override
  Future<void> setSpeed(int? textureId, double speed) async {
    return _players[textureId]?.setRate(speed);
  }

  /// Sets the video track parameters (used to select quality of the video)
  @override
  Future<void> setTrackParameters(int? textureId, int? width, int? height, int? bitrate) async {
    // MediaKit handles track selection automatically
    // This is a placeholder implementation
  }

  /// Sets the video position to a [Duration] from the start.
  @override
  Future<void> seekTo(int? textureId, Duration? position) async {
    if (position == null) return;
    return _players[textureId]?.seek(position);
  }

  /// Gets the video position as [Duration] from the start.
  @override
  Future<Duration> getPosition(int? textureId) async {
    return _players[textureId]?.state.position ?? Duration.zero;
  }

  /// Gets the video position as [DateTime].
  @override
  Future<DateTime?> getAbsolutePosition(int? textureId) async {
    // Not supported by MediaKit, return null
    return null;
  }

  /// Pre-caches a video.
  @override
  Future<void> preCache(DataSource dataSource, int preCacheSize) async {
    // Pre-caching not supported in MediaKit
  }

  /// Pre-caches a video.
  @override
  Future<void> stopPreCache(String url, String? cacheKey) async {
    // Pre-caching not supported in MediaKit
  }

  /// Enables PiP mode.
  @override
  Future<void> enablePictureInPicture(int? textureId, double? top, double? left, double? width, double? height) async {
    // PiP not supported on desktop/web
  }

  /// Disables PiP mode.
  @override
  Future<void> disablePictureInPicture(int? textureId) async {
    // PiP not supported on desktop/web
  }

  @override
  Future<bool?> isPictureInPictureEnabled(int? textureId) async {
    // PiP not supported on desktop/web
    return false;
  }

  @override
  Future<void> setAudioTrack(int? textureId, String? name, int? index) async {
    // Audio track selection handled by MediaKit
  }

  @override
  Future<void> setMixWithOthers(int? textureId, bool mixWithOthers) async {
    // Audio mixing handled by MediaKit
  }

  @override
  Future<void> clearCache() async {
    // Cache clearing not needed for MediaKit
  }

  /// Returns a widget displaying the video with a given textureId.
  @override
  Widget buildView(int? textureId) {
    if (textureId == null || _videoControllers[textureId] == null) {
      throw StateError(
          'VideoPlayer for textureId $textureId is not found, Check if its disposed.');
    }
    
    final controller = _videoControllers[textureId]!;
    
    // Debug: Print video state information
    print('MediaKit buildView - textureId: $textureId');
    print('MediaKit Video Controller state - isPlaying: ${controller.player.state.playing}');
    print('MediaKit Video Controller state - position: ${controller.player.state.position}');
    print('MediaKit Video Controller state - duration: ${controller.player.state.duration}');
    print('MediaKit Video Controller state - width: ${controller.player.state.width}');
    print('MediaKit Video Controller state - height: ${controller.player.state.height}');
    
    // Wrap in error handling to catch threading issues
    return Builder(
      builder: (context) {
        try {
          // Try a different approach - wrap in MaterialVideoControlsTheme to ensure proper rendering
          return MaterialVideoControlsTheme(
            normal: MaterialVideoControlsThemeData(
              // Use transparent controls to avoid interference
              buttonBarButtonSize: 24.0,
              buttonBarButtonColor: Colors.transparent,
            ),
            fullscreen: MaterialVideoControlsThemeData(
              buttonBarButtonSize: 24.0,
              buttonBarButtonColor: Colors.transparent,
            ),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black,
              child: Video(
                key: ValueKey('video_$textureId'),
                controller: controller,
                controls: NoVideoControls,
                // Try different fill colors to debug rendering
                fill: Colors.transparent,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                aspectRatio: 16.0 / 9.0,
                filterQuality: FilterQuality.medium,
              ),
            ),
          );
        } catch (e) {
          print('MediaKit Video Widget Error: $e');
          // Return a black container as fallback if video widget fails
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: const Center(
              child: Icon(
                Icons.error,
                color: Colors.white,
                size: 48.0,
              ),
            ),
          );
        }
      },
    );
  }

  /// Safely dispatch an event to the main thread to avoid platform channel threading issues
  void _safeDispatchEvent(StreamController<VideoEvent> streamController, VideoEvent event) {
    // Use Timer.run to ensure we're scheduled on the main isolate's event loop
    Timer.run(() {
      if (!streamController.isClosed) {
        streamController.add(event);
      }
    });
  }

  /// Safely dispatch an error to the main thread to avoid platform channel threading issues
  void _safeDispatchError(StreamController<VideoEvent> streamController, Object error) {
    // Use Timer.run to ensure we're scheduled on the main isolate's event loop
    Timer.run(() {
      if (!streamController.isClosed) {
        streamController.addError(error);
      }
    });
  }

  /// Initialize the [Stream]s for a given textureId.
  void _initialize(int textureId) {
    if (_streamSubscriptions[textureId]?.isNotEmpty ?? false) {
      return;
    }

    final player = _players[textureId];
    final completer = _completers[textureId];
    final streamController = _streamControllers[textureId];
    final streamSubscriptions = _streamSubscriptions[textureId];

    if (player != null &&
        completer != null &&
        streamController != null &&
        streamSubscriptions != null) {
      // VideoEventType.initialized

      int? width;
      int? height;
      Duration? duration;

      void notify() {
        if (!completer.isCompleted) {
          if (width != null && height != null && duration != null) {
            _safeDispatchEvent(
              streamController,
              VideoEvent(
                eventType: VideoEventType.initialized,
                key: textureId.toString(),
                size: Size(
                  (width ?? 0) * 1.0,
                  (height ?? 0) * 1.0,
                ),
                duration: duration,
                isLiveStream: duration == null || duration == Duration.zero,
              ),
            );
            completer.complete();
          }
        }
      }

      streamSubscriptions.add(
        player.stream.duration.listen(
          (event) {
            if (event > Duration.zero) {
              duration = event;
              notify();
            }
          },
        ),
      );
      streamSubscriptions.add(
        player.stream.videoParams.listen(
          (event) {
            width = event.dw;
            height = event.dh;
            if ((width ?? 0) > 0 && (height ?? 0) > 0) {
              notify();
            }
          },
        ),
      );
      streamSubscriptions.add(
        player.stream.tracks.listen(
          (event) {
            // No video track is available i.e. an audio file.
            if (event.video.length == 2 && event.audio.length > 2) {
              width = 0;
              height = 0;
              notify();
            }
          },
        ),
      );
      
      // VideoEventType.play and pause events with debouncing
      bool? lastPlayingState;
      
      streamSubscriptions.add(
        player.stream.playing.listen(
          (event) async {
            await completer.future;
            
            // Only emit if state actually changed and debounce rapid changes
            if (lastPlayingState != event) {
              // Cancel previous timer if exists
              _debounceTimers[textureId]?.cancel();
              
              // Debounce rapid state changes (wait 100ms)
              _debounceTimers[textureId] = Timer(const Duration(milliseconds: 100), () {
                if (lastPlayingState != event) {
                  lastPlayingState = event;
                  _safeDispatchEvent(
                    streamController,
                    VideoEvent(
                      eventType: event ? VideoEventType.play : VideoEventType.pause,
                      key: textureId.toString(),
                    ),
                  );
                }
              });
            }
          },
        ),
      );
      
      // VideoEventType.completed
      streamSubscriptions.add(
        player.stream.completed.listen(
          (event) async {
            await completer.future;
            if (event) {
              _safeDispatchEvent(
                streamController,
                VideoEvent(
                  eventType: VideoEventType.completed,
                  key: textureId.toString(),
                ),
              );
            }
          },
        ),
      );
      
      // VideoEventType.bufferingStart and bufferingEnd
      streamSubscriptions.add(
        player.stream.buffering.listen(
          (event) async {
            await completer.future;
            _safeDispatchEvent(
              streamController,
              VideoEvent(
                eventType: event
                    ? VideoEventType.bufferingStart
                    : VideoEventType.bufferingEnd,
                key: textureId.toString(),
              ),
            );
          },
        ),
      );
      
      // VideoEventType.bufferingUpdate
      streamSubscriptions.add(
        player.stream.buffer.listen(
          (event) async {
            await completer.future;
            _safeDispatchEvent(
              streamController,
              VideoEvent(
                eventType: VideoEventType.bufferingUpdate,
                key: textureId.toString(),
                buffered: [
                  DurationRange(
                    Duration.zero,
                    event,
                  ),
                ],
              ),
            );
          },
        ),
      );

      // VideoEventType.seek - Listen to position changes for seek events
      Duration? lastPosition;
      streamSubscriptions.add(
        player.stream.position.listen(
          (event) async {
            await completer.future;
            // Only emit seek event if there was a significant jump in position
            if (lastPosition != null && 
                (event - lastPosition!).abs() > const Duration(seconds: 1)) {
              _safeDispatchEvent(
                streamController,
                VideoEvent(
                  eventType: VideoEventType.seek,
                  key: textureId.toString(),
                  position: event,
                ),
              );
            }
            lastPosition = event;
          },
        ),
      );

      // Error handling
      streamSubscriptions.add(
        player.stream.error.listen(
          (event) {
            _safeDispatchError(
              streamController,
              PlatformException(
                code: 'MEDIA_KIT_ERROR',
                message: event,
              ),
            );
          },
        ),
      );
    }
  }
}