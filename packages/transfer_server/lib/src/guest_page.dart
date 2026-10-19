import 'guest_strings.dart';
import 'shared_file.dart';
import 'user_agent.dart';

/// File extensions Chrome downloads over plain HTTP without its
/// "File can’t be downloaded securely" prompt. Copied from Chromium's
/// chrome/browser/download/insecure_download_blocking.cc (kSafeExtensions).
const chromeSafeExtensions = {
  'txt', 'css', 'json', 'csv', 'tsv', //
  'jpg', 'jpeg', 'png', 'gif', 'tif', 'tiff', 'ico', 'webp', 'avif', //
  'aac', 'midi', 'ogg', 'wav', 'webm', 'mp3', 'mp4', 'm4a', 'flac', 'mpeg',
  'mov', 'wmv',
};

/// The lower-case extension of [name] without the dot, or '' if none.
String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// "3.2 MB", "245 MB", "1.4 GB" (decimal units, as phones show them).
String formatSize(int bytes, GuestStrings s) {
  if (bytes < 1000) return s.get('size_bytes', {'n': bytes});
  const units = ['size_kb', 'size_mb', 'size_gb'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final text =
      value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
  return s.get(units[unit], {'n': text});
}

/// Shortens long names in the middle, keeping the start and the extension.
String shortenMiddle(String name, {int max = 60}) {
  final runes = name.runes.toList();
  if (runes.length <= max) return name;
  const tail = 16;
  final head = max - tail - 1;
  return '${String.fromCharCodes(runes.take(head))}…'
      '${String.fromCharCodes(runes.skip(runes.length - tail))}';
}

/// Escapes text for HTML element content and quoted attribute values.
String escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// Which "where does the file go" text to show this guest.
String whereKey(GuestDevice d) {
  final inApp =
      d.browser == GuestBrowser.webView || d.browser == GuestBrowser.googleApp;
  switch (d.platform) {
    case GuestPlatform.ios:
      if (inApp) return 'where_in_app_browser';
      return d.browser == GuestBrowser.safari
          ? 'where_ios_safari'
          : 'where_ios_other';
    case GuestPlatform.android:
      if (inApp) return 'where_in_app_browser';
      return switch (d.browser) {
        GuestBrowser.chrome => 'where_android_chrome',
        GuestBrowser.samsungInternet => 'where_android_samsung',
        _ => 'where_android_other',
      };
    case GuestPlatform.mac:
    case GuestPlatform.other:
      return 'where_computer';
  }
}

/// The page a guest sees when the host is sending files.
///
/// Works without JavaScript: every download is a plain link, and the "where
/// does it go" text is chosen on the server. The script (ES5 only, for old
/// browsers) adds a "Downloading…" status, a connection banner and the
/// iPadOS fix.
String renderSendPage({
  required List<SharedFile> files,
  required GuestStrings strings,
  required GuestDevice device,
  required String nonce,
}) {
  final s = strings;
  final total = files.fold<int>(0, (sum, f) => sum + f.length);
  final needsKeepHint = device.usesChromeDownloads &&
      files.any((f) => !chromeSafeExtensions.contains(extensionOf(f.name)));

  final items = StringBuffer();
  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    final ext = extensionOf(f.name);
    final badge = ext.isEmpty
        ? 'FILE'
        : (ext.length > 4 ? ext.substring(0, 4) : ext).toUpperCase();
    final href = 'f/$i/${Uri.encodeComponent(f.name)}';
    items.write('<li class="card">'
        '<div class="row"><span class="badge">${escapeHtml(badge)}</span>'
        '<div class="meta"><div class="name" title="${escapeHtml(f.name)}">'
        '${escapeHtml(shortenMiddle(f.name))}</div>'
        '<div class="size">${escapeHtml(formatSize(f.length, s))}</div></div></div>'
        '<a class="dl" href="${escapeHtml(href)}" download data-s="s$i">'
        '${escapeHtml(s.get('download_button'))}</a>'
        '<p class="status" id="s$i" aria-live="polite"></p>'
        '</li>');
  }

  final ipadText = device.platform == GuestPlatform.mac
      ? ' data-ipad="${escapeHtml(s.get('where_ios_safari'))}"'
      : '';
  final heading = files.isEmpty
      ? s.get('send_empty')
      : s.plural('send_heading', files.length);

  return '<!DOCTYPE html>'
      '<html lang="${s.languageCode}"><head>'
      '<meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<meta name="referrer" content="no-referrer">'
      '<meta name="color-scheme" content="light dark">'
      '<title>${escapeHtml(s.get('page_title'))}</title>'
      '<style>$_css</style></head>'
      '<body data-started="${escapeHtml(s.get('download_started'))}"'
      ' data-lost="${escapeHtml(s.get('connection_lost'))}"'
      ' data-ended="${escapeHtml(s.get('session_ended'))}"$ipadText>'
      '<div id="banner" class="banner hidden" role="status"></div>'
      '<main class="wrap">'
      '<h1>${escapeHtml(heading)}</h1>'
      '${files.isEmpty ? '' : '<p class="sub">${escapeHtml(s.get('send_total', {'size': formatSize(total, s)}))}'
          ' · ${escapeHtml(s.get('send_tap_download'))}</p>'}'
      '<p class="note" id="where">${escapeHtml(s.get(whereKey(device)))}</p>'
      '${needsKeepHint ? '<p class="note warn">${escapeHtml(s.get('chrome_keep_hint'))}</p>' : ''}'
      '<ul class="files">$items</ul>'
      '${files.isEmpty ? '' : '<p class="foot">${escapeHtml(s.get('keep_page_open'))}</p>'}'
      '<p class="foot small">${escapeHtml(s.get('footer'))}</p>'
      '</main>'
      '<script nonce="$nonce">$_script</script>'
      '</body></html>';
}

