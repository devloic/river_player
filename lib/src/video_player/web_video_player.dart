// Web-specific video player implementation using standard video_player plugin
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart' as vp;
import 'package:river_player/src/configuration/better_player_buffering_configuration.dart';
import 'video_player_platform_interface.dart';

/// Web implementation of [VideoPlayerPlatform] using the standard video_player plugin.
class WebVideoPlayer extends VideoPlayerPlatform {
  final Map<int, vp.VideoPlayerController> _controllers = {};
  final Map<int, StreamController<VideoEvent>> _streamControllers = {};
  int _nextTextureId = 0;

  @override
  Future<void> init() async {
    // Dispose all existing controllers
    for (final controller in _controllers.values) {
      await controller.dispose();
    }
    
    _controllers.clear();
    _streamControllers.clear();
    _nextTextureId = 0;
  }

  @override
  Future<void> dispose(int? textureId) async {
    if (textureId == null) return;
    
    final controller = _controllers[textureId];
    if (controller != null) {
      await controller.dispose();
      _controllers.remove(textureId);
    }
    
    final streamController = _streamControllers[textureId];
    if (streamController != null && !streamController.isClosed) {
      await streamController.close();
      _streamControllers.remove(textureId);
    }
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
    
    return textureId;
  }

  /// Check if a video format is likely supported by web browsers
  bool _isWebCompatibleFormat(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    
    // Common web-compatible formats
    final webFormats = ['.mp4', '.webm', '.ogg'];
    
    return webFormats.any((format) => path.endsWith(format));
  }

  /// Check if URL is a streaming manifest that needs special handling
  bool _isStreamingManifest(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    
    // Check for streaming manifest formats
    return path.contains('/manifest/dash/') ||  // DASH manifest API endpoint
           path.endsWith('.mpd') ||              // DASH manifest file
           path.endsWith('.m3u8') ||             // HLS manifest
           url.contains('manifest') ||           // Generic manifest indicator
           url.contains('dash');                 // DASH indicator
  }

  /// Helper to make URLs absolute
  String _makeAbsoluteUrl(String url, String manifestUrl) {
    if (url.startsWith('http')) {
      return url;
    }
    
    final manifestUri = Uri.parse(manifestUrl);
    return '${manifestUri.scheme}://${manifestUri.host}${manifestUri.port != 80 && manifestUri.port != 443 ? ':${manifestUri.port}' : ''}$url';
  }

  /// Attempt to extract direct video URL from DASH manifest
  Future<String?> _tryExtractVideoUrlFromDash(String manifestUrl) async {
    try {
      print('WebVideoPlayer: Attempting to parse DASH manifest: $manifestUrl');
      
      final response = await http.get(Uri.parse(manifestUrl));
      if (response.statusCode != 200) {
        print('WebVideoPlayer: Failed to fetch manifest: ${response.statusCode}');
        return null;
      }

      final manifestContent = response.body;
      print('WebVideoPlayer: Manifest content type: ${response.headers['content-type']}');
      
      // Look for video representations by finding AdaptationSet with video content
      final videoAdaptationSets = RegExp(r'<AdaptationSet[^>]*contentType="video"[^>]*>.*?</AdaptationSet>', dotAll: true).allMatches(manifestContent);
      
      for (final adaptationSet in videoAdaptationSets) {
        final adaptationContent = adaptationSet.group(0)!;
        print('WebVideoPlayer: Found video AdaptationSet');
        
        // Look for BaseURL in video adaptation set
        final baseUrlMatch = RegExp(r'<BaseURL[^>]*>([^<]+)</BaseURL>').firstMatch(adaptationContent);
        if (baseUrlMatch != null) {
          var baseUrl = baseUrlMatch.group(1)!.trim();
          print('WebVideoPlayer: Found video BaseURL: $baseUrl');
          return _makeAbsoluteUrl(baseUrl, manifestUrl);
        }
        
        // Look for Representation with BaseURL in video adaptation set
        final repMatch = RegExp(r'<Representation[^>]*>.*?<BaseURL[^>]*>([^<]+)</BaseURL>', dotAll: true).firstMatch(adaptationContent);
        if (repMatch != null) {
          var baseUrl = repMatch.group(1)!.trim();
          print('WebVideoPlayer: Found video Representation BaseURL: $baseUrl');
          return _makeAbsoluteUrl(baseUrl, manifestUrl);
        }
      }
      
      // Fallback: Look for video representations with specific itags (YouTube)
      final videoItags = ['18', '22', '37', '298', '299', '136', '137', '396', '397'];
      
      for (final itag in videoItags) {
        final itagPattern = RegExp('itag=$itag[^"&]*');
        final itagMatch = itagPattern.firstMatch(manifestContent);
        if (itagMatch != null) {
          print('WebVideoPlayer: Found video itag $itag in manifest');
          
          // Try to find the BaseURL that contains this itag
          final urlsWithItag = RegExp(r'<BaseURL[^>]*>([^<]*itag=' + itag + r'[^<]*)</BaseURL>').allMatches(manifestContent);
          for (final match in urlsWithItag) {
            var baseUrl = match.group(1)!.trim();
            print('WebVideoPlayer: Found video BaseURL for itag $itag: ${baseUrl.substring(0, 100)}...');
            return _makeAbsoluteUrl(baseUrl, manifestUrl);
          }
        }
      }
      
      // Try to extract any BaseURL from DASH MPD
      final baseUrlMatch = RegExp(r'<BaseURL[^>]*>([^<]+)</BaseURL>').firstMatch(manifestContent);
      if (baseUrlMatch != null) {
        var baseUrl = baseUrlMatch.group(1)!.trim();
        print('WebVideoPlayer: Found BaseURL in manifest: $baseUrl');
        
        // Check if it's an audio-only stream (itag 140 is audio)
        if (baseUrl.contains('mime=audio') || baseUrl.contains('itag=140')) {
          print('WebVideoPlayer: Detected audio-only stream, looking for video alternatives...');
          
          // Try to modify the URL to get video instead of audio
          final videoUrl = baseUrl.replaceAll('itag=140', 'itag=18'); // Basic MP4 video
          if (videoUrl != baseUrl) {
            print('WebVideoPlayer: Attempting to use video URL: $videoUrl');
            return _makeAbsoluteUrl(videoUrl, manifestUrl);
          }
        }
        
        return _makeAbsoluteUrl(baseUrl, manifestUrl);
      }

      // Try to find representation URLs
      final repMatch = RegExp(r'<Representation[^>]*>.*?<BaseURL[^>]*>([^<]+)</BaseURL>', dotAll: true).firstMatch(manifestContent);
      if (repMatch != null) {
        var videoUrl = repMatch.group(1)!.trim();
        print('WebVideoPlayer: Found Representation BaseURL: $videoUrl');
        return _makeAbsoluteUrl(videoUrl, manifestUrl);
      }

      print('WebVideoPlayer: No direct video URL found in DASH manifest');
      return null;
      
    } catch (e) {
      print('WebVideoPlayer: Error parsing DASH manifest: $e');
      return null;
    }
  }

