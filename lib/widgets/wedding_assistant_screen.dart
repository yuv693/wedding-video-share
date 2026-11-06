import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

import '../services/backend.dart';

/// In-app guided help for the Wedding Video Share customer journey.
/// This first version uses verified product rules locally; it does not send
/// customer messages, PINs, payment details or videos to an AI provider.
class WeddingAssistantScreen extends StatefulWidget {
  const WeddingAssistantScreen({
    super.key,
    required this.paymentStatus,
    required this.uploadStatus,
    required this.driveEmail,
    required this.manualPaymentStatus,
    required this.uploadLocked,
  });

  final String paymentStatus;
  final String uploadStatus;
  final String driveEmail;
  final String manualPaymentStatus;
  final bool uploadLocked;

  @override
  State<WeddingAssistantScreen> createState() => _WeddingAssistantScreenState();
}

class _WeddingAssistantScreenState extends State<WeddingAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _overlayBusy = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _speechReady = false;
  bool _listening = false;
  String _speechLocale = 'hi_IN';

  Future<void> _enableFloatingAndee() async {
    if (_overlayBusy) return;
    setState(() => _overlayBusy = true);
    try {
      var granted = await FlutterOverlayWindow.isPermissionGranted();
      if (granted != true) {
        granted = await FlutterOverlayWindow.requestPermission() ?? false;
      }
      if (granted != true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please allow Display over other apps for Wedding Video Share.')),
        );
        return;
      }
      await FlutterOverlayWindow.showOverlay(
        height: 72,
        width: 72,
        alignment: OverlayAlignment.centerRight,
        enableDrag: true,
        positionGravity: PositionGravity.auto,
        overlayTitle: 'Andee AI is ready',
        overlayContent: 'Tap the floating Andee bubble to open Help in Wedding Video Share.',
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Floating Andee is on. You can drag the bubble around your screen.')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start Floating Andee: $e')),
      );
    } finally {
      if (mounted) setState(() => _overlayBusy = false);
    }
  }
  final List<_ChatLine> _messages = [
    const _ChatLine(
      false,
      'Hello! I’m Andee, your Wedding Video Share AI assistant. Ask me about Google Drive, video upload, ₹290 payment, sharing links or guest downloads.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initVoice();
  }

  Future<void> _initVoice() async {
    try {
      _speechReady = await _speech.initialize(
        onStatus: (status) { if (mounted) setState(() => _listening = status == 'listening'); },
        onError: (error) { if (mounted) setState(() => _listening = false); },
      );
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _speechReady = false);
    }
  }

  Future<void> _toggleListening() async {
    if (!_speechReady) {
      await _initVoice();
      if (!_speechReady && mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition unavailable. Check microphone permission and Google speech services.')),
      );
      return;
    }
    if (_speech.isListening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    await _tts.stop();
    await _speech.listen(
      localeId: _speechLocale,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      onResult: (result) {
        if (!mounted) return;
        setState(() => _controller.text = result.recognizedWords);
        _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) _ask(result.recognizedWords);
      },
    );
    if (mounted) setState(() => _listening = true);
  }

  Future<void> _speakAnswer(String text) async {
    try {
      await _tts.stop();
      final hasGujarati = RegExp(r'[\\u0A80-\\u0AFF]').hasMatch(text);
      final hasHindi = RegExp(r'[\\u0900-\\u097F]').hasMatch(text);
      await _tts.setLanguage(hasGujarati ? 'gu-IN' : (hasHindi ? 'hi-IN' : 'en-IN'));
      await _tts.speak(text);
    } catch (_) {}
  }

  @override
  void dispose() {
    _speech.cancel();
    _tts.stop();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatLine(true, trimmed));
      _sending = true;
    });
    _controller.clear();

    try {
      final response = await supabase.functions.invoke(
        'wedding-ai-assistant',
        body: {
          'question': trimmed,
          'appStatus': {
            'paymentStatus': widget.paymentStatus,
            'uploadStatus': widget.uploadStatus,
            'driveConnected': widget.driveEmail.isNotEmpty,
            'manualPaymentStatus': widget.manualPaymentStatus,
            'uploadLocked': widget.uploadLocked,
          },
        },
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (response.status != 200 || data['answer'] is! String) {
        throw Exception(data['error']?.toString() ?? 'AI assistant is unavailable.');
      }
      if (!mounted) return;
      final answer = data['answer'] as String;
      setState(() => _messages.add(_ChatLine(false, answer)));
      await _speakAnswer(answer);
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages.add(const _ChatLine(
        false,
        'AI assistant abhi connect nahi ho pa raha. Thodi der baad dobara try karein. Payment, OTP, UPI PIN ya guest password chat mein share na karein.',
      )));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    final suggestions = ['Payment / ₹290', 'Connect Google Drive', 'Upload video', 'Guest download'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF4EAE6),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              CircleAvatar(
                backgroundColor: burgundy,
                child: Icon(Icons.auto_awesome, color: Colors.white),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Andee AI Assistant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: burgundy)),
                    SizedBox(height: 3),
                    Text('Your smart wedding-sharing helper', style: TextStyle(fontSize: 12, color: Color(0xFF66575B))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _overlayBusy ? null : _enableFloatingAndee,
          icon: const Icon(Icons.bubble_chart_outlined),
          label: Text(_overlayBusy ? 'Starting Andee…' : 'Enable Floating Andee'),
        ),
        const Text(
          'Android will ask once for permission to display the Andee bubble over other apps. Tap the bubble to switch to the Andee Help tab in this app.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestions.map((s) => ActionChip(
            label: Text(s),
            onPressed: () => _ask(s),
          )).toList(),
        ),
        const SizedBox(height: 12),
        Container(
          height: 330,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFEADFD9)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return Align(
                alignment: message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 290),
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: message.fromUser ? const Color(0xFFF4EAE6) : const Color(0xFFF8F6F4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(message.text, style: const TextStyle(height: 1.4)),
                ),
              );
            },
          ),
        ),
        if (_sending) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (value) { if (value.trim().isNotEmpty) _ask(value.trim()); },
                decoration: const InputDecoration(
                  hintText: 'Ask about your wedding video…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: _listening ? 'Stop listening' : 'Ask Andee by voice',
              onPressed: _sending ? null : _toggleListening,
              icon: Icon(_listening ? Icons.mic : Icons.mic_none_rounded, color: _listening ? Colors.red : burgundy, size: 28),
            ),
            IconButton.filled(
              onPressed: _sending ? null : () { final value = _controller.text.trim(); if (value.isNotEmpty) _ask(value); },
              style: IconButton.styleFrom(backgroundColor: burgundy, foregroundColor: Colors.white),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        DropdownButton<String>(
          value: _speechLocale,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'hi_IN', child: Text('Voice language: Hindi')),
            DropdownMenuItem(value: 'gu_IN', child: Text('Voice language: Gujarati')),
            DropdownMenuItem(value: 'en_IN', child: Text('Voice language: English')),
          ],
          onChanged: (value) { if (value != null) setState(() => _speechLocale = value); },
        ),
        const SizedBox(height: 8),
        const Text(
          'AI answers are for guidance only. Payment approval is done by the owner after checking the real receipt. Never share OTP, UPI PIN, passwords or guest download PIN here.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }
}

class _ChatLine {
  const _ChatLine(this.fromUser, this.text);
  final bool fromUser;
  final String text;
}
