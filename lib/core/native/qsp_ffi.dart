import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../helpers/qsp_var_discovery.dart';
import 'qsp_models.dart';
import 'qsp_utf16.dart';

import 'qsp_ffi_types.dart';
export 'qsp_ffi_types.dart';

class QspFfi {
  QspFfi._(this._library) {
    debugPrint('[QSP FFI] Binding functions from dynamic library...');
    _init = _library.lookupFunction<NativeQSPInit, DartQSPInit>('QSPInit');
    _terminate = _library
        .lookupFunction<NativeQSPTerminate, DartQSPTerminate>('QSPTerminate');
    _getVersion =
        _library.lookupFunction<NativeQSPGetVersion, DartQSPGetVersion>(
            'QSPGetVersion');
    _getMainDesc =
        _library.lookupFunction<NativeQSPGetMainDesc, DartQSPGetMainDesc>(
            'QSPGetMainDesc');
    _getVarsDesc =
        _library.lookupFunction<NativeQSPGetVarsDesc, DartQSPGetVarsDesc>(
            'QSPGetVarsDesc');

    _getActions =
        _library.lookupFunction<NativeQSPGetActions, DartQSPGetActions>(
            'QSPGetActions');
    _setSelActionIndex = _library.lookupFunction<NativeQSPSetSelActionIndex,
        DartQSPSetSelActionIndex>('QSPSetSelActionIndex');
    _executeSelActionCode = _library.lookupFunction<
        NativeQSPExecuteSelActionCode,
        DartQSPExecuteSelActionCode>('QSPExecuteSelActionCode');

    _getObjects =
        _library.lookupFunction<NativeQSPGetObjects, DartQSPGetObjects>(
            'QSPGetObjects');
    _setSelObjectIndex = _library.lookupFunction<NativeQSPSetSelObjectIndex,
        DartQSPSetSelObjectIndex>('QSPSetSelObjectIndex');

    _execString =
        _library.lookupFunction<NativeQSPExecString, DartQSPExecString>(
            'QSPExecString');
    _loadGameWorldFromData = _library.lookupFunction<
        NativeQSPLoadGameWorldFromData,
        DartQSPLoadGameWorldFromData>('QSPLoadGameWorldFromData');
    _openSavedGameFromData = _library.lookupFunction<
        NativeQSPOpenSavedGameFromData,
        DartQSPOpenSavedGameFromData>('QSPOpenSavedGameFromData');
    _saveGameAsData =
        _library.lookupFunction<NativeQSPSaveGameAsData, DartQSPSaveGameAsData>(
            'QSPSaveGameAsData');
    _restartGame =
        _library.lookupFunction<NativeQSPRestartGame, DartQSPRestartGame>(
            'QSPRestartGame');
    _getLastErrorData = _library.lookupFunction<NativeQSPGetLastErrorData,
        DartQSPGetLastErrorData>('QSPGetLastErrorData');

    try {
      _setCallback =
          _library.lookupFunction<NativeQSPSetCallback, DartQSPSetCallback>(
              'QSPSetCallback');
      debugPrint('[QSP FFI] QSPSetCallback successfully resolved.');
    } catch (_) {
      debugPrint('[QSP FFI] QSPSetCallback symbol unavailable.');
    }
    try {
      _execCounter =
          _library.lookupFunction<NativeQSPExecCounter, DartQSPExecCounter>(
              'QSPExecCounter');
      debugPrint('[QSP FFI] QSPExecCounter successfully resolved.');
    } catch (_) {
      debugPrint('[QSP FFI] QSPExecCounter symbol unavailable.');
    }

    try {
      _getNumVarValue = _library.lookupFunction<NativeQSPGetNumVarValue,
          DartQSPGetNumVarValue>('QSPGetNumVarValue');
      _getStrVarValue = _library.lookupFunction<NativeQSPGetStrVarValue,
          DartQSPGetStrVarValue>('QSPGetStrVarValue');
      debugPrint('[QSP FFI] QSPGetNumVarValue and QSPGetStrVarValue resolved.');
    } catch (_) {
      debugPrint('[QSP FFI] Var lookup symbols unavailable.');
    }

    try {
      final verStruct = _getVersion();
      if (verStruct.str != nullptr) {
        if (verStruct.end != nullptr) {
          if (verStruct.end.address > verStruct.str.address) {
            final byteLen = verStruct.end.address - verStruct.str.address;
            var detectedSize = 2;
            if (byteLen >= 20) {
              detectedSize = 4;
            } else if (byteLen >= 10) {
              if (byteLen < 20) {
                detectedSize = 2;
              }
            } else if (byteLen % 4 == 0) {
              detectedSize = 4;
            }
            QspUtf16.setWcharSize(detectedSize);
            debugPrint(
                '[QSP FFI] Detected native wchar_t size: ${QspUtf16.nativeWcharSize} bytes (byteLen: $byteLen)');
          }
        }
      }
    } catch (e) {
      debugPrint('[QSP FFI] Calibration warning: $e');
    }
  }

