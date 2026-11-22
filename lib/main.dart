import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NexoraApp());

class NexoraApp extends StatelessWidget {
  const NexoraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'NEXORA AI',
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B72FF), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF090B12),
    ),
    home: const RootPage(),
  );
}

class Api {
  static String base = '';
  static String admin = '';
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    base = p.getString('server') ?? '';
    admin = p.getString('admin') ?? '';
  }
  static Future<void> save(String url, String password) async {
    final p = await SharedPreferences.getInstance();
    base = url.trim().replaceAll(RegExp(r'/$'), '');
    admin = password;
    await p.setString('server', base);
    await p.setString('admin', admin);
  }
  static Map<String,String> get headers => {'Content-Type':'application/json', if(admin.isNotEmpty)'X-Admin-Password':admin};
  static Future<dynamic> get(String path) async {
    final r=await http.get(Uri.parse('$base$path'),headers:headers).timeout(const Duration(seconds:20));
    if(r.statusCode>=400) throw Exception(r.body);
    return jsonDecode(r.body);
  }
  static Future<dynamic> post(String path,Map<String,dynamic> body) async {
    final r=await http.post(Uri.parse('$base$path'),headers:headers,body:jsonEncode(body)).timeout(const Duration(seconds:60));
    if(r.statusCode>=400) throw Exception(r.body);
    return jsonDecode(r.body);
  }
  static Future<dynamic> patch(String path,Map<String,dynamic> body) async {
    final r=await http.patch(Uri.parse('$base$path'),headers:headers,body:jsonEncode(body)).timeout(const Duration(seconds:30));
    if(r.statusCode>=400) throw Exception(r.body);
    return jsonDecode(r.body);
  }
}

class RootPage extends StatefulWidget { const RootPage({super.key}); @override State<RootPage> createState()=>_RootPageState(); }
class _RootPageState extends State<RootPage> {
  int tab=0; bool loaded=false;
  @override void initState(){super.initState();Api.load().then((_){if(mounted)setState(()=>loaded=true);});}
  @override Widget build(BuildContext context) {
    if(!loaded)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final pages=[const ChatPage(),const CellsPage(),const AdminPage()];
    return Scaffold(
      appBar:AppBar(title:const Row(children:[Icon(Icons.hub,color:Color(0xFFB09EFF)),SizedBox(width:9),Text('NEXORA AI',style:TextStyle(fontWeight:FontWeight.w800))]),actions:[IconButton(onPressed:()=>showDialog(context:context,builder:(_)=>const ServerDialog()),icon:const Icon(Icons.settings))]),
      body:pages[tab],
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const[
        NavigationDestination(icon:Icon(Icons.chat_bubble_outline),label:'المحادثة'),
        NavigationDestination(icon:Icon(Icons.grid_view),label:'الخلايا'),
        NavigationDestination(icon:Icon(Icons.admin_panel_settings_outlined),label:'الإدارة'),
      ]),
    );
  }
}

