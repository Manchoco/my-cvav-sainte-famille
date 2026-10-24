import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/repository.dart';
import '../../config.dart';
import '../../models.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Administration complète : comptes, maintenance et mises à jour, code d'accès responsable, journal.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administration'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(icon: Icon(Icons.manage_accounts_rounded), text: 'Comptes'),
            Tab(icon: Icon(Icons.construction_rounded), text: 'Maintenance'),
            Tab(icon: Icon(Icons.key_rounded), text: 'Accès'),
            Tab(icon: Icon(Icons.history_rounded), text: 'Journal'),
          ]),
        ),
        body: const TabBarView(children: [_UsersTab(), _MaintenanceTab(), _AccessTab(), _AuditTab()]),
      ),
    );
  }
}

Future<void> _showSecret(BuildContext context, {required String title, required String intro, required String secret, required String shareText}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(intro),
        const SizedBox(height: 14),
        SelectableText(secret, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2, color: AppColors.primaryDark)),
        const SizedBox(height: 10),
        const Text('Il ne sera plus affiché : transmettez-le maintenant, en privé.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: secret));
            showMessage(ctx, 'Copié');
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copier'),
        ),
        TextButton.icon(
          onPressed: () => SharePlus.instance.share(ShareParams(text: shareText)),
          icon: const Icon(Icons.share_rounded),
          label: const Text('Partager'),
        ),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

// ---------------- Comptes ----------------

class _UsersTab extends StatefulWidget {
  const _UsersTab();
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  String? _role;
  String _query = '';
  Timer? _debounce;
  late Future<List<AdminUser>> _future = _load();

  Future<List<AdminUser>> _load() => Repo.adminUsers(role: _role, q: _query);
  void _reload() => setState(() => _future = _load());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CreateUserSheet(),
    );
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add_rounded), label: const Text('Créer')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Nom ou numéro', prefixIcon: Icon(Icons.search_rounded), contentPadding: EdgeInsets.symmetric(vertical: 12)),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                _query = v.trim();
                _reload();
              });
            },
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final (value, label) in [(null, 'Tous'), ('admin', 'Administrateurs'), ('responsable', 'Responsables'), ('parent', 'Parents')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _role == value,
                  onSelected: (_) {
                    _role = value;
                    _reload();
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: AsyncBody<List<AdminUser>>(
              future: _future,
              onRetry: _reload,
              builder: (users) => users.isEmpty
                  ? ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.person_search_rounded, title: 'Aucun compte')])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: users.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final u = users[i];
                        final color = u.role == 'admin' ? AppColors.danger : u.role == 'responsable' ? AppColors.primary : AppColors.warning;
                        return Card(
                          child: ListTile(
                            onTap: () async {
                              final changed = await showModalBottomSheet<bool>(
                                context: context,
                                isScrollControlled: true,
                                showDragHandle: true,
                                builder: (_) => _UserSheet(user: u),
                              );
                              if (changed == true) _reload();
                            },
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.15),
                              child: Icon(u.role == 'admin' ? Icons.shield_rounded : u.role == 'responsable' ? Icons.groups_rounded : Icons.family_restroom_rounded, color: color),
                            ),
                            title: Text(u.fullName, style: TextStyle(fontWeight: FontWeight.w700, decoration: u.disabled ? TextDecoration.lineThrough : null)),
                            subtitle: Text([
                              u.phone,
                              if (u.role == 'parent') '${u.childrenCount} enfant(s)',
                              if (u.legion != null) u.legion!.label,
                              if (u.lastLoginAt != null) 'vu ${formatDate(u.lastLoginAt, pattern: 'd MMM')}',
                            ].join(' · ')),
                            trailing: u.disabled
                                ? const StatusPill(label: 'Désactivé', color: AppColors.muted)
                                : StatusPill(label: u.roleLabel, color: color),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CreateUserSheet extends StatefulWidget {
  const _CreateUserSheet();
  @override
  State<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends State<_CreateUserSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'responsable';
  Legion? _legion;
  bool _busy = false;

  Future<void> _submit() async {
    if (_name.text.trim().length < 2 || _phone.text.replaceAll(RegExp(r'\D'), '').length < 8) {
      showMessage(context, 'Nom et numéro de téléphone requis', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final (user, password) = await Repo.adminCreateUser(role: _role, fullName: _name.text.trim(), phone: _phone.text, legion: _legion);
      if (!mounted) return;
      await _showSecret(
        context,
        title: 'Compte créé',
        intro: '${user.fullName} se connecte avec le numéro ${user.phone} et ce mot de passe provisoire :',
        secret: password,
        shareText: 'Bonjour ${user.fullName}, votre compte My CVAV Sainte Famille est prêt.\n'
            'Numéro : ${user.phone}\nMot de passe provisoire : $password\n'
            'Vous choisirez votre propre mot de passe à la première connexion.',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Créer un compte', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'parent', label: Text('Parent')),
              ButtonSegment(value: 'responsable', label: Text('Responsable')),
              ButtonSegment(value: 'admin', label: Text('Admin')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 14),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nom et prénoms')),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Numéro de téléphone')),
          if (_role != 'parent') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<Legion>(
              initialValue: _legion,
              decoration: const InputDecoration(labelText: 'Légion (facultatif)'),
              items: [for (final l in Legion.values) DropdownMenuItem(value: l, child: Text(l.label))],
              onChanged: (v) => setState(() => _legion = v),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Créer et obtenir le mot de passe')),
        ]),
      ),
    );
  }
}

