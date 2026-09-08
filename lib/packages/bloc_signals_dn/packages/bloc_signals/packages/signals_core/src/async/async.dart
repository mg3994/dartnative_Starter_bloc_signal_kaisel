import 'dart:async';

import 'package:dartnative/dartnative.dart' show VoidCallback;

import '../core/core.dart';

sealed class AsyncState<T> {
  const AsyncState();

  bool get isLoading;
  T? get value;
  Object? get error;
  StackTrace? get stackTrace;
}

class AsyncLoading<T> extends AsyncState<T> {
  const AsyncLoading({this.previous});

  final T? previous;

  @override
  bool get isLoading => true;

  @override
  T? get value => previous;

  @override
  Object? get error => null;

  @override
  StackTrace? get stackTrace => null;

  @override
  bool operator ==(Object other) =>
      other is AsyncLoading<T> && other.previous == previous;

  @override
  int get hashCode => Object.hash('loading', previous);
}

class AsyncData<T> extends AsyncState<T> {
  const AsyncData(this.data);

  final T data;

  @override
  bool get isLoading => false;

  @override
  T get value => data;

  @override
  Object? get error => null;

  @override
  StackTrace? get stackTrace => null;

  @override
  bool operator ==(Object other) => other is AsyncData<T> && other.data == data;

  @override
  int get hashCode => Object.hash('data', data);
}

class AsyncError<T> extends AsyncState<T> {
  const AsyncError(this.exception, [this.trace]);

  final Object exception;
  final StackTrace? trace;

  @override
  bool get isLoading => false;

  @override
  T? get value => null;

  @override
  Object get error => exception;

  @override
  StackTrace? get stackTrace => trace;

  @override
  bool operator ==(Object other) =>
      other is AsyncError<T> && other.exception == exception;

  @override
  int get hashCode => Object.hash('error', exception);
}

class AsyncSignalOptions<T> {
  const AsyncSignalOptions({
    this.name,
    this.autoDispose = false,
    this.lazy = true,
    this.timeout,
  });

  final String? name;
  final bool autoDispose;
  final bool lazy;
  final Duration? timeout;
}

class FutureSignal<T> extends ReadonlySignal<AsyncState<T>> {
  FutureSignal(
    Future<T> future, {
    T? initialValue,
    AsyncSignalOptions<T>? options,
  }) : _state = signal<AsyncState<T>>(
          initialValue == null ? AsyncLoading<T>() : AsyncData<T>(initialValue),
          options: SignalOptions<AsyncState<T>>(name: options?.name),
        ) {
    unawaited(
      future.then(
        (value) => _state.value = AsyncData<T>(value),
        onError: (Object error, StackTrace trace) {
          _state.value = AsyncError<T>(error, trace);
        },
      ),
    );
  }

  final Signal<AsyncState<T>> _state;
  @override
  AsyncState<T> get value => _state.value;

  @override
  AsyncState<T> peek() => _state.peek();

  @override
  bool get isDisposed => _state.isDisposed;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  VoidCallback subscribe(void Function(AsyncState<T> value) listener) =>
      _state.subscribe(listener);

  @override
  void dispose() => _state.dispose();
}

FutureSignal<T> toFutureSignal<T>(
  Future<T> future, {
  Duration? timeout,
  T? initialValue,
  bool lazy = true,
  List<ReadonlySignal<dynamic>> dependencies = const [],
  AsyncSignalOptions<T>? options,
}) =>
    FutureSignal<T>(
      timeout == null ? future : future.timeout(timeout),
      initialValue: initialValue,
      options: options,
    );

extension FutureSignalExtension<T> on Future<T> {
  FutureSignal<T> toFutureSignal({
    Duration? timeout,
    T? initialValue,
    bool lazy = true,
    List<ReadonlySignal<dynamic>> dependencies = const [],
    AsyncSignalOptions<T>? options,
  }) =>
      signalsToFutureSignal(
        this,
        timeout: timeout,
        initialValue: initialValue,
        lazy: lazy,
        dependencies: dependencies,
        options: options,
      );
}

FutureSignal<T> signalsToFutureSignal<T>(
  Future<T> future, {
  Duration? timeout,
  T? initialValue,
  bool lazy = true,
  List<ReadonlySignal<dynamic>> dependencies = const [],
  AsyncSignalOptions<T>? options,
}) =>
    toFutureSignal(
      future,
      timeout: timeout,
      initialValue: initialValue,
      lazy: lazy,
      dependencies: dependencies,
      options: options,
    );

class StreamSignal<T> extends ReadonlySignal<AsyncState<T>> {
  StreamSignal(
    Stream<T> stream, {
    T? initialValue,
    bool cancelOnError = false,
    AsyncSignalOptions<T>? options,
  }) : _state = signal<AsyncState<T>>(
          initialValue == null ? AsyncLoading<T>() : AsyncData<T>(initialValue),
          options: SignalOptions<AsyncState<T>>(name: options?.name),
        ) {
    _subscription = stream.listen(
      (value) => _state.value = AsyncData<T>(value),
      onError: (Object error, StackTrace trace) {
        _state.value = AsyncError<T>(error, trace);
        if (cancelOnError) unawaited(_subscription.cancel());
      },
    );
  }

  final Signal<AsyncState<T>> _state;
  late final StreamSubscription<T> _subscription;

  @override
  AsyncState<T> get value => _state.value;

  @override
  AsyncState<T> peek() => _state.peek();

  @override
  bool get isDisposed => _state.isDisposed;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  VoidCallback subscribe(void Function(AsyncState<T> value) listener) =>
      _state.subscribe(listener);

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _state.dispose();
  }
}

StreamSignal<T> toStreamSignal<T>(
  Stream<T> stream, {
  T? initialValue,
  bool cancelOnError = false,
  bool lazy = true,
  List<ReadonlySignal<dynamic>> dependencies = const [],
  AsyncSignalOptions<T>? options,
}) =>
    StreamSignal<T>(
      stream,
      initialValue: initialValue,
      cancelOnError: cancelOnError,
      options: options,
    );

extension StreamSignalExtension<T> on Stream<T> {
  StreamSignal<T> toStreamSignal({
    T? initialValue,
    bool cancelOnError = false,
    bool lazy = true,
    List<ReadonlySignal<dynamic>> dependencies = const [],
    AsyncSignalOptions<T>? options,
  }) =>
      signalsToStreamSignal<T>(
        this,
        initialValue: initialValue,
        cancelOnError: cancelOnError,
        lazy: lazy,
        dependencies: dependencies,
        options: options,
      );
}

StreamSignal<T> signalsToStreamSignal<T>(
  Stream<T> stream, {
  T? initialValue,
  bool cancelOnError = false,
  bool lazy = true,
  List<ReadonlySignal<dynamic>> dependencies = const [],
  AsyncSignalOptions<T>? options,
}) =>
    toStreamSignal(
      stream,
      initialValue: initialValue,
      cancelOnError: cancelOnError,
      lazy: lazy,
      dependencies: dependencies,
      options: options,
    );

extension ReadonlySignalStreamExtension<T> on ReadonlySignal<T> {
  Stream<T> toStream() {
    late StreamController<T> controller;
    VoidCallback? cancel;
    controller = StreamController<T>(
      sync: true,
      onListen: () {
        controller.add(value);
        cancel = subscribe((next) => controller.add(next));
      },
      onCancel: () {
        cancel?.call();
        cancel = null;
      },
    );
    return controller.stream;
  }
}
