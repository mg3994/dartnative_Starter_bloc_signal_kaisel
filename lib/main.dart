import 'dart:async';

import 'package:dartnative/dartnative.dart' hide App;
import 'package:dartnative_skia/dartnative_skia.dart';
import 'package:dartnative_keys/dartnative_keys.dart';
import 'package:dartnative_supabase/dartnative_supabase.dart' hide AuthState;

import 'api/auth_service.dart';
import 'config.dart';
import 'dartnative_plugin_registrant.dart';
import 'navigation/app_router.dart';
import 'repositories/app_repository.dart';
import 'screens/create_profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'utils/constants.dart';
import 'utils/shared_prefs.dart';

/// Debug: when true, every launch shows the onboarding as if the app were
/// freshly installed (the persisted session, profile and onboarding flag
/// are cleared at boot). Handy while designing the slides. Ship it false.
const bool kDebugAlwaysShowOnboarding = false;

Future<void> main() async {
  await DartNativeLogger.run(
    () async {
      // MUST be first. registerAll() registers the platform bindings and
      // loads every plugin's FFI symbols. Missing this shows as a white
      // screen with no error.
      DartNativePluginRegistrant.registerAll();
      registerSkiaFactories();
      // Registers pubspec declared fonts with the OS. No-op on Android.
      DartNativeFontRegistrant.registerAll();
      dnLog('main: [boot] plugins and fonts registered');

      // Every pushable screen, registered by name. Two reasons:
      // 1. Navigator.pushNamed(context, '/notes') works anywhere.
      // 2. Hot restart replay: the native side remembers which route
      //    names are on the stack and replays them from this map. A route
      //    pushed WITHOUT a registered name is dropped on hot restart.
      registerRoutes({
        '/onboarding': (_) => const OnboardingScreen(),
        '/create_profile': (_) => const CreateProfileScreen(),
        '/home': (_) => const HomeScreen(),
        // Drawer SECTIONS (Notes, Favorites, ...) are not routes: they
        // render in place inside the home screen, and the Website item is
        // a link, not a screen. Register pushed secondary screens here,
        // the way StubScreen shows.
      });

      // Bundled key value config (.dnkeys in the project root). With no
      // keys present the app still runs, in demo mode.
      await DnKeys.load();
      await SharedPrefs.instance.initialize();
      // Construct the theme now, not lazily: its constructor restores the
      // persisted choice and pins the native appearance (alerts, keyboard).
      // Left to the first themed screen, a cold start into the onboarding
      // showed system-appearance alerts until Home had built once.
      AppRepository.themeState;
      // Warm the database during the splash, without blocking boot: the
      // first open pays for directory creation, SQLite open, migrations
      // and the first query. Left to the first Notes visit, that cost
      // shows as a visibly late list.
      unawaited(AppRepository.notesState.loadIfNeeded());
      if (kDebugAlwaysShowOnboarding) {
        await SharedPrefs.instance.remove(kPrefOnboardingComplete);
        await SharedPrefs.instance.remove(kPrefDemoSession);
        await SharedPrefs.instance.remove(kPrefCachedProfile);
      }
      dnLog('main: [boot] keys and prefs ready');

      // Auth, resolved BEFORE runApp so the first frame is already the
      // right screen. Supabase restores its session asynchronously after
      // initialize(), so we wait for the auth state to resolve, with a
      // bound so a slow or offline start cannot hang the splash.
      if (AuthService.restoreDemoSession()) {
        dnLog('main: [boot] demo session restored');
      } else if (AppConfig.isAuthConfigured) {
        try {
          await Supabase.initialize(
            url: AppConfig.supabaseUrl,
            anonKey: AppConfig.supabaseAnonKey,
          );
          AuthService.initialize();
          await AppRepository.authState.waitUntilResolved(
            const Duration(seconds: 3),
          );
          // A restored session needs the profile too; do not block the
          // first frame on it, the state notifies when it lands.
          if (AuthService.isAuthenticated) {
            unawaited(AuthService.fetchProfile());
          }
        } catch (e) {
          dnLog('main: auth init error: $e, continuing to runApp');
        }
      } else {
        dnLog('main: [boot] no Supabase keys, demo mode only');
      }

      dnLog('main: [boot] runApp');
      runApp(App(initialRoute: resolveInitialRoute()));
    },
    verbose: false,
    saveToFile: true,
  );
}
