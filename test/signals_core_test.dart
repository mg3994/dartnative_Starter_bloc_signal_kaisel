import 'package:test/test.dart';

import 'package:dartnative_starter/packages/bloc_signals_dn/packages/bloc_signals/signals_core/signals_core.dart';

void main() {
  test('signal updates subscribers and suppresses equal values', () {
    final count = signal(0);
    var notifications = 0;
    final cancel = count.subscribe((_) => notifications++);

    count.value = 0;
    count.value = 1;
    count.update((value) => value + 1);

    expect(count.value, 2);
    expect(notifications, 2);
    cancel();
    count.value = 3;
    expect(notifications, 2);
  });

  test('computed values track dependencies and effects can be cancelled', () {
    final count = signal(2);
    final doubled = computed(() => count.value * 2);
    final values = <int>[];
    final stop = effect(() => values.add(doubled.value));

    expect(doubled.value, 4);
    count.value = 3;
    expect(doubled.value, 6);
    expect(values, [4, 6]);

    stop();
    count.value = 4;
    expect(values, [4, 6]);
  });

  test('disposed signals reject reads and writes', () {
    final count = signal(1);
    count.dispose();

    expect(() => count.value, throwsA(isA<SignalsReadAfterDisposeError>()));
    expect(() => count.value = 2,
        throwsA(isA<SignalsWriteAfterDisposeError>()));
  });
}
