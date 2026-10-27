import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/auth_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/crt.dart';

const _bootLines = [
  'NIDO // TERMINAL DE PATRIMONIO v1.0',
  'COMPROBANDO CINTA ............... OK',
  'SINCRONIZACIÓN MÓVIL <> PC ...... OK',
  'MODO SIN CONEXIÓN ............ LISTO',
  'CIFRADO DE SESIÓN ............... OK',
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    try {
      if (_register) {
        await auth.register(_email.text, _password.text);
      } else {
        await auth.signIn(_email.text, _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Escribe tu correo arriba para recibir el enlace.');
      return;
    }
    try {
      await context.read<AuthService>().sendPasswordReset(_email.text);
      showMessage('Te hemos enviado un correo para restablecer la contraseña.');
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = _form(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1040 : 440),
              child: wide
                  ? IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Expanded(flex: 6, child: _BootPanel()),
                        const SizedBox(width: 20),
                        Expanded(flex: 5, child: form),
                      ]),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Center(child: NidoWordmark(size: 40)),
                      const SizedBox(height: 8),
                      Text(
                        'Tu patrimonio, sincronizado entre el móvil y el ordenador.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Crt.beige),
                      ),
                      const SizedBox(height: 20),
                      form,
                    ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              PromptLabel(_register ? 'Nueva cuenta' : 'Acceso', cursor: true, color: Crt.green),
              const SizedBox(height: 18),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('TENGO CUENTA')),
                  ButtonSegment(value: true, label: Text('SOY NUEVO')),
                ],
                selected: {_register},
                showSelectedIcon: false,
                onSelectionChanged: _busy ? null : (s) => setState(() {
                  _register = s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 20),
              LabeledField(
                label: 'Correo electrónico',
                child: TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(hintText: 'tu@correo.com'),
                  style: mono(size: 16, color: Crt.offWhite),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v != null && v.contains('@')) ? null : 'Escribe un correo válido',
                ),
              ),
              const SizedBox(height: 14),
              LabeledField(
                label: 'Contraseña',
                hint: _register ? 'Mínimo 6 caracteres. Aquí van tus finanzas: usa una buena.' : null,
                child: TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  style: mono(size: 16, color: Crt.offWhite),
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) => (v != null && v.length >= 6) ? null : 'Mínimo 6 caracteres',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Crt.redText),
                  ),
                  child: Text('ERROR: $_error', style: theme.textTheme.bodyMedium?.copyWith(color: Crt.redText)),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _busy
                    ? const TapeReels(width: 56, label: null)
                    : Text(_register ? 'CREAR CUENTA' : 'ENTRAR'),
              ),
              if (!_register) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _resetPassword,
                  style: TextButton.styleFrom(foregroundColor: Crt.beige),
                  child: const Text('HE OLVIDADO MI CONTRASEÑA'),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Panel de arranque con las líneas del "sistema" escribiéndose solas.
class _BootPanel extends StatelessWidget {
  const _BootPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CrtScreen(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NidoWordmark(size: 44),
        const SizedBox(height: 10),
        Text(
          'Cuentas, inversiones, bienes y deudas en un solo sitio. Lo que apuntas en el móvil aparece al momento en el ordenador.',
          style: theme.textTheme.bodyLarge?.copyWith(color: Crt.beige),
        ),
        const SizedBox(height: 28),
        const _Typewriter(lines: _bootLines),
        const Spacer(),
        const SizedBox(height: 28),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const TapeReels(width: 132, label: 'CINTA 01 // LADO A'),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('MEMORIA', style: theme.textTheme.labelSmall),
            Text('EUR · ES', style: mono(size: 13, color: Crt.amber)),
          ]),
        ]),
      ]),
    );
  }
}

class _Typewriter extends StatefulWidget {
  const _Typewriter({required this.lines});

  final List<String> lines;

  @override
  State<_Typewriter> createState() => _TypewriterState();
}

class _TypewriterState extends State<_Typewriter> with SingleTickerProviderStateMixin {
  late final int _total = widget.lines.fold(0, (n, l) => n + l.length);
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: _total * 22));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
    } else if (_c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = mono(size: 14, color: Crt.green, height: 1.7).copyWith(shadows: glow(Crt.green, blur: 4));
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        var left = (_c.value * _total).round();
        final shown = <String>[];
        for (final l in widget.lines) {
          if (left <= 0) break;
          shown.add(l.substring(0, left.clamp(0, l.length)));
          left -= l.length;
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in shown) Text('> $l', style: style),
          if (_c.isCompleted)
            Row(children: [Text('> INTRODUCE TUS DATOS ', style: style), const BlinkingCursor(size: 16)]),
        ]);
      },
    );
  }
}
