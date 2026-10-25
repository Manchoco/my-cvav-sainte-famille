import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

const _playStoreAuthenticator = 'https://play.google.com/store/apps/details?id=com.google.android.apps.authenticator2';

/// Double vérification administrateur par application d'authentification (Google Authenticator, Microsoft Authenticator…).
class TotpScreen extends StatefulWidget {
  const TotpScreen({super.key});

  @override
  State<TotpScreen> createState() => _TotpScreenState();
}

class _TotpScreenState extends State<TotpScreen> {
  ({String secret, String uri})? _setup;
  final _code = TextEditingController();
  bool _busy = false;

  Future<String?> _askPassword(String title) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Mot de passe actuel')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuer')),
        ],
      ),
    );
    return ok == true && ctrl.text.isNotEmpty ? ctrl.text : null;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final password = await _askPassword('Configurer l\'application');
    if (password == null || !mounted) return;
    await _run(() async {
      final setup = await context.read<Session>().totpSetup(password);
      setState(() => _setup = setup);
    });
  }

  Future<void> _enable() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      showMessage(context, 'Le code contient 6 chiffres', error: true);
      return;
    }
    await _run(() async {
      final codes = await context.read<Session>().totpEnable(code);
      if (!mounted) return;
      setState(() => _setup = null);
      await _showRecoveryCodes(codes);
    });
  }

  Future<void> _regenerate() async {
    final password = await _askPassword('Nouveaux codes de secours');
    if (password == null || !mounted) return;
    await _run(() async {
      final codes = await context.read<Session>().totpRegenerateCodes(password);
      if (mounted) await _showRecoveryCodes(codes);
    });
  }

  Future<void> _disable() async {
    final ok = await confirm(context,
        title: 'Désactiver l\'application ?',
        message: 'La connexion administrateur repassera au code SMS.',
        confirmLabel: 'Désactiver',
        danger: true);
    if (!ok || !mounted) return;
    final password = await _askPassword('Confirmer la désactivation');
    if (password == null || !mounted) return;
    await _run(() => context.read<Session>().totpDisable(password));
  }

  Future<void> _showRecoveryCodes(List<String> codes) {
    final text = codes.join('\n');
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Codes de secours'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Si vous perdez votre téléphone, chacun de ces codes permet UNE connexion. '
              'Notez-les sur papier ou gardez-les en lieu sûr : ils ne seront plus affichés.'),
          const SizedBox(height: 12),
          SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w800, height: 1.5)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              showMessage(ctx, 'Copié');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copier'),
          ),
          TextButton.icon(
            onPressed: () => SharePlus.instance.share(ShareParams(text: 'Codes de secours My CVAV :\n$text')),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Partager'),
          ),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx), child: const Text('C\'est noté')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.watch<Session>().user?.totpEnabled ?? false;
    final setup = _setup;
    return Scaffold(
      appBar: AppBar(title: const Text('Application d\'authentification')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Card(
          color: (enabled ? AppColors.success : AppColors.warning).withValues(alpha: 0.12),
          child: ListTile(
            leading: Icon(enabled ? Icons.verified_user_rounded : Icons.phonelink_lock_rounded,
                color: enabled ? AppColors.success : AppColors.warning, size: 34),
            title: Text(enabled ? 'Activée' : 'Non activée', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(enabled
                ? 'À chaque connexion administrateur, le code est lu dans votre application : plus besoin de SMS.'
                : 'Sans application, le code de connexion administrateur est envoyé par SMS.'),
          ),
        ),
        const SizedBox(height: 16),
        if (enabled) ...[
          OutlinedButton.icon(onPressed: _busy ? null : _regenerate, icon: const Icon(Icons.key_rounded), label: const Text('Nouveaux codes de secours')),
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _busy ? null : _disable,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Désactiver'),
          ),
        ] else if (setup == null) ...[
          const Text('1. Installez Google Authenticator (gratuit), ou Microsoft Authenticator si vous l\'avez déjà.',
              style: TextStyle(fontWeight: FontWeight.w600)),
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(_playStoreAuthenticator), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.shop_rounded),
            label: const Text('Ouvrir le Play Store'),
          ),
          const SizedBox(height: 8),
          const Text('2. Revenez ici et touchez « Configurer ».', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _busy ? null : _start, icon: const Icon(Icons.settings_rounded), label: const Text('Configurer')),
        ] else ...[
          const Text('Ajoutez « My CVAV » dans l\'application :', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              final ok = await launchUrl(Uri.parse(setup.uri), mode: LaunchMode.externalApplication);
              if (!ok && context.mounted) showMessage(context, 'Application introuvable : utilisez la clé ci-dessous.', error: true);
            },
            icon: const Icon(Icons.add_moderator_rounded),
            label: const Text('Ajouter automatiquement'),
          ),
          const SizedBox(height: 12),
          const Text('Ou, dans l\'application : « + » › « Saisir une clé de configuration », nom : My CVAV, clé :',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          Card(
            child: ListTile(
              title: SelectableText(
                RegExp('.{1,4}').allMatches(setup.secret).map((m) => m.group(0)).join(' '),
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 16),
              ),
              trailing: IconButton(
                tooltip: 'Copier la clé',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: setup.secret));
                  showMessage(context, 'Clé copiée');
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Saisissez le code à 6 chiffres affiché par l\'application :', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w800),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(counterText: '', hintText: '••••••'),
            onSubmitted: (_) => _enable(),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _enable, child: const Text('Activer')),
        ],
      ]),
    );
  }
}
