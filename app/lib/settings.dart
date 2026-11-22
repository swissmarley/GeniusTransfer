import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform/host_platform.dart';

/// The user's settings, kept on this device.
///
/// - [folder]: where received files go. Null means the default: Pictures,
///   Movies or Download › GeniusTransfer on Android (by file type), Files ›
///   On My iPhone › GeniusTransfer › Received on iOS, and Downloads ›
///   GeniusTransfer on computers.
/// - [requirePin]: each session gets a 4-digit PIN the guest must type.
/// - [useHttps]: sessions serve HTTPS with a self-signed certificate, so
///   files are encrypted on the network. On by default.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._folder, this._requirePin, this._useHttps);

  /// Starts with [folder] (default: none) and touches no storage until
  /// something changes. For tests.
  @visibleForTesting
  AppSettings.forTest(
      {SaveFolder? folder, bool requirePin = false, bool useHttps = true})
      : this._(folder, requirePin, useHttps);

  static const _idKey = 'saveFolder.id';
  static const _nameKey = 'saveFolder.name';
  static const _pinKey = 'requirePin';
  static const _httpsKey = 'useHttps';

  late final _prefs = SharedPreferencesAsync();
  SaveFolder? _folder;
  bool _requirePin;
  bool _useHttps;

  SaveFolder? get folder => _folder;
  bool get requirePin => _requirePin;
  bool get useHttps => _useHttps;

  Future<void> setUseHttps(bool value) async {
    _useHttps = value;
    notifyListeners();
    await _prefs.setBool(_httpsKey, value);
  }

  Future<void> setRequirePin(bool value) async {
    _requirePin = value;
    notifyListeners();
    await _prefs.setBool(_pinKey, value);
  }

  static Future<AppSettings> load() async {
    final prefs = SharedPreferencesAsync();
    SaveFolder? folder;
    var requirePin = false;
    var useHttps = true;
    try {
      final id = await prefs.getString(_idKey);
      final name = await prefs.getString(_nameKey);
      if (id != null && name != null) folder = SaveFolder(id: id, name: name);
      requirePin = await prefs.getBool(_pinKey) ?? false;
      useHttps = await prefs.getBool(_httpsKey) ?? true;
    } catch (e) {
      debugPrint('Could not read settings: $e');
    }
    return AppSettings._(folder, requirePin, useHttps);
  }

  /// Lets the user choose a folder and remembers it. Returns false if they
  /// cancelled.
  Future<bool> chooseFolder(HostPlatform platform) async {
    final SaveFolder? picked;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      // These need native code to keep access to the folder after a
      // restart (a persisted URI permission or a security-scoped bookmark).
      picked = await platform.pickFolder();
    } else {
      final path = await FilePicker.getDirectoryPath();
      picked = path == null ? null : SaveFolder(id: path, name: path);
    }
    if (picked == null) return false;
    await _store(picked);
    return true;
  }

  /// Goes back to the default folder.
  Future<void> useDefault() async {
    _folder = null;
    notifyListeners();
    await _prefs.remove(_idKey);
    await _prefs.remove(_nameKey);
  }

  /// Stores a refreshed bookmark for the same folder (iOS, macOS).
  Future<void> refreshFolderId(String id) async {
    final current = _folder;
    if (current == null) return;
    await _store(SaveFolder(id: id, name: current.name));
  }

  Future<void> _store(SaveFolder folder) async {
    _folder = folder;
    notifyListeners();
    await _prefs.setString(_idKey, folder.id);
    await _prefs.setString(_nameKey, folder.name);
  }
}
