import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/repository.dart';
import '../../models.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../common/posts_screen.dart';
import '../common/profile_screen.dart';

class ParentShell extends StatefulWidget {
  const ParentShell({super.key});

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> {
  int _index = 0;
  final _infoKey = GlobalKey<_ParentInfoScreenState>();
  final _homeKey = GlobalKey<_ParentHomeScreenState>();
  final _attendanceKey = GlobalKey<_ParentAttendanceScreenState>();

  void _go(int i) {
    setState(() => _index = i);
    // Données fraîches à chaque changement d'onglet.
    switch (i) {
      case 0:
        _homeKey.currentState?.reload();
      case 1:
        _attendanceKey.currentState?.reload();
      case 2:
        _infoKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: [
        ParentHomeScreen(key: _homeKey, onNavigate: _go),
        ParentAttendanceScreen(key: _attendanceKey),
        ParentInfoScreen(key: _infoKey),
        const ProfileScreen(embedded: true),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check_rounded), label: 'Présences'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign_rounded), label: 'Informations'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profil'),
        ],
      ),
    );
  }
}

Future<bool> showLinkChildDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  final linked = await showModalBottomSheet<Child>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      var busy = false;
      return StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.viewInsetsOf(ctx).bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Ajouter mon enfant', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Saisissez le code enfant à 8 caractères remis par le responsable de sa légion.', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(hintText: 'AB12CD34'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (ctrl.text.trim().length < 4) return;
                      setSheet(() => busy = true);
                      try {
                        final child = await Repo.linkChild(ctrl.text.trim());
                        if (ctx.mounted) Navigator.pop(ctx, child);
                      } catch (e) {
                        setSheet(() => busy = false);
                        if (ctx.mounted) showMessage(ctx, errorText(e), error: true);
                      }
                    },
              child: const Text('Valider'),
            ),
          ]),
        ),
      );
    },
  );
  if (linked != null && context.mounted) showMessage(context, '${linked.fullName} a été ajouté(e) à votre compte');
  return linked != null;
}

// ---------------- Accueil ----------------

class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeData {
  _ParentHomeData(this.children, this.dues, this.posts);
  final List<Child> children;
  final List<ParentDue> dues;
  final List<Post> posts;
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  late Future<_ParentHomeData> _future = _load();

  Future<_ParentHomeData> _load() async {
    final results = await Future.wait([Repo.myChildren(), Repo.myDues(), Repo.posts()]);
    return _ParentHomeData(
      results[0] as List<Child>,
      (results[1] as (String, List<ParentDue>)).$2,
      results[2] as List<Post>,
    );
  }

