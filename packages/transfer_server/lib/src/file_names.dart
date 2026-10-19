import 'dart:convert';
import 'dart:io';

const _forbidden = '<>:"|?*';

const _windowsReserved = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// Longest name we create, in UTF-8 bytes. Most file systems allow 255.
const maxNameBytes = 200;

/// Turns a name chosen by a guest into a safe file name for any host
/// platform: one path segment, no control or bidi characters, nothing
/// Windows rejects, at most [maxNameBytes] bytes, never empty.
String sanitizeFileName(String raw) {
  // Keep only the last path segment, for both separators.
  var name = raw.split(RegExp(r'[/\\]')).last;

  final out = StringBuffer();
  for (final rune in name.runes) {
    if (rune < 0x20 || (rune >= 0x7f && rune <= 0x9f)) continue;
    if (_isBidiControl(rune)) continue;
    if (rune < 0x80 && _forbidden.contains(String.fromCharCode(rune))) continue;
    out.writeCharCode(rune);
  }
  name = out.toString().trim();
  // Windows drops trailing dots and spaces; a name of only dots is a path.
  name = name.replaceFirst(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) return 'file';
  // No hidden files.
  if (name.startsWith('.')) name = '_${name.replaceFirst(RegExp(r'^\.+'), '')}';

  final stem = name.split('.').first.toLowerCase().trimRight();
  if (_windowsReserved.contains(stem)) name = '_$name';

  return _capBytes(name);
}

bool _isBidiControl(int rune) =>
    rune == 0x200e ||
    rune == 0x200f ||
    rune == 0x061c ||
    (rune >= 0x202a && rune <= 0x202e) ||
    (rune >= 0x2066 && rune <= 0x2069) ||
    rune == 0xfeff;

/// Shortens [name] to [maxNameBytes] UTF-8 bytes, keeping a short extension.
String _capBytes(String name, [int max = maxNameBytes]) {
  if (utf8.encode(name).length <= max) return name;
  final dot = name.lastIndexOf('.');
  var ext = dot > 0 ? name.substring(dot) : '';
  if (utf8.encode(ext).length > 16) ext = '';
  final stem = ext.isEmpty ? name : name.substring(0, dot);
  final budget = max - utf8.encode(ext).length;
  final runes = stem.runes.toList();
  var bytes = 0;
  var keep = 0;
  for (final rune in runes) {
    final size = utf8.encode(String.fromCharCode(rune)).length;
    if (bytes + size > budget) break;
    bytes += size;
    keep++;
  }
  return '${String.fromCharCodes(runes.take(keep)).trimRight()}$ext';
}

/// A name based on [name] that does not exist yet in [dir] and is not in
/// [taken] (compared ignoring case, as on macOS and Windows): "a.jpg",
/// then "a (1).jpg", "a (2).jpg"… The chosen name is added to [taken].
String uniqueName(Directory dir, String name, Set<String> taken) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var candidate = name;
  for (var n = 1;; n++) {
    final free = !taken.contains(candidate.toLowerCase()) &&
        FileSystemEntity.typeSync('${dir.path}/$candidate',
                followLinks: false) ==
            FileSystemEntityType.notFound;
    if (free) break;
    candidate = _capBytes('$stem ($n)$ext');
    if (candidate == name) candidate = '$n$ext';
  }
  taken.add(candidate.toLowerCase());
  return candidate;
}

/// The path for [name] inside [dir], or null if it would land anywhere
/// else. A last line of defence after [sanitizeFileName].
String? containedPath(Directory dir, String name) {
  if (name.isEmpty || name == '.' || name == '..') return null;
  if (name.contains('/') || name.contains('\\') || name.contains('\x00')) {
    return null;
  }
  final base = dir.absolute.path;
  final path = '$base${Platform.pathSeparator}$name';
  final parent = File(path).parent.absolute.path;
  return parent == base ? path : null;
}
