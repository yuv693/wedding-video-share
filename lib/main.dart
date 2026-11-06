import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/andee_overlay.dart';

import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'screens/account_recovery_screen.dart';
import 'services/backend.dart';

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AndeeFloatingBubble(),
  ));
}

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

/// Supabase keeps the private app customer record. Google OAuth confirms
/// the customer's Google account and grants the separate Drive file permission.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _starting = false;
  bool _signedIn = supabase.auth.currentSession != null;
  bool _recovering = false;
  String? _error;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = supabase.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        _signedIn = state.session != null;
        if (_signedIn) _recovering = false;
      });
    });
    if (supabase.auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_connectDriveForExistingCustomer());
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startGoogleDriveConsent() async {
    final response = await supabase.functions.invoke(
      'google-drive-oauth',
      body: {'action': 'start'},
    );
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final authorizationUrl = data['authorizationUrl']?.toString();
    if (response.status != 200 || data['ok'] != true || authorizationUrl == null) {
      throw Exception(data['error']?.toString() ??
          'Google Drive confirmation is not configured yet. Please try again later.');
    }
    final opened = await launchUrl(
      Uri.parse(authorizationUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw Exception('Could not open Google confirmation.');
  }

  Future<void> _connectDriveForExistingCustomer() async {
    try {
      final quota = await supabase.functions.invoke(
        'google-drive-storage',
        body: {'action': 'quota'},
      );
      final data = quota.data is Map
          ? Map<String, dynamic>.from(quota.data as Map)
          : <String, dynamic>{};
      if (quota.status == 200 && data['ok'] == true && data['email'] != null) return;
      await _startGoogleDriveConsent();
    } catch (e) {
      debugPrint('Automatic Google Drive connection could not start: $e');
    }
  }

  Future<void> _getStarted() async {
    setState(() { _starting = true; _error = null; });
    try {
      if (supabase.auth.currentSession == null) {
        await supabase.auth.signInAnonymously();
      }
      await _startGoogleDriveConsent();
      if (mounted) setState(() => _signedIn = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error =
          'Account setup is not enabled yet. Please contact support. (' + e.message + ')');
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not start Google confirmation. Please try again. Details: $e');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_signedIn) return const HomeScreen();
    if (_recovering) {
      return AccountRecoveryScreen(
        onBack: () => setState(() => _recovering = false),
        onAuthenticated: () => setState(() { _signedIn = true; _recovering = false; }),
      );
    }
    return WelcomeScreen(
      onGetStarted: _getStarted,
      onRecoverAccount: () => setState(() => _recovering = true),
      busy: _starting,
      error: _error,
    );
  }
}
