#ifndef FLUTTER_PLUGIN_RIVER_PLAYER_PLUGIN_H_
#define FLUTTER_PLUGIN_RIVER_PLAYER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace river_player {

class RiverPlayerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  RiverPlayerPlugin();

  virtual ~RiverPlayerPlugin();

  // Disallow copy and assign.
  RiverPlayerPlugin(const RiverPlayerPlugin&) = delete;
  RiverPlayerPlugin& operator=(const RiverPlayerPlugin&) = delete;

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace river_player

#endif  // FLUTTER_PLUGIN_RIVER_PLAYER_PLUGIN_H_