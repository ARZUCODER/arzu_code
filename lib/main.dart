import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'services/environment_service.dart';
import 'theme/app_theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase native init failed (Ignored, Dart API will work): $e');
  }

  EnvironmentService.detect();

  runApp(const ProviderScope(child: ArzuCodeApp()));
}

class ArzuCodeApp extends StatelessWidget {
  const ArzuCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arzu Code',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}