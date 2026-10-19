import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:transfer_server/src/range.dart';
import 'package:transfer_server/transfer_server.dart';

import 'helpers.dart';

void main() {
  group('token', () {
    test('is 26 base32 characters (130 bits)', () {
      final token = generateToken();
      expect(token, hasLength(tokenLength));
      expect(token, matches(RegExp(r'^[A-Z2-7]{26}$')));
      expect(tokenLength * 5, greaterThanOrEqualTo(128));
    });

    test('is different every time', () {
      final tokens = {for (var i = 0; i < 10000; i++) generateToken()};
      expect(tokens, hasLength(10000));
    });

    test('uses every symbol about equally (no modulo bias)', () {
      final counts = <String, int>{};
      final rng = Random(42);
      for (var i = 0; i < 4000; i++) {
        for (final c in generateToken(rng).split('')) {
          counts[c] = (counts[c] ?? 0) + 1;
        }
      }
      expect(counts, hasLength(32));
      final expected = 4000 * tokenLength / 32;
      for (final n in counts.values) {
        expect(n, closeTo(expected, expected * 0.1));
      }
    });
  });

  group('decideRange', () {
    PartialContent partial(String h, int size) =>
        decideRange(rangeHeader: h, size: size) as PartialContent;

    test('no header means the whole file', () {
      expect(decideRange(rangeHeader: null, size: 10), isA<FullContent>());
    });

    test('closed, open and suffix ranges', () {
      expect(partial('bytes=0-0', 10), _range(0, 1));
      expect(partial('bytes=2-5', 10), _range(2, 6));
      expect(partial('bytes=7-', 10), _range(7, 10));
      expect(partial('bytes=-3', 10), _range(7, 10));
      expect(partial('bytes=-30', 10), _range(0, 10));
      expect(partial('bytes=5-999', 10), _range(5, 10));
      expect(partial('BYTES = 1-2', 10), _range(1, 3));
      expect(partial('bytes=9-9', 10), _range(9, 10));
    });

    test('ranges past the end are unsatisfiable', () {
      expect(decideRange(rangeHeader: 'bytes=10-', size: 10),
          isA<Unsatisfiable>());
      expect(decideRange(rangeHeader: 'bytes=10-20', size: 10),
          isA<Unsatisfiable>());
      expect(decideRange(rangeHeader: 'bytes=-0', size: 10),
          isA<Unsatisfiable>());
      expect(decideRange(rangeHeader: 'bytes=0-', size: 0),
          isA<Unsatisfiable>());
    });

    test('offsets beyond 4 GiB', () {
      const size = 6 * 1024 * 1024 * 1024;
      expect(partial('bytes=5000000000-5000000099', size),
          _range(5000000000, 5000000100));
    });

    test('malformed or multiple ranges fall back to the whole file', () {
      for (final h in [
        'bytes=a-b',
        'bytes=5-2',
        'bytes=-',
        'bytes=1-2,4-5',
        'items=0-1',
        'bytes 0-1',
        'bytes=+1-2',
        'bytes=0x1-2',
        'bytes=99999999999999999999-',
      ]) {
        expect(decideRange(rangeHeader: h, size: 10), isA<FullContent>(),
            reason: h);
      }
    });

    test('If-Range must match exactly, otherwise the whole file', () {
      RangeDecision d(String ifRange) => decideRange(
          rangeHeader: 'bytes=1-2',
          size: 10,
          ifRange: ifRange,
          etag: '"abc"',
          lastModified: 'Mon, 19 Oct 2026 10:00:00 GMT');
      expect(d('"abc"'), isA<PartialContent>());
      expect(d('Mon, 19 Oct 2026 10:00:00 GMT'), isA<PartialContent>());
      expect(d('"other"'), isA<FullContent>());
      expect(d('W/"abc"'), isA<FullContent>()); // Weak never matches.
      expect(d('Tue, 20 Oct 2026 10:00:00 GMT'), isA<FullContent>());
    });
  });

  group('Content-Disposition', () {
    test('ASCII names', () {
      expect(contentDisposition('IMG_0412.HEIC'),
          'attachment; filename="IMG_0412.HEIC"; filename*=UTF-8\'\'IMG_0412.HEIC');
    });

    test('non-ASCII names get an RFC 8187 form and a safe fallback', () {
      final value = contentDisposition('Città é 日本.pdf');
      expect(value, contains('filename="Citt_ _ __.pdf"'));
      expect(value,
          contains("filename*=UTF-8''Citt%C3%A0%20%C3%A9%20%E6%97%A5%E6%9C%AC.pdf"));
    });

    test('quotes, backslashes and control characters cannot break out', () {
      final value = contentDisposition('a"b\\c\r\nd;e.txt');
      expect(value, isNot(contains('\r')));
      expect(value, isNot(contains('\n')));
      expect(value, contains('filename="a_b_c__d;e.txt"'));
      expect(value, contains('a%22b%5Cc%0D%0Ad%3Be.txt'));
    });
  });

  group('isLanAddress', () {
    bool lan(String a) => isLanAddress(InternetAddress(a));

    test('private, link-local, loopback, CGNAT and CLAT are LAN', () {
      for (final a in [
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.23',
        '169.254.10.1',
        '127.0.0.1',
        '100.64.0.1',
        '192.0.0.2',
        '::1',
        'fe80::1',
        'fd00::1',
        '::ffff:192.168.1.5',
      ]) {
        expect(lan(a), isTrue, reason: a);
      }
    });

    test('public addresses are not', () {
      for (final a in [
        '8.8.8.8',
        '172.32.0.1',
        '192.169.0.1',
        '100.128.0.1',
        '2001:4860::8888',
        '::ffff:8.8.8.8',
      ]) {
        expect(lan(a), isFalse, reason: a);
      }
    });

    test('isPrivateIpv4 only accepts RFC 1918', () {
      expect(isPrivateIpv4(InternetAddress('192.168.0.10')), isTrue);
      expect(isPrivateIpv4(InternetAddress('127.0.0.1')), isFalse);
      expect(isPrivateIpv4(InternetAddress('169.254.1.1')), isFalse);
    });
  });

  group('GuestDevice', () {
    test('classifies common guest browsers', () {
      expect(GuestDevice.fromUserAgent(uaIphoneSafari).label, 'iPhone · Safari');
      expect(GuestDevice.fromUserAgent(uaIphoneChrome).label, 'iPhone · Chrome');
      expect(GuestDevice.fromUserAgent(uaAndroidChrome).label, 'Android · Chrome');
      expect(GuestDevice.fromUserAgent(uaSamsung).label,
          'Android · Samsung Internet');
      expect(GuestDevice.fromUserAgent(uaAndroidWebView).label,
          'Android · in-app browser');
      expect(GuestDevice.fromUserAgent(uaAndroidGoogleApp).label,
          'Android · Google app');
      expect(GuestDevice.fromUserAgent(uaIpadDesktop).platform,
          GuestPlatform.mac);
      expect(GuestDevice.fromUserAgent(null).label, 'Unknown device');
    });

    test('Chrome download rules apply to Chrome-based Android browsers only',
        () {
      expect(GuestDevice.fromUserAgent(uaAndroidChrome).usesChromeDownloads,
          isTrue);
      expect(GuestDevice.fromUserAgent(uaOldAndroid8Chrome).usesChromeDownloads,
          isTrue);
      expect(GuestDevice.fromUserAgent(uaSamsung).usesChromeDownloads, isFalse);
      expect(GuestDevice.fromUserAgent(uaIphoneChrome).usesChromeDownloads,
          isFalse);
    });
  });

  group('GuestStrings', () {
    test('falls back to English and reads Accept-Language', () {
      expect(GuestStrings.forAcceptLanguage(null).languageCode, 'en');
      expect(GuestStrings.forAcceptLanguage('it-CH, it;q=0.9, en;q=0.8')
          .languageCode, 'en');
      expect(GuestStrings.forAcceptLanguage('*').languageCode, 'en');
    });

    test('plural forms and placeholders', () {
      final s = GuestStrings.english;
      expect(s.plural('send_heading', 1), '1 file for you');
      expect(s.plural('send_heading', 3), '3 files for you');
      expect(s.get('send_total', {'size': '4 MB'}), '4 MB in total');
    });

    test('every language has exactly the English keys', () {
      final english = GuestStrings.keysOf('en');
      for (final code in GuestStrings.languageCodes) {
        expect(GuestStrings.keysOf(code), english, reason: code);
      }
    });

    test('every key used in the code exists', () {
      final used = <String>{};
      final source = Directory('lib/src')
          .listSync()
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join('\n');
      for (final m in RegExp(r"""\.get\(\s*'([a-z0-9_]+)'""")
          .allMatches(source)) {
        used.add(m.group(1)!);
      }
      for (final m in RegExp(r"""\.plural\(\s*'([a-z0-9_]+)'""")
          .allMatches(source)) {
        used
          ..add('${m.group(1)}_one')
          ..add('${m.group(1)}_other');
      }
      for (final m in RegExp(r"""return '(where_[a-z_]+)'|=> '(where_[a-z_]+)'|\? '(where_[a-z_]+)'|: '(where_[a-z_]+)'""")
          .allMatches(source)) {
        used.add([m.group(1), m.group(2), m.group(3), m.group(4)]
            .firstWhere((g) => g != null)!);
      }
      expect(used, isNotEmpty);
      expect(GuestStrings.keysOf('en'), containsAll(used));
    });
  });
}

Matcher _range(int start, int end) => isA<PartialContent>()
    .having((p) => p.start, 'start', start)
    .having((p) => p.end, 'end', end);
