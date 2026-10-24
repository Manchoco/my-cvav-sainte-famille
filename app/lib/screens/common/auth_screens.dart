import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'forgot_password_screen.dart';

/// Connexion / création de compte pour un rôle donné.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.role});
  final String role;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _register = false;
  bool get _isResp => widget.role == 'responsable';

  @override
  Widget build(BuildContext context) {
    final color = _isResp ? AppColors.primary : AppColors.gold;
    return Scaffold(
      appBar: AppBar(title: Text(_isResp ? 'Espace responsable' : 'Espace parent')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(_isResp ? Icons.groups_rounded : Icons.family_restroom_rounded, size: 42, color: color),
              ),
            ),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Se connecter'), icon: Icon(Icons.login_rounded)),
                ButtonSegment(value: true, label: Text('Créer un compte'), icon: Icon(Icons.person_add_alt_1_rounded)),
              ],
              selected: {_register},
              onSelectionChanged: (s) => setState(() => _register = s.first),
            ),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _register
                  ? _RegisterForm(key: const ValueKey('r'), role: widget.role)
                  : const _LoginForm(key: ValueKey('l')),
            ),
          ],
        ),
      ),
    );
  }
}

String? _phoneValidator(String? v) {
  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < 8) return 'Numéro de téléphone invalide';
  return null;
}

class _LoginForm extends StatefulWidget {
  const _LoginForm({super.key});
  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().login(_phone.text, _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(labelText: 'Numéro de téléphone', prefixIcon: Icon(Icons.phone_rounded), hintText: '07 00 00 00 00'),
            validator: _phoneValidator,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v ?? '').isEmpty ? 'Mot de passe requis' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Se connecter'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialPhone: _phone.text)),
            ),
            child: const Text('Mot de passe oublié ?'),
          ),
        ]),
      ),
    );
  }
}

class _RegisterForm extends StatefulWidget {
  const _RegisterForm({super.key, required this.role});
  final String role;
  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _code = TextEditingController();
  Legion? _legion;
  bool _busy = false;
  bool _obscure = true;

  bool get _isResp => widget.role == 'responsable';

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().register(
            role: widget.role,
            fullName: _name.text.trim(),
            phone: _phone.text,
            password: _password.text,
            legion: _legion,
            signupCode: _isResp ? _code.text.trim() : null,
          );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nom et prénoms', prefixIcon: Icon(Icons.person_rounded)),
          validator: (v) => (v ?? '').trim().length < 2 ? 'Nom requis' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Numéro de téléphone', prefixIcon: Icon(Icons.phone_rounded), hintText: '07 00 00 00 00'),
          validator: _phoneValidator,
        ),
        if (_isResp) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<Legion>(
            initialValue: _legion,
            decoration: const InputDecoration(labelText: 'Ma légion', prefixIcon: Icon(Icons.flag_rounded)),
            items: [for (final l in Legion.values) DropdownMenuItem(value: l, child: Text(l.label))],
            onChanged: (v) => setState(() => _legion = v),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _code,
            decoration: const InputDecoration(
              labelText: 'Code d\'accès responsable',
              prefixIcon: Icon(Icons.verified_user_rounded),
              helperText: 'Fourni par l\'aumônier ou le chef de section',
            ),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Code requis' : null,
          ),
        ],
        const SizedBox(height: 14),
        TextFormField(
          controller: _password,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Mot de passe (8 caractères min.)',
            prefixIcon: const Icon(Icons.lock_rounded),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          validator: (v) => (v ?? '').length < 8 ? 'Au moins 8 caractères' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _password2,
          obscureText: _obscure,
          decoration: const InputDecoration(labelText: 'Confirmer le mot de passe', prefixIcon: Icon(Icons.lock_outline_rounded)),
          validator: (v) => v != _password.text ? 'Les mots de passe ne correspondent pas' : null,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Créer mon compte'),
        ),
        if (!_isResp) ...[
          const SizedBox(height: 16),
          const Text(
            'Après la création du compte, ajoutez vos enfants avec le code enfant remis par le responsable de leur légion.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ]),
    );
  }
}