  final DynamicLibrary _library;

  DynamicLibrary get nativeLibrary => _library;

  late final DartQSPInit _init;
  late final DartQSPTerminate _terminate;
  late final DartQSPGetVersion _getVersion;
  late final DartQSPGetMainDesc _getMainDesc;
  late final DartQSPGetVarsDesc _getVarsDesc;
  late final DartQSPGetActions _getActions;
  late final DartQSPSetSelActionIndex _setSelActionIndex;
  late final DartQSPExecuteSelActionCode _executeSelActionCode;
  late final DartQSPGetObjects _getObjects;
  late final DartQSPSetSelObjectIndex _setSelObjectIndex;
  late final DartQSPExecString _execString;
  late final DartQSPLoadGameWorldFromData _loadGameWorldFromData;
  late final DartQSPOpenSavedGameFromData _openSavedGameFromData;
  late final DartQSPSaveGameAsData _saveGameAsData;
  late final DartQSPRestartGame _restartGame;
  late final DartQSPGetLastErrorData _getLastErrorData;
  DartQSPSetCallback? _setCallback;
  DartQSPExecCounter? _execCounter;

  DartQSPGetNumVarValue? _getNumVarValue;
  DartQSPGetStrVarValue? _getStrVarValue;

  static QspFfi? instance;

  static QspFfi? tryLoad() {
    if (instance != null) {
      return instance;
    }
    try {
      if (Platform.isIOS) {
        // iOS forbids loading unsigned dynamic libraries. The QSP engine is
        // linked statically into the Runner binary, so its C symbols are
        // resolved from the running process.
        debugPrint(
            '[QSP FFI] Resolving QSP symbols from the app process on iOS...');
        instance = QspFfi._(DynamicLibrary.process());
        return instance;
      }
      if (Platform.isAndroid) {
        debugPrint('[QSP FFI] Opening libqsp.so on Android...');
        instance = QspFfi._(DynamicLibrary.open('libqsp.so'));
        return instance;
      }
      if (Platform.isWindows) {
        debugPrint('[QSP FFI] Opening qsp.dll on Windows...');
        instance = QspFfi._(DynamicLibrary.open('qsp.dll'));
        return instance;
      }
    } catch (e, st) {
      debugPrint('[QSP FFI] Error opening native library: $e\n$st');
      return null;
    }
    debugPrint('[QSP FFI] Unsupported platform: ${Platform.operatingSystem}');
    return null;
  }

  bool get isAvailable => _library.providesSymbol('QSPInit');

  void init() {
    debugPrint('[QSP FFI] Calling QSPInit()...');
    _init();
  }

  void dispose() {
    debugPrint('[QSP FFI] Calling QSPTerminate()...');
    _terminate();
  }

  String getVersion() {
    final s = _getVersion();
    final ver = QspUtf16.fromStruct(s);
    debugPrint('[QSP FFI] QSPGetVersion() => "$ver"');
    return ver;
  }

  String getMainDesc() {
    final s = _getMainDesc();
    return QspUtf16.fromStruct(s);
  }

  String getVarsDesc() {
    final s = _getVarsDesc();
    return QspUtf16.fromStruct(s);
  }

  List<QspAction> getActions() {
    final bufSize = 256;
    final itemsPtr = calloc<QSPListItemStruct>(bufSize);
    try {
      final count = _getActions(itemsPtr, bufSize);
      final actions = <QspAction>[];
      for (var i = 0; i < count; i++) {
        final item = itemsPtr[i];
        final name = QspUtf16.fromStruct(item.name);
        final image = QspUtf16.fromStruct(item.image);
        actions.add(QspAction(index: i, name: name, image: image));
      }
      return actions;
    } finally {
      calloc.free(itemsPtr);
    }
  }

