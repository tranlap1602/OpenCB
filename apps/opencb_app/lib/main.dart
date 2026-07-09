import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:opencb_app/l10n/generated/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

const MethodChannel _rootPlatformChannel = MethodChannel('opencb/platform');
const String _appVersion = '1.6.0';
const String _appVersionLabel = 'v$_appVersion';
const String _landingPageUrl = 'https://tranlap1602.github.io/OpenCB/';
const String _githubRepoUrl = 'https://github.com/tranlap1602/OpenCB';
const String _latestReleaseApiUrl =
    'https://api.github.com/repos/tranlap1602/OpenCB/releases/latest';
const String _latestReleaseUrl =
    'https://github.com/tranlap1602/OpenCB/releases/latest';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _configureAndroidEdgeToEdge();
  runApp(const OpenCbApp());
}

void _configureAndroidEdgeToEdge() {
  if (!Platform.isAndroid) return;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  const initialSystemBarColor = Color(0xFFFBFEFC);
  _applyAndroidSystemUiStyle(
    Brightness.light,
    navigationBarColor: initialSystemBarColor,
    statusBarColor: initialSystemBarColor,
  );
}

void _applyAndroidSystemUiStyle(
  Brightness brightness, {
  Color? navigationBarColor,
  Color? statusBarColor,
}) {
  if (!Platform.isAndroid) return;
  final iconBrightness = brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: statusBarColor ?? Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  if (navigationBarColor != null) {
    unawaited(
      _rootPlatformChannel
          .invokeMethod<bool>('setSystemBars', {
            'navigationBarColor': navigationBarColor.toARGB32(),
            'statusBarColor': (statusBarColor ?? navigationBarColor).toARGB32(),
            'lightSystemBars': brightness == Brightness.light,
            'edgeToEdge': true,
          })
          .catchError((_) => false),
    );
  }
}

enum ClipboardKind { text, code, url, image, fileReference }

enum _HistoryScopeFilter { all, pinned, tagged }

enum AppLanguage {
  system(null),
  vi(Locale('vi')),
  en(Locale('en'));

  const AppLanguage(this.locale);

  final Locale? locale;

  String get storageValue => name;

  static AppLanguage fromStorageValue(String? value) {
    return AppLanguage.values.firstWhere(
      (language) => language.storageValue == value,
      orElse: () => AppLanguage.system,
    );
  }
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

const double _compactDesktopLayoutBreakpoint = 1020;
const double _mobileLayoutBreakpoint = 840;
const int _defaultRetentionLimit = 2000;
const Duration _discoveredDeviceOnlineWindow = Duration(seconds: 20);
const Duration _discoveredDeviceCacheWindow = Duration(minutes: 3);
const Duration _discoveredDevicePruneInterval = Duration(seconds: 12);
const Duration _discoveryReplyThrottle = Duration(seconds: 8);
const Duration _discoverySubnetSweepInterval = Duration(seconds: 24);

class ClipboardEntry {
  const ClipboardEntry({
    required this.id,
    required this.kind,
    required this.preview,
    required this.source,
    required this.createdAt,
    required this.pinned,
    required this.tags,
    this.body,
    this.filePath,
    this.imageBytes,
    this.sourceIconBytes,
  });

  factory ClipboardEntry.fromJson(Map<String, dynamic> json) {
    return ClipboardEntry(
      id: json['id'] as String,
      kind: _kindFromName(json['kind'] as String? ?? 'text'),
      preview: json['preview'] as String? ?? '',
      source: json['source'] as String? ?? 'Clipboard',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      pinned: json['pinned'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag.toString())
          .where((tag) => tag.trim().isNotEmpty)
          .toList(),
      body: json['body'] as String?,
      filePath: json['filePath'] as String?,
      imageBytes: json['imageBytes'] is String
          ? base64Decode(json['imageBytes'] as String)
          : null,
      sourceIconBytes: json['sourceIconBytes'] is String
          ? base64Decode(json['sourceIconBytes'] as String)
          : null,
    );
  }

  factory ClipboardEntry.fromCoreJson(
    Map<String, dynamic> json, {
    Uint8List? imageBytes,
    Uint8List? sourceIconBytes,
  }) {
    return ClipboardEntry(
      id: json['id'] as String,
      kind: _kindFromName(json['content_type'] as String? ?? 'text'),
      preview: json['preview'] as String? ?? '',
      source: json['source_app'] as String? ?? 'Clipboard',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      pinned: json['pinned'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag.toString())
          .where((tag) => tag.trim().isNotEmpty)
          .toList(),
      body: json['content_text'] as String?,
      filePath: json['file_path'] as String?,
      imageBytes: imageBytes,
      sourceIconBytes: sourceIconBytes,
    );
  }

  final String id;
  final ClipboardKind kind;
  final String preview;
  final String source;
  final DateTime createdAt;
  final bool pinned;
  final List<String> tags;
  final String? body;
  final String? filePath;
  final Uint8List? imageBytes;
  final Uint8List? sourceIconBytes;

  String get createdLabel => _relativeTime(createdAt);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'preview': preview,
      'source': source,
      'createdAt': createdAt.toIso8601String(),
      'pinned': pinned,
      'tags': tags,
      'body': body,
      'filePath': filePath,
    };
  }

  ClipboardEntry copyWith({
    String? id,
    ClipboardKind? kind,
    String? preview,
    String? source,
    DateTime? createdAt,
    bool? pinned,
    List<String>? tags,
    String? body,
    String? filePath,
    Uint8List? imageBytes,
    Uint8List? sourceIconBytes,
  }) {
    return ClipboardEntry(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      preview: preview ?? this.preview,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      pinned: pinned ?? this.pinned,
      tags: tags ?? this.tags,
      body: body ?? this.body,
      filePath: filePath ?? this.filePath,
      imageBytes: imageBytes ?? this.imageBytes,
      sourceIconBytes: sourceIconBytes ?? this.sourceIconBytes,
    );
  }
}

class TagDefinition {
  const TagDefinition({
    required this.name,
    required this.colorValue,
    required this.iconKey,
  });

  factory TagDefinition.fromJson(Map<String, dynamic> json) {
    final colorValue = json['colorValue'];
    return TagDefinition(
      name: json['name'] as String? ?? '',
      colorValue: colorValue is int ? colorValue : _tagColorOptions.first,
      iconKey: json['iconKey'] as String? ?? _tagIconOptions.first.key,
    );
  }

  final String name;
  final int colorValue;
  final String iconKey;

  Color get color => Color(colorValue);
  IconData get icon => _tagIconByKey(iconKey);

  Map<String, dynamic> toJson() {
    return {'name': name, 'colorValue': colorValue, 'iconKey': iconKey};
  }
}

class _TagEditResult {
  const _TagEditResult({
    required this.tags,
    required this.definitions,
    this.deletedTags = const {},
  });

  final List<String> tags;
  final Map<String, TagDefinition> definitions;
  final Set<String> deletedTags;
}

class SyncPeer {
  const SyncPeer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.pairCode,
    this.filePort = _defaultFileTransferPort,
    this.lastSyncedAt,
    this.lastError,
  });

  factory SyncPeer.fromJson(Map<String, dynamic> json) {
    return SyncPeer(
      id:
          json['id'] as String? ??
          'peer-${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Thiết bị LAN',
      host: json['host'] as String? ?? '127.0.0.1',
      port: json['port'] as int? ?? _defaultSyncPort,
      pairCode: json['pairCode'] as String? ?? '',
      filePort: json['filePort'] as int? ?? _defaultFileTransferPort,
      lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
      lastError: json['lastError'] as String?,
    );
  }

  final String id;
  final String name;
  final String host;
  final int port;
  final String pairCode;
  final int filePort;
  final DateTime? lastSyncedAt;
  final String? lastError;

  String get endpoint => '$host:$port';
  String get status => lastError == null ? 'Thiết bị tin cậy' : 'Lỗi sync';
  String get lastSynced {
    if (lastError != null) return _friendlySyncError(lastError!);
    if (lastSyncedAt == null) return 'Chưa từng sync';
    return 'Sync lần cuối ${_relativeTime(lastSyncedAt!)}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'pairCode': pairCode,
      'filePort': filePort,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'lastError': lastError,
    };
  }

  SyncPeer copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? pairCode,
    int? filePort,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncPeer(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      pairCode: pairCode ?? this.pairCode,
      filePort: filePort ?? this.filePort,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class DiscoveredSyncDevice {
  const DiscoveredSyncDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.filePort,
    required this.lastSeenAt,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final int filePort;
  final DateTime lastSeenAt;

  String get endpoint => '$host:$port';

  SyncPeer toPeer({required String pairCode}) {
    return SyncPeer(
      id: id,
      name: name,
      host: host,
      port: port,
      pairCode: pairCode,
      filePort: filePort,
    );
  }
}

enum FileTransferDirection { send, receive }

enum FileTransferStatus {
  waiting,
  sending,
  receiving,
  completed,
  rejected,
  failed,
  canceled,
}

class _FileTransferCanceledException implements Exception {
  const _FileTransferCanceledException();
}

class _SocketFrameReader {
  _SocketFrameReader(Socket socket) : _iterator = StreamIterator(socket);

  final StreamIterator<List<int>> _iterator;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  Future<Map<String, dynamic>> readJson({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final line = await _readLine().timeout(timeout);
    return jsonDecode(line) as Map<String, dynamic>;
  }

  Future<void> readBytes(
    int byteCount,
    FutureOr<void> Function(Uint8List bytes) onChunk,
  ) async {
    var remaining = byteCount;
    while (remaining > 0) {
      if (_available == 0) {
        await _fill();
      }
      final take = math.min(remaining, _available);
      final chunk = Uint8List.sublistView(_buffer, _offset, _offset + take);
      _offset += take;
      remaining -= take;
      _compactBuffer();
      await onChunk(chunk);
    }
  }

  int get _available => _buffer.length - _offset;

  Future<String> _readLine() async {
    while (true) {
      for (var index = _offset; index < _buffer.length; index += 1) {
        if (_buffer[index] != 10) continue;
        var end = index;
        if (end > _offset && _buffer[end - 1] == 13) {
          end -= 1;
        }
        final bytes = Uint8List.sublistView(_buffer, _offset, end);
        _offset = index + 1;
        _compactBuffer();
        return utf8.decode(bytes);
      }
      await _fill();
    }
  }

  Future<void> _fill() async {
    if (!await _iterator.moveNext()) {
      throw const SocketException('Kết nối đã đóng.');
    }
    final incoming = _iterator.current;
    if (_offset == 0) {
      final next = Uint8List(_buffer.length + incoming.length);
      next.setRange(0, _buffer.length, _buffer);
      next.setRange(_buffer.length, next.length, incoming);
      _buffer = next;
    } else {
      final remaining = _buffer.length - _offset;
      final next = Uint8List(remaining + incoming.length);
      next.setRange(0, remaining, _buffer, _offset);
      next.setRange(remaining, next.length, incoming);
      _buffer = next;
      _offset = 0;
    }
  }

  void _compactBuffer() {
    if (_offset == 0) return;
    if (_offset == _buffer.length) {
      _buffer = Uint8List(0);
      _offset = 0;
      return;
    }
    if (_offset > 1024 * 1024) {
      _buffer = Uint8List.sublistView(_buffer, _offset);
      _offset = 0;
    }
  }
}

class FileTransferFile {
  const FileTransferFile({
    required this.name,
    required this.size,
    this.path,
    this.uri,
    this.savedPath,
    this.relativePath,
  });

  factory FileTransferFile.fromJson(Map<String, dynamic> json) {
    return FileTransferFile(
      name: json['name'] as String? ?? 'file',
      size: json['size'] as int? ?? 0,
      path: json['path'] as String?,
      uri: json['uri'] as String?,
      savedPath: json['savedPath'] as String?,
      relativePath: json['relativePath'] as String?,
    );
  }

  final String name;
  final int size;
  final String? path;
  final String? uri;
  final String? savedPath;
  final String? relativePath;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'size': size,
      if (path != null) 'path': path,
      if (uri != null) 'uri': uri,
      if (savedPath != null) 'savedPath': savedPath,
      if (relativePath != null) 'relativePath': relativePath,
    };
  }

  FileTransferFile copyWith({String? savedPath}) {
    return FileTransferFile(
      name: name,
      size: size,
      path: path,
      uri: uri,
      savedPath: savedPath ?? this.savedPath,
      relativePath: relativePath,
    );
  }

  String get displayPath {
    final value = relativePath?.trim();
    if (value == null || value.isEmpty) return name;
    return value;
  }
}

class FileTransferRecord {
  const FileTransferRecord({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.direction,
    required this.status,
    required this.files,
    required this.totalBytes,
    required this.transferredBytes,
    required this.createdAt,
    this.speedBytesPerSecond = 0,
    this.error,
    this.saveDirectory,
  });

  factory FileTransferRecord.fromJson(Map<String, dynamic> json) {
    return FileTransferRecord(
      id: json['id'] as String? ?? _generateTransferId(),
      peerId: json['peerId'] as String? ?? '',
      peerName: json['peerName'] as String? ?? 'Thiết bị LAN',
      direction: FileTransferDirection.values.firstWhere(
        (direction) => direction.name == json['direction'],
        orElse: () => FileTransferDirection.receive,
      ),
      status: FileTransferStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => FileTransferStatus.completed,
      ),
      files: (json['files'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FileTransferFile.fromJson)
          .toList(),
      totalBytes: json['totalBytes'] as int? ?? 0,
      transferredBytes: json['transferredBytes'] as int? ?? 0,
      speedBytesPerSecond: json['speedBytesPerSecond'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      error: json['error'] as String?,
      saveDirectory: json['saveDirectory'] as String?,
    );
  }

  final String id;
  final String peerId;
  final String peerName;
  final FileTransferDirection direction;
  final FileTransferStatus status;
  final List<FileTransferFile> files;
  final int totalBytes;
  final int transferredBytes;
  final DateTime createdAt;
  final int speedBytesPerSecond;
  final String? error;
  final String? saveDirectory;

  double get progress {
    if (totalBytes <= 0) return status == FileTransferStatus.completed ? 1 : 0;
    return (transferredBytes / totalBytes).clamp(0, 1).toDouble();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'peerId': peerId,
      'peerName': peerName,
      'direction': direction.name,
      'status': status.name,
      'files': files.map((file) => file.toJson()).toList(),
      'totalBytes': totalBytes,
      'transferredBytes': transferredBytes,
      'speedBytesPerSecond': speedBytesPerSecond,
      'createdAt': createdAt.toIso8601String(),
      'error': error,
      'saveDirectory': saveDirectory,
    };
  }

  FileTransferRecord copyWith({
    FileTransferStatus? status,
    List<FileTransferFile>? files,
    int? transferredBytes,
    int? speedBytesPerSecond,
    String? error,
    String? saveDirectory,
  }) {
    return FileTransferRecord(
      id: id,
      peerId: peerId,
      peerName: peerName,
      direction: direction,
      status: status ?? this.status,
      files: files ?? this.files,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      createdAt: createdAt,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      error: error ?? this.error,
      saveDirectory: saveDirectory ?? this.saveDirectory,
    );
  }
}

class LocalSyncIdentity {
  const LocalSyncIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.pairCode,
  });

  factory LocalSyncIdentity.fromJson(Map<String, dynamic> json) {
    return LocalSyncIdentity(
      deviceId: json['deviceId'] as String? ?? _generateDeviceId(),
      deviceName: json['deviceName'] as String? ?? Platform.localHostname,
      pairCode: json['pairCode'] as String? ?? _generatePairCode(),
    );
  }

  factory LocalSyncIdentity.create() {
    return LocalSyncIdentity(
      deviceId: _generateDeviceId(),
      deviceName: Platform.localHostname,
      pairCode: _generatePairCode(),
    );
  }

  final String deviceId;
  final String deviceName;
  final String pairCode;

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'pairCode': pairCode,
    };
  }

  LocalSyncIdentity copyWith({String? deviceName}) {
    return LocalSyncIdentity(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      pairCode: pairCode,
    );
  }
}

class M3ThemePreset {
  const M3ThemePreset({
    required this.id,
    required this.name,
    required this.seedColor,
  });

  final String id;
  final String name;
  final Color seedColor;
}

const List<M3ThemePreset> _m3ThemePresets = [
  M3ThemePreset(
    id: 'opencb_teal',
    name: 'Xanh OpenCB',
    seedColor: Color(0xFF0E7C7B),
  ),
  M3ThemePreset(
    id: 'forest_green',
    name: 'Xanh Rừng',
    seedColor: Color(0xFF386A20),
  ),
  M3ThemePreset(
    id: 'baseline_purple',
    name: 'Tím',
    seedColor: Color(0xFF7B4DFF),
  ),
  M3ThemePreset(id: 'ink_blue', name: 'Serenity', seedColor: Color(0xFF285EA8)),
  M3ThemePreset(
    id: 'soft_pink',
    name: 'Rose Quartz',
    seedColor: Color(0xFFFFD7E3),
  ),
  M3ThemePreset(
    id: 'sunset_coral',
    name: 'San Hô Hoàng Hôn',
    seedColor: Color(0xFFB3261E),
  ),
  M3ThemePreset(
    id: 'mono_black_white',
    name: 'Đen trắng',
    seedColor: Color(0xFF1F1F1F),
  ),
  M3ThemePreset(
    id: 'blue_grey',
    name: 'Blue Grey',
    seedColor: Color(0xFF607D8B),
  ),
];

class _TagIconOption {
  const _TagIconOption(this.key, this.icon);

  final String key;
  final IconData icon;
}

class QuickOpenHotKey {
  const QuickOpenHotKey({
    required this.enabled,
    required this.control,
    required this.alt,
    required this.shift,
    required this.meta,
    required this.keyLabel,
    required this.keyCode,
  });

  factory QuickOpenHotKey.defaults() {
    return const QuickOpenHotKey(
      enabled: true,
      control: true,
      alt: true,
      shift: false,
      meta: false,
      keyLabel: 'V',
      keyCode: 0x56,
    );
  }

  factory QuickOpenHotKey.fromJson(Map<String, dynamic>? json) {
    if (json == null) return QuickOpenHotKey.defaults();
    final rawKeyCode = json['keyCode'];
    return QuickOpenHotKey(
      enabled: json['enabled'] as bool? ?? true,
      control: json['control'] as bool? ?? true,
      alt: json['alt'] as bool? ?? true,
      shift: json['shift'] as bool? ?? false,
      meta: json['meta'] as bool? ?? false,
      keyLabel: json['keyLabel'] as String? ?? 'V',
      keyCode: rawKeyCode is int
          ? rawKeyCode
          : int.tryParse('$rawKeyCode') ?? 0x56,
    );
  }

  final bool enabled;
  final bool control;
  final bool alt;
  final bool shift;
  final bool meta;
  final String keyLabel;
  final int keyCode;

  int get modifiers {
    var value = 0;
    if (alt) value |= 0x0001;
    if (control) value |= 0x0002;
    if (shift) value |= 0x0004;
    if (meta) value |= 0x0008;
    return value;
  }

  String get label {
    final parts = [
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Win',
      keyLabel,
    ];
    return parts.join(' + ');
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'control': control,
      'alt': alt,
      'shift': shift,
      'meta': meta,
      'keyLabel': keyLabel,
      'keyCode': keyCode,
    };
  }

  QuickOpenHotKey copyWith({
    bool? enabled,
    bool? control,
    bool? alt,
    bool? shift,
    bool? meta,
    String? keyLabel,
    int? keyCode,
  }) {
    return QuickOpenHotKey(
      enabled: enabled ?? this.enabled,
      control: control ?? this.control,
      alt: alt ?? this.alt,
      shift: shift ?? this.shift,
      meta: meta ?? this.meta,
      keyLabel: keyLabel ?? this.keyLabel,
      keyCode: keyCode ?? this.keyCode,
    );
  }
}

class ClipboardSettings {
  const ClipboardSettings({
    required this.retentionLimit,
    required this.excludedSources,
    required this.autoPasteFromQuickPicker,
    required this.autoSetClipboardFromSync,
    required this.captureText,
    required this.captureImages,
    required this.captureFileReferences,
    required this.quickOpenHotKey,
    required this.windowsAutoStart,
    required this.androidBackgroundSync,
    required this.androidClipboardSendPrompt,
    required this.autoCheckUpdates,
  });

  factory ClipboardSettings.defaults() {
    return const ClipboardSettings(
      retentionLimit: _defaultRetentionLimit,
      excludedSources: [],
      autoPasteFromQuickPicker: true,
      autoSetClipboardFromSync: true,
      captureText: true,
      captureImages: true,
      captureFileReferences: true,
      quickOpenHotKey: QuickOpenHotKey(
        enabled: true,
        control: true,
        alt: true,
        shift: false,
        meta: false,
        keyLabel: 'V',
        keyCode: 0x56,
      ),
      windowsAutoStart: false,
      androidBackgroundSync: true,
      androidClipboardSendPrompt: false,
      autoCheckUpdates: true,
    );
  }

  factory ClipboardSettings.fromJson(Map<String, dynamic> json) {
    final rawLimit = json['retentionLimit'];
    final limit = rawLimit is int ? rawLimit : int.tryParse('$rawLimit');
    final sources =
        (json['excludedSources'] as List<dynamic>? ?? const [])
            .map((source) => source.toString().trim())
            .where((source) => source.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ClipboardSettings(
      retentionLimit: _normalizeRetentionLimit(limit ?? _defaultRetentionLimit),
      excludedSources: sources,
      autoPasteFromQuickPicker:
          json['autoPasteFromQuickPicker'] as bool? ?? true,
      autoSetClipboardFromSync: true,
      captureText: json['captureText'] as bool? ?? true,
      captureImages: json['captureImages'] as bool? ?? true,
      captureFileReferences: json['captureFileReferences'] as bool? ?? true,
      quickOpenHotKey: QuickOpenHotKey.fromJson(
        json['quickOpenHotKey'] is Map<String, dynamic>
            ? json['quickOpenHotKey'] as Map<String, dynamic>
            : null,
      ),
      windowsAutoStart: json['windowsAutoStart'] as bool? ?? false,
      androidBackgroundSync: true,
      androidClipboardSendPrompt: false,
      autoCheckUpdates: json['autoCheckUpdates'] as bool? ?? true,
    );
  }

  final int retentionLimit;
  final List<String> excludedSources;
  final bool autoPasteFromQuickPicker;
  final bool autoSetClipboardFromSync;
  final bool captureText;
  final bool captureImages;
  final bool captureFileReferences;
  final QuickOpenHotKey quickOpenHotKey;
  final bool windowsAutoStart;
  final bool androidBackgroundSync;
  final bool androidClipboardSendPrompt;
  final bool autoCheckUpdates;

  Map<String, dynamic> toJson() {
    return {
      'retentionLimit': retentionLimit,
      'excludedSources': excludedSources,
      'autoPasteFromQuickPicker': autoPasteFromQuickPicker,
      'autoSetClipboardFromSync': autoSetClipboardFromSync,
      'captureText': captureText,
      'captureImages': captureImages,
      'captureFileReferences': captureFileReferences,
      'quickOpenHotKey': quickOpenHotKey.toJson(),
      'windowsAutoStart': windowsAutoStart,
      'androidBackgroundSync': androidBackgroundSync,
      'androidClipboardSendPrompt': androidClipboardSendPrompt,
      'autoCheckUpdates': autoCheckUpdates,
    };
  }

  ClipboardSettings copyWith({
    int? retentionLimit,
    List<String>? excludedSources,
    bool? autoPasteFromQuickPicker,
    bool? autoSetClipboardFromSync,
    bool? captureText,
    bool? captureImages,
    bool? captureFileReferences,
    QuickOpenHotKey? quickOpenHotKey,
    bool? windowsAutoStart,
    bool? androidBackgroundSync,
    bool? androidClipboardSendPrompt,
    bool? autoCheckUpdates,
  }) {
    return ClipboardSettings(
      retentionLimit: _normalizeRetentionLimit(
        retentionLimit ?? this.retentionLimit,
      ),
      excludedSources:
          (excludedSources ?? this.excludedSources)
              .map((source) => source.trim())
              .where((source) => source.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      autoPasteFromQuickPicker:
          autoPasteFromQuickPicker ?? this.autoPasteFromQuickPicker,
      autoSetClipboardFromSync:
          autoSetClipboardFromSync ?? this.autoSetClipboardFromSync,
      captureText: captureText ?? this.captureText,
      captureImages: captureImages ?? this.captureImages,
      captureFileReferences:
          captureFileReferences ?? this.captureFileReferences,
      quickOpenHotKey: quickOpenHotKey ?? this.quickOpenHotKey,
      windowsAutoStart: windowsAutoStart ?? this.windowsAutoStart,
      androidBackgroundSync:
          androidBackgroundSync ?? this.androidBackgroundSync,
      androidClipboardSendPrompt:
          androidClipboardSendPrompt ?? this.androidClipboardSendPrompt,
      autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
    );
  }
}

const List<int> _tagColorOptions = [
  0xFFE53935,
  0xFFD81B60,
  0xFF8E24AA,
  0xFF3949AB,
  0xFF1E88E5,
  0xFF00ACC1,
  0xFF00897B,
  0xFF43A047,
  0xFFC0CA33,
  0xFFFDD835,
  0xFFFB8C00,
  0xFF757575,
];

const List<_TagIconOption> _tagIconOptions = [
  _TagIconOption('tag', Icons.sell_outlined),
  _TagIconOption('work', Icons.work_outline),
  _TagIconOption('code', Icons.code),
  _TagIconOption('idea', Icons.lightbulb_outline),
  _TagIconOption('bookmark', Icons.bookmark_border),
  _TagIconOption('star', Icons.star_outline),
  _TagIconOption('alert', Icons.priority_high),
  _TagIconOption('check', Icons.check_circle_outline),
  _TagIconOption('flag', Icons.flag_outlined),
  _TagIconOption('schedule', Icons.schedule),
  _TagIconOption('lock', Icons.lock_outline),
  _TagIconOption('person', Icons.person_outline),
  _TagIconOption('chat', Icons.chat_bubble_outline),
  _TagIconOption('link', Icons.link),
  _TagIconOption('image', Icons.image_outlined),
  _TagIconOption('file', Icons.insert_drive_file_outlined),
  _TagIconOption('folder', Icons.folder_outlined),
  _TagIconOption('terminal', Icons.terminal),
  _TagIconOption('database', Icons.storage_outlined),
  _TagIconOption('cloud', Icons.cloud_outlined),
];

class OpenCbApp extends StatefulWidget {
  const OpenCbApp({super.key});

  @override
  State<OpenCbApp> createState() => _OpenCbAppState();
}

class _OpenCbAppState extends State<OpenCbApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.light;
  M3ThemePreset _themePreset = _m3ThemePresets.first;
  AppLanguage _language = AppLanguage.vi;

  Brightness get _effectiveSystemUiBrightness {
    return switch (_themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
  }

  void _applyCurrentAndroidSystemUiStyle() {
    final brightness = _effectiveSystemUiBrightness;
    final colorScheme = _colorSchemeForPreset(_themePreset, brightness);
    _applyAndroidSystemUiStyle(
      brightness,
      navigationBarColor: colorScheme.surfaceContainerLowest,
      statusBarColor: colorScheme.surfaceContainerLowest,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyCurrentAndroidSystemUiStyle();
    _loadThemeSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyCurrentAndroidSystemUiStyle();
    });
  }

  Future<void> _loadThemeSettings() async {
    try {
      final file = await _themeFile();
      if (!await file.exists()) return;
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final preset = _presetById(decoded['presetId'] as String?);
      final mode = _themeModeFromName(decoded['themeMode'] as String?);
      final language = AppLanguage.fromStorageValue(
        decoded['language'] as String?,
      );
      if (!mounted) return;
      setState(() {
        _themePreset = preset;
        _themeMode = mode;
        _language = language;
      });
      _applyCurrentAndroidSystemUiStyle();
    } catch (_) {
      // Keep default light Material 3 theme when settings are unreadable.
    }
  }

  Future<void> _saveThemeSettings() async {
    final file = await _themeFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert({
        'themeMode': _themeMode.name,
        'presetId': _themePreset.id,
        'language': _language.storageValue,
      }),
    );
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    _applyCurrentAndroidSystemUiStyle();
    _saveThemeSettings();
  }

  void _setThemePreset(M3ThemePreset preset) {
    setState(() => _themePreset = preset);
    _applyCurrentAndroidSystemUiStyle();
    _saveThemeSettings();
  }

  void _setLanguage(AppLanguage language) {
    setState(() => _language = language);
    _saveThemeSettings();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OpenCB',
      locale: _language.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: _buildTheme(Brightness.light, _themePreset),
      darkTheme: _buildTheme(Brightness.dark, _themePreset),
      themeMode: _themeMode,
      home: ClipboardHomePage(
        themeMode: _themeMode,
        themePreset: _themePreset,
        language: _language,
        onThemeModeChanged: _setThemeMode,
        onThemePresetChanged: _setThemePreset,
        onLanguageChanged: _setLanguage,
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness, M3ThemePreset preset) {
  final colorScheme = _colorSchemeForPreset(preset, brightness);
  final typography = Typography.material2021();
  final textTheme =
      (brightness == Brightness.dark ? typography.white : typography.black)
          .apply(
            bodyColor: colorScheme.onSurface,
            displayColor: colorScheme.onSurface,
          );
  final labelLarge = textTheme.labelLarge?.copyWith(
    fontWeight: FontWeight.w600,
    leadingDistribution: TextLeadingDistribution.even,
  );
  final interactiveCursor = WidgetStateProperty.resolveWith<MouseCursor?>(
    (states) => states.contains(WidgetState.disabled)
        ? SystemMouseCursors.basic
        : SystemMouseCursors.click,
  );
  final buttonStyle = ButtonStyle(
    alignment: Alignment.center,
    fixedSize: const WidgetStatePropertyAll(Size.fromHeight(40)),
    minimumSize: const WidgetStatePropertyAll(Size(64, 40)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
    mouseCursor: interactiveCursor,
    tapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    textStyle: WidgetStatePropertyAll(labelLarge),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    visualDensity: VisualDensity.standard,
    textTheme: textTheme,
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(style: buttonStyle),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        alignment: Alignment.center,
        minimumSize: const WidgetStatePropertyAll(Size.square(40)),
        mouseCursor: interactiveCursor,
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      ),
    ),
    checkboxTheme: CheckboxThemeData(mouseCursor: interactiveCursor),
    switchTheme: SwitchThemeData(mouseCursor: interactiveCursor),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      indicatorColor: colorScheme.secondaryContainer,
      selectedIconTheme: IconThemeData(color: colorScheme.onSecondaryContainer),
      selectedLabelTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide(color: colorScheme.outlineVariant),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant, height: 1.0),
    ),
  );
}

ColorScheme _colorSchemeForPreset(M3ThemePreset preset, Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: preset.seedColor,
    brightness: brightness,
  );
  return switch (preset.id) {
    'mono_black_white' =>
      brightness == Brightness.dark
          ? base.copyWith(
              primary: const Color(0xFFE5E5E5),
              onPrimary: const Color(0xFF1A1A1A),
              primaryContainer: const Color(0xFF3A3A3A),
              onPrimaryContainer: const Color(0xFFF2F2F2),
              secondary: const Color(0xFFC7C7C7),
              onSecondary: const Color(0xFF242424),
              secondaryContainer: const Color(0xFF343434),
              onSecondaryContainer: const Color(0xFFEDEDED),
              tertiary: const Color(0xFFBDBDBD),
              onTertiary: const Color(0xFF202020),
              tertiaryContainer: const Color(0xFF2F2F2F),
              onTertiaryContainer: const Color(0xFFEAEAEA),
            )
          : base.copyWith(
              primary: const Color(0xFF111111),
              onPrimary: Colors.white,
              primaryContainer: const Color(0xFFE6E6E6),
              onPrimaryContainer: const Color(0xFF111111),
              secondary: const Color(0xFF555555),
              onSecondary: Colors.white,
              secondaryContainer: const Color(0xFFE0E0E0),
              onSecondaryContainer: const Color(0xFF1D1D1D),
              tertiary: const Color(0xFF707070),
              onTertiary: Colors.white,
              tertiaryContainer: const Color(0xFFE9E9E9),
              onTertiaryContainer: const Color(0xFF202020),
            ),
    'blue_grey' =>
      brightness == Brightness.dark
          ? base.copyWith(
              primary: const Color(0xFFB9CBD3),
              onPrimary: const Color(0xFF102027),
              primaryContainer: const Color(0xFF314952),
              onPrimaryContainer: const Color(0xFFD7EAF1),
              secondary: const Color(0xFFC1CED4),
              onSecondary: const Color(0xFF253238),
              secondaryContainer: const Color(0xFF3A4A51),
              onSecondaryContainer: const Color(0xFFDDE8ED),
              tertiary: const Color(0xFFAFC9DA),
              onTertiary: const Color(0xFF193240),
              tertiaryContainer: const Color(0xFF304D5C),
              onTertiaryContainer: const Color(0xFFD3EAF7),
            )
          : base.copyWith(
              primary: const Color(0xFF455A64),
              onPrimary: Colors.white,
              primaryContainer: const Color(0xFFD7E4EA),
              onPrimaryContainer: const Color(0xFF102027),
              secondary: const Color(0xFF607D8B),
              onSecondary: Colors.white,
              secondaryContainer: const Color(0xFFDCE8ED),
              onSecondaryContainer: const Color(0xFF1B2A30),
              tertiary: const Color(0xFF546E7A),
              onTertiary: Colors.white,
              tertiaryContainer: const Color(0xFFD8E7EF),
              onTertiaryContainer: const Color(0xFF152A34),
            ),
    _ => base,
  };
}

class ClipboardHomePage extends StatefulWidget {
  const ClipboardHomePage({
    super.key,
    required this.themeMode,
    required this.themePreset,
    required this.language,
    required this.onThemeModeChanged,
    required this.onThemePresetChanged,
    required this.onLanguageChanged,
  });

  final ThemeMode themeMode;
  final M3ThemePreset themePreset;
  final AppLanguage language;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<M3ThemePreset> onThemePresetChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  State<ClipboardHomePage> createState() => _ClipboardHomePageState();
}

class _ClipboardHomePageState extends State<ClipboardHomePage>
    with WidgetsBindingObserver {
  static const Duration _quickPickerExitDuration = Duration(milliseconds: 130);
  static const List<String> _mobileMainSections = [
    'Lịch sử',
    'Gửi file',
    'Thiết bị',
    'Cài đặt',
  ];
  static const MethodChannel _windowsClipboardChannel = MethodChannel(
    'opencb/windows_clipboard',
  );
  static const MethodChannel _platformChannel = MethodChannel(
    'opencb/platform',
  );

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final PageController _mobilePageController = PageController();
  final GlobalKey _desktopDetailActionBarKey = GlobalKey();
  Timer? _pollTimer;
  Timer? _autoSyncTimer;
  Timer? _discoveryTimer;
  ServerSocket? _syncServer;
  ServerSocket? _fileTransferServer;
  RawDatagramSocket? _discoverySocket;
  int _selectedIndex = 0;
  int? _mobilePageAnimationTargetIndex;
  double? _mobileToolbarDragPosition;
  bool _mobileToolbarDragging = false;
  bool _settingsUpdatePageOpen = false;
  _HistoryScopeFilter _historyScopeFilter = _HistoryScopeFilter.all;
  bool _capturePaused = false;
  bool _lanSyncEnabled = true;
  bool _loaded = false;
  bool _autoSyncInFlight = false;
  bool _quickPickerMode = false;
  bool _quickPickerClosing = false;
  bool _openingMainFromQuickPicker = false;
  bool _syncHostRefreshInFlight = false;
  bool _mobileSearchOpen = false;
  bool _checkingForUpdates = false;
  bool _appInForeground = true;
  DateTime _lastDiscoveredDevicePruneAt = DateTime.fromMillisecondsSinceEpoch(
    0,
  );
  DateTime _lastDiscoverySubnetSweepAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _quickPickerCloseFuture;
  final int _syncPort = _defaultSyncPort;
  String _syncHost = Platform.localHostname;
  String _section = 'Lịch sử';
  ClipboardKind? _kindFilter;
  FileTransferStatus? _fileTransferStatusFilter;
  String? _syncError;
  String? _latestUpdateMessage;
  String? _lastClipboardText;
  String _lastAndroidBackgroundNotificationDevicesKey = '';
  OpenCbStorage? _storage;
  LocalSyncIdentity _syncIdentity = LocalSyncIdentity.create();
  ClipboardSettings _clipboardSettings = ClipboardSettings.defaults();
  Map<String, Uint8List> _sourceIcons = {};
  Map<String, TagDefinition> _tagDefinitions = {};
  final Set<String> _tagFilters = {};
  Set<String> _bulkSelectedIds = {};
  bool _bulkSelectMode = false;
  String? _promotedEntryId;
  int _promotionToken = 0;
  final Set<String> _pendingDeleteIds = {};
  final Map<String, Timer> _pendingDeleteTimers = {};
  final Map<String, DateTime> _syncTombstones = {};
  final Map<String, DateTime> _peerDiscoveryRetryAfter = {};
  final Map<String, DateTime> _discoveryReplyAfter = {};
  final Map<String, ({int bytes, DateTime at})> _fileTransferSpeedSamples = {};
  final Map<String, Completer<bool>> _pendingFileOfferDecisions = {};
  final Map<String, FileTransferRecord> _pendingFileOfferRecords = {};
  final Map<String, Socket> _activeFileTransferSockets = {};
  final Set<String> _canceledFileTransferIds = {};
  final Set<String> _fileTransferTargetIds = {};
  OverlayEntry? _noticeOverlayEntry;
  Timer? _noticeOverlayTimer;
  bool _showingPendingFileOfferDialog = false;
  bool _draggingTransferFiles = false;
  bool _androidIgnoringBatteryOptimizations = false;
  List<ClipboardEntry> _entries = [];
  List<SyncPeer> _peers = [];
  List<FileTransferRecord> _fileTransfers = [];
  List<FileTransferFile> _selectedTransferFiles = [];
  final List<String> _pendingAndroidClipboardTexts = [];
  Map<String, DiscoveredSyncDevice> _discoveredDevices = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platformChannel.setMethodCallHandler(_handlePlatformMethodCall);
    _refreshSyncHost();
    _initializeStorage();
    _loadFileTransfers();
    _initializeSync();
    unawaited(_consumePendingSharedFiles());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _autoSyncTimer?.cancel();
    _discoveryTimer?.cancel();
    _discoverySocket?.close();
    for (final timer in _pendingDeleteTimers.values) {
      timer.cancel();
    }
    _syncServer?.close();
    _fileTransferServer?.close();
    for (final socket in _activeFileTransferSockets.values) {
      socket.destroy();
    }
    for (final completer in _pendingFileOfferDecisions.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _noticeOverlayTimer?.cancel();
    _noticeOverlayEntry?.remove();
    _windowsClipboardChannel.setMethodCallHandler(null);
    _platformChannel.setMethodCallHandler(null);
    _storage?.close();
    _mobilePageController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    if (_appInForeground) {
      unawaited(_refreshAndroidBatteryOptimizationStatus());
      unawaited(_captureClipboardText());
      unawaited(_syncAllPeers());
      unawaited(_showNextPendingFileOfferDialog());
    }
  }

  Future<dynamic> _handlePlatformMethodCall(MethodCall call) async {
    if (call.method == 'fileOfferNotificationAction') {
      final args = call.arguments;
      if (args is! Map) return null;
      final transferId = args['transferId']?.toString();
      final action = args['action']?.toString();
      if (transferId == null || action == null) return null;
      if (action == 'open') {
        unawaited(_showPendingFileOfferDialog(transferId));
        return null;
      }
      final completer = _pendingFileOfferDecisions.remove(transferId);
      _pendingFileOfferRecords.remove(transferId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(action == 'accept');
      }
      return null;
    }
    if (call.method == 'sharedFiles') {
      await _stageSharedFiles(call.arguments);
      return null;
    }
    if (call.method == 'androidClipboardText') {
      final args = call.arguments;
      if (args is! Map) return null;
      final text = args['text']?.toString();
      if (text == null || text.isEmpty) return null;
      final source = args['source']?.toString();
      await _handleAndroidClipboardText(
        text,
        source: source == null || source.isEmpty ? 'Clipboard Android' : source,
      );
      return null;
    }
    if (call.method == 'backgroundNotificationAction') {
      final args = call.arguments;
      if (args is! Map) return null;
      final action = args['action']?.toString();
      if (action == 'sendClipboard') {
        await _sendClipboardFromNotification(args['text']?.toString());
      } else if (action == 'pickFiles') {
        await _pickTransferFilesFromNotification();
      }
      return null;
    }
    return null;
  }

  Future<void> _consumePendingSharedFiles() async {
    if (!Platform.isAndroid) return;
    try {
      final files = await _platformChannel.invokeMethod<List<dynamic>>(
        'consumeSharedFiles',
      );
      if (files == null || files.isEmpty) return;
      await _stageSharedFiles(files);
    } catch (_) {}
  }

  Future<void> _consumePendingAndroidClipboardTexts() async {
    if (!Platform.isAndroid) return;
    try {
      final texts = await _platformChannel.invokeMethod<List<dynamic>>(
        'consumeAndroidClipboardTexts',
      );
      if (texts != null) {
        for (final text in texts) {
          await _handleAndroidClipboardText(
            text?.toString() ?? '',
            source: 'Clipboard Android',
          );
        }
      }
    } catch (_) {}
    while (_pendingAndroidClipboardTexts.isNotEmpty && _loaded) {
      final text = _pendingAndroidClipboardTexts.removeAt(0);
      await _captureTextValue(text, source: 'Clipboard Android');
    }
  }

  Future<void> _handleAndroidClipboardText(
    String text, {
    required String source,
  }) async {
    if (text.trim().isEmpty) return;
    if (!_loaded) {
      if (_pendingAndroidClipboardTexts.isEmpty ||
          _pendingAndroidClipboardTexts.last != text) {
        _pendingAndroidClipboardTexts.add(text);
      }
      return;
    }
    await _captureTextValue(text, source: source);
  }

  List<ClipboardEntry> _visibleEntriesForSection(
    String section, {
    _HistoryScopeFilter? historyScopeOverride,
  }) {
    Iterable<ClipboardEntry> entries = _entries.where(
      (entry) => !_pendingDeleteIds.contains(entry.id),
    );
    if (section == 'Đã ghim') {
      entries = entries.where((entry) => entry.pinned);
    }
    if (section == 'Thẻ') {
      entries = entries.where((entry) => entry.tags.isNotEmpty);
    }
    if (section == 'Lịch sử') {
      final historyScope = historyScopeOverride ?? _historyScopeFilter;
      entries = switch (historyScope) {
        _HistoryScopeFilter.all => entries,
        _HistoryScopeFilter.pinned => entries.where((entry) => entry.pinned),
        _HistoryScopeFilter.tagged => entries.where(
          (entry) => entry.tags.isNotEmpty,
        ),
      };
    }
    if (_kindFilter != null) {
      entries = entries.where((entry) => entry.kind == _kindFilter);
    }
    if (section != 'Lịch sử' && _tagFilters.isNotEmpty) {
      entries = entries.where((entry) => entry.tags.any(_tagFilters.contains));
    }

    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      entries = entries.where((entry) {
        return entry.preview.toLowerCase().contains(query) ||
            (entry.body ?? '').toLowerCase().contains(query) ||
            entry.source.toLowerCase().contains(query) ||
            entry.tags.any((tag) => tag.toLowerCase().contains(query));
      });
    }
    return entries.toList();
  }

  List<ClipboardEntry> get _visibleEntries {
    return _visibleEntriesForSection(_section);
  }

  List<String> get _availableTags => _availableEntryTags(_entries);

  ClipboardEntry? get _selectedEntry {
    final entries = _visibleEntries;
    if (entries.isEmpty) return null;
    final index = _selectedIndex.clamp(0, entries.length - 1);
    return entries[index];
  }

  int get _entryLoadLimit =>
      math.max(1200, _clipboardSettings.retentionLimit + 200);

  Future<void> _initializeStorage() async {
    final storage = await OpenCbStorage.open();
    _storage = storage;
    await _loadClipboardSettings();
    await _loadSourceIcons();
    await _loadTagDefinitions();
    await _loadSyncTombstones();
    await _migrateLegacyHistory(storage);
    await _cleanupLegacyPinnedItems(storage);
    await _loadEntries();
    await _consumePendingAndroidClipboardTexts();
    if (Platform.isWindows && _clipboardSettings.windowsAutoStart) {
      unawaited(_applyWindowsAutoStart(true));
    }
    await _syncAndroidBackgroundService(
      _clipboardSettings.androidBackgroundSync,
      openBatterySettings: false,
    );
    await _syncAndroidClipboardSendPromptPreference(
      _clipboardSettings.androidClipboardSendPrompt,
    );
    await _refreshAndroidBatteryOptimizationStatus();
    await _startNativeClipboardBridge();
    if (_clipboardSettings.autoCheckUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_checkForUpdates(userInitiated: false));
      });
    }
  }

  Future<void> _migrateLegacyHistory(OpenCbStorage storage) async {
    try {
      if (storage is LegacyJsonStorage) return;
      final markerFile = await _legacyMigrationMarkerFile();
      if (await markerFile.exists()) return;

      final file = await _historyFile();
      if (!await file.exists()) {
        await _writeLegacyMigrationMarker(markerFile);
        return;
      }

      final existingEntries = await storage.listItems(limit: 1);
      if (existingEntries.isNotEmpty) {
        await _writeLegacyMigrationMarker(markerFile);
        return;
      }

      final jsonText = await file.readAsString();
      final decoded = jsonDecode(jsonText) as List<dynamic>;
      final legacyEntries = decoded
          .whereType<Map<String, dynamic>>()
          .map(ClipboardEntry.fromJson)
          .toList();
      for (final entry in legacyEntries) {
        final stored = switch (entry.kind) {
          ClipboardKind.text => await storage.captureText(
            entry.body ?? entry.preview,
            source: entry.source,
          ),
          ClipboardKind.code => await storage.captureText(
            entry.body ?? entry.preview,
            source: entry.source,
          ),
          ClipboardKind.url => await storage.captureText(
            entry.body ?? entry.preview,
            source: entry.source,
          ),
          ClipboardKind.fileReference => await storage.captureFileReference(
            entry.filePath ?? entry.preview,
            source: entry.source,
          ),
          ClipboardKind.image =>
            entry.imageBytes == null
                ? null
                : await storage.captureImage(
                    entry.imageBytes!,
                    source: entry.source,
                  ),
        };
        if (stored == null) continue;
        if (entry.pinned) await storage.setPinned(stored.id, true);
        if (entry.tags.isNotEmpty) await storage.setTags(stored.id, entry.tags);
      }
      await _writeLegacyMigrationMarker(markerFile);
    } catch (_) {}
  }

  Future<void> _writeLegacyMigrationMarker(File markerFile) async {
    await markerFile.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await markerFile.writeAsString(
      encoder.convert({
        'migratedAt': DateTime.now().toIso8601String(),
        'source': 'clipboard_history.json',
      }),
    );
  }

  Future<void> _cleanupLegacyPinnedItems(OpenCbStorage storage) async {
    try {
      if (storage is LegacyJsonStorage) return;
      final markerFile = await _legacyPinnedCleanupMarkerFile();
      if (await markerFile.exists()) return;

      final file = await _historyFile();
      if (!await file.exists()) {
        await _writeLegacyPinnedCleanupMarker(markerFile, cleanedCount: 0);
        return;
      }

      final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
      final legacyPinnedTexts = decoded
          .whereType<Map<String, dynamic>>()
          .map(ClipboardEntry.fromJson)
          .where((entry) => entry.pinned && entry.kind == ClipboardKind.text)
          .map((entry) => (entry.body ?? entry.preview).trim())
          .where((text) => text.isNotEmpty)
          .toSet();

      if (legacyPinnedTexts.isEmpty) {
        await _writeLegacyPinnedCleanupMarker(markerFile, cleanedCount: 0);
        return;
      }

      var cleanedCount = 0;
      final entries = await storage.listItems(limit: 10000);
      for (final entry in entries) {
        final text = (entry.body ?? entry.preview).trim();
        if (!entry.pinned || !legacyPinnedTexts.contains(text)) continue;
        await storage.setPinned(entry.id, false);
        cleanedCount += 1;
      }
      await _writeLegacyPinnedCleanupMarker(
        markerFile,
        cleanedCount: cleanedCount,
      );
    } catch (_) {}
  }

  Future<void> _writeLegacyPinnedCleanupMarker(
    File markerFile, {
    required int cleanedCount,
  }) async {
    await markerFile.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await markerFile.writeAsString(
      encoder.convert({
        'cleanedAt': DateTime.now().toIso8601String(),
        'source': 'clipboard_history.json',
        'cleanedPinnedItems': cleanedCount,
      }),
    );
  }

  Future<void> _loadEntries({bool captureCurrentClipboard = true}) async {
    try {
      final storage = _storage;
      if (storage == null) return;
      _entries = (await storage.listItems(limit: _entryLoadLimit))
          .where((entry) => !_pendingDeleteIds.contains(entry.id))
          .map(_entryWithSourceIcon)
          .toList();
      _sortEntries();
    } catch (_) {
      _entries = [];
    }
    if (mounted) {
      setState(() => _loaded = true);
    }
    if (captureCurrentClipboard) {
      await _captureClipboardText();
    }
  }

  Future<void> _loadClipboardSettings() async {
    try {
      final file = await _clipboardSettingsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      _clipboardSettings = ClipboardSettings.fromJson(decoded);
    } catch (_) {
      _clipboardSettings = ClipboardSettings.defaults();
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveClipboardSettings() async {
    final file = await _clipboardSettingsFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(_clipboardSettings.toJson()));
  }

  Future<void> _updateRetentionLimit(int value) async {
    final normalized = _normalizeRetentionLimit(value);
    setState(() {
      _clipboardSettings = _clipboardSettings.copyWith(
        retentionLimit: normalized,
      );
    });
    await _saveClipboardSettings();
    await _storage?.applyRetention(maxItems: normalized);
    await _loadEntries();
  }

  Future<void> _updateClipboardSettings(ClipboardSettings settings) async {
    final previousSettings = _clipboardSettings;
    if (jsonEncode(previousSettings.quickOpenHotKey.toJson()) !=
        jsonEncode(settings.quickOpenHotKey.toJson())) {
      setState(() => _clipboardSettings = settings);
      await _saveClipboardSettings();
      await _applyQuickOpenHotKey(settings.quickOpenHotKey);
      return;
    }
    if (previousSettings.windowsAutoStart != settings.windowsAutoStart) {
      setState(() => _clipboardSettings = settings);
      await _saveClipboardSettings();
      await _applyWindowsAutoStart(settings.windowsAutoStart);
      return;
    }
    if (previousSettings.androidBackgroundSync !=
        settings.androidBackgroundSync) {
      final applied = await _applyAndroidBackgroundSyncPreference(
        settings.androidBackgroundSync,
      );
      if (!applied) return;
    }
    if (previousSettings.androidClipboardSendPrompt !=
        settings.androidClipboardSendPrompt) {
      await _syncAndroidClipboardSendPromptPreference(
        settings.androidClipboardSendPrompt,
      );
    }
    setState(() => _clipboardSettings = settings);
    await _saveClipboardSettings();
  }

  Future<void> _applyQuickOpenHotKey(QuickOpenHotKey hotKey) async {
    if (!Platform.isWindows) return;
    try {
      final registered = await _windowsClipboardChannel
          .invokeMethod<bool>('setQuickOpenHotKey', {
            'enabled': hotKey.enabled,
            'modifiers': hotKey.modifiers,
            'keyCode': hotKey.keyCode,
          });
      if (registered == false && mounted) {
        _showCenterSnackBar('Không đăng ký được phím tắt này.');
      }
    } catch (_) {}
  }

  Future<void> _applyWindowsAutoStart(bool enabled) async {
    if (!Platform.isWindows) return;
    const runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    try {
      final result = enabled
          ? await Process.run('reg', [
              'add',
              runKey,
              '/v',
              'OpenCB',
              '/t',
              'REG_SZ',
              '/d',
              '"${Platform.resolvedExecutable}" --background',
              '/f',
            ])
          : await Process.run('reg', ['delete', runKey, '/v', 'OpenCB', '/f']);
      if (enabled && result.exitCode != 0 && mounted) {
        _showCenterSnackBar('Không cập nhật được tự khởi động Windows.');
      }
    } catch (_) {
      if (mounted) {
        _showCenterSnackBar('Không cập nhật được tự khởi động Windows.');
      }
    }
  }

  Future<bool> _applyAndroidBackgroundSyncPreference(bool enabled) async {
    if (!Platform.isAndroid) return true;
    return _syncAndroidBackgroundService(enabled, openBatterySettings: enabled);
  }

  Future<void> _syncAndroidClipboardSendPromptPreference(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _platformChannel.invokeMethod<bool>(
        'setClipboardSendPromptEnabled',
        {'enabled': enabled},
      );
    } catch (_) {}
  }

  List<String> get _androidBackgroundNotificationDeviceNames {
    if (!_lanSyncEnabled) return const [];
    final seen = <String>{};
    final names = <String>[];
    for (final peer in _onlineFileTransferPeers) {
      final name = peer.name.trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
      names.add(name);
    }
    return names;
  }

  Future<void> _syncAndroidBackgroundNotificationDevices({
    bool force = false,
  }) async {
    if (!Platform.isAndroid) return;
    final names = _androidBackgroundNotificationDeviceNames;
    final key = names.join('\u0001');
    if (!force && key == _lastAndroidBackgroundNotificationDevicesKey) return;
    try {
      await _platformChannel.invokeMethod<bool>(
        'setBackgroundNotificationDevices',
        {'names': names},
      );
      _lastAndroidBackgroundNotificationDevicesKey = key;
    } catch (_) {}
  }

  Future<bool> _syncAndroidBackgroundService(
    bool enabled, {
    required bool openBatterySettings,
  }) async {
    if (!Platform.isAndroid) return true;
    try {
      if (enabled) {
        await _platformChannel
            .invokeMethod<bool>('requestNotificationPermission')
            .catchError((_) => false);
      }
      final serviceOk = await _platformChannel.invokeMethod<bool>(
        enabled ? 'startBackgroundSyncService' : 'stopBackgroundSyncService',
      );
      if (serviceOk == false && mounted) {
        _showCenterSnackBar(
          enabled
              ? 'Không bật được chạy nền Android.'
              : 'Không tắt được chạy nền Android.',
        );
        return false;
      }
      unawaited(_syncAndroidBackgroundNotificationDevices(force: true));
      if (!enabled || !openBatterySettings) return true;
      final opened = await _platformChannel.invokeMethod<bool>(
        'requestIgnoreBatteryOptimizations',
      );
      if (opened == false && mounted) {
        _showCenterSnackBar('Không mở được cài đặt tối ưu pin.');
      }
      return true;
    } catch (_) {
      if (mounted) {
        _showCenterSnackBar(
          enabled
              ? 'Không bật được chạy nền Android.'
              : 'Không tắt được chạy nền Android.',
        );
      }
      return false;
    }
  }

  Future<void> _openAndroidNotificationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      final opened = await _platformChannel.invokeMethod<bool>(
        'openNotificationSettings',
      );
      if (opened == false && mounted) {
        _showCenterSnackBar('Không mở được cài đặt thông báo.');
      }
    } catch (_) {
      if (mounted) {
        _showCenterSnackBar('Không mở được cài đặt thông báo.');
      }
    }
  }

  Future<void> _refreshAndroidBatteryOptimizationStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final ignoring = await _platformChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      if (!mounted || ignoring == null) return;
      setState(() => _androidIgnoringBatteryOptimizations = ignoring);
    } catch (_) {}
  }

  Future<void> _toggleAndroidBatteryOptimizationBypass(bool enabled) async {
    if (!Platform.isAndroid) return;
    if (enabled) {
      try {
        final opened = await _platformChannel.invokeMethod<bool>(
          'requestIgnoreBatteryOptimizations',
        );
        if (opened == false && mounted) {
          _showCenterSnackBar('Không mở được cài đặt tối ưu pin.');
        }
      } catch (_) {
        if (mounted) {
          _showCenterSnackBar('Không mở được cài đặt tối ưu pin.');
        }
      }
      await _refreshAndroidBatteryOptimizationStatus();
      return;
    }
    await _openAndroidAppSettings();
  }

  Future<void> _openAndroidAppSettings() async {
    if (!Platform.isAndroid) return;
    try {
      final opened = await _platformChannel.invokeMethod<bool>(
        'openAppSettings',
      );
      if (opened == false && mounted) {
        _showCenterSnackBar('Không mở được cài đặt ứng dụng.');
      }
    } catch (_) {
      if (mounted) {
        _showCenterSnackBar('Không mở được cài đặt ứng dụng.');
      }
    }
  }

  Future<bool> _showAndroidBackgroundNotification({
    required String title,
    required String body,
    String? transferId,
    bool showFileOfferActions = false,
    bool silent = false,
    int? autoCancelAfterMs,
  }) async {
    if (!Platform.isAndroid || _appInForeground) return false;
    try {
      return await _platformChannel.invokeMethod<bool>(
            'showOpenCbNotification',
            {
              'title': title,
              'body': body,
              ...?(transferId == null ? null : {'transferId': transferId}),
              'showFileOfferActions': showFileOfferActions,
              'silent': silent,
              ...?(autoCancelAfterMs == null
                  ? null
                  : {'autoCancelAfterMs': autoCancelAfterMs}),
            },
          ) ??
          false;
    } catch (_) {}
    return false;
  }

  Future<void> _addExcludedSource(String source) async {
    final normalized = source.trim();
    if (normalized.isEmpty) return;
    final existing = _clipboardSettings.excludedSources
        .map((item) => item.toLowerCase())
        .toSet();
    if (existing.contains(normalized.toLowerCase())) return;
    setState(() {
      _clipboardSettings = _clipboardSettings.copyWith(
        excludedSources: [..._clipboardSettings.excludedSources, normalized],
      );
    });
    await _saveClipboardSettings();
  }

  Future<void> _removeExcludedSource(String source) async {
    setState(() {
      _clipboardSettings = _clipboardSettings.copyWith(
        excludedSources: _clipboardSettings.excludedSources
            .where((item) => item.toLowerCase() != source.toLowerCase())
            .toList(),
      );
    });
    await _saveClipboardSettings();
  }

  ClipboardEntry _entryWithSourceIcon(ClipboardEntry entry) {
    final iconBytes = _sourceIcons[entry.source];
    if (iconBytes == null || iconBytes.isEmpty) return entry;
    return entry.copyWith(sourceIconBytes: iconBytes);
  }

  Future<void> _loadSourceIcons() async {
    try {
      final file = await _sourceIconsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final icons = <String, Uint8List>{};
      for (final item in decoded.entries) {
        final value = item.value;
        if (value is! String) continue;
        final bytes = Uint8List.fromList(base64Decode(value));
        if (_isPngBytes(bytes)) {
          icons[item.key] = bytes;
        }
      }
      _sourceIcons = icons;
    } catch (_) {
      _sourceIcons = {};
    }
  }

  Future<void> _saveSourceIcons() async {
    final file = await _sourceIconsFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert({
        for (final item in _sourceIcons.entries)
          item.key: base64Encode(item.value),
      }),
    );
  }

  Future<void> _rememberSourceIcon(String source, Uint8List? iconBytes) async {
    if (source.trim().isEmpty || iconBytes == null || iconBytes.isEmpty) {
      return;
    }
    if (!_isPngBytes(iconBytes)) return;
    final existing = _sourceIcons[source];
    if (existing != null &&
        existing.length == iconBytes.length &&
        _sameBytes(existing, iconBytes)) {
      return;
    }
    _sourceIcons[source] = iconBytes;
    await _saveSourceIcons();
  }

  Future<void> _loadTagDefinitions() async {
    try {
      final file = await _tagDefinitionsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List<dynamic>) return;
      _tagDefinitions = {
        for (final item in decoded.whereType<Map<String, dynamic>>())
          if ((item['name'] as String? ?? '').trim().isNotEmpty)
            (item['name'] as String).trim(): TagDefinition.fromJson(item),
      };
    } catch (_) {
      _tagDefinitions = {};
    }
  }

  Future<void> _saveTagDefinitions() async {
    final file = await _tagDefinitionsFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(
        _tagDefinitions.values.map((definition) => definition.toJson()).toList()
          ..sort(
            (a, b) => a['name'].toString().compareTo(b['name'].toString()),
          ),
      ),
    );
  }

  Future<void> _loadSyncTombstones() async {
    try {
      final file = await _syncTombstonesFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List<dynamic>) return;
      _syncTombstones
        ..clear()
        ..addAll(_parseSyncTombstones(decoded));
      await _pruneAndSaveSyncTombstones();
    } catch (_) {
      _syncTombstones.clear();
    }
  }

  Future<void> _saveSyncTombstones() async {
    final file = await _syncTombstonesFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(_syncTombstonesPayload()));
  }

  Future<void> _pruneAndSaveSyncTombstones() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    _syncTombstones.removeWhere((_, deletedAt) => deletedAt.isBefore(cutoff));
    if (_syncTombstones.length > 5000) {
      final sorted = _syncTombstones.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _syncTombstones
        ..clear()
        ..addEntries(sorted.take(5000));
    }
    await _saveSyncTombstones();
  }

  List<Map<String, dynamic>> _tagDefinitionsPayload() {
    final definitions = _tagDefinitions.values
        .map((definition) => definition.toJson())
        .toList();
    definitions.sort(
      (a, b) => a['name'].toString().compareTo(b['name'].toString()),
    );
    return definitions;
  }

  Map<String, TagDefinition> _parseRemoteTagDefinitions(Object? value) {
    final definitions = <String, TagDefinition>{};
    void addDefinition(Map<String, dynamic> json, [String? fallbackName]) {
      final name = (json['name'] as String? ?? fallbackName ?? '').trim();
      if (name.isEmpty) return;
      definitions[name] = TagDefinition.fromJson({...json, 'name': name});
    }

    if (value is List<dynamic>) {
      for (final item in value.whereType<Map<String, dynamic>>()) {
        addDefinition(item);
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        final item = entry.value;
        if (item is Map<String, dynamic>) {
          addDefinition(item, entry.key.toString());
        } else if (item is Map) {
          addDefinition(Map<String, dynamic>.from(item), entry.key.toString());
        }
      }
    }
    return definitions;
  }

  Future<bool> _mergeRemoteTagDefinitions(
    Object? value, {
    required bool replaceExisting,
  }) async {
    final remoteDefinitions = _parseRemoteTagDefinitions(value);
    if (remoteDefinitions.isEmpty) return false;
    var changed = false;
    final nextDefinitions = Map<String, TagDefinition>.from(_tagDefinitions);
    for (final entry in remoteDefinitions.entries) {
      final current = nextDefinitions[entry.key];
      final remote = entry.value;
      if (current == null ||
          (replaceExisting &&
              (current.colorValue != remote.colorValue ||
                  current.iconKey != remote.iconKey))) {
        nextDefinitions[entry.key] = remote;
        changed = true;
      }
    }
    if (!changed) return false;
    _tagDefinitions = nextDefinitions;
    await _saveTagDefinitions();
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _initializeSync() async {
    await _loadSyncIdentity();
    await _loadPeers();
    await _startSyncServer();
    await _startFileTransferServer();
    await _startLanDiscovery();
    _startAutoSync();
    unawaited(_syncAndroidBackgroundNotificationDevices(force: true));
  }

  Future<void> _refreshSyncHost() async {
    if (_syncHostRefreshInFlight) return;
    _syncHostRefreshInFlight = true;
    final String? host;
    try {
      host = await _detectLanIpv4Address();
    } finally {
      _syncHostRefreshInFlight = false;
    }
    if (!mounted || host == null || host == _syncHost) return;
    final nextHost = host;
    setState(() => _syncHost = nextHost);
  }

  Future<void> _loadSyncIdentity() async {
    try {
      final file = await _syncIdentityFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          _syncIdentity = LocalSyncIdentity.fromJson(decoded);
        }
      } else {
        await _saveSyncIdentity();
      }
    } catch (_) {
      _syncIdentity = LocalSyncIdentity.create();
      await _saveSyncIdentity();
    }
    await _upgradeLocalDeviceNameIfNeeded();
    if (mounted) setState(() {});
  }

  Future<void> _upgradeLocalDeviceNameIfNeeded() async {
    if (!_isPlaceholderSyncDeviceName(_syncIdentity.deviceName)) return;
    final deviceName = await _resolveLocalDeviceName();
    if (deviceName == null || _isPlaceholderSyncDeviceName(deviceName)) return;
    _syncIdentity = _syncIdentity.copyWith(deviceName: deviceName);
    await _saveSyncIdentity();
  }

  Future<String?> _resolveLocalDeviceName() async {
    if (Platform.isAndroid) {
      try {
        final nativeName = await _platformChannel.invokeMethod<String>(
          'getDeviceName',
        );
        final trimmedName = nativeName?.trim();
        if (trimmedName != null && trimmedName.isNotEmpty) {
          return trimmedName;
        }
      } catch (_) {
        // Fallback below keeps older Android builds usable.
      }
    }
    final hostname = Platform.localHostname.trim();
    if (_isPlaceholderSyncDeviceName(hostname)) return null;
    return hostname;
  }

  Future<void> _saveSyncIdentity() async {
    final file = await _syncIdentityFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(_syncIdentity.toJson()));
  }

  Future<void> _loadPeers() async {
    try {
      final file = await _peersFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        _peers = decoded
            .whereType<Map<String, dynamic>>()
            .map(SyncPeer.fromJson)
            .toList();
      }
    } catch (_) {
      _peers = [];
    }
    if (mounted) setState(() {});
    unawaited(_syncAndroidBackgroundNotificationDevices(force: true));
  }

  Future<void> _savePeers() async {
    final file = await _peersFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(_peers.map((peer) => peer.toJson()).toList()),
    );
    unawaited(_syncAndroidBackgroundNotificationDevices(force: true));
  }

  Future<void> _startSyncServer() async {
    if (!_lanSyncEnabled || _syncServer != null) return;
    try {
      _syncServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _syncPort,
        shared: true,
      );
      _syncServer!.listen(_handleSyncSocket, onError: (_) {});
      if (mounted) {
        setState(() => _syncError = null);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _syncError = 'Port $_syncPort không khả dụng');
      }
    }
  }

  Future<void> _stopSyncServer() async {
    await _syncServer?.close();
    _syncServer = null;
  }

  Future<void> _startFileTransferServer() async {
    if (!_lanSyncEnabled || _fileTransferServer != null) return;
    try {
      _fileTransferServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _defaultFileTransferPort,
        shared: true,
      );
      _fileTransferServer!.listen(_handleFileTransferSocket, onError: (_) {});
    } catch (error) {
      if (mounted && _syncError == null) {
        setState(
          () =>
              _syncError = 'Port file $_defaultFileTransferPort không khả dụng',
        );
      }
    }
  }

  Future<void> _stopFileTransferServer() async {
    await _fileTransferServer?.close();
    _fileTransferServer = null;
    for (final socket in _activeFileTransferSockets.values) {
      socket.destroy();
    }
    _activeFileTransferSockets.clear();
  }

  Future<void> _startLanDiscovery() async {
    if (!_lanSyncEnabled || _discoverySocket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _syncPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      socket.broadcastEnabled = true;
      socket.listen(_handleDiscoveryEvent, onError: (_) {});
      _discoverySocket = socket;
      unawaited(_sendDiscoveryBeacon());
      unawaited(_syncAndroidBackgroundNotificationDevices(force: true));
      _discoveryTimer?.cancel();
      _discoveryTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        unawaited(_sendDiscoveryBeacon());
        unawaited(_syncAndroidBackgroundNotificationDevices());
      });
    } catch (_) {}
  }

  void _stopLanDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    if (mounted) setState(() => _discoveredDevices = {});
    unawaited(_syncAndroidBackgroundNotificationDevices(force: true));
  }

  void _handleDiscoveryEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _discoverySocket;
    if (socket == null) return;
    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      _handleDiscoveryDatagram(datagram!);
    }
  }

  Future<void> _sendDiscoveryBeacon() async {
    final socket = _discoverySocket;
    if (!_lanSyncEnabled || socket == null) return;
    _pruneStaleDiscoveredDevices();
    final detectedHost = await _detectLanIpv4Address();
    final beaconHost = detectedHost ?? _syncHost;
    if (mounted && detectedHost != null && detectedHost != _syncHost) {
      setState(() => _syncHost = detectedHost);
    }
    final payload = _discoveryPayload(beaconHost);
    final bytes = utf8.encode(payload);
    final targets = {
      for (final target in await _discoveryBroadcastTargets()) target.address,
      for (final peer in _peers)
        if (_isUsableLanIpv4(peer.host)) peer.host,
    };
    final now = DateTime.now();
    if (_appInForeground &&
        now.difference(_lastDiscoverySubnetSweepAt) >=
            _discoverySubnetSweepInterval) {
      _lastDiscoverySubnetSweepAt = now;
      targets.addAll(_classCSubnetTargets(beaconHost));
    }
    for (final target in targets) {
      try {
        socket.send(bytes, InternetAddress(target), _syncPort);
      } catch (_) {}
    }
  }

  String _discoveryPayload(String beaconHost) {
    return jsonEncode({
      'protocol': _discoveryProtocol,
      'deviceId': _syncIdentity.deviceId,
      'deviceName': _syncIdentity.deviceName,
      'host': beaconHost,
      'port': _syncPort,
      'filePort': _defaultFileTransferPort,
    });
  }

  Future<void> _sendDiscoveryReply(String target) async {
    final socket = _discoverySocket;
    if (!_lanSyncEnabled || socket == null || !_isUsableLanIpv4(target)) return;
    final now = DateTime.now();
    final retryAfter = _discoveryReplyAfter[target];
    if (retryAfter != null && now.isBefore(retryAfter)) return;
    _discoveryReplyAfter[target] = now.add(_discoveryReplyThrottle);
    final detectedHost = await _detectLanIpv4Address();
    final beaconHost = detectedHost ?? _syncHost;
    try {
      socket.send(
        utf8.encode(_discoveryPayload(beaconHost)),
        InternetAddress(target),
        _syncPort,
      );
    } catch (_) {}
  }

  void _handleDiscoveryDatagram(Datagram datagram) {
    try {
      final decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['protocol'] != _discoveryProtocol) return;
      final deviceId = decoded['deviceId']?.toString();
      if (deviceId == null ||
          deviceId.isEmpty ||
          deviceId == _syncIdentity.deviceId) {
        return;
      }
      final deviceName = decoded['deviceName']?.toString().trim();
      final payloadHost = decoded['host']?.toString().trim();
      final host = _isUsableLanIpv4(payloadHost ?? '')
          ? payloadHost!
          : datagram.address.address;
      final portValue = decoded['port'];
      final port = portValue is int ? portValue : int.tryParse('$portValue');
      final filePortValue = decoded['filePort'];
      final filePort = filePortValue is int
          ? filePortValue
          : int.tryParse('$filePortValue');
      if (!_isUsableLanIpv4(host) ||
          port == null ||
          port <= 0 ||
          port > 65535) {
        return;
      }

      final discovered = DiscoveredSyncDevice(
        id: deviceId,
        name: deviceName == null || deviceName.isEmpty
            ? 'Thiết bị LAN'
            : deviceName,
        host: host,
        port: port,
        filePort: filePort == null || filePort <= 0 || filePort > 65535
            ? _defaultFileTransferPort
            : filePort,
        lastSeenAt: DateTime.now(),
      );
      _rememberDiscoveredDevice(discovered);
      unawaited(_sendDiscoveryReply(datagram.address.address));
    } catch (_) {}
  }

  void _rememberDiscoveredDevice(DiscoveredSyncDevice device) {
    var shouldSavePeers = false;
    final peerIndex = _peers.indexWhere((peer) => peer.id == device.id);
    setState(() {
      _discoveredDevices = {..._discoveredDevices, device.id: device};
      if (peerIndex >= 0) {
        final peer = _peers[peerIndex];
        if (peer.host != device.host ||
            peer.port != device.port ||
            peer.filePort != device.filePort) {
          _peers[peerIndex] = peer.copyWith(
            host: device.host,
            port: device.port,
            filePort: device.filePort,
            clearError: true,
          );
          shouldSavePeers = true;
        }
      }
    });
    if (shouldSavePeers) unawaited(_savePeers());
    unawaited(_syncAndroidBackgroundNotificationDevices());
    if (peerIndex >= 0) _maybeRetryDiscoveredPeer(device.id);
  }

  void _pruneStaleDiscoveredDevices() {
    final now = DateTime.now();
    if (now.difference(_lastDiscoveredDevicePruneAt) <
        _discoveredDevicePruneInterval) {
      return;
    }
    _lastDiscoveredDevicePruneAt = now;
    final cutoff = now.subtract(_discoveredDeviceCacheWindow);
    final freshDevices = Map<String, DiscoveredSyncDevice>.fromEntries(
      _discoveredDevices.entries.where(
        (entry) => entry.value.lastSeenAt.isAfter(cutoff),
      ),
    );
    if (freshDevices.length == _discoveredDevices.length) return;
    if (mounted) {
      setState(() => _discoveredDevices = freshDevices);
    } else {
      _discoveredDevices = freshDevices;
    }
    unawaited(_syncAndroidBackgroundNotificationDevices());
  }

  void _maybeRetryDiscoveredPeer(String peerId) {
    if (!_lanSyncEnabled) return;
    final peerIndex = _peers.indexWhere((peer) => peer.id == peerId);
    if (peerIndex < 0) return;
    final peer = _peers[peerIndex];
    final now = DateTime.now();
    final recentGoodSync =
        peer.lastError == null &&
        peer.lastSyncedAt != null &&
        now.difference(peer.lastSyncedAt!) < const Duration(seconds: 35);
    if (recentGoodSync) return;
    final retryAfter = _peerDiscoveryRetryAfter[peerId];
    if (retryAfter != null && now.isBefore(retryAfter)) return;
    _peerDiscoveryRetryAfter[peerId] = now.add(const Duration(seconds: 24));
    unawaited(_syncPeer(peer));
  }

  Future<void> _handleSyncSocket(Socket socket) async {
    try {
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      final request = jsonDecode(line) as Map<String, dynamic>;
      if (request['protocol'] != _syncProtocol) {
        throw const FormatException('Giao thức sync không được hỗ trợ');
      }
      if (!_isTrustedSyncRequest(request)) {
        throw const FormatException('Mã pairing không hợp lệ');
      }
      if (request['action'] == 'pairRequest') {
        final accepted = await _acceptPairRequest(
          request,
          socket.remoteAddress.address,
        );
        if (!accepted) {
          socket.writeln(
            jsonEncode({
              'protocol': _syncProtocol,
              'action': 'pairRejected',
              'error': 'Thiết bị kia đã từ chối ghép nối.',
            }),
          );
          await socket.flush();
          return;
        }
        socket.writeln(
          jsonEncode({..._syncPayload(), 'action': 'pairAccepted'}),
        );
        await socket.flush();
        return;
      }
      if (request['action'] == 'unpairRequest') {
        await _acceptUnpairRequest(request);
        socket.writeln(jsonEncode(_syncPayload()));
        await socket.flush();
        return;
      }
      if (request['action'] == 'pushItems') {
        final incoming = (request['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClipboardEntry.fromJson)
            .toList();
        await _mergeSyncTombstones(request['deletedItems']);
        await _mergeRemoteTagDefinitions(
          request['tagDefinitions'],
          replaceExisting: request['replaceTagDefinitions'] as bool? ?? true,
        );
        await _mergeSyncedEntries(
          incoming,
          request['deviceName'] as String?,
          touchExisting: request['touchExisting'] as bool? ?? true,
          replaceMetadata: true,
        );
        socket.writeln(jsonEncode(_syncAckPayload()));
        await socket.flush();
        return;
      }
      if (request['action'] == 'deleteItems') {
        await _mergeSyncTombstones(request['deletedItems']);
        socket.writeln(jsonEncode(_syncAckPayload()));
        await socket.flush();
        return;
      }
      if (request['action'] == 'deviceUpdated') {
        await _acceptDeviceUpdatedRequest(
          request,
          socket.remoteAddress.address,
        );
        socket.writeln(jsonEncode(_syncAckPayload()));
        await socket.flush();
        return;
      }
      if (request['action'] == 'ping') {
        await _acceptDeviceUpdatedRequest(
          request,
          socket.remoteAddress.address,
        );
        unawaited(_showPongForPingRequest(request));
        socket.writeln(jsonEncode({..._syncAckPayload(), 'action': 'pong'}));
        await socket.flush();
        return;
      }
      final incoming = (request['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ClipboardEntry.fromJson)
          .toList();
      await _mergeSyncTombstones(request['deletedItems']);
      await _mergeRemoteTagDefinitions(
        request['tagDefinitions'],
        replaceExisting: false,
      );
      await _mergeSyncedEntries(incoming, request['deviceName'] as String?);

      socket.writeln(jsonEncode(_syncPayload()));
      await socket.flush();
    } catch (error) {
      socket.writeln(
        jsonEncode({'protocol': _syncProtocol, 'error': '$error'}),
      );
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  Map<String, dynamic> _syncPayload() {
    return {
      'protocol': _syncProtocol,
      'deviceId': _syncIdentity.deviceId,
      'deviceName': _syncIdentity.deviceName,
      'host': _syncHost,
      'port': _syncPort,
      'filePort': _defaultFileTransferPort,
      'pairCode': _syncIdentity.pairCode,
      'tagDefinitions': _tagDefinitionsPayload(),
      'deletedItems': _syncTombstonesPayload(),
      'items': _entries
          .where(_isLanSyncableEntry)
          .map((entry) => entry.toJson())
          .toList(),
    };
  }

  Map<String, dynamic> _syncAckPayload() {
    return {
      'protocol': _syncProtocol,
      'deviceId': _syncIdentity.deviceId,
      'deviceName': _syncIdentity.deviceName,
      'host': _syncHost,
      'port': _syncPort,
      'filePort': _defaultFileTransferPort,
      'pairCode': _syncIdentity.pairCode,
      'deletedItems': _syncTombstonesPayload(),
    };
  }

  Map<String, dynamic> _syncPayloadForPeer(SyncPeer peer) {
    return {
      ..._syncPayload(),
      'targetPairCode': peer.pairCode.trim().toUpperCase(),
    };
  }

  Map<String, dynamic> _pairRequestPayloadForPeer(SyncPeer peer) {
    return {
      ..._syncPayload(),
      'action': 'pairRequest',
      'targetPairCode': peer.pairCode.trim().toUpperCase(),
    };
  }

  Map<String, dynamic> _unpairRequestPayloadForPeer(SyncPeer peer) {
    return {
      ..._syncPayload(),
      'action': 'unpairRequest',
      'targetPairCode': peer.pairCode.trim().toUpperCase(),
    };
  }

  Map<String, dynamic> _pushItemsPayloadForPeer(
    SyncPeer peer,
    List<ClipboardEntry> items, {
    bool touchExisting = true,
  }) {
    return {
      ..._syncAckPayload(),
      'action': 'pushItems',
      'touchExisting': touchExisting,
      'replaceTagDefinitions': true,
      'targetPairCode': peer.pairCode.trim().toUpperCase(),
      'tagDefinitions': _tagDefinitionsPayload(),
      'deletedItems': _syncTombstonesPayload(),
      'items': items.map((entry) => entry.toJson()).toList(),
    };
  }

  Map<String, dynamic> _deleteItemsPayloadForPeer(
    SyncPeer peer,
    Map<String, DateTime> tombstones,
  ) {
    return {
      ..._syncAckPayload(),
      'action': 'deleteItems',
      'targetPairCode': peer.pairCode.trim().toUpperCase(),
      'deletedItems': _syncTombstonesPayload(tombstones),
    };
  }

  Map<String, dynamic> _deviceUpdatedPayloadForPeer(SyncPeer peer) {
    return {
      ..._syncAckPayload(),
      'action': 'deviceUpdated',
      'targetPairCode': peer.pairCode.trim().toUpperCase(),
    };
  }

  Map<String, dynamic> _pingPayloadForPeer(SyncPeer peer) {
    return {
      ..._syncAckPayload(),
      'action': 'ping',
      'targetPairCode': peer.pairCode.trim().toUpperCase(),
    };
  }

  Future<void> _showPongForPingRequest(Map<String, dynamic> request) async {
    const message = 'Pong!';
    if (Platform.isAndroid && !_appInForeground) {
      try {
        await _platformChannel.invokeMethod<bool>('showToast', {
          'message': message,
        });
        return;
      } catch (_) {}
    }
    if (mounted) _showCenterSnackBar(message);
  }

  bool _isTrustedSyncRequest(Map<String, dynamic> request) {
    final targetCode = request['targetPairCode']
        ?.toString()
        .trim()
        .toUpperCase();
    if (targetCode != null &&
        targetCode.isNotEmpty &&
        targetCode == _syncIdentity.pairCode) {
      return true;
    }

    final remoteDeviceId = request['deviceId']?.toString();
    if (remoteDeviceId == null || remoteDeviceId.isEmpty) return false;
    return _peers.any((peer) => peer.id == remoteDeviceId);
  }

  Future<bool> _acceptPairRequest(
    Map<String, dynamic> request,
    String socketHost,
  ) async {
    final remoteDeviceId = request['deviceId']?.toString().trim();
    if (remoteDeviceId == null ||
        remoteDeviceId.isEmpty ||
        remoteDeviceId == _syncIdentity.deviceId) {
      return false;
    }
    final remoteName = request['deviceName']?.toString().trim();
    final remoteHost = request['host']?.toString().trim();
    final host = _isUsableLanIpv4(remoteHost ?? '') ? remoteHost! : socketHost;
    final portValue = request['port'];
    final port = portValue is int ? portValue : int.tryParse('$portValue');
    final filePortValue = request['filePort'];
    final filePort = filePortValue is int
        ? filePortValue
        : int.tryParse('$filePortValue');
    final pairCode = request['pairCode']?.toString().trim().toUpperCase();
    if (!_isUsableLanIpv4(host) ||
        port == null ||
        port <= 0 ||
        port > 65535 ||
        pairCode == null ||
        pairCode.length < 6) {
      return false;
    }
    final peer = SyncPeer(
      id: remoteDeviceId,
      name: remoteName == null || remoteName.isEmpty
          ? 'Thiết bị LAN'
          : remoteName,
      host: host,
      port: port,
      pairCode: pairCode,
      filePort: filePort == null || filePort <= 0 || filePort > 65535
          ? _defaultFileTransferPort
          : filePort,
    );
    final existingPeer = _peers.any((item) => item.id == peer.id);
    final accepted = existingPeer || (await _confirmIncomingPairRequest(peer));
    if (!accepted) return false;
    await _upsertPeer(peer);
    return true;
  }

  Future<void> _acceptUnpairRequest(Map<String, dynamic> request) async {
    final remoteDeviceId = request['deviceId']?.toString().trim();
    if (remoteDeviceId == null || remoteDeviceId.isEmpty) return;
    final before = _peers.length;
    if (mounted) {
      setState(() {
        _peers = _peers.where((peer) => peer.id != remoteDeviceId).toList();
      });
    } else {
      _peers = _peers.where((peer) => peer.id != remoteDeviceId).toList();
    }
    if (_peers.length != before) await _savePeers();
  }

  Future<void> _acceptDeviceUpdatedRequest(
    Map<String, dynamic> request,
    String socketHost,
  ) async {
    final changed = _updatePeerFromSyncPayload(
      request,
      fallbackSocketHost: socketHost,
      markSynced: false,
    );
    if (changed) {
      if (mounted) setState(() {});
      await _savePeers();
    }
  }

  bool _updatePeerFromSyncPayload(
    Map<String, dynamic> payload, {
    SyncPeer? fallbackPeer,
    String? fallbackSocketHost,
    bool markSynced = true,
  }) {
    final remoteDeviceId = payload['deviceId']?.toString().trim();
    if (remoteDeviceId == null ||
        remoteDeviceId.isEmpty ||
        remoteDeviceId == _syncIdentity.deviceId) {
      return false;
    }
    final index = _peers.indexWhere(
      (peer) =>
          peer.id == remoteDeviceId ||
          (fallbackPeer != null && peer.id == fallbackPeer.id),
    );
    if (index < 0) return false;

    final current = _peers[index];
    final remoteName = payload['deviceName']?.toString().trim();
    final remoteHost = payload['host']?.toString().trim();
    final host = _isUsableLanIpv4(remoteHost ?? '')
        ? remoteHost
        : fallbackSocketHost;
    final portValue = payload['port'];
    final port = portValue is int ? portValue : int.tryParse('$portValue');
    final filePortValue = payload['filePort'];
    final filePort = filePortValue is int
        ? filePortValue
        : int.tryParse('$filePortValue');
    final pairCode = payload['pairCode']?.toString().trim().toUpperCase();

    final updated = current.copyWith(
      id: remoteDeviceId,
      name: remoteName == null || remoteName.isEmpty ? null : remoteName,
      host: host != null && _isUsableLanIpv4(host) ? host : null,
      port: port != null && port > 0 && port <= 65535 ? port : null,
      filePort: filePort != null && filePort > 0 && filePort <= 65535
          ? filePort
          : null,
      pairCode: pairCode != null && pairCode.length >= 6 ? pairCode : null,
      lastSyncedAt: markSynced ? DateTime.now() : null,
      clearError: true,
    );
    final changed =
        updated.id != current.id ||
        updated.name != current.name ||
        updated.host != current.host ||
        updated.port != current.port ||
        updated.filePort != current.filePort ||
        updated.pairCode != current.pairCode ||
        updated.lastSyncedAt != current.lastSyncedAt ||
        updated.lastError != current.lastError;
    if (changed) _peers[index] = updated;
    _rememberReachablePeer(updated);
    return changed;
  }

  void _rememberReachablePeer(SyncPeer peer) {
    if (!_isUsableLanIpv4(peer.host)) return;
    final device = DiscoveredSyncDevice(
      id: peer.id,
      name: peer.name,
      host: peer.host,
      port: peer.port,
      filePort: peer.filePort,
      lastSeenAt: DateTime.now(),
    );
    if (mounted) {
      setState(() {
        _discoveredDevices = {..._discoveredDevices, device.id: device};
      });
    } else {
      _discoveredDevices = {..._discoveredDevices, device.id: device};
    }
  }

  Future<void> _mergeSyncedEntries(
    List<ClipboardEntry> incoming,
    String? deviceName, {
    bool touchExisting = false,
    bool replaceMetadata = false,
  }) async {
    var changed = false;
    final storage = _storage;
    if (storage == null) return;
    final existingEntries = await storage.listItems(limit: _entryLoadLimit);
    final existingByBody = <String, ClipboardEntry>{};
    String? newestRealtimeBody;
    DateTime? newestRealtimeCreatedAt;
    for (final entry in existingEntries.where(_isLanSyncableEntry)) {
      final body = (entry.body ?? entry.preview).trim();
      if (body.isEmpty) continue;
      existingByBody.putIfAbsent(body, () => entry);
    }

    for (final remote in incoming.where(_isLanSyncableEntry)) {
      final body = remote.body ?? remote.preview;
      final normalizedBody = body.trim();
      if (normalizedBody.isEmpty) continue;
      if (_isTombstonedSyncEntry(remote)) continue;
      if (touchExisting &&
          (newestRealtimeCreatedAt == null ||
              remote.createdAt.isAfter(newestRealtimeCreatedAt))) {
        newestRealtimeBody = body;
        newestRealtimeCreatedAt = remote.createdAt;
      }

      var stored = existingByBody[normalizedBody];
      final wasMissing = stored == null;
      if (wasMissing || touchExisting) {
        stored = await storage.captureText(
          body,
          source: _displaySourceLabel(deviceName ?? remote.source),
        );
        if (stored != null) {
          existingByBody[normalizedBody] = stored;
          changed = true;
        }
      }

      if (stored == null) continue;

      final shouldApplyMetadata = replaceMetadata || wasMissing;
      if (!shouldApplyMetadata) continue;

      if (remote.pinned != stored.pinned) {
        await storage.setPinned(stored.id, remote.pinned);
        stored = stored.copyWith(pinned: remote.pinned);
        existingByBody[normalizedBody] = stored;
        changed = true;
      }

      final currentTags = stored.tags.toSet();
      final remoteTags = remote.tags.toSet();
      final shouldUpdateTags =
          remoteTags.length != currentTags.length ||
          !currentTags.containsAll(remoteTags);
      if (shouldUpdateTags) {
        final tags = remoteTags.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        await storage.setTags(stored.id, tags);
        stored = stored.copyWith(tags: tags);
        existingByBody[normalizedBody] = stored;
        changed = true;
      }
    }

    if (_clipboardSettings.autoSetClipboardFromSync &&
        touchExisting &&
        newestRealtimeBody != null &&
        newestRealtimeBody.isNotEmpty) {
      await _setSyncedClipboardText(newestRealtimeBody);
    }

    if (!changed) return;
    await storage.applyRetention(maxItems: _clipboardSettings.retentionLimit);
    await _loadEntries(captureCurrentClipboard: false);
    if (mounted) setState(() {});
  }

  Future<void> _setSyncedClipboardText(String text) async {
    try {
      if (Platform.isAndroid) {
        final ok = await _platformChannel.invokeMethod<bool>(
          'setAndroidClipboardText',
          {'text': text},
        );
        if (ok == true) {
          _lastClipboardText = text;
        }
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      _lastClipboardText = text;
    } catch (_) {}
  }

  List<Map<String, dynamic>> _syncTombstonesPayload([
    Map<String, DateTime>? tombstones,
  ]) {
    final source = tombstones ?? _syncTombstones;
    return source.entries
        .map(
          (entry) => {
            'signature': entry.key,
            'deletedAt': entry.value.toIso8601String(),
          },
        )
        .toList()
      ..sort(
        (a, b) =>
            (b['deletedAt'] as String).compareTo(a['deletedAt'] as String),
      );
  }

  Map<String, DateTime> _parseSyncTombstones(Object? value) {
    if (value is! List<dynamic>) return const {};
    final tombstones = <String, DateTime>{};
    for (final item in value.whereType<Map<String, dynamic>>()) {
      final signature = item['signature']?.toString().trim();
      final deletedAt = DateTime.tryParse(item['deletedAt']?.toString() ?? '');
      if (signature == null || signature.isEmpty || deletedAt == null) {
        continue;
      }
      final current = tombstones[signature];
      if (current == null || deletedAt.isAfter(current)) {
        tombstones[signature] = deletedAt;
      }
    }
    return tombstones;
  }

  Future<void> _mergeSyncTombstones(Object? value) async {
    final incoming = _parseSyncTombstones(value);
    if (incoming.isEmpty) return;
    var changed = false;
    for (final entry in incoming.entries) {
      final current = _syncTombstones[entry.key];
      if (current == null || entry.value.isAfter(current)) {
        _syncTombstones[entry.key] = entry.value;
        changed = true;
      }
    }
    final deletedLocalItems = await _applySyncTombstonesToStorage(incoming);
    if (changed) await _pruneAndSaveSyncTombstones();
    if (deletedLocalItems) {
      await _loadEntries(captureCurrentClipboard: false);
    }
  }

  Future<bool> _applySyncTombstonesToStorage(
    Map<String, DateTime> tombstones,
  ) async {
    final storage = _storage;
    if (storage == null || tombstones.isEmpty) return false;
    final entries = await storage.listItems(limit: _entryLoadLimit);
    var changed = false;
    final deletedIds = <String>{};
    for (final entry in entries.where(_isLanSyncableEntry)) {
      final signature = _syncEntrySignature(entry);
      if (signature == null) continue;
      final deletedAt = tombstones[signature];
      if (deletedAt == null || entry.createdAt.isAfter(deletedAt)) continue;
      await storage.deleteItem(entry.id);
      _pendingDeleteTimers.remove(entry.id)?.cancel();
      _pendingDeleteIds.remove(entry.id);
      deletedIds.add(entry.id);
      changed = true;
    }
    if (changed && mounted) {
      setState(() {
        _entries = _entries
            .where((entry) => !deletedIds.contains(entry.id))
            .toList();
        final visibleLength = _visibleEntries.length;
        _selectedIndex = visibleLength == 0
            ? 0
            : _selectedIndex.clamp(0, visibleLength - 1).toInt();
      });
    }
    return changed;
  }

  bool _isTombstonedSyncEntry(ClipboardEntry entry) {
    final signature = _syncEntrySignature(entry);
    if (signature == null) return false;
    final deletedAt = _syncTombstones[signature];
    return deletedAt != null && !entry.createdAt.isAfter(deletedAt);
  }

  Future<Map<String, DateTime>> _rememberDeletedEntries(
    List<ClipboardEntry> entries,
  ) async {
    final deletedAt = DateTime.now();
    final remembered = <String, DateTime>{};
    for (final entry in entries.where(_isLanSyncableEntry)) {
      final signature = _syncEntrySignature(entry);
      if (signature == null) continue;
      final current = _syncTombstones[signature];
      if (current == null || deletedAt.isAfter(current)) {
        _syncTombstones[signature] = deletedAt;
        remembered[signature] = deletedAt;
      }
    }
    if (remembered.isNotEmpty) await _pruneAndSaveSyncTombstones();
    return remembered;
  }

  Future<void> _syncPeer(SyncPeer peer) async {
    final index = _peers.indexWhere((item) => item.id == peer.id);
    try {
      final socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: const Duration(seconds: 4),
      );
      socket.writeln(jsonEncode(_syncPayloadForPeer(peer)));
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 8));
      await socket.close();

      final response = jsonDecode(line) as Map<String, dynamic>;
      if (response['error'] != null) {
        throw Exception(response['error']);
      }
      final incoming = (response['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ClipboardEntry.fromJson)
          .toList();
      await _mergeSyncTombstones(response['deletedItems']);
      await _mergeRemoteTagDefinitions(
        response['tagDefinitions'],
        replaceExisting: false,
      );
      await _mergeSyncedEntries(incoming, response['deviceName'] as String?);

      if (index >= 0) {
        _updatePeerFromSyncPayload(
          response,
          fallbackPeer: peer,
          markSynced: true,
        );
      }
    } catch (error) {
      if (index >= 0) {
        _peers[index] = peer.copyWith(lastError: _friendlySyncError(error));
      }
    }
    if (mounted) setState(() {});
    await _savePeers();
  }

  Future<void> _pushEntriesToPeer(
    SyncPeer peer,
    List<ClipboardEntry> entries, {
    bool touchExisting = true,
  }) async {
    final items = entries.where(_isLanSyncableEntry).toList();
    if (!_lanSyncEnabled || items.isEmpty) return;
    final index = _peers.indexWhere((item) => item.id == peer.id);
    try {
      final socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: const Duration(seconds: 3),
      );
      socket.writeln(
        jsonEncode(
          _pushItemsPayloadForPeer(peer, items, touchExisting: touchExisting),
        ),
      );
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 4));
      await socket.close();

      final response = jsonDecode(line) as Map<String, dynamic>;
      if (response['error'] != null) {
        throw Exception(response['error']);
      }
      await _mergeSyncTombstones(response['deletedItems']);
      if (index >= 0) {
        _updatePeerFromSyncPayload(
          response,
          fallbackPeer: peer,
          markSynced: true,
        );
      }
    } catch (error) {
      if (index >= 0) {
        _peers[index] = peer.copyWith(lastError: _friendlySyncError(error));
      }
    }
    if (mounted) setState(() {});
    await _savePeers();
  }

  Future<void> _pushTombstonesToPeer(
    SyncPeer peer,
    Map<String, DateTime> tombstones,
  ) async {
    if (!_lanSyncEnabled || tombstones.isEmpty) return;
    final index = _peers.indexWhere((item) => item.id == peer.id);
    try {
      final socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: const Duration(seconds: 3),
      );
      socket.writeln(jsonEncode(_deleteItemsPayloadForPeer(peer, tombstones)));
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 4));
      await socket.close();

      final response = jsonDecode(line) as Map<String, dynamic>;
      if (response['error'] != null) {
        throw Exception(response['error']);
      }
      await _mergeSyncTombstones(response['deletedItems']);
      if (index >= 0) {
        _updatePeerFromSyncPayload(
          response,
          fallbackPeer: peer,
          markSynced: true,
        );
      }
    } catch (error) {
      if (index >= 0) {
        _peers[index] = peer.copyWith(lastError: _friendlySyncError(error));
      }
    }
    if (mounted) setState(() {});
    await _savePeers();
  }

  Future<void> _pushTombstonesToOnlinePeers(
    Map<String, DateTime> tombstones,
  ) async {
    if (!_lanSyncEnabled || _peers.isEmpty || tombstones.isEmpty) return;
    await Future.wait(
      List<SyncPeer>.from(
        _peers,
      ).map((peer) => _pushTombstonesToPeer(peer, tombstones)),
    );
  }

  Future<void> _sendDeviceUpdatedToPeer(SyncPeer peer) async {
    if (!_lanSyncEnabled) return;
    final index = _peers.indexWhere((item) => item.id == peer.id);
    try {
      final socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: const Duration(seconds: 3),
      );
      socket.writeln(jsonEncode(_deviceUpdatedPayloadForPeer(peer)));
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 4));
      await socket.close();

      final response = jsonDecode(line) as Map<String, dynamic>;
      if (response['error'] != null) {
        throw Exception(response['error']);
      }
      _updatePeerFromSyncPayload(
        response,
        fallbackPeer: peer,
        markSynced: true,
      );
    } catch (error) {
      if (index >= 0) {
        _peers[index] = peer.copyWith(lastError: _friendlySyncError(error));
      }
    }
  }

  Future<void> _sendDeviceUpdatedToOnlinePeers() async {
    if (!_lanSyncEnabled || _peers.isEmpty) return;
    await Future.wait(
      List<SyncPeer>.from(_peers).map(_sendDeviceUpdatedToPeer),
    );
    if (mounted) setState(() {});
    await _savePeers();
  }

  Future<void> _pushEntriesToOnlinePeers(
    List<ClipboardEntry> entries, {
    bool touchExisting = true,
  }) async {
    final items = entries.where(_isLanSyncableEntry).toList();
    if (!_lanSyncEnabled || _peers.isEmpty || items.isEmpty) {
      return;
    }
    await Future.wait(
      List<SyncPeer>.from(_peers).map(
        (peer) => _pushEntriesToPeer(peer, items, touchExisting: touchExisting),
      ),
    );
  }

  Future<void> _pushEntryToOnlinePeers(
    ClipboardEntry entry, {
    bool touchExisting = true,
  }) {
    return _pushEntriesToOnlinePeers([entry], touchExisting: touchExisting);
  }

  Future<void> _syncAllPeers() async {
    if (_autoSyncInFlight) return;
    if (mounted) {
      setState(() => _autoSyncInFlight = true);
    } else {
      _autoSyncInFlight = true;
    }
    try {
      for (final peer in List<SyncPeer>.from(_peers)) {
        await _syncPeer(peer);
      }
    } finally {
      if (mounted) {
        setState(() => _autoSyncInFlight = false);
      } else {
        _autoSyncInFlight = false;
      }
    }
  }

  void _startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_lanSyncEnabled || _peers.isEmpty) return;
      _syncAllPeers();
    });
  }

  Future<void> _loadFileTransfers() async {
    try {
      final file = await _fileTransfersFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List<dynamic>) return;
      final records = decoded
          .whereType<Map<String, dynamic>>()
          .map(FileTransferRecord.fromJson)
          .map((record) {
            if (!_isActiveTransferStatus(record.status)) return record;
            return record.copyWith(
              status: FileTransferStatus.failed,
              error: 'App đã đóng trước khi hoàn tất.',
            );
          })
          .toList();
      if (mounted) {
        setState(() => _fileTransfers = records);
      } else {
        _fileTransfers = records;
      }
    } catch (_) {
      _fileTransfers = [];
    }
  }

  Future<void> _saveFileTransfers() async {
    final file = await _fileTransfersFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    final records = List<FileTransferRecord>.from(_fileTransfers)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await file.writeAsString(
      encoder.convert(
        records.take(60).map((record) => record.toJson()).toList(),
      ),
    );
  }

  void _upsertFileTransfer(FileTransferRecord record) {
    if (!mounted) {
      final index = _fileTransfers.indexWhere((item) => item.id == record.id);
      if (index >= 0) {
        _fileTransfers[index] = record;
      } else {
        _fileTransfers = [record, ..._fileTransfers].take(60).toList();
      }
      unawaited(_saveFileTransfers());
      return;
    }
    setState(() {
      final index = _fileTransfers.indexWhere((item) => item.id == record.id);
      if (index >= 0) {
        _fileTransfers[index] = record;
      } else {
        _fileTransfers = [record, ..._fileTransfers].take(60).toList();
      }
    });
    unawaited(_saveFileTransfers());
  }

  void _updateFileTransfer(
    String id, {
    FileTransferStatus? status,
    int? transferredBytes,
    String? error,
    String? saveDirectory,
  }) {
    final index = _fileTransfers.indexWhere((record) => record.id == id);
    if (index < 0) return;
    final current = _fileTransfers[index];
    int? speedBytesPerSecond;
    final nextStatus = status ?? current.status;
    if (transferredBytes != null && _isActiveTransferStatus(nextStatus)) {
      final now = DateTime.now();
      final previous = _fileTransferSpeedSamples[id];
      if (previous != null) {
        final elapsedMs = now.difference(previous.at).inMilliseconds;
        final deltaBytes = transferredBytes - previous.bytes;
        if (elapsedMs > 0 && deltaBytes >= 0) {
          final instantSpeed = (deltaBytes * 1000 / elapsedMs).round();
          final previousSpeed = current.speedBytesPerSecond;
          speedBytesPerSecond = previousSpeed <= 0
              ? instantSpeed
              : (previousSpeed * 0.65 + instantSpeed * 0.35).round();
        }
      }
      _fileTransferSpeedSamples[id] = (bytes: transferredBytes, at: now);
    }
    if (status != null && !_isActiveTransferStatus(status)) {
      speedBytesPerSecond = 0;
      _fileTransferSpeedSamples.remove(id);
    }
    final updated = _fileTransfers[index].copyWith(
      status: status,
      transferredBytes: transferredBytes,
      speedBytesPerSecond: speedBytesPerSecond,
      error: error,
      saveDirectory: saveDirectory,
    );
    _upsertFileTransfer(updated);
  }

  void _updateFileTransferSavedPath(
    String id, {
    required int index,
    required String savedPath,
  }) {
    final recordIndex = _fileTransfers.indexWhere((record) => record.id == id);
    if (recordIndex < 0) return;
    final current = _fileTransfers[recordIndex];
    if (index < 0 || index >= current.files.length) return;
    final files = List<FileTransferFile>.from(current.files);
    files[index] = files[index].copyWith(savedPath: savedPath);
    _upsertFileTransfer(current.copyWith(files: files));
  }

  Future<void> _clearFinishedFileTransferHistory() async {
    final removableCount = _fileTransfers
        .where((transfer) => !_isActiveTransferStatus(transfer.status))
        .length;
    if (removableCount == 0) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.clearTransferHistoryTitle),
        content: Text(
          '${context.l10n.clearTransferHistoryBodyPrefix} ${_localizedItemCount(context.l10n, removableCount)} ${context.l10n.clearTransferHistoryBodySuffix}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.clear),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _fileTransfers = _fileTransfers
          .where((transfer) => _isActiveTransferStatus(transfer.status))
          .toList();
      if (_fileTransferStatusFilter != null) {
        _fileTransferStatusFilter = null;
      }
    });
    unawaited(_saveFileTransfers());
  }

  List<SyncPeer> get _onlineFileTransferPeers {
    final cutoff = DateTime.now().subtract(_discoveredDeviceOnlineWindow);
    final onlinePeers = _peers.where((peer) {
      final discovered = _discoveredDevices[peer.id];
      if (discovered != null && discovered.lastSeenAt.isAfter(cutoff)) {
        return true;
      }
      return peer.lastError == null &&
          peer.lastSyncedAt != null &&
          peer.lastSyncedAt!.isAfter(cutoff);
    });
    return onlinePeers.map((peer) {
        final discovered = _discoveredDevices[peer.id];
        if (discovered == null) return peer;
        return peer.copyWith(
          host: discovered.host,
          port: discovered.port,
          filePort: discovered.filePort,
          clearError: true,
        );
      }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<Directory> _receivedFilesDirectory() async {
    if (Platform.isAndroid) {
      return Directory('Download${Platform.pathSeparator}OpenCB');
    }
    final downloads = await getDownloadsDirectory();
    final base = downloads ?? await _opencbDataDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}OpenCB');
    await dir.create(recursive: true);
    return dir;
  }

  Future<(String, String)> _openPublicDownloadFile(
    String name, {
    String? relativePath,
  }) async {
    final response = await _platformChannel.invokeMapMethod<String, String>(
      'openPublicDownloadFile',
      relativePath == null
          ? {'name': name}
          : {'name': name, 'relativePath': relativePath},
    );
    final token = response?['token'];
    final path = response?['path'] ?? 'Download/OpenCB/${_safeFileName(name)}';
    if (token == null || token.isEmpty) {
      throw const FileSystemException('Không tạo được file trong Downloads');
    }
    return (token, path);
  }

  Future<void> _writePublicDownloadChunk(String? token, Uint8List bytes) async {
    if (token == null || token.isEmpty) {
      throw const FileSystemException('Download stream chưa mở');
    }
    await _platformChannel.invokeMethod<bool>('writePublicDownloadChunk', {
      'token': token,
      'bytes': bytes,
    });
  }

  Future<void> _finishPublicDownloadFile(String? token) async {
    if (token == null || token.isEmpty) return;
    await _platformChannel.invokeMethod<bool>('finishPublicDownloadFile', {
      'token': token,
    });
  }

  Future<void> _cancelPublicDownloadFile(String? token) async {
    if (token == null || token.isEmpty) return;
    await _platformChannel.invokeMethod<bool>('cancelPublicDownloadFile', {
      'token': token,
    });
  }

  Future<File> _uniqueReceivedFile(
    Directory directory,
    String name, {
    String? relativePath,
  }) async {
    final safeRelativePath = _safeRelativeFilePath(relativePath ?? name);
    final safeName = _safeFileName(
      safeRelativePath.split(RegExp(r'[\\/]+')).last,
    );
    final relativeParts = safeRelativePath
        .split(RegExp(r'[\\/]+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    final parentParts = relativeParts.length <= 1
        ? const <String>[]
        : relativeParts.sublist(0, relativeParts.length - 1);
    var targetDirectory = directory;
    for (final part in parentParts) {
      targetDirectory = Directory(
        '${targetDirectory.path}${Platform.pathSeparator}${_safeFileName(part)}',
      );
    }
    await targetDirectory.create(recursive: true);
    final separator = Platform.pathSeparator;
    var candidate = File('${targetDirectory.path}$separator$safeName');
    if (!await candidate.exists()) return candidate;
    final dotIndex = safeName.lastIndexOf('.');
    final stem = dotIndex <= 0 ? safeName : safeName.substring(0, dotIndex);
    final extension = dotIndex <= 0 ? '' : safeName.substring(dotIndex);
    for (var index = 1; index < 10000; index += 1) {
      candidate = File(
        '${targetDirectory.path}$separator$stem ($index)$extension',
      );
      if (!await candidate.exists()) return candidate;
    }
    return File(
      '${targetDirectory.path}$separator$stem-${DateTime.now().millisecondsSinceEpoch}$extension',
    );
  }

  Future<bool> _confirmIncomingFileOffer(FileTransferRecord record) async {
    if (Platform.isAndroid && !_appInForeground) {
      final decision = Completer<bool>();
      _pendingFileOfferDecisions[record.id] = decision;
      _pendingFileOfferRecords[record.id] = record;
      final l10n = context.l10n;
      final shown = await _showAndroidBackgroundNotification(
        title: l10n.incomingFileNotificationTitle,
        body:
            '${record.peerName} ${l10n.wantsToSend} ${_localizedFileCount(l10n, record.files.length)} (${_formatBytes(record.totalBytes)}).',
        transferId: record.id,
        showFileOfferActions: true,
      );
      if (!shown) {
        _pendingFileOfferDecisions.remove(record.id);
        _pendingFileOfferRecords.remove(record.id);
        return false;
      }
      try {
        return await decision.future.timeout(
          const Duration(minutes: 5),
          onTimeout: () => false,
        );
      } finally {
        _pendingFileOfferDecisions.remove(record.id);
        _pendingFileOfferRecords.remove(record.id);
      }
    }
    return _showIncomingFileOfferDialog(record);
  }

  Future<bool> _showIncomingFileOfferDialog(FileTransferRecord record) async {
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final l10n = context.l10n;
        return AlertDialog(
          title: Text(l10n.incomingFileTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.peerName} ${l10n.wantsToSend} ${_localizedFileCount(l10n, record.files.length)} (${_formatBytes(record.totalBytes)}).',
                ),
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final file in record.files.take(4))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.insert_drive_file_outlined,
                            ),
                            title: Text(
                              file.displayPath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(_formatBytes(file.size)),
                          ),
                        if (record.files.length > 4)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _localizedMoreFileCount(
                                l10n,
                                record.files.length - 4,
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.rejected),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.file_download_outlined),
              label: Text(l10n.accept),
            ),
          ],
        );
      },
    );
    return accepted ?? false;
  }

  Future<void> _showNextPendingFileOfferDialog() async {
    if (_showingPendingFileOfferDialog || _pendingFileOfferRecords.isEmpty) {
      return;
    }
    final transferId = _pendingFileOfferRecords.keys.first;
    await _showPendingFileOfferDialog(transferId);
  }

  Future<void> _showPendingFileOfferDialog(String transferId) async {
    if (_showingPendingFileOfferDialog || !mounted) return;
    final record = _pendingFileOfferRecords[transferId];
    final completer = _pendingFileOfferDecisions[transferId];
    if (record == null || completer == null || completer.isCompleted) return;
    _showingPendingFileOfferDialog = true;
    try {
      final accepted = await _showIncomingFileOfferDialog(record);
      _pendingFileOfferDecisions.remove(transferId);
      _pendingFileOfferRecords.remove(transferId);
      if (!completer.isCompleted) completer.complete(accepted);
    } finally {
      _showingPendingFileOfferDialog = false;
    }
  }

  Future<void> _stageSharedFiles(dynamic rawFiles) async {
    final items = rawFiles is List ? rawFiles : const [];
    final files = <FileTransferFile>[];
    for (final item in items) {
      if (item is! Map) continue;
      final path = item['path']?.toString();
      final uri = item['uri']?.toString();
      if ((path == null || path.trim().isEmpty) &&
          (uri == null || uri.trim().isEmpty)) {
        continue;
      }
      final sizeValue = item['size'];
      var size = sizeValue is int ? sizeValue : int.tryParse('$sizeValue') ?? 0;
      if (size <= 0 && path != null && path.trim().isNotEmpty) {
        final file = File(path);
        if (!await file.exists()) continue;
        size = await file.length();
      }
      if (size < 0) continue;
      final name = item['name']?.toString().trim();
      files.add(
        FileTransferFile(
          name: name == null || name.isEmpty
              ? _fileNameFromPath(path ?? uri ?? 'file')
              : name,
          size: size,
          path: path,
          uri: uri,
          relativePath: item['relativePath']?.toString(),
        ),
      );
    }
    if (files.isEmpty) return;
    if (mounted) {
      setState(() {
        _selectedTransferFiles = _mergeTransferFiles(
          _selectedTransferFiles,
          files,
        );
        _openFileTransferSectionForStagedFiles();
      });
    } else {
      _selectedTransferFiles = _mergeTransferFiles(
        _selectedTransferFiles,
        files,
      );
      _openFileTransferSectionForStagedFiles();
    }
  }

  Future<void> _pickTransferFiles() async {
    if (Platform.isAndroid) {
      final result = await _platformChannel.invokeMethod<List<dynamic>>(
        'pickAndroidFiles',
      );
      if (result == null || result.isEmpty) return;
      await _stageSharedFiles(result);
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      lockParentWindow: true,
    );
    final paths =
        result?.paths
            .whereType<String>()
            .where((path) => path.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    if (paths.isEmpty) return;
    await _addTransferPaths(paths);
  }

  Future<void> _pickTransferFilesFromNotification() async {
    if (!mounted) return;
    _selectSection('Gửi file');
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    await _pickTransferFiles();
  }

  Future<void> _pickTransferFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      lockParentWindow: true,
      dialogTitle: context.l10n.chooseFolder,
    );
    if (path == null || path.trim().isEmpty) return;
    await _addTransferPaths([path]);
  }

  Future<void> _addTransferPaths(List<String> paths) async {
    final l10n = context.l10n;
    final files = <FileTransferFile>[];
    for (final path in paths) {
      final file = File(path);
      final directory = Directory(path);
      if (await file.exists()) {
        files.add(
          FileTransferFile(
            name: _fileNameFromPath(path),
            size: await file.length(),
            path: path,
          ),
        );
        continue;
      }
      if (await directory.exists()) {
        files.addAll(await _filesFromDirectory(directory));
      }
    }
    if (files.isEmpty) {
      _showCenterSnackBar(l10n.cannotReadSelectedFileOrFolder);
      return;
    }
    setState(() {
      _selectedTransferFiles = _mergeTransferFiles(
        _selectedTransferFiles,
        files,
      );
    });
  }

  Future<List<FileTransferFile>> _filesFromDirectory(
    Directory directory,
  ) async {
    final rootName = _safeFileName(_fileNameFromPath(directory.path));
    final rootPath = directory.absolute.path;
    final files = <FileTransferFile>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final path = entity.absolute.path;
      final relativePath = path
          .substring(math.min(rootPath.length, path.length))
          .replaceFirst(RegExp(r'^[\\/]+'), '');
      final safeRelativePath = _safeRelativeFilePath('$rootName/$relativePath');
      files.add(
        FileTransferFile(
          name: _fileNameFromPath(path),
          size: await entity.length(),
          path: path,
          relativePath: safeRelativePath,
        ),
      );
    }
    return files;
  }

  List<FileTransferFile> _mergeTransferFiles(
    List<FileTransferFile> current,
    List<FileTransferFile> incoming,
  ) {
    final byKey = <String, FileTransferFile>{
      for (final file in current)
        '${file.path ?? file.uri ?? file.displayPath}|${file.size}': file,
    };
    for (final file in incoming) {
      byKey['${file.path ?? file.uri ?? file.displayPath}|${file.size}'] = file;
    }
    return byKey.values.toList()..sort(
      (a, b) =>
          a.displayPath.toLowerCase().compareTo(b.displayPath.toLowerCase()),
    );
  }

  void _removeSelectedTransferFile(FileTransferFile file) {
    setState(() {
      _selectedTransferFiles = _selectedTransferFiles
          .where(
            (item) =>
                item.path != file.path ||
                item.uri != file.uri ||
                item.displayPath != file.displayPath ||
                item.size != file.size,
          )
          .toList();
    });
  }

  void _clearSelectedTransferFiles() {
    setState(() {
      _selectedTransferFiles = [];
      _fileTransferTargetIds.clear();
    });
  }

  void _toggleFileTransferTarget(String peerId) {
    setState(() {
      if (!_fileTransferTargetIds.add(peerId)) {
        _fileTransferTargetIds.remove(peerId);
      }
    });
  }

  void _toggleAllFileTransferTargets() {
    final onlineIds = _onlineFileTransferPeers.map((peer) => peer.id).toSet();
    setState(() {
      if (onlineIds.isEmpty) return;
      if (_fileTransferTargetIds.containsAll(onlineIds)) {
        _fileTransferTargetIds.removeAll(onlineIds);
      } else {
        _fileTransferTargetIds
          ..removeWhere((id) => !onlineIds.contains(id))
          ..addAll(onlineIds);
      }
    });
  }

  Future<void> _sendSelectedFilesToTargets() async {
    final l10n = context.l10n;
    final files = List<FileTransferFile>.from(_selectedTransferFiles);
    final peers = _onlineFileTransferPeers
        .where((peer) => _fileTransferTargetIds.contains(peer.id))
        .toList();
    if (files.isEmpty) {
      _showCenterSnackBar(context.l10n.chooseFileOrFolderFirst);
      return;
    }
    if (peers.isEmpty) {
      _showCenterSnackBar(context.l10n.chooseOnlineDeviceFirst);
      return;
    }
    final results = await Future.wait([
      for (final peer in peers) _sendFilesToPeer(peer, files),
    ]);
    final completedCount = results
        .where((status) => status == FileTransferStatus.completed)
        .length;
    if (completedCount == peers.length) {
      if (!mounted) return;
      setState(() {
        _selectedTransferFiles = [];
        _fileTransferTargetIds.clear();
      });
      _showCenterSnackBar(
        peers.length == 1
            ? l10n.fileSentSuccess
            : '${l10n.fileSentTo} ${_localizedDeviceCount(l10n, peers.length)}.',
        success: true,
        maxWidth: 360,
        duration: const Duration(seconds: 2),
      );
    } else if (completedCount > 0) {
      _showCenterSnackBar(
        '${l10n.fileSendPartialDone} $completedCount/${peers.length} ${l10n.deviceUnit}.',
        maxWidth: 360,
      );
    }
  }

  Future<FileTransferStatus> _sendFilesToPeer(
    SyncPeer peer,
    List<FileTransferFile> selectedFiles,
  ) async {
    final files = selectedFiles
        .where(
          (file) =>
              (file.path != null && file.path!.trim().isNotEmpty) ||
              (file.uri != null && file.uri!.trim().isNotEmpty),
        )
        .toList();
    if (files.isEmpty) {
      _showCenterSnackBar(context.l10n.cannotReadSelectedFile);
      return FileTransferStatus.failed;
    }

    final transferId = _generateTransferId();
    final totalBytes = files.fold<int>(0, (sum, file) => sum + file.size);
    final record = FileTransferRecord(
      id: transferId,
      peerId: peer.id,
      peerName: peer.name,
      direction: FileTransferDirection.send,
      status: FileTransferStatus.waiting,
      files: files,
      totalBytes: totalBytes,
      transferredBytes: 0,
      createdAt: DateTime.now(),
    );
    _upsertFileTransfer(record);

    Socket? socket;
    try {
      socket = await Socket.connect(
        peer.host,
        peer.filePort,
        timeout: const Duration(seconds: 4),
      );
      _activeFileTransferSockets[transferId] = socket;
      socket.writeln(
        jsonEncode({
          'protocol': _fileTransferProtocol,
          'action': 'fileOffer',
          'transferId': transferId,
          'deviceId': _syncIdentity.deviceId,
          'deviceName': _syncIdentity.deviceName,
          'targetPairCode': peer.pairCode.trim().toUpperCase(),
          'files': files
              .map(
                (file) => {
                  'name': file.name,
                  'size': file.size,
                  if (file.relativePath != null)
                    'relativePath': file.relativePath,
                },
              )
              .toList(),
          'totalBytes': totalBytes,
        }),
      );
      await socket.flush();
      final reader = _SocketFrameReader(socket);
      final ack = await reader.readJson(timeout: const Duration(minutes: 2));
      if (ack['action'] == 'fileRejected') {
        _updateFileTransfer(transferId, status: FileTransferStatus.rejected);
        return FileTransferStatus.rejected;
      }
      if (ack['action'] != 'fileAccepted') {
        throw const FormatException('Thiết bị nhận không xác nhận file.');
      }
      _updateFileTransfer(transferId, status: FileTransferStatus.sending);

      Completer<void>? fileStoredWaiter;
      final transferStoredWaiter = Completer<void>();
      Object? controlError;
      final controlLoop = () async {
        try {
          while (true) {
            final message = await reader.readJson(
              timeout: const Duration(minutes: 10),
            );
            final action = message['action']?.toString();
            if (action == 'transferProgress') {
              final remoteBytesValue = message['transferredBytes'];
              final remoteBytes = remoteBytesValue is int
                  ? remoteBytesValue
                  : int.tryParse('$remoteBytesValue');
              if (remoteBytes != null) {
                _updateFileTransfer(
                  transferId,
                  transferredBytes: remoteBytes.clamp(0, totalBytes).toInt(),
                );
              }
              continue;
            }
            if (action == 'fileStored') {
              final waiter = fileStoredWaiter;
              if (waiter != null && !waiter.isCompleted) {
                waiter.complete();
              }
              continue;
            }
            if (action == 'transferStored') {
              if (!transferStoredWaiter.isCompleted) {
                transferStoredWaiter.complete();
              }
              return;
            }
            if (message['error'] != null) {
              throw Exception(message['error']);
            }
          }
        } catch (error) {
          controlError = error;
          final waiter = fileStoredWaiter;
          if (waiter != null && !waiter.isCompleted) {
            waiter.completeError(error);
          }
          if (!transferStoredWaiter.isCompleted) {
            transferStoredWaiter.completeError(error);
          }
        }
      }();

      for (var index = 0; index < files.length; index += 1) {
        if (_canceledFileTransferIds.contains(transferId)) {
          throw const _FileTransferCanceledException();
        }
        final transferFile = files[index];
        if (transferFile.path == null && transferFile.uri == null) continue;
        socket.writeln(
          jsonEncode({
            'protocol': _fileTransferProtocol,
            'action': 'fileStart',
            'transferId': transferId,
            'index': index,
            'name': transferFile.name,
            if (transferFile.relativePath != null)
              'relativePath': transferFile.relativePath,
            'size': transferFile.size,
          }),
        );
        await socket.flush();
        await _streamTransferFileToSocket(
          transferFile,
          socket,
          transferId: transferId,
        );
        await socket.flush();
        final currentFileStoredWaiter = Completer<void>();
        fileStoredWaiter = currentFileStoredWaiter;
        socket.writeln(
          jsonEncode({
            'protocol': _fileTransferProtocol,
            'action': 'fileEnd',
            'transferId': transferId,
            'index': index,
          }),
        );
        await socket.flush();
        await currentFileStoredWaiter.future.timeout(
          const Duration(minutes: 2),
        );
        fileStoredWaiter = null;
        if (controlError != null) throw controlError!;
      }
      socket.writeln(
        jsonEncode({
          'protocol': _fileTransferProtocol,
          'action': 'transferComplete',
          'transferId': transferId,
        }),
      );
      await socket.flush();
      await transferStoredWaiter.future.timeout(const Duration(minutes: 2));
      if (controlError != null) throw controlError!;
      await controlLoop.catchError((_) {});
      _updateFileTransfer(
        transferId,
        status: FileTransferStatus.completed,
        transferredBytes: totalBytes,
      );
      return FileTransferStatus.completed;
    } on _FileTransferCanceledException {
      _updateFileTransfer(transferId, status: FileTransferStatus.canceled);
      return FileTransferStatus.canceled;
    } catch (error) {
      _updateFileTransfer(
        transferId,
        status: FileTransferStatus.failed,
        error: _friendlySyncError(error),
      );
      return FileTransferStatus.failed;
    } finally {
      _activeFileTransferSockets.remove(transferId);
      _canceledFileTransferIds.remove(transferId);
      await socket?.close().catchError((_) {});
    }
  }

  Future<void> _streamTransferFileToSocket(
    FileTransferFile transferFile,
    Socket socket, {
    required String transferId,
  }) async {
    final path = transferFile.path;
    if (path != null && path.trim().isNotEmpty) {
      await for (final chunk in File(path).openRead()) {
        if (_canceledFileTransferIds.contains(transferId)) {
          throw const _FileTransferCanceledException();
        }
        socket.add(chunk);
      }
      return;
    }

    final uri = transferFile.uri;
    if (uri == null || uri.trim().isEmpty) {
      throw const FileSystemException('Không có nguồn file để gửi');
    }
    final token = await _platformChannel.invokeMethod<String>(
      'openContentInputStream',
      {'uri': uri},
    );
    if (token == null || token.isEmpty) {
      throw const FileSystemException('Không mở được file Android');
    }
    try {
      while (true) {
        if (_canceledFileTransferIds.contains(transferId)) {
          throw const _FileTransferCanceledException();
        }
        final chunk = await _platformChannel.invokeMethod<Uint8List>(
          'readContentInputChunk',
          {'token': token, 'size': _androidContentReadChunkBytes},
        );
        if (chunk == null || chunk.isEmpty) break;
        socket.add(chunk);
        if (chunk.length < _androidContentReadChunkBytes) break;
      }
    } finally {
      await _platformChannel
          .invokeMethod<bool>('closeContentInputStream', {'token': token})
          .catchError((_) => false);
    }
  }

  Future<void> _handleFileTransferSocket(Socket socket) async {
    FileTransferRecord? record;
    IOSink? sink;
    File? tempFile;
    File? finalFile;
    String? publicDownloadToken;
    BytesBuilder? publicDownloadBuffer;
    var publicDownloadBufferedBytes = 0;
    var transferred = 0;
    var accepted = false;
    var lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    Future<void> updateReceiveProgress(
      String transferId, {
      bool force = false,
    }) async {
      final now = DateTime.now();
      if (!force &&
          now.difference(lastProgressUpdate) <
              const Duration(milliseconds: 120)) {
        return;
      }
      lastProgressUpdate = now;
      _updateFileTransfer(transferId, transferredBytes: transferred);
      socket.writeln(
        jsonEncode({
          'protocol': _fileTransferProtocol,
          'action': 'transferProgress',
          'transferId': transferId,
          'transferredBytes': transferred,
          'totalBytes': record?.totalBytes ?? 0,
        }),
      );
      await socket.flush();
    }

    Future<void> flushPublicDownloadBuffer() async {
      final token = publicDownloadToken;
      final buffer = publicDownloadBuffer;
      if (token == null || buffer == null || publicDownloadBufferedBytes == 0) {
        return;
      }
      final bytes = buffer.takeBytes();
      publicDownloadBufferedBytes = 0;
      await _writePublicDownloadChunk(token, bytes);
    }

    try {
      final reader = _SocketFrameReader(socket);
      while (true) {
        final message = await reader.readJson();
        if (message['protocol'] != _fileTransferProtocol) {
          throw const FormatException('Giao thức file không được hỗ trợ.');
        }
        final action = message['action']?.toString();
        if (action == 'fileOffer') {
          if (!_isTrustedSyncRequest(message)) {
            throw const FormatException('Thiết bị gửi file chưa tin cậy.');
          }
          final remoteDeviceId = message['deviceId']?.toString().trim() ?? '';
          final remoteDeviceName =
              message['deviceName']?.toString().trim() ?? 'Thiết bị LAN';
          final files = (message['files'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(FileTransferFile.fromJson)
              .toList();
          if (remoteDeviceId.isEmpty || files.isEmpty) {
            throw const FormatException('Offer file không hợp lệ.');
          }
          final totalBytes =
              message['totalBytes'] as int? ??
              files.fold<int>(0, (sum, file) => sum + file.size);
          final transferId =
              message['transferId']?.toString() ?? _generateTransferId();
          record = FileTransferRecord(
            id: transferId,
            peerId: remoteDeviceId,
            peerName: remoteDeviceName,
            direction: FileTransferDirection.receive,
            status: FileTransferStatus.waiting,
            files: files,
            totalBytes: totalBytes,
            transferredBytes: 0,
            createdAt: DateTime.now(),
          );
          _upsertFileTransfer(record);
          _activeFileTransferSockets[transferId] = socket;
          accepted = await _confirmIncomingFileOffer(record);
          if (!accepted) {
            socket.writeln(
              jsonEncode({
                'protocol': _fileTransferProtocol,
                'action': 'fileRejected',
                'transferId': transferId,
              }),
            );
            await socket.flush();
            _updateFileTransfer(
              transferId,
              status: FileTransferStatus.rejected,
            );
            return;
          }
          final directory = await _receivedFilesDirectory();
          _updateFileTransfer(
            transferId,
            status: FileTransferStatus.receiving,
            saveDirectory: directory.path,
          );
          socket.writeln(
            jsonEncode({
              'protocol': _fileTransferProtocol,
              'action': 'fileAccepted',
              'transferId': transferId,
            }),
          );
          await socket.flush();
          continue;
        }

        final transferId = record?.id;
        if (!accepted || transferId == null) {
          throw const FormatException('Chưa xác nhận nhận file.');
        }
        if (_canceledFileTransferIds.contains(transferId)) {
          throw const _FileTransferCanceledException();
        }
        if (action == 'fileStart') {
          await sink?.close();
          if (publicDownloadToken != null) {
            await _cancelPublicDownloadFile(publicDownloadToken);
            publicDownloadToken = null;
            publicDownloadBuffer = null;
            publicDownloadBufferedBytes = 0;
          }
          final fileName = message['name']?.toString() ?? 'file';
          final relativePath = message['relativePath']?.toString();
          final sizeValue = message['size'];
          final fileSize = sizeValue is int
              ? sizeValue
              : int.tryParse('$sizeValue');
          if (fileSize == null || fileSize < 0) {
            throw const FormatException('Kích thước file không hợp lệ.');
          }
          if (Platform.isAndroid) {
            final download = await _openPublicDownloadFile(
              fileName,
              relativePath: relativePath,
            );
            publicDownloadToken = download.$1;
            publicDownloadBuffer = BytesBuilder(copy: false);
            publicDownloadBufferedBytes = 0;
            _updateFileTransfer(transferId, saveDirectory: download.$2);
          } else {
            final directory = await _receivedFilesDirectory();
            finalFile = await _uniqueReceivedFile(
              directory,
              fileName,
              relativePath: relativePath,
            );
            tempFile = File('${finalFile.path}.part');
            await tempFile.parent.create(recursive: true);
            sink = tempFile.openWrite();
          }
          await reader.readBytes(fileSize, (bytes) async {
            if (_canceledFileTransferIds.contains(transferId)) {
              throw const _FileTransferCanceledException();
            }
            if (publicDownloadToken != null) {
              publicDownloadBuffer ??= BytesBuilder(copy: false);
              publicDownloadBuffer!.add(bytes);
              publicDownloadBufferedBytes += bytes.length;
              if (publicDownloadBufferedBytes >= _androidFileWriteBatchBytes) {
                await flushPublicDownloadBuffer();
              }
            } else {
              final activeSink = sink;
              if (activeSink == null) {
                throw const FormatException('File đến trước metadata.');
              }
              activeSink.add(bytes);
            }
            transferred += bytes.length;
            await updateReceiveProgress(transferId);
          });
          await updateReceiveProgress(transferId, force: true);
          continue;
        }
        if (action == 'fileEnd') {
          final indexValue = message['index'];
          final fileIndex = indexValue is int
              ? indexValue
              : int.tryParse('$indexValue') ?? -1;
          if (publicDownloadToken != null) {
            await flushPublicDownloadBuffer();
            await _finishPublicDownloadFile(publicDownloadToken);
            publicDownloadToken = null;
            publicDownloadBuffer = null;
            publicDownloadBufferedBytes = 0;
            socket.writeln(
              jsonEncode({
                'protocol': _fileTransferProtocol,
                'action': 'fileStored',
                'transferId': transferId,
              }),
            );
            await socket.flush();
            continue;
          }
          final activeSink = sink;
          final activeTemp = tempFile;
          final activeFinal = finalFile;
          if (activeSink == null || activeTemp == null || activeFinal == null) {
            throw const FormatException('File kết thúc không hợp lệ.');
          }
          await activeSink.flush();
          await activeSink.close();
          sink = null;
          if (await activeFinal.exists()) {
            await activeFinal.delete();
          }
          await activeTemp.rename(activeFinal.path);
          _updateFileTransferSavedPath(
            transferId,
            index: fileIndex,
            savedPath: activeFinal.path,
          );
          tempFile = null;
          finalFile = null;
          socket.writeln(
            jsonEncode({
              'protocol': _fileTransferProtocol,
              'action': 'fileStored',
              'transferId': transferId,
            }),
          );
          await socket.flush();
          continue;
        }
        if (action == 'transferComplete') {
          await sink?.close();
          sink = null;
          _updateFileTransfer(
            transferId,
            status: FileTransferStatus.completed,
            transferredBytes: record!.totalBytes,
          );
          final receivedMessage =
              '${record.peerName}: ${record.files.length} file đã lưu vào Download/OpenCB.';
          if (_appInForeground && mounted) {
            _showCenterSnackBar(
              'Đã nhận xong file.',
              success: true,
              maxWidth: 320,
              duration: const Duration(seconds: 2),
            );
          } else {
            await _showAndroidBackgroundNotification(
              title: 'Đã nhận file',
              body: receivedMessage,
            );
          }
          socket.writeln(
            jsonEncode({
              'protocol': _fileTransferProtocol,
              'action': 'transferStored',
              'transferId': transferId,
            }),
          );
          await socket.flush();
          return;
        }
      }
    } on _FileTransferCanceledException {
      if (record != null) {
        _updateFileTransfer(record.id, status: FileTransferStatus.canceled);
      }
    } catch (error) {
      if (record != null) {
        _updateFileTransfer(
          record.id,
          status: FileTransferStatus.failed,
          error: _friendlySyncError(error),
        );
      }
    } finally {
      await sink?.close().catchError((_) {});
      if (publicDownloadToken != null) {
        await _cancelPublicDownloadFile(
          publicDownloadToken,
        ).catchError((_) => false);
      }
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete().catchError((_) => tempFile!);
      }
      if (record != null) {
        _activeFileTransferSockets.remove(record.id);
        _canceledFileTransferIds.remove(record.id);
      }
      await socket.close().catchError((_) {});
    }
  }

  void _cancelFileTransfer(String id) {
    _canceledFileTransferIds.add(id);
    _activeFileTransferSockets.remove(id)?.destroy();
    _updateFileTransfer(id, status: FileTransferStatus.canceled);
  }

  Future<void> _captureClipboardText() async {
    if (_capturePaused || !_loaded) return;
    if (!_clipboardSettings.captureText) return;
    final ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      return;
    }
    final text = data?.text;
    if (text == null) return;
    await _captureTextValue(text, source: 'Clipboard hệ thống');
  }

  Future<void> _sendClipboardFromNotification(String? nativeText) async {
    if (!_loaded || !_clipboardSettings.captureText) {
      await _showAndroidBackgroundNotification(
        title: 'Chưa gửi clipboard',
        body: 'OpenCB chưa sẵn sàng để gửi clipboard.',
      );
      return;
    }
    var text = nativeText;
    if (text == null || text.isEmpty) {
      try {
        text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      } catch (_) {
        text = null;
      }
    }
    if (text == null || text.isEmpty) {
      await _showAndroidBackgroundNotification(
        title: 'Chưa gửi clipboard',
        body: 'Không đọc được clipboard hiện tại.',
      );
      return;
    }
    if (_isSourceExcluded('Clipboard Android')) return;
    if (_peers.isEmpty) {
      await _showAndroidBackgroundNotification(
        title: 'Chưa gửi clipboard',
        body: 'Chưa có thiết bị đã ghép nối.',
      );
      return;
    }

    _lastClipboardText = text;
    var stored = await _storage?.captureText(text, source: 'Clipboard Android');
    await _storage?.applyRetention(maxItems: _clipboardSettings.retentionLimit);
    await _loadEntries(captureCurrentClipboard: false);
    stored ??= _entries.cast<ClipboardEntry?>().firstWhere(
      (entry) => (entry?.body ?? entry?.preview) == text,
      orElse: () => null,
    );
    if (mounted) setState(() => _selectedIndex = 0);
    if (stored != null) {
      await _pushEntryToOnlinePeers(stored, touchExisting: true);
      await _showAndroidBackgroundNotification(
        title: 'Đã gửi clipboard',
        body: '',
        silent: true,
        autoCancelAfterMs: 1800,
      );
    }
  }

  Future<void> _captureTextValue(String text, {required String source}) async {
    if (_capturePaused || !_loaded) return;
    if (!_clipboardSettings.captureText) return;
    if (_isSourceExcluded(source)) return;
    if (text.isEmpty || text == _lastClipboardText) return;
    _lastClipboardText = text;

    final stored = await _storage?.captureText(text, source: source);
    await _storage?.applyRetention(maxItems: _clipboardSettings.retentionLimit);
    await _loadEntries();
    if (mounted) {
      setState(() => _selectedIndex = 0);
    }
    if (stored != null) {
      unawaited(_pushEntryToOnlinePeers(stored));
    }
  }

  Future<void> _captureFileReferences(
    List<String> files, {
    required String source,
  }) async {
    if (_capturePaused || !_loaded || files.isEmpty) return;
    if (!_clipboardSettings.captureFileReferences) return;
    if (_isSourceExcluded(source)) return;
    var changed = false;
    for (final path in files.where((path) => path.trim().isNotEmpty)) {
      await _storage?.captureFileReference(path, source: source);
      changed = true;
    }
    if (!changed) return;
    await _storage?.applyRetention(maxItems: _clipboardSettings.retentionLimit);
    await _loadEntries();
    if (mounted) setState(() => _selectedIndex = 0);
  }

  Future<void> _captureImageValue(
    Uint8List bytes, {
    required String source,
  }) async {
    if (_capturePaused || !_loaded || bytes.isEmpty) return;
    if (!_clipboardSettings.captureImages) return;
    if (_isSourceExcluded(source)) return;
    await _storage?.captureImage(bytes, source: source);
    await _storage?.applyRetention(maxItems: _clipboardSettings.retentionLimit);
    await _loadEntries();
    if (mounted) setState(() => _selectedIndex = 0);
  }

  Future<void> _startNativeClipboardBridge() async {
    if (!Platform.isWindows) {
      _startClipboardPolling();
      return;
    }

    _windowsClipboardChannel.setMethodCallHandler((call) async {
      if (call.method == 'clipboardChanged') {
        await _handleNativeClipboardPayload(call.arguments);
        return;
      }
      if (call.method == 'quickOpenRequested') {
        if (mounted) await _openQuickPickerShell();
        return;
      }
      if (call.method == 'mainWindowRequested') {
        if (mounted && _quickPickerMode) {
          setState(() {
            _quickPickerMode = false;
            _quickPickerClosing = false;
          });
        }
        return;
      }
      if (call.method == 'quickPickerDeactivated') {
        if (_openingMainFromQuickPicker) return;
        if (mounted && _quickPickerMode) {
          await _closeQuickPickerShell();
        }
        return;
      }
    });

    await _applyQuickOpenHotKey(_clipboardSettings.quickOpenHotKey);

    try {
      final snapshot = await _windowsClipboardChannel.invokeMethod<Object?>(
        'getSnapshot',
      );
      await _handleNativeClipboardPayload(snapshot);
    } catch (_) {
      _startClipboardPolling();
    }
  }

  Future<void> _openQuickPickerShell() async {
    if (!mounted) return;
    setState(() {
      _quickPickerMode = true;
      _quickPickerClosing = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_quickPickerMode) return;
    try {
      await _windowsClipboardChannel.invokeMethod<void>(
        'showQuickPickerWindow',
      );
    } catch (_) {}
  }

  Future<void> _closeQuickPickerShell({bool hideWindow = true}) async {
    if (!mounted) return;
    final runningClose = _quickPickerCloseFuture;
    if (runningClose != null) {
      await runningClose;
      return;
    }
    final closeFuture = _runQuickPickerClose(hideWindow: hideWindow);
    _quickPickerCloseFuture = closeFuture;
    try {
      await closeFuture;
    } finally {
      if (identical(_quickPickerCloseFuture, closeFuture)) {
        _quickPickerCloseFuture = null;
      }
    }
  }

  Future<void> _runQuickPickerClose({required bool hideWindow}) async {
    if (!mounted) return;
    if (_quickPickerMode) {
      setState(() => _quickPickerClosing = true);
      await Future<void>.delayed(_quickPickerExitDuration);
      if (!mounted) return;
      setState(() {
        _quickPickerMode = false;
        _quickPickerClosing = false;
      });
    }
    if (!hideWindow) return;
    try {
      await _windowsClipboardChannel.invokeMethod<void>('hideWindow');
    } catch (_) {}
  }

  Future<void> _openMainAppFromQuickPicker() async {
    if (!mounted) return;
    _openingMainFromQuickPicker = true;
    try {
      await _windowsClipboardChannel.invokeMethod<void>(
        'prepareMainWindowFromQuickPicker',
      );
      if (!mounted) return;
      setState(() {
        _quickPickerMode = false;
        _quickPickerClosing = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _windowsClipboardChannel.invokeMethod<void>(
        'showPreparedMainWindow',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _quickPickerMode = false;
        _quickPickerClosing = false;
      });
      try {
        await _windowsClipboardChannel.invokeMethod<void>('showMainWindow');
      } catch (_) {}
    } finally {
      _openingMainFromQuickPicker = false;
    }
  }

  Future<void> _handleQuickPickerShellSelection(
    ClipboardEntry entry, {
    required bool keepOpen,
  }) async {
    await _copyEntryToClipboard(entry);
    if (_clipboardSettings.autoPasteFromQuickPicker) {
      await _pasteToQuickPickerTarget(returnToQuickPicker: keepOpen);
    }
    if (keepOpen) return;
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await _closeQuickPickerShell();
  }

  Future<void> _pasteToQuickPickerTarget({
    required bool returnToQuickPicker,
  }) async {
    if (!Platform.isWindows) return;
    try {
      await _windowsClipboardChannel.invokeMethod<bool>('pasteToQuickTarget', {
        'returnToQuickPicker': returnToQuickPicker,
      });
    } catch (_) {}
  }

  void _startClipboardPolling() {
    _pollTimer ??= Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => _captureClipboardText(),
    );
  }

  Future<void> _handleNativeClipboardPayload(Object? payload) async {
    if (payload is! Map) return;
    final type = payload['type'];
    final source = _nativeSourceLabel(payload);
    final sourceIconBytes = _nativeSourceIconBytes(payload);
    await _rememberSourceIcon(source, sourceIconBytes);
    if (type == 'text') {
      final text = payload['text'];
      if (text is String) {
        await _captureTextValue(text, source: source);
      }
      return;
    }
    if (type == 'file_reference') {
      final files = payload['files'];
      if (files is List) {
        await _captureFileReferences(
          files.whereType<String>().toList(),
          source: source == 'Clipboard hệ thống' ? 'File Explorer' : source,
        );
      }
      return;
    }
    if (type == 'image') {
      final bytes = payload['bytes'];
      if (bytes is Uint8List) {
        await _captureImageValue(bytes, source: source);
      } else if (bytes is List<int>) {
        await _captureImageValue(Uint8List.fromList(bytes), source: source);
      }
    }
  }

  bool _isSourceExcluded(String source) {
    final normalized = source.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return _clipboardSettings.excludedSources.any(
      (item) => item.trim().toLowerCase() == normalized,
    );
  }

  Future<void> _copyEntryToClipboard(ClipboardEntry entry) async {
    if (entry.kind == ClipboardKind.image && entry.imageBytes != null) {
      try {
        await _windowsClipboardChannel.invokeMethod<void>('setImage', {
          'bytes': entry.imageBytes,
        });
        await _markEntryCopied(entry);
        return;
      } catch (_) {
        // Fall through to copying the preview text if native image restore fails.
      }
    }
    final text = entry.kind == ClipboardKind.fileReference
        ? entry.filePath ?? entry.preview
        : entry.body ?? entry.preview;
    await Clipboard.setData(ClipboardData(text: text));
    _lastClipboardText = text;
    await _markEntryCopied(entry);
  }

  Future<void> _markEntryCopied(ClipboardEntry entry) async {
    final now = DateTime.now();
    final updatedEntry = entry.copyWith(createdAt: now);
    await _storage?.touchItem(entry.id);
    if (!mounted) return;
    setState(() {
      _promotedEntryId = entry.id;
      _promotionToken += 1;
      _entries = [
        for (final item in _entries)
          if (item.id == entry.id) updatedEntry else item,
      ];
      _sortEntries();
      final visibleIndex = _visibleEntries.indexWhere(
        (item) => item.id == entry.id,
      );
      if (visibleIndex >= 0) {
        _selectedIndex = visibleIndex;
      } else {
        final visibleLength = _visibleEntries.length;
        _selectedIndex = visibleLength == 0
            ? 0
            : _selectedIndex.clamp(0, visibleLength - 1).toInt();
      }
    });
    unawaited(_pushEntryToOnlinePeers(updatedEntry, touchExisting: true));
  }

  Future<void> _openUrlEntry(ClipboardEntry entry) async {
    final url = _normalizedUrl(entry.body ?? entry.preview);
    if (url == null) {
      _showCenterSnackBar('URL không hợp lệ.');
      return;
    }
    try {
      if (Platform.isWindows) {
        await Process.run('rundll32.exe', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isAndroid) {
        final opened = await _platformChannel.invokeMethod<bool>('openUrl', {
          'url': url,
        });
        if (opened != true) {
          throw PlatformException(code: 'open_failed');
        }
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        _showCenterSnackBar('Đã copy URL vào clipboard.');
        return;
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      _showCenterSnackBar('Không mở được URL, đã copy vào clipboard.');
    }
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('rundll32.exe', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isAndroid) {
        final opened = await _platformChannel.invokeMethod<bool>('openUrl', {
          'url': url,
        });
        if (opened != true) throw PlatformException(code: 'open_failed');
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        _showCenterSnackBar('Đã copy đường dẫn.');
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      _showCenterSnackBar('Không mở được link, đã copy vào clipboard.');
    }
  }

  Future<void> _checkForUpdates({bool userInitiated = true}) async {
    if (_checkingForUpdates) return;
    final l10n = context.l10n;
    if (mounted) {
      setState(() {
        _checkingForUpdates = true;
        if (userInitiated) _latestUpdateMessage = l10n.checkingUpdatesMessage;
      });
    }

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final request = await client.getUrl(Uri.parse(_latestReleaseApiUrl));
        request.headers.set(HttpHeaders.userAgentHeader, 'OpenCB/$_appVersion');
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw const FormatException('Không đọc được thông tin release.');
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Release không hợp lệ.');
        }
        final tag = decoded['tag_name']?.toString().trim() ?? '';
        final releaseUrl =
            decoded['html_url']?.toString().trim().isNotEmpty == true
            ? decoded['html_url'].toString().trim()
            : _latestReleaseUrl;
        if (tag.isEmpty) {
          throw const FormatException('Release không có phiên bản.');
        }
        final hasUpdate = _isRemoteVersionNewer(tag, _appVersion);
        if (!mounted) return;
        setState(() {
          _latestUpdateMessage = hasUpdate
              ? '${l10n.newVersionAvailable} $tag.'
              : l10n.latestVersionMessage;
        });
        if (hasUpdate) {
          await _showUpdateAvailableDialog(tag, releaseUrl);
        } else if (userInitiated) {
          _showCenterSnackBar(l10n.latestVersionMessage, success: true);
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (userInitiated) {
          _latestUpdateMessage = l10n.cannotCheckUpdatesMessage;
        }
      });
      if (userInitiated) {
        _showCenterSnackBar(l10n.cannotCheckUpdates);
      }
    } finally {
      if (mounted) setState(() => _checkingForUpdates = false);
    }
  }

  Future<void> _showUpdateAvailableDialog(String tag, String releaseUrl) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.system_update_alt, color: colorScheme.primary),
          title: Text('Đã có OpenCB $tag'),
          content: const Text(
            'Bạn có thể tải bản cài đặt mới nhất từ GitHub Releases.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(_openExternalUrl(releaseUrl));
              },
              child: const Text('Tải xuống'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openFileLocation(ClipboardEntry entry) async {
    final rawPath = (entry.filePath ?? entry.preview).trim();
    if (rawPath.isEmpty) {
      _showCenterSnackBar('Không có đường dẫn file.');
      return;
    }

    final type = await FileSystemEntity.type(rawPath);
    String? folderPath;
    if (type == FileSystemEntityType.directory) {
      folderPath = rawPath;
    } else if (type == FileSystemEntityType.file) {
      folderPath = File(rawPath).parent.path;
    } else {
      final parent = File(rawPath).parent;
      if (await parent.exists()) folderPath = parent.path;
    }

    if (folderPath == null || folderPath.trim().isEmpty) {
      _showCenterSnackBar('Không tìm thấy thư mục chứa file.');
      return;
    }

    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [folderPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [folderPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [folderPath]);
      } else {
        await Clipboard.setData(ClipboardData(text: folderPath));
        _showCenterSnackBar('Đã copy đường dẫn thư mục.');
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: folderPath));
      _showCenterSnackBar('Không mở được thư mục, đã copy đường dẫn.');
    }
  }

  Future<void> _openReceivedFilesFolder() async {
    final directory = await _receivedFilesDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await _openLocalPath(directory.path, fallbackCopy: false);
  }

  Future<void> _openFileTransferLocalFile(FileTransferRecord transfer) async {
    final path = _localFileTransferPath(transfer);
    if (path == null || path.trim().isEmpty) {
      _showCenterSnackBar('Không tìm thấy file local để mở.');
      return;
    }
    await _openLocalPath(path);
  }

  String? _localFileTransferPath(FileTransferRecord transfer) {
    if (transfer.files.length != 1) return null;
    final file = transfer.files.first;
    final savedPath = file.savedPath?.trim();
    if (savedPath != null && savedPath.isNotEmpty) return savedPath;
    if (transfer.direction == FileTransferDirection.send) {
      final path = file.path?.trim();
      if (path != null && path.isNotEmpty) return path;
    }
    if (transfer.direction == FileTransferDirection.receive &&
        transfer.saveDirectory != null) {
      final candidate = File(
        '${transfer.saveDirectory}${Platform.pathSeparator}${_safeRelativeFilePath(file.displayPath).replaceAll('/', Platform.pathSeparator)}',
      );
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }

  Future<void> _openLocalPath(String path, {bool fallbackCopy = true}) async {
    try {
      if (Platform.isWindows) {
        final type = FileSystemEntity.typeSync(path);
        if (type == FileSystemEntityType.directory) {
          await Process.run('explorer.exe', [path]);
        } else {
          await Process.run('rundll32.exe', [
            'url.dll,FileProtocolHandler',
            path,
          ]);
        }
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      } else {
        if (fallbackCopy) {
          await Clipboard.setData(ClipboardData(text: path));
          _showCenterSnackBar('Đã copy đường dẫn.');
        } else {
          _showCenterSnackBar('File đã lưu trong Download/OpenCB.');
        }
      }
    } catch (_) {
      if (fallbackCopy) {
        await Clipboard.setData(ClipboardData(text: path));
        _showCenterSnackBar('Không mở được, đã copy đường dẫn.');
      } else {
        _showCenterSnackBar('Không mở được folder nhận file.');
      }
    }
  }

  EdgeInsets _bottomCenterSnackBarMargin() {
    final mobile = MediaQuery.sizeOf(context).width < _mobileLayoutBreakpoint;
    return EdgeInsets.fromLTRB(16, 0, 16, mobile ? 104 : 18);
  }

  void _removeNoticeOverlay() {
    _noticeOverlayTimer?.cancel();
    _noticeOverlayTimer = null;
    _noticeOverlayEntry?.remove();
    _noticeOverlayEntry = null;
  }

  void _showCenterSnackBar(
    String message, {
    Duration duration = const Duration(milliseconds: 1600),
    double maxWidth = 300,
    bool success = false,
  }) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = success
        ? colorScheme.surfaceContainerHighest
        : colorScheme.inverseSurface;
    final foregroundColor = success
        ? colorScheme.onSurface
        : colorScheme.onInverseSurface;
    final margin = _bottomCenterSnackBarMargin();
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: foregroundColor,
      fontWeight: FontWeight.w700,
      height: 1.12,
    );
    _removeNoticeOverlay();
    final overlay = Overlay.of(context, rootOverlay: true);
    _noticeOverlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: margin.left,
        right: margin.right,
        bottom: margin.bottom + MediaQuery.paddingOf(context).bottom,
        child: IgnorePointer(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: success
                        ? Border.all(color: colorScheme.outlineVariant)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.16),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (success) ...[
                          Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: foregroundColor,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: textStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_noticeOverlayEntry!);
    _noticeOverlayTimer = Timer(duration, _removeNoticeOverlay);
  }

  EdgeInsets _deleteUndoNoticeMargin() {
    final mobile = MediaQuery.sizeOf(context).width < _mobileLayoutBreakpoint;
    return EdgeInsets.fromLTRB(16, 0, 16, mobile ? 116 : 78);
  }

  Rect? _desktopDetailActionBarRect() {
    final currentContext = _desktopDetailActionBarKey.currentContext;
    if (currentContext == null) return null;
    final renderObject = currentContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  void _showDeleteUndoNotice(List<ClipboardEntry> entries) {
    if (!mounted || entries.isEmpty) return;
    final l10n = context.l10n;
    final message = entries.length == 1
        ? l10n.deletedClipboard
        : '${l10n.deletedClipboardPrefix} ${entries.length} ${l10n.deletedClipboardSuffix}';
    final margin = _deleteUndoNoticeMargin();
    final actionBarRect = _desktopDetailActionBarRect();
    final overlay = Overlay.of(context, rootOverlay: true);
    _removeNoticeOverlay();
    _noticeOverlayEntry = OverlayEntry(
      builder: (context) {
        final mediaPadding = MediaQuery.paddingOf(context);
        final positioned = actionBarRect == null
            ? Positioned(
                left: margin.left,
                right: margin.right,
                bottom: margin.bottom + mediaPadding.bottom,
                child: _DeleteUndoNoticeContent(
                  message: message,
                  onUndo: () => _undoDeletedEntries(entries),
                ),
              )
            : Positioned(
                left: actionBarRect.left + 20,
                width: math.min(420, math.max(260, actionBarRect.width - 40)),
                top: math.max(mediaPadding.top + 8, actionBarRect.top - 46),
                child: _DeleteUndoNoticeContent(
                  message: message,
                  onUndo: () => _undoDeletedEntries(entries),
                ),
              );
        return positioned;
      },
    );
    overlay.insert(_noticeOverlayEntry!);
    _noticeOverlayTimer = Timer(
      const Duration(seconds: 3),
      _removeNoticeOverlay,
    );
  }

  Future<void> _togglePin(ClipboardEntry entry) async {
    final pinned = !entry.pinned;
    await _storage?.setPinned(entry.id, pinned);
    unawaited(
      _pushEntryToOnlinePeers(
        entry.copyWith(pinned: pinned),
        touchExisting: false,
      ),
    );
    await _loadEntries();
  }

  Future<void> _toggleQuickPickerPin(ClipboardEntry entry) async {
    final pinned = !entry.pinned;
    await _storage?.setPinned(entry.id, pinned);
    final updatedEntry = entry.copyWith(pinned: pinned);
    unawaited(_pushEntryToOnlinePeers(updatedEntry, touchExisting: false));
    if (!mounted) return;
    setState(() {
      _entries = [
        for (final item in _entries)
          if (item.id == entry.id) updatedEntry else item,
      ];
    });
  }

  Future<void> _deleteEntry(ClipboardEntry entry) async {
    _deleteEntriesWithUndo([entry]);
  }

  void _deleteEntriesWithUndo(List<ClipboardEntry> entries) {
    if (entries.isEmpty) return;
    final ids = entries.map((entry) => entry.id).toSet();
    for (final entry in entries) {
      _pendingDeleteTimers.remove(entry.id)?.cancel();
      _pendingDeleteIds.add(entry.id);
    }
    if (mounted) {
      setState(() {
        _entries = _entries.where((item) => !ids.contains(item.id)).toList();
        final visibleLength = _visibleEntries.length;
        _selectedIndex = visibleLength == 0
            ? 0
            : _selectedIndex.clamp(0, visibleLength - 1).toInt();
      });
    }
    for (final entry in entries) {
      _pendingDeleteTimers[entry.id] = Timer(const Duration(seconds: 3), () {
        _pendingDeleteTimers.remove(entry.id);
        _pendingDeleteIds.remove(entry.id);
        unawaited(_finalizeDeletedEntries([entry]));
      });
    }
    _showDeleteUndoNotice(entries);
  }

  void _undoDeletedEntries(List<ClipboardEntry> entries) {
    if (entries.isEmpty) return;
    var restoredAny = false;
    for (final entry in entries) {
      final timer = _pendingDeleteTimers.remove(entry.id);
      if (timer == null) continue;
      timer.cancel();
      _pendingDeleteIds.remove(entry.id);
      restoredAny = true;
    }
    if (!restoredAny || !mounted) {
      _removeNoticeOverlay();
      return;
    }
    setState(() {
      final existingIds = _entries.map((entry) => entry.id).toSet();
      _entries = [
        ..._entries,
        for (final entry in entries)
          if (!existingIds.contains(entry.id)) entry,
      ];
      _sortEntries();
      final restoredIndex = _visibleEntries.indexWhere(
        (item) => item.id == entries.first.id,
      );
      if (restoredIndex >= 0) _selectedIndex = restoredIndex;
    });
    _removeNoticeOverlay();
  }

  Future<void> _finalizeDeletedEntries(List<ClipboardEntry> entries) async {
    if (entries.isEmpty) return;
    final tombstones = await _rememberDeletedEntries(entries);
    final storage = _storage;
    if (storage != null) {
      for (final entry in entries) {
        await storage.deleteItem(entry.id);
      }
    }
    if (tombstones.isNotEmpty) {
      unawaited(_pushTombstonesToOnlinePeers(tombstones));
    }
  }

  Future<void> _editTags(ClipboardEntry entry) async {
    final knownTags =
        {
            ..._tagDefinitions.keys,
            for (final item in _entries) ...item.tags,
            ...entry.tags,
          }.where((tag) => tag.trim().isNotEmpty).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final result = await showDialog<_TagEditResult>(
      context: context,
      builder: (context) => _TagEditorDialog(
        initialTags: entry.tags,
        knownTags: knownTags,
        definitions: _tagDefinitions,
      ),
    );
    if (result == null) return;
    _tagDefinitions = result.definitions;
    await _saveTagDefinitions();
    await _applyDeletedTags(result.deletedTags);
    await _storage?.setTags(entry.id, result.tags);
    unawaited(
      _pushEntryToOnlinePeers(
        entry.copyWith(tags: result.tags),
        touchExisting: false,
      ),
    );
    await _loadEntries();
  }

  Future<void> _manageTags() async {
    final knownTags = _availableTags;
    final result = await showDialog<_TagEditResult>(
      context: context,
      builder: (context) => _TagEditorDialog(
        initialTags: const [],
        knownTags: knownTags,
        definitions: _tagDefinitions,
        libraryOnly: true,
      ),
    );
    if (result == null) return;
    setState(() => _tagDefinitions = result.definitions);
    await _saveTagDefinitions();
    await _applyDeletedTags(result.deletedTags);
  }

  Future<void> _applyDeletedTags(Set<String> deletedTags) async {
    if (deletedTags.isEmpty) return;
    final storage = _storage;
    final updatedEntries = <ClipboardEntry>[];
    for (final entry in _entries) {
      if (!entry.tags.any(deletedTags.contains)) continue;
      final tags = entry.tags
          .where((tag) => !deletedTags.contains(tag))
          .toList();
      await storage?.setTags(entry.id, tags);
      updatedEntries.add(entry.copyWith(tags: tags));
    }
    if (!mounted) return;
    final updatedById = {for (final entry in updatedEntries) entry.id: entry};
    setState(() {
      _tagFilters.removeAll(deletedTags);
      _entries = [for (final entry in _entries) updatedById[entry.id] ?? entry];
    });
    if (updatedEntries.isNotEmpty) {
      unawaited(
        _pushEntriesToOnlinePeers(updatedEntries, touchExisting: false),
      );
    }
    await _loadEntries(captureCurrentClipboard: false);
  }

  TagDefinition _tagDefinitionFor(String tag) {
    final existing = _tagDefinitions[tag];
    if (existing != null) return existing;
    final hash = tag.codeUnits.fold<int>(0, (value, code) => value + code);
    return TagDefinition(
      name: tag,
      colorValue: _tagColorOptions[hash % _tagColorOptions.length],
      iconKey: _tagIconOptions[hash % _tagIconOptions.length].key,
    );
  }

  Map<String, TagDefinition> _definitionsForEntry(ClipboardEntry entry) {
    return {for (final tag in entry.tags) tag: _tagDefinitionFor(tag)};
  }

  Future<void> _confirmAndClearUnpinned() async {
    final unpinnedCount = _entries.where((entry) => !entry.pinned).length;
    if (unpinnedCount == 0) {
      if (!mounted) return;
      _showCenterSnackBar(context.l10n.noUnpinnedClipboardToClean);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final l10n = context.l10n;
        return AlertDialog(
          icon: const Icon(Icons.clear_all),
          title: Text(l10n.cleanClipboardTitle),
          content: Text(
            '${l10n.cleanClipboardBodyPrefix} ${_localizedItemCount(l10n, unpinnedCount)} ${l10n.cleanClipboardBodySuffix}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: _ButtonLabel(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: _ButtonLabel(l10n.clear),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await _clearUnpinned();
  }

  Future<void> _clearUnpinned() async {
    final storage = _storage;
    var tombstones = <String, DateTime>{};
    if (storage != null) {
      final unpinned = _entries.where((entry) => !entry.pinned).toList();
      tombstones = await _rememberDeletedEntries(unpinned);
      for (final entry in unpinned) {
        await storage.deleteItem(entry.id);
      }
    }
    await _loadEntries();
    if (mounted) setState(() => _selectedIndex = 0);
    if (tombstones.isNotEmpty) {
      unawaited(_pushTombstonesToOnlinePeers(tombstones));
    }
  }

  Future<void> _openDataDirectory() async {
    final directory = await _opencbDataDirectory();
    await directory.create(recursive: true);
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [directory.path]);
      return;
    }
    if (!mounted) return;
    _showCenterSnackBar('Thư mục dữ liệu: ${directory.path}');
  }

  Future<void> _exportDataBackup() async {
    final directory = await _opencbDataDirectory();
    await directory.create(recursive: true);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}opencb_backup_$timestamp.json',
    );
    const encoder = JsonEncoder.withIndent('  ');
    final payload = {
      'format': 'opencb_backup_v1',
      'createdAt': DateTime.now().toIso8601String(),
      'device': _syncIdentity.toJson(),
      'settings': _clipboardSettings.toJson(),
      'tagDefinitions': _tagDefinitions.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'peers': _peers.map((peer) => peer.toJson()).toList(),
      'items': _entries.map((entry) => entry.toJson()).toList(),
    };
    await file.writeAsString(encoder.convert(payload));
    if (!mounted) return;
    _showCenterSnackBar('Đã tạo backup trong thư mục dữ liệu.');
  }

  Future<void> _restoreDataBackup() async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => const _RestoreBackupDialog(),
    );
    final normalizedPath = _normalizeBackupPath(path ?? '');
    if (normalizedPath == null) return;

    try {
      final file = File(normalizedPath);
      if (!await file.exists()) {
        _showCenterSnackBar('Không tìm thấy file backup.');
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != 'opencb_backup_v1') {
        _showCenterSnackBar('File backup không hợp lệ.');
        return;
      }

      final itemCount = (decoded['items'] as List<dynamic>? ?? const []).length;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final l10n = context.l10n;
          return AlertDialog(
            icon: const Icon(Icons.restore_outlined),
            title: Text(l10n.restoreDataTitle),
            content: Text(
              '${l10n.restoreDataBodyPrefix} ${_localizedItemCount(l10n, itemCount)} ${l10n.restoreDataBodySuffix}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: _ButtonLabel(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: _ButtonLabel(l10n.restoreAction),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;

      final imported = await _restoreBackupPayload(decoded);
      if (!mounted) return;
      final l10n = context.l10n;
      _showCenterSnackBar(
        '${l10n.restoredClipboardPrefix} ${_localizedItemCount(l10n, imported)} ${l10n.restoredClipboardSuffix}',
      );
    } catch (_) {
      if (!mounted) return;
      _showCenterSnackBar('Không khôi phục được backup.');
    }
  }

  String? _normalizeBackupPath(String value) {
    var path = value.trim();
    if (path.isEmpty) return null;
    if ((path.startsWith('"') && path.endsWith('"')) ||
        (path.startsWith("'") && path.endsWith("'"))) {
      path = path.substring(1, path.length - 1).trim();
    }
    return path.isEmpty ? null : path;
  }

  Future<int> _restoreBackupPayload(Map<String, dynamic> payload) async {
    final settings = payload['settings'];
    if (settings is Map<String, dynamic>) {
      await _updateClipboardSettings(ClipboardSettings.fromJson(settings));
    }

    await _mergeRemoteTagDefinitions(
      payload['tagDefinitions'],
      replaceExisting: true,
    );

    final peers = payload['peers'];
    if (peers is List<dynamic>) {
      for (final item in peers.whereType<Map<String, dynamic>>()) {
        final peer = SyncPeer.fromJson(item);
        if (peer.id == _syncIdentity.deviceId) continue;
        await _upsertPeer(peer, notify: false);
      }
    }

    final storage = _storage;
    if (storage == null) return 0;
    var imported = 0;
    final items = payload['items'];
    if (items is List<dynamic>) {
      for (final item in items.whereType<Map<String, dynamic>>()) {
        final entry = ClipboardEntry.fromJson(item);
        final restored = await _restoreBackupEntry(storage, entry);
        if (restored) imported += 1;
      }
    }
    await storage.applyRetention(maxItems: _clipboardSettings.retentionLimit);
    await _loadEntries(captureCurrentClipboard: false);
    if (mounted) {
      setState(() {
        _selectedIndex = 0;
        _bulkSelectedIds = {};
        _bulkSelectMode = false;
      });
    }
    return imported;
  }

  Future<bool> _restoreBackupEntry(
    OpenCbStorage storage,
    ClipboardEntry entry,
  ) async {
    ClipboardEntry? stored;
    switch (entry.kind) {
      case ClipboardKind.text:
      case ClipboardKind.code:
      case ClipboardKind.url:
        final text = entry.body ?? entry.preview;
        if (text.trim().isEmpty) return false;
        stored = await storage.captureText(text, source: entry.source);
      case ClipboardKind.fileReference:
        final path = entry.filePath ?? entry.preview;
        if (path.trim().isEmpty) return false;
        stored = await storage.captureFileReference(path, source: entry.source);
      case ClipboardKind.image:
        final bytes = entry.imageBytes;
        if (bytes == null || bytes.isEmpty) return false;
        stored = await storage.captureImage(bytes, source: entry.source);
    }
    if (stored == null) return false;
    if (entry.pinned) await storage.setPinned(stored.id, true);
    if (entry.tags.isNotEmpty) await storage.setTags(stored.id, entry.tags);
    return true;
  }

  Future<void> _confirmResetClipboardHistory() async {
    if (_entries.isEmpty) {
      _showCenterSnackBar(context.l10n.historyAlreadyEmpty);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = context.l10n;
        return AlertDialog(
          icon: const Icon(Icons.delete_sweep_outlined),
          title: Text(l10n.clearAllHistoryTitle),
          content: Text(
            '${l10n.clearAllHistoryBodyPrefix} ${_localizedItemCount(l10n, _entries.length)} ${l10n.clearAllHistoryBodySuffix}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: _ButtonLabel(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: _ButtonLabel(l10n.deleteHistory),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final storage = _storage;
    if (storage == null) return;
    final entries = List<ClipboardEntry>.from(_entries);
    final tombstones = await _rememberDeletedEntries(entries);
    for (final entry in entries) {
      await storage.deleteItem(entry.id);
    }
    _pendingDeleteIds.clear();
    for (final timer in _pendingDeleteTimers.values) {
      timer.cancel();
    }
    _pendingDeleteTimers.clear();
    await _loadEntries();
    if (!mounted) return;
    setState(() {
      _selectedIndex = 0;
      _bulkSelectedIds = {};
      _bulkSelectMode = false;
    });
    if (tombstones.isNotEmpty) {
      unawaited(_pushTombstonesToOnlinePeers(tombstones));
    }
  }

  Future<void> _toggleLanSync(bool enabled) async {
    setState(() {
      _lanSyncEnabled = enabled;
      _syncError = null;
    });
    if (enabled) {
      await _startSyncServer();
      await _startFileTransferServer();
      await _startLanDiscovery();
    } else {
      await _stopSyncServer();
      await _stopFileTransferServer();
      _stopLanDiscovery();
    }
    unawaited(_syncAndroidBackgroundNotificationDevices(force: true));
  }

  Future<void> _addPeer() async {
    final peer = await showDialog<SyncPeer>(
      context: context,
      builder: (context) => const _AddPeerDialog(),
    );
    if (peer == null) return;
    final accepted = await _sendPairRequest(peer);
    if (!mounted) return;
    _showCenterSnackBar(
      accepted
          ? '${context.l10n.paired} ${peer.name}.'
          : context.l10n.notPaired,
    );
  }

  Future<void> _scanAndAddPeer() async {
    final payload = await _showPairQrScanner(context);
    if (payload == null || !mounted) return;
    final peer = _parsePairPayload(payload);
    if (peer == null) {
      _showCenterSnackBar(context.l10n.invalidQrPairing);
      return;
    }
    final accepted = await _sendPairRequest(peer);
    if (!mounted) return;
    _showCenterSnackBar(
      accepted
          ? '${context.l10n.paired} ${peer.name}.'
          : context.l10n.notPaired,
    );
  }

  Future<void> _upsertPeer(SyncPeer peer, {bool notify = true}) async {
    void updatePeer() {
      final existingIndex = _peers.indexWhere((item) => item.id == peer.id);
      if (existingIndex >= 0) {
        _peers[existingIndex] = peer.copyWith(clearError: true);
      } else {
        _peers.add(peer);
      }
    }

    if (notify && mounted) {
      setState(updatePeer);
    } else {
      updatePeer();
    }
    _rememberReachablePeer(peer.copyWith(clearError: true));
    await _savePeers();
  }

  Future<void> _addDiscoveredPeer(DiscoveredSyncDevice device) async {
    final peer = await showDialog<SyncPeer>(
      context: context,
      builder: (context) => _ConfirmDiscoveredPeerDialog(device: device),
    );
    if (peer == null) return;
    final accepted = await _sendPairRequest(peer);
    if (!mounted) return;
    _showCenterSnackBar(
      accepted
          ? '${context.l10n.paired} ${device.name}.'
          : context.l10n.notPaired,
    );
  }

  Future<bool> _sendPairRequest(SyncPeer peer) async {
    try {
      final socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: const Duration(seconds: 4),
      );
      socket.writeln(jsonEncode(_pairRequestPayloadForPeer(peer)));
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 6));
      await socket.close();
      final response = jsonDecode(line) as Map<String, dynamic>;
      if (response['error'] != null) throw Exception(response['error']);
      if (response['action'] != 'pairAccepted') {
        throw Exception('Thiết bị kia chưa xác nhận ghép nối.');
      }
      await _mergeRemoteTagDefinitions(
        response['tagDefinitions'],
        replaceExisting: false,
      );
      final acceptedPeer = _peerFromPairResponse(response, fallback: peer);
      await _upsertPeer(
        acceptedPeer.copyWith(lastSyncedAt: DateTime.now(), clearError: true),
      );
      await _mergeSyncedEntries(
        (response['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClipboardEntry.fromJson)
            .toList(),
        response['deviceName'] as String?,
      );
      return true;
    } catch (error) {
      final index = _peers.indexWhere((item) => item.id == peer.id);
      if (index >= 0 && mounted) {
        setState(() {
          _peers[index] = peer.copyWith(lastError: _friendlySyncError(error));
        });
        await _savePeers();
      }
      return false;
    }
  }

  Future<bool> _confirmIncomingPairRequest(SyncPeer peer) async {
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final l10n = context.l10n;
        return AlertDialog(
          icon: const Icon(Icons.devices_other_outlined),
          title: Text(l10n.pairDeviceQuestion),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${peer.name} ${l10n.wantsToPairWithThisDevice}'),
              const SizedBox(height: 12),
              Text(
                '${peer.endpoint} - ${peer.pairCode}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: _ButtonLabel(l10n.rejected),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: _ButtonLabel(l10n.pair),
            ),
          ],
        );
      },
    );
    return accepted == true;
  }

  SyncPeer _peerFromPairResponse(
    Map<String, dynamic> response, {
    required SyncPeer fallback,
  }) {
    final id = response['deviceId']?.toString().trim();
    final name = response['deviceName']?.toString().trim();
    final host = response['host']?.toString().trim();
    final portValue = response['port'];
    final port = portValue is int ? portValue : int.tryParse('$portValue');
    final filePortValue = response['filePort'];
    final filePort = filePortValue is int
        ? filePortValue
        : int.tryParse('$filePortValue');
    final pairCode = response['pairCode']?.toString().trim().toUpperCase();
    if (id == null ||
        id.isEmpty ||
        pairCode == null ||
        pairCode.length < 6 ||
        host == null ||
        !_isUsableLanIpv4(host) ||
        port == null ||
        port <= 0 ||
        port > 65535) {
      return fallback;
    }
    return SyncPeer(
      id: id,
      name: name == null || name.isEmpty ? fallback.name : name,
      host: host,
      port: port,
      filePort: filePort == null || filePort <= 0 || filePort > 65535
          ? fallback.filePort
          : filePort,
      pairCode: pairCode,
    );
  }

  Future<void> _copyLocalPairPayload() async {
    final refreshedHost = await _detectLanIpv4Address();
    if (refreshedHost != null && refreshedHost != _syncHost) {
      if (mounted) setState(() => _syncHost = refreshedHost);
    }
    final payload = _buildPairPayload(
      _syncIdentity,
      _syncPort,
      host: refreshedHost ?? _syncHost,
    );
    await Clipboard.setData(ClipboardData(text: payload));
  }

  Future<String?> _showRenameDeviceDialog({
    required String title,
    required String initialName,
  }) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          _RenameDeviceDialog(title: title, initialName: initialName),
    );
    final normalized = name?.trim();
    if (normalized == null || normalized.isEmpty || normalized == initialName) {
      return null;
    }
    await Future<void>.delayed(Duration.zero);
    return normalized;
  }

  Future<void> _renameLocalDevice() async {
    final name = await _showRenameDeviceDialog(
      title: context.l10n.renameThisDevice,
      initialName: _syncIdentity.deviceName,
    );
    if (name == null) return;
    setState(() => _syncIdentity = _syncIdentity.copyWith(deviceName: name));
    await _saveSyncIdentity();
    await _sendDiscoveryBeacon();
    unawaited(_sendDeviceUpdatedToOnlinePeers());
  }

  Future<void> _removePeer(SyncPeer peer) async {
    await _sendUnpairRequest(peer);
    setState(
      () => _peers = _peers.where((item) => item.id != peer.id).toList(),
    );
    await _savePeers();
  }

  Future<void> _sendUnpairRequest(SyncPeer peer) async {
    try {
      final socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: const Duration(seconds: 3),
      );
      socket.writeln(jsonEncode(_unpairRequestPayloadForPeer(peer)));
      await socket.flush();
      await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 4));
      await socket.close();
    } catch (_) {}
  }

  Future<void> _confirmRemovePeer(SyncPeer peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = context.l10n;
        return AlertDialog(
          icon: const Icon(Icons.link_off),
          title: Text(l10n.removeSyncDeviceTitle),
          content: Text(
            '${l10n.removeSyncDeviceBodyPrefix} "${peer.name}" ${l10n.removeSyncDeviceBodySuffix}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: _ButtonLabel(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: _ButtonLabel(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed == true) await _removePeer(peer);
  }

  Future<void> _renamePeer(SyncPeer peer) async {
    final name = await _showRenameDeviceDialog(
      title: context.l10n.renameDevice,
      initialName: peer.name,
    );
    if (name == null) return;
    final index = _peers.indexWhere((item) => item.id == peer.id);
    if (index < 0) return;
    setState(() => _peers[index] = peer.copyWith(name: name));
    await _savePeers();
  }

  Future<void> _testPeerConnection(SyncPeer peer) async {
    final l10n = context.l10n;
    final index = _peers.indexWhere((item) => item.id == peer.id);
    Socket? socket;
    try {
      socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: const Duration(seconds: 3),
      );
      socket.writeln(jsonEncode(_pingPayloadForPeer(peer)));
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 4));
      await socket.close();
      socket = null;

      final response = jsonDecode(line) as Map<String, dynamic>;
      if (response['error'] != null) {
        throw Exception(response['error']);
      }
      final gotPong = response['action'] == 'pong';
      if (index >= 0) {
        final changed = _updatePeerFromSyncPayload(
          response,
          fallbackPeer: peer,
          markSynced: true,
        );
        setState(() {
          if (!changed && index < _peers.length) {
            _peers[index] = peer.copyWith(
              lastSyncedAt: DateTime.now(),
              clearError: true,
            );
          }
        });
      }
      _showCenterSnackBar(
        gotPong
            ? 'Ping ${peer.name}!'
            : '${peer.name}: ${l10n.connectionSuccess}',
      );
    } catch (error) {
      final message = _friendlySyncError(error);
      if (index >= 0) {
        setState(() => _peers[index] = peer.copyWith(lastError: message));
      }
      _showCenterSnackBar('${l10n.connectionFailedPrefix} ${peer.name}.');
    } finally {
      await socket?.close();
    }
    await _savePeers();
  }

  void _setKindFilter(ClipboardKind? kind) {
    setState(() {
      _kindFilter = kind;
      _selectedIndex = 0;
    });
  }

  void _setHistoryScopeFilter(_HistoryScopeFilter filter) {
    setState(() {
      _historyScopeFilter = filter;
      _selectedIndex = 0;
    });
  }

  int _historyScopeIndex(_HistoryScopeFilter filter) {
    return _HistoryScopeFilter.values.indexOf(filter).clamp(0, 2);
  }

  void _toggleBulkSelectMode() {
    setState(() {
      _bulkSelectMode = !_bulkSelectMode;
      if (!_bulkSelectMode) _bulkSelectedIds = {};
    });
  }

  void _toggleBulkSelected(ClipboardEntry entry) {
    setState(() {
      if (!_bulkSelectedIds.add(entry.id)) {
        _bulkSelectedIds.remove(entry.id);
      }
    });
  }

  Future<void> _deleteBulkSelectedEntries() async {
    final entries = _entries
        .where((entry) => _bulkSelectedIds.contains(entry.id))
        .toList();
    if (entries.isEmpty) return;
    _deleteEntriesWithUndo(entries);
    setState(() {
      _bulkSelectedIds = {};
      _bulkSelectMode = false;
    });
  }

  void _toggleAllVisibleBulkEntries() {
    setState(() {
      _bulkSelectMode = true;
      final visibleIds = _visibleEntries.map((entry) => entry.id).toSet();
      final allVisibleSelected =
          visibleIds.isNotEmpty && visibleIds.every(_bulkSelectedIds.contains);
      if (allVisibleSelected) {
        _bulkSelectedIds = {..._bulkSelectedIds}..removeAll(visibleIds);
      } else {
        _bulkSelectedIds = {..._bulkSelectedIds, ...visibleIds};
      }
    });
  }

  Future<void> _setBulkPinned(bool pinned) async {
    final storage = _storage;
    if (storage == null || _bulkSelectedIds.isEmpty) return;
    final updatedEntries = <ClipboardEntry>[];
    final selectedEntries = _entries
        .where((entry) => _bulkSelectedIds.contains(entry.id))
        .toList();
    for (final entry in selectedEntries) {
      await storage.setPinned(entry.id, pinned);
      updatedEntries.add(entry.copyWith(pinned: pinned));
    }
    unawaited(_pushEntriesToOnlinePeers(updatedEntries, touchExisting: false));
    await _loadEntries();
    if (!mounted) return;
    _showCenterSnackBar(
      pinned ? context.l10n.bulkPinned : context.l10n.bulkUnpinned,
    );
  }

  Future<void> _addTagsToBulkSelectedEntries() async {
    final storage = _storage;
    if (storage == null || _bulkSelectedIds.isEmpty) return;
    final selectedEntries = _entries
        .where((entry) => _bulkSelectedIds.contains(entry.id))
        .toList();
    final updatedEntries = <ClipboardEntry>[];
    final knownTags =
        {
            ..._tagDefinitions.keys,
            for (final item in _entries) ...item.tags,
          }.where((tag) => tag.trim().isNotEmpty).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final result = await showDialog<_TagEditResult>(
      context: context,
      builder: (context) => _TagEditorDialog(
        initialTags: const [],
        knownTags: knownTags,
        definitions: _tagDefinitions,
      ),
    );
    if (result == null || result.tags.isEmpty) return;
    _tagDefinitions = result.definitions;
    await _saveTagDefinitions();
    for (final entry in selectedEntries) {
      final mergedTags = {...entry.tags, ...result.tags}.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      await storage.setTags(entry.id, mergedTags);
      updatedEntries.add(entry.copyWith(tags: mergedTags));
    }
    unawaited(_pushEntriesToOnlinePeers(updatedEntries, touchExisting: false));
    await _loadEntries();
    if (!mounted) return;
    final l10n = context.l10n;
    _showCenterSnackBar(
      '${l10n.bulkTaggedPrefix} ${_localizedItemCount(l10n, selectedEntries.length)}${l10n.bulkTaggedSuffix}',
    );
  }

  void _sortEntries() {
    _entries.sort(_sortClipboardEntries);
  }

  int _mobileSectionIndex(String section) {
    return _mobileMainSections.indexOf(section);
  }

  void _syncMobilePageToSection(String section) {
    final index = _mobileSectionIndex(section);
    if (index < 0) return;
    if (!_mobilePageController.hasClients ||
        _mobilePageController.positions.length != 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_mobilePageController.hasClients ||
            _mobilePageController.positions.length != 1) {
          return;
        }
        final currentPage = _mobilePageController.page?.round();
        if (currentPage == index) return;
        _mobilePageController.jumpToPage(index);
      });
      return;
    }
    final rawPage = _mobilePageController.page;
    final currentPage = rawPage?.round();
    if (currentPage == index && ((rawPage ?? index) - index).abs() < 0.001) {
      if (_mobileToolbarDragging) return;
      if (_mobilePageAnimationTargetIndex != null ||
          _mobileToolbarDragPosition != null) {
        setState(() {
          _mobilePageAnimationTargetIndex = null;
          _mobileToolbarDragPosition = null;
        });
      }
      return;
    }
    final fromPage = rawPage ?? currentPage?.toDouble() ?? 0;
    final pageDistance = (index - fromPage).abs().clamp(1.0, 3.0);
    final duration = Duration(
      milliseconds:
          (index == 1 && fromPage > 0 && fromPage < 1
                  ? 260 + (1 - fromPage) * 180
                  : 320 + pageDistance * 140)
              .round(),
    );
    _mobilePageAnimationTargetIndex = index;
    unawaited(
      _mobilePageController
          .animateToPage(
            index,
            duration: duration,
            curve: Curves.easeInOutCubic,
          )
          .whenComplete(() {
            if (!mounted) return;
            if (_mobileToolbarDragging) return;
            if (_mobilePageAnimationTargetIndex == index) {
              setState(() {
                _mobilePageAnimationTargetIndex = null;
                _mobileToolbarDragPosition = null;
              });
            }
          }),
    );
  }

  void _openFileTransferSectionForStagedFiles() {
    _section = 'Gửi file';
    _selectedIndex = 0;
    _settingsUpdatePageOpen = false;
    _mobileSearchOpen = false;
    _fileTransferStatusFilter = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncMobilePageToSection('Gửi file');
    });
  }

  void _selectSection(String section, {bool syncMobilePage = true}) {
    setState(() {
      _section = section;
      _selectedIndex = 0;
      if (section != 'Cài đặt') {
        _settingsUpdatePageOpen = false;
      }
      if (!_isClipboardSection) {
        _mobileSearchOpen = false;
      }
    });
    if (syncMobilePage) {
      _syncMobilePageToSection(section);
    }
    if (section == 'Thiết bị') {
      unawaited(_refreshSyncHost());
    }
  }

  void _selectMobileToolbarSection(String section) {
    final index = _mobileSectionIndex(section);
    if (index < 0) {
      _selectSection(section);
      return;
    }
    final currentPage =
        _mobilePageController.hasClients &&
            _mobilePageController.positions.length == 1
        ? _mobilePageController.page?.round()
        : null;
    if (currentPage == index) {
      _selectSection(section, syncMobilePage: false);
      return;
    }
    setState(() {
      _mobilePageAnimationTargetIndex = index;
      if (section == 'Lịch sử') {
        _historyScopeFilter = _HistoryScopeFilter.all;
      }
      _selectedIndex = 0;
      if (section != 'Cài đặt') {
        _settingsUpdatePageOpen = false;
      }
      if (!_isClipboardSectionFor(section)) {
        _mobileSearchOpen = false;
      }
    });
    _syncMobilePageToSection(section);
  }

  void _openUpdateSettingsPage() {
    setState(() {
      _section = 'Cài đặt';
      _settingsUpdatePageOpen = true;
      _mobileSearchOpen = false;
    });
    _syncMobilePageToSection('Cài đặt');
  }

  void _closeUpdateSettingsPage() {
    if (!_settingsUpdatePageOpen) return;
    setState(() => _settingsUpdatePageOpen = false);
  }

  void _jumpMobilePageToToolbarPosition(double page) {
    if (!_mobilePageController.hasClients ||
        _mobilePageController.positions.length != 1) {
      return;
    }
    final pagePosition = _mobilePageController.position;
    final targetPixels = page * pagePosition.viewportDimension;
    if (!targetPixels.isFinite) return;
    pagePosition.jumpTo(
      targetPixels.clamp(
        pagePosition.minScrollExtent,
        pagePosition.maxScrollExtent,
      ),
    );
  }

  void _updateMobileToolbarDragPosition(double position) {
    if (!mounted || _mobileMainSections.isEmpty) return;
    final clamped = position.clamp(
      0.0,
      (_mobileMainSections.length - 1).toDouble(),
    );
    final wasDragging = _mobileToolbarDragging;
    _mobileToolbarDragPosition = clamped;
    _mobilePageAnimationTargetIndex = null;
    if (!wasDragging) {
      setState(() => _mobileToolbarDragging = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_mobileToolbarDragging) return;
        _jumpMobilePageToToolbarPosition(_mobileToolbarDragPosition ?? clamped);
      });
      return;
    }
    _jumpMobilePageToToolbarPosition(clamped);
  }

  void _endMobileToolbarDrag(int index) {
    if (!mounted || _mobileMainSections.isEmpty) return;
    final clampedIndex = index.clamp(0, _mobileMainSections.length - 1).toInt();
    final section = _mobileMainSections[clampedIndex];
    final rawPage =
        _mobilePageController.hasClients &&
            _mobilePageController.positions.length == 1
        ? _mobilePageController.page
        : null;
    final exactAtTarget =
        ((rawPage ?? clampedIndex) - clampedIndex).abs() < 0.001;
    if (exactAtTarget) {
      setState(() {
        _mobileToolbarDragging = false;
        _mobileToolbarDragPosition = null;
        _mobilePageAnimationTargetIndex = null;
      });
      _selectSection(section, syncMobilePage: false);
      return;
    }
    setState(() {
      _section = section;
      _mobileToolbarDragging = false;
      _mobileToolbarDragPosition = clampedIndex.toDouble();
      _mobilePageAnimationTargetIndex = clampedIndex;
      if (section == 'Lịch sử') {
        _historyScopeFilter = _HistoryScopeFilter.all;
      }
      _selectedIndex = 0;
      if (!_isClipboardSectionFor(section)) {
        _mobileSearchOpen = false;
      }
    });
    _syncMobilePageToSection(section);
  }

  void _cancelMobileToolbarDrag() {
    if (!mounted || _mobileToolbarDragPosition == null) return;
    _mobileToolbarDragging = false;
    setState(() => _mobileToolbarDragPosition = null);
    _syncMobilePageToSection(_section);
  }

  void _toggleMobileSearch() {
    setState(() {
      if (!_isClipboardSection) {
        _section = 'Lịch sử';
        _historyScopeFilter = _HistoryScopeFilter.all;
        _selectedIndex = 0;
        _mobileSearchOpen = true;
        _syncMobilePageToSection('Lịch sử');
      } else {
        if (_mobileSearchOpen) {
          _searchController.clear();
          _selectedIndex = 0;
        }
        _mobileSearchOpen = !_mobileSearchOpen;
      }
    });
    if (_mobileSearchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    } else {
      _searchFocusNode.unfocus();
    }
  }

  void _clearMobileSearchText() {
    _searchController.clear();
    setState(() => _selectedIndex = 0);
    _searchFocusNode.requestFocus();
  }

  String _historyListTitle([String? section]) {
    final l10n = context.l10n;
    return switch (section ?? _section) {
      'Đã ghim' => l10n.pinnedTitle,
      'Thẻ' => l10n.taggedTitle,
      _ => l10n.historyTitle,
    };
  }

  String _historyEmptyMessage({
    String? section,
    required bool hasHistoryFilters,
  }) {
    final l10n = context.l10n;
    if (hasHistoryFilters) {
      return l10n.noMatchingItems;
    }
    return switch (section ?? _section) {
      'Đã ghim' => l10n.noPinnedItems,
      'Thẻ' => l10n.noTaggedItems,
      _ => l10n.noClipboardItems,
    };
  }

  void _openMobileEntryDetail(ClipboardEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;
    var sheetEntry = entry;
    var sheetOpen = true;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return FractionallySizedBox(
                heightFactor: 0.48,
                child: Column(
                  children: [
                    const _CompactSheetDragHandle(),
                    Expanded(
                      child: _DetailPanel(
                        entry: sheetEntry,
                        compact: true,
                        onRestore: () {
                          unawaited(_copyEntryToClipboard(sheetEntry));
                          Navigator.of(context).pop();
                        },
                        onOpenUrl: sheetEntry.kind == ClipboardKind.url
                            ? () {
                                unawaited(_openUrlEntry(sheetEntry));
                                Navigator.of(context).pop();
                              }
                            : null,
                        onOpenFileLocation:
                            sheetEntry.kind == ClipboardKind.fileReference
                            ? () => _openFileLocation(sheetEntry)
                            : null,
                        onTogglePin: () async {
                          final previousEntry = sheetEntry;
                          setSheetState(() {
                            sheetEntry = sheetEntry.copyWith(
                              pinned: !sheetEntry.pinned,
                            );
                          });
                          await _togglePin(previousEntry);
                        },
                        onDelete: () {
                          Navigator.of(context).pop();
                          unawaited(_deleteEntry(sheetEntry));
                        },
                        onEditTags: () async {
                          await _editTags(sheetEntry);
                          if (!sheetOpen) return;
                          final updatedEntry = _entries.where(
                            (item) => item.id == sheetEntry.id,
                          );
                          if (updatedEntry.isEmpty) return;
                          setSheetState(() {
                            sheetEntry = updatedEntry.first;
                          });
                        },
                        tagDefinitions: _definitionsForEntry(sheetEntry),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ).whenComplete(() => sheetOpen = false),
    );
  }

  Widget _buildHistoryList({
    required List<ClipboardEntry> visibleEntries,
    required bool mobile,
    bool compact = false,
    String? section,
    _HistoryScopeFilter? historyScope,
  }) {
    final activeSection = section ?? _section;
    final activeHistoryScope = historyScope ?? _historyScopeFilter;
    final showHistoryScopeFilter = activeSection == 'Lịch sử';
    final hasHistoryFilters =
        _kindFilter != null ||
        (showHistoryScopeFilter &&
            activeHistoryScope != _HistoryScopeFilter.all) ||
        (!showHistoryScopeFilter && _tagFilters.isNotEmpty);
    return _HistoryList(
      title: _historyListTitle(activeSection),
      emptyMessage: _historyEmptyMessage(
        section: activeSection,
        hasHistoryFilters: hasHistoryFilters,
      ),
      entries: visibleEntries,
      tagDefinitions: _tagDefinitions,
      promotedEntryId: _promotedEntryId,
      promotionToken: _promotionToken,
      selectedKind: _kindFilter,
      selectedScope: activeHistoryScope,
      selectedScopePosition: _historyScopeIndex(activeHistoryScope).toDouble(),
      showScopeFilter: showHistoryScopeFilter,
      bulkSelectMode: _bulkSelectMode,
      bulkSelectedIds: _bulkSelectedIds,
      selectedIndex: _selectedIndex,
      loaded: _loaded,
      compact: mobile || compact,
      bottomContentPadding: mobile ? 96 : 12,
      onKindSelected: _setKindFilter,
      onScopeSelected: _setHistoryScopeFilter,
      onCopy: (entry) => unawaited(_copyEntryToClipboard(entry)),
      onTogglePin: (entry) => unawaited(_togglePin(entry)),
      onEditTags: (entry) => unawaited(_editTags(entry)),
      onDelete: (entry) => unawaited(_deleteEntry(entry)),
      onToggleBulkSelectMode: _toggleBulkSelectMode,
      onToggleBulkSelected: _toggleBulkSelected,
      onSelectAllBulkVisible: _toggleAllVisibleBulkEntries,
      onSetBulkPinned: (pinned) => unawaited(_setBulkPinned(pinned)),
      onAddBulkTags: () => unawaited(_addTagsToBulkSelectedEntries()),
      onDeleteBulkSelected: () => unawaited(_deleteBulkSelectedEntries()),
      onClearUnpinned: _confirmAndClearUnpinned,
      onManageTags: activeSection == 'Thẻ'
          ? () => unawaited(_manageTags())
          : null,
      hideHeaderActions:
          mobile && _mobileSearchOpen && activeSection == _section,
      headerReplacement:
          mobile && _mobileSearchOpen && activeSection == _section
          ? _MobileInlineSearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (_) => setState(() => _selectedIndex = 0),
              onClear: _clearMobileSearchText,
            )
          : null,
      onSelected: (index) {
        setState(() => _selectedIndex = index);
        if (mobile && index >= 0 && index < visibleEntries.length) {
          _openMobileEntryDetail(visibleEntries[index]);
        }
      },
      onContextSelected: (index) {
        setState(() => _selectedIndex = index);
      },
    );
  }

  Widget _buildSectionContent({String? section}) {
    final activeSection = section ?? _section;
    if (activeSection == 'Thiết bị') {
      return _DevicesPage(
        peers: _peers,
        discoveredDevices: _discoveredDevices.values.toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ),
        identity: _syncIdentity,
        lanSyncEnabled: _lanSyncEnabled,
        syncHost: _syncHost,
        syncPort: _syncPort,
        syncError: _syncError,
        onAddPeer: _addPeer,
        onScanPairQr: Platform.isAndroid ? _scanAndAddPeer : null,
        onCopyPairPayload: _copyLocalPairPayload,
        onRenameLocalDevice: _renameLocalDevice,
        onAddDiscoveredPeer: _addDiscoveredPeer,
        onSyncPeer: _syncPeer,
        onTestPeer: _testPeerConnection,
        onRenamePeer: _renamePeer,
        onRemovePeer: _confirmRemovePeer,
      );
    }

    if (activeSection == 'Gửi file') {
      return _FileTransferPage(
        peers: _onlineFileTransferPeers,
        transfers: _fileTransfers,
        selectedFiles: _selectedTransferFiles,
        selectedPeerIds: _fileTransferTargetIds,
        statusFilter: _fileTransferStatusFilter,
        draggingFiles: _draggingTransferFiles,
        lanSyncEnabled: _lanSyncEnabled,
        onPickFiles: () => unawaited(_pickTransferFiles()),
        onPickFolder: () => unawaited(_pickTransferFolder()),
        onDropPaths: (paths) => unawaited(_addTransferPaths(paths)),
        onDragChanged: (dragging) =>
            setState(() => _draggingTransferFiles = dragging),
        onRemoveSelectedFile: _removeSelectedTransferFile,
        onClearSelectedFiles: _clearSelectedTransferFiles,
        onTogglePeer: _toggleFileTransferTarget,
        onToggleAllPeers: _toggleAllFileTransferTargets,
        onSendSelected: () => unawaited(_sendSelectedFilesToTargets()),
        onStatusFilterChanged: (status) =>
            setState(() => _fileTransferStatusFilter = status),
        onClearTransferHistory: () =>
            unawaited(_clearFinishedFileTransferHistory()),
        onOpenTransferFile: _openFileTransferLocalFile,
        onCancelTransfer: _cancelFileTransfer,
      );
    }

    if (activeSection == 'Cài đặt') {
      return _SettingsPageSlideSwitcher(
        showUpdatePage: _settingsUpdatePageOpen,
        mainPage: _SettingsPage(
          capturePaused: _capturePaused,
          storagePath: _historyFilePathPreview(),
          clipboardSettings: _clipboardSettings,
          sourceSuggestions: _knownSourceSuggestions(),
          themeMode: widget.themeMode,
          themePreset: widget.themePreset,
          language: widget.language,
          androidIgnoringBatteryOptimizations:
              _androidIgnoringBatteryOptimizations,
          onToggleCapture: () {
            setState(() => _capturePaused = !_capturePaused);
            if (!_capturePaused) _captureClipboardText();
          },
          onRetentionLimitChanged: _updateRetentionLimit,
          onClipboardSettingsChanged: _updateClipboardSettings,
          onAddExcludedSource: _addExcludedSource,
          onRemoveExcludedSource: _removeExcludedSource,
          onThemeModeChanged: widget.onThemeModeChanged,
          onThemePresetChanged: widget.onThemePresetChanged,
          onLanguageChanged: widget.onLanguageChanged,
          onOpenDataDirectory: () => unawaited(_openDataDirectory()),
          onExportBackup: () => unawaited(_exportDataBackup()),
          onRestoreBackup: () => unawaited(_restoreDataBackup()),
          onResetClipboardHistory: () =>
              unawaited(_confirmResetClipboardHistory()),
          onOpenAndroidNotificationSettings: _openAndroidNotificationSettings,
          onToggleAndroidBatteryOptimizationBypass: (enabled) =>
              unawaited(_toggleAndroidBatteryOptimizationBypass(enabled)),
          onOpenDevices: null,
          onOpenUpdates: _openUpdateSettingsPage,
        ),
        updatePage: _UpdateSettingsPage(
          currentVersion: _appVersionLabel,
          autoCheckUpdates: _clipboardSettings.autoCheckUpdates,
          checking: _checkingForUpdates,
          latestMessage: _latestUpdateMessage,
          onBack: _closeUpdateSettingsPage,
          onCheckNow: () => unawaited(_checkForUpdates()),
          onToggleAutoCheck: (value) => unawaited(
            _updateClipboardSettings(
              _clipboardSettings.copyWith(autoCheckUpdates: value),
            ),
          ),
          onOpenLandingPage: () => unawaited(_openExternalUrl(_landingPageUrl)),
          onOpenGithub: () => unawaited(_openExternalUrl(_githubRepoUrl)),
        ),
      );
    }

    final visibleEntries = section == null
        ? _visibleEntries
        : _visibleEntriesForSection(activeSection);
    final selectedEntry = _selectedEntry;
    final compactDesktop =
        MediaQuery.sizeOf(context).width < _compactDesktopLayoutBreakpoint;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactColumns = constraints.maxWidth < 960;
        final historyWidth = (constraints.maxWidth * 0.52)
            .clamp(
              compactColumns ? 360.0 : 480.0,
              compactColumns ? 500.0 : 680.0,
            )
            .toDouble();
        return Row(
          children: [
            SizedBox(
              width: historyWidth,
              child: _buildHistoryList(
                visibleEntries: visibleEntries,
                mobile: false,
                compact: compactDesktop,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: _DetailPanel(
                      entry: selectedEntry,
                      compact: compactDesktop,
                      actionBarKey: _desktopDetailActionBarKey,
                      onRestore: selectedEntry == null
                          ? null
                          : () => _copyEntryToClipboard(selectedEntry),
                      onOpenUrl: selectedEntry == null
                          ? null
                          : () => _openUrlEntry(selectedEntry),
                      onOpenFileLocation: selectedEntry == null
                          ? null
                          : () => _openFileLocation(selectedEntry),
                      onTogglePin: selectedEntry == null
                          ? null
                          : () => _togglePin(selectedEntry),
                      onDelete: selectedEntry == null
                          ? null
                          : () => _deleteEntry(selectedEntry),
                      onEditTags: selectedEntry == null
                          ? null
                          : () => _editTags(selectedEntry),
                      tagDefinitions: selectedEntry == null
                          ? const {}
                          : _definitionsForEntry(selectedEntry),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<String> _knownSourceSuggestions() {
    final excluded = _clipboardSettings.excludedSources
        .map((source) => source.toLowerCase())
        .toSet();
    final sources =
        _entries
            .map((entry) => entry.source.trim())
            .where((source) => source.isNotEmpty)
            .where((source) => !excluded.contains(source.toLowerCase()))
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sources.take(12).toList();
  }

  bool _isClipboardSectionFor(String section) =>
      section != 'Thiết bị' && section != 'Gửi file' && section != 'Cài đặt';

  bool get _isClipboardSection => _isClipboardSectionFor(_section);

  Widget _buildMobileSectionContent({String? section}) {
    final activeSection = section ?? _section;
    if (activeSection == 'Lịch sử') {
      return _buildHistoryList(
        visibleEntries: _visibleEntriesForSection('Lịch sử'),
        mobile: true,
        section: 'Lịch sử',
      );
    }
    if (_isClipboardSectionFor(activeSection)) {
      return _buildHistoryList(
        visibleEntries: _visibleEntriesForSection(activeSection),
        mobile: true,
        section: activeSection,
      );
    }
    return _buildSectionContent(section: activeSection);
  }

  Widget _buildMobileTopBar({String? section}) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final activeSection = section ?? _section;
    final isClipboardSection = _isClipboardSectionFor(activeSection);
    final showingUpdatePage =
        activeSection == 'Cài đặt' && _settingsUpdatePageOpen;
    final title = switch (activeSection) {
      'Thiết bị' => l10n.devicesLan,
      'Gửi file' => l10n.navSendFiles,
      'Cài đặt' => showingUpdatePage ? l10n.updateApp : l10n.navSettings,
      _ => 'OpenCB',
    };
    if (isClipboardSection) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 64,
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              if (activeSection == 'Cài đặt')
                Expanded(
                  child: _MobileSettingsTopBarTitle(
                    showUpdatePage: showingUpdatePage,
                    onBack: _closeUpdateSettingsPage,
                  ),
                )
              else ...[
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (activeSection == 'Thiết bị') ...[
                  Tooltip(
                    message: 'Sync tất cả thiết bị LAN',
                    child: IconButton.filledTonal(
                      onPressed: _syncAllPeers,
                      icon: const Icon(Icons.sync),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Switch(value: _lanSyncEnabled, onChanged: _toggleLanSync),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileScaffold() {
    final l10n = context.l10n;
    final sections =
        <
          ({IconData icon, IconData selectedIcon, String section, String label})
        >[
          (
            icon: Icons.history_outlined,
            selectedIcon: Icons.history,
            section: 'Lịch sử',
            label: l10n.navHistory,
          ),
          (
            icon: Icons.compare_arrows_rounded,
            selectedIcon: Icons.compare_arrows_rounded,
            section: 'Gửi file',
            label: l10n.navSendFiles,
          ),
          (
            icon: Icons.devices_other_outlined,
            selectedIcon: Icons.devices_other,
            section: 'Thiết bị',
            label: l10n.navDevices,
          ),
          (
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            section: 'Cài đặt',
            label: l10n.navSettings,
          ),
        ];
    final targetIndex = _mobilePageAnimationTargetIndex;
    final mobileSection =
        targetIndex != null &&
            targetIndex >= 0 &&
            targetIndex < _mobileMainSections.length
        ? _mobileMainSections[targetIndex]
        : _mobileMainSections.contains(_section)
        ? _section
        : 'Lịch sử';
    final selectedIndex = sections.indexWhere(
      (section) => section.section == mobileSection,
    );
    Widget buildMobileMainPage(String section) {
      final page = Column(
        children: [
          _buildMobileTopBar(section: section),
          Expanded(child: _buildMobileSectionContent(section: section)),
        ],
      );
      return KeyedSubtree(
        key: PageStorageKey<String>('mobile-$section'),
        child: RepaintBoundary(child: page),
      );
    }

    final showFloatingToolbar = !_settingsUpdatePageOpen;
    final showMobileSearchButton = showFloatingToolbar;
    return PopScope(
      canPop: !_settingsUpdatePageOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_settingsUpdatePageOpen) {
          _closeUpdateSettingsPage();
        }
        return;
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        body: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
              ),
            ),
            SafeArea(
              child: Stack(
                children: [
                  PageView(
                    controller: _mobilePageController,
                    pageSnapping: !_mobileToolbarDragging,
                    physics: _mobileToolbarDragging
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    onPageChanged: (index) {
                      if (index < 0 || index >= _mobileMainSections.length) {
                        return;
                      }
                      if (_mobileToolbarDragging) {
                        return;
                      }
                      final targetIndex = _mobilePageAnimationTargetIndex;
                      if (targetIndex != null && index != targetIndex) return;
                      final pageSection = _mobileMainSections[index];
                      setState(() {
                        _section = pageSection;
                        _selectedIndex = 0;
                        if (pageSection != 'Cài đặt') {
                          _settingsUpdatePageOpen = false;
                        }
                        if (!_isClipboardSectionFor(pageSection)) {
                          _mobileSearchOpen = false;
                        }
                      });
                      if (pageSection == 'Thiết bị') {
                        unawaited(_refreshSyncHost());
                      }
                    },
                    children: [
                      for (final section in _mobileMainSections)
                        buildMobileMainPage(section),
                    ],
                  ),
                  if (showFloatingToolbar)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: double.infinity,
                        height: 76,
                        child: Row(
                          children: [
                            Expanded(
                              child: AnimatedBuilder(
                                animation: _mobilePageController,
                                builder: (context, _) {
                                  final targetIndex =
                                      _mobilePageAnimationTargetIndex;
                                  var selectedPosition =
                                      (selectedIndex < 0 ? 0 : selectedIndex)
                                          .toDouble();
                                  if (_mobileToolbarDragPosition != null) {
                                    selectedPosition =
                                        _mobileToolbarDragPosition!;
                                  } else if (_mobilePageController.hasClients &&
                                      _mobilePageController.positions.length ==
                                          1) {
                                    selectedPosition =
                                        _mobilePageController.page ??
                                        selectedPosition;
                                  }
                                  final effectiveSelectedIndex =
                                      targetIndex ??
                                      (selectedIndex < 0 ? 0 : selectedIndex);
                                  final visualSelectedIndex =
                                      _mobileToolbarDragPosition == null
                                      ? effectiveSelectedIndex
                                      : (selectedIndex < 0 ? 0 : selectedIndex);
                                  return _MobileFloatingToolbar(
                                    items: sections,
                                    selectedIndex: visualSelectedIndex,
                                    selectedPosition: selectedPosition,
                                    onSelected: (index) =>
                                        _selectMobileToolbarSection(
                                          sections[index].section,
                                        ),
                                    onDragPositionChanged:
                                        _updateMobileToolbarDragPosition,
                                    onDragEnded: _endMobileToolbarDrag,
                                    onDragCanceled: _cancelMobileToolbarDrag,
                                  );
                                },
                              ),
                            ),
                            if (showMobileSearchButton)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  0,
                                  12,
                                  10,
                                ),
                                child: _MobileSearchButton(
                                  active: _mobileSearchOpen,
                                  onPressed: _toggleMobileSearch,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return _TopBar(
      section: _section,
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      onSearchChanged: (_) => setState(() => _selectedIndex = 0),
      onClearUnpinned: _confirmAndClearUnpinned,
      onOpenReceivedFolder: _openReceivedFilesFolder,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_quickPickerMode) {
      return Scaffold(
        body: SafeArea(
          child: IgnorePointer(
            ignoring: _quickPickerClosing,
            child: AnimatedOpacity(
              opacity: _quickPickerClosing ? 0 : 1,
              duration: _quickPickerExitDuration,
              curve: Curves.easeInCubic,
              child: AnimatedScale(
                scale: _quickPickerClosing ? 0.985 : 1,
                duration: _quickPickerExitDuration,
                curve: Curves.easeInCubic,
                child: _QuickPickerShell(
                  entries: _entries,
                  tagDefinitions: _tagDefinitions,
                  promotedEntryId: _promotedEntryId,
                  promotionToken: _promotionToken,
                  onSelected: _handleQuickPickerShellSelection,
                  onTogglePin: _toggleQuickPickerPin,
                  onOpenItem: (entry) async {
                    if (entry.kind == ClipboardKind.url) {
                      await _openUrlEntry(entry);
                    } else if (entry.kind == ClipboardKind.fileReference) {
                      await _openFileLocation(entry);
                    }
                  },
                  onDeleteItem: _deleteEntry,
                  onOpenMainApp: _openMainAppFromQuickPicker,
                  onClose: _closeQuickPickerShell,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _mobileLayoutBreakpoint) {
          return _buildMobileScaffold();
        }
        final compactDesktop =
            constraints.maxWidth < _compactDesktopLayoutBreakpoint;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                SizedBox(
                  width: compactDesktop ? 76 : 188,
                  child: _Sidebar(
                    currentSection: _section,
                    onSectionChanged: _selectSection,
                    lanSyncEnabled: _lanSyncEnabled,
                    syncInFlight: _autoSyncInFlight,
                    onToggleSync: _toggleLanSync,
                    onSyncAll: _syncAllPeers,
                    compact: compactDesktop,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _isClipboardSection
                      ? _buildSectionContent()
                      : Column(
                          children: [
                            _buildTopBar(),
                            Expanded(child: _buildSectionContent()),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.currentSection,
    required this.onSectionChanged,
    required this.lanSyncEnabled,
    required this.syncInFlight,
    required this.onToggleSync,
    required this.onSyncAll,
    this.compact = false,
  });

  final String currentSection;
  final ValueChanged<String> onSectionChanged;
  final bool lanSyncEnabled;
  final bool syncInFlight;
  final ValueChanged<bool> onToggleSync;
  final FutureOr<void> Function() onSyncAll;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final items =
        <
          ({IconData icon, IconData selectedIcon, String section, String label})
        >[
          (
            icon: Icons.history_outlined,
            selectedIcon: Icons.history,
            section: 'Lịch sử',
            label: l10n.navHistory,
          ),
          (
            icon: Icons.bookmark_border,
            selectedIcon: Icons.bookmark,
            section: 'Đã ghim',
            label: l10n.navPinned,
          ),
          (
            icon: Icons.sell_outlined,
            selectedIcon: Icons.sell,
            section: 'Thẻ',
            label: l10n.navTags,
          ),
          (
            icon: Icons.compare_arrows_rounded,
            selectedIcon: Icons.compare_arrows_rounded,
            section: 'Gửi file',
            label: l10n.navSendFiles,
          ),
          (
            icon: Icons.devices_other_outlined,
            selectedIcon: Icons.devices_other,
            section: 'Thiết bị',
            label: l10n.navDevices,
          ),
          (
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            section: 'Cài đặt',
            label: l10n.navSettings,
          ),
        ];
    final selectedIndex = items.indexWhere(
      (item) => item.section == currentSection,
    );
    Widget menuCursor(Widget child) {
      return MouseRegion(cursor: SystemMouseCursors.click, child: child);
    }

    if (compact) {
      return Material(
        color: colorScheme.surfaceContainer,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 20),
              child: _OpenCbLogoMark(size: 30),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in items)
                    _CompactSidebarDestination(
                      icon: item.icon,
                      selectedIcon: item.selectedIcon,
                      section: item.section,
                      label: item.label,
                      selected: item.section == currentSection,
                      onPressed: () => onSectionChanged(item.section),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: _SidebarLanSyncControls(
                enabled: lanSyncEnabled,
                syncing: syncInFlight,
                onToggle: onToggleSync,
                onSyncAll: onSyncAll,
                compact: true,
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: colorScheme.surfaceContainer,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.zero,
              child: NavigationRail(
                extended: true,
                selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
                minWidth: 56,
                minExtendedWidth: 178,
                useIndicator: true,
                indicatorColor: colorScheme.secondaryContainer,
                indicatorShape: const StadiumBorder(),
                selectedIconTheme: IconThemeData(
                  color: colorScheme.onSecondaryContainer,
                ),
                labelType: NavigationRailLabelType.none,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _OpenCbLogoMark(size: 28),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'OpenCB',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                destinations: [
                  for (final item in items)
                    NavigationRailDestination(
                      icon: menuCursor(
                        Tooltip(
                          message: item.label,
                          child: _OpenCbMenuIcon(
                            section: item.section,
                            icon: item.icon,
                          ),
                        ),
                      ),
                      selectedIcon: menuCursor(
                        Tooltip(
                          message: item.label,
                          child: _OpenCbMenuIcon(
                            section: item.section,
                            icon: item.selectedIcon,
                          ),
                        ),
                      ),
                      label: menuCursor(Text(item.label)),
                    ),
                ],
                onDestinationSelected: (index) =>
                    onSectionChanged(items[index].section),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: _SidebarLanSyncControls(
              enabled: lanSyncEnabled,
              syncing: syncInFlight,
              onToggle: onToggleSync,
              onSyncAll: onSyncAll,
              compact: compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileSearchButton extends StatelessWidget {
  const _MobileSearchButton({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = colorScheme.brightness == Brightness.dark;
    final glassFill = colorScheme.surfaceContainerHigh.withValues(
      alpha: isDark ? 0.58 : 0.46,
    );
    final glassBorder = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10),
      colorScheme.outlineVariant.withValues(alpha: 0.34),
    );
    final activeFill = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.38 : 0.30),
      colorScheme.surfaceContainerHighest.withValues(alpha: 0.74),
    );
    final background = active ? activeFill : glassFill;
    return Tooltip(
      message: active ? l10n.close : l10n.search,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 56,
        height: 56,
        decoration: ShapeDecoration(
          color: background,
          shape: CircleBorder(side: BorderSide(color: glassBorder, width: 1.1)),
          shadows: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Material(
              color: Colors.transparent,
              surfaceTintColor: colorScheme.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colorScheme.surfaceBright.withValues(
                                alpha: isDark ? 0.05 : 0.20,
                              ),
                              colorScheme.surfaceContainerHighest.withValues(
                                alpha: isDark ? 0.04 : 0.07,
                              ),
                              colorScheme.surfaceDim.withValues(
                                alpha: isDark ? 0.06 : 0.03,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onPressed,
                    mouseCursor: SystemMouseCursors.click,
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final rotationCurve = CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                            reverseCurve: Curves.easeInCubic,
                          );
                          final scaleCurve = CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutBack,
                            reverseCurve: Curves.easeInCubic,
                          );
                          return FadeTransition(
                            opacity: animation,
                            child: RotationTransition(
                              turns: Tween<double>(
                                begin: active ? -0.25 : 0.25,
                                end: 0,
                              ).animate(rotationCurve),
                              child: ScaleTransition(
                                scale: Tween<double>(
                                  begin: 0.82,
                                  end: 1,
                                ).animate(scaleCurve),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: Icon(
                          active ? Icons.close : Icons.search,
                          key: ValueKey(active),
                          color: active
                              ? Colors.black
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileSettingsTopBarTitle extends StatefulWidget {
  const _MobileSettingsTopBarTitle({
    required this.showUpdatePage,
    required this.onBack,
  });

  final bool showUpdatePage;
  final VoidCallback onBack;

  @override
  State<_MobileSettingsTopBarTitle> createState() =>
      _MobileSettingsTopBarTitleState();
}

class _MobileSettingsTopBarTitleState extends State<_MobileSettingsTopBarTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 390),
      reverseDuration: const Duration(milliseconds: 340),
      value: widget.showUpdatePage ? 1 : 0,
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _MobileSettingsTopBarTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showUpdatePage == oldWidget.showUpdatePage) return;
    if (widget.showUpdatePage) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);
    final l10n = context.l10n;
    return SizedBox(
      height: 44,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _curve,
          builder: (context, _) {
            final value = _curve.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                FractionalTranslation(
                  translation: Offset(-0.18 * value, 0),
                  child: Opacity(
                    opacity: 1 - (0.18 * value),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l10n.navSettings, style: titleStyle),
                    ),
                  ),
                ),
                FractionalTranslation(
                  translation: Offset(1 - value, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.chevron_left_rounded),
                        tooltip: l10n.back,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          l10n.updateApp,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MobileInlineSearchBar extends StatelessWidget {
  const _MobileInlineSearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        mouseCursor: SystemMouseCursors.click,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          labelText: l10n.search,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: IconButton(
            tooltip: l10n.clearSearch,
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 20),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 42,
            minHeight: 42,
          ),
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _MobileFloatingToolbar extends StatelessWidget {
  const _MobileFloatingToolbar({
    required this.items,
    required this.selectedIndex,
    required this.selectedPosition,
    required this.onSelected,
    required this.onDragPositionChanged,
    required this.onDragEnded,
    required this.onDragCanceled,
  });

  final List<
    ({IconData icon, IconData selectedIcon, String section, String label})
  >
  items;
  final int selectedIndex;
  final double selectedPosition;
  final ValueChanged<int> onSelected;
  final ValueChanged<double> onDragPositionChanged;
  final ValueChanged<int> onDragEnded;
  final VoidCallback onDragCanceled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(0.0, constraints.maxWidth - 24);
        final estimatedItemWidth = items.isEmpty
            ? availableWidth
            : availableWidth / items.length;
        final minItemWidthForLabels = textScale <= 1.18
            ? 66.0
            : textScale <= 1.35
            ? 74.0
            : 86.0;
        final showLabels =
            estimatedItemWidth >= minItemWidthForLabels && textScale <= 1.18;
        final isDark = colorScheme.brightness == Brightness.dark;
        final glassFill = colorScheme.surfaceContainerHigh.withValues(
          alpha: isDark ? 0.58 : 0.46,
        );
        final glassBorder = Color.alphaBlend(
          colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10),
          colorScheme.outlineVariant.withValues(alpha: 0.34),
        );
        final activePillColor = Color.alphaBlend(
          colorScheme.primary.withValues(alpha: isDark ? 0.38 : 0.30),
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.74),
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: glassFill,
                  shape: StadiumBorder(
                    side: BorderSide(color: glassBorder, width: 1.1),
                  ),
                  shadows: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      blurRadius: 28,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  colorScheme.surfaceBright.withValues(
                                    alpha: isDark ? 0.05 : 0.20,
                                  ),
                                  colorScheme.surfaceContainerHighest
                                      .withValues(alpha: isDark ? 0.04 : 0.07),
                                  colorScheme.surfaceDim.withValues(
                                    alpha: isDark ? 0.06 : 0.03,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: LayoutBuilder(
                          builder: (context, innerConstraints) {
                            const gap = 4.0;
                            final itemCount = items.length;
                            final totalGap = gap * math.max(0, itemCount - 1);
                            final itemWidth = itemCount == 0
                                ? 0.0
                                : math.max(
                                    48.0,
                                    (innerConstraints.maxWidth - totalGap) /
                                        itemCount,
                                  );
                            final clampedSelectedIndex = itemCount == 0
                                ? 0
                                : selectedIndex.clamp(0, itemCount - 1).toInt();
                            final clampedSelectedPosition = itemCount == 0
                                ? 0.0
                                : selectedPosition.clamp(
                                    0.0,
                                    (itemCount - 1).toDouble(),
                                  );
                            final indicatorLeft =
                                clampedSelectedPosition * (itemWidth + gap);
                            final isDraggingPage =
                                (clampedSelectedPosition -
                                        clampedSelectedPosition.round())
                                    .abs() >
                                0.001;
                            final indicatorDistance =
                                (clampedSelectedIndex - clampedSelectedPosition)
                                    .abs()
                                    .clamp(1.0, 3.0);
                            final indicatorDuration = Duration(
                              milliseconds: (320 + indicatorDistance * 140)
                                  .round(),
                            );
                            final toolbarHeight = showLabels ? 52.0 : 44.0;
                            double positionFromDx(double dx) {
                              if (itemCount <= 1) return 0;
                              return ((dx - itemWidth / 2) / (itemWidth + gap))
                                  .clamp(0.0, (itemCount - 1).toDouble());
                            }

                            return GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onHorizontalDragStart: (details) =>
                                  onDragPositionChanged(
                                    positionFromDx(details.localPosition.dx),
                                  ),
                              onHorizontalDragUpdate: (details) =>
                                  onDragPositionChanged(
                                    positionFromDx(details.localPosition.dx),
                                  ),
                              onHorizontalDragEnd: (details) {
                                final target = clampedSelectedPosition.round();
                                onDragEnded(target);
                              },
                              onHorizontalDragCancel: onDragCanceled,
                              child: SizedBox(
                                height: toolbarHeight,
                                child: Stack(
                                  children: [
                                    AnimatedPositioned(
                                      duration: isDraggingPage
                                          ? Duration.zero
                                          : indicatorDuration,
                                      curve: Curves.easeInOutCubic,
                                      left: indicatorLeft,
                                      top: 0,
                                      width: itemWidth,
                                      height: toolbarHeight,
                                      child: IgnorePointer(
                                        child: TweenAnimationBuilder<double>(
                                          key: ValueKey(
                                            'toolbar-pill-squash-$clampedSelectedIndex',
                                          ),
                                          tween: Tween(begin: 0, end: 1),
                                          duration: const Duration(
                                            milliseconds: 480,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          builder: (context, value, child) {
                                            final squash = math.sin(
                                              value * math.pi,
                                            );
                                            return Transform.scale(
                                              scaleX: 1 + squash * 0.025,
                                              scaleY: 1 - squash * 0.08,
                                              child: child,
                                            );
                                          },
                                          child: DecoratedBox(
                                            decoration: ShapeDecoration(
                                              color: activePillColor,
                                              shape: StadiumBorder(
                                                side: BorderSide(
                                                  color: colorScheme.primary
                                                      .withValues(alpha: 0.16),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.max,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        for (
                                          var index = 0;
                                          index < items.length;
                                          index++
                                        ) ...[
                                          Expanded(
                                            child: _MobileFloatingToolbarItem(
                                              icon: items[index].icon,
                                              selectedIcon:
                                                  items[index].selectedIcon,
                                              section: items[index].section,
                                              label: items[index].label,
                                              selected: index == selectedIndex,
                                              showLabel: showLabels,
                                              onPressed: () =>
                                                  onSelected(index),
                                            ),
                                          ),
                                          if (index != items.length - 1)
                                            const SizedBox(width: gap),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileFloatingToolbarItem extends StatelessWidget {
  const _MobileFloatingToolbarItem({
    required this.icon,
    required this.selectedIcon,
    required this.section,
    required this.label,
    required this.selected,
    required this.showLabel,
    required this.onPressed,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String section;
  final String label;
  final bool selected;
  final bool showLabel;
  final VoidCallback onPressed;

  Widget _buildIconTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    if (section == 'Gửi file') {
      final smooth = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: smooth, child: child),
      );
    }
    if (section == 'Cài đặt') {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: curved, child: child),
      );
    }
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, selected ? 0.18 : -0.12),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(scale: curved, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? Colors.black : colorScheme.onSurfaceVariant;
    final iconSize = section == 'Gửi file'
        ? (selected ? 25.0 : 24.0)
        : (selected ? 21.0 : 20.0);
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          mouseCursor: SystemMouseCursors.click,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: _buildIconTransition,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('$section-$selected'),
                      tween: Tween<double>(
                        begin: 0,
                        end: selected && section == 'Cài đặt'
                            ? 2.5
                            : selected && section == 'Lịch sử'
                            ? -1
                            : selected && section == 'Gửi file'
                            ? 1
                            : 0,
                      ),
                      duration: const Duration(milliseconds: 620),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Transform.rotate(
                          angle: value * math.pi * 2,
                          child: child,
                        );
                      },
                      child: AnimatedScale(
                        scale: selected ? 1.08 : 1,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutBack,
                        child: _OpenCbMenuIcon(
                          section: section,
                          icon: selected ? selectedIcon : icon,
                          size: iconSize,
                          color: foreground,
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: showLabel
                        ? Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: SizedBox(
                              width: double.infinity,
                              height: 12,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                  softWrap: false,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: foreground,
                                        fontWeight: FontWeight.w500,
                                        height: 1.0,
                                      ),
                                  textHeightBehavior: const TextHeightBehavior(
                                    applyHeightToFirstAscent: false,
                                    applyHeightToLastDescent: false,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenCbMenuIcon extends StatelessWidget {
  const _OpenCbMenuIcon({
    required this.section,
    required this.icon,
    this.size,
    this.color,
  });

  final String section;
  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (section != 'Gửi file') {
      return Icon(icon, size: size, color: color);
    }
    final iconTheme = IconTheme.of(context);
    return _OpenCbFileShareIcon(
      size: size ?? iconTheme.size ?? 24,
      color: color ?? iconTheme.color ?? Colors.black,
    );
  }
}

class _OpenCbFileShareIcon extends StatelessWidget {
  const _OpenCbFileShareIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: CustomPaint(painter: _OpenCbFileShareIconPainter(color)),
      ),
    );
  }
}

class _OpenCbFileShareIconPainter extends CustomPainter {
  const _OpenCbFileShareIconPainter(this.color);

  final Color color;

  static final Path _topPath = Path()
    ..moveTo(423.960938, 255.066406)
    ..cubicTo(
      415.589844,
      255.066406,
      408.421969,
      248.753906,
      407.542969,
      240.296875,
    )
    ..cubicTo(
      399.550781,
      162.804688,
      334.394531,
      104.371094,
      256.003906,
      104.371094,
    )
    ..cubicTo(
      192.488281,
      104.371094,
      136.726562,
      143.019531,
      114.167969,
      200.445312,
    )
    ..lineTo(214.425781, 200.445312)
    ..lineTo(206.3125, 192.367188)
    ..cubicTo(
      203.5625,
      189.636719,
      202.015625,
      185.917969,
      202.015625,
      182.042969,
    )
    ..cubicTo(
      202.015625,
      178.164062,
      203.5625,
      174.445312,
      206.3125,
      171.714844,
    )
    ..cubicTo(
      212.058594,
      166.007812,
      221.332031,
      166.007812,
      227.078125,
      171.714844,
    )
    ..lineTo(262.066406, 206.535156)
    ..cubicTo(
      264.820312,
      209.269531,
      266.367188,
      212.988281,
      266.367188,
      216.867188,
    )
    ..cubicTo(
      266.367188,
      220.746094,
      264.820312,
      224.46875,
      262.066406,
      227.199219,
    )
    ..lineTo(227.078125, 262.023438)
    ..cubicTo(
      221.335938,
      267.726562,
      212.066406,
      267.726562,
      206.324219,
      262.023438,
    )
    ..cubicTo(
      203.570312,
      259.289062,
      202.023438,
      255.566406,
      202.023438,
      251.6875,
    )
    ..cubicTo(
      202.023438,
      247.808594,
      203.570312,
      244.089844,
      206.324219,
      241.355469,
    )
    ..lineTo(214.378906, 233.339844)
    ..lineTo(92.957031, 233.339844)
    ..cubicTo(87.894531, 233.339844, 82.371094, 230.648438, 79.234375, 226.6875)
    ..cubicTo(
      76.089844,
      222.707031,
      74.78125,
      216.675781,
      75.992188,
      211.773438,
    )
    ..cubicTo(96.40625, 129.179688, 170.4375, 71.496094, 256.003906, 71.496094)
    ..cubicTo(
      351.394531,
      71.496094,
      430.675781,
      142.628906,
      440.417969,
      236.941406,
    )
    ..cubicTo(
      441.347656,
      245.96875,
      434.742188,
      254.050781,
      425.664062,
      254.976562,
    )
    ..cubicTo(
      425.097656,
      255.035156,
      424.53125,
      255.066406,
      423.960938,
      255.066406,
    )
    ..close();

  static final Path _bottomPath = Path()
    ..moveTo(86.339844, 256.816406)
    ..cubicTo(
      95.527344,
      255.996094,
      103.523438,
      262.488281,
      104.453125,
      271.515625,
    )
    ..cubicTo(
      104.730469,
      274.28125,
      105.089844,
      277.027344,
      105.519531,
      279.738281,
    )
    ..cubicTo(
      117.214844,
      353.84375,
      180.507812,
      407.609375,
      256.003906,
      407.609375,
    )
    ..cubicTo(
      319.546875,
      407.609375,
      375.324219,
      368.953125,
      397.867188,
      311.476562,
    )
    ..lineTo(297.519531, 311.476562)
    ..lineTo(305.695312, 319.613281)
    ..cubicTo(
      308.449219,
      322.347656,
      309.996094,
      326.066406,
      309.996094,
      329.945312,
    )
    ..cubicTo(
      309.996094,
      333.824219,
      308.449219,
      337.542969,
      305.695312,
      340.28125,
    )
    ..cubicTo(
      299.953125,
      345.984375,
      290.683594,
      345.984375,
      284.941406,
      340.28125,
    )
    ..lineTo(249.945312, 305.453125)
    ..cubicTo(
      247.195312,
      302.71875,
      245.644531,
      298.996094,
      245.644531,
      295.117188,
    )
    ..cubicTo(
      245.644531,
      291.238281,
      247.195312,
      287.519531,
      249.945312,
      284.785156,
    )
    ..lineTo(284.933594, 249.960938)
    ..cubicTo(
      290.679688,
      244.257812,
      299.953125,
      244.257812,
      305.699219,
      249.960938,
    )
    ..cubicTo(308.453125, 252.695312, 310, 256.414062, 310, 260.289062)
    ..cubicTo(310, 264.167969, 308.453125, 267.886719, 305.699219, 270.621094)
    ..lineTo(297.703125, 278.582031)
    ..lineTo(419.078125, 278.582031)
    ..cubicTo(
      424.140625,
      278.582031,
      429.671875,
      281.273438,
      432.800781,
      285.234375,
    )
    ..cubicTo(
      435.945312,
      289.214844,
      437.253906,
      295.207031,
      436.042969,
      300.128906,
    )
    ..cubicTo(
      415.652344,
      382.777344,
      341.621094,
      440.503906,
      256.003906,
      440.503906,
    )
    ..cubicTo(
      164.132812,
      440.503906,
      87.121094,
      375.035156,
      72.882812,
      284.84375,
    )
    ..cubicTo(
      72.359375,
      281.519531,
      71.925781,
      278.179688,
      71.582031,
      274.832031,
    )
    ..cubicTo(
      70.660156,
      265.808594,
      77.273438,
      257.742188,
      86.339844,
      256.816406,
    )
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.save();
    canvas.scale(size.width / 512, size.height / 512);
    canvas.drawPath(_topPath, strokePaint);
    canvas.drawPath(_bottomPath, strokePaint);
    canvas.drawPath(_topPath, fillPaint);
    canvas.drawPath(_bottomPath, fillPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OpenCbFileShareIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _CompactSidebarDestination extends StatelessWidget {
  const _CompactSidebarDestination({
    required this.icon,
    required this.selectedIcon,
    required this.section,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String section;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Tooltip(
        message: label,
        child: Material(
          color: selected ? colorScheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            mouseCursor: SystemMouseCursors.click,
            hoverColor: colorScheme.secondaryContainer.withValues(alpha: 0.42),
            splashColor: colorScheme.secondaryContainer.withValues(alpha: 0.50),
            highlightColor: colorScheme.secondaryContainer.withValues(
              alpha: 0.34,
            ),
            child: SizedBox(
              width: 56,
              height: 44,
              child: Center(
                child: _OpenCbMenuIcon(
                  section: section,
                  icon: selected ? selectedIcon : icon,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.section,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onClearUnpinned,
    required this.onOpenReceivedFolder,
  });

  final String section;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearUnpinned;
  final VoidCallback onOpenReceivedFolder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isClipboardSection =
        section != 'Thiết bị' && section != 'Gửi file' && section != 'Cài đặt';
    final title = switch (section) {
      'Thiết bị' => l10n.devicesLan,
      'Gửi file' => l10n.navSendFiles,
      'Cài đặt' => l10n.navSettings,
      _ => l10n.clipboard,
    };
    final subtitle = switch (section) {
      'Thiết bị' => '',
      'Gửi file' => '',
      'Cài đặt' => '',
      _ => l10n.quickClipboardSearch,
    };
    return SizedBox(
      height: isClipboardSection ? 64 : 76,
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: isClipboardSection ? 10 : 14,
          ),
          child: Row(
            children: [
              Expanded(
                child: isClipboardSection
                    ? SizedBox(
                        height: 42,
                        child: TextField(
                          controller: searchController,
                          focusNode: searchFocusNode,
                          mouseCursor: SystemMouseCursors.click,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: l10n.search,
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            prefixIcon: const Icon(Icons.search, size: 20),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHigh,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(21),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(21),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(21),
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                          onChanged: onSearchChanged,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                        ],
                      ),
              ),
              if (isClipboardSection) ...[
                const SizedBox(width: 12),
                Tooltip(
                  message: context.l10n.cleanClipboardTitle,
                  child: IconButton.outlined(
                    onPressed: onClearUnpinned,
                    icon: const Icon(Icons.clear_all),
                  ),
                ),
              ] else if (section == 'Gửi file') ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onOpenReceivedFolder,
                  icon: const Icon(Icons.folder_open),
                  label: Text(context.l10n.openFolder),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarLanSyncControls extends StatefulWidget {
  const _SidebarLanSyncControls({
    required this.enabled,
    required this.syncing,
    required this.onToggle,
    required this.onSyncAll,
    this.compact = false,
  });

  final bool enabled;
  final bool syncing;
  final ValueChanged<bool> onToggle;
  final FutureOr<void> Function() onSyncAll;
  final bool compact;

  @override
  State<_SidebarLanSyncControls> createState() =>
      _SidebarLanSyncControlsState();
}

class _SidebarLanSyncControlsState extends State<_SidebarLanSyncControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _syncAnimation;
  bool _manualSyncing = false;

  bool get _isSyncing => widget.syncing || _manualSyncing;

  @override
  void initState() {
    super.initState();
    _syncAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    if (_isSyncing) _syncAnimation.repeat();
  }

  @override
  void didUpdateWidget(covariant _SidebarLanSyncControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateSyncAnimation();
  }

  @override
  void dispose() {
    _syncAnimation.dispose();
    super.dispose();
  }

  void _updateSyncAnimation() {
    if (_isSyncing) {
      if (!_syncAnimation.isAnimating) _syncAnimation.repeat();
    } else if (_syncAnimation.isAnimating) {
      _syncAnimation.stop();
      _syncAnimation.value = 0;
    }
  }

  Future<void> _syncNow() async {
    if (!widget.enabled || _manualSyncing) return;
    setState(() => _manualSyncing = true);
    _updateSyncAnimation();
    try {
      await Future.wait([
        Future<void>.sync(widget.onSyncAll),
        Future<void>.delayed(const Duration(milliseconds: 760)),
      ]);
    } finally {
      if (mounted) {
        setState(() => _manualSyncing = false);
        _updateSyncAnimation();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (widget.compact) {
      return Center(
        child: Tooltip(
          message: widget.enabled
              ? 'Sync tất cả thiết bị LAN'
              : 'Sync LAN đang tắt',
          child: IconButton.filledTonal(
            onPressed: widget.enabled && !_isSyncing ? _syncNow : null,
            icon: RotationTransition(
              turns: _syncAnimation,
              child: const Icon(Icons.sync, size: 18),
            ),
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              Icons.lan_outlined,
              size: 17,
              color: widget.enabled
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Sync',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: widget.enabled
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 44,
              height: 28,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Switch(
                  value: widget.enabled,
                  onChanged: widget.onToggle,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Sync tất cả thiết bị LAN',
              child: IconButton.filledTonal(
                onPressed: widget.enabled && !_isSyncing ? _syncNow : null,
                icon: RotationTransition(
                  turns: _syncAnimation,
                  child: const Icon(Icons.sync, size: 18),
                ),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenCbLogoMark extends StatelessWidget {
  const _OpenCbLogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Logo OpenCB',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _OpenCbLogoPainter(colorScheme: colorScheme),
        ),
      ),
    );
  }
}

class _OpenCbLogoPainter extends CustomPainter {
  const _OpenCbLogoPainter({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 512;
    canvas.save();
    canvas.scale(scale);

    final background = Paint()..color = colorScheme.primary;
    final paper = Paint()..color = colorScheme.primaryContainer;
    final clip = Paint()..color = colorScheme.tertiaryContainer;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 512, 512),
        const Radius.circular(128),
      ),
      background,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(126, 132, 260, 264),
        const Radius.circular(40),
      ),
      paper,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(180, 100, 152, 74),
        const Radius.circular(24),
      ),
      clip,
    );

    final paperClip = Path()
      ..moveTo(720, -330)
      ..quadraticBezierTo(720, -226, 647, -153)
      ..quadraticBezierTo(574, -80, 470, -80)
      ..quadraticBezierTo(366, -80, 293, -153)
      ..quadraticBezierTo(220, -226, 220, -330)
      ..lineTo(220, -700)
      ..quadraticBezierTo(220, -775, 272.5, -827.5)
      ..quadraticBezierTo(325, -880, 400, -880)
      ..quadraticBezierTo(475, -880, 527.5, -827.5)
      ..quadraticBezierTo(580, -775, 580, -700)
      ..lineTo(580, -350)
      ..quadraticBezierTo(580, -304, 548, -272)
      ..quadraticBezierTo(516, -240, 470, -240)
      ..quadraticBezierTo(424, -240, 392, -272)
      ..quadraticBezierTo(360, -304, 360, -350)
      ..lineTo(360, -720)
      ..lineTo(440, -720)
      ..lineTo(440, -350)
      ..quadraticBezierTo(440, -337, 448.5, -328.5)
      ..quadraticBezierTo(457, -320, 470, -320)
      ..quadraticBezierTo(483, -320, 491.5, -328.5)
      ..quadraticBezierTo(500, -337, 500, -350)
      ..lineTo(500, -700)
      ..quadraticBezierTo(499, -742, 470.5, -771)
      ..quadraticBezierTo(442, -800, 400, -800)
      ..quadraticBezierTo(358, -800, 329, -771)
      ..quadraticBezierTo(300, -742, 300, -700)
      ..lineTo(300, -330)
      ..quadraticBezierTo(299, -259, 349, -209.5)
      ..quadraticBezierTo(399, -160, 470, -160)
      ..quadraticBezierTo(540, -160, 589, -209.5)
      ..quadraticBezierTo(638, -260, 640, -330)
      ..lineTo(640, -720)
      ..lineTo(720, -720)
      ..lineTo(720, -330)
      ..close();
    canvas.save();
    canvas.translate(256, 260);
    canvas.rotate(-45 * math.pi / 180);
    canvas.translate(-256, -260);
    canvas.translate(152.6, 375.6);
    canvas.scale(0.22);
    canvas.drawPath(paperClip, Paint()..color = colorScheme.onPrimaryContainer);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OpenCbLogoPainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme;
  }
}

class _QuickPickerShell extends StatefulWidget {
  const _QuickPickerShell({
    required this.entries,
    required this.tagDefinitions,
    required this.promotedEntryId,
    required this.promotionToken,
    required this.onSelected,
    required this.onTogglePin,
    required this.onOpenItem,
    required this.onDeleteItem,
    required this.onOpenMainApp,
    required this.onClose,
  });

  final List<ClipboardEntry> entries;
  final Map<String, TagDefinition> tagDefinitions;
  final String? promotedEntryId;
  final int promotionToken;
  final Future<void> Function(ClipboardEntry entry, {required bool keepOpen})
  onSelected;
  final Future<void> Function(ClipboardEntry entry) onTogglePin;
  final Future<void> Function(ClipboardEntry entry) onOpenItem;
  final Future<void> Function(ClipboardEntry entry) onDeleteItem;
  final Future<void> Function() onOpenMainApp;
  final Future<void> Function() onClose;

  @override
  State<_QuickPickerShell> createState() => _QuickPickerShellState();
}

class _QuickPickerShellState extends State<_QuickPickerShell> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  final Map<String, bool> _pinOverrides = {};
  final Set<String> _selectedTagFilters = {};
  ClipboardKind? _selectedKindFilter;
  String? _quickPickerPromotedEntryId;
  int _quickPickerPromotionToken = 0;
  String? _expandedImageEntryId;
  int _selectedIndex = 0;
  bool _pinned = false;
  bool _showPinnedOnly = false;
  bool _searchExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    unawaited(_setQuickPickerAlwaysOnTop(false));
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _QuickPickerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.promotionToken == oldWidget.promotionToken) return;
    if (!_pinned) return;
    final promotedId = widget.promotedEntryId;
    if (promotedId == null) return;
    _quickPickerPromotedEntryId = promotedId;
    _quickPickerPromotionToken = widget.promotionToken;
    final promotedIndex = _filteredEntries.indexWhere(
      (entry) => entry.id == promotedId,
    );
    if (promotedIndex >= 0) {
      _selectedIndex = promotedIndex;
    }
  }

  Future<void> _setQuickPickerAlwaysOnTop(bool enabled) async {
    if (!Platform.isWindows) return;
    try {
      await _ClipboardHomePageState._windowsClipboardChannel.invokeMethod<void>(
        'setQuickPickerAlwaysOnTop',
        {'enabled': enabled},
      );
    } catch (_) {}
  }

  void _toggleWindowPinned() {
    final nextPinned = !_pinned;
    setState(() => _pinned = nextPinned);
    unawaited(_setQuickPickerAlwaysOnTop(nextPinned));
  }

  void _openSearchField() {
    setState(() => _searchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _clearAndCollapseSearch() {
    setState(() {
      _controller.clear();
      _selectedIndex = 0;
      _searchExpanded = false;
    });
    _focusNode.unfocus();
  }

  List<ClipboardEntry> get _filteredEntries {
    Iterable<ClipboardEntry> entries =
        _filterQuickPickerEntries(widget.entries, _controller.text).map(
          (entry) =>
              entry.copyWith(pinned: _pinOverrides[entry.id] ?? entry.pinned),
        );
    if (_showPinnedOnly) {
      entries = entries.where((entry) => entry.pinned);
    }
    if (_selectedKindFilter != null) {
      entries = entries.where((entry) => entry.kind == _selectedKindFilter);
    }
    if (_selectedTagFilters.isNotEmpty) {
      entries = entries.where(
        (entry) => entry.tags.any(_selectedTagFilters.contains),
      );
    }
    return entries.take(100).toList();
  }

  List<String> get _availableTags => _availableEntryTags(widget.entries);

  String get _emptyMessage {
    final hasQuery = _controller.text.trim().isNotEmpty;
    if (_selectedTagFilters.isNotEmpty && hasQuery) {
      return context.l10n.noMatchingSelectedTags;
    }
    if (_selectedTagFilters.isNotEmpty) {
      return context.l10n.noItemsInSelectedTags;
    }
    if (_showPinnedOnly && hasQuery) {
      return context.l10n.noMatchingPinned;
    }
    if (_showPinnedOnly) {
      return context.l10n.noPinnedItems;
    }
    return context.l10n.noMatchingClipboard;
  }

  void _toggleTagFilter(String tag) {
    setState(() {
      if (!_selectedTagFilters.add(tag)) {
        _selectedTagFilters.remove(tag);
      }
      _selectedIndex = 0;
    });
  }

  void _setKindFilter(ClipboardKind? kind) {
    setState(() {
      _selectedKindFilter = kind;
      _selectedIndex = 0;
    });
  }

  Future<void> _toggleEntryPin(ClipboardEntry entry) async {
    final pinned = !entry.pinned;
    await widget.onTogglePin(entry);
    if (!mounted) return;
    setState(() {
      _pinOverrides[entry.id] = pinned;
      final entries = _filteredEntries;
      if (entries.isEmpty) {
        _selectedIndex = 0;
      } else {
        _selectedIndex = _selectedIndex.clamp(0, entries.length - 1);
      }
    });
  }

  void _selectFirstVisible() {
    final entries = _filteredEntries;
    if (entries.isEmpty) return;
    final index = _selectedIndex.clamp(0, entries.length - 1);
    unawaited(widget.onSelected(entries[index], keepOpen: _pinned));
  }

  void _moveSelection(int delta) {
    final entries = _filteredEntries;
    if (entries.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, entries.length - 1);
    });
    _scrollSelectedIntoView();
  }

  void _scrollSelectedIntoView() {
    if (!_scrollController.hasClients) return;
    const itemExtent = 78.0;
    final viewport = _scrollController.position.viewportDimension;
    final minVisible = _scrollController.offset;
    final maxVisible = minVisible + viewport - itemExtent;
    final target = _selectedIndex * itemExtent;
    if (target < minVisible) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    } else if (target > maxVisible) {
      _scrollController.animateTo(
        target - viewport + itemExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      final entries = _filteredEntries;
      if (entries.isNotEmpty) {
        setState(() => _selectedIndex = 0);
        _scrollSelectedIntoView();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      final entries = _filteredEntries;
      if (entries.isNotEmpty) {
        setState(() => _selectedIndex = entries.length - 1);
        _scrollSelectedIntoView();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _selectFirstVisible();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(widget.onClose());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final entries = _filteredEntries;
    final availableTags = _availableTags;
    ButtonStyle quickPickerToolButtonStyle({bool active = false}) =>
        IconButton.styleFrom(
          backgroundColor: active
              ? colorScheme.secondary
              : colorScheme.surfaceContainerHighest,
          foregroundColor: active
              ? colorScheme.onSecondary
              : colorScheme.onSurfaceVariant,
          fixedSize: const Size.square(36),
          maximumSize: const Size.square(36),
          minimumSize: const Size.square(36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: _searchExpanded ? 108 : 36,
                    child: _searchExpanded
                        ? Focus(
                            onKeyEvent: _handleKey,
                            child: SizedBox(
                              height: 36,
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                mouseCursor: SystemMouseCursors.click,
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: l10n.search,
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.auto,
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 18,
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: l10n.clearSearch,
                                    onPressed: _clearAndCollapseSearch,
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 34,
                                  ),
                                  suffixIconConstraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color: colorScheme.outlineVariant,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color: colorScheme.primary,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                onChanged: (_) =>
                                    setState(() => _selectedIndex = 0),
                                onSubmitted: (_) => _selectFirstVisible(),
                              ),
                            ),
                          )
                        : Tooltip(
                            message: l10n.search,
                            child: IconButton(
                              style: quickPickerToolButtonStyle(),
                              onPressed: _openSearchField,
                              icon: const Icon(Icons.search, size: 20),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: _ConnectedButtonGroup(
                        expanded: true,
                        height: 34,
                        iconSize: 17,
                        gap: 2,
                        iconOnlyHorizontalPadding: 0,
                        segments: [
                          _ConnectedButtonSegment(
                            label: l10n.allItems,
                            icon: Icons.all_inclusive,
                            selected: _selectedKindFilter == null,
                            iconOnly: true,
                            onPressed: () => _setKindFilter(null),
                          ),
                          for (final kind in ClipboardKind.values)
                            _ConnectedButtonSegment(
                              label: _quickPickerKindLabel(context.l10n, kind),
                              icon: _kindIcon(kind),
                              selected: _selectedKindFilter == kind,
                              iconOnly: true,
                              onPressed: () => _setKindFilter(kind),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _pinned
                        ? l10n.quickPickerPinned
                        : l10n.pinQuickPicker,
                    child: IconButton(
                      style: quickPickerToolButtonStyle(active: _pinned),
                      onPressed: _toggleWindowPinned,
                      icon: Icon(
                        _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: l10n.close,
                    child: IconButton(
                      style: quickPickerToolButtonStyle(),
                      onPressed: () => unawaited(widget.onClose()),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (availableTags.isNotEmpty)
                    Expanded(
                      child: _QuickPickerTagFilterBar(
                        tags: availableTags,
                        tagDefinitions: widget.tagDefinitions,
                        selectedTags: _selectedTagFilters,
                        onClear: () => setState(() {
                          _selectedTagFilters.clear();
                          _selectedIndex = 0;
                        }),
                        onToggle: _toggleTagFilter,
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _showPinnedOnly
                        ? l10n.showAllClipboards
                        : l10n.showPinnedOnly,
                    child: IconButton(
                      style: quickPickerToolButtonStyle(
                        active: _showPinnedOnly,
                      ),
                      onPressed: () => setState(() {
                        _showPinnedOnly = !_showPinnedOnly;
                        _selectedIndex = 0;
                      }),
                      icon: Icon(
                        _showPinnedOnly
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: l10n.openMainApp,
                    child: IconButton(
                      style: quickPickerToolButtonStyle(),
                      onPressed: () => unawaited(widget.onOpenMainApp()),
                      icon: const Icon(Icons.open_in_new, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          _emptyMessage,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      )
                    : _AnimatedClipboardEntryList(
                        controller: _scrollController,
                        entries: entries,
                        promotedEntryId: _quickPickerPromotedEntryId,
                        promotionToken: _quickPickerPromotionToken,
                        itemSpacing: 5,
                        itemBuilder: (context, entry, index) {
                          return _QuickPickerRow(
                            entry: entry,
                            tagDefinitions: widget.tagDefinitions,
                            selected: index == _selectedIndex,
                            imageExpanded: _expandedImageEntryId == entry.id,
                            onTogglePin: () => _toggleEntryPin(entry),
                            onToggleImagePreview: () => setState(() {
                              _expandedImageEntryId =
                                  _expandedImageEntryId == entry.id
                                  ? null
                                  : entry.id;
                            }),
                            onSelected: () => unawaited(
                              widget.onSelected(entry, keepOpen: _pinned),
                            ),
                            onOpenItem: () =>
                                unawaited(widget.onOpenItem(entry)),
                            onDelete: () =>
                                unawaited(widget.onDeleteItem(entry)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPickerTagFilterBar extends StatefulWidget {
  const _QuickPickerTagFilterBar({
    required this.tags,
    required this.tagDefinitions,
    required this.selectedTags,
    required this.onClear,
    required this.onToggle,
  });

  final List<String> tags;
  final Map<String, TagDefinition> tagDefinitions;
  final Set<String> selectedTags;
  final VoidCallback onClear;
  final ValueChanged<String> onToggle;

  @override
  State<_QuickPickerTagFilterBar> createState() =>
      _QuickPickerTagFilterBarState();
}

class _QuickPickerTagFilterBarState extends State<_QuickPickerTagFilterBar> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    _scrollController.jumpTo(target.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scrollBehavior = ScrollConfiguration.of(context).copyWith(
      scrollbars: false,
      dragDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      },
    );
    return SizedBox(
      height: 34,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: ScrollConfiguration(
          behavior: scrollBehavior,
          child: ListView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            children: [
              _ConnectedButtonGroup(
                height: 34,
                iconSize: 17,
                gap: 2,
                iconOnlyHorizontalPadding: 11,
                labelHorizontalPadding: 9,
                segments: [
                  _ConnectedButtonSegment(
                    label: context.l10n.allItems,
                    icon: Icons.all_inclusive,
                    selected: widget.selectedTags.isEmpty,
                    iconOnly: true,
                    onPressed: widget.onClear,
                  ),
                  for (final tag in widget.tags)
                    _ConnectedButtonSegment(
                      label: tag,
                      icon: widget.selectedTags.contains(tag)
                          ? Icons.check
                          : widget.tagDefinitions[tag]?.icon ??
                                Icons.sell_outlined,
                      selected: widget.selectedTags.contains(tag),
                      iconColor:
                          widget.tagDefinitions[tag]?.color ??
                          colorScheme.tertiary,
                      maxLabelWidth: 86,
                      onPressed: () => widget.onToggle(tag),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPickerRow extends StatelessWidget {
  const _QuickPickerRow({
    required this.entry,
    required this.tagDefinitions,
    required this.selected,
    required this.imageExpanded,
    required this.onTogglePin,
    required this.onToggleImagePreview,
    required this.onSelected,
    required this.onOpenItem,
    required this.onDelete,
  });

  final ClipboardEntry entry;
  final Map<String, TagDefinition> tagDefinitions;
  final bool selected;
  final bool imageExpanded;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleImagePreview;
  final VoidCallback onSelected;
  final VoidCallback onOpenItem;
  final VoidCallback onDelete;
  static OverlayEntry? _openContextMenuEntry;

  static void _closeOpenContextMenu() {
    _openContextMenuEntry?.remove();
    _openContextMenuEntry = null;
  }

  void _showContextMenu(BuildContext context, Offset position) {
    _closeOpenContextMenu();
    const menuWidth = 168.0;
    void closeMenu() {
      _closeOpenContextMenu();
    }

    void runAction(VoidCallback action) {
      closeMenu();
      action();
    }

    _openContextMenuEntry = OverlayEntry(
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final left = math
            .min(position.dx, math.max(8, size.width - menuWidth - 8))
            .clamp(8.0, math.max(8.0, size.width - menuWidth - 8));
        final top = math
            .min(position.dy, math.max(8, size.height - 224))
            .clamp(8.0, math.max(8.0, size.height - 8));
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: closeMenu,
              ),
            ),
            Positioned(
              left: left.toDouble(),
              top: top.toDouble(),
              child: SizedBox(
                width: menuWidth,
                child: _QuickPickerContextMenu(
                  entry: entry,
                  onCopy: () => runAction(onSelected),
                  onOpenItem: () => runAction(onOpenItem),
                  onDelete: () => runAction(onDelete),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_openContextMenuEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(12);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      decoration: ShapeDecoration(
        color: selected
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: GestureDetector(
          onSecondaryTapDown: (details) =>
              _showContextMenu(context, details.globalPosition),
          onLongPressStart: (details) =>
              _showContextMenu(context, details.globalPosition),
          child: InkWell(
            borderRadius: borderRadius,
            mouseCursor: SystemMouseCursors.click,
            onTap: () {
              _closeOpenContextMenu();
              onSelected();
            },
            child: Padding(
              padding: EdgeInsets.fromLTRB(selected ? 7 : 10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: selected ? 4 : 0,
                        height: 46,
                        decoration: ShapeDecoration(
                          color: colorScheme.primary,
                          shape: const StadiumBorder(),
                        ),
                      ),
                      if (selected) const SizedBox(width: 8),
                      Icon(
                        _kindIcon(entry.kind),
                        size: 17,
                        color: selected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: selected
                                              ? colorScheme.onSecondaryContainer
                                              : colorScheme.onSurface,
                                          fontWeight: FontWeight.w800,
                                          height: 1.08,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (_shouldShowSourceIcon(entry)) ...[
                                  _SourceAppIcon(entry: entry, dimension: 16),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(
                                    '${_quickPickerMetaKindLabel(context.l10n, entry.kind)} - ${_displaySourceLabel(entry.source)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: selected
                                              ? colorScheme.onSecondaryContainer
                                              : colorScheme.onSurfaceVariant,
                                          fontSize: 11.5,
                                          height: 1.05,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _MiniChip(
                                  label: entry.createdLabel,
                                  timeTone: true,
                                ),
                              ],
                            ),
                            if (entry.tags.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final tag in entry.tags.take(3))
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 110,
                                      ),
                                      child: _TagBadge(
                                        label: tag,
                                        definition: tagDefinitions[tag],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (entry.kind == ClipboardKind.image &&
                          entry.imageBytes != null &&
                          entry.imageBytes!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: imageExpanded
                              ? context.l10n.collapsePreview
                              : context.l10n.expandPreview,
                          child: GestureDetector(
                            onTap: onToggleImagePreview,
                            child: _QuickPickerImageThumb(
                              imageBytes: entry.imageBytes!,
                              expanded: imageExpanded,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
                      Tooltip(
                        message: entry.pinned
                            ? context.l10n.unpinThisItem
                            : context.l10n.pinThisItem,
                        child: SizedBox.square(
                          dimension: 32,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              alignment: Alignment.center,
                              fixedSize: const Size.square(32),
                              maximumSize: const Size.square(32),
                              minimumSize: const Size.square(32),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: entry.pinned
                                  ? colorScheme.tertiaryContainer
                                  : Colors.transparent,
                              foregroundColor: entry.pinned
                                  ? colorScheme.onTertiaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                            onPressed: onTogglePin,
                            iconSize: 17,
                            icon: Icon(
                              entry.pinned
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child:
                        imageExpanded &&
                            entry.kind == ClipboardKind.image &&
                            entry.imageBytes != null &&
                            entry.imageBytes!.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _QuickPickerExpandedImagePreview(
                              imageBytes: entry.imageBytes!,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickPickerExpandedImagePreview extends StatelessWidget {
  const _QuickPickerExpandedImagePreview({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 270,
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.broken_image_outlined,
                size: 28,
                color: colorScheme.onSurfaceVariant,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _QuickPickerImageThumb extends StatelessWidget {
  const _QuickPickerImageThumb({
    required this.imageBytes,
    this.expanded = false,
  });

  final Uint8List imageBytes;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: expanded
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.72),
            width: expanded ? 2 : 1,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 46,
          height: 46,
          color: colorScheme.surfaceContainerHighest,
          child: Image.memory(
            imageBytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.broken_image_outlined,
                size: 22,
                color: colorScheme.onSurfaceVariant,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _QuickPickerContextMenu extends StatelessWidget {
  const _QuickPickerContextMenu({
    required this.entry,
    required this.onCopy,
    required this.onOpenItem,
    required this.onDelete,
  });

  final ClipboardEntry entry;
  final VoidCallback onCopy;
  final VoidCallback onOpenItem;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final openLabel = switch (entry.kind) {
      ClipboardKind.url => l10n.openUrl,
      ClipboardKind.fileReference => l10n.openFolder,
      _ => null,
    };
    final openIcon = switch (entry.kind) {
      ClipboardKind.url => Icons.open_in_browser,
      ClipboardKind.fileReference => Icons.folder_open_outlined,
      _ => Icons.open_in_new,
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset((1 - value) * -4, (1 - value) * -4),
            child: Transform.scale(
              scale: 0.96 + value * 0.04,
              alignment: Alignment.topLeft,
              child: child,
            ),
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ExpressiveFabMenuAction(
              icon: Icons.copy,
              label: l10n.copy,
              successLabel: l10n.copied,
              actionDelay: const Duration(milliseconds: 220),
              onPressed: onCopy,
            ),
            if (openLabel != null) ...[
              const SizedBox(height: 8),
              _ExpressiveFabMenuAction(
                icon: openIcon,
                label: openLabel,
                onPressed: onOpenItem,
              ),
            ],
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.delete_outline,
              label: l10n.delete,
              successLabel: l10n.deleted,
              actionDelay: const Duration(milliseconds: 260),
              destructive: true,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

typedef _AnimatedClipboardEntryBuilder =
    Widget Function(BuildContext context, ClipboardEntry entry, int index);

class _AnimatedClipboardEntryList extends StatefulWidget {
  const _AnimatedClipboardEntryList({
    required this.entries,
    required this.promotedEntryId,
    required this.promotionToken,
    required this.itemBuilder,
    this.controller,
    this.padding,
    this.itemSpacing = 0,
  });

  final List<ClipboardEntry> entries;
  final String? promotedEntryId;
  final int promotionToken;
  final _AnimatedClipboardEntryBuilder itemBuilder;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final double itemSpacing;

  @override
  State<_AnimatedClipboardEntryList> createState() =>
      _AnimatedClipboardEntryListState();
}

class _AnimatedClipboardEntryListState
    extends State<_AnimatedClipboardEntryList> {
  late List<ClipboardEntry> _items;
  late final ScrollController _ownedController;
  GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  ScrollController get _scrollController =>
      widget.controller ?? _ownedController;

  @override
  void initState() {
    super.initState();
    _items = List<ClipboardEntry>.from(widget.entries);
    _ownedController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant _AnimatedClipboardEntryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_animatePromotionIfNeeded(oldWidget)) return;
    if (_sameEntryOrder(_items, widget.entries)) {
      _items = List<ClipboardEntry>.from(widget.entries);
      return;
    }
    _resetList(widget.entries);
  }

  @override
  void dispose() {
    _ownedController.dispose();
    super.dispose();
  }

  bool _animatePromotionIfNeeded(_AnimatedClipboardEntryList oldWidget) {
    if (widget.promotionToken == oldWidget.promotionToken) return false;
    final promotedId = widget.promotedEntryId;
    if (promotedId == null) return false;
    final targetIndex = widget.entries.indexWhere(
      (entry) => entry.id == promotedId,
    );
    final oldIndex = _items.indexWhere((entry) => entry.id == promotedId);
    if (targetIndex != 0 || oldIndex <= 0) {
      _resetList(widget.entries);
      return true;
    }
    if (!_sameEntrySet(_items, widget.entries)) {
      _resetList(widget.entries);
      return true;
    }

    final listState = _listKey.currentState;
    if (listState == null) {
      _items = List<ClipboardEntry>.from(widget.entries);
      return true;
    }

    final removedEntry = _items.removeAt(oldIndex);
    listState.removeItem(
      oldIndex,
      (context, animation) =>
          _buildAnimatedItem(context, removedEntry, oldIndex, animation),
      duration: const Duration(milliseconds: 170),
    );

    _items.insert(0, widget.entries.first);
    listState.insertItem(0, duration: const Duration(milliseconds: 280));
    _refreshVisibleItems(widget.entries);
    _scrollPromotedItemIntoView();
    return true;
  }

  void _resetList(List<ClipboardEntry> entries) {
    _items = List<ClipboardEntry>.from(entries);
    _listKey = GlobalKey<AnimatedListState>();
  }

  void _refreshVisibleItems(List<ClipboardEntry> entries) {
    final byId = {for (final entry in entries) entry.id: entry};
    for (var i = 0; i < _items.length; i++) {
      _items[i] = byId[_items[i].id] ?? _items[i];
    }
  }

  void _scrollPromotedItemIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _sameEntryOrder(
    List<ClipboardEntry> current,
    List<ClipboardEntry> next,
  ) {
    if (current.length != next.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (current[i].id != next[i].id) return false;
    }
    return true;
  }

  bool _sameEntrySet(List<ClipboardEntry> current, List<ClipboardEntry> next) {
    if (current.length != next.length) return false;
    final currentIds = current.map((entry) => entry.id).toSet();
    final nextIds = next.map((entry) => entry.id).toSet();
    return currentIds.length == nextIds.length &&
        currentIds.containsAll(nextIds);
  }

  Widget _buildAnimatedItem(
    BuildContext context,
    ClipboardEntry entry,
    int index,
    Animation<double> animation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SizeTransition(
      sizeFactor: curved,
      // Flutter 3.41 deprecates this in favor of alignment, but the current
      // stable SDK used locally has not exposed the replacement yet.
      // ignore: deprecated_member_use
      axisAlignment: -1,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.10),
            end: Offset.zero,
          ).animate(curved),
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.itemSpacing),
            child: widget.itemBuilder(context, entry, index),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      controller: _scrollController,
      padding: widget.padding,
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) {
        return _buildAnimatedItem(context, _items[index], index, animation);
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.title,
    required this.emptyMessage,
    required this.entries,
    required this.tagDefinitions,
    required this.promotedEntryId,
    required this.promotionToken,
    required this.selectedKind,
    required this.selectedScope,
    required this.selectedScopePosition,
    required this.showScopeFilter,
    required this.bulkSelectMode,
    required this.bulkSelectedIds,
    required this.selectedIndex,
    required this.loaded,
    this.compact = false,
    this.bottomContentPadding = 12,
    required this.onKindSelected,
    required this.onScopeSelected,
    required this.onCopy,
    required this.onTogglePin,
    required this.onEditTags,
    required this.onDelete,
    required this.onToggleBulkSelectMode,
    required this.onToggleBulkSelected,
    required this.onSelectAllBulkVisible,
    required this.onSetBulkPinned,
    required this.onAddBulkTags,
    required this.onDeleteBulkSelected,
    required this.onClearUnpinned,
    this.onManageTags,
    this.hideHeaderActions = false,
    this.headerReplacement,
    required this.onSelected,
    required this.onContextSelected,
  });

  final String title;
  final String emptyMessage;
  final List<ClipboardEntry> entries;
  final Map<String, TagDefinition> tagDefinitions;
  final String? promotedEntryId;
  final int promotionToken;
  final ClipboardKind? selectedKind;
  final _HistoryScopeFilter selectedScope;
  final double selectedScopePosition;
  final bool showScopeFilter;
  final bool bulkSelectMode;
  final Set<String> bulkSelectedIds;
  final int selectedIndex;
  final bool loaded;
  final bool compact;
  final double bottomContentPadding;
  final ValueChanged<ClipboardKind?> onKindSelected;
  final ValueChanged<_HistoryScopeFilter> onScopeSelected;
  final ValueChanged<ClipboardEntry> onCopy;
  final ValueChanged<ClipboardEntry> onTogglePin;
  final ValueChanged<ClipboardEntry> onEditTags;
  final ValueChanged<ClipboardEntry> onDelete;
  final VoidCallback onToggleBulkSelectMode;
  final ValueChanged<ClipboardEntry> onToggleBulkSelected;
  final VoidCallback onSelectAllBulkVisible;
  final ValueChanged<bool> onSetBulkPinned;
  final VoidCallback onAddBulkTags;
  final VoidCallback onDeleteBulkSelected;
  final VoidCallback onClearUnpinned;
  final VoidCallback? onManageTags;
  final bool hideHeaderActions;
  final Widget? headerReplacement;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onContextSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final allVisibleSelected =
        entries.isNotEmpty &&
        entries.every((entry) => bulkSelectedIds.contains(entry.id));
    final isTagSection = onManageTags != null;
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          SizedBox(
            height: compact ? 64 : 76,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 20,
                vertical: compact ? 10 : 14,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [...previousChildren, ?currentChild],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -0.08),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child:
                          headerReplacement ??
                          Text(
                            title,
                            key: ValueKey('title-$title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                    ),
                  ),
                  if (!hideHeaderActions) const SizedBox(width: 10),
                  if (!hideHeaderActions && bulkSelectMode) ...[
                    if (!compact) ...[
                      Text(
                        '${bulkSelectedIds.length} ${l10n.selected}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Tooltip(
                      message: allVisibleSelected
                          ? l10n.deselectVisible
                          : l10n.selectVisible,
                      child: IconButton(
                        onPressed: entries.isEmpty
                            ? null
                            : onSelectAllBulkVisible,
                        icon: Icon(
                          allVisibleSelected
                              ? Icons.deselect_outlined
                              : Icons.select_all,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _BulkActionsFabMenu(
                      enabled: bulkSelectedIds.isNotEmpty,
                      onPin: () => onSetBulkPinned(true),
                      onUnpin: () => onSetBulkPinned(false),
                      onTags: onAddBulkTags,
                      onDelete: onDeleteBulkSelected,
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: l10n.exitBulkSelect,
                      child: IconButton(
                        onPressed: onToggleBulkSelectMode,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ] else if (!hideHeaderActions) ...[
                    if (isTagSection) ...[
                      Tooltip(
                        message: l10n.createTag,
                        child: compact
                            ? IconButton.filledTonal(
                                onPressed: onManageTags,
                                icon: const Icon(Icons.add),
                              )
                            : FilledButton.tonalIcon(
                                onPressed: onManageTags,
                                icon: const Icon(Icons.add),
                                label: _ButtonLabel(l10n.createTag),
                              ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (!compact) ...[
                      Text(
                        _localizedItemCount(l10n, entries.length),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Tooltip(
                      message: l10n.selectMultiple,
                      child: IconButton(
                        onPressed: entries.isEmpty
                            ? null
                            : onToggleBulkSelectMode,
                        icon: const Icon(Icons.checklist_outlined),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: l10n.cleanClipboardTitle,
                      child: IconButton(
                        onPressed: onClearUnpinned,
                        icon: const Icon(Icons.clear_all),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _HistoryFilterBar(
            selectedKind: selectedKind,
            selectedScope: selectedScope,
            selectedScopePosition: selectedScopePosition,
            showScopeFilter: showScopeFilter,
            compact: compact,
            onKindSelected: onKindSelected,
            onScopeSelected: onScopeSelected,
          ),
          Expanded(
            child: !loaded
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                ? _EmptyHistory(
                    message: emptyMessage,
                    actionLabel: isTagSection ? l10n.createTag : null,
                    actionIcon: isTagSection ? Icons.add : null,
                    onAction: onManageTags,
                  )
                : _ScrollToTopHistoryBody(
                    bottomContentPadding: bottomContentPadding,
                    builder: (scrollController) => _AnimatedClipboardEntryList(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(
                        12,
                        0,
                        12,
                        bottomContentPadding,
                      ),
                      entries: entries,
                      promotedEntryId: promotedEntryId,
                      promotionToken: promotionToken,
                      itemBuilder: (context, entry, index) {
                        return _ClipboardTile(
                          entry: entry,
                          tagDefinitions: tagDefinitions,
                          selected: index == selectedIndex,
                          bulkSelectMode: bulkSelectMode,
                          bulkSelected: bulkSelectedIds.contains(entry.id),
                          onTap: bulkSelectMode
                              ? () => onToggleBulkSelected(entry)
                              : () => onSelected(index),
                          onToggleBulkSelected: () =>
                              onToggleBulkSelected(entry),
                          onContextMenuOpened: () => onContextSelected(index),
                          onCopy: () => onCopy(entry),
                          onTogglePin: () => onTogglePin(entry),
                          onEditTags: () => onEditTags(entry),
                          onDelete: () => onDelete(entry),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScrollToTopHistoryBody extends StatefulWidget {
  const _ScrollToTopHistoryBody({
    required this.builder,
    required this.bottomContentPadding,
  });

  final Widget Function(ScrollController scrollController) builder;
  final double bottomContentPadding;

  @override
  State<_ScrollToTopHistoryBody> createState() =>
      _ScrollToTopHistoryBodyState();
}

class _ScrollToTopHistoryBodyState extends State<_ScrollToTopHistoryBody> {
  late final ScrollController _controller;
  bool _showButton = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_handleScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    final nextVisible = _controller.hasClients && _controller.offset > 260;
    if (nextVisible == _showButton) return;
    setState(() => _showButton = nextVisible);
  }

  void _scrollToTop() {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMobileBody = widget.bottomContentPadding > 48;
    final bottomOffset = isMobileBody ? widget.bottomContentPadding - 8 : 18.0;
    return Stack(
      children: [
        Positioned.fill(child: widget.builder(_controller)),
        Positioned(
          right: 18,
          bottom: bottomOffset,
          child: IgnorePointer(
            ignoring: !_showButton,
            child: AnimatedOpacity(
              opacity: _showButton ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: AnimatedScale(
                scale: _showButton ? 1 : 0.88,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: FloatingActionButton(
                    heroTag: null,
                    tooltip: context.l10n.scrollToTop,
                    mini: true,
                    mouseCursor: SystemMouseCursors.click,
                    elevation: 3,
                    highlightElevation: 4,
                    backgroundColor: colorScheme.surfaceContainerHigh,
                    foregroundColor: colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onPressed: _scrollToTop,
                    child: const Icon(Icons.keyboard_arrow_up),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BulkActionsFabMenu extends StatefulWidget {
  const _BulkActionsFabMenu({
    required this.enabled,
    required this.onPin,
    required this.onUnpin,
    required this.onTags,
    required this.onDelete,
  });

  final bool enabled;
  final VoidCallback onPin;
  final VoidCallback onUnpin;
  final VoidCallback onTags;
  final VoidCallback onDelete;

  @override
  State<_BulkActionsFabMenu> createState() => _BulkActionsFabMenuState();
}

class _BulkActionsFabMenuState extends State<_BulkActionsFabMenu> {
  bool _menuOpen = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void didUpdateWidget(covariant _BulkActionsFabMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _hideMenu();
  }

  @override
  void dispose() {
    _hideMenu(updateState: false);
    super.dispose();
  }

  void _runAction(VoidCallback action) {
    _hideMenu();
    action();
  }

  void _showMenu() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            showWhenUnlinked: false,
            child: _ExpressiveBulkActionMenu(
              onPin: () => _runAction(widget.onPin),
              onUnpin: () => _runAction(widget.onUnpin),
              onTags: () => _runAction(widget.onTags),
              onDelete: () => _runAction(widget.onDelete),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_overlayEntry!);
    if (mounted) setState(() => _menuOpen = true);
  }

  void _hideMenu({bool updateState = true}) {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (updateState && mounted) setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeContainer = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.18),
      colorScheme.surfaceContainerHigh,
    );
    final openContainer = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.30),
      colorScheme.surfaceContainerHighest,
    );
    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: widget.enabled
            ? context.l10n.selectedItemsAction
            : context.l10n.noSelectedItems,
        child: FloatingActionButton.small(
          heroTag: null,
          elevation: _menuOpen ? 4 : 2,
          backgroundColor: _menuOpen
              ? openContainer
              : widget.enabled
              ? activeContainer
              : colorScheme.surfaceContainerHighest,
          foregroundColor: _menuOpen
              ? colorScheme.primary
              : widget.enabled
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          onPressed: widget.enabled
              ? () => _menuOpen ? _hideMenu() : _showMenu()
              : null,
          child: AnimatedRotation(
            turns: _menuOpen ? 0.5 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: const Icon(Icons.more_vert),
          ),
        ),
      ),
    );
  }
}

class _ExpressiveBulkActionMenu extends StatelessWidget {
  const _ExpressiveBulkActionMenu({
    required this.onPin,
    required this.onUnpin,
    required this.onTags,
    required this.onDelete,
  });

  final VoidCallback onPin;
  final VoidCallback onUnpin;
  final VoidCallback onTags;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * -6),
            child: Transform.scale(
              scale: 0.96 + value * 0.04,
              alignment: Alignment.topRight,
              child: child,
            ),
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ExpressiveFabMenuAction(
              icon: Icons.bookmark_add_outlined,
              label: l10n.pin,
              onPressed: onPin,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.bookmark_remove_outlined,
              label: l10n.unpin,
              onPressed: onUnpin,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.sell_outlined,
              label: l10n.tagsAction,
              onPressed: onTags,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.delete_outline,
              label: l10n.delete,
              successLabel: l10n.deleted,
              actionDelay: const Duration(milliseconds: 320),
              destructive: true,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpressiveFabMenuAction extends StatefulWidget {
  const _ExpressiveFabMenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.successLabel = 'Xong',
    this.actionDelay = Duration.zero,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final String successLabel;
  final Duration actionDelay;
  final bool destructive;

  @override
  State<_ExpressiveFabMenuAction> createState() =>
      _ExpressiveFabMenuActionState();
}

class _ExpressiveFabMenuActionState extends State<_ExpressiveFabMenuAction> {
  bool _showFeedback = false;
  bool _pressed = false;
  bool _running = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _handlePressed() async {
    if (_running) return;
    _resetTimer?.cancel();
    setState(() {
      _running = true;
      _pressed = true;
      _showFeedback = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (mounted) setState(() => _pressed = false);
    if (widget.actionDelay > Duration.zero) {
      await Future<void>.delayed(widget.actionDelay);
    }
    widget.onPressed();
    if (!mounted) return;
    _resetTimer = Timer(const Duration(milliseconds: 720), () {
      if (!mounted) return;
      setState(() => _showFeedback = false);
      _resetTimer = Timer(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        setState(() => _running = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showingFeedback = _showFeedback;
    final successLabel = widget.successLabel == 'Xong'
        ? context.l10n.done
        : widget.successLabel;
    final containerColor = colorScheme.secondaryContainer;
    final contentColor = colorScheme.onSecondaryContainer;
    return AnimatedScale(
      scale: _pressed ? 0.94 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: ShapeDecoration(
          color: containerColor,
          shape: const StadiumBorder(),
          shadows: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            mouseCursor: SystemMouseCursors.click,
            onTap: _running ? null : _handlePressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 0,
                    child: _FeedbackLabelRow(
                      icon: widget.icon,
                      label: widget.label,
                      color: contentColor,
                    ),
                  ),
                  Opacity(
                    opacity: 0,
                    child: _FeedbackLabelRow(
                      icon: Icons.check_circle_outline,
                      label: successLabel,
                      color: contentColor,
                    ),
                  ),
                  _AnimatedFeedbackLabel(
                    showFeedback: showingFeedback,
                    icon: widget.icon,
                    label: widget.label,
                    successLabel: widget.successLabel,
                    color: contentColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizontalWheelScroll extends StatefulWidget {
  const _HorizontalWheelScroll({required this.height, required this.children});

  final double height;
  final List<Widget> children;

  @override
  State<_HorizontalWheelScroll> createState() => _HorizontalWheelScrollState();
}

class _HorizontalWheelScrollState extends State<_HorizontalWheelScroll> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    _scrollController.jumpTo(target.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final scrollBehavior = ScrollConfiguration.of(context).copyWith(
      scrollbars: false,
      dragDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      },
    );
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          Listener(
            onPointerSignal: _handlePointerSignal,
            child: ScrollConfiguration(
              behavior: scrollBehavior,
              child: ListView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                children: widget.children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({
    required this.selectedKind,
    required this.selectedScope,
    required this.selectedScopePosition,
    required this.showScopeFilter,
    this.compact = false,
    required this.onKindSelected,
    required this.onScopeSelected,
  });

  final ClipboardKind? selectedKind;
  final _HistoryScopeFilter selectedScope;
  final double selectedScopePosition;
  final bool showScopeFilter;
  final bool compact;
  final ValueChanged<ClipboardKind?> onKindSelected;
  final ValueChanged<_HistoryScopeFilter> onScopeSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final tight = width < 380;
        final medium = width >= 380 && width < 520;
        final iconOnlyCategories = width < 560;
        const expandCategoryButtons = true;
        final buttonHeight = tight
            ? 34.0
            : medium
            ? 36.0
            : 38.0;
        final iconSize = tight
            ? 16.0
            : medium
            ? 17.0
            : 18.0;
        final iconPadding = tight
            ? 10.0
            : medium
            ? 12.0
            : 14.0;
        final labelPadding = tight
            ? 8.0
            : medium
            ? 9.0
            : 10.0;
        final groupGap = tight ? 2.0 : 3.0;
        final rowGap = tight ? 6.0 : 7.0;

        return Padding(
          padding: EdgeInsets.fromLTRB(tight ? 10 : 12, 0, tight ? 10 : 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: buttonHeight,
                width: double.infinity,
                child: _ConnectedButtonGroup(
                  expanded: expandCategoryButtons,
                  height: buttonHeight,
                  iconSize: iconSize,
                  iconOnlyHorizontalPadding: iconPadding,
                  labelHorizontalPadding: labelPadding,
                  gap: groupGap,
                  segments: [
                    _ConnectedButtonSegment(
                      label: context.l10n.allItems,
                      icon: Icons.all_inclusive,
                      selected: selectedKind == null,
                      iconOnly: iconOnlyCategories,
                      onPressed: () => onKindSelected(null),
                    ),
                    for (final kind in ClipboardKind.values)
                      _ConnectedButtonSegment(
                        label: _shortKindLabel(context.l10n, kind),
                        icon: _kindIcon(kind),
                        selected: selectedKind == kind,
                        iconOnly: iconOnlyCategories,
                        onPressed: () => onKindSelected(kind),
                      ),
                  ],
                ),
              ),
              if (showScopeFilter) ...[
                SizedBox(height: rowGap),
                _HistoryScopePillBar(
                  selected: selectedScope,
                  selectedPosition: selectedScopePosition,
                  height: tight ? 30 : 32,
                  compact: iconOnlyCategories,
                  onSelected: onScopeSelected,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HistoryScopePillBar extends StatelessWidget {
  const _HistoryScopePillBar({
    required this.selected,
    required this.selectedPosition,
    required this.height,
    required this.compact,
    required this.onSelected,
  });

  final _HistoryScopeFilter selected;
  final double selectedPosition;
  final double height;
  final bool compact;
  final ValueChanged<_HistoryScopeFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = colorScheme.brightness == Brightness.dark;
    final items =
        <
          ({
            _HistoryScopeFilter value,
            String label,
            IconData icon,
            IconData selectedIcon,
          })
        >[
          (
            value: _HistoryScopeFilter.all,
            label: l10n.allItems,
            icon: Icons.all_inclusive,
            selectedIcon: Icons.all_inclusive,
          ),
          (
            value: _HistoryScopeFilter.pinned,
            label: l10n.pin,
            icon: Icons.bookmark_border,
            selectedIcon: Icons.bookmark,
          ),
          (
            value: _HistoryScopeFilter.tagged,
            label: l10n.tagged,
            icon: Icons.sell_outlined,
            selectedIcon: Icons.sell,
          ),
        ];
    final selectedIndex = items.indexWhere((item) => item.value == selected);
    final safeSelectedIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final safeSelectedPosition = selectedPosition.clamp(
      0.0,
      (items.length - 1).toDouble(),
    );
    final dragging =
        (safeSelectedPosition - safeSelectedIndex.toDouble()).abs() > 0.001;
    final glassFill = colorScheme.surfaceContainerHigh.withValues(
      alpha: isDark ? 0.64 : 0.58,
    );
    final glassBorder = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.08),
      colorScheme.outlineVariant.withValues(alpha: 0.34),
    );
    final activePillColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.30 : 0.20),
      colorScheme.surfaceContainerHighest.withValues(alpha: 0.76),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: glassFill,
                  shape: StadiumBorder(
                    side: BorderSide(color: glassBorder, width: 1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: LayoutBuilder(
                    builder: (context, innerConstraints) {
                      const gap = 3.0;
                      final itemWidth =
                          (innerConstraints.maxWidth -
                              gap * (items.length - 1)) /
                          items.length;
                      final indicatorLeft =
                          safeSelectedPosition * (itemWidth + gap);
                      final indicator = IgnorePointer(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(
                            'history-scope-pill-$safeSelectedIndex',
                          ),
                          tween: Tween(begin: 0, end: 1),
                          duration: dragging
                              ? Duration.zero
                              : const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            final squash = math.sin(value * math.pi);
                            return Transform.scale(
                              scaleX: 1 + squash * 0.025,
                              scaleY: 1 - squash * 0.10,
                              child: child,
                            );
                          },
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: activePillColor,
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                      return Stack(
                        children: [
                          if (dragging)
                            Positioned(
                              left: indicatorLeft,
                              top: 0,
                              width: itemWidth,
                              height: innerConstraints.maxHeight,
                              child: indicator,
                            )
                          else
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              left: indicatorLeft,
                              top: 0,
                              width: itemWidth,
                              height: innerConstraints.maxHeight,
                              child: indicator,
                            ),
                          Row(
                            children: [
                              for (var index = 0; index < items.length; index++)
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: index == items.length - 1
                                          ? 0
                                          : gap,
                                    ),
                                    child: _HistoryScopePillButton(
                                      label: items[index].label,
                                      icon: items[index].icon,
                                      selectedIcon: items[index].selectedIcon,
                                      selected: index == safeSelectedIndex,
                                      onPressed: () =>
                                          onSelected(items[index].value),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HistoryScopePillButton extends StatelessWidget {
  const _HistoryScopePillButton({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: SystemMouseCursors.click,
        customBorder: const StadiumBorder(),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: selected ? 16 : 15,
                color: foreground,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectedButtonSegment {
  const _ConnectedButtonSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.iconColor,
    this.maxLabelWidth,
    this.iconOnly = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final Color? iconColor;
  final double? maxLabelWidth;
  final bool iconOnly;
}

class _ConnectedButtonGroup extends StatefulWidget {
  const _ConnectedButtonGroup({
    required this.segments,
    this.expanded = false,
    this.height = 38,
    this.iconSize = 18,
    this.iconOnlyHorizontalPadding = 14,
    this.labelHorizontalPadding = 10,
    this.gap = 3,
  });

  final List<_ConnectedButtonSegment> segments;
  final bool expanded;
  final double height;
  final double iconSize;
  final double iconOnlyHorizontalPadding;
  final double labelHorizontalPadding;
  final double gap;

  @override
  State<_ConnectedButtonGroup> createState() => _ConnectedButtonGroupState();
}

class _ConnectedButtonGroupState extends State<_ConnectedButtonGroup> {
  final GlobalKey _groupKey = GlobalKey();
  late List<GlobalKey> _itemKeys;
  double _indicatorLeft = 0;
  double _indicatorWidth = 0;
  double? _lastLayoutWidth;

  int get _selectedIndex {
    final index = widget.segments.indexWhere((segment) => segment.selected);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _itemKeys = _keysFor(widget.segments.length);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncIndicator());
  }

  @override
  void didUpdateWidget(covariant _ConnectedButtonGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments.length != widget.segments.length) {
      _itemKeys = _keysFor(widget.segments.length);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncIndicator());
  }

  List<GlobalKey> _keysFor(int count) {
    return List<GlobalKey>.generate(count, (_) => GlobalKey());
  }

  void _syncIndicator() {
    if (!mounted || widget.segments.isEmpty) return;
    final groupContext = _groupKey.currentContext;
    final itemContext = _itemKeys[_selectedIndex].currentContext;
    if (groupContext == null || itemContext == null) return;
    final groupBox = groupContext.findRenderObject() as RenderBox?;
    final itemBox = itemContext.findRenderObject() as RenderBox?;
    if (groupBox == null || itemBox == null) return;
    final itemOffset = itemBox.localToGlobal(Offset.zero, ancestor: groupBox);
    final nextLeft = itemOffset.dx;
    final nextWidth = itemBox.size.width;
    if ((nextLeft - _indicatorLeft).abs() < 0.5 &&
        (nextWidth - _indicatorWidth).abs() < 0.5) {
      return;
    }
    setState(() {
      _indicatorLeft = nextLeft;
      _indicatorWidth = nextWidth;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedCount = widget.segments
        .where((segment) => segment.selected)
        .length;
    final useMovingIndicator = selectedCount <= 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutWidth = constraints.maxWidth;
        if (_lastLayoutWidth == null ||
            (_lastLayoutWidth! - layoutWidth).abs() > 0.5) {
          _lastLayoutWidth = layoutWidth;
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncIndicator());
        }
        return Stack(
          key: _groupKey,
          clipBehavior: Clip.none,
          children: [
            if (useMovingIndicator && _indicatorWidth > 0)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubicEmphasized,
                left: _indicatorLeft,
                top: 0,
                width: _indicatorWidth,
                height: widget.height,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: colorScheme.secondary,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            Row(
              mainAxisSize: widget.expanded
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              children: [
                for (
                  var index = 0;
                  index < widget.segments.length;
                  index++
                ) ...[
                  if (widget.expanded)
                    Expanded(
                      child: KeyedSubtree(
                        key: _itemKeys[index],
                        child: _ConnectedButtonGroupItem(
                          segment: widget.segments[index],
                          index: index,
                          count: widget.segments.length,
                          useMovingIndicator: useMovingIndicator,
                          height: widget.height,
                          iconSize: widget.iconSize,
                          iconOnlyHorizontalPadding:
                              widget.iconOnlyHorizontalPadding,
                          labelHorizontalPadding: widget.labelHorizontalPadding,
                          expanded: true,
                        ),
                      ),
                    )
                  else
                    KeyedSubtree(
                      key: _itemKeys[index],
                      child: _ConnectedButtonGroupItem(
                        segment: widget.segments[index],
                        index: index,
                        count: widget.segments.length,
                        useMovingIndicator: useMovingIndicator,
                        height: widget.height,
                        iconSize: widget.iconSize,
                        iconOnlyHorizontalPadding:
                            widget.iconOnlyHorizontalPadding,
                        labelHorizontalPadding: widget.labelHorizontalPadding,
                        expanded: false,
                      ),
                    ),
                  if (index != widget.segments.length - 1)
                    SizedBox(width: widget.gap),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ConnectedButtonGroupItem extends StatelessWidget {
  const _ConnectedButtonGroupItem({
    required this.segment,
    required this.index,
    required this.count,
    required this.useMovingIndicator,
    required this.height,
    required this.iconSize,
    required this.iconOnlyHorizontalPadding,
    required this.labelHorizontalPadding,
    required this.expanded,
  });

  final _ConnectedButtonSegment segment;
  final int index;
  final int count;
  final bool useMovingIndicator;
  final double height;
  final double iconSize;
  final double iconOnlyHorizontalPadding;
  final double labelHorizontalPadding;
  final bool expanded;

  BorderRadius get _borderRadius {
    final outer = Radius.circular(height / 2);
    const inner = Radius.circular(4);
    if (segment.selected || count == 1) {
      return BorderRadius.circular(height / 2);
    }
    if (index == 0) {
      return BorderRadius.horizontal(left: outer, right: inner);
    }
    if (index == count - 1) {
      return BorderRadius.horizontal(left: inner, right: outer);
    }
    return BorderRadius.circular(4);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = segment.selected
        ? colorScheme.onSecondary
        : colorScheme.onSecondaryContainer;
    final iconColor = segment.selected
        ? colorScheme.onSecondary
        : segment.iconColor ?? foregroundColor;
    final borderRadius = _borderRadius;
    Widget labelWidget() {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: segment.maxLabelWidth ?? 96),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          style:
              Theme.of(context).textTheme.labelLarge?.copyWith(
                color: foregroundColor,
                fontWeight: segment.selected ? FontWeight.w700 : null,
              ) ??
              TextStyle(color: foregroundColor),
          child: Text(
            segment.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    final button = Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        hoverColor: foregroundColor.withValues(alpha: 0.08),
        splashColor: foregroundColor.withValues(alpha: 0.10),
        highlightColor: foregroundColor.withValues(alpha: 0.06),
        mouseCursor: SystemMouseCursors.click,
        onTap: segment.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: segment.iconOnly
                ? iconOnlyHorizontalPadding
                : labelHorizontalPadding,
          ),
          decoration: ShapeDecoration(
            color: segment.selected && useMovingIndicator
                ? Colors.transparent
                : segment.selected
                ? colorScheme.secondary
                : colorScheme.secondaryContainer,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
          ),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(segment.icon, size: iconSize, color: iconColor),
              if (!segment.iconOnly) ...[
                SizedBox(width: height <= 34 ? 5 : 7),
                if (expanded) Flexible(child: labelWidget()) else labelWidget(),
              ],
            ],
          ),
        ),
      ),
    );
    if (!segment.iconOnly) return button;
    return Tooltip(message: segment.label, child: button);
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.content_paste_search, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? Icons.add),
              label: _ButtonLabel(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClipboardTile extends StatefulWidget {
  const _ClipboardTile({
    required this.entry,
    required this.tagDefinitions,
    required this.selected,
    required this.bulkSelectMode,
    required this.bulkSelected,
    required this.onTap,
    required this.onToggleBulkSelected,
    required this.onContextMenuOpened,
    required this.onCopy,
    required this.onTogglePin,
    required this.onEditTags,
    required this.onDelete,
  });

  final ClipboardEntry entry;
  final Map<String, TagDefinition> tagDefinitions;
  final bool selected;
  final bool bulkSelectMode;
  final bool bulkSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleBulkSelected;
  final VoidCallback onContextMenuOpened;
  final VoidCallback onCopy;
  final VoidCallback onTogglePin;
  final VoidCallback onEditTags;
  final VoidCallback onDelete;
  static OverlayEntry? _openContextMenuEntry;

  static void _closeOpenContextMenu() {
    _openContextMenuEntry?.remove();
    _openContextMenuEntry = null;
  }

  @override
  State<_ClipboardTile> createState() => _ClipboardTileState();
}

class _ClipboardTileState extends State<_ClipboardTile> {
  bool _suppressNextTap = false;

  void _showContextMenu(BuildContext context, Offset position) {
    widget.onContextMenuOpened();
    _ClipboardTile._closeOpenContextMenu();
    void closeMenu() {
      _ClipboardTile._closeOpenContextMenu();
    }

    void runAction(VoidCallback action) {
      closeMenu();
      action();
    }

    _ClipboardTile._openContextMenuEntry = OverlayEntry(
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final left = math
            .min(position.dx, math.max(8, size.width - 168))
            .clamp(8.0, math.max(8.0, size.width - 8));
        final top = math
            .min(position.dy, math.max(8, size.height - 232))
            .clamp(8.0, math.max(8.0, size.height - 8));
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: closeMenu,
              ),
            ),
            Positioned(
              left: left.toDouble(),
              top: top.toDouble(),
              child: _ExpressiveClipboardContextMenu(
                pinned: widget.entry.pinned,
                onCopy: () => runAction(widget.onCopy),
                onTogglePin: () => runAction(widget.onTogglePin),
                onEditTags: () => runAction(widget.onEditTags),
                onDelete: () => runAction(widget.onDelete),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_ClipboardTile._openContextMenuEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bulkSelectedColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.18),
      colorScheme.surfaceContainerHigh,
    );
    final bulkSelectedBorderColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.42),
      colorScheme.outlineVariant,
    );
    final tileColor = widget.bulkSelected
        ? bulkSelectedColor
        : widget.selected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerLow;
    final contentColor = widget.bulkSelected
        ? colorScheme.onPrimaryContainer
        : widget.selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;
    final supportingColor = widget.bulkSelected
        ? colorScheme.onPrimaryContainer
        : widget.selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final borderRadius = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        decoration: ShapeDecoration(
          color: tileColor,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(
              color: widget.selected
                  ? colorScheme.primary
                  : widget.bulkSelected
                  ? bulkSelectedBorderColor
                  : colorScheme.outlineVariant,
              width: widget.selected ? 2 : 1,
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: GestureDetector(
            onSecondaryTapDown: (details) =>
                _showContextMenu(context, details.globalPosition),
            onLongPressStart: (details) {
              _suppressNextTap = true;
              _showContextMenu(context, details.globalPosition);
            },
            child: InkWell(
              borderRadius: borderRadius,
              mouseCursor: SystemMouseCursors.click,
              onTap: () {
                if (_suppressNextTap) {
                  _suppressNextTap = false;
                  return;
                }
                widget.onTap();
              },
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  widget.selected ? 8 : 12,
                  10,
                  12,
                  10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: widget.selected ? 4 : 0,
                      height: widget.selected ? 44 : 0,
                      decoration: ShapeDecoration(
                        color: colorScheme.primary,
                        shape: const StadiumBorder(),
                      ),
                    ),
                    if (widget.selected) const SizedBox(width: 8),
                    Icon(
                      _kindIcon(widget.entry.kind),
                      size: 20,
                      color: supportingColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.bulkSelectMode) ...[
                            Row(
                              children: [
                                Checkbox(
                                  value: widget.bulkSelected,
                                  onChanged: (_) =>
                                      widget.onToggleBulkSelected(),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    widget.entry.preview,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: contentColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ] else
                            Text(
                              widget.entry.preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: contentColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (_shouldShowSourceIcon(widget.entry)) ...[
                                _SourceAppIcon(
                                  entry: widget.entry,
                                  dimension: 18,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _displaySourceLabel(
                                          widget.entry.source,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: supportingColor),
                                      ),
                                    ),
                                    if (widget.entry.tags.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      for (final tag in widget.entry.tags.take(
                                        2,
                                      )) ...[
                                        Flexible(
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 92,
                                            ),
                                            child: _TagBadge(
                                              label: tag,
                                              definition:
                                                  widget.tagDefinitions[tag],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      if (widget.entry.tags.length > 2)
                                        _M3Badge(
                                          label:
                                              '+${widget.entry.tags.length - 2}',
                                          tone: _M3BadgeTone.surface,
                                          horizontalPadding: 7,
                                          tightText: true,
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _M3Badge(
                                label: widget.entry.createdLabel,
                                icon: Icons.schedule,
                                tone: widget.bulkSelected || widget.selected
                                    ? _M3BadgeTone.selected
                                    : _M3BadgeTone.primary,
                                horizontalPadding: 8,
                                tightText: true,
                                containerColorOverride: Color.alphaBlend(
                                  colorScheme.primary.withValues(alpha: 0.10),
                                  colorScheme.surfaceContainerHigh,
                                ),
                                contentColorOverride: colorScheme.primary,
                                iconColorOverride: colorScheme.primary,
                                borderColorOverride: colorScheme.primary
                                    .withValues(alpha: 0.18),
                              ),
                              if (widget.entry.pinned) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.bookmark,
                                  size: 16,
                                  color: supportingColor,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpressiveClipboardContextMenu extends StatelessWidget {
  const _ExpressiveClipboardContextMenu({
    required this.pinned,
    required this.onCopy,
    required this.onTogglePin,
    required this.onEditTags,
    required this.onDelete,
  });

  final bool pinned;
  final VoidCallback onCopy;
  final VoidCallback onTogglePin;
  final VoidCallback onEditTags;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset((1 - value) * -4, (1 - value) * -4),
            child: Transform.scale(
              scale: 0.96 + value * 0.04,
              alignment: Alignment.topLeft,
              child: child,
            ),
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ExpressiveFabMenuAction(
              icon: Icons.copy,
              label: l10n.copy,
              successLabel: l10n.copied,
              actionDelay: const Duration(milliseconds: 260),
              onPressed: onCopy,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: pinned ? Icons.bookmark : Icons.bookmark_border,
              label: pinned ? l10n.unpin : l10n.pin,
              onPressed: onTogglePin,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.sell_outlined,
              label: l10n.tagsAction,
              onPressed: onEditTags,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.delete_outline,
              label: l10n.delete,
              successLabel: l10n.deleted,
              actionDelay: const Duration(milliseconds: 320),
              destructive: true,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceAppIcon extends StatelessWidget {
  const _SourceAppIcon({required this.entry, this.dimension = 24});

  final ClipboardEntry entry;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconBytes = entry.sourceIconBytes;
    final fallbackIcon = _shouldUseDeviceSourceIcon(entry)
        ? Icons.devices_other_outlined
        : _kindIcon(entry.kind);
    final fallback = Icon(
      fallbackIcon,
      size: 18,
      color: colorScheme.onSurfaceVariant,
    );

    final shouldUseSourceIcon = _hasUsableSourceIcon(entry);
    return SizedBox.square(
      dimension: dimension,
      child: Center(
        child: !shouldUseSourceIcon
            ? fallback
            : ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.memory(
                  iconBytes!,
                  width: dimension - 2,
                  height: dimension - 2,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => fallback,
                ),
              ),
      ),
    );
  }
}

bool _hasUsableSourceIcon(ClipboardEntry entry) {
  final iconBytes = entry.sourceIconBytes;
  return iconBytes != null && _isPngBytes(iconBytes);
}

bool _shouldUseDeviceSourceIcon(ClipboardEntry entry) {
  if (_hasUsableSourceIcon(entry)) return false;
  return _isLikelySyncedDeviceSource(entry.source);
}

bool _shouldShowSourceIcon(ClipboardEntry entry) {
  if (Platform.isAndroid && _isPlainClipboardSource(entry.source)) {
    return false;
  }
  return _hasUsableSourceIcon(entry) || _shouldUseDeviceSourceIcon(entry);
}

bool _isPlainClipboardSource(String source) {
  final normalized = _displaySourceLabel(source).trim().toLowerCase();
  return normalized == 'clipboard android' ||
      normalized == 'clipboard hệ thống' ||
      normalized == 'clipboard he thong';
}

bool _isLikelySyncedDeviceSource(String source) {
  final normalized = _displaySourceLabel(source).trim().toLowerCase();
  if (normalized.isEmpty) return false;
  const localSources = {
    'clipboard',
    'clipboard hệ thống',
    'clipboard he thong',
    'clipboard android',
    'file explorer',
    'windows explorer',
  };
  if (localSources.contains(normalized)) return false;
  if (normalized.endsWith('.exe')) return false;
  return true;
}

class _CompactSheetDragHandle extends StatelessWidget {
  const _CompactSheetDragHandle();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        height: 8,
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: ShapeDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
              shape: const StadiumBorder(),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteUndoNoticeContent extends StatelessWidget {
  const _DeleteUndoNoticeContent({required this.message, required this.onUndo});

  final String message;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 6, 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onUndo,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      fixedSize: const Size.fromHeight(26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      context.l10n.undo,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.entry,
    this.compact = false,
    this.actionBarKey,
    required this.onRestore,
    required this.onOpenUrl,
    required this.onOpenFileLocation,
    required this.onTogglePin,
    required this.onDelete,
    required this.onEditTags,
    required this.tagDefinitions,
  });

  final ClipboardEntry? entry;
  final bool compact;
  final Key? actionBarKey;
  final VoidCallback? onRestore;
  final VoidCallback? onOpenUrl;
  final VoidCallback? onOpenFileLocation;
  final VoidCallback? onTogglePin;
  final VoidCallback? onDelete;
  final VoidCallback? onEditTags;
  final Map<String, TagDefinition> tagDefinitions;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final detailActionButtonStyle = FilledButton.styleFrom(
      fixedSize: const Size.fromHeight(38),
      minimumSize: const Size(60, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final detailIconButtonStyle = IconButton.styleFrom(
      fixedSize: const Size.square(38),
      minimumSize: const Size.square(38),
      maximumSize: const Size.square(38),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final deleteActionButtonStyle = FilledButton.styleFrom(
      fixedSize: const Size.fromHeight(38),
      minimumSize: const Size(60, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: colorScheme.errorContainer,
      foregroundColor: colorScheme.onErrorContainer,
    );
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          if (entry != null)
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  border: Border(
                    bottom: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, compact ? 8 : 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _OpticallyCenteredIcon(
                              _kindIcon(entry.kind),
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                _kindLabel(context.l10n, entry.kind),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textHeightBehavior: const TextHeightBehavior(
                                  applyHeightToFirstAscent: false,
                                  applyHeightToLastDescent: false,
                                ),
                                style: const TextStyle(
                                  fontSize: 20,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Tooltip(
                            message: l10n.copyToClipboard,
                            child: _MotionFeedbackButton(
                              onPressed: onRestore,
                              icon: Icons.copy,
                              label: l10n.copy,
                              successLabel: l10n.copied,
                              variant: _MotionFeedbackButtonVariant.filledTonal,
                              labelYOffset: compact ? 1 : -1,
                            ),
                          ),
                          if (entry.kind == ClipboardKind.url)
                            Tooltip(
                              message: l10n.openUrlTooltip,
                              child: compact
                                  ? IconButton.filledTonal(
                                      onPressed: onOpenUrl,
                                      style: detailIconButtonStyle,
                                      icon: const Icon(Icons.open_in_browser),
                                    )
                                  : FilledButton.tonalIcon(
                                      onPressed: onOpenUrl,
                                      style: detailActionButtonStyle,
                                      icon: const Icon(Icons.open_in_browser),
                                      label: _ButtonLabel(l10n.openUrl),
                                    ),
                            ),
                          if (entry.kind == ClipboardKind.fileReference)
                            Tooltip(
                              message: l10n.openFileLocationTooltip,
                              child: compact
                                  ? IconButton.filledTonal(
                                      onPressed: onOpenFileLocation,
                                      style: detailIconButtonStyle,
                                      icon: const Icon(
                                        Icons.folder_open_outlined,
                                      ),
                                    )
                                  : FilledButton.tonalIcon(
                                      onPressed: onOpenFileLocation,
                                      style: detailActionButtonStyle,
                                      icon: const Icon(
                                        Icons.folder_open_outlined,
                                      ),
                                      label: _ButtonLabel(l10n.openFolder),
                                    ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  entry == null ? 0 : 16,
                  20,
                  entry == null ? 20 : 12,
                ),
                children: [
                  if (entry == null)
                    const _NoSelectionPanel()
                  else ...[
                    _PreviewBox(entry: entry),
                    const SizedBox(height: 16),
                    if (entry.tags.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in entry.tags)
                            _TagBadge(
                              label: tag,
                              definition: tagDefinitions[tag],
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (entry != null)
            DecoratedBox(
              key: actionBarKey,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final iconOnlyActions =
                          compact || constraints.maxWidth < 390;
                      return Row(
                        children: [
                          Tooltip(
                            message: entry.pinned ? l10n.unpin : l10n.pin,
                            child: iconOnlyActions
                                ? IconButton.filledTonal(
                                    onPressed: onTogglePin,
                                    style: detailIconButtonStyle,
                                    icon: Transform.translate(
                                      offset: Offset(compact ? 0 : -0.75, 0),
                                      child: Icon(
                                        entry.pinned
                                            ? Icons.bookmark
                                            : Icons.bookmark_border,
                                      ),
                                    ),
                                  )
                                : FilledButton.tonalIcon(
                                    onPressed: onTogglePin,
                                    style: detailActionButtonStyle,
                                    icon: Icon(
                                      entry.pinned
                                          ? Icons.bookmark
                                          : Icons.bookmark_border,
                                    ),
                                    label: _ButtonLabel(
                                      entry.pinned
                                          ? l10n.pinnedState
                                          : l10n.pin,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: l10n.tagsAction,
                            child: iconOnlyActions
                                ? IconButton.filledTonal(
                                    onPressed: onEditTags,
                                    style: detailIconButtonStyle,
                                    icon: Transform.translate(
                                      offset: Offset(compact ? 0.75 : 0, 0),
                                      child: const Icon(Icons.sell_outlined),
                                    ),
                                  )
                                : FilledButton.tonalIcon(
                                    onPressed: onEditTags,
                                    style: detailActionButtonStyle,
                                    icon: const Icon(Icons.sell_outlined),
                                    label: _ButtonLabel(l10n.tagsAction),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: l10n.deleteClipboard,
                            child: FilledButton.tonalIcon(
                              onPressed: onDelete,
                              style: deleteActionButtonStyle,
                              icon: const Icon(Icons.delete_outline),
                              label: compact
                                  ? Transform.translate(
                                      offset: const Offset(0, 1),
                                      child: _ButtonLabel(l10n.delete),
                                    )
                                  : _ButtonLabel(l10n.delete),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _CopiedAtLabel(
                                value: entry.createdAt,
                                compact: true,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CopiedAtLabel extends StatelessWidget {
  const _CopiedAtLabel({required this.value, this.compact = false});

  final DateTime value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 170 : 240),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 8 : 9,
      ),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 17,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Transform.translate(
              offset: Offset(0, compact ? 0 : -1),
              child: Text(
                _copyTimeLabel(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSelectionPanel extends StatelessWidget {
  const _NoSelectionPanel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(child: Text(context.l10n.selectClipboardPreview)),
    );
  }
}

class _OpticallyCenteredIcon extends StatelessWidget {
  const _OpticallyCenteredIcon(this.icon, {required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, 1.5),
      child: Icon(icon, size: size),
    );
  }
}

class _TagEditorDialog extends StatefulWidget {
  const _TagEditorDialog({
    required this.initialTags,
    required this.knownTags,
    required this.definitions,
    this.libraryOnly = false,
  });

  final List<String> initialTags;
  final List<String> knownTags;
  final Map<String, TagDefinition> definitions;
  final bool libraryOnly;

  @override
  State<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<_TagEditorDialog> {
  late final TextEditingController _controller;
  TextEditingController? _colorController;
  late final Set<String> _selectedTags;
  Set<String>? _deletedTags;
  late final Map<String, TagDefinition> _definitions;
  late int _selectedColorValue;
  late String _selectedIconKey;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _selectedTags = widget.initialTags.toSet();
    _definitions = Map<String, TagDefinition>.from(widget.definitions);
    _selectedColorValue = _tagColorOptions.first;
    _selectedIconKey = _tagIconOptions.first.key;
  }

  Set<String> get _deletedTagSet => _deletedTags ??= <String>{};
  TextEditingController get _tagColorController => _colorController ??=
      TextEditingController(text: _hexColorText(_selectedColorValue));

  @override
  void dispose() {
    _controller.dispose();
    _colorController?.dispose();
    super.dispose();
  }

  List<String> get _allTags {
    final tags = {...widget.knownTags, ..._selectedTags, ..._definitions.keys}
        .where((tag) => tag.trim().isNotEmpty && !_deletedTagSet.contains(tag))
        .toList();
    tags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return tags;
  }

  void _addOrUpdateTag() {
    final name = _normalizeTagName(_controller.text);
    if (name.isEmpty) return;
    setState(() {
      _definitions[name] = TagDefinition(
        name: name,
        colorValue: _selectedColorValue,
        iconKey: _selectedIconKey,
      );
      _deletedTagSet.remove(name);
      if (!widget.libraryOnly) {
        _selectedTags.add(name);
      }
      _controller.clear();
    });
  }

  void _setSelectedColor(Color color, {bool updateInput = true}) {
    setState(() {
      _selectedColorValue = _opaqueColorValue(color.toARGB32());
      if (updateInput) {
        _tagColorController.text = _hexColorText(_selectedColorValue);
      }
    });
  }

  void _applyCustomColor() {
    final color = _parseHexColor(_tagColorController.text);
    if (color == null) return;
    _setSelectedColor(color, updateInput: true);
  }

  void _pickTagForEditing(String tag) {
    final definition = _definitions[tag];
    setState(() {
      _controller.text = tag;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: tag.length,
      );
      if (definition != null) {
        _selectedColorValue = _opaqueColorValue(definition.colorValue);
        _tagColorController.text = _hexColorText(_selectedColorValue);
        _selectedIconKey = definition.iconKey;
      }
    });
  }

  void _deleteTag(String tag) {
    setState(() {
      _deletedTagSet.add(tag);
      _definitions.remove(tag);
      _selectedTags.remove(tag);
      if (_normalizeTagName(_controller.text) == tag) {
        _controller.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final previewName = _normalizeTagName(_controller.text).isEmpty
        ? l10n.newTagPreview
        : _normalizeTagName(_controller.text);
    final previewDefinition = TagDefinition(
      name: previewName,
      colorValue: _selectedColorValue,
      iconKey: _selectedIconKey,
    );
    final dialogContentWidth = math.min(
      620.0,
      math.max(280.0, MediaQuery.sizeOf(context).width - 64),
    );
    return AlertDialog(
      title: Text(widget.libraryOnly ? l10n.tagLibrary : l10n.attachTags),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      buttonPadding: const EdgeInsets.symmetric(horizontal: 4),
      content: SizedBox(
        width: dialogContentWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(MediaQuery.sizeOf(context).height * 0.72, 640),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.libraryOnly) ...[
                  _TagEditorSection(
                    title: l10n.attachedTags,
                    child: _selectedTags.isEmpty
                        ? Text(
                            l10n.noTags,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          )
                        : _ResponsiveTagChipGrid(
                            itemCount: _selectedTags.length,
                            minItemWidth: 112,
                            itemBuilder: (context, index, maxWidth) {
                              final tag = _selectedTags.elementAt(index);
                              return _AttachedTagChip(
                                label: tag,
                                definition: _definitions[tag],
                                maxButtonWidth: math.max(72, maxWidth - 36),
                                onPressed: () => _pickTagForEditing(tag),
                                onDeleted: () {
                                  setState(() => _selectedTags.remove(tag));
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
                _TagEditorSection(
                  title: l10n.tagLibrary,
                  child: _allTags.isEmpty
                      ? Text(
                          l10n.noTags,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        )
                      : _ResponsiveTagChipGrid(
                          itemCount: _allTags.length,
                          minItemWidth: 132,
                          itemBuilder: (context, index, maxWidth) {
                            final tag = _allTags[index];
                            return _TagLibraryChip(
                              label: tag,
                              definition: _definitions[tag],
                              maxButtonWidth: math.max(72, maxWidth - 70),
                              selected:
                                  !widget.libraryOnly &&
                                  _selectedTags.contains(tag),
                              onSelected: (selected) {
                                if (widget.libraryOnly) {
                                  _pickTagForEditing(tag);
                                } else {
                                  setState(() {
                                    if (selected) {
                                      _selectedTags.add(tag);
                                    } else {
                                      _selectedTags.remove(tag);
                                    }
                                  });
                                }
                              },
                              onEdit: () => _pickTagForEditing(tag),
                              onDelete: () => _deleteTag(tag),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                _TagEditorSection(
                  title: l10n.createEditTag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TagBadge(
                        label: previewName,
                        definition: previewDefinition,
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final availableWidth = constraints.maxWidth.isFinite
                              ? constraints.maxWidth
                              : MediaQuery.sizeOf(context).width - 72;
                          final showFullButton = availableWidth >= 360;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _addOrUpdateTag(),
                                  decoration: InputDecoration(
                                    labelText: l10n.tagName,
                                    hintText: 'cong-viec, sync',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tooltip(
                                message: l10n.addOrUpdate,
                                child: showFullButton
                                    ? FilledButton.tonalIcon(
                                        onPressed: _addOrUpdateTag,
                                        icon: const Icon(Icons.add),
                                        label: _ButtonLabel(l10n.addOrUpdate),
                                      )
                                    : IconButton.filledTonal(
                                        onPressed: _addOrUpdateTag,
                                        icon: const Icon(Icons.add),
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final colorValue in _tagColorOptions)
                            _TagColorButton(
                              color: Color(colorValue),
                              selected:
                                  _opaqueColorValue(_selectedColorValue) ==
                                  _opaqueColorValue(colorValue),
                              onTap: () => _setSelectedColor(Color(colorValue)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final maxWidth = constraints.maxWidth.isFinite
                              ? constraints.maxWidth
                              : 320.0;
                          return SizedBox(
                            width: math.min(maxWidth, 360),
                            child: TextField(
                              controller: _tagColorController,
                              textInputAction: TextInputAction.done,
                              textCapitalization: TextCapitalization.characters,
                              onSubmitted: (_) => _applyCustomColor(),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: l10n.customColor,
                                hintText: '#7C3AED',
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Color(_selectedColorValue),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: colorScheme.outlineVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                suffixIcon: IconButton(
                                  tooltip: l10n.applyColor,
                                  onPressed: _applyCustomColor,
                                  icon: const Icon(Icons.check),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _ResponsiveTagIconGrid(
                        selectedIconKey: _selectedIconKey,
                        onSelected: (key) {
                          setState(() => _selectedIconKey = key);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: _ButtonLabel(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _TagEditResult(
                tags: _selectedTags.toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
                definitions: _definitions,
                deletedTags: _deletedTagSet,
              ),
            );
          },
          child: _ButtonLabel(l10n.save),
        ),
      ],
    );
  }
}

class _ResponsiveTagChipGrid extends StatelessWidget {
  const _ResponsiveTagChipGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.minItemWidth = 152,
  });

  final int itemCount;
  final double minItemWidth;
  final Widget Function(BuildContext context, int index, double maxWidth)
  itemBuilder;

  @override
  Widget build(BuildContext context) {
    const spacing = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 72;
        final maxItemWidth = math.max(minItemWidth, width);
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var index = 0; index < itemCount; index++)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxItemWidth),
                child: itemBuilder(context, index, maxItemWidth),
              ),
          ],
        );
      },
    );
  }
}

class _ResponsiveTagIconGrid extends StatelessWidget {
  const _ResponsiveTagIconGrid({
    required this.selectedIconKey,
    required this.onSelected,
  });

  final String selectedIconKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 72;
        const spacing = 8.0;
        final columns = math
            .max(4, math.min(8, ((width + spacing) / 48).floor()))
            .toInt();
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final option in _tagIconOptions)
              SizedBox(
                width: itemWidth,
                child: Center(
                  child: IconButton.filledTonal(
                    isSelected: selectedIconKey == option.key,
                    tooltip: option.key,
                    onPressed: () => onSelected(option.key),
                    icon: Icon(option.icon),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TagColorButton extends StatelessWidget {
  const _TagColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final checkColor = color.computeLuminance() > 0.45
        ? Colors.black87
        : Colors.white;
    return Tooltip(
      message: '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
      child: InkResponse(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        radius: 22,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? colorScheme.onSurface : colorScheme.outline,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 16, color: checkColor)
              : null,
        ),
      ),
    );
  }
}

class _AttachedTagChip extends StatelessWidget {
  const _AttachedTagChip({
    required this.label,
    required this.definition,
    required this.onPressed,
    required this.onDeleted,
    this.maxButtonWidth = 190,
  });

  final String label;
  final TagDefinition? definition;
  final VoidCallback onPressed;
  final VoidCallback onDeleted;
  final double maxButtonWidth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final tagColor = definition?.color ?? colorScheme.tertiary;
    final containerColor = Color.alphaBlend(
      tagColor.withValues(alpha: 0.16),
      colorScheme.surfaceContainerHigh,
    );
    return _TagButtonGroupFrame(
      borderColor: tagColor.withValues(alpha: 0.42),
      children: [
        _TagGroupButton(
          label: label,
          icon: definition?.icon ?? Icons.sell_outlined,
          iconColor: tagColor,
          backgroundColor: containerColor,
          foregroundColor: colorScheme.onSurface,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(20),
          ),
          maxWidth: maxButtonWidth,
          onTap: onPressed,
        ),
        _TagGroupDivider(color: tagColor.withValues(alpha: 0.36)),
        _TagGroupIconButton(
          icon: Icons.close,
          tooltip: l10n.removeTag,
          backgroundColor: containerColor,
          foregroundColor: colorScheme.onSurfaceVariant,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(20),
          ),
          onTap: onDeleted,
        ),
      ],
    );
  }
}

class _TagLibraryChip extends StatelessWidget {
  const _TagLibraryChip({
    required this.label,
    required this.definition,
    required this.selected,
    required this.onSelected,
    required this.onEdit,
    required this.onDelete,
    this.maxButtonWidth = 190,
  });

  final String label;
  final TagDefinition? definition;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final double maxButtonWidth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final tagColor = definition?.color ?? colorScheme.tertiary;
    final borderColor = selected
        ? tagColor.withValues(alpha: 0.56)
        : tagColor.withValues(alpha: 0.24);
    final containerColor = selected
        ? Color.alphaBlend(
            tagColor.withValues(alpha: 0.14),
            colorScheme.surfaceContainerHigh,
          )
        : Color.alphaBlend(
            tagColor.withValues(alpha: 0.07),
            colorScheme.surfaceContainerLow,
          );
    return _TagButtonGroupFrame(
      borderColor: borderColor,
      children: [
        _TagGroupButton(
          label: label,
          icon: selected
              ? Icons.check
              : definition?.icon ?? Icons.sell_outlined,
          iconColor: tagColor,
          backgroundColor: containerColor,
          foregroundColor: colorScheme.onSurface,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(20),
          ),
          maxWidth: maxButtonWidth,
          onTap: () => onSelected(!selected),
        ),
        _TagGroupDivider(color: borderColor),
        _TagGroupIconButton(
          icon: Icons.edit_outlined,
          tooltip: l10n.editTag,
          backgroundColor: containerColor,
          foregroundColor: colorScheme.onSurfaceVariant,
          borderRadius: BorderRadius.zero,
          onTap: onEdit,
        ),
        _TagGroupDivider(color: borderColor),
        _TagGroupIconButton(
          icon: Icons.delete_outline,
          tooltip: l10n.deleteTag,
          backgroundColor: containerColor,
          foregroundColor: colorScheme.error,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(20),
          ),
          onTap: onDelete,
        ),
      ],
    );
  }
}

class _TagButtonGroupFrame extends StatelessWidget {
  const _TagButtonGroupFrame({
    required this.borderColor,
    required this.children,
  });

  final Color borderColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: borderColor)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _TagGroupDivider extends StatelessWidget {
  const _TagGroupDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 34, color: color);
  }
}

class _TagGroupButton extends StatelessWidget {
  const _TagGroupButton({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderRadius,
    required this.onTap,
    this.maxWidth = 190,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color foregroundColor;
  final BorderRadius borderRadius;
  final VoidCallback onTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      child: InkWell(
        borderRadius: borderRadius,
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 34, maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: iconColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagGroupIconButton extends StatelessWidget {
  const _TagGroupIconButton({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderRadius,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        child: InkWell(
          borderRadius: borderRadius,
          mouseCursor: SystemMouseCursors.click,
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 17, color: foregroundColor),
          ),
        ),
      ),
    );
  }
}

class _TagEditorSection extends StatelessWidget {
  const _TagEditorSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: ShapeDecoration(
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.title, required this.initialName});

  final String title;
  final String initialName;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      icon: const Icon(Icons.drive_file_rename_outline),
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.deviceName,
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: _ButtonLabel(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: _ButtonLabel(l10n.save)),
      ],
    );
  }
}

class _RestoreBackupDialog extends StatefulWidget {
  const _RestoreBackupDialog();

  @override
  State<_RestoreBackupDialog> createState() => _RestoreBackupDialogState();
}

class _RestoreBackupDialogState extends State<_RestoreBackupDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.restore_outlined),
      title: const Text('Khôi phục backup'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: _compactRoundedInputDecoration(
            context,
            labelText: 'Đường dẫn file backup',
            hintText: r'C:\...\opencb_backup_....json',
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const _ButtonLabel('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const _ButtonLabel('Khôi phục'),
        ),
      ],
    );
  }
}

class _AddPeerDialog extends StatefulWidget {
  const _AddPeerDialog();

  @override
  State<_AddPeerDialog> createState() => _AddPeerDialogState();
}

class _AddPeerDialogState extends State<_AddPeerDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _endpointController;
  late final TextEditingController _pairCodeController;
  late final TextEditingController _pairPayloadController;
  String? _payloadError;
  String? _parsedPeerId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Thiết bị LAN');
    _endpointController = TextEditingController(
      text: '192.168.1.10:$_defaultSyncPort',
    );
    _pairCodeController = TextEditingController();
    _pairPayloadController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _pairCodeController.dispose();
    _pairPayloadController.dispose();
    super.dispose();
  }

  void _applyPairPayload() {
    _applyPairPayloadText(_pairPayloadController.text);
  }

  void _applyPairPayloadText(String value) {
    final parsed = _parsePairPayload(value);
    if (parsed == null) {
      setState(() {
        _payloadError = context.l10n.pairPayloadInvalid;
      });
      return;
    }
    setState(() {
      _parsedPeerId = parsed.id;
      _nameController.text = parsed.name;
      _endpointController.text = parsed.endpoint;
      _pairCodeController.text = parsed.pairCode;
      _payloadError = null;
    });
  }

  Future<void> _scanQrPayload() async {
    final payload = await _showPairQrScanner(context);
    if (payload == null || !mounted) return;
    _pairPayloadController.text = payload;
    _applyPairPayloadText(payload);
  }

  void _submit() {
    final parsed = _parseEndpoint(_endpointController.text);
    if (parsed == null) {
      setState(() => _payloadError = context.l10n.hostPortInvalid);
      return;
    }
    final pairCode = _pairCodeController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    if (pairCode.length < 6) {
      setState(() => _payloadError = context.l10n.pairCodeTooShort);
      return;
    }
    Navigator.of(context).pop(
      SyncPeer(
        id: _parsedPeerId ?? 'peer-${DateTime.now().microsecondsSinceEpoch}',
        name: _nameController.text.trim().isEmpty
            ? 'Thiết bị LAN'
            : _nameController.text.trim(),
        host: parsed.$1,
        port: parsed.$2,
        pairCode: pairCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.addLanDevice),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 44,
                child: TextField(
                  controller: _pairPayloadController,
                  maxLines: 1,
                  decoration: _compactRoundedInputDecoration(
                    context,
                    labelText: l10n.pairPayload,
                    hintText: l10n.pastePairPayloadHint,
                  ).copyWith(errorText: _payloadError),
                  onSubmitted: (_) => _applyPairPayload(),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _applyPairPayload,
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      label: _ButtonLabel(l10n.applyPayload),
                    ),
                    if (Platform.isAndroid)
                      OutlinedButton.icon(
                        onPressed: _scanQrPayload,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: _OffsetButtonLabel(l10n.scanQr, y: 1),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: l10n.deviceName),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _endpointController,
                decoration: InputDecoration(
                  labelText: l10n.hostAndPort,
                  hintText: '192.168.1.10:47873',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pairCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l10n.peerPairCode,
                  hintText: 'VD: A1B2C3D4',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: _ButtonLabel(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: _ButtonLabel(l10n.add)),
      ],
    );
  }
}

class _ConfirmDiscoveredPeerDialog extends StatefulWidget {
  const _ConfirmDiscoveredPeerDialog({required this.device});

  final DiscoveredSyncDevice device;

  @override
  State<_ConfirmDiscoveredPeerDialog> createState() =>
      _ConfirmDiscoveredPeerDialogState();
}

class _ConfirmDiscoveredPeerDialogState
    extends State<_ConfirmDiscoveredPeerDialog> {
  late final TextEditingController _codeController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submitCode() {
    final code = _codeController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    if (code.length < 6) {
      setState(() => _errorText = context.l10n.enterCodeShownOnPeer);
      return;
    }
    Navigator.of(context).pop(widget.device.toPeer(pairCode: code));
  }

  Future<void> _scanQr() async {
    final payload = await _showPairQrScanner(context);
    if (payload == null || !mounted) return;
    final peer = _parsePairPayload(payload);
    if (peer == null) {
      setState(() => _errorText = context.l10n.invalidQrPairing);
      return;
    }
    if (peer.id != widget.device.id) {
      setState(() => _errorText = context.l10n.qrBelongsToOtherDevice);
      return;
    }
    Navigator.of(context).pop(peer);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      icon: const Icon(Icons.verified_user_outlined),
      title: Text(l10n.confirmConnection),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.device.name} - ${widget.device.endpoint}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.codeOnPeer,
                hintText: 'VD: A1B2C3D4',
                errorText: _errorText,
              ),
              onSubmitted: (_) => _submitCode(),
            ),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: _OffsetButtonLabel(l10n.scanQrInstead, y: 1),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: _ButtonLabel(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submitCode,
          child: _OffsetButtonLabel(l10n.connect, y: 1),
        ),
      ],
    );
  }
}

class _PairQrScannerDialog extends StatefulWidget {
  const _PairQrScannerDialog();

  @override
  State<_PairQrScannerDialog> createState() => _PairQrScannerDialogState();
}

class _PairQrScannerDialogState extends State<_PairQrScannerDialog> {
  late final MobileScannerController _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.trim().isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(value.trim());
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dialogWidth = math.min(
      math.max(MediaQuery.sizeOf(context).width - 88, 220.0),
      360.0,
    );
    return AlertDialog(
      title: Text(context.l10n.scanQr),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      content: SizedBox.square(
        dimension: dialogWidth,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.36),
                width: 1.5,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _handleDetect,
                  ),
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.72),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: _ButtonLabel(context.l10n.cancel),
        ),
      ],
    );
  }
}

Future<String?> _showPairQrScanner(BuildContext context) {
  if (!Platform.isAndroid) return Future.value(null);
  return showDialog<String>(
    context: context,
    builder: (context) => const _PairQrScannerDialog(),
  );
}

class _FileTransferPage extends StatelessWidget {
  const _FileTransferPage({
    required this.peers,
    required this.transfers,
    required this.selectedFiles,
    required this.selectedPeerIds,
    required this.statusFilter,
    required this.draggingFiles,
    required this.lanSyncEnabled,
    required this.onPickFiles,
    required this.onPickFolder,
    required this.onDropPaths,
    required this.onDragChanged,
    required this.onRemoveSelectedFile,
    required this.onClearSelectedFiles,
    required this.onTogglePeer,
    required this.onToggleAllPeers,
    required this.onSendSelected,
    required this.onStatusFilterChanged,
    required this.onClearTransferHistory,
    required this.onOpenTransferFile,
    required this.onCancelTransfer,
  });

  final List<SyncPeer> peers;
  final List<FileTransferRecord> transfers;
  final List<FileTransferFile> selectedFiles;
  final Set<String> selectedPeerIds;
  final FileTransferStatus? statusFilter;
  final bool draggingFiles;
  final bool lanSyncEnabled;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;
  final ValueChanged<List<String>> onDropPaths;
  final ValueChanged<bool> onDragChanged;
  final ValueChanged<FileTransferFile> onRemoveSelectedFile;
  final VoidCallback onClearSelectedFiles;
  final ValueChanged<String> onTogglePeer;
  final VoidCallback onToggleAllPeers;
  final VoidCallback onSendSelected;
  final ValueChanged<FileTransferStatus?> onStatusFilterChanged;
  final VoidCallback onClearTransferHistory;
  final ValueChanged<FileTransferRecord> onOpenTransferFile;
  final ValueChanged<String> onCancelTransfer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final mobile = MediaQuery.sizeOf(context).width < _mobileLayoutBreakpoint;
    final sortedTransfers = List<FileTransferRecord>.from(transfers)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final filteredTransfers = statusFilter == null
        ? sortedTransfers
        : sortedTransfers
              .where((transfer) => transfer.status == statusFilter)
              .toList();
    final visibleTransfers = filteredTransfers.take(40).toList();
    final finishedTransferCount = sortedTransfers
        .where((transfer) => !_isActiveTransferStatus(transfer.status))
        .length;
    final selectedOnlinePeers = peers
        .where((peer) => selectedPeerIds.contains(peer.id))
        .toList();
    final totalBytes = selectedFiles.fold<int>(
      0,
      (sum, file) => sum + file.size,
    );
    final contentSection = _SectionSurface(
      title: l10n.sendFilesContent,
      trailing: selectedFiles.isEmpty
          ? null
          : _MiniChip(
              label:
                  '${_localizedFileCount(l10n, selectedFiles.length)} - ${_formatBytes(totalBytes)}',
              timeTone: true,
            ),
      child: _FileTransferDropZone(
        dragging: draggingFiles,
        selectedFiles: selectedFiles,
        onPickFiles: onPickFiles,
        onPickFolder: onPickFolder,
        onDropPaths: onDropPaths,
        onDragChanged: onDragChanged,
        onRemoveSelectedFile: onRemoveSelectedFile,
        onClearSelectedFiles: onClearSelectedFiles,
      ),
    );
    final deviceSection = _SectionSurface(
      title: l10n.chooseReceivingDevice,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (peers.length > 1)
            TextButton(
              onPressed: onToggleAllPeers,
              child: Text(
                selectedPeerIds.containsAll(peers.map((peer) => peer.id))
                    ? l10n.deselect
                    : l10n.allItems,
              ),
            ),
        ],
      ),
      child: Column(
        children: [
          peers.isEmpty
              ? _FileTransferNotice(
                  icon: Icons.devices_other_outlined,
                  title: l10n.noOnlineDevices,
                  message: l10n.openPairedDevicesWifi,
                )
              : Column(
                  children: [
                    for (final peer in peers) ...[
                      _FileTransferPeerTile(
                        peer: peer,
                        selected: selectedPeerIds.contains(peer.id),
                        onToggle: () => onTogglePeer(peer.id),
                      ),
                      if (peer != peers.last) const SizedBox(height: 8),
                    ],
                  ],
                ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed:
                  selectedFiles.isNotEmpty && selectedOnlinePeers.isNotEmpty
                  ? onSendSelected
                  : null,
              icon: const Icon(Icons.send),
              label: Text(
                selectedOnlinePeers.length <= 1
                    ? l10n.send
                    : '${l10n.sendTo} ${_localizedDeviceCount(l10n, selectedOnlinePeers.length)}',
              ),
            ),
          ),
        ],
      ),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, mobile ? 104 : 20),
      children: [
        if (!lanSyncEnabled) ...[
          _FileTransferNotice(
            icon: Icons.sync_disabled,
            title: l10n.lanSyncOff,
            message: l10n.enableLanToSendFiles,
          ),
          const SizedBox(height: 12),
        ],
        if (mobile)
          Column(
            children: [
              contentSection,
              const SizedBox(height: 14),
              deviceSection,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: contentSection),
              const SizedBox(width: 14),
              Expanded(flex: 5, child: deviceSection),
            ],
          ),
        const SizedBox(height: 14),
        _SectionSurface(
          title: l10n.sendReceiveActivity,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniChip(
                label: _localizedItemCount(l10n, filteredTransfers.length),
                timeTone: true,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l10n.clearTransferHistory,
                onPressed: finishedTransferCount > 0
                    ? onClearTransferHistory
                    : null,
                icon: const Icon(Icons.clear_all),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FileTransferStatusToolbar(
                selectedStatus: statusFilter,
                onChanged: onStatusFilterChanged,
              ),
              const SizedBox(height: 10),
              visibleTransfers.isEmpty
                  ? _FileTransferNotice(
                      icon: Icons.swap_horiz,
                      title: statusFilter == null
                          ? l10n.noTransfers
                          : '${l10n.noTransferWithStatus} ${_fileTransferStatusLabel(l10n, statusFilter!).toLowerCase()}',
                      message: statusFilter == null
                          ? l10n.chooseOnlineDeviceToSend
                          : l10n.changeFilterToViewTransfers,
                    )
                  : Column(
                      children: [
                        for (final transfer in visibleTransfers) ...[
                          _FileTransferRecordTile(
                            transfer: transfer,
                            onOpenFile: _canOpenFileTransferLocally(transfer)
                                ? () => onOpenTransferFile(transfer)
                                : null,
                            onCancel: _isActiveTransferStatus(transfer.status)
                                ? () => onCancelTransfer(transfer.id)
                                : null,
                          ),
                          if (transfer != visibleTransfers.last)
                            Divider(color: colorScheme.outlineVariant),
                        ],
                      ],
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionSurface extends StatelessWidget {
  const _SectionSurface({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _FileTransferNotice extends StatelessWidget {
  const _FileTransferNotice({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTransferStatusToolbar extends StatelessWidget {
  const _FileTransferStatusToolbar({
    required this.selectedStatus,
    required this.onChanged,
  });

  final FileTransferStatus? selectedStatus;
  final ValueChanged<FileTransferStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = <({FileTransferStatus? status, String label, IconData icon})>[
      (status: null, label: l10n.allItems, icon: Icons.all_inbox_outlined),
      (
        status: FileTransferStatus.completed,
        label: l10n.completed,
        icon: Icons.check_circle_outline,
      ),
      (
        status: FileTransferStatus.rejected,
        label: l10n.rejected,
        icon: Icons.block_outlined,
      ),
      (
        status: FileTransferStatus.failed,
        label: l10n.error,
        icon: Icons.error_outline,
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _FileTransferStatusButton(
              label: items[index].label,
              icon: items[index].icon,
              selected: selectedStatus == items[index].status,
              onPressed: () => onChanged(items[index].status),
            ),
            if (index != items.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _FileTransferStatusButton extends StatelessWidget {
  const _FileTransferStatusButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = selected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerHighest;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    return Material(
      color: background,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: SystemMouseCursors.click,
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileTransferDropZone extends StatelessWidget {
  const _FileTransferDropZone({
    required this.dragging,
    required this.selectedFiles,
    required this.onPickFiles,
    required this.onPickFolder,
    required this.onDropPaths,
    required this.onDragChanged,
    required this.onRemoveSelectedFile,
    required this.onClearSelectedFiles,
  });

  final bool dragging;
  final List<FileTransferFile> selectedFiles;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;
  final ValueChanged<List<String>> onDropPaths;
  final ValueChanged<bool> onDragChanged;
  final ValueChanged<FileTransferFile> onRemoveSelectedFile;
  final VoidCallback onClearSelectedFiles;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mobile = MediaQuery.sizeOf(context).width < _mobileLayoutBreakpoint;
    final useMobileHeader = Platform.isAndroid || mobile;
    final l10n = context.l10n;
    final description = selectedFiles.isEmpty
        ? Platform.isWindows
              ? l10n.dragFilesHere
              : l10n.chooseFileToSend
        : Platform.isAndroid
        ? l10n.addMoreFiles
        : l10n.addMoreFilesOrFolders;
    final pickButtonStyle = OutlinedButton.styleFrom(
      fixedSize: const Size.fromHeight(40),
      minimumSize: const Size(0, 40),
      visualDensity: VisualDensity.standard,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(height: 1.0),
    );
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dragging
            ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dragging
              ? colorScheme.secondary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (useMobileHeader)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onPickFiles,
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: _OffsetButtonLabel(l10n.chooseFile, y: 1),
                  style: pickButtonStyle,
                ),
              ],
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.file_upload_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: onPickFiles,
                  icon: const Icon(Icons.attach_file),
                  label: _OffsetButtonLabel(l10n.chooseFile, y: 1),
                  style: pickButtonStyle,
                ),
                if (!Platform.isAndroid)
                  OutlinedButton.icon(
                    onPressed: onPickFolder,
                    icon: const Icon(Icons.folder_open),
                    label: _ButtonLabel(l10n.chooseFolder),
                    style: pickButtonStyle,
                  ),
              ],
            ),
          ],
          if (selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: colorScheme.outlineVariant),
            const SizedBox(height: 4),
            _SelectedTransferFilesInlineList(
              files: selectedFiles,
              onRemove: onRemoveSelectedFile,
              onClear: onClearSelectedFiles,
            ),
          ],
        ],
      ),
    );

    if (!Platform.isWindows) return content;
    return DropTarget(
      onDragEntered: (_) => onDragChanged(true),
      onDragExited: (_) => onDragChanged(false),
      onDragDone: (details) {
        onDragChanged(false);
        onDropPaths(
          details.files
              .map((file) => file.path)
              .where((path) => path.trim().isNotEmpty)
              .toList(),
        );
      },
      child: content,
    );
  }
}

class _SelectedTransferFilesInlineList extends StatefulWidget {
  const _SelectedTransferFilesInlineList({
    required this.files,
    required this.onRemove,
    required this.onClear,
  });

  final List<FileTransferFile> files;
  final ValueChanged<FileTransferFile> onRemove;
  final VoidCallback onClear;

  @override
  State<_SelectedTransferFilesInlineList> createState() =>
      _SelectedTransferFilesInlineListState();
}

class _SelectedTransferFilesInlineListState
    extends State<_SelectedTransferFilesInlineList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final shouldScroll = widget.files.length > 4;
    final fileList = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final file in widget.files)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              file.relativePath == null
                  ? Icons.insert_drive_file_outlined
                  : Icons.folder_outlined,
              color: colorScheme.onSurfaceVariant,
            ),
            title: Text(
              file.displayPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_formatBytes(file.size)),
            trailing: IconButton(
              tooltip: l10n.removeFile,
              onPressed: () => widget.onRemove(file),
              icon: const Icon(Icons.close),
            ),
          ),
      ],
    );
    return Column(
      children: [
        Row(
          children: [
            Text(
              l10n.selectedFiles,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: widget.onClear,
              icon: const Icon(Icons.clear_all),
              label: Text(l10n.clearList),
            ),
          ],
        ),
        if (shouldScroll)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 224),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: fileList,
              ),
            ),
          )
        else
          fileList,
      ],
    );
  }
}

class _FileTransferPeerTile extends StatelessWidget {
  const _FileTransferPeerTile({
    required this.peer,
    required this.selected,
    required this.onToggle,
  });

  final SyncPeer peer;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.secondaryContainer.withValues(alpha: 0.62)
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onToggle,
        mouseCursor: SystemMouseCursors.click,
        leading: CircleAvatar(
          backgroundColor: selected
              ? colorScheme.primaryContainer
              : Color.alphaBlend(
                  colorScheme.primary.withValues(alpha: 0.10),
                  colorScheme.surfaceContainerHigh,
                ),
          foregroundColor: selected
              ? colorScheme.onPrimaryContainer
              : colorScheme.primary,
          child: const Icon(Icons.devices_other),
        ),
        title: Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${peer.host}:${peer.filePort}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Checkbox(value: selected, onChanged: (_) => onToggle()),
      ),
    );
  }
}

class _FileTransferRecordTile extends StatelessWidget {
  const _FileTransferRecordTile({
    required this.transfer,
    this.onOpenFile,
    this.onCancel,
  });

  final FileTransferRecord transfer;
  final VoidCallback? onOpenFile;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final fileLabel = transfer.files.length == 1
        ? transfer.files.first.displayPath
        : _localizedFileCount(l10n, transfer.files.length);
    final directionLabel = transfer.direction == FileTransferDirection.send
        ? l10n.sendTo
        : l10n.receiveFrom;
    final supportingPath = transfer.error ?? transfer.saveDirectory;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                transfer.direction == FileTransferDirection.send
                    ? Icons.file_upload_outlined
                    : Icons.file_download_outlined,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$directionLabel ${transfer.peerName} - ${_formatBytes(transfer.totalBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _FileTransferStatusBadge(status: transfer.status),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: transfer.progress,
              minHeight: 7,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: switch (transfer.status) {
                FileTransferStatus.failed => colorScheme.error,
                FileTransferStatus.rejected ||
                FileTransferStatus.canceled => colorScheme.tertiary,
                FileTransferStatus.completed => colorScheme.primary,
                FileTransferStatus.waiting ||
                FileTransferStatus.sending ||
                FileTransferStatus.receiving => colorScheme.secondary,
              },
            ),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_formatBytes(transfer.transferredBytes)} / ${_formatBytes(transfer.totalBytes)}'
                      '${_isActiveTransferStatus(transfer.status) ? ' • ${_formatTransferSpeed(transfer.speedBytesPerSecond, l10n)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (supportingPath != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        supportingPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: transfer.error != null
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onOpenFile != null || onCancel != null) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onOpenFile != null)
                      IconButton(
                        tooltip: l10n.openFile,
                        onPressed: onOpenFile,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.open_in_new),
                      ),
                    if (onCancel != null)
                      IconButton(
                        tooltip: l10n.cancel,
                        onPressed: onCancel,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FileTransferStatusBadge extends StatelessWidget {
  const _FileTransferStatusBadge({required this.status});

  final FileTransferStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (baseColor, contentColor) = switch (status) {
      FileTransferStatus.failed => (colorScheme.error, colorScheme.error),
      FileTransferStatus.rejected || FileTransferStatus.canceled => (
        colorScheme.tertiary,
        colorScheme.tertiary,
      ),
      FileTransferStatus.waiting ||
      FileTransferStatus.sending ||
      FileTransferStatus.receiving => (
        colorScheme.secondary,
        colorScheme.secondary,
      ),
      FileTransferStatus.completed => (
        colorScheme.primary,
        colorScheme.primary,
      ),
    };
    return _M3Badge(
      label: _fileTransferStatusLabel(context.l10n, status),
      tone: _M3BadgeTone.primary,
      horizontalPadding: 8,
      tightText: true,
      containerColorOverride: Color.alphaBlend(
        baseColor.withValues(alpha: 0.10),
        colorScheme.surfaceContainerHigh,
      ),
      contentColorOverride: contentColor,
      iconColorOverride: contentColor,
      borderColorOverride: baseColor.withValues(alpha: 0.18),
    );
  }
}

class _DevicesPage extends StatelessWidget {
  const _DevicesPage({
    required this.peers,
    required this.discoveredDevices,
    required this.identity,
    required this.lanSyncEnabled,
    required this.syncHost,
    required this.syncPort,
    required this.syncError,
    required this.onAddPeer,
    required this.onScanPairQr,
    required this.onCopyPairPayload,
    required this.onRenameLocalDevice,
    required this.onAddDiscoveredPeer,
    required this.onSyncPeer,
    required this.onTestPeer,
    required this.onRenamePeer,
    required this.onRemovePeer,
  });

  final List<SyncPeer> peers;
  final List<DiscoveredSyncDevice> discoveredDevices;
  final LocalSyncIdentity identity;
  final bool lanSyncEnabled;
  final String syncHost;
  final int syncPort;
  final String? syncError;
  final VoidCallback onAddPeer;
  final VoidCallback? onScanPairQr;
  final VoidCallback onCopyPairPayload;
  final VoidCallback onRenameLocalDevice;
  final ValueChanged<DiscoveredSyncDevice> onAddDiscoveredPeer;
  final ValueChanged<SyncPeer> onSyncPeer;
  final ValueChanged<SyncPeer> onTestPeer;
  final ValueChanged<SyncPeer> onRenamePeer;
  final ValueChanged<SyncPeer> onRemovePeer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mobile = MediaQuery.sizeOf(context).width < _mobileLayoutBreakpoint;
    final discoveredById = {
      for (final device in discoveredDevices) device.id: device,
    };
    final unpairedDevices = discoveredDevices
        .where((device) => !peers.any((peer) => peer.id == device.id))
        .toList();
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, mobile ? 112 : 24),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final leftColumn = Column(
                children: [
                  _LocalDeviceRow(
                    identity: identity,
                    syncHost: syncHost,
                    syncPort: syncPort,
                    syncError: syncError,
                    lanSyncEnabled: lanSyncEnabled,
                    onRename: onRenameLocalDevice,
                  ),
                  const SizedBox(height: 16),
                  _PairQrCard(
                    payload: _buildPairPayload(
                      identity,
                      syncPort,
                      host: syncHost,
                    ),
                    onCopyPairPayload: onCopyPairPayload,
                  ),
                ],
              );
              final rightColumn = Column(
                children: [
                  _PairingActionsCard(
                    onAddPeer: onAddPeer,
                    onScanPairQr: onScanPairQr,
                  ),
                  const SizedBox(height: 16),
                  _DiscoveredDevicesCard(
                    devices: unpairedDevices,
                    onAdd: onAddDiscoveredPeer,
                  ),
                  const SizedBox(height: 16),
                  _TrustedDevicesCard(
                    peers: peers,
                    discoveredById: discoveredById,
                    onSyncPeer: onSyncPeer,
                    onTestPeer: onTestPeer,
                    onRenamePeer: onRenamePeer,
                    onRemovePeer: onRemovePeer,
                    onAddPeer: onAddPeer,
                  ),
                ],
              );

              if (constraints.maxWidth < 780) {
                return Column(
                  children: [
                    leftColumn,
                    const SizedBox(height: 16),
                    rightColumn,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: leftColumn),
                  const SizedBox(width: 16),
                  Expanded(flex: 6, child: rightColumn),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PairingActionsCard extends StatelessWidget {
  const _PairingActionsCard({
    required this.onAddPeer,
    required this.onScanPairQr,
  });

  final VoidCallback onAddPeer;
  final VoidCallback? onScanPairQr;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final scanQr = onScanPairQr;
    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (scanQr == null)
          FilledButton.tonalIcon(
            onPressed: onAddPeer,
            icon: const Icon(Icons.keyboard_alt_outlined),
            label: _ButtonLabel(l10n.enterPayload),
          )
        else
          FilledButton.tonalIcon(
            onPressed: scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: _OffsetButtonLabel(l10n.scanQr, y: 1),
          ),
      ],
    );
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.add_link, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.devicePairing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              flex: 0,
              child: Align(
                alignment: Alignment.centerRight,
                child: actionButtons,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustedDevicesCard extends StatelessWidget {
  const _TrustedDevicesCard({
    required this.peers,
    required this.discoveredById,
    required this.onSyncPeer,
    required this.onTestPeer,
    required this.onRenamePeer,
    required this.onRemovePeer,
    required this.onAddPeer,
  });

  final List<SyncPeer> peers;
  final Map<String, DiscoveredSyncDevice> discoveredById;
  final ValueChanged<SyncPeer> onSyncPeer;
  final ValueChanged<SyncPeer> onTestPeer;
  final ValueChanged<SyncPeer> onRenamePeer;
  final ValueChanged<SyncPeer> onRemovePeer;
  final VoidCallback onAddPeer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return _SettingsCard(
      icon: Icons.verified_user_outlined,
      title: l10n.pairedDevices,
      subtitle: '',
      trailing: _MiniChip(
        label: _localizedDeviceCount(l10n, peers.length),
        labelYOffset: 0,
      ),
      child: peers.isEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: ShapeDecoration(
                color: colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.noPairedDevices,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.pairedDeviceHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: onAddPeer,
                      icon: const Icon(Icons.add_link),
                      label: _ButtonLabel(l10n.addDevice),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final peer in peers) ...[
                  _DeviceRow(
                    peer: peer,
                    discoveredDevice: discoveredById[peer.id],
                    onSync: () => onSyncPeer(peer),
                    onTest: () => onTestPeer(peer),
                    onRename: () => onRenamePeer(peer),
                    onRemove: () => onRemovePeer(peer),
                  ),
                  if (peer != peers.last) const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }
}

class _SettingsPageSlideSwitcher extends StatefulWidget {
  const _SettingsPageSlideSwitcher({
    required this.showUpdatePage,
    required this.mainPage,
    required this.updatePage,
  });

  final bool showUpdatePage;
  final Widget mainPage;
  final Widget updatePage;

  @override
  State<_SettingsPageSlideSwitcher> createState() =>
      _SettingsPageSlideSwitcherState();
}

class _SettingsPageSlideSwitcherState extends State<_SettingsPageSlideSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 390),
      reverseDuration: const Duration(milliseconds: 340),
      value: widget.showUpdatePage ? 1 : 0,
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _SettingsPageSlideSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showUpdatePage == oldWidget.showUpdatePage) return;
    if (widget.showUpdatePage) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, _) {
          final value = _curve.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              FractionalTranslation(
                translation: Offset(-0.12 * value, 0),
                child: Opacity(
                  opacity: 1 - (0.08 * value),
                  child: IgnorePointer(
                    ignoring: value > 0.02,
                    child: widget.mainPage,
                  ),
                ),
              ),
              FractionalTranslation(
                translation: Offset(1 - value, 0),
                child: IgnorePointer(
                  ignoring: value < 0.98,
                  child: widget.updatePage,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.capturePaused,
    required this.storagePath,
    required this.clipboardSettings,
    required this.sourceSuggestions,
    required this.themeMode,
    required this.themePreset,
    required this.language,
    required this.androidIgnoringBatteryOptimizations,
    required this.onToggleCapture,
    required this.onRetentionLimitChanged,
    required this.onClipboardSettingsChanged,
    required this.onAddExcludedSource,
    required this.onRemoveExcludedSource,
    required this.onThemeModeChanged,
    required this.onThemePresetChanged,
    required this.onLanguageChanged,
    required this.onOpenDataDirectory,
    required this.onExportBackup,
    required this.onRestoreBackup,
    required this.onResetClipboardHistory,
    this.onOpenAndroidNotificationSettings,
    this.onToggleAndroidBatteryOptimizationBypass,
    this.onOpenDevices,
    required this.onOpenUpdates,
  });

  final bool capturePaused;
  final String storagePath;
  final ClipboardSettings clipboardSettings;
  final List<String> sourceSuggestions;
  final ThemeMode themeMode;
  final M3ThemePreset themePreset;
  final AppLanguage language;
  final bool androidIgnoringBatteryOptimizations;
  final VoidCallback onToggleCapture;
  final ValueChanged<int> onRetentionLimitChanged;
  final ValueChanged<ClipboardSettings> onClipboardSettingsChanged;
  final ValueChanged<String> onAddExcludedSource;
  final ValueChanged<String> onRemoveExcludedSource;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<M3ThemePreset> onThemePresetChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onOpenDataDirectory;
  final VoidCallback onExportBackup;
  final VoidCallback onRestoreBackup;
  final VoidCallback onResetClipboardHistory;
  final VoidCallback? onOpenAndroidNotificationSettings;
  final ValueChanged<bool>? onToggleAndroidBatteryOptimizationBypass;
  final VoidCallback? onOpenDevices;
  final VoidCallback onOpenUpdates;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mobile = MediaQuery.sizeOf(context).width < _mobileLayoutBreakpoint;
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, mobile ? 112 : 24),
        children: [
          _AppUpdateSummaryCard(
            versionLabel: _appVersionLabel,
            onTap: onOpenUpdates,
          ),
          const SizedBox(height: 16),
          if (onOpenDevices != null) ...[
            _SettingsNavigationRow(
              icon: Icons.devices_other_outlined,
              title: context.l10n.devicesLan,
              subtitle: context.l10n.settingsDevicesSubtitle,
              onTap: onOpenDevices!,
            ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              Widget buildClipboardSettingsPanel() => _ClipboardSettingsPanel(
                settings: clipboardSettings,
                capturePaused: capturePaused,
                sourceSuggestions: sourceSuggestions,
                onToggleCapture: onToggleCapture,
                onRetentionLimitChanged: onRetentionLimitChanged,
                onSettingsChanged: onClipboardSettingsChanged,
                onAddExcludedSource: onAddExcludedSource,
                onRemoveExcludedSource: onRemoveExcludedSource,
                onOpenAndroidNotificationSettings:
                    onOpenAndroidNotificationSettings,
                androidIgnoringBatteryOptimizations:
                    androidIgnoringBatteryOptimizations,
                onToggleAndroidBatteryOptimizationBypass:
                    onToggleAndroidBatteryOptimizationBypass,
              );
              Widget buildThemeSettingsPanel() => _ThemeSettingsPanel(
                themeMode: themeMode,
                selectedPreset: themePreset,
                language: language,
                onThemeModeChanged: onThemeModeChanged,
                onThemePresetChanged: onThemePresetChanged,
                onLanguageChanged: onLanguageChanged,
              );

              final leftColumn = buildClipboardSettingsPanel();
              final rightColumn = buildThemeSettingsPanel();
              if (constraints.maxWidth < 900) {
                return Column(
                  children: [
                    buildThemeSettingsPanel(),
                    const SizedBox(height: 16),
                    buildClipboardSettingsPanel(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: leftColumn),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: rightColumn),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AppUpdateSummaryCard extends StatelessWidget {
  const _AppUpdateSummaryCard({
    required this.versionLabel,
    required this.onTap,
  });

  final String versionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              const _OpenCbLogoMark(size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OpenCB $versionLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.openUpdateSettings,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateSettingsPage extends StatelessWidget {
  const _UpdateSettingsPage({
    required this.currentVersion,
    required this.autoCheckUpdates,
    required this.checking,
    required this.latestMessage,
    required this.onBack,
    required this.onCheckNow,
    required this.onToggleAutoCheck,
    required this.onOpenLandingPage,
    required this.onOpenGithub,
  });

  final String currentVersion;
  final bool autoCheckUpdates;
  final bool checking;
  final String? latestMessage;
  final VoidCallback onBack;
  final VoidCallback onCheckNow;
  final ValueChanged<bool> onToggleAutoCheck;
  final VoidCallback onOpenLandingPage;
  final VoidCallback onOpenGithub;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final mobile = MediaQuery.sizeOf(context).width < _mobileLayoutBreakpoint;
    final pagePadding = EdgeInsets.fromLTRB(24, mobile ? 0 : 18, 24, 24);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!mobile) ...[
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: onBack,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: l10n.back,
              ),
              const SizedBox(width: 10),
              Text(
                l10n.updateApp,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final mobileIntro = Card.filled(
              margin: EdgeInsets.zero,
              color: colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    const _OpenCbLogoMark(size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OpenCB $currentVersion',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (latestMessage != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              latestMessage!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: checking ? null : onCheckNow,
                      icon: _DirectorySyncIcon(checking: checking),
                      tooltip: l10n.checkUpdates,
                    ),
                  ],
                ),
              ),
            );
            final desktopIntro = _SettingsCard(
              icon: Icons.info_outline,
              title: l10n.currentVersion,
              subtitle: '',
              trailing: FilledButton.tonalIcon(
                onPressed: checking ? null : onCheckNow,
                icon: _DirectorySyncIcon(checking: checking),
                label: _ButtonLabel(checking ? l10n.checking : l10n.check),
              ),
              child: Row(
                children: [
                  const _OpenCbLogoMark(size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OpenCB $currentVersion',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (latestMessage != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            latestMessage!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
            final mobileUpdateControls = Column(
              children: [
                _UpdateSettingsSimpleRow(
                  title: l10n.autoCheckUpdates,
                  trailing: IgnorePointer(
                    child: Switch(
                      value: autoCheckUpdates,
                      onChanged: onToggleAutoCheck,
                    ),
                  ),
                  onTap: () => onToggleAutoCheck(!autoCheckUpdates),
                ),
                const SizedBox(height: 8),
                _UpdateSettingsSimpleRow(
                  title: l10n.landingPage,
                  onTap: onOpenLandingPage,
                ),
                const SizedBox(height: 8),
                _UpdateSettingsSimpleRow(title: 'GitHub', onTap: onOpenGithub),
              ],
            );
            final desktopUpdateControls = _SettingsCard(
              icon: Icons.system_update_alt,
              title: l10n.checkUpdates,
              subtitle: '',
              child: Column(
                children: [
                  _SettingsSwitchRow(
                    icon: Icons.notifications_active_outlined,
                    title: l10n.autoCheckUpdates,
                    subtitle: autoCheckUpdates
                        ? l10n.autoCheckUpdatesEnabled
                        : l10n.autoCheckUpdatesDisabled,
                    value: autoCheckUpdates,
                    onChanged: onToggleAutoCheck,
                  ),
                  const SizedBox(height: 8),
                  _SettingsNavigationRow(
                    icon: Icons.public,
                    title: l10n.landingPage,
                    subtitle: _landingPageUrl,
                    onTap: onOpenLandingPage,
                  ),
                  const SizedBox(height: 8),
                  _SettingsNavigationRow(
                    icon: Icons.code,
                    title: 'GitHub',
                    subtitle: _githubRepoUrl,
                    onTap: onOpenGithub,
                  ),
                ],
              ),
            );
            if (mobile) {
              return Column(
                children: [
                  mobileIntro,
                  const SizedBox(height: 16),
                  mobileUpdateControls,
                ],
              );
            }
            if (!wide) {
              return Column(
                children: [
                  desktopIntro,
                  const SizedBox(height: 16),
                  desktopUpdateControls,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: desktopIntro),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: desktopUpdateControls),
              ],
            );
          },
        ),
      ],
    );
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: ListView(padding: pagePadding, children: [content]),
    );
  }
}

class _UpdateSettingsSimpleRow extends StatelessWidget {
  const _UpdateSettingsSimpleRow({
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectorySyncIcon extends StatefulWidget {
  const _DirectorySyncIcon({required this.checking});

  final bool checking;

  @override
  State<_DirectorySyncIcon> createState() => _DirectorySyncIconState();
}

class _DirectorySyncIconState extends State<_DirectorySyncIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.checking) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _DirectorySyncIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checking == oldWidget.checking) return;
    if (widget.checking) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    final icon = CustomPaint(
      painter: _DirectorySyncIconPainter(color: color ?? Colors.black),
      size: const Size.square(24),
    );
    return SizedBox.square(
      dimension: 24,
      child: widget.checking
          ? RotationTransition(turns: _controller, child: icon)
          : icon,
    );
  }
}

class _DirectorySyncIconPainter extends CustomPainter {
  const _DirectorySyncIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 960;
    final path = _directorySyncPath();
    canvas.save();
    canvas.scale(scale, scale);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  Path _directorySyncPath() {
    double y(double value) => value + 960;
    return Path()
      ..moveTo(212, y(-239))
      ..relativeQuadraticBezierTo(-43, -48, -67.5, -110)
      ..quadraticBezierTo(120, y(-411), 120, y(-480))
      ..relativeQuadraticBezierTo(0, -150, 105, -255)
      ..quadraticBezierTo(330, y(-840), 480, y(-840))
      ..relativeLineTo(0, -80)
      ..relativeLineTo(200, 150)
      ..relativeLineTo(-200, 150)
      ..relativeLineTo(0, -80)
      ..relativeQuadraticBezierTo(-91, 0, -155.5, 64.5)
      ..quadraticBezierTo(260, y(-571), 260, y(-480))
      ..relativeQuadraticBezierTo(0, 46, 17.5, 86)
      ..quadraticBezierTo(295, y(-354), 325, y(-324))
      ..relativeLineTo(-113, 85)
      ..close()
      ..moveTo(480, y(-40))
      ..lineTo(280, y(-190))
      ..relativeLineTo(200, -150)
      ..relativeLineTo(0, 80)
      ..relativeQuadraticBezierTo(91, 0, 155.5, -64.5)
      ..quadraticBezierTo(700, y(-389), 700, y(-480))
      ..relativeQuadraticBezierTo(0, -46, -17.5, -86)
      ..quadraticBezierTo(665, y(-606), 635, y(-636))
      ..relativeLineTo(113, -85)
      ..relativeQuadraticBezierTo(43, 48, 67.5, 110)
      ..quadraticBezierTo(840, y(-549), 840, y(-480))
      ..relativeQuadraticBezierTo(0, 150, -105, 255)
      ..quadraticBezierTo(630, y(-120), 480, y(-120))
      ..relativeLineTo(0, 80)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _DirectorySyncIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                final titleBlock = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icon, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
                if (trailing == null) return titleBlock;
                if (compact) {
                  if (trailing is _MiniChip) {
                    return Row(
                      children: [
                        Expanded(child: titleBlock),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: trailing!,
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleBlock,
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerRight, child: trailing!),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: titleBlock),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing!,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

InputDecoration _compactRoundedInputDecoration(
  BuildContext context, {
  required String labelText,
  String? hintText,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final borderRadius = BorderRadius.circular(18);
  final borderSide = BorderSide(color: colorScheme.outlineVariant);
  return InputDecoration(
    isDense: true,
    labelText: labelText,
    hintText: hintText,
    filled: true,
    fillColor: colorScheme.surfaceContainerHigh,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    border: OutlineInputBorder(borderRadius: borderRadius),
    enabledBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: borderSide,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    ),
  );
}

class _ThemeSettingsPanel extends StatelessWidget {
  const _ThemeSettingsPanel({
    required this.themeMode,
    required this.selectedPreset,
    required this.language,
    required this.onThemeModeChanged,
    required this.onThemePresetChanged,
    required this.onLanguageChanged,
  });

  final ThemeMode themeMode;
  final M3ThemePreset selectedPreset;
  final AppLanguage language;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<M3ThemePreset> onThemePresetChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SettingsCard(
      icon: Icons.palette_outlined,
      title: l10n.appearance,
      subtitle: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.displayMode,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Center(
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_outlined),
                  label: _FittedOneLineLabel(l10n.light),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto_outlined),
                  label: _FittedOneLineLabel(l10n.system, minWidth: 54),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_outlined),
                  label: _FittedOneLineLabel(l10n.dark),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) {
                onThemeModeChanged(selection.first);
              },
            ),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.language,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Center(
            child: SegmentedButton<AppLanguage>(
              segments: [
                ButtonSegment(
                  value: AppLanguage.system,
                  icon: const Icon(Icons.language_outlined),
                  label: _FittedOneLineLabel(l10n.languageSystem, minWidth: 54),
                ),
                ButtonSegment(
                  value: AppLanguage.vi,
                  icon: const Icon(Icons.translate_outlined),
                  label: _FittedOneLineLabel(
                    l10n.languageVietnamese,
                    minWidth: 56,
                  ),
                ),
                ButtonSegment(
                  value: AppLanguage.en,
                  icon: const Icon(Icons.translate),
                  label: _FittedOneLineLabel(
                    l10n.languageEnglish,
                    minWidth: 56,
                  ),
                ),
              ],
              selected: {language},
              onSelectionChanged: (selection) {
                onLanguageChanged(selection.first);
              },
            ),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.materialYouPalette,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final mobile =
                  MediaQuery.sizeOf(context).width < _mobileLayoutBreakpoint;
              final compactChips = mobile || Platform.isAndroid;
              const columns = 2;
              final spacing = compactChips ? 4.0 : 6.0;
              final chipWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: compactChips ? 4 : 6,
                children: [
                  for (final preset in _m3ThemePresets)
                    SizedBox(
                      width: chipWidth,
                      child: FilterChip(
                        selected: selectedPreset.id == preset.id,
                        showCheckmark: false,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: compactChips
                            ? const VisualDensity(horizontal: -2, vertical: -3)
                            : VisualDensity.standard,
                        padding: EdgeInsets.symmetric(
                          horizontal: compactChips ? 6 : 8,
                          vertical: compactChips ? 2 : 4,
                        ),
                        avatar: _ThemeSwatch(color: preset.seedColor),
                        label: SizedBox(
                          width: double.infinity,
                          child: Text(
                            _themePresetName(context.l10n, preset),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onSelected: (_) => onThemePresetChanged(preset),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ClipboardSettingsPanel extends StatefulWidget {
  const _ClipboardSettingsPanel({
    required this.settings,
    required this.capturePaused,
    required this.sourceSuggestions,
    required this.onToggleCapture,
    required this.onRetentionLimitChanged,
    required this.onSettingsChanged,
    required this.onAddExcludedSource,
    required this.onRemoveExcludedSource,
    required this.androidIgnoringBatteryOptimizations,
    this.onOpenAndroidNotificationSettings,
    this.onToggleAndroidBatteryOptimizationBypass,
  });

  final ClipboardSettings settings;
  final bool capturePaused;
  final List<String> sourceSuggestions;
  final VoidCallback onToggleCapture;
  final ValueChanged<int> onRetentionLimitChanged;
  final ValueChanged<ClipboardSettings> onSettingsChanged;
  final ValueChanged<String> onAddExcludedSource;
  final ValueChanged<String> onRemoveExcludedSource;
  final bool androidIgnoringBatteryOptimizations;
  final VoidCallback? onOpenAndroidNotificationSettings;
  final ValueChanged<bool>? onToggleAndroidBatteryOptimizationBypass;

  @override
  State<_ClipboardSettingsPanel> createState() =>
      _ClipboardSettingsPanelState();
}

class _ClipboardSettingsPanelState extends State<_ClipboardSettingsPanel> {
  late final TextEditingController _excludedSourceController;
  late int _pendingRetentionLimit;

  @override
  void initState() {
    super.initState();
    _excludedSourceController = TextEditingController();
    _pendingRetentionLimit = widget.settings.retentionLimit;
  }

  @override
  void didUpdateWidget(covariant _ClipboardSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settings.retentionLimit != oldWidget.settings.retentionLimit) {
      _pendingRetentionLimit = widget.settings.retentionLimit;
    }
  }

  @override
  void dispose() {
    _excludedSourceController.dispose();
    super.dispose();
  }

  void _addSource(String value) {
    final source = value.trim();
    if (source.isEmpty) return;
    widget.onAddExcludedSource(source);
    _excludedSourceController.clear();
  }

  Future<void> _recordHotKey() async {
    final result = await showDialog<QuickOpenHotKey>(
      context: context,
      builder: (context) =>
          _HotKeyRecorderDialog(initialHotKey: widget.settings.quickOpenHotKey),
    );
    if (result == null) return;
    widget.onSettingsChanged(widget.settings.copyWith(quickOpenHotKey: result));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final retentionValue = _pendingRetentionLimit.toDouble();
    final isAndroid = Platform.isAndroid;
    return Column(
      children: [
        if (!isAndroid) ...[
          _SettingsSwitchRow(
            icon: widget.capturePaused
                ? Icons.pause_circle_outline
                : Icons.check_circle_outline,
            title: l10n.captureClipboard,
            subtitle: widget.capturePaused
                ? l10n.capturePausedSubtitle
                : l10n.captureEnabledSubtitle,
            value: !widget.capturePaused,
            onChanged: (_) => widget.onToggleCapture(),
          ),
          const SizedBox(height: 8),
        ],
        _SettingsSwitchRow(
          icon: Icons.notes,
          title: l10n.textAndUrl,
          subtitle: l10n.textAndUrlSubtitle,
          value: widget.settings.captureText,
          onChanged: (value) => widget.onSettingsChanged(
            widget.settings.copyWith(captureText: value),
          ),
        ),
        const SizedBox(height: 8),
        if (!isAndroid) ...[
          _SettingsSwitchRow(
            icon: Icons.image_outlined,
            title: l10n.images,
            subtitle: l10n.imagesSubtitle,
            value: widget.settings.captureImages,
            onChanged: (value) => widget.onSettingsChanged(
              widget.settings.copyWith(captureImages: value),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (!isAndroid) ...[
          _SettingsSwitchRow(
            icon: Icons.insert_drive_file_outlined,
            title: l10n.fileFolderPaths,
            subtitle: l10n.fileFolderPathsSubtitle,
            value: widget.settings.captureFileReferences,
            onChanged: (value) => widget.onSettingsChanged(
              widget.settings.copyWith(captureFileReferences: value),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsSwitchRow(
            icon: Icons.keyboard_tab_outlined,
            title: l10n.autoPasteQuickPicker,
            subtitle: l10n.autoPasteQuickPickerSubtitle,
            value: widget.settings.autoPasteFromQuickPicker,
            onChanged: (value) => widget.onSettingsChanged(
              widget.settings.copyWith(autoPasteFromQuickPicker: value),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (isAndroid) ...[
          if (widget.onToggleAndroidBatteryOptimizationBypass != null) ...[
            _SettingsSwitchRow(
              icon: Icons.battery_saver_outlined,
              title: l10n.ignoreBatteryOptimization,
              subtitle: l10n.ignoreBatteryOptimizationSubtitle,
              value: widget.androidIgnoringBatteryOptimizations,
              onChanged: widget.onToggleAndroidBatteryOptimizationBypass!,
            ),
            const SizedBox(height: 8),
          ],
          if (widget.onOpenAndroidNotificationSettings != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: widget.onOpenAndroidNotificationSettings,
                icon: const Icon(Icons.notifications_outlined),
                label: _OffsetButtonLabel(l10n.notificationSettings, y: 1),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
        if (!isAndroid) ...[
          _SettingsSwitchRow(
            icon: Icons.login,
            title: l10n.windowsAutoStart,
            subtitle: l10n.windowsAutoStartSubtitle,
            value: widget.settings.windowsAutoStart,
            onChanged: (value) => widget.onSettingsChanged(
              widget.settings.copyWith(windowsAutoStart: value),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsSwitchRow(
            icon: Icons.keyboard_command_key,
            title: l10n.quickOpenHotkey,
            subtitle: widget.settings.quickOpenHotKey.enabled
                ? widget.settings.quickOpenHotKey.label
                : l10n.disabled,
            value: widget.settings.quickOpenHotKey.enabled,
            onChanged: (value) => widget.onSettingsChanged(
              widget.settings.copyWith(
                quickOpenHotKey: widget.settings.quickOpenHotKey.copyWith(
                  enabled: value,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _recordHotKey,
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: _ButtonLabel(l10n.changeHotkey),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SettingsCard(
          icon: Icons.inventory_2_outlined,
          title: l10n.storage,
          subtitle: '',
          trailing: _MiniChip(
            label: _formatClipboardCount(_pendingRetentionLimit, l10n),
            labelYOffset: 1,
          ),
          child: _RetentionStandardSlider(
            value: retentionValue,
            onChanged: (value) {
              setState(() {
                _pendingRetentionLimit = _normalizeRetentionLimit(
                  value.round(),
                );
              });
            },
            onChangeEnd: (value) {
              widget.onRetentionLimitChanged(
                _normalizeRetentionLimit(value.round()),
              );
            },
          ),
        ),
        if (!isAndroid) ...[
          const SizedBox(height: 16),
          _SettingsCard(
            icon: Icons.visibility_off_outlined,
            title: l10n.excludedApps,
            subtitle: l10n.excludedAppsSubtitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _excludedSourceController,
                        decoration: _compactRoundedInputDecoration(
                          context,
                          labelText: l10n.sourceAppName,
                          hintText: 'Chrome, 1Password, KeePass...',
                        ),
                        onSubmitted: _addSource,
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          _addSource(_excludedSourceController.text),
                      icon: const Icon(Icons.add),
                      label: _ButtonLabel(l10n.add),
                    ),
                  ],
                ),
                if (widget.sourceSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final source in widget.sourceSuggestions)
                        ActionChip(
                          avatar: const Icon(Icons.add_circle_outline),
                          label: Text(source),
                          onPressed: () => _addSource(source),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                if (widget.settings.excludedSources.isEmpty)
                  Text(
                    l10n.noExcludedApps,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final source in widget.settings.excludedSources)
                        InputChip(
                          avatar: const Icon(Icons.block),
                          label: Text(source),
                          onDeleted: () =>
                              widget.onRemoveExcludedSource(source),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _HotKeyRecorderDialog extends StatefulWidget {
  const _HotKeyRecorderDialog({required this.initialHotKey});

  final QuickOpenHotKey initialHotKey;

  @override
  State<_HotKeyRecorderDialog> createState() => _HotKeyRecorderDialogState();
}

class _HotKeyRecorderDialogState extends State<_HotKeyRecorderDialog> {
  late final FocusNode _focusNode;
  QuickOpenHotKey? _recordedHotKey;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _recordedHotKey = widget.initialHotKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyPart = _hotKeyPartFromLogicalKey(event.logicalKey);
    if (keyPart == null) {
      if (!_isModifierLogicalKey(event.logicalKey)) {
        setState(() => _errorText = context.l10n.unsupportedHotkey);
      }
      return KeyEventResult.handled;
    }

    final keyboard = HardwareKeyboard.instance;
    final hasModifier =
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        keyboard.isMetaPressed;
    if (!hasModifier) {
      setState(() => _errorText = context.l10n.hotkeyNeedsModifier);
      return KeyEventResult.handled;
    }

    setState(() {
      _errorText = null;
      _recordedHotKey = QuickOpenHotKey(
        enabled: true,
        control: keyboard.isControlPressed,
        alt: keyboard.isAltPressed,
        shift: keyboard.isShiftPressed,
        meta: keyboard.isMetaPressed,
        keyLabel: keyPart.label,
        keyCode: keyPart.keyCode,
      );
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final hotKey = _recordedHotKey ?? widget.initialHotKey;
    return AlertDialog(
      icon: const Icon(Icons.keyboard_alt_outlined),
      title: Text(l10n.changeHotkey),
      content: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.pressHotkeyInstruction,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                decoration: ShapeDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Text(
                  hotKey.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: _ButtonLabel(l10n.cancel),
        ),
        FilledButton(
          onPressed: _recordedHotKey == null
              ? null
              : () => Navigator.of(context).pop(_recordedHotKey),
          child: _ButtonLabel(l10n.save),
        ),
      ],
    );
  }
}

class _HotKeyPart {
  const _HotKeyPart({required this.label, required this.keyCode});

  final String label;
  final int keyCode;
}

class _SettingsNavigationRow extends StatelessWidget {
  const _SettingsNavigationRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        mouseCursor: SystemMouseCursors.click,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetentionStandardSlider extends StatelessWidget {
  const _RetentionStandardSlider({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  static const double _min = 200;
  static const double _max = 10000;
  static const int _divisions = 49;

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final roundedValue = _normalizeRetentionLimit(value.round());
    final labelStyle = textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Semantics(
      label: l10n.retentionLimitClipboard,
      value: _formatClipboardCount(roundedValue, l10n),
      increasedValue: _formatClipboardCount(
        _normalizeRetentionLimit(roundedValue + 200),
        l10n,
      ),
      decreasedValue: _formatClipboardCount(
        _normalizeRetentionLimit(roundedValue - 200),
        l10n,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.retentionLimit, style: labelStyle),
              const Spacer(),
              Text(
                _formatClipboardCount(roundedValue, l10n),
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const HandleThumbShape(),
              thumbSize: const WidgetStatePropertyAll(Size(4, 32)),
              trackShape: const GappedSliderTrackShape(),
              trackGap: 6,
              showValueIndicator: ShowValueIndicator.onlyForDiscrete,
              valueIndicatorColor: colorScheme.inverseSurface,
              valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
                color: colorScheme.onInverseSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Slider(
              value: roundedValue.toDouble(),
              min: _min,
              max: _max,
              divisions: _divisions,
              label: _formatClipboardCount(roundedValue, l10n),
              semanticFormatterCallback: (value) => _formatClipboardCount(
                _normalizeRetentionLimit(value.round()),
                l10n,
              ),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(
                  _formatClipboardCount(_min.toInt(), l10n),
                  style: labelStyle,
                ),
                const Spacer(),
                Text(
                  _formatClipboardCount(_max.toInt(), l10n),
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -1),
      child: Text(
        text,
        textHeightBehavior: const TextHeightBehavior(
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }
}

class _OffsetButtonLabel extends StatelessWidget {
  const _OffsetButtonLabel(this.text, {required this.y});

  final String text;
  final double y;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(offset: Offset(0, y), child: _ButtonLabel(text));
  }
}

class _FittedOneLineLabel extends StatelessWidget {
  const _FittedOneLineLabel(this.text, {this.minWidth = 42});

  final String text;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -1),
      child: SizedBox(
        width: minWidth,
        height: 16,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            textHeightBehavior: const TextHeightBehavior(
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        ),
      ),
    );
  }
}

enum _MotionFeedbackButtonVariant { filled, filledTonal, outlined }

class _AnimatedFeedbackLabel extends StatelessWidget {
  const _AnimatedFeedbackLabel({
    required this.showFeedback,
    required this.icon,
    required this.label,
    required this.successLabel,
    this.color,
    this.labelYOffset = 0,
  });

  final bool showFeedback;
  final IconData icon;
  final String label;
  final String successLabel;
  final Color? color;
  final double labelYOffset;

  @override
  Widget build(BuildContext context) {
    final contentKey = showFeedback ? 'feedback' : 'normal';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        final key = child.key;
        final isFeedbackChild =
            key is ValueKey<String> && key.value == 'feedback';
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(isFeedbackChild ? 0.08 : -0.08, 0),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
      child: _FeedbackLabelRow(
        key: ValueKey(contentKey),
        icon: showFeedback ? Icons.check_circle_outline : icon,
        label: showFeedback ? successLabel : label,
        color: color,
        labelYOffset: labelYOffset,
      ),
    );
  }
}

class _FeedbackLabelRow extends StatelessWidget {
  const _FeedbackLabelRow({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.labelYOffset = 0,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final double labelYOffset;

  @override
  Widget build(BuildContext context) {
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = inheritedStyle.copyWith(
      color: color ?? inheritedStyle.color,
      fontWeight: FontWeight.w600,
      height: 1.0,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Transform.translate(
          offset: Offset(0, labelYOffset),
          child: Text(label, style: effectiveStyle),
        ),
      ],
    );
  }
}

class _MotionFeedbackButton extends StatefulWidget {
  const _MotionFeedbackButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.successLabel = 'Xong',
    this.variant = _MotionFeedbackButtonVariant.outlined,
    this.labelYOffset = 0,
  });

  final IconData icon;
  final String label;
  final FutureOr<void> Function()? onPressed;
  final String successLabel;
  final _MotionFeedbackButtonVariant variant;
  final double labelYOffset;

  @override
  State<_MotionFeedbackButton> createState() => _MotionFeedbackButtonState();
}

class _MotionFeedbackButtonState extends State<_MotionFeedbackButton> {
  bool _showFeedback = false;
  bool _running = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _handlePressed() async {
    final action = widget.onPressed;
    if (action == null || _running) return;
    _resetTimer?.cancel();
    setState(() {
      _running = true;
      _showFeedback = true;
    });
    try {
      await action();
    } finally {
      if (mounted) _scheduleReset();
    }
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      setState(() => _showFeedback = false);
      _resetTimer = Timer(const Duration(milliseconds: 240), () {
        if (!mounted) return;
        setState(() => _running = false);
      });
    });
  }

  ButtonStyle _style() {
    const baseStyle = ButtonStyle(
      alignment: Alignment.center,
      animationDuration: Duration(milliseconds: 220),
      fixedSize: WidgetStatePropertyAll(Size.fromHeight(38)),
      minimumSize: WidgetStatePropertyAll(Size(60, 38)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
      shape: WidgetStatePropertyAll(StadiumBorder()),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    return baseStyle;
  }

  Widget _content(BuildContext context) {
    return _AnimatedFeedbackLabel(
      showFeedback: _showFeedback,
      icon: widget.icon,
      label: widget.label,
      successLabel: widget.successLabel,
      labelYOffset: widget.labelYOffset,
    );
  }

  Widget _plainContent({required IconData icon, required String label}) {
    return _FeedbackLabelRow(
      icon: icon,
      label: label,
      labelYOffset: widget.labelYOffset,
    );
  }

  Widget _button({
    required Widget child,
    required ButtonStyle style,
    required VoidCallback? onPressed,
  }) {
    return switch (widget.variant) {
      _MotionFeedbackButtonVariant.filled => FilledButton(
        onPressed: onPressed,
        style: style,
        child: child,
      ),
      _MotionFeedbackButtonVariant.filledTonal => FilledButton.tonal(
        onPressed: onPressed,
        style: style,
        child: child,
      ),
      _MotionFeedbackButtonVariant.outlined => OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: child,
      ),
    };
  }

  Widget _sizePlaceholder({
    required ButtonStyle style,
    required IconData icon,
    required String label,
    required bool enabled,
  }) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Opacity(
          opacity: 0,
          child: _button(
            onPressed: enabled ? () {} : null,
            style: style,
            child: _plainContent(icon: icon, label: label),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final style = _style();
    return Stack(
      alignment: Alignment.center,
      children: [
        _sizePlaceholder(
          enabled: enabled,
          style: style,
          icon: widget.icon,
          label: widget.label,
        ),
        _sizePlaceholder(
          enabled: enabled,
          style: style,
          icon: Icons.check_circle_outline,
          label: widget.successLabel,
        ),
        Positioned.fill(
          child: _button(
            onPressed: enabled ? _handlePressed : null,
            style: style,
            child: Center(child: _content(context)),
          ),
        ),
      ],
    );
  }
}

class _MotionFeedbackIconButton extends StatefulWidget {
  const _MotionFeedbackIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final FutureOr<void> Function()? onPressed;

  @override
  State<_MotionFeedbackIconButton> createState() =>
      _MotionFeedbackIconButtonState();
}

class _MotionFeedbackIconButtonState extends State<_MotionFeedbackIconButton> {
  bool _showFeedback = false;
  bool _pressed = false;
  bool _running = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _handlePressed() async {
    final action = widget.onPressed;
    if (action == null || _running) return;
    _resetTimer?.cancel();
    setState(() {
      _running = true;
      _pressed = true;
      _showFeedback = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (mounted) setState(() => _pressed = false);
    await action();
    if (!mounted) return;
    _resetTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      setState(() {
        _showFeedback = false;
        _running = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: IconButton.filledTonal(
          onPressed: enabled ? _handlePressed : null,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.84, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: Icon(
              _showFeedback ? Icons.check : widget.icon,
              key: ValueKey(_showFeedback),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.entry});

  final ClipboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imagePreviewMaxHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.42,
      420.0,
    );
    Widget child;
    var minHeight = 0.0;
    switch (entry.kind) {
      case ClipboardKind.text:
        child = SelectableText(
          entry.body ?? entry.preview,
          style: const TextStyle(fontSize: 16, height: 1.4),
        );
      case ClipboardKind.code:
        child = SelectableText(
          entry.body ?? entry.preview,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontFamily: 'Consolas',
            fontSize: 14,
            height: 1.45,
          ),
        );
      case ClipboardKind.url:
        final url = entry.body ?? entry.preview;
        child = SelectableText(
          url,
          style: TextStyle(
            color: colorScheme.primary,
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        );
      case ClipboardKind.image:
        minHeight = 180;
        if (entry.imageBytes == null || entry.imageBytes!.isEmpty) {
          child = const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_outlined, size: 48),
              SizedBox(height: 10),
              Text('Không đọc được dữ liệu ảnh trong clipboard'),
            ],
          );
        } else {
          child = Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: imagePreviewMaxHeight),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  entry.imageBytes!,
                  fit: BoxFit.scaleDown,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) {
                    return const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image_outlined, size: 48),
                        SizedBox(height: 10),
                        Text('Ảnh đã lưu nhưng không preview được'),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        }
      case ClipboardKind.fileReference:
        child = SelectableText(entry.filePath ?? entry.preview);
    }

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _LocalDeviceRow extends StatelessWidget {
  const _LocalDeviceRow({
    required this.identity,
    required this.syncHost,
    required this.syncPort,
    required this.syncError,
    required this.lanSyncEnabled,
    required this.onRename,
  });

  final LocalSyncIdentity identity;
  final String syncHost;
  final int syncPort;
  final String? syncError;
  final bool lanSyncEnabled;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final hasError = syncError != null;
    Widget localDeviceBadge({
      required String label,
      required IconData icon,
      required Color color,
    }) {
      return _M3Badge(
        label: label,
        icon: icon,
        tone: _M3BadgeTone.primary,
        horizontalPadding: 8,
        tightText: true,
        containerColorOverride: Color.alphaBlend(
          color.withValues(alpha: 0.10),
          colorScheme.surfaceContainerHigh,
        ),
        contentColorOverride: colorScheme.onSurfaceVariant,
        iconColorOverride: color,
        borderColorOverride: color.withValues(alpha: 0.18),
      );
    }

    return _SettingsCard(
      icon: hasError ? Icons.error_outline : Icons.computer,
      title: l10n.thisDevice,
      subtitle: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: ShapeDecoration(
              color: hasError
                  ? colorScheme.errorContainer
                  : colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: hasError
                      ? colorScheme.error.withValues(alpha: 0.32)
                      : colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        identity.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: hasError ? colorScheme.onErrorContainer : null,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: l10n.renameThisDevice,
                      child: IconButton(
                        onPressed: onRename,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          fixedSize: const Size.square(32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  syncError ?? syncHost,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: hasError
                        ? colorScheme.onErrorContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: compact ? WrapAlignment.center : WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  localDeviceBadge(
                    label: identity.pairCode,
                    icon: Icons.key_outlined,
                    color: colorScheme.primary,
                  ),
                  localDeviceBadge(
                    label: 'Port $syncPort',
                    icon: Icons.settings_ethernet,
                    color: colorScheme.primary,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PairQrCard extends StatelessWidget {
  const _PairQrCard({required this.payload, required this.onCopyPairPayload});

  final String payload;
  final VoidCallback onCopyPairPayload;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.qrPairing,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _MotionFeedbackButton(
                  onPressed: onCopyPairPayload,
                  icon: Icons.copy_all_outlined,
                  label: l10n.copyPayload,
                  successLabel: l10n.copied,
                  variant: _MotionFeedbackButtonVariant.filledTonal,
                  labelYOffset: 1,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(child: _PairQrImage(payload: payload)),
          ],
        ),
      ),
    );
  }
}

class _PairQrImage extends StatelessWidget {
  const _PairQrImage({required this.payload});

  final String payload;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'QR pairing LAN',
      child: Container(
        width: 184,
        height: 184,
        padding: const EdgeInsets.all(10),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: QrImageView(
          data: payload,
          version: QrVersions.auto,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
          gapless: false,
        ),
      ),
    );
  }
}

class _DiscoveredDevicesCard extends StatelessWidget {
  const _DiscoveredDevicesCard({required this.devices, required this.onAdd});

  final List<DiscoveredSyncDevice> devices;
  final ValueChanged<DiscoveredSyncDevice> onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    if (devices.isEmpty) {
      return _SettingsCard(
        icon: Icons.radar_outlined,
        title: l10n.visibleDevices,
        subtitle: '',
        child: Row(
          children: [
            Icon(Icons.radar_outlined, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.noVisibleDevices,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _SettingsCard(
      icon: Icons.radar_outlined,
      title: l10n.visibleDevices,
      subtitle: '',
      trailing: _MiniChip(
        label: '${devices.length} ${l10n.found}',
        labelYOffset: 0,
      ),
      child: Column(
        children: [
          for (final device in devices) ...[
            _DiscoveredDeviceRow(device: device, onAdd: () => onAdd(device)),
            if (device != devices.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _DiscoveredDeviceRow extends StatelessWidget {
  const _DiscoveredDeviceRow({required this.device, required this.onAdd});

  final DiscoveredSyncDevice device;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Material(
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            final info = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.devices_other_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${device.endpoint} - ${l10n.seen} ${_relativeTime(device.lastSeenAt, l10n)}',
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final addButton = FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_link),
              label: _OffsetButtonLabel(l10n.connect, y: 1),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  info,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: addButton),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 10),
                addButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.peer,
    required this.discoveredDevice,
    required this.onSync,
    required this.onTest,
    required this.onRename,
    required this.onRemove,
  });

  final SyncPeer peer;
  final DiscoveredSyncDevice? discoveredDevice;
  final VoidCallback onSync;
  final VoidCallback onTest;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final hasError = peer.lastError != null;
    final peerErrorText = peer.lastError == null
        ? null
        : _friendlySyncError(peer.lastError!);
    final lastSeenAge = discoveredDevice == null
        ? null
        : DateTime.now().difference(discoveredDevice!.lastSeenAt);
    final online =
        lastSeenAge != null && lastSeenAge <= _discoveredDeviceOnlineWindow;
    final recentlySeen =
        !online &&
        lastSeenAge != null &&
        lastSeenAge <= _discoveredDeviceCacheWindow;
    Widget deviceActionButton({
      required String tooltip,
      required VoidCallback onPressed,
      required IconData icon,
      Color? foregroundColor,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 19,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: foregroundColor,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    final actionButtons = [
      deviceActionButton(
        tooltip: l10n.testConnection,
        onPressed: onTest,
        icon: Icons.network_ping,
      ),
      deviceActionButton(
        tooltip: l10n.renameDevice,
        onPressed: onRename,
        icon: Icons.edit_outlined,
      ),
      deviceActionButton(
        tooltip: l10n.syncDevice,
        onPressed: onSync,
        icon: Icons.sync,
      ),
      deviceActionButton(
        tooltip: l10n.removeDevice,
        onPressed: onRemove,
        icon: Icons.link_off,
        foregroundColor: colorScheme.error,
      ),
    ];
    final spacedActionButtons = [
      for (var index = 0; index < actionButtons.length; index++) ...[
        if (index > 0) const SizedBox(width: 4),
        actionButtons[index],
      ],
    ];
    final statusBaseColor = !hasError && online
        ? const Color(0xFF2E7D32)
        : colorScheme.error;
    final statusBadge = _M3Badge(
      label: hasError
          ? l10n.error
          : online
          ? l10n.online
          : recentlySeen
          ? l10n.recentlySeen
          : l10n.offline,
      tone: _M3BadgeTone.surface,
      horizontalPadding: 8,
      tightText: true,
      containerColorOverride: Color.alphaBlend(
        statusBaseColor.withValues(alpha: 0.10),
        colorScheme.surfaceContainerHigh,
      ),
      contentColorOverride: statusBaseColor,
      borderColorOverride: statusBaseColor.withValues(alpha: 0.18),
      labelYOffset: 0,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasError
            ? colorScheme.errorContainer.withValues(alpha: 0.72)
            : colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? colorScheme.error.withValues(alpha: 0.32)
              : colorScheme.outlineVariant,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final titleRow = Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      hasError
                          ? Icons.sync_problem
                          : online
                          ? Icons.wifi_tethering
                          : recentlySeen
                          ? Icons.schedule_outlined
                          : Icons.verified_user_outlined,
                      size: 22,
                      color: hasError
                          ? colorScheme.error
                          : online
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        peer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 4,
                runSpacing: 0,
                alignment: WrapAlignment.end,
                children: actionButtons,
              ),
            ],
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${peer.endpoint} - ${peer.pairCode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  statusBadge,
                ],
              ),
              const SizedBox(height: 2),
              Text(
                peerErrorText ?? _lastSyncedLabel(peer, l10n),
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: hasError
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                  fontWeight: hasError ? FontWeight.w700 : null,
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            hasError
                                ? Icons.sync_problem
                                : online
                                ? Icons.wifi_tethering
                                : recentlySeen
                                ? Icons.schedule_outlined
                                : Icons.verified_user_outlined,
                            size: 22,
                            color: hasError
                                ? colorScheme.error
                                : online
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              peer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: spacedActionButtons,
                    ),
                  ],
                ),
                details,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleRow, details],
          );
        },
      ),
    );
  }
}

enum _M3BadgeTone { neutral, surface, primary, accent, selected }

class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.label, required this.definition});

  final String label;
  final TagDefinition? definition;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tagColor = definition?.color ?? colorScheme.tertiary;
    final readableContentColor = colorScheme.brightness == Brightness.light
        ? Colors.black87
        : colorScheme.onSurface;
    final containerColor = Color.alphaBlend(
      tagColor.withValues(alpha: 0.18),
      colorScheme.surfaceContainerHighest,
    );
    return _M3Badge(
      label: label,
      icon: definition?.icon ?? Icons.sell_outlined,
      tone: _M3BadgeTone.accent,
      containerColorOverride: containerColor,
      contentColorOverride: readableContentColor,
      iconColorOverride: _readableTagAccent(tagColor),
      borderColorOverride: tagColor.withValues(alpha: 0.48),
    );
  }
}

class _M3Badge extends StatelessWidget {
  const _M3Badge({
    required this.label,
    required this.tone,
    this.icon,
    this.containerColorOverride,
    this.contentColorOverride,
    this.iconColorOverride,
    this.borderColorOverride,
    this.horizontalPadding,
    this.tightText = false,
    this.labelYOffset,
  });

  final String label;
  final IconData? icon;
  final _M3BadgeTone tone;
  final Color? containerColorOverride;
  final Color? contentColorOverride;
  final Color? iconColorOverride;
  final Color? borderColorOverride;
  final double? horizontalPadding;
  final bool tightText;
  final double? labelYOffset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (
      baseContainerColor,
      baseContentColor,
      baseBorderColor,
    ) = switch (tone) {
      _M3BadgeTone.neutral => (
        colorScheme.surfaceContainerHigh,
        colorScheme.onSurfaceVariant,
        colorScheme.outlineVariant,
      ),
      _M3BadgeTone.surface => (
        colorScheme.surfaceContainerHigh,
        colorScheme.onSurfaceVariant,
        colorScheme.outlineVariant,
      ),
      _M3BadgeTone.primary => (
        colorScheme.surfaceContainerHigh,
        colorScheme.onSurfaceVariant,
        colorScheme.outlineVariant,
      ),
      _M3BadgeTone.accent => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
        colorScheme.outlineVariant,
      ),
      _M3BadgeTone.selected => (
        colorScheme.surfaceContainerHigh,
        colorScheme.onSurfaceVariant,
        colorScheme.outlineVariant,
      ),
    };
    final containerColor = containerColorOverride ?? baseContainerColor;
    final contentColor = contentColorOverride ?? baseContentColor;
    final iconColor = iconColorOverride ?? contentColor;
    final borderColor = borderColorOverride ?? baseBorderColor;

    return Semantics(
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 22,
        constraints: const BoxConstraints(minWidth: 0, maxWidth: 190),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding ?? (icon == null ? 6 : 5),
        ),
        decoration: ShapeDecoration(
          color: containerColor,
          shape: StadiumBorder(side: BorderSide(color: borderColor)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Transform.translate(
                  offset: Offset(0, labelYOffset ?? (tightText ? 0 : -0.75)),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: tightText
                        ? const StrutStyle(
                            fontSize: 11,
                            height: 1,
                            leading: 0,
                            forceStrutHeight: true,
                          )
                        : null,
                    textHeightBehavior: tightText
                        ? const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          )
                        : null,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: contentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    this.timeTone = false,
    this.labelYOffset,
  });

  final String label;
  final bool timeTone;
  final double? labelYOffset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!timeTone) {
      return _M3Badge(
        label: label,
        tone: _M3BadgeTone.surface,
        labelYOffset: labelYOffset,
      );
    }
    return _M3Badge(
      label: label,
      tone: _M3BadgeTone.primary,
      horizontalPadding: 8,
      tightText: true,
      labelYOffset: labelYOffset,
      containerColorOverride: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.10),
        colorScheme.surfaceContainerHigh,
      ),
      contentColorOverride: colorScheme.primary,
      iconColorOverride: colorScheme.primary,
      borderColorOverride: colorScheme.primary.withValues(alpha: 0.18),
    );
  }
}

Future<File> _historyFile() async {
  return _opencbDataFile('clipboard_history.json');
}

Future<File> _legacyMigrationMarkerFile() async {
  return _opencbDataFile('clipboard_history.migrated.json');
}

Future<File> _legacyPinnedCleanupMarkerFile() async {
  return _opencbDataFile('clipboard_history.pinned_cleanup.json');
}

Future<File> _peersFile() async {
  return _opencbDataFile('sync_peers.json');
}

Future<File> _syncIdentityFile() async {
  return _opencbDataFile('sync_identity.json');
}

Future<File> _sourceIconsFile() async {
  return _opencbDataFile('source_icons.json');
}

Future<File> _tagDefinitionsFile() async {
  return _opencbDataFile('tag_definitions.json');
}

Future<File> _syncTombstonesFile() async {
  return _opencbDataFile('sync_tombstones.json');
}

Future<File> _clipboardSettingsFile() async {
  return _opencbDataFile('clipboard_settings.json');
}

Future<File> _fileTransfersFile() async {
  return _opencbDataFile('file_transfers.json');
}

Future<File> _themeFile() async {
  return _opencbDataFile('theme.json');
}

Future<File> _opencbDataFile(String fileName) async {
  final dir = await _opencbDataDirectory();
  return File('${dir.path}${Platform.pathSeparator}$fileName');
}

Future<Directory> _opencbDataDirectory() async {
  if (Platform.isAndroid) {
    final supportDir = await getApplicationSupportDirectory();
    return Directory('${supportDir.path}${Platform.pathSeparator}OpenCB');
  }
  final base =
      Platform.environment['APPDATA'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  return Directory('$base${Platform.pathSeparator}OpenCB');
}

String _historyFilePathPreview() {
  return _databaseFilePathPreview();
}

String _databaseFilePathPreview() {
  final base =
      Platform.environment['APPDATA'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  return '$base${Platform.pathSeparator}OpenCB${Platform.pathSeparator}opencb.sqlite3';
}

String _fileNameFromPath(String path) {
  final normalized = path.replaceAll('\\', Platform.pathSeparator);
  final parts = normalized.split(Platform.pathSeparator);
  final name = parts.isEmpty ? path : parts.last;
  return name.trim().isEmpty ? 'file' : name;
}

String _safeFileName(String value) {
  final sanitized = value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .trim();
  return sanitized.isEmpty ? 'file' : sanitized;
}

String _safeRelativeFilePath(String value) {
  final parts = value
      .replaceAll('\\', '/')
      .split('/')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty && part != '.' && part != '..')
      .map(_safeFileName)
      .toList();
  if (parts.isEmpty) return _safeFileName(value);
  return parts.join('/');
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final decimals = value >= 100
      ? 0
      : value >= 10
      ? 1
      : 2;
  return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

String _formatTransferSpeed(int bytesPerSecond, [AppLocalizations? l10n]) {
  if (bytesPerSecond <= 0) return l10n?.measuring ?? 'Đang đo';
  return '${_formatBytes(bytesPerSecond)}/s';
}

String _localizedCount(
  AppLocalizations l10n,
  int count,
  String unit, {
  String? pluralUnit,
}) {
  final effectiveUnit = l10n.localeName.startsWith('en') && count != 1
      ? (pluralUnit ?? '${unit}s')
      : unit;
  return '$count $effectiveUnit';
}

String _localizedFileCount(AppLocalizations l10n, int count) =>
    _localizedCount(l10n, count, l10n.fileUnit);

String _localizedMoreFileCount(AppLocalizations l10n, int count) {
  if (l10n.localeName.startsWith('en')) {
    return '+$count ${l10n.moreFiles}';
  }
  return '+$count ${l10n.fileUnit} ${l10n.moreFiles}';
}

String _localizedDeviceCount(AppLocalizations l10n, int count) =>
    _localizedCount(l10n, count, l10n.deviceUnit);

String _localizedItemCount(AppLocalizations l10n, int count) =>
    _localizedCount(l10n, count, l10n.itemUnit);

String _generateTransferId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final suffix = math.Random().nextInt(0xFFFFFF).toRadixString(16);
  return 'transfer-$now-$suffix';
}

String _fileTransferStatusLabel(
  AppLocalizations l10n,
  FileTransferStatus status,
) {
  return switch (status) {
    FileTransferStatus.waiting => l10n.waitingForConfirm,
    FileTransferStatus.sending => l10n.sending,
    FileTransferStatus.receiving => l10n.receiving,
    FileTransferStatus.completed => l10n.completed,
    FileTransferStatus.rejected => l10n.rejected,
    FileTransferStatus.failed => l10n.error,
    FileTransferStatus.canceled => l10n.canceled,
  };
}

bool _isActiveTransferStatus(FileTransferStatus status) {
  return status == FileTransferStatus.waiting ||
      status == FileTransferStatus.sending ||
      status == FileTransferStatus.receiving;
}

bool _canOpenFileTransferLocally(FileTransferRecord transfer) {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return false;
  }
  if (transfer.direction != FileTransferDirection.receive ||
      transfer.status != FileTransferStatus.completed ||
      transfer.files.length != 1) {
    return false;
  }
  final file = transfer.files.first;
  final savedPath = file.savedPath?.trim();
  if (savedPath != null &&
      savedPath.isNotEmpty &&
      File(savedPath).existsSync()) {
    return true;
  }
  final saveDirectory = transfer.saveDirectory?.trim();
  if (saveDirectory == null || saveDirectory.isEmpty) return false;
  final candidate = File(
    '$saveDirectory${Platform.pathSeparator}${_safeRelativeFilePath(file.displayPath).replaceAll('/', Platform.pathSeparator)}',
  );
  return candidate.existsSync();
}

ClipboardKind _kindFromName(String name) {
  if (name == 'file_reference') return ClipboardKind.fileReference;
  if (name == 'url') return ClipboardKind.url;
  return ClipboardKind.values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => ClipboardKind.text,
  );
}

M3ThemePreset _presetById(String? id) {
  return _m3ThemePresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => _m3ThemePresets.first,
  );
}

String _themePresetName(AppLocalizations l10n, M3ThemePreset preset) {
  return switch (preset.id) {
    'opencb_teal' => l10n.themeOpenCbTeal,
    'forest_green' => l10n.themeForestGreen,
    'baseline_purple' => l10n.themeBaselinePurple,
    'ink_blue' => l10n.themeSerenity,
    'soft_pink' => l10n.themeRoseQuartz,
    'sunset_coral' => l10n.themeSunsetCoral,
    'mono_black_white' => l10n.themeMonoBlackWhite,
    'blue_grey' => l10n.themeBlueGrey,
    _ => preset.name,
  };
}

ThemeMode _themeModeFromName(String? name) {
  return ThemeMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => ThemeMode.light,
  );
}

int _normalizeRetentionLimit(int value) {
  final clamped = value.clamp(200, 10000);
  return ((clamped / 200).round() * 200).clamp(200, 10000);
}

String _formatClipboardCount(int value, [AppLocalizations? l10n]) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index += 1) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write('.');
    }
  }
  final unit = l10n == null ? 'mục' : _localizedItemUnit(l10n, value);
  return '$buffer $unit';
}

String _localizedItemUnit(AppLocalizations l10n, int count) {
  if (l10n.localeName.startsWith('en') && count != 1) {
    return '${l10n.itemUnit}s';
  }
  return l10n.itemUnit;
}

bool _isRemoteVersionNewer(String remoteTag, String currentVersion) {
  final remote = _versionParts(remoteTag);
  final current = _versionParts(currentVersion);
  for (
    var index = 0;
    index < math.max(remote.length, current.length);
    index++
  ) {
    final remotePart = index < remote.length ? remote[index] : 0;
    final currentPart = index < current.length ? current[index] : 0;
    if (remotePart > currentPart) return true;
    if (remotePart < currentPart) return false;
  }
  return false;
}

List<int> _versionParts(String value) {
  final normalized = value
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('-')
      .first;
  return normalized
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList(growable: false);
}

bool _isModifierLogicalKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;
}

_HotKeyPart? _hotKeyPartFromLogicalKey(LogicalKeyboardKey key) {
  final label = key.keyLabel.toUpperCase();
  if (label.length == 1) {
    final codeUnit = label.codeUnitAt(0);
    final isLetter = codeUnit >= 0x41 && codeUnit <= 0x5A;
    final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
    if (isLetter || isDigit) {
      return _HotKeyPart(label: label, keyCode: codeUnit);
    }
  }

  const functionKeys = [
    LogicalKeyboardKey.f1,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5,
    LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7,
    LogicalKeyboardKey.f8,
    LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10,
    LogicalKeyboardKey.f11,
    LogicalKeyboardKey.f12,
  ];
  final functionIndex = functionKeys.indexOf(key);
  if (functionIndex >= 0) {
    return _HotKeyPart(
      label: 'F${functionIndex + 1}',
      keyCode: 0x70 + functionIndex,
    );
  }
  return null;
}

IconData _kindIcon(ClipboardKind kind) {
  return switch (kind) {
    ClipboardKind.text => Icons.notes,
    ClipboardKind.code => Icons.code,
    ClipboardKind.url => Icons.link,
    ClipboardKind.image => Icons.image_outlined,
    ClipboardKind.fileReference => Icons.file_copy_outlined,
  };
}

IconData _tagIconByKey(String key) {
  return _tagIconOptions
      .firstWhere(
        (option) => option.key == key,
        orElse: () => _tagIconOptions.first,
      )
      .icon;
}

String _normalizeTagName(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
}

int _opaqueColorValue(int value) {
  return 0xFF000000 | (value & 0x00FFFFFF);
}

String _hexColorText(int value) {
  return '#${(value & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? _parseHexColor(String value) {
  var normalized = value.trim().replaceFirst('#', '');
  if (normalized.length == 3) {
    normalized = normalized.split('').map((char) => '$char$char').join();
  }
  if (normalized.length == 6) {
    normalized = 'FF$normalized';
  }
  if (normalized.length != 8) return null;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return null;
  return Color(_opaqueColorValue(parsed));
}

Color _readableTagAccent(Color color) {
  final luminance = color.computeLuminance();
  if (luminance > 0.56) {
    return Color.alphaBlend(Colors.black.withValues(alpha: 0.38), color);
  }
  return color;
}

String _kindLabel(AppLocalizations l10n, ClipboardKind kind) {
  return switch (kind) {
    ClipboardKind.text => l10n.clipboardText,
    ClipboardKind.code => l10n.clipboardCode,
    ClipboardKind.url => l10n.clipboardUrl,
    ClipboardKind.image => l10n.clipboardImage,
    ClipboardKind.fileReference => l10n.clipboardPath,
  };
}

String _shortKindLabel(AppLocalizations l10n, ClipboardKind kind) {
  return switch (kind) {
    ClipboardKind.text => l10n.clipboardText,
    ClipboardKind.code => l10n.clipboardCode,
    ClipboardKind.url => l10n.clipboardUrl,
    ClipboardKind.image => l10n.clipboardImage,
    ClipboardKind.fileReference => l10n.clipboardPath,
  };
}

String _quickPickerKindLabel(AppLocalizations l10n, ClipboardKind kind) =>
    _shortKindLabel(l10n, kind);

String _quickPickerMetaKindLabel(AppLocalizations l10n, ClipboardKind kind) =>
    _kindLabel(l10n, kind);

String _displaySourceLabel(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return source;
  return trimmed.replaceFirst(RegExp(r'^LAN\s*[-:–—]?\s+'), '');
}

Iterable<ClipboardEntry> _filterQuickPickerEntries(
  Iterable<ClipboardEntry> entries,
  String rawQuery,
) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return entries;
  return entries.where((entry) {
    return entry.preview.toLowerCase().contains(query) ||
        (entry.body ?? '').toLowerCase().contains(query) ||
        entry.source.toLowerCase().contains(query) ||
        entry.tags.any((tag) => tag.toLowerCase().contains(query));
  });
}

List<String> _availableEntryTags(Iterable<ClipboardEntry> entries) {
  final tags = {
    for (final entry in entries)
      for (final tag in entry.tags)
        if (tag.trim().isNotEmpty) tag.trim(),
  }.toList();
  tags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return tags;
}

String _nativeSourceLabel(Map payload) {
  final value = payload['sourceApp'];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return 'Clipboard hệ thống';
}

Uint8List? _nativeSourceIconBytes(Map payload) {
  final value = payload['sourceIcon'];
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  return null;
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _isPngBytes(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < signature.length) return false;
  for (var index = 0; index < signature.length; index += 1) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}

String _previewText(String text) {
  final compact = text
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
  if (compact.length <= 160) return compact;
  return '${compact.substring(0, 160)}...';
}

bool _isClipboardUrl(String value) => _normalizedUrl(value) != null;

ClipboardKind _classifyTextClipboard(String value) {
  if (_isClipboardUrl(value)) return ClipboardKind.url;
  if (_looksLikeCode(value)) return ClipboardKind.code;
  return ClipboardKind.text;
}

bool _looksLikeCode(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 12) return false;
  final lines = trimmed.split(RegExp(r'\r?\n'));
  var score = 0;

  if (RegExp(
    r'\b(class|function|const|let|var|final|import|export|return|if|else|for|while|switch|case|try|catch|async|await|fn|pub|impl|struct|enum|use|def|from|select|insert|update|delete|create|where)\b',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    score += 2;
  }
  if (RegExp(
    r'(=>|->|::|&&|\|\||==|!=|<=|>=|\+=|-=|\*=|/=)',
  ).hasMatch(trimmed)) {
    score += 2;
  }
  if (RegExp(r'[{};]').hasMatch(trimmed)) score += 1;
  if (RegExp(r'^\s*<[A-Za-z][\w:-]*(\s|>|/)').hasMatch(trimmed)) score += 2;
  if (RegExp(r'^\s*[\[{].*[:=].*[\]}]\s*$', dotAll: true).hasMatch(trimmed)) {
    score += 2;
  }
  if (lines.length >= 3 &&
      lines
              .where((line) => line.startsWith('  ') || line.startsWith('\t'))
              .length >=
          2) {
    score += 1;
  }
  if (lines.length >= 2 && RegExp(r'[(){}\[\];]').hasMatch(trimmed)) {
    score += 1;
  }

  return score >= 3;
}

String? _normalizedUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (!uri.host.contains('.') && uri.host.toLowerCase() != 'localhost') {
    return null;
  }
  return uri.toString();
}

String _relativeTime(DateTime value, [AppLocalizations? l10n]) {
  final diff = DateTime.now().difference(value);
  if (l10n != null) {
    if (diff.inSeconds < 60) return l10n.justNow;
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${l10n.minuteAgo}';
    if (diff.inHours < 24) return '${diff.inHours} ${l10n.hourAgo}';
    if (diff.inDays < 7) return '${diff.inDays} ${l10n.dayAgo}';
  } else {
    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
  }
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

String _lastSyncedLabel(SyncPeer peer, AppLocalizations l10n) {
  final lastSyncedAt = peer.lastSyncedAt;
  if (lastSyncedAt == null) return l10n.neverSynced;
  return '${l10n.lastSyncPrefix} ${_relativeTime(lastSyncedAt, l10n)}';
}

String _copyTimeLabel(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final copiedDay = DateTime(value.year, value.month, value.day);
  final time =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  if (copiedDay == today) return time;
  if (copiedDay == today.subtract(const Duration(days: 1))) {
    return 'Hôm qua $time';
  }

  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year} $time';
}

(String, int)? _parseEndpoint(String value) {
  final trimmed = value.trim();
  final separator = trimmed.lastIndexOf(':');
  if (separator <= 0 || separator == trimmed.length - 1) return null;
  final host = trimmed.substring(0, separator).trim();
  final port = int.tryParse(trimmed.substring(separator + 1).trim());
  if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
  return (host, port);
}

String _buildPairPayload(
  LocalSyncIdentity identity,
  int port, {
  required String host,
}) {
  return Uri(
    scheme: 'opencb',
    host: 'pair',
    queryParameters: {
      'id': identity.deviceId,
      'name': identity.deviceName,
      'host': host,
      'port': '$port',
      'filePort': '$_defaultFileTransferPort',
      'code': identity.pairCode,
    },
  ).toString();
}

Future<String?> _detectLanIpv4Address() async {
  if (Platform.isWindows) {
    final routedAddress = await _detectWindowsDefaultRouteIpv4();
    if (routedAddress != null) return routedAddress;
  }
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final candidates = <({String address, String interfaceName})>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (_isUsableLanIpv4(address.address)) {
          candidates.add((
            address: address.address,
            interfaceName: interface.name,
          ));
        }
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final aScore = _lanAddressPriority(a.address, a.interfaceName);
      final bScore = _lanAddressPriority(b.address, b.interfaceName);
      return bScore.compareTo(aScore);
    });
    return candidates.first.address;
  } catch (_) {
    return null;
  }
}

Future<String?> _detectWindowsDefaultRouteIpv4() async {
  try {
    final result = await Process.run('route', ['print', '-4', '0.0.0.0']);
    if (result.exitCode != 0) return null;
    final output = '${result.stdout}\n${result.stderr}';
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 5 && parts[0] == '0.0.0.0' && parts[1] == '0.0.0.0') {
        final interfaceAddress = parts[3];
        if (_isUsableLanIpv4(interfaceAddress)) return interfaceAddress;
      }
    }
  } catch (_) {}
  return null;
}

Future<List<InternetAddress>> _discoveryBroadcastTargets() async {
  final targets = <String>{'255.255.255.255'};
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final value = address.address;
        if (!_isUsableLanIpv4(value)) continue;
        final directed = _classCDirectedBroadcast(value);
        if (directed != null) targets.add(directed);
      }
    }
  } catch (_) {}
  return targets.map(InternetAddress.new).toList();
}

String? _classCDirectedBroadcast(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return null;
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((part) => part == null || part < 0 || part > 255)) {
    return null;
  }
  return '${numbers[0]}.${numbers[1]}.${numbers[2]}.255';
}

List<String> _classCSubnetTargets(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return const [];
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((part) => part == null || part < 0 || part > 255)) {
    return const [];
  }
  final self = numbers[3]!;
  final prefix = '${numbers[0]}.${numbers[1]}.${numbers[2]}';
  return [
    for (var host = 1; host <= 254; host += 1)
      if (host != self) '$prefix.$host',
  ];
}

bool _isUsableLanIpv4(String address) {
  return address != '0.0.0.0' &&
      !address.startsWith('127.') &&
      !address.startsWith('169.254.');
}

int _lanAddressPriority(String address, String interfaceName) {
  var score = 0;
  final name = interfaceName.toLowerCase();
  if (address.startsWith('192.168.')) score += 30;
  if (address.startsWith('10.')) score += 20;
  final parts = address.split('.');
  final second = parts.length > 1 ? int.tryParse(parts[1]) : null;
  if (address.startsWith('172.') &&
      second != null &&
      second >= 16 &&
      second <= 31) {
    score += 20;
  }
  if (name.contains('wi-fi') ||
      name.contains('wifi') ||
      name.contains('wlan') ||
      name.contains('ethernet')) {
    score += 10;
  }
  if (name.contains('virtual') ||
      name.contains('vmware') ||
      name.contains('vbox') ||
      name.contains('hyper-v') ||
      name.contains('bluetooth')) {
    score -= 25;
  }
  if (name.contains('tailscale') || name.contains('zerotier')) {
    score -= 8;
  }
  return score;
}

SyncPeer? _parsePairPayload(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) {
      return _syncPeerFromPairMap(decoded);
    }
  } catch (_) {}

  try {
    final uri = Uri.parse(trimmed);
    if (uri.scheme != 'opencb' || uri.host != 'pair') return null;
    return _syncPeerFromPairMap(uri.queryParameters);
  } catch (_) {
    return null;
  }
}

SyncPeer? _syncPeerFromPairMap(Map<String, dynamic> data) {
  final endpoint = data['endpoint']?.toString();
  final host = data['host']?.toString().trim();
  final parsedEndpoint = endpoint == null ? null : _parseEndpoint(endpoint);
  final portValue = data['port'];
  final port =
      parsedEndpoint?.$2 ??
      (portValue is int ? portValue : int.tryParse('$portValue'));
  final filePortValue = data['filePort'];
  final filePort = filePortValue is int
      ? filePortValue
      : int.tryParse('$filePortValue');
  final resolvedHost = parsedEndpoint?.$1 ?? host;
  final pairCode = (data['code'] ?? data['pairCode'])
      ?.toString()
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .toUpperCase();

  if (resolvedHost == null ||
      resolvedHost.isEmpty ||
      port == null ||
      port <= 0 ||
      port > 65535 ||
      pairCode == null ||
      pairCode.length < 6) {
    return null;
  }

  final id = (data['id'] ?? data['deviceId'])?.toString().trim();
  final name = (data['name'] ?? data['deviceName'])?.toString().trim();
  return SyncPeer(
    id: id == null || id.isEmpty
        ? 'peer-${DateTime.now().microsecondsSinceEpoch}'
        : id,
    name: name == null || name.isEmpty ? 'Thiết bị LAN' : name,
    host: resolvedHost,
    port: port,
    filePort: filePort == null || filePort <= 0 || filePort > 65535
        ? _defaultFileTransferPort
        : filePort,
    pairCode: pairCode,
  );
}

bool _isLanSyncableEntry(ClipboardEntry entry) {
  return entry.kind == ClipboardKind.text ||
      entry.kind == ClipboardKind.code ||
      entry.kind == ClipboardKind.url;
}

String? _syncEntrySignature(ClipboardEntry entry) {
  if (!_isLanSyncableEntry(entry)) return null;
  final body = (entry.body ?? entry.preview).trim();
  if (body.isEmpty) return null;
  return 'text:${body.length}:${_stableTextHash(body)}';
}

String _stableTextHash(String value) {
  const fnvPrime = 0x01000193;
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * fnvPrime) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _friendlySyncError(Object error) {
  final message = error.toString().trim();
  final normalized = message.toLowerCase();
  final cleaned = message
      .replaceFirst(RegExp(r'^(SocketException|TimeoutException):\s*'), '')
      .replaceFirst(RegExp(r',\s*address\s*=.*$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*\(OS Error:.*$', caseSensitive: false), '')
      .trim();
  if (normalized.contains('no route to host') ||
      normalized.contains('network is unreachable') ||
      normalized.contains('host is unreachable')) {
    return 'Không có đường mạng tới host. Kiểm tra cùng Wi-Fi/VPN, IP trong payload và firewall Windows.';
  }
  if (normalized.contains('connection refused') ||
      normalized.contains('actively refused') ||
      normalized.contains('remote computer refused') ||
      normalized.contains('connection attempt failed')) {
    return 'Kết nối bị từ chối. Thiết bị kia có thể chưa mở OpenCB.';
  }
  if (normalized.contains('connection reset')) {
    return 'Kết nối bị ngắt giữa chừng. Kiểm tra mạng LAN hoặc mở lại OpenCB trên thiết bị kia.';
  }
  if (normalized.contains('connection closed') ||
      normalized.contains('kết nối đã đóng')) {
    return 'Kết nối đã đóng trước khi sync xong.';
  }
  if (normalized.contains('timed out') ||
      normalized.contains('time out') ||
      normalized.contains('timeoutexception')) {
    return 'Sync quá thời gian chờ';
  }
  if (normalized.contains('failed host lookup') ||
      normalized.contains('nodename nor servname provided')) {
    return 'Không tìm thấy host';
  }
  if (normalized.contains('permission denied')) {
    return 'Không có quyền mở kết nối mạng. Kiểm tra quyền mạng hoặc firewall.';
  }
  return cleaned.length > 80 ? '${cleaned.substring(0, 80)}...' : cleaned;
}

bool _isPlaceholderSyncDeviceName(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'localhost' ||
      normalized == 'localhost.localdomain' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

String _generateDeviceId() {
  final random = math.Random.secure();
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final suffix = List.generate(
    12,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
  return 'device-$now-$suffix';
}

String _generatePairCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = math.Random.secure();
  return List.generate(
    8,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

abstract class OpenCbStorage {
  static Future<OpenCbStorage> open() async {
    if (!Platform.isWindows) {
      return LegacyJsonStorage();
    }
    try {
      return OpenCbRustStorage.open();
    } catch (_) {
      return LegacyJsonStorage();
    }
  }

  Future<List<ClipboardEntry>> listItems({int limit = 1200});
  Future<ClipboardEntry?> captureText(String text, {required String source});
  Future<ClipboardEntry?> captureFileReference(
    String path, {
    required String source,
  });
  Future<ClipboardEntry?> captureImage(
    Uint8List bytes, {
    required String source,
  });
  Future<void> setPinned(String id, bool pinned);
  Future<void> setTags(String id, List<String> tags);
  Future<void> touchItem(String id);
  Future<void> deleteItem(String id);
  Future<void> applyRetention({required int maxItems});
  void close();
}

class LegacyJsonStorage implements OpenCbStorage {
  List<ClipboardEntry> _entries = [];
  bool _loaded = false;

  @override
  Future<List<ClipboardEntry>> listItems({int limit = 1200}) async {
    await _ensureLoaded();
    final entries = [..._entries]..sort(_sortClipboardEntries);
    return entries.take(limit).toList();
  }

  @override
  Future<ClipboardEntry?> captureText(
    String text, {
    required String source,
  }) async {
    await _ensureLoaded();
    if (text.trim().isEmpty) return null;
    final now = DateTime.now();
    final existing = _entries.indexWhere((entry) => entry.body == text);
    final kind = _classifyTextClipboard(text);
    late final ClipboardEntry stored;
    if (existing >= 0) {
      stored = _entries[existing].copyWith(
        kind: kind,
        source: source,
        createdAt: now,
      );
      _entries[existing] = stored;
    } else {
      stored = ClipboardEntry(
        id: 'clip-${now.microsecondsSinceEpoch}',
        kind: kind,
        preview: _previewText(text),
        source: source,
        createdAt: now,
        pinned: false,
        tags: const [],
        body: text,
      );
      _entries.add(stored);
    }
    await _save();
    return stored;
  }

  @override
  Future<ClipboardEntry?> captureFileReference(
    String path, {
    required String source,
  }) async {
    await _ensureLoaded();
    if (path.trim().isEmpty) return null;
    final now = DateTime.now();
    final existing = _entries.indexWhere(
      (entry) =>
          entry.kind == ClipboardKind.fileReference && entry.filePath == path,
    );
    if (existing >= 0) {
      _entries[existing] = _entries[existing].copyWith(
        source: source,
        createdAt: now,
      );
    } else {
      _entries.add(
        ClipboardEntry(
          id: 'file-${now.microsecondsSinceEpoch}',
          kind: ClipboardKind.fileReference,
          preview: path,
          source: source,
          createdAt: now,
          pinned: false,
          tags: const [],
          filePath: path,
        ),
      );
    }
    await _save();
    return _entries.firstWhere(
      (entry) =>
          entry.kind == ClipboardKind.fileReference && entry.filePath == path,
    );
  }

  @override
  Future<ClipboardEntry?> captureImage(
    Uint8List bytes, {
    required String source,
  }) async {
    await _ensureLoaded();
    final now = DateTime.now();
    final entry = ClipboardEntry(
      id: 'image-${now.microsecondsSinceEpoch}',
      kind: ClipboardKind.image,
      preview: 'Ảnh clipboard - ${(bytes.length / 1024).toStringAsFixed(1)} KB',
      source: source,
      createdAt: now,
      pinned: false,
      tags: const [],
      imageBytes: bytes,
    );
    _entries.add(entry);
    await _save();
    return entry;
  }

  @override
  Future<void> setPinned(String id, bool pinned) async {
    await _ensureLoaded();
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index >= 0) {
      _entries[index] = _entries[index].copyWith(pinned: pinned);
      await _save();
    }
  }

  @override
  Future<void> setTags(String id, List<String> tags) async {
    await _ensureLoaded();
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index >= 0) {
      _entries[index] = _entries[index].copyWith(tags: tags);
      await _save();
    }
  }

  @override
  Future<void> touchItem(String id) async {
    await _ensureLoaded();
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index >= 0) {
      _entries[index] = _entries[index].copyWith(createdAt: DateTime.now());
      await _save();
    }
  }

  @override
  Future<void> deleteItem(String id) async {
    await _ensureLoaded();
    _entries = _entries.where((entry) => entry.id != id).toList();
    await _save();
  }

  @override
  Future<void> applyRetention({required int maxItems}) async {
    await _ensureLoaded();
    final sorted = [..._entries]..sort(_sortClipboardEntries);
    final pinned = sorted.where((entry) => entry.pinned).toList();
    final regular = sorted.where((entry) => !entry.pinned).take(maxItems);
    _entries = [...pinned, ...regular];
    await _save();
  }

  @override
  void close() {}

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final file = await _historyFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        _entries = decoded
            .whereType<Map<String, dynamic>>()
            .map(ClipboardEntry.fromJson)
            .toList();
      }
    } catch (_) {
      _entries = [];
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final file = await _historyFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(_entries.map((entry) => entry.toJson()).toList()),
    );
  }
}

class OpenCbRustStorage implements OpenCbStorage {
  OpenCbRustStorage._(this._bindings, this._handle);

  final _OpenCbCoreBindings _bindings;
  final ffi.Pointer<ffi.Void> _handle;

  static OpenCbRustStorage open() {
    final bindings = _OpenCbCoreBindings.load();
    final dbPath = _databaseFilePathPreview();
    Directory(File(dbPath).parent.path).createSync(recursive: true);
    final handle = bindings.open(dbPath, Platform.localHostname);
    if (handle == ffi.nullptr) {
      throw StateError(bindings.lastError());
    }
    return OpenCbRustStorage._(bindings, handle);
  }

  @override
  Future<List<ClipboardEntry>> listItems({int limit = 1200}) async {
    final jsonText = _bindings.listItems(_handle, limit, 0);
    final decoded = jsonDecode(jsonText) as List<dynamic>;
    final entries = <ClipboardEntry>[];
    for (final item in decoded.whereType<Map<String, dynamic>>()) {
      Uint8List? imageBytes;
      if (item['content_type'] == 'image') {
        imageBytes = _bindings.getBlob(_handle, item['id'] as String);
      }
      entries.add(ClipboardEntry.fromCoreJson(item, imageBytes: imageBytes));
    }
    entries.sort(_sortClipboardEntries);
    return entries;
  }

  @override
  Future<ClipboardEntry?> captureText(
    String text, {
    required String source,
  }) async {
    final jsonText = _bindings.captureText(_handle, text, source);
    return _entryFromCoreResponse(jsonText);
  }

  @override
  Future<ClipboardEntry?> captureFileReference(
    String path, {
    required String source,
  }) async {
    final jsonText = _bindings.captureFileReference(_handle, path, source);
    return _entryFromCoreResponse(jsonText);
  }

  @override
  Future<ClipboardEntry?> captureImage(
    Uint8List bytes, {
    required String source,
  }) async {
    final jsonText = _bindings.captureImage(_handle, bytes, source);
    final entry = _entryFromCoreResponse(jsonText);
    return entry?.copyWith(imageBytes: bytes);
  }

  @override
  Future<void> setPinned(String id, bool pinned) async {
    _bindings.setPinned(_handle, id, pinned);
  }

  @override
  Future<void> setTags(String id, List<String> tags) async {
    _bindings.setTags(_handle, id, tags);
  }

  @override
  Future<void> touchItem(String id) async {
    _bindings.touchItem(_handle, id);
  }

  @override
  Future<void> deleteItem(String id) async {
    _bindings.deleteItem(_handle, id);
  }

  @override
  Future<void> applyRetention({required int maxItems}) async {
    _bindings.applyRetention(_handle, maxItems, 1024, true);
  }

  @override
  void close() {
    _bindings.close(_handle);
  }

  ClipboardEntry? _entryFromCoreResponse(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;
    return ClipboardEntry.fromCoreJson(decoded);
  }
}

class _OpenCbCoreBindings {
  _OpenCbCoreBindings(ffi.DynamicLibrary lib)
    : _open = lib.lookupFunction<_NativeOpen, _DartOpen>('opencb_open'),
      _close = lib.lookupFunction<_NativeClose, _DartClose>('opencb_close'),
      _stringFree = lib.lookupFunction<_NativeStringFree, _DartStringFree>(
        'opencb_string_free',
      ),
      _lastErrorJson = lib
          .lookupFunction<_NativeLastErrorJson, _DartLastErrorJson>(
            'opencb_last_error_json',
          ),
      _listItemsJson = lib
          .lookupFunction<_NativeListItemsJson, _DartListItemsJson>(
            'opencb_list_items_json',
          ),
      _captureTextJson = lib
          .lookupFunction<_NativeCaptureTextJson, _DartCaptureTextJson>(
            'opencb_capture_text_json',
          ),
      _captureFileReferenceJson = lib
          .lookupFunction<
            _NativeCaptureFileReferenceJson,
            _DartCaptureFileReferenceJson
          >('opencb_capture_file_reference_json'),
      _captureImageJson = lib
          .lookupFunction<_NativeCaptureImageJson, _DartCaptureImageJson>(
            'opencb_capture_image_json',
          ),
      _deleteItem = lib.lookupFunction<_NativeDeleteItem, _DartDeleteItem>(
        'opencb_delete_item',
      ),
      _setPinned = lib.lookupFunction<_NativeSetPinned, _DartSetPinned>(
        'opencb_set_pinned',
      ),
      _setTagsJson = lib.lookupFunction<_NativeSetTagsJson, _DartSetTagsJson>(
        'opencb_set_tags_json',
      ),
      _touchItem = lib.lookupFunction<_NativeTouchItem, _DartTouchItem>(
        'opencb_touch_item',
      ),
      _applyRetention = lib
          .lookupFunction<_NativeApplyRetention, _DartApplyRetention>(
            'opencb_apply_retention',
          ),
      _getBlob = lib.lookupFunction<_NativeGetBlob, _DartGetBlob>(
        'opencb_get_blob',
      ),
      _blobFree = lib.lookupFunction<_NativeBlobFree, _DartBlobFree>(
        'opencb_blob_free',
      );

  final _DartOpen _open;
  final _DartClose _close;
  final _DartStringFree _stringFree;
  final _DartLastErrorJson _lastErrorJson;
  final _DartListItemsJson _listItemsJson;
  final _DartCaptureTextJson _captureTextJson;
  final _DartCaptureFileReferenceJson _captureFileReferenceJson;
  final _DartCaptureImageJson _captureImageJson;
  final _DartDeleteItem _deleteItem;
  final _DartSetPinned _setPinned;
  final _DartSetTagsJson _setTagsJson;
  final _DartTouchItem _touchItem;
  final _DartApplyRetention _applyRetention;
  final _DartGetBlob _getBlob;
  final _DartBlobFree _blobFree;

  static _OpenCbCoreBindings load() {
    return _OpenCbCoreBindings(ffi.DynamicLibrary.open('opencb_core.dll'));
  }

  ffi.Pointer<ffi.Void> open(String path, String deviceName) {
    final pathPtr = path.toNativeUtf8();
    final deviceNamePtr = deviceName.toNativeUtf8();
    try {
      return _open(pathPtr, deviceNamePtr);
    } finally {
      malloc.free(pathPtr);
      malloc.free(deviceNamePtr);
    }
  }

  void close(ffi.Pointer<ffi.Void> handle) => _close(handle);

  String listItems(ffi.Pointer<ffi.Void> handle, int limit, int offset) {
    return _takeString(_listItemsJson(handle, limit, offset));
  }

  String captureText(ffi.Pointer<ffi.Void> handle, String text, String source) {
    final textPtr = text.toNativeUtf8();
    final sourcePtr = source.toNativeUtf8();
    try {
      return _takeString(_captureTextJson(handle, textPtr, sourcePtr));
    } finally {
      malloc.free(textPtr);
      malloc.free(sourcePtr);
    }
  }

  String captureFileReference(
    ffi.Pointer<ffi.Void> handle,
    String path,
    String source,
  ) {
    final pathPtr = path.toNativeUtf8();
    final sourcePtr = source.toNativeUtf8();
    try {
      return _takeString(_captureFileReferenceJson(handle, pathPtr, sourcePtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(sourcePtr);
    }
  }

  String captureImage(
    ffi.Pointer<ffi.Void> handle,
    Uint8List bytes,
    String source,
  ) {
    final bytesPtr = malloc<ffi.Uint8>(bytes.length);
    final sourcePtr = source.toNativeUtf8();
    try {
      bytesPtr.asTypedList(bytes.length).setAll(0, bytes);
      return _takeString(
        _captureImageJson(handle, bytesPtr, bytes.length, sourcePtr),
      );
    } finally {
      malloc.free(bytesPtr);
      malloc.free(sourcePtr);
    }
  }

  void deleteItem(ffi.Pointer<ffi.Void> handle, String id) {
    final idPtr = id.toNativeUtf8();
    try {
      _deleteItem(handle, idPtr);
    } finally {
      malloc.free(idPtr);
    }
  }

  void setPinned(ffi.Pointer<ffi.Void> handle, String id, bool pinned) {
    final idPtr = id.toNativeUtf8();
    try {
      _setPinned(handle, idPtr, pinned);
    } finally {
      malloc.free(idPtr);
    }
  }

  void setTags(ffi.Pointer<ffi.Void> handle, String id, List<String> tags) {
    final idPtr = id.toNativeUtf8();
    final tagsPtr = jsonEncode(tags).toNativeUtf8();
    try {
      _setTagsJson(handle, idPtr, tagsPtr);
    } finally {
      malloc.free(idPtr);
      malloc.free(tagsPtr);
    }
  }

  void touchItem(ffi.Pointer<ffi.Void> handle, String id) {
    final idPtr = id.toNativeUtf8();
    try {
      _touchItem(handle, idPtr);
    } finally {
      malloc.free(idPtr);
    }
  }

  void applyRetention(
    ffi.Pointer<ffi.Void> handle,
    int maxItems,
    int maxStorageMb,
    bool preservePinned,
  ) {
    _applyRetention(handle, maxItems, maxStorageMb, preservePinned);
  }

  Uint8List? getBlob(ffi.Pointer<ffi.Void> handle, String id) {
    final idPtr = id.toNativeUtf8();
    final lenPtr = malloc<ffi.Size>();
    try {
      final ptr = _getBlob(handle, idPtr, lenPtr);
      final len = lenPtr.value;
      if (ptr == ffi.nullptr || len == 0) return null;
      final bytes = Uint8List.fromList(ptr.asTypedList(len));
      _blobFree(ptr, len);
      return bytes;
    } finally {
      malloc.free(idPtr);
      malloc.free(lenPtr);
    }
  }

  String lastError() {
    final decoded = jsonDecode(_takeString(_lastErrorJson()));
    if (decoded is Map<String, dynamic>) {
      return decoded['error']?.toString() ?? 'Không mở được OpenCB core';
    }
    return 'Không mở được OpenCB core';
  }

  String _takeString(ffi.Pointer<Utf8> ptr) {
    if (ptr == ffi.nullptr) return 'null';
    final value = ptr.toDartString();
    _stringFree(ptr);
    return value;
  }
}

int _sortClipboardEntries(ClipboardEntry a, ClipboardEntry b) {
  return b.createdAt.compareTo(a.createdAt);
}

typedef _NativeOpen =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _DartOpen =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _NativeClose = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _DartClose = void Function(ffi.Pointer<ffi.Void>);
typedef _NativeStringFree = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _DartStringFree = void Function(ffi.Pointer<Utf8>);
typedef _NativeLastErrorJson = ffi.Pointer<Utf8> Function();
typedef _DartLastErrorJson = ffi.Pointer<Utf8> Function();
typedef _NativeListItemsJson =
    ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>, ffi.Size, ffi.Size);
typedef _DartListItemsJson =
    ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>, int, int);
typedef _NativeCaptureTextJson =
    ffi.Pointer<Utf8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
    );
typedef _DartCaptureTextJson =
    ffi.Pointer<Utf8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
    );
typedef _NativeCaptureFileReferenceJson =
    ffi.Pointer<Utf8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
    );
typedef _DartCaptureFileReferenceJson =
    ffi.Pointer<Utf8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
    );
typedef _NativeCaptureImageJson =
    ffi.Pointer<Utf8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<Utf8>,
    );
typedef _DartCaptureImageJson =
    ffi.Pointer<Utf8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<Utf8>,
    );
typedef _NativeDeleteItem =
    ffi.Bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>);
typedef _DartDeleteItem =
    bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>);
typedef _NativeSetPinned =
    ffi.Bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>, ffi.Bool);
typedef _DartSetPinned =
    bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>, bool);
typedef _NativeSetTagsJson =
    ffi.Bool Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
    );
typedef _DartSetTagsJson =
    bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _NativeTouchItem =
    ffi.Bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>);
typedef _DartTouchItem =
    bool Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>);
typedef _NativeApplyRetention =
    ffi.IntPtr Function(ffi.Pointer<ffi.Void>, ffi.Size, ffi.Size, ffi.Bool);
typedef _DartApplyRetention =
    int Function(ffi.Pointer<ffi.Void>, int, int, bool);
typedef _NativeGetBlob =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Size>,
    );
typedef _DartGetBlob =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Size>,
    );
typedef _NativeBlobFree = ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _DartBlobFree = void Function(ffi.Pointer<ffi.Uint8>, int);

const int _defaultSyncPort = 47873;
const int _defaultFileTransferPort = 47874;
const String _syncProtocol = 'opencb_lan_text_v1';
const String _discoveryProtocol = 'opencb_lan_discovery_v1';
const String _fileTransferProtocol = 'opencb_lan_file_v1';
const int _androidFileWriteBatchBytes = 4 * 1024 * 1024;
const int _androidContentReadChunkBytes = 1024 * 1024;
