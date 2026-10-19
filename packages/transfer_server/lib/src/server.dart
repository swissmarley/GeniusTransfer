import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mime/mime.dart';

import 'content_disposition.dart';
import 'events.dart';
import 'file_names.dart';
import 'guest_page.dart';
import 'guest_strings.dart';
import 'net_util.dart';
import 'range.dart';
import 'receive.dart';
import 'shared_file.dart';
import 'token.dart';
import 'user_agent.dart';

part 'uploads.dart';

/// Tunables for a [TransferServer]. The defaults are the product defaults.
class ServerConfig {
  const ServerConfig({
    this.preferredPort = 8080,
    this.idleTimeout = const Duration(minutes: 30),
    this.idleCheckInterval = const Duration(seconds: 30),
    this.maxRequestsPerAddress = 8,
    this.maxRequestsTotal = 32,
    this.progressInterval = const Duration(milliseconds: 250),
  });

  /// Port tried first, so URLs look familiar. Not below 1024 and not on
  /// Chrome's blocked-port list. If it is taken, another port is used.
  final int preferredPort;

  /// End the session after this long without requests or transfers.
  final Duration idleTimeout;
  final Duration idleCheckInterval;

  /// Concurrent requests allowed from one guest address, and in total.
  final int maxRequestsPerAddress;
  final int maxRequestsTotal;

  /// Minimum time between [DownloadProgress] events for one download.
  final Duration progressInterval;
}

/// One sharing session: a plain-HTTP server that serves [files] and a guest
/// page under `/<token>/`, on the given LAN addresses only.
///
/// In [SessionMode.receive] it serves an upload page instead, and guests
/// can send files to the host after it accepts them (see [approveUpload]).
///
/// Every request must carry the session token as the first path segment.
/// Requests without it get a neutral "link expired" page that reveals
/// nothing about the session.
///
/// The server owns [files]: [stop] closes them.
class TransferServer {
  TransferServer({
    List<SharedFile> files = const [],
    String? token,
    this.config = const ServerConfig(),
    this.mode = SessionMode.send,
    this.receiveOptions,
  })  : files = List.unmodifiable(files),
        token = token ?? generateToken() {
    if (mode == SessionMode.receive && receiveOptions == null) {
      throw ArgumentError('A receiving session needs ReceiveOptions.');
    }
  }

  final List<SharedFile> files;
  final String token;
  final ServerConfig config;
  final SessionMode mode;
  final ReceiveOptions? receiveOptions;

  final _batches = <String, _Batch>{};
  final _runningUploads = <Future<void>>{};
  int _activeUploads = 0;

  final _events = StreamController<ServerEvent>.broadcast();
  final _listening = <HttpServer>[];
  final _draining = <HttpServer>[];
  final _inFlightByAddress = <String, int>{};
  final _seenGuests = <String>{};
  final _random = Random.secure();

  List<InternetAddress> _addresses = const [];
  Set<String> _allowedHosts = const {};
  int? _port;
  bool _stopped = false;
  Timer? _idleTimer;
  DateTime _lastActivity = DateTime.now();
  bool _idleReported = false;
  int _inFlightTotal = 0;
  int _activeDownloads = 0;
  int _nextDownloadId = 0;

  /// Session events for the host UI.
  Stream<ServerEvent> get events => _events.stream;

  /// The port in use, once started.
  int? get port => _port;

  /// The addresses the server listens on (or will listen on after resume).
  List<InternetAddress> get addresses => List.unmodifiable(_addresses);

  bool get isListening => _listening.isNotEmpty;
  bool get isStopped => _stopped;

  /// Downloads in progress.
  int get activeDownloads => _activeDownloads;

  /// Uploads in progress (receive mode).
  int get activeUploads => _activeUploads;

  /// The guest URL for the first address: `http://<ip>:<port>/<TOKEN>/`.
  Uri? get url => _addresses.isEmpty || _port == null
      ? null
      : urlFor(_addresses.first);

  Uri urlFor(InternetAddress address) => Uri(
      scheme: 'http', host: address.address, port: _port, path: '/$token/');

  /// Starts listening on [addresses] (normally one private IPv4 address).
  Future<void> start(List<InternetAddress> addresses) async {
    if (_stopped) throw StateError('This session has been stopped.');
    await _bind(addresses);
    _lastActivity = DateTime.now();
    _idleTimer ??=
        Timer.periodic(config.idleCheckInterval, (_) => _checkIdle());
  }

