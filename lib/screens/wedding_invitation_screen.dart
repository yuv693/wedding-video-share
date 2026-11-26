import 'package:flutter/material.dart';
import '../services/backend.dart';

class WeddingInvitationScreen extends StatefulWidget {
  const WeddingInvitationScreen({super.key});
  @override
  State<WeddingInvitationScreen> createState()=>_WeddingInvitationScreenState();
}
class _WeddingInvitationScreenState extends State<WeddingInvitationScreen>{
  bool loading=true,saving=false;
  String? error;
  List<Map<String,dynamic>> projects=[],invitations=[];
  @override
  void initState(){super.initState();load();}
  Future<void> load() async{
    try{
      final p=await supabase.from('wedding_projects').select('id,title').order('created_at',ascending:false);
      final rows=await supabase.from('digital_wedding_invitations').select('id,project_id,title,template_key,event_details,rsvp_enabled,published_at,created_at').order('created_at',ascending:false);
      if(!mounted)return;
      setState(()=>{projects=List<Map<String,dynamic>>.from(p),invitations=List<Map<String,dynamic>>.from(rows)});
    }catch(e){error='Could not load invitations: $e';}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> createInvitation() async{
    if(projects.isEmpty){setState(()=>error='Pehle Wedding Studio mein project banayein.');return;}
    final title=TextEditingController(text:'Wedding Invitation');
    final bride=TextEditingController(),groom=TextEditingController(),venue=TextEditingController(),date=TextEditingController(),contact=TextEditingController(),map=TextEditingController();
    String projectId=projects.first['id'].toString(),template='classic_floral';
    bool rsvp=false;
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(
      title:const Text('Create digital invitation'),
      content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:title,decoration:const InputDecoration(labelText:'Invitation title')),
        DropdownButtonFormField<String>(value:projectId,decoration:const InputDecoration(labelText:'Wedding project'),items:projects.map((p)=>DropdownMenuItem<String>(value:p['id'].toString(),child:Text(p['title'].toString()))).toList(),onChanged:(v){if(v!=null)refresh(()=>projectId=v);}),
        DropdownButtonFormField<String>(value:template,decoration:const InputDecoration(labelText:'Design template'),items:const [
          DropdownMenuItem(value:'classic_floral',child:Text('Classic floral')),
          DropdownMenuItem(value:'royal',child:Text('Royal')),
          DropdownMenuItem(value:'minimal',child:Text('Minimal')),
          DropdownMenuItem(value:'traditional',child:Text('Traditional')),
        ],onChanged:(v){if(v!=null)refresh(()=>template=v);}),
        TextField(controller:bride,decoration:const InputDecoration(labelText:'Bride name')),
        TextField(controller:groom,decoration:const InputDecoration(labelText:'Groom name')),
        TextField(controller:date,decoration:const InputDecoration(labelText:'Event date and time')),
        TextField(controller:venue,decoration:const InputDecoration(labelText:'Venue')),
        TextField(controller:map,decoration:const InputDecoration(labelText:'Map link (optional)')),
        TextField(controller:contact,decoration:const InputDecoration(labelText:'RSVP contact (optional)')),
        SwitchListTile(value:rsvp,title:const Text('Enable RSVP field'),contentPadding:EdgeInsets.zero,onChanged:(v)=>refresh(()=>rsvp=v)),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save draft'))],
    )));
    if(ok!=true){for(final c in [title,bride,groom,venue,date,contact,map]){c.dispose();}return;}
    setState(()=>saving=true);
    try{
      final user=supabase.auth.currentUser;if(user==null)throw Exception('Please sign in again.');
      await supabase.from('digital_wedding_invitations').insert({
        'project_id':projectId,'owner_customer_id':user.id,'title':title.text.trim().isEmpty?'Wedding Invitation':title.text.trim(),
        'template_key':template,'rsvp_enabled':rsvp,
        'event_details':{'bride':bride.text.trim(),'groom':groom.text.trim(),'date_time':date.text.trim(),'venue':venue.text.trim(),'map_link':map.text.trim(),'rsvp_contact':contact.text.trim()},
      });
      await load();
    }catch(e){if(mounted)setState(()=>error='Save failed: $e');}
    finally{for(final c in [title,bride,groom,venue,date,contact,map]){c.dispose();}if(mounted)setState(()=>saving=false);}
  }
  Future<void> toggleRsvp(Map<String,dynamic> row,bool value)async{
    try{await supabase.from('digital_wedding_invitations').update({'rsvp_enabled':value,'updated_at':DateTime.now().toIso8601String()}).eq('id',row['id']);await load();}
    catch(e){if(mounted)setState(()=>error='Could not update RSVP: $e');}
  }
  Future<void> deleteDraft(Map<String,dynamic> row)async{
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Delete invitation draft?'),content:const Text('This only deletes this invitation draft; wedding photos and videos are untouched.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Delete'))]));
    if(ok!=true)return;
    try{await supabase.from('digital_wedding_invitations').delete().eq('id',row['id']);await load();}
    catch(e){if(mounted)setState(()=>error='Delete failed: $e');}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Digital Wedding Invitations')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      const Chip(label:Text('Development Mode')),
      const Text('Create and save invitation drafts with event details, design templates and RSVP settings. Public guest links and live RSVP collection are not enabled yet.'),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:saving?null:createInvitation,icon:const Icon(Icons.add),label:Text(saving?'Saving…':'Create invitation draft')),
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
      if(invitations.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('No invitation drafts yet.'))),
      ...invitations.map((row){
        final details=row['event_details'] is Map?Map<String,dynamic>.from(row['event_details'] as Map):<String,dynamic>{};
        return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(row['title'].toString(),style:Theme.of(context).textTheme.titleMedium),
          Text('Template: ${row['template_key']} • Draft'),
          if((details['bride']??'').toString().isNotEmpty||(details['groom']??'').toString().isNotEmpty)Text('${details['bride']??''} & ${details['groom']??''}'),
          if((details['date_time']??'').toString().isNotEmpty)Text('Date: ${details['date_time']}'),
          if((details['venue']??'').toString().isNotEmpty)Text('Venue: ${details['venue']}'),
          SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('RSVP enabled (draft setting)'),value:row['rsvp_enabled']==true,onChanged:(v)=>toggleRsvp(row,v)),
          Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:()=>deleteDraft(row),icon:const Icon(Icons.delete_outline),label:const Text('Delete draft'))),
        ])));
      }),
    ]),
  );
}