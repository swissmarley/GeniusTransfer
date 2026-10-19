import 'dart:io';

/// What a session does: the host sends files to the guest, or receives them.
enum SessionMode { send, receive }

/// Limits and storage for a receiving session.
class ReceiveOptions {
  const ReceiveOptions({
    required this.stagingDir,
    this.maxBatchBytes = 20000000000,
    this.maxFiles = 500,
    this.freeBytes,
    this.reserveBytes = 1000000000,
    this.offerTimeout = const Duration(minutes: 10),
    this.longPollTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
    this.copyOnDelivery = false,
  });

  /// Where uploads are written. Each batch gets its own folder:
  /// `<stagingDir>/<id>/files/` for accepted files, `<stagingDir>/q-<id>/`
  /// for files that arrived before they were accepted (guests without
  /// JavaScript). The host moves accepted files to their final place.
  final Directory stagingDir;

  /// Largest batch accepted, in bytes.
  final int maxBatchBytes;

  /// Most files in one batch.
  final int maxFiles;

  /// Free bytes on the volume of [stagingDir], or null if unknown. Offers
  /// that would leave less than [reserveBytes] free are refused.
  final Future<int?> Function()? freeBytes;
  final int reserveBytes;

  /// An offer the host neither accepts nor declines in this time expires.
  final Duration offerTimeout;

  /// How long `GET offer/<id>` waits for a decision before answering.
  final Duration longPollTimeout;

  /// An upload that sends nothing for this long is dropped, so a guest
  /// whose Wi-Fi dropped can send the file again.
  final Duration stallTimeout;

  /// The host copies each file once more when it puts it in place (Android
  /// MediaStore), so a batch needs room for its largest file twice.
  final bool copyOnDelivery;
}

/// A file a guest wants to send: its sanitized name and declared size.
class OfferedFile {
  const OfferedFile(this.name, this.size);
  final String name;
  final int size;

  @override
  String toString() => 'OfferedFile($name, $size)';
}

/// Where a batch of uploads stands.
enum OfferState {
  /// Files from a guest without JavaScript are arriving before approval.
  uploading,

  /// Waiting for the host to accept or decline.
  pending,

  /// Accepted; files are arriving (or the guest stopped sending).
  accepted,
  declined,

  /// Nobody answered in time.
  expired,

  /// Every file has arrived.
  done,

  /// The upload failed or the session ended first.
  cancelled,
}
