#include "include/river_player/river_player_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>

#define RIVER_PLAYER_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), river_player_plugin_get_type(), \
                               RiverPlayerPlugin))

struct _RiverPlayerPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(RiverPlayerPlugin, river_player_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void river_player_plugin_handle_method_call(
    RiverPlayerPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  // Get the method name (unused since we return not implemented for all methods)
  const gchar* method = fl_method_call_get_name(method_call);
  (void)method; // Mark as intentionally unused to avoid compiler warning

  // For now, just return not implemented for all methods
  // The actual video player functionality is handled by MediaKit
  response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());

  fl_method_call_respond(method_call, response, nullptr);
}

static void river_player_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(river_player_plugin_parent_class)->dispose(object);
}

static void river_player_plugin_class_init(RiverPlayerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = river_player_plugin_dispose;
}

static void river_player_plugin_init(RiverPlayerPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  RiverPlayerPlugin* plugin = RIVER_PLAYER_PLUGIN(user_data);
  river_player_plugin_handle_method_call(plugin, method_call);
}

void river_player_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  RiverPlayerPlugin* plugin = RIVER_PLAYER_PLUGIN(
      g_object_new(river_player_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "river_player",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}