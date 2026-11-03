import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/backend.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _connectGoogleAccount() async {
    setState(() { _busy = true; _error = null; });
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'weddingvideoshare://login-callback',
        scopes: 'openid email profile',
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Google account could not be connected. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFCF8),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _busy ? null : widget.onBack,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.cloud_done_rounded, size: 68, color: burgundy),
                  const SizedBox(height: 22),
                  const Text(
                    'Connect your Google Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w800, color: burgundy),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Use one Google account to create your customer profile. You will choose Google Drive access for your wedding video in the next step.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF66575B), height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _connectGoogleAccount,
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                    label: const Text('Continue with Google'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: burgundy,
                      side: const BorderSide(color: Color(0xFFD9C5C0)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 18),
                    const Center(child: CircularProgressIndicator(color: burgundy)),
                    const SizedBox(height: 8),
                    const Text('Opening secure Google sign-in…', textAlign: TextAlign.center),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Your Google account identifies your plan. Your video will be saved to the Google Drive account you authorize separately.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
