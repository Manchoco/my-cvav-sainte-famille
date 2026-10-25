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

/// Administration complète : comptes, sécurité, maintenance et mises à jour, code d'accès responsable, journal.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administration'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(icon: Icon(Icons.manage_accounts_rounded), text: 'Comptes'),
            Tab(icon: Icon(Icons.security_rounded), text: 'Sécurité'),
            Tab(icon: Icon(Icons.construction_rounded), text: 'Maintenance'),
            Tab(icon: Icon(Icons.key_rounded), text: 'Accès'),
            Tab(icon: Icon(Icons.history_rounded), text: 'Journal'),
          ]),
        ),
        body: const TabBarView(children: [_UsersTab(), _SecurityTab(), _MaintenanceTab(), _AccessTab(), _AuditTab()]),
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
                      if (s.first == 'admin') {
                        final password = await _askPassword(context,
                            title: 'Nommer ${u.fullName} administrateur ?',
                            message: 'Cette personne aura un contrôle total de l\'application. Confirmez avec votre mot de passe.');
                        if (password == null) return;
                        await _update({'role': 'admin', 'confirmPassword': password});
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
  'due.amounts': 'Prix d\'une cotisation modifiés',
  'security.block_ip': 'Adresse IP bloquée',
  'security.unblock_ip': 'Adresse IP débloquée',
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

Future<String?> _askPassword(BuildContext context, {required String title, required String message}) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message),
        const SizedBox(height: 12),
        TextField(controller: ctrl, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Votre mot de passe')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
      ],
    ),
  );
  return ok == true && ctrl.text.isNotEmpty ? ctrl.text : null;
}

// ---------------- Sécurité ----------------

Color _severityColor(String? s) => switch (s) { 'critical' => AppColors.danger, 'warning' => AppColors.warning, _ => AppColors.primary };

