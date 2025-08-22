// DASH XML parsing web video player implementation
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:river_player/src/configuration/better_player_buffering_configuration.dart';
import 'video_player_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:just_audio/just_audio.dart';

/// Web implementation of [VideoPlayerPlatform] using manual DASH XML parsing for video source resolution.
class DashWebVideoPlayer extends VideoPlayerPlatform {
  final Map<int, vp.VideoPlayerController> _controllers = {};
  final Map<int, AudioPlayer> _audioControllers = {}; // Audio players for each texture
  final Map<int, StreamController<VideoEvent>> _streamControllers = {};
  final Set<int> _disposedControllers = {}; // Track disposed controllers
  int _nextTextureId = 0;

  @override
  Future<void> init() async {
    // Dispose all existing controllers
    for (final controller in _controllers.values) {
      await controller.dispose();
    }
    
    // Dispose all audio controllers
    for (final audioController in _audioControllers.values) {
      await audioController.dispose();
    }
    
    _controllers.clear();
    _audioControllers.clear();
    _streamControllers.clear();
    _disposedControllers.clear();
    _nextTextureId = 0;
    
    print('DashWebVideoPlayer: Initialized with DASH XML parsing');
  }

  @override
  Future<void> dispose(int? textureId) async {
    if (textureId == null) return;
    
    // Mark as disposed immediately to prevent further access
    _disposedControllers.add(textureId);
    
    final controller = _controllers[textureId];
    if (controller != null) {
      await controller.dispose();
      _controllers.remove(textureId);
    }
    
    final audioController = _audioControllers[textureId];
    if (audioController != null) {
      await audioController.dispose();
      _audioControllers.remove(textureId);
    }
    
    final streamController = _streamControllers[textureId];
    if (streamController != null && !streamController.isClosed) {
      await streamController.close();
      _streamControllers.remove(textureId);
    }
    
    print('DashWebVideoPlayer: Disposed texture $textureId');
  }

  @override
  Future<int?> create({BetterPlayerBufferingConfiguration? bufferingConfiguration}) async {
    final textureId = _nextTextureId++;
    
    // Create a dummy controller that will be replaced when setDataSource is called
    final controller = vp.VideoPlayerController.networkUrl(
      Uri.parse('about:blank'), // Placeholder URL
    );
    
    _controllers[textureId] = controller;
    _streamControllers[textureId] = StreamController<VideoEvent>.broadcast();
    
    print('DashWebVideoPlayer: Created texture $textureId');
    return textureId;
  }

  /// Check if a controller is valid and not disposed
  bool _isControllerValid(int? textureId) {
    if (textureId == null) return false;
    if (_disposedControllers.contains(textureId)) return false;
    return _controllers.containsKey(textureId);
  }

  /// Safely get a controller if it's valid
  vp.VideoPlayerController? _getSafeController(int? textureId) {
    if (!_isControllerValid(textureId)) return null;
    return _controllers[textureId];
  }

  /// Extract video ID from various Invidious/YouTube URL formats
  String? _extractVideoId(String url) {
    // Handle various URL formats
    final patterns = [
      RegExp(r'/watch\?v=([a-zA-Z0-9_-]{11})'),           // /watch?v=VIDEO_ID
      RegExp(r'/api/manifest/dash/id/([a-zA-Z0-9_-]{11})'), // DASH manifest API
      RegExp(r'/videos/([a-zA-Z0-9_-]{11})'),             // /videos/VIDEO_ID
      RegExp(r'[&?]v=([a-zA-Z0-9_-]{11})'),              // ?v=VIDEO_ID or &v=VIDEO_ID
      RegExp(r'/([a-zA-Z0-9_-]{11})$'),                   // Direct video ID
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
    }
    
    return null;
  }

  /// Extract server base URL from the request URL
  String _extractServerUrl(String url) {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
  }

