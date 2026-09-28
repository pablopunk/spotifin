import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../common/brand_logo.dart';
import '../common/design_system.dart';
import '../common/glass.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackdrop()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: _LoginCard(
                  glass: ref.watch(glassEffectsProvider),
                  glassOpacity: ref.watch(glassOpacityProvider),
                  child: Padding(
                    padding: const EdgeInsets.all(SpotifinSpacing.xxl),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: SpotifinLogo(size: 60)),
                          const SizedBox(height: 16),
                          Text(
                            'Your music. Your rules.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Connect directly to your Jellyfin server.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: SpotifinColors.textMuted),
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _server,
                            decoration: const InputDecoration(
                              labelText: 'Jellyfin server',
                              hintText: 'https://music.example.com',
                              prefixIcon: Icon(Icons.dns_outlined),
                            ),
                            keyboardType: TextInputType.url,
                            autofillHints: const [AutofillHints.url],
                            validator: _required,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _username,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            autofillHints: const [AutofillHints.username],
                            validator: _required,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: _hidePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _hidePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                            autofillHints: const [AutofillHints.password],
                            validator: _required,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (state.error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              state.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          if (state.cacheOwnerConflict) ...[
                            const SizedBox(height: 14),
                            _CacheConflictCard(
                              message: state.cacheOwnerMessage ?? 'This device has a saved library from another account.',
                              onClear: () => _confirmClearSavedLibrary(context),
                            ),
                          ],
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: state.syncing ? null : _submit,
                            icon: state.syncing
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward_rounded),
                            label: Text(
                              state.syncing ? 'CONNECTING…' : 'CONNECT',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(appControllerProvider.notifier)
        .signIn(_server.text, _username.text, _password.text);
  }

  Future<void> _confirmClearSavedLibrary(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _ClearSavedLibraryDialog(),
    );
    // Cancellation makes no changes.
    if (confirmed != true || !context.mounted) return;
    await ref.read(appControllerProvider.notifier).clearSavedLibrary();
  }
}

class _CacheConflictCard extends StatelessWidget {
  const _CacheConflictCard({required this.message, required this.onClear});

  final String message;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear saved library'),
          ),
        ],
      ),
    ),
  );
}

class _ClearSavedLibraryDialog extends ConsumerWidget {
  const _ClearSavedLibraryDialog();

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) => AlertDialog(
    title: const Text('Clear saved library?'),
    content: FutureBuilder<String>(
      future: _describeSavedLibrary(widgetRef),
      builder: (context, snapshot) => Text(
        snapshot.data ?? 'This removes the saved library and pending edits from this device.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Clear'),
      ),
    ],
  );

  Future<String> _describeSavedLibrary(WidgetRef widgetRef) async {
    try {
      final database = widgetRef.read(databaseProvider);
      final tracks = await database.allTracks();
      final pending = await database.pendingOperations();
      final songWord = tracks.length == 1 ? 'song' : 'songs';
      final editWord = pending.length == 1 ? 'edit' : 'edits';
      return 'This removes ${tracks.length} saved $songWord and '
          '${pending.length} pending $editWord from this device. '
          'This cannot be undone.';
    } catch (_) {
      return 'This removes the saved library and pending edits from '
          'this device. This cannot be undone.';
    }
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF292929), SpotifinColors.background],
      ),
    ),
  );
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.glass,
    required this.glassOpacity,
    required this.child,
  });

  final bool glass;
  final double glassOpacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (glass) {
      return GlassCard(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        settings: SpotifinGlass.settings(glassOpacity),
        padding: EdgeInsets.zero,
        shape: const LiquidRoundedSuperellipse(
          borderRadius: SpotifinRadii.panel,
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: SpotifinColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(SpotifinRadii.panel)),
        boxShadow: [SpotifinShadows.dialog],
      ),
      child: child,
    );
  }
}
