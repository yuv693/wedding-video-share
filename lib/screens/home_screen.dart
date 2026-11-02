import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/backend.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _razorpay = Razorpay();
  StreamSubscription<Uri>? _linkSubscription;
  bool _busy = false;
  String? _status, _driveEmail;
  Map<String, dynamic>? _order, _quota;

  @override
  void initState() {
    super.initState();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _linkSubscription = AppLinks().uriLinkStream.listen((uri) {
      if (uri.scheme == 'weddingvideoshare' && uri.host == 'drive-connected' && mounted) {
        setState(() => _status = 'Google Drive connection returned to the app. Refreshing account details…');
        _loadQuota();
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _razorpay.clear();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  Future<void> _refresh() async {
    await _loadOrder();
    await _loadQuota();
  }

  Future<void> _loadOrder() async {
    try {
      final row = await supabase.from('wedding_orders')
        .select('id,payment_status,upload_locked,workflow_status')
        .maybeSingle();
      if (mounted) setState(() => _order = row);
    } catch (_) {
      if (mounted) setState(() => _status = 'Account status will appear after your first payment attempt.');
    }
  }

  Future<void> _loadQuota() async {
    try {
      final response = await supabase.functions.invoke('google-drive-storage', body: {'action': 'quota'});
      final data = _map(response.data);
      if (response.status == 200 && data['ok'] == true && mounted) {
        setState(() { _quota = data; _driveEmail = data['email']?.toString(); });
      }
    } catch (_) {
      // Google Drive must be connected before its quota can be read.
    }
  }

  Future<void> _connectDrive() async {
    setState(() { _busy = true; _status = null; });
    try {
      final response = await supabase.functions.invoke('google-drive-oauth', body: {'action': 'start'});
      final data = _map(response.data);
      final authUrl = data['authorizationUrl']?.toString();
      if (response.status != 200 || authUrl == null) {
        throw Exception(data['error']?.toString() ?? 'Google Drive setup is not ready.');
      }
      if (!await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open Google sign-in.');
      }
      if (mounted) setState(() => _status = 'Finish Google permission in the browser, then return to this app.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Drive connection: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startPayment() async {
    setState(() { _busy = true; _status = null; });
    try {
      final response = await supabase.functions.invoke('razorpay-payments', body: {'action': 'create_order'});
      final data = _map(response.data);
      if (response.status != 200 || data['ok'] != true) {
        throw Exception(data['note']?.toString() ?? data['error']?.toString() ?? 'Payment setup is not ready.');
      }
      final keyId = data['keyId']?.toString();
      final gatewayOrderId = data['razorpayOrderId']?.toString();
      if (keyId == null || gatewayOrderId == null) throw Exception('Payment order details were incomplete.');
      _razorpay.open({
        'key': keyId,
        'amount': 29000,
        'currency': 'INR',
        'name': 'Wedding Video Share',
        'description': 'One wedding video upload and share',
        'order_id': gatewayOrderId,
        'prefill': {
          'email': supabase.auth.currentUser?.email ?? '',
          'contact': supabase.auth.currentUser?.phone ?? '',
        },
        'theme': {'color': '#6F2438'},
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Payment: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) {
    if (!mounted) return;
    setState(() => _status = 'Payment submitted. The server webhook must verify it before upload is enabled.');
    // A client callback is never treated as proof of payment.
    Future<void>.delayed(const Duration(seconds: 2), _loadOrder);
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (mounted) setState(() => _status = 'Payment was not completed. Please try again.');
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (mounted) setState(() => _status = 'External wallet selected: ${response.walletName ?? 'wallet'}');
  }

  String _bytes(dynamic value) {
    final n = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    if (n >= 1024 * 1024 * 1024) return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (n >= 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(n / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    final user = supabase.auth.currentUser;
    final paid = _order?['payment_status'] == 'paid';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wedding Video Share', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
          IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout), tooltip: 'Sign out'),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: const Color(0xFFF4EAE6), borderRadius: BorderRadius.circular(22)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.favorite, color: burgundy, size: 34),
                  const SizedBox(height: 12),
                  const Text('Your wedding memories, beautifully shared.',
                    style: TextStyle(fontSize: 23, height: 1.2, fontWeight: FontWeight.w800, color: burgundy)),
                  const SizedBox(height: 8),
                  Text(user?.email ?? user?.phone ?? 'Your account'),
                ]),
              ),
              const SizedBox(height: 18),
              Card(child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('1. Connect your Google Drive', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(_driveEmail == null ? 'Your video will be stored in your own Google Drive.' : 'Connected: $_driveEmail'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _connectDrive,
                    icon: const Icon(Icons.add_link),
                    label: Text(_driveEmail == null ? 'Connect Google Drive' : 'Reconnect Google Drive'),
                  ),
                  if (_quota != null) ...[
                    const SizedBox(height: 8),
                    Text('Drive used: ${_bytes(_quota!['usedBytes'])}  •  Available: ${_quota!['availableBytes'] == null ? 'Not reported' : _bytes(_quota!['availableBytes'])}'),
                  ],
                ]),
              )),
              const SizedBox(height: 12),
              Card(child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('2. One wedding video plan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('₹290 • One account • One video upload and share cycle'),
                  const Text('Maximum video size: 15 GB (decimal).'),
                  const SizedBox(height: 12),
                  if (paid)
                    const Row(children: [Icon(Icons.verified, color: Colors.green), SizedBox(width: 8), Text('Payment verified by server')])
                  else
                    FilledButton(
                      onPressed: _busy ? null : _startPayment,
                      style: FilledButton.styleFrom(backgroundColor: burgundy),
                      child: const Text('Pay ₹290 securely'),
                    ),
                  if (_order != null) ...[
                    const SizedBox(height: 8),
                    Text('Order status: ${_order!['payment_status'] ?? 'pending'}'),
                    if (_order!['upload_locked'] == true) const Text('This account has completed its video cycle.'),
                  ],
                ]),
              )),
              const SizedBox(height: 12),
              Card(child: const Padding(
                padding: EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('3. Video upload and sharing', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text('The next app module will add large-file streaming upload, resumable transfer, and a private receiver link. Your phone original will never be deleted by the app.'),
                ]),
              )),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFF8F0E8), borderRadius: BorderRadius.circular(12)),
                  child: Text(_status!),
                ),
              ],
              const SizedBox(height: 20),
              const Text('Need help? Contact the Wedding Video Share support team.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
