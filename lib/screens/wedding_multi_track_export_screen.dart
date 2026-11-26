import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:share_plus/share_plus.dart';

/// Experimental on-device render path for ordered clips and independent audio tracks.
/// Source media remains on-device; only the finished export can be shared by the customer.
class WeddingMultiTrackExportScreen extends StatefulWidget {
  const WeddingMultiTrackExportScreen({super.key, required this.projectTitle});

  final String projectTitle;

  @override
  State<WeddingMultiTrackExportScreen> createState() =>
      _WeddingMultiTrackExportScreenState();
}

class _WeddingMultiTrackExportScreenState
    extends State<WeddingMultiTrackExportScreen> {
  final List<PlatformFile> _clips = [];
  final List<PlatformFile> _tracks = [];
  bool _working = false;
  double _progress = 0;
  String? _outputPath;
  String? _error;

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
      _outputPath = null;
      _error = null;
    });
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
      final render = VideoRenderData(
        videoSegments: _clips.map((clip) {
          final path = clip.path;
          if (path == null) throw StateError('A selected clip is no longer available.');
          return VideoSegment(video: EditorVideo.file(File(path)));
        }).toList(),
        audioTracks: _tracks.map((track) {
          final path = track.path;
          if (path == null) throw StateError('A selected audio track is no longer available.');
          return VideoAudioTrack(path: path, volume: 1.0);
        }).toList(),
        outputFormat: VideoOutputFormat.mp4,
      );
      final subscription = ProVideoEditor.instance.progressStream.listen((event) {
        if (mounted) setState(() => _progress = event.progress.clamp(0.0, 1.0));
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
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

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
          ..._clips.map((clip) => ListTile(
            dense: true,
            leading: const Icon(Icons.movie_outlined),
            title: Text(clip.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          )),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _working ? null : _pickTracks,
            icon: const Icon(Icons.library_music_outlined),
            label: Text('Choose music tracks (${_tracks.length})'),
          ),
          ..._tracks.map((track) => ListTile(
            dense: true,
            leading: const Icon(Icons.music_note_outlined),
            title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          )),
          const SizedBox(height: 16),
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
            'Beta note: this first render path joins clips and mixes full-length audio tracks. Per-track trim, start offsets, fades, transitions, timed effects and text overlays will be wired to the saved timeline in the next pass. Selected source files are not uploaded.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