  List<QspObject> getObjects() {
    final bufSize = 256;
    final itemsPtr = calloc<QSPListItemStruct>(bufSize);
    try {
      final count = _getObjects(itemsPtr, bufSize);
      final objects = <QspObject>[];
      for (var i = 0; i < count; i++) {
        final item = itemsPtr[i];
        final name = QspUtf16.fromStruct(item.name);
        final image = QspUtf16.fromStruct(item.image);
        objects.add(QspObject(index: i, name: name, image: image));
      }
      return objects;
    } finally {
      calloc.free(itemsPtr);
    }
  }

  bool executeAction(int index, {bool refresh = true}) {
    debugPrint('[QSP FFI] executeAction(index: $index, refresh: $refresh)');
    final res = _setSelActionIndex(index, refresh ? 1 : 0);
    if (res == 0) {
      debugPrint('[QSP FFI] QSPSetSelActionIndex($index) failed');
      return false;
    }
    final ok = _executeSelActionCode(refresh ? 1 : 0) != 0;
    debugPrint('[QSP FFI] QSPExecuteSelActionCode() => $ok');
    return ok;
  }

  bool selectObject(int index, {bool refresh = true}) {
    debugPrint('[QSP FFI] selectObject(index: $index, refresh: $refresh)');
    final ok = _setSelObjectIndex(index, refresh ? 1 : 0) != 0;
    debugPrint('[QSP FFI] QSPSetSelObjectIndex() => $ok');
    return ok;
  }

  bool execString(String code, {bool refresh = true}) {
    debugPrint('[QSP FFI] execString("$code", refresh: $refresh)');
    final ptr = QspUtf16.stringToNative(code);
    final strStruct = calloc<QSPStringStruct>();
    try {
      QspUtf16.populateStruct(strStruct.ref, ptr, code);
      final ok = _execString(strStruct.ref, refresh ? 1 : 0) != 0;
      debugPrint('[QSP FFI] QSPExecString() => $ok');
      return ok;
    } finally {
      calloc.free(ptr);
      calloc.free(strStruct);
    }
  }

  bool loadGameData(Uint8List data, {bool isNew = true}) {
    debugPrint(
        '[QSP FFI] loadGameData(size: ${data.length} bytes, isNew: $isNew)');
    final ptr = calloc<Uint8>(data.length);
    try {
      ptr.asTypedList(data.length).setAll(0, data);
      final ok = _loadGameWorldFromData(ptr, data.length, isNew ? 1 : 0) != 0;
      debugPrint('[QSP FFI] QSPLoadGameWorldFromData() => $ok');
      return ok;
    } finally {
      calloc.free(ptr);
    }
  }

  bool openSaveData(Uint8List data, {bool refresh = true}) {
    debugPrint(
        '[QSP FFI] openSaveData(size: ${data.length} bytes, refresh: $refresh)');
    final ptr = calloc<Uint8>(data.length);
    try {
      ptr.asTypedList(data.length).setAll(0, data);
      final ok = _openSavedGameFromData(ptr, data.length, refresh ? 1 : 0) != 0;
      debugPrint('[QSP FFI] QSPOpenSavedGameFromData() => $ok');
      return ok;
    } finally {
      calloc.free(ptr);
    }
  }

  Uint8List? saveGameData({bool refresh = true}) {
    debugPrint('[QSP FFI] saveGameData(refresh: $refresh)');
    final initialSize = 512 * 1024;
    final bufPtr = calloc<Uint8>(initialSize);
    final sizePtr = calloc<Int32>();
    try {
      sizePtr.value = initialSize;
      final ok = _saveGameAsData(bufPtr, sizePtr, refresh ? 1 : 0) != 0;
      if (!ok) {
        debugPrint('[QSP FFI] QSPSaveGameAsData() failed');
        return null;
      }
      final size = sizePtr.value;
      debugPrint('[QSP FFI] QSPSaveGameAsData() succeeded, size: $size bytes');
      return Uint8List.fromList(bufPtr.asTypedList(size));
    } finally {
      calloc.free(bufPtr);
      calloc.free(sizePtr);
    }
  }

