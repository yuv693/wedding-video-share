import 'package:flutter/material.dart';
import '../services/backend.dart';

class PhotographerStudioPortalScreen extends StatefulWidget{
  const PhotographerStudioPortalScreen({super.key});
  @override
  State<PhotographerStudioPortalScreen> createState()=>_PhotographerStudioPortalScreenState();
}
class _PhotographerStudioPortalScreenState extends State<PhotographerStudioPortalScreen>{
  final name=TextEditingController(),email=TextEditingController(),phone=TextEditingController(),website=TextEditingController();
  bool loading=true,saving=false;
  String? error,studioId;
  List<Map<String,dynamic>> projects=[];
  @override
  void initState(){super.initState();load();}
  @override
  void dispose(){name.dispose();email.dispose();phone.dispose();website.dispose();super.dispose();}
  Future<void> load()async{
    try{
      final profile=await supabase.from('photographer_studios').select('id,studio_name,contact_email,contact_phone,website_url').maybeSingle();
      final rows=await supabase.from('wedding_projects').select('id,title,studio_id,status').order('created_at',ascending:false);
      if(!mounted)return;
      if(profile!=null){studioId=profile['id'].toString();name.text=profile['studio_name']?.toString()??'';email.text=profile['contact_email']?.toString()??'';phone.text=profile['contact_phone']?.toString()??'';website.text=profile['website_url']?.toString()??'';}
      setState(()=>projects=List<Map<String,dynamic>>.from(rows));
    }catch(e){error='Could not load studio portal: $e';}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> saveProfile()async{
    if(name.text.trim().isEmpty){setState(()=>error='Studio name is required.');return;}
    setState(()=>saving=true);
    try{
      final user=supabase.auth.currentUser;if(user==null)throw Exception('Please sign in again.');
      final result=await supabase.from('photographer_studios').upsert({
        'owner_customer_id':user.id,'studio_name':name.text.trim(),
        'contact_email':email.text.trim().isEmpty?null:email.text.trim(),
        'contact_phone':phone.text.trim().isEmpty?null:phone.text.trim(),
        'website_url':website.text.trim().isEmpty?null:website.text.trim(),
        'updated_at':DateTime.now().toIso8601String(),
      },onConflict:'owner_customer_id').select('id').single();
      studioId=result['id'].toString();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Studio profile saved.')));
      await load();
    }catch(e){if(mounted)setState(()=>error='Save failed: $e');}
    finally{if(mounted)setState(()=>saving=false);}
  }
  Future<void> assignProject(Map<String,dynamic> project,bool attach)async{
    if(studioId==null){setState(()=>error='Save your studio profile first.');return;}
    try{
      await supabase.from('wedding_projects').update({'studio_id':attach?studioId:null,'updated_at':DateTime.now().toIso8601String()}).eq('id',project['id']);
      await load();
    }catch(e){if(mounted)setState(()=>error='Project assignment failed: $e');}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Photographer Studio Portal')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      const Chip(label:Text('Development Mode')),
      const Text('Set up your studio profile and connect wedding projects. This is a private owner portal; customer invitations and guest access are not published.'),
      const SizedBox(height:12),
      TextField(controller:name,decoration:const InputDecoration(labelText:'Studio / photographer name',border:OutlineInputBorder())),
      const SizedBox(height:10),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Contact email',border:OutlineInputBorder())),
      const SizedBox(height:10),
      TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Contact phone',border:OutlineInputBorder())),
      const SizedBox(height:10),
      TextField(controller:website,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'Website (optional)',border:OutlineInputBorder())),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:saving?null:saveProfile,icon:const Icon(Icons.save_outlined),label:Text(saving?'Saving…':'Save studio profile')),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(error!,style:const TextStyle(color:Colors.red))),
      const SizedBox(height:18),
      Text('Wedding projects',style:Theme.of(context).textTheme.titleLarge),
      if(projects.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Create a wedding project in Wedding Studio to manage it here.'))),
      ...projects.map((p){
        final attached=p['studio_id']!=null&&p['studio_id'].toString()==studioId;
        return Card(child:ListTile(
          leading:const Icon(Icons.favorite_outline),
          title:Text(p['title'].toString()),
          subtitle:Text('Status: ${p['status']??'active'}'),
          trailing:TextButton(onPressed:()=>assignProject(p,!attached),child:Text(attached?'Remove':'Add to studio')),
        ));
      }),
    ]),
  );
}