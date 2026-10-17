import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'github/github_api.dart';
import 'github/github_auth.dart';
import 'github/github_login_screen.dart';

const _bg = Color(0xFF0E141B);
const _surface = Color(0xFF16202A);
const _border = Color(0xFF243140);
const _accent = Color(0xFF4FC3F7);
const _ok = Color(0xFF5BD38A);
const _warn = Color(0xFFF5B84B);
const _bad = Color(0xFFFF7A7A);

String _errText(Object e) => e is GitHubException ? e.message : '$e';

void _toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'الآن';
  if (d.inMinutes < 60) return 'قبل ${d.inMinutes} دقيقة';
  if (d.inHours < 24) return 'قبل ${d.inHours} ساعة';
  return 'قبل ${d.inDays} يوم';
}

// ───────────── حالة التطبيق ─────────────

class AppState extends ChangeNotifier {
  final auth = GitHubAuth();
  GitHubApi? api;
  String? user;
  List<Repo> repos = [];
  Repo? current;
  bool loadingRepos = false;
  String? error;

  bool get signedIn => api != null;

  Future<void> restore() async {
    final t = await auth.savedToken();
    if (t != null) await signIn(t);
  }

  Future<void> signIn(String token) async {
    api = GitHubApi(token);
    try {
      user = await api!.login();
    } catch (e) {
      error = _errText(e);
      if (e is GitHubException && e.statusCode == 401) {
        await signOut();
        return;
      }
    }
    notifyListeners();
    await loadRepos();
  }

  Future<void> loadRepos() async {
    final a = api;
    if (a == null) return;
    loadingRepos = true;
    error = null;
    notifyListeners();
    try {
      repos = await a.listRepos();
    } catch (e) {
      error = _errText(e);
    }
    loadingRepos = false;
    notifyListeners();
  }

  void select(Repo r) {
    current = r;
    notifyListeners();
  }

  void addRepo(Repo r) {
    repos = [r, ...repos];
    current = r;
    notifyListeners();
  }

  Future<void> signOut() async {
    await auth.signOut();
    api = null;
    user = null;
    repos = [];
    current = null;
    notifyListeners();
  }
}

final appState = AppState();

Future<bool> signInFlow(BuildContext context) async {
  final token = await Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => GitHubLoginScreen(auth: appState.auth)),
  );
  if (token == null) return false;
  await appState.signIn(token);
  return true;
}

// ───────────── التطبيق ─────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await appState.restore();
  } catch (_) {}
  runApp(const FlutterStudioApp());
}

class FlutterStudioApp extends StatelessWidget {
  const FlutterStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: _bg,
        cardTheme: CardThemeData(
          color: _surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _border),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border),
          ),
        ),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      initialRoute: appState.signedIn ? '/home' : '/',
      routes: {
        '/': (_) => const StartScreen(),
        '/home': (_) => const MainShell(),
        '/new': (_) => const NewProjectScreen(),
      },
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

// ───────────── شاشة البداية ─────────────

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  Future<void> _github(BuildContext context) async {
    final ok = await signInFlow(context);
    if (ok && context.mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _border),
                  ),
                  child: Center(
                    child: Transform.rotate(
                      angle: 0.785398,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Flutter Studio',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                'أنشئ مشاريع Flutter وعدّلها وابنِها من جوالك، مع مزامنة كاملة مع GitHub',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.7),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => _github(context),
                child: const Text('المتابعة عبر GitHub'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/home'),
                child: const Text('تصفّح بدون حساب'),
              ),
              const SizedBox(height: 12),
              Text(
                'بالمتابعة فأنت توافق على الشروط وسياسة الخصوصية',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────── الهيكل الرئيسي ─────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      final arg = ModalRoute.of(context)?.settings.arguments;
      if (arg is int) _index = arg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ProjectsPage(onOpen: () => setState(() => _index = 1)),
      EditorPage(onBuild: () => setState(() => _index = 2)),
      const BuildPage(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.folder_outlined), label: 'المشاريع'),
          NavigationDestination(icon: Icon(Icons.code), label: 'المحرر'),
          NavigationDestination(
              icon: Icon(Icons.build_outlined), label: 'البناء'),
        ],
      ),
    );
  }
}

