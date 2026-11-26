import 'package:flutter/material.dart';

import '../services/backend.dart';

class WeddingStudioHub extends StatefulWidget {
  const WeddingStudioHub({super.key});

  @override
  State<WeddingStudioHub> createState() => _WeddingStudioHubState();
}

class _WeddingStudioHubState extends State<WeddingStudioHub> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _projects = [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await supabase
          .from('wedding_projects')
          .select('id,title,status,created_at')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _projects = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Studio database is not ready yet. Apply the latest Supabase migration first. Details: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createProject() async {
    final controller = TextEditingController(text: 'My Wedding');
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create wedding project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Project name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please sign in again.');
      await supabase.from('wedding_projects').insert({
        'owner_customer_id': user.id,
        'title': title,
      });
      await _loadProjects();
    } catch (e) {
      if (mounted) _showError('Could not create project: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: const Color(0xFFF4EAE6),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.movie_creation_outlined, color: burgundy, size: 32),
              const SizedBox(height: 8),
              const Text('Wedding Studio', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: burgundy)),
              const SizedBox(height: 6),
              const Text('Create a project and keep your editable wedding timeline saved. Your original media remains in your own Google Drive.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _createProject,
                icon: const Icon(Icons.add),
                label: const Text('Create wedding project'),
                style: FilledButton.styleFrom(backgroundColor: burgundy),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Your projects', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        if (_loading) const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ) else if (_error != null)
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_error!)))
        else if (_projects.isEmpty)
          const Card(child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('No studio projects yet. Create your first wedding project above.'),
          ))
        else
          ..._projects.map((project) => Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.favorite_outline)),
              title: Text(project['title']?.toString() ?? 'Wedding project'),
              subtitle: Text('Status: ${project['status'] ?? 'active'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WeddingTimelineDraftScreen(
                  projectId: project['id'].toString(),
                  projectTitle: project['title'].toString(),
                ),
              )),
            ),
          )),
        const SizedBox(height: 16),
        const Text('More wedding tools', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _comingSoon(Icons.qr_code_2, 'QR Wedding Album', 'Private guest album and upload permissions'),
        _comingSoon(Icons.camera_alt_outlined, 'Photographer Studio Portal', 'Manage client wedding projects'),
        _comingSoon(Icons.auto_awesome, 'AI Wedding Highlights', 'Suggested highlights with customer approval'),
        _comingSoon(Icons.mail_outline, 'Digital Invitations', 'Editable invitations and RSVP'),
        _comingSoon(Icons.video_library_outlined, 'Wedding Reels', 'Vertical 9:16 reels and export'),
        _comingSoon(Icons.photo_camera_front_outlined, 'Instagram Connection', 'Official account connection, subject to Meta approval'),
        _comingSoon(Icons.admin_panel_settings_outlined, 'Admin & Billing', 'Separate product administration and payment records'),
      ],
    );
  }

  Widget _comingSoon(IconData icon, String title, String subtitle) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF6F2438)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Chip(label: Text('In development')),
      ),
    );
  }
}

class WeddingTimelineDraftScreen extends StatefulWidget {
  const WeddingTimelineDraftScreen({
    super.key,
    required this.projectId,
    required this.projectTitle,
  });

  final String projectId;
  final String projectTitle;

  @override
  State<WeddingTimelineDraftScreen> createState() => _WeddingTimelineDraftScreenState();
}

class _WeddingTimelineDraftScreenState extends State<WeddingTimelineDraftScreen> {
  final _notes = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _editorId;
  int _clipCount = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    try {
      final row = await supabase
          .from('wedding_editor_projects')
          .select('id,timeline_json')
          .eq('project_id', widget.projectId)
          .maybeSingle();
      if (row != null) {
        _editorId = row['id'].toString();
        final timeline = row['timeline_json'] is Map
            ? Map<String, dynamic>.from(row['timeline_json'] as Map)
            : <String, dynamic>{};
        final clips = timeline['clips'];
        _clipCount = clips is List ? clips.length : 0;
        _notes.text = timeline['notes']?.toString() ?? '';
      }
    } catch (e) {
      _error = 'Could not load the saved timeline: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveDraft() async {
    setState(() { _saving = true; _error = null; });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please sign in again.');
      final timeline = <String, dynamic>{
        'version': 1,
        'clips': List.generate(_clipCount, (i) => {'id': 'clip-${i + 1}', 'source': null, 'trimStartMs': 0, 'trimEndMs': 0}),
        'audioTracks': [],
        'overlays': [],
        'transitions': [],
        'notes': _notes.text.trim(),
        'status': 'editable_draft',
      };
      final payload = {
        'project_id': widget.projectId,
        'owner_customer_id': user.id,
        'name': 'Wedding edit',
        'timeline_json': timeline,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (_editorId == null) {
        final inserted = await supabase.from('wedding_editor_projects').insert(payload).select('id').single();
        _editorId = inserted['id'].toString();
      } else {
        await supabase.from('wedding_editor_projects').update(payload).eq('id', _editorId!);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Editable timeline draft saved.')));
    } catch (e) {
      if (mounted) setState(() => _error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    return Scaffold(
      appBar: AppBar(title: Text(widget.projectTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              const Text('Editable timeline draft', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('This saves your editing plan only. Real clip trimming, music mixing, transitions and video export are not enabled yet.'),
              const SizedBox(height: 16),
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Timeline clips', style: TextStyle(fontWeight: FontWeight.w700)),
                  Row(children: [
                    IconButton(onPressed: _clipCount > 0 ? () => setState(() => _clipCount--) : null, icon: const Icon(Icons.remove_circle_outline)),
                    Text('$_clipCount', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    IconButton(onPressed: () => setState(() => _clipCount++), icon: const Icon(Icons.add_circle_outline)),
                    const Text('planned clips'),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Edit notes / song change points',
                      hintText: 'Example: change to the second song at 00:45',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveDraft,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save editable draft'),
                      style: FilledButton.styleFrom(backgroundColor: burgundy),
                    ),
                  ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                ]),
              )),
              const SizedBox(height: 12),
              const Card(child: ListTile(
                leading: Icon(Icons.cloud_outlined),
                title: Text('Original media stays in your Google Drive'),
                subtitle: Text('This draft stores only timeline metadata and notes. It does not copy or delete your source videos.'),
              )),
            ]),
    );
  }
}
