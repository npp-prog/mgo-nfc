import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../models/tag_info.dart';
import '../../router.dart';
import '../../services/admin_repository.dart';

class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = AppScope.of(context).admin;
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.tagNew),
        icon: const Icon(Icons.add),
        label: const Text('Add tag'),
      ),
      body: StreamBuilder<List<TagInfo>>(
        stream: admin.watchTags(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Could not load tags.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tags = snap.data!;
          if (tags.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No tags yet. Tap "Add tag" and hold a blank NTAG215 sticker to the phone.',
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: tags.length,
            itemBuilder: (context, i) => _TagTile(tag: tags[i]),
          );
        },
      ),
    );
  }
}

class _TagTile extends StatelessWidget {
  const _TagTile({required this.tag});
  final TagInfo tag;

  Future<void> _edit(BuildContext context) async {
    final admin = AppScope.of(context).admin;
    final messenger = ScaffoldMessenger.of(context);
    final label = TextEditingController(text: tag.label);
    final location = TextEditingController(text: tag.location);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${tag.tagId}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('tag-edit-label'),
              controller: label,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            TextField(
              key: const Key('tag-edit-location'),
              controller: location,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || label.text.trim().isEmpty) return;
    try {
      await admin.updateTag(
        tag.tagId,
        label: label.text.trim(),
        location: location.text.trim(),
        active: tag.active,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errorText(e))));
    }
  }

  Future<void> _setActive(BuildContext context, bool active) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppScope.of(context).admin.updateTag(
        tag.tagId,
        label: tag.label,
        location: tag.location,
        active: active,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errorText(e))));
    }
  }

  static String _errorText(Object e) =>
      e is AdminFailure ? e.message : 'Could not save. Check your connection.';

  @override
  Widget build(BuildContext context) => ListTile(
    key: Key('tag-${tag.tagId}'),
    leading: Icon(
      Icons.nfc,
      color: tag.active ? null : Theme.of(context).disabledColor,
    ),
    title: Text(tag.label),
    subtitle: Text(
      [
        if (tag.location.isNotEmpty) tag.location,
        'ID ${tag.tagId}',
        'UID ${tag.uid}',
        if (!tag.active) 'Disabled',
      ].join(' · '),
    ),
    isThreeLine: true,
    trailing: PopupMenuButton<String>(
      key: Key('tag-menu-${tag.tagId}'),
      onSelected: (v) => switch (v) {
        'edit' => _edit(context),
        'rewrite' => context.push(Routes.tagRewrite(tag.tagId)),
        'disable' => _setActive(context, false),
        'enable' => _setActive(context, true),
        _ => null,
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: Text('Edit label / location'),
        ),
        const PopupMenuItem(
          value: 'rewrite',
          child: Text('Rewrite or replace tag'),
        ),
        tag.active
            ? const PopupMenuItem(
                value: 'disable',
                child: Text('Disable (stops check-ins)'),
              )
            : const PopupMenuItem(value: 'enable', child: Text('Enable')),
      ],
    ),
  );
}
