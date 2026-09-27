import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import 'ledger_entry_screen.dart';

class MoneyBoardScreen extends StatefulWidget {
  const MoneyBoardScreen({super.key});
  @override State<MoneyBoardScreen> createState()=>_MoneyBoardScreenState();
}

class _MoneyBoardScreenState extends State<MoneyBoardScreen>{
  DateTime month=DateTime(DateTime.now().year,DateTime.now().month);
  String? show;
  final search=TextEditingController();
  @override void dispose(){search.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Money board')),
    body:LoadView(
      load:()=>apiOf(context).get('accounts/board',query:{'month':isoMonth(month)}),
      builder:(context,d,reload){
        final counts=d['counts'] as Map? ?? const{};final totals=d['totals'] as Map? ?? const{};
        final q=search.text.trim().toLowerCase();
        final rows=(d['rows'] as List? ?? const[]).where((x){final r=x as Map; if(show=='owing'&&toDouble(r['due'])<=.009)return false;if(show=='clear'&&toDouble(r['to_collect'])>.009)return false;if(show=='deposit'&&toDouble(r['deposit_short'])<=.009)return false;if(show=='charges'&&toDouble(r['charge_short'])<=.009)return false;if(show=='unpaid'&&!['unpaid','partial'].contains('${r['rent_state']}'))return false;if(show=='credit'&&toDouble(r['credit'])<=.009)return false;if(q.isNotEmpty&&!('${r['full_name']} ${r['resident_code']} ${r['phone']} ${r['room_number']}'.toLowerCase().contains(q)))return false;return true;}).toList();
        return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[IconButton(onPressed:()=>setState(()=>month=DateTime(month.year,month.month-1)),icon:const Icon(Icons.chevron_left)),Expanded(child:Text(fmtMonth(isoMonth(month)),textAlign:TextAlign.center,style:Theme.of(context).textTheme.titleMedium)),IconButton(onPressed:()=>setState(()=>month=DateTime(month.year,month.month+1)),icon:const Icon(Icons.chevron_right))]),
          StatGrid([StatTile(label:'Pending dues',value:money(totals['due'])),StatTile(label:'Deposits left',value:money(totals['deposit_short'])),StatTile(label:'Charges left',value:money(totals['charge_short'])),StatTile(label:'Total to collect',value:money(totals['to_collect']))]),
          const SizedBox(height:8),
          SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[for(final f in const [null,'owing','clear','deposit','charges','unpaid','credit'])Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(f==null?'All (${counts['all']??0})':'${f[0].toUpperCase()}${f.substring(1)} (${counts[f]??0})'),selected:show==f,onSelected:(_)=>setState(()=>show=f)))])),
          const SizedBox(height:8),
          AppTextField(controller:search,label:'Search resident, code, phone or room',onChanged:(_)=>setState((){})),
          const SizedBox(height:8),
          for(final raw in rows) _MoneyRow(r:Map<String,dynamic>.from(raw as Map),reload:reload),
        ]);
      },
    ),
  );
}

class _MoneyRow extends StatelessWidget{
  const _MoneyRow({required this.r,required this.reload});final Map<String,dynamic> r;final Future<void> Function() reload;
  @override Widget build(BuildContext context){final total=toDouble(r['to_collect']);return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${r['full_name']}',style:const TextStyle(fontWeight:FontWeight.w700)),Text('${r['resident_code']} · ${r['room_number']??'—'} / ${r['bed_label']??'—'}')])),Text(total>.009?money(total):'Clear',style:TextStyle(fontWeight:FontWeight.w800,color:total>.009?Theme.of(context).colorScheme.error:null))]),
    const Divider(),
    Wrap(spacing:14,runSpacing:6,children:[Text('Rent: ${money(r['rent_billed'])} (${r['rent_state']})'),Text('Paid: ${money(r['paid_this_month'])}'),Text('Due: ${money(r['due'])}'),Text('Deposit left: ${money(r['deposit_short'])}'),Text('Charges left: ${money(r['charge_short'])}'),if(toDouble(r['rent_short'])>.009)Text('Undercharged: ${money(r['rent_short'])}')]),
    const SizedBox(height:8),
    Align(alignment:Alignment.centerRight,child:FilledButton.tonalIcon(onPressed:()async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>LedgerEntryScreen(resident: {'id': toInt(r['id']), 'name': '${r['full_name']}', 'code': '${r['resident_code']}', 'phone': '${r['phone'] ?? ''}'}, type: 'payment')));await reload();},icon:const Icon(Icons.payments_outlined),label:const Text('Payment'))),
  ])));}
}
