import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';

class AdminToolsScreen extends StatelessWidget {
  const AdminToolsScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(title: const Text('Administration'), bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Users'), Tab(text: 'Roles'), Tab(text: 'Audit'), Tab(text: 'Backups')])),
      body: const TabBarView(children: [_UsersTab(), _RolesTab(), _AuditTab(), _BackupsTab()]),
    ),
  );
}

class _UsersTab extends StatefulWidget { const _UsersTab(); @override State<_UsersTab> createState()=>_UsersTabState(); }
class _UsersTabState extends State<_UsersTab> {
  final key=GlobalKey<LoadViewState>();
  Future<void> _edit(Json data, [Map? user]) async {
    final roles=(data['roles'] as List? ?? const []).cast<Map>();
    final name=TextEditingController(text:'${user?['name']??''}');
    final username=TextEditingController(text:'${user?['username']??''}');
    final email=TextEditingController(text:'${user?['email']??''}');
    final password=TextEditingController();
    int? roleId=user==null?(roles.isEmpty?null:toInt(roles.first['id'])):toInt(user['role_id']);
    bool must=user?['must_change_password']!=false;
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
      title:Text(user==null?'Add user':'Edit ${user['name']}'),
      content:SizedBox(width:500,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        AppTextField(controller:name,label:'Full name'), AppTextField(controller:username,label:'Username'), AppTextField(controller:email,label:'Email',keyboard:TextInputType.emailAddress),
        DropdownButtonFormField<int>(initialValue:roleId,decoration:const InputDecoration(labelText:'Role'),items:[for(final r in roles)DropdownMenuItem(value:toInt(r['id']),child:Text('${r['name']}'))],onChanged:(v)=>set(()=>roleId=v)),
        PasswordInput(controller:password,label:user==null?'Temporary password':'New password (optional)'),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Require password change'),value:must,onChanged:(v)=>set(()=>must=v)),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Save'))],
    )));
    if(ok!=true||roleId==null)return;
    if(!mounted)return;
    final body={'name':name.text.trim(),'username':username.text.trim(),'email':email.text.trim(),'role_id':roleId,'must_change_password':must,'password':password.text};
    if(user!=null&&password.text.isEmpty) body['password']='';
    final r=await runTask(context,()=>apiOf(context).post(user==null?'admin/users':'admin/users/${user['id']}',body));
    if(r!=null)key.currentState?.reload();
  }
  Future<void> _action(Map u,String action) async { final r=await runTask(context,()=>apiOf(context).post('admin/users/${u['id']}/action',{'action':action})); if(r!=null)key.currentState?.reload(); }
  @override Widget build(BuildContext context)=>LoadView(key:key,load:()=>apiOf(context).get('admin/users'),builder:(context,d,reload){final rows=(d['users'] as List? ?? const []);return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:()=>_edit(d),icon:const Icon(Icons.add),label:const Text('Add user'))),
    for(final raw in rows) Builder(builder:(context){final u=Map<String,dynamic>.from(raw as Map);final locked=toInt(u['recent_failures'])>=toInt(d['max_attempts']);return Card(child:ListTile(title:Text('${u['name']}'),subtitle:Text('${u['username']} · ${u['role_name']}\n${u['is_active']==true||toInt(u['is_active'])==1?'Active':'Inactive'}${locked?' · Locked':''}'),isThreeLine:true,trailing:PopupMenuButton<String>(onSelected:(x){if(x=='edit'){_edit(d,u);}else{_action(u,x);}},itemBuilder:(_)=>[const PopupMenuItem(value:'edit',child:Text('Edit')),if(locked)const PopupMenuItem(value:'unlock',child:Text('Unlock')),PopupMenuItem(value:(u['is_active']==true||toInt(u['is_active'])==1)?'deactivate':'activate',child:Text((u['is_active']==true||toInt(u['is_active'])==1)?'Deactivate':'Activate'))])));}),
  ]);});
}

