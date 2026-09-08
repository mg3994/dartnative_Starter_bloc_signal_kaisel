import 'packages/kaisel/kaisel.dart';

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class OnboardingRoute extends AppRoute {
  const OnboardingRoute();

  @override
  String get routeName => '/onboarding';
}

final class CreateProfileRoute extends AppRoute {
  const CreateProfileRoute({this.prefillName});

  final String? prefillName;

  @override
  List<Object?> get props => [prefillName];

  @override
  String get routeName => '/create_profile';
}

final class HomeRoute extends AppRoute {
  const HomeRoute();

  @override
  String get routeName => '/home';
}
