import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/repository.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'attendance_screens.dart';

class DuesScreen extends StatefulWidget {
  const DuesScreen({super.key});

  @override
  State<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends State<DuesScreen> {
  late Future<List<Due>> _future = Repo.dues();

  void _reload() => setState(() => _future = Repo.dues());

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cotisations')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncBody<List<Due>>(
          future: _future,
          onRetry: _reload,
          builder: (dues) {
            final paroisse = dues.firstWhere((d) => d.kind == 'paroissiale');
            final diocese = dues.firstWhere((d) => d.kind == 'diocesaine');
            final activities = dues.where((d) => d.kind == 'activite').toList();
            final activitiesCollected = activities.fold<int>(0, (s, d) => s + d.collected);
            final activitiesPending = activities.fold<int>(0, (s, d) => s + d.pendingCount);
            final total = dues.fold<int>(0, (s, d) => s + d.collected);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(gradient: AppColors.headerGradient, borderRadius: BorderRadius.circular(22)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Total encaissé cette année', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                    const SizedBox(height: 4),
                    Text(formatMoney(total), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                  ]),
                ),
                const SizedBox(height: 16),
                _DueCard(
                  icon: Icons.church_rounded,
                  color: AppColors.primary,
                  title: 'Cotisation paroissiale',
                  subtitle: formatMoney(paroisse.amount),
                  paid: paroisse.paidCount,
                  pending: paroisse.pendingCount,
                  onTap: () => _open(DuePaymentsScreen(dueId: paroisse.id)),
                ),
                _DueCard(
                  icon: Icons.account_balance_rounded,
                  color: const Color(0xFF7B4BC4),
                  title: 'Cotisation diocésaine',
                  subtitle: diocese.amount == null ? 'Montant à définir — touchez pour le fixer' : formatMoney(diocese.amount),
                  paid: diocese.paidCount,
                  pending: diocese.pendingCount,
                  onTap: () async {
                    if (diocese.amount == null) {
                      final amount = await _askAmount(context, title: 'Montant de la cotisation diocésaine', current: null);
                      if (amount == null || amount < 0 || !context.mounted) return;
                      try {
                        await Repo.setDueAmount(diocese.id, amount);
                      } catch (e) {
                        if (context.mounted) showMessage(context, errorText(e), error: true);
                        return;
                      }
                    }
                    await _open(DuePaymentsScreen(dueId: diocese.id));
                  },
                ),
                _DueCard(
                  icon: Icons.celebration_rounded,
                  color: AppColors.gold,
                  title: 'Cotisation des activités',
                  subtitle: '${activities.length} activités · ${formatMoney(activitiesCollected)} reçus',
                  pending: activitiesPending,
                  onTap: () => _open(const ActivityDuesScreen()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({required this.icon, required this.color, required this.title, required this.subtitle, this.paid, this.pending = 0, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int? paid;
  final int pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted)),
                  if (paid != null || pending > 0) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, children: [
                      if (paid != null) StatusPill(label: '$paid payé(s)', color: AppColors.success),
                      if (pending > 0) StatusPill(label: '$pending à confirmer', color: AppColors.warning),
                    ]),
                  ],
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

Future<int?> _askAmount(BuildContext context, {required String title, int? current}) async {
  final ctrl = TextEditingController(text: current?.toString() ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(suffixText: 'F CFA'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
      ],
    ),
  );
  if (ok != true) return null;
  return int.tryParse(ctrl.text.trim()) ?? -1;
}

/// Liste des activités de l'année avec leur prix.
class ActivityDuesScreen extends StatefulWidget {
  const ActivityDuesScreen({super.key});

  @override
  State<ActivityDuesScreen> createState() => _ActivityDuesScreenState();
}

class _ActivityDuesScreenState extends State<ActivityDuesScreen> {
  late Future<List<Due>> _future = _load();

  Future<List<Due>> _load() async => (await Repo.dues()).where((d) => d.kind == 'activite').toList();
  void _reload() => setState(() => _future = _load());