  /// Parse DASH XML manifest to extract video and audio URLs
  Future<Map<String, String?>> _parseDashManifest(String dashUrl) async {
    try {
      print('DashWebVideoPlayer: Parsing DASH manifest: $dashUrl');
      
      final response = await http.get(Uri.parse(dashUrl));
      if (response.statusCode != 200) {
        print('DashWebVideoPlayer: Failed to fetch DASH manifest: ${response.statusCode}');
        return {'video': null, 'audio': null};
      }
      
      final document = XmlDocument.parse(response.body);
      print('DashWebVideoPlayer: Successfully parsed DASH XML');
      
      // Find video and audio representations
      final videoRepresentations = <Map<String, String>>[];
      final audioRepresentations = <Map<String, String>>[];
      
      // Look for AdaptationSet elements
      final adaptationSets = document.findAllElements('AdaptationSet');
      
      for (final adaptationSet in adaptationSets) {
        final mimeType = adaptationSet.getAttribute('mimeType') ?? '';
        final contentType = adaptationSet.getAttribute('contentType') ?? '';
        
        // Check if this is a video adaptation set
        if (mimeType.startsWith('video/') || contentType == 'video') {
          print('DashWebVideoPlayer: Found video AdaptationSet: $mimeType');
          _parseRepresentations(adaptationSet, videoRepresentations, 'video');
        }
        // Check if this is an audio adaptation set
        else if (mimeType.startsWith('audio/') || contentType == 'audio') {
          print('DashWebVideoPlayer: Found audio AdaptationSet: $mimeType');
          _parseRepresentations(adaptationSet, audioRepresentations, 'audio');
        }
      }
      
      print('DashWebVideoPlayer: Found ${videoRepresentations.length} video representations, ${audioRepresentations.length} audio representations');
      
      // Prefer separate video and audio streams for better quality and dual-player support
      // This approach works better for web audio compatibility
      if (videoRepresentations.isNotEmpty) {
        // Sort and select best video
        videoRepresentations.sort((a, b) {
          final aBandwidth = int.tryParse(a['bandwidth']!) ?? 0;
          final bBandwidth = int.tryParse(b['bandwidth']!) ?? 0;
          final aWidth = int.tryParse(a['width']!) ?? 0;
          final bWidth = int.tryParse(b['width']!) ?? 0;
          
          if (aWidth != bWidth) {
            return bWidth.compareTo(aWidth); // Higher width first
          }
          return bBandwidth.compareTo(aBandwidth); // Higher bandwidth first
        });
        
        final selectedVideoRep = videoRepresentations.first;
        final videoUrl = selectedVideoRep['url']!;
        
        print('DashWebVideoPlayer: Selected video representation: ${selectedVideoRep['width']}x${selectedVideoRep['height']}, bandwidth: ${selectedVideoRep['bandwidth']}');
        
        // Find best audio stream
        String? audioUrl;
        if (audioRepresentations.isNotEmpty) {
          // Sort audio by bandwidth (higher is better)
          audioRepresentations.sort((a, b) {
            final aBandwidth = int.tryParse(a['bandwidth']!) ?? 0;
            final bBandwidth = int.tryParse(b['bandwidth']!) ?? 0;
            return bBandwidth.compareTo(aBandwidth); // Higher bandwidth first
          });
          
          final selectedAudioRep = audioRepresentations.first;
          audioUrl = selectedAudioRep['url']!;
          
          print('DashWebVideoPlayer: Selected audio representation: bandwidth: ${selectedAudioRep['bandwidth']}, codecs: ${selectedAudioRep['codecs']}');
        } else {
          print('DashWebVideoPlayer: No audio representations found');
        }
        
        return {'video': videoUrl, 'audio': audioUrl};
      }
      
      // Fallback: Try combined (video+audio) representations if separate streams failed
      print('DashWebVideoPlayer: No separate audio found, trying combined video+audio streams');
      final combinedRepresentations = videoRepresentations.where((rep) {
        final codecs = rep['codecs']!.toLowerCase();
        // Look for representations that might contain both video and audio
        return codecs.contains('avc1') || codecs.contains('av01') || codecs.contains('vp9');
      }).toList();
      
      if (combinedRepresentations.isNotEmpty) {
        // Sort and select best combined representation
        combinedRepresentations.sort((a, b) {
          final aBandwidth = int.tryParse(a['bandwidth']!) ?? 0;
          final bBandwidth = int.tryParse(b['bandwidth']!) ?? 0;
          final aWidth = int.tryParse(a['width']!) ?? 0;
          final bWidth = int.tryParse(b['width']!) ?? 0;
          
          if (aWidth != bWidth) {
            return bWidth.compareTo(aWidth); // Higher width first
          }
          return bBandwidth.compareTo(aBandwidth); // Higher bandwidth first
        });
        
        final selectedRep = combinedRepresentations.first;
        final selectedUrl = selectedRep['url']!;
        
        print('DashWebVideoPlayer: Selected combined video+audio representation as fallback: ${selectedRep['width']}x${selectedRep['height']}, bandwidth: ${selectedRep['bandwidth']}');
        print('DashWebVideoPlayer: Selected URL: ${selectedUrl.substring(0, selectedUrl.length.clamp(0, 100))}...');
        
        return {'video': selectedUrl, 'audio': null}; // Combined stream
      }
      
      print('DashWebVideoPlayer: No suitable representations found');
      return {'video': null, 'audio': null};
      
    } catch (e) {
      print('DashWebVideoPlayer: Error parsing DASH manifest: $e');
      return {'video': null, 'audio': null};
    }
  }
  
