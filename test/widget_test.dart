import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flus/main.dart';

void main() {
  test('URL validation rejects unsafe input', () {
    expect(validateUrl(''), isNotNull);
    expect(validateUrl('http://disk.yandex.ru/edit/d/example'), isNotNull);
    expect(
      validateUrl('https://disk.yandex.ru.evil.example/edit/d/test'),
      isNotNull,
    );
    expect(validateUrl('https://user@disk.yandex.ru/edit/d/test'), isNotNull);
    expect(validateUrl('https://disk.yandex.ru/edit/d/example'), isNull);
    expect(validateUrl('https://disk.yandex.com/i/example'), isNull);
  });

  testWidgets(
    'Minimal launcher shows TEST and local-only preview',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const FlusApp());
      await tester.pumpAndSettle();
      expect(find.text('FLUS'), findsOneWidget);
      expect(find.text('TEST'), findsOneWidget);
      expect(find.text('Остановлен'), findsOneWidget);
      expect(find.text('Веб-превью'), findsOneWidget);
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Вставьте Yandex Docs URL.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'Small screen does not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const FlusApp());
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
