import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: burgundy,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFCF8),
          foregroundColor: burgundy,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const WelcomeScreen(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    const gold = Color(0xFFB28A4A);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Wedding Video Share',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 28),
                  Container(
                    height: 190,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4EAE6),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Center(
                      child: Icon(Icons.favorite, size: 76, color: burgundy),
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Your wedding memories,\nbeautifully shared.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 29,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: burgundy,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Share your wedding video privately with family and friends. Your video is stored in your own Google Drive.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: burgundy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Account setup will be enabled after authentication integration.',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Get Started',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'One account • One wedding video • ₹290',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Maximum video size: 15 GB. Upload permission is locked only after the server verifies the receiver transfer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
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
