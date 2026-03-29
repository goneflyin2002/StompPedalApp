import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/scanner_screen.dart';
import 'services/ble_service.dart';

void main() {
  runApp(const PedalConfigApp());
}


class PedalConfigApp extends StatelessWidget {
  const PedalConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BleService(),
      child: MaterialApp(
        title: 'Pedal Config',
        theme: ThemeData(
          colorScheme: ColorScheme.dark(
            surface: const Color(0xFF2d2d2d),         // Card background
            surfaceContainerHighest: const Color(0xFF3a3a3a),  // Elevated surfaces
            primary: const Color(0xFF4CAF50),         // Green - active/success
            secondary: const Color(0xFFff9800),       // Orange - highlights
            tertiary: const Color(0xFF00bcd4),        // Cyan - info
            error: const Color(0xFFf44336),           // Red - errors
            onSurface: const Color(0xFFFFFFFF),       // White text on cards
            onPrimary: const Color(0xFF000000),       // Black text on green
            onSecondary: const Color(0xFF000000),     // Black text on orange
          ),
          scaffoldBackgroundColor: const Color(0xFF1a1a1a),  // Dark charcoal (was background)
          cardTheme: CardThemeData(
            color: const Color(0xFF2d2d2d),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: const Color(0xFF000000),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF3a3a3a),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 2),
            ),
          ),
          useMaterial3: true,
        ),
        home: const ScannerScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
