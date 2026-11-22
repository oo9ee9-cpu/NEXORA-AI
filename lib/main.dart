import 'package:flutter/material.dart';

void main() => runApp(const NexoraApp());

class NexoraApp extends StatelessWidget {
  const NexoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NEXORA AI',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8065FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF090B12),
      ),
      home: const NexoraHome(),
    );
  }
}

class NexoraHome extends StatefulWidget {
  const NexoraHome({super.key});

  @override
  State<NexoraHome> createState() => _NexoraHomeState();
}

class _NexoraHomeState extends State<NexoraHome> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [ChatPage(), CellsPage(), AdminPage()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('✦ NEXORA AI',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), label: 'المحادثة'),
          NavigationDestination(
              icon: Icon(Icons.grid_view_rounded), label: 'الخلايا'),
          NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              label: 'الإدارة'),
        ],
      ),
    );
  }
}

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome,
                      size: 58, color: Color(0xFFAA98FF)),
                  SizedBox(height: 18),
                  Text('مرحباً بك في NEXORA AI',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 23, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Text(
                    'هذه النسخة الأولى من واجهة NEXORA AI. ربط الذكاء الاصطناعي والخادم وقاعدة المعرفة سيأتي في المراحل التالية.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.7),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'اكتب رسالتك...',
              filled: true,
              fillColor: const Color(0xFF191B28),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class CellsPage extends StatelessWidget {
  const CellsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text('إدارة الخلايا',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        CellTile(number: '01', title: 'خلية المحادثة',
            detail: 'إدارة الحوار والردود', icon: Icons.chat),
        CellTile(number: '02', title: 'خلية المعرفة',
            detail: 'البحث في ملفاتك ومعلوماتك', icon: Icons.menu_book),
        CellTile(number: '03', title: 'خلية البحث',
            detail: 'البحث في الإنترنت والتحقق', icon: Icons.travel_explore),
        CellTile(number: '04', title: 'خلية المطوّر',
            detail: 'إدارة المشاريع وGitHub', icon: Icons.code),
      ],
    );
  }
}

class CellTile extends StatelessWidget {
  const CellTile({
    super.key,
    required this.number,
    required this.title,
    required this.detail,
    required this.icon,
  });

  final String number;
  final String title;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF191B28),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF30275A),
          child: Icon(icon, color: const Color(0xFFB7A8FF)),
        ),
        title: Text('$number · $title'),
        subtitle: Text(detail),
        trailing: const Chip(label: Text('قيد الإعداد')),
      ),
    );
  }
}

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text('لوحة الإدارة',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        AdminTile(icon: Icons.api, title: 'إدارة مزوّدي API',
            detail: 'إضافة المفاتيح واختبارها وتحديد الأولويات'),
        AdminTile(icon: Icons.library_books, title: 'قاعدة المعرفة',
            detail: 'إضافة المعلومات والملفات والمستندات'),
        AdminTile(icon: Icons.account_tree, title: 'إعداد الخلايا',
            detail: 'تحديد المهام والتعليمات وحالة كل خلية'),
        AdminTile(icon: Icons.monitor_heart, title: 'مراقبة النظام',
            detail: 'متابعة الطلبات والأخطاء والاستهلاك'),
        SizedBox(height: 12),
        Text(
          'تنبيه: مفاتيح API ستُحفظ في الخادم بشكل آمن، وليس داخل APK.',
          style: TextStyle(color: Colors.orangeAccent, height: 1.5),
        ),
      ],
    );
  }
}

class AdminTile extends StatelessWidget {
  const AdminTile({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF191B28),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFB7A8FF)),
        title: Text(title),
        subtitle: Text(detail),
      ),
    );
  }
}
