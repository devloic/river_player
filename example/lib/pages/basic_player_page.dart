import 'package:river_player/river_player.dart';
import 'package:better_player_example/constants.dart';
import 'package:better_player_example/utils.dart';
import 'package:flutter/material.dart';

class BasicPlayerPage extends StatefulWidget {
  @override
  _BasicPlayerPageState createState() => _BasicPlayerPageState();
}

class _BasicPlayerPageState extends State<BasicPlayerPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Basic player"),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Offline Video Player (Local File):",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 250,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: FutureBuilder<String>(
              future: Utils.getFileUrl(Constants.fileTestVideoUrl),
              builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
                if (snapshot.hasError) {
                  // If local file fails (like on web), use online video
                  print("Local file failed, using online video: ${snapshot.error}");
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: BetterPlayer.network(
                      Constants.forBiggerBlazesUrl,
                      betterPlayerConfiguration: BetterPlayerConfiguration(
                        aspectRatio: 16 / 9,
                        fit: BoxFit.contain,
                        autoPlay: true,
                        looping: true,
                        placeholder: Container(
                          color: Colors.black,
                          child: const Center(
                            child: Text("Loading Online Video...", style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        controlsConfiguration: BetterPlayerControlsConfiguration(
                          showControls: true,
                          enableProgressText: true,
                          enableMute: true,
                          enableFullscreen: true,
                          controlBarColor: Colors.black54,
                        ),
                      ),
                    ),
                  );
                }
                if (snapshot.data != null) {
                  print("Loading video from: ${snapshot.data}");
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: BetterPlayer.file(
                      snapshot.data!,
                      betterPlayerConfiguration: BetterPlayerConfiguration(
                        aspectRatio: 16 / 9,
                        fit: BoxFit.contain,
                        autoPlay: true,
                        looping: true,
                        showPlaceholderUntilPlay: false,
                        placeholder: Container(
                          color: Colors.black,
                          child: const Center(
                            child: Text("Loading Local Video...", style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        controlsConfiguration: BetterPlayerControlsConfiguration(
                          showControls: true,
                          enableProgressText: true,
                          enableMute: true,
                          enableFullscreen: true,
                          controlBarColor: Colors.black54,
                        ),
                      ),
                    ),
                  );
                } else {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Video file: testvideo.mp4 (stored in Documents folder)",
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Note: If you hear audio but see blue/black screen, this is a known MediaKit texture rendering issue on some Linux configurations. The video is playing correctly.",
              style: TextStyle(fontSize: 12, color: Colors.orange[800]),
            ),
          )
          ],
        ),
      ),
    );
  }
}
