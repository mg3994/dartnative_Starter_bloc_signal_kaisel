import 'dart:io' show Platform, exit;

import 'package:dartnative/dartnative.dart';

import '../api/auth_service.dart';
import '../repositories/app_repository.dart';
import '../router.dart';
import '../screens/create_profile_screen.dart';
import '../screens/home_screen.dart';
import '../screens/onboarding_screen.dart';
import '../state/auth_state.dart';
import '../utils/constants.dart';
import '../utils/shared_prefs.dart';
import '../packages/kaisel/kaisel.dart';

AppRoute resolveInitialRoute() {
  if (!AppRepository.authState.isAuthenticated) {
    return const OnboardingRoute();
  }

  final onboarded =
      SharedPrefs.instance.getBool(kPrefOnboardingComplete) ?? false;
  if (!onboarded) return const OnboardingRoute();

  final hasProfile = AuthService.currentUser?.username?.isNotEmpty ?? false;
  return hasProfile ? const HomeRoute() : const CreateProfileRoute();
}

class App extends StatefulWidget {
  const App({super.key, required this.initialRoute});

  final AppRoute initialRoute;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final KaiselRouterConfig<AppRoute> _config;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  DateTime? _lastRootBack;
  bool _resolvingLateAuth = false;

  @override
  void initState() {
    super.initState();
    _config = KaiselRouterConfig<AppRoute>(
      initial: widget.initialRoute,
      onBack: _handleBack,
      builder: (context, route) {
        return switch (route) {
          OnboardingRoute() => const OnboardingScreen(),
          CreateProfileRoute(:final prefillName) => CreateProfileScreen(
            prefillName: prefillName,
          ),
          HomeRoute() => HomeScreen(key: _homeKey),
        };
      },
    );
    AppRepository.authState.addListener(_onAuthChanged);
  }

  Future<bool> _handleBack(BuildContext context) async {
    if (_homeKey.currentState?.handleBack() ?? false) {
      _lastRootBack = null;
      return true;
    }
    if (_config.router.canPop) {
      await _config.router.pop();
      _lastRootBack = null;
      return true;
    }

    if (!Platform.isAndroid) return true;
    final now = DateTime.now();
    final previous = _lastRootBack;
    if (previous != null &&
        now.difference(previous) <= const Duration(seconds: 2)) {
      exit(0);
    }
    _lastRootBack = now;
    return true;
  }

  void _onAuthChanged() {
    final auth = AppRepository.authState;
    if (auth.status == AuthStatus.unauthenticated) {
      if (_config.router.current is! OnboardingRoute) {
        _config.router.replaceAll(const OnboardingRoute());
      }
      return;
    }

    if (auth.status == AuthStatus.authenticated &&
        _config.router.current is OnboardingRoute &&
        !_resolvingLateAuth) {
      _resolvingLateAuth = true;
      _resolveLateAuth();
    }
  }

  Future<void> _resolveLateAuth() async {
    try {
      await AuthService.fetchProfile();
      if (!mounted || !AppRepository.authState.isAuthenticated) return;
      if (_config.router.current is OnboardingRoute) {
        final route = resolveInitialRoute();
        if (route is! OnboardingRoute) {
          await _config.router.replaceTop(route);
        }
      }
    } finally {
      _resolvingLateAuth = false;
    }
  }

  @override
  void dispose() {
    AppRepository.authState.removeListener(_onAuthChanged);
    _config.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _config.host();
}
