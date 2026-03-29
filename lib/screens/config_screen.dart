import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import 'edit_config_screen.dart';
import 'settings_screen.dart';
import 'scanner_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  bool _isLoading = true;
  bool _prevWifiOk = false; // tracks last known mixer WiFi state for auto-refresh

  @override
  void initState() {
    super.initState();
    // Data is already loaded by connect() before navigation
    // Just check once with a short delay for safety
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _isLoading = false);
    });
  }

  Future<void> _refreshData() async {
    final bleService = Provider.of<BleService>(context, listen: false);
    setState(() => _isLoading = true);
    await bleService.readAllData();
    setState(() => _isLoading = false);
  }

  // ── BT icon tap: connect/disconnect/switch pedal ─────────────────────────
  Future<void> _handleBtIconTap(BleService bleService) async {
    if (bleService.isReconnecting) return;

    if (bleService.isConnected) {
      // Already connected - show options
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bluetooth'),
          content: Text('Connected to ${bleService.connectedDevice?.platformName ?? "pedal"}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'switch'),
              child: const Text('Switch Pedal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'disconnect'),
              child: Text('Disconnect',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          ],
        ),
      );

      if (action == 'switch' || action == 'disconnect') {
        await bleService.disconnect();
        if (!mounted) return;
        if (action == 'switch') {
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const ScannerScreen()));
        }
      }
      return;
    }

    // Not connected - try auto-reconnect then fall back to scanner
    if (bleService.hasLastDevice) {
      final ok = await bleService.tryReconnect();
      if (ok) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Reconnected!'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
        return;
      }
    }

    // Fall back to scanner
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
  }

  // ── Mixer WiFi status from mixerInfo characteristic ───────────────────────
  // Returns (label, isWifiOk)
  (String, bool) _getMixerStatus(BleService bleService) {
    final info = bleService.mixerInfo;
    final config = bleService.pedalConfig;
    final mixerType = config?['mixer']?['type'] ?? 0;
    final mixerName = bleService.getMixerTypeName(mixerType);

    if (info == null) return ('$mixerName · Unknown', false);

    final connected = info['connected'] == true;
    final ssid      = info['ssid']?.toString() ?? '';

    if (connected && ssid.isNotEmpty) {
      return ('$mixerName · $ssid', true);
    } else if (connected) {
      return ('$mixerName · WiFi', true);
    } else {
      return ('$mixerName · No WiFi', false);
    }
  }

  String _getModeName(int mode, int mixerType) {
    if (mode == 0) return 'Tap Tempo';
    if (mode == 1) return 'Mute Channel';
    if (mode == 2) return 'Mute Bus';
    if (mixerType == 0) {
      switch (mode) {
        case 3:  return 'Mute Mgrp';
        case 4:  return 'Mute Aux';
        case 5:  return 'Mute Main';
        case 6:  return 'Mute Mtx';
        case 7:  return 'Mute DCA';
        case 14: return 'Scene Control';
        default: return 'Unknown';
      }
    }
    if (mixerType == 1) {
      switch (mode) {
        case 6:  return 'Mute Mtx';
        case 7:  return 'Mute DCA';
        case 8:  return 'Mute FXRtn';
        case 9:  return 'Mute AUX';
        case 10: return 'Mute M/ST';
        case 11: return 'Mute M/C';
        case 14: return 'Scene Control';
        default: return 'Unknown';
      }
    }
    if (mixerType == 2) {
      switch (mode) {
        case 7:  return 'Mute DCA';
        case 12: return 'Mute FXSend';
        case 13: return 'Mute M/LR';
        case 14: return 'Scene Control';
        default: return 'Unknown';
      }
    }
    return 'Unknown';
  }

  // Safe int helper - JSON values from ArduinoJson may be int, double or null
  int _safeInt(Map<String, dynamic> ch, String key, [int def = 0]) {
    final v = ch[key];
    if (v == null) return def;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? def;
  }

  String _getTargetName(Map<String, dynamic> channel, int mixerType,
      List<String> channelNames, List<String> busNames, List<String> fxNames,
      BleService bleService) {
    final mode = _safeInt(channel, 'mode', 0);
    if (mode == 0) {
      final n = _safeInt(channel, 'fxNum', 1);
      return n > 0 && n <= fxNames.length ? 'FX $n - ${fxNames[n - 1]}' : 'FX $n';
    }
    if (mode == 1) {
      final n = _safeInt(channel, 'muteChannel', 1);
      return n > 0 && n <= channelNames.length ? 'Ch $n - ${channelNames[n - 1]}' : 'Ch $n';
    }
    if (mode == 2) {
      final n = _safeInt(channel, 'muteBus', 1);
      return n > 0 && n <= busNames.length ? 'Bus $n - ${busNames[n - 1]}' : 'Bus $n';
    }
    if (mode == 3)  return 'Mgrp ${_safeInt(channel, "muteMgrp", 1)}';
    if (mode == 4)  return 'Aux ${_safeInt(channel, "muteAux", 1)}';
    if (mode == 5)  return 'Main ${_safeInt(channel, "muteMain", 1)}';
    if (mode == 6)  return 'Mtx ${_safeInt(channel, "muteMtx", 1)}';
    if (mode == 7) {
      final n = _safeInt(channel, 'muteDca', 1);
      return n > 0 && n <= bleService.dcaNames.length && bleService.dcaNames[n-1].isNotEmpty
          ? 'DCA $n · ${bleService.dcaNames[n-1]}'
          : 'DCA $n';
    }
    if (mode == 8) {
      final n = _safeInt(channel, 'muteFxrtn', 1);
      final pair = ((n - 1) ~/ 2) + 1;
      final side = ((n - 1) % 2 == 0) ? 'L' : 'R';
      final xLabel = 'Fx $pair$side';
      return n > 0 && n <= bleService.fxrtnNames.length && bleService.fxrtnNames[n-1].isNotEmpty
          ? '$xLabel · ${bleService.fxrtnNames[n-1]}'
          : xLabel;
    }
    if (mode == 9) {
      final n = _safeInt(channel, 'muteAuxin', 1);
      return n > 0 && n <= bleService.auxinNames.length && bleService.auxinNames[n-1].isNotEmpty
          ? 'AUX $n · ${bleService.auxinNames[n-1]}'
          : 'AUX $n';
    }
    if (mode == 10) return bleService.mainStName.isNotEmpty ? 'M/ST · ${bleService.mainStName}' : 'M/ST';
    if (mode == 11) return bleService.mainMName.isNotEmpty  ? 'M/C · ${bleService.mainMName}'   : 'M/C';
    if (mode == 12) return 'FXSend ${_safeInt(channel, "muteFxsend", 1)}';
    if (mode == 13) return bleService.lrName.isNotEmpty ? 'M/LR · ${bleService.lrName}' : 'M/LR';
    if (mode == 14) {
      final num  = bleService.currentSceneNumber;
      final name = bleService.currentSceneName;
      if (num > 0 && name.isNotEmpty) return 'Scene $num - $name';
      if (num > 0) return 'Scene $num';
      return 'Scene Control';
    }
    return 'N/A';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, bleService, child) {
        final (mixerStatus, wifiOk) = _getMixerStatus(bleService);

        // Auto-refresh names when mixer WiFi transitions from offline → online
        if (wifiOk && !_prevWifiOk && !_isLoading) {
          _prevWifiOk = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            setState(() => _isLoading = true);
            await bleService.readAllData();
            if (mounted) setState(() => _isLoading = false);
          });
        } else if (!wifiOk) {
          _prevWifiOk = false;
        }

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(104),
            child: _HeaderPanel(
              mixerName:      bleService.getMixerTypeName(
                                bleService.pedalConfig?['mixer']?['type'] ?? 0),
              bleConnected:   bleService.isConnected,
              isReconnecting: bleService.isReconnecting,
              mixerStatus:    mixerStatus,
              wifiOk:         wifiOk,
              onBtTap:        () => _handleBtIconTap(bleService),
              onSettings:     () async {
                await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
                // Don't read immediately - pedal may be doing deferred WiFi reconnect
                // The mixer info timer will detect WiFi reconnect and auto-refresh
                // But do a delayed refresh after 3s to catch quick/no-change cases
                if (mounted) {
                  await Future.delayed(const Duration(seconds: 3));
                  if (mounted) await _refreshData();
                }
              },
            ),
          ),

          body: _buildBody(bleService),
        );
      },
    );
  }

  Widget _buildBody(BleService bleService) {
    final config = bleService.pedalConfig;

    if (_isLoading || config == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Loading configuration...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onBackground.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    final mixer      = config['mixer'] ?? {};
    final mixerType  = mixer['type'] ?? 0;
    final channelA   = config['channelA'] ?? {};
    final channelB   = config['channelB'] ?? {};

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: Theme.of(context).colorScheme.primary,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Channel A card
          _ChannelCard(
            label:       'STOMP CHANNEL A',
            modeName:    _getModeName(channelA['mode'] ?? 1, mixerType),
            targetName:  _getTargetName(channelA, mixerType,
                             bleService.channelNames, bleService.busNames, bleService.fxNames, bleService),
            onTap: bleService.isConnected ? () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => EditConfigScreen(
                  channelName: 'A', channelConfig: channelA, isChannelA: true),
              ));
            } : null,
          ),

          const SizedBox(height: 16),

          // Channel B card
          _ChannelCard(
            label:       'STOMP CHANNEL B',
            modeName:    _getModeName(channelB['mode'] ?? 1, mixerType),
            targetName:  _getTargetName(channelB, mixerType,
                             bleService.channelNames, bleService.busNames, bleService.fxNames, bleService),
            onTap: bleService.isConnected ? () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => EditConfigScreen(
                  channelName: 'B', channelConfig: channelB, isChannelA: false),
              ));
            } : null,
          ),

          const SizedBox(height: 24),

          // Live pedal graphic
          _PedalGraphic(
            muteA:           bleService.muteStateA,
            muteB:           bleService.muteStateB,
            bpmA:            bleService.bpmA,
            bpmB:            bleService.bpmB,
            modeA:           _safeInt(channelA, 'mode', 1),
            modeB:           _safeInt(channelB, 'mode', 1),
            sceneNumber:     bleService.currentSceneNumber,
            sceneName:       bleService.currentSceneName,
            firmwareVersion: bleService.firmwareVersion,
          ),

          const SizedBox(height: 16),
          Center(
            child: Text(
              'Pull down to refresh',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onBackground.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Unified header panel ─────────────────────────────────────────────────────
class _HeaderPanel extends StatelessWidget implements PreferredSizeWidget {
  final String       mixerName;
  final bool         bleConnected;
  final bool         isReconnecting;
  final String       mixerStatus;
  final bool         wifiOk;
  final VoidCallback onBtTap;
  final VoidCallback onSettings;

  const _HeaderPanel({
    required this.mixerName,
    required this.bleConnected,
    required this.isReconnecting,
    required this.mixerStatus,
    required this.wifiOk,
    required this.onBtTap,
    required this.onSettings,
  });

  @override
  Size get preferredSize => const Size.fromHeight(104);

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final btColor   = isReconnecting ? cs.secondary : (bleConnected ? cs.primary : cs.error);
    final wifiColor = bleConnected ? (wifiOk ? cs.primary : cs.error) : cs.onSurface.withOpacity(0.35);
    final borderColor = bleConnected && wifiOk ? cs.primary : cs.error;

    final btLabel   = isReconnecting
        ? 'Reconnecting...'
        : (bleConnected ? 'BT Connected to Pedal' : 'Tap to reconnect');
    final wifiLabel = bleConnected ? mixerStatus : 'Mixer: unknown';

    return GestureDetector(
      onTap: onBtTap,  // Always tappable - shows options when connected, reconnects when not
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            bottom: BorderSide(color: borderColor, width: 2),
          ),
        ),
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16, right: 8, bottom: 0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title row ──────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '5G WIFI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(0.5),
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      '$mixerName STOMP BOX',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.settings,
                      color: cs.onSurface.withOpacity(0.6)),
                  onPressed: onSettings,
                ),
              ],
            ),

            // ── Status row ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Row(
                children: [
                  // BT status - tap to connect/switch/disconnect
                  GestureDetector(
                    onTap: onBtTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        isReconnecting
                            ? SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: btColor))
                            : Icon(Icons.bluetooth, size: 15, color: btColor),
                        const SizedBox(width: 5),
                        Text(btLabel,
                            style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600, color: btColor)),
                        const SizedBox(width: 2),
                        Icon(Icons.expand_more, size: 14,
                            color: btColor.withOpacity(0.6)),
                      ],
                    ),
                  ),

                  // Divider
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Container(width: 1, height: 12,
                        color: cs.onSurface.withOpacity(0.2)),
                  ),

                  // WiFi / mixer status
                  Icon(
                    bleConnected && wifiOk ? Icons.wifi : Icons.wifi_off,
                    size: 15, color: wifiColor,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(wifiLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600, color: wifiColor)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable channel card ─────────────────────────────────────────────────────
class _ChannelCard extends StatelessWidget {
  final String     label;
  final String     modeName;
  final String     targetName;
  final VoidCallback? onTap;

  const _ChannelCard({
    required this.label,
    required this.modeName,
    required this.targetName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1.0,
        child: Stack(
          children: [
            // Main card body
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a2a),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10, width: 1),
              ),
              padding: const EdgeInsets.fromLTRB(21, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: cs.secondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _row('Mode',   modeName,   context),
                  const SizedBox(height: 6),
                  _row('Select', targetName, context),
                ],
              ),
            ),
            // Orange left accent bar — clipped to card's rounded corners
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 4,
                    color: cs.secondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0x80FFFFFF),  // white at 50% — dim label
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Live Pedal Graphic ────────────────────────────────────────────────────────
class _PedalGraphic extends StatelessWidget {
  final bool   muteA;
  final bool   muteB;
  final int    bpmA;
  final int    bpmB;
  final int    modeA;
  final int    modeB;
  final int    sceneNumber;
  final String sceneName;
  final String firmwareVersion;