  /// Stops accepting new connections. Requests already running continue,
  /// so a download in progress can finish. Used when an iOS app goes to the
  /// background. Call [resume] to listen again.
  Future<void> suspend() async {
    final servers = List.of(_listening);
    _listening.clear();
    for (final server in servers) {
      _draining.add(server);
      unawaited(server.close().whenComplete(() => _draining.remove(server)));
    }
  }

  /// Closes every connection, including downloads still running.
  Future<void> dropConnections() async {
    final servers = [..._listening, ..._draining];
    _draining.clear();
    for (final server in servers) {
      await server.close(force: true);
    }
    _listening.removeWhere(servers.contains);
  }

  /// Listens again, on [addresses] (which may have changed). Keeps the same
  /// port when it is still free, so the QR code stays valid; otherwise picks
  /// another one, and [url] changes.
  Future<void> resume(List<InternetAddress> addresses) async {
    if (_stopped) throw StateError('This session has been stopped.');
    await _bind(addresses);
  }

  /// Accepts upload offer [id] (from an [UploadOffered] event). The guest
  /// then sends the files; or, if they are already here (quarantined), they
  /// are moved into place now. Returns false if the offer is not pending.
  Future<bool> approveUpload(String id) => _approve(id);

  /// Refuses upload offer [id] and deletes anything already received for
  /// it. Returns false if the offer is not pending.
  Future<bool> declineUpload(String id) => _decline(id);

  /// The folder where accepted files of batch [id] are written.
  Directory? uploadFolder(String id) {
    final options = receiveOptions;
    return options == null
        ? null
        : Directory('${options.stagingDir.path}/$id/files');
  }

