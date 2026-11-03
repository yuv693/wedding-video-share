import 'package:flutter/material.dart';

/// Informational step retained for compatibility with older navigation.
/// Customer identity is handled by the app; Google Drive is connected
/// separately from the Home screen through the Drive OAuth flow.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF8),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack,
        ),
        title: const Text('Your account'),
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
                    'Your account is ready',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: burgundy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Connect Google Drive separately from the Home screen. Choose the Google account where you want your wedding video stored.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF66575B), height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: onBack,
                    style: FilledButton.styleFrom(
                      backgroundColor: burgundy,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Continue to Home'),
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