class _UserSheet extends StatefulWidget {
  const _UserSheet({required this.user});
  final AdminUser user;
  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  late AdminUser _user = widget.user;
  bool _changed = false;

  bool get _isMe => context.read<Session>().user?.id == _user.id;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _changed = true;
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _update(Map<String, dynamic> data) => _run(() async {
        final u = await Repo.adminUpdateUser(_user.id, data);
        setState(() => _user = u);
      });

  @override
  Widget build(BuildContext context) {
    final u = _user;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(u.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${u.phone} · ${u.roleLabel}${u.mustChangePassword ? ' · mot de passe provisoire' : ''}', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            const Text('Rôle', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'parent', label: Text('Parent')),
                ButtonSegment(value: 'responsable', label: Text('Responsable')),
                ButtonSegment(value: 'admin', label: Text('Admin')),
              ],
              selected: {u.role},
              onSelectionChanged: _isMe
                  ? null
                  : (s) async {
                      if (s.first == 'admin' &&
                          !await confirm(context, title: 'Donner les droits administrateur ?', message: '${u.fullName} aura un contrôle total de l\'application.')) {
                        return;
                      }
                      await _update({'role': s.first});
                    },
            ),
            if (u.role != 'parent') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<Legion?>(
                initialValue: u.legion,
                decoration: const InputDecoration(labelText: 'Légion'),
                items: [
                  const DropdownMenuItem<Legion?>(value: null, child: Text('Aucune')),
                  for (final l in Legion.values) DropdownMenuItem<Legion?>(value: l, child: Text(l.label)),
                ],
                onChanged: (v) => _update({'legion': v?.name}),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compte actif'),
              subtitle: Text(u.disabled ? 'Connexion impossible' : 'Peut se connecter'),
              value: !u.disabled,
              onChanged: _isMe ? null : (v) => _update({'disabled': !v}),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.password_rounded),
              title: const Text('Réinitialiser le mot de passe'),
              subtitle: const Text('Génère un mot de passe provisoire'),
              onTap: () => _run(() async {
                if (!await confirm(context, title: 'Réinitialiser ?', message: 'Le mot de passe actuel de ${u.fullName} ne fonctionnera plus.')) return;
                final pwd = await Repo.adminResetPassword(u.id);
                if (!context.mounted) return;
                await _showSecret(
                  context,
                  title: 'Mot de passe provisoire',
                  intro: 'Nouveau mot de passe de ${u.fullName} (${u.phone}) :',
                  secret: pwd,
                  shareText: 'Bonjour ${u.fullName}, votre mot de passe My CVAV a été réinitialisé.\n'
                      'Numéro : ${u.phone}\nMot de passe provisoire : $pwd\nVous en choisirez un nouveau à la connexion.',
                );
              }),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Déconnecter tous ses appareils'),
              onTap: () => _run(() async {
                await Repo.adminLogoutUser(u.id);
                if (context.mounted) showMessage(context, 'Sessions fermées');
              }),
            ),
            if (!_isMe)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                title: const Text('Supprimer le compte', style: TextStyle(color: AppColors.danger)),
                onTap: () => _run(() async {
                  if (!await confirm(context, title: 'Supprimer ${u.fullName} ?', message: 'Action définitive. Les enfants ne sont pas supprimés.', confirmLabel: 'Supprimer', danger: true)) {
                    return;
                  }
                  await Repo.adminDeleteUser(u.id);
                  _changed = true;
                  if (context.mounted) Navigator.pop(context, true);
                }),
              ),
          ]),
        ),
      ),
    );
  }
}

