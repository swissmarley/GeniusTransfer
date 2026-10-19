import 'dart:math';

/// RFC 4648 base32 alphabet. Upper case only, so the whole URL fits the
/// QR "alphanumeric" mode, which gives smaller, easier-to-scan codes.
const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Number of base32 characters in a session token: 26 × 5 = 130 bits.
const tokenLength = 26;

/// Returns a new unguessable session token (130 random bits, base32).
String generateToken([Random? random]) {
  final rng = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < tokenLength; i++) {
    buffer.write(_base32Alphabet[rng.nextInt(_base32Alphabet.length)]);
  }
  return buffer.toString();
}

/// Compares a token taken from a request path with the session token.
///
/// Case-insensitive (the QR code uses upper case, but people may type lower
/// case) and constant-time for equal lengths, so response timing does not
/// reveal how many leading characters were right.
bool tokenMatches(String candidate, String token) {
  if (candidate.length != token.length) return false;
  final a = candidate.toUpperCase();
  var diff = 0;
  for (var i = 0; i < token.length; i++) {
    diff |= a.codeUnitAt(i) ^ token.codeUnitAt(i);
  }
  return diff == 0;
}