  /// Helper method to parse representations from an AdaptationSet
  void _parseRepresentations(XmlElement adaptationSet, List<Map<String, String>> representations, String type) {
    final representations_ = adaptationSet.findAllElements('Representation');
    
    for (final representation in representations_) {
      final id = representation.getAttribute('id') ?? '';
      final bandwidth = representation.getAttribute('bandwidth') ?? '0';
      final width = representation.getAttribute('width') ?? '';
      final height = representation.getAttribute('height') ?? '';
      final codecs = representation.getAttribute('codecs') ?? '';
      
      // Look for BaseURL within this representation
      final baseUrlElement = representation.findElements('BaseURL').firstOrNull;
      if (baseUrlElement != null) {
        final baseUrl = baseUrlElement.innerText.trim();
        
        if (baseUrl.isNotEmpty) {
          representations.add({
            'id': id,
            'bandwidth': bandwidth,
            'width': width,
            'height': height,
            'codecs': codecs,
            'url': baseUrl,
            'type': type,
          });
          
          if (type == 'video') {
            print('DashWebVideoPlayer: Found video representation: ${width}x$height, bandwidth: $bandwidth, codecs: $codecs');
          } else {
            print('DashWebVideoPlayer: Found audio representation: bandwidth: $bandwidth, codecs: $codecs');
          }
        }
      }
    }
  }
  
  /// Try alternative video resolution strategies
  Future<Map<String, String?>> _getWebCompatibleVideoUrl(String videoId, String serverUrl) async {
    try {
      print('DashWebVideoPlayer: Resolving video for $videoId from $serverUrl');
      
      // Try DASH manifest first
      final dashUrl = '$serverUrl/api/manifest/dash/id/$videoId';
      final dashResult = await _parseDashManifest(dashUrl);
      if (dashResult['video'] != null) {
        return dashResult;
      }
      
      // Fallback: Try HLS streaming
      print('DashWebVideoPlayer: DASH failed, trying HLS streaming');
      final hlsUrl = '$serverUrl/api/manifest/hls_variant/$videoId.m3u8';
      
      try {
        final response = await http.head(Uri.parse(hlsUrl));
        if (response.statusCode == 200) {
          print('DashWebVideoPlayer: Found working HLS stream');
          return {'video': hlsUrl, 'audio': null}; // HLS is combined
        }
      } catch (e) {
        print('DashWebVideoPlayer: HLS stream failed: $e');
      }
      
      print('DashWebVideoPlayer: No compatible video format found');
      return {'video': null, 'audio': null};
      
    } catch (e) {
      print('DashWebVideoPlayer: Error getting video URL: $e');
      return {'video': null, 'audio': null};
    }
  }

