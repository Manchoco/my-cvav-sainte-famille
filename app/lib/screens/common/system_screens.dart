import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'auth_screens.dart';

class _CenteredPanel extends StatelessWidget {
  const _CenteredPanel({required this.icon, required this.title, required this.message, required this.actions});
  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Image.asset('assets/images/logo_cvav.png', height: 84),
              const SizedBox(height: 24),
              Icon(icon, size: 48, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4)),
              const SizedBox(height: 28),
              ...actions,
            ]),
          ),
        ),
      ),
    );
  }
}

/// Affiché à tous sauf à l'administrateur quand la maintenance est activée.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return _CenteredPanel(
      icon: Icons.construction_rounded,
      title: 'Maintenance en cours',
      message: session.status.maintenanceMessage,
      actions: [
        FilledButton.icon(onPressed: session.refreshStatus, icon: const Icon(Icons.refresh_rounded), label: const Text('Réessayer')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            if (session.isLoggedIn) await session.logout();
            if (context.mounted) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen(role: 'responsable', loginOnly: true)));
            }
          },
          child: const Text('Connexion administrateur'),
        ),
      ],
    );
  }
}

Future<void> openUpdateLink(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showMessage(context, 'Impossible d\'ouvrir le lien de mise à jour', error: true);
}

/// Version trop ancienne : la mise à jour est obligatoire.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<Session>().status;
    return _CenteredPanel(
      icon: Icons.system_update_rounded,
      title: 'Mise à jour nécessaire',
      message: 'Cette version de My CVAV n\'est plus prise en charge. Installez la nouvelle version pour continuer.'
          '${status.updateNotes.isNotEmpty ? '\n\n${status.updateNotes}' : ''}',
      actions: [
        FilledButton.icon(
          onPressed: () => openUpdateLink(context, status.updateUrl),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Télécharger la mise à jour'),
        ),
        const SizedBox(height: 8),
        Text('Version installée : ${AppConfig.appVersion} (${AppConfig.appBuild})',
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }
}

/// Mise à jour facultative : proposée une fois par lancement.
bool _updateOffered = false;
Future<void> offerOptionalUpdate(BuildContext context) async {
  final status = context.read<Session>().status;
  if (_updateOffered || !status.updateAvailable || status.updateRequired) return;
  _updateOffered = true;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nouvelle version disponible'),
      content: Text(status.updateNotes.isEmpty ? 'Une nouvelle version de My CVAV est disponible.' : status.updateNotes),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Plus tard')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () {
            Navigator.pop(ctx);
            openUpdateLink(context, status.updateUrl);
          },
          child: const Text('Mettre à jour'),
        ),
      ],
    ),
  );
}

/// Mot de passe provisoire (créé ou réinitialisé par l'administrateur) : à changer avant d'aller plus loin.
class ForcePasswordChangeScreen extends StatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  State<ForcePasswordChangeScreen> createState() => _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().changePassword(_current.text, _next.text);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau mot de passe'),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => context.read<Session>().logout(), child: const Text('Déconnexion'))],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Icon(Icons.lock_reset_rounded, size: 56, color: AppColors.primary),
          const SizedBox(height: 12),
          Text('Bonjour ${user.fullName}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Votre mot de passe est provisoire. Choisissez-en un personnel pour continuer.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 24),
          TextFormField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe provisoire')),
          const SizedBox(height: 14),
          TextFormField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Nouveau mot de passe (8 caractères min.)'),
            validator: (v) => (v ?? '').length < 8 ? 'Au moins 8 caractères' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirmer'),
            validator: (v) => v != _next.text ? 'Les mots de passe ne correspondent pas' : null,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Enregistrer')),
        ]),
      ),
    );
  }
}
