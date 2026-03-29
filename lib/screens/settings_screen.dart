import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wifi_scan/wifi_scan.dart';
import '../services/ble_service.dart';
import 'ota_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int mixerType;
  late int tapFlashMode;
  late bool secondaryPedal;
  late TextEditingController ssidController;
  late TextEditingController passwordController;
  late TextEditingController ipController;
  
  bool _passwordVisible = false;
  bool _isSaving = false;
  bool _isScanning = false;

  Future<void> _scanWiFiNetworks() async {
    setState(() {
      _isScanning = true;
    });

    try {
      // Check if WiFi scan is supported
      final can = await WiFiScan.instance.canStartScan();
      if (can != CanStartScan.yes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WiFi scanning not available: $can'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        setState(() {
          _isScanning = false;
        });
        return;
      }

      // Start scan
      await WiFiScan.instance.startScan();
      
      // Wait a bit for scan to complete
      await Future.delayed(const Duration(seconds: 2));
      
      // Get results
      final results = await WiFiScan.instance.getScannedResults();
      
      setState(() {
        _isScanning = false;
      });

      if (!mounted) return;

      // Show network selection dialog
      _showNetworkSelectionDialog(results);
      
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('WiFi scan error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showNetworkSelectionDialog(List<WiFiAccessPoint> networks) {
    // Remove duplicates (same SSID) and sort by signal strength
    final Map<String, WiFiAccessPoint> uniqueNetworks = {};
    for (var network in networks) {
      if (network.ssid.isNotEmpty) {
        if (!uniqueNetworks.containsKey(network.ssid) ||
            network.level > uniqueNetworks[network.ssid]!.level) {
          uniqueNetworks[network.ssid] = network;
        }
      }
    }
    
    final sortedNetworks = uniqueNetworks.values.toList()
      ..sort((a, b) => b.level.compareTo(a.level));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Network'),
        content: SizedBox(
          width: double.maxFinite,
          child: sortedNetworks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No networks found'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: sortedNetworks.length,
                  itemBuilder: (context, index) {
                    final network = sortedNetworks[index];
                    final signalStrength = network.level;
                    
                    // Determine signal icon and color
                    IconData signalIcon;
                    Color signalColor;
                    if (signalStrength > -50) {
                      signalIcon = Icons.wifi;
                      signalColor = Theme.of(context).colorScheme.primary;
                    } else if (signalStrength > -70) {
                      signalIcon = Icons.wifi_2_bar;
                      signalColor = Theme.of(context).colorScheme.secondary;
                    } else {
                      signalIcon = Icons.wifi_1_bar;
                      signalColor = Theme.of(context).colorScheme.error;
                    }

                    return ListTile(
                      leading: Icon(signalIcon, color: signalColor),
                      title: Text(network.ssid),
                      subtitle: Text('${signalStrength} dBm'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        setState(() {
                          ssidController.text = network.ssid;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // Safe type helpers - ArduinoJson may return int, double or null
  int _cfgInt(dynamic v, int def) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? def;
  }
  bool _cfgBool(dynamic v, bool def) {
    if (v == null) return def;
    if (v is bool) return v;
    return v.toString() == 'true';
  }

  @override
  void initState() {
    super.initState();
    
    final bleService = Provider.of<BleService>(context, listen: false);
    final config = bleService.pedalConfig;
    final mixer = config?['mixer'] ?? {};
    
    // Load current values
    mixerType      = _cfgInt(mixer['type'], 0);
    tapFlashMode   = _cfgInt(config?['tapFlashMode'], 2);
    secondaryPedal = _cfgBool(config?['secondaryPedal'], false);
    
    ssidController = TextEditingController(text: mixer['ssid'] ?? '');
    // Password not returned from pedal for security - leave blank, only fill to change
    passwordController = TextEditingController(text: '');
    
    // Load IP for current mixer type
    String currentIP = '';
    if (mixerType == 0) {
      currentIP = mixer['ipWING'] ?? '192.168.8.234';
    } else if (mixerType == 1) {
      currentIP = mixer['ipX32'] ?? '192.168.0.103';
    } else {
      currentIP = mixer['ipXR18'] ?? '192.168.1.101';
    }
    
    ipController = TextEditingController(text: currentIP);
  }

  @override
  void dispose() {
    ssidController.dispose();
    passwordController.dispose();
    ipController.dispose();
    super.dispose();
  }

  void _onMixerTypeChanged(int newType) {
    setState(() {
      final oldType = mixerType;
      mixerType = newType;
      
      // Update IP field to show new mixer's IP
      final bleService = Provider.of<BleService>(context, listen: false);
      final mixer = bleService.pedalConfig?['mixer'] ?? {};
      
      String newIP = '';
      if (mixerType == 0) {
        newIP = mixer['ipWING'] ?? '192.168.8.234';
      } else if (mixerType == 1) {
        newIP = mixer['ipX32'] ?? '192.168.0.103';
      } else {
        newIP = mixer['ipXR18'] ?? '192.168.1.101';
      }
      
      ipController.text = newIP;
    });
  }

  Future<void> _saveSettings() async {
    final bleService = Provider.of<BleService>(context, listen: false);
    
    if (!bleService.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Not connected to pedal'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    // Build config with only current mixer's IP
    final config = bleService.pedalConfig ?? {};
    final channelA = config['channelA'] ?? {};
    final channelB = config['channelB'] ?? {};
    
    final newConfig = {
      'channelA': channelA,
      'channelB': channelB,
      'mixer': {
        'type': mixerType,
        'ssid': ssidController.text,
        // Only send password if user typed one - blank means keep existing
        if (passwordController.text.isNotEmpty) 'password': passwordController.text,
        'ip': ipController.text,  // Single IP field!
      },
      'tapFlashMode':   tapFlashMode,
      'secondaryPedal': secondaryPedal,
    };
    
    final success = await bleService.writeConfig(newConfig);
    
    setState(() {
      _isSaving = false;
    });
    
    if (!mounted) return;
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Settings saved successfully'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to save settings'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  String _getMixerName(int type) {
    switch (type) {
      case 0: return 'WING';
      case 1: return 'X32';
      case 2: return 'XR18';
      default: return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text(
          'SETTINGS',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: Colors.white,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            height: 2,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Mixer Type Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MIXER TYPE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('WING')),
                      ButtonSegment(value: 1, label: Text('X32')),
                      ButtonSegment(value: 2, label: Text('XR18')),
                    ],
                    selected: {mixerType},
                    onSelectionChanged: (Set<int> selection) {
                      _onMixerTypeChanged(selection.first);
                    },
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context).colorScheme.primary;
                        }
                        return Theme.of(context).colorScheme.surfaceVariant;
                      }),
                      foregroundColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context).colorScheme.onPrimary;
                        }
                        return Theme.of(context).colorScheme.onSurface;
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // WiFi Settings Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WIFI NETWORK',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: ssidController,
                          decoration: const InputDecoration(
                            labelText: 'SSID',
                            hintText: 'Network name',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isScanning ? null : _scanWiFiNetworks,
                        icon: _isScanning
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.wifi_find, size: 20),
                        label: const Text('Scan'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: !_passwordVisible,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Leave blank to keep current password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _passwordVisible ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _passwordVisible = !_passwordVisible;
                          });
                        },
                      ),
                    ),
                    autofillHints: const [AutofillHints.password],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Mixer IP Section - Single field!
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'MIXER IP ADDRESS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _getMixerName(mixerType),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ipController,
                    decoration: InputDecoration(
                      labelText: '${_getMixerName(mixerType)} IP',
                      hintText: '192.168.x.x',
                    ),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Port: ${mixerType == 0 ? '2223' : mixerType == 1 ? '10023' : '10024'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Tap Flash Mode Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TAP FLASH MODE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Off')),
                      ButtonSegment(value: 1, label: Text('20x')),
                      ButtonSegment(value: 2, label: Text('Always')),
                    ],
                    selected: {tapFlashMode},
                    onSelectionChanged: (Set<int> selection) {
                      setState(() {
                        tapFlashMode = selection.first;
                      });
                    },
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context).colorScheme.primary;
                        }
                        return Theme.of(context).colorScheme.surfaceVariant;
                      }),
                      foregroundColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context).colorScheme.onPrimary;
                        }
                        return Theme.of(context).colorScheme.onSurface;
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Info card
          Card(
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Changing WiFi or mixer settings will cause the pedal to reconnect. This may take up to 20 seconds.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Secondary Pedal toggle - must be top-level ListView item for bounded width
          Card(
            child: SwitchListTile(
              value: secondaryPedal,
              onChanged: (val) => setState(() { secondaryPedal = val; }),
              activeColor: Theme.of(context).colorScheme.primary,
              title: const Text('Secondary Pedal',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Use polling mode (200ms). Enable when running two pedals simultaneously.',
                style: TextStyle(fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Firmware Update Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FIRMWARE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.secondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Installed version',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      Consumer<BleService>(
                        builder: (context, ble, _) => Text(
                          ble.firmwareVersion.isEmpty ? 'Unknown' : ble.firmwareVersion,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const OtaScreen())),
                      icon: const Icon(Icons.system_update, size: 18),
                      label: const Text('Check for Updates'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Text(
                      'SAVE SETTINGS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
      ),  // SafeArea
    );
  }
}
