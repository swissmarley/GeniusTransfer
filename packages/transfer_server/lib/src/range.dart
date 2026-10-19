/// The byte range to send for a download, decided from the request's
/// `Range` and `If-Range` headers (RFC 9110 §14).
sealed class RangeDecision {
  const RangeDecision();
}

/// Send the whole file with status 200.
final class FullContent extends RangeDecision {
  const FullContent();
}

/// Send bytes [start, end) with status 206.
final class PartialContent extends RangeDecision {
  const PartialContent(this.start, this.end);
  final int start;

  /// Exclusive.
  final int end;
}

/// Reply 416 with `Content-Range: bytes */<size>`.
final class Unsatisfiable extends RangeDecision {
  const Unsatisfiable();
}

/// Decides what to send for a file of [size] bytes.
///
/// Only a single range is supported. A request for several ranges gets the
/// whole file, which the spec allows. Malformed headers are ignored (whole
/// file), as the spec requires. `If-Range` must match [etag] exactly (strong
/// comparison) or [lastModified] exactly; otherwise the whole file is sent.
RangeDecision decideRange({
  required String? rangeHeader,
  required int size,
  String? ifRange,
  String? etag,
  String? lastModified,
}) {
  if (rangeHeader == null) return const FullContent();
  if (ifRange != null) {
    final value = ifRange.trim();
    final matches = value.startsWith('"')
        ? value == etag
        : (lastModified != null && value == lastModified);
    if (!matches) return const FullContent();
  }

  final header = rangeHeader.trim();
  final eq = header.indexOf('=');
  if (eq < 0) return const FullContent();
  if (header.substring(0, eq).trim().toLowerCase() != 'bytes') {
    return const FullContent();
  }
  final spec = header.substring(eq + 1).trim();
  if (spec.contains(',')) return const FullContent();

  final dash = spec.indexOf('-');
  if (dash < 0) return const FullContent();
  final first = spec.substring(0, dash).trim();
  final last = spec.substring(dash + 1).trim();

  if (first.isEmpty) {
    // Suffix range: the last N bytes.
    final n = _parseDigits(last);
    if (n == null) return const FullContent();
    if (n == 0 || size == 0) return const Unsatisfiable();
    final start = n >= size ? 0 : size - n;
    return PartialContent(start, size);
  }

  final start = _parseDigits(first);
  if (start == null) return const FullContent();
  int end;
  if (last.isEmpty) {
    end = size;
  } else {
    final lastByte = _parseDigits(last);
    if (lastByte == null || lastByte < start) return const FullContent();
    end = lastByte + 1 > size ? size : lastByte + 1;
  }
  if (start >= size) return const Unsatisfiable();
  return PartialContent(start, end);
}

/// Parses a non-negative decimal integer made only of ASCII digits. Rejects
/// signs, spaces and values too large to be a real file offset.
int? _parseDigits(String s) {
  if (s.isEmpty || s.length > 18) return null;
  for (final c in s.codeUnits) {
    if (c < 0x30 || c > 0x39) return null;
  }
  return int.parse(s);
}