  @override
  Future<void> setDataSource(int? textureId, DataSource dataSource) async {
    if (textureId == null) return;
    
    print('DashWebVideoPlayer: Setting data source: ${dataSource.uri}');
    
    // Dispose the old controller if it exists
    final oldController = _controllers[textureId];
    if (oldController != null) {
      await oldController.dispose();
    }
    
    late vp.VideoPlayerController controller;
    
    try {
      if (dataSource.sourceType == DataSourceType.network && dataSource.uri != null) {
        final url = dataSource.uri!;
        final videoId = _extractVideoId(url);
        
        if (videoId != null) {
          print('DashWebVideoPlayer: Extracted video ID: $videoId');
          
          // Extract server from the URL
          final serverUrl = _extractServerUrl(url);
          print('DashWebVideoPlayer: Using server: $serverUrl');
          
          // Get web-compatible video and audio URLs using DASH parsing
          final mediaUrls = await _getWebCompatibleVideoUrl(videoId, serverUrl);
          final videoUrl = mediaUrls['video'];
          final audioUrl = mediaUrls['audio'];
          
          if (videoUrl != null) {
            print('DashWebVideoPlayer: Using DASH-resolved video URL: ${videoUrl.substring(0, 100)}...');
            
            controller = vp.VideoPlayerController.networkUrl(
              Uri.parse(videoUrl),
              httpHeaders: dataSource.headers?.cast<String, String>() ?? {},
            );
            
            // Set up audio player if we have a separate audio stream
            if (audioUrl != null) {
              print('DashWebVideoPlayer: Setting up separate audio stream: ${audioUrl.substring(0, 100)}...');
              final audioPlayer = AudioPlayer();
              _audioControllers[textureId] = audioPlayer;
              
              try {
                await audioPlayer.setUrl(audioUrl);
                _setupAudioListeners(textureId, audioPlayer);
                print('DashWebVideoPlayer: Audio player initialized successfully');
              } catch (e) {
                print('DashWebVideoPlayer: Failed to set audio URL: $e');
                await audioPlayer.dispose();
                _audioControllers.remove(textureId);
              }
            } else {
              print('DashWebVideoPlayer: Using combined video+audio stream or video-only');
            }
          } else {
            throw Exception('Could not resolve video URL using DASH parsing');
          }
        } else {
          print('DashWebVideoPlayer: No video ID found, using direct URL');
          controller = vp.VideoPlayerController.networkUrl(
            Uri.parse(url),
            httpHeaders: dataSource.headers?.cast<String, String>() ?? {},
          );
        }
      } else if (dataSource.sourceType == DataSourceType.asset) {
        final asset = dataSource.package != null 
            ? 'packages/${dataSource.package}/${dataSource.asset}'
            : dataSource.asset;
        if (asset == null) {
          throw ArgumentError('asset must not be null for asset source');
        }
        controller = vp.VideoPlayerController.asset(asset);
      } else {
        throw UnsupportedError('${dataSource.sourceType} is not supported in DashWebVideoPlayer');
      }
      
      _controllers[textureId] = controller;
      
      // Initialize the controller with error handling
      try {
        await controller.initialize();
        print('DashWebVideoPlayer: Controller initialized successfully');
        
        // Set up listeners after successful initialization
        _setupListeners(textureId, controller);
        
        // Emit initialized event
        final streamController = _streamControllers[textureId];
        if (streamController != null && !streamController.isClosed) {
          streamController.add(VideoEvent(
            eventType: VideoEventType.initialized,
            key: textureId.toString(),
            size: controller.value.size,
            duration: controller.value.duration,
            isLiveStream: controller.value.duration == Duration.zero,
          ));
        }
        
        // Delay auto-play slightly to ensure initialization is complete
        print('DashWebVideoPlayer: Starting delayed auto-play...');
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Start both video and audio if available
        final audioPlayer = _audioControllers[textureId];
        if (audioPlayer != null) {
          print('DashWebVideoPlayer: Starting synchronized video+audio playback');
          // Start both simultaneously for better sync
          await Future.wait([
            controller.play(),
            audioPlayer.play(),
          ]);
        } else {
          await controller.play();
        }
        
        print('DashWebVideoPlayer: Video initialized and started successfully');
      } catch (initError) {
        print('DashWebVideoPlayer: Controller initialization failed: $initError');
        
        // Try to continue anyway - sometimes the error is not fatal
        _setupListeners(textureId, controller);
        
        // Emit initialized event with error context
        final streamController = _streamControllers[textureId];
        if (streamController != null && !streamController.isClosed) {
          streamController.add(VideoEvent(
            eventType: VideoEventType.initialized,
            key: textureId.toString(),
            size: const Size(640, 480), // Default size
            duration: Duration.zero,
            isLiveStream: true, // Assume live stream if duration unknown
          ));
        }
        
        // Try to play anyway - the video might still work
        try {
          await Future.delayed(const Duration(milliseconds: 200));
          
          // Try to start both video and audio if available
          final audioPlayer = _audioControllers[textureId];
          if (audioPlayer != null) {
            print('DashWebVideoPlayer: Attempting synchronized video+audio playback despite init error');
            await Future.wait([
              controller.play(),
              audioPlayer.play(),
            ]);
          } else {
            await controller.play();
          }
          print('DashWebVideoPlayer: Video playing despite initialization error');
        } catch (playError) {
          print('DashWebVideoPlayer: Play also failed: $playError');
          rethrow;
        }
      }
      
    } catch (e) {
      print('DashWebVideoPlayer: Failed to initialize video: $e');
      
      // Don't propagate initialization errors if we have a working controller
      final controller = _controllers[textureId];
      if (controller != null) {
        print('DashWebVideoPlayer: Controller exists, checking if video is working...');
        
        // Try to emit a successful initialization event to continue playback
        final streamController = _streamControllers[textureId];
        if (streamController != null && !streamController.isClosed) {
          try {
            // Wait a moment and check if the controller has usable state
            Timer(const Duration(milliseconds: 500), () {
              // Check if controller still exists and hasn't been disposed
              final currentController = _controllers[textureId];
              if (currentController != null && currentController == controller) {
                try {
                  // Set up listeners only if controller is still valid
                  _setupListeners(textureId, currentController);
                  
                  if (currentController.value.hasError) {
                    print('DashWebVideoPlayer: Controller has error: ${currentController.value.errorDescription}');
                  } else {
                    print('DashWebVideoPlayer: Controller seems to be working, emitting successful init');
                    if (!streamController.isClosed) {
                      streamController.add(VideoEvent(
                        eventType: VideoEventType.initialized,
                        key: textureId.toString(),
                        size: currentController.value.size.isEmpty ? const Size(640, 480) : currentController.value.size,
                        duration: currentController.value.duration,
                        isLiveStream: currentController.value.duration == Duration.zero,
                      ));
                    }
                  }
                } catch (setupError) {
                  print('DashWebVideoPlayer: Error setting up controller after delay: $setupError');
                }
              } else {
                print('DashWebVideoPlayer: Controller was disposed before delayed setup');
              }
            });
          } catch (eventError) {
            print('DashWebVideoPlayer: Error setting up delayed initialization: $eventError');
          }
        }
      }
    }
  }

