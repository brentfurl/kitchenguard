import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_entry.dart';
import 'firebase_options.dart';
import 'main_mobile.dart' if (dart.library.js_interop) 'main_web.dart'
    as platform;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await platform.initPlatform();

  runApp(const ProviderScope(child: KitchenGuardApp()));
}
