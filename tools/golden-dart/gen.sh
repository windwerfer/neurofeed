#!/usr/bin/env bash
# Regenerate crates/nf-feedback/tests/golden/*.json from the legacy Dart engine.
# Vendors the pure Dart files verbatim except for import rewrites and
# DateTime.now() -> shimNow() (an injected clock). See README.md.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../..
V=.vendor; rm -rf $V; mkdir -p $V
for f in target_state feedback_engine baseline_window feedback_phase; do
  sed -e "s#import 'package:flutter/foundation.dart';#import 'shim.dart';#" \
      -e "s#import 'package:neurofeed/src/rust/api/muse.dart';#import 'shim.dart';#" \
      -e "s#import 'package:neurofeed/src/feedback/\([a-z_]*\).dart';#import '\1.dart';#" \
      -e "s#DateTime.now()#shimNow()#g" \
      $ROOT/lib/src/feedback/$f.dart > $V/$f.dart
done
# stabilityOutputPercentile is pure but lives in reward_lane.dart: copy it verbatim.
{ awk '/^double stabilityOutputPercentile/,/^}/' $ROOT/lib/src/feedback/reward_lane.dart; } > $V/stability_pct.dart
cat > $V/shim.dart <<'D'
// Flutter/FRB stand-ins for the headless harness.
DateTime shimClock = DateTime.fromMillisecondsSinceEpoch(0);
DateTime shimNow() => shimClock;
void debugPrint(String? s) {}
const immutable = Object();
class BandsDto {
  BandsDto({required this.electrode, required this.timestamp, required this.delta,
    required this.theta, required this.alpha, required this.beta, required this.gamma});
  final int electrode; final double timestamp, delta, theta, alpha, beta, gamma;
}
D
~/dart-sdk/bin/dart run bin/golden.dart "$ROOT/crates/nf-feedback/tests/golden"
