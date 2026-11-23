import 'package:flutter_test/flutter_test.dart';

import 'package:uwb_locator/main.dart';

void main() {
  testWidgets('shows the splash, then the start screen', (tester) async {
    await tester.pumpWidget(const UwbLocatorApp());
    expect(find.text('Find My Friend'), findsOneWidget); // splash

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Start looking'), findsOneWidget);
  });

  test('splits peer names into name and id', () {
    final parts = splitPeerName('iPhone-60AF9');
    expect(parts.name, 'iPhone');
    expect(parts.tag, '60AF9');
    expect(splitPeerName('Laptop').tag, isNull);
  });
}
