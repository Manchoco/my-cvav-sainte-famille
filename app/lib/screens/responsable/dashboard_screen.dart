import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/repository.dart';
import '../../models.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin/admin_screen.dart';
import '../common/profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> _future = Repo.stats();

  Future<void> _reload() async {
    setState(() => _future = Repo.stats());
    await _future.catchError((_) => <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          final stats = snap.data;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              GradientHeader(
                title: 'Bonjour, ${user.fullName.split(' ').first}',
                subtitle: '${user.roleLabel}${user.legion != null ? ' · ${user.legion!.label}' : ''} · ${stats?['year'] ?? ''}',
                trailing: IconButton(
                  tooltip: 'Mon profil',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                  icon: const Icon(Icons.account_circle_rounded, color: Colors.white, size: 32),
                ),
                child: Row(children: [
                  _HeaderStat(label: 'Enfants inscrits', value: '${stats?['totalChildren'] ?? '–'}'),
                  const SizedBox(width: 12),
                  _HeaderStat(label: 'Cotisations reçues', value: stats == null ? '–' : formatMoney(stats['collected'] as int)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (user.isAdmin) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: const Color(0xFFFDECEC),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: const Icon(Icons.shield_rounded, color: AppColors.danger),
                        title: const Text('Administration', style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: const Text('Comptes, sécurité, maintenance, mises à jour, journal'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                      ),
                    ),
                  ],
                  if (snap.hasError) Padding(padding: const EdgeInsets.only(top: 16), child: ErrorView(error: snap.error!, onRetry: _reload)),
                  if (stats != null) ...[
                    const SectionTitle('Effectifs par légion'),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.7,
                      children: [
                        for (final l in Legion.values)
                          _LegionTile(legion: l, count: (stats['byLegion'] as Map)[l.name] as int? ?? 0, onTap: () => widget.onNavigate(1)),
                      ],
                    ),
                    if ((stats['pendingPayments'] as int? ?? 0) > 0) ...[
                      const SizedBox(height: 16),
                      Card(
                        color: const Color(0xFFFFF6E5),
                        child: ListTile(
                          leading: const Icon(Icons.hourglass_top_rounded, color: AppColors.warning),
                          title: Text('${stats['pendingPayments']} paiement(s) Wave à confirmer'),
                          subtitle: const Text('Déclarés par les parents'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => widget.onNavigate(3),
                        ),
                      ),
                    ],
                    if (stats['lastEvent'] != null) ...[
                      const SectionTitle('Dernier pointage'),
                      _LastEventCard(event: stats['lastEvent'] as Map<String, dynamic>, onTap: () => widget.onNavigate(2)),
                    ],
                  ],
                  const SectionTitle('Actions rapides'),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    _QuickAction(icon: Icons.person_add_alt_1_rounded, label: 'Ajouter un enfant', onTap: () => widget.onNavigate(1)),
                    _QuickAction(icon: Icons.fact_check_rounded, label: 'Faire l\'appel', onTap: () => widget.onNavigate(2)),
                    _QuickAction(icon: Icons.payments_rounded, label: 'Cotisations', onTap: () => widget.onNavigate(3)),
                    _QuickAction(icon: Icons.campaign_rounded, label: 'Publier une info', onTap: () => widget.onNavigate(4)),
                  ]),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900))),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
        ]),
      ),
    );
  }
}

class _LegionTile extends StatelessWidget {
  const _LegionTile({required this.legion, required this.count, required this.onTap});
  final Legion legion;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: legion.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(legion.icon, color: legion.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$count', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                Text(legion.label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LastEventCard extends StatelessWidget {
  const _LastEventCard({required this.event, required this.onTap});
  final Map<String, dynamic> event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final present = event['present'] as int;
    final absent = event['absent'] as int;
    final total = present + absent;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(formatDate(event['date'] as String?), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : present / total,
                minHeight: 10,
                backgroundColor: AppColors.danger.withValues(alpha: 0.2),
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 8),
            Text('$present présent(s) · $absent absent(s)', style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 32 - 12) / 2;
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            child: Column(children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}
