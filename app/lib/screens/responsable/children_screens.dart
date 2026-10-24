import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../api/repository.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key});

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  late Future<List<Child>> _future = Repo.children();
  final _search = TextEditingController();
  String _query = '';
  Timer? _debounce;

  void _reload() => setState(() => _future = Repo.children());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _openForm([Child? child]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ChildFormScreen(child: child)));
    if (saved == true) _reload();
  }

  Future<void> _openImport() async {
    final imported = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ImportScreen()));
    if (imported == true) _reload();
  }

  void _showAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_rounded)),
              title: const Text('Ajouter un enfant', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Saisie manuelle'),
              onTap: () {
                Navigator.pop(ctx);
                _openForm();
              },
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.upload_file_rounded)),
              title: const Text('Importer une liste', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Word, PDF, Excel ou CSV'),
              onTap: () {
                Navigator.pop(ctx);
                _openImport();
              },
            ),
          ]),
        ),
      ),
    );
  }

  List<Child> _filter(List<Child> all, Legion? legion) {
    final q = _query.toLowerCase();
    return all.where((c) {
      if (legion != null && c.legion != legion) return false;
      if (q.isEmpty) return true;
      return c.fullName.toLowerCase().contains(q) || (c.parentPhone ?? '').contains(q) || (c.address ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = legionTabs();
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Enfants'),
          actions: [IconButton(tooltip: 'Importer', onPressed: _openImport, icon: const Icon(Icons.upload_file_rounded))],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(112),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Rechercher un nom, un contact, un quartier…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 250), () => setState(() => _query = v.trim()));
                  },
                ),
              ),
              FutureBuilder<List<Child>>(
                future: _future,
                builder: (context, snap) {
                  final all = snap.data ?? const <Child>[];
                  return TabBar(
                    isScrollable: true,
                    tabs: [for (final l in tabs) legionTab(l, count: snap.hasData ? _filter(all, l).length : null)],
                  );
                },
              ),
            ]),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddMenu,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Ajouter'),
        ),
        body: AsyncBody<List<Child>>(
          future: _future,
          onRetry: _reload,
          builder: (all) => TabBarView(
            children: [
              for (final l in tabs)
                RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: _ChildList(
                    children: _filter(all, l),
                    emptyAction: all.isEmpty ? _showAddMenu : null,
                    onTap: (c) => _showDetail(c),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(Child child) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChildDetailSheet(child: child, onEdit: () => _openForm(child)),
    );
    if (changed == true) _reload();
  }
}

class _ChildList extends StatelessWidget {
  const _ChildList({required this.children, required this.onTap, this.emptyAction});
  final List<Child> children;
  final ValueChanged<Child> onTap;
  final VoidCallback? emptyAction;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 60),
        EmptyState(
          icon: Icons.groups_rounded,
          title: 'Aucun enfant ici',
          message: emptyAction != null ? 'Ajoutez les enfants un par un ou importez votre liste (Word, PDF, Excel).' : 'Aucun résultat pour ce filtre.',
          action: emptyAction == null
              ? null
              : FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
                  onPressed: emptyAction,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ajouter des enfants'),
                ),
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = children[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () => onTap(c),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: ChildAvatar(c),
            title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              [if (c.age != null) '${c.age} ans', if (c.address != null) c.address!, if (c.parentPhone != null) c.parentPhone!].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: LegionBadge(c.legion, small: true),
          ),
        );
      },
    );
  }
}

class ChildDetailSheet extends StatefulWidget {
  const ChildDetailSheet({super.key, required this.child, required this.onEdit});
  final Child child;
  final VoidCallback onEdit;

  @override
  State<ChildDetailSheet> createState() => _ChildDetailSheetState();
}

class _ChildDetailSheetState extends State<ChildDetailSheet> {
  late Child _child = widget.child;
  bool _changed = false;

