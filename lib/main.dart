import 'dart:convert';
import 'dart:io';
import 'package:apk_sideload/install_apk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const secureStore = FlutterSecureStorage();
const keyName = 'nexora_gemini_api_key';
const modelName = 'gemini-2.5-flash';

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
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9B83FF), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF090B12),
    ),
    home: const ChatPage(),
  );
}

class NexoraEngine {
  static Future<List<Map<String,String>>> search(String query) async {
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': query});
    final res = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/122 Mobile Safari/537.36'
    }).timeout(const Duration(seconds: 18));
    if (res.statusCode != 200) throw Exception('تعذر البحث في الإنترنت: HTTP ${res.statusCode}');
    final doc = html_parser.parse(res.body);
    final items = <Map<String,String>>[];
    for (final node in doc.querySelectorAll('.result')) {
      final a = node.querySelector('.result__a');
      if (a == null) continue;
      var url = a.attributes['href'] ?? '';
      final parsed = Uri.tryParse(url);
      if (parsed != null && parsed.queryParameters['uddg'] != null) url = parsed.queryParameters['uddg']!;
      if (!url.startsWith('http')) continue;
      final title = a.text.trim();
      final snippet = node.querySelector('.result__snippet')?.text.trim() ?? '';
      if (title.isNotEmpty) items.add({'title':title,'url':url,'snippet':snippet});
      if (items.length >= 6) break;
    }
    return items;
  }

  static Future<String> ask(String question, String key) async {
    final greeting = RegExp(r'^(مرحبا|مرحباً|هلا|هلو|السلام عليكم|سلام|اهلا|أهلا|hello|hi|hey)[!！。.؟? ]*$', caseSensitive:false).hasMatch(question.trim());
    List<Map<String,String>> results = [];
    if (!greeting) {
      try { results = await search(question); } catch (_) {}
    }
    final sources = results.isEmpty ? 'لم تتوفر نتائج بحث ويب.' : results.asMap().entries.map((e) =>
      '[${e.key+1}] ${e.value['title']}\n${e.value['snippet']}\n${e.value['url']}').join('\n\n');
    final prompt = '''
رسالة المستخدم:
$question

نتائج البحث من الإنترنت:
$sources

أجب بلغة المستخدم. حلل نتائج البحث واكتب إجابة مفصلة وواضحة عند توفر المصادر، وأدرج روابطها الأصلية. لا تخترع معلومات أو روابط، واذكر بوضوح إن لم تكفِ المصادر. إذا كانت الرسالة تحية، رحّب بالمستخدم واسأله كيف تساعده.
''';
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=${Uri.encodeQueryComponent(key)}');
    final res = await http.post(uri, headers:{'Content-Type':'application/json'}, body:jsonEncode({
      'systemInstruction': {'parts':[{'text':'أنت NEXORA AI، مساعد ذكي عام ودقيق وصريح.'}]},
      'contents':[{'role':'user','parts':[{'text':prompt}]}],
      'generationConfig':{'temperature':0.4,'maxOutputTokens':4096}
    })).timeout(const Duration(seconds:90));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var detail = res.body;
      try { detail = jsonDecode(res.body)['error']['message']?.toString() ?? res.body; } catch (_) {}
      throw Exception('خدمة الذكاء الاصطناعي: $detail');
    }
    final data = jsonDecode(res.body) as Map<String,dynamic>;
    final candidates = data['candidates'] as List? ?? [];
    if (candidates.isEmpty) throw Exception('لم يُرجع النموذج إجابة.');
    final parts = candidates.first['content']['parts'] as List? ?? [];
    final answer = parts.map((p)=>(p as Map)['text']?.toString() ?? '').join('\n').trim();
    if (answer.isEmpty) throw Exception('الإجابة فارغة.');
    return answer;
  }
}

