import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onGetStarted,
    this.onRecoverAccount,
    this.busy = false,
    this.error,
  });

  final VoidCallback onGetStarted;
  final VoidCallback? onRecoverAccount;
  final bool busy;
  final String? error;

  static const burgundy = Color(0xFF6F2438);
  static const gold = Color(0xFFC49A54);
  static const ivory = Color(0xFFFFFCF8);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ivory,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 42,
                        width: 42,
                        decoration: const BoxDecoration(color: burgundy, shape: BoxShape.circle),
                        child: const Icon(Icons.favorite_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      const Text('WEDDING VIDEO SHARE', style: TextStyle(
                        color: burgundy, fontSize: 13, letterSpacing: 1.3, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 34),
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4EAE6),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFFE8D8D0)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 112, width: 112,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            shape: BoxShape.circle,
                            border: Border.all(color: gold, width: 1.5),
                          ),
                          child: const Icon(Icons.favorite_rounded, color: burgundy, size: 54),
                        ),
                        const SizedBox(height: 24),
                        const Text('Celebrate. Share. Cherish.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: burgundy, fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        const Text('Your wedding memories, beautifully shared.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: burgundy, fontSize: 27, height: 1.18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        const Text('One wedding. One clear plan. Your own Google Drive.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF66575B), fontSize: 15, height: 1.5)),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
                          child: const Text('₹290  •  One wedding video',
                            style: TextStyle(color: burgundy, fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  const _WelcomeStep(number: '1', icon: Icons.person_outline_rounded,
                    title: 'Start your customer account',
                    detail: 'No separate Google sign-in is needed here.'),
                  const SizedBox(height: 12),
                  const _WelcomeStep(number: '2', icon: Icons.cloud_outlined,
                    title: 'Connect your Google Drive',
                    detail: 'Choose your Google account and allow access to save your video in your own Drive.'),
                  const SizedBox(height: 12),
                  const _WelcomeStep(number: '3', icon: Icons.video_file_outlined,
                    title: 'Upload first, pay when you share',
                    detail: 'Upload one video up to 15 GB for free. Pay ₹290 only when you are ready to create your private share link.'),
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: busy ? null : onGetStarted,
                    style: FilledButton.styleFrom(
                      backgroundColor: burgundy, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    child: busy
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Get Started'),
                  ),
                  if (onRecoverAccount != null) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: busy ? null : onRecoverAccount,
                      child: const Text('Already have an account? Recover it'),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 12),
                  const Text('Your Google Drive copy remains there until you choose to delete it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF7A6A6D), fontSize: 12, height: 1.4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.number, required this.icon, required this.title, required this.detail});
  final String number;
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 42, width: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF6F2438).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: const Color(0xFF6F2438)),
        ),
        const SizedBox(width: 13),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$number. $title', style: const TextStyle(
              color: Color(0xFF3B2C31), fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 3),
            Text(detail, style: const TextStyle(
              color: Color(0xFF77696B), fontSize: 13, height: 1.4)),
          ],
        )),
      ],
    );
  }
}
