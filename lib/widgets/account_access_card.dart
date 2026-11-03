import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/backend.dart';

class AccountAccessCard extends StatefulWidget {
  const AccountAccessCard({super.key, required this.onLinked});

  final VoidCallback onLinked;

  @override
  State<AccountAccessCard> createState() => _AccountAccessCardState();
}

class _AccountAccessCardState extends State<AccountAccessCard> {
  final _email = TextEditingController();
  final _otp = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    super.dispose();
  }

  String? get _confirmedEmail => supabase.auth.currentUser?.emailConfirmedAt == null
      ? null
      : supabase.auth.currentUser?.email;

  Future<void> _sendCode() async {
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() { _message = 'Enter a valid email address.'; _error = true; });
      return;
    }
    setState(() { _busy = true; _message = null; _error = false; });
    try {
      await supabase.auth.updateUser(UserAttributes(email: email));
      if (!mounted) return;
      setState(() {
        _sent = true;
        _message = 'A verification code has been requested. Check your email and enter the code here.';
      });
    } on AuthException catch (e) {
      if (mounted) setState(() { _message = e.message; _error = true; });
    } catch (_) {
      if (mounted) setState(() { _message = 'Could not request verification. Please try again.'; _error = true; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final email = _email.text.trim().toLowerCase();
    final code = _otp.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() { _message = 'Enter the 6-digit code from your email.'; _error = true; });
      return;
    }
    setState(() { _busy = true; _message = null; _error = false; });
    try {
      await supabase.auth.verifyOTP(email: email, token: code, type: OtpType.emailChange);
      if (!mounted) return;
      final confirmed = supabase.auth.currentUser?.emailConfirmedAt != null;
      setState(() {
        _sent = false;
        _message = confirmed
            ? 'Email verified. Your account can now be recovered on another device.'
            : 'Verification was accepted. Refresh your account status to confirm the email.';
        _error = !confirmed;
      });
      if (confirmed) widget.onLinked();
    } on AuthException catch (e) {
      if (mounted) setState(() { _message = e.message; _error = true; });
    } catch (_) {
      if (mounted) setState(() { _message = 'Could not verify the code. Please try again.'; _error = true; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    final email = _confirmedEmail;
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFEADFD9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.verified_user_outlined, color: burgundy),
              SizedBox(width: 8),
              Text('Protect your account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            if (email != null) ...[
              const Text('Your recovery email is verified. Use this same email to sign in if you change or reset your phone.'),
              const SizedBox(height: 8),
              Text(email, style: const TextStyle(fontWeight: FontWeight.w700, color: burgundy)),
            ] else ...[
              const Text('Verify an email address before paying. You can use it to recover this same customer account if you change or reset your phone.'),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                enabled: !_busy && !_sent,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Your email address',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              if (_sent) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _otp,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '6-digit email code',
                    prefixIcon: Icon(Icons.password_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : (_sent ? _verifyCode : _sendCode),
                  style: FilledButton.styleFrom(backgroundColor: burgundy),
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_sent ? 'Verify email' : 'Send verification code'),
                ),
              ),
              if (_sent)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _sendCode,
                    child: const Text('Resend code'),
                  ),
                ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!, style: TextStyle(color: _error ? Colors.red.shade700 : Colors.green.shade700)),
            ],
          ],
        ),
      ),
    );
  }
}
