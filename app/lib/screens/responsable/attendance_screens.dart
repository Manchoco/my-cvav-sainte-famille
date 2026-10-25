import 'package:flutter/material.dart';

import '../../api/repository.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Liste des activités de l'année et des réunions, point d'entrée du pointage.
class AttendanceEventsScreen extends StatefulWidget {
  const AttendanceEventsScreen({super.key});

  @override
  State<AttendanceEventsScreen> createState() => _AttendanceEventsScreenState();
}

class _AttendanceEventsScreenState extends State<AttendanceEventsScreen> {
  late Future<List<EventItem>> _future = Repo.events();

  void _reload() => setState(() => _future = Repo.events());

  Future<void> _open(EventItem e) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceSheetScreen(event: e)));
    _reload();
  }

  Future<void> _addMeeting() async {
    final created = await showEventDialog(context, kind: 'reunion');
    if (created != null) {
      _reload();
      if (mounted) _open(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Présences')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMeeting,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle réunion'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncBody<List<EventItem>>(
          future: _future,
          onRetry: _reload,
          builder: (events) {
            final activities = events.where((e) => e.isActivity).toList();
            final meetings = events.where((e) => !e.isActivity).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                const SectionTitle('Activités de l\'année'),
                for (final e in activities) _EventCard(event: e, onTap: () => _open(e)),
                SectionTitle('Réunions', action: TextButton.icon(onPressed: _addMeeting, icon: const Icon(Icons.add_rounded), label: const Text('Ajouter'))),
                if (meetings.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.event_note_rounded, color: AppColors.muted),
                      title: Text('Aucune réunion enregistrée'),
                      subtitle: Text('Créez une réunion pour faire l\'appel.'),
                    ),
                  ),
                for (final e in meetings) _EventCard(event: e, onTap: () => _open(e)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});
  final EventItem event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = event.present + event.absent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: (event.isActivity ? AppColors.primary : AppColors.gold).withValues(alpha: 0.15),
            child: Icon(event.isActivity ? Icons.celebration_rounded : Icons.groups_2_rounded,
                color: event.isActivity ? AppColors.primary : AppColors.warning),
          ),
          title: Text(event.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(formatDate(event.date)),
          trailing: total == 0
              ? const StatusPill(label: 'À pointer', color: AppColors.muted)
              : StatusPill(label: '${event.present}/$total', color: AppColors.success, icon: Icons.check_rounded),
        ),
      ),
    );
  }
}

/// Création / modification d'une activité ou d'une réunion.
Future<EventItem?> showEventDialog(BuildContext context, {required String kind, EventItem? event}) {
  final name = TextEditingController(text: event?.name ?? (kind == 'reunion' ? 'Réunion' : ''));
  final initialPrice = event?.price?.toString() ?? '';
  final price = TextEditingController(text: initialPrice);
  String? date = event?.date ?? (kind == 'reunion' ? DateTime.now().toIso8601String().substring(0, 10) : null);
  var busy = false;
  return showModalBottomSheet<EventItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(event == null ? (kind == 'reunion' ? 'Nouvelle réunion' : 'Nouvelle activité') : 'Modifier',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Intitulé')),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: date != null ? DateTime.parse(date!) : DateTime.now(),
                firstDate: DateTime(DateTime.now().year - 2),
                lastDate: DateTime(DateTime.now().year + 2),
              );
              if (d != null) setSheet(() => date = d.toIso8601String().substring(0, 10));
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_month_rounded)),
              child: Text(formatDate(date)),
            ),
          ),
          if (kind == 'activite') ...[
            const SizedBox(height: 12),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Prix, identique pour toutes les légions (F CFA)',
                helperText: event?.hasLegionPrices == true
                    ? 'Prix différents selon la légion : laissez vide pour les garder.'
                    : 'Pour un prix par légion : Cotisations › Cotisation des activités.',
                helperMaxLines: 2,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (name.text.trim().length < 2) return;
                    setSheet(() => busy = true);
                    try {
                      final p = int.tryParse(price.text.trim());
                      final saved = event == null
                          ? await Repo.createEvent(kind: kind, name: name.text.trim(), date: date, price: p)
                          : await Repo.updateEvent(event.id, {
                              'name': name.text.trim(),
                              'date': date,
                              // Le prix n'est envoyé que s'il a été modifié (sinon les prix par légion seraient effacés).
                              if (kind == 'activite' && price.text.trim() != initialPrice) 'price': p,
                            });
                      if (ctx.mounted) Navigator.pop(ctx, saved);
                    } catch (e) {
                      setSheet(() => busy = false);
                      if (ctx.mounted) showMessage(ctx, errorText(e), error: true);
                    }
                  },
            child: const Text('Enregistrer'),
          ),
        ]),
      ),
    ),
  );
}

/// Feuille d'appel : un onglet par légion, Présent / Absent pour chaque enfant.
class AttendanceSheetScreen extends StatefulWidget {
  const AttendanceSheetScreen({super.key, required this.event});
  final EventItem event;

