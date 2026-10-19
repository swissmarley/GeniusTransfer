import 'package:mime/mime.dart';

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

/// Whether [name] is a HEIC/HEIF photo (iPhone camera format).
bool isHeic(String name) {
  final ext = extensionOf(name);
  return ext == 'heic' || ext == 'heif';
}

/// "IMG_0412.HEIC" → "IMG_0412.jpg".
String jpegName(String name) {
  final dot = name.lastIndexOf('.');
  return '${dot > 0 ? name.substring(0, dot) : name}.jpg';
}

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
  bool jpegCopies = false,
}) {
  final s = strings;
  final total = files.fold<int>(0, (sum, f) => sum + f.length);
  // Apple devices open HEIC; others may not, so offer a JPEG copy.
  final apple = device.platform == GuestPlatform.ios ||
      device.platform == GuestPlatform.mac;
  bool offerJpeg(SharedFile f) => jpegCopies && !apple && isHeic(f.name);
  final heicHint = files.any(offerJpeg);
  final needsKeepHint = device.usesChromeDownloads &&
      files.any((f) => !chromeSafeExtensions.contains(extensionOf(f.name)));
  // Downloads on an iPhone go to Files. Photos and videos get an extra
  // "Open" link: shown in Safari, they can be saved to Photos from there.
  bool forPhotos(SharedFile f) {
    if (device.platform != GuestPlatform.ios) return false;
    final type = lookupMimeType(f.name) ?? '';
    return type.startsWith('image/') || type.startsWith('video/');
  }

  final photosHint = files.any(forPhotos);

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
        '${forPhotos(f) ? '<a class="view" href="${escapeHtml('v/$i/${Uri.encodeComponent(f.name)}')}">${escapeHtml(s.get('view_button'))}</a>' : ''}'
        '${offerJpeg(f) ? '<a class="view" href="${escapeHtml('j/$i/${Uri.encodeComponent(jpegName(f.name))}')}" download>${escapeHtml(s.get('jpg_button'))}</a>' : ''}'
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
      '${photosHint ? '<p class="note">${escapeHtml(s.get('ios_photos_hint'))}</p>' : ''}'
      '${heicHint ? '<p class="note">${escapeHtml(s.get('heic_hint'))}</p>' : ''}'
      '<ul class="files">$items</ul>'
      '${files.isEmpty ? '' : '<p class="foot">${escapeHtml(s.get('keep_page_open'))}</p>'}'
      '<p class="foot small">${escapeHtml(s.get('footer'))}</p>'
      '</main>'
      '<script nonce="$nonce">$_script</script>'
      '</body></html>';
}

