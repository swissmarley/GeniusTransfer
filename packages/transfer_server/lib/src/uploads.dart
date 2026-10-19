part of 'server.dart';

/// Largest `POST offer` body.
const _maxOfferBody = 64 * 1024;

const _idAlphabet = 'abcdefghijklmnopqrstuvwxyz234567';

/// One group of files a guest sends at once.
class _Batch {
  _Batch({
    required this.id,
    required this.address,
    required this.device,
    required this.dir,
    required this.quarantined,
    required this.state,
  });

  final String id;
  final String address;
  final GuestDevice device;

  /// `<staging>/<id>` (accepted files go to its `files/` folder), or
  /// `<staging>/q-<id>` for files that arrived before approval.
  final Directory dir;
  final bool quarantined;
  OfferState state;
  List<OfferedFile> files = const [];

  /// Indexes of files that have arrived completely, or are arriving now.
  final received = <int>{};
  final uploading = <int>{};

  /// Names given out in [dir] or [filesDir], lower-case.
  final taken = <String>{};

  /// Files waiting in quarantine, in offer order.
  final quarantineFiles = <File>[];
  Timer? timer;

  var _changed = Completer<void>();

  /// Completes the next time [state] changes.
  Future<void> get changed => _changed.future;

  Directory get filesDir => Directory('${dir.path}/files');

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  bool get isOpen =>
      state == OfferState.uploading || state == OfferState.pending;

  void setState(OfferState next) {
    state = next;
    final previous = _changed;
    _changed = Completer<void>();
    previous.complete();
  }
}

/// A limit was hit while reading a multipart upload.
class _LimitHit implements Exception {
  const _LimitHit(this.code);
  final String code;
}

extension _Uploads on TransferServer {
  ReceiveOptions get _options => receiveOptions!;

  /// Handles the receive-mode routes. Returns false for anything else.
  Future<bool> _routeUpload(HttpRequest request, InternetAddress remote,
      List<String> rest, GuestStrings strings) async {
    final method = request.method;
    final first = rest.first;

    if (rest.length == 1 && (first == 'offer' || first == 'u')) {
      if (method != 'POST') {
        await _notAllowed(request, 'POST');
      } else if (!_originAllowed(request)) {
        await _sendJson(request, HttpStatus.forbidden, {'error': 'forbidden'});
      } else {
        _noteGuest(request, remote);
        if (first == 'offer') {
          await _handleOffer(request, remote);
        } else {
          await _handleMultipart(request, remote, strings);
        }
      }
      return true;
    }

    if (rest.length == 2 && (first == 'offer' || first == 'wait')) {
      final batch = _batches[rest[1]];
      if (method != 'GET' && method != 'HEAD') {
        await _notAllowed(request, 'GET, HEAD');
      } else if (batch == null) {
        if (first == 'offer') {
          await _sendJson(
              request, HttpStatus.notFound, {'error': 'not_found'});
        } else {
          await _sendMessage(request, HttpStatus.notFound, strings,
              strings.get('not_found'), '');
        }
      } else if (first == 'offer') {
        await _handlePoll(request, batch);
      } else {
        await _sendWaitPage(request, batch, strings);
      }
      return true;
    }

    if (rest.length == 3 && first == 'u') {
      final batch = _batches[rest[1]];
      final index = batch == null ? null : _parseUploadIndex(rest[2], batch);
      if (method != 'POST') {
        await _notAllowed(request, 'POST');
      } else if (!_originAllowed(request)) {
        await _sendJson(request, HttpStatus.forbidden, {'error': 'forbidden'});
      } else if (batch == null || index == null) {
        await _sendJson(request, HttpStatus.notFound, {'error': 'not_found'});
      } else {
        await _handleUpload(request, batch, index);
      }
      return true;
    }
    return false;
  }

  Future<void> _sendReceivePage(HttpRequest request, GuestStrings strings,
      {required bool head}) {
    final nonce = _nonce();
    final html = renderReceivePage(
      strings: strings,
      nonce: nonce,
      maxFiles: _options.maxFiles,
      maxBytes: _options.maxBatchBytes,
    );
    request.response.headers
      ..contentType = ContentType.html
      ..set('content-security-policy', _pageCsp(nonce));
    return _writeBody(request.response, utf8.encode(html), head: head);
  }

  // ---- Offers (guests with JavaScript) ----

