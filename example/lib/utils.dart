import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class Utils {
  static Future<String> getFileUrl(String fileName) async {
    try {
      if (kIsWeb) {
        // On web, we can't access local files, so return the asset path
        // This would need to be served by the web server
        return "assets/$fileName";
      } else {
        final directory = await getApplicationDocumentsDirectory();
        return "${directory.path}/$fileName";
      }
    } catch (e) {
      // Fallback for platforms without file system access
      return "assets/$fileName";
    }
  }
}
