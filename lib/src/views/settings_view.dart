import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/settings.dart';

/// Settings view — session storage folder configuration.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  Future<String?> _pickFolder() async {
    if (Platform.isAndroid) {
      return SafSessionStorage.pickFolder();
    }
    final dir = await getDirectoryPath(
      initialDirectory: null,
      confirmButtonText: 'Choose this folder',
    );
    return dir;
  }

  Future<void> _applyFolder(
    WidgetRef ref,
    String? folder, {
    required bool migrate,
  }) async {
    if (folder == null) {
      return;
    }
    final settings = ref.read(settingsProvider);
    final current = ref.read(sessionStorageProvider);
    final oldStorage = current.valueOrNull;

    if (migrate && oldStorage != null) {
      final store = await ref.read(sessionStoreProvider.future);
      await store.moveAllTo(resolveStorageFromFolder(folder));
    }

    await settings.setSessionFolder(folder);
    ref.invalidate(sessionStorageProvider);
    ref.invalidate(sessionStoreProvider);
    ref.invalidate(sessionListProvider);
  }

  Future<void> _resetFolder(WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    await settings.clearSessionFolder();
    ref.invalidate(sessionStorageProvider);
    ref.invalidate(sessionStoreProvider);
    ref.invalidate(sessionListProvider);
  }

  Future<void> _onPickFolder(
    WidgetRef ref,
    BuildContext context,
    Settings settings,
  ) async {
    final folder = await _pickFolder();
    if (folder == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final current = ref.read(sessionStorageProvider);
    final existing = current.valueOrNull;
    final count = existing == null
        ? 0
        : (await existing.listFiles()).where(
            (n) => n.startsWith('session_') && n.endsWith('.muse'),
          ).length;
    if (!context.mounted) {
      return;
    }
    final migrate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy existing sessions?'),
        content: Text(
          count > 0
              ? 'Move $count existing session(s) into the new folder? '
                  'Choosing No leaves them in the current folder.'
              : 'Choose this folder for saved sessions?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(count > 0 ? 'Copy' : 'Yes'),
          ),
        ],
      ),
    );
    if (migrate != null) {
      await _applyFolder(ref, folder, migrate: migrate);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final storage = ref.watch(sessionStorageProvider);
    final folder = settings.sessionFolder;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Save feedback to folder'),
                  subtitle: storage.maybeWhen(
                    data: (s) => Text(
                      s.displayName,
                      style: theme.textTheme.bodySmall,
                    ),
                    orElse: () => const Text('Resolving storage…'),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _onPickFolder(ref, context, settings),
                ),
                const Divider(height: 24),
                Text(
                  folder == null
                      ? 'Using the default folder. Tap to choose where session '
                          'history is stored.'
                      : 'Sessions are saved to the folder above. Cache/temp '
                          'files live in a hidden .cache subfolder.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (folder != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _resetFolder(ref),
                    icon: const Icon(Icons.autorenew),
                    label: const Text('Reset to default folder'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}