  void reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    return RefreshIndicator(
      onRefresh: () async => reload(),
      child: FutureBuilder<_ParentHomeData>(
        future: _future,
        builder: (context, snap) {
          final data = snap.data;
          final toPay = data?.dues.where((d) => d.status == 'unpaid').toList() ?? const <ParentDue>[];
          final totalToPay = toPay.fold<int>(0, (s, d) => s + d.amount);
          return ListView(padding: EdgeInsets.zero, children: [
            GradientHeader(
              title: 'Bonjour, ${user.fullName.split(' ').first}',
              subtitle: 'Espace parent',
              child: data == null
                  ? null
                  : InkWell(
                      onTap: () => widget.onNavigate(2),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
                        child: Row(children: [
                          const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(toPay.isEmpty ? 'Aucune cotisation en attente' : '${toPay.length} cotisation(s) à payer',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                              if (toPay.isNotEmpty)
                                Text('Total : ${formatMoney(totalToPay)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                            ]),
                          ),
                          if (toPay.isNotEmpty) const Icon(Icons.chevron_right_rounded, color: Colors.white),
                        ]),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (snap.hasError) ErrorView(error: snap.error!, onRetry: reload),
                if (!snap.hasData && !snap.hasError) const Padding(padding: EdgeInsets.all(40), child: LoadingView()),
                if (data != null) ...[
                  SectionTitle('Mes enfants',
                      action: TextButton.icon(
                        onPressed: () async {
                          if (await showLinkChildDialog(context)) reload();
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Ajouter'),
                      )),
                  if (data.children.isEmpty)
                    EmptyState(
                      icon: Icons.child_care_rounded,
                      title: 'Ajoutez votre premier enfant',
                      message: 'Demandez le code enfant au responsable de sa légion, puis saisissez-le ici.',
                      action: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
                        onPressed: () async {
                          if (await showLinkChildDialog(context)) reload();
                        },
                        icon: const Icon(Icons.qr_code_rounded),
                        label: const Text('Saisir un code enfant'),
                      ),
                    ),
                  for (final c in data.children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          leading: ChildAvatar(c),
                          title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(c.age != null ? '${c.age} ans' : c.legion.label),
                          trailing: LegionBadge(c.legion, small: true),
                          onLongPress: () async {
                            final ok = await confirm(context,
                                title: 'Retirer ${c.fullName} ?',
                                message: 'Vous ne verrez plus ses présences ni ses cotisations.',
                                confirmLabel: 'Retirer',
                                danger: true);
                            if (!ok) return;
                            try {
                              await Repo.unlinkChild(c.id);
                              reload();
                            } catch (e) {
                              if (context.mounted) showMessage(context, errorText(e), error: true);
                            }
                          },
                        ),
                      ),
                    ),
                  if (data.posts.isNotEmpty) ...[
                    SectionTitle('Dernière information', action: TextButton(onPressed: () => widget.onNavigate(2), child: const Text('Tout voir'))),
                    PostCard(post: data.posts.first),
                  ],
                ],
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

// ---------------- Présences ----------------

class ParentAttendanceScreen extends StatefulWidget {
  const ParentAttendanceScreen({super.key});

  @override
  State<ParentAttendanceScreen> createState() => _ParentAttendanceScreenState();
}

class _ParentAttendanceScreenState extends State<ParentAttendanceScreen> {
  late Future<List<AttendanceRecord>> _future = Repo.myAttendance();
  int? _childFilter;

  void reload() => setState(() => _future = Repo.myAttendance());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Présences et absences')),
      body: RefreshIndicator(
        onRefresh: () async => reload(),
        child: AsyncBody<List<AttendanceRecord>>(
          future: _future,
          onRetry: reload,
          builder: (records) {
            if (records.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.fact_check_rounded,
                  title: 'Aucun pointage pour le moment',
                  message: 'Les présences cochées par les responsables apparaîtront ici après chaque activité ou réunion.',
                ),
              ]);
            }
            // Les enregistrements arrivent triés par ordre alphabétique des enfants.
            final children = <int, String>{};
            for (final r in records) {
              children[r.childId] = r.childName;
            }
            final visible = records.where((r) => _childFilter == null || r.childId == _childFilter).toList();
            final present = visible.where((r) => r.status == 'present').length;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              if (children.length > 1)
                SizedBox(
                  height: 48,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: const Text('Tous'), selected: _childFilter == null, onSelected: (_) => setState(() => _childFilter = null)),
                    ),
                    for (final e in children.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(label: Text(e.value), selected: _childFilter == e.key, onSelected: (_) => setState(() => _childFilter = e.key)),
                      ),
                  ]),
                ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    _Counter(value: present, label: 'Présences', color: AppColors.success),
                    _Counter(value: visible.length - present, label: 'Absences', color: AppColors.danger),
                    _Counter(
                      value: visible.isEmpty ? 0 : (present * 100 / visible.length).round(),
                      label: 'Assiduité',
                      color: AppColors.primary,
                      suffix: '%',
                    ),
                  ]),
                ),
              ),
              for (final childId in children.keys.where((id) => _childFilter == null || id == _childFilter)) ...[
                SectionTitle(children[childId]!),
                for (final r in visible.where((r) => r.childId == childId))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: Icon(
                          r.status == 'present' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: r.status == 'present' ? AppColors.success : AppColors.danger,
                          size: 30,
                        ),
                        title: Text(r.eventName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          formatDate(r.eventDate),
                          if (r.markedBy != null) 'pointé par ${r.markedBy}',
                        ].join(' · ')),
                        trailing: StatusPill(
                          label: r.status == 'present' ? 'Présent' : 'Absent',
                          color: r.status == 'present' ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                  ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.value, required this.label, required this.color, this.suffix = ''});
  final int value;
  final String label;
  final Color color;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text('$value$suffix', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
    );
  }
}

// ---------------- Informations & cotisations ----------------

class ParentInfoScreen extends StatefulWidget {
  const ParentInfoScreen({super.key});

  @override
  State<ParentInfoScreen> createState() => _ParentInfoScreenState();
}

class _ParentInfoScreenState extends State<ParentInfoScreen> with WidgetsBindingObserver {
  late Future<(String, List<ParentDue>, List<Post>)> _future = _load();
  ParentDue? _awaitingReturn;
  String _mode = 'disabled';

  Future<(String, List<ParentDue>, List<Post>)> _load() async {
    final results = await Future.wait([Repo.myDues(), Repo.posts()]);
    final dues = results[0] as (String, List<ParentDue>);
    _mode = dues.$1;
    return (dues.$1, dues.$2, results[1] as List<Post>);
  }

