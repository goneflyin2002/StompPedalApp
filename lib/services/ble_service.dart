import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService extends ChangeNotifier {
  // BLE UUIDs
  static const String serviceUuidFull = "0000ffe0-0000-1000-8000-00805f9b34fb";
  static const String serviceUuidShort = "ffe0";

  static const String configUuid       = "0000ffe1-0000-1000-8000-00805f9b34fb";
  static const String channelNamesUuid = "0000ffe2-0000-1000-8000-00805f9b34fb";
  static const String fxNamesUuid      = "0000ffe3-0000-1000-8000-00805f9b34fb";
  static const String busNamesUuid     = "0000ffe4-0000-1000-8000-00805f9b34fb";
  static const String mixerInfoUuid    = "0000ffe5-0000-1000-8000-00805f9b34fb";
  static const String wingNamesUuid    = "0000ffe6-0000-1000-8000-00805f9b34fb";
  static const String commonNamesUuid  = "0000ffe7-0000-1000-8000-00805f9b34fb";
  static const String x32NamesUuid     = "0000ffe8-0000-1000-8000-00805f9b34fb";
  static const String xr18NamesUuid    = "0000ffe9-0000-1000-8000-00805f9b34fb";
  static const String sceneNamesUuid   = "0000ffea-0000-1000-8000-00805f9b34fb";
  static const String otaCtrlUuid      = "0000ffeb-0000-1000-8000-00805f9b34fb";
  static const String otaStatusUuid    = "0000ffec-0000-1000-8000-00805f9b34fb";

  BluetoothDevice? connectedDevice;
  BluetoothDevice? _lastDevice; // remembered for auto-reconnect

  BluetoothCharacteristic? configChar;
  BluetoothCharacteristic? channelNamesChar;
  BluetoothCharacteristic? fxNamesChar;
  BluetoothCharacteristic? busNamesChar;
  BluetoothCharacteristic? mixerInfoChar;
  BluetoothCharacteristic? wingNamesChar;
  BluetoothCharacteristic? commonNamesChar;
  BluetoothCharacteristic? x32NamesChar;
  BluetoothCharacteristic? xr18NamesChar;
  BluetoothCharacteristic? sceneNamesChar;
  BluetoothCharacteristic? otaCtrlChar;
  BluetoothCharacteristic? otaStatusChar;

  bool isConnecting   = false;
  bool isConnected    = false;
  bool isReconnecting = false;
  String statusMessage = "Not connected";

  // Cached data
  Map<String, dynamic>? pedalConfig;
  List<String> channelNames = [];
  List<String> fxNames      = [];
  List<String> busNames     = [];
  List<String> mgrpNames    = [];
  List<String> auxNames     = [];
  List<String> mainNames    = [];
  List<String> mtxNames     = [];
  List<String> dcaNames     = [];
  String mainStName = '';
  String mainMName  = '';
  String lrName     = '';
  List<String> fxrtnNames   = [];
  List<String> auxinNames   = [];
  List<String> fxsendNames  = [];
  List<String> sceneNames   = [];
  Map<String, dynamic>? mixerInfo;

  // Current active scene (updated by mixer info refresh)
  String currentSceneName   = '';
  int    currentSceneNumber = 0;
  bool   _prevMixerConnected = true;   // true = don't trigger readAllData on first tick

  // Live pedal state (updated by mixer info refresh every 10s)
  bool muteStateA = false;
  bool muteStateB = false;
  int  bpmA       = 0;
  int  bpmB       = 0;

  // Firmware version (read from mixerInfo)
  String firmwareVersion = '';

  // Internal subscriptions / timers
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  Timer? _mixerInfoTimer;
  Timer? _namesTimer;

  // ── Connection state listener ──────────────────────────────────────────────
  void _listenToConnectionState(BluetoothDevice device) {
    _connectionStateSub?.cancel();
    _connectionStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        print("[BLE] Device disconnected unexpectedly");
        _onDeviceDisconnected();
      }
    });
  }

  void _onDeviceDisconnected() {
    isConnected  = false;
    isConnecting = false;
    connectedDevice = null;
    _clearCharacteristics();
    _mixerInfoTimer?.cancel();
    _namesTimer?.cancel();
    statusMessage = "Disconnected";
    notifyListeners();
  }

  void _clearCharacteristics() {
    configChar = channelNamesChar = fxNamesChar = busNamesChar = null;
    mixerInfoChar = wingNamesChar = commonNamesChar = null;
    x32NamesChar = xr18NamesChar = sceneNamesChar = null;
    otaCtrlChar = otaStatusChar = null;
  }

  // ── Auto-reconnect ─────────────────────────────────────────────────────────
  /// Tries to reconnect to the last known device.
  /// Returns true on success, false if caller should fall back to scanner.
  Future<bool> tryReconnect() async {
    if (_lastDevice == null) return false;

    isReconnecting = true;
    statusMessage  = "Reconnecting...";
    notifyListeners();

    try {
      final success = await connect(_lastDevice!);
      isReconnecting = false;
      notifyListeners();
      return success;
    } catch (e) {
      print("[BLE] Auto-reconnect failed: $e");
      isReconnecting = false;
      statusMessage  = "Reconnect failed";
      notifyListeners();
      return false;
    }
  }

  bool get hasLastDevice => _lastDevice != null;

  // ── Periodic mixer-info refresh (every 30s) ────────────────────────────────
  void _startMixerInfoTimer() {
    _mixerInfoTimer?.cancel();
    _mixerInfoTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!isConnected || mixerInfoChar == null) return;
      try {
        final value = await mixerInfoChar!.read();
        mixerInfo   = jsonDecode(utf8.decode(value));
        // Update live pedal state for UI
        muteStateA = mixerInfo!['muteA'] == true;
        muteStateB = mixerInfo!['muteB'] == true;
        bpmA = (mixerInfo!['bpmA'] ?? 0) is int ? mixerInfo!['bpmA'] : (mixerInfo!['bpmA'] ?? 0).toInt();
        bpmB = (mixerInfo!['bpmB'] ?? 0) is int ? mixerInfo!['bpmB'] : (mixerInfo!['bpmB'] ?? 0).toInt();

        // Detect WiFi reconnect (mixer connected → disconnected → connected)
        // This happens when switching mixer type or changing WiFi settings
        final mixerNowConnected = mixerInfo!['connected'] == true;
        final wifiReconnected   = mixerNowConnected && !_prevMixerConnected;
        _prevMixerConnected     = mixerNowConnected;

        // Extract active scene fields and detect scene changes
        if (mixerInfo!.containsKey('sceneName')) {
          final newSceneNumber = mixerInfo!['sceneNumber'] ?? 0;
          final sceneChanged   = newSceneNumber != currentSceneNumber && newSceneNumber > 0;
          currentSceneName     = mixerInfo!['sceneName']?.toString() ?? '';
          currentSceneNumber   = newSceneNumber;
          notifyListeners();
          print("[BLE] Mixer info refreshed - scene: $currentSceneNumber $currentSceneName");

          // Full refresh on scene change OR WiFi reconnect (mixer type switch etc.)
          if (sceneChanged || wifiReconnected) {
            final reason = wifiReconnected ? "WiFi reconnected" : "scene changed";
            print("[BLE] $reason - triggering full refresh");
            await readAllData();
          }
        } else {
          // Even without scene info, refresh everything on WiFi reconnect
          if (wifiReconnected) {
            print("[BLE] WiFi reconnected - triggering full refresh");
            await readAllData();
          } else {
            notifyListeners();
          }
        }
      } catch (e) {
        print("[BLE] Mixer info refresh failed: $e");
      }
    });
  }

  // ── Connect ────────────────────────────────────────────────────────────────
  Future<bool> connect(BluetoothDevice device) async {
    try {
      isConnecting  = true;
      statusMessage = "Connecting...";
      notifyListeners();

      await device.connect(timeout: const Duration(seconds: 10));
      connectedDevice = device;
      _lastDevice     = device; // remember for auto-reconnect

      // Subscribe to connection state immediately so we catch drops
      _listenToConnectionState(device);

      statusMessage = "Discovering services...";
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 500));
      final services = await device.discoverServices();

      print("[DEBUG] Found ${services.length} services");

      BluetoothService? pedalService;
      for (var svc in services) {
        final uuid       = svc.uuid.toString().toLowerCase();
        final uuidNoDash = uuid.replaceAll('-', '');
        final targetND   = serviceUuidFull.toLowerCase().replaceAll('-', '');
        if (uuid == serviceUuidFull.toLowerCase() ||
            uuid.contains(serviceUuidShort) ||
            uuidNoDash == targetND) {
          pedalService = svc;
          break;
        }
      }

      if (pedalService == null) {
        throw Exception("WING Pedal service not found (${services.length} services seen).");
      }

      for (var char in pedalService.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        final nd   = uuid.replaceAll('-', '');
        if      (nd.contains('ffe1')) configChar       = char;
        else if (nd.contains('ffe2')) channelNamesChar = char;
        else if (nd.contains('ffe3')) fxNamesChar      = char;
        else if (nd.contains('ffe4')) busNamesChar     = char;
        else if (nd.contains('ffe5')) mixerInfoChar    = char;
        else if (nd.contains('ffe6')) wingNamesChar    = char;
        else if (nd.contains('ffe7')) commonNamesChar  = char;
        else if (nd.contains('ffe8')) x32NamesChar     = char;
        else if (nd.contains('ffe9')) xr18NamesChar    = char;
        else if (nd.contains('ffea')) sceneNamesChar   = char;
        else if (nd.contains('ffeb')) otaCtrlChar      = char;
        else if (nd.contains('ffec')) otaStatusChar    = char;
      }

      if (configChar == null) throw Exception("Config characteristic not found");

      isConnected          = true;
      isConnecting         = false;
      _prevMixerConnected  = false;  // Reset so WiFi connect transition is detected fresh
      statusMessage        = "Connected to ${device.platformName}";
      notifyListeners();

      await readAllData();
      _startMixerInfoTimer();
      _startNamesTimer();

      // If mixer shows not connected on first read, re-check after 3s
      // (pedal may still be establishing WiFi connection when BLE connects)
      if (mixerInfo == null || mixerInfo!['connected'] != true) {
        Future.delayed(const Duration(seconds: 3), () async {
          if (!isConnected || mixerInfoChar == null) return;
          try {
            final value = await mixerInfoChar!.read();
            final info  = jsonDecode(utf8.decode(value));
            if (info['connected'] == true) {
              print("[BLE] Delayed WiFi check - now connected, refreshing all data");
              await readAllData();
            }
          } catch (e) {
            print("[BLE] Delayed WiFi check failed: $e");
          }
        });
      }

      return true;
    } catch (e) {
      print("[ERROR] Connection failed: $e");
      isConnecting  = false;
      isConnected   = false;
      statusMessage = "Connection failed: $e";
      notifyListeners();
      try { await connectedDevice?.disconnect(); } catch (_) {}
      connectedDevice = null;
      return false;
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _connectionStateSub?.cancel();
    _mixerInfoTimer?.cancel();
    _namesTimer?.cancel();
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      connectedDevice = null;
    }
    _clearCharacteristics();
    isConnected   = false;
    statusMessage = "Disconnected";
    notifyListeners();
  }

  // ── Read all data ──────────────────────────────────────────────────────────
  Future<void> readAllData() async {
    try {
      statusMessage = "Reading configuration...";
      notifyListeners();

      if (configChar != null) {
        pedalConfig = jsonDecode(utf8.decode(await configChar!.read()));
      }
      // Determine mixer type early so we only read relevant characteristics
      final mType = pedalConfig?['mixer']?['type'] ?? -1;

      if (channelNamesChar != null) {
        channelNames = (jsonDecode(utf8.decode(await channelNamesChar!.read())) as List)
            .map((e) => e.toString()).toList();
      }
      if (fxNamesChar != null) {
        fxNames = (jsonDecode(utf8.decode(await fxNamesChar!.read())) as List)
            .map((e) => e.toString()).toList();
      }
      if (busNamesChar != null) {
        busNames = (jsonDecode(utf8.decode(await busNamesChar!.read())) as List)
            .map((e) => e.toString()).toList();
      }
      if (mType == 0 && wingNamesChar != null) {
        // WING only: mgrp, aux, main names
        final w = jsonDecode(utf8.decode(await wingNamesChar!.read())) as Map<String, dynamic>;
        if (w['mgrps'] != null) mgrpNames = (w['mgrps'] as List).map((e) => e.toString()).toList();
        if (w['aux']   != null) auxNames  = (w['aux']   as List).map((e) => e.toString()).toList();
        if (w['main']  != null) mainNames = (w['main']  as List).map((e) => e.toString()).toList();
      }
      if (commonNamesChar != null) {
        // All mixers: mtx, dca, mainSt, mainM, lr
        final c = jsonDecode(utf8.decode(await commonNamesChar!.read())) as Map<String, dynamic>;
        if (c['mtx'] != null) mtxNames = (c['mtx'] as List).map((e) => e.toString()).toList();
        if (c['dca'] != null) dcaNames = (c['dca'] as List).map((e) => e.toString()).toList();
        mainStName = c['mainSt']?.toString() ?? '';
        mainMName  = c['mainM']?.toString()  ?? '';
        lrName     = c['lr']?.toString()     ?? '';
      }
      if (mType == 1 && x32NamesChar != null) {
        // X32 only: fxrtn, auxin
        final x = jsonDecode(utf8.decode(await x32NamesChar!.read())) as Map<String, dynamic>;
        if (x['fxrtn'] != null) fxrtnNames = (x['fxrtn'] as List).map((e) => e.toString()).toList();
        if (x['auxin'] != null) auxinNames  = (x['auxin'] as List).map((e) => e.toString()).toList();
      }
      if (mType == 2 && xr18NamesChar != null) {
        // XR18 only: fxsend
        final x = jsonDecode(utf8.decode(await xr18NamesChar!.read())) as Map<String, dynamic>;
        if (x['fxsend'] != null) fxsendNames = (x['fxsend'] as List).map((e) => e.toString()).toList();
      }
      if (sceneNamesChar != null) {
        sceneNames = (jsonDecode(utf8.decode(await sceneNamesChar!.read())) as List)
            .map((e) => e.toString()).toList();
      }
      if (mixerInfoChar != null) {
        mixerInfo = jsonDecode(utf8.decode(await mixerInfoChar!.read()));
        if (mixerInfo!.containsKey('sceneName')) {
          currentSceneName   = mixerInfo!['sceneName']?.toString() ?? '';
          currentSceneNumber = mixerInfo!['sceneNumber'] ?? 0;
        }
        if (mixerInfo!.containsKey('fwVersion')) {
          firmwareVersion = mixerInfo!['fwVersion']?.toString() ?? '';
        }
      }

      statusMessage = "Data loaded successfully";
      notifyListeners();
      print("[DEBUG] ✓ All data read successfully");
    } catch (e) {
      print("[ERROR] Reading data failed: $e");
      statusMessage = "Error reading data: $e";
      notifyListeners();
    }
  }

  // ── Read names only (lightweight — for edit screen population) ───────────
  Future<void> readNamesOnly() async {
    if (!isConnected) return;
    try {
      final mType = pedalConfig?['mixer']?['type'] ?? mixerInfo?['mixerType'] ?? -1;
      if (channelNamesChar != null) {
        channelNames = (jsonDecode(utf8.decode(await channelNamesChar!.read())) as List)
            .map((e) => e.toString()).toList();
      }
      if (fxNamesChar != null) {
        fxNames = (jsonDecode(utf8.decode(await fxNamesChar!.read())) as List)
            .map((e) => e.toString()).toList();
      }
      if (busNamesChar != null) {
        busNames = (jsonDecode(utf8.decode(await busNamesChar!.read())) as List)
            .map((e) => e.toString()).toList();
      }
      if (mType == 0 && wingNamesChar != null) {
        final w = jsonDecode(utf8.decode(await wingNamesChar!.read())) as Map<String, dynamic>;
        if (w['mgrps'] != null) mgrpNames = (w['mgrps'] as List).map((e) => e.toString()).toList();
        if (w['aux']   != null) auxNames  = (w['aux']   as List).map((e) => e.toString()).toList();
        if (w['main']  != null) mainNames = (w['main']  as List).map((e) => e.toString()).toList();
      }
      if (commonNamesChar != null) {
        final c = jsonDecode(utf8.decode(await commonNamesChar!.read())) as Map<String, dynamic>;
        if (c['mtx'] != null) mtxNames = (c['mtx'] as List).map((e) => e.toString()).toList();
        if (c['dca'] != null) dcaNames = (c['dca'] as List).map((e) => e.toString()).toList();
        mainStName = c['mainSt']?.toString() ?? '';
        mainMName  = c['mainM']?.toString()  ?? '';
        lrName     = c['lr']?.toString()     ?? '';
      }
      if (mType == 1 && x32NamesChar != null) {
        final x = jsonDecode(utf8.decode(await x32NamesChar!.read())) as Map<String, dynamic>;
        if (x['fxrtn'] != null) fxrtnNames = (x['fxrtn'] as List).map((e) => e.toString()).toList();
        if (x['auxin'] != null) auxinNames  = (x['auxin'] as List).map((e) => e.toString()).toList();
      }
      if (mType == 2 && xr18NamesChar != null) {
        final x = jsonDecode(utf8.decode(await xr18NamesChar!.read())) as Map<String, dynamic>;
        if (x['fxsend'] != null) fxsendNames = (x['fxsend'] as List).map((e) => e.toString()).toList();
      }
      if (sceneNamesChar != null) {
        sceneNames = (jsonDecode(utf8.decode(await sceneNamesChar!.read())) as List)
            .map((e) => e.toString()).toList();
      }
      notifyListeners();
    } catch (e) {
      print("[ERROR] readNamesOnly failed: $e");
    }
  }

  // ── Write config ───────────────────────────────────────────────────────────
  Future<bool> writeConfig(Map<String, dynamic> config) async {
    if (configChar == null) return false;
    try {
      statusMessage = "Writing configuration...";
      notifyListeners();

      final bytes = utf8.encode(jsonEncode(config));
      const maxChunk = 500;
      print("[DEBUG] Config size: ${bytes.length} bytes");

      if (bytes.length <= maxChunk) {
        await configChar!.write(bytes, withoutResponse: false);
      } else {
        int offset = 0, chunkNum = 0;
        while (offset < bytes.length) {
          final sz = (bytes.length - offset > maxChunk) ? maxChunk : bytes.length - offset;
          await configChar!.write(bytes.sublist(offset, offset + sz), withoutResponse: false);
          await Future.delayed(const Duration(milliseconds: 50));
          offset += sz;
          chunkNum++;
        }
        print("[DEBUG] Wrote $chunkNum chunks");
      }

      pedalConfig   = config;
      statusMessage = "Configuration saved";
      notifyListeners();
      return true;
    } catch (e) {
      print("[ERROR] Write failed: $e");
      statusMessage = "Error writing config: $e";
      notifyListeners();
      return false;
    }
  }

  // ── Periodic names refresh (every 30s) ────────────────────────────────────
  void _startNamesTimer() {
    _namesTimer?.cancel();
    _namesTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!isConnected) return;
      try {
        bool changed = false;
        if (channelNamesChar != null) {
          final n = (jsonDecode(utf8.decode(await channelNamesChar!.read())) as List).map((e) => e.toString()).toList();
          if (!_listEquals(n, channelNames)) { channelNames = n; changed = true; }
        }
        if (fxNamesChar != null) {
          final n = (jsonDecode(utf8.decode(await fxNamesChar!.read())) as List).map((e) => e.toString()).toList();
          if (!_listEquals(n, fxNames)) { fxNames = n; changed = true; }
        }
        if (busNamesChar != null) {
          final n = (jsonDecode(utf8.decode(await busNamesChar!.read())) as List).map((e) => e.toString()).toList();
          if (!_listEquals(n, busNames)) { busNames = n; changed = true; }
        }
        // Only read mixer-specific characteristics for the active mixer type
        final mType = mixerInfo?['mixerType'] ?? -1;
        if (mType == 0 && wingNamesChar != null) {
          // WING only
          final w = jsonDecode(utf8.decode(await wingNamesChar!.read())) as Map<String, dynamic>;
          final mg = (w['mgrps'] as List?)?.map((e) => e.toString()).toList() ?? mgrpNames;
          final ax = (w['aux']   as List?)?.map((e) => e.toString()).toList() ?? auxNames;
          final mn = (w['main']  as List?)?.map((e) => e.toString()).toList() ?? mainNames;
          if (!_listEquals(mg, mgrpNames) || !_listEquals(ax, auxNames) || !_listEquals(mn, mainNames)) {
            mgrpNames = mg; auxNames = ax; mainNames = mn; changed = true;
          }
        }
        if (commonNamesChar != null) {
          // WING + X32 (mtx, dca, mainSt, mainM, lr)
          final c = jsonDecode(utf8.decode(await commonNamesChar!.read())) as Map<String, dynamic>;
          final mt  = (c['mtx'] as List?)?.map((e) => e.toString()).toList() ?? mtxNames;
          final dc  = (c['dca'] as List?)?.map((e) => e.toString()).toList() ?? dcaNames;
          final mst = c['mainSt']?.toString() ?? mainStName;
          final mm  = c['mainM']?.toString()  ?? mainMName;
          final lr  = c['lr']?.toString()     ?? lrName;
          if (!_listEquals(mt, mtxNames) || !_listEquals(dc, dcaNames) ||
              mst != mainStName || mm != mainMName || lr != lrName) {
            mtxNames = mt; dcaNames = dc;
            mainStName = mst; mainMName = mm; lrName = lr;
            changed = true;
          }
        }
        if (mType == 1 && x32NamesChar != null) {
          // X32 only
          final x = jsonDecode(utf8.decode(await x32NamesChar!.read())) as Map<String, dynamic>;
          final fr = (x['fxrtn'] as List?)?.map((e) => e.toString()).toList() ?? fxrtnNames;
          final ai = (x['auxin'] as List?)?.map((e) => e.toString()).toList() ?? auxinNames;
          if (!_listEquals(fr, fxrtnNames) || !_listEquals(ai, auxinNames)) {
            fxrtnNames = fr; auxinNames = ai; changed = true;
          }
        }
        if (mType == 2 && xr18NamesChar != null) {
          // XR18 only
          final x = jsonDecode(utf8.decode(await xr18NamesChar!.read())) as Map<String, dynamic>;
          final fs = (x['fxsend'] as List?)?.map((e) => e.toString()).toList() ?? fxsendNames;
          if (!_listEquals(fs, fxsendNames)) { fxsendNames = fs; changed = true; }
        }
        if (sceneNamesChar != null) {
          final n = (jsonDecode(utf8.decode(await sceneNamesChar!.read())) as List).map((e) => e.toString()).toList();
          if (!_listEquals(n, sceneNames)) { sceneNames = n; changed = true; }
        }
        if (changed) { print("[BLE] Names updated"); notifyListeners(); }
      } catch (e) { print("[BLE] Names refresh failed: $e"); }
    });
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; }
    return true;
  }

  // ── OTA Methods ───────────────────────────────────────────────────────────
  Future<bool> writeOtaCtrl(List<int> data, {bool withoutResponse = false}) async {
    if (otaCtrlChar == null) return false;
    try {
      await otaCtrlChar!.write(data, withoutResponse: withoutResponse);
      return true;
    } catch (e) {
      print("[OTA] Write error: $e");
      return false;
    }
  }

  Future<void> subscribeOtaStatus(Function(Map<String, dynamic>) onStatus) async {
    if (otaStatusChar == null) return;
    try {
      await otaStatusChar!.setNotifyValue(true);
      otaStatusChar!.lastValueStream.listen((value) {
        if (value.isEmpty) return;
        try {
          final json = jsonDecode(utf8.decode(value)) as Map<String, dynamic>;
          onStatus(json);
        } catch (e) { print("[OTA] Status parse error: $e"); }
      });
    } catch (e) { print("[OTA] Subscribe error: $e"); }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String getModeName(int mode) {
    const names = [
      'Tap Tempo', 'Mute Channel', 'Mute Bus', 'Mute Mgrp',
      'Mute Aux', 'Mute Main', 'Mute Mtx', 'Mute DCA',
      'Mute FX Return', 'Mute Aux In', 'Mute Main ST', 'Mute Main M',
      'Mute FX Send', 'Mute LR', 'Scene Control',
    ];
    return mode >= 0 && mode < names.length ? names[mode] : 'Unknown';
  }

  String getMixerTypeName(int type) {
    const names = ['WING', 'X32', 'XR18'];
    return type >= 0 && type < names.length ? names[type] : 'Unknown';
  }

  @override
  void dispose() {
    _connectionStateSub?.cancel();
    _mixerInfoTimer?.cancel();
    _namesTimer?.cancel();
    super.dispose();
  }
}