Future<void> checkUpdates(BuildContext context, {bool silent=false}) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final current = int.tryParse(info.buildNumber) ?? 0;
    final res = await http.get(Uri.parse('https://api.github.com/repos/oo9ee9-cpu/NEXORA-AI/releases/latest'), headers:{'Accept':'application/vnd.github+json'}).timeout(const Duration(seconds:15));
    if (res.statusCode != 200) throw Exception('تعذر فحص التحديثات: HTTP ${res.statusCode}');
    final release = jsonDecode(res.body) as Map<String,dynamic>;
    final tag = (release['tag_name'] ?? '').toString();
    final match = RegExp(r'android-build-(\d+)').firstMatch(tag);
    final latest = int.tryParse(match?.group(1) ?? '') ?? 0;
    final assets = release['assets'] as List? ?? [];
    Map? apk;
    for (final a in assets) { if ((a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) { apk=a; break; } }
    if (apk == null) throw Exception('لم يتم العثور على ملف APK');
    if (latest <= current) { if (!silent && context.mounted) showMsg(context,'تطبيقك محدث إلى آخر إصدار.'); return; }
    if (!context.mounted) return;
    final yes = await showDialog<bool>(context:context,builder:(d)=>AlertDialog(
      title:const Text('يتوفر تحديث جديد'),
      content:Text('الإصدار الحالي: ${info.version}+${info.buildNumber}\nالإصدار الجديد: ${tag.replaceAll('android-build-','')}\n\nهل تريد تنزيل التحديث؟'),
      actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('تنزيل التحديث'))],
    ));
    if (yes == true && context.mounted) await downloadUpdate(context, apk['browser_download_url'].toString());
  } catch(e) { if (!silent && context.mounted) showMsg(context,'تعذر فحص التحديث: $e'); }
}

Future<void> downloadUpdate(BuildContext context, String url) async {
  showDialog<void>(context:context,barrierDismissible:false,builder:(_)=>const AlertDialog(content:Row(children:[CircularProgressIndicator(),SizedBox(width:16),Expanded(child:Text('جارٍ تنزيل التحديث...'))])));
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(minutes:4));
    if (res.statusCode != 200) throw Exception('فشل التنزيل: HTTP ${res.statusCode}');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/nexora-update.apk');
    await file.writeAsBytes(res.bodyBytes,flush:true);
    if (await file.length() < 1024) throw Exception('ملف التحديث غير صالح');
    if (context.mounted) { Navigator.of(context,rootNavigator:true).pop(); await InstallApk().installApk(file.path); }
  } catch(e) { if (context.mounted) { Navigator.of(context,rootNavigator:true).pop(); showMsg(context,'تعذر تثبيت التحديث: $e'); } }
}

void showMsg(BuildContext context,String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override State<ChatPage> createState()=>_ChatPageState();
}
class _ChatPageState extends State<ChatPage> {
  final input=TextEditingController();
  final scroll=ScrollController();
  final messages=<({String text,bool user})>[];
  String? apiKey;
  bool busy=false;

  @override void initState() {
    super.initState();
    secureStore.read(key:keyName).then((v){if(mounted)setState(()=>apiKey=v);});
    WidgetsBinding.instance.addPostFrameCallback((_){checkUpdates(context,silent:true);});
  }
  @override void dispose(){input.dispose();scroll.dispose();super.dispose();}

