class DevelopmentLogin {
  const DevelopmentLogin({
    required this.enabled,
    required this.server,
    required this.username,
    required this.password,
  });

  const DevelopmentLogin.fromEnvironment()
    : enabled = const bool.fromEnvironment('SPOTIFIN_AUTO_LOGIN'),
      server = const String.fromEnvironment('SPOTIFIN_SERVER'),
      username = const String.fromEnvironment('SPOTIFIN_USERNAME'),
      password = const String.fromEnvironment('SPOTIFIN_PASSWORD');

  final bool enabled;
  final String server;
  final String username;
  final String password;

  bool get canSignIn =>
      enabled &&
      server.isNotEmpty &&
      username.isNotEmpty &&
      password.isNotEmpty;
}
