import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:better_player_example/utils.dart';
import 'package:better_player_example/constants.dart';

/// Test page with aggressive MediaKit fixes for Linux video rendering
class FixedMediaKitTestPage extends StatefulWidget {
  @override
  _FixedMediaKitTestPageState createState() => _FixedMediaKitTestPageState();
}

class _FixedMediaKitTestPageState extends State<FixedMediaKitTestPage> {
  late Player player;
  late VideoController controller;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() {
    // Try multiple approaches to fix Linux video rendering
    player = Player(
      configuration: PlayerConfiguration(
        title: 'Fixed MediaKit Test',
        logLevel: MPVLogLevel.debug,
        // Try to force specific rendering pipeline
        osc: false,
      ),
    );
    
    controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: false, // Force software
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );
    
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    try {
      final videoPath = await Utils.getFileUrl(Constants.fileTestVideoUrl);
      print('Fixed MediaKit Test - Loading: $videoPath');
      await player.open(Media(videoPath), play: true);
    } catch (e) {
      print('Fixed MediaKit Test - Error: $e');
      // Try alternative approach with online video
      try {
        print('Trying online video fallback...');
        await player.open(Media('https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'), play: true);
      } catch (e2) {
        print('Fixed MediaKit Test - Fallback Error: $e2');
      }
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fixed MediaKit Test"),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "MediaKit with Linux Video Fixes",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Attempting: software rendering + X11 video output + EGL backend",
              style: TextStyle(fontSize: 12, color: Colors.blue),
            ),
            const SizedBox(height: 16),
            
            // Video Container 1: Standard approach
            Container(
              height: 200,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.black,
              ),
              child: Video(
                controller: controller,
                fit: BoxFit.contain,
                fill: Colors.black,
                controls: NoVideoControls,
              ),
            ),
            
            // Video Container 2: Alternative approach
            Container(
              height: 200,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[900],
              ),
              child: Video(
                controller: controller,
                fit: BoxFit.cover,
                fill: Colors.transparent,
                controls: MaterialVideoControls,
                aspectRatio: 16/9,
                filterQuality: FilterQuality.low,
              ),
            ),
            
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => player.play(),
                  child: const Text("Play"),
                ),
                ElevatedButton(
                  onPressed: () => player.pause(),
                  child: const Text("Pause"),
                ),
                ElevatedButton(
                  onPressed: () => _reloadVideo(),
                  child: const Text("Reload"),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Status info
            StreamBuilder(
              stream: player.stream.position,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                return Text("Position: ${position.toString().substring(2, 7)}");
              },
            ),
            StreamBuilder(
              stream: player.stream.duration,
              builder: (context, snapshot) {
                final duration = snapshot.data ?? Duration.zero;
                return Text("Duration: ${duration.toString().substring(2, 7)}");
              },
            ),
            StreamBuilder(
              stream: player.stream.playing,
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return Text("Playing: $playing", 
                  style: TextStyle(color: playing ? Colors.green : Colors.red));
              },
            ),
            
            const SizedBox(height: 16),
            const Text(
              "Red border: NoVideoControls | Green border: MaterialVideoControls\nTesting different rendering approaches simultaneously.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _reloadVideo() async {
    await player.stop();
    await Future.delayed(const Duration(milliseconds: 500));
    await _loadVideo();
  }
}