import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:share_plus/share_plus.dart';
import '../services/backend.dart';

class WeddingReelsScreen extends StatefulWidget {
  const WeddingReelsScreen({super.key, required this.projectId, required this.projectTitle});
  final String projectId;
  final String projectTitle;
  @override
  State<WeddingReelsScreen> createState() => _WeddingReelsScreenState();
}

class _WeddingReelsScreenState extends State<WeddingReelsScreen> {
  bool loading = true, rendering = false;
  double progress = 0;
  String? error, outputPath;
  String preset = 'couple_entry';
  List<Map<String,dynamic>> clips = [];
  List<Map<String,dynamic>> tracks = [];

  static const presets = {
    'couple_entry': 'Couple entry',
    'bride_groom_entry': 'Bride / groom entry',
    'ceremony': 'Ceremony',
    'family_moments': 'Family moments',
    'teaser': 'Wedding teaser',
  };

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final row = await supabase.from('wedding_editor_projects')
          .select('id,timeline_json').eq('project_id', widget.projectId)
          .order('updated_at', ascending: false).limit(1).maybeSingle();
      final timeline = row?['timeline_json'];
      if (timeline is Map) {
        clips = timeline['clips'] is List
            ? List<Map<String,dynamic>>.from((timeline['clips'] as List).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)))
            : [];
        tracks = timeline['audioTracks'] is List
            ? List<Map<String,dynamic>>.from((timeline['audioTracks'] as List).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)))
            : [];
      }
    } catch (e) { error = 'Could not load saved timeline: $e'; }
    finally { if (mounted) setState(()=>loading=false); }
  }

  Future<void> renderReel() async {
    final available = clips.where((c) {
      final p = c['path']?.toString();
      return p != null && File(p).existsSync();
    }).toList();
    if (available.isEmpty) { setState(()=>error='Add and save video clips in the timeline first.'); return; }
    setState(() { rendering=true; progress=0; error=null; outputPath=null; });
    try {
      final segments = available.map((clip) {
        final path = clip['path'].toString();
        final start = (clip['trimStartMs'] as num?)?.toInt() ?? 0;
        final end = (clip['trimEndMs'] as num?)?.toInt();
        return VideoSegment(
          video: EditorVideo.file(File(path)),
          startTime: Duration(milliseconds: start),
          endTime: end == null ? null : Duration(milliseconds: end),
          playbackSpeed: (clip['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
        );
      }).toList();
      final audio = tracks.where((t)=>t['path'] is String && File(t['path'].toString()).existsSync()).map((t)=>VideoAudioTrack(
        path: t['path'].toString(),
        volume: (t['volume'] as num?)?.toDouble() ?? 1,
        startTime: Duration(milliseconds:(t['startAtMs'] as num?)?.toInt() ?? 0),
        audioStartTime: Duration(milliseconds:(t['trimStartMs'] as num?)?.toInt() ?? 0),
        audioEndTime: (t['trimEndMs'] as num?) == null ? null : Duration(milliseconds:(t['trimEndMs'] as num).toInt()),
        fadeInDuration: Duration(milliseconds:(t['fadeInMs'] as num?)?.toInt() ?? 0),
        fadeOutDuration: Duration(milliseconds:(t['fadeOutMs'] as num?)?.toInt() ?? 0),
      )).toList();
      final directory = await getApplicationDocumentsDirectory();
      final output = '${directory.path}/wedding-reel-${DateTime.now().millisecondsSinceEpoch}.mp4';
      final render = VideoRenderData(
        composition: VideoComposition(
          canvasSize: const Size(1080,1920),
          backgroundColor: const Color(0xFF000000),
          layers: [
            VideoLayer(
              transform: const SegmentTransform(offset: Offset.zero,size: Size(1080,1920),fit: SegmentFit.cover),
              clips: segments,
            ),
          ],
        ),
        audioTracks: audio,
        outputFormat: VideoOutputFormat.mp4,
        shouldOptimizeForNetworkUse: true,
      );
      final sub = ProVideoEditor.instance.progressStream.listen((e){
        if(mounted)setState(()=>progress=e.progress.clamp(0.0,1.0));
      });
      try { await ProVideoEditor.instance.renderVideoToFile(output,render); }
      finally { await sub.cancel(); }
      if (!mounted) return;
      final user=supabase.auth.currentUser;
      if(user!=null){
        await supabase.from('wedding_reel_exports').insert({
          'project_id':widget.projectId,'owner_customer_id':user.id,
          'preset_key':preset,'aspect_ratio':'9:16',
          'edit_settings_json':{'clipCount':available.length,'audioTrackCount':audio.length,'localExportName':output.split('/').last},
          'status':'ready',
        });
      }
      setState(() { outputPath=output; progress=1; });
    } catch(e) { if(mounted)setState(()=>error='Reel export failed: $e'); }
    finally { if(mounted)setState(()=>rendering=false); }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Wedding Reels • 9:16')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      const Chip(label:Text('Development Mode')),
      const Text('Create a vertical 9:16 MP4 from your saved clip and music timeline. Source files stay in the app-private working folder; originals are unchanged.'),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(
        initialValue:preset,
        decoration:const InputDecoration(labelText:'Reel preset'),
        items:presets.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),
        onChanged:rendering?null:(v)=>setState(()=>preset=v??preset),
      ),
      const SizedBox(height:12),
      Text('Saved clips: ${clips.length} • Saved music tracks: ${tracks.length}'),
      FilledButton.icon(onPressed:rendering?null:renderReel,icon:const Icon(Icons.movie_creation_outlined),label:Text(rendering?'Rendering…':'Render vertical reel')),
      if(rendering)LinearProgressIndicator(value:progress==0?null:progress),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:const TextStyle(color:Colors.red))),
      if(outputPath!=null)...[
        const SizedBox(height:16),
        const Text('Vertical reel exported successfully.'),
        OutlinedButton.icon(onPressed:()=>Share.shareXFiles([XFile(outputPath!)],text:'Wedding Reel'),icon:const Icon(Icons.share),label:const Text('Share reel')),
      ],
    ]),
  );
}
