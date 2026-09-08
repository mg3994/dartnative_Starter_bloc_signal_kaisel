import 'package:dartnative/dartnative.dart';
// ignore: implementation_imports
import 'package:dartnative/src/reconciler/element.dart';

/// Equality strategy used by writable and derived signals.
abstract class SignalEquality<T> {
  const SignalEquality();

  bool equals(T previous, T next);

  const factory SignalEquality.identity() = _IdentityEquality<T>;
  const factory SignalEquality.structural() = _StructuralEquality<T>;
  const factory SignalEquality.custom(bool Function(T previous, T next) fn) =
      _CustomEquality<T>;
}

class _IdentityEquality<T> extends SignalEquality<T> {
  const _IdentityEquality();

  @override
  bool equals(T previous, T next) => identical(previous, next);
}

class _StructuralEquality<T> extends SignalEquality<T> {
  const _StructuralEquality();

  @override
  bool equals(T previous, T next) => previous == next;
}

class _CustomEquality<T> extends SignalEquality<T> {
  const _CustomEquality(this.fn);

  final bool Function(T previous, T next) fn;

  @override
  bool equals(T previous, T next) => fn(previous, next);
}

class SignalOptions<T> {
  const SignalOptions({
    this.name,
    this.autoDispose = false,
    this.watched,
    this.unwatched,
    this.equality,
  });

  final String? name;
  final bool autoDispose;
  final void Function()? watched;
  final void Function()? unwatched;
  final SignalEquality<T>? equality;

  SignalEquality<T>? get equalityCheck => equality;
}

class EffectOptions {
  const EffectOptions({this.name, this.onDispose});

  final String? name;
  final void Function()? onDispose;
}

abstract class ReadonlySignal<T> {
  T get value;
  T peek();
  bool get isDisposed;
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
  VoidCallback subscribe(void Function(T value) listener);
  void dispose();
}

class Signal<T> extends ReadonlySignal<T> {
  Signal(this._value, {SignalOptions<T>? options})
      : _equality = options?.equality ?? SignalEquality<T>.structural(),
        options = options ?? SignalOptions<T>();

  T _value;
  final SignalEquality<T> _equality;
  final SignalOptions<T> options;
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  bool _disposed = false;
  bool _notifying = false;

  @override
  bool get isDisposed => _disposed;

  @override
  T get value {
    _ensureReadable();
    _track(this);
    return _value;
  }

  @override
  T peek() {
    _ensureReadable();
    return _value;
  }

  set value(T next) {
    _ensureWritable();
    if (_equality.equals(_value, next)) return;
    _value = next;
    _notify();
  }

  void update(T Function(T current) fn) => value = fn(peek());

  @override
  void addListener(VoidCallback listener) {
    _ensureReadable();
    final wasEmpty = _listeners.isEmpty;
    _listeners.add(listener);
    if (wasEmpty) options.watched?.call();
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_disposed) return;
    _listeners.remove(listener);
    if (_listeners.isEmpty) options.unwatched?.call();
  }

  @override
  VoidCallback subscribe(void Function(T value) listener) {
    void notify() => listener(peek());
    addListener(notify);
    return () => removeListener(notify);
  }

  void _notify() {
    if (_notifying) return;
    _notifying = true;
    try {
      for (final listener in List<VoidCallback>.of(_listeners)) {
        listener();
      }
    } finally {
      _notifying = false;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
    options.unwatched?.call();
  }

  void _ensureReadable() {
    if (_disposed) throw SignalsReadAfterDisposeError(this);
  }

  void _ensureWritable() {
    if (_disposed) throw SignalsWriteAfterDisposeError(this);
  }
}

class Computed<T> extends ReadonlySignal<T> {
  Computed(this._compute, {SignalOptions<T>? options})
      : options = options ?? SignalOptions<T>() {
    _recompute();
  }

  final T Function() _compute;
  final SignalOptions<T> options;
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  final Map<ReadonlySignal<dynamic>, VoidCallback> _dependencies =
      <ReadonlySignal<dynamic>, VoidCallback>{};
  T? _value;
  bool _hasValue = false;
  bool _disposed = false;
  bool _computing = false;

  @override
  bool get isDisposed => _disposed;

  @override
  T get value {
    _ensureReadable();
    _track(this);
    return _value as T;
  }

  @override
  T peek() {
    _ensureReadable();
    return _value as T;
  }

  @override
  void addListener(VoidCallback listener) {
    _ensureReadable();
    final wasEmpty = _listeners.isEmpty;
    _listeners.add(listener);
    if (wasEmpty) {
      for (final dependency in _dependencies.keys) {
        dependency.addListener(_dependencyChanged);
      }
      options.watched?.call();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_disposed) return;
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      for (final dependency in _dependencies.keys) {
        dependency.removeListener(_dependencyChanged);
      }
      options.unwatched?.call();
    }
  }

  @override
  VoidCallback subscribe(void Function(T value) listener) {
    void notify() => listener(peek());
    addListener(notify);
    return () => removeListener(notify);
  }

  void _dependencyChanged() {
    final oldValue = _value;
    _recompute();
    if (!_same(oldValue, _value)) {
      for (final listener in List<VoidCallback>.of(_listeners)) {
        listener();
      }
    }
  }

  void _recompute() {
    if (_computing) throw EffectCycleDetectionError();
    _computing = true;
    final previous = _activeTracker;
    final discovered = <ReadonlySignal<dynamic>>{};
    _activeTracker = _DependencyCollector(discovered);
    try {
      final next = _compute();
      _value = next;
      _hasValue = true;
    } finally {
      _activeTracker = previous;
      _computing = false;
    }
    final stale =
        _dependencies.keys.where((d) => !discovered.contains(d)).toList();
    for (final dependency in stale) {
      dependency.removeListener(_dependencyChanged);
      _dependencies.remove(dependency);
    }
    for (final dependency in discovered) {
      _dependencies.putIfAbsent(dependency, () {
        if (_listeners.isNotEmpty) dependency.addListener(_dependencyChanged);
        return _dependencyChanged;
      });
    }
  }

  bool _same(T? previous, T? next) =>
      _hasValue &&
      (options.equality ?? SignalEquality<T>.structural())
          .equals(previous as T, next as T);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final dependency in _dependencies.keys) {
      dependency.removeListener(_dependencyChanged);
    }
    _dependencies.clear();
    _listeners.clear();
    options.unwatched?.call();
  }

  void _ensureReadable() {
    if (_disposed) throw SignalsReadAfterDisposeError(this);
  }
}

