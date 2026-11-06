import 'package:flutter/material.dart';

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
  final List<_ChatLine> _messages = [
    const _ChatLine(
      false,
      'Hello! I’m Andee, your Wedding Video Share AI assistant. Ask me about Google Drive, video upload, ₹290 payment, sharing links or guest downloads.',
    ),
  ];

  @override
  void dispose() {
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
      setState(() => _messages.add(_ChatLine(false, data['answer'] as String)));
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
            IconButton.filled(
              onPressed: _sending ? null : () { final value = _controller.text.trim(); if (value.isNotEmpty) _ask(value); },
              style: IconButton.styleFrom(backgroundColor: burgundy, foregroundColor: Colors.white),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
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
