import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

const MethodChannel _rootPlatformChannel = MethodChannel('opencb/platform');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _configureAndroidEdgeToEdge();
  runApp(const OpenCbApp());
}

void _configureAndroidEdgeToEdge() {
  if (!Platform.isAndroid) return;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  _applyAndroidSystemUiStyle(
    Brightness.light,
    navigationBarColor: const Color(0xFFFBFEFC),
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
            'lightSystemBars': brightness == Brightness.light,
            'edgeToEdge': true,
          })
          .catchError((_) => false),
    );
  }
}

enum ClipboardKind { text, code, url, image, fileReference }

const double _compactDesktopLayoutBreakpoint = 1120;
const double _mobileLayoutBreakpoint = 840;
const int _defaultRetentionLimit = 2000;

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
      lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
      lastError: json['lastError'] as String?,
    );
  }

  final String id;
  final String name;
  final String host;
  final int port;
  final String pairCode;
  final DateTime? lastSyncedAt;
  final String? lastError;

  String get endpoint => '$host:$port';
  String get status => lastError == null ? 'Thiết bị tin cậy' : 'Lỗi sync';
  String get lastSynced {
    if (lastError != null) return lastError!;
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
    required this.lastSeenAt,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final DateTime lastSeenAt;

  String get endpoint => '$host:$port';

  SyncPeer toPeer({required String pairCode}) {
    return SyncPeer(
      id: id,
      name: name,
      host: host,
      port: port,
      pairCode: pairCode,
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
    required this.description,
    required this.seedColor,
  });

  final String id;
  final String name;
  final String description;
  final Color seedColor;
}