  void reload() => setState(() => _future = _load());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Retour depuis l'application Wave.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _awaitingReturn == null) return;
    final due = _awaitingReturn!;
    _awaitingReturn = null;
    if (_mode == 'merchant_link') {
      _askDeclare(due);
    } else {
      reload();
    }
  }

  Future<void> _pay(ParentDue due) async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Paiement par Wave', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            _PayLine(label: 'Enfant', value: due.childName),
            _PayLine(label: 'Type', value: due.kindLabel),
            if (due.kind == 'activite') _PayLine(label: 'Activité', value: due.label),
            const Divider(height: 24),
            _PayLine(label: 'Montant', value: formatMoney(due.amount), bold: true),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1DC8FF), foregroundColor: AppColors.navy),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Ouvrir Wave'),
            ),
            const SizedBox(height: 8),
            const Text('Vous allez être redirigé vers l\'application Wave pour finaliser le paiement.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ]),
        ),
      ),
    );
    if (go != true) return;
    try {
      final res = await Repo.waveCheckout(due.dueId, due.childId);
      _mode = res['mode'] as String;
      final launched = await launchUrl(Uri.parse(res['url'] as String), mode: LaunchMode.externalApplication);
      if (!launched) {
        if (mounted) showMessage(context, 'Impossible d\'ouvrir Wave. Vérifiez que l\'application est installée.', error: true);
        return;
      }
      _awaitingReturn = due;
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _askDeclare(ParentDue due) async {
    final ref = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paiement effectué ?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Avez-vous payé ${formatMoney(due.amount)} pour « ${due.label} » (${due.childName}) ?'),
          const SizedBox(height: 12),
          TextField(controller: ref, decoration: const InputDecoration(labelText: 'N° de transaction Wave (facultatif)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Pas encore')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, j\'ai payé')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.declarePayment(due.dueId, due.childId, reference: ref.text.trim());
      if (mounted) showMessage(context, 'Merci ! Un responsable va confirmer votre paiement.');
      reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informations')),
      body: RefreshIndicator(
        onRefresh: () async => reload(),
        child: AsyncBody<(String, List<ParentDue>, List<Post>)>(
          future: _future,
          onRetry: reload,
          builder: (data) {
            final (_, dues, posts) = data;
            final toPay = dues.where((d) => d.status != 'paid').toList();
            final paid = dues.where((d) => d.status == 'paid').toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              const SectionTitle('Cotisations à payer'),
              if (dues.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('Aucune cotisation'),
                    subtitle: Text('Ajoutez vos enfants pour voir leurs cotisations.'),
                  ),
                ),
              if (dues.isNotEmpty && toPay.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.verified_rounded, color: AppColors.success),
                    title: Text('Tout est réglé, merci !'),
                  ),
                ),
              for (final d in toPay) _DueToPayCard(due: d, onPay: () => _pay(d)),
              if (paid.isNotEmpty) ...[
                const SectionTitle('Déjà payées'),
                for (final d in paid)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.check_circle_rounded, color: AppColors.success),
                        title: Text(d.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${d.childName} · ${formatMoney(d.amount)}'),
                        trailing: d.method == 'wave' ? const StatusPill(label: 'Wave', color: AppColors.primary) : null,
                      ),
                    ),
                  ),
              ],
              const SectionTitle('Annonces'),
              if (posts.isEmpty)
                const Card(child: ListTile(leading: Icon(Icons.campaign_outlined), title: Text('Aucune annonce pour le moment'))),
              for (final p in posts) Padding(padding: const EdgeInsets.only(bottom: 10), child: PostCard(post: p)),
            ]);
          },
        ),
      ),
    );
  }
}

class _DueToPayCard extends StatelessWidget {
  const _DueToPayCard({required this.due, required this.onPay});
  final ParentDue due;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final pending = due.status == 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (due.kind == 'activite')
                    Text(due.kindLabel, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(due.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(due.childName, style: const TextStyle(color: AppColors.muted)),
                ]),
              ),
              Text(formatMoney(due.amount), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
            ]),
            const SizedBox(height: 14),
            if (pending)
              const StatusPill(label: 'Paiement déclaré — en attente de confirmation', color: AppColors.warning, icon: Icons.hourglass_top_rounded)
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: onPay,
                icon: const Icon(Icons.payments_rounded),
                label: const Text('PAYER LA COTISATION'),
              ),
          ]),
        ),
      ),
    );
  }
}

class _PayLine extends StatelessWidget {
  const _PayLine({required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600, fontSize: bold ? 20 : 15)),
        ),
      ]),
    );
  }
}