  Future<void> _handleOffer(HttpRequest request, InternetAddress remote) async {
    final body = await _readSmallBody(request, _maxOfferBody);
    if (body == null) {
      return _sendJson(request, HttpStatus.requestEntityTooLarge,
          {'error': 'bad_request'});
    }
    final List<OfferedFile> files;
    try {
      final decoded = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      files = [
        for (final f in decoded['files'] as List)
          OfferedFile(sanitizeFileName((f as Map)['name'] as String),
              _validSize(f['size'])),
      ];
      if (files.isEmpty) throw const FormatException('No files.');
    } catch (_) {
      return _sendJson(
          request, HttpStatus.badRequest, {'error': 'bad_request'});
    }

    final total = files.fold<int>(0, (sum, f) => sum + f.size);
    final largest = files.fold<int>(0, (m, f) => f.size > m ? f.size : m);
    final error = await _checkLimits(files.length, total, largest: largest);
    if (error != null) {
      return _sendJson(request, _limitStatus(error), {'error': error});
    }
    final batch = _newBatch(request, remote, quarantined: false)
      ..files = files;
    _offer(batch);
    return _sendJson(
        request, HttpStatus.ok, {'id': batch.id, 'state': batch.state.name});
  }

  /// Long poll: answers when the state changes, or after a while.
  Future<void> _handlePoll(HttpRequest request, _Batch batch) async {
    if (batch.isOpen) {
      await batch.changed
          .timeout(_options.longPollTimeout, onTimeout: () {});
    }
    return _sendJson(request, HttpStatus.ok, {
      'state': batch.state.name,
      'received': batch.received.toList()..sort(),
    });
  }

  Future<void> _handleUpload(
      HttpRequest request, _Batch batch, int index) async {
    if (batch.received.contains(index)) {
      return _sendJson(
          request, HttpStatus.conflict, {'error': 'already_received'});
    }
    if (batch.uploading.contains(index)) {
      // A retry while the first try is still open (the guest's Wi-Fi
      // dropped): that one stalls out soon, then the guest tries again.
      return _sendJson(request, HttpStatus.conflict, {'error': 'in_progress'});
    }
    if (batch.quarantined || batch.state != OfferState.accepted) {
      return _sendJson(
          request, HttpStatus.forbidden, {'error': 'not_accepted'});
    }
    final expected = batch.files[index].size;
    if (request.contentLength < 0) {
      return _sendJson(
          request, HttpStatus.lengthRequired, {'error': 'length_required'});
    }
    if (request.contentLength != expected) {
      return _sendJson(
          request, HttpStatus.badRequest, {'error': 'size_mismatch'});
    }

    batch.uploading.add(index);
    final finished = _startUpload();
    final part = File('${batch.dir.path}/.part-$index');
    var stored = false;
    try {
      final received = await _writeStream(
        request,
        part,
        onProgress: (n) => _emit(UploadProgress(batch.id, index, n)),
      );
      if (received != expected) {
        throw const FormatException('The upload was cut short.');
      }
      if (batch.state != OfferState.accepted) {
        throw StateError('The batch is no longer accepted.');
      }
      final name =
          uniqueName(batch.filesDir, batch.files[index].name, batch.taken);
      final path = containedPath(batch.filesDir, name);
      if (path == null) throw StateError('Unsafe file name.');
      final file = await part.rename(path);
      stored = true;
      batch.received.add(index);
      _emit(UploadFileReceived(batch.id, index, file, name, expected));
      if (batch.received.length == batch.files.length) {
        batch.setState(OfferState.done);
        _emit(UploadBatchFinished(
            batch.id, batch.files.length, batch.totalBytes));
      }
      await _sendJson(request, HttpStatus.ok, {'ok': true});
    } catch (_) {
      if (!stored) {
        await _deleteQuietly(part);
        _emit(UploadFileFailed(batch.id, index));
      }
      await _sendJson(
          request, HttpStatus.internalServerError, {'error': 'failed'});
    } finally {
      batch.uploading.remove(index);
      _endUpload(finished);
    }
  }

  // ---- Plain form uploads (guests without JavaScript) ----

