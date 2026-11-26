import 'package:flutter/material.dart';
import '../services/backend.dart';

class WeddingStudioAdminScreen extends StatefulWidget {
  const WeddingStudioAdminScreen({super.key});
  @override
  State<WeddingStudioAdminScreen> createState() => _WeddingStudioAdminScreenState();
}

class _WeddingStudioAdminScreenState extends State<WeddingStudioAdminScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic> dashboard = {};
  List<Map<String, dynamic>> projects = [];
  List<Map<String, dynamic>> payments = [];
  List<Map<String, dynamic>> events = [];

  Future<Map<String, dynamic>> _call(String action) async {
    final response = await supabase.functions.invoke(
      'wedding-studio-admin',
      body: {'action': action},
    );
    final data = response.data;
    if (response.status < 200 || response.status >= 300 || data is! Map || data['ok'] != true) {
      throw Exception(data is Map ? (data['error'] ?? 'Admin request failed') : 'Admin request failed');
    }
    return Map<String, dynamic>.from(data);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait([
        _call('dashboard'), _call('projects'), _call('payments'), _call('audit'),
      ]);
      if (!mounted) return;
      setState(() {
        dashboard = results[0];
        projects = List<Map<String, dynamic>>.from(results[1]['projects'] ?? []);
        payments = List<Map<String, dynamic>>.from(results[2]['payments'] ?? []);
        events = List<Map<String, dynamic>>.from(results[3]['events'] ?? []);
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Admin access or data unavailable: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _rupees(dynamic paise) => '₹${(double.tryParse('${paise ?? 0}') ?? 0) / 100}';
  Future<void> _reviewPayment(Map<String,dynamic> payment, String action) async {
    final approved = action == 'approve';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approved ? 'Approve ₹290 payment?' : 'Reject payment?'),
        content: Text(approved
          ? 'This verifies the customer payment and starts the existing share-ready workflow.'
          : 'This marks the manual UPI payment as failed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(approved ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => loading = true);
    try {
      final response = await supabase.functions.invoke('manual-payment-admin', body: {
        'action': action,
        'payment_id': payment['id'],
      });
      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map || data['ok'] != true) {
        throw Exception(data is Map ? (data['error'] ?? 'Payment review failed') : 'Payment review failed');
      }
      await load();
    } catch (e) {
      if (mounted) setState(() { loading = false; error = 'Payment review failed: $e'; });
    }
  }


  @override
  Widget build(BuildContext context) {
    final modules = dashboard['modules'] is Map
        ? Map<String, dynamic>.from(dashboard['modules'] as Map)
        : <String, dynamic>{};
    final billing = dashboard['billing'] is Map
        ? Map<String, dynamic>.from(dashboard['billing'] as Map)
        : <String, dynamic>{};
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wedding Studio Admin'),
          actions: [IconButton(onPressed: loading ? null : load, icon: const Icon(Icons.refresh))],
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Overview'), Tab(text: 'Projects'), Tab(text: 'Billing'), Tab(text: 'Audit'),
          ]),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: load, child: const Text('Retry')),
                    ]),
                  ))
                : TabBarView(children: [
                    ListView(padding: const EdgeInsets.all(16), children: [
                      const Chip(label: Text('Development Mode • Admin only')),
                      const Text('Module totals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ...modules.entries.map((e) => Card(child: ListTile(
                        title: Text(e.key.replaceAll('_', ' ').toUpperCase()),
                        trailing: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ))),
                      const SizedBox(height: 12),
                      const Text('₹290 share billing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Card(child: Column(children: [
                        ListTile(title: const Text('Total orders'), trailing: Text('${billing['orders'] ?? 0}')),
                        ListTile(title: const Text('Verified payments'), trailing: Text('${billing['verifiedPayments'] ?? 0}')),
                        ListTile(title: const Text('Pending payments'), trailing: Text('${billing['pendingPayments'] ?? 0}')),
                        ListTile(title: const Text('Verified revenue'), trailing: Text(_rupees(billing['revenuePaise']))),
                      ])),
                    ]),
                    ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: projects.length,
                      itemBuilder: (context, i) {
                        final p = projects[i];
                        return Card(child: ListTile(
                          title: Text(p['title']?.toString() ?? 'Wedding project'),
                          subtitle: Text('${p['customerEmail'] ?? 'Customer'} • ${p['status'] ?? 'active'}'),
                          trailing: Text((p['event_date'] ?? '').toString()),
                        ));
                      },
                    ),
                    ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: payments.length,
                      itemBuilder: (context, i) {
                        final p = payments[i];
                        final pendingManual = p['gateway'] == 'manual_upi' && p['status'] == 'pending';
                        return Card(child: ListTile(
                          title: Text(_rupees(p['amount_paise'])),
                          subtitle: Text('${p['customerEmail'] ?? 'Customer'} • ${p['gateway'] ?? ''}'),
                          trailing: pendingManual
                              ? Wrap(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(tooltip: 'Approve ₹290', onPressed: () => _reviewPayment(p, 'approve'), icon: const Icon(Icons.check_circle_outline, color: Colors.green)),
                                  IconButton(tooltip: 'Reject payment', onPressed: () => _reviewPayment(p, 'reject'), icon: const Icon(Icons.cancel_outlined, color: Colors.red)),
                                ])
                              : Text(p['status']?.toString() ?? ''),
                        ));
                      },
                    ),
                    ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: events.length,
                      itemBuilder: (context, i) {
                        final e = events[i];
                        return Card(child: ListTile(
                          title: Text(e['event_type']?.toString() ?? 'Event'),
                          subtitle: Text('${e['created_at'] ?? ''}'),
                        ));
                      },
                    ),
                  ]),
      ),
    );
  }
}
