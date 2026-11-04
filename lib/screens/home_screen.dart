import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/backend.dart';
import '../services/firebase_backend.dart';
import '../services/firebase_drive_service.dart';
import '../services/firebase_wedding_service.dart';
import '../widgets/account_access_card.dart';
import '../services/video_upload_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _razorpay = Razorpay();
  final _uploadService = VideoUploadService(useFirebase: true);
  final _firebaseDrive = FirebaseDriveService();
  final _firebaseWedding = FirebaseWeddingService();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool _busy = false, _uploading = false, _autoDeleteConsent = false;
  int _selectedTab = 0;
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

  bool get _accountProtected {
    final legacyUser = supabase.auth.currentUser;
    final firebaseUser = FirebaseBackend.currentUser;
    return legacyUser?.emailConfirmedAt != null &&
        firebaseUser?.email != null &&
        firebaseUser!.email!.toLowerCase() == legacyUser!.email?.toLowerCase();
  }

  Future<void> _startNewWedding() async {
    if (_order?['upload_locked'] != true) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start another wedding?'),
        content: const Text('This creates a separate customer account for a new wedding. The new account needs its own verified recovery email and a new ₹290 payment. Your completed wedding remains saved in the previous account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Create new account')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await supabase.auth.signOut();
      await FirebaseBackend.signOut();
      await FirebaseBackend.signInAnonymouslyIfNeeded();
      await supabase.auth.signInAnonymously();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create a new wedding account: $e')),
        );
      }
    }
  }

  Future<void> _refresh() async {
    await _loadOrder();
    await _loadQuota();
    await _loadNotifications();
  }

  Future<void> _loadOrder() async {
    try {
      await _firebaseWedding.bootstrapCustomer();
      final state = await _firebaseWedding.getAccountState();
      final rawOrder = _map(state['order']);
      final rawVideo = _map(state['video']);
      final order = rawOrder.isEmpty ? null : <String, dynamic>{
        'id': FirebaseBackend.currentUser?.uid,
        'payment_status': rawOrder['paymentStatus'],
        'upload_locked': rawOrder['uploadLocked'],
        'workflow_status': rawOrder['workflowStatus'],
      };
      final video = rawVideo.isEmpty ? null : <String, dynamic>{
        'id': rawVideo['id'], 'original_filename': rawVideo['originalFilename'],
        'file_size_bytes': rawVideo['fileSizeBytes'], 'upload_status': rawVideo['uploadStatus'],
        'google_drive_account_email': rawVideo['googleDriveAccountEmail'],
        'deleted_at': rawVideo['deletedAt'], 'auto_delete_consent_at': rawVideo['autoDeleteConsentAt'],
      };
      final notifications = (state['notifications'] as List? ?? const []).map((item) {
        final row = _map(item);
        return <String, dynamic>{
          'id': row['id'], 'notification_type': row['notificationType'],
          'title': row['title'], 'message': row['message'],
          'created_at': row['createdAt'], 'read_at': row['readAt'],
        };
      }).toList();
      if (!mounted) return;
      setState(() {
        _order = order; _video = video;
        _autoDeleteConsent = video?['auto_delete_consent_at'] != null;
        _notifications = notifications;
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'Firebase account status could not be loaded. Pull down to refresh.');
    }
  }

  Future<void> _loadQuota() async {
    try {
      final data = await _firebaseDrive.getConnection();
      if (mounted) setState(() => _driveEmail = data['connected'] == true ? data['email']?.toString() : null);
    } catch (_) {
      if (mounted) setState(() => _driveEmail = null);
    }
  }

  Future<void> _loadNotifications() async {
    // Loaded together with the Firebase account state in _loadOrder().
  }

  Future<void> _connectDrive() async {
    setState(() { _busy = true; _status = null; });
    try {
      final opened = await _firebaseDrive.connectGoogleDrive();
      if (!opened) throw Exception('Could not open Google sign-in.');
      if (mounted) setState(() => _status = 'Complete Google permission in the browser, then return to this app.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Drive connection: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startPayment() async {
    if (!_autoDeleteConsent) {
      if (mounted) setState(() => _status = 'Please confirm automatic Google Drive deletion after the receiver’s full verified download before payment.');
      return;
    }
    if (_video?['upload_status'] != 'uploaded' || _order == null) {
      setState(() => _status = 'Upload your wedding video first. Payment is needed when you share it.');
      return;
    }
    if (!_accountProtected) {
      setState(() { _selectedTab = 2; _status = 'Verify your recovery email before payment so you can recover this customer account later.'; });
      return;
    }
    setState(() { _busy = true; _status = null; });
    try {
      final data = await _firebaseWedding.createRazorpayOrder();
      final keyId = data['keyId']?.toString();
      final gatewayOrderId = data['razorpayOrderId']?.toString();
      if (data['ok'] != true || keyId == null || gatewayOrderId == null) {
        throw Exception(data['error']?.toString() ?? 'Payment setup is not ready.');
      }
      _razorpay.open({
        'key': keyId, 'amount': 29000, 'currency': 'INR',
        'name': 'Wedding Video Share',
        'description': 'One wedding video upload and share',
        'order_id': gatewayOrderId,
        'prefill': {
          'email': FirebaseBackend.currentUser?.email ?? supabase.auth.currentUser?.email ?? '',
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

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    setState(() => _status = 'Payment submitted. Verifying securely with Firebase and Razorpay…');
    try {
      final orderId = response.orderId;
      final paymentId = response.paymentId;
      final signature = response.signature;
      if (orderId == null || paymentId == null || signature == null) {
        throw Exception('Razorpay did not return complete verification details.');
      }
      await _firebaseWedding.verifyRazorpayPayment(
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      );
      await _refresh();
      if (!mounted) return;
      setState(() => _status = 'Payment verified. Creating your private share link…');
      await _makeShareLink();
    } catch (e) {
      if (mounted) setState(() => _status = 'Payment verification: $e. Tap Refresh before retrying.');
    }
  }


  void _onPaymentError(PaymentFailureResponse response) {
    if (mounted) setState(() => _status = 'Payment was not completed. Please try again.');
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (mounted) setState(() => _status = 'External wallet selected: ${response.walletName ?? 'wallet'}');
  }

  Future<void> _chooseAndUpload() async {
    if (supabase.auth.currentUser?.emailConfirmedAt == null) {
      setState(() { _selectedTab = 2; _status = 'Verify your recovery email before uploading so your account can be recovered later.'; });
      return;
    }
    if (_order?['upload_locked'] == true || _video != null) {
      setState(() => _status = 'This account has already used its one video slot. Create a new account for another wedding.');
      return;
    }
    setState(() { _busy = true; _status = null; _uploadProgress = 0; });
    try {
      final prepared = await _firebaseWedding.prepareWeddingUpload();
      if (prepared['ok'] != true) throw Exception('Could not prepare your Firebase wedding upload.');
      await _loadOrder();
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video, allowMultiple: false, withReadStream: true, withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (!mounted) return;
      setState(() { _uploading = true; _busy = false; _status = 'Uploading ${file.name}…'; });
      final uid = FirebaseBackend.currentUser?.uid;
      if (uid == null) throw Exception('Firebase customer account is not signed in.');
      await _uploadService.upload(
        orderId: uid, file: file,
        onProgress: (value) { if (mounted) setState(() => _uploadProgress = value); },
      );
      if (!mounted) return;
      setState(() {
        _shareUrl = null; _sharePin = null;
        _status = 'Video uploaded and verified in Google Drive. Pay ₹290 when you are ready to share it.';
        _uploading = false;
      });
      await _refresh();
    } catch (e) {
      if (mounted) {
        setState(() { _status = 'Upload: $e'; _uploading = false; });
        await _loadOrder();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateAutoDeleteConsent(bool consent) async {
    if (_video == null || _video!['id'] == null) return;
    final previous = _autoDeleteConsent;
    setState(() { _autoDeleteConsent = consent; _status = null; });
    try {
      final result = await _firebaseWedding.setAutoDeleteConsent(
        videoId: _video!['id'].toString(), consent: consent,
      );
      if (result['ok'] != true) throw Exception('Could not save your consent choice.');
      if (mounted) setState(() => _status = consent
        ? 'Automatic Google Drive deletion is enabled after the receiver’s full verified download.'
        : 'Automatic Google Drive deletion consent has been withdrawn. Your Drive copy will be kept.');
      await _refresh();
    } catch (e) {
      if (mounted) setState(() { _autoDeleteConsent = previous; _status = 'Consent update: $e'; });
    }
  }

  Future<void> _makeShareLink() async {
    if (_order == null || _video?['upload_status'] != 'uploaded') return;
    if (!_autoDeleteConsent) {
      if (mounted) setState(() => _status = 'Please confirm automatic deletion of the Google Drive copy after the receiver completes the full download.');
      return;
    }
    if (_order?['payment_status'] != 'paid') {
      await _startPayment();
      return;
    }
    setState(() { _busy = true; _status = null; });
    try {
      final data = await _firebaseWedding.createWeddingShare();
      final url = data['shareUrl']?.toString();
      if (data['ok'] != true || url == null) {
        throw Exception(data['error']?.toString() ?? 'Could not create the private link.');
      }
      if (mounted) setState(() {
        _shareUrl = url; _sharePin = data['downloadPin']?.toString();
        _status = 'Private link and 6-digit download password are ready. Send them separately.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Share link: $e');
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
    final accountProtected = _accountProtected;
    final locked = _order?['upload_locked'] == true;
    final videoReady = _video?['upload_status'] == 'uploaded';
    final videoDeleted = _video?['upload_status'] == 'deleted';
    final videoSlotUsed = _video != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wedding Video Share', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: _busy || _uploading ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
          IconButton(onPressed: _busy || _uploading ? null : () => setState(() => _selectedTab = 2), icon: const Icon(Icons.person_outline_rounded), tooltip: 'Account'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFF4EAE6),
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library_rounded), label: 'Videos'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Account'),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_selectedTab == 0) ...[
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: const Color(0xFFF4EAE6), borderRadius: BorderRadius.circular(22)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.favorite, color: burgundy, size: 34),
                  const SizedBox(height: 12),
                  const Text('Celebrate. Share. Cherish.',
                    style: TextStyle(fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: burgundy)),
                  const SizedBox(height: 8),
                  const Text('One wedding. One clear plan.',
                    style: TextStyle(fontSize: 23, height: 1.2, fontWeight: FontWeight.w800, color: burgundy)),
                  const SizedBox(height: 8),
                  Text(user?.email ?? user?.phone ?? 'Your account'),
                  const SizedBox(height: 8),
                  const Text('Your own Google Drive. Your memories stay in your control.',
                    style: TextStyle(color: Color(0xFF66575B), fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 18),
              Card(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFEADFD9))), child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your Wedding', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('₹290  •  One-Wedding Plan'),
                  const Text('Upload one wedding video up to 40 GB.'),
                  const Text('Maximum video size: 40 GB (decimal).'),
                  const SizedBox(height: 12),
                  if (paid)
                    const Row(children: [Icon(Icons.verified, color: Colors.green), SizedBox(width: 8), Text('Payment verified by server')])
                  else if (!accountProtected)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Verify your recovery email before uploading.'),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => setState(() => _selectedTab = 2),
                          child: const Text('Verify recovery email'),
                        ),
                      ],
                    )
                  else
                    const Text('Upload your wedding video first. Pay ₹290 only when you are ready to share it.'),
                  if (_order != null) ...[
                    const SizedBox(height: 8),
                    Text('Order status: ${_order!['payment_status'] ?? 'pending'}'),
                    if (locked) const Text('This account has completed its video cycle.'),
                  ],
                ]),
              )),
              ],
              if (_selectedTab == 1) ...[
              Card(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFEADFD9))), child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your Drive. Your storage.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(_driveEmail == null
                      ? 'Connect your Google Drive to store your wedding video securely using your own Drive storage.'
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
              Card(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFEADFD9))), child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Upload without the guesswork.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('Choose one video up to 40 GB. It uploads to your own Google Drive; your phone original is never deleted. If the connection stops, choose the same file again to resume.'),
                  const SizedBox(height: 12),
                  if (videoReady)
                    Text('Uploaded: ${_video!['original_filename']} (${_bytes(_video!['file_size_bytes'])})')
                  else if (videoDeleted)
                    const Text('Your Google Drive copy was deleted by you. The phone original remains untouched; this one-video plan cannot be reused.')
                  else if (videoSlotUsed)
                    const Text('This account has already used its one video slot. Create a new account for another wedding video.')
                  else
                    FilledButton.icon(
                      onPressed: _busy || _uploading || locked || _driveEmail == null ? null : _chooseAndUpload,
                      style: FilledButton.styleFrom(backgroundColor: burgundy),
                      icon: const Icon(Icons.video_file),
                      label: const Text('Choose your wedding video'),
                    ),
                  if (_uploading) ...[
                    const SizedBox(height: 14),
                    const Text('Uploading to your Google Drive…', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _uploadProgress),
                    const SizedBox(height: 6),
                    Text('${(_uploadProgress * 100).toStringAsFixed(1)}% uploaded · resumable 8 MB chunks'),
                  ],
                  if (!paid) const Text('Payment is needed only when you share your uploaded video.', style: TextStyle(color: Colors.black54)),
                  if (_driveEmail == null) const Text('Connect Google Drive before uploading.', style: TextStyle(color: Colors.black54)),
                  if (locked) const Text('This account cannot upload another video.', style: TextStyle(color: Colors.black54)),
                ]),
              )),
              if (videoReady) ...[
                const SizedBox(height: 12),
                Card(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFEADFD9))), child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('A private link, ready to send.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text("Pay ₹290 to unlock private sharing. After the receiver's full video transfer is verified by our server, the Google Drive copy will be automatically deleted if you confirm below. Your phone original is never deleted."),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _autoDeleteConsent,
                      onChanged: _busy || _uploading ? null : (value) => unawaited(_updateAutoDeleteConsent(value == true)),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('I agree: automatically delete my Google Drive video after the receiver’s full download is verified.'),
                      subtitle: const Text('Only the Google Drive copy is deleted. The original on your phone is not touched. If the download is interrupted or cannot be verified, the Drive copy is kept.'),
                    ),
                    if (!paid)
                      FilledButton.icon(
                        onPressed: _busy || _uploading || !_autoDeleteConsent ? null : _startPayment,
                        icon: const Icon(Icons.lock_open_rounded),
                        label: const Text('Share Video – Pay ₹290'),
                        style: FilledButton.styleFrom(backgroundColor: burgundy),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _busy || _uploading || !_autoDeleteConsent ? null : _makeShareLink,
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
                    const Text(
                      'Your Google Drive copy is managed securely by the verified download process.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
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
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFEADFD9))),
                  child: ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined, color: burgundy),
                    title: const Text('Drive copy deleted'),
                    subtitle: const Text('Your phone original remains untouched. This account’s one-video plan stays used.'),
                  ),
                ),
              ],
              ],
              if (_selectedTab == 2) ...[
              const SizedBox(height: 12),
              AccountAccessCard(onLinked: _refresh),
              if (_order?['upload_locked'] == true) ...[
                const SizedBox(height: 12),
                Card(
                  color: const Color(0xFFF4EAE6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFFE8D8D0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF26734D), size: 34),
                        const SizedBox(height: 10),
                        const Text('Download complete!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: burgundy)),
                        const SizedBox(height: 6),
                        const Text('Thank you for sharing your special day. The server verified the full video transfer. Your Google Drive copy is automatically deleted when you gave consent; your phone original remains untouched.'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _selectedTab = 1),
                          icon: const Icon(Icons.video_library_outlined),
                          label: const Text('View video and storage'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
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
                        const Text('Ready for another celebration?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Text('Create a separate account for the next wedding. Your completed wedding stays saved in this account.'),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _startNewWedding,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Start another wedding'),
                            style: FilledButton.styleFrom(backgroundColor: burgundy),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFEADFD9))),
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
            ],
          ),
        ),
      ),
    );
  }
}
