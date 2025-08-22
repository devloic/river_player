import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:better_player_example/utils.dart';
import 'package:better_player_example/constants.dart';

/// Test page to see if raw MediaKit Video widget works directly
class RawMediaKitTestPage extends StatefulWidget {
  @override
  _RawMediaKitTestPageState createState() => _RawMediaKitTestPageState();
}

class _RawMediaKitTestPageState extends State<RawMediaKitTestPage> {
  late Player player;
  late VideoController controller;

  @override
  void initState() {
    super.initState();
    // Try different MediaKit configuration for Linux video rendering
    player = Player(
      configuration: PlayerConfiguration(
        // Force software rendering to fix Linux texture issues
        osc: false,
        title: 'MediaKit Test',
        logLevel: MPVLogLevel.info,
      ),
    );
    controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        // Additional video configuration
        enableHardwareAcceleration: false,
      ),
    );
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final videoPath = await Utils.getFileUrl(Constants.fileTestVideoUrl);
      print('Raw MediaKit Test - Loading: $videoPath');
      await player.open(Media(videoPath), play: true);
    } catch (e) {
      print('Raw MediaKit Test - Error: $e');
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
        title: const Text("Raw MediaKit Test"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Direct MediaKit Video Widget Test",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.black,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Video(
                  controller: controller,
                  fit: BoxFit.contain,
                  fill: Colors.black,
                  alignment: Alignment.center,
                  // Additional properties to fix rendering
                  aspectRatio: 16.0 / 9.0,
                  filterQuality: FilterQuality.low,
                  // Try different controls to see if it affects rendering
                  controls: AdaptiveVideoControls,
                ),
              ),
            ),
            const SizedBox(height: 16),
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
                  onPressed: () => player.seek(Duration.zero),
                  child: const Text("Reset"),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 8),
            const Text(
              "If you see video here, MediaKit works directly.\nIf not, it's a deeper MediaKit/Linux compatibility issue.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}