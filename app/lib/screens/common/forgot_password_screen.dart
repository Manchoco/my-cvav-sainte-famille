import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Mot de passe oublié : 1) numéro -> code SMS  2) code + nouveau mot de passe.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialPhone});
  final String? initialPhone;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.initialPhone);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  bool _obscure = true;

  Future<void> _sendCode() async {
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 8) {
      showMessage(context, 'Numéro de téléphone invalide', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<Session>().requestPasswordReset(_phone.text);
      if (!mounted) return;
      setState(() => _codeSent = true);
      showMessage(context, 'Si ce numéro a un compte, un code vient de lui être envoyé par SMS.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().resetPassword(_phone.text, _code.text.trim(), _password.text);
      if (!mounted) return;
      showMessage(context, 'Mot de passe modifié. Bienvenue !');
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 32), children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(_codeSent ? Icons.sms_rounded : Icons.lock_reset_rounded, size: 40, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _codeSent
                ? 'Saisissez le code à 6 chiffres reçu par SMS et choisissez un nouveau mot de passe.'
                : 'Indiquez le numéro de votre compte : nous vous enverrons un code par SMS.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 15),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _phone,
            enabled: !_codeSent,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Numéro de téléphone', prefixIcon: Icon(Icons.phone_rounded), hintText: '07 00 00 00 00'),
          ),
          if (!_codeSent) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _sendCode,
              child: _busy ? const CircularProgressIndicator(color: Colors.white) : const Text('Recevoir le code'),
            ),
          ] else ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _code,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(labelText: 'Code SMS', counterText: ''),
              validator: (v) => (v ?? '').length != 6 ? 'Le code contient 6 chiffres' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe (8 caractères min.)',
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
              onPressed: _busy ? null : _reset,
              child: _busy ? const CircularProgressIndicator(color: Colors.white) : const Text('Changer mon mot de passe'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _codeSent = false;
                        _code.clear();
                      }),
              child: const Text('Pas reçu ? Renvoyer un code'),
            ),
          ],
        ]),
      ),
    );
  }
}
