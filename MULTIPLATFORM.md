# River Player Multiplatform Support

River Player now supports all platforms through a hybrid approach:
- **Android & iOS**: Native implementation via method channels
- **Windows, macOS, Linux & Web**: MediaKit-based implementation

## Quick Start

### 1. Add dependencies

Add these to your `pubspec.yaml`:

```yaml
dependencies:
  river_player: ^0.1.4
  # Platform-specific MediaKit libraries
  media_kit_libs_windows_video: ^1.0.5  # Windows
  media_kit_libs_macos_video: ^1.0.5    # macOS  
  media_kit_libs_linux: ^1.0.5          # Linux
  media_kit_libs_video: ^1.0.5          # Universal fallback
```

### 2. Initialize in main()

```dart
import 'package:river_player/river_player.dart';

void main() {
  // Initialize River Player for all platforms
  RiverPlayerPlatform.ensureInitialized();
  
  runApp(MyApp());
}
```

### 3. Use normally

River Player API remains the same - the platform detection is automatic:

```dart
import 'package:river_player/river_player.dart';

class VideoPlayerWidget extends StatefulWidget {
  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late BetterPlayerController _controller;

  @override
  void initState() {
    super.initState();
    
    // Same API across all platforms
    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        aspectRatio: 16 / 9,
        fit: BoxFit.contain,
      ),
    );
    
    // Setup data source
    _controller.setupDataSource(
      BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BetterPlayer(controller: _controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

## Platform Detection

You can check which implementation is being used:

```dart
import 'package:river_player/river_player.dart';

// Check platform type
print('Platform: ${RiverPlayerPlatform.platformDescription}');
print('Using native: ${RiverPlayerPlatform.isNativePlatform}');
print('Using MediaKit: ${RiverPlayerPlatform.isMediaKitPlatform}');
```

## Supported Features by Platform

| Feature | Android | iOS | Windows | macOS | Linux | Web |
|---------|---------|-----|---------|-------|--------|-----|
| Basic Playback | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| HLS/DASH | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Subtitles | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Controls | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Picture-in-Picture | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Background Audio | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Caching | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| DRM | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |

## Technical Details

### Architecture

```
River Player
├── Android/iOS (Native)
│   ├── ExoPlayer (Android)
│   └── AVPlayer (iOS)
└── Desktop/Web (MediaKit)
    ├── libmpv (Windows/Linux)
    ├── AVPlayer (macOS)
    └── Media Source Extensions (Web)
```

### Platform Selection Logic

The platform is automatically detected at runtime:

```dart
// In VideoPlayerPlatform.instance getter:
if (UniversalPlatform.isAndroid || UniversalPlatform.isIOS) {
  // Use native implementation
  return MethodChannelVideoPlayer();
} else {
  // Use MediaKit implementation for desktop/web
  return MediaKitVideoPlayer();
}
```

## Migration from Better Player

River Player maintains full API compatibility with Better Player, so existing code should work without changes. Just update your imports:

```dart
// Old
import 'package:better_player/better_player.dart';

// New  
import 'package:river_player/river_player.dart';
```

## Troubleshooting

### Desktop Issues

If you encounter issues on desktop platforms:

1. Ensure you've added the correct platform libraries to `pubspec.yaml`
2. For Linux, you may need additional system dependencies:
   ```bash
   sudo apt-get update
   sudo apt-get install libmpv-dev mpv
   ```

### Web Issues

Web support is experimental. For better web support, consider using the native HTML5 video element for simple use cases.

### Performance

- Native platforms (Android/iOS) offer the best performance and battery efficiency
- Desktop platforms using MediaKit provide good performance with broad codec support
- Web performance depends on browser Media Source Extensions support

## Contributing

When contributing to multiplatform support:

1. Test on all target platforms
2. Keep API compatibility with existing Better Player code
3. Platform-specific features should gracefully degrade on unsupported platforms
4. Update platform support matrix in documentation