  void _setupListeners(int textureId, vp.VideoPlayerController controller) {
    final streamController = _streamControllers[textureId];
    if (streamController == null || streamController.isClosed) return;
    
    // Check if controller is still valid before adding listener
    if (!_isControllerValid(textureId)) {
      print('DashWebVideoPlayer: Controller invalid in _setupListeners, skipping');
      return;
    }
    
    // Track previous state to avoid duplicate events
    bool? wasPlaying;
    bool? wasBuffering;
    Duration? lastPosition;
    
    try {
      controller.addListener(() {
      // Double-check validity inside the listener
      if (streamController.isClosed || !_isControllerValid(textureId)) return;
      
      try {
        final value = controller.value;
        final currentlyPlaying = value.isPlaying;
        final currentlyBuffering = value.isBuffering;
        final currentPosition = value.position;
      
        // Only fire play/pause events when state actually changes
        if (wasPlaying != currentlyPlaying) {
          wasPlaying = currentlyPlaying;
          if (currentlyPlaying) {
            streamController.add(VideoEvent(
              eventType: VideoEventType.play,
              key: textureId.toString(),
            ));
          } else {
            streamController.add(VideoEvent(
              eventType: VideoEventType.pause,
              key: textureId.toString(),
            ));
          }
        }
        
        // Only fire position updates if position changed significantly (>1 second)
        if (lastPosition == null || 
            (currentPosition - lastPosition!).abs() > const Duration(seconds: 1)) {
          lastPosition = currentPosition;
          streamController.add(VideoEvent(
            eventType: VideoEventType.seek,
            key: textureId.toString(),
            position: currentPosition,
          ));
        }
        
        // Only fire buffering events when state actually changes
        if (wasBuffering != currentlyBuffering) {
          wasBuffering = currentlyBuffering;
          if (currentlyBuffering) {
            streamController.add(VideoEvent(
              eventType: VideoEventType.bufferingStart,
              key: textureId.toString(),
            ));
          } else {
            streamController.add(VideoEvent(
              eventType: VideoEventType.bufferingEnd,
              key: textureId.toString(),
            ));
          }
        }
        
        // Handle completion
        if (currentPosition >= value.duration && value.duration > Duration.zero) {
          streamController.add(VideoEvent(
            eventType: VideoEventType.completed,
            key: textureId.toString(),
          ));
        }
      } catch (valueError) {
        print('DashWebVideoPlayer: Error accessing controller value: $valueError');
      }
    });
    } catch (listenerError) {
      print('DashWebVideoPlayer: Error setting up listener: $listenerError');
    }
  }

