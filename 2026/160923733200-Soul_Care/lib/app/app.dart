import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/settings_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/design_system.dart';
import '../core/home_widget/widget_data.dart';
import '../core/widgets/app_widgets.dart';
import '../core/widgets/pin_gate.dart';

class SoulCareApp extends StatefulWidget {
  /// Whether onboarding completed. Defaults to true so widget tests
  /// (and any host without settings) always land on /home.
  final bool onboarded;
  const SoulCareApp({super.key, this.onboarded = true});

  @override
  State<SoulCareApp> createState() => _SoulCareAppState();
}

class _SoulCareAppState extends State<SoulCareApp> with WidgetsBindingObserver {
  // Fresh router per app instance (also makes widget tests independent).
  late final _router = createAppRouter(onboarded: widget.onboarded);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetLink.attach(_router);
  }

  @override
  void dispose() {
    WidgetLink.detach(_router);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = context.read<SettingsProvider>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      settings.recordBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      settings.recordForegrounded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.loaded) {
      return MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SoulCareMark(size: 72, radius: 20),
                const SizedBox(height: DS.l),
                Text(
                  'SoulCare',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: DS.textPrimary(Brightness.light),
                  ),
                ),
                const SizedBox(height: DS.massive),
                const SizedBox(
                  width: 20,
                  height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppTheme.brandSeed,
                ),
                ),
                const SizedBox(height: DS.m),
                Text(
                  'Opening SoulCare…',
                  style: TextStyle(
                    fontSize: 13,
                    color: DS.textSecondary(Brightness.light),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return MaterialApp.router(
      title: 'SoulCare',
      theme: AppTheme.themed(
        dark: false,
        seed: Color(settings.settings.colorSeed),
        fontFamily: settings.settings.fontFamily,
      ),
      darkTheme: AppTheme.themed(
        dark: true,
        seed: Color(settings.settings.colorSeed),
        fontFamily: settings.settings.fontFamily,
      ),
      themeMode: settings.themeMode,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Display scale: UI zoom × font-size preference (defaults 1.0 × 1.0).
        final scale = (settings.settings.uiZoom * settings.settings.fontScale)
            .clamp(0.4, 3.0);
        final mq = MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale));
        return MediaQuery(
          data: mq,
          child: PinGate(
            fullApp: true,
            title: 'SoulCare is locked',
            subtitle:
                'Unlock with biometrics or your PIN to continue. Everything stays on this device.',
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
