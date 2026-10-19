/// Local plain-HTTP server for GeniusTransfer.
///
/// A [TransferServer] serves one sharing session: the shared files and a
/// self-contained guest page, under a secret token, on LAN addresses only.
library;

export 'src/content_disposition.dart' show contentDisposition;
export 'src/events.dart';
export 'src/fd_file.dart' show FdFileReader, FdSharedFile;
export 'src/guest_strings.dart' show GuestStrings;
export 'src/net_util.dart' show isLanAddress, isPrivateIpv4;
export 'src/server.dart' show ServerConfig, TransferServer;
export 'src/shared_file.dart';
export 'src/token.dart' show generateToken, tokenLength;
export 'src/user_agent.dart';