  Future<void> _call() async {
    final phone = _child.parentPhone;
    if (phone == null) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _whatsapp() async {
    final phone = _child.parentPhone;
    if (phone == null) return;
    final intl = phone.length == 10 ? '225$phone' : phone;
    await launchUrl(Uri.parse('https://wa.me/$intl'), mode: LaunchMode.externalApplication);
  }

  void _shareCode() {
    SharePlus.instance.share(ShareParams(
      text: 'Bonjour ! Voici le code enfant de ${_child.fullName} pour l\'application My CVAV Sainte Famille : '
          '${_child.linkCode}\nCréez votre compte parent puis saisissez ce code dans « Mes enfants ».',
    ));
  }

  Future<void> _regenerate() async {
    final ok = await confirm(context,
        title: 'Nouveau code ?',
        message: 'Les parents déjà liés à cet enfant perdront l\'accès et devront saisir le nouveau code.',
        confirmLabel: 'Générer');
    if (!ok) return;
    try {
      final c = await Repo.regenerateCode(_child.id);
      setState(() {
        _child = c;
        _changed = true;
      });
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: 'Supprimer ${_child.fullName} ?',
        message: 'Ses présences et cotisations seront aussi supprimées. Cette action est définitive.',
        confirmLabel: 'Supprimer',
        danger: true);
    if (!ok) return;
    try {
      await Repo.deleteChild(_child.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              ChildAvatar(c, radius: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Row(children: [
                    LegionBadge(c.legion),
                    if (c.age != null) ...[const SizedBox(width: 8), Text('${c.age} ans', style: const TextStyle(color: AppColors.muted))],
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            _InfoRow(icon: Icons.cake_rounded, label: 'Date de naissance', value: c.birthDate != null ? formatDate(c.birthDate) : 'Non renseignée'),
            _InfoRow(icon: Icons.person_rounded, label: 'Parent / tuteur', value: c.parentName ?? 'Non renseigné'),
            _InfoRow(icon: Icons.phone_rounded, label: 'Contact des parents', value: c.parentPhone ?? 'Non renseigné'),
            _InfoRow(icon: Icons.home_rounded, label: 'Lieu d\'habitation', value: c.address ?? 'Non renseigné'),
            if (c.parentPhone != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: _call, icon: const Icon(Icons.call_rounded), label: const Text('Appeler'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: _whatsapp, icon: const Icon(Icons.chat_rounded), label: const Text('WhatsApp'))),
              ]),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Code enfant (pour le parent)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: SelectableText(c.linkCode ?? '—',
                        style: const TextStyle(fontSize: 26, letterSpacing: 4, fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
                  ),
                  IconButton(
                    tooltip: 'Copier',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: c.linkCode ?? ''));
                      showMessage(context, 'Code copié');
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton(tooltip: 'Partager', onPressed: _shareCode, icon: const Icon(Icons.share_rounded)),
                ]),
                Text(
                  (c.linkedParents ?? 0) > 0 ? '${c.linkedParents} parent(s) lié(s)' : 'Aucun parent lié pour le moment',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                TextButton.icon(onPressed: _regenerate, icon: const Icon(Icons.autorenew_rounded, size: 18), label: const Text('Générer un nouveau code')),
              ]),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context, _changed);
                widget.onEdit();
              },
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Modifier'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Supprimer'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ]),
        ),
      ]),
    );
  }
}

class ChildFormScreen extends StatefulWidget {
  const ChildFormScreen({super.key, this.child});
  final Child? child;

