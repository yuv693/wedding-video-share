import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/backend.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _identity = TextEditingController();
  final _otp = TextEditingController();
  bool _usePhone = false, _codeSent = false, _busy = false;
  String? _message, _error;

  @override
  void dispose() { _identity.dispose(); _otp.dispose(); super.dispose(); }

  String get _normalizedPhone {
    final value = _identity.text.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (value.startsWith('+')) return value;
    if (value.length == 10) return '+91$value';
    return '+$value';
  }

  Future<void> _sendCode() async {
    final value = _identity.text.trim();
    if (value.isEmpty) {
      setState(() => _error = _usePhone ? 'Enter your mobile number.' : 'Enter your email address.');
      return;
    }
    setState(() { _busy = true; _error = null; _message = null; });
    try {
      if (_usePhone) {
        await supabase.auth.signInWithOtp(phone: _normalizedPhone, shouldCreateUser: true);
      } else {
        await supabase.auth.signInWithOtp(email: value, shouldCreateUser: true);
      }
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _message = 'Verification code sent. Please check your ${_usePhone ? 'SMS' : 'email'}.';
      });
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _otp.text.trim();
    if (code.length < 4) { setState(() => _error = 'Enter the verification code.'); return; }
    setState(() { _busy = true; _error = null; _message = null; });
    try {
      await supabase.auth.verifyOTP(
        type: _usePhone ? OtpType.sms : OtpType.email,
        token: code,
        email: _usePhone ? null : _identity.text.trim(),
        phone: _usePhone ? _normalizedPhone : null,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Verification failed. Please check the code and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.favorite, size: 54, color: burgundy),
                  const SizedBox(height: 18),
                  const Text('Welcome', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: burgundy)),
                  const SizedBox(height: 8),
                  const Text('Sign in to share your wedding memories.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 28),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Email'), icon: Icon(Icons.email_outlined)),
                      ButtonSegment(value: true, label: Text('Phone'), icon: Icon(Icons.phone_android)),
                    ],
                    selected: {_usePhone},
                    onSelectionChanged: _busy ? null : (v) => setState(() {
                      _usePhone = v.first; _codeSent = false; _otp.clear(); _error = null; _message = null;
                    }),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _identity,
                    enabled: !_codeSent && !_busy,
                    keyboardType: _usePhone ? TextInputType.phone : TextInputType.emailAddress,
                    autofillHints: _usePhone ? const [AutofillHints.telephoneNumber] : const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: _usePhone ? 'Mobile number' : 'Email address',
                      hintText: _usePhone ? '9876543210' : 'you@example.com',
                      prefixIcon: Icon(_usePhone ? Icons.phone : Icons.mail_outline),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 14),
                    TextField(controller: _otp, keyboardType: TextInputType.number, maxLength: 8,
                      decoration: const InputDecoration(labelText: 'Verification code',
                        prefixIcon: Icon(Icons.lock_outline), border: OutlineInputBorder())),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!, style: const TextStyle(color: Colors.green), textAlign: TextAlign.center),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : (_codeSent ? _verifyCode : _sendCode),
                    style: FilledButton.styleFrom(backgroundColor: burgundy, padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_codeSent ? 'Verify and continue' : 'Send verification code'),
                  ),
                  if (_codeSent)
                    TextButton(onPressed: _busy ? null : () => setState(() {
                      _codeSent = false; _otp.clear(); _message = null;
                    }), child: const Text('Change email or phone number')),
                  const SizedBox(height: 20),
                  const Text('By continuing, you agree to use Wedding Video Share responsibly.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black45)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
