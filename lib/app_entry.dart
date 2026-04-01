// Conditional export: resolves to the mobile app on native platforms and the
// web management dashboard when compiled for Flutter web.
//
// Both targets export a KitchenGuardApp widget used as the root of the
// widget tree in main.
export 'app.dart' if (dart.library.js_interop) 'web/web_app.dart';