class ChatPage extends StatefulWidget { const ChatPage({super.key}); @override State<ChatPage> createState()=>_ChatPageState(); }
class _ChatPageState extends State<ChatPage> {
  final input=TextEditingController(); final scroll=ScrollController(); final messages=<Map<String,String>>[]; bool busy=false;
  @override void dispose(){input.dispose();scroll.dispose();super.dispose();}
  Future<void> send() async {
    final q=input.text.trim(); if(q.isEmpty||busy)return;
    setState((){messages.add({'role':'user','text':q});input.clear();busy=true;});
    try {
      if(Api.base.isEmpty)throw Exception('اضبط عنوان الخادم من زر الإعدادات أولاً.');
      final d=await Api.post('/api/chat',{'message':q});
      setState(()=>messages.add({'role':'assistant','text':d['answer']?.toString()??'لا توجد إجابة'}));
    } catch(e){setState(()=>messages.add({'role':'assistant','text':'تعذر الاتصال: $e'}));}
    finally{if(mounted)setState(()=>busy=false);WidgetsBinding.instance.addPostFrameCallback((_){if(scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,duration:const Duration(milliseconds:250),curve:Curves.easeOut);});}
  }
  @override Widget build(BuildContext context)=>Column(children:[
    Expanded(child:messages.isEmpty?const Center(child:Padding(padding:EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.auto_awesome,size:58,color:Color(0xFFAA98FF)),SizedBox(height:18),Text('مرحباً بك في NEXORA AI',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),SizedBox(height:10),Text('يبحث النظام في قاعدة المعرفة الداخلية أولاً، ثم يستخدم مزود الذكاء الاصطناعي عند الحاجة.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white70,height:1.7))]))):ListView.builder(controller:scroll,padding:const EdgeInsets.all(14),itemCount:messages.length,itemBuilder:(c,i){final m=messages[i];final user=m['role']=='user';return Align(alignment:user?Alignment.centerRight:Alignment.centerLeft,child:Container(margin:const EdgeInsets.symmetric(vertical:6),padding:const EdgeInsets.all(14),constraints:const BoxConstraints(maxWidth:340),decoration:BoxDecoration(color:user?const Color(0xFF30275A):const Color(0xFF191B28),borderRadius:BorderRadius.circular(17)),child:Text(m['text']??'',style:const TextStyle(height:1.5))));})),
    if(busy)const LinearProgressIndicator(),
    Padding(padding:const EdgeInsets.fromLTRB(12,8,12,14),child:Row(children:[Expanded(child:TextField(controller:input,onSubmitted:(_)=>send(),minLines:1,maxLines:4,decoration:InputDecoration(hintText:'اكتب رسالتك...',filled:true,fillColor:const Color(0xFF191B28),border:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide.none)))),const SizedBox(width:8),IconButton.filled(onPressed:busy?null:send,icon:const Icon(Icons.send))]))
  ]);
}

class CellsPage extends StatefulWidget {const CellsPage({super.key});@override State<CellsPage> createState()=>_CellsPageState();}
class _CellsPageState extends State<CellsPage>{
  List cells=[];String? error;bool loading=true;
  Future<void> load()async{try{final d=await Api.get('/api/cells');setState((){cells=d['cells']??[];error=null;});}catch(e){setState(()=>error=e.toString());}finally{setState(()=>loading=false);}}
  @override void initState(){super.initState();load();}
  Future<void> toggle(Map c)async{try{await Api.patch('/api/cells/${c['id']}',{'enabled':!(c['enabled']==true)});await load();}catch(e){_snack(context,e.toString());}}
  @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('إدارة الخلايا',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    const Text('تشغيل وإيقاف وحدات النظام.',style:TextStyle(color:Colors.white60)),
    if(loading)const LinearProgressIndicator(),
    if(error!=null)Text('تعذر تحميل الخلايا: $error'),
    ...cells.map<Widget>((v){final c=Map<String,dynamic>.from(v);return Card(color:const Color(0xFF191B28),child:SwitchListTile(value:c['enabled']==true,onChanged:(_)=>toggle(c),title:Text('${c['number']??''} · ${c['name']??''}'),subtitle:Text(c['description']??''),secondary:const Icon(Icons.hub,color:Color(0xFFB7A8FF))));}),
  ]));
}

