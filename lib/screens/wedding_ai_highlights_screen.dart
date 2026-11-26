import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import '../services/backend.dart';

class WeddingAiHighlightsScreen extends StatefulWidget {
  const WeddingAiHighlightsScreen({super.key,required this.projectId,required this.projectTitle});
  final String projectId,projectTitle;
  @override
  State<WeddingAiHighlightsScreen> createState()=>_WeddingAiHighlightsScreenState();
}
class _WeddingAiHighlightsScreenState extends State<WeddingAiHighlightsScreen>{
  bool loading=true,working=false,consent=false;
  String? error,jobId;
  List<Map<String,dynamic>> clips=[];
  List<Map<String,dynamic>> moments=[];
  @override
  void initState(){super.initState();load();}
  Future<void> load()async{
    try{
      final row=await supabase.from('wedding_editor_projects').select('timeline_json')
        .eq('project_id',widget.projectId).order('updated_at',ascending:false).limit(1).maybeSingle();
      final t=row?['timeline_json'];
      if(t is Map&&t['clips'] is List)clips=List<Map<String,dynamic>>.from((t['clips'] as List).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)));
    }catch(e){error='Could not load clips: $e';}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> analyse()async{
    if(!consent){setState(()=>error='Please confirm consent before sending sample frames to AI.');return;}
    final available=clips.where((c)=>c['path'] is String&&File(c['path'].toString()).existsSync()).take(6).toList();
    if(available.isEmpty){setState(()=>error='Add and save clips in your timeline first.');return;}
    setState((){working=true;error=null;moments=[];jobId=null;});
    try{
      final frames=<Map<String,dynamic>>[];
      for(var i=0;i<available.length;i++){
        final clip=available[i],path=clip['path'].toString();
        final video=EditorVideo.file(File(path));
        final metadata=await ProVideoEditor.instance.getMetadata(video:video);
        final duration=metadata.duration.inMilliseconds;
        if(duration<500)continue;
        final times=[(duration*.2).round(),(duration*.5).round(),(duration*.8).round()].toSet().toList();
        final thumbs=await ProVideoEditor.instance.getThumbnails(ThumbnailConfigs(
          video:video,outputFormat:ThumbnailFormat.jpeg,
          timestamps:times.map((ms)=>Duration(milliseconds:ms)).toList(),
          outputSize:const Size(320,180),boxFit:ThumbnailBoxFit.cover,
        ));
        for(var j=0;j<thumbs.length&&j<times.length;j++){
          frames.add({
            'clipIndex':i,'clipName':clip['name']?.toString()??'Wedding clip',
            'timestampMs':times[j],'clipDurationMs':duration,
            'imageBase64':base64Encode(thumbs[j]),
          });
        }
      }
      if(frames.length<3)throw Exception('Not enough video frames could be sampled.');
      final response=await supabase.functions.invoke('wedding-ai-highlights',body:{
        'projectId':widget.projectId,'frames':frames,
      });
      final data=response.data;
      if(response.status<200||response.status>=300||data is! Map||data['ok']!=true){
        throw Exception(data is Map?(data['error']??'AI analysis failed'):'AI analysis failed');
      }
      final suggested=data['suggestedTimeline'] is Map?Map<String,dynamic>.from(data['suggestedTimeline'] as Map):<String,dynamic>{};
      if(!mounted)return;
      setState(()=>{
        jobId=data['jobId']?.toString();
        moments=List<Map<String,dynamic>>.from((suggested['moments'] as List? ?? []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)));
      });
    }catch(e){if(mounted)setState(()=>error='AI highlight analysis failed: $e');}
    finally{if(mounted)setState(()=>working=false);}
  }
  Future<void> approve()async{
    if(jobId==null||moments.isEmpty)return;
    setState(()=>working=true);
    try{
      final selected=<Map<String,dynamic>>[];
      for(var i=0;i<moments.length;i++){
        final m=moments[i],idx=(m['clipIndex'] as num?)?.toInt()??-1;
        if(idx<0||idx>=clips.length)continue;
        final source=clips[idx],path=source['path']?.toString();
        if(path==null||!File(path).existsSync())continue;
        final duration=(m['clipDurationMs'] as num?)?.toInt()??0;
        final at=(m['timestampMs'] as num?)?.toInt()??0;
        final start=(at-2500).clamp(0,duration);
        final end=(at+3500).clamp(start+1,duration);
        if(end<=start)continue;
        selected.add({
          'id':'ai-$jobId-$i','name':'${source['name']} • ${m['label']}',
          'path':path,'sizeBytes':source['sizeBytes']??File(path).lengthSync(),
          'trimStartMs':start,'trimEndMs':end,'playbackSpeed':1.0,
          'aiReason':m['reason'],'aiLabel':m['label'],
        });
      }
      if(selected.isEmpty)throw Exception('No valid highlight segments to approve.');
      final row=await supabase.from('wedding_editor_projects').select('id,timeline_json')
        .eq('project_id',widget.projectId).order('updated_at',ascending:false).limit(1).maybeSingle();
      final timeline=row?['timeline_json'] is Map?Map<String,dynamic>.from(row!['timeline_json'] as Map):<String,dynamic>{};
      timeline['sourceClipsBeforeAi']=timeline['clips']??clips;
      timeline['clips']=selected;
      timeline['clipOrder']=selected.map((c)=>c['id']).toList();
      timeline['aiHighlightJobId']=jobId;
      timeline['aiHighlightsApprovedAt']=DateTime.now().toIso8601String();
      final user=supabase.auth.currentUser;
      if(user==null)throw Exception('Please sign in again.');
      if(row==null){
        await supabase.from('wedding_editor_projects').insert({'project_id':widget.projectId,'owner_customer_id':user.id,'name':'AI Wedding Highlights','timeline_json':timeline});
      }else{
        await supabase.from('wedding_editor_projects').update({'timeline_json':timeline,'updated_at':DateTime.now().toIso8601String()}).eq('id',row['id']);
      }
      await supabase.from('wedding_ai_highlight_jobs').update({'status':'approved','customer_approved_at':DateTime.now().toIso8601String(),'updated_at':DateTime.now().toIso8601String()}).eq('id',jobId!);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('AI highlights approved and saved to the editable timeline.')));
      if(mounted)Navigator.pop(context);
    }catch(e){if(mounted)setState(()=>error='Could not approve highlights: $e');}
    finally{if(mounted)setState(()=>working=false);}
  }
  Future<void> reject()async{
    if(jobId==null)return;
    setState(()=>working=true);
    try{await supabase.from('wedding_ai_highlight_jobs').update({'status':'rejected','updated_at':DateTime.now().toIso8601String()}).eq('id',jobId!);if(mounted)setState(()=>{moments=[];jobId=null;});}
    catch(e){if(mounted)setState(()=>error='Could not reject suggestions: $e');}
    finally{if(mounted)setState(()=>working=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('AI Wedding Highlights')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      const Chip(label:Text('Development Mode')),
      const Text('AI checks sampled still frames from your saved video clips and suggests highlight moments. It does not upload the full videos or analyse audio.'),
      CheckboxListTile(
        value:consent,
        onChanged:working?null:(v)=>setState(()=>consent=v??false),
        title:const Text('I consent to send selected sample frames to the AI provider for visual analysis.'),
        controlAffinity:ListTileControlAffinity.leading,
        contentPadding:EdgeInsets.zero,
      ),
      Text('Saved clips: ${clips.length} • Up to six clips and three sample frames per clip will be analysed.'),
      FilledButton.icon(onPressed:working?null:analyse,icon:const Icon(Icons.auto_awesome),label:Text(working?'Analysing…':'Analyse wedding highlights')),
      if(working)const LinearProgressIndicator(),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:const TextStyle(color:Colors.red))),
      if(moments.isNotEmpty)...[
        const SizedBox(height:18),const Text('Suggested moments • Review before approval',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
        ...moments.map((m)=>Card(child:ListTile(
          leading:const Icon(Icons.movie_filter_outlined),
          title:Text(m['label']?.toString()??'Wedding highlight'),
          subtitle:Text('${m['clipName']??''} • ${((m['timestampMs'] as num?)?.toInt()??0)/1000}s\n${m['reason']??''}'),
        ))),
        FilledButton.icon(onPressed:working?null:approve,icon:const Icon(Icons.check_circle_outline),label:const Text('Approve and add to timeline')),
        TextButton.icon(onPressed:working?null:reject,icon:const Icon(Icons.close),label:const Text('Reject suggestions')),
      ],
    ]),
  );
}