  const _PedalGraphic({
    required this.muteA,
    required this.muteB,
    required this.bpmA,
    required this.bpmB,
    required this.modeA,
    required this.modeB,
    required this.sceneNumber,
    required this.sceneName,
    required this.firmwareVersion,
  });

  static const int _modeTap = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bodyColor    = isDark ? const Color(0xFF1e1e1e) : const Color(0xFF2a2a2a);
    final panelColor   = isDark ? const Color(0xFF262626) : const Color(0xFF303030);
    final strokeColor  = isDark ? const Color(0xFF4a4a4a) : const Color(0xFF555555);
    final screenBg     = const Color(0xFF080808);
    final screenGreen  = const Color(0xFF00cc88);
    final screenDim    = const Color(0xFF888888);

    // LED colors
    final tapAColor  = (modeA == _modeTap && bpmA > 0)
        ? const Color(0xFF00aaff) : const Color(0xFF002244);
    final muteAColor = muteA ? const Color(0xFFff2200) : const Color(0xFF330000);
    final tapBColor  = (modeB == _modeTap && bpmB > 0)
        ? const Color(0xFF00aaff) : const Color(0xFF002244);
    final muteBColor = muteB ? const Color(0xFFff2200) : const Color(0xFF330000);

    final bpmALabel = bpmA > 0 ? '$bpmA BPM' : '';
    final bpmBLabel = bpmB > 0 ? '$bpmB BPM' : '';

