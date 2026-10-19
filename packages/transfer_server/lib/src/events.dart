import 'dart:io';

import 'receive.dart';
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
      this.id, this.address, this.fileIndex, this.start, this.end,
      {this.converted = false});

  /// Unique per response, to match later events.
  final int id;
  final String address;
  final int fileIndex;
  final int start;

  /// Exclusive.
  final int end;

  /// The guest asked for a JPEG copy of this HEIC photo, not the original:
  /// [start] and [end] count bytes of the copy.
  final bool converted;
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

/// Someone typed a wrong PIN. [attemptsLeft] more are allowed.
final class PinRejected extends ServerEvent {
  const PinRejected(this.address, this.attemptsLeft);

  final String address;
  final int attemptsLeft;
}

/// Too many wrong PINs: the session lets nobody new in.
final class PinLockedOut extends ServerEvent {
  const PinLockedOut();
}

/// Nothing has happened for the configured idle timeout and no transfer is
/// running. The host app should end the session.
final class SessionIdle extends ServerEvent {
  const SessionIdle();
}

/// A guest wants to send files. Call `approveUpload(id)` or
/// `declineUpload(id)`. If [quarantined], the files have already arrived
/// (the guest's browser has no JavaScript) and wait in quarantine.
final class UploadOffered extends ServerEvent {
  const UploadOffered(this.id, this.address, this.device, this.files,
      this.totalBytes, this.quarantined);

  final String id;
  final String address;
  final GuestDevice device;
  final List<OfferedFile> files;
  final int totalBytes;
  final bool quarantined;
}

/// An offer was not answered within the offer timeout and is gone.
final class UploadOfferExpired extends ServerEvent {
  const UploadOfferExpired(this.id);
  final String id;
}

/// Bytes of file [fileIndex] of batch [batchId] received so far.
final class UploadProgress extends ServerEvent {
  const UploadProgress(this.batchId, this.fileIndex, this.received);

  final String batchId;
  final int fileIndex;
  final int received;
}

/// File [fileIndex] of batch [batchId] arrived completely and is [file].
final class UploadFileReceived extends ServerEvent {
  const UploadFileReceived(
      this.batchId, this.fileIndex, this.file, this.name, this.size);

  final String batchId;
  final int fileIndex;
  final File file;

  /// The final file name ([file]'s base name).
  final String name;
  final int size;
}

/// File [fileIndex] of batch [batchId] did not arrive completely (the guest
/// went away or sent the wrong size). The guest may try it again.
final class UploadFileFailed extends ServerEvent {
  const UploadFileFailed(this.batchId, this.fileIndex);

  final String batchId;
  final int fileIndex;
}

/// Every file of batch [batchId] has arrived.
final class UploadBatchFinished extends ServerEvent {
  const UploadBatchFinished(this.batchId, this.fileCount, this.totalBytes);

  final String batchId;
  final int fileCount;
  final int totalBytes;
}
