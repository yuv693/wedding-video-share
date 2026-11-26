import 'package:flutter/material.dart';
import '../services/backend.dart';

class WeddingSupportScreen extends StatefulWidget {
  const WeddingSupportScreen({super.key,this.projectId});
  final String? projectId;
  @override
  State<WeddingSupportScreen> createState()=>_WeddingSupportScreenState();
}
class _WeddingSupportScreenState extends State<WeddingSupportScreen>{
  bool loading=true,saving=false;
  String? error;
  List<Map<String,dynamic>> tickets=[];
  @override
  void initState(){super.initState();load();}
  Future<void> load()async{
    try{
      final user=supabase.auth.currentUser;if(user==null)throw Exception('Please sign in again.');
      final rows=await supabase.from('wedding_support_tickets').select('id,subject,message,status,admin_response,created_at,updated_at')
        .eq('owner_customer_id',user.id).order('created_at',ascending:false).limit(100);
      if(mounted)setState(()=>tickets=List<Map<String,dynamic>>.from(rows));
    }catch(e){if(mounted)setState(()=>error='Could not load support requests: $e');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> createTicket()async{
    final subject=TextEditingController(),message=TextEditingController();
    final key=GlobalKey<FormState>();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Contact Wedding Studio support'),
      content:Form(key:key,child:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(controller:subject,maxLength:120,decoration:const InputDecoration(labelText:'Subject'),validator:(v)=>v==null||v.trim().length<3?'Enter a subject':null),
        TextFormField(controller:message,minLines:4,maxLines:8,maxLength:3000,decoration:const InputDecoration(labelText:'Describe the issue'),validator:(v)=>v==null||v.trim().length<5?'Please add more detail':null),
      ])))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,key.currentState!.validate()),child:const Text('Send request'))],
    ));
    if(ok==true){
      setState(()=>saving=true);
      try{
        final user=supabase.auth.currentUser;if(user==null)throw Exception('Please sign in again.');
        await supabase.from('wedding_support_tickets').insert({
          'owner_customer_id':user.id,'project_id':widget.projectId,
          'subject':subject.text.trim(),'message':message.text.trim(),
        });
        await load();
      }catch(e){if(mounted)setState(()=>error='Could not send request: $e');}
      finally{if(mounted)setState(()=>saving=false);}
    }
    subject.dispose();message.dispose();
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Wedding Studio Support'),actions:[IconButton(onPressed:loading?null:load,icon:const Icon(Icons.refresh))]),
    floatingActionButton:FloatingActionButton.extended(onPressed:saving?null:createTicket,icon:const Icon(Icons.add),label:const Text('New request')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      const Chip(label:Text('Development Mode')),
      const Text('Send a support request and track the reply from the Wedding Studio team.'),
      if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!,style:const TextStyle(color:Colors.red))),
      if(tickets.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(18),child:Text('No support requests yet.'))),
      ...tickets.map((t)=>Card(child:ExpansionTile(
        title:Text(t['subject']?.toString()??'Support request'),
        subtitle:Text('Status: ${t['status']??'open'} • ${t['created_at']??''}'),
        childrenPadding:const EdgeInsets.fromLTRB(16,0,16,16),
        children:[
          Align(alignment:Alignment.centerLeft,child:Text(t['message']?.toString()??'')),
          if((t['admin_response']??'').toString().isNotEmpty)...[
            const Divider(),const Align(alignment:Alignment.centerLeft,child:Text('Support reply',style:TextStyle(fontWeight:FontWeight.bold))),
            Align(alignment:Alignment.centerLeft,child:Text(t['admin_response'].toString())),
          ],
        ],
      ))),
    ]),
  );
}
