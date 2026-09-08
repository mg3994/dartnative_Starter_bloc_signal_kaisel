import 'package:dartnative/dartnative.dart';

import '../packages/kaisel_core/framework.dart';
import '../packages/kaisel_core/kaisel_core.dart';

/// Builds a screen for a typed Kaisel route.
typedef KaiselPageBuilder<R extends KaiselRoute> =
    Widget Function(BuildContext context, R route);

typedef KaiselBackHandler = Future<bool> Function(BuildContext context);

/// A DartNative router host backed by [KaiselRouter].
///
/// DartNative exposes an imperative Navigator rather than Flutter's
/// declarative `Navigator.pages` API. This host therefore keeps the router as
/// the source of truth and renders its current top route in a permanent root
/// widget. Back actions always pass through the router guard pipeline.
class KaiselRouterDelegate<R extends KaiselRoute> extends StatefulWidget {
  const KaiselRouterDelegate({
    super.key,
    required this.router,
    required this.builder,
    this.onBack,
  });

  final KaiselRouter<R> router;
  final KaiselPageBuilder<R> builder;
  final KaiselBackHandler? onBack;

  @override
  State<KaiselRouterDelegate<R>> createState() =>
      _KaiselRouterDelegateState<R>();
}

class _KaiselRouterDelegateState<R extends KaiselRoute>
    extends State<KaiselRouterDelegate<R>> {
  @override
  void initState() {
    super.initState();
    widget.router.addListener(_onRouterChanged);
  }

  @override
  void didUpdateWidget(KaiselRouterDelegate<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.router, widget.router)) {
      oldWidget.router.removeListener(_onRouterChanged);
      widget.router.addListener(_onRouterChanged);
    }
  }

  void _onRouterChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.router.removeListener(_onRouterChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.router.entries;
    final entry = entries.last;
    final page = widget.builder(context, entry.route);
    return RouterScope<R>(
      router: widget.router,
      child: KaiselPageScope(
        route: entry.route,
        position: entries.length - 1,
        stackLength: entries.length,
        previous: entries.length > 1 ? entries[entries.length - 2].route : null,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final handled = await widget.onBack?.call(context) ?? false;
            if (!handled && widget.router.canPop) {
              await widget.router.pop();
            }
          },
          child: page,
        ),
      ),
    );
  }
}

/// Immutable construction helper for a native Kaisel router host.
class KaiselRouterConfig<R extends KaiselRoute> {
  KaiselRouterConfig({
    required R initial,
    required this.builder,
    this.onBack,
    List<KaiselGuard<R>> guards = const [],
    KaiselTransitionCallback<R>? onTransition,
  }) : router = KaiselRouter<R>(
         initial: initial,
         guards: guards,
         onTransition: onTransition,
       );

  final KaiselRouter<R> router;
  final KaiselPageBuilder<R> builder;
  final KaiselBackHandler? onBack;

  /// The widget to pass to [runApp] or another DartNative widget tree.
  Widget host({Key? key}) => KaiselRouterDelegate<R>(
    key: key,
    router: router,
    builder: builder,
    onBack: onBack,
  );

  void dispose() => router.dispose();
}

/// Exposes a typed router to descendants.
class RouterScope<R extends KaiselRoute> extends InheritedWidget {
  const RouterScope({super.key, required this.router, required super.child});

  final KaiselRouter<R> router;

  static RouterScope<R>? maybeOf<R extends KaiselRoute>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RouterScope<R>>();

  static RouterScope<R> of<R extends KaiselRoute>(BuildContext context) {
    final scope = maybeOf<R>(context);
    if (scope == null) {
      throw StateError('RouterScope<$R> was not found above this context.');
    }
    return scope;
  }

  @override
  bool updateShouldNotify(RouterScope<R> oldWidget) =>
      !identical(oldWidget.router, router);
}

/// Typed navigation helpers for DartNative widget contexts.
extension KaiselRouterContextX on BuildContext {
  KaiselRouter<R> router<R extends KaiselRoute>() =>
      RouterScope.of<R>(this).router;

  Future<void> push<R extends KaiselRoute>(R route) => router<R>().push(route);

  Future<T?> pushForResult<R extends KaiselRoute, T>(R route) =>
      router<R>().pushForResult<T>(route);

  Future<void> replaceTop<R extends KaiselRoute>(R route) =>
      router<R>().replaceTop(route);

  Future<bool> pop<R extends KaiselRoute>([Object? result]) =>
      router<R>().pop(result);
}

/// Route metadata exposed to a page and its descendants.
class KaiselPageScope extends InheritedWidget {
  const KaiselPageScope({
    super.key,
    required this.route,
    required this.position,
    required this.stackLength,
    this.previous,
    required super.child,
  });

  final KaiselRoute route;
  final int position;
  final int stackLength;
  final KaiselRoute? previous;

  bool get isTop => position == stackLength - 1;
  bool get isBottom => position == 0;

  static KaiselPageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KaiselPageScope>();

  static KaiselPageScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw StateError('KaiselPageScope was not found above this context.');
    }
    return scope;
  }

  @override
  bool updateShouldNotify(KaiselPageScope oldWidget) =>
      route != oldWidget.route ||
      position != oldWidget.position ||
      stackLength != oldWidget.stackLength ||
      previous != oldWidget.previous;
}

/// A DartNative builder that rebuilds when [router] changes.
class KaiselListenableBuilder<R extends KaiselRoute> extends StatefulWidget {
  const KaiselListenableBuilder({
    super.key,
    required this.router,
    required this.builder,
    this.child,
  });

  final KaiselRouter<R> router;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  State<KaiselListenableBuilder<R>> createState() =>
      _KaiselListenableBuilderState<R>();
}

class _KaiselListenableBuilderState<R extends KaiselRoute>
    extends State<KaiselListenableBuilder<R>> {
  @override
  void initState() {
    super.initState();
    widget.router.addListener(_onChange);
  }

  @override
  void didUpdateWidget(KaiselListenableBuilder<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.router, widget.router)) {
      oldWidget.router.removeListener(_onChange);
      widget.router.addListener(_onChange);
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.router.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.child);
}