  void _setupAudioListeners(int textureId, AudioPlayer audioPlayer) {
    print('DashWebVideoPlayer: Setting up audio listeners for texture $textureId');
    
    // Listen to audio player state changes for debugging and sync
    audioPlayer.playerStateStream.listen((state) {
      print('DashWebVideoPlayer: Audio player state changed: $state');
    });
    
    // Listen to audio position for potential sync validation
    audioPlayer.positionStream.listen((position) {
      // We could add sync validation here if needed
      // For now, just log occasionally
      if (position.inSeconds % 10 == 0) {
        print('DashWebVideoPlayer: Audio position: ${position.inSeconds}s');
      }
    });
    
    // Listen to audio playback events
    audioPlayer.playbackEventStream.listen((event) {
      if (event.processingState == ProcessingState.completed) {
        print('DashWebVideoPlayer: Audio playback completed');
      }
    });
  }

  // Standard VideoPlayerPlatform methods implementation
  @override
  Stream<VideoEvent> videoEventsFor(int? textureId) {
    if (textureId == null || _streamControllers[textureId] == null) {
      throw StateError('VideoPlayer for textureId $textureId is not found');
    }
    return _streamControllers[textureId]!.stream;
  }

  @override
  Future<void> setLooping(int? textureId, bool looping) async {
    final controller = _getSafeController(textureId);
    if (controller != null) {
      try {
        await controller.setLooping(looping);
      } catch (e) {
        print('DashWebVideoPlayer: Error setting looping, controller disposed: $e');
      }
    }
  }

