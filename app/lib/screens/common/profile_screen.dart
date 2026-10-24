import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    if (user == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil'), automaticallyImplyLeading: !embedded),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primary)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(user.phone, style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 6),
                  StatusPill(
                    label: user.isResponsable ? 'Responsable${user.legion != null ? ' · ${user.legion!.label}' : ''}' : 'Parent',
                    color: user.isResponsable ? AppColors.primary : AppColors.warning,
                  ),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('Changer mon mot de passe'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _changePassword(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('À propos'),
              subtitle: Text('My CVAV Sainte Famille · ${AppConfig.apiUrl}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'My CVAV Sainte Famille',
                applicationVersion: '1.0.0',
                applicationIcon: Image.asset('assets/images/logo_cvav.png', width: 48),
                children: const [Text('Cœurs Vaillants – Âmes Vaillantes\nExternat Sainte Famille, Cocody Riviera II')],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () async {
            final ok = await confirm(context, title: 'Se déconnecter ?', message: 'Vous devrez saisir à nouveau votre mot de passe.', confirmLabel: 'Déconnexion');
            if (!ok || !context.mounted) return;
            if (!embedded) Navigator.of(context).popUntil((r) => r.isFirst);
            await context.read<Session>().logout();
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Se déconnecter'),
        ),
      ]),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau mot de passe'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe actuel')),
            const SizedBox(height: 12),
            TextFormField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nouveau (8 caractères min.)'),
              validator: (v) => (v ?? '').length < 8 ? 'Au moins 8 caractères' : null,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<Session>().changePassword(current.text, next.text);
      if (context.mounted) showMessage(context, 'Mot de passe modifié. Vos autres appareils ont été déconnectés.');
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e), error: true);
    }
  }
}
