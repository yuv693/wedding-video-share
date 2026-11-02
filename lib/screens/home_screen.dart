import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/backend.dart';
import '../services/video_upload_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _razorpay = Razorpay();
  final _uploadService = VideoUploadService();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool _busy = false, _uploading = false;
  double _uploadProgress = 0;
  String? _status, _driveEmail, _shareUrl;
  Map<String, dynamic>? _order, _quota, _video;

  @override
  void initState() {
    super.initState();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleIncomingLink);
    unawaited(_loadInitialLink());
    _refresh();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _loadInitialLink() async {
    try {
      _handleIncomingLink(await _appLinks.getInitialLink());
    } catch (_) {}
  }

  void _handleIncomingLink(Uri? uri) {
    if (uri != null && uri.scheme == 'weddingvideoshare' && uri.host == 'drive-connected' && mounted) {
      setState(() => _status = 'Google Drive connection returned to the app. Refreshing account details…');
      _loadQuota();
    }
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
      if (!mounted) return;
      setState(() => _order = row);
      if (row != null) {
        final video = await supabase.from('wedding_videos')
          .select('id,original_filename,file_size_bytes,upload_status')
          .eq('order_id', row['id'])
          .maybeSingle();
        if (mounted) setState(() => _video = video);
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'Account status could not be loaded. Pull down to refresh.');
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
      // No linked Drive account yet, or the server has not been configured.
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
    setState(() => _status = 'Payment submitted. Waiting for secure server verification…');
    unawaited(_pollPaymentVerification());
  }

  Future<void> _pollPaymentVerification() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      await _loadOrder();
      if (_order?['payment_status'] == 'paid') {
        if (mounted) setState(() => _status = 'Payment verified. You can now upload your wedding video.');
        return;
      }
    }
    if (mounted) setState(() => _status = 'Payment is still being confirmed. Tap Refresh in a moment.');
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (mounted) setState(() => _status = 'Payment was not completed. Please try again.');
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (mounted) setState(() => _status = 'External wallet selected: ${response.walletName ?? 'wallet'}');
  }

  Future<void> _chooseAndUpload() async {
    if (_order == null || _order!['payment_status'] != 'paid' || _order!['upload_locked'] == true) return;
    setState(() { _busy = true; _status = null; _uploadProgress = 0; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withReadStream: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (!mounted) return;
      setState(() { _uploading = true; _busy = false; _status = 'Uploading ${file.name}…'; });
      final upload = await _uploadService.upload(
        orderId: _order!['id'].toString(),
        file: file,
        onProgress: (value) {
          if (mounted) setState(() => _uploadProgress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _shareUrl = upload.shareUrl;
        _status = 'Video uploaded and verified. Your private receiver link is ready.';
        _uploading = false;
      });
      await _loadOrder();
    } catch (e) {
      if (mounted) {
        setState(() { _status = 'Upload: $e'; _uploading = false; });
        await _loadOrder();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _makeShareLink() async {
    if (_order == null) return;
    setState(() { _busy = true; _status = null; });
    try {
      final response = await supabase.functions.invoke('wedding-share', body: {
        'action': 'create_share',
        'orderId': _order!['id'],
      });
      final data = _map(response.data);
      final url = data['shareUrl']?.toString();
      if (response.status != 200 || data['ok'] != true || url == null) {
        throw Exception(data['error']?.toString() ?? 'Could not create the private link.');
      }
      if (mounted) setState(() { _shareUrl = url; _status = 'A new private receiver link has been created.'; });
    } catch (e) {
      if (mounted) setState(() => _status = 'Share link: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyShareLink() async {
    if (_shareUrl == null) return;
    await Clipboard.setData(ClipboardData(text: _shareUrl!));
    if (mounted) setState(() => _status = 'Private link copied. Send it only to your wedding guests.');
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
    final locked = _order?['upload_locked'] == true;
    final videoReady = _video?['upload_status'] == 'uploaded';
    final videoSlotUsed = _video != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wedding Video Share', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: _busy || _uploading ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
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
                    onPressed: _busy || _uploading ? null : _connectDrive,
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
                      onPressed: _busy || _uploading ? null : _startPayment,
                      style: FilledButton.styleFrom(backgroundColor: burgundy),
                      child: const Text('Pay ₹290 securely'),
                    ),
                  if (_order != null) ...[
                    const SizedBox(height: 8),
                    Text('Order status: ${_order!['payment_status'] ?? 'pending'}'),
                    if (locked) const Text('This account has completed its video cycle.'),
                  ],
                ]),
              )),
              const SizedBox(height: 12),
              Card(child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('3. Upload your wedding video', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('Choose one video up to 15 GB. It goes directly to your own Google Drive. Your phone original is not deleted.'),
                  const SizedBox(height: 12),
                  if (videoReady)
                    Text('Uploaded: ${_video!['original_filename']} (${_bytes(_video!['file_size_bytes'])})')
                  else if (videoSlotUsed)
                    const Text('This account has already used its one video slot. Create a new account for another wedding video.')
                  else
                    FilledButton.icon(
                      onPressed: _busy || _uploading || !paid || locked || _driveEmail == null ? null : _chooseAndUpload,
                      style: FilledButton.styleFrom(backgroundColor: burgundy),
                      icon: const Icon(Icons.video_file),
                      label: const Text('Choose video and upload'),
                    ),
                  if (_uploading) ...[
                    const SizedBox(height: 14),
                    LinearProgressIndicator(value: _uploadProgress),
                    const SizedBox(height: 6),
                    Text('${(_uploadProgress * 100).toStringAsFixed(1)}% uploaded'),
                  ],
                  if (!paid) const Text('Complete the ₹290 payment first.', style: TextStyle(color: Colors.black54)),
                  if (paid && _driveEmail == null) const Text('Connect Google Drive before uploading.', style: TextStyle(color: Colors.black54)),
                  if (locked) const Text('This account cannot upload another video.', style: TextStyle(color: Colors.black54)),
                ]),
              )),
              if (videoReady) ...[
                const SizedBox(height: 12),
                Card(child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('4. Share with your guests', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Create a private download link. The account is locked only after the download service verifies the full video transfer.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy || _uploading ? null : _makeShareLink,
                      icon: const Icon(Icons.link),
                      label: const Text('Create / refresh private link'),
                    ),
                    if (_shareUrl != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(_shareUrl!, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _copyShareLink,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy guest link'),
                        style: FilledButton.styleFrom(backgroundColor: burgundy),
                      ),
                    ],
                  ]),
                )),
              ],
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