class _RolesTab extends StatefulWidget { const _RolesTab(); @override State<_RolesTab> createState()=>_RolesTabState(); }
class _RolesTabState extends State<_RolesTab>{ final key=GlobalKey<LoadViewState>(); Map<String,Set<int>> grants={};
  Future<void> _save(Json d) async { final body={'action':'save','grants':{for(final e in grants.entries)e.key:e.value.toList()}}; final r=await runTask(context,()=>apiOf(context).post('admin/roles',body)); if(r!=null)key.currentState?.reload(); }
  @override Widget build(BuildContext context)=>LoadView(key:key,load:()=>apiOf(context).get('admin/roles'),builder:(context,d,reload){ final roles=(d['roles'] as List? ?? const []);final perms=(d['permissions'] as List? ?? const []); if(grants.isEmpty){final g=(d['granted'] as Map? ?? const {});for(final r in roles){final id='${(r as Map)['id']}';grants[id]={for(final x in (g[id] as List? ?? g[toInt(id)] as List? ?? const []))toInt(x)};}}
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[for(final rr in roles) Builder(builder:(context){final r=Map<String,dynamic>.from(rr as Map);final id='${r['id']}';final superRole='${r['slug']}'=='super_admin';return Card(child:ExpansionTile(title:Text('${r['name']}'),subtitle:Text('${r['users']} users${superRole?' · Full access':''}'),children:[for(final pp in perms) CheckboxListTile(dense:true,title:Text('${(pp as Map)['slug']}'),value:superRole||grants.putIfAbsent(id,()=>{}).contains(toInt(pp['id'])),onChanged:superRole?null:(v)=>setState((){if(v==true){grants[id]!.add(toInt(pp['id']));}else{grants[id]!.remove(toInt(pp['id']));}}))]));}), const SizedBox(height:8),FilledButton(onPressed:()=>_save(d),child:const Text('Save permissions'))]);});}

class _AuditTab extends StatelessWidget { const _AuditTab(); @override Widget build(BuildContext context)=>LoadView(load:()=>apiOf(context).get('admin/audit'),builder:(context,d,reload)=>Column(children:[for(final raw in (d['rows'] as List? ?? const [])) Builder(builder:(context){final r=raw as Map;return Card(child:ListTile(title:Text('${r['action']}'),subtitle:Text('${r['created_at']} · ${r['user_name']??'System'}\n${r['entity_type']??''}${r['entity_id']==null?'':' #${r['entity_id']}'} ${r['details']??''}'),isThreeLine:true,trailing:Text('${r['ip']??''}')));})])); }

class _BackupsTab extends StatefulWidget{const _BackupsTab();@override State<_BackupsTab> createState()=>_BackupsTabState();}
class _BackupsTabState extends State<_BackupsTab>{final key=GlobalKey<LoadViewState>();Future<void> act(String action,[String? name])async{final r=await runTask(context,()=>apiOf(context).post('admin/backups',{'action':action,'name':?name}));if(r!=null)key.currentState?.reload();}
@override Widget build(BuildContext context)=>LoadView(key:key,load:()=>apiOf(context).get('admin/backups'),builder:(context,d,reload)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[FilledButton.icon(onPressed:()=>act('create'),icon:const Icon(Icons.backup_outlined),label:const Text('Create backup now')),const SizedBox(height:8),for(final raw in (d['backups'] as List? ?? const []))Builder(builder:(context){final b=raw as Map;final name='${b['name']}';return Card(child:ListTile(title:Text(name),subtitle:Text('${b['size']} bytes'),trailing:PopupMenuButton<String>(onSelected:(x){if(x=='download'){downloadAndOpen(context,'admin/backups/$name',name);}else{act('delete',name);}},itemBuilder:(_)=>const [PopupMenuItem(value:'download',child:Text('Download')),PopupMenuItem(value:'delete',child:Text('Delete'))])));})]));}
