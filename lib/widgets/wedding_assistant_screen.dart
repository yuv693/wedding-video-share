import 'package:flutter/material.dart';

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
  final List<_ChatLine> _messages = [
    const _ChatLine(
      false,
      'Hello! I’m your Wedding Video Share assistant. Ask me about Google Drive, video upload, ₹290 payment, sharing links or guest downloads.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _ask(String question) {
    final q = question.toLowerCase();
    String answer;
    if (q.contains('payment') || q.contains('₹290') || q.contains('pay') || q.contains('qr')) {
      answer = 'Your payment status is: ${widget.paymentStatus}. QR/UPI requests show as pending until the owner checks the real Paytm receipt and approves them. “I have paid” is only a request, not proof. Never share your UPI PIN or OTP.';
    } else if (q.contains('drive') || q.contains('google')) {
      answer = widget.driveEmail.isEmpty
          ? 'Google Drive is not currently shown as connected. Open the Videos tab and tap Connect Google Drive before uploading.'
          : 'Google Drive is connected as ${widget.driveEmail}. Your video is stored in your own Drive.';
    } else if (q.contains('upload') || q.contains('video') || q.contains('40 gb') || q.contains('size')) {
      answer = 'Video status: ${widget.uploadStatus}. This plan supports one wedding video up to 40 GB. Choose the same file again if an interrupted upload needs to resume. Your phone original is not deleted.';
    } else if (q.contains('link') || q.contains('share') || q.contains('pin') || q.contains('password')) {
      answer = widget.paymentStatus == 'paid'
          ? 'After your video is uploaded and payment is verified, open the Videos tab and create or refresh the private guest link. Send the six-digit download password separately from the link.'
          : 'First upload your video, then complete the ₹290 payment. The private guest link and six-digit password are available after the server verifies payment.';
    } else if (q.contains('download') || q.contains('guest') || q.contains('receiver')) {
      answer = 'The guest opens the private link, enters the six-digit password and downloads the video. The server checks the full transfer before marking it complete. An interrupted transfer is not treated as completed.';
    } else if (q.contains('new wedding') || q.contains('another') || q.contains('second')) {
      answer = 'Each customer account is for one wedding-video sharing cycle. To share another wedding, use the Account tab and choose Start another wedding. It creates a separate account and needs a separate ₹290 payment.';
    } else if (q.contains('status') || q.contains('account') || q.contains('pending')) {
      answer = 'Here is the current app status: Google Drive: ${widget.driveEmail.isEmpty ? 'not connected' : widget.driveEmail}; video: ${widget.uploadStatus}; payment: ${widget.paymentStatus}; manual QR request: ${widget.manualPaymentStatus}; upload locked: ${widget.uploadLocked ? 'yes' : 'no'}. Pull down on Home to refresh.';
    } else if (q.contains('delete') || q.contains('remove')) {
      answer = 'Only the Google Drive copy can be deleted from the app. Your original phone video is not deleted. Automatic deletion after a guest download happens only when you explicitly consent and the server verifies the full transfer.';
    } else {
      answer = 'I can help with Google Drive connection, video upload, ₹290 QR payment, private sharing links, guest downloads and starting another wedding. Try one of those topics. For account-specific errors, share the exact error message with support, but never send passwords, OTPs or UPI PINs.';
    }

    setState(() {
      _messages.add(_ChatLine(true, question));
      _messages.add(_ChatLine(false, answer));
    });
    _controller.clear();
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
                    Text('Wedding Assistant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: burgundy)),
                    SizedBox(height: 3),
                    Text('Guided help for your wedding sharing journey', style: TextStyle(fontSize: 12, color: Color(0xFF66575B))),
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
              onPressed: () { final value = _controller.text.trim(); if (value.isNotEmpty) _ask(value); },
              style: IconButton.styleFrom(backgroundColor: burgundy, foregroundColor: Colors.white),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'This first version uses built-in help rules, not a live generative AI service. It cannot approve payments or access private bank information.',
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
