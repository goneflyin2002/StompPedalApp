import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import 'config_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  String statusMessage = "";

  @override
  void initState() {
    super.initState();
    checkPermissions();
  }

  Future<void> checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    
    if (!allGranted) {
      setState(() {
        statusMessage = "Bluetooth permissions required";
      });
    } else {
      startScan();
    }
  }

  Future<void> startScan() async {
    setState(() {
      isScanning = true;
      scanResults.clear();
      statusMessage = "Scanning for Pedal Config...";
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          scanResults = results;
          if (results.isEmpty) {
            statusMessage = "No devices found yet...";
          } else {
            statusMessage = "Found ${results.length} device(s)";
          }
        });
      });

      await Future.delayed(const Duration(seconds: 10));
      await FlutterBluePlus.stopScan();

      setState(() {
        isScanning = false;
        if (scanResults.isEmpty) {
          statusMessage = "No devices found. Make sure pedal is powered on.";
        }
      });
    } catch (e) {
      setState(() {
        isScanning = false;
        statusMessage = "Scan error: $e";
      });
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    final bleService = Provider.of<BleService>(context, listen: false);

    if (!mounted) return;
    
    try {
      // connect() internally calls readAllData() - navigate after data is loaded
      await bleService.connect(device);
      
      if (!mounted) return;
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ConfigScreen()),
      );
      
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Pedal Config'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Status message
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    if (isScanning)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    if (!isScanning)
                      Icon(
                        Icons.bluetooth,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        statusMessage,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Scan Again button
            if (!isScanning)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: startScan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Scan Again'),
                ),
              ),
            
            const SizedBox(height: 24),
            
            // Device list
            if (scanResults.isEmpty && !isScanning)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bluetooth_disabled,
                        size: 64,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "No devices found",
                        style: TextStyle(
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Make sure your pedal is powered on",
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: scanResults.length,
                  itemBuilder: (context, index) {
                    final result = scanResults[index];
                    final device = result.device;
                    final deviceName = device.platformName.isNotEmpty 
                        ? device.platformName 
                        : "Unknown Device";
                    
                    // Highlight our pedal
                    final isPedalConfig = deviceName.contains("Pedal Config");
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isPedalConfig 
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                          : null,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Icon(
                          Icons.bluetooth,
                          color: isPedalConfig 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          size: 32,
                        ),
                        title: Text(
                          deviceName,
                          style: TextStyle(
                            fontWeight: isPedalConfig ? FontWeight.bold : FontWeight.normal,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              device.remoteId.toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                            if (isPedalConfig)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "Pedal Config",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          color: Theme.of(context).colorScheme.primary,
                          size: 16,
                        ),
                        onTap: () => connectToDevice(device),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
