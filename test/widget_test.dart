import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wedding_video_share/screens/welcome_screen.dart';
import 'package:wedding_video_share/services/video_upload_service.dart';

void main() {
  test('video upload limits remain 15 GB with 8 MB resumable chunks', () {
    expect(maxVideoBytes, 15000000000);
    expect(uploadChunkBytes, 8 * 1024 * 1024);
  });

  testWidgets('welcome screen follows approved Canva welcome copy and account actions', (tester) async {
    var started = false;
    var recovering = false;

    await tester.pumpWidget(MaterialApp(
      home: WelcomeScreen(
        onGetStarted: () => started = true,
        onRecoverAccount: () => recovering = true,
      ),
    ));

    expect(find.text('WEDDING VIDEO SHARE'), findsOneWidget);
    expect(find.text('Celebrate. Share. Cherish.'), findsOneWidget);
    expect(find.textContaining('A welcome that feels'), findsOneWidget);
    expect(find.text('One clear invitation. No setup anxiety, no clutter.'), findsOneWidget);
    expect(find.text('₹290  •  One-Wedding Plan'), findsOneWidget);
    expect(find.textContaining('Upload first, pay when you share'), findsOneWidget);

    final getStarted = find.text('Get Started');
    await tester.ensureVisible(getStarted);
    await tester.tap(getStarted);
    expect(started, isTrue);

    final recover = find.text('Already have an account? Recover it');
    await tester.ensureVisible(recover);
    await tester.tap(recover);
    expect(recovering, isTrue);
  });

  testWidgets('welcome actions are disabled while account setup is busy', (tester) async {
    var started = false;
    var recovering = false;

    await tester.pumpWidget(MaterialApp(
      home: WelcomeScreen(
        onGetStarted: () => started = true,
        onRecoverAccount: () => recovering = true,
        busy: true,
      ),
    ));

    final buttons = tester.widgetList<Widget>(find.byType(FilledButton));
    expect(buttons.length, 1);
    expect((buttons.single as FilledButton).onPressed, isNull);
    final recover = tester.widget<TextButton>(find.byType(TextButton));
    expect(recover.onPressed, isNull);
    expect(started, isFalse);
    expect(recovering, isFalse);
  });
}
