import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import 'scanner_screen.dart';

// GitHub raw URL for version manifest
const String versionUrl =
    'https://raw.githubusercontent.com/goneflyin2002/StompPedalFirmware/main/version.json';

class OtaScreen extends StatefulWidget {
  const OtaScreen({super.key});

  @override
  State<OtaScreen> createState() => _OtaScreenState();
}

class _OtaScreenState extends State<OtaScreen> {
  bool   _checking      = false;
  bool   _downloading   = false;
  bool   _sending       = false;
  bool   _complete      = false;
  String _statusText    = '';
  double _downloadPct   = 0;
  double _sendPct       = 0;
  Map<String, dynamic>? _versionInfo;
  String? _error;
  bool   _navigating    = false;  // guard against double-navigation

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
    // Listen for BLE disconnect after successful flash — navigate to scanner
    final bleService = Provider.of<BleService>(context, listen: false);
    bleService.addListener(_onBleStateChange);
  }

  @override
  void dispose() {
    final bleService = Provider.of<BleService>(context, listen: false);
    bleService.removeListener(_onBleStateChange);
    super.dispose();
  }

  void _onBleStateChange() {
    if (!_complete || _navigating) return;
    final bleService = Provider.of<BleService>(context, listen: false);
    if (!bleService.isConnected) {
      _navigating = true;
      // Small delay — let pedal finish booting before scanner starts
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ScannerScreen()),
          (route) => false,
        );
      });
    }
  }

  // ── Fetch version.json from GitHub ──────────────────────────────────────
  Future<void> _checkForUpdate() async {
    setState(() { _checking = true; _error = null; });
    try {
      final resp = await http.get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        setState(() {
          _versionInfo = jsonDecode(resp.body);
          _checking    = false;
        });
      } else {
        setState(() {
          _error    = 'Could not fetch version info (${resp.statusCode})';
          _checking = false;
        });
      }
    } catch (e) {
      setState(() {
        _error    = 'Network error: $e';
        _checking = false;
      });
    }
  }

  // ── Download binary from GitHub then send to pedal ──────────────────────
  Future<void> _startUpdate() async {
    final bleService = Provider.of<BleService>(context, listen: false);
    if (_versionInfo == null) return;

    final url     = _versionInfo!['url'] as String;
    final size    = (_versionInfo!['size'] as num).toInt();

    // Step 1: Download
    setState(() { _downloading = true; _downloadPct = 0; _statusText = 'Downloading firmware...'; });
    Uint8List binary = Uint8List(0);
    try {
      // Use simple http.get() which handles redirects automatically
      print('[OTA] Downloading from: $url');
      final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 120));
      
      print('[OTA] HTTP status: ${response.statusCode}');
      print('[OTA] Content-Length: ${response.contentLength}');
      print('[OTA] Body bytes: ${response.bodyBytes.length}');
      
      if (response.statusCode != 200) {
        setState(() {
          _downloading = false;
          _error = 'Download failed: HTTP ${response.statusCode}';
        });
        return;
      }
      
      binary = response.bodyBytes;
      setState(() { _downloading = false; _downloadPct = 1.0; });
      print('[OTA] Download complete: ${binary.length} bytes');
    } catch (e) {
      setState(() { _downloading = false; _error = 'Download failed: $e'; });
      return;
    }

    // Verify download got a real binary (should be > 100KB)
    if (binary.length < 100000) {
      setState(() { 
        _error = 'Download too small (${binary.length} bytes) - check GitHub URL'; 
      });
      return;
    }
    print('[OTA] Binary verified: ${binary.length} bytes');

    // Step 2: Send to pedal via BLE
    setState(() { _sending = true; _sendPct = 0; _statusText = 'Sending to pedal...'; });

    // Subscribe to OTA status notifications
    bleService.subscribeOtaStatus((status) {
      if (!mounted) return;
      setState(() {
        if (status['status'] == 'progress') {
          _sendPct = (status['progress'] as num) / 100.0;
          _statusText = 'Flashing... ${status['progress']}%';
        } else if (status['status'] == 'complete') {
          _sending  = false;
          _complete = true;
          _statusText = 'Update complete! Pedal is rebooting...';
        } else if (status['status'] == 'error') {
          _sending    = false;
          _error      = 'Pedal reported an error during flash';
          _statusText = '';
        }
      });
    });

    // Send START command - prefix with 0x01 type byte to identify as JSON
    final startCmd = jsonEncode({'cmd': 'start', 'size': binary.length});
    final startBytes = [0x01, ...utf8.encode(startCmd)];
    bool ok = await bleService.writeOtaCtrl(startBytes);
    if (!ok) {
      setState(() { _sending = false; _error = 'Failed to start OTA on pedal'; });
      return;
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // Send binary in chunks
    // Use smaller chunks for reliability - 200 bytes fits comfortably in BLE MTU
    const chunkSize = 199;  // +1 type byte = 200 total, fits BLE MTU
    int offset      = 0;
    int chunkNum    = 0;

    while (offset < binary.length) {
      final end   = (offset + chunkSize < binary.length) ? offset + chunkSize : binary.length;
      final chunk = binary.sublist(offset, end);

      // Prepend 0x02 type byte to identify as binary chunk
      final typedChunk = [0x02, ...chunk];
      // First 10 chunks use withoutResponse:false to confirm BLE is ready
      // After that switch to withoutResponse:true for speed
      final noResponse = chunkNum > 10;
      ok = await bleService.writeOtaCtrl(typedChunk, withoutResponse: noResponse);

      if (!ok) {
        setState(() { _sending = false; _error = 'Transfer failed at byte $offset'; });
        return;
      }

      offset   += chunk.length;
      chunkNum++;

      // Small delay every 20 chunks to let BLE stack breathe
      if (chunkNum % 20 == 0) {
        await Future.delayed(const Duration(milliseconds: 20));
        setState(() { _sendPct = offset / binary.length; });
      }
    }

    // Send END command - prefix with 0x01 type byte
    await Future.delayed(const Duration(milliseconds: 200));
    final endBytes = [0x01, ...utf8.encode(jsonEncode({'cmd': 'end'}))];
    await bleService.writeOtaCtrl(endBytes);
  }

  // ── Abort ────────────────────────────────────────────────────────────────
  Future<void> _abort() async {
    final bleService = Provider.of<BleService>(context, listen: false);
    final abortBytes = [0x01, ...utf8.encode(jsonEncode({'cmd': 'abort'}))];
    await bleService.writeOtaCtrl(abortBytes);
    setState(() { _sending = false; _downloading = false; _statusText = 'Update cancelled'; });
  }

  bool get _isUpdateAvailable {
    if (_versionInfo == null) return false;
    final bleService = Provider.of<BleService>(context, listen: false);
    final current    = bleService.firmwareVersion;
    final latest     = _versionInfo!['version'] as String? ?? '';
    return latest.isNotEmpty && latest != current;
  }

  @override
  Widget build(BuildContext context) {
    final cs         = Theme.of(context).colorScheme;
    final bleService = Provider.of<BleService>(context);
    final current    = bleService.firmwareVersion;
    final latest     = _versionInfo?['version'] as String? ?? '—';
    final notes      = _versionInfo?['notes']   as String? ?? '';
    final busy       = _downloading || _sending;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('FIRMWARE UPDATE',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                letterSpacing: 0.5, color: Colors.white)),
        backgroundColor: cs.surface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(height: 2, color: cs.secondary),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [

            // Version info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VERSIONS', style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w800, color: cs.secondary,
                        letterSpacing: 1.2)),
                    const SizedBox(height: 16),
                    _vRow('Current firmware', current.isEmpty ? 'Unknown' : current, context),
                    const SizedBox(height: 8),
                    _checking
                        ? Row(children: [
                            const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text('Checking GitHub...', style: TextStyle(
                                fontSize: 14, color: cs.onSurface.withOpacity(0.6))),
                          ])
                        : _vRow('Latest available', latest, context,
                            highlight: _isUpdateAvailable),
                    if (notes.isNotEmpty && _versionInfo != null) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text('RELEASE NOTES', style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w700, color: cs.secondary,
                          letterSpacing: 1.0)),
                      const SizedBox(height: 6),
                      Text(notes, style: TextStyle(fontSize: 13,
                          color: cs.onSurface.withOpacity(0.8), height: 1.5)),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Error
            if (_error != null)
              Card(
                color: const Color(0xFF3a0000),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: cs.error.withOpacity(0.6), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: cs.error, size: 22),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_error!,
                        style: TextStyle(color: cs.error, fontSize: 13))),
                  ]),
                ),
              ),

            // Progress
            if (busy || _complete) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_statusText, style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      if (_downloading) ...[
                        Text('Downloading firmware from GitHub...',
                            style: TextStyle(fontSize: 12,
                                color: cs.onSurface.withOpacity(0.6))),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: null,  // indeterminate while downloading
                          backgroundColor: cs.surfaceContainerHighest,
                          color: cs.tertiary,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                      if (_sending) ...[
                        Text('Flashing: ${(_sendPct * 100).toStringAsFixed(0)}%',
                            style: TextStyle(fontSize: 12,
                                color: cs.onSurface.withOpacity(0.6))),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: _sendPct,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: cs.primary,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 8),
                        Text('Do not close the app or power off the pedal',
                            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic,
                                color: cs.secondary)),
                      ],
                      if (_complete)
                        Row(children: [
                          Icon(Icons.check_circle, color: cs.primary, size: 20),
                          const SizedBox(width: 8),
                          Text('Reconnect after pedal reboots',
                              style: TextStyle(fontSize: 13, color: cs.primary)),
                        ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Buttons
            if (!busy && !_complete) ...[
              if (!bleService.isConnected)
                Card(
                  color: cs.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(Icons.bluetooth_disabled, color: cs.error, size: 20),
                      const SizedBox(width: 12),
                      Text('Pedal must be connected via BLE to update',
                          style: TextStyle(fontSize: 13,
                              color: cs.onSurface.withOpacity(0.7))),
                    ]),
                  ),
                )
              else if (_isUpdateAvailable)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startUpdate,
                    icon: const Icon(Icons.system_update),
                    label: Text('UPDATE TO $latest'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      textStyle: const TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w800, letterSpacing: 0.5),
                    ),
                  ),
                )
              else if (_versionInfo != null)
                Card(
                  color: cs.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(Icons.check_circle, color: cs.primary, size: 20),
                      const SizedBox(width: 12),
                      Text('Firmware is up to date',
                          style: TextStyle(fontSize: 13,
                              color: cs.onSurface.withOpacity(0.7))),
                    ]),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _checking ? null : _checkForUpdate,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Check Again'),
                ),
              ),
            ],

            if (busy && !_complete)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _abort,
                    icon: Icon(Icons.cancel, color: cs.error, size: 18),
                    label: Text('Abort Update', style: TextStyle(color: cs.error)),
                  ),
                ),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _vRow(String label, String value, BuildContext context,
      {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
        Text(value, style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700,
          color: highlight
              ? Theme.of(context).colorScheme.secondary
              : Theme.of(context).colorScheme.onSurface,
        )),
      ],
    );
  }
}
