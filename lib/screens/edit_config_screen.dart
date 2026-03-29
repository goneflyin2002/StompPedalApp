import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';

class EditConfigScreen extends StatefulWidget {
  final String channelName;
  final Map<String, dynamic> channelConfig;
  final bool isChannelA;

  const EditConfigScreen({
    super.key,
    required this.channelName,
    required this.channelConfig,
    required this.isChannelA,
  });

  @override
  State<EditConfigScreen> createState() => _EditConfigScreenState();
}

class _EditConfigScreenState extends State<EditConfigScreen> {
  late int selectedMode;
  late int muteChannel;
  late int muteBus;
  late int muteMgrp;
  late int muteAux;
  late int muteMain;
  late int muteMtx;
  late int muteDca;
  late int muteFxrtn;
  late int muteAuxin;
  late int muteMainST;
  late int muteMainM;
  late int muteFxsend;
  late int fxNum;
  late int sceneNum;

  // Get valid modes for current mixer type
  List<int> getValidModesForMixer(int mixerType) {
    if (mixerType == 0) {
      // WING modes
      return [0, 1, 2, 3, 4, 5, 6, 7, 14]; // Tap, Ch, Bus, Mgrp, Aux, Main, Mtx, DCA, Scene
    } else if (mixerType == 1) {
      // X32 modes
      return [0, 1, 2, 6, 7, 8, 9, 10, 11, 14]; // Tap, Ch, Bus, Mtx, DCA, FXRtn, AuxIn, M/ST, M/C, Scene
    } else {
      // XR18 modes
      return [0, 1, 2, 7, 12, 13, 14]; // Tap, Ch, Bus, DCA, FXSend, M/LR, Scene
    }
  }

  @override
  void initState() {
    super.initState();
    
    // Load current values
    // Safe int helper - JSON values from ArduinoJson may be int, double or null
    int safeInt(String key, int defaultVal) {
      final v = widget.channelConfig[key];
      if (v == null) return defaultVal;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString()) ?? defaultVal;
    }

    selectedMode = safeInt('mode', 0);
    muteChannel  = safeInt('muteChannel', 1);
    muteBus      = safeInt('muteBus', 1);
    muteMgrp     = safeInt('muteMgrp', 1);
    muteAux      = safeInt('muteAux', 1);
    muteMain     = safeInt('muteMain', 1);
    muteMtx      = safeInt('muteMtx', 1);
    muteDca      = safeInt('muteDca', 1);
    muteFxrtn    = safeInt('muteFxrtn', 1);
    muteAuxin    = safeInt('muteAuxin', 1);
    muteMainST   = safeInt('muteMainST', 1);
    muteMainM    = safeInt('muteMainM', 1);
    muteFxsend   = safeInt('muteFxsend', 1);
    fxNum        = safeInt('fxNum', 1);

    // For sceneNum, prefer the live mixer scene over the saved value --
    // the mixer may have advanced via stomps since the config was last saved
    final bleService = Provider.of<BleService>(context, listen: false);
    final liveScene = bleService.currentSceneNumber;
    sceneNum = (liveScene > 0) ? liveScene : (widget.channelConfig['sceneNum'] ?? 1);

