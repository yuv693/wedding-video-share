import 'package:flutter/material.dart';

import '../services/backend.dart';
import 'wedding_video_editor_screen.dart';
import 'wedding_qr_album_screen.dart';
import 'wedding_invitation_screen.dart';
import 'photographer_studio_portal_screen.dart';
import 'wedding_clip_timeline_screen.dart';
import 'wedding_audio_timeline_screen.dart';
import 'wedding_multi_track_export_screen.dart';
import 'wedding_studio_admin_screen.dart';

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
    final details = _moduleDetails[title]!;
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF6F2438)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(label: Text('Development mode')),
            Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => title == 'QR Wedding Album'
              ? const WeddingQrAlbumScreen()
              : title == 'Digital Invitations'
                  ? const WeddingInvitationScreen()
                  : title == 'Photographer Studio Portal'
                      ? const PhotographerStudioPortalScreen()
                      : title == 'Admin & Billing'
                          ? const WeddingStudioAdminScreen()
                          : WeddingStudioModuleScreen(
                  title: title,
                  description: subtitle,
                  features: details,
                ),
        )),
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
  Map<String, dynamic> _timeline = {};
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
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) {
        _editorId = row['id'].toString();
        final timeline = row['timeline_json'] is Map
            ? Map<String, dynamic>.from(row['timeline_json'] as Map)
            : <String, dynamic>{};
        _timeline = timeline;
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

  Future<void> _openClipTimeline() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WeddingClipTimelineScreen(
        projectId: widget.projectId,
        projectTitle: widget.projectTitle,
      ),
    ));
    await _loadDraft();
  }

  Future<void> _openAudioTimeline() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WeddingAudioTimelineScreen(
        projectId: widget.projectId,
        projectTitle: widget.projectTitle,
      ),
    ));
    await _loadDraft();
  }

  Future<void> _openRenderer() async {
    final clips = _timeline['clips'] is List
        ? List<Map<String, dynamic>>.from((_timeline['clips'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
        : <Map<String, dynamic>>[];
    final tracks = _timeline['audioTracks'] is List
        ? List<Map<String, dynamic>>.from((_timeline['audioTracks'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
        : <Map<String, dynamic>>[];
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WeddingMultiTrackExportScreen(
        projectTitle: widget.projectTitle,
        initialClips: clips,
        initialAudioTracks: tracks,
      ),
    ));
  }

  Future<void> _saveDraft() async {
    setState(() { _saving = true; _error = null; });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please sign in again.');
      // Preserve the actual clip and audio timeline saved by the dedicated
      // timeline screens. This screen only owns the notes/status fields.
      final timeline = Map<String, dynamic>.from(_timeline);
      timeline['version'] = (timeline['version'] as num?)?.toInt() ?? 1;
      timeline.putIfAbsent('clips', () => <dynamic>[]);
      timeline.putIfAbsent('audioTracks', () => <dynamic>[]);
      timeline.putIfAbsent('overlays', () => <dynamic>[]);
      timeline.putIfAbsent('transitions', () => <dynamic>[]);
      timeline['notes'] = _notes.text.trim();
      timeline['status'] = 'editable_draft';
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
              const Text('Open the on-device editor beta to trim a video, preview it, change speed, replace its soundtrack and export a new copy.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => WeddingVideoEditorScreen(
                    projectId: widget.projectId,
                    projectTitle: widget.projectTitle,
                  ),
                )),
                icon: const Icon(Icons.movie_creation_outlined),
                label: const Text('Open Wedding Video Editor'),
                style: FilledButton.styleFrom(backgroundColor: burgundy),
              ),
              const SizedBox(height: 12),
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Saved timeline • $_clipCount clips', style: const TextStyle(fontWeight: FontWeight.w700)),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _openClipTimeline,
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Manage video clips and order'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _openAudioTimeline,
                    icon: const Icon(Icons.library_music_outlined),
                    label: const Text('Manage multiple music tracks'),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _openRenderer,
                    icon: const Icon(Icons.movie_filter_outlined),
                    label: const Text('Render saved timeline to MP4'),
                    style: FilledButton.styleFrom(backgroundColor: burgundy),
                  ),
                  const SizedBox(height: 8),
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


const Map<String, List<String>> _moduleDetails = {
  'QR Wedding Album': [
    'Create a private wedding album and its unique QR code',
    'Let invited guests upload and view photos/videos',
    'Choose guest upload, viewing and download permissions',
    'Protect album access with a private link or PIN',
  ],
  'Photographer Studio Portal': [
    'Create a photographer or studio profile',
    'Manage separate customer wedding projects',
    'Invite customers and hand over uploaded media',
    'Track album and editing project status',
  ],
  'AI Wedding Highlights': [
    'Analyse selected wedding clips for highlight moments',
    'Prepare a suggested highlights sequence',
    'Preview and approve suggestions before export',
    'Keep original customer media unchanged',
  ],
  'Digital Invitations': [
    'Choose and personalise a wedding invitation template',
    'Add couple names, dates, venue and event details',
    'Create a shareable invitation with RSVP/contact details',
    'Add a map/location link for guests',
  ],
  'Wedding Reels': [
    'Prepare vertical 9:16 wedding reel projects',
    'Choose entry, ceremony, family or teaser presets',
    'Add captions, text and a cover before preview',
    'Export a reel for the customer to share',
  ],
  'Instagram Connection': [
    'Connect an eligible Instagram professional/creator account using official Meta sign-in',
    'Never request or store an Instagram password',
    'Review the reel and approve each publish action',
    'Direct publishing depends on Meta permissions and app approval',
  ],
  'Admin & Billing': [
    'View wedding projects and module status',
    'Review payment records and reconciliation',
    'Track customer support and audit events',
    'Manage plans and storage/quota visibility',
  ],
};

class WeddingStudioModuleScreen extends StatelessWidget {
  const WeddingStudioModuleScreen({
    super.key,
    required this.title,
    required this.description,
    required this.features,
  });

  final String title;
  final String description;
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: const Color(0xFFF4EAE6),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.construction_outlined, color: burgundy),
                      SizedBox(width: 8),
                      Text(
                        'Development mode',
                        style: TextStyle(
                          color: burgundy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(description),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Planned module features',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...features.map((feature) => Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline, color: burgundy),
              title: Text(feature),
            ),
          )),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'This module opens in the app, but its full workflows are not enabled yet. It will remain in Development Mode until implementation and testing are complete. No customer-facing release is active.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
