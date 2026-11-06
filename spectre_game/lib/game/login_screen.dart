import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/client.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'social.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _passFocus = FocusNode();

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _name.dispose();
    _email.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && _error != null) _passFocus.requestFocus();
    }
  }

  void _submit() {
    final c = ClientScope.read(context);
    final u = _user.text.trim();
    final p = _pass.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Kullanıcı adı ve şifre gerekli');
      return;
    }
    _run(() => _register ? c.register(u, p, _name.text.trim(), email: _email.text.trim()) : c.login(u, p));
  }

  @override
  Widget build(BuildContext context) {
    final c = ClientScope.of(context);
    final cfg = c.config;
    return Scaffold(
      body: SpectreBackground(
        animate: !c.lightMode,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: BrandLogo(text: cfg.brandName, size: 40, letterSpacing: 8)),
                    if (cfg.tagline.isNotEmpty)
                      Text(cfg.tagline, textAlign: TextAlign.center, style: const TextStyle(color: SpectreColors.muted)),
                    const SizedBox(height: 24),
                    if (cfg.maintenance)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassPanel(
                          tint: SpectreColors.amber.withOpacity(0.3),
                          child: Row(children: [
                            const Icon(Icons.construction_rounded, color: SpectreColors.amber),
                            const SizedBox(width: 10),
                            Expanded(child: Text(cfg.maintenanceText)),
                          ]),
                        ),
                      ),
                    GlassPanel(
                      padding: const EdgeInsets.all(20),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<bool>(
                              segments: [
                                ButtonSegment(value: false, label: Text(cfg.t('login.title', 'Giriş yap'))),
                                ButtonSegment(value: true, label: Text(cfg.t('login.register', 'Kayıt ol')), enabled: cfg.registrationOpen),
                              ],
                              selected: {_register},
                              onSelectionChanged: (s) => setState(() {
                                _register = s.first;
                                _error = null;
                              }),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _user,
                              autofillHints: const [AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                  labelText: 'Kullanıcı adı', prefixIcon: Icon(Icons.person_rounded)),
                            ),
                            const SizedBox(height: 10),
                            if (_register) ...[
                              TextField(
                                controller: _name,
                                textInputAction: TextInputAction.next,
                                maxLength: 20,
                                decoration: const InputDecoration(
                                    labelText: 'Görünen ad (isteğe bağlı)',
                                    counterText: '',
                                    prefixIcon: Icon(Icons.badge_rounded)),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                    labelText: cfg.requireEmail ? 'E-posta' : 'E-posta (şifre sıfırlama için önerilir)',
                                    prefixIcon: const Icon(Icons.alternate_email_rounded)),
                              ),
                              const SizedBox(height: 10),
                            ],
                            TextField(
                              controller: _pass,
                              focusNode: _passFocus,
                              obscureText: _hide,
                              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                              onSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Şifre',
                                helperText: _register ? 'En az 8 karakter' : null,
                                prefixIcon: const Icon(Icons.lock_rounded),
                                suffixIcon: IconButton(
                                  icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                                  onPressed: () => setState(() => _hide = !_hide),
                                ),
                              ),
                            ),
                            AnimatedSize(
                              duration: SpectreMotion.normal,
                              child: _error == null
                                  ? const SizedBox(height: 16)
                                  : Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      child: Text(_error!, style: const TextStyle(color: SpectreColors.red)),
                                    ),
                            ),
                            PressButton(
                              onTap: _busy ? null : _submit,
                              child: Center(
                                child: _busy
                                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(_register ? 'Hesap oluştur' : cfg.t('login.title', 'Giriş yap')),
                              ),
                            ),
                            if (!_register && cfg.mailReady)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => showForgotPassword(context, c),
                                  child: const Text('Şifremi unuttum'),
                                ),
                              ),
                            if (cfg.guestLogin) ...[
                              const SizedBox(height: 10),
                              PressButton(
                                filled: false,
                                glow: false,
                                onTap: _busy ? null : () => _run(c.guest),
                                child: Center(child: Text(cfg.t('login.guest', 'Misafir olarak devam et'))),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (c.lastError != null && c.config.j.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('Sunucuya ulaşılamıyor: ${c.lastError}',
                            textAlign: TextAlign.center, style: const TextStyle(color: SpectreColors.red)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
