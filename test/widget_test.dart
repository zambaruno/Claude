import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lost_mvp/main.dart';

void main() {
  testWidgets('long press emblem identifies the installed build', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.longPress(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(find.textContaining('$appVersion (local)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'emblem opens second screen with matching main and navigation lenses',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      expect(find.byType(AppNavBar), findsNothing);
      expect(find.byType(LensHero), findsNothing);
      final emblem = tester.widget<Image>(find.byType(Image));
      expect(
        (emblem.image as AssetImage).assetName,
        'assets/file_000000008284822fab87455a1155f93a.png',
      );
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.byType(CapturePage), findsOneWidget);
      expect(find.byType(AppNavBar), findsOneWidget);
      expect(find.byType(LensHero), findsNWidgets(2));
    },
  );
}
