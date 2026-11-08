import 'package:flutter/material.dart';

import 'src/screens/home_shell.dart';
import 'src/screens/login_screen.dart';
import 'src/services/app_state.dart';
import 'src/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await authService.init();
  // セッションが残っている場合は自動ログイン（domain状態を復元してホームへ）
  final restored = authService.buildSessionUser(
    lat: appState.anchorLat,
    lng: appState.anchorLng,
  );
  if (restored != null) {
    appState.attachUser(restored, reseed: true);
  }
  runApp(const MeshitomoApp());
}

class MeshitomoApp extends StatelessWidget {
  const MeshitomoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'めしとも（プロトタイプ）',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD9480F),
        ),
      ),
      home: ListenableBuilder(
        listenable: Listenable.merge([appState, authService]),
        builder: (_, _) =>
            appState.me == null ? const LoginScreen() : const HomeShell(),
      ),
    );
  }
}
