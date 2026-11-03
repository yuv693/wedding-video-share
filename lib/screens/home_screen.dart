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
  String? _status, _driveEmail, _shareUrl, _sharePin;
  Map<String, dynamic>? _order, _quota, _video;
  List<Map<String, dynamic>> _notifications = [];

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
    await _loadNotifications();
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
          .select('id,original_filename,file_size_bytes,upload_status,google_drive_account_email,deleted_at')
          .eq('order_id', row['id'])
          .maybeSingle();
        if (mounted) setState(() => _video = video);
      } else {
        setState(() => _video = null);
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

  Future<void> _loadNotifications() async {
    try {
      final rows = await supabase.from('customer_notifications')
        .select('id,notification_type,title,message,created_at,read_at')
        .order('created_at', ascending: false)
        .limit(5);
      if (!mounted) return;
      setState(() => _notifications = rows.map((row) => _map(row)).toList());
    } catch (_) {
      // Notifications are optional UI; the server remains the source of truth.
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
        _sharePin = upload.downloadPin;
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
      if (mounted) setState(() { _shareUrl = url; _sharePin = data['downloadPin']?.toString(); _status = 'Private link and 6-digit download password are ready. Send them separately.'; });
    } catch (e) {
      if (mounted) setState(() => _status = 'Share link: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDriveCopy() async {
    if (_video == null || _video!['id'] == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your Google Drive copy?'),
        content: const Text(
          'This permanently deletes the Wedding Video Share copy from your own Google Drive. '
          'The original video on your phone will not be touched. Your one-video plan will remain used.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep video'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6F2438)),
            child: const Text('Delete Drive copy'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() { _busy = true; _status = null; });
    try {
      final response = await supabase.functions.invoke('google-drive-storage', body: {
        'action': 'delete_video',
        'videoId': _video!['id'],
      });
      final data = _map(response.data);
      if (response.status != 200 || data['ok'] != true || data['deleted'] != true) {
        throw Exception(data['error']?.toString() ?? 'The Google Drive copy could not be deleted.');
      }
      if (mounted) {
        setState(() => _status =
            'Your Google Drive copy was deleted. The original video on your phone is untouched. This account’s one-video slot remains used.');
      }
      await _loadOrder();
    } catch (e) {
      if (mounted) setState(() => _status = 'Delete: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _notificationDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '';
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  Future<void> _openLegal(String document) async {
    final uri = Uri.parse('https://github.com/yuv693/wedding-video-share/blob/main/docs/$document');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyShareLink() async {
    if (_shareUrl == null) return;
    await Clipboard.setData(ClipboardData(text: _shareUrl!));
    if (mounted) setState(() => _status = 'Private link copied. Send the password separately.');
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
    final videoDeleted = _video?['upload_status'] == 'deleted';
    final videoSlotUsed = _video != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wedding Video Share', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: _busy || _uploading ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
          IconButton(onPressed: _busy || _uploading ? null : () => supabase.auth.signOut(), icon: const Icon(Icons.logout), tooltip: 'Sign out'),
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
                  const SizedBox(height: 8),
                  const Text('One wedding. One video. Your own Drive.',
                    style: TextStyle(color: Color(0xFF66575B), fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 18),
              Card(child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('1. Connect your Google Drive', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(_driveEmail == null
                      ? 'Your video is stored in your own Google Drive. Wedding Video Share does not provide video storage.'
                      : 'Connected to your Google Drive: $_driveEmail'),
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
                  const Text('Choose one video up to 15 GB. It uploads to your own Google Drive; your phone original is never deleted. If the connection stops, choose the same file again to resume.'),
                  const SizedBox(height: 12),
                  if (videoReady)
                    Text('Uploaded: ${_video!['original_filename']} (${_bytes(_video!['file_size_bytes'])})')
                  else if (videoDeleted)
                    const Text('Your Google Drive copy was deleted by you. The phone original remains untouched; this one-video plan cannot be reused.')
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
                    const Text('Uploading to your Google Drive…', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _uploadProgress),
                    const SizedBox(height: 6),
                    Text('${(_uploadProgress * 100).toStringAsFixed(1)}% uploaded · resumable 8 MB chunks'),
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
                    const Text('Create a private download link and send the 6-digit password separately. Your Google Drive copy stays saved until you choose to delete it.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy || _uploading ? null : _makeShareLink,
                      icon: const Icon(Icons.link),
                      label: const Text('Create / refresh private link'),
                    ),
                    if (_shareUrl != null) ...[
                      const SizedBox(height: 8),
                      const Text('Private receiver link', style: TextStyle(fontWeight: FontWeight.w700)),
                      SelectableText(_shareUrl!, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 12),
                      if (_sharePin != null) ...[
                        const Text('6-digit download password', style: TextStyle(fontWeight: FontWeight.w700)),
                        SelectableText(_sharePin!, style: const TextStyle(fontSize: 26, letterSpacing: 5, fontWeight: FontWeight.w800, color: burgundy)),
                        const Text('Send this password separately from the link.', style: TextStyle(color: Colors.black54, fontSize: 12)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: _sharePin!)); if (mounted) setState(() => _status = 'Download password copied.'); }, icon: const Icon(Icons.password), label: const Text('Copy password')),
                      ],
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _copyShareLink,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy guest link'),
                        style: FilledButton.styleFrom(backgroundColor: burgundy),
                      ),
                    ],
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _busy || _uploading ? null : _deleteDriveCopy,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete my Google Drive copy'),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Only the Drive copy is deleted. Your phone original is not touched.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ]),
                )),
              ],
              if (videoDeleted) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined, color: burgundy),
                    title: const Text('Drive copy deleted'),
                    subtitle: const Text('Your phone original remains untouched. This account’s one-video plan stays used.'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.notifications_active_outlined, color: burgundy),
                          SizedBox(width: 8),
                          Text('Guest download updates', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_notifications.isEmpty)
                        const Text('When your guest finishes the full video transfer, a completion update will appear here.')
                      else
                        for (final notification in _notifications)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              notification['notification_type'] == 'receiver_download_completed'
                                  ? Icons.check_circle_rounded
                                  : Icons.notifications_none_rounded,
                              color: notification['notification_type'] == 'receiver_download_completed'
                                  ? Colors.green
                                  : burgundy,
                            ),
                            title: Text(notification['title']?.toString() ?? 'Account update',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(notification['message']?.toString() ?? ''),
                            trailing: Text(
                              _notificationDate(notification['created_at']),
                              style: const TextStyle(fontSize: 10, color: Colors.black54),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFF8F0E8), borderRadius: BorderRadius.circular(12)),
                  child: Text(_status!),
                ),
              ],
              const SizedBox(height: 20),
              const Text('Wedding Video Share', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 12)),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(onPressed: () => _openLegal('privacy-policy.md'), child: const Text('Privacy Policy')),
                  TextButton(onPressed: () => _openLegal('terms-of-service.md'), child: const Text('Terms of Service')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