  Future<void> _handleMultipart(HttpRequest request, InternetAddress remote,
      GuestStrings strings) async {
    final type = request.headers.contentType;
    final boundary = type?.parameters['boundary'];
    if (type?.mimeType != 'multipart/form-data' ||
        boundary == null ||
        boundary.isEmpty) {
      return _sendWaitMessage(request, HttpStatus.badRequest, strings,
          strings.get('receive_failed'));
    }
    if (request.contentLength < 0) {
      return _sendWaitMessage(request, HttpStatus.lengthRequired, strings,
          strings.get('receive_failed'));
    }
    final limit = await _checkLimits(0, request.contentLength,
        largest: request.contentLength);
    if (limit != null) {
      return _sendWaitMessage(
          request, _limitStatus(limit), strings, _limitText(limit, strings));
    }

    final batch = _newBatch(request, remote, quarantined: true);
    final finished = _startUpload();
    final files = <OfferedFile>[];
    try {
      await batch.dir.create(recursive: true);
      var total = 0;
      final parts =
          request.cast<List<int>>().transform(MimeMultipartTransformer(boundary));
      await for (final part in parts) {
        final filename = _filenameOf(part.headers['content-disposition']);
        if (filename == null) {
          await part.drain<void>();
          continue;
        }
        final index = files.length;
        if (index >= _options.maxFiles) throw const _LimitHit('too_many_files');
        final partFile = File('${batch.dir.path}/.part-$index');
        final size = await _writeStream(part, partFile, onChunk: (n) {
          total += n;
          if (total > _options.maxBatchBytes) {
            throw const _LimitHit('too_large');
          }
        });
        final name =
            uniqueName(batch.dir, sanitizeFileName(filename), batch.taken);
        final path = containedPath(batch.dir, name);
        if (path == null) throw StateError('Unsafe file name.');
        batch.quarantineFiles.add(await partFile.rename(path));
        files.add(OfferedFile(name, size));
      }
      if (batch.state != OfferState.uploading) {
        throw StateError('The session ended.');
      }
      if (files.isEmpty) {
        _dropBatch(batch);
        await _sendWaitMessage(request, HttpStatus.badRequest, strings,
            strings.get('receive_pick_first'));
        return;
      }
      batch.files = files;
      _offer(batch);
      final response = request.response
        ..statusCode = HttpStatus.seeOther
        ..headers.set(HttpHeaders.locationHeader, 'wait/${batch.id}');
      await _writeBody(response, const [], head: true);
    } on _LimitHit catch (e) {
      _dropBatch(batch);
      await _sendWaitMessage(
          request, _limitStatus(e.code), strings, _limitText(e.code, strings));
    } catch (_) {
      _dropBatch(batch);
      await _sendWaitMessage(request, HttpStatus.internalServerError, strings,
          strings.get('receive_failed'));
    } finally {
      _endUpload(finished);
    }
  }

  Future<void> _sendWaitPage(
      HttpRequest request, _Batch batch, GuestStrings strings) {
    final count = batch.files.length;
    final (title, body, refresh) = switch (batch.state) {
      OfferState.uploading ||
      OfferState.pending =>
        (strings.get('receive_waiting'), strings.get('receive_arrived_waiting'), true),
      OfferState.accepted || OfferState.done => (
          count == 1
              ? strings.get('receive_done_one')
              : strings.get('receive_done_other', {'count': count}),
          '',
          false
        ),
      OfferState.declined => (strings.get('receive_declined'), '', false),
      OfferState.expired => (strings.get('receive_expired'), '', false),
      OfferState.cancelled => (strings.get('receive_failed'), '', false),
    };
    final html = renderWaitPage(
        title: title, body: body, refresh: refresh, strings: strings);
    request.response.headers
      ..contentType = ContentType.html
      ..set('content-security-policy', _plainCsp);
    return _writeBody(request.response, utf8.encode(html),
        head: request.method == 'HEAD');
  }

  Future<void> _sendWaitMessage(HttpRequest request, int status,
      GuestStrings strings, String title) {
    // Served at <T>/u, so "./" leads back to the upload page.
    final html = renderWaitPage(
        title: title,
        body: '',
        refresh: false,
        strings: strings,
        moreHref: './');
    final response = request.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..headers.set('content-security-policy', _plainCsp);
    // The body of a refused upload may still be arriving; do not reuse the
    // connection.
    response.persistentConnection = false;
    return _writeBody(response, utf8.encode(html), head: false);
  }

  // ---- Host decisions ----

  Future<bool> _approve(String id) async {
    final batch = _batches[id];
    if (batch == null || batch.state != OfferState.pending) return false;
    batch.timer?.cancel();
    if (!batch.quarantined) {
      await batch.filesDir.create(recursive: true);
      batch.setState(OfferState.accepted);
      return true;
    }
    // The files are already here: move them out of quarantine.
    final target = Directory('${_options.stagingDir.path}/$id/files');
    await target.create(recursive: true);
    final taken = <String>{};
    batch.setState(OfferState.accepted);
    for (var i = 0; i < batch.quarantineFiles.length; i++) {
      final source = batch.quarantineFiles[i];
      final name = uniqueName(target, batch.files[i].name, taken);
      final path = containedPath(target, name);
      if (path == null) continue;
      final file = await source.rename(path);
      batch.received.add(i);
      _emit(UploadFileReceived(id, i, file, name, batch.files[i].size));
    }
    await _deleteQuietly(batch.dir);
    batch.setState(OfferState.done);
    _emit(UploadBatchFinished(id, batch.files.length, batch.totalBytes));
    return true;
  }

