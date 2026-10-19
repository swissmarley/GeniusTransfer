/// The guest's platform, as far as the User-Agent tells.
enum GuestPlatform { ios, android, mac, other }

/// The guest's browser. [googleApp] and [webView] are in-app browsers, where
/// downloads may not work.
enum GuestBrowser {
  safari,
  chrome,
  samsungInternet,
  firefox,
  edge,
  googleApp,
  webView,
  other,
}

/// What we know about a guest device from its User-Agent header.
class GuestDevice {
  const GuestDevice(this.platform, this.browser, this.model);

  /// Classifies a User-Agent string. iPadOS 13+ reports a Mac User-Agent;
  /// that case is classified as [GuestPlatform.mac] here and fixed on the
  /// page with JavaScript (touch support).
  factory GuestDevice.fromUserAgent(String? ua) {
    if (ua == null || ua.isEmpty) {
      return const GuestDevice(GuestPlatform.other, GuestBrowser.other, '');
    }
    final iosModel = RegExp(r'\b(iPhone|iPad|iPod)\b').firstMatch(ua)?.group(1);
    if (iosModel != null && !ua.contains('Windows Phone')) {
      final GuestBrowser browser;
      if (ua.contains('CriOS/')) {
        browser = GuestBrowser.chrome;
      } else if (ua.contains('FxiOS/')) {
        browser = GuestBrowser.firefox;
      } else if (ua.contains('EdgiOS/')) {
        browser = GuestBrowser.edge;
      } else if (ua.contains('GSA/')) {
        browser = GuestBrowser.googleApp;
      } else if (ua.contains('Safari/')) {
        browser = GuestBrowser.safari;
      } else {
        browser = GuestBrowser.webView;
      }
      return GuestDevice(GuestPlatform.ios, browser, iosModel);
    }
    if (ua.contains('Android')) {
      final GuestBrowser browser;
      if (ua.contains('SamsungBrowser/')) {
        browser = GuestBrowser.samsungInternet;
      } else if (ua.contains('GSA/')) {
        browser = GuestBrowser.googleApp;
      } else if (ua.contains('; wv)')) {
        browser = GuestBrowser.webView;
      } else if (ua.contains('Firefox/')) {
        browser = GuestBrowser.firefox;
      } else if (ua.contains('EdgA/')) {
        browser = GuestBrowser.edge;
      } else if (ua.contains('Chrome/')) {
        browser = GuestBrowser.chrome;
      } else {
        browser = GuestBrowser.other;
      }
      return GuestDevice(GuestPlatform.android, browser, 'Android');
    }
    if (ua.contains('Macintosh')) {
      final browser = ua.contains('Chrome/')
          ? GuestBrowser.chrome
          : ua.contains('Firefox/')
              ? GuestBrowser.firefox
              : ua.contains('Safari/')
                  ? GuestBrowser.safari
                  : GuestBrowser.other;
      return GuestDevice(GuestPlatform.mac, browser, 'Mac');
    }
    final browser = ua.contains('Chrome/')
        ? GuestBrowser.chrome
        : ua.contains('Firefox/')
            ? GuestBrowser.firefox
            : GuestBrowser.other;
    return GuestDevice(GuestPlatform.other, browser, 'Computer');
  }

  final GuestPlatform platform;
  final GuestBrowser browser;

  /// "iPhone", "iPad", "Android", "Mac", "Computer", or empty if unknown.
  final String model;

  /// Whether Chrome's download handling (and its insecure-download warning)
  /// applies.
  bool get usesChromeDownloads =>
      platform == GuestPlatform.android &&
      (browser == GuestBrowser.chrome ||
          browser == GuestBrowser.googleApp ||
          browser == GuestBrowser.webView);

  /// A short label for the host UI, e.g. "iPhone · Safari".
  String get label {
    final b = switch (browser) {
      GuestBrowser.safari => 'Safari',
      GuestBrowser.chrome => 'Chrome',
      GuestBrowser.samsungInternet => 'Samsung Internet',
      GuestBrowser.firefox => 'Firefox',
      GuestBrowser.edge => 'Edge',
      GuestBrowser.googleApp => 'Google app',
      GuestBrowser.webView => 'in-app browser',
      GuestBrowser.other => '',
    };
    final m = model.isEmpty ? 'Unknown device' : model;
    return b.isEmpty ? m : '$m · $b';
  }
}
