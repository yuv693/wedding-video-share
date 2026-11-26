import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/backend.dart';

class WeddingAudioTimelineScreen extends StatefulWidget {
  const WeddingAudioTimelineScreen({
    super.key,
    required this.projectId,
    required this.projectTitle,
  });

  final String projectId;
  final String projectTitle;

  @override
  State<WeddingAudioTimelineScreen> createState() => _WeddingAudioTimelineScreenState();
}

class _WeddingAudioTimelineScreenState extends State<WeddingAudioTimelineScreen> {
  final List<Map<String, dynamic>> _tracks = [];
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
      final data = row?['timeline_json'];
      final saved = data is Map ? data['audioTracks'] : null;
      if (saved is List) {
        _tracks
          ..clear()
          ..addAll(saved.whereType<Map>().map((item) => Map<String, dynamic>.from(item)));
      }
    } catch (e) {
      _error = 'Could not load audio timeline: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addTracks() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final additions = result.files.map((file) => <String, dynamic>{
      'id': 'audio-${DateTime.now().microsecondsSinceEpoch}-${file.name.hashCode}',
      'name': file.name,
      'path': file.path,
      'startAtMs': 0,
      'trimStartMs': 0,
      'trimEndMs': null,
      'volume': 1.0,
      'fadeInMs': 0,
      'fadeOutMs': 0,
    }).toList();
    if (!mounted) return;
    setState(() {
      _tracks.addAll(additions);
      _error = null;
    });
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
      timeline['version'] = 4;
      timeline['audioTracks'] = _tracks.map((track) => {
        'id': track['id'],
        'name': track['name'],
        'startAtMs': track['startAtMs'] ?? 0,
        'trimStartMs': track['trimStartMs'] ?? 0,
        'trimEndMs': track['trimEndMs'],
        'volume': track['volume'] ?? 1.0,
        'fadeInMs': track['fadeInMs'] ?? 0,
        'fadeOutMs': track['fadeOutMs'] ?? 0,
      }).toList();
      timeline['audioTimelineStatus'] = 'editable_audio_timeline_draft';
      timeline['audioMediaNote'] = 'Audio source paths are kept on this device and are not uploaded. Re-select audio files after reinstall or on another device.';
      final payload = {
        'project_id': widget.projectId,
        'owner_customer_id': user.id,
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
          const SnackBar(content: Text('Audio track settings saved to your editable project.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save audio timeline: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editTrack(int index) async {
    final track = _tracks[index];
    final start = TextEditingController(text: '${track['startAtMs'] ?? 0}');
    final trimStart = TextEditingController(text: '${track['trimStartMs'] ?? 0}');
    final trimEnd = TextEditingController(text: '${track['trimEndMs'] ?? ''}');
    final fadeIn = TextEditingController(text: '${track['fadeInMs'] ?? 0}');
    final fadeOut = TextEditingController(text: '${track['fadeOutMs'] ?? 0}');
    double volume = (track['volume'] as num?)?.toDouble() ?? 1.0;
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text(track['name']?.toString() ?? 'Audio track'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _numberField(start, 'Start at (milliseconds)'),
              _numberField(trimStart, 'Trim from (milliseconds)'),
              _numberField(trimEnd, 'Trim end (milliseconds; optional)'),
              _numberField(fadeIn, 'Fade in (milliseconds)'),
              _numberField(fadeOut, 'Fade out (milliseconds)'),
              const SizedBox(height: 8),
              Text('Volume · ${(volume * 100).round()}%'),
              Slider(
                min: 0,
                max: 1,
                divisions: 20,
                value: volume.clamp(0, 1),
                onChanged: (value) => setDialogState(() => volume = value),
              ),
            ],
          )),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(context, true);
          }, child: const Text('Save settings')),
        ],
      )),
    );
    if (ok == true && mounted) {
      setState(() {
        track['startAtMs'] = int.parse(start.text);
        track['trimStartMs'] = int.parse(trimStart.text);
        track['trimEndMs'] = trimEnd.text.trim().isEmpty ? null : int.parse(trimEnd.text);
        track['fadeInMs'] = int.parse(fadeIn.text);
        track['fadeOutMs'] = int.parse(fadeOut.text);
        track['volume'] = volume;
      });
    }
  }

  Widget _numberField(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return label.contains('optional') ? null : 'Enter a value';
        final number = int.tryParse(value);
        if (number == null || number < 0) return 'Use zero or a positive number';
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    return Scaffold(
      appBar: AppBar(title: Text('Music timeline · ${widget.projectTitle}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Add multiple songs and set where each one belongs in your wedding video.'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _addTracks,
                    icon: const Icon(Icons.library_music_outlined),
                    label: const Text('Add multiple music tracks'),
                  ),
                  const Text('Edit each track to set timeline start, trim, volume and fade in/out. Use music you own or are licensed to use.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
              Expanded(
                child: _tracks.isEmpty
                    ? const Center(child: Text('No music tracks yet.'))
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _tracks.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex--;
                            final item = _tracks.removeAt(oldIndex);
                            _tracks.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final track = _tracks[index];
                          final volume = ((track['volume'] as num?)?.toDouble() ?? 1) * 100;
                          return Card(
                            key: ValueKey(track['id']),
                            child: ListTile(
                              leading: const Icon(Icons.music_note),
                              title: Text(track['name']?.toString() ?? 'Music track'),
                              subtitle: Text('Starts ${track['startAtMs'] ?? 0} ms · Volume ${volume.round()}% · Fade in ${track['fadeInMs'] ?? 0} ms · Fade out ${track['fadeOutMs'] ?? 0} ms'),
                              onTap: () => _editTrack(index),
                              trailing: IconButton(
                                tooltip: 'Remove track',
                                onPressed: _saving ? null : () => setState(() => _tracks.removeAt(index)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_error != null)
                Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save music timeline'),
                      style: FilledButton.styleFrom(backgroundColor: burgundy),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }
}
