import Cocoa
import FlutterMacOS

public class RiverPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "river_player", binaryMessenger: registrar.messenger)
    let instance = RiverPlayerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // For now, just return not implemented for all methods
    // The actual video player functionality is handled by MediaKit
    result(FlutterMethodNotImplemented)
  }
}