  /// Ends the session: closes all connections and listeners, releases the
  /// files and invalidates the token. Not reversible.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _idleTimer?.cancel();
    for (final batch in _batches.values) {
      batch.timer?.cancel();
    }
    await dropConnections();
    await _cleanUpUploads();
    for (final file in files) {
      try {
        await file.close();
      } catch (_) {
        // Releasing one file must not prevent releasing the others.
      }
    }
    await _events.close();
  }

  Future<void> _bind(List<InternetAddress> addresses) async {
    if (addresses.isEmpty) throw ArgumentError('No address to listen on.');
    await suspend();
    final ports = <int>{
      ?_port,
      config.preferredPort,
      0, // Any free port.
    };
    Object? lastError;
    for (final candidate in ports) {
      final bound = <HttpServer>[];
      try {
        var port = candidate;
        for (final address in addresses) {
          final server = await HttpServer.bind(address, port);
          port = server.port;
          bound.add(server);
        }
        _port = port;
        _addresses = List.of(addresses);
        _allowedHosts = {for (final a in addresses) '${a.address}:$port'};
        for (final server in bound) {
          _configure(server);
          _listening.add(server);
          server.listen(_handle, onError: (Object _) {});
        }
        return;
      } on SocketException catch (e) {
        lastError = e;
        for (final server in bound) {
          await server.close(force: true);
        }
      }
    }
    throw lastError ?? StateError('Could not listen on any port.');
  }

  void _configure(HttpServer server) {
    server
      ..autoCompress = false
      ..idleTimeout = const Duration(seconds: 30)
      ..serverHeader = null;
    server.defaultResponseHeaders
      ..clear()
      ..set('x-content-type-options', 'nosniff')
      ..set('referrer-policy', 'no-referrer')
      ..set('cache-control', 'no-store');
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    // A guest that disconnects makes `done` fail; that is not an error here.
    unawaited(response.done.then((_) {}, onError: (Object _) {}));

    final remote = request.connectionInfo?.remoteAddress;
    if (_stopped || remote == null || !isLanAddress(remote)) {
      response.statusCode = HttpStatus.forbidden;
      return _closeQuietly(response);
    }
    // Only accept requests addressed to our own IP and port. This defeats
    // DNS rebinding: a web page elsewhere cannot make a guest's browser talk
    // to us under another host name.
    final host = request.headers.value(HttpHeaders.hostHeader)?.toLowerCase();
    if (host == null || !_allowedHosts.contains(host)) {
      response.statusCode = HttpStatus.badRequest;
      return _closeQuietly(response);
    }

    final key = remote.address;
    final perAddress = _inFlightByAddress[key] ?? 0;
    if (perAddress >= config.maxRequestsPerAddress ||
        _inFlightTotal >= config.maxRequestsTotal) {
      response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.set('retry-after', '2');
      return _closeQuietly(response);
    }
    _inFlightByAddress[key] = perAddress + 1;
    _inFlightTotal++;
    _touch();
    try {
      await _route(request, remote);
    } catch (_) {
      // Headers may already be sent; make sure the connection is released.
      await _closeQuietly(response);
    } finally {
      final left = (_inFlightByAddress[key] ?? 1) - 1;
      if (left <= 0) {
        _inFlightByAddress.remove(key);
      } else {
        _inFlightByAddress[key] = left;
      }
      _inFlightTotal--;
      _touch();
    }
  }

  Future<void> _route(HttpRequest request, InternetAddress remote) async {
    final strings = GuestStrings.forAcceptLanguage(
        request.headers.value(HttpHeaders.acceptLanguageHeader));
    final segments = request.uri.pathSegments;
    if (segments.isEmpty || !tokenMatches(segments.first, token)) {
      return _sendMessage(request, HttpStatus.notFound, strings,
          strings.get('expired_title'), strings.get('expired_body'));
    }

    final isGet = request.method == 'GET';
    final isHead = request.method == 'HEAD';
    final rest = segments.sublist(1);

    // "/TOKEN" without the slash: redirect, so relative links resolve.
    if (rest.isEmpty) {
      return _redirect(request, '/${segments.first}/');
    }
    if (rest.length == 1 && rest.first.isEmpty) {
      if (!isGet && !isHead) return _methodNotAllowed(request);
      _noteGuest(request, remote);
      if (mode == SessionMode.receive) {
        return _sendReceivePage(request, strings, head: isHead);
      }
      return _sendPage(request, strings, head: isHead);
    }
    if (mode == SessionMode.receive) {
      final handled = await _routeUpload(request, remote, rest, strings);
      if (handled) return;
    }
    if (rest.first == 'f' && (rest.length == 2 || rest.length == 3)) {
      final index = _parseIndex(rest[1]);
      if (index == null) {
        return _sendMessage(request, HttpStatus.notFound, strings,
            strings.get('not_found'), '');
      }
      if (!isGet && !isHead) return _methodNotAllowed(request);
      _noteGuest(request, remote);
      return _sendFile(request, index, remote, head: isHead);
    }
    if (rest.length == 1 && rest.first == 'status') {
      if (!isGet && !isHead) return _methodNotAllowed(request);
      return _sendStatus(request, head: isHead);
    }
    return _sendMessage(
        request, HttpStatus.notFound, strings, strings.get('not_found'), '');
  }

  /// Parses a file index: ASCII digits only, no leading zeros, in range.
  int? _parseIndex(String s) {
    if (s.isEmpty || s.length > 6) return null;
    if (s.length > 1 && s.startsWith('0')) return null;
    for (final c in s.codeUnits) {
      if (c < 0x30 || c > 0x39) return null;
    }
    final i = int.parse(s);
    return i < files.length ? i : null;
  }

  void _noteGuest(HttpRequest request, InternetAddress remote) {
    if (_seenGuests.add(remote.address)) {
      _emit(GuestConnected(
          remote.address,
          GuestDevice.fromUserAgent(
              request.headers.value(HttpHeaders.userAgentHeader))));
    }
  }

  Future<void> _sendPage(HttpRequest request, GuestStrings strings,
      {required bool head}) async {
    final nonce = _nonce();
    final html = renderSendPage(
      files: files,
      strings: strings,
      device: GuestDevice.fromUserAgent(
          request.headers.value(HttpHeaders.userAgentHeader)),
      nonce: nonce,
    );
    final response = request.response;
    response.headers
      ..contentType = ContentType.html
      ..set('content-security-policy', _pageCsp(nonce));
    return _writeBody(response, utf8.encode(html), head: head);
  }

  Future<void> _sendStatus(HttpRequest request, {required bool head}) {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    return _writeBody(response, utf8.encode(jsonEncode({'files': files.length})),
        head: head);
  }

  Future<void> _sendMessage(HttpRequest request, int status,
      GuestStrings strings, String title, String body) {
    final response = request.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..headers.set('content-security-policy',
          "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; "
              "form-action 'none'; frame-ancestors 'none'");
    final html =
        renderMessagePage(title: title, body: body, strings: strings);
    return _writeBody(response, utf8.encode(html),
        head: request.method == 'HEAD');
  }

  Future<void> _redirect(HttpRequest request, String location) {
    final response = request.response
      ..statusCode = HttpStatus.found
      ..headers.set(HttpHeaders.locationHeader, location);
    return _writeBody(response, const [], head: true);
  }

  Future<void> _methodNotAllowed(HttpRequest request) {
    final response = request.response
      ..statusCode = HttpStatus.methodNotAllowed
      ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
    return _writeBody(response, const [], head: true);
  }

  Future<void> _sendFile(HttpRequest request, int index, InternetAddress remote,
      {required bool head}) async {
    final file = files[index];
    final size = file.length;
    final response = request.response;
    final modified = file.lastModified;
    final lastModified = modified == null ? null : HttpDate.format(modified);
    final etag = '"$index-${size.toRadixString(36)}-'
        '${(modified?.millisecondsSinceEpoch ?? 0).toRadixString(36)}"';

    final decision = decideRange(
      rangeHeader: request.headers.value(HttpHeaders.rangeHeader),
      size: size,
      ifRange: request.headers.value(HttpHeaders.ifRangeHeader),
      etag: etag,
      lastModified: lastModified,
    );

    response.headers
      ..set(HttpHeaders.contentTypeHeader,
          lookupMimeType(file.name) ?? 'application/octet-stream')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.etagHeader, etag)
      ..set('content-disposition', contentDisposition(file.name));
    if (lastModified != null) {
      response.headers.set(HttpHeaders.lastModifiedHeader, lastModified);
    }

    int start;
    int end;
    switch (decision) {
      case FullContent():
        start = 0;
        end = size;
      case PartialContent(start: final s, end: final e):
        start = s;
        end = e;
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
              HttpHeaders.contentRangeHeader, 'bytes $s-${e - 1}/$size');
      case Unsatisfiable():
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        return _writeBody(response, const [], head: true);
    }

    final length = end - start;
    response.contentLength = length;
    if (head || length == 0) {
      return _closeQuietly(response);
    }

    final id = _nextDownloadId++;
    _activeDownloads++;
    _emit(DownloadStarted(id, remote.address, index, start, end));
    var sent = 0;
    var lastReport = DateTime.now();
    final counted = file.openRead(start, end).map((chunk) {
      sent += chunk.length;
      final now = DateTime.now();
      if (now.difference(lastReport) >= config.progressInterval) {
        lastReport = now;
        _touch();
        _emit(DownloadProgress(id, index, sent));
      }
      return chunk;
    });
    var completed = false;
    try {
      await response.addStream(counted);
      await response.close();
      completed = sent == length;
    } catch (_) {
      completed = false;
      await _closeQuietly(response);
    } finally {
      _activeDownloads--;
      _touch();
      _emit(DownloadEnded(id, index, sent, completed));
    }
  }

  Future<void> _writeBody(HttpResponse response, List<int> body,
      {required bool head}) async {
    response.contentLength = body.length;
    if (!head && body.isNotEmpty) response.add(body);
    await _closeQuietly(response);
  }

  Future<void> _closeQuietly(HttpResponse response) async {
    try {
      await response.close();
    } catch (_) {
      // The guest went away; nothing to do.
    }
  }

  String _pageCsp(String nonce) =>
      "default-src 'none'; style-src 'unsafe-inline'; "
      // 'unsafe-inline' is ignored by browsers that understand nonces and
      // keeps very old ones (CSP level 1) working.
      "script-src 'nonce-$nonce' 'unsafe-inline'; "
      "connect-src 'self'; img-src 'self' data:; base-uri 'none'; "
      "form-action 'self'; frame-ancestors 'none'";

  String _nonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void _touch() {
    _lastActivity = DateTime.now();
    _idleReported = false;
  }

  void _checkIdle() {
    if (_stopped ||
        _idleReported ||
        _activeDownloads > 0 ||
        _activeUploads > 0) {
      return;
    }
    if (DateTime.now().difference(_lastActivity) >= config.idleTimeout) {
      _idleReported = true;
      _emit(const SessionIdle());
    }
  }

  void _emit(ServerEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