  @override
  State<AttendanceSheetScreen> createState() => _AttendanceSheetScreenState();
}

class _AttendanceSheetScreenState extends State<AttendanceSheetScreen> {
  late EventItem _event = widget.event;
  late Future<List<AttendanceEntry>> _future = Repo.attendance(_event.id);
  final Map<int, String?> _changes = {};
  bool _saving = false;

  void _reload() => setState(() {
        _changes.clear();
        _future = Repo.attendance(_event.id);
      });

  void _set(AttendanceEntry e, String? status) {
    setState(() {
      e.status = status;
      _changes[e.child.id] = status;
    });
  }

  void _markAll(List<AttendanceEntry> entries, String status) {
    setState(() {
      for (final e in entries) {
        if (e.status == null) {
          e.status = status;
          _changes[e.child.id] = status;
        }
      }
    });
  }

  Future<void> _save() async {
    if (_changes.isEmpty) return;
    setState(() => _saving = true);
    try {
      await Repo.saveAttendance(_event.id, Map.of(_changes));
      _changes.clear();
      if (mounted) showMessage(context, 'Présences enregistrées');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (_changes.isEmpty) return true;
    return confirm(context,
        title: 'Modifications non enregistrées', message: 'Quitter sans enregistrer les présences ?', confirmLabel: 'Quitter', danger: true);
  }

  Future<void> _edit() async {
    final updated = await showEventDialog(context, kind: _event.kind, event: _event);
    if (updated != null) setState(() => _event = updated);
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: 'Supprimer « ${_event.name} » ?',
        message: _event.isActivity ? 'Les présences et la cotisation de cette activité seront supprimées.' : 'Les présences de cette réunion seront supprimées.',
        confirmLabel: 'Supprimer',
        danger: true);
    if (!ok) return;
    try {
      await Repo.deleteEvent(_event.id);
      _changes.clear();
      if (mounted) Navigator.pop(context);
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
        if (await _confirmLeave() && context.mounted) {
          _changes.clear();
          Navigator.pop(context);
        }
      },
      child: DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_event.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(formatDate(_event.date), style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w500)),
            ]),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? _edit() : _delete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Modifier l\'intitulé / la date')),
                  PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                ],
              ),
            ],
            bottom: TabBar(isScrollable: true, tabs: [for (final l in tabs) legionTab(l)]),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: _saving || _changes.isEmpty ? null : _save,
                icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
                label: Text(_changes.isEmpty ? 'Tout est enregistré' : 'Enregistrer (${_changes.length})'),
              ),
            ),
          ),
          body: AsyncBody<List<AttendanceEntry>>(
            future: _future,
            onRetry: _reload,
            builder: (all) => TabBarView(children: [
              for (final l in tabs) _LegionAttendance(entries: all.where((e) => e.child.legion == l).toList(), onSet: _set, onMarkAll: _markAll),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LegionAttendance extends StatelessWidget {
  const _LegionAttendance({required this.entries, required this.onSet, required this.onMarkAll});
  final List<AttendanceEntry> entries;
  final void Function(AttendanceEntry, String?) onSet;
  final void Function(List<AttendanceEntry>, String) onMarkAll;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyState(icon: Icons.groups_rounded, title: 'Aucun enfant dans cette légion');
    }
    final present = entries.where((e) => e.status == 'present').length;
    final absent = entries.where((e) => e.status == 'absent').length;
    final todo = entries.length - present - absent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(children: [
          StatusPill(label: '$present présent(s)', color: AppColors.success),
          const SizedBox(width: 8),
          StatusPill(label: '$absent absent(s)', color: AppColors.danger),
          const Spacer(),
          if (todo > 0)
            TextButton(onPressed: () => onMarkAll(entries, 'present'), child: Text('Restants présents ($todo)')),
        ]),
        const SizedBox(height: 8),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(children: [
                  ChildAvatar(e.child, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.child.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (e.markedBy != null) Text('Pointé par ${e.markedBy}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                  _ToggleButton(
                    label: 'P',
                    tooltip: 'Présent',
                    selected: e.status == 'present',
                    color: AppColors.success,
                    onTap: () => onSet(e, e.status == 'present' ? null : 'present'),
                  ),
                  const SizedBox(width: 8),
                  _ToggleButton(
                    label: 'A',
                    tooltip: 'Absent',
                    selected: e.status == 'absent',
                    color: AppColors.danger,
                    onTap: () => onSet(e, e.status == 'absent' ? null : 'absent'),
                  ),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.label, required this.tooltip, required this.selected, required this.color, required this.onTap});
  final String label;
  final String tooltip;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? color : color.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: Text(label, style: TextStyle(color: selected ? Colors.white : color, fontWeight: FontWeight.w900, fontSize: 16))),
          ),
        ),
      ),
    );
  }
}
