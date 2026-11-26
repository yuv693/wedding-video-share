import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/backend.dart';

class WeddingQrAlbumScreen extends StatefulWidget {
  const WeddingQrAlbumScreen({super.key});
  @override
  State<WeddingQrAlbumScreen> createState() => _WeddingQrAlbumScreenState();
}
class _WeddingQrAlbumScreenState extends State<WeddingQrAlbumScreen> {
  bool loading=true, saving=false;
  String? error;
  List<Map<String,dynamic>> projects=[], albums=[];
  @override
  void initState(){super.initState();load();}
  Future<void> load() async {
    try {
      final p=await supabase.from('wedding_projects').select('id,title').order('created_at',ascending:false);
      final a=await supabase.from('wedding_albums').select('id,title,guest_uploads_enabled,guest_view_enabled,downloads_enabled,revoked_at,created_at').order('created_at',ascending:false);
      if(!mounted)return;
      setState(() { projects=List<Map<String,dynamic>>.from(p); albums=List<Map<String,dynamic>>.from(a); });
    } catch(e){error='Could not load albums: $e';}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> createAlbum() async {
    if(projects.isEmpty){setState(()=>error='Pehle Wedding Studio project banayein.');return;}
    final name=TextEditingController(text:'Wedding Album');
    String projectId=projects.first['id'].toString();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(
      title:const Text('Create wedding album'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Album name')),
        DropdownButtonFormField<String>(value:projectId,decoration:const InputDecoration(labelText:'Project'),
          items:projects.map((p)=>DropdownMenuItem<String>(value:p['id'].toString(),child:Text(p['title'].toString()))).toList(),
          onChanged:(v){if(v!=null)refresh(()=>projectId=v);}),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Create'))],
    )));
    if(ok!=true||name.text.trim().isEmpty){name.dispose();return;}
    setState(()=>saving=true);
    try{
      final user=supabase.auth.currentUser;
      if(user==null)throw Exception('Please sign in again.');
      await supabase.from('wedding_albums').insert({'project_id':projectId,'owner_customer_id':user.id,'title':name.text.trim(),'guest_uploads_enabled':false,'guest_view_enabled':true,'downloads_enabled':false});
      await load();
    }catch(e){if(mounted)setState(()=>error='Create failed: $e');}
    finally{name.dispose();if(mounted)setState(()=>saving=false);}
  }
  Future<void> setPermission(Map<String,dynamic> a,String field,bool value) async {
    try{await supabase.from('wedding_albums').update({field:value,'updated_at':DateTime.now().toIso8601String()}).eq('id',a['id']);await load();}
    catch(e){if(mounted)setState(()=>error='Update failed: $e');}
  }
  Future<void> revoke(Map<String,dynamic> a) async {
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Revoke access?'),content:const Text('Guest access will be disabled. Original Drive files are not deleted.'),actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Revoke'))]));
    if(ok!=true)return;
    try{await supabase.from('wedding_albums').update({'revoked_at':DateTime.now().toIso8601String(),'guest_uploads_enabled':false,'guest_view_enabled':false}).eq('id',a['id']);await load();}
    catch(e){if(mounted)setState(()=>error='Revoke failed: $e');}
  }
  void showQr(Map<String,dynamic> a){
    final value='weddingvideoshare://album/'+a['id'].toString();
    showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text(a['title'].toString()),content:Column(mainAxisSize:MainAxisSize.min,children:[
      QrImageView(data:value,size:210),
      const Text('Development QR only. Secure guest upload/view webpage is not deployed yet.',textAlign:TextAlign.center),
      SelectableText(value)]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))]));
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('QR Wedding Album')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      const Chip(label:Text('Development Mode')),
      const Text('Create albums and manage owner-side guest permissions. Media originals remain in customer Google Drive.'),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:saving?null:createAlbum,icon:const Icon(Icons.add),label:const Text('Create wedding album')),
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
      if(albums.isEmpty)const Text('No albums created yet.'),
      ...albums.map((a){
        final revoked=a['revoked_at']!=null;
        return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(a['title'].toString(),style:Theme.of(context).textTheme.titleMedium),
          Text(revoked?'Access revoked':'Album active'),
          SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Guest viewing'),value:a['guest_view_enabled']==true&&!revoked,onChanged:revoked?null:(v)=>setPermission(a,'guest_view_enabled',v)),
          SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Guest uploads'),value:a['guest_uploads_enabled']==true&&!revoked,onChanged:revoked?null:(v)=>setPermission(a,'guest_uploads_enabled',v)),
          SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Guest downloads'),value:a['downloads_enabled']==true&&!revoked,onChanged:revoked?null:(v)=>setPermission(a,'downloads_enabled',v)),
          Wrap(spacing:8,children:[OutlinedButton.icon(onPressed:()=>showQr(a),icon:const Icon(Icons.qr_code),label:const Text('Show QR')),if(!revoked)TextButton.icon(onPressed:()=>revoke(a),icon:const Icon(Icons.block),label:const Text('Revoke'))])
        ])));
      })
    ]));
}