  @override
  Future<void> play(int? textureId) async {
    final controller = _getSafeController(textureId);
    final audioPlayer = _audioControllers[textureId];
    
    if (controller != null) {
      try {
        // Start both video and audio (if available) simultaneously
        final List<Future> playFutures = [];
        
        // Start video playback
        playFutures.add(controller.play());
        
        // Start audio playback if available
        if (audioPlayer != null) {
          print('DashWebVideoPlayer: Starting audio playback alongside video');
          playFutures.add(audioPlayer.play());
        }
        
        // Wait for both to start
        await Future.wait(playFutures);
        print('DashWebVideoPlayer: Both video and audio started successfully');
      } catch (e) {
        print('DashWebVideoPlayer: Error playing, controller disposed: $e');
      }
    }
  }

  @override
  Future<void> pause(int? textureId) async {
    final controller = _getSafeController(textureId);
    final audioPlayer = _audioControllers[textureId];
    
    if (controller != null) {
      try {
        // Pause both video and audio (if available) simultaneously
        final List<Future> pauseFutures = [];
        
        // Pause video playback
        pauseFutures.add(controller.pause());
        
        // Pause audio playback if available
        if (audioPlayer != null) {
          print('DashWebVideoPlayer: Pausing audio playback alongside video');
          pauseFutures.add(audioPlayer.pause());
        }
        
        // Wait for both to pause
        await Future.wait(pauseFutures);
        print('DashWebVideoPlayer: Both video and audio paused successfully');
      } catch (e) {
        print('DashWebVideoPlayer: Error pausing, controller disposed: $e');
      }
    }
  }

  @override
  Future<void> setVolume(int? textureId, double volume) async {
    final controller = _getSafeController(textureId);
    final audioPlayer = _audioControllers[textureId];
    
    if (controller != null) {
      try {
        // Ensure volume is in range [0.0, 1.0]
        double clampedVolume = volume.clamp(0.0, 1.0);
        
        // If volume appears to be in percentage (0-100), convert to 0-1 range
        if (volume > 1.0 && volume <= 100.0) {
          clampedVolume = volume / 100.0;
        }
        
        print('DashWebVideoPlayer: Setting volume from $volume to $clampedVolume');
        
        // Set volume for both video and audio (if available)
        final List<Future> volumeFutures = [];
        
        // Set video volume
        volumeFutures.add(controller.setVolume(clampedVolume));
        
        // Set audio volume if available
        if (audioPlayer != null) {
          print('DashWebVideoPlayer: Setting audio volume alongside video');
          volumeFutures.add(audioPlayer.setVolume(clampedVolume));
        }
        
        // Wait for both volume changes
        await Future.wait(volumeFutures);
        print('DashWebVideoPlayer: Volume set for both video and audio');
      } catch (e) {
        print('DashWebVideoPlayer: Error setting volume, controller disposed: $e');
      }
    }
  }

  @override
  Future<void> setSpeed(int? textureId, double speed) async {
    final controller = _getSafeController(textureId);
    final audioPlayer = _audioControllers[textureId];
    
    if (controller != null) {
      try {
        // Ensure speed is in a reasonable range [0.1, 4.0]
        double clampedSpeed = speed.clamp(0.1, 4.0);
        print('DashWebVideoPlayer: Setting speed from $speed to $clampedSpeed');
        
        // Set speed for both video and audio (if available)
        final List<Future> speedFutures = [];
        
        // Set video speed
        speedFutures.add(controller.setPlaybackSpeed(clampedSpeed));
        
        // Set audio speed if available
        if (audioPlayer != null) {
          print('DashWebVideoPlayer: Setting audio speed alongside video');
          speedFutures.add(audioPlayer.setSpeed(clampedSpeed));
        }
        
        // Wait for both speed changes
        await Future.wait(speedFutures);
        print('DashWebVideoPlayer: Speed set for both video and audio');
      } catch (e) {
        print('DashWebVideoPlayer: Error setting speed, controller disposed: $e');
      }
    }
  }