  @override
  Future<void> setDataSource(int? textureId, DataSource dataSource) async {
    if (textureId == null) return;
    
    // Check format compatibility for network sources
    if (dataSource.sourceType == DataSourceType.network && dataSource.uri != null) {
      // Check for streaming manifests that need special handling
      if (_isStreamingManifest(dataSource.uri!)) {
        print('WebVideoPlayer: DASH/HLS manifest detected: ${dataSource.uri}');
        
        // Try to extract direct video URL from manifest
        final extractedVideoUrl = await _tryExtractVideoUrlFromDash(dataSource.uri!);
        
        if (extractedVideoUrl != null) {
          print('WebVideoPlayer: Successfully extracted direct video URL: $extractedVideoUrl');
          
          // Check if it's a YouTube/Google Video URL that needs special headers
          final isYouTubeUrl = extractedVideoUrl.contains('googlevideo.com') || 
                              extractedVideoUrl.contains('youtube.com');
          
          Map<String, String> videoHeaders = dataSource.headers?.cast<String, String>() ?? {};
          String finalVideoUrl = extractedVideoUrl;
          
          if (isYouTubeUrl) {
            print('WebVideoPlayer: YouTube URL detected, implementing bypass strategies...');
            
            // Option 1: Try to decode URL-encoded entities first
            finalVideoUrl = finalVideoUrl.replaceAll('&amp;', '&');
            print('WebVideoPlayer: Decoded URL entities');
            
            // Option 2: Alternative approach - try to get a different format
            // Check if we can modify the itag to get a more web-compatible version
            if (finalVideoUrl.contains('itag=140')) {
              // Try to get a video+audio combined stream
              finalVideoUrl = finalVideoUrl.replaceAll('itag=140', 'itag=18'); // Basic MP4 video+audio
              print('WebVideoPlayer: Trying alternative combined stream: itag=18');
            }
            
            // Option 3: As fallback info, prepare CORS proxy option
            final corsProxyUrl = 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(finalVideoUrl)}';
            print('WebVideoPlayer: CORS proxy available as fallback if needed');
            
            // Still add headers for better compatibility
            videoHeaders.addAll({
              'Referer': 'https://www.youtube.com/',
              'Origin': 'https://www.youtube.com',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            });
          }
          
          // Update the data source to use the processed URL with bypass headers
          dataSource = DataSource(
            sourceType: dataSource.sourceType,
            uri: finalVideoUrl,
            headers: videoHeaders,
            // Copy other properties as needed
          );
        } else {
          print('WebVideoPlayer: Could not extract direct video URL from manifest');
          final streamController = _streamControllers[textureId];
          if (streamController != null && !streamController.isClosed) {
            streamController.addError(
              PlatformException(
                code: 'UNSUPPORTED_STREAMING_FORMAT',
                message: 'DASH/HLS streaming is not supported on web platform. Could not extract direct video URL from manifest.',
                details: 'URL: ${dataSource.uri}',
              )
            );
          }
          return;
        }
      }
      
      if (!_isWebCompatibleFormat(dataSource.uri!)) {
        print('WebVideoPlayer: Warning - ${dataSource.uri} may not be compatible with web browsers. Recommended formats: MP4 (H.264), WebM, OGG');
      }
    }
    
