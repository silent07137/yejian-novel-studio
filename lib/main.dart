import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/sqlite_store.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';
import 'ui/profile_setup_page.dart';
import 'ui/workspace_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YejianBootstrap());
}

class YejianBootstrap extends StatefulWidget {
  const YejianBootstrap({super.key});

  @override
  State<YejianBootstrap> createState() => _YejianBootstrapState();
}

class _YejianBootstrapState extends State<YejianBootstrap> {
  late Future<AppController> _startup = _initialize();

  Future<AppController> _initialize() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      final store = SqliteStore();
      final data = await store.load();
      final controller = AppController(store: store, data: data);
      await controller.loadConfiguredFont();
      return controller;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: '页间启动',
        ),
      );
      rethrow;
    }
  }

  void _retry() {
    setState(() => _startup = _initialize());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppController>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return YejianApp(controller: snapshot.requireData);
        }

        return MaterialApp(
          title: '页间',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF735A92),
            ),
            useMaterial3: true,
          ),
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: snapshot.hasError
                      ? _StartupError(error: snapshot.error!, onRetry: _retry)
                      : const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 20),
                            Text('正在打开页间……'),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text('启动失败', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('本地数据未能正常读取，可重试一次。'),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class YejianApp extends StatefulWidget {
  const YejianApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<YejianApp> createState() => _YejianAppState();
}

class _YejianAppState extends State<YejianApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.controller.flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final settings = widget.controller.data.settings;
        final themeMode = switch (settings.appearanceMode) {
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => ThemeMode.light,
        };
        return MaterialApp(
          title: '页间',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: buildTheme(
            settings.palette,
            brightness: Brightness.light,
            customFontFamily: widget.controller.loadedFontFamily,
          ),
          darkTheme: buildTheme(
            settings.palette,
            brightness: Brightness.dark,
            customFontFamily: widget.controller.loadedFontFamily,
          ),
          home: widget.controller.data.profile.setupComplete
              ? WorkspaceShell(controller: widget.controller)
              : OnboardingPage(controller: widget.controller),
        );
      },
    );
  }
}
