part of 'server.dart';

/// Wrong PINs allowed per session before it stops accepting any.
const maxPinAttempts = 5;

const _pinCookie = 'gt_pin';

extension _Pin on TransferServer {
  /// Whether [request] carries the cookie given out for the right PIN.
  bool _pinAccepted(HttpRequest request) {
    if (pin == null) return true;
    try {
      return request.cookies
          .any((c) => c.name == _pinCookie && _pinGrants.contains(c.value));
    } on HttpException {
      return false; // A malformed Cookie header.
    }
  }

  /// Everything under the token needs the PIN first. Script requests get a
  /// JSON error; anything else gets the PIN page.
  Future<void> _requirePin(HttpRequest request, String tokenSegment,
      List<String> rest, GuestStrings strings) async {
    if (rest.length == 1 && rest.first == 'pin') {
      if (request.method != 'POST') {
        return _sendPinPage(request, strings, tokenSegment);
      }
      return _checkPin(request, strings, tokenSegment);
    }
    final wantsJson = rest.first == 'status' ||
        rest.first == 'offer' ||
        (rest.first == 'u' && rest.length == 3);
    if (wantsJson) {
      final response = request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..persistentConnection = request.method != 'POST';
      return _writeBody(response, utf8.encode('{"error":"pin"}'),
          head: request.method == 'HEAD');
    }
    return _sendPinPage(request, strings, tokenSegment);
  }

  Future<void> _checkPin(
      HttpRequest request, GuestStrings strings, String tokenSegment) async {
    if (_pinFailures >= maxPinAttempts) {
      return _sendPinPage(request, strings, tokenSegment,
          status: HttpStatus.forbidden);
    }
    final body = await _readPinForm(request);
    // Other guesses may have arrived while this body was being read.
    if (_pinFailures >= maxPinAttempts) {
      return _sendPinPage(request, strings, tokenSegment,
          status: HttpStatus.forbidden);
    }
    final entered = (body == null ? '' : body['pin'] ?? '').trim();
    if (_sameDigits(entered, pin!)) {
      final grant = _nonce();
      _pinGrants.add(grant);
      final response = request.response
        ..statusCode = HttpStatus.seeOther
        ..headers.set(HttpHeaders.locationHeader, '/$tokenSegment/');
      // Scoped to this session's path; gone when the browser closes.
      response.cookies.add(Cookie(_pinCookie, grant)
        ..path = '/$tokenSegment/'
        ..httpOnly = true
        ..sameSite = SameSite.lax);
      return _writeBody(response, const [], head: true);
    }
    _pinFailures++;
    final left = maxPinAttempts - _pinFailures;
    final remote = request.connectionInfo?.remoteAddress.address ?? '';
    _emit(PinRejected(remote, left));
    if (left == 0) _emit(const PinLockedOut());
    return _sendPinPage(request, strings, tokenSegment,
        status: left == 0 ? HttpStatus.forbidden : HttpStatus.unauthorized,
        wrong: true);
  }

  Future<void> _sendPinPage(
      HttpRequest request, GuestStrings strings, String tokenSegment,
      {int status = HttpStatus.unauthorized, bool wrong = false}) {
    final left = maxPinAttempts - _pinFailures;
    final html = renderPinPage(
      strings: strings,
      action: '/$tokenSegment/pin',
      error: left <= 0
          ? strings.get('pin_locked')
          : wrong
              ? strings.plural('pin_wrong', left)
              : null,
      locked: left <= 0,
    );
    final response = request.response
      ..statusCode = left <= 0 ? HttpStatus.forbidden : status
      ..headers.contentType = ContentType.html
      ..headers.set('content-security-policy',
          "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; "
              "form-action 'self'; frame-ancestors 'none'");
    if (request.method == 'POST') response.persistentConnection = false;
    return _writeBody(response, utf8.encode(html),
        head: request.method == 'HEAD');
  }

  /// The fields of a small `application/x-www-form-urlencoded` body.
  Future<Map<String, String>?> _readPinForm(HttpRequest request) async {
    final bytes = await _readSmallBody(request, 1024);
    if (bytes == null) return null;
    try {
      return Uri.splitQueryString(ascii.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  /// Compares in constant time, so timing reveals nothing about the PIN.
  bool _sameDigits(String entered, String expected) {
    if (entered.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= entered.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }
}