  bool restartGame({bool refresh = true}) {
    debugPrint('[QSP FFI] restartGame(refresh: $refresh)');
    final ok = _restartGame(refresh ? 1 : 0) != 0;
    debugPrint('[QSP FFI] QSPRestartGame() => $ok');
    return ok;
  }

  bool get supportsCallbacks => _setCallback != null;

  void setCallback(int type, Pointer<NativeFunction<NativeQspCallback>> func) {
    debugPrint('[QSP FFI] setCallback(type: $type)');
    _setCallback?.call(type, func);
  }

  bool execCounter({bool refresh = true}) {
    final exec = _execCounter;
    if (exec == null) return false;
    return exec(refresh ? 1 : 0) != 0;
  }

  QspErrorInfo getLastError() {
    final err = _getLastErrorData();
    final info = QspErrorInfo(
      errorNum: err.errorNum,
      errorDesc: QspUtf16.fromStruct(err.errorDesc),
      locName: QspUtf16.fromStruct(err.locName),
      actIndex: err.actIndex,
      lineNum: err.intLineNum,
      codeLine: QspUtf16.fromStruct(err.intLine),
    );
    if (info.errorNum != 0) {
      debugPrint('[QSP FFI] getLastError() => $info');
    }
    return info;
  }

  /// Reads a numeric variable through `QSPGetNumVarValue`.
  ///
  /// The native out-parameter is `QSP_BIGINT *`. The [Int32] buffer below
  /// matches the current native build, where `QSP_USE_BIGINT` is undefined and
  /// `QSP_BIGINT` is therefore `int` (see `native/qsp/qsp/bindings/qsp.h`).
  int getVarNum(String name, [int index = 0]) {
    if (_getNumVarValue == null) return 0;
    final ptr = QspUtf16.stringToNative(name);
    final nameStruct = calloc<QSPStringStruct>();
    final resPtr = calloc<Int32>();
    try {
      QspUtf16.populateStruct(nameStruct.ref, ptr, name);
      final ok = _getNumVarValue!(nameStruct.ref, index, resPtr) != 0;
      return ok ? resPtr.value : 0;
    } finally {
      calloc.free(ptr);
      calloc.free(nameStruct);
      calloc.free(resPtr);
    }
  }

  String getVarStr(String name, [int index = 0]) {
    if (_getStrVarValue == null) return '';
    final ptr = QspUtf16.stringToNative(name);
    final nameStruct = calloc<QSPStringStruct>();
    final resStruct = calloc<QSPStringStruct>();
    try {
      QspUtf16.populateStruct(nameStruct.ref, ptr, name);
      final ok = _getStrVarValue!(nameStruct.ref, index, resStruct) != 0;
      return ok ? QspUtf16.fromStruct(resStruct.ref) : '';
    } finally {
      calloc.free(ptr);
      calloc.free(nameStruct);
      calloc.free(resStruct);
    }
  }

  /// Collects variable names by probing the engine, never by reading raw
  /// engine memory.
  ///
  /// An earlier revision walked the native `qspVars` bucket table directly.
  /// That approach could never work: `qspVars` is not part of the exported
  /// C-API symbol set, so the lookup always failed. Even with a resolvable
  /// symbol the walk was unsound, because the guessed `QSPVar` stride (48 or
  /// 28 bytes) does not match the real layout (56 bytes on 64-bit) and the
  /// only bounds were a bucket count and a `ValsCount < 500` guess, which
  /// together let the walk run past the end of a real allocation. Variable
  /// discovery therefore relies exclusively on the two safe fallbacks below.
  List<String> getDiscoveredVarNames({String varsDesc = '', String mainDesc = ''}) {
    final discovered = <String>{};

    // 1. Tokens named in the game text that the engine reports a value for.
    for (final token in extractVarTokens(varsDesc, mainDesc)) {
      if (getVarNum(token) != 0 || getVarStr(token).isNotEmpty) {
        discovered.add(token);
      }
    }

    // 2. Common QSP game variables that this particular game also defines.
    for (final name in kCommonQspVarNames) {
      if (getVarNum(name) != 0 || getVarStr(name).isNotEmpty) {
        discovered.add(name);
      }
    }

    final list = discovered.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }
}
