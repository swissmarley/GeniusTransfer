import 'user_agent.dart';

/// Something that happened in a session, reported to the host UI.
sealed class ServerEvent {
  const ServerEvent();
}

/// A guest device opened the session page for the first time.
final class GuestConnected extends ServerEvent {
  const GuestConnected(this.address, this.device);

  /// The guest's IP address.
  final String address;
  final GuestDevice device;
}

/// A guest started downloading bytes [start, end) of file [fileIndex].
final class DownloadStarted extends ServerEvent {
  const DownloadStarted(
      this.id, this.address, this.fileIndex, this.start, this.end);

  /// Unique per response, to match later events.
  final int id;
  final String address;
  final int fileIndex;
  final int start;

  /// Exclusive.
  final int end;
}

/// Bytes sent so far for download [id] (reported a few times a second).
final class DownloadProgress extends ServerEvent {
  const DownloadProgress(this.id, this.fileIndex, this.sent);

  final int id;
  final int fileIndex;

  /// Bytes sent since this response started (not counting the range start).
  final int sent;
}

/// Download [id] finished: all requested bytes were sent ([completed]), or
/// the guest disconnected or the session stopped before that.
final class DownloadEnded extends ServerEvent {
  const DownloadEnded(this.id, this.fileIndex, this.sent, this.completed);

  final int id;
  final int fileIndex;
  final int sent;
  final bool completed;
}

/// Nothing has happened for the configured idle timeout and no transfer is
/// running. The host app should end the session.
final class SessionIdle extends ServerEvent {
  const SessionIdle();
}
