import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSectionPage extends StatefulWidget {
  const AdminSectionPage({super.key, required this.section});
  final String section;

  @override
  State<AdminSectionPage> createState() => _AdminSectionPageState();
}

class _AdminSectionPageState extends State<AdminSectionPage> {
  bool loading = false;
  String error = '';
  String search = '';
  Map<String, dynamic> stats = {};
  List<dynamic> rows = [];
  final searchController = TextEditingController();

  String get action => switch (widget.section) {
    'history' => 'history',
    'customers' => 'customers',
    'videos' => 'videos',
    _ => 'dashboard',
  };

  @override
  void initState() {
    super.initState();
    if (widget.section != 'profile') load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> load({String? query}) async {
    if (widget.section == 'profile' || loading) return;
    setState(() { loading = true; error = ''; });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'manual-payment-admin',
        body: {'action': action, if (query != null) 'search': query},
      );
      final data = response.data as Map;
      if (response.status != 200 || data['error'] != null) {
        throw Exception(data['error'] ?? 'Unable to load data');
      }
      if (!mounted) return;
      setState(() {
        if (widget.section == 'dashboard') {
          stats = Map<String, dynamic>.from(data['stats'] as Map? ?? {});
        } else {
          final key = widget.section == 'history' ? 'payments' : widget.section;
          rows = List<dynamic>.from(data[key] as List? ?? []);
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String money(dynamic paise) {
    final value = ((paise as num?)?.toDouble() ?? 0) / 100;
    return '₹${value.toStringAsFixed(2)}';
  }

  String date(dynamic value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse(value.toString())?.toLocal();
    if (parsed == null) return value.toString();
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  Widget metric(String label, String value, IconData icon) => Card(
    child: ListTile(
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      subtitle: Text(label),
    ),
  );

  Widget searchBar(String hint) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Row(children: [
      Expanded(child: TextField(
        controller: searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (value) => load(query: value.trim()),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      )),
      IconButton(
        tooltip: 'Search',
        onPressed: () => load(query: searchController.text.trim()),
        icon: const Icon(Icons.search),
      ),
      IconButton(
        tooltip: 'Refresh',
        onPressed: () => load(query: searchController.text.trim()),
        icon: const Icon(Icons.refresh),
      ),
    ]),
  );

  Widget buildDashboard() => RefreshIndicator(
    onRefresh: load,
    child: ListView(padding: const EdgeInsets.all(12), children: [
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Business overview', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      ),
      metric('Total verified revenue', money(stats['totalRevenuePaise']), Icons.currency_rupee),
      metric('Approved payments', '${stats['verifiedPayments'] ?? 0}', Icons.verified),
      metric('Pending payments', '${stats['pendingPayments'] ?? 0}', Icons.hourglass_top),
      metric('Pending amount', money(stats['pendingAmountPaise']), Icons.pending_actions),
      metric('Rejected payments', '${stats['rejectedPayments'] ?? 0}', Icons.cancel_outlined),
      metric('Total wedding orders', '${stats['totalOrders'] ?? 0}', Icons.receipt_long),
      metric('Uploaded videos', '${stats['totalVideos'] ?? 0}', Icons.video_library),
      metric('Active share links', '${stats['activeShares'] ?? 0}', Icons.link),
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Revenue is calculated from payment transactions marked verified.'),
      ),
    ]),
  );

  Widget buildHistory() => Column(children: [
    searchBar('Search email, payment ID or status'),
    Expanded(child: loading && rows.isEmpty
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(onRefresh: () => load(query: searchController.text.trim()), child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (rows.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No payment history found.'))),
            for (final raw in rows)
              Builder(builder: (context) {
                final item = Map<String, dynamic>.from(raw as Map);
                final status = (item['status'] ?? 'unknown').toString();
                final color = status == 'verified' ? Colors.green : status == 'pending' ? Colors.orange : Colors.red;
                return Card(child: ListTile(
                  title: Text(money(item['amount_paise']), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${item['customer_email'] ?? 'Guest account'}\n${item['gateway'] ?? 'Payment'} • ${date(item['created_at'])}\nID: ${item['id']}'),
                  isThreeLine: true,
                  trailing: Chip(label: Text(status), side: BorderSide(color: color), visualDensity: VisualDensity.compact),
                ));
              }),
          ],
        ))),
  ]);

  Widget buildCustomers() => Column(children: [
    searchBar('Search customer email or ID'),
    Expanded(child: loading && rows.isEmpty
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(onRefresh: () => load(query: searchController.text.trim()), child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (rows.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No customers found.'))),
            for (final raw in rows)
              Builder(builder: (context) {
                final item = Map<String, dynamic>.from(raw as Map);
                return Card(child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(item['email']?.toString() ?? 'Guest account'),
                  subtitle: Text('Orders: ${item['orders'] ?? 0} • Paid: ${item['paid_orders'] ?? 0}\nLast status: ${item['latest_status'] ?? '—'}\nCustomer ID: ${item['customer_id'] ?? ''}'),
                  isThreeLine: true,
                  trailing: Text(money(item['total_paid_paise']), style: const TextStyle(fontWeight: FontWeight.bold)),
                ));
              }),
          ],
        ))),
  ]);

  Widget buildVideos() => Column(children: [
    searchBar('Search customer, video name or order ID'),
    Expanded(child: loading && rows.isEmpty
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(onRefresh: () => load(query: searchController.text.trim()), child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (rows.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No videos found.'))),
            for (final raw in rows)
              Builder(builder: (context) {
                final item = Map<String, dynamic>.from(raw as Map);
                final bytes = (item['file_size_bytes'] as num?)?.toDouble() ?? 0;
                final size = bytes >= 1024 * 1024 * 1024
                    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
                    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
                final canShare = item['deleted_at'] == null && item['upload_status'] == 'uploaded' && item['payment_status'] == 'paid';
                return Card(child: Column(children: [
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.video_file)),
                    title: Text(item['original_filename']?.toString() ?? 'Wedding video'),
                    subtitle: Text('${item['customer_email'] ?? 'Guest account'}\nUpload: ${item['upload_status'] ?? '—'} • ${size}\nPayment: ${item['payment_status'] ?? '—'} • ${date(item['uploaded_at'] ?? item['created_at'])}\nOrder: ${item['order_id'] ?? ''}'),
                    isThreeLine: true,
                    trailing: item['deleted_at'] == null ? const Icon(Icons.check_circle_outline, color: Colors.green) : const Icon(Icons.delete_outline, color: Colors.grey),
                  ),
                  if (canShare) Align(alignment: Alignment.centerRight, child: Padding(
                    padding: const EdgeInsets.only(right: 12, bottom: 10),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link),
                      label: const Text('Generate new guest link'),
                      onPressed: () async {
                        final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                          title: const Text('Generate a new link?'),
                          content: const Text('This creates a new guest link and PIN and replaces the current active link for this wedding order.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue'))],
                        ));
                        if (yes != true || !context.mounted) return;
                        try {
                          final response = await Supabase.instance.client.functions.invoke('manual-payment-admin', body: {'action': 'create_link', 'order_id': item['order_id'], 'customer_id': item['customer_id']});
                          final result = response.data as Map;
                          if (response.status != 200 || result['error'] != null) throw Exception(result['error'] ?? 'Unable to create link');
                          if (!context.mounted) return;
                          await showDialog<void>(context: context, builder: (c) => AlertDialog(
                            title: const Text('New guest link ready'),
                            content: SelectableText('Link:\n${result['shareUrl']}\n\n6-digit PIN: ${result['downloadPin']}'),
                            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
                          ));
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      },
                    ),
                  )),
                ]));
              }),
          ],
        ))),
  ]);

  Widget buildProfile() {
    final user = Supabase.instance.client.auth.currentUser;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const SizedBox(height: 20),
      const CircleAvatar(radius: 38, child: Icon(Icons.admin_panel_settings, size: 40)),
      const SizedBox(height: 12),
      Center(child: Text(user?.email ?? 'Owner account', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      Center(child: Text('Private Admin Account', style: TextStyle(color: Theme.of(context).colorScheme.secondary))),
      const SizedBox(height: 24),
      Card(child: ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('Admin user ID'), subtitle: SelectableText(user?.id ?? '—'))),
      Card(child: ListTile(leading: const Icon(Icons.verified_user_outlined), title: const Text('Access'), subtitle: const Text('Owner-only account'))),
      Card(child: ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: const Text('Notification permission'),
        subtitle: const Text('Allow alerts for new payment requests'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notification permission: ${settings.authorizationStatus.name}')));
        },
      )),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => Supabase.instance.client.auth.signOut(),
        icon: const Icon(Icons.logout),
        label: const Text('Logout'),
        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Text('This screen does not change customer videos or payment records.', textAlign: TextAlign.center),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (error.isNotEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: load, child: const Text('Try again')),
        ],
      )));
    }
    return switch (widget.section) {
      'history' => buildHistory(),
      'customers' => buildCustomers(),
      'videos' => buildVideos(),
      'profile' => buildProfile(),
      _ => buildDashboard(),
    };
  }
}
