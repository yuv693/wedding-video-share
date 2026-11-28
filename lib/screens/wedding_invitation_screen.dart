import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
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
      final user=supabase.auth.currentUser;
      if(user==null) throw Exception('Please sign in again.');
      final p=await supabase.from('wedding_projects').select('id,title').eq('owner_customer_id',user.id).order('created_at',ascending:false);
      final rows=await supabase.from('digital_wedding_invitations').select('id,project_id,title,template_key,event_details,rsvp_enabled,published_at,public_slug,created_at').order('created_at',ascending:false);
      if(!mounted)return;
      setState(() { projects=List<Map<String,dynamic>>.from(p); invitations=List<Map<String,dynamic>>.from(rows); });
    }catch(e){error='Could not load invitations: $e';}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> createInvitation() async{
    if(projects.isEmpty){setState(()=>error='Pehle Wedding Studio mein project banayein.');return;}
    final title=TextEditingController(text:'Wedding Invitation');
    final bride=TextEditingController(),groom=TextEditingController(),venue=TextEditingController(),address=TextEditingController(),date=TextEditingController(),functionName=TextEditingController(),contact=TextEditingController(),map=TextEditingController();
    String projectId=projects.first['id'].toString(),template='hindu_traditional',community='Hindu',presentationStyle='classic_card',language='gu';
    final hosts=TextEditingController(),message=TextEditingController(),optionalWording=TextEditingController();
    bool rsvp=false;
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(
      title:const Text('Create digital invitation'),
      content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:title,decoration:const InputDecoration(labelText:'Invitation title')),
        DropdownButtonFormField<String>(value:projectId,decoration:const InputDecoration(labelText:'Wedding project'),items:projects.map((p)=>DropdownMenuItem<String>(value:p['id'].toString(),child:Text(p['title'].toString()))).toList(),onChanged:(v){if(v!=null)refresh(()=>projectId=v);}),
        DropdownButtonFormField<String>(value:community,decoration:const InputDecoration(labelText:'Community / tradition'),items:const [
          DropdownMenuItem(value:'Hindu',child:Text('Hindu')),
          DropdownMenuItem(value:'Muslim',child:Text('Muslim')),
          DropdownMenuItem(value:'Sikh',child:Text('Sikh')),
          DropdownMenuItem(value:'Christian',child:Text('Christian')),
          DropdownMenuItem(value:'Jain',child:Text('Jain')),
          DropdownMenuItem(value:'Buddhist',child:Text('Buddhist')),
          DropdownMenuItem(value:'Parsi',child:Text('Parsi')),
          DropdownMenuItem(value:'Other',child:Text('Other / Custom')),
        ],onChanged:(v){if(v!=null)refresh((){community=v;template=switch(v){'Hindu'=>'hindu_traditional','Muslim'=>'muslim_nikah','Sikh'=>'sikh_anand_karaj','Christian'=>'christian_classic','Jain'=>'jain_traditional','Buddhist'=>'buddhist_traditional','Parsi'=>'parsi_traditional',_=>'custom_minimal'};});}),
        DropdownButtonFormField<String>(value:template,decoration:const InputDecoration(labelText:'Invitation design'),items:const [
          DropdownMenuItem(value:'hindu_traditional',child:Text('Hindu traditional')),
          DropdownMenuItem(value:'muslim_nikah',child:Text('Muslim Nikah')),
          DropdownMenuItem(value:'muslim_walima',child:Text('Muslim Walima')),
          DropdownMenuItem(value:'sikh_anand_karaj',child:Text('Sikh Anand Karaj')),
          DropdownMenuItem(value:'christian_classic',child:Text('Christian classic')),
          DropdownMenuItem(value:'jain_traditional',child:Text('Jain traditional')),
          DropdownMenuItem(value:'buddhist_traditional',child:Text('Buddhist traditional')),
          DropdownMenuItem(value:'parsi_traditional',child:Text('Parsi traditional')),
          DropdownMenuItem(value:'custom_minimal',child:Text('Simple / Custom')),
          DropdownMenuItem(value:'modern_editorial',child:Text('Modern Editorial 2027')),
        ],onChanged:(v){if(v!=null)refresh(()=>template=v);}),
        DropdownButtonFormField<String>(value:language,decoration:const InputDecoration(labelText:'Invitation language'),items:const [DropdownMenuItem(value:'gu',child:Text('Gujarati')),DropdownMenuItem(value:'hi',child:Text('Hindi')),DropdownMenuItem(value:'ur',child:Text('Urdu')),DropdownMenuItem(value:'en',child:Text('English'))],onChanged:(v){if(v!=null)refresh(()=>language=v);}),
        DropdownButtonFormField<String>(value:presentationStyle,decoration:const InputDecoration(labelText:'Invitation format'),items:const [
          DropdownMenuItem(value:'classic_card',child:Text('Classic digital card')),
          DropdownMenuItem(value:'scrolling_webpage',child:Text('Scrolling invitation webpage')),
          DropdownMenuItem(value:'cinematic_animated',child:Text('Animated cinematic webpage')),
        ],onChanged:(v){if(v!=null)refresh(()=>presentationStyle=v);}),
        TextField(controller:bride,decoration:const InputDecoration(labelText:'Bride name')),
        TextField(controller:groom,decoration:const InputDecoration(labelText:'Groom name')),
        TextField(controller:functionName,decoration:const InputDecoration(labelText:'Function name (e.g. Nikah, Haldi, Reception)')),
        TextField(controller:date,decoration:const InputDecoration(labelText:'Function date and time')),
        TextField(controller:venue,decoration:const InputDecoration(labelText:'Venue / hall name')),
        TextField(controller:address,decoration:const InputDecoration(labelText:'Full address / area / city')),
        TextField(controller:map,decoration:const InputDecoration(labelText:'Map link (optional)')),
        TextField(controller:contact,decoration:const InputDecoration(labelText:'RSVP contact (optional)')),
        TextField(controller:hosts,decoration:const InputDecoration(labelText:'Family / hosts (optional)')),
        TextField(controller:message,decoration:const InputDecoration(labelText:'Personal message (optional)'),maxLines:3),
        TextField(controller:optionalWording,decoration:const InputDecoration(labelText:'Optional religious / blessing wording (your choice)'),maxLines:2),
        SwitchListTile(value:rsvp,title:const Text('Enable RSVP field'),contentPadding:EdgeInsets.zero,onChanged:(v)=>refresh(()=>rsvp=v)),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save draft'))],
    )));
    if(ok!=true){for(final c in [title,bride,groom,venue,address,date,functionName,contact,map]){c.dispose();}return;}
    setState(()=>saving=true);
    try{
      final user=supabase.auth.currentUser;if(user==null)throw Exception('Please sign in again.');
      await supabase.from('digital_wedding_invitations').insert({
        'project_id':projectId,'owner_customer_id':user.id,'title':title.text.trim().isEmpty?'Wedding Invitation':title.text.trim(),
        'template_key':template,'rsvp_enabled':rsvp,
        'event_details':{'presentation_style':presentationStyle,'community':community,'language':language,'family_hosts':hosts.text.trim(),'custom_message':message.text.trim(),'optional_religious_wording':optionalWording.text.trim(),'bride':bride.text.trim(),'groom':groom.text.trim(),'function_name':functionName.text.trim(),'date_time':date.text.trim(),'venue':venue.text.trim(),'address':address.text.trim(),'map_link':map.text.trim(),'rsvp_contact':contact.text.trim(),'functions':[{'name':functionName.text.trim(),'date_time':date.text.trim(),'venue':venue.text.trim(),'address':address.text.trim()}]},
      });
      await load();
    }catch(e){if(mounted)setState(()=>error='Save failed: $e');}
    finally{for(final c in [title,bride,groom,venue,address,date,functionName,contact,map,hosts,message,optionalWording]){c.dispose();}if(mounted)setState(()=>saving=false);}
  }
  Future<void> editInvitation(Map<String,dynamic> row) async {
    final details = row['event_details'] is Map
        ? Map<String,dynamic>.from(row['event_details'] as Map)
        : <String,dynamic>{};
    final title = TextEditingController(text: row['title']?.toString() ?? '');
    final bride = TextEditingController(text: details['bride']?.toString() ?? '');
    final groom = TextEditingController(text: details['groom']?.toString() ?? '');
    final date = TextEditingController(text: details['date_time']?.toString() ?? '');
    final venue = TextEditingController(text: details['venue']?.toString() ?? '');
    final address = TextEditingController(text: details['address']?.toString() ?? '');
    final functionName = TextEditingController(text: details['function_name']?.toString() ?? '');
    String community = details['community']?.toString() ?? 'Other';
    final map = TextEditingController(text: details['map_link']?.toString() ?? '');
    final contact = TextEditingController(text: details['rsvp_contact']?.toString() ?? '');
    final hosts = TextEditingController(text: details['family_hosts']?.toString() ?? '');
    final message = TextEditingController(text: details['custom_message']?.toString() ?? '');
    final optionalWording = TextEditingController(text: details['optional_religious_wording']?.toString() ?? '');
    String language = details['language']?.toString() ?? 'gu';
    String template = row['template_key']?.toString() ?? 'hindu_traditional';
    String presentationStyle = details['presentation_style']?.toString() ?? 'classic_card';
    bool rsvp = row['rsvp_enabled'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('Edit invitation draft'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Invitation title')),
                DropdownButtonFormField<String>(
                  value: community,
                  decoration: const InputDecoration(labelText: 'Community / tradition'),
                  items: const ['Hindu','Muslim','Sikh','Christian','Jain','Buddhist','Parsi','Other'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) { if (v != null) refresh(() { community = v; }); },
                ),
                DropdownButtonFormField<String>(
                  value: template,
                  decoration: const InputDecoration(labelText: 'Design template'),
                  items: const [
                    DropdownMenuItem(value: 'hindu_traditional', child: Text('Hindu traditional')),
                    DropdownMenuItem(value: 'muslim_nikah', child: Text('Muslim Nikah')),
                    DropdownMenuItem(value: 'muslim_walima', child: Text('Muslim Walima')),
                    DropdownMenuItem(value: 'sikh_anand_karaj', child: Text('Sikh Anand Karaj')),
                    DropdownMenuItem(value: 'christian_classic', child: Text('Christian classic')),
                    DropdownMenuItem(value: 'jain_traditional', child: Text('Jain traditional')),
                    DropdownMenuItem(value: 'buddhist_traditional', child: Text('Buddhist traditional')),
                    DropdownMenuItem(value: 'parsi_traditional', child: Text('Parsi traditional')),
                    DropdownMenuItem(value: 'custom_minimal', child: Text('Simple / Custom')),
                    DropdownMenuItem(value: 'modern_editorial', child: Text('Modern Editorial 2027')),
                  ],
                  onChanged: (v) { if (v != null) refresh(() => template = v); },
                ),
                DropdownButtonFormField<String>(
                  value: language,
                  decoration: const InputDecoration(labelText: 'Invitation language'),
                  items: const [DropdownMenuItem(value:'gu',child:Text('Gujarati')),DropdownMenuItem(value:'hi',child:Text('Hindi')),DropdownMenuItem(value:'ur',child:Text('Urdu')),DropdownMenuItem(value:'en',child:Text('English'))],
                  onChanged: (v) { if (v != null) refresh(() => language = v); },
                ),
                DropdownButtonFormField<String>(
                  value: presentationStyle,
                  decoration: const InputDecoration(labelText: 'Invitation format'),
                  items: const [
                    DropdownMenuItem(value: 'classic_card', child: Text('Classic digital card')),
                    DropdownMenuItem(value: 'scrolling_webpage', child: Text('Scrolling invitation webpage')),
                    DropdownMenuItem(value: 'cinematic_animated', child: Text('Animated cinematic webpage')),
                  ],
                  onChanged: (v) { if (v != null) refresh(() => presentationStyle = v); },
                ),
                TextField(controller: bride, decoration: const InputDecoration(labelText: 'Bride name')),
                TextField(controller: groom, decoration: const InputDecoration(labelText: 'Groom name')),
                TextField(controller: functionName, decoration: const InputDecoration(labelText: 'Function name')),
                TextField(controller: date, decoration: const InputDecoration(labelText: 'Function date and time')),
                TextField(controller: venue, decoration: const InputDecoration(labelText: 'Venue / hall name')),
                TextField(controller: address, decoration: const InputDecoration(labelText: 'Full address / area / city')),
                TextField(controller: map, decoration: const InputDecoration(labelText: 'Map link (optional)')),
                TextField(controller: contact, decoration: const InputDecoration(labelText: 'RSVP contact (optional)')),
                TextField(controller: hosts, decoration: const InputDecoration(labelText: 'Family / hosts (optional)')),
                TextField(controller: message, decoration: const InputDecoration(labelText: 'Personal message (optional)'), maxLines: 3),
                TextField(controller: optionalWording, decoration: const InputDecoration(labelText: 'Optional religious / blessing wording (your choice)'), maxLines: 2),
                SwitchListTile(
                  value: rsvp,
                  title: const Text('Enable RSVP (draft setting)'),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => refresh(() => rsvp = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save changes')),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() => saving = true);
      try {
        await supabase.from('digital_wedding_invitations').update({
          'title': title.text.trim().isEmpty ? 'Wedding Invitation' : title.text.trim(),
          'template_key': template,
          'rsvp_enabled': rsvp,
          'event_details': {
            'presentation_style': presentationStyle,
            'community': community,
            'language': language,
            'family_hosts': hosts.text.trim(),
            'custom_message': message.text.trim(),
            'optional_religious_wording': optionalWording.text.trim(),
            'bride': bride.text.trim(),
            'groom': groom.text.trim(),
            'function_name': functionName.text.trim(),
            'date_time': date.text.trim(),
            'venue': venue.text.trim(),
            'address': address.text.trim(),
            'functions': [{'name': functionName.text.trim(), 'date_time': date.text.trim(), 'venue': venue.text.trim(), 'address': address.text.trim()}],
            'map_link': map.text.trim(),
            'rsvp_contact': contact.text.trim(),
          },
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', row['id']);
        await load();
      } catch (e) {
        if (mounted) setState(() => error = 'Could not update invitation: $e');
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }
    for (final c in [title, bride, groom, date, venue, address, functionName, map, contact, hosts, message, optionalWording]) {
      c.dispose();
    }
  }

  Future<void> publishInvitation(Map<String,dynamic> row) async {
    setState(() => saving = true);
    try {
      final response = await supabase.functions.invoke(
        'wedding-invitation-public',
        body: {'action': 'publish', 'invitationId': row['id']},
      );
      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map || data['ok'] != true) {
        throw Exception(data is Map ? (data['error'] ?? 'Publish failed') : 'Publish failed');
      }
      final link = data['publicUrl']?.toString() ?? '';
      await load();
      if (link.isNotEmpty && mounted) {
        await Share.share(link, subject: 'Wedding invitation');
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Could not publish invitation: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> unpublishInvitation(Map<String,dynamic> row) async {
    setState(() => saving = true);
    try {
      final response = await supabase.functions.invoke(
        'wedding-invitation-public',
        body: {'action': 'unpublish', 'invitationId': row['id']},
      );
      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map || data['ok'] != true) {
        throw Exception(data is Map ? (data['error'] ?? 'Unpublish failed') : 'Unpublish failed');
      }
      await load();
    } catch (e) {
      if (mounted) setState(() => error = 'Could not unpublish invitation: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> showRsvpResponses(Map<String,dynamic> row) async {
    try {
      final responses = await supabase.from('wedding_invitation_rsvps')
          .select('guest_name,guest_email,attending,guest_count,message,created_at')
          .eq('invitation_id', row['id']).order('created_at', ascending: false);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Guest RSVP responses'),
          content: SizedBox(
            width: 440,
            child: responses.isEmpty
                ? const Text('No guest responses yet.')
                : ListView(
                    shrinkWrap: true,
                    children: responses.map((r) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r['guest_name']?.toString() ?? 'Guest'),
                      subtitle: Text([
                        r['attending'] == true ? 'Attending' : 'Not attending',
                        'Guests: ${r['guest_count'] ?? 1}',
                        if ((r['guest_email'] ?? '').toString().isNotEmpty) r['guest_email'].toString(),
                        if ((r['message'] ?? '').toString().isNotEmpty) r['message'].toString(),
                      ].join(' • ')),
                    )).toList(),
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = 'Could not load RSVP responses: $e');
    }
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
      const Chip(label:Text('Free feature')),
      const Text('Create a separate invitation for each function. Choose a community design, enter names, function, date, venue and address, then publish and share. No feature charge.'),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:saving?null:createInvitation,icon:const Icon(Icons.add),label:Text(saving?'Saving…':'Create invitation draft')),
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
      if(invitations.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('No invitation drafts yet.'))),
      ...invitations.map((row){
        final details=row['event_details'] is Map?Map<String,dynamic>.from(row['event_details'] as Map):<String,dynamic>{};
        return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(row['title'].toString(),style:Theme.of(context).textTheme.titleMedium),
          Text('Community: ${details['community'] ?? 'Custom'} • Design: ${row['template_key']}'),
          if ((details['function_name'] ?? '').toString().isNotEmpty) Text('Function: ${details['function_name']}'),
          if((details['bride']??'').toString().isNotEmpty||(details['groom']??'').toString().isNotEmpty)Text('${details['bride']??''} & ${details['groom']??''}'),
          if((details['date_time']??'').toString().isNotEmpty)Text('Date: ${details['date_time']}'),
          if((details['venue']??'').toString().isNotEmpty)Text('Venue: ${details['venue']}'),
          if((details['address']??'').toString().isNotEmpty)Text('Address: ${details['address']}'),
          SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('RSVP enabled (draft setting)'),value:row['rsvp_enabled']==true,onChanged:(v)=>toggleRsvp(row,v)),
          if (row['published_at'] == null) ...[
            FilledButton.icon(
              onPressed: saving ? null : () => publishInvitation(row),
              icon: const Icon(Icons.public),
              label: const Text('Publish share link'),
            ),
          ] else ...[
            Text('Published invitation • Guest link active', style: TextStyle(color: Colors.green.shade700)),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: saving ? null : () => Share.share(
                  '${supabaseUrl}/functions/v1/wedding-invitation-public?slug=${row['public_slug']}',
                  subject: 'Wedding invitation',
                ),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share link'),
              ),
              OutlinedButton.icon(
                onPressed: saving ? null : () => showRsvpResponses(row),
                icon: const Icon(Icons.people_outline),
                label: const Text('View RSVPs'),
              ),
              TextButton.icon(
                onPressed: saving ? null : () => unpublishInvitation(row),
                icon: const Icon(Icons.link_off),
                label: const Text('Unpublish'),
              ),
            ]),
          ],
          Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
            TextButton.icon(onPressed: saving ? null : () => editInvitation(row), icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
            TextButton.icon(onPressed: saving ? null : () => deleteDraft(row), icon: const Icon(Icons.delete_outline), label: const Text('Delete draft')),
          ]),
        ])));
      }),
    ]),
  );
}