/// Asks for the session PIN. A plain form: works without JavaScript.
String renderPinPage({
  required GuestStrings strings,
  required String action,
  required String? error,
  required bool locked,
}) {
  final s = strings;
  final form = locked
      ? ''
      : '<form method="post" action="${escapeHtml(action)}">'
          '<label class="pick" for="pin">${escapeHtml(s.get('pin_label'))}</label>'
          '<input id="pin" class="picker pin" name="pin" type="text" '
          'inputmode="numeric" pattern="[0-9]*" autocomplete="one-time-code" '
          'maxlength="8" autofocus required>'
          '<button class="dl" type="submit">${escapeHtml(s.get('pin_button'))}</button>'
          '</form>';
  return '<!DOCTYPE html>'
      '<html lang="${s.languageCode}"><head>'
      '<meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<meta name="referrer" content="no-referrer">'
      '<meta name="color-scheme" content="light dark">'
      '<title>${escapeHtml(s.get('page_title'))}</title>'
      '<style>$_css</style></head><body><main class="wrap">'
      '<h1>${escapeHtml(s.get('pin_title'))}</h1>'
      '<p class="sub">${escapeHtml(s.get('pin_body'))}</p>'
      '${error == null ? '' : '<p class="note warn" role="alert">${escapeHtml(error)}</p>'}'
      '$form'
      '</main></body></html>';
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

/// The page a guest sees when the host is receiving files.
///
/// Works without JavaScript: the form posts the files in one multipart
/// request and the host accepts them afterwards. With JavaScript (ES5
/// only), the page asks first, then sends file by file with progress.
String renderReceivePage({
  required GuestStrings strings,
  required String nonce,
  required int maxFiles,
  required int maxBytes,
}) {
  final s = strings;
  String data(String name, String text) => ' data-$name="${escapeHtml(text)}"';
  final attrs = StringBuffer()
    ..write(data('pick-first', s.get('receive_pick_first')))
    ..write(data('waiting', s.get('receive_waiting')))
    ..write(data('sending', s.get('receive_sending')))
    ..write(data('file-done', s.get('receive_file_done')))
    ..write(data('done-one', s.get('receive_done_one')))
    ..write(data('done-other', s.get('receive_done_other')))
    ..write(data('declined', s.get('receive_declined')))
    ..write(data('expired', s.get('receive_expired')))
    ..write(data('busy', s.get('receive_busy')))
    ..write(data('too-many', s.get('receive_too_many', {'count': maxFiles})))
    ..write(data('too-large',
        s.get('receive_too_large', {'size': formatSize(maxBytes, s)})))
    ..write(data('no-space', s.get('receive_no_space')))
    ..write(data('failed', s.get('receive_failed')))
    ..write(data('max-files', '$maxFiles'))
    ..write(data('max-bytes', '$maxBytes'))
    ..write(data('u-b', s.get('size_bytes')))
    ..write(data('u-kb', s.get('size_kb')))
    ..write(data('u-mb', s.get('size_mb')))
    ..write(data('u-gb', s.get('size_gb')));

  return '<!DOCTYPE html>'
      '<html lang="${s.languageCode}"><head>'
      '<meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<meta name="referrer" content="no-referrer">'
      '<meta name="color-scheme" content="light dark">'
      '<title>${escapeHtml(s.get('page_title'))}</title>'
      '<style>$_css</style></head>'
      '<body$attrs>'
      '<main class="wrap">'
      '<h1>${escapeHtml(s.get('receive_heading'))}</h1>'
      '<p class="sub">${escapeHtml(s.get('receive_sub'))}</p>'
      '<form id="form" method="post" action="u" enctype="multipart/form-data">'
      '<label class="pick" for="pick">${escapeHtml(s.get('receive_choose'))}</label>'
      '<input id="pick" class="picker" type="file" name="f" multiple>'
      '<button class="dl" id="send" type="submit">'
      '${escapeHtml(s.get('receive_send_button'))}</button>'
      '</form>'
      '<p class="note hidden" id="msg" role="status" aria-live="polite"></p>'
      '<ul class="files" id="list"></ul>'
      '<p class="foot small">${escapeHtml(s.get('footer'))}</p>'
      '</main>'
      '<script nonce="$nonce">$_receiveScript</script>'
      '</body></html>';
}

/// The no-JavaScript upload result page. While [refresh] is true it reloads
/// itself every few seconds to show the host's decision.
String renderWaitPage({
  required String title,
  required String body,
  required bool refresh,
  required GuestStrings strings,
}) {
  return '<!DOCTYPE html>'
      '<html lang="${strings.languageCode}"><head>'
      '<meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<meta name="referrer" content="no-referrer">'
      '<meta name="color-scheme" content="light dark">'
      '${refresh ? '<meta http-equiv="refresh" content="3">' : ''}'
      '<title>${escapeHtml(strings.get('page_title'))}</title>'
      '<style>$_css</style></head><body><main class="wrap">'
      '<h1>${escapeHtml(title)}</h1>'
      '${body.isEmpty ? '' : '<p class="sub">${escapeHtml(body)}</p>'}'
      '${refresh ? '' : '<a class="dl" href="../">${escapeHtml(strings.get('receive_more'))}</a>'}'
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
a.dl,button.dl{display:block;margin-top:12px;padding:16px;border-radius:12px;background:#1a56db;color:#fff;text-align:center;text-decoration:none;font-weight:700;font-size:18px}
a.dl:active,button.dl:active{background:#1646b3}
button.dl{width:100%;border:0;font-family:inherit;-webkit-appearance:none}
button.dl[disabled]{opacity:.5}
a.view{display:block;margin-top:8px;padding:12px;border-radius:12px;border:2px solid #1a56db;color:#1a56db;text-align:center;text-decoration:none;font-weight:600}
.pin{font-size:26px;letter-spacing:6px;text-align:center;border-style:solid}
form{margin:0 0 14px}
.pick{display:block;margin:16px 0 6px;font-weight:600}
.picker{display:block;width:100%;box-sizing:border-box;padding:14px;border:2px dashed #b8c2d6;border-radius:12px;background:#fff;font-size:16px}
.bar{height:6px;margin-top:10px;border-radius:3px;background:#e3e6eb;overflow:hidden}
.fill{height:6px;width:0;background:#1a56db}
.note.ok{background:#e3f6e8;color:#14532d}
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
a.dl,button.dl{background:#3b6fe8}a.dl:active,button.dl:active{background:#2f5bc4}
a.view{border-color:#9dbbff;color:#9dbbff}
.picker{background:#1b1e24;border-color:#3a4150;color:#e7e9ee}
.bar{background:#2a2e36}.fill{background:#3b6fe8}
.note.ok{background:#12301c;color:#a6e9b9}
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

// ES5 only, like the send page script.
const _receiveScript = '''
(function(){
var b=document.body,form=document.getElementById('form'),pick=document.getElementById('pick'),btn=document.getElementById('send'),msg=document.getElementById('msg'),list=document.getElementById('list');
if(!form||!pick||!window.XMLHttpRequest||!window.JSON||!pick.files)return;
var busy=false,rows=[];
function t(k){return b.getAttribute('data-'+k)||'';}
function say(text,kind){msg.textContent=text;msg.className=text?'note'+(kind?' '+kind:''):'note hidden';}
function finish(text,kind){busy=false;btn.disabled=false;say(text,kind);}
function fmt(n){if(n<1000)return t('u-b').replace('{n}',n);var u=['u-kb','u-mb','u-gb'],v=n/1000,i=0;while(v>=1000&&i<2){v/=1000;i++;}return t(u[i]).replace('{n}',v>=100?Math.round(v):v.toFixed(1));}
function req(method,url,body,timeout,done){
var x=new XMLHttpRequest();x.open(method,url,true);x.timeout=timeout;
x.onreadystatechange=function(){if(x.readyState!==4)return;var data=null;try{data=JSON.parse(x.responseText);}catch(e){}done(x.status,data);};
if(body!==null)x.setRequestHeader('Content-Type','application/json');
x.send(body);
}
function el(tag,cls,text){var e=document.createElement(tag);e.className=cls;if(text)e.textContent=text;return e;}
function draw(files){
list.innerHTML='';rows=[];
for(var i=0;i<files.length;i++){
var li=el('li','card'),bar=el('div','bar'),fill=el('div','fill'),st=el('p','status');
li.appendChild(el('div','name',files[i].name));li.appendChild(el('div','size',fmt(files[i].size)));
bar.appendChild(fill);li.appendChild(bar);li.appendChild(st);list.appendChild(li);
rows.push({fill:fill,st:st});
}
}
function errorText(code){return t(code==='busy'?'busy':code==='too_many_files'?'too-many':code==='too_large'?'too-large':code==='no_space'?'no-space':'failed');}
form.onsubmit=function(){
if(busy)return false;
var files=pick.files,chosen=[],offer=[],total=0,i;
if(!files||!files.length){say(t('pick-first'),'warn');return false;}
for(i=0;i<files.length;i++){chosen.push(files[i]);total+=files[i].size;offer.push({name:files[i].name,size:files[i].size,type:files[i].type||''});}
if(chosen.length>parseInt(t('max-files'),10)){say(t('too-many'),'warn');return false;}
if(total>parseFloat(t('max-bytes'))){say(t('too-large'),'warn');return false;}
busy=true;btn.disabled=true;draw(chosen);say(t('waiting'));
req('POST','offer',JSON.stringify({files:offer}),15000,function(status,data){
if(status===200&&data&&data.id){wait(data.id,chosen,0);return;}
finish(errorText(data&&data.error),'warn');
});
return false;
};
function wait(id,files,fails){
req('GET','offer/'+id+'?t='+new Date().getTime(),null,40000,function(status,data){
if(status===200&&data){
if(data.state==='pending'){wait(id,files,0);return;}
if(data.state==='accepted'||data.state==='done'){say(t('sending'));send(id,files,0,data.received||[],0);return;}
finish(t(data.state==='declined'?'declined':data.state==='expired'?'expired':'failed'),'warn');return;
}
if(status===0&&fails<5){setTimeout(function(){wait(id,files,fails+1);},2000);return;}
finish(t('failed'),'warn');
});
}
function has(a,v){for(var i=0;i<a.length;i++){if(a[i]===v)return true;}return false;}
function sent(row){row.fill.style.width='100%';row.st.textContent=t('file-done');row.st.className='status on';}
function send(id,files,i,done,fails){
if(i>=files.length){pick.value='';finish(files.length===1?t('done-one'):t('done-other').replace('{count}',files.length),'ok');return;}
var row=rows[i];
if(has(done,i)){sent(row);send(id,files,i+1,done,0);return;}
var x=new XMLHttpRequest();
x.open('POST','u/'+id+'/'+i,true);
if(x.upload)x.upload.onprogress=function(e){if(e.lengthComputable&&e.total>0)row.fill.style.width=Math.floor(e.loaded*100/e.total)+'%';};
x.onreadystatechange=function(){
if(x.readyState!==4)return;
if(x.status===200||x.status===409){sent(row);send(id,files,i+1,done,0);return;}
if(x.status===0&&fails<3){setTimeout(function(){send(id,files,i,done,fails+1);},2000);return;}
finish(t('failed'),'warn');
};
x.setRequestHeader('Content-Type','application/octet-stream');
x.send(files[i]);
}
})();
''';

/// The receive page script, exposed for tests.
const receivePageScriptForTest = _receiveScript;