  Future<void> _setPrice(Due d) async {
    final amount = await _askAmount(context, title: 'Prix — ${d.label}', current: d.amount);
    if (amount == null) return;
    try {
      await Repo.setDueAmount(d.id, amount < 0 ? null : amount);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _addActivity() async {
    final created = await showEventDialog(context, kind: 'activite');
    if (created != null) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cotisation des activités')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addActivity,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Activité'),
      ),
      body: AsyncBody<List<Due>>(
        future: _future,
        onRetry: _reload,
        builder: (dues) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12, left: 4),
              child: Text('Fixez le prix de chaque activité : il sera affiché aux parents avec le bouton « Payer la cotisation ».',
                  style: TextStyle(color: AppColors.muted)),
            ),
            for (final d in dues)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => DuePaymentsScreen(dueId: d.id)));
                      _reload();
                    },
                    title: Text(d.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${formatDate(d.eventDate)} · ${d.paidCount} payé(s)${d.pendingCount > 0 ? ' · ${d.pendingCount} à confirmer' : ''}'),
                    trailing: ActionChip(
                      avatar: Icon(d.amount == null ? Icons.edit_rounded : Icons.sell_rounded, size: 18),
                      label: Text(d.amount == null ? 'Fixer le prix' : formatMoney(d.amount)),
                      onPressed: () => _setPrice(d),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Liste des enfants par légion : le responsable coche ceux qui ont payé.
class DuePaymentsScreen extends StatefulWidget {
  const DuePaymentsScreen({super.key, required this.dueId});
  final int dueId;

  @override
  State<DuePaymentsScreen> createState() => _DuePaymentsScreenState();
}

class _DuePaymentsScreenState extends State<DuePaymentsScreen> {
  late Future<(Due, List<PaymentEntry>)> _future = Repo.payments(widget.dueId);
  final Map<int, bool> _changes = {};
  bool _saving = false;

  void _reload() => setState(() {
        _changes.clear();
        _future = Repo.payments(widget.dueId);
      });

  void _toggle(PaymentEntry e, bool paid) {
    setState(() {
      e.status = paid ? 'paid' : 'unpaid';
      _changes[e.child.id] = paid;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Repo.savePayments(widget.dueId, Map.of(_changes));
      if (mounted) showMessage(context, 'Cotisations enregistrées');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editAmount(Due due) async {
    final amount = await _askAmount(context, title: 'Montant — ${due.label}', current: due.amount);
    if (amount == null) return;
    try {
      await Repo.setDueAmount(due.id, amount < 0 ? null : amount);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = legionTabs(withAll: false);
    return PopScope(
      canPop: _changes.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirm(context,
            title: 'Modifications non enregistrées', message: 'Quitter sans enregistrer ?', confirmLabel: 'Quitter', danger: true);
        if (leave && context.mounted) {
          _changes.clear();
          Navigator.pop(context);
        }
      },
      child: FutureBuilder<(Due, List<PaymentEntry>)>(
        future: _future,
        builder: (context, snap) {
          final due = snap.data?.$1;
          final entries = snap.data?.$2 ?? const <PaymentEntry>[];
          return DefaultTabController(
            length: tabs.length,
            child: Scaffold(
              appBar: AppBar(
                title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(due?.label ?? 'Cotisation', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  if (due != null)
                    Text(formatMoney(due.amount), style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w500)),
                ]),
                actions: [
                  if (due != null) IconButton(tooltip: 'Modifier le montant', onPressed: () => _editAmount(due), icon: const Icon(Icons.edit_rounded)),
                ],
                bottom: TabBar(
                  isScrollable: true,
                  tabs: [
                    for (final l in tabs)
                      legionTab(l, count: snap.hasData ? entries.where((e) => e.child.legion == l && e.status == 'paid').length : null),
                  ],
                ),
              ),
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _saving || _changes.isEmpty ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_changes.isEmpty ? 'Tout est enregistré' : 'Enregistrer (${_changes.length})'),
                  ),
                ),
              ),
              body: snap.hasError
                  ? ErrorView(error: snap.error!, onRetry: _reload)
                  : !snap.hasData
                      ? const LoadingView()
                      : TabBarView(children: [
                          for (final l in tabs) _PaymentList(entries: entries.where((e) => e.child.legion == l).toList(), onToggle: _toggle),
                        ]),
            ),
          );
        },
      ),
    );
  }
}

class _PaymentList extends StatelessWidget {
  const _PaymentList({required this.entries, required this.onToggle});
  final List<PaymentEntry> entries;
  final void Function(PaymentEntry, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const EmptyState(icon: Icons.groups_rounded, title: 'Aucun enfant dans cette légion');
    final paid = entries.where((e) => e.status == 'paid').length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('$paid / ${entries.length} ont payé', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
        const SizedBox(height: 8),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: CheckboxListTile(
                value: e.status == 'paid',
                onChanged: e.lockedByWave ? null : (v) => onToggle(e, v ?? false),
                activeColor: AppColors.success,
                secondary: ChildAvatar(e.child, radius: 20),
                title: Text(e.child.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: e.status == 'pending'
                    ? const Text('Paiement Wave déclaré — cochez pour confirmer', style: TextStyle(color: AppColors.warning))
                    : e.lockedByWave
                        ? const Text('Payé via Wave (confirmé automatiquement)', style: TextStyle(color: AppColors.success))
                        : e.status == 'paid' && e.updatedBy != null
                            ? Text('Coché par ${e.updatedBy}')
                            : null,
              ),
            ),
          ),
      ],
    );
  }
}