    return Card(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PEDAL STATUS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: cs.secondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 460 / 280,
              child: CustomPaint(
                painter: _PedalPainter(
                  bodyColor:   bodyColor,
                  panelColor:  panelColor,
                  strokeColor: strokeColor,
                  screenBg:    screenBg,
                  screenGreen: screenGreen,
                  screenDim:   screenDim,
                  tapAColor:   tapAColor,
                  muteAColor:  muteAColor,
                  tapBColor:   tapBColor,
                  muteBColor:  muteBColor,
                  bpmALabel:   bpmALabel,
                  bpmBLabel:   bpmBLabel,
                  muteA:       muteA,
                  muteB:       muteB,
                  modeA:       modeA,
                  modeB:       modeB,
                  sceneNumber: sceneNumber,
                  sceneName:   sceneName,
                  firmwareVersion: firmwareVersion,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Status row — CH A centered under screen left edge, CH B under screen right edge
            LayoutBuilder(
              builder: (context, constraints) {
                // Screen occupies roughly center 48% of card width (scrX=118..342 of 460)
                // Map those pedal coords to actual widget width
                final double w = constraints.maxWidth;
                final double scrLeftX  = w * (118 / 460);
                final double scrRightX = w * (342 / 460);
                return Stack(
                  children: [
                    const SizedBox(width: double.infinity, height: 24),
                    Positioned(
                      left: scrLeftX,
                      child: Transform.translate(
                        offset: const Offset(-40, 0),
                        child: _StatusLabel(
                          label: 'CH A',
                          isMuted: muteA,
                          bpm: modeA == _modeTap ? bpmA : null,
                          isScene: modeA == 14,
                          sceneNumber: sceneNumber,
                          cs: cs,
                        ),
                      ),
                    ),
                    Positioned(
                      left: scrRightX,
                      child: Transform.translate(
                        offset: const Offset(-40, 0),
                        child: _StatusLabel(
                          label: 'CH B',
                          isMuted: muteB,
                          bpm: modeB == _modeTap ? bpmB : null,
                          isScene: modeB == 14,
                          sceneNumber: sceneNumber,
                          cs: cs,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final String      label;
  final bool        isMuted;
  final int?        bpm;
  final bool        isScene;
  final int         sceneNumber;
  final ColorScheme cs;
  const _StatusLabel({
    required this.label, required this.isMuted, required this.bpm,
    required this.isScene, required this.sceneNumber, required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final bool isTap = bpm != null;
    // Priority: scene > tap > mute
    final statusText = isScene
        ? (sceneNumber > 0 ? 'SNAP $sceneNumber' : 'SCENE')
        : (isTap ? (bpm! > 0 ? '$bpm BPM' : 'TAP!') : (isMuted ? 'MUTED' : 'ON'));
    final dotColor  = isScene ? const Color(0xFFffaa00)
        : (isTap ? const Color(0xFF0088ff)
        : (isMuted ? const Color(0xFFff2200) : const Color(0xFF00aa44)));
    final textColor = isScene ? const Color(0xFFffaa00)
        : (isTap ? cs.primary
        : (isMuted ? const Color(0xFFff2200) : const Color(0xFF00aa44)));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.45), letterSpacing: .6)),
        const SizedBox(width: 5),
        Text(statusText,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
      ],
    );
  }
}

class _PedalPainter extends CustomPainter {
  final Color bodyColor, panelColor, strokeColor, screenBg, screenGreen, screenDim;
  final Color tapAColor, muteAColor, tapBColor, muteBColor;
  final String bpmALabel, bpmBLabel;
  final bool muteA, muteB;
  final int modeA, modeB;
  final int sceneNumber;
  final String sceneName;
  final String firmwareVersion;

  const _PedalPainter({
    required this.bodyColor, required this.panelColor, required this.strokeColor,
    required this.screenBg, required this.screenGreen, required this.screenDim,
    required this.tapAColor, required this.muteAColor,
    required this.tapBColor, required this.muteBColor,
    required this.bpmALabel, required this.bpmBLabel,
    required this.muteA, required this.muteB,
    required this.modeA, required this.modeB,
    required this.sceneNumber, required this.sceneName,
    required this.firmwareVersion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double sx = w / 460;
    final double sy = h / 280;

    void drawRRect(double x, double y, double rw, double rh, double r, Color fill, Color stroke, double sw) {
      final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(x * sx, y * sy, rw * sx, rh * sy), Radius.circular(r * ((sx + sy) / 2)));
      canvas.drawRRect(rr, Paint()..color = fill);
      canvas.drawRRect(rr, Paint()..color = stroke..style = PaintingStyle.stroke..strokeWidth = sw);
    }

    void drawCircle(double x, double y, double r, Color fill, Color stroke, double sw) {
      final c = Offset(x * sx, y * sy);
      final rr = r * ((sx + sy) / 2);
      canvas.drawCircle(c, rr, Paint()..color = fill);
      canvas.drawCircle(c, rr, Paint()..color = stroke..style = PaintingStyle.stroke..strokeWidth = sw);
    }

    void drawText(String text, double x, double y, double fontSize, Color color, {TextAlign align = TextAlign.center, FontWeight weight = FontWeight.normal}) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontSize: fontSize * ((sx + sy) / 2), color: color, fontWeight: weight, fontFamily: 'monospace')),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = align == TextAlign.center ? x * sx - tp.width / 2 : x * sx;
      canvas.drawText(tp, Offset(dx, y * sy - tp.height / 2));
    }

    // Layout constants
    const double stompCY = 165;   // raised from 215 by 50
    const double stompR1 = 32.0;
    const double stompR2 = 25.0;
    const double stompR3 = 19.0;
    const double ledR    = 7.0;
    const double axC     = 62.0;
    const double bxC     = 398.0;

    // Body: bottom at y=270 (height=260)
    drawRRect(10, 10, 440, 260, 22, bodyColor, strokeColor.withOpacity(.6), 1.5);
    drawRRect(20, 20, 420, 240, 16, panelColor, strokeColor.withOpacity(.4), 1);

    // ── TFT Screen ──
    const double scrX = 118, scrY = 68, scrW = 224, scrH = 148;
    drawRRect(scrX, scrY, scrW, scrH, 8, screenBg, const Color(0xFF555555), 1.2);

    // Header — always shows pedal identity
    drawText('STOMP  v$firmwareVersion', scrX + scrW / 2, scrY + 17, 14, screenGreen, weight: FontWeight.bold);
    canvas.drawLine(
      Offset((scrX + 6) * sx, (scrY + 28) * sy),
      Offset((scrX + scrW - 6) * sx, (scrY + 28) * sy),
      Paint()..color = const Color(0xFF1a3a2a)..strokeWidth = .8,
    );

    // CH A row — scene=14, tap=0, else mute state
    final bool aTap   = modeA == 0;
    final bool aScene = modeA == 14;
    final String aText  = aScene
        ? 'SCENE CTL'
        : (aTap ? 'TAP!' : (muteA ? 'MUTED' : 'ON'));
    final Color aColor  = aScene
        ? const Color(0xFFffaa00)
        : (aTap ? const Color(0xFF44bbff) : (muteA ? const Color(0xFFff4422) : const Color(0xFF00dd77)));
    drawText('CH A', scrX + 14, scrY + 52, 13, screenDim, align: TextAlign.left);
    drawText(aText, scrX + scrW / 2 - 10, scrY + 52, 14, aColor, weight: FontWeight.bold);



    canvas.drawLine(
      Offset((scrX + 6) * sx, (scrY + 68) * sy),
      Offset((scrX + scrW - 6) * sx, (scrY + 68) * sy),
      Paint()..color = const Color(0xFF1a3a2a)..strokeWidth = .6,
    );

    // CH B row — scene=14, tap=0, else mute state
    final bool bTap   = modeB == 0;
    final bool bScene = modeB == 14;
    final String bText  = bScene
        ? 'SCENE CTL'
        : (bTap ? 'TAP!' : (muteB ? 'MUTED' : 'ON'));
    final Color bColor  = bScene
        ? const Color(0xFFffaa00)
        : (bTap ? const Color(0xFF44bbff) : (muteB ? const Color(0xFFff4422) : const Color(0xFF00dd77)));
    drawText('CH B', scrX + 14, scrY + 92, 13, screenDim, align: TextAlign.left);
    drawText(bText, scrX + scrW / 2 - 10, scrY + 92, 14, bColor, weight: FontWeight.bold);



    canvas.drawLine(
      Offset((scrX + 6) * sx, (scrY + 108) * sy),
      Offset((scrX + scrW - 6) * sx, (scrY + 108) * sy),
      Paint()..color = const Color(0xFF1a3a2a)..strokeWidth = .6,
    );

    drawText('DM STOMP  ·  v$firmwareVersion', scrX + scrW / 2, scrY + 130, 10, const Color(0xFF336633));

    // ── CHANNEL A (left) ──
    drawText('CHAN A', axC, 30, 8, const Color(0xFF505050));        // label top y=30
    drawCircle(axC, 57, ledR, tapAColor, const Color(0xFF333333), 1);   // TAP y=57
    drawText('TAP', axC, 70, 8, screenDim);
    drawCircle(axC, 90, ledR, (aTap || aScene) ? const Color(0xFF1a0000) : muteAColor, const Color(0xFF333333), 1);  // MUTE y=90
    drawText('MUTE', axC, 103, 8, screenDim);
    drawCircle(axC, stompCY, stompR1, const Color(0xFF1e1e1e), const Color(0xFF4a4a4a), 1.5);
    drawCircle(axC, stompCY, stompR2, const Color(0xFF181818), const Color(0xFF3a3a3a), 1);
    drawCircle(axC, stompCY, stompR3, const Color(0xFF252525), const Color(0xFF5a5a5a), 2);
    drawText('A', axC, stompCY + 2, 9, const Color(0xFF555555), weight: FontWeight.bold);

    // ── CHANNEL B (right) ──
    drawText('CHAN B', bxC, 30, 8, const Color(0xFF505050));        // label top y=30
    drawCircle(bxC, 57, ledR, tapBColor, const Color(0xFF333333), 1);   // TAP y=57
    drawText('TAP', bxC, 70, 8, screenDim);
    drawCircle(bxC, 90, ledR, (bTap || bScene) ? const Color(0xFF1a0000) : muteBColor, const Color(0xFF333333), 1);  // MUTE y=90
    drawText('MUTE', bxC, 103, 8, screenDim);
    drawCircle(bxC, stompCY, stompR1, const Color(0xFF1e1e1e), const Color(0xFF4a4a4a), 1.5);
    drawCircle(bxC, stompCY, stompR2, const Color(0xFF181818), const Color(0xFF3a3a3a), 1);
    drawCircle(bxC, stompCY, stompR3, const Color(0xFF252525), const Color(0xFF5a5a5a), 2);
    drawText('B', bxC, stompCY + 2, 9, const Color(0xFF555555), weight: FontWeight.bold);

    // Brand strip
    drawText('DM STOMP CONTROLLER', 230, 268, 8, const Color(0xFF3a3a3a));
  }

  @override
  bool shouldRepaint(_PedalPainter old) =>
      old.muteA != muteA || old.muteB != muteB ||
      old.modeA != modeA || old.modeB != modeB ||
      old.sceneNumber != sceneNumber || old.sceneName != sceneName ||
      old.bpmALabel != bpmALabel || old.bpmBLabel != bpmBLabel ||
      old.tapAColor != tapAColor || old.tapBColor != tapBColor ||
      old.firmwareVersion != firmwareVersion;
}

// Extension to allow drawing TextPainter on Canvas
extension on Canvas {
  void drawText(TextPainter tp, Offset offset) => tp.paint(this, offset);
}
