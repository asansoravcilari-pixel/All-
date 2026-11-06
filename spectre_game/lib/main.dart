import 'package:flutter/material.dart';

import 'data/backend.dart';
import 'game/lobby_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SpectreApp(backend: SpectreBackend()));
}

class SpectreApp extends StatelessWidget {
  const SpectreApp({super.key, required this.backend});
  final SpectreBackend backend;

  @override
  Widget build(BuildContext context) {
    return BackendScope(
      backend: backend,
      child: MaterialApp(
        title: 'SPECTRE',
        debugShowCheckedModeBanner: false,
        theme: buildSpectreTheme(),
        home: const LobbyScreen(),
      ),
    );
  }
}