  @override
  State<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends State<ChildFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _last = TextEditingController(text: widget.child?.lastName);
  late final _first = TextEditingController(text: widget.child?.firstName);
  late final _age = TextEditingController(text: widget.child?.birthDate == null ? widget.child?.age?.toString() : null);
  late final _parent = TextEditingController(text: widget.child?.parentName);
  late final _phone = TextEditingController(text: widget.child?.parentPhone);
  late final _address = TextEditingController(text: widget.child?.address);
  late String? _birthDate = widget.child?.birthDate;
  late Legion? _legion = widget.child?.legion;
  bool _busy = false;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birthDate != null ? DateTime.parse(_birthDate!) : DateTime(now.year - 10),
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      helpText: 'Date de naissance',
    );
    if (d != null) setState(() => _birthDate = d.toIso8601String().substring(0, 10));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Repo.saveChild({
        'lastName': _last.text.trim(),
        'firstName': _first.text.trim(),
        'birthDate': _birthDate,
        'age': _birthDate == null && _age.text.trim().isNotEmpty ? int.parse(_age.text.trim()) : null,
        'legion': _legion!.name,
        'parentName': _parent.text.trim(),
        'parentPhone': _phone.text.trim(),
        'address': _address.text.trim(),
      }, id: widget.child?.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.child == null ? 'Nouvel enfant' : 'Modifier')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            TextFormField(
              controller: _last,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Nom *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Nom requis' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _first,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Prénoms *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Prénom requis' : null,
            ),
            const SizedBox(height: 14),
            const Text('Légion *', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            FormField<Legion>(
              initialValue: _legion,
              validator: (_) => _legion == null ? 'Choisissez une légion' : null,
              builder: (state) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final l in Legion.values)
                    ChoiceChip(
                      label: Text(l.label),
                      avatar: Icon(l.icon, size: 18, color: _legion == l ? Colors.white : l.color),
                      selected: _legion == l,
                      selectedColor: l.color,
                      labelStyle: TextStyle(color: _legion == l ? Colors.white : AppColors.navy, fontWeight: FontWeight.w600),
                      showCheckmark: false,
                      onSelected: (_) {
                        setState(() => _legion = l);
                        state.didChange(l);
                      },
                    ),
                ]),
                if (state.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text(state.errorText!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date de naissance',
                      suffixIcon: _birthDate == null
                          ? const Icon(Icons.calendar_month_rounded)
                          : IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => setState(() => _birthDate = null)),
                    ),
                    child: Text(_birthDate == null ? '—' : formatDate(_birthDate)),
                  ),
                ),
              ),
              if (_birthDate == null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    controller: _age,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'ou âge'),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return null;
                      final n = int.tryParse(v!);
                      return n == null || n > 30 ? 'Invalide' : null;
                    },
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 24),
            const Text('Parents', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            TextFormField(controller: _parent, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nom du parent / tuteur')),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Contact des parents', prefixIcon: Icon(Icons.phone_rounded)),
              validator: (v) {
                final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return v!.trim().isNotEmpty && d.length < 8 ? 'Numéro invalide' : null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Lieu d\'habitation', prefixIcon: Icon(Icons.home_rounded)),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const CircularProgressIndicator(color: Colors.white) : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Import d'une liste : choix du fichier -> aperçu modifiable -> validation.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  List<ImportRow>? _rows;
  String? _fileName;
  bool _busy = false;

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['docx', 'pdf', 'xlsx', 'csv', 'txt'],
    );
    if (file == null) return;
    setState(() {
      _busy = true;
      _fileName = file.name;
    });
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) throw ApiException('Fichier trop volumineux (5 Mo maximum)');
      final rows = await Repo.importPreview(bytes, file.name);
      for (final r in rows) {
        r.selected = !r.duplicate;
      }
      setState(() => _rows = rows);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final selected = _rows!.where((r) => r.selected).toList();
    if (selected.any((r) => !r.valid)) {
      showMessage(context, 'Complétez la légion et le prénom des lignes signalées en rouge.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await Repo.importCommit(selected, skipDuplicates: false);
      if (!mounted) return;
      showMessage(context, '${res['created']} enfant(s) ajouté(s)');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editRow(ImportRow row) async {
    final last = TextEditingController(text: row.lastName);
    final first = TextEditingController(text: row.firstName);
    final phone = TextEditingController(text: row.parentPhone);
    final address = TextEditingController(text: row.address);
    Legion? legion = row.legion;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: last, decoration: const InputDecoration(labelText: 'Nom')),
              const SizedBox(height: 10),
              TextField(controller: first, decoration: const InputDecoration(labelText: 'Prénoms')),
              const SizedBox(height: 10),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact')),
              const SizedBox(height: 10),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Lieu d\'habitation')),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final l in Legion.values)
                  ChoiceChip(label: Text(l.label), selected: legion == l, onSelected: (_) => setSheet(() => legion = l)),
              ]),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        row
          ..lastName = last.text.trim().toUpperCase()
          ..firstName = first.text.trim()
          ..parentPhone = phone.text.trim().isEmpty ? null : phone.text.trim()
          ..address = address.text.trim().isEmpty ? null : address.text.trim()
          ..legion = legion;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final selectedCount = rows?.where((r) => r.selected).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Importer une liste')),
      bottomNavigationBar: rows == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _busy || selectedCount == 0 ? null : _commit,
                  icon: const Icon(Icons.check_rounded),
                  label: Text('Ajouter $selectedCount enfant(s)'),
                ),
              ),
            ),
      body: _busy
          ? const LoadingView()
          : rows == null
              ? ListView(padding: const EdgeInsets.all(24), children: [
                  const SizedBox(height: 20),
                  const EmptyState(
                    icon: Icons.upload_file_rounded,
                    title: 'Importez votre liste d\'enfants',
                    message: 'Formats acceptés : Word (.docx), PDF, Excel (.xlsx) ou CSV.\nL\'application reconnaît les colonnes Nom, Prénoms, Âge ou Date de naissance, Contact des parents, Lieu d\'habitation et Légion, ainsi que les titres de légion (« Cadets », « Aînés »…).',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.folder_open_rounded), label: const Text('Choisir un fichier')),
                  const SizedBox(height: 12),
                  const Text('Vous pourrez vérifier et corriger chaque ligne avant l\'enregistrement.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ])
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.description_rounded, color: AppColors.primary),
                      title: Text(_fileName ?? ''),
                      subtitle: Text('${rows.length} enfant(s) reconnu(s) · ${rows.where((r) => r.duplicate).length} déjà inscrit(s)'),
                      trailing: TextButton(onPressed: _pick, child: const Text('Changer')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: r.selected && !r.valid ? AppColors.danger : const Color(0xFFE3EDF4)),
                        ),
                        child: CheckboxListTile(
                          value: r.selected,
                          onChanged: (v) => setState(() => r.selected = v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text('${r.lastName} ${r.firstName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text([if (r.age != null) '${r.age} ans', if (r.parentPhone != null) r.parentPhone!, if (r.address != null) r.address!].join(' · ')),
                            const SizedBox(height: 4),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              if (r.legion != null) LegionBadge(r.legion!, small: true),
                              if (r.duplicate) const StatusPill(label: 'Déjà inscrit', color: AppColors.warning),
                              for (final w in r.warnings) StatusPill(label: w, color: AppColors.muted),
                            ]),
                          ]),
                          secondary: IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => _editRow(r)),
                        ),
                      ),
                    ),
                ]),
    );
  }
}
