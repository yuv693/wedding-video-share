import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const endpointEmail = 'ym6250067@gmail.com';
const projectUrl = 'https://mnaswhizatnwfwmjmtvm.supabase.co';
const publicKey = 'sb_publishable_BwuKkASTfQuapaf1vnIAig_6sR9AGpW';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: projectUrl, publishableKey: publicKey);
  runApp(const OwnerConsole());
}

class OwnerConsole extends StatelessWidget {
  const OwnerConsole({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Owner Console',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6F2438))),
    home: const LoginPage(),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool sent = false, busy = false;
  bool signedIn = Supabase.instance.client.auth.currentSession != null;
  String? status;
  StreamSubscription<AuthState>? authSubscription;

  @override
  void initState() {
    super.initState();
    authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        signedIn = state.session != null;
        if (signedIn) status = null;
      });
    }, onError: (Object error) {
      if (mounted) setState(() => status = 'Sign-in callback failed: $error');
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }
  Future<void> send() async {
    setState(() { busy = true; status = null; });
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: endpointEmail, shouldCreateUser: false, emailRedirectTo: 'weddingvideoshareadmin://login-callback');
      if (!mounted) return;
      setState(() { sent = true; status = 'Check the owner email and open the sign-in link on this phone.'; });
    } catch (e) { if (mounted) setState(() => status = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    if (signedIn || Supabase.instance.client.auth.currentSession != null) return const ConsolePage();
    return Scaffold(appBar: AppBar(title: const Text('Owner Console')), body: Padding(
      padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.lock_outline, size: 52),
        const Text('Private owner access'),
        const SizedBox(height: 16),
        Text(endpointEmail),
        FilledButton(onPressed: busy ? null : send, child: Text(busy ? 'Please wait' : 'Send sign-in link')),
        if (status != null) Text(status!),
      ]),
    ));
  }
}

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});
  @override
  State<ConsolePage> createState() => _ConsolePageState();
}
class _ConsolePageState extends State<ConsolePage> with WidgetsBindingObserver {
  bool busy = false;
  List<dynamic> items = [];
  String status = '';
  Timer? _requestPollTimer;
  bool _loadingRequests = false;
  bool _hasInitialRequestSnapshot = false;
  final Set<String> _knownPaymentIds = <String>{};

  Future<void> load({bool quiet = false}) async {
    if (_loadingRequests) return;
    _loadingRequests = true;
    if (!quiet && mounted) setState(() => busy = true);
    try {
      final r = await Supabase.instance.client.functions.invoke('manual-payment-admin', body: {'action': 'list'});
      final d = r.data as Map;
      if (r.status != 200 || d['error'] != null) throw Exception(d['error'] ?? 'Unable to load');
      final latest = (d['payments'] as List? ?? []).toList();
      final latestIds = latest.map((item) => item['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
      final newIds = _hasInitialRequestSnapshot ? latestIds.difference(_knownPaymentIds) : <String>{};
      _knownPaymentIds
        ..clear()
        ..addAll(latestIds);
      _hasInitialRequestSnapshot = true;
      if (!mounted) return;
      setState(() { items = latest; status = ''; });
      if (newIds.isNotEmpty) {
        unawaited(SystemSound.play(SystemSoundType.alert));
        unawaited(HapticFeedback.vibrate());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${newIds.length} new payment request${newIds.length == 1 ? '' : 's'} received'), duration: const Duration(seconds: 6)),
          );
        }
      }
    } catch (e) {
      if (mounted && !quiet) setState(() => status = e.toString());
    } finally {
      _loadingRequests = false;
      if (mounted && !quiet) setState(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    _requestPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        load(quiet: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load(quiet: true);
  }

  @override
  void dispose() {
    _requestPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> decide(dynamic item, String action) async {
    if (action == 'approve') {
      final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('Confirm approval'),
        content: const Text('Only continue after checking the customer payment in your UPI app.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('YES'))],
      ));
      if (yes != true) return;
    }
    try {
      final r = await Supabase.instance.client.functions.invoke('manual-payment-admin', body: {'action': action, 'payment_id': item['id']});
      final d = r.data as Map;
      if (r.status != 200 || d['error'] != null) throw Exception(d['error'] ?? 'Request failed');
      if (action == 'approve' && d['shareUrl'] != null) {
        final shareUrl = d['shareUrl'].toString();
        final pin = d['downloadPin'].toString();
        await showDialog<void>(context: context, builder: (c) => AlertDialog(
          title: const Text('Video link ready'),
          content: SelectableText('Link:\n' + shareUrl + '\n\nPIN: ' + pin + '\n\nThis link and PIN are now in the customer app.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
        ));
      }
      await load();
    } catch (e) { setState(() => status = e.toString()); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Owner Console'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh)), IconButton(onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout))]),
    body: RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: [
      if (status.isNotEmpty) Text(status),
      if (busy) const Center(child: CircularProgressIndicator()),
      if (!busy && items.isEmpty) const Text('No new requests.'),
      for (final item in items) Card(child: ListTile(title: Text('₹' + (((item['amount_paise'] as num?)?.toInt() ?? 0) ~/ 100).toString()), subtitle: Text(item['customer_email']?.toString() ?? 'Customer'), trailing: Wrap(children: [IconButton(onPressed: busy ? null : () => decide(item, 'approve'), icon: const Icon(Icons.check_circle, color: Colors.green)), IconButton(onPressed: busy ? null : () => decide(item, 'reject'), icon: const Icon(Icons.cancel_outlined, color: Colors.red))]))),
    ])),
  );
}
