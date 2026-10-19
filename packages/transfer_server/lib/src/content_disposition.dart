import 'dart:convert';

/// Builds a `Content-Disposition` header value (RFC 6266) for [fileName]:
/// an ASCII-only `filename` for old browsers plus an RFC 8187 `filename*`
/// with the exact UTF-8 name.
String contentDisposition(String fileName, {bool inline = false}) {
  final type = inline ? 'inline' : 'attachment';
  return '$type; filename="${asciiFallbackName(fileName)}"; '
      "filename*=UTF-8''${encodeRfc8187(fileName)}";
}

/// Replaces anything outside printable ASCII, plus quote and backslash,
/// with `_`, keeping the extension readable.
String asciiFallbackName(String name) {
  final out = StringBuffer();
  for (final rune in name.runes) {
    final ok = rune >= 0x20 && rune < 0x7f && rune != 0x22 && rune != 0x5c;
    out.write(ok ? String.fromCharCode(rune) : '_');
  }
  final s = out.toString().trim();
  return s.isEmpty ? 'file' : s;
}

/// Percent-encodes [value] as an RFC 8187 `value-chars` string.
String encodeRfc8187(String value) {
  const attrChars = "!#\$&+-.^_`|~";
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final isAlnum = (byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a);
    if (isAlnum || attrChars.codeUnits.contains(byte)) {
      out.writeCharCode(byte);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}