  Future<void> configureKey({bool required=false}) async {
    final c=TextEditingController(text:apiKey ?? '');
    final value=await showDialog<String>(context:context,builder:(d)=>AlertDialog(
      title:const Text('تفعيل NEXORA AI'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('أدخل مفتاح Gemini API لتشغيل المحادثة والبحث الذكي. يُحفظ المفتاح بأمان على هذا الجهاز فقط.'),
        const SizedBox(height:12),
        TextField(controller:c,obscureText:true,decoration:const InputDecoration(labelText:'Gemini API Key',border:OutlineInputBorder())),
        const SizedBox(height:8),
        const Text('يمكنك إنشاء مفتاح من Google AI Studio.',style:TextStyle(fontSize:12,color:Colors.white60)),
      ]),
      actions:[if(!required)TextButton(onPressed:()=>Navigator.pop(d),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,c.text.trim()),child:const Text('حفظ'))],
    ));
    c.dispose();
    if(value!=null && value.isNotEmpty){await secureStore.write(key:keyName,value:value);if(mounted)setState(()=>apiKey=value);}
  }

  Future<void> send() async {
    final q=input.text.trim();
    if(q.isEmpty || busy)return;
    if(apiKey==null || apiKey!.isEmpty){await configureKey(required:true);if(apiKey==null || apiKey!.isEmpty)return;}
    setState(()=>{messages.add((text:q,user:true)),input.clear(),busy=true});
    scrollBottom();
    try { final answer=await NexoraEngine.ask(q,apiKey!); if(mounted)setState(()=>messages.add((text:answer,user:false))); }
    catch(e){if(mounted)setState(()=>messages.add((text:'تعذر إكمال الطلب: $e',user:false)));}
    finally{if(mounted)setState(()=>busy=false);scrollBottom();}
  }
  void scrollBottom()=>WidgetsBinding.instance.addPostFrameCallback((_){if(scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,duration:const Duration(milliseconds:250),curve:Curves.easeOut);});

  Future<void> openSettings() async {
    await showModalBottomSheet<void>(context:context,backgroundColor:const Color(0xFF191B28),builder:(d)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:const Icon(Icons.key),title:const Text('إعداد مفتاح الذكاء الاصطناعي'),onTap:(){Navigator.pop(d);configureKey();}),
      ListTile(leading:const Icon(Icons.system_update_alt),title:const Text('التحقق من وجود تحديث'),onTap:(){Navigator.pop(d);checkUpdates(context);}),
    ])));
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Row(children:[Icon(Icons.hub,color:Color(0xFFB09EFF)),SizedBox(width:9),Text('NEXORA AI',style:TextStyle(fontWeight:FontWeight.w800))]),actions:[IconButton(onPressed:openSettings,icon:const Icon(Icons.settings_outlined))]),
    body:Column(children:[
      Expanded(child:messages.isEmpty?const Center(child:Padding(padding:EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Icon(Icons.auto_awesome,size:62,color:Color(0xFFAA98FF)),SizedBox(height:18),
        Text('مرحباً بك في NEXORA AI',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),SizedBox(height:10),
        Text('اكتب ما تريد. سيبحث NEXORA في الإنترنت عند الحاجة، ثم يحلل النتائج ويجيبك داخل المحادثة.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white70,height:1.7)),
      ]))):ListView.builder(controller:scroll,padding:const EdgeInsets.all(14),itemCount:messages.length,itemBuilder:(c,i){final m=messages[i];return Align(alignment:m.user?Alignment.centerRight:Alignment.centerLeft,child:Container(margin:const EdgeInsets.symmetric(vertical:6),padding:const EdgeInsets.all(14),constraints:const BoxConstraints(maxWidth:350),decoration:BoxDecoration(color:m.user?const Color(0xFF30275A):const Color(0xFF191B28),borderRadius:BorderRadius.circular(18)),child:SelectableText(m.text,style:const TextStyle(height:1.55))));})),
      if(busy)const Padding(padding:EdgeInsets.symmetric(horizontal:16),child:Row(children:[SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)),SizedBox(width:10),Text('يبحث ويحلل ويكتب الإجابة...',style:TextStyle(color:Colors.white70))])),
      SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(12,8,12,12),child:Row(children:[
        Expanded(child:TextField(controller:input,onSubmitted:(_)=>send(),minLines:1,maxLines:5,decoration:InputDecoration(hintText:'اكتب رسالتك...',filled:true,fillColor:const Color(0xFF191B28),contentPadding:const EdgeInsets.symmetric(horizontal:18,vertical:15),border:OutlineInputBorder(borderRadius:BorderRadius.circular(20),borderSide:BorderSide.none)))),
        const SizedBox(width:8),IconButton.filled(onPressed:busy?null:send,icon:const Icon(Icons.arrow_upward),style:IconButton.styleFrom(backgroundColor:const Color(0xFFB09EFF),foregroundColor:const Color(0xFF171323),minimumSize:const Size(54,54))),
      ]))),
    ]),
  );
}
