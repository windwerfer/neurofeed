import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/feedback/session_store_core.dart';

export 'session_store_core.dart' show SessionStore;
export 'session_metadata.dart';
export 'session_v5_models.dart';

/// Storage-backed store that derives its [SessionStorage] from the active
/// [Settings]. Reading [sessionStorageProvider] here keeps history and the
/// recorder on the same folder.
final sessionStoreProvider = FutureProvider<SessionStore>((ref) async {
  final settings = ref.watch(settingsProvider);
  return SessionStore(storage: resolveSessionStorage(settings));
});

/// Background-loads the session list through the metadata cache.
class SessionListNotifier extends AsyncNotifier<List<SessionSummary>> {
  bool _disposed = false;

  @override
  Future<List<SessionSummary>> build() async {
    ref.onDispose(() => _disposed = true);
    final store = await ref.watch(sessionStoreProvider.future);
    final summaries = await store.list();
    // Lazy loading: the first emission is the already-cached subset (fast).
    // New or changed files are backfilled in the background; once done the
    /// list is re-read so the newly discovered sessions appear.
    if (store.pendingBackfillCount > 0) {
      unawaited(_backfill(store));
    }
    return summaries;
  }

  Future<void> _backfill(SessionStore store) async {
    await store.backfillPending();
    if (!_disposed) {
      ref.invalidateSelf();
    }
  }
}

final sessionListProvider =
    AsyncNotifierProvider<SessionListNotifier, List<SessionSummary>>(
      SessionListNotifier.new,
    );