// ───────────── المشاريع ─────────────

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final muted = Theme.of(context).colorScheme.onSurfaceVariant;

        if (!appState.signedIn) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('سجّل الدخول لعرض مشاريعك من GitHub'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => signInFlow(context),
                    child: const Text('المتابعة عبر GitHub'),
                  ),
                ],
              ),
            ),
          );
        }

        final repos = appState.repos
            .where((r) => r.name.toLowerCase().contains(_q.toLowerCase()))
            .toList();

        return RefreshIndicator(
          onRefresh: appState.loadRepos,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('مشاريعي',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      StatusChip('GitHub: @${appState.user ?? '...'}', _ok),
                      IconButton(
                        tooltip: 'تسجيل الخروج',
                        onPressed: appState.signOut,
                        icon: const Icon(Icons.logout, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  hintText: 'ابحث في المشاريع',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 14),
              if (appState.loadingRepos)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (appState.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(appState.error!,
                      style: const TextStyle(color: _bad)),
                ),
              for (final r in repos) ...[
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: appState.current?.fullName == r.fullName
                          ? _accent
                          : _border,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      appState.select(r);
                      widget.onOpen();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(r.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              StatusChip(r.isPrivate ? 'خاص' : 'عام',
                                  r.isPrivate ? Colors.grey : _accent),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(r.fullName,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                  color: muted,
                                  fontSize: 13,
                                  fontFamily: 'monospace')),
                          const SizedBox(height: 4),
                          Text(
                              'آخر تعديل: ${_ago(r.updatedAt)} · فرع ${r.defaultBranch}',
                              style: TextStyle(color: muted, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => Navigator.pushNamed(context, '/new'),
                icon: const Icon(Icons.add),
                label: const Text('مشروع جديد'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────── مشروع جديد ─────────────

class NewProjectScreen extends StatefulWidget {
  const NewProjectScreen({super.key});

  @override
  State<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends State<NewProjectScreen> {
  final _name = TextEditingController(text: 'my_app');
  final _pkg = TextEditingController(text: 'com.example.my_app');
  bool _private = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _pkg.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final api = appState.api;
    if (api == null) {
      _toast(context, 'سجّل الدخول عبر GitHub أولًا');
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast(context, 'أدخل اسم المشروع');
      return;
    }
    final parts = _pkg.text.trim().split('.');
    final org =
        parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : 'com.example';

    setState(() => _busy = true);
    try {
      final repo = await api.bootstrapFlutterProject(
        name: name,
        org: org,
        private: _private,
      );
      appState.addRepo(repo);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false,
          arguments: 1);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(context, _errText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مشروع Flutter جديد')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'اسم المشروع'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pkg,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'معرّف الحزمة'),
          ),
          const SizedBox(height: 14),
          Card(
            child: SwitchListTile(
              title: const Text('مستودع خاص'),
              subtitle: const Text('أوقفه لإنشاء مستودع عام'),
              value: _private,
              onChanged: (v) => setState(() => _private = v),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'يُنشأ المستودع مع ملف Workflow لبناء Android عبر GitHub Actions.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('إنشاء وربط المستودع'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}

// ───────────── المحرر ─────────────

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.onBuild});
  final VoidCallback onBuild;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  static const _defaultPath = 'lib/main.dart';

  final _ctrl = TextEditingController();
  Repo? _repo;
  String _path = _defaultPath;
  String? _sha;
  bool _loading = false;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onState);
    _onState();
  }

  @override
  void dispose() {
    appState.removeListener(_onState);
    _ctrl.dispose();
    super.dispose();
  }

  void _onState() {
    final cur = appState.current;
    if (cur?.fullName != _repo?.fullName) {
      _repo = cur;
      _path = _defaultPath;
      _load();
    }
  }

  Future<void> _load() async {
    final repo = _repo;
    final api = appState.api;
    if (repo == null || api == null) {
      setState(() {
        _ctrl.clear();
        _sha = null;
        _dirty = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = await api.readFile(repo.owner, repo.name, _path,
          ref: repo.defaultBranch);
      if (!mounted) return;
      setState(() {
        _ctrl.text = f.content;
        _sha = f.sha;
        _dirty = false;
        _loading = false;
      });
    } on FormatException {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'هذا الملف غير نصي ولا يمكن تحريره';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _errText(e);
        });
      }
    }
  }

  Future<String?> _askMessage() {
    final c = TextEditingController(text: 'Update $_path');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رسالة الـ Commit'),
        content: TextField(controller: c, textDirection: TextDirection.ltr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Commit')),
        ],
      ),
    );
  }

  Future<void> _commit() async {
    final repo = _repo;
    final api = appState.api;
    if (repo == null || api == null) return;
    final msg = await _askMessage();
    if (msg == null || msg.isEmpty) return;
    setState(() => _saving = true);
    try {
      final sha = await api.writeFile(
          repo.owner, repo.name, _path, _ctrl.text, msg,
          sha: _sha, branch: repo.defaultBranch);
      if (!mounted) return;
      setState(() {
        _sha = sha;
        _dirty = false;
        _saving = false;
      });
      _toast(context, 'تم الـ Commit على ${repo.defaultBranch}');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast(context, _errText(e));
      }
    }
  }

  Future<void> _pickFile() async {
    final repo = _repo;
    final api = appState.api;
    if (repo == null || api == null) return;
    final p = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FileBrowser(api: api, repo: repo),
    );
    if (p != null) {
      _path = p;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    if (repo == null) {
      return const Center(child: Text('اختر مشروعًا من تبويب المشاريع'));
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _path,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              StatusChip(repo.defaultBranch, Colors.grey),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Card(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(_error!,
                                style: const TextStyle(color: _bad),
                                textAlign: TextAlign.center),
                          ),
                        )
                      : TextField(
                          controller: _ctrl,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          textDirection: TextDirection.ltr,
                          onChanged: (_) {
                            if (!_dirty) setState(() => _dirty = true);
                          },
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13, height: 1.6),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.all(14),
                          ),
                        ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _dirty && !_saving ? _commit : null,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Commit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                    onPressed: _pickFile, child: const Text('الملفات')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                    onPressed: widget.onBuild, child: const Text('بناء')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FileBrowser extends StatefulWidget {
  const FileBrowser({super.key, required this.api, required this.repo});
  final GitHubApi api;
  final Repo repo;

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  String _dir = '';
  List<RepoEntry>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final l = await widget.api.listDir(
          widget.repo.owner, widget.repo.name, _dir,
          ref: widget.repo.defaultBranch);
      l.sort((a, b) => a.isDir == b.isDir
          ? a.name.compareTo(b.name)
          : (a.isDir ? -1 : 1));
      if (mounted) setState(() => _items = l);
    } catch (e) {
      if (mounted) setState(() => _error = _errText(e));
    }
  }

  void _up() {
    final i = _dir.lastIndexOf('/');
    _dir = i < 0 ? '' : _dir.substring(0, i);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: _bad)))
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    if (_dir.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.arrow_upward),
                        title: const Text('..'),
                        onTap: _up,
                      ),
                    for (final e in items)
                      ListTile(
                        leading: Icon(e.isDir
                            ? Icons.folder_outlined
                            : Icons.description_outlined),
                        title: Text(e.name, textDirection: TextDirection.ltr),
                        onTap: () {
                          if (e.isDir) {
                            _dir = e.path;
                            _load();
                          } else {
                            Navigator.pop(context, e.path);
                          }
                        },
                      ),
                  ],
                ),
    );
  }
}

