import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the REVE AI engine (model downloaded + native library ready) is
/// available for the drowsiness protocol.
///
/// Placeholder for commit that lands the model store/download; until then the
/// engine is never available, which gates the Pure Jhana start button behind
/// an explanatory dialog.
final reveEngineAvailabilityProvider = Provider<bool>((ref) => false);
