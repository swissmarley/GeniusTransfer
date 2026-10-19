import 'package:test/test.dart';
import 'package:transfer_server/src/guest_page.dart';
import 'package:transfer_server/transfer_server.dart';

import 'helpers.dart';

/// An in-memory file, enough for rendering.
class FakeFile implements SharedFile {
  FakeFile(this.name, this.length);
  @override
  final String name;
  @override
  final int length;
  @override
  DateTime? get lastModified => null;
  @override
  Stream<List<int>> openRead(int start, int end) => const Stream.empty();
  @override
  Future<void> close() async {}
}

String render(List<SharedFile> files, String? ua) => renderSendPage(
      files: files,
      strings: GuestStrings.english,
      device: GuestDevice.fromUserAgent(ua),
      nonce: 'NONCE',
    );

void main() {
  final files = [
    FakeFile('IMG_0412.HEIC', 3200000),
    FakeFile('holiday.mp4', 1400000000),
    FakeFile('notes.pdf', 54321),
  ];

  test('makes no request to anything but this server', () {
    for (final ua in [uaIphoneSafari, uaAndroidChrome, uaSamsung, null]) {
      final html = render(files, ua);
      expect(html, isNot(contains('http://')));
      expect(html, isNot(contains('https://')));
      expect(html, isNot(contains('//')), reason: 'no protocol-relative URLs');
      expect(html, isNot(contains('@import')));
      expect(html, isNot(contains('url(')));
      expect(html,
          isNot(matches(RegExp(r'<(link|img|iframe|object|embed|video|audio|source)[\s>/]'))));
      for (final m
          in RegExp(r'''(?:src|href|action)\s*=\s*"([^"]*)"''').allMatches(html)) {
        final value = m.group(1)!;
        expect(value, isNot(contains(':')), reason: value);
        expect(value.startsWith('f/') || value.startsWith('v/'), isTrue,
            reason: value);
      }
    }
  });

  test('downloads are plain links, so they work without JavaScript', () {
    final html = render(files, uaIphoneSafari);
    expect(html, contains('<a class="dl" href="f/0/IMG_0412.HEIC" download'));
    expect(html, contains('href="f/1/holiday.mp4"'));
    expect(html, contains('href="f/2/notes.pdf"'));
  });

  test('stays small', () {
    final many = [for (var i = 0; i < 20; i++) FakeFile('IMG_$i.JPG', 4000000)];
    expect(render(many, uaAndroidChrome).length, lessThan(30 * 1024));
  });

  test('the script is ES5 only, for old browsers', () {
    const script = guestPageScriptForTest;
    for (final forbidden in [
      '=>',
      '`',
      'let ',
      'const ',
      'class ',
      'fetch(',
      'Promise',
      'async ',
      'await ',
      '...',
      '?.',
      '??',
      'includes(',
      'Object.assign',
      'Array.from',
    ]) {
      expect(script, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('CSS avoids features missing from Safari 13 and old Chrome', () {
    final html = render(files, uaIphoneSafari);
    final css = RegExp(r'<style>(.*?)</style>', dotAll: true)
        .firstMatch(html)!
        .group(1)!;
    for (final forbidden in ['var(--', 'display:grid', 'gap:', 'clamp(', ':is(', ':has(']) {
      expect(css, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('file names are escaped', () {
    final html = render([FakeFile('<script>alert(1)</script>".jpg', 1)], null);
    expect(html, isNot(contains('<script>alert')));
    expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt;&quot;.jpg'));
    expect(html, contains('href="f/0/%3Cscript%3Ealert(1)%3C%2Fscript%3E%22.jpg"'));
  });

  test('long names are shortened in the middle, full name kept in title', () {
    final name = '${'a' * 80}_END.pdf';
    final html = render([FakeFile(name, 1)], null);
    expect(html, contains('title="$name"'));
    expect(html, contains('…'));
    expect(html, contains('_END.pdf</div>'));
  });

  group('where the file goes', () {
    test('iPhone Safari: Files › Downloads', () {
      expect(render(files, uaIphoneSafari),
          contains('Files are saved in the Files app › Downloads'));
    });

    test('Android Chrome: Downloads folder', () {
      expect(render(files, uaAndroidChrome),
          contains('Files are saved in your Downloads folder'));
    });

    test('Samsung Internet: My Files › Downloads', () {
      expect(render(files, uaSamsung), contains('My Files › Downloads'));
    });

    test('in-app browsers: suggest opening a real browser', () {
      expect(render(files, uaAndroidGoogleApp),
          contains('open this page in your browser'));
      expect(render(files, uaAndroidWebView),
          contains('open this page in your browser'));
    });

    test('iPadOS (Mac User-Agent) gets the iOS text through the script', () {
      final html = render(files, uaIpadDesktop);
      expect(html, contains('data-ipad="Files are saved in the Files app'));
    });
  });

  group('Chrome "tap Keep" hint', () {
    test('shown on Android Chrome when a file type will be questioned', () {
      expect(render(files, uaAndroidChrome), contains('Tap Keep'));
      expect(render(files, uaOldAndroid8Chrome), contains('Tap Keep'));
    });

    test('not shown when every file is on Chrome\'s safe list', () {
      final safe = [FakeFile('a.jpg', 1), FakeFile('b.MP4', 1), FakeFile('c.mov', 1)];
      expect(render(safe, uaAndroidChrome), isNot(contains('Tap Keep')));
    });

    test('not shown on iPhone or Samsung Internet', () {
      expect(render(files, uaIphoneSafari), isNot(contains('Tap Keep')));
      expect(render(files, uaSamsung), isNot(contains('Tap Keep')));
    });
  });

  test('sizes use decimal units like phones do', () {
    final s = GuestStrings.english;
    expect(formatSize(999, s), '999 bytes');
    expect(formatSize(1000, s), '1.0 kB');
    expect(formatSize(3200000, s), '3.2 MB');
    expect(formatSize(245000000, s), '245 MB');
    expect(formatSize(1400000000, s), '1.4 GB');
    expect(formatSize(5 * 1024 * 1024 * 1024, s), '5.4 GB');
  });

  test('the Chrome safe list matches Chromium', () {
    // Guard against accidental edits; see guest_page.dart for the source.
    expect(chromeSafeExtensions, hasLength(26));
    expect(chromeSafeExtensions, containsAll(['jpg', 'mp4', 'mov']));
    expect(chromeSafeExtensions, isNot(contains('heic')));
    expect(chromeSafeExtensions, isNot(contains('pdf')));
  });

  test('the expired page has no session details', () {
    final html = renderMessagePage(
        title: 'This link has expired', body: 'Ask again.', strings: GuestStrings.english);
    expect(html, isNot(contains('<script')));
    expect(html, isNot(contains('href')));
  });
}
