import 'package:flutter/material.dart';
import 'package:river_player/river_player.dart';

class PlatformInfoPage extends StatelessWidget {
  const PlatformInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("River Player Platform Info"),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Multiplatform Support Status',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      'Platform',
                      RiverPlayerPlatform.platformDescription,
                      Icons.devices,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      'Initialized',
                      RiverPlayerPlatform.isInitialized ? 'Yes' : 'No',
                      RiverPlayerPlatform.isInitialized 
                          ? Icons.check_circle 
                          : Icons.error,
                      color: RiverPlayerPlatform.isInitialized 
                          ? Colors.green 
                          : Colors.red,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      'Implementation',
                      RiverPlayerPlatform.isNativePlatform 
                          ? 'Native (ExoPlayer/AVPlayer)' 
                          : 'MediaKit (libmpv/MSE)',
                      RiverPlayerPlatform.isNativePlatform 
                          ? Icons.phone_android 
                          : Icons.desktop_windows,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      'Cross-Platform',
                      RiverPlayerPlatform.isMediaKitPlatform 
                          ? 'Desktop/Web Support' 
                          : 'Mobile Only',
                      RiverPlayerPlatform.isMediaKitPlatform 
                          ? Icons.laptop 
                          : Icons.smartphone,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Platform Features',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildFeatureRow('Basic Playback', true),
                    _buildFeatureRow('HLS/DASH Streaming', true),
                    _buildFeatureRow('Subtitles', true),
                    _buildFeatureRow('Custom Controls', true),
                    _buildFeatureRow(
                      'Picture-in-Picture', 
                      RiverPlayerPlatform.isNativePlatform,
                    ),
                    _buildFeatureRow(
                      'Background Audio', 
                      true,
                    ),
                    _buildFeatureRow(
                      'Caching', 
                      RiverPlayerPlatform.isNativePlatform,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.video_library),
                label: const Text('Try Video Examples'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.blue),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: color ?? Colors.black87,
              fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureRow(String feature, bool supported) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            supported ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: supported ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(feature),
        ],
      ),
    );
  }
}