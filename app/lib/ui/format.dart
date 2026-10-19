import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../net/lan_address.dart';

/// "3.2 MB", "245 MB", "1.4 GB": decimal units, as phones and the guest page
/// show them.
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['kB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final text =
      value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// "Wi-Fi", "Network cable", "Hotspot"…
String networkKindLabel(BuildContext context, LanKind kind) {
  final l = AppLocalizations.of(context);
  return switch (kind) {
    LanKind.wifi => l.networkWifi,
    LanKind.wired => l.networkWired,
    LanKind.hotspot => l.networkHotspot,
    LanKind.other => l.networkOther,
  };
}

/// "Wi-Fi · 192.168.1.23"
String describeAddress(BuildContext context, LanAddress a) =>
    '${networkKindLabel(context, a.kind)} · ${a.address.address}';
