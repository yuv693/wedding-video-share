import 'dart:ui';
import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted, this.onRecoverAccount, this.busy = false, this.error});
  final VoidCallback onGetStarted;
  final VoidCallback? onRecoverAccount;
  final bool busy;
  final String? error;
  static const burgundy = Color(0xFF70243B);
  static const ivory = Color(0xFFFFF8EC);
  static const muted = Color(0xFF6F5C59);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ivory,
    body: Stack(fit: StackFit.expand, children: [
      const _CelebrationBackdrop(),
      SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final cardWidth = constraints.maxWidth.clamp(280.0, 420.0).toDouble();
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 56),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: cardWidth,
                constraints: const BoxConstraints(minHeight: 440, maxHeight: 560),
                padding: const EdgeInsets.fromLTRB(26, 44, 26, 34),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  border: Border.all(color: burgundy, width: 1.4),
                  boxShadow: const [BoxShadow(color: Color(0x226F2438), blurRadius: 32, offset: Offset(0, 16))],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const SizedBox(height: 8),
                  Column(children: [
                    Container(
                      height: 76, width: 76,
                      decoration: const BoxDecoration(color: burgundy, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const Text('WVS', style: TextStyle(color: Colors.white, fontFamily: 'Georgia', fontSize: 19, letterSpacing: 0.4)),
                    ),
                    const SizedBox(height: 24),
                    const Text('Celebrate. Share. Cherish.', textAlign: TextAlign.center,
                      style: TextStyle(color: burgundy, fontFamily: 'Georgia', fontSize: 15, fontWeight: FontWeight.w500)),
                  ]),
                  Column(children: [
                    SizedBox(width: double.infinity, child: FilledButton(
                      onPressed: busy ? null : onGetStarted,
                      style: FilledButton.styleFrom(
                        backgroundColor: burgundy, foregroundColor: Colors.white,
                        disabledBackgroundColor: burgundy.withValues(alpha: 0.55),
                        padding: const EdgeInsets.symmetric(vertical: 17),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      child: busy ? const SizedBox(height: 19, width: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Get Started'),
                    )),
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ]),
                ]),
              ),
              if (onRecoverAccount != null) ...[
                const SizedBox(height: 20),
                TextButton(onPressed: busy ? null : onRecoverAccount, style: TextButton.styleFrom(foregroundColor: burgundy),
                  child: const Text('Already have an account? Recover it')),
              ],
              const SizedBox(height: 10),
              const Text('One wedding. One beautiful way to share.', textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12, letterSpacing: 0.35)),
            ])),
          ),
        );
      })),
    ]),
  );
}

class _CelebrationBackdrop extends StatelessWidget {
  const _CelebrationBackdrop();
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    Row(children: [
      Expanded(flex: 5, child: Container(color: const Color(0xFFFFF8EC))),
      const Expanded(flex: 5, child: Image(image: AssetImage('assets/wedding_photo.jpg'), fit: BoxFit.cover, alignment: Alignment.center)),
    ]),
    Positioned.fill(child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      child: Container(color: const Color(0x44FFF4E6)),
    )),
    Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: [const Color(0xFFFFF8EC).withValues(alpha: 0.10), const Color(0xFFFFF8EC).withValues(alpha: 0.02)]),
    ))),
  ]);
}