// ---------------- Maintenance & mises à jour ----------------

class _MaintenanceTab extends StatefulWidget {
  const _MaintenanceTab();
  @override
  State<_MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends State<_MaintenanceTab> {
  late Future<Map<String, dynamic>> _future = Repo.adminSettings();
  final _message = TextEditingController();
  final _latest = TextEditingController();
  final _min = TextEditingController();
  final _url = TextEditingController();
  final _notes = TextEditingController();
  bool _enabled = false;
  bool _loaded = false;
  bool _busy = false;

  void _fill(Map<String, dynamic> s) {
    if (_loaded) return;
    _loaded = true;
    final m = s['maintenance'] as Map<String, dynamic>;
    final u = s['appUpdate'] as Map<String, dynamic>;
    _enabled = m['enabled'] == true;
    _message.text = m['message'] as String? ?? '';
    _latest.text = '${u['latestBuild'] ?? 0}';
    _min.text = '${u['minBuild'] ?? 0}';
    _url.text = u['url'] as String? ?? '';
    _notes.text = u['notes'] as String? ?? '';
  }

  Future<void> _save(Future<void> Function() action, String ok) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        showMessage(context, ok);
        context.read<Session>().refreshStatus();
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Map<String, dynamic>>(
      future: _future,
      onRetry: () => setState(() => _future = Repo.adminSettings()),
      builder: (s) {
        _fill(s);
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            color: _enabled ? const Color(0xFFFFF3E0) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mode maintenance', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Bloque l\'application pour tous, sauf les administrateurs. Les paiements Wave restent confirmés.'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                TextField(controller: _message, maxLines: 3, decoration: const InputDecoration(labelText: 'Message affiché aux utilisateurs')),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _enabled ? AppColors.warning : null),
                  onPressed: _busy
                      ? null
                      : () => _save(() => Repo.adminSetMaintenance(_enabled, _message.text.trim()),
                          _enabled ? 'Maintenance activée' : 'Maintenance désactivée'),
                  child: Text(_enabled ? 'Activer la maintenance' : 'Enregistrer (application ouverte)'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Mise à jour de l\'application', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Cet appareil : version ${AppConfig.appVersion}, build ${AppConfig.appBuild}.', style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: _latest, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dernier build'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _min, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Build minimal'))),
                ]),
                const SizedBox(height: 12),
                TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Lien de téléchargement (https://…)')),
                const SizedBox(height: 12),
                TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Nouveautés')),
                const SizedBox(height: 8),
                const Text('« Dernier build » propose la mise à jour ; un « build minimal » supérieur à celui d\'un téléphone l\'oblige à mettre à jour.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _save(
                            () => Repo.adminSetAppUpdate(
                              latestBuild: int.tryParse(_latest.text.trim()) ?? 0,
                              minBuild: int.tryParse(_min.text.trim()) ?? 0,
                              url: _url.text.trim(),
                              notes: _notes.text.trim(),
                            ),
                            'Informations de mise à jour publiées',
                          ),
                  child: const Text('Publier'),
                ),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

// ---------------- Code d'accès responsable ----------------

class _AccessTab extends StatefulWidget {
  const _AccessTab();
  @override
  State<_AccessTab> createState() => _AccessTabState();
}

class _AccessTabState extends State<_AccessTab> {
  late Future<Map<String, dynamic>> _future = Repo.adminSettings();

  @override
  Widget build(BuildContext context) {
    return AsyncBody<Map<String, dynamic>>(
      future: _future,
      onRetry: () => setState(() => _future = Repo.adminSettings()),
      builder: (s) {
        final code = s['signupCode'] as String? ?? '';
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Code d\'accès responsable', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('Demandé à la création d\'un compte responsable. Ne le donnez qu\'aux responsables.', style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 14),
                SelectableText(code.isEmpty ? 'Aucun (inscription fermée)' : code,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: AppColors.primaryDark)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: code.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: code));
                              showMessage(context, 'Code copié');
                            },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copier'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: code.isEmpty
                          ? null
                          : () => SharePlus.instance.share(ShareParams(
                                text: 'Code d\'accès responsable My CVAV Sainte Famille : $code\n'
                                    'Choisissez « Responsable » puis « Créer un compte » dans l\'application.',
                              )),
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('Partager'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () async {
                    if (!await confirm(context,
                        title: 'Générer un nouveau code ?',
                        message: 'L\'ancien code ne fonctionnera plus. Les comptes déjà créés ne sont pas touchés.',
                        confirmLabel: 'Générer')) {
                      return;
                    }
                    try {
                      await Repo.adminRotateSignupCode();
                      setState(() => _future = Repo.adminSettings());
                    } catch (e) {
                      if (context.mounted) showMessage(context, errorText(e), error: true);
                    }
                  },
                  icon: const Icon(Icons.autorenew_rounded),
                  label: const Text('Générer un nouveau code'),
                ),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

// ---------------- Journal ----------------

const _actionLabels = {
  'user.create': 'Compte créé',
  'user.update': 'Compte modifié',
  'user.reset_password': 'Mot de passe réinitialisé',
  'user.logout': 'Sessions fermées',
  'user.delete': 'Compte supprimé',
  'maintenance.on': 'Maintenance activée',
  'maintenance.off': 'Maintenance désactivée',
  'app_update.set': 'Mise à jour publiée',
  'signup_code.rotate': 'Nouveau code d\'accès',
  'child.delete': 'Enfant supprimé',
  'child.regenerate_code': 'Nouveau code enfant',
};

class _AuditTab extends StatefulWidget {
  const _AuditTab();
  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  late Future<List<Map<String, dynamic>>> _future = Repo.adminAudit();

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _future = Repo.adminAudit()),
      child: AsyncBody<List<Map<String, dynamic>>>(
        future: _future,
        onRetry: () => setState(() => _future = Repo.adminAudit()),
        builder: (entries) => entries.isEmpty
            ? ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.history_rounded, title: 'Aucune action enregistrée')])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final e = entries[i];
                  final details = e['details'] is Map ? (e['details'] as Map) : const {};
                  return Card(
                    child: ListTile(
                      dense: true,
                      title: Text(_actionLabels[e['action']] ?? '${e['action']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        '${e['actor'] ?? 'Système'} · ${formatDate(e['createdAt'] as String?, pattern: 'd MMM yyyy HH:mm')}',
                        if (details['name'] != null) '${details['name']}',
                        if (details['fullName'] != null) '${details['fullName']}',
                      ].join('\n')),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