const List<M3ThemePreset> _m3ThemePresets = [
  M3ThemePreset(
    id: 'opencb_teal',
    name: 'Xanh OpenCB',
    description: 'Bình tĩnh, tập trung, hợp làm việc với clipboard',
    seedColor: Color(0xFF0E7C7B),
  ),
  M3ThemePreset(
    id: 'baseline_purple',
    name: 'Tím Material',
    description: 'Cảm giác Material You cổ điển',
    seedColor: Color(0xFF6750A4),
  ),
  M3ThemePreset(
    id: 'ocean_blue',
    name: 'Xanh Đại Dương',
    description: 'Sạch, rõ, hợp công cụ desktop',
    seedColor: Color(0xFF006A6A),
  ),
  M3ThemePreset(
    id: 'ink_blue',
    name: 'Mực Lam',
    description: 'Sắc xanh lam trầm, rõ nét nhưng không gắt',
    seedColor: Color(0xFF285EA8),
  ),
  M3ThemePreset(
    id: 'forest_green',
    name: 'Xanh Rừng',
    description: 'Dịu mắt, dễ tập trung',
    seedColor: Color(0xFF386A20),
  ),
  M3ThemePreset(
    id: 'sunset_coral',
    name: 'San Hô Hoàng Hôn',
    description: 'Ấm hơn, giàu sắc thái hơn',
    seedColor: Color(0xFFB3261E),
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
      androidBackgroundSync: false,
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
      autoSetClipboardFromSync:
          json['autoSetClipboardFromSync'] as bool? ?? true,
      captureText: json['captureText'] as bool? ?? true,
      captureImages: json['captureImages'] as bool? ?? true,
      captureFileReferences: json['captureFileReferences'] as bool? ?? true,
      quickOpenHotKey: QuickOpenHotKey.fromJson(
        json['quickOpenHotKey'] is Map<String, dynamic>
            ? json['quickOpenHotKey'] as Map<String, dynamic>
            : null,
      ),
      windowsAutoStart: json['windowsAutoStart'] as bool? ?? false,
      androidBackgroundSync: json['androidBackgroundSync'] as bool? ?? false,
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

class _OpenCbAppState extends State<OpenCbApp> {
  ThemeMode _themeMode = ThemeMode.light;
  M3ThemePreset _themePreset = _m3ThemePresets.first;

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
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _themePreset.seedColor,
      brightness: brightness,
    );
    _applyAndroidSystemUiStyle(
      brightness,
      navigationBarColor: colorScheme.surfaceContainerLowest,
    );
  }

  @override
  void initState() {
    super.initState();
    _applyCurrentAndroidSystemUiStyle();
    _loadThemeSettings();
  }

  Future<void> _loadThemeSettings() async {
    try {
      final file = await _themeFile();
      if (!await file.exists()) return;
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final preset = _presetById(decoded['presetId'] as String?);
      final mode = _themeModeFromName(decoded['themeMode'] as String?);
      if (!mounted) return;
      setState(() {
        _themePreset = preset;
        _themeMode = mode;
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OpenCB',
      theme: _buildTheme(Brightness.light, _themePreset),
      darkTheme: _buildTheme(Brightness.dark, _themePreset),
      themeMode: _themeMode,
      home: ClipboardHomePage(
        themeMode: _themeMode,
        themePreset: _themePreset,
        onThemeModeChanged: _setThemeMode,
        onThemePresetChanged: _setThemePreset,
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness, M3ThemePreset preset) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: preset.seedColor,
    brightness: brightness,
  );
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

class ClipboardHomePage extends StatefulWidget {
  const ClipboardHomePage({
    super.key,
    required this.themeMode,
    required this.themePreset,
    required this.onThemeModeChanged,
    required this.onThemePresetChanged,
  });

  final ThemeMode themeMode;
  final M3ThemePreset themePreset;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<M3ThemePreset> onThemePresetChanged;

  @override
  State<ClipboardHomePage> createState() => _ClipboardHomePageState();
}

class _ClipboardHomePageState extends State<ClipboardHomePage> {
  static const Duration _quickPickerExitDuration = Duration(milliseconds: 130);
  static const List<String> _mobileMainSections = [
    'Lịch sử',
    'Đã ghim',
    'Thẻ',
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
  Timer? _pollTimer;
  Timer? _autoSyncTimer;
  Timer? _discoveryTimer;
  ServerSocket? _syncServer;
  RawDatagramSocket? _discoverySocket;
  int _selectedIndex = 0;
  bool _capturePaused = false;
  bool _lanSyncEnabled = true;
  bool _loaded = false;
  bool _autoSyncInFlight = false;
  bool _quickPickerMode = false;
  bool _quickPickerClosing = false;
  bool _openingMainFromQuickPicker = false;
  bool _syncHostRefreshInFlight = false;
  bool _mobileSearchOpen = false;
  Future<void>? _quickPickerCloseFuture;
  final int _syncPort = _defaultSyncPort;
  String _syncHost = Platform.localHostname;
  String _section = 'Lịch sử';
  ClipboardKind? _kindFilter;
  String? _syncError;
  String? _lastClipboardText;
  OpenCbStorage? _storage;
  LocalSyncIdentity _syncIdentity = LocalSyncIdentity.create();
  ClipboardSettings _clipboardSettings = ClipboardSettings.defaults();
  Map<String, Uint8List> _sourceIcons = {};
  Map<String, TagDefinition> _tagDefinitions = {};
  Set<String> _tagFilters = {};
  Set<String> _bulkSelectedIds = {};
  bool _bulkSelectMode = false;
  String? _promotedEntryId;
  int _promotionToken = 0;
  final Set<String> _pendingDeleteIds = {};
  final Map<String, Timer> _pendingDeleteTimers = {};
  final Map<String, DateTime> _syncTombstones = {};
  final Map<String, DateTime> _peerDiscoveryRetryAfter = {};
  List<ClipboardEntry> _entries = [];
  List<SyncPeer> _peers = [];
  Map<String, DiscoveredSyncDevice> _discoveredDevices = {};

  @override
  void initState() {
    super.initState();
    _refreshSyncHost();
    _initializeStorage();
    _initializeSync();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _autoSyncTimer?.cancel();
    _discoveryTimer?.cancel();
    _discoverySocket?.close();
    for (final timer in _pendingDeleteTimers.values) {
      timer.cancel();
    }
    _syncServer?.close();
    _windowsClipboardChannel.setMethodCallHandler(null);
    _storage?.close();
    _mobilePageController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<ClipboardEntry> _visibleEntriesForSection(String section) {
    Iterable<ClipboardEntry> entries = _entries.where(
      (entry) => !_pendingDeleteIds.contains(entry.id),
    );
    if (section == 'Đã ghim') {
      entries = entries.where((entry) => entry.pinned);
    }
    if (section == 'Thẻ') {
      entries = entries.where((entry) => entry.tags.isNotEmpty);
    }
    if (_kindFilter != null) {
      entries = entries.where((entry) => entry.kind == _kindFilter);
    }
    if (_tagFilters.isNotEmpty) {
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
    await _startNativeClipboardBridge();
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
    setState(() => _clipboardSettings = settings);
    await _saveClipboardSettings();
    if (jsonEncode(previousSettings.quickOpenHotKey.toJson()) !=
        jsonEncode(settings.quickOpenHotKey.toJson())) {
      await _applyQuickOpenHotKey(settings.quickOpenHotKey);
    }
    if (previousSettings.windowsAutoStart != settings.windowsAutoStart) {
      await _applyWindowsAutoStart(settings.windowsAutoStart);
    }
    if (previousSettings.androidBackgroundSync !=
        settings.androidBackgroundSync) {
      await _applyAndroidBackgroundSyncPreference(
        settings.androidBackgroundSync,
      );
    }
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
              '"${Platform.resolvedExecutable}"',
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

  Future<void> _applyAndroidBackgroundSyncPreference(bool enabled) async {
    if (!Platform.isAndroid) return;
    if (!enabled) return;
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
    await _startLanDiscovery();
    _startAutoSync();
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
  }

  Future<void> _savePeers() async {
    final file = await _peersFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(_peers.map((peer) => peer.toJson()).toList()),
    );
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
      _discoveryTimer?.cancel();
      _discoveryTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(_sendDiscoveryBeacon()),
      );
    } catch (_) {}
  }

  void _stopLanDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    if (mounted) setState(() => _discoveredDevices = {});
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
    final payload = jsonEncode({
      'protocol': _discoveryProtocol,
      'deviceId': _syncIdentity.deviceId,
      'deviceName': _syncIdentity.deviceName,
      'host': beaconHost,
      'port': _syncPort,
    });
    final bytes = utf8.encode(payload);
    final targets = {
      for (final target in await _discoveryBroadcastTargets()) target.address,
      for (final peer in _peers)
        if (_isUsableLanIpv4(peer.host)) peer.host,
    };
    for (final target in targets) {
      try {
        socket.send(bytes, InternetAddress(target), _syncPort);
      } catch (_) {}
    }
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
        lastSeenAt: DateTime.now(),
      );
      _rememberDiscoveredDevice(discovered);
    } catch (_) {}
  }

  void _rememberDiscoveredDevice(DiscoveredSyncDevice device) {
    var shouldSavePeers = false;
    final peerIndex = _peers.indexWhere((peer) => peer.id == device.id);
    setState(() {
      _discoveredDevices = {..._discoveredDevices, device.id: device};
      if (peerIndex >= 0) {
        final peer = _peers[peerIndex];
        if (peer.host != device.host || peer.port != device.port) {
          _peers[peerIndex] = peer.copyWith(
            host: device.host,
            port: device.port,
            clearError: true,
          );
          shouldSavePeers = true;
        }
      }
    });
    if (shouldSavePeers) unawaited(_savePeers());
    if (peerIndex >= 0) _maybeRetryDiscoveredPeer(device.id);
  }

  void _pruneStaleDiscoveredDevices() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 18));
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
    final pairCode = payload['pairCode']?.toString().trim().toUpperCase();

    final updated = current.copyWith(
      id: remoteDeviceId,
      name: remoteName == null || remoteName.isEmpty ? null : remoteName,
      host: host != null && _isUsableLanIpv4(host) ? host : null,
      port: port != null && port > 0 && port <= 65535 ? port : null,
      pairCode: pairCode != null && pairCode.length >= 6 ? pairCode : null,
      lastSyncedAt: markSynced ? DateTime.now() : null,
      clearError: true,
    );
    final changed =
        updated.id != current.id ||
        updated.name != current.name ||
        updated.host != current.host ||
        updated.port != current.port ||
        updated.pairCode != current.pairCode ||
        updated.lastSyncedAt != current.lastSyncedAt ||
        updated.lastError != current.lastError;
    if (changed) _peers[index] = updated;
    return changed;
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
      await Clipboard.setData(ClipboardData(text: newestRealtimeBody));
      _lastClipboardText = newestRealtimeBody;
    }

    if (!changed) return;
    await storage.applyRetention(maxItems: _clipboardSettings.retentionLimit);
    await _loadEntries(captureCurrentClipboard: false);
    if (mounted) setState(() {});
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

  Future<void> _captureClipboardText() async {
    if (_capturePaused || !_loaded) return;
    if (!_clipboardSettings.captureText) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null) return;
    await _captureTextValue(text, source: 'Clipboard hệ thống');
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

  EdgeInsets _bottomCenterSnackBarMargin() {
    return const EdgeInsets.fromLTRB(16, 0, 16, 18);
  }

  void _showCenterSnackBar(
    String message, {
    Duration duration = const Duration(milliseconds: 1600),
    double maxWidth = 300,
  }) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: duration,
        margin: _bottomCenterSnackBarMargin(),
        padding: EdgeInsets.zero,
        content: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.inverseSurface,
                borderRadius: BorderRadius.circular(10),
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
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
      _showCenterSnackBar('Không có clipboard chưa ghim để dọn.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: const Icon(Icons.clear_all),
          title: const Text('Dọn clipboard'),
          content: Text('Xóa $unpinnedCount mục chưa ghim khỏi lịch sử.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const _ButtonLabel('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const _ButtonLabel('Dọn'),
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
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.restore_outlined),
          title: const Text('Khôi phục dữ liệu?'),
          content: Text(
            'Nhập $itemCount mục clipboard từ backup. '
            'Dữ liệu hiện có sẽ được giữ lại và gộp thêm dữ liệu trong file.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const _ButtonLabel('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const _ButtonLabel('Khôi phục'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final imported = await _restoreBackupPayload(decoded);
      if (!mounted) return;
      _showCenterSnackBar('Đã khôi phục $imported mục clipboard.');
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
      _showCenterSnackBar('Lịch sử clipboard đang trống.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_outlined),
        title: const Text('Xóa toàn bộ lịch sử?'),
        content: Text(
          'Thao tác này sẽ xóa ${_entries.length} mục clipboard đang lưu. '
          'Cài đặt, thẻ và thiết bị sync vẫn được giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const _ButtonLabel('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const _ButtonLabel('Xóa lịch sử'),
          ),
        ],
      ),
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
      await _startLanDiscovery();
    } else {
      await _stopSyncServer();
      _stopLanDiscovery();
    }
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
      accepted ? 'Đã kết nối ${peer.name}.' : 'Chưa ghép nối thiết bị.',
    );
  }

  Future<void> _scanAndAddPeer() async {
    final payload = await _showPairQrScanner(context);
    if (payload == null || !mounted) return;
    final peer = _parsePairPayload(payload);
    if (peer == null) {
      _showCenterSnackBar('QR pairing không hợp lệ.');
      return;
    }
    final accepted = await _sendPairRequest(peer);
    if (!mounted) return;
    _showCenterSnackBar(
      accepted ? 'Đã kết nối ${peer.name}.' : 'Chưa ghép nối thiết bị.',
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
      accepted ? 'Đã kết nối ${device.name}.' : 'Chưa ghép nối thiết bị.',
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
        return AlertDialog(
          icon: const Icon(Icons.devices_other_outlined),
          title: const Text('Ghép thiết bị?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${peer.name} muốn ghép nối với OpenCB trên thiết bị này.'),
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
              child: const _ButtonLabel('Từ chối'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const _ButtonLabel('Ghép nối'),
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
      title: 'Đổi tên thiết bị này',
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
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.link_off),
        title: const Text('Xóa thiết bị sync?'),
        content: Text(
          'Thiết bị "${peer.name}" sẽ bị xóa khỏi danh sách tin cậy. Nếu thiết bị kia đang online, OpenCB cũng sẽ gỡ kết nối ở bên đó.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const _ButtonLabel('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const _ButtonLabel('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _removePeer(peer);
  }

  Future<void> _renamePeer(SyncPeer peer) async {
    final name = await _showRenameDeviceDialog(
      title: 'Đổi tên thiết bị',
      initialName: peer.name,
    );
    if (name == null) return;
    final index = _peers.indexWhere((item) => item.id == peer.id);
    if (index < 0) return;
    setState(() => _peers[index] = peer.copyWith(name: name));
    await _savePeers();
  }

  Future<void> _testPeerConnection(SyncPeer peer) async {
    final index = _peers.indexWhere((item) => item.id == peer.id);
    try {
      final socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: const Duration(seconds: 3),
      );
      await socket.close();
      if (index >= 0) {
        setState(() {
          _peers[index] = peer.copyWith(
            lastSyncedAt: DateTime.now(),
            clearError: true,
          );
        });
      }
      _showCenterSnackBar('Kết nối ${peer.name} thành công.');
    } catch (error) {
      final message = _friendlySyncError(error);
      if (index >= 0) {
        setState(() => _peers[index] = peer.copyWith(lastError: message));
      }
      _showCenterSnackBar('Không kết nối được ${peer.name}.');
    }
    await _savePeers();
  }

  void _setKindFilter(ClipboardKind? kind) {
    setState(() {
      _kindFilter = kind;
      _selectedIndex = 0;
    });
  }

  void _toggleTagFilter(String tag) {
    setState(() {
      if (!_tagFilters.add(tag)) {
        _tagFilters.remove(tag);
      }
      _selectedIndex = 0;
    });
  }

  void _clearTagFilters() {
    setState(() {
      _tagFilters = {};
      _selectedIndex = 0;
    });
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
    _showCenterSnackBar(pinned ? 'Đã ghim các mục đã chọn.' : 'Đã bỏ ghim.');
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
    _showCenterSnackBar('Đã gắn thẻ cho ${selectedEntries.length} mục.');
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
    final currentPage = _mobilePageController.page?.round();
    if (currentPage == index) return;
    unawaited(
      _mobilePageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _selectSection(String section, {bool syncMobilePage = true}) {
    setState(() {
      _section = section;
      _selectedIndex = 0;
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

  void _toggleMobileSearch() {
    setState(() {
      if (!_isClipboardSection) {
        _section = 'Lịch sử';
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
    return switch (section ?? _section) {
      'Đã ghim' => 'Clipboard đã ghim',
      'Thẻ' => 'Clipboard có thẻ',
      _ => 'Lịch sử clipboard',
    };
  }

  String _historyEmptyMessage({
    String? section,
    required bool hasHistoryFilters,
  }) {
    if (hasHistoryFilters) {
      return 'Không có clipboard phù hợp với bộ lọc hiện tại.';
    }
    return switch (section ?? _section) {
      'Đã ghim' => 'Chưa có mục nào được ghim.',
      'Thẻ' => 'Chưa có mục nào có thẻ.',
      _ => 'Copy bất kỳ văn bản nào trên Windows, nội dung sẽ hiện ở đây.',
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
  }) {
    final hasHistoryFilters = _kindFilter != null || _tagFilters.isNotEmpty;
    final activeSection = section ?? _section;
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
      availableTags: _availableTags,
      selectedKind: _kindFilter,
      selectedTags: _tagFilters,
      bulkSelectMode: _bulkSelectMode,
      bulkSelectedIds: _bulkSelectedIds,
      selectedIndex: _selectedIndex,
      loaded: _loaded,
      compact: mobile || compact,
      bottomContentPadding: mobile ? 96 : 12,
      onKindSelected: _setKindFilter,
      onTagToggled: _toggleTagFilter,
      onClearTagFilters: _clearTagFilters,
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

    if (activeSection == 'Cài đặt') {
      return _SettingsPage(
        capturePaused: _capturePaused,
        storagePath: _historyFilePathPreview(),
        clipboardSettings: _clipboardSettings,
        sourceSuggestions: _knownSourceSuggestions(),
        themeMode: widget.themeMode,
        themePreset: widget.themePreset,
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
        onOpenDataDirectory: () => unawaited(_openDataDirectory()),
        onExportBackup: () => unawaited(_exportDataBackup()),
        onRestoreBackup: () => unawaited(_restoreDataBackup()),
        onResetClipboardHistory: () =>
            unawaited(_confirmResetClipboardHistory()),
        onOpenDevices: Platform.isAndroid
            ? () => _selectSection('Thiết bị')
            : null,
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
      section != 'Thiết bị' && section != 'Cài đặt';

  bool get _isClipboardSection => _isClipboardSectionFor(_section);

  Widget _buildMobileSectionContent({String? section}) {
    final activeSection = section ?? _section;
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
    final activeSection = section ?? _section;
    final isClipboardSection = _isClipboardSectionFor(activeSection);
    final isDevicesSubPage = activeSection == 'Thiết bị';
    final title = switch (activeSection) {
      'Thiết bị' => 'Thiết bị LAN',
      'Cài đặt' => 'Cài đặt',
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
              if (isDevicesSubPage) ...[
                IconButton(
                  tooltip: 'Quay về Cài đặt',
                  onPressed: () => _selectSection('Cài đặt'),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
              ],
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
          ),
        ),
      ),
    );
  }

  Widget _buildMobileScaffold() {
    final sections = <({IconData icon, IconData selectedIcon, String label})>[
      (
        icon: Icons.history_outlined,
        selectedIcon: Icons.history,
        label: 'Lịch sử',
      ),
      (
        icon: Icons.bookmark_border,
        selectedIcon: Icons.bookmark,
        label: 'Đã ghim',
      ),
      (icon: Icons.sell_outlined, selectedIcon: Icons.sell, label: 'Thẻ'),
      (
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'Cài đặt',
      ),
    ];
    final mobileSection = _section == 'Thiết bị' ? 'Cài đặt' : _section;
    final selectedIndex = sections.indexWhere(
      (section) => section.label == mobileSection,
    );
    Widget buildMobileMainPage(String section) {
      return KeyedSubtree(
        key: PageStorageKey<String>('mobile-$section'),
        child: Column(
          children: [
            _buildMobileTopBar(section: section),
            Expanded(child: _buildMobileSectionContent(section: section)),
          ],
        ),
      );
    }

    final showFloatingToolbar = _section != 'Thiết bị';
    final showMobileSearchButton = showFloatingToolbar;
    return PopScope(
      canPop: _section != 'Thiết bị',
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _section != 'Thiết bị') return;
        _selectSection('Cài đặt');
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
                    onPageChanged: (index) {
                      if (index < 0 || index >= sections.length) return;
                      _selectSection(
                        sections[index].label,
                        syncMobilePage: false,
                      );
                    },
                    children: [
                      for (final section in _mobileMainSections)
                        buildMobileMainPage(section),
                    ],
                  ),
                  if (_section == 'Thiết bị')
                    Positioned.fill(
                      child: Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLowest,
                        child: Column(
                          children: [
                            _buildMobileTopBar(),
                            Expanded(child: _buildMobileSectionContent()),
                          ],
                        ),
                      ),
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
                              child: _MobileFloatingToolbar(
                                items: sections,
                                selectedIndex: selectedIndex < 0
                                    ? 0
                                    : selectedIndex,
                                onSelected: (index) =>
                                    _selectSection(sections[index].label),
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
    final items = <({IconData icon, IconData selectedIcon, String label})>[
      (
        icon: Icons.history_outlined,
        selectedIcon: Icons.history,
        label: 'Lịch sử',
      ),
      (
        icon: Icons.bookmark_border,
        selectedIcon: Icons.bookmark,
        label: 'Đã ghim',
      ),
      (icon: Icons.sell_outlined, selectedIcon: Icons.sell, label: 'Thẻ'),
      (
        icon: Icons.devices_other_outlined,
        selectedIcon: Icons.devices_other,
        label: 'Thiết bị',
      ),
      (
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'Cài đặt',
      ),
    ];
    final selectedIndex = items.indexWhere(
      (item) => item.label == currentSection,
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
                      label: item.label,
                      selected: item.label == currentSection,
                      onPressed: () => onSectionChanged(item.label),
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
              padding: const EdgeInsets.only(left: 10),
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
                        Tooltip(message: item.label, child: Icon(item.icon)),
                      ),
                      selectedIcon: menuCursor(
                        Tooltip(
                          message: item.label,
                          child: Icon(item.selectedIcon),
                        ),
                      ),
                      label: menuCursor(Text(item.label)),
                    ),
                ],
                onDestinationSelected: (index) =>
                    onSectionChanged(items[index].label),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 12),
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
    final background = active
        ? Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.16),
            colorScheme.surfaceContainerHigh,
          )
        : colorScheme.surfaceContainerHigh;
    return Tooltip(
      message: active ? 'Ẩn tìm kiếm' : 'Tìm kiếm',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: ShapeDecoration(
          color: background,
          shape: const CircleBorder(),
          shadows: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: active ? 0.20 : 0.16),
              blurRadius: active ? 10 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          surfaceTintColor: colorScheme.primary,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            mouseCursor: SystemMouseCursors.click,
            splashColor: colorScheme.primary.withValues(alpha: 0.10),
            highlightColor: colorScheme.primary.withValues(alpha: 0.06),
            child: SizedBox.square(
              dimension: 56,
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
                  color: active ? Colors.black : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
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
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        mouseCursor: SystemMouseCursors.click,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          labelText: 'Tìm kiếm',
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: IconButton(
            tooltip: 'Xóa tìm kiếm',
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
    required this.onSelected,
  });

  final List<({IconData icon, IconData selectedIcon, String label})> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(0.0, constraints.maxWidth - 24);
        final showLabels = availableWidth >= 300;
        final activePillColor = Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.70),
          colorScheme.surfaceContainerHigh,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Material(
            color: colorScheme.surfaceContainerHigh,
            elevation: 3,
            shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
            surfaceTintColor: colorScheme.primary,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: LayoutBuilder(
                builder: (context, innerConstraints) {
                  const gap = 4.0;
                  final itemCount = items.length;
                  final totalGap = gap * math.max(0, itemCount - 1);
                  final itemWidth = itemCount == 0
                      ? 0.0
                      : math.max(
                          48.0,
                          (innerConstraints.maxWidth - totalGap) / itemCount,
                        );
                  final clampedSelectedIndex = itemCount == 0
                      ? 0
                      : selectedIndex.clamp(0, itemCount - 1).toInt();
                  final indicatorLeft =
                      clampedSelectedIndex * (itemWidth + gap);

                  return SizedBox(
                    height: 52,
                    child: Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOutCubic,
                          left: indicatorLeft,
                          top: 0,
                          width: itemWidth,
                          height: 52,
                          child: IgnorePointer(
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey(
                                'toolbar-pill-squash-$clampedSelectedIndex',
                              ),
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 420),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                final squash = math.sin(value * math.pi);
                                return Transform.scale(
                                  scaleX: 1 + squash * 0.025,
                                  scaleY: 1 - squash * 0.13,
                                  child: child,
                                );
                              },
                              child: DecoratedBox(
                                decoration: ShapeDecoration(
                                  color: activePillColor,
                                  shape: const StadiumBorder(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (
                              var index = 0;
                              index < items.length;
                              index++
                            ) ...[
                              Expanded(
                                child: _MobileFloatingToolbarItem(
                                  icon: items[index].icon,
                                  selectedIcon: items[index].selectedIcon,
                                  label: items[index].label,
                                  selected: index == selectedIndex,
                                  showLabel: showLabels,
                                  onPressed: () => onSelected(index),
                                ),
                              ),
                              if (index != items.length - 1)
                                const SizedBox(width: gap),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
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
    required this.label,
    required this.selected,
    required this.showLabel,
    required this.onPressed,
  });

  final IconData icon;
  final IconData selectedIcon;
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
    if (label == 'Cài đặt') {
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
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          mouseCursor: SystemMouseCursors.click,
          splashColor: colorScheme.primary.withValues(alpha: 0.10),
          highlightColor: colorScheme.primary.withValues(alpha: 0.06),
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
                      key: ValueKey('$label-$selected'),
                      tween: Tween<double>(
                        begin: 0,
                        end: selected && label == 'Cài đặt'
                            ? 2.5
                            : selected && label == 'Lịch sử'
                            ? -2
                            : 0,
                      ),
                      duration: const Duration(milliseconds: 620),
                      curve: Curves.easeOutCubic,
                      builder: (context, turns, child) {
                        return Transform.rotate(
                          angle: turns * math.pi * 2,
                          child: child,
                        );
                      },
                      child: AnimatedScale(
                        scale: selected ? 1.08 : 1,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutBack,
                        child: Icon(
                          selected ? selectedIcon : icon,
                          size: selected ? 21 : 20,
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
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w500,
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

class _CompactSidebarDestination extends StatelessWidget {
  const _CompactSidebarDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final IconData selectedIcon;
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
              child: Icon(selected ? selectedIcon : icon, color: foreground),
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
  });

  final String section;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearUnpinned;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isClipboardSection = section != 'Thiết bị' && section != 'Cài đặt';
    final title = switch (section) {
      'Thiết bị' => 'Thiết bị LAN',
      'Cài đặt' => 'Cài đặt',
      _ => 'Clipboard',
    };
    final subtitle = switch (section) {
      'Thiết bị' => '',
      'Cài đặt' => '',
      _ => 'Tìm nhanh trong lịch sử clipboard.',
    };
    return SizedBox(
      height: 76,
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: isClipboardSection
                    ? SizedBox(
                        height: 48,
                        child: TextField(
                          controller: searchController,
                          focusNode: searchFocusNode,
                          mouseCursor: SystemMouseCursors.click,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Tìm kiếm',
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            prefixIcon: const Icon(Icons.search, size: 20),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHigh,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
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
                  message: 'Xóa lịch sử chưa ghim',
                  child: IconButton.outlined(
                    onPressed: onClearUnpinned,
                    icon: const Icon(Icons.clear_all),
                  ),
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
  int _selectedIndex = 0;
  bool _pinned = false;
  bool _showPinnedOnly = false;

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
      return 'Không tìm thấy clipboard phù hợp với thẻ đã chọn.';
    }
    if (_selectedTagFilters.isNotEmpty) {
      return 'Không có clipboard nào trong thẻ đã chọn.';
    }
    if (_showPinnedOnly && hasQuery) {
      return 'Không tìm thấy clipboard đã ghim phù hợp.';
    }
    if (_showPinnedOnly) {
      return 'Chưa có clipboard nào được ghim.';
    }
    return 'Không tìm thấy clipboard phù hợp.';
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
    const itemExtent = 86.0;
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
          fixedSize: const Size.square(40),
          maximumSize: const Size.square(40),
          minimumSize: const Size.square(40),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 148,
                    child: Focus(
                      onKeyEvent: _handleKey,
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          mouseCursor: SystemMouseCursors.click,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Tìm kiếm',
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            prefixIcon: const Icon(Icons.search, size: 20),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                          onChanged: (_) => setState(() => _selectedIndex = 0),
                          onSubmitted: (_) => _selectFirstVisible(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HorizontalWheelScroll(
                      height: 38,
                      children: [
                        _ConnectedButtonGroup(
                          segments: [
                            _ConnectedButtonSegment(
                              label: 'Tất cả',
                              icon: Icons.all_inclusive,
                              selected: _selectedKindFilter == null,
                              iconOnly: true,
                              onPressed: () => _setKindFilter(null),
                            ),
                            for (final kind in ClipboardKind.values)
                              _ConnectedButtonSegment(
                                label: _quickPickerKindLabel(kind),
                                icon: _kindIcon(kind),
                                selected: _selectedKindFilter == kind,
                                iconOnly: true,
                                onPressed: () => _setKindFilter(kind),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _pinned
                        ? 'Đang ghim quick picker'
                        : 'Ghim quick picker',
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
                    message: 'Đóng',
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
                        ? 'Hiện tất cả clipboard'
                        : 'Chỉ hiện mục đã ghim',
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
                    message: 'Mở app chính',
                    child: IconButton(
                      style: quickPickerToolButtonStyle(),
                      onPressed: () => unawaited(widget.onOpenMainApp()),
                      icon: const Icon(Icons.open_in_new, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                        itemSpacing: 6,
                        itemBuilder: (context, entry, index) {
                          return _QuickPickerRow(
                            entry: entry,
                            tagDefinitions: widget.tagDefinitions,
                            selected: index == _selectedIndex,
                            onTogglePin: () => _toggleEntryPin(entry),
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
      height: 38,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: ScrollConfiguration(
          behavior: scrollBehavior,
          child: ListView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            children: [
              _ConnectedButtonGroup(
                segments: [
                  _ConnectedButtonSegment(
                    label: 'Tất cả',
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
                      maxLabelWidth: 112,
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
    required this.onTogglePin,
    required this.onSelected,
    required this.onOpenItem,
    required this.onDelete,
  });

  final ClipboardEntry entry;
  final Map<String, TagDefinition> tagDefinitions;
  final bool selected;
  final VoidCallback onTogglePin;
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
              padding: EdgeInsets.fromLTRB(selected ? 8 : 12, 12, 12, 12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: selected ? 4 : 0,
                    height: 52,
                    decoration: ShapeDecoration(
                      color: colorScheme.primary,
                      shape: const StadiumBorder(),
                    ),
                  ),
                  if (selected) const SizedBox(width: 8),
                  Icon(
                    _kindIcon(entry.kind),
                    size: 18,
                    color: selected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
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
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: selected
                                          ? colorScheme.onSecondaryContainer
                                          : colorScheme.onSurface,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (_hasUsableSourceIcon(entry)) ...[
                              _SourceAppIcon(entry: entry, dimension: 18),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                '${_quickPickerMetaKindLabel(entry.kind)} - ${_displaySourceLabel(entry.source)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: selected
                                          ? colorScheme.onSecondaryContainer
                                          : colorScheme.onSurfaceVariant,
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
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final tag in entry.tags.take(3))
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 122,
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
                    const SizedBox(width: 10),
                    _QuickPickerImageThumb(imageBytes: entry.imageBytes!),
                  ],
                  const SizedBox(width: 12),
                  Tooltip(
                    message: entry.pinned ? 'Bỏ ghim mục này' : 'Ghim mục này',
                    child: SizedBox.square(
                      dimension: 34,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          alignment: Alignment.center,
                          fixedSize: const Size.square(34),
                          maximumSize: const Size.square(34),
                          minimumSize: const Size.square(34),
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
                        iconSize: 18,
                        icon: Icon(
                          entry.pinned ? Icons.bookmark : Icons.bookmark_border,
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

class _QuickPickerImageThumb extends StatelessWidget {
  const _QuickPickerImageThumb({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 52,
        height: 52,
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
    final openLabel = switch (entry.kind) {
      ClipboardKind.url => 'Mở URL',
      ClipboardKind.fileReference => 'Mở thư mục',
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
              label: 'Copy',
              successLabel: 'Copied',
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
              label: 'Xóa',
              successLabel: 'Đã xóa',
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
    required this.availableTags,
    required this.selectedKind,
    required this.selectedTags,
    required this.bulkSelectMode,
    required this.bulkSelectedIds,
    required this.selectedIndex,
    required this.loaded,
    this.compact = false,
    this.bottomContentPadding = 12,
    required this.onKindSelected,
    required this.onTagToggled,
    required this.onClearTagFilters,
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
  });

  final String title;
  final String emptyMessage;
  final List<ClipboardEntry> entries;
  final Map<String, TagDefinition> tagDefinitions;
  final String? promotedEntryId;
  final int promotionToken;
  final List<String> availableTags;
  final ClipboardKind? selectedKind;
  final Set<String> selectedTags;
  final bool bulkSelectMode;
  final Set<String> bulkSelectedIds;
  final int selectedIndex;
  final bool loaded;
  final bool compact;
  final double bottomContentPadding;
  final ValueChanged<ClipboardKind?> onKindSelected;
  final ValueChanged<String> onTagToggled;
  final VoidCallback onClearTagFilters;
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allVisibleSelected =
        entries.isNotEmpty &&
        entries.every((entry) => bulkSelectedIds.contains(entry.id));
    final isTagSection = onManageTags != null;
    return Material(
      color: colorScheme.surface,
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
                        '${bulkSelectedIds.length} đã chọn',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Tooltip(
                      message: allVisibleSelected
                          ? 'Bỏ chọn tất cả đang hiển thị'
                          : 'Chọn tất cả đang hiển thị',
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
                      message: 'Thoát chọn nhiều',
                      child: IconButton(
                        onPressed: onToggleBulkSelectMode,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ] else if (!hideHeaderActions) ...[
                    if (isTagSection) ...[
                      Tooltip(
                        message: 'Tạo thẻ',
                        child: compact
                            ? IconButton.filledTonal(
                                onPressed: onManageTags,
                                icon: const Icon(Icons.add),
                              )
                            : FilledButton.tonalIcon(
                                onPressed: onManageTags,
                                icon: const Icon(Icons.add),
                                label: const _ButtonLabel('Tạo thẻ'),
                              ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (!compact) ...[
                      Text(
                        '${entries.length} mục',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Tooltip(
                      message: 'Chọn nhiều',
                      child: IconButton(
                        onPressed: entries.isEmpty
                            ? null
                            : onToggleBulkSelectMode,
                        icon: const Icon(Icons.checklist_outlined),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Dọn clipboard',
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
            availableTags: availableTags,
            tagDefinitions: tagDefinitions,
            selectedKind: selectedKind,
            selectedTags: selectedTags,
            compact: compact,
            onKindSelected: onKindSelected,
            onTagToggled: onTagToggled,
            onClearTagFilters: onClearTagFilters,
          ),
          Expanded(
            child: !loaded
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                ? _EmptyHistory(
                    message: emptyMessage,
                    actionLabel: isTagSection ? 'Tạo thẻ' : null,
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
                          onContextMenuOpened: () => onSelected(index),
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
                    tooltip: 'Lên đầu trang',
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
            ? 'Thao tác với mục đã chọn'
            : 'Chưa chọn mục nào',
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
              label: 'Ghim',
              onPressed: onPin,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.bookmark_remove_outlined,
              label: 'Bỏ ghim',
              onPressed: onUnpin,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.sell_outlined,
              label: 'Thẻ',
              onPressed: onTags,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.delete_outline,
              label: 'Xóa',
              successLabel: 'Đã xóa',
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
                      label: widget.successLabel,
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
  const _HorizontalWheelScroll({
    required this.height,
    required this.children,
    this.showOverflowHint = false,
  });

  final double height;
  final List<Widget> children;
  final bool showOverflowHint;

  @override
  State<_HorizontalWheelScroll> createState() => _HorizontalWheelScrollState();
}

class _HorizontalWheelScrollState extends State<_HorizontalWheelScroll> {
  late final ScrollController _scrollController;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_syncOverflowHint);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflowHint());
  }

  @override
  void didUpdateWidget(covariant _HorizontalWheelScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflowHint());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncOverflowHint);
    _scrollController.dispose();
    super.dispose();
  }

  void _syncOverflowHint() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final nextCanScrollForward = position.maxScrollExtent - position.pixels > 2;
    if (nextCanScrollForward == _canScrollForward) return;
    setState(() => _canScrollForward = nextCanScrollForward);
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

  void _scrollForward() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + 160).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
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
    final colorScheme = Theme.of(context).colorScheme;
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
                padding: EdgeInsets.only(
                  right: widget.showOverflowHint ? widget.height + 6 : 0,
                ),
                children: widget.children,
              ),
            ),
          ),
          if (widget.showOverflowHint)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_canScrollForward,
                child: AnimatedOpacity(
                  opacity: _canScrollForward ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          colorScheme.surface.withValues(alpha: 0),
                          colorScheme.surface,
                        ],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Material(
                        color: colorScheme.secondaryContainer,
                        shape: const StadiumBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          mouseCursor: SystemMouseCursors.click,
                          onTap: _scrollForward,
                          customBorder: const StadiumBorder(),
                          child: SizedBox.square(
                            dimension: widget.height,
                            child: Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
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
    required this.availableTags,
    required this.tagDefinitions,
    required this.selectedKind,
    required this.selectedTags,
    this.compact = false,
    required this.onKindSelected,
    required this.onTagToggled,
    required this.onClearTagFilters,
  });

  final List<String> availableTags;
  final Map<String, TagDefinition> tagDefinitions;
  final ClipboardKind? selectedKind;
  final Set<String> selectedTags;
  final bool compact;
  final ValueChanged<ClipboardKind?> onKindSelected;
  final ValueChanged<String> onTagToggled;
  final VoidCallback onClearTagFilters;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final tight = width < 380;
        final medium = width >= 380 && width < 520;
        final adaptiveCompact = compact || width < 560;
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
        final rowGap = tight ? 5.0 : 6.0;

        return Padding(
          padding: EdgeInsets.fromLTRB(tight ? 10 : 12, 0, tight ? 10 : 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: buttonHeight,
                width: double.infinity,
                child: _ConnectedButtonGroup(
                  expanded: adaptiveCompact,
                  height: buttonHeight,
                  iconSize: iconSize,
                  iconOnlyHorizontalPadding: iconPadding,
                  labelHorizontalPadding: labelPadding,
                  gap: groupGap,
                  segments: [
                    _ConnectedButtonSegment(
                      label: 'Tất cả',
                      icon: Icons.all_inclusive,
                      selected: selectedKind == null,
                      iconOnly: adaptiveCompact,
                      onPressed: () => onKindSelected(null),
                    ),
                    for (final kind in ClipboardKind.values)
                      _ConnectedButtonSegment(
                        label: _shortKindLabel(kind),
                        icon: _kindIcon(kind),
                        selected: selectedKind == kind,
                        iconOnly: adaptiveCompact,
                        onPressed: () => onKindSelected(kind),
                      ),
                  ],
                ),
              ),
              if (availableTags.isNotEmpty) ...[
                SizedBox(height: rowGap),
                _HorizontalWheelScroll(
                  height: buttonHeight,
                  showOverflowHint: true,
                  children: [
                    _ConnectedButtonGroup(
                      height: buttonHeight,
                      iconSize: iconSize,
                      iconOnlyHorizontalPadding: iconPadding,
                      labelHorizontalPadding: labelPadding,
                      gap: groupGap,
                      segments: [
                        _ConnectedButtonSegment(
                          label: 'Tất cả',
                          icon: Icons.all_inclusive,
                          selected: selectedTags.isEmpty,
                          iconOnly: false,
                          hideIcon: true,
                          horizontalPadding: iconPadding,
                          maxLabelWidth: tight ? 58 : 72,
                          onPressed: onClearTagFilters,
                        ),
                        for (final tag in availableTags)
                          _ConnectedButtonSegment(
                            label: tag,
                            icon: selectedTags.contains(tag)
                                ? Icons.check
                                : tagDefinitions[tag]?.icon ??
                                      Icons.sell_outlined,
                            selected: selectedTags.contains(tag),
                            iconColor:
                                tagDefinitions[tag]?.color ??
                                colorScheme.tertiary,
                            maxLabelWidth: tight
                                ? 82
                                : medium
                                ? 104
                                : adaptiveCompact
                                ? 118
                                : 128,
                            iconOnly: false,
                            onPressed: () => onTagToggled(tag),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
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
    this.hideIcon = false,
    this.horizontalPadding,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final Color? iconColor;
  final double? maxLabelWidth;
  final bool iconOnly;
  final bool hideIcon;
  final double? horizontalPadding;
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
          mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (var index = 0; index < widget.segments.length; index++) ...[
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
                    iconOnlyHorizontalPadding: widget.iconOnlyHorizontalPadding,
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
            horizontal:
                segment.horizontalPadding ??
                (segment.iconOnly
                    ? iconOnlyHorizontalPadding
                    : labelHorizontalPadding),
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
              if (!segment.hideIcon)
                Icon(segment.icon, size: iconSize, color: iconColor),
              if (!segment.iconOnly) ...[
                if (!segment.hideIcon) SizedBox(width: height <= 34 ? 5 : 7),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: segment.maxLabelWidth ?? 96,
                  ),
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
                ),
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
            child: InkWell(
              borderRadius: borderRadius,
              mouseCursor: SystemMouseCursors.click,
              onTap: widget.onTap,
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
                              _SourceAppIcon(
                                entry: widget.entry,
                                dimension: 18,
                              ),
                              const SizedBox(width: 6),
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
              label: 'Copy',
              successLabel: 'Copied',
              actionDelay: const Duration(milliseconds: 260),
              onPressed: onCopy,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: pinned ? Icons.bookmark : Icons.bookmark_border,
              label: pinned ? 'Bỏ ghim' : 'Ghim',
              onPressed: onTogglePin,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.sell_outlined,
              label: 'Thẻ',
              onPressed: onEditTags,
            ),
            const SizedBox(height: 8),
            _ExpressiveFabMenuAction(
              icon: Icons.delete_outline,
              label: 'Xóa',
              successLabel: 'Đã xóa',
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
    final fallback = Icon(
      _kindIcon(entry.kind),
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

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.entry,
    this.compact = false,
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
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
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
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                                _kindLabel(entry.kind),
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
                          if (compact)
                            _MotionFeedbackIconButton(
                              icon: Icons.copy,
                              tooltip: 'Copy vào clipboard',
                              onPressed: onRestore,
                            )
                          else
                            Tooltip(
                              message: 'Copy vào clipboard',
                              child: _MotionFeedbackButton(
                                onPressed: onRestore,
                                icon: Icons.copy,
                                label: 'Copy',
                                successLabel: 'Copied',
                                variant:
                                    _MotionFeedbackButtonVariant.filledTonal,
                              ),
                            ),
                          if (entry.kind == ClipboardKind.url)
                            Tooltip(
                              message: 'Mở URL bằng trình duyệt mặc định',
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
                                      label: const _ButtonLabel('Mở URL'),
                                    ),
                            ),
                          if (entry.kind == ClipboardKind.fileReference)
                            Tooltip(
                              message: 'Mở thư mục chứa file',
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
                                      label: const _ButtonLabel('Mở thư mục'),
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
                            message: entry.pinned ? 'Bỏ ghim' : 'Ghim',
                            child: iconOnlyActions
                                ? IconButton.filledTonal(
                                    onPressed: onTogglePin,
                                    style: detailIconButtonStyle,
                                    icon: Icon(
                                      entry.pinned
                                          ? Icons.bookmark
                                          : Icons.bookmark_border,
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
                                      entry.pinned ? 'Đã ghim' : 'Ghim',
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Thẻ',
                            child: iconOnlyActions
                                ? IconButton.filledTonal(
                                    onPressed: onEditTags,
                                    style: detailIconButtonStyle,
                                    icon: const Icon(Icons.sell_outlined),
                                  )
                                : FilledButton.tonalIcon(
                                    onPressed: onEditTags,
                                    style: detailActionButtonStyle,
                                    icon: const Icon(Icons.sell_outlined),
                                    label: const _ButtonLabel('Thẻ'),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          _MotionFeedbackButton(
                            onPressed: onDelete,
                            icon: Icons.delete_outline,
                            label: 'Xóa',
                            successLabel: 'Đã xóa',
                            variant: _MotionFeedbackButtonVariant.filledTonal,
                            destructive: true,
                            actionDelay: const Duration(milliseconds: 320),
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
        ],
      ),
    );
  }
}

class _NoSelectionPanel extends StatelessWidget {
  const _NoSelectionPanel();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 180,
      child: Center(
        child: Text('Chọn một mục clipboard để xem trước và sao chép lại.'),
      ),
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
    final previewName = _normalizeTagName(_controller.text).isEmpty
        ? 'thẻ-mới'
        : _normalizeTagName(_controller.text);
    final previewDefinition = TagDefinition(
      name: previewName,
      colorValue: _selectedColorValue,
      iconKey: _selectedIconKey,
    );
    return AlertDialog(
      title: Text(widget.libraryOnly ? 'Thư viện thẻ' : 'Gắn thẻ'),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      buttonPadding: const EdgeInsets.symmetric(horizontal: 4),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: math.min(MediaQuery.sizeOf(context).height * 0.72, 640),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.libraryOnly) ...[
                _TagEditorSection(
                  title: 'Đang gắn',
                  child: _selectedTags.isEmpty
                      ? Text(
                          'Chưa có thẻ',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in _selectedTags)
                              _AttachedTagChip(
                                label: tag,
                                definition: _definitions[tag],
                                onPressed: () => _pickTagForEditing(tag),
                                onDeleted: () {
                                  setState(() => _selectedTags.remove(tag));
                                },
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
              ],
              _TagEditorSection(
                title: 'Thư viện thẻ',
                child: _allTags.isEmpty
                    ? Text(
                        'Chưa có thẻ',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in _allTags)
                            _TagLibraryChip(
                              label: tag,
                              definition: _definitions[tag],
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
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              _TagEditorSection(
                title: 'Thiết kế thẻ',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _TagBadge(
                          label: previewName,
                          definition: previewDefinition,
                        ),
                        SizedBox(
                          width: 260,
                          child: TextField(
                            controller: _controller,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addOrUpdateTag(),
                            decoration: const InputDecoration(
                              labelText: 'Tên thẻ',
                              hintText: 'cong-viec, sync, y-tuong',
                            ),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _addOrUpdateTag,
                          icon: const Icon(Icons.add),
                          label: const _ButtonLabel('Thêm / cập nhật'),
                        ),
                      ],
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
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: _tagColorController,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _applyCustomColor(),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'Màu tùy chỉnh',
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
                            tooltip: 'Áp dụng màu',
                            onPressed: _applyCustomColor,
                            icon: const Icon(Icons.check),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in _tagIconOptions)
                          IconButton.filledTonal(
                            isSelected: _selectedIconKey == option.key,
                            tooltip: option.key,
                            onPressed: () {
                              setState(() => _selectedIconKey = option.key);
                            },
                            icon: Icon(option.icon),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const _ButtonLabel('Hủy'),
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
          child: const _ButtonLabel('Lưu'),
        ),
      ],
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
  });

  final String label;
  final TagDefinition? definition;
  final VoidCallback onPressed;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
          onTap: onPressed,
        ),
        _TagGroupDivider(color: tagColor.withValues(alpha: 0.36)),
        _TagGroupIconButton(
          icon: Icons.close,
          tooltip: 'Bỏ thẻ',
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
  });

  final String label;
  final TagDefinition? definition;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
          onTap: () => onSelected(!selected),
        ),
        _TagGroupDivider(color: borderColor),
        _TagGroupIconButton(
          icon: Icons.edit_outlined,
          tooltip: 'Sửa màu và icon',
          backgroundColor: containerColor,
          foregroundColor: colorScheme.onSurfaceVariant,
          borderRadius: BorderRadius.zero,
          onTap: onEdit,
        ),
        _TagGroupDivider(color: borderColor),
        _TagGroupIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Xóa thẻ',
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
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color foregroundColor;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      child: InkWell(
        borderRadius: borderRadius,
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34, maxWidth: 190),
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
    return AlertDialog(
      icon: const Icon(Icons.drive_file_rename_outline),
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Tên thiết bị',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const _ButtonLabel('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const _ButtonLabel('Lưu')),
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
        _payloadError =
            'Payload không hợp lệ. Hãy dán mã bắt đầu bằng opencb://pair.';
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
      setState(() => _payloadError = 'Host và port không hợp lệ.');
      return;
    }
    final pairCode = _pairCodeController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    if (pairCode.length < 6) {
      setState(() => _payloadError = 'Mã pairing phải có ít nhất 6 ký tự.');
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
    return AlertDialog(
      title: const Text('Thêm thiết bị LAN'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _pairPayloadController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Payload pairing',
                  hintText: 'Dán opencb://pair?... từ máy kia',
                  border: const OutlineInputBorder(),
                  errorText: _payloadError,
                ),
                onSubmitted: (_) => _applyPairPayload(),
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
                      label: const _ButtonLabel('Áp dụng payload'),
                    ),
                    if (Platform.isAndroid)
                      OutlinedButton.icon(
                        onPressed: _scanQrPayload,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const _ButtonLabel('Quét QR'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Tên thiết bị'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _endpointController,
                decoration: const InputDecoration(
                  labelText: 'Host và port',
                  hintText: '192.168.1.10:47873',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pairCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Mã pairing của thiết bị kia',
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
          child: const _ButtonLabel('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const _ButtonLabel('Thêm')),
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
      setState(() => _errorText = 'Nhập mã đang hiển thị trên thiết bị kia.');
      return;
    }
    Navigator.of(context).pop(widget.device.toPeer(pairCode: code));
  }

  Future<void> _scanQr() async {
    final payload = await _showPairQrScanner(context);
    if (payload == null || !mounted) return;
    final peer = _parsePairPayload(payload);
    if (peer == null) {
      setState(() => _errorText = 'QR pairing không hợp lệ.');
      return;
    }
    if (peer.id != widget.device.id) {
      setState(() => _errorText = 'QR này thuộc thiết bị khác.');
      return;
    }
    Navigator.of(context).pop(peer);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.verified_user_outlined),
      title: const Text('Xác nhận kết nối'),
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
                labelText: 'Mã trên thiết bị kia',
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
                label: const _ButtonLabel('Quét QR thay vì nhập mã'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const _ButtonLabel('Hủy'),
        ),
        FilledButton(
          onPressed: _submitCode,
          child: const _ButtonLabel('Kết nối'),
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
    return AlertDialog(
      title: const Text('Quét QR pairing'),
      content: SizedBox(
        width: 360,
        height: 360,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: MobileScanner(
            controller: _controller,
            onDetect: _handleDetect,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const _ButtonLabel('Hủy'),
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
    final discoveredById = {
      for (final device in discoveredDevices) device.id: device,
    };
    final unpairedDevices = discoveredDevices
        .where((device) => !peers.any((peer) => peer.id == device.id))
        .toList();
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: ListView(
        padding: const EdgeInsets.all(24),
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

              if (constraints.maxWidth < 980) {
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
    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.tonalIcon(
          onPressed: onAddPeer,
          icon: const Icon(Icons.keyboard_alt_outlined),
          label: const _ButtonLabel('Nhập payload'),
        ),
        if (onScanPairQr != null) ...[
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onScanPairQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const _ButtonLabel('Quét QR'),
          ),
        ],
      ],
    );
    return _SettingsCard(
      icon: Icons.add_link,
      title: 'Ghép thiết bị mới',
      subtitle: '',
      trailing: actionButtons,
      child: const SizedBox.shrink(),
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
    return _SettingsCard(
      icon: Icons.verified_user_outlined,
      title: 'Thiết bị đã ghép',
      subtitle: '',
      trailing: _MiniChip(label: '${peers.length} thiết bị'),
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
                    'Chưa ghép thiết bị LAN nào.',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Khi thiết bị được xác nhận bằng mã hoặc QR, thiết bị sẽ xuất hiện ở đây.',
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
                      label: const _ButtonLabel('Thêm thiết bị'),
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

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.capturePaused,
    required this.storagePath,
    required this.clipboardSettings,
    required this.sourceSuggestions,
    required this.themeMode,
    required this.themePreset,
    required this.onToggleCapture,
    required this.onRetentionLimitChanged,
    required this.onClipboardSettingsChanged,
    required this.onAddExcludedSource,
    required this.onRemoveExcludedSource,
    required this.onThemeModeChanged,
    required this.onThemePresetChanged,
    required this.onOpenDataDirectory,
    required this.onExportBackup,
    required this.onRestoreBackup,
    required this.onResetClipboardHistory,
    this.onOpenDevices,
  });

  final bool capturePaused;
  final String storagePath;
  final ClipboardSettings clipboardSettings;
  final List<String> sourceSuggestions;
  final ThemeMode themeMode;
  final M3ThemePreset themePreset;
  final VoidCallback onToggleCapture;
  final ValueChanged<int> onRetentionLimitChanged;
  final ValueChanged<ClipboardSettings> onClipboardSettingsChanged;
  final ValueChanged<String> onAddExcludedSource;
  final ValueChanged<String> onRemoveExcludedSource;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<M3ThemePreset> onThemePresetChanged;
  final VoidCallback onOpenDataDirectory;
  final VoidCallback onExportBackup;
  final VoidCallback onRestoreBackup;
  final VoidCallback onResetClipboardHistory;
  final VoidCallback? onOpenDevices;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          onOpenDevices != null ? 112 : 24,
        ),
        children: [
          if (onOpenDevices != null) ...[
            _SettingsNavigationRow(
              icon: Icons.devices_other_outlined,
              title: 'Thiết bị LAN',
              subtitle: 'Ghép thiết bị, quét QR và quản lý sync.',
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
              );
              Widget buildStorageToolsPanel() => _StorageToolsPanel(
                storagePath: storagePath,
                onOpenDataDirectory: onOpenDataDirectory,
                onExportBackup: onExportBackup,
                onRestoreBackup: onRestoreBackup,
                onResetClipboardHistory: onResetClipboardHistory,
              );
              Widget buildThemeSettingsPanel() => _ThemeSettingsPanel(
                themeMode: themeMode,
                selectedPreset: themePreset,
                onThemeModeChanged: onThemeModeChanged,
                onThemePresetChanged: onThemePresetChanged,
              );

              final leftColumn = buildClipboardSettingsPanel();
              final rightColumn = Column(
                children: [
                  buildThemeSettingsPanel(),
                  const SizedBox(height: 16),
                  buildStorageToolsPanel(),
                ],
              );
              if (constraints.maxWidth < 900) {
                return Column(
                  children: [
                    buildThemeSettingsPanel(),
                    const SizedBox(height: 16),
                    buildClipboardSettingsPanel(),
                    const SizedBox(height: 16),
                    buildStorageToolsPanel(),
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

class _StorageToolsPanel extends StatelessWidget {
  const _StorageToolsPanel({
    required this.storagePath,
    required this.onOpenDataDirectory,
    required this.onExportBackup,
    required this.onRestoreBackup,
    required this.onResetClipboardHistory,
  });

  final String storagePath;
  final VoidCallback onOpenDataDirectory;
  final VoidCallback onExportBackup;
  final VoidCallback onRestoreBackup;
  final VoidCallback onResetClipboardHistory;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _SettingsCard(
      icon: Icons.folder_copy_outlined,
      title: 'Dữ liệu cục bộ',
      subtitle: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: ShapeDecoration(
              color: colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Text(
              storagePath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _TwoByTwoActionGrid(
            children: [
              _StorageActionButton(
                filled: true,
                onPressed: onOpenDataDirectory,
                icon: Icons.folder_open_outlined,
                label: 'Mở thư mục',
              ),
              _StorageActionButton(
                onPressed: onExportBackup,
                icon: Icons.download_outlined,
                label: 'Tạo backup',
              ),
              _StorageActionButton(
                onPressed: onRestoreBackup,
                icon: Icons.restore_outlined,
                label: 'Khôi phục',
              ),
              _StorageActionButton(
                onPressed: onResetClipboardHistory,
                icon: Icons.delete_sweep_outlined,
                label: 'Xóa lịch sử',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TwoByTwoActionGrid extends StatelessWidget {
  const _TwoByTwoActionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    assert(children.length == 4);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 8),
            Expanded(child: children[1]),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: children[2]),
            const SizedBox(width: 8),
            Expanded(child: children[3]),
          ],
        ),
      ],
    );
  }
}

class _StorageActionButton extends StatelessWidget {
  const _StorageActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.filled = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = _ButtonLabel(label);
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: filled
          ? FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: child,
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: child,
            ),
    );
  }
}

class _ThemeSettingsPanel extends StatelessWidget {
  const _ThemeSettingsPanel({
    required this.themeMode,
    required this.selectedPreset,
    required this.onThemeModeChanged,
    required this.onThemePresetChanged,
  });

  final ThemeMode themeMode;
  final M3ThemePreset selectedPreset;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<M3ThemePreset> onThemePresetChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.palette_outlined,
      title: 'Giao diện',
      subtitle: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chế độ hiển thị',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Center(
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: _ButtonLabel('Sáng'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: _ButtonLabel('Hệ thống'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: _ButtonLabel('Tối'),
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
            'Bảng màu Material You',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const columns = 2;
              const spacing = 8.0;
              final chipWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: 8,
                children: [
                  for (final preset in _m3ThemePresets)
                    SizedBox(
                      width: chipWidth,
                      child: FilterChip(
                        selected: selectedPreset.id == preset.id,
                        showCheckmark: false,
                        avatar: _ThemeSwatch(color: preset.seedColor),
                        label: SizedBox(
                          width: double.infinity,
                          child: Text(
                            preset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        tooltip: preset.description,
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
  });

  final ClipboardSettings settings;
  final bool capturePaused;
  final List<String> sourceSuggestions;
  final VoidCallback onToggleCapture;
  final ValueChanged<int> onRetentionLimitChanged;
  final ValueChanged<ClipboardSettings> onSettingsChanged;
  final ValueChanged<String> onAddExcludedSource;
  final ValueChanged<String> onRemoveExcludedSource;

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
    final retentionValue = _pendingRetentionLimit.toDouble();
    final isAndroid = Platform.isAndroid;
    return Column(
      children: [
        if (!isAndroid) ...[
          _SettingsSwitchRow(
            icon: widget.capturePaused
                ? Icons.pause_circle_outline
                : Icons.check_circle_outline,
            title: 'Bắt clipboard',
            subtitle: widget.capturePaused
                ? 'Tạm dừng toàn bộ việc lưu clipboard mới.'
                : 'Theo dõi clipboard trong nền.',
            value: !widget.capturePaused,
            onChanged: (_) => widget.onToggleCapture(),
          ),
          const SizedBox(height: 8),
        ],
        _SettingsSwitchRow(
          icon: Icons.notes,
          title: 'Văn bản và URL',
          subtitle: 'Lưu text, tự nhận diện URL để mở nhanh.',
          value: widget.settings.captureText,
          onChanged: (value) => widget.onSettingsChanged(
            widget.settings.copyWith(captureText: value),
          ),
        ),
        const SizedBox(height: 8),
        _SettingsSwitchRow(
          icon: Icons.image_outlined,
          title: 'Hình ảnh',
          subtitle: 'Lưu ảnh clipboard khi app nguồn cung cấp dữ liệu ảnh.',
          value: widget.settings.captureImages,
          onChanged: (value) => widget.onSettingsChanged(
            widget.settings.copyWith(captureImages: value),
          ),
        ),
        const SizedBox(height: 8),
        if (!isAndroid) ...[
          _SettingsSwitchRow(
            icon: Icons.insert_drive_file_outlined,
            title: 'Đường dẫn file/folder',
            subtitle: 'Chỉ lưu đường dẫn, không lưu nội dung file thật.',
            value: widget.settings.captureFileReferences,
            onChanged: (value) => widget.onSettingsChanged(
              widget.settings.copyWith(captureFileReferences: value),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsSwitchRow(
            icon: Icons.keyboard_tab_outlined,
            title: 'Tự dán từ chọn nhanh',
            subtitle:
                'Khi chọn item trong quick picker, tự paste vào ô đang nhập.',
            value: widget.settings.autoPasteFromQuickPicker,
            onChanged: (value) => widget.onSettingsChanged(
              widget.settings.copyWith(autoPasteFromQuickPicker: value),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SettingsSwitchRow(
          icon: Icons.sync_alt_outlined,
          title: 'Tự đặt clipboard khi nhận sync',
          subtitle: 'Đặt luôn vào clipboard hệ thống khi nhận sync.',
          value: widget.settings.autoSetClipboardFromSync,
          onChanged: (value) => widget.onSettingsChanged(
            widget.settings.copyWith(autoSetClipboardFromSync: value),
          ),
        ),
        const SizedBox(height: 8),
        if (isAndroid) ...[
          _SettingsSwitchRow(
            icon: Icons.battery_saver_outlined,
            title: 'Giảm tối ưu pin cho Sync LAN',
            subtitle: 'Mở cài đặt Android để cho OpenCB chạy nền ổn hơn.',
            value: widget.settings.androidBackgroundSync,
            onChanged: (value) => widget.onSettingsChanged(
              widget.settings.copyWith(androidBackgroundSync: value),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (!isAndroid) ...[
          _SettingsSwitchRow(
            icon: Icons.login,
            title: 'Tự mở cùng Windows',
            subtitle: 'Đăng ký OpenCB trong Startup của tài khoản hiện tại.',
            value: widget.settings.windowsAutoStart,
            onChanged: (value) => widget.onSettingsChanged(
              widget.settings.copyWith(windowsAutoStart: value),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsSwitchRow(
            icon: Icons.keyboard_command_key,
            title: 'Phím tắt mở chọn nhanh',
            subtitle: widget.settings.quickOpenHotKey.enabled
                ? widget.settings.quickOpenHotKey.label
                : 'Đang tắt',
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
              label: const _ButtonLabel('Đổi phím tắt'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SettingsCard(
          icon: Icons.inventory_2_outlined,
          title: 'Lưu trữ',
          subtitle: '',
          trailing: _MiniChip(
            label: _formatClipboardCount(_pendingRetentionLimit),
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
        const SizedBox(height: 16),
        _SettingsCard(
          icon: Icons.visibility_off_outlined,
          title: 'Ứng dụng loại trừ',
          subtitle: 'Không lưu clipboard khi nguồn thuộc danh sách này.',
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
                        labelText: 'Tên ứng dụng nguồn',
                        hintText: 'Chrome, 1Password, KeePass...',
                      ),
                      onSubmitted: _addSource,
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: () => _addSource(_excludedSourceController.text),
                    icon: const Icon(Icons.add),
                    label: const _ButtonLabel('Thêm'),
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
                  'Chưa loại trừ ứng dụng nào.',
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
                        onDeleted: () => widget.onRemoveExcludedSource(source),
                      ),
                  ],
                ),
            ],
          ),
        ),
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
        setState(() => _errorText = 'Phím này chưa được hỗ trợ.');
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
      setState(
        () =>
            _errorText = 'Hãy dùng ít nhất một phím Ctrl, Alt, Shift hoặc Win.',
      );
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
    final hotKey = _recordedHotKey ?? widget.initialHotKey;
    return AlertDialog(
      icon: const Icon(Icons.keyboard_alt_outlined),
      title: const Text('Đổi phím tắt'),
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
                'Nhấn tổ hợp phím muốn dùng để mở chọn nhanh.',
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
          child: const _ButtonLabel('Hủy'),
        ),
        FilledButton(
          onPressed: _recordedHotKey == null
              ? null
              : () => Navigator.of(context).pop(_recordedHotKey),
          child: const _ButtonLabel('Lưu'),
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
    final roundedValue = _normalizeRetentionLimit(value.round());
    final labelStyle = textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Semantics(
      label: 'Giới hạn lưu clipboard',
      value: _formatClipboardCount(roundedValue),
      increasedValue: _formatClipboardCount(
        _normalizeRetentionLimit(roundedValue + 200),
      ),
      decreasedValue: _formatClipboardCount(
        _normalizeRetentionLimit(roundedValue - 200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Giới hạn lưu', style: labelStyle),
              const Spacer(),
              Text(
                _formatClipboardCount(roundedValue),
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
              label: _formatClipboardCount(roundedValue),
              semanticFormatterCallback: (value) => _formatClipboardCount(
                _normalizeRetentionLimit(value.round()),
              ),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(_formatClipboardCount(_min.toInt()), style: labelStyle),
                const Spacer(),
                Text(_formatClipboardCount(_max.toInt()), style: labelStyle),
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

enum _MotionFeedbackButtonVariant { filled, filledTonal, outlined }

class _AnimatedFeedbackLabel extends StatelessWidget {
  const _AnimatedFeedbackLabel({
    required this.showFeedback,
    required this.icon,
    required this.label,
    required this.successLabel,
    this.color,
  });

  final bool showFeedback;
  final IconData icon;
  final String label;
  final String successLabel;
  final Color? color;

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
  });

  final IconData icon;
  final String label;
  final Color? color;

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
        Text(label, style: effectiveStyle),
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
    this.destructive = false,
    this.actionDelay = Duration.zero,
  });

  final IconData icon;
  final String label;
  final FutureOr<void> Function()? onPressed;
  final String successLabel;
  final _MotionFeedbackButtonVariant variant;
  final bool destructive;
  final Duration actionDelay;

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
      if (widget.actionDelay > Duration.zero) {
        await Future<void>.delayed(widget.actionDelay);
      }
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
    );
  }

  Widget _plainContent({required IconData icon, required String label}) {
    return _FeedbackLabelRow(icon: icon, label: label);
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
    final hasError = syncError != null;
    return _SettingsCard(
      icon: hasError ? Icons.error_outline : Icons.computer,
      title: 'Thiết bị này',
      subtitle: '',
      trailing: _MiniChip(label: lanSyncEnabled ? 'Port $syncPort' : 'Tắt'),
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
                      message: 'Đổi tên thiết bị này',
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
                  syncError ?? '$syncHost:$syncPort',
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _M3Badge(
                label: identity.pairCode,
                icon: Icons.key_outlined,
                tone: _M3BadgeTone.primary,
              ),
              _M3Badge(
                label: lanSyncEnabled ? 'Đang quảng bá LAN' : 'Đã tắt',
                icon: lanSyncEnabled
                    ? Icons.wifi_tethering
                    : Icons.cloud_off_outlined,
                tone: lanSyncEnabled
                    ? _M3BadgeTone.selected
                    : _M3BadgeTone.surface,
              ),
            ],
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
                    'QR pairing',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _MotionFeedbackButton(
                  onPressed: onCopyPairPayload,
                  icon: Icons.copy_all_outlined,
                  label: 'Copy payload',
                  successLabel: 'Copied',
                  variant: _MotionFeedbackButtonVariant.filledTonal,
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
    if (devices.isEmpty) {
      return _SettingsCard(
        icon: Icons.radar_outlined,
        title: 'Thiết bị đang thấy',
        subtitle: '',
        child: Row(
          children: [
            Icon(Icons.radar_outlined, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Chưa thấy thiết bị OpenCB khác. Hãy mở app trên thiết bị cùng Wi-Fi/VPN.',
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
      title: 'Thiết bị đang thấy',
      subtitle: '',
      trailing: _MiniChip(label: '${devices.length} tìm thấy'),
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
                        '${device.endpoint} - thấy ${_relativeTime(device.lastSeenAt)}',
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
              label: const _ButtonLabel('Kết nối'),
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
    final hasError = peer.lastError != null;
    final online =
        discoveredDevice != null &&
        DateTime.now().difference(discoveredDevice!.lastSeenAt) <=
            const Duration(seconds: 18);
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
        tooltip: 'Test kết nối',
        onPressed: onTest,
        icon: Icons.network_ping,
      ),
      deviceActionButton(
        tooltip: 'Đổi tên thiết bị',
        onPressed: onRename,
        icon: Icons.edit_outlined,
      ),
      deviceActionButton(
        tooltip: 'Sync thiết bị',
        onPressed: onSync,
        icon: Icons.sync,
      ),
      deviceActionButton(
        tooltip: 'Xóa thiết bị',
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
    final statusBadge = _M3Badge(
      label: hasError
          ? 'Lỗi'
          : online
          ? 'Online'
          : 'Offline',
      tone: _M3BadgeTone.surface,
      icon: hasError
          ? Icons.error_outline
          : online
          ? Icons.check_circle_outline
          : Icons.cloud_off_outlined,
      containerColorOverride: hasError
          ? Color.alphaBlend(
              colorScheme.error.withValues(alpha: 0.12),
              colorScheme.surfaceContainerHigh,
            )
          : online
          ? Color.alphaBlend(
              colorScheme.primary.withValues(alpha: 0.12),
              colorScheme.surfaceContainerHigh,
            )
          : null,
      contentColorOverride: hasError
          ? colorScheme.error
          : online
          ? colorScheme.primary
          : null,
      iconColorOverride: hasError
          ? colorScheme.error
          : online
          ? colorScheme.primary
          : null,
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
                    const SizedBox(width: 4),
                    statusBadge,
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
              Text(
                '${peer.endpoint} - ${peer.pairCode}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hasError ? 'Lỗi: ${peer.lastError}' : peer.lastSynced,
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
                          const SizedBox(width: 4),
                          Flexible(child: statusBadge),
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
                  offset: Offset(0, tightText ? 0 : -0.75),
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
  const _MiniChip({required this.label, this.timeTone = false});

  final String label;
  final bool timeTone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!timeTone) {
      return _M3Badge(label: label, tone: _M3BadgeTone.surface);
    }
    return _M3Badge(
      label: label,
      tone: _M3BadgeTone.primary,
      horizontalPadding: 8,
      tightText: true,
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

String _formatClipboardCount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index += 1) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write('.');
    }
  }
  return '$buffer mục';
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

String _kindLabel(ClipboardKind kind) {
  return switch (kind) {
    ClipboardKind.text => 'Văn bản',
    ClipboardKind.code => 'Code',
    ClipboardKind.url => 'URL',
    ClipboardKind.image => 'Hình ảnh',
    ClipboardKind.fileReference => 'Path',
  };
}

String _shortKindLabel(ClipboardKind kind) {
  return switch (kind) {
    ClipboardKind.text => 'Text',
    ClipboardKind.code => 'Code',
    ClipboardKind.url => 'URL',
    ClipboardKind.image => 'Image',
    ClipboardKind.fileReference => 'Path',
  };
}

String _quickPickerKindLabel(ClipboardKind kind) {
  return switch (kind) {
    ClipboardKind.text => 'Text',
    ClipboardKind.code => 'Code',
    ClipboardKind.url => 'URL',
    ClipboardKind.image => 'Image',
    ClipboardKind.fileReference => 'Path',
  };
}

String _quickPickerMetaKindLabel(ClipboardKind kind) {
  return switch (kind) {
    ClipboardKind.text => 'Văn bản',
    ClipboardKind.code => 'Code',
    ClipboardKind.url => 'URL',
    ClipboardKind.image => 'Hình ảnh',
    ClipboardKind.fileReference => 'Path',
  };
}

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

String _relativeTime(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inSeconds < 60) return 'Vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays < 7) return '${diff.inDays} ngày trước';
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
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
  final message = error.toString();
  if (message.contains('No route to host') ||
      message.contains('Network is unreachable')) {
    return 'Không có đường mạng tới host. Kiểm tra cùng Wi-Fi/VPN, IP trong payload và firewall Windows.';
  }
  if (message.contains('Connection refused')) return 'Kết nối bị từ chối';
  if (message.contains('timed out') || message.contains('TimeoutException')) {
    return 'Sync quá thời gian chờ';
  }
  if (message.contains('Failed host lookup')) return 'Không tìm thấy host';
  return message.length > 80 ? '${message.substring(0, 80)}...' : message;
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
      stored = _entries[existing].copyWith(kind: kind, createdAt: now);
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
      _entries[existing] = _entries[existing].copyWith(createdAt: now);
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
const String _syncProtocol = 'opencb_lan_text_v1';
const String _discoveryProtocol = 'opencb_lan_discovery_v1';
