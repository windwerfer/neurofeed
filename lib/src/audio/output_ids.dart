/// Frozen reward-output ids (PR 5). JSON / prefs store [name].
enum RewardOutputId {
  chime,
  musicFilter,
  rainStage,
  binauralSwell,
  none;

  String get label => switch (this) {
    RewardOutputId.chime => 'Bowl chimes',
    RewardOutputId.rainStage => 'Rain',
    RewardOutputId.musicFilter => 'Music',
    RewardOutputId.binauralSwell => 'Binaural Beats',
    RewardOutputId.none => 'None',
  };

  String get subtitle => switch (this) {
    RewardOutputId.chime => 'Warm chimes when you reach the target',
    RewardOutputId.rainStage => 'Rain that quiets as you get closer',
    RewardOutputId.musicFilter => 'Your folder through a reward-driven filter',
    RewardOutputId.binauralSwell =>
      'Synth alpha-flow beats that swell as you reach the '
          'target (headphones required)',
    RewardOutputId.none => 'Silent feedback — no reward sound',
  };

  /// Rain and music occupy the soundscape and suppress background.
  bool get suppressesBackground =>
      this == RewardOutputId.rainStage || this == RewardOutputId.musicFilter;

  /// Modulated outputs that [setMuffle] can duck. Chime is never muffled.
  bool get mufflable =>
      this == RewardOutputId.musicFilter ||
      this == RewardOutputId.rainStage ||
      this == RewardOutputId.binauralSwell;
}

/// Unmapped background layer. Orchestrator starts/stops this from
/// [Settings.soundName] (user override) / catalog `background.kind`.
enum BackgroundKind {
  drone,
  droneLoop,
  rain,
  userMusic,
  binaural,
  none,
}

/// Today's background picker labels (user override). Catalog uses [BackgroundKind].
const String backgroundSoundDrone = 'Ambient Drone';
const String backgroundSoundDroneLoop = 'Drone Loop';
const String backgroundSoundRain = 'Rain';
const String backgroundSoundNone = 'No background';
const String musicSoundName = 'Music from folder';
const String binauralSoundName = 'Binaural Beats';

BackgroundKind backgroundKindFromSoundName(String? name) => switch (name) {
  backgroundSoundDroneLoop => BackgroundKind.droneLoop,
  backgroundSoundRain => BackgroundKind.rain,
  musicSoundName => BackgroundKind.userMusic,
  binauralSoundName => BackgroundKind.binaural,
  backgroundSoundNone => BackgroundKind.none,
  _ => BackgroundKind.drone,
};

String soundNameFromBackgroundKind(BackgroundKind kind) => switch (kind) {
  BackgroundKind.drone => backgroundSoundDrone,
  BackgroundKind.droneLoop => backgroundSoundDroneLoop,
  BackgroundKind.rain => backgroundSoundRain,
  BackgroundKind.userMusic => musicSoundName,
  BackgroundKind.binaural => binauralSoundName,
  BackgroundKind.none => backgroundSoundNone,
};

/// Maps a stored pref / metadata string to a [RewardOutputId].
/// Accepts old FeedbackMode names (`bowlChimes`, `rain`, `music`, `binaural`)
/// and the new ids. Unknown → [RewardOutputId.chime].
RewardOutputId rewardOutputIdFromStored(String? name) {
  switch (name) {
    case 'bowlChimes':
    case 'chime':
      return RewardOutputId.chime;
    case 'rain':
    case 'rainStage':
      return RewardOutputId.rainStage;
    case 'music':
    case 'musicFilter':
      return RewardOutputId.musicFilter;
    case 'binaural':
    case 'binauralSwell':
      return RewardOutputId.binauralSwell;
    case 'none':
      return RewardOutputId.none;
    default:
      return RewardOutputId.chime;
  }
}

/// Eager-migrate helper: old `feedback_mode` names → new ids. Unchanged if
/// already a new id or unset.
String? migrateRewardOutputPref(String? stored) {
  if (stored == null || stored.isEmpty) {
    return stored;
  }
  final id = rewardOutputIdFromStored(stored);
  return id.name;
}

/// User pref wins; catalog default when unset. No-reward protocols → [none].
RewardOutputId resolveRewardOutputId({
  required bool hasReward,
  String? storedPref,
  String? catalogOutput,
}) {
  if (!hasReward) {
    return RewardOutputId.none;
  }
  if (storedPref != null && storedPref.isNotEmpty) {
    return rewardOutputIdFromStored(storedPref);
  }
  if (catalogOutput != null && catalogOutput.isNotEmpty) {
    return rewardOutputIdFromStored(catalogOutput);
  }
  return RewardOutputId.chime;
}

/// User pref wins; catalog default when unset. Guard ids stay [GuardrailSound] names.
String resolveGuardOutputId({
  String? storedPref,
  String? catalogOutput,
}) {
  if (storedPref != null && storedPref.isNotEmpty) {
    return storedPref;
  }
  if (catalogOutput != null && catalogOutput.isNotEmpty) {
    return catalogOutput;
  }
  return 'softBowl';
}

/// Display label for a session `feedbackSound` string (old or new id).
String feedbackSoundLabel(String? stored) =>
    rewardOutputIdFromStored(stored).label;