class _SecurityTab extends StatefulWidget {
  const _SecurityTab();
  @override
  State<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<_SecurityTab> {
  late Future<Map<String, dynamic>> _future = Repo.adminSecurity();

  void _reload() => setState(() => _future = Repo.adminSecurity());

  Future<void> _block(String ip) async {
    int? hours = 24;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Bloquer $ip ?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Toutes les requêtes venant de cette adresse seront refusées. Plusieurs abonnés d'un même opérateur mobile "
                'peuvent partager une adresse : préférez un blocage limité dans le temps.'),
            const SizedBox(height: 12),
            SegmentedButton<int?>(
              segments: const [
                ButtonSegment(value: 24, label: Text('24 h')),
                ButtonSegment(value: 24 * 7, label: Text('7 jours')),
                ButtonSegment(value: null, label: Text('Définitif')),
              ],
              selected: {hours},
              onSelectionChanged: (s) => setD(() => hours = s.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif (facultatif)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Bloquer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Repo.adminBlockIp(ip, hours: hours, reason: reason.text.trim().isEmpty ? null : reason.text.trim());
      if (mounted) showMessage(context, 'Adresse $ip bloquée');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _unblock(String ip) async {
    if (!await confirm(context, title: 'Débloquer $ip ?', message: 'Les requêtes de cette adresse seront de nouveau acceptées.')) return;
    try {
      await Repo.adminUnblockIp(ip);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _openUser(int id) async {
    try {
      final users = await Repo.adminUsers();
      final u = users.where((x) => x.id == id).firstOrNull;
      if (u == null || !mounted) return;
      await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _UserSheet(user: u));
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: AsyncBody<Map<String, dynamic>>(
        future: _future,
        onRetry: _reload,
        builder: (data) {
          final status = data['status'] as String? ?? 'ok';
          final threats = (data['threats'] as List? ?? const []).cast<Map<String, dynamic>>();
          final counts = (data['counts'] as Map? ?? const {}).cast<String, dynamic>();
          final topIps = (data['topIps'] as List? ?? const []).cast<Map<String, dynamic>>();
          final blocked = (data['blocked'] as List? ?? const []).cast<Map<String, dynamic>>();
          final events = (data['events'] as List? ?? const []).cast<Map<String, dynamic>>();
          int day(String t) => ((counts[t] as Map?)?['day'] as int?) ?? 0;
          final color = _severityColor(status == 'ok' ? null : status);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                color: (status == 'ok' ? AppColors.success : color).withValues(alpha: 0.12),
                child: ListTile(
                  leading: Icon(
                    status == 'ok' ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
                    color: status == 'ok' ? AppColors.success : color,
                    size: 36,
                  ),
                  title: Text(
                    status == 'ok' ? 'Aucune menace détectée' : status == 'critical' ? 'Menace sérieuse détectée' : 'Activité suspecte',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(status == 'ok'
                      ? 'Analyse des dernières 24 heures. Tirez vers le bas pour actualiser.'
                      : '${threats.length} point(s) à traiter ci-dessous, avec la marche à suivre.'),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                StatusPill(label: '${day('login_failed') + day('admin_login_failed')} échec(s) de connexion', color: AppColors.warning),
                StatusPill(label: '${day('suspicious_input')} injection(s)', color: AppColors.danger),
                StatusPill(label: '${day('invalid_token')} jeton(s) falsifié(s)', color: AppColors.danger),
                StatusPill(label: '${day('forbidden')} accès interdit(s)', color: AppColors.warning),
                StatusPill(label: '${day('rate_limited')} limitation(s)', color: AppColors.primary),
                StatusPill(label: '${day('admin_login')} connexion(s) admin', color: AppColors.primary),
              ]),
              for (final t in threats) ...[
                const SizedBox(height: 12),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: _severityColor(t['level'] as String?), width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.warning_amber_rounded, color: _severityColor(t['level'] as String?)),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${t['title']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                      ]),
                      const SizedBox(height: 6),
                      Text('${t['detail']}'),
                      const SizedBox(height: 8),
                      Text('Que faire : ${t['remedy']}', style: const TextStyle(color: AppColors.muted)),
                      if (t['action'] is Map) ...[
                        const SizedBox(height: 10),
                        Builder(builder: (_) {
                          final a = (t['action'] as Map).cast<String, dynamic>();
                          return a['type'] == 'block_ip'
                              ? FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                                  onPressed: () => _block(a['ip'] as String),
                                  icon: const Icon(Icons.block_rounded),
                                  label: Text('Bloquer ${a['ip']}'),
                                )
                              : FilledButton.tonalIcon(
                                  onPressed: () => _openUser(a['userId'] as int),
                                  icon: const Icon(Icons.manage_accounts_rounded),
                                  label: const Text('Ouvrir le compte'),
                                );
                        }),
                      ],
                    ]),
                  ),
                ),
              ],
              if (blocked.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Adresses bloquées', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                for (final b in blocked)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.block_rounded, color: AppColors.danger),
                      title: Text('${b['ip']}'),
                      subtitle: Text([
                        if (b['reason'] != null) '${b['reason']}',
                        b['expiresAt'] == null ? 'Définitif' : 'Jusqu\'au ${formatDate(b['expiresAt'] as String?, pattern: 'd MMM HH:mm')}',
                      ].join(' · ')),
                      trailing: TextButton(onPressed: () => _unblock(b['ip'] as String), child: const Text('Débloquer')),
                    ),
                  ),
              ],
              if (topIps.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Adresses les plus actives (24 h)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                for (final ip in topIps)
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.public_rounded, color: (ip['critical'] as int? ?? 0) > 0 ? AppColors.danger : AppColors.muted),
                      title: Text('${ip['ip']}'),
                      subtitle: Text('${ip['count']} événement(s)${(ip['critical'] as int? ?? 0) > 0 ? ' dont ${ip['critical']} grave(s)' : ''}'),
                      trailing: ip['blocked'] == true
                          ? const StatusPill(label: 'Bloquée', color: AppColors.danger)
                          : ip['mine'] == true
                              ? const StatusPill(label: 'Votre adresse', color: AppColors.primary)
                              : TextButton(onPressed: () => _block(ip['ip'] as String), child: const Text('Bloquer')),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              const Text('Journal de sécurité', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const Text('Touchez un événement pour voir la conduite à tenir.', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              if (events.isEmpty) const EmptyState(icon: Icons.shield_rounded, title: 'Aucun événement'),
              for (final e in events)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: Icon(Icons.circle, size: 14, color: _severityColor(e['severity'] as String?)),
                    title: Text('${e['label']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      formatDate(e['createdAt'] as String?, pattern: 'd MMM HH:mm'),
                      if (e['ip'] != null) '${e['ip']}',
                      if (e['user'] != null) '${e['user']}',
                    ].join(' · ')),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (e['advice'] != null) Text('Que faire : ${e['advice']}'),
                      if (e['path'] != null) Text('Adresse appelée : ${e['path']}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      if (e['phone'] != null) Text('Numéro visé : ${e['phone']}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      if (e['details'] is Map && (e['details'] as Map)['extrait'] != null)
                        Text('Extrait : ${(e['details'] as Map)['extrait']}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      if (e['ip'] != null && e['ip'] != data['viewerIp'] && e['type'] != 'admin_login' && !blocked.any((b) => b['ip'] == e['ip']))
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _block(e['ip'] as String),
                            icon: const Icon(Icons.block_rounded, color: AppColors.danger),
                            label: const Text('Bloquer cette adresse'),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
