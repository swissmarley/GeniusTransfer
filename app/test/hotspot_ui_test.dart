import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geniustransfer/l10n/app_localizations.dart';
import 'package:geniustransfer/platform/host_platform.dart';
import 'package:geniustransfer/session/session_controller.dart';
import 'package:geniustransfer/ui/no_network_screen.dart';
import 'package:geniustransfer/ui/qr_code_view.dart';
import 'package:geniustransfer/ui/session_screen.dart';

Widget app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('hotspot step 1 shows the Wi-Fi code, name and password',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    final platform = HostPlatform();
    final controller = SessionController.send(
      files: const [],
      platform: platform,
      notificationTitle: '',
      notificationText: '',
      notificationStop: '',
    );
    const hotspot = HotspotInfo(ssid: 'AndroidShare_4821', password: 'k7qx9mz2');
    controller.hotspot = hotspot;

    await tester.pumpWidget(app(HotspotStepView(
      controller: controller,
      hotspot: hotspot,
      size: 240,
      onOtherWays: () {},
    )));

    expect(find.text("Step 1 of 2: join this phone's Wi-Fi"), findsOneWidget);
    expect(find.text('Network: AndroidShare_4821\nPassword: k7qx9mz2'),
        findsOneWidget);
    final qr = tester.widget<QrCodeView>(find.byType(QrCodeView));
    expect(qr.data, 'WIFI:T:WPA;S:AndroidShare_4821;P:k7qx9mz2;;');

    expect(controller.hotspotStep, 1);
    await tester.tap(find.text('Joined? Show the second code'));
    expect(controller.hotspotStep, 2);
  });

  testWidgets('the guide on a computer: join the phone\'s hotspot',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NoNetworkScreen(platform: HostPlatform()),
    ));
    // Tests run on the desktop host, so this is the computer version.
    expect(find.text("Use the other phone's hotspot"), findsOneWidget);
    expect(find.text('On this computer, join that Wi-Fi network.'),
        findsOneWidget);
    expect(find.text("Use this iPhone's Personal Hotspot"), findsNothing);
    expect(find.text("Use this phone's hotspot"), findsNothing);
  });
}
