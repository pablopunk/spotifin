class AppFeatures {
  const AppFeatures._();

  static const downtify = bool.fromEnvironment(
    'SPOTIFIN_DOWNTIFY',
    defaultValue: true,
  );
}