    // Dispose the old controller if it exists
    final oldController = _controllers[textureId];
    if (oldController != null) {
      await oldController.dispose();
    }
    
    // Create new controller based on data source
    late vp.VideoPlayerController controller;
    
    switch (dataSource.sourceType) {
      case DataSourceType.network:
        if (dataSource.uri == null) {
          throw ArgumentError('uri must not be null for network source');
        }
        controller = vp.VideoPlayerController.networkUrl(
          Uri.parse(dataSource.uri!),
          httpHeaders: dataSource.headers?.cast<String, String>() ?? {},
        );
        break;
        
      case DataSourceType.file:
        if (dataSource.uri == null) {
          throw ArgumentError('uri must not be null for file source');
        }
        // For web, treat file sources as network URLs
        controller = vp.VideoPlayerController.networkUrl(
          Uri.parse(dataSource.uri!),
        );
        break;
        
      case DataSourceType.asset:
        final asset = dataSource.package != null 
            ? 'packages/${dataSource.package}/${dataSource.asset}'
            : dataSource.asset;
        if (asset == null) {
          throw ArgumentError('asset must not be null for asset source');
        }
        controller = vp.VideoPlayerController.asset(asset);
        break;
        
      default:
        throw UnsupportedError('${dataSource.sourceType} is not supported on web');
    }
    
    _controllers[textureId] = controller;
    
    // Initialize the controller and set up listeners
    try {
      await controller.initialize();
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
    } catch (e) {
      // Enhanced error handling for web video compatibility
      print('WebVideoPlayer: Failed to initialize video: $e');
      
      // Check if it's a format/codec error
      final isFormatError = e.toString().contains('MEDIA_ERR_SRC_NOT_SUPPORTED') ||
                           e.toString().contains('format not supported') ||
                           e.toString().contains('codec');
      
      final streamController = _streamControllers[textureId];
      if (streamController != null && !streamController.isClosed) {
        if (isFormatError) {
          // Emit a specific error for unsupported format
          streamController.add(VideoEvent(
            eventType: VideoEventType.unknown,
            key: textureId.toString(),
          ));
          print('WebVideoPlayer: Video format not supported by browser. Consider using MP4 with H.264 codec for better web compatibility.');
        } else {
          streamController.addError(e);
        }
      }
    }
  }

  void _setupListeners(int textureId, vp.VideoPlayerController controller) {
    final streamController = _streamControllers[textureId];
    if (streamController == null || streamController.isClosed) return;
    
    controller.addListener(() {
      if (streamController.isClosed) return;
      
      final value = controller.value;
      
      // Handle play/pause events
      if (value.isPlaying) {
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
      
      // Handle position updates
      streamController.add(VideoEvent(
        eventType: VideoEventType.seek,
        key: textureId.toString(),
        position: value.position,
      ));
      
      // Handle buffering
      if (value.isBuffering) {
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
      
      // Handle completion
      if (value.position >= value.duration && value.duration > Duration.zero) {
        streamController.add(VideoEvent(
          eventType: VideoEventType.completed,
          key: textureId.toString(),
        ));
      }
    });
  }

  @override
  Stream<VideoEvent> videoEventsFor(int? textureId) {
    if (textureId == null || _streamControllers[textureId] == null) {
      throw StateError('VideoPlayer for textureId $textureId is not found');
    }
    return _streamControllers[textureId]!.stream;
  }

  @override
  Future<void> setLooping(int? textureId, bool looping) async {
    final controller = _controllers[textureId];
    if (controller != null) {
      await controller.setLooping(looping);
    }
  }

  @override
  Future<void> play(int? textureId) async {
    final controller = _controllers[textureId];
    if (controller != null) {
      await controller.play();
    }
  }

  @override
  Future<void> pause(int? textureId) async {
    final controller = _controllers[textureId];
    if (controller != null) {
      await controller.pause();
    }
  }

  @override
  Future<void> setVolume(int? textureId, double volume) async {
    final controller = _controllers[textureId];
    if (controller != null) {
      await controller.setVolume(volume);
    }
  }

  @override
  Future<void> setSpeed(int? textureId, double speed) async {
    final controller = _controllers[textureId];
    if (controller != null) {
      await controller.setPlaybackSpeed(speed);
    }
  }

  @override
  Future<void> setTrackParameters(int? textureId, int? width, int? height, int? bitrate) async {
    // Track parameters not supported in standard video_player
  }

  @override
  Future<void> seekTo(int? textureId, Duration? position) async {
    if (position == null) return;
    final controller = _controllers[textureId];
    if (controller != null) {
      await controller.seekTo(position);
    }
  }

  @override
  Future<Duration> getPosition(int? textureId) async {
    final controller = _controllers[textureId];
    return controller?.value.position ?? Duration.zero;
  }

  @override
  Future<DateTime?> getAbsolutePosition(int? textureId) async {
    // Absolute position not supported
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

  @override
  Widget buildView(int? textureId) {
    final controller = _controllers[textureId];
    if (controller == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            'Video player not initialized',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: vp.VideoPlayer(controller),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}