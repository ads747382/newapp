import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../widgets/common.dart';

class SystemUpdateScreen extends StatefulWidget {
  const SystemUpdateScreen({super.key});
  @override State<SystemUpdateScreen> createState()=>_SystemUpdateScreenState();
}

class _SystemUpdateScreenState extends State<SystemUpdateScreen>{
  final key=GlobalKey<LoadViewState>(); bool backup=true;
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('System update')),
    body:LoadView(key:key,load:()=>apiOf(context).get('admin/update'),builder:(context,d,reload){final up=d['up_to_date']==true;return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(up?'Everything is up to date':'Update available',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w700)),
        const SizedBox(height:8),InfoRows([('App version','${d['app_version']}'),('Database version','${d['database_version']} of ${d['target_version']}')]),
      ]))),
      if(!up) Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Create backup first'),value:backup,onChanged:(v)=>setState(()=>backup=v)),
        const Text('This runs the same database installer used by Admin → System update on the website.'),
        const SizedBox(height:12),
        FilledButton.icon(onPressed:()async{if(!await confirm(context,'Update database?','The app will run pending schema updates.',ok:'Update'))return;final r=await runTask(context,()=>apiOf(context).post('admin/update',{'backup_first':backup}));if(r!=null){showMessage(context,'${r['message']}');key.currentState?.reload();}},icon:const Icon(Icons.system_update_alt),label:const Text('Update database')),
      ]))),
    ]);}),
  );
}
