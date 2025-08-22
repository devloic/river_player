#include "river_player_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace river_player {

// static
void RiverPlayerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "river_player",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<RiverPlayerPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

RiverPlayerPlugin::RiverPlayerPlugin() {}

RiverPlayerPlugin::~RiverPlayerPlugin() {}

void RiverPlayerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Get the method name (unused since we return not implemented for all methods)
  const std::string method_name = method_call.method_name();
  (void)method_name; // Mark as intentionally unused to avoid compiler warning

  // For now, just return not implemented for all methods
  // The actual video player functionality is handled by MediaKit
  result->NotImplemented();
}

}  // namespace river_player