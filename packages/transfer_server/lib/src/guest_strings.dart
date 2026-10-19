/// Every piece of text the guest sees, in one place so it can be translated.
///
/// To add a language: copy [_en] to a new map with the same keys, translate
/// the values, and add it to [_languages]. Placeholders look like `{name}`.
/// Keys ending in `_one` / `_other` are the singular and plural forms.
/// A test checks that every language has exactly the keys of English.
class GuestStrings {
  GuestStrings._(this.languageCode, this._values);

  /// Picks the best language for an `Accept-Language` header, falling back
  /// to English.
  factory GuestStrings.forAcceptLanguage(String? header) {
    for (final code in _preferredLanguages(header)) {
      final values = _languages[code];
      if (values != null) return GuestStrings._(code, values);
    }
    return GuestStrings._('en', _en);
  }

  /// English, the source language.
  static final GuestStrings english = GuestStrings._('en', _en);

  /// Language codes that have translations.
  static Iterable<String> get languageCodes => _languages.keys;

  /// The keys of a language's table, for tests.
  static Set<String> keysOf(String languageCode) =>
      _languages[languageCode]!.keys.toSet();

  /// BCP 47 primary language subtag, e.g. "en".
  final String languageCode;
  final Map<String, String> _values;

  /// The text for [key], with `{placeholders}` replaced from [args].
  String get(String key, [Map<String, Object> args = const {}]) {
    var text = _values[key] ?? _en[key];
    if (text == null) throw ArgumentError('Unknown guest string: $key');
    for (final entry in args.entries) {
      text = text!.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return text!;
  }

  /// [key]_one or [key]_other depending on [count], with `{count}` filled.
  String plural(String key, int count, [Map<String, Object> args = const {}]) =>
      get(count == 1 ? '${key}_one' : '${key}_other', {'count': count, ...args});

  static List<String> _preferredLanguages(String? header) {
    if (header == null) return const [];
    final entries = <(String, double)>[];
    for (final part in header.split(',')) {
      final pieces = part.trim().split(';');
      final tag = pieces.first.trim().toLowerCase();
      if (tag.isEmpty || tag == '*') continue;
      var q = 1.0;
      for (final p in pieces.skip(1)) {
        final kv = p.trim().split('=');
        if (kv.length == 2 && kv[0].trim() == 'q') {
          q = double.tryParse(kv[1].trim()) ?? 0;
        }
      }
      entries.add((tag.split('-').first, q));
    }
    entries.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in entries) if (e.$2 > 0) e.$1];
  }
}

const _languages = <String, Map<String, String>>{
  'en': _en,
};

const _en = <String, String>{
  'page_title': 'GeniusTransfer',

  // Send page (the guest downloads).
  'send_heading_one': '1 file for you',
  'send_heading_other': '{count} files for you',
  'send_total': '{size} in total',
  'send_tap_download': 'Tap Download to save a file here.',
  'download_button': 'Download',
  'download_started': 'Download started.',
  'send_empty': 'Nothing is being shared right now.',
  'keep_page_open': 'Keep this page open until your downloads have finished.',

  // Receive page (the guest sends files to the host).
  'receive_heading': 'Send files to the other device',
  'receive_sub':
      'Choose photos, videos or other files. The other device will ask '
          'before accepting them.',
  'receive_choose': 'Choose files',
  'receive_send_button': 'Send',
  'receive_pick_first': 'Choose at least one file first.',
  'receive_waiting': 'Waiting for the other device to accept…',
  'receive_sending': 'Sending… Keep this page open until it has finished.',
  'receive_file_done': 'Sent',
  'receive_done_one': '1 file sent.',
  'receive_done_other': '{count} files sent.',
  'receive_declined': 'The other device declined these files.',
  'receive_expired':
      'Nobody answered on the other device. Send the files again.',
  'receive_busy':
      'The other device is still deciding about other files. Try again in '
          'a moment.',
  'receive_too_many': 'Too many files at once. Send at most {count}.',
  'receive_too_large':
      'That is too much at once. Send at most {size} at a time.',
  'receive_no_space': 'The other device does not have enough free space.',
  'receive_failed':
      'Sending stopped. Check that both devices are still on the same '
          'network, then send again.',
  'receive_arrived_waiting':
      'Your files have arrived. Waiting for the other device to accept '
          'them…',
  'receive_more': 'Send more files',

  // Where the file goes. Shown under the heading, chosen by platform.
  'where_ios_safari':
      'Files are saved in the Files app › Downloads. If Safari asks, tap Download.',
  'where_ios_other':
      'When the download finishes, look for the file in the Files app.',
  'where_android_chrome':
      'Files are saved in your Downloads folder (Files app › Downloads).',
  'where_android_samsung': 'Files are saved in My Files › Downloads.',
  'where_android_other': 'Files are saved in your Downloads folder.',
  'where_in_app_browser':
      'If nothing happens when you tap Download, open this page in your browser '
          '(Safari or Chrome) and try again.',
  'where_computer': 'Files are saved in your browser’s downloads folder.',

  // Chrome on Android asks before keeping files that arrive without HTTPS,
  // except common photo, video and audio types.
  'chrome_keep_hint':
      'Chrome may say “File can’t be downloaded securely”. That is expected '
          'here: the file comes straight from the other device, without the '
          'internet. Tap Keep to save it.',

  // Connection state, updated by the page while it is open.
  'connection_lost':
      'Can’t reach the other device. Keep it on and unlocked, with '
          'GeniusTransfer open.',
  'session_ended': 'The other device has stopped sharing.',

  // PIN page, when the other device asks for one.
  'pin_title': 'Enter the PIN',
  'pin_body': 'It is shown on the other device.',
  'pin_label': 'PIN',
  'pin_button': 'Continue',
  'pin_wrong_one': 'Wrong PIN. 1 try left.',
  'pin_wrong_other': 'Wrong PIN. {count} tries left.',
  'pin_locked':
      'Too many wrong PINs. Ask the other device to start sharing again.',

  // Saving photos and videos to Photos on an iPhone or iPad.
  'view_button': 'Open',
  'ios_photos_hint':
      'To put a photo or video in Photos: tap Open, then touch and hold the '
          'photo, or tap Share under the video, and choose Save.',

  // Shown for old or wrong links.
  'expired_title': 'This link has expired',
  'expired_body':
      'Ask for a new code on the other device, then scan or type it again.',
  'not_found': 'Not found.',

  'footer': 'Sent directly from the other device. No internet, no cloud.',

  // File sizes.
  'size_bytes': '{n} bytes',
  'size_kb': '{n} kB',
  'size_mb': '{n} MB',
  'size_gb': '{n} GB',
};
