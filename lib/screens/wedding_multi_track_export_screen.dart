import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backend.dart';
import '../services/editor_media_sync_service.dart';

/// Experimental on-device render path for ordered clips and independent audio tracks.
/// Source media remains on-device; only the finished export can be shared by the customer.
class WeddingMultiTrackExportScreen extends StatefulWidget {
  const WeddingMultiTrackExportScreen({
    super.key,
    required this.projectTitle,
    required this.projectId,
    this.initialClips = const [],
    this.initialAudioTracks = const [],
  });

  final String projectTitle;
  final String projectId;
  final List<Map<String, dynamic>> initialClips;
  final List<Map<String, dynamic>> initialAudioTracks;

  @override
  State<WeddingMultiTrackExportScreen> createState() =>
      _WeddingMultiTrackExportScreenState();
}

class _WeddingMultiTrackExportScreenState
    extends State<WeddingMultiTrackExportScreen> {
  final _titleController = TextEditingController();
  final _captionController = TextEditingController();
  final List<PlatformFile> _clips = [];
  final List<PlatformFile> _tracks = [];
  final Map<String, Map<String, dynamic>> _trackSettings = {};
  final Map<String, Map<String, dynamic>> _clipSettings = {};
  bool _useDissolve = true;
  bool _warmFilter = false;
  bool _working = false;
  double _progress = 0;
  String? _outputPath;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    for (final clip in widget.initialClips) {
      final path = clip['path']?.toString();
      if (path == null || !File(path).existsSync()) continue;
      _clips.add(PlatformFile(
        name: clip['name']?.toString() ?? 'Wedding clip',
        size: (clip['sizeBytes'] as num?)?.toInt() ?? File(path).lengthSync(),
        path: path,
      ));
      _clipSettings[path] = Map<String, dynamic>.from(clip);
    }
    for (final track in widget.initialAudioTracks) {
      final path = track['path']?.toString();
      if (path == null || !File(path).existsSync()) continue;
      _tracks.add(PlatformFile(
        name: track['name']?.toString() ?? 'Music track',
        size: File(path).lengthSync(),
        path: path,
      ));
      _trackSettings[path] = {
        'startAtMs': (track['startAtMs'] as num?)?.toInt() ?? 0,
        'trimStartMs': (track['trimStartMs'] as num?)?.toInt() ?? 0,
        'trimEndMs': (track['trimEndMs'] as num?)?.toInt(),
        'volume': (track['volume'] as num?)?.toDouble() ?? 1.0,
        'fadeInMs': (track['fadeInMs'] as num?)?.toInt() ?? 0,
        'fadeOutMs': (track['fadeOutMs'] as num?)?.toInt() ?? 0,
      };
    }
    _loadSavedTimeline();
  }

  final _mediaSync = EditorMediaSyncService();

  String _mediaMimeType(String path, {required bool audio}) {
    final extension = path.split('.').last.toLowerCase();
    const types = {
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'm4v': 'video/x-m4v',
      'webm': 'video/webm', 'mkv': 'video/x-matroska', '3gp': 'video/3gpp',
      'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'aac': 'audio/aac',
      'wav': 'audio/wav', 'ogg': 'audio/ogg', 'flac': 'audio/flac',
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'webp': 'image/webp',
    };
    return types[extension] ?? (audio ? 'audio/mpeg' : 'video/mp4');
  }

  Future<void> _loadSavedTimeline() async {
    try {
      final row = await supabase.from('wedding_editor_projects')
          .select('id,timeline_json')
          .eq('project_id', widget.projectId)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final data = row?['timeline_json'];
      if (data is! Map || row?['id'] == null) return;
      final editorId = row!['id'].toString();
      final clips = data['clips'];
      final tracks = data['audioTracks'];
      final loadedClips = <PlatformFile>[];
      final loadedClipSettings = <String, Map<String, dynamic>>{};
      if (clips is List) {
        for (final item in clips.whereType<Map>()) {
          final value = Map<String, dynamic>.from(item);
          var path = value['path']?.toString();
          if (path == null || !File(path).existsSync()) {
            final driveId = value['driveFileId']?.toString();
            if (driveId != null && driveId.isNotEmpty) {
              final restored = await _mediaSync.downloadFile(
                editorProjectId: editorId,
                fileId: driveId,
                filename: value['name']?.toString() ?? 'Wedding clip.mp4',
              );
              path = restored.path;
              value['path'] = path;
            }
          }
          if (path == null || !File(path).existsSync()) continue;
          loadedClips.add(PlatformFile(name: value['name']?.toString() ?? 'Wedding clip', size: File(path).lengthSync(), path: path));
          loadedClipSettings[path] = value;
        }
      }
      final loadedTracks = <PlatformFile>[];
      final loadedTrackSettings = <String, Map<String, dynamic>>{};
      if (tracks is List) {
        for (final item in tracks.whereType<Map>()) {
          final value = Map<String, dynamic>.from(item);
          var path = value['path']?.toString();
          if (path == null || !File(path).existsSync()) {
            final driveId = value['driveFileId']?.toString();
            if (driveId != null && driveId.isNotEmpty) {
              final restored = await _mediaSync.downloadFile(
                editorProjectId: editorId,
                fileId: driveId,
                filename: value['name']?.toString() ?? 'Wedding music.mp3',
              );
              path = restored.path;
              value['path'] = path;
            }
          }
          if (path == null || !File(path).existsSync()) continue;
          loadedTracks.add(PlatformFile(name: value['name']?.toString() ?? 'Music track', size: File(path).lengthSync(), path: path));
          loadedTrackSettings[path] = value;
        }
      }
      if (!mounted) return;
      setState(() {
        if (loadedClips.isNotEmpty) { _clips..clear()..addAll(loadedClips); _clipSettings..clear()..addAll(loadedClipSettings); }
        if (loadedTracks.isNotEmpty) { _tracks..clear()..addAll(loadedTracks); _trackSettings..clear()..addAll(loadedTrackSettings); }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not restore saved editor media: $e');
    }
  }

  Future<void> _saveTimelineDraft() async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Please sign in again.');
    final project = await supabase.from('wedding_projects').select('owner_customer_id').eq('id', widget.projectId).single();
    final existing = await supabase.from('wedding_editor_projects')
        .select('id,timeline_json').eq('project_id', widget.projectId)
        .order('updated_at', ascending: false).limit(1).maybeSingle();
    final previous = existing?['timeline_json'];
    final timeline = previous is Map ? Map<String, dynamic>.from(previous) : <String, dynamic>{};
    timeline['version'] = 7;
    timeline['clips'] = _clips.map((clip) {
      final path = clip.path!;
      return <String, dynamic>{'name': clip.name, 'path': path, 'sizeBytes': clip.size, ...?_clipSettings[path]};
    }).toList();
    timeline['audioTracks'] = _tracks.map((track) {
      final path = track.path!;
      return <String, dynamic>{'name': track.name, 'path': path, 'sizeBytes': track.size, ...?_trackSettings[path]};
    }).toList();
    timeline['clipOrder'] = _clips.map((clip) => clip.path).toList();
    timeline['editorStorageNote'] = 'Original source media is backed up to the connected Google Drive and can be restored on another signed-in device.';
    if (_outputPath != null) timeline['lastLocalExportPath'] = _outputPath;
    final payload = {'project_id': widget.projectId, 'owner_customer_id': project['owner_customer_id'], 'name': 'Wedding edit', 'timeline_json': timeline, 'updated_at': DateTime.now().toIso8601String()};
    String editorId;
    if (existing == null) {
      final inserted = await supabase.from('wedding_editor_projects').insert(payload).select('id').single();
      editorId = inserted['id'].toString();
    } else {
      editorId = existing['id'].toString();
      await supabase.from('wedding_editor_projects').update(payload).eq('id', editorId);
    }

    final assets = await _mediaSync.listAssets(editorId);
    Future<void> syncList(List<dynamic> items, bool audio) async {
      for (final raw in items) {
        final item = Map<String, dynamic>.from(raw as Map);
        final driveId = item['driveFileId']?.toString();
        if (driveId != null && driveId.isNotEmpty) continue;
        final path = item['path']?.toString();
        if (path == null || !File(path).existsSync()) continue;
        final file = File(path);
        final size = await file.length();
        final name = item['name']?.toString() ?? (audio ? 'Wedding music' : 'Wedding clip');
        Map<String, dynamic>? existingAsset;
        for (final asset in assets) {
          if (asset['original_filename'] == name &&
              (asset['file_size_bytes'] as num?)?.toInt() == size &&
              asset['media_kind'] == (audio ? 'audio' : 'video')) {
            existingAsset = asset;
            break;
          }
        }
        if (existingAsset != null) {
          item['driveFileId'] = existingAsset['drive_file_id'];
        } else {
          final uploaded = await _mediaSync.uploadFile(
            editorProjectId: editorId,
            file: file,
            filename: name,
            mimeType: _mediaMimeType(path, audio: audio),
            mediaKind: audio ? 'audio' : 'video',
          );
          item['driveFileId'] = uploaded['fileId'];
          assets.add({
            'drive_file_id': uploaded['fileId'],
            'original_filename': name,
            'file_size_bytes': size,
            'media_kind': audio ? 'audio' : 'video',
          });
        }
      }
    }
    await syncList(timeline['clips'] as List, false);
    await syncList(timeline['audioTracks'] as List, true);
    timeline['driveMediaSyncedAt'] = DateTime.now().toIso8601String();
    timeline['editorStorageNote'] = 'Source video and audio are stored in Google Drive; missing local copies are restored when this project opens on another signed-in device.';
    await supabase.from('wedding_editor_projects').update({
      'timeline_json': timeline,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', editorId);
  }

  Future<void> _pickClips() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return;
    final valid = result.files.where((f) => f.path != null).toList();
    if (mounted) setState(() {
      _clips
        ..clear()
        ..addAll(valid);
      _clipSettings
        ..clear()
        ..addEntries(valid.where((f) => f.path != null).map((f) => MapEntry(f.path!, {
          'trimStartMs': 0, 'trimEndMs': null, 'playbackSpeed': 1.0,
        })));
      _outputPath = null;
      _error = null;
    });
  }

  Future<void> _pickTracks() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return;
    final valid = result.files.where((f) => f.path != null).toList();
    if (mounted) setState(() {
      _tracks
        ..clear()
        ..addAll(valid);
      _trackSettings
        ..clear()
        ..addEntries(valid.where((f) => f.path != null).map((f) => MapEntry(f.path!, {
          'startAtMs': 0, 'trimStartMs': 0, 'trimEndMs': null,
          'volume': 1.0, 'fadeInMs': 0, 'fadeOutMs': 0,
        })));
      _outputPath = null;
      _error = null;
    });
  }

  Future<Uint8List?> _buildTextOverlay() async {
    final title = _titleController.text.trim();
    final caption = _captionController.text.trim();
    if (title.isEmpty && caption.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final background = Paint()..color = const Color(0x99000000);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 1080, 260), const Radius.circular(24)),
      background,
    );
    var y = 28.0;
    if (title.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(text: title, style: const TextStyle(
          color: Colors.white, fontSize: 58, fontWeight: FontWeight.w800,
          shadows: [Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(1, 2))],
        )),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
      )..layout(maxWidth: 980);
      painter.paint(canvas, Offset((1080 - painter.width) / 2, y));
      y += painter.height + 12;
    }
    if (caption.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(text: caption, style: const TextStyle(
          color: Colors.white, fontSize: 34, fontWeight: FontWeight.w500,
          shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
        )),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
      )..layout(maxWidth: 980);
      painter.paint(canvas, Offset((1080 - painter.width) / 2, y));
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(1080, 260);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  Future<void> _export() async {
    if (_clips.isEmpty) {
      setState(() => _error = 'Choose at least one video clip.');
      return;
    }
    setState(() {
      _working = true;
      _progress = 0;
      _error = null;
      _outputPath = null;
    });
    try {
      final directory = await getApplicationDocumentsDirectory();
      final output = '${directory.path}/wedding-multitrack-${DateTime.now().millisecondsSinceEpoch}.mp4';
      final overlayBytes = await _buildTextOverlay();
      final render = VideoRenderData(
        imageLayers: overlayBytes == null ? const [] : [
          ImageLayer(
            image: EditorLayerImage.memory(overlayBytes),
            offset: const Offset(0, 1500),
            size: const Size(1080, 260),
            startTime: Duration.zero,
            endTime: const Duration(seconds: 6),
          ),
        ],
        videoSegments: _clips.map((clip) {
          final path = clip.path;
          if (path == null) throw StateError('A selected clip is no longer available.');
          final index = _clips.indexOf(clip);
          final settings = _clipSettings[path] ?? const <String, dynamic>{};
          final trimStart = (settings['trimStartMs'] as num?)?.toInt() ?? 0;
          final trimEnd = (settings['trimEndMs'] as num?)?.toInt();
          final speed = (settings['playbackSpeed'] as num?)?.toDouble() ?? 1.0;
          return VideoSegment(
            video: EditorVideo.file(File(path)),
            startTime: Duration(milliseconds: trimStart),
            endTime: trimEnd == null ? null : Duration(milliseconds: trimEnd),
            playbackSpeed: speed,
            transition: _useDissolve && index < _clips.length - 1
                ? const ClipTransition(
                    type: ClipTransitionType.dissolve,
                    duration: Duration(milliseconds: 600),
                    curve: AnimationCurve.easeInOut,
                  )
                : null,
          );
        }).toList(),
        audioTracks: _tracks.map((track) {
          final path = track.path;
          if (path == null) throw StateError('A selected audio track is no longer available.');
          final settings = _trackSettings[path] ?? const <String, dynamic>{};
          final trimStart = (settings['trimStartMs'] as int?) ?? 0;
          final trimEnd = settings['trimEndMs'] as int?;
          final startAt = (settings['startAtMs'] as int?) ?? 0;
          final fadeIn = (settings['fadeInMs'] as int?) ?? 0;
          final fadeOut = (settings['fadeOutMs'] as int?) ?? 0;
          return VideoAudioTrack(
            path: path,
            volume: (settings['volume'] as num?)?.toDouble() ?? 1.0,
            startTime: Duration(milliseconds: startAt),
            audioStartTime: Duration(milliseconds: trimStart),
            audioEndTime: trimEnd == null ? null : Duration(milliseconds: trimEnd),
            fadeInDuration: Duration(milliseconds: fadeIn),
            fadeOutDuration: Duration(milliseconds: fadeOut),
          );
        }).toList(),
        outputFormat: VideoOutputFormat.mp4,
        colorFilters: _warmFilter ? const [ColorFilter(matrix: [
          1.08, 0, 0, 0, 0.02,
          0, 1.02, 0, 0, 0.01,
          0, 0, 0.92, 0, 0,
          0, 0, 0, 1, 0,
        ])] : const [],
      );
      final subscription = ProVideoEditor.instance.progressStream.listen((event) {
        if (mounted) setState(() => _progress = event.progress.clamp(0.0, 1.0).toDouble());
      });
      try {
        await ProVideoEditor.instance.renderVideoToFile(output, render);
      } finally {
        await subscription.cancel();
      }
      if (!mounted) return;
      setState(() {
        _outputPath = output;
        _progress = 1;
      });
      await _saveTimelineDraft();
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editTrack(PlatformFile track) async {
    final path = track.path;
    if (path == null) return;
    final current = Map<String, dynamic>.from(_trackSettings[path] ?? {
      'startAtMs': 0, 'trimStartMs': 0, 'trimEndMs': null,
      'volume': 1.0, 'fadeInMs': 0, 'fadeOutMs': 0,
    });
    final start = TextEditingController(text: '${current['startAtMs']}');
    final trimStart = TextEditingController(text: '${current['trimStartMs']}');
    final trimEnd = TextEditingController(text: '${current['trimEndMs'] ?? ''}');
    final fadeIn = TextEditingController(text: '${current['fadeInMs']}');
    final fadeOut = TextEditingController(text: '${current['fadeOutMs']}');
    double volume = (current['volume'] as num).toDouble();
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text(track.name),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            _timeField(start, 'Start at (ms)'),
            _timeField(trimStart, 'Trim from (ms)'),
            _timeField(trimEnd, 'Trim end (ms, optional)', optional: true),
            _timeField(fadeIn, 'Fade in (ms)'),
            _timeField(fadeOut, 'Fade out (ms)'),
            Text('Volume ${(volume * 100).round()}%'),
            Slider(value: volume.clamp(0, 1).toDouble(), min: 0, max: 1, divisions: 20,
              onChanged: (value) => setDialogState(() => volume = value)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(context, true);
          }, child: const Text('Save')),
        ],
      )),
    );
    if (saved == true && mounted) {
      setState(() {
        _trackSettings[path] = {
          'startAtMs': int.parse(start.text),
          'trimStartMs': int.parse(trimStart.text),
          'trimEndMs': trimEnd.text.trim().isEmpty ? null : int.parse(trimEnd.text),
          'fadeInMs': int.parse(fadeIn.text),
          'fadeOutMs': int.parse(fadeOut.text),
          'volume': volume,
        };
        _outputPath = null;
      });
    }
  }

  Widget _timeField(TextEditingController controller, String label, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: (value) {
        if (optional && (value == null || value.trim().isEmpty)) return null;
        final number = int.tryParse(value ?? '');
        if (number == null || number < 0) return 'Enter zero or a positive number';
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multi-track export beta')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.projectTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Select clips in the order you want them joined, then add licensed or customer-owned music tracks. This beta renders all selected clips and mixes the selected audio tracks on the device.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _working ? null : _pickClips,
            icon: const Icon(Icons.video_library_outlined),
            label: Text('Choose video clips (${_clips.length})'),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _clips.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _clips.removeAt(oldIndex);
                _clips.insert(newIndex, item);
                _outputPath = null;
              });
            },
            itemBuilder: (context, index) => ListTile(
              key: ValueKey('clip-${_clips[index].path}'),
              dense: true,
              leading: const Icon(Icons.drag_handle),
              title: Text(_clips[index].name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('Clip ${index + 1} · drag to reorder'),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _working ? null : _pickTracks,
            icon: const Icon(Icons.library_music_outlined),
            label: Text('Choose music tracks (${_tracks.length})'),
          ),
          ..._tracks.map((track) {
            final path = track.path!;
            final settings = _trackSettings[path] ?? const <String, dynamic>{};
            final volume = ((settings['volume'] as num?)?.toDouble() ?? 1) * 100;
            return ListTile(
              dense: true,
              leading: const Icon(Icons.music_note_outlined),
              title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('Start ${(settings['startAtMs'] ?? 0)} ms · ${volume.round()}% volume'),
              trailing: IconButton(
                tooltip: 'Edit track timing and volume',
                icon: const Icon(Icons.tune),
                onPressed: _working ? null : () => _editTrack(track),
              ),
            );
          }),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Video title overlay (optional)', border: OutlineInputBorder()),
            onChanged: (_) => setState(() => _outputPath = null),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _captionController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Caption / date overlay (optional)', border: OutlineInputBorder()),
            onChanged: (_) => setState(() => _outputPath = null),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _useDissolve,
            onChanged: _working ? null : (value) => setState(() { _useDissolve = value; _outputPath = null; }),
            title: const Text('Dissolve transitions between clips'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _warmFilter,
            onChanged: _working ? null : (value) => setState(() { _warmFilter = value; _outputPath = null; }),
            title: const Text('Warm wedding colour filter'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _working ? null : () async {
              try { await _saveTimelineDraft(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wedding edit timeline saved.'))); }
              catch (e) { if (mounted) setState(() => _error = 'Could not save timeline: $e'); }
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save editable timeline'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _working ? null : _export,
            icon: const Icon(Icons.movie_creation_outlined),
            label: Text(_working ? 'Rendering…' : 'Render combined wedding video'),
          ),
          if (_working) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            Text('${(_progress * 100).round()}%'),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_outputPath != null) ...[
            const SizedBox(height: 16),
            const Text('Export completed and saved in app documents.'),
            OutlinedButton.icon(
              onPressed: () => Share.shareXFiles(
                [XFile(_outputPath!)],
                text: 'Edited wedding video',
              ),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share / save video'),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'This on-device editor applies clip order, per-clip trim and speed, dissolve transitions, optional title/caption overlays, a warm colour filter, and per-track start, trim, volume and fade settings. Source files stay on this device; only the exported MP4 can be shared.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
