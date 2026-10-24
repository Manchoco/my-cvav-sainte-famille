import 'package:flutter/material.dart';

import '../../api/repository.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Informations : publication par les responsables, lecture par tous.
class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key, required this.canEdit});
  final bool canEdit;

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  late Future<List<Post>> _future = Repo.posts();

  void _reload() => setState(() => _future = Repo.posts());

  Future<void> _edit([Post? post]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PostFormScreen(post: post)));
    if (saved == true) _reload();
  }

  Future<void> _delete(Post p) async {
    final ok = await confirm(context, title: 'Supprimer cette information ?', message: p.title, confirmLabel: 'Supprimer', danger: true);
    if (!ok) return;
    try {
      await Repo.deletePost(p.id);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informations')),
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.edit_rounded), label: const Text('Publier'))
          : null,
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncBody<List<Post>>(
          future: _future,
          onRetry: _reload,
          builder: (posts) => posts.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  EmptyState(icon: Icons.campaign_rounded, title: 'Aucune information', message: 'Les annonces des responsables apparaîtront ici.'),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: posts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => PostCard(
                    post: posts[i],
                    onEdit: widget.canEdit ? () => _edit(posts[i]) : null,
                    onDelete: widget.canEdit ? () => _delete(posts[i]) : null,
                  ),
                ),
        ),
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, this.onEdit, this.onDelete});
  final Post post;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (post.pinned) const Padding(padding: EdgeInsets.only(right: 6, top: 2), child: Icon(Icons.push_pin_rounded, size: 18, color: AppColors.gold)),
            Expanded(child: Text(post.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            if (onEdit != null)
              PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? onEdit!() : onDelete!(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Modifier')),
                  PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                ],
              ),
          ]),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(post.body, style: const TextStyle(fontSize: 15, height: 1.4)),
          ),
          const SizedBox(height: 10),
          Text('${post.author ?? 'Responsable'} · ${formatDate(post.createdAt, pattern: 'd MMM yyyy à HH:mm')}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class PostFormScreen extends StatefulWidget {
  const PostFormScreen({super.key, this.post});
  final Post? post;

  @override
  State<PostFormScreen> createState() => _PostFormScreenState();
}

class _PostFormScreenState extends State<PostFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.post?.title);
  late final _body = TextEditingController(text: widget.post?.body);
  late bool _pinned = widget.post?.pinned ?? false;
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Repo.savePost(id: widget.post?.id, title: _title.text.trim(), body: _body.text.trim(), pinned: _pinned);
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
      appBar: AppBar(title: Text(widget.post == null ? 'Nouvelle information' : 'Modifier')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          TextFormField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Titre'),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Titre requis' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _body,
            minLines: 6,
            maxLines: 14,
            maxLength: 5000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Message aux parents', alignLabelWithHint: true),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Message requis' : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
            title: const Text('Épingler en haut de la liste'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Publier'),
          ),
        ]),
      ),
    );
  }
}
