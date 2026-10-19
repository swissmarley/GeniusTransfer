import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geniustransfer/l10n/app_localizations.dart';
import 'package:geniustransfer/platform/host_platform.dart';
import 'package:geniustransfer/receive/delivery.dart';
import 'package:geniustransfer/settings.dart';
import 'package:geniustransfer/session/session_controller.dart';
import 'package:geniustransfer/ui/receive_panel.dart';
import 'package:transfer_server/transfer_server.dart';

void main() {
  late SessionController controller;

  UploadOffered offer(String id, int count) => UploadOffered(
        id,
        '192.168.1.40',
        GuestDevice.fromUserAgent(
            'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 '
            'Mobile/15E148 Safari/604.1'),
        [for (var i = 0; i < count; i++) OfferedFile('IMG_$i.HEIC', 2500000)],
        count * 2500000,
        false,
      );

  /// Opens the sheet from a button and returns a getter for its answer.
  Future<bool? Function()> openSheet(
      WidgetTester tester, UploadOffered o) async {
    bool? answer;
    var answered = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            answer = await showModalBottomSheet<bool>(
              context: context,
              isDismissible: false,
              isScrollControlled: true,
              builder: (_) => OfferSheet(controller: controller, offer: o),
            );
            answered = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () {
      expect(answered, isTrue, reason: 'the sheet should have closed');
      return answer;
    };
  }

  setUp(() {
    final platform = HostPlatform();
    controller = SessionController.receive(
      stagingDir: Directory.systemTemp,
      delivery: Delivery(platform: platform, settings: AppSettings.forTest()),
      platform: platform,
      notificationTitle: '',
      notificationText: '',
      notificationStop: '',
    );
  });

  testWidgets('shows who sends what, and Accept answers true', (tester) async {
    final o = offer('a', 2);
    controller.pendingOffer = o;
    final result = await openSheet(tester, o);
    expect(find.text('iPhone · Safari wants to send you 2 files'), findsOneWidget);
    expect(find.text('5.0 MB in total'), findsOneWidget);
    expect(find.text('IMG_0.HEIC'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(result(), isTrue);
  });

  testWidgets('Decline answers false', (tester) async {
    final o = offer('b', 1);
    controller.pendingOffer = o;
    final result = await openSheet(tester, o);
    expect(find.text('iPhone · Safari wants to send you 1 file'), findsOneWidget);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(result(), isFalse);
  });

  testWidgets('long lists are cut, with a count of the rest', (tester) async {
    final o = offer('c', 9);
    controller.pendingOffer = o;
    await openSheet(tester, o);
    expect(find.text('IMG_5.HEIC'), findsOneWidget);
    expect(find.text('IMG_6.HEIC'), findsNothing);
    expect(find.text('and 3 more'), findsOneWidget);
  });

  testWidgets('closes by itself when the offer goes away', (tester) async {
    final o = offer('d', 1);
    controller.pendingOffer = o;
    final result = await openSheet(tester, o);
    controller.pendingOffer = null;
    controller.offerExpired = true;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Accept'), findsNothing);
    expect(result(), isNull);
  });
}
