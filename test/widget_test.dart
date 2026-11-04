import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wedding_video_share/screens/welcome_screen.dart';
import 'package:wedding_video_share/services/video_upload_service.dart';

void main() {
  test('video upload limit remains 40 GB with 8 MB resumable chunks', () {
    expect(maxVideoBytes, 40000000000);
    expect(uploadChunkBytes, 8 * 1024 * 1024);
  });

  testWidgets('welcome screen matches approved Canva WVS mockup and actions', (tester) async {
    var started = false;
    var recovering = false;
    tester.view.physicalSize = const Size(432, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: WelcomeScreen(
      onGetStarted: () => started = true,
      onRecoverAccount: () => recovering = true,
    )));

    expect(find.text('WVS'), findsOneWidget);
    expect(find.text('Celebrate. Share. Cherish.'), findsOneWidget);
    expect(find.text('Choose Google Account & Connect Drive'), findsOneWidget);
    expect(find.text('One wedding. One beautiful way to share.'), findsOneWidget);

    await tester.ensureVisible(find.text('Choose Google Account & Connect Drive'));
    await tester.tap(find.text('Choose Google Account & Connect Drive'));
    expect(started, isTrue);

    await tester.ensureVisible(find.text('Already have an account? Recover it'));
    await tester.tap(find.text('Already have an account? Recover it'));
    expect(recovering, isTrue);
  });

  testWidgets('welcome actions are disabled while account setup is busy', (tester) async {
    await tester.pumpWidget(MaterialApp(home: WelcomeScreen(
      onGetStarted: () {}, onRecoverAccount: () {}, busy: true,
    )));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    final recover = tester.widget<TextButton>(find.byType(TextButton));
    expect(recover.onPressed, isNull);
  });
}
