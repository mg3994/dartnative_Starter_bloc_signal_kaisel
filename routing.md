Absolutely. Here’s a small DartNative + Kaisel example showing typed routes, a router host, push/pop, a result, and a native-style transition.

DartNative Kaisel Navigation Example

import 'package:dartnative/dartnative.dart'; import 'kaisel_router.dart'; void main() { final config = KaiselRouterConfig<AppRoute>( initial: const HomeRoute(), builder: (context, route) { return switch (route) { HomeRoute() => const HomeScreen(), DetailsRoute(:final id) => DetailsScreen(id: id), SettingsRoute() => const SettingsScreen(), }; }, ); runApp( App( title: 'Kaisel + DartNative', home: config.host(), ), ); } // --------------------------------------------------------------------------- // Routes // --------------------------------------------------------------------------- sealed class AppRoute extends KaiselRoute { const AppRoute(); } final class HomeRoute extends AppRoute { const HomeRoute(); } final class DetailsRoute extends AppRoute { const DetailsRoute(this.id); final String id; } final class SettingsRoute extends AppRoute { const SettingsRoute(); } // --------------------------------------------------------------------------- // Home // --------------------------------------------------------------------------- class HomeScreen extends StatelessWidget { const HomeScreen({super.key}); @override Widget build(BuildContext context) { final router = context.router<AppRoute>(); return Container( padding: const EdgeInsets.all(24), color: Colors.white, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ const Text( 'Home', style: TextStyle( fontSize: 30, fontWeight: FontWeight.bold, ), ), const SizedBox(height: 24), Button( onPressed: () async { await router.push( const DetailsRoute('product-123'), ); }, child: const Text('Open Details'), ), const SizedBox(height: 12), Button( onPressed: () async { await context.push<AppRoute>( const SettingsRoute(), ); }, child: const Text('Settings'), ), ], ), ); } } // --------------------------------------------------------------------------- // Details // --------------------------------------------------------------------------- class DetailsScreen extends StatelessWidget { const DetailsScreen({ super.key, required this.id, }); final String id; @override Widget build(BuildContext context) { return Container( padding: const EdgeInsets.all(24), color: Colors.white, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Text( 'Details', style: const TextStyle( fontSize: 30, fontWeight: FontWeight.bold, ), ), const SizedBox(height: 12), Text('Product: $id'), const SizedBox(height: 24), Button( onPressed: () { context.pop<AppRoute>(); }, child: const Text('Back'), ), ], ), ); } } // --------------------------------------------------------------------------- // Settings // --------------------------------------------------------------------------- class SettingsScreen extends StatelessWidget { const SettingsScreen({super.key}); @override Widget build(BuildContext context) { return Container( padding: const EdgeInsets.all(24), color: Colors.white, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ const Text( 'Settings', style: TextStyle( fontSize: 30, fontWeight: FontWeight.bold, ), ), const SizedBox(height: 24), Button( onPressed: () { context.pop<AppRoute>(); }, child: const Text('Done'), ), ], ), ); } } 

What happens at runtime

The important part is:

final config = KaiselRouterConfig<AppRoute>( initial: const HomeRoute(), builder: (context, route) { return switch (route) { HomeRoute() => const HomeScreen(), DetailsRoute(:final id) => DetailsScreen(id: id), SettingsRoute() => const SettingsScreen(), }; }, ); 

Kaisel owns the navigation state:

HomeRoute │ │ context.push(DetailsRoute) ▼ HomeRoute → DetailsRoute │ │ router notification ▼ KaiselRouterDelegate rebuilds │ ▼ DetailsScreen 

And Android back can flow through the DartNative startup hooks:

Android system back ↓ DNActivityHooks ↓ DartNative back handling ↓ PopScope ↓ KaiselRouter.pop() ↓ previous KaiselRoute 

Adding a native transition

If your KaiselRouter transition callback is intended to control the native transition, configure it when creating the router:

final config = KaiselRouterConfig<AppRoute>( initial: const HomeRoute(), onTransition: (from, to) { // Map this to your DartNative/native reconciliation // transition implementation. }, builder: (context, route) { return switch (route) { HomeRoute() => const HomeScreen(), DetailsRoute(:final id) => DetailsScreen(id: id), SettingsRoute() => const SettingsScreen(), }; }, ); 

For a more direct DartNative PageRoute implementation, you could instead make KaiselRouter delegate physical screen transitions to DartNative's Navigator, while retaining KaiselRouter as the typed/guarded source of truth.

One caveat: I used Button and the other widget names according to the DartNative-style API you've provided; if your actual framework.dart exposes a different button widget, that one line should be changed.