  Future<bool> _decline(String id) async {
    final batch = _batches[id];
    if (batch == null || batch.state != OfferState.pending) return false;
    batch.timer?.cancel();
    batch.setState(OfferState.declined);
    if (batch.quarantined) await _deleteQuietly(batch.dir);
    return true;
  }

  // ---- Bookkeeping ----

  _Batch _newBatch(HttpRequest request, InternetAddress remote,
      {required bool quarantined}) {
    String id;
    do {
      id = String.fromCharCodes(List.generate(
          12, (_) => _idAlphabet.codeUnitAt(_random.nextInt(32))));
    } while (_batches.containsKey(id));
    final staging = _options.stagingDir.path;
    final batch = _Batch(
      id: id,
      address: remote.address,
      device: GuestDevice.fromUserAgent(
          request.headers.value(HttpHeaders.userAgentHeader)),
      dir: Directory(quarantined ? '$staging/q-$id' : '$staging/$id'),
      quarantined: quarantined,
      state: quarantined ? OfferState.uploading : OfferState.pending,
    );
    _batches[id] = batch;
    return batch;
  }

  /// Puts [batch] in front of the host.
  void _offer(_Batch batch) {
    if (batch.state != OfferState.pending) batch.setState(OfferState.pending);
    batch.timer = Timer(_options.offerTimeout, () async {
      if (batch.state != OfferState.pending) return;
      batch.setState(OfferState.expired);
      if (batch.quarantined) await _deleteQuietly(batch.dir);
      _emit(UploadOfferExpired(batch.id));
    });
    _emit(UploadOffered(batch.id, batch.address, batch.device,
        List.unmodifiable(batch.files), batch.totalBytes, batch.quarantined));
  }

  /// Forgets a batch that never reached the host and deletes its files.
  void _dropBatch(_Batch batch) {
    if (batch.isOpen) batch.setState(OfferState.cancelled);
    _batches.remove(batch.id);
    unawaited(_deleteQuietly(batch.dir));
  }

  /// Null if a batch of [count] files and [bytes] bytes may be offered now,
  /// else the error code for the guest.
  Future<String?> _checkLimits(int count, int bytes, {int largest = 0}) async {
    if (_batches.values.any((b) => b.isOpen)) return 'busy';
    if (count > _options.maxFiles) return 'too_many_files';
    if (bytes > _options.maxBatchBytes) return 'too_large';
    final free = await _options.freeBytes?.call();
    // Files of accepted batches that have not arrived yet still need room.
    var owed = 0;
    for (final b in _batches.values) {
      if (b.state != OfferState.accepted) continue;
      for (var i = 0; i < b.files.length; i++) {
        if (!b.received.contains(i)) owed += b.files[i].size;
      }
    }
    final copy = _options.copyOnDelivery ? largest : 0;
    if (free != null && bytes + owed + copy + _options.reserveBytes > free) {
      return 'no_space';
    }
    // Another offer may have arrived while we asked for the free space.
    if (_batches.values.any((b) => b.isOpen)) return 'busy';
    return null;
  }

  int _limitStatus(String code) => switch (code) {
        'busy' => HttpStatus.conflict,
        'no_space' => HttpStatus.insufficientStorage,
        _ => HttpStatus.requestEntityTooLarge,
      };

  String _limitText(String code, GuestStrings strings) => switch (code) {
        'busy' => strings.get('receive_busy'),
        'too_many_files' =>
          strings.get('receive_too_many', {'count': _options.maxFiles}),
        'too_large' => strings.get('receive_too_large',
            {'size': formatSize(_options.maxBatchBytes, strings)}),
        'no_space' => strings.get('receive_no_space'),
        _ => strings.get('receive_failed'),
      };

  Completer<void> _startUpload() {
    _activeUploads++;
    final finished = Completer<void>();
    _runningUploads.add(finished.future);
    return finished;
  }

  void _endUpload(Completer<void> finished) {
    _activeUploads--;
    _runningUploads.remove(finished.future);
    finished.complete();
    _touch();
  }