    // Refresh names in background so dropdowns (FX, channel, bus etc.)
    // are populated even if the names haven't loaded yet.
    // Use readNamesOnly to avoid overwriting config the user is editing.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await bleService.readNamesOnly();
    });
  }

  Future<void> saveConfig() async {
    final bleService = Provider.of<BleService>(context, listen: false);
    
    // Build updated channel config
    Map<String, dynamic> updatedChannel = {
      'mode': selectedMode,
      'muteChannel': muteChannel,
      'muteBus': muteBus,
      'muteMgrp': muteMgrp,
      'muteAux': muteAux,
      'muteMain': muteMain,
      'muteMtx': muteMtx,
      'muteDca': muteDca,
      'muteFxrtn': muteFxrtn,
      'muteAuxin': muteAuxin,
      'muteMainST': muteMainST,
      'muteMainM': muteMainM,
      'muteFxsend': muteFxsend,
      'fxNum': fxNum,
      'sceneNum': sceneNum,
    };

    // Get full config
    Map<String, dynamic> fullConfig = Map.from(bleService.pedalConfig ?? {});
    
    // Update the correct channel
    if (widget.isChannelA) {
      fullConfig['channelA'] = updatedChannel;
    } else {
      fullConfig['channelB'] = updatedChannel;
    }

    // Transient sceneJump - pedal executes jump then discards, never saved to flash
    if (selectedMode == 14 && sceneNum >= 1) {
      fullConfig['sceneJump'] = sceneNum;
    } else {
      fullConfig.remove('sceneJump');
    }

    // Show saving dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Saving to pedal..."),
              ],
            ),
          ),
        ),
      ),
    );

    // Write to pedal
    bool success = await bleService.writeConfig(fullConfig);

    if (!mounted) return;
    Navigator.pop(context); // Close dialog

    if (success) {
      // Show success and go back
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuration saved!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context); // Go back to config screen
    } else {
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: ${bleService.statusMessage}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, bleService, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'STOMP ${widget.channelName} — Edit Config',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
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
            actions: [
              IconButton(
                icon: Icon(Icons.refresh,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                tooltip: 'Refresh Names',
                onPressed: () async {
                  await bleService.readAllData();
                  setState(() {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Names refreshed!')),
                    );
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Mode Selection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MODE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        value: () {
                          final validModes = getValidModesForMixer(bleService.mixerInfo?['mixerType'] ?? 0);
                          return validModes.contains(selectedMode) ? selectedMode : validModes.first;
                        }(),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Select Mode',
                        ),
                        items: getValidModesForMixer(bleService.mixerInfo?['mixerType'] ?? 0)
                            .map((modeIndex) {
                          return DropdownMenuItem(
                            value: modeIndex,
                            child: Text(bleService.getModeName(modeIndex)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedMode = value ?? 0;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Target Selection (based on mode)
              _buildTargetSelector(bleService),

              const SizedBox(height: 24),

              // Save Button
              FilledButton.icon(
                onPressed: saveConfig,
                icon: const Icon(Icons.save),
                label: const Text('Save to Pedal'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTargetSelector(BleService bleService) {
    switch (selectedMode) {
      case 0: // Tap Tempo
        return _buildFXSelector(bleService);
      case 1: // Mute Channel
        return _buildChannelSelector(bleService);
      case 2: // Mute Bus
        return _buildBusSelector(bleService);
      case 3: // Mute Mgrp
        return _buildMgrpSelector(bleService);
      case 4: // Mute Aux
        return _buildAuxSelector(bleService);
      case 5: // Mute Main
        return _buildMainSelector(bleService);
      case 6: // Mute Mtx
        return _buildMtxSelector(bleService);
      case 7: // Mute DCA
        return _buildDCASelector(bleService);
      case 8: // Mute FX Return
        return _buildFXRtnSelector(bleService);
      case 9: // Mute Aux In
        return _buildAuxInSelector(bleService);
      case 10: // Mute M/ST (X32) — no target selector needed
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('No target selection needed for Main ST'),
          ),
        );
      case 11: // Mute M/C (X32) — no target selector needed
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('No target selection needed for Main M/C'),
          ),
        );
      case 12: // Mute FX Send (XR18 only)
        return _buildFXSendSelector(bleService);
      case 13: // Mute M/LR (XR18) — no target selector needed
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('No target selection needed for Main LR'),
          ),
        );
      case 14: // Scene Control
        return _buildSceneSelector(bleService);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildChannelSelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'CHANNEL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: muteChannel,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select Channel',
              ),
              items: List.generate(bleService.channelNames.length, (index) {
                String name = bleService.channelNames[index];
                String label = name.isEmpty 
                    ? 'Ch ${index + 1}'
                    : 'Ch ${index + 1} - $name';
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  muteChannel = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusSelector(BleService bleService) {
    // Fallback if names haven't loaded yet
    int maxBuses = bleService.busNames.isEmpty ? 16 : bleService.busNames.length;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'BUS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: muteBus,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select Bus',
              ),
              items: List.generate(maxBuses, (index) {
                String name = index < bleService.busNames.length 
                    ? bleService.busNames[index] 
                    : '';
                String label = name.isEmpty 
                    ? 'Bus ${index + 1}'
                    : 'Bus ${index + 1} - $name';
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  muteBus = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFXSelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'FX SLOT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: fxNum,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select FX',
              ),
              items: List.generate(bleService.fxNames.length, (index) {
                String name = bleService.fxNames[index];
                String label = name.isEmpty 
                    ? 'FX ${index + 1}'
                    : 'FX ${index + 1} - $name';
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  fxNum = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberSelector(
    String label,
    int currentValue,
    int min,
    int max,
    Function(int) onChanged,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: currentValue,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Select $label',
              ),
              items: List.generate(max - min + 1, (index) {
                int value = min + index;
                return DropdownMenuItem(
                  value: value,
                  child: Text('$label $value'),
                );
              }),
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Mgrp selector with names (WING only)
  Widget _buildMgrpSelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'MUTE GROUP',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: muteMgrp,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select Mute Group',
              ),
              items: List.generate(bleService.mgrpNames.length, (index) {
                String name = bleService.mgrpNames[index];
                String label = name.isEmpty 
                    ? 'Mgrp ${index + 1}'
                    : 'Mgrp ${index + 1} - $name';
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  muteMgrp = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // Aux selector with names (WING only)
  Widget _buildAuxSelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'AUX',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: muteAux,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select Aux',
              ),
              items: List.generate(bleService.auxNames.length.clamp(0, 8), (index) {
                String name = bleService.auxNames[index];
                String label = name.isEmpty 
                    ? 'Aux ${index + 1}'
                    : 'Aux ${index + 1} - $name';
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  muteAux = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // Main selector with names
  Widget _buildMainSelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'MAIN',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: muteMain,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select Main',
              ),
              items: List.generate(bleService.mainNames.length, (index) {
                String name = bleService.mainNames[index];
                String label = name.isEmpty 
                    ? 'Main ${index + 1}'
                    : name; // Main names are usually short like "L", "C", "R"
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  muteMain = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // Mtx selector with names
  Widget _buildMtxSelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'MATRIX',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: muteMtx,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select Matrix',
              ),
              items: List.generate(bleService.mtxNames.length, (index) {
                String name = bleService.mtxNames[index];
                String label = name.isEmpty 
                    ? 'Mtx ${index + 1}'
                    : 'Mtx ${index + 1} - $name';
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  muteMtx = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // DCA selector with names
  Widget _buildDCASelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'DCA',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: muteDca,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select DCA',
              ),
              items: List.generate(bleService.dcaNames.length, (index) {
                String name = bleService.dcaNames[index];
                String label = name.isEmpty 
                    ? 'DCA ${index + 1}'
                    : 'DCA ${index + 1} - $name';
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  muteDca = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // FXRtn selector with names (X32 only)
  // X32 FX returns are stereo pairs: Fx 1L, Fx 1R, Fx 2L, Fx 2R ... Fx 4L, Fx 4R
  String _fxRtnLabel(int index) {
    final pair   = (index ~/ 2) + 1;  // 1-4
    final side   = (index % 2 == 0) ? 'L' : 'R';
    return 'Fx $pair$side';
  }

  Widget _buildFXRtnSelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'FX RETURN',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: muteFxrtn,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select FX Return',
              ),
              items: List.generate(bleService.fxrtnNames.length, (index) {
                final xLabel = _fxRtnLabel(index);
                final name   = bleService.fxrtnNames[index];
                final label  = name.isEmpty ? xLabel : '$xLabel · $name';
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  muteFxrtn = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // AuxIn selector with names (X32 only)
  Widget _buildAuxInSelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'AUX IN',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: muteAuxin,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select Aux In',
              ),
              items: List.generate(bleService.auxinNames.length, (index) {
                String name = bleService.auxinNames[index];
                String label = name.isEmpty 
                    ? 'AuxIn ${index + 1}'
                    : 'AuxIn ${index + 1} - $name';
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  muteAuxin = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // FXSend selector with names (XR18 only)
  Widget _buildFXSendSelector(BleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                        'FX SEND',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: muteFxsend,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Select FX Send',
              ),
              items: List.generate(bleService.fxsendNames.length, (index) {
                String name = bleService.fxsendNames[index];
                String label = name.isEmpty 
                    ? 'FXSend ${index + 1}'
                    : 'FXSend ${index + 1} - $name';
                return DropdownMenuItem(
                  value: index + 1,
                  child: Text(label),
                );
              }),
              onChanged: (value) {
                setState(() {
                  muteFxsend = value ?? 1;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // Scene selector with names (or numbers if names unavailable)
  Widget _buildSceneSelector(BleService bleService) {
    const int maxScenes = 24;
    final names   = bleService.sceneNames;
    final hasNames = names.isNotEmpty && names.any((n) => n.isNotEmpty);

    return Column(
      children: [
        // Scene dropdown card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SCENE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.secondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasNames
                      ? '${names.where((n) => n.isNotEmpty).length} scenes loaded from mixer'
                      : 'Scene name displays on pedal when loaded',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: sceneNum,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Select Scene',
                  ),
                  selectedItemBuilder: (context) => List.generate(maxScenes, (index) {
                    String label = 'Scene ${index + 1}';
                    if (index < names.length && names[index].isNotEmpty) {
                      label = '${index + 1}  -  ${names[index]}';
                    }
                    return Text(label, overflow: TextOverflow.ellipsis, maxLines: 1);
                  }),
                  items: List.generate(maxScenes, (index) {
                    String label = 'Scene ${index + 1}';
                    if (index < names.length && names[index].isNotEmpty) {
                      label = '${index + 1}  -  ${names[index]}';
                    }
                    return DropdownMenuItem(
                      value: index + 1,
                      child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
                    );
                  }),
                  onChanged: (value) {
                    setState(() { sceneNum = value ?? 1; });
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Warning card
        Card(
          color: const Color(0xFF3a2800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: const Color(0xFFff9800).withOpacity(0.6),
              width: 1.5,
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFff9800), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Scene Control: tap = next snapshot, long press = previous snapshot.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFFffcc80),
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
