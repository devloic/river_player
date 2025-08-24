import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:river_player/river_player.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'River Player DASH Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DashPlayerDemo(),
    );
  }
}

class DashPlayerDemo extends StatefulWidget {
  const DashPlayerDemo({super.key});

  @override
  State<DashPlayerDemo> createState() => _DashPlayerDemoState();
}

class _DashPlayerDemoState extends State<DashPlayerDemo> {
  WindowsDashVideoController? _controller;
  bool _isLoading = true;
  String? _error;
  int _currentUrlIndex = 0;

  // Sample DASH manifest URLs for testing
  final List<String> _dashUrls = [
    'http://dash.akamaized.net/dash264/TestCases/1a/qualcomm/1/MultiRate.mpd',
    'http://ftp.itec.aau.at/datasets/DASHDataset2014/BigBuckBunny/2sec/BigBuckBunny_2s_onDemand_2014_05_09.mpd',
    'http://y.lolo.asia/api/manifest/dash/id/LN_HedbXBkg',
    'https://y.lolo.asia/api/manifest/dash/id/w860o1CceTk',
    'https://y.lolo.asia/api/manifest/dash/id/F8pum4jbpnw',
  ];

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Check if we're on Windows - if not, show platform info
      if (!UniversalPlatform.isWindows) {
        setState(() {
          _error = 'This example is designed for Windows platform with DASH streaming support.\n'
                  'Current platform: ${UniversalPlatform.operatingSystem}\n'
                  'VideoWin package only supports Windows.';
          _isLoading = false;
        });
        return;
      }

      // Create and initialize the controller
      _controller = WindowsDashVideoController();
      
      // Setup DASH streaming with the current URL
      final manifestUrl = _dashUrls[_currentUrlIndex];
      await _controller!.setupDashStream(
        manifestUrl,
        targetResolution: 720,
        includeAudio: true,
      );

      setState(() {
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _error = 'Failed to initialize DASH player: $e';
        _isLoading = false;
      });
    }
  }

  void _switchUrl() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }

    setState(() {
      _currentUrlIndex = (_currentUrlIndex + 1) % _dashUrls.length;
    });

    await _initializePlayer();
  }

  void _togglePlayPause() {
    if (_controller == null || _controller!.videoController == null) return;

    final videoController = _controller!.videoController!;
    if (videoController.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return "${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}";
    } else {
      return "${twoDigits(minutes)}:${twoDigits(seconds)}";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('River Player DASH Example'),
      ),
      body: Center(
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading DASH stream...'),
        ],
      );
    }

    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            'Error',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: SelectableText(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initializePlayer,
            child: const Text('Retry'),
          ),
        ],
      );
    }

    if (_controller == null || _controller!.videoController == null || !_controller!.videoController!.value.isInitialized) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Initializing video player...'),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Video Player
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            constraints: const BoxConstraints(
              maxHeight: 400,
              maxWidth: 800,
            ),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: WindowsDashVideoPlayer(controller: _controller!),
            ),
          ),

          const SizedBox(height: 20),

          // Player Info
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Player Status',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _controller!.videoController!.value.isPlaying
                            ? Icons.play_arrow
                            : Icons.pause,
                        color: _controller!.videoController!.value.isPlaying
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _controller!.videoController!.value.isPlaying ? 'Playing' : 'Paused',
                        style: TextStyle(
                          color: _controller!.videoController!.value.isPlaying
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      const Spacer(),
                      if (_controller!.isDualPlayback)
                        const Row(
                          children: [
                            Icon(Icons.sync, color: Colors.blue),
                            SizedBox(width: 4),
                            Text('Dual Playback', style: TextStyle(color: Colors.blue)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_controller!.videoController!.value.duration != null)
                    Text(
                      'Duration: ${_formatDuration(_controller!.videoController!.value.duration!)}',
                    ),
                  Text(
                    'Position: ${_formatDuration(_controller!.videoController!.value.position)}',
                  ),
                  if (_controller!.videoController!.value.size != null)
                    Text(
                      'Resolution: ${_controller!.videoController!.value.size!.width.toInt()}x${_controller!.videoController!.value.size!.height.toInt()}',
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: Icon(
                  _controller!.videoController!.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
                label: Text(
                  _controller!.videoController!.value.isPlaying ? 'Pause' : 'Play',
                ),
                onPressed: _togglePlayPause,
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.skip_next),
                label: const Text('Switch URL'),
                onPressed: _switchUrl,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Current URL Info
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current DASH Stream (${_currentUrlIndex + 1}/${_dashUrls.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getUrlDescription(_dashUrls[_currentUrlIndex]),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: _getUrlColor(_dashUrls[_currentUrlIndex]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _dashUrls[_currentUrlIndex],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'This example demonstrates River Player with VideoWin integration:\n'
              '• Windows DASH streaming support\n'
              '• VideoWin package integration\n'
              '• Dual stream audio/video playback\n'
              '• Multiple DASH manifest formats\n'
              '• Audio-video synchronization',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String _getUrlDescription(String url) {
    if (url.contains('akamaized.net')) {
      return 'Akamai Test Stream (SegmentTemplate)';
    } else if (url.contains('ftp.itec')) {
      return 'ITEC BigBuckBunny (BaseURL)';
    } else if (url.contains('y.lolo.asia')) {
      return 'Y.Lolo.Asia Stream (BaseURL)';
    }
    return 'Unknown Stream';
  }

  Color _getUrlColor(String url) {
    if (url.contains('akamaized.net')) {
      return Colors.blue;
    } else if (url.contains('ftp.itec')) {
      return Colors.green;
    } else if (url.contains('y.lolo.asia')) {
      return Colors.orange;
    }
    return Colors.grey;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}