  /// Writes [source] to [file] and returns the number of bytes written.
  /// [onChunk] may throw to stop early.
  Future<int> _writeStream(Stream<List<int>> source, File file,
      {void Function(int received)? onProgress,
      void Function(int chunk)? onChunk}) async {
    var received = 0;
    var lastReport = DateTime.now();
    final sink = file.openWrite();
    try {
      // A guest that stops sending (Wi-Fi gone, page closed) must not hold
      // the file open forever.
      await sink.addStream(source.timeout(_options.stallTimeout).map((chunk) {
        onChunk?.call(chunk.length);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastReport) >= config.progressInterval) {
          lastReport = now;
          _touch();
          onProgress?.call(received);
        }
        return chunk;
      }));
    } finally {
      try {
        await sink.close();
      } catch (_) {
        // Reported by addStream already, or the file is deleted next.
      }
    }
    onProgress?.call(received);
    return received;
  }

  /// Marks open batches cancelled, waits briefly for running uploads, then
  /// deletes partial files and quarantine folders. Completed files stay.
  Future<void> _cleanUpUploads() async {
    for (final batch in _batches.values) {
      batch.timer?.cancel();
      if (batch.isOpen || batch.state == OfferState.accepted) {
        batch.setState(OfferState.cancelled);
      }
    }
    if (_runningUploads.isNotEmpty) {
      await Future.wait(List.of(_runningUploads))
          .timeout(const Duration(seconds: 3), onTimeout: () => const []);
    }
    for (final batch in _batches.values) {
      if (batch.quarantined) {
        await _deleteQuietly(batch.dir);
        continue;
      }
      if (!batch.dir.existsSync()) continue;
      for (final entity in batch.dir.listSync(followLinks: false)) {
        final name = entity.uri.pathSegments.last;
        if (entity is File && name.startsWith('.part-')) {
          await _deleteQuietly(entity);
        }
      }
    }
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (entity is Directory) {
        if (await entity.exists()) await entity.delete(recursive: true);
      } else if (await entity.exists()) {
        await entity.delete();
      }
    } catch (_) {
      // Best effort: it may be gone already, or still open on Windows.
    }
  }

  // ---- Small helpers ----

  int? _parseUploadIndex(String s, _Batch batch) {
    if (s.isEmpty || s.length > 4) return null;
    if (s.length > 1 && s.startsWith('0')) return null;
    for (final c in s.codeUnits) {
      if (c < 0x30 || c > 0x39) return null;
    }
    final i = int.parse(s);
    return i < batch.files.length ? i : null;
  }

  int _validSize(Object? size) {
    if (size is int && size >= 0 && size <= 1 << 53) return size;
    if (size is double &&
        size >= 0 &&
        size <= 9007199254740992 &&
        size == size.truncateToDouble()) {
      return size.toInt();
    }
    throw const FormatException('Bad size.');
  }

  /// Cross-site requests are refused. Same-origin requests from a page
  /// with `referrer-policy: no-referrer` may say `Origin: null`.
  bool _originAllowed(HttpRequest request) {
    final origin = request.headers.value('origin');
    if (origin == null || origin == 'null') return true;
    final host = request.headers.value(HttpHeaders.hostHeader)?.toLowerCase();
    return origin.toLowerCase() == 'http://$host';
  }

  Future<List<int>?> _readSmallBody(HttpRequest request, int max) async {
    if (request.contentLength > max) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > max) return null;
    }
    return builder.takeBytes();
  }

  /// The file name in a multipart part's Content-Disposition, or null for
  /// ordinary fields and empty file inputs.
  String? _filenameOf(String? header) {
    if (header == null) return null;
    final value = HeaderValue.parse(header, parameterSeparator: ';');
    final raw = value.parameters['filename'];
    if (raw == null || raw.isEmpty) return null;
    // Browsers send the name as raw UTF-8; the parser read it as Latin-1.
    try {
      return utf8.decode(latin1.encode(raw));
    } catch (_) {
      return raw;
    }
  }

  Future<void> _sendJson(HttpRequest request, int status, Object body) {
    final response = request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    if (status >= 400 && request.method == 'POST') {
      // Do not wait for, or reuse the connection after, an unread body.
      response.persistentConnection = false;
    }
    return _writeBody(response, utf8.encode(jsonEncode(body)),
        head: request.method == 'HEAD');
  }

  Future<void> _notAllowed(HttpRequest request, String allow) {
    final response = request.response
      ..statusCode = HttpStatus.methodNotAllowed
      ..headers.set(HttpHeaders.allowHeader, allow);
    return _writeBody(response, const [], head: true);
  }
}

const _plainCsp = "default-src 'none'; style-src 'unsafe-inline'; "
    "base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
