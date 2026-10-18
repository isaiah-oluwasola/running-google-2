import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/auth_screens.dart';
import 'services/backend.dart';
import 'theme.dart';
import 'widgets/call_overlay.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // reads android/app/google-services.json
  await Backend.init();
  await AppState.instance.loadPrefs();
  runApp(const HeyApp());
}

class HeyApp extends StatelessWidget {
  const HeyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) => MaterialApp(
        title: 'HeyApp',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: AppState.instance.themeMode,
        home: const AuthGate(),
        builder: (context, child) => Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const CallOverlay(),
          ],
        ),
      ),
    );
  }
}
