import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class WeddingInstagramHandoffScreen extends StatefulWidget {
  const WeddingInstagramHandoffScreen({super.key});
  @override
  State<WeddingInstagramHandoffScreen> createState()=>_WeddingInstagramHandoffScreenState();
}
class _WeddingInstagramHandoffScreenState extends State<WeddingInstagramHandoffScreen>{
  bool loading=true;
  List<File> reels=[];
  @override
  void initState(){super.initState();load();}
  Future<void> load()async{
    try{
      final dir=await getApplicationDocumentsDirectory();
      final entries=await dir.list().toList();
      reels=entries.whereType<File>().where((e)=>e.path.split('/').last.startsWith('wedding-reel-')&&e.path.endsWith('.mp4')).toList();
      reels.sort((a,b)=>b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    }finally{if(mounted)setState(()=>loading=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Instagram Reels')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      const Chip(label:Text('Development Mode')),
      const Text('Share an exported 9:16 reel to Instagram using Android’s share sheet. Direct in-app publishing is not enabled yet.'),
      const SizedBox(height:12),
      const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Direct publishing requires a Meta developer app, Instagram Business/Creator account authorization, approved publishing permissions and app review. Never enter your Instagram password here.'))),
      if(reels.isEmpty)const Text('No exported reels found on this device. Create a 9:16 reel from a wedding project first.'),
      ...reels.map((file)=>Card(child:ListTile(
        leading:const Icon(Icons.video_library_outlined),
        title:Text(file.path.split('/').last),
        subtitle:Text('${(file.lengthSync()/1024/1024).toStringAsFixed(1)} MB'),
        trailing:IconButton(icon:const Icon(Icons.share),onPressed:()=>Share.shareXFiles([XFile(file.path)],text:'Wedding Reel')),
      ))),
    ]),
  );
}