// ───────────── البناء ─────────────

class BuildPage extends StatefulWidget {
  const BuildPage({super.key});

  @override
  State<BuildPage> createState() => _BuildPageState();
}

class _BuildPageState extends State<BuildPage> {
  String _target = 'apk'; // apk | appbundle
  BuildSnapshot? _snap;
  bool _running = false;
  bool _downloading = false;
  String? _error;
  StreamSubscription<BuildSnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    appState.addListener(_reset);
  }

  @override
  void dispose() {
    appState.removeListener(_reset);
    _sub?.cancel();
    super.dispose();
  }

  String? _lastRepo;

  void _reset() {
    final name = appState.current?.fullName;
    if (name != _lastRepo) {
      _lastRepo = name;
      _sub?.cancel();
      setState(() {
        _snap = null;
        _running = false;
        _error = null;
      });
    }
  }

  Future<void> _start() async {
    final repo = appState.current;
    final api = appState.api;
    if (repo == null || api == null) return;
    final startedAt = DateTime.now();
    setState(() {
      _running = true;
      _snap = null;
      _error = null;
    });
    try {
      await api.dispatchBuild(repo.owner, repo.name,
          branch: repo.defaultBranch, target: _target);
    } catch (e) {
      final notFound = e is GitHubException && e.statusCode == 404;
      setState(() {
        _running = false;
        _error = notFound
            ? 'لم يُعثر على build.yml في المستودع. أنشئ المشروع من التطبيق أو أضف الملف يدويًا.'
            : _errText(e);
      });
      return;
    }
    _sub?.cancel();
    _sub = api
        .watchBuild(repo.owner, repo.name,
            branch: repo.defaultBranch, startedAt: startedAt)
        .listen(
      (s) => setState(() => _snap = s),
      onError: (Object e) => setState(() {
        _running = false;
        _error = _errText(e);
      }),
      onDone: () => setState(() => _running = false),
    );
  }

  Future<void> _download(BuildArtifact a) async {
    final repo = appState.current;
    final api = appState.api;
    if (repo == null || api == null) return;
    setState(() => _downloading = true);
    try {
      final bytes = await api.downloadArtifact(repo.owner, repo.name, a.id);
      final archive = ZipDecoder().decodeBytes(bytes);
      final dir = await getTemporaryDirectory();
      final paths = <XFile>[];
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final out = File('${dir.path}/${f.name.split('/').last}');
        await out.writeAsBytes(f.content as List<int>);
        paths.add(XFile(out.path));
      }
      if (paths.isEmpty) throw GitHubException('الملف المضغوط فارغ');
      await Share.shareXFiles(paths);
    } catch (e) {
      if (mounted) _toast(context, _errText(e));
    }
    if (mounted) setState(() => _downloading = false);
  }

  Widget _stepChip(BuildStep s) {
    if (s.isDone) {
      if (s.failed) return const StatusChip('فشل', _bad);
      if (s.conclusion == 'skipped') {
        return const StatusChip('تم تخطيه', Colors.grey);
      }
      return const StatusChip('تم', _ok);
    }
    if (s.isRunning) return const StatusChip('جارٍ', _warn);
    return const StatusChip('بانتظار', Colors.grey);
  }

  @override
  Widget build(BuildContext context) {
    final repo = appState.current;
    if (repo == null) {
      return const Center(child: Text('اختر مشروعًا من تبويب المشاريع'));
    }
    final snap = _snap;
    final Widget status;
    if (snap == null) {
      status = StatusChip(_running ? 'قيد التشغيل' : 'جاهز', Colors.grey);
    } else if (!snap.isFinished) {
      status = const StatusChip('قيد التنفيذ', _warn);
    } else if (snap.succeeded) {
      status = const StatusChip('اكتمل', _ok);
    } else {
      status = const StatusChip('فشل', _bad);
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('بناء المشروع',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            status,
          ],
        ),
        const SizedBox(height: 6),
        Text(repo.fullName,
            textDirection: TextDirection.ltr,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13)),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'apk', label: Text('APK')),
            ButtonSegment(value: 'appbundle', label: Text('AAB')),
          ],
          selected: {_target},
          onSelectionChanged:
              _running ? null : (s) => setState(() => _target = s.first),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: snap == null || snap.steps.isEmpty
                ? Text(
                    _running ? 'جارٍ تشغيل البناء على GitHub...' : 'لم يبدأ بناء بعد',
                    textAlign: TextAlign.center)
                : Column(
                    children: [
                      for (final s in snap.steps)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(child: Text(s.name)),
                              _stepChip(s),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: _bad)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: _running ? null : _start,
          child: Text(snap == null ? 'بدء البناء' : 'إعادة البناء'),
        ),
        if (snap != null && snap.isFinished) ...[
          const SizedBox(height: 10),
          for (final a in snap.artifacts.where((a) => !a.expired))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _downloading ? null : () => _download(a),
                child: Text(_downloading ? 'جارٍ التنزيل...' : 'تنزيل ومشاركة الناتج'),
              ),
            ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => launchUrl(Uri.parse(snap.htmlUrl),
                mode: LaunchMode.externalApplication),
            child: const Text('عرض السجل على GitHub'),
          ),
        ],
      ],
    );
  }
}
