import 'package:flutter/material.dart';

import 'data/client.dart';
import 'game/lobby_screen.dart';
import 'game/login_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SpectreApp(client: SpectreClient()..boot()));
}

class SpectreApp extends StatelessWidget {
  const SpectreApp({super.key, required this.client});
  final SpectreClient client;

  @override
  Widget build(BuildContext context) {
    return ClientScope(
      client: client,
      child: ListenableBuilder(
        listenable: client,
        builder: (context, _) => MaterialApp(
          title: client.config.brandName,
          debugShowCheckedModeBanner: false,
          theme: buildSpectreTheme(),
          builder: (context, child) => Brand(
            background: parseHexColor(client.config.backgroundColor),
            backgroundImage: client.config.backgroundImageUrl,
            logo: client.config.logoUrl,
            child: child!,
          ),
          home: const _Gate(),
        ),
      ),
    );
  }
}

/// Oturum yoksa giriş ekranı, varsa lobi.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final c = ClientScope.of(context);
    Widget child;
    if (c.booting) {
      child = const Scaffold(
        key: ValueKey('boot'),
        body: SpectreBackground(child: Center(child: CircularProgressIndicator())),
      );
    } else if (c.me == null) {
      child = const LoginScreen(key: ValueKey('login'));
    } else {
      child = const LobbyScreen(key: ValueKey('lobby'));
    }
    return AnimatedSwitcher(duration: SpectreMotion.slow, child: child);
  }
}
