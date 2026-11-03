import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'services/backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
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

/// Creates a private backend customer session without Supabase Google sign-in.
/// The customer connects Google Drive directly from the home screen.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _starting = false;
  bool _signedIn = supabase.auth.currentSession != null;
  String? _error;

  Future<void> _getStarted() async {
    setState(() { _starting = true; _error = null; });
    try {
      if (supabase.auth.currentSession == null) {
        await supabase.auth.signInAnonymously();
      }
      if (mounted) setState(() => _signedIn = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error =
          'Account setup is not enabled yet. Please contact support. (' + e.message + ')');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start your account. Please try again.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_signedIn) return const HomeScreen();
    return WelcomeScreen(
      onGetStarted: _getStarted,
      busy: _starting,
      error: _error,
    );
  }
}