abstract class _Tracker {
  void track(ReadonlySignal<dynamic> signal);
}

class _DependencyCollector implements _Tracker {
  _DependencyCollector(this.dependencies);

  final Set<ReadonlySignal<dynamic>> dependencies;

  @override
  void track(ReadonlySignal<dynamic> signal) => dependencies.add(signal);
}

_Tracker? _activeTracker;

void _track(ReadonlySignal<dynamic> signal) => _activeTracker?.track(signal);

Computed<T> computed<T>(T Function() compute, {SignalOptions<T>? options}) =>
    Computed<T>(compute, options: options);

Signal<T> signal<T>(T initial, {SignalOptions<T>? options}) =>
    Signal<T>(initial, options: options);

VoidCallback effect(void Function() fn, {EffectOptions? options}) {
  late final _EffectRunner runner;
  runner = _EffectRunner(fn, options: options);
  runner.run();
  _activeModel?._addCleanup(runner.cancel);
  return runner.cancel;
}

class _EffectRunner implements _Tracker {
  _EffectRunner(this.fn, {this.options});

  final void Function() fn;
  final EffectOptions? options;
  final Map<ReadonlySignal<dynamic>, VoidCallback> dependencies =
      <ReadonlySignal<dynamic>, VoidCallback>{};
  bool cancelled = false;
  bool running = false;

  void run() {
    if (cancelled || running) return;
    running = true;
    for (final dependency in dependencies.keys) {
      dependency.removeListener(_rerun);
    }
    dependencies.clear();
    final previous = _activeTracker;
    _activeTracker = this;
    try {
      fn();
    } finally {
      _activeTracker = previous;
      running = false;
    }
  }

  void _rerun() => run();

  @override
  void track(ReadonlySignal<dynamic> signal) {
    if (dependencies.containsKey(signal)) return;
    dependencies[signal] = _rerun;
    signal.addListener(_rerun);
  }

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    for (final dependency in dependencies.keys) {
      dependency.removeListener(_rerun);
    }
    dependencies.clear();
    options?.onDispose?.call();
  }
}

class SignalModel<T> {
  SignalModel(this._dispose);

  final void Function() _dispose;
  final List<VoidCallback> _cleanups = <VoidCallback>[];
  bool _disposed = false;

  void _addCleanup(VoidCallback cleanup) => _cleanups.add(cleanup);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final cleanup in _cleanups.reversed) {
      cleanup();
    }
    _cleanups.clear();
    _dispose();
  }
}

typedef SignalModelConstructor<T> = SignalModel<T> Function();

SignalModelConstructor<T> createModel<T>(T Function() builder) {
  return () {
    final model = SignalModel<T>(() {});
    final previous = _activeModel;
    _activeModel = model;
    try {
      builder();
    } finally {
      _activeModel = previous;
    }
    return model;
  };
}

SignalModel<dynamic>? _activeModel;

T peek<T>(ReadonlySignal<T> signal) => signal.peek();

void batch(void Function() fn) => fn();

T untracked<T>(T Function() fn) {
  final previous = _activeTracker;
  _activeTracker = null;
  try {
    return fn();
  } finally {
    _activeTracker = previous;
  }
}

class SignalsError extends Error {
  SignalsError(this.message);
  final String message;
  @override
  String toString() => message;
}

class SignalsReadAfterDisposeError extends SignalsError {
  SignalsReadAfterDisposeError(ReadonlySignal instance)
      : super(
            'A ${instance.runtimeType} signal was read after being disposed.');
}

class SignalsWriteAfterDisposeError extends SignalsError {
  SignalsWriteAfterDisposeError(ReadonlySignal instance)
      : super(
            'A ${instance.runtimeType} signal was written after being disposed.');
}

class EffectCycleDetectionError extends Error {}

extension SignalWatch<T> on ReadonlySignal<T> {
  T watch(BuildContext context) {
    final element = context as Element;
    void rebuild() => element.markDirty();
    addListener(rebuild);
    element.addSubscription(() => removeListener(rebuild));
    return value;
  }
}

extension ListenableWatch on Listenable {
  T watch<T extends Listenable>(BuildContext context) {
    final element = context as Element;
    void rebuild() => element.markDirty();
    addListener(rebuild);
    element.addSubscription(() => removeListener(rebuild));
    return this as T;
  }
}

class Provided<T> extends InheritedWidget {
  const Provided({super.key, required this.value, required super.child});

  final T value;

  static T of<T>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Provided<T>>()!.value;

  @override
  bool updateShouldNotify(Provided<T> old) => !identical(value, old.value);
}
