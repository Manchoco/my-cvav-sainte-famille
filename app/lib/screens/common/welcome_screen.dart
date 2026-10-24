import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'auth_screens.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final expired = context.select<Session, bool>((s) => s.expired);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE6F4FB), AppColors.background],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                GestureDetector(
                  onLongPress: AppConfig.canChangeServer ? () => showServerSettings(context) : null,
                  child: Image.asset('assets/images/logo_cvav.png', height: 96),
                ),
                const SizedBox(width: 16),
                Image.asset('assets/images/logo_sainte_famille.png', height: 96),
              ]),
              const SizedBox(height: 28),
              const Text('My CVAV\nSainte Famille',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, height: 1.1, fontWeight: FontWeight.w900, color: AppColors.navy)),
              const SizedBox(height: 10),
              const Text(
                'Cœurs Vaillants – Âmes Vaillantes\nPrésences, cotisations et informations au même endroit.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4),
              ),
              if (expired) ...[
                const SizedBox(height: 16),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_clock_rounded, color: AppColors.warning),
                    title: Text('Votre session a expiré, reconnectez-vous.'),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              const Text('Je suis…', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.groups_rounded,
                color: AppColors.primary,
                title: 'Responsable',
                subtitle: 'Enfants, présences, cotisations et informations',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen(role: 'responsable'))),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.family_restroom_rounded,
                color: AppColors.gold,
                title: 'Parent',
                subtitle: 'Présences de mes enfants, informations et paiement Wave',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen(role: 'parent'))),
              ),
              const SizedBox(height: 32),
              const Text('Externat Sainte Famille · Cocody Riviera II',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}

Future<void> showServerSettings(BuildContext context) async {
  final controller = TextEditingController(text: AppConfig.apiUrl);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.viewInsetsOf(ctx).bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Adresse du serveur', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Réservé à l\'administrateur de l\'application.', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL de l\'API')),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        TextButton(
          onPressed: () {
            controller.text = AppConfig.defaultApiUrl;
            Navigator.pop(ctx, true);
          },
          child: const Text('Valeur par défaut'),
        ),
      ]),
    ),
  );
  if (saved == true) {
    final url = controller.text.trim();
    if (url.isNotEmpty && !url.startsWith('https://') && !url.startsWith('http://')) {
      if (context.mounted) showMessage(context, 'L\'adresse doit commencer par https://', error: true);
      return;
    }
    await AppConfig.setApiUrl(url);
    if (context.mounted) showMessage(context, 'Serveur : ${AppConfig.apiUrl}');
  }
}
