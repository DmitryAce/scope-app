import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'settings.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final store = StoreScope.read(context);
    _user.text = store.username ?? '';
    _error = store.error;
    store.api.resolve(force: true).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _login() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Введите логин и пароль');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await StoreScope.read(context).login(_user.text, _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // Мягкое свечение фона, как на веб-версии.
        Positioned(
          top: -140,
          left: -100,
          child: _Glow(color: C.accent.withValues(alpha: 0.16), size: 380),
        ),
        Positioned(
          bottom: -160,
          right: -120,
          child: _Glow(color: C.logo.withValues(alpha: 0.14), size: 420),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Center(child: ScopeLogo(size: 72)),
                const SizedBox(height: 22),
                const Center(
                  child: Text('Scope',
                      style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1)),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _user,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Логин',
                    prefixIcon: Icon(PhosphorIconsRegular.user, color: C.text2),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: _hide,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    hintText: 'Пароль',
                    prefixIcon: const Icon(PhosphorIconsRegular.lockSimple, color: C.text2),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _hide = !_hide),
                      icon: Icon(_hide ? PhosphorIconsRegular.eye : PhosphorIconsRegular.eyeSlash,
                          color: C.text2),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _error == null
                      ? const SizedBox(height: 20)
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(children: [
                            const Icon(PhosphorIconsRegular.warningCircle, color: C.urgent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: const TextStyle(color: C.urgent))),
                          ]),
                        ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: C.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('Войти', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: ConnectionPill(
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const ServerSettingsScreen())),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );
}
