import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/backend.dart';

class PhotographerStudioPortalScreen extends StatefulWidget {
  const PhotographerStudioPortalScreen({super.key});
  @override
  State<PhotographerStudioPortalScreen> createState() => _PhotographerStudioPortalScreenState();
}

class _PhotographerStudioPortalScreenState extends State<PhotographerStudioPortalScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final website = TextEditingController();
  bool loading = true, saving = false;
  String? error, studioId;
  List<Map<String, dynamic>> projects = [];
  List<Map<String, dynamic>> invitations = [];

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { name.dispose(); email.dispose(); phone.dispose(); website.dispose(); super.dispose(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please sign in again.');
      final profile = await supabase.from('photographer_studios')
          .select('id,studio_name,contact_email,contact_phone,website_url')
          .eq('owner_customer_id', user.id).maybeSingle();
      final rows = await supabase.from('wedding_projects')
          .select('id,owner_customer_id,title,studio_id,status,event_date,venue,client_name,client_email,client_phone,created_at')
          .order('created_at', ascending: false);
      final inviteRows = await supabase.from('wedding_project_invitations')
          .select('id,project_id,inviter_user_id,invitee_email,role,status,can_view,can_upload,can_edit,expires_at')
          .inFilter('status', ['pending','accepted']).gt('expires_at', DateTime.now().toIso8601String()).order('created_at', ascending: false);
      if (!mounted) return;
      if (profile != null) {
        studioId = profile['id'].toString();
        name.text = profile['studio_name']?.toString() ?? '';
        email.text = profile['contact_email']?.toString() ?? '';
        phone.text = profile['contact_phone']?.toString() ?? '';
        website.text = profile['website_url']?.toString() ?? '';
      } else { studioId = null; }
      setState(() {
        projects = List<Map<String, dynamic>>.from(rows);
        invitations = List<Map<String, dynamic>>.from(inviteRows);
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Could not load studio portal: $e');
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> saveProfile() async {
    if (name.text.trim().isEmpty) { setState(() => error = 'Studio name is required.'); return; }
    setState(() { saving = true; error = null; });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please sign in again.');
      final result = await supabase.from('photographer_studios').upsert({
        'owner_customer_id': user.id, 'studio_name': name.text.trim(),
        'contact_email': email.text.trim().isEmpty ? null : email.text.trim(),
        'contact_phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'website_url': website.text.trim().isEmpty ? null : website.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'owner_customer_id').select('id').single();
      studioId = result['id'].toString();
      await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Studio profile saved.')));
    } catch (e) {
      if (mounted) setState(() => error = 'Save failed: $e');
    } finally { if (mounted) setState(() => saving = false); }
  }

  Future<void> editProject([Map<String, dynamic>? project]) async {
    final title = TextEditingController(text: project?['title']?.toString() ?? '');
    final client = TextEditingController(text: project?['client_name']?.toString() ?? '');
    final clientEmail = TextEditingController(text: project?['client_email']?.toString() ?? '');
    final clientPhone = TextEditingController(text: project?['client_phone']?.toString() ?? '');
    final venue = TextEditingController(text: project?['venue']?.toString() ?? '');
    final eventDate = TextEditingController(text: project?['event_date']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(project == null ? 'Create wedding project' : 'Edit wedding project'),
        content: SizedBox(width: 460, child: SingleChildScrollView(
          child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Project / wedding name'), validator: (v) => v == null || v.trim().isEmpty ? 'Project name is required' : null),
            TextFormField(controller: client, decoration: const InputDecoration(labelText: 'Customer name')),
            TextFormField(controller: clientEmail, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Customer email')),
            TextFormField(controller: clientPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Customer phone')),
            TextFormField(controller: eventDate, decoration: const InputDecoration(labelText: 'Event date (YYYY-MM-DD)'), keyboardType: TextInputType.datetime),
            TextFormField(controller: venue, decoration: const InputDecoration(labelText: 'Venue / location')),
          ])),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save')),
        ],
      ),
    );
    if (result != true) {
      for (final c in [title, client, clientEmail, clientPhone, venue, eventDate]) { c.dispose(); }
      return;
    }
    setState(() { saving = true; error = null; });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please sign in again.');
      DateTime? parsedDate;
      if (eventDate.text.trim().isNotEmpty) {
        parsedDate = DateTime.tryParse(eventDate.text.trim());
        if (parsedDate == null) throw Exception('Enter event date as YYYY-MM-DD.');
      }
      final values = {
        'title': title.text.trim(),
        'client_name': client.text.trim().isEmpty ? null : client.text.trim(),
        'client_email': clientEmail.text.trim().isEmpty ? null : clientEmail.text.trim(),
        'client_phone': clientPhone.text.trim().isEmpty ? null : clientPhone.text.trim(),
        'event_date': parsedDate == null ? null : parsedDate.toIso8601String().substring(0, 10),
        'venue': venue.text.trim().isEmpty ? null : venue.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (project == null) {
        await supabase.from('wedding_projects').insert({...values, 'owner_customer_id': user.id});
      } else {
        await supabase.from('wedding_projects').update(values)
            .eq('id', project['id']).eq('owner_customer_id', user.id);
      }
      await load();
    } catch (e) {
      if (mounted) setState(() => error = 'Project save failed: $e');
    } finally {
      for (final c in [title, client, clientEmail, clientPhone, venue, eventDate]) { c.dispose(); }
      if (mounted) setState(() => saving = false);
    }
  }


  Future<void> invitePhotographer(Map<String, dynamic> project) async {
    final emailController = TextEditingController();
    String role = 'photographer';
    bool canUpload = true, canEdit = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Invite photographer / editor'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: emailController, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Photographer login email')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: role, decoration: const InputDecoration(labelText: 'Role'),
            items: const [
              DropdownMenuItem(value: 'photographer', child: Text('Photographer')),
              DropdownMenuItem(value: 'editor', child: Text('Video editor')),
              DropdownMenuItem(value: 'viewer', child: Text('Viewer only')),
            ],
            onChanged: (v) => setDialogState(() => role = v ?? 'photographer'),
          ),
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: canUpload,
            title: const Text('Can upload wedding media'),
            onChanged: role == 'viewer' ? null : (v) => setDialogState(() => canUpload = v ?? false)),
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: canEdit,
            title: const Text('Can edit timeline / reels'),
            onChanged: role == 'viewer' ? null : (v) => setDialogState(() => canEdit = v ?? false)),
          const Text('The invitee must verify this exact email, sign in and accept. Invitation expires after 14 days.', style: TextStyle(fontSize: 12)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create invitation')),
        ],
      )),
    );
    if (accepted != true) { emailController.dispose(); return; }
    final targetEmail = emailController.text.trim().toLowerCase();
    emailController.dispose();
    if (!targetEmail.contains('@') || targetEmail.endsWith('@')) {
      setState(() => error = 'Enter a valid photographer email.');
      return;
    }
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please sign in again.');
      await supabase.from('wedding_project_invitations').insert({
        'project_id': project['id'], 'inviter_user_id': user.id,
        'invitee_email': targetEmail, 'role': role, 'can_view': true,
        'can_upload': role == 'viewer' ? false : canUpload,
        'can_edit': role == 'viewer' ? false : canEdit,
      });
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation saved. Share the instructions with the photographer.')));
        await Share.share(
          'You are invited to collaborate on the wedding project "${project['title']}".\n\n'
          'Open Wedding Video Share, sign in using $targetEmail, then open Photographer Studio Portal > Invitations for you and tap Accept. '
          'Your invitation expires in 14 days. Access is limited to the permissions selected by the customer.',
          subject: 'Wedding Video Share project invitation',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Invitation failed: $e');
    }
  }

  Future<void> acceptInvitation(Map<String, dynamic> invitation) async {
    try {
      await supabase.rpc('accept_wedding_project_invitation', params: {'p_invitation_id': invitation['id']});
      await load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitation accepted. The shared wedding project is now available.')));
    } catch (e) {
      if (mounted) setState(() => error = 'Could not accept invitation. Verify the invited email and try again: $e');
    }
  }

  Future<void> revokeInvitation(Map<String, dynamic> invitation) async {
    try {
      await supabase.rpc('revoke_wedding_project_invitation', params: {'p_invitation_id': invitation['id']});
      await load();
    } catch (e) {
      if (mounted) setState(() => error = 'Could not revoke access: $e');
    }
  }

  Future<void> updateStatus(Map<String, dynamic> project, String status) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please sign in again.');
      await supabase.from('wedding_projects').update({
        'status': status, 'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', project['id']).eq('owner_customer_id', user.id);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = 'Could not update project status: $e');
    }
  }

  Future<void> assignProject(Map<String, dynamic> project, bool attach) async {
    if (studioId == null) { setState(() => error = 'Save your studio profile first.'); return; }
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please sign in again.');
      await supabase.from('wedding_projects').update({
        'studio_id': attach ? studioId : null, 'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', project['id']).eq('owner_customer_id', user.id);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = 'Project assignment failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Photographer Studio Portal'),
      actions: [IconButton(onPressed: loading ? null : load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')]),
    body: loading ? const Center(child: CircularProgressIndicator()) : ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Chip(label: Text('Studio workspace')),
        const Text('Customer and photographer use the same wedding project. The customer controls invitations and can revoke access at any time.'),
        const SizedBox(height: 12),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Studio / photographer name', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Contact email', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact phone', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: website, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Website (optional)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: saving ? null : saveProfile, icon: const Icon(Icons.save_outlined), label: Text(saving ? 'Saving…' : 'Save studio profile')),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 18),
        if (invitations.any((i) => i['inviter_user_id'] != supabase.auth.currentUser?.id && i['status'] == 'pending')) ...[
          Text('Invitations for you', style: Theme.of(context).textTheme.titleLarge),
          ...invitations.where((i) => i['inviter_user_id'] != supabase.auth.currentUser?.id && i['status'] == 'pending').map((i) => Card(child: ListTile(
            leading: const Icon(Icons.mail_outline), title: Text('Wedding project invitation • ${i['role']}'),
            subtitle: Text('Invited email: ${i['invitee_email']}'),
            trailing: FilledButton(onPressed: saving ? null : () => acceptInvitation(i), child: const Text('Accept')),
          ))), const SizedBox(height: 12),
        ],
        Row(children: [
          Expanded(child: Text('Wedding projects (${projects.length})', style: Theme.of(context).textTheme.titleLarge)),
          FilledButton.tonalIcon(onPressed: saving ? null : () => editProject(), icon: const Icon(Icons.add), label: const Text('New project')),
        ]),
        if (projects.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No wedding projects yet. Create your first project here.'))),
        ...projects.map((p) {
          final isOwner = p['owner_customer_id'] == supabase.auth.currentUser?.id;
          final attached = p['studio_id'] != null && p['studio_id'].toString() == studioId;
          final status = p['status']?.toString() ?? 'active';
          return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.favorite_outline), const SizedBox(width: 8),
                Expanded(child: Text(p['title']?.toString() ?? 'Wedding project', style: Theme.of(context).textTheme.titleMedium)),
                if (isOwner) PopupMenuButton<String>(
                  tooltip: 'Change project status',
                  onSelected: (value) => updateStatus(p, value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'active', child: Text('Active')),
                    PopupMenuItem(value: 'completed', child: Text('Completed')),
                    PopupMenuItem(value: 'archived', child: Text('Archived')),
                  ],
                  child: Chip(label: Text(status)),
                ),
              ]),
              if ((p['client_name'] ?? '').toString().isNotEmpty) Text('Customer: ${p['client_name']}'),
              if ((p['client_email'] ?? '').toString().isNotEmpty) Text('Email: ${p['client_email']}'),
              if ((p['client_phone'] ?? '').toString().isNotEmpty) Text('Phone: ${p['client_phone']}'),
              if ((p['event_date'] ?? '').toString().isNotEmpty) Text('Date: ${p['event_date']}'),
              if ((p['venue'] ?? '').toString().isNotEmpty) Text('Venue: ${p['venue']}'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                if (isOwner) OutlinedButton.icon(onPressed: saving ? null : () => editProject(p), icon: const Icon(Icons.edit_outlined), label: const Text('Edit project')),
                if (isOwner) OutlinedButton.icon(onPressed: saving ? null : () => assignProject(p, !attached), icon: Icon(attached ? Icons.link_off : Icons.link), label: Text(attached ? 'Remove from studio' : 'Add to studio')),
                if (isOwner) OutlinedButton.icon(onPressed: saving ? null : () => invitePhotographer(p), icon: const Icon(Icons.person_add_alt_1), label: const Text('Invite photographer')),
                if (!isOwner) const Chip(label: Text('Shared with you')),
              ]),
              if (isOwner) ...invitations.where((i) => i['project_id'] == p['id']).map((i) => ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                leading: Icon(i['status'] == 'accepted' ? Icons.verified_user_outlined : Icons.hourglass_top),
                title: Text(i['invitee_email']?.toString() ?? 'Collaborator'),
                subtitle: Text('${i['role']} • ${i['status']} • upload: ${i['can_upload']} • edit: ${i['can_edit']}'),
                trailing: IconButton(tooltip: 'Revoke access', icon: const Icon(Icons.person_remove_alt_1),
                  onPressed: saving ? null : () => revokeInvitation(i)),
              )),
            ],
          )));
        }),
      ],
    ),
  );
}
