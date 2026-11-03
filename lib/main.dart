import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const WeddingVideoShareApp());
}

class WeddingVideoShareApp extends StatelessWidget {
  const WeddingVideoShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    return MaterialApp(
      title: 'Wedding Video Share',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFFCF8),
        colorScheme: ColorScheme.fromSeed(seedColor: burgundy, brightness: Brightness.light),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFCF8),
          foregroundColor: burgundy,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _subscription;
  bool _signedIn = supabase.auth.currentSession != null;
  bool _showWelcome = true;

  @override
  void initState() {
    super.initState();
    _subscription = supabase.auth.onAuthStateChange.listen((state) {
      if (mounted) setState(() => _signedIn = state.session != null);
    });
  }

  @override
  void dispose() { _subscription?.cancel(); super.dispose(); }

  @override
  @override
  Widget build(BuildContext context) {
    if (_signedIn) return const HomeScreen();
    if (_showWelcome) {
      return WelcomeScreen(onGetStarted: () {
        if (mounted) setState(() => _showWelcome = false);
      });
    }
    return AuthScreen(onBack: () {
      if (mounted) setState(() => _showWelcome = true);
    });
  }
}
