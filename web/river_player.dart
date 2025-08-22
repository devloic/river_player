import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// A web implementation of the RiverPlayer plugin.
class RiverPlayerWeb {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'river_player',
      const StandardMethodCodec(),
      registrar,
    );

    final pluginInstance = RiverPlayerWeb();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  /// Handles method calls over the MethodChannel of this plugin.
  Future<dynamic> handleMethodCall(MethodCall call) async {
    // For now, just return not implemented for all methods
    // The actual video player functionality is handled by MediaKit
    throw PlatformException(
      code: 'Unimplemented',
      details: 'river_player for web doesn\'t implement \'${call.method}\'',
    );
  }
}