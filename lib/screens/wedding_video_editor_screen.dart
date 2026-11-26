import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:native_video_editor/native_video_editor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../services/backend.dart';
import 'wedding_clip_timeline_screen.dart';

class WeddingVideoEditorScreen extends StatefulWidget {
  const WeddingVideoEditorScreen({
    super.key,
    required this.projectId,
    required this.projectTitle,
  });

  final String projectId;
  final String projectTitle;

  @override
  State<WeddingVideoEditorScreen> createState() => _WeddingVideoEditorScreenState();
}

class _WeddingVideoEditorScreenState extends State<WeddingVideoEditorScreen> {
  VideoPlayerController? _preview;
  String? _videoPath;
  String? _videoName;
  String? _musicPath;
  String? _musicName;
  String? _exportedPath;
  Duration _duration = Duration.zero;
  RangeValues _trim = const RangeValues(0, 1);
  double _speed = 1;
  double _progress = 0;
  bool _working = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await _preview?.dispose();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _preview = controller;
        _videoPath = path;
        _videoName = result!.files.single.name;
        _duration = controller.value.duration;
        final max = _duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
        _trim = RangeValues(0, max);
        _exportedPath = null;
        _error = null;
        _message = 'Video ready. Choose a trim range and export.';
      });
    } catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _error = 'Could not open this video: $e');
    }
  }

  Future<void> _pickMusic() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _musicPath = path;
      _musicName = result!.files.single.name;
      _exportedPath = null;
      _error = null;
    });
  }

  Future<void> _togglePreview() async {
    final player = _preview;
    if (player == null) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _export() async {
    final input = _videoPath;
    if (input == null || _duration.inMilliseconds < 1000) {
      setState(() => _error = 'Choose a video with a valid duration first.');
      return;
    }
    if (_trim.end - _trim.start < 1) {
      setState(() => _error = 'Select at least one second of video.');
      return;
    }

    setState(() {
      _working = true;
      _progress = 0;
      _error = null;
      _message = 'Preparing your wedding video…';
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final trimmedPath = '${directory.path}/wedding-${stamp}-trimmed.mp4';
      final finalPath = '${directory.path}/wedding-${stamp}-final.mp4';

      await NativeVideoEditor.processVideo(
        VideoEditRequest(
          inputPath: input,
          outputPath: trimmedPath,
          trimStart: Duration(milliseconds: _trim.start.round()),
          trimEnd: Duration(milliseconds: _trim.end.round()),
          speedMultiplier: _speed,
        ),
        onProgress: (value) {
          if (mounted) setState(() => _progress = value * (_musicPath == null ? 1 : 0.5));
        },
      );

      final music = _musicPath;
      if (music != null) {
        await NativeVideoEditor.mergeAudioIntoVideo(
          AudioMergeRequest(
            inputVideoPath: trimmedPath,
            audioPath: music,
            outputPath: finalPath,
            replaceExistingAudio: true,
          ),
          onProgress: (value) {
            if (mounted) setState(() => _progress = 0.5 + value * 0.5);
          },
        );
        await File(trimmedPath).delete().catchError((_) => File(trimmedPath));
      } else {
        await File(trimmedPath).rename(finalPath);
      }

      if (!mounted) return;
      setState(() {
        _exportedPath = finalPath;
        _progress = 1;
        _message = 'Export complete. Your original source video was not changed.';
      });
      await _saveDraftMetadata();
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed on this device: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveDraftMetadata() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final data = {
        'version': 2,
        'sourceName': _videoName,
        'musicName': _musicName,
        'trimStartMs': _trim.start.round(),
        'trimEndMs': _trim.end.round(),
        'sourceDurationMs': _duration.inMilliseconds,
        'speedMultiplier': _speed,
        'exportedAt': DateTime.now().toIso8601String(),
        'status': 'exported_local_draft',
        'note': 'Local media paths are not uploaded. Re-select original files to edit again on this device.',
      };
      final existing = await supabase
          .from('wedding_editor_projects')
          .select('id')
          .eq('project_id', widget.projectId)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final payload = {
        'project_id': widget.projectId,
        'owner_customer_id': user.id,
        'name': 'Wedding edit',
        'timeline_json': data,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (existing == null) {
        await supabase.from('wedding_editor_projects').insert(payload);
      } else {
        await supabase.from('wedding_editor_projects').update(payload).eq('id', existing['id']);
      }
    } catch (_) {
      // Local export remains available even if cloud draft metadata cannot sync.
    }
  }

  String _time(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${value.inHours > 0 ? '${value.inHours.toString().padLeft(2, '0')}:' : ''}$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF6F2438);
    final totalMs = _duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
    final player = _preview;
    return Scaffold(
      appBar: AppBar(title: Text('Edit · ${widget.projectTitle}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFFF4EAE6),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Wedding Video Editor', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: burgundy)),
                const SizedBox(height: 6),
                const Text('Trim, preview, adjust speed and replace the soundtrack. Original video files are never overwritten.'),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: _working ? null : _pickVideo,
                  icon: const Icon(Icons.video_library_outlined),
                  label: Text(_videoName ?? 'Choose wedding video'),
                  style: FilledButton.styleFrom(backgroundColor: burgundy),
                )),
              ]),
            ),
          ),
          if (player != null && player.value.isInitialized) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: player.value.aspectRatio,
                child: VideoPlayer(player),
              ),
            ),
            Center(child: IconButton.filledTonal(
              onPressed: _working ? null : _togglePreview,
              icon: Icon(player.value.isPlaying ? Icons.pause : Icons.play_arrow),
            )),
            const SizedBox(height: 8),
            Text('Trim range  ·  ${_time(Duration(milliseconds: _trim.start.round()))} – ${_time(Duration(milliseconds: _trim.end.round()))}'),
            RangeSlider(
              min: 0,
              max: totalMs,
              divisions: totalMs > 1 ? totalMs.round().clamp(1, 1000).toInt() : 1,
              values: RangeValues(
                _trim.start.clamp(0, totalMs - 1).toDouble(),
                _trim.end.clamp(1, totalMs).toDouble(),
              ),
              onChanged: _working ? null : (value) => setState(() {
                _trim = RangeValues(value.start, value.end);
                _exportedPath = null;
              }),
            ),
            const SizedBox(height: 8),
            const Text('Playback speed'),
            Slider(
              min: 0.5,
              max: 2,
              divisions: 6,
              value: _speed,
              label: '${_speed.toStringAsFixed(2)}×',
              onChanged: _working ? null : (value) => setState(() {
                _speed = value;
                _exportedPath = null;
              }),
            ),
            Center(child: Text('${_speed.toStringAsFixed(2)}×  ·  0.5× slow motion to 2× fast')),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _working ? null : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WeddingClipTimelineScreen(
                  projectId: widget.projectId,
                  projectTitle: widget.projectTitle,
                ),
              ),
            ),
            icon: const Icon(Icons.video_collection_outlined),
            label: const Text('Manage multi-clip timeline'),
          ),
          OutlinedButton.icon(
            onPressed: _working || _videoPath == null ? null : _pickMusic,
            icon: const Icon(Icons.music_note),
            label: Text(_musicName ?? 'Choose replacement music (optional)'),
          ),
          if (_musicName != null)
            TextButton.icon(
              onPressed: _working ? null : () => setState(() {
                _musicPath = null;
                _musicName = null;
                _exportedPath = null;
              }),
              icon: const Icon(Icons.close),
              label: const Text('Remove replacement music'),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _working || _videoPath == null ? null : _export,
            icon: const Icon(Icons.movie_creation_outlined),
            label: Text(_working ? 'Exporting…' : 'Export edited wedding video'),
            style: FilledButton.styleFrom(backgroundColor: burgundy),
          ),
          if (_working) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            Text('${(_progress * 100).toStringAsFixed(0)}%'),
          ],
          if (_message != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_message!, style: const TextStyle(color: Colors.green)),
          ),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
          if (_exportedPath != null) ...[
            const SizedBox(height: 12),
            SelectableText('Export saved locally: $_exportedPath'),
            const Text("This export is saved in the app's private documents folder. Share it or keep it here; uninstalling the app removes app-private files."),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Share.shareXFiles([XFile(_exportedPath!)], text: 'My edited wedding video'),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share / save edited video'),
            ),
          ],
          const SizedBox(height: 16),
          const Card(child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Current editor beta limits'),
            subtitle: Text('This build supports one video source, trim, speed and one replacement music file. Multi-clip timelines, timed song changes, multiple simultaneous tracks, transitions, text, filters and Reels presets still need implementation.'),
          )),
          const Card(child: ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Your originals stay safe'),
            subtitle: Text('Editing runs on your phone. The source file is read-only; this editor does not upload your wedding media to company storage.'),
          )),
        ],
      ),
    );
  }
}