  @override
  Future<void> seekTo(int? textureId, Duration? position) async {
    if (position == null) return;
    final controller = _getSafeController(textureId);
    final audioPlayer = _audioControllers[textureId];
    
    if (controller != null) {
      try {
        // Seek both video and audio (if available) simultaneously
        final List<Future> seekFutures = [];
        
        // Seek video
        seekFutures.add(controller.seekTo(position));
        
        // Seek audio if available
        if (audioPlayer != null) {
          print('DashWebVideoPlayer: Seeking audio to position ${position.inSeconds}s alongside video');
          seekFutures.add(audioPlayer.seek(position));
        }
        
        // Wait for both seek operations
        await Future.wait(seekFutures);
        print('DashWebVideoPlayer: Both video and audio seeked to ${position.inSeconds}s successfully');
      } catch (e) {
        print('DashWebVideoPlayer: Error seeking, controller disposed: $e');
      }
    }
  }

  @override
  Future<Duration> getPosition(int? textureId) async {
    final controller = _getSafeController(textureId);
    if (controller == null) return Duration.zero;
    
    try {
      return controller.value.position;
    } catch (e) {
      print('DashWebVideoPlayer: Error getting position, controller disposed: $e');
      return Duration.zero;
    }
  }

  @override
  Widget buildView(int? textureId) {
    final controller = _getSafeController(textureId);
    
    print('DashWebVideoPlayer: buildView called for texture $textureId, controller exists: ${controller != null}');
    
    if (controller == null) {
      print('DashWebVideoPlayer: No controller found for texture $textureId');
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            'Invidious video player not initialized',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    // Safely check controller state with disposal protection
    bool isInitialized = false;
    bool hasError = false;
    String? errorDescription;
    double aspectRatio = 16.0 / 9.0; // Default aspect ratio
    
    try {
      isInitialized = controller.value.isInitialized;
      hasError = controller.value.hasError;
      errorDescription = controller.value.errorDescription;
      if (isInitialized && controller.value.size.width > 0 && controller.value.size.height > 0) {
        aspectRatio = controller.value.aspectRatio;
      }
    } catch (e) {
      print('DashWebVideoPlayer: Controller disposed while checking state: $e');
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            'Video player was disposed',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    
    print('DashWebVideoPlayer: Controller initialized: $isInitialized, hasError: $hasError');
    
    if (hasError) {
      print('DashWebVideoPlayer: Video error: $errorDescription');
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            'Video Error: $errorDescription',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: isInitialized
            ? AspectRatio(
                aspectRatio: aspectRatio,
                child: vp.VideoPlayer(controller),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading Invidious video...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
      ),
    );
  }

  // Unsupported methods for web platform
  @override
  Future<void> setTrackParameters(int? textureId, int? width, int? height, int? bitrate) async {
    // Track parameters not supported in standard video_player
  }

  @override
  Future<DateTime?> getAbsolutePosition(int? textureId) async {
    return null;
  }

  @override
  Future<void> preCache(DataSource dataSource, int preCacheSize) async {
    // Pre-caching not supported on web
  }

  @override
  Future<void> stopPreCache(String url, String? cacheKey) async {
    // Pre-caching not supported on web
  }

  @override
  Future<void> enablePictureInPicture(int? textureId, double? top, double? left, double? width, double? height) async {
    // PiP not supported on web
  }

  @override
  Future<void> disablePictureInPicture(int? textureId) async {
    // PiP not supported on web
  }

  @override
  Future<bool?> isPictureInPictureEnabled(int? textureId) async {
    return false;
  }

  @override
  Future<void> setAudioTrack(int? textureId, String? name, int? index) async {
    // Audio track selection not supported in standard video_player
  }

  @override
  Future<void> setMixWithOthers(int? textureId, bool mixWithOthers) async {
    // Audio mixing not supported on web
  }

  @override
  Future<void> clearCache() async {
    // Cache clearing not needed
  }
}