class AdminPage extends StatefulWidget {const AdminPage({super.key});@override State<AdminPage> createState()=>_AdminPageState();}
class _AdminPageState extends State<AdminPage>{
  List providers=[];bool loading=true;String? error;
  Future<void> load()async{try{final d=await Api.get('/api/admin/providers');setState((){providers=d['providers']??[];error=null;});}catch(e){setState(()=>error=e.toString());}finally{setState(()=>loading=false);}}
  @override void initState(){super.initState();load();}
  Future<void> addProvider()async{
    final n=TextEditingController(),b=TextEditingController(),m=TextEditingController(),k=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('إضافة مزوّد API'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[_input(n,'اسم المزود'),_input(b,'عنوان API الأساسي'),_input(m,'اسم النموذج'),_input(k,'مفتاح API',secret:true)])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حفظ'))]));
    if(ok==true){try{await Api.post('/api/admin/providers',{'name':n.text,'base_url':b.text,'model':m.text,'api_key':k.text,'enabled':true});await load();_snack(context,'تمت إضافة المزود.');}catch(e){_snack(context,e.toString());}}
    n.dispose();b.dispose();m.dispose();k.dispose();
  }
  Future<void> addKnowledge()async{
    final t=TextEditingController(),body=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('إضافة معرفة داخلية'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[_input(t,'العنوان'),TextField(controller:body,minLines:4,maxLines:8,decoration:const InputDecoration(labelText:'المحتوى',border:OutlineInputBorder()))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('إضافة'))]));
    if(ok==true){try{await Api.post('/api/admin/knowledge',{'title':t.text,'content':body.text});_snack(context,'تمت إضافة المعرفة.');}catch(e){_snack(context,e.toString());}}
    t.dispose();body.dispose();
  }
  Future<void> uploadPdf()async{
    try{final result=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['pdf'],withData:true);if(result==null)return;final f=result.files.single;if(f.bytes==null)throw Exception('تعذرت قراءة الملف');final req=http.MultipartRequest('POST',Uri.parse('${Api.base}/api/admin/knowledge/upload'));req.headers['X-Admin-Password']=Api.admin;req.files.add(http.MultipartFile.fromBytes('file',f.bytes!,filename:f.name));final res=await req.send();final body=await res.stream.bytesToString();if(res.statusCode>=400)throw Exception(body);_snack(context,'تم رفع PDF إلى قاعدة المعرفة.');}catch(e){_snack(context,e.toString());}
  }
  @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('لوحة الإدارة',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    const Text('إدارة مزودي النماذج وقاعدة المعرفة.',style:TextStyle(color:Colors.white60)),
    const SizedBox(height:12),
    _action(Icons.add_link,'إضافة مزوّد API','حفظ endpoint والنموذج والمفتاح على الخادم',addProvider),
    _action(Icons.library_add,'إضافة معلومة','إضافة معلومة لها الأولوية قبل طلب النموذج',addKnowledge),
    _action(Icons.picture_as_pdf,'رفع ملف PDF','استخراج النص وإضافته إلى المعرفة',uploadPdf),
    _action(Icons.refresh,'تحديث المزودين','إعادة تحميل قائمة المزودين',load),
    const SizedBox(height:12),const Text('المزوّدون',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    if(loading)const LinearProgressIndicator(),if(error!=null)Text(error!),
    ...providers.map<Widget>((p)=>Card(color:const Color(0xFF191B28),child:ListTile(leading:const Icon(Icons.api,color:Color(0xFFB7A8FF)),title:Text(p['name']??'مزود'),subtitle:Text('${p['model']??''} · ${p['key_configured']==true?'المفتاح محفوظ':'لا يوجد مفتاح'}'),trailing:Text(p['enabled']==true?'مفعّل':'متوقف')))),
    const SizedBox(height:12),const Text('يلزم إعداد ADMIN_PASSWORD وNEXORA_MASTER_KEY في الخادم. لا تضع مفاتيح API في ملفات التطبيق.',style:TextStyle(color:Colors.orangeAccent,height:1.5)),
  ]));
}

Widget _input(TextEditingController c,String label,{bool secret=false})=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:c,obscureText:secret,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));
Widget _action(IconData icon,String title,String subtitle,VoidCallback tap)=>Card(color:const Color(0xFF191B28),child:ListTile(onTap:tap,leading:Icon(icon,color:const Color(0xFFB7A8FF)),title:Text(title),subtitle:Text(subtitle),trailing:const Icon(Icons.chevron_right)));
void _snack(BuildContext c,String text)=>ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text(text)));

class ServerDialog extends StatefulWidget{const ServerDialog({super.key});@override State<ServerDialog> createState()=>_ServerDialogState();}
class _ServerDialogState extends State<ServerDialog>{
  late final url=TextEditingController(text:Api.base);late final password=TextEditingController(text:Api.admin);String status='';
  Future<void> test()async{try{final u=url.text.trim().replaceAll(RegExp(r'/$'), '');final r=await http.get(Uri.parse('$u/health')).timeout(const Duration(seconds:10));setState(()=>status=r.statusCode==200?'الاتصال ناجح ✓':'استجابة الخادم: ${r.statusCode}');}catch(e){setState(()=>status='فشل الاتصال: $e');}}
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('إعداد اتصال NEXORA'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:url,decoration:const InputDecoration(labelText:'رابط الخادم HTTPS')),TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'كلمة مرور المدير')),const SizedBox(height:8),Text(status,style:const TextStyle(fontSize:12))])),actions:[TextButton(onPressed:test,child:const Text('اختبار')),TextButton(onPressed:()=>Navigator.pop(context),child:const Text('إغلاق')),FilledButton(onPressed:()async{await Api.save(url.text,password.text);if(context.mounted)Navigator.pop(context);},child:const Text('حفظ'))]);
  @override void dispose(){url.dispose();password.dispose();super.dispose();}
}
