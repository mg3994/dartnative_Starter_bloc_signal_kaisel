import 'dart:async';

import 'package:dartnative/dartnative.dart'
    show
        StatefulWidget,
        BuildContext,
        SizedBox,
        Widget,
        State,
        InheritedWidget,
        StatelessWidget;

import '../packages/bloc_signals/bloc_signals.dart';
import '../packages/bloc_signals/signals_core/signals_core.dart'
    show SignalWatch;
// import 'package:flutter/widgets.dart';
// import 'package:signals_flutter/signals_flutter.dart';

/// A Flutter widget that provides a [BlocSignal] to its descendants via
/// the element tree and automatically disposes of it when the provider
/// is removed from the tree.
///
/// Example:
/// ```dart
/// BlocSignalProvider(
///   create: (context) => CounterBloc(),
///   child: CounterScreen(),
/// )
/// ```
class BlocSignalProvider<T extends BlocSignalBase<dynamic>>
    extends StatefulWidget {
  /// Creates a [BlocSignalProvider] that manages the lifecycle of a new
  /// [BlocSignal] returned by [create].
  const BlocSignalProvider({
    required T Function(BuildContext context) this.create,
    this.child = const SizedBox.shrink(),
    this.lazy = true,
    super.key,
  }) : value = null;

  /// Creates a [BlocSignalProvider] that provides an existing [value] to
  /// the tree, without managing its lifecycle (does not close it on dispose).
  const BlocSignalProvider.value({
    required T this.value,
    this.child = const SizedBox.shrink(),
    super.key,
  })  : create = null,
        lazy = false;

  /// The factory function to create a new [BlocSignal] instance.
  final T Function(BuildContext context)? create;

  /// An existing [BlocSignal] instance to provide to the widget tree.
  final T? value;

  /// Whether the [BlocSignal] should be created lazily.
  ///
  /// Defaults to `true`.
  final bool lazy;

  /// The widget subtree that will have access to the provided [BlocSignal].
  final Widget child;

  /// Looks up the closest [BlocSignal] of type [T] in the widget tree.
  static T of<T extends BlocSignalBase<dynamic>>(
    BuildContext context, {
    bool listen = false,
  }) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<_BlocSignalProviderInherited<T>>();
    if (provider == null) {
      throw StateError(
        'BlocSignalProvider.of() called without a provider of type $T.',
      );
    }
    return provider.bloc!;
  }

  /// Clones this provider with a new child widget.
  BlocSignalProvider<T> copyWith(Widget child) {
    if (create != null) {
      return BlocSignalProvider<T>(
        create: create!,
        lazy: lazy,
        key: key,
        child: child,
      );
    } else {
      return BlocSignalProvider<T>.value(
        value: value!,
        key: key,
        child: child,
      );
    }
  }

  @override
  State<BlocSignalProvider<T>> createState() => _BlocSignalProviderState<T>();
}

class _BlocSignalProviderState<T extends BlocSignalBase<dynamic>>
    extends State<BlocSignalProvider<T>> {
  T? _bloc;
  bool _isInitialized = false;

  T get bloc {
    if (widget.value != null) return widget.value!;
    if (!_isInitialized) {
      _bloc = widget.create!(context);
      _isInitialized = true;
    }
    return _bloc!;
  }

  T? get blocInstance => widget.value ?? _bloc;

  @override
  void initState() {
    super.initState();
    if (!widget.lazy && widget.create != null) {
      _bloc = widget.create!(context);
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    if (_bloc != null) {
      unawaited(_bloc!.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BlocSignalProviderInherited<T>(
      bloc: widget.value ?? _bloc,
      state: this,
      child: widget.child,
    );
  }
}

class _BlocSignalProviderInherited<T extends BlocSignalBase<dynamic>>
    extends InheritedWidget {
  const _BlocSignalProviderInherited({
    required this.bloc,
    required this.state,
    required super.child,
  });

  final T? bloc;
  final _BlocSignalProviderState<T> state;

  @override
  bool updateShouldNotify(_BlocSignalProviderInherited<T> oldWidget) {
    return bloc != oldWidget.bloc;
  }
}

/// Helper extension on [BuildContext] to access [BlocSignal] instances.
extension BlocSignalProviderExtension on BuildContext {
  /// Reads a [BlocSignal] without listening for changes (ideal for calling
  /// methods or dispatching events).
  ///
  /// Example:
  /// ```dart
  /// context.read<CounterBloc>().add(Increment());
  /// ```
  T read<T extends BlocSignalBase<dynamic>>() => BlocSignalProvider.of<T>(this);

  /// Watches a [BlocSignalBase] and registers a rebuild dependency on the
  /// provider.
  ///
  /// Example:
  /// ```dart
  /// final bloc = context.watch<CounterBloc>();
  /// ```
  T watch<T extends BlocSignalBase<dynamic>>() =>
      BlocSignalProvider.of<T>(this, listen: true);

  /// Listens to changes on a selected value of the [BlocSignal] state.
  ///
  /// Note on Generic Type Parameters:
  /// Unlike Riverpod's 3-parameter `context.select` or `package:flutter_bloc`,
  /// `BlocSignal`'s `context.select` takes **2** generic type parameters:
  /// 1. `T`: The [BlocSignalBase] container type
  ///    (for example `CounterBloc` or `UserCubit`).
  /// 2. `R`: The selected return value type (for example `int` or `String`).
  ///
  /// The selector callback receives the **`bloc` instance** directly:
  /// `(bloc) => bloc.stateValue.property`.
  ///
  /// Example:
  /// ```dart
  /// final username = context.select<UserBloc, String>(
  ///   (bloc) => bloc.stateValue.username,
  /// );
  /// ```
  R select<T extends BlocSignalBase<dynamic>, R>(
    R Function(T bloc) selector,
  ) {
    final bloc = BlocSignalProvider.of<T>(this, listen: true);
    bloc.state.watch(this);
    return selector(bloc);
  }
}

/// A widget that merges multiple [BlocSignalProvider]s into a single linear
/// widget hierarchy to improve readability.
///
/// Example:
/// ```dart
/// MultiBlocSignalProvider(
///   providers: [
///     BlocSignalProvider<AuthBloc>(create: (context) => AuthBloc()),
///     BlocSignalProvider<ThemeBloc>(create: (context) => ThemeBloc()),
///   ],
///   child: HomeScreen(),
/// )
/// ```
class MultiBlocSignalProvider extends StatelessWidget {
  /// Creates a [MultiBlocSignalProvider] that provides multiple [providers].
  const MultiBlocSignalProvider({
    required this.child,
    required this.providers,
    super.key,
  });

  /// The list of provider widgets (such as [BlocSignalProvider]) to inject.
  final List<dynamic> providers;

  /// The child widget subtree that will have access to all provided blocs.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    var current = child;
    for (final provider in providers.reversed) {
      if (provider is BlocSignalProvider) {
        current = (provider as dynamic).copyWith(current) as Widget;
      }
    }
    return current;
  }
}