/// A minimal page with a title and one line of text: expired links,
/// not-found, and similar. Reveals nothing about the session.
String renderMessagePage({
  required String title,
  required String body,
  required GuestStrings strings,
}) {
  return '<!DOCTYPE html>'
      '<html lang="${strings.languageCode}"><head>'
      '<meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<meta name="referrer" content="no-referrer">'
      '<meta name="color-scheme" content="light dark">'
      '<title>${escapeHtml(strings.get('page_title'))}</title>'
      '<style>$_css</style></head><body><main class="wrap">'
      '<h1>${escapeHtml(title)}</h1>'
      '<p class="sub">${escapeHtml(body)}</p>'
      '</main></body></html>';
}

// Inline CSS. Flexbox only (no grid, no custom properties) so Chrome on
// Android 8 and Safari on iOS 13 render it the same as current browsers.
const _css = '''
html{-webkit-text-size-adjust:100%}
body{margin:0;background:#f4f5f7;color:#16181d;font:17px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif}
.wrap{max-width:560px;margin:0 auto;padding:20px 16px 32px}
h1{font-size:26px;line-height:1.2;margin:8px 0 6px}
.sub{margin:0 0 14px;color:#4a505c}
.note{margin:0 0 12px;padding:12px 14px;border-radius:12px;background:#e7eefc;color:#1d3a75}
.note.warn{background:#fff3d6;color:#5c4100}
.files{list-style:none;margin:16px 0 0;padding:0}
.card{background:#fff;border-radius:16px;padding:14px;margin:0 0 12px;box-shadow:0 1px 2px rgba(0,0,0,.08)}
.row{display:-webkit-box;display:-webkit-flex;display:flex;-webkit-align-items:center;align-items:center}
.badge{-webkit-flex:none;flex:none;width:52px;height:52px;line-height:52px;margin-right:12px;border-radius:12px;background:#e7eefc;color:#1a4fd0;font-size:13px;font-weight:700;text-align:center;letter-spacing:.5px}
.meta{-webkit-flex:1;flex:1;min-width:0}
.name{font-weight:600;word-wrap:break-word;overflow-wrap:break-word;word-break:break-word}
.size{color:#5d6470;font-size:15px}
a.dl{display:block;margin-top:12px;padding:16px;border-radius:12px;background:#1a56db;color:#fff;text-align:center;text-decoration:none;font-weight:700;font-size:18px}
a.dl:active{background:#1646b3}
.status{margin:8px 2px 0;font-size:15px;color:#1a7f37;display:none}
.status.on{display:block}
.foot{margin:18px 0 0;color:#4a505c}
.small{font-size:14px;color:#6b7280}
.banner{position:-webkit-sticky;position:sticky;top:0;z-index:9;padding:12px 16px;background:#b42318;color:#fff;font-weight:600;text-align:center}
.banner.ended{background:#3b3f46}
.hidden{display:none}
@media (prefers-color-scheme:dark){
body{background:#0f1115;color:#e7e9ee}
.sub,.foot{color:#a9afbb}.small,.size{color:#8d94a1}
.note{background:#1b2a4a;color:#cddcff}.note.warn{background:#3d3010;color:#ffe3a3}
.card{background:#1b1e24;box-shadow:none}
.badge{background:#1b2a4a;color:#9dbbff}
a.dl{background:#3b6fe8}a.dl:active{background:#2f5bc4}
.status{color:#5fd07a}
}
''';

// ES5 only: no let/const, arrow functions, template literals, fetch or
// Promise. A test enforces this.
const _script = '''
(function(){
var b=document.body,banner=document.getElementById('banner'),where=document.getElementById('where');
if(where&&b.getAttribute('data-ipad')&&navigator.maxTouchPoints>1){where.textContent=b.getAttribute('data-ipad');}
var links=document.getElementsByTagName('a');
for(var i=0;i<links.length;i++){
if((' '+links[i].className+' ').indexOf(' dl ')<0)continue;
links[i].onclick=function(){var s=document.getElementById(this.getAttribute('data-s'));if(s){s.textContent=b.getAttribute('data-started')+(where?' '+where.textContent:'');s.className='status on';}};
}
function show(text,ended){banner.textContent=text;banner.className=ended?'banner ended':'banner';}
var failures=0,stopped=false;
function ping(){
if(stopped)return;
var x=new XMLHttpRequest();
x.open('GET','status?t='+new Date().getTime(),true);
x.timeout=4000;
x.onreadystatechange=function(){
if(x.readyState!==4)return;
if(x.status===200){failures=0;banner.className='banner hidden';}
else if(x.status===404){stopped=true;show(b.getAttribute('data-ended'),true);return;}
else{failures++;if(failures>=2)show(b.getAttribute('data-lost'),false);}
setTimeout(ping,5000);
};
x.send();
}
setTimeout(ping,5000);
})();
''';

/// The inline script, exposed for tests.
const guestPageScriptForTest = _script;
