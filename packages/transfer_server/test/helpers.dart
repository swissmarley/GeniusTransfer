import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:transfer_server/transfer_server.dart';

final loopback = InternetAddress.loopbackIPv4;

/// User-Agent strings of the guest browsers we care about.
const uaIphoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1';
const uaIphoneChrome =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) CriOS/140.0.7339.122 Mobile/15E148 Safari/604.1';
const uaIpadDesktop =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.6 Safari/605.1.15';
const uaAndroidChrome =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/154.0.0.0 Mobile Safari/537.36';
const uaSamsung =
    'Mozilla/5.0 (Linux; Android 15; SAMSUNG SM-S931B) AppleWebKit/537.36 '
    '(KHTML, like Gecko) SamsungBrowser/28.0 Chrome/130.0.0.0 Mobile Safari/537.36';
const uaAndroidWebView =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP2A; wv) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Version/4.0 Chrome/140.0.0.0 Mobile Safari/537.36';
const uaAndroidGoogleApp =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/140.0.0.0 Mobile Safari/537.36 GSA/15.30.38.29.arm64';
const uaOldAndroid8Chrome =
    'Mozilla/5.0 (Linux; Android 8.0.0; SM-G950F) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/58.0.3029.83 Mobile Safari/537.36';

/// Creates a temp directory that is deleted after the test.
Future<Directory> tempDir() =>
    Directory.systemTemp.createTemp('transfer_server_test_');

/// Writes [bytes] to a new file in [dir].
Future<File> writeFile(Directory dir, String name, List<int> bytes) async {
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// Deterministic test content: byte i is (i * 31 + 7) & 0xff.
Uint8List pattern(int length, {int offset = 0}) => Uint8List.fromList(
    List<int>.generate(length, (i) => ((i + offset) * 31 + 7) & 0xff));

/// Starts a server on 127.0.0.1 with an ephemeral port.
Future<TransferServer> startServer(List<SharedFile> files,
    {ServerConfig? config, String? token}) async {
  final server = TransferServer(
      files: files,
      token: token,
      config: config ?? const ServerConfig(preferredPort: 0));
  await server.start([loopback]);
  return server;
}

/// A finished HTTP exchange.
class Reply {
  Reply(this.status, this.headers, this.body);
  final int status;
  final HttpHeaders headers;
  final Uint8List body;
  String get text => utf8.decode(body, allowMalformed: true);
  String? header(String name) => headers.value(name);
}

/// Sends one request and reads the whole body.
Future<Reply> send(
  TransferServer server,
  String path, {
  String method = 'GET',
  Map<String, String> headers = const {},
  String? hostOverride,
}) async {
  final client = HttpClient()..autoUncompress = false;
  try {
    final uri = Uri.parse('http://127.0.0.1:${server.port}$path');
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    if (hostOverride != null) request.headers.host = hostOverride;
    headers.forEach(request.headers.set);
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return Reply(response.statusCode, response.headers, builder.takeBytes());
  } finally {
    client.close(force: true);
  }
}

/// Sends raw bytes on a new TCP connection and returns everything the
/// server sends back until it closes the connection (or [timeout]).
Future<List<int>> rawExchange(int port, List<int> bytes,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final socket = await Socket.connect(loopback, port);
  socket.add(bytes);
  await socket.flush();
  final received = <int>[];
  await socket
      .listen(received.addAll)
      .asFuture<void>()
      .timeout(timeout, onTimeout: () => socket.destroy());
  socket.destroy();
  return received;
}

/// Collects server events until [stop] completes.
List<ServerEvent> recordEvents(TransferServer server) {
  final events = <ServerEvent>[];
  server.events.listen(events.add);
  return events;
}
