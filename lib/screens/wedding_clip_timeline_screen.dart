import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';

import '../services/backend.dart';

class WeddingClipTimelineScreen extends StatefulWidget {
  const WeddingClipTimelineScreen({
    super.key,
    required this.projectId,
    required this.projectTitle,
  });

  final String projectId;
  final String projectTitle;

  @override
  State<WeddingClipTimelineScreen> createState() => _WeddingClipTimelineScreenState();
}

class _WeddingClipTimelineScreenState extends State<WeddingClipTimelineScreen> {
  final List<Map<String, dynamic>> _clips = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await supabase
          .from('wedding_editor_projects')
          .select('timeline_json')
          .eq('project_id', widget.projectId)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final timeline = row?['timeline_json'];
      final saved = timeline is Map ? timeline['clips'] : null;
      if (saved is List) {
        _clips
          ..clear()
          ..addAll(saved.whereType<Map>().map((item) => Map<String, dynamic>.from(item)));
      }
    } catch (e) {
      _error = 'Could not load clip timeline: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addClips() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final directory = await getApplicationDocumentsDirectory();
    final cache = Directory('${directory.path}/wedding_media/${widget.projectId}/clips');
    await cache.create(recursive: true);
    final additions = <Map<String, dynamic>>[];
    for (final file in result.files) {
      final source = file.path;
      if (source == null) continue;
      final local = await File(source).copy(
        '${cache.path}/${DateTime.now().microsecondsSinceEpoch}_${file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}',
      );
      additions.add({
        'id': 'clip-${DateTime.now().microsecondsSinceEpoch}-${file.name.hashCode}',
        'name': file.name,
        'path': local.path,
        'sizeBytes': file.size,
        'trimStartMs': 0,
        'trimEndMs': null,
      });
    }
    if (!mounted) return;
    setState(() {
      _clips.addAll(additions);
      _error = null;
    });
  }

  Future<void> _editClip(int index) async {
    final clip = _clips[index];
    final start = TextEditingController(text: '${clip['trimStartMs'] ?? 0}');
    final end = TextEditingController(text: '${clip['trimEndMs'] ?? ''}');
    final speed = TextEditingController(text: '${clip['playbackSpeed'] ?? 1.0}');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(clip['name']?.toString() ?? 'Clip settings'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: start, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Trim start (milliseconds)'),
              validator: (v) => int.tryParse(v ?? '') == null || int.parse(v!) < 0 ? 'Enter zero or more' : null),
            TextFormField(controller: end, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Trim end (milliseconds, blank = full clip)'),
              validator: (v) => (v == null || v.trim().isEmpty) ? null :
                (int.tryParse(v) == null || int.parse(v) <= int.parse(start.text.isEmpty ? '0' : start.text) ? 'Must be after trim start' : null)),
            TextFormField(controller: speed, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Playback speed (0.5 to 2.0)'),
              validator: (v) { final n = double.tryParse(v ?? ''); return n == null || n < 0.5 || n > 2 ? 'Use 0.5 to 2.0' : null; }),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        clip['trimStartMs'] = int.parse(start.text);
        clip['trimEndMs'] = end.text.trim().isEmpty ? null : int.parse(end.text);
        clip['playbackSpeed'] = double.parse(speed.text);
      });
    }
    start.dispose(); end.dispose(); speed.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please sign in again.');
      final existing = await supabase
          .from('wedding_editor_projects')
          .select('id,timeline_json')
          .eq('project_id', widget.projectId)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final previous = existing?['timeline_json'];
      final timeline = previous is Map
          ? Map<String, dynamic>.from(previous)
          : <String, dynamic>{};
      timeline['version'] = 3;
      timeline['clips'] = _clips.map((clip) => {
        'id': clip['id'],
        'name': clip['name'],
        'path': clip['path'],
        'sizeBytes': clip['sizeBytes'],
        'trimStartMs': clip['trimStartMs'] ?? 0,
        'trimEndMs': clip['trimEndMs'],
        'playbackSpeed': clip['playbackSpeed'] ?? 1.0,
      }).toList();
      timeline['clipOrder'] = _clips.map((clip) => clip['id']).toList();
      timeline['status'] = 'editable_timeline_draft';
      timeline['mediaNote'] = 'Working copies are stored in this app private folder for timeline rendering. Original media remains unchanged; no source files are uploaded to company storage.';
      final payload = {
        'project_id': widget.projectId,
        'owner_customer_id': projectOwnerId,
        'name': 'Wedding edit',
        'timeline_json': timeline,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (existing == null) {
        await supabase.from('wedding_editor_projects').insert(payload);
      } else {
        await supabase.from('wedding_editor_projects').update(payload).eq('id', existing['id']);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clip order saved to your editable timeline.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save clip timeline: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    return Scaffold(
      appBar: AppBar(title: Text('Clip timeline · ${widget.projectTitle}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text(
                    'Add wedding clips and arrange their playback order.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _addClips,
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Add multiple video clips'),
                  ),
                  const Text(
                    'Drag clips to reorder them. Original files are not changed or uploaded.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ]),
              ),
              Expanded(
                child: _clips.isEmpty
                    ? const Center(child: Text('No clips yet. Add your wedding videos.'))
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _clips.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex--;
                            final clip = _clips.removeAt(oldIndex);
                            _clips.insert(newIndex, clip);
                          });
                        },
                        itemBuilder: (context, index) {
                          final clip = _clips[index];
                          return Card(
                            key: ValueKey(clip['id']),
                            child: ListTile(
                              leading: CircleAvatar(child: Text('${index + 1}')),
                              title: Text(clip['name']?.toString() ?? 'Wedding clip'),
                              subtitle: Text(
                                clip['path'] == null ? 'Source needs to be selected again' : 'Copied to secure app-private working folder',
                              ),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  tooltip: 'Trim and speed',
                                  onPressed: _saving ? null : () => _editClip(index),
                                  icon: const Icon(Icons.tune),
                                ),
                                IconButton(
                                  tooltip: 'Remove clip',
                                  onPressed: _saving ? null : () => setState(() => _clips.removeAt(index)),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save clip timeline'),
                      style: FilledButton.styleFrom(backgroundColor: burgundy),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }
}
