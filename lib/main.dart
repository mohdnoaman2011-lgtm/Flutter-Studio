import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'apk_store.dart';
import 'github/github_api.dart';
import 'github/github_auth.dart';
import 'github/github_login_screen.dart';
import 'icon_maker.dart';
import 'theme.dart';
import 'widgets.dart';

// ───────────── أدوات مساعدة ─────────────

String errText(Object e) => e is GitHubException ? e.message : '$e';

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'الآن';
  if (d.inMinutes < 60) return 'قبل ${d.inMinutes} دقيقة';
  if (d.inHours < 24) return 'قبل ${d.inHours} ساعة';
  return 'قبل ${d.inDays} يوم';
}

String fmtSize(int b) => b >= 1048576
    ? '${(b / 1048576).toStringAsFixed(1)} MB'
    : '${(b / 1024).toStringAsFixed(0)} KB';

// ───────────── حالة التطبيق ─────────────

class AppState extends ChangeNotifier {
  final auth = GitHubAuth();
  GitHubApi? api;
  String? user;
  List<Repo> repos = [];
  List<SavedApk> saved = [];
  Repo? current;
  bool loadingRepos = false;
  String? error;

  bool get signedIn => api != null;
  String? get avatarUrl =>
      user == null ? null : 'https://github.com/$user.png?size=96';

  Future<void> restore() async {
    final t = await auth.savedToken();
    if (t != null) await signIn(t);
  }

  Future<void> signIn(String token) async {
    api = GitHubApi(token);
    try {
      user = await api!.login();
    } catch (e) {
      error = errText(e);
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
      error = errText(e);
    }
    loadingRepos = false;
    notifyListeners();
  }

  Future<void> loadSaved() async {
    try {
      saved = await ApkStore.list();
    } catch (_) {}
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
  await appState.loadSaved();
  runApp(const FlutterStudioApp());
}

class FlutterStudioApp extends StatelessWidget {
  const FlutterStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Studio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
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

// ───────────── شاشة البداية ─────────────

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  Future<void> _github(BuildContext context) async {
    final ok = await signInFlow(context);
    if (ok && context.mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Widget _feature(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            IconBadge(icon),
            const SizedBox(width: 14),
            Expanded(child: Text(text)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 112,
                  height: 112,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withAlpha(40),
                        blurRadius: 32,
                      ),
                    ],
                  ),
                  child: Image.asset('assets/icon/logo.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 24),
              Text('Flutter Studio',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'أنشئ مشاريع Flutter وعدّلها وابنِها من جوالك',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, height: 1.6),
              ),
              const SizedBox(height: 32),
              _feature(Icons.add_box_outlined, 'إنشاء مشروع بقالب جاهز'),
              _feature(Icons.edit_note, 'تحرير الملفات وCommit مباشرة'),
              _feature(Icons.rocket_launch_outlined,
                  'بناء APK عبر GitHub Actions وتثبيته'),
              const Spacer(flex: 3),
              FilledButton.icon(
                onPressed: () => _github(context),
                icon: const Icon(Icons.login),
                label: const Text('المتابعة عبر GitHub'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/home'),
                child: const Text('تصفّح بدون حساب'),
              ),
              const SizedBox(height: 16),
              const Text(
                'بالمتابعة فأنت توافق على الشروط وسياسة الخصوصية',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
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

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      ProjectsPage(onOpen: () => _go(1)),
      EditorPage(onBuild: () => _go(2)),
      BuildPage(onSaved: () {}),
      const DownloadsPage(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: 'المشاريع'),
          NavigationDestination(
              icon: Icon(Icons.code), label: 'المحرر'),
          NavigationDestination(
              icon: Icon(Icons.rocket_launch_outlined),
              selectedIcon: Icon(Icons.rocket_launch),
              label: 'البناء'),
          NavigationDestination(
              icon: Icon(Icons.download_for_offline_outlined),
              selectedIcon: Icon(Icons.download_for_offline),
              label: 'التنزيلات'),
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
        if (!appState.signedIn) {
          return EmptyState(
            icon: Icons.lock_outline,
            title: 'سجّل الدخول',
            subtitle: 'اربط حساب GitHub لعرض مشاريعك وبنائها',
            action: FilledButton(
              onPressed: () => signInFlow(context),
              child: const Text('المتابعة عبر GitHub'),
            ),
          );
        }

        final repos = appState.repos
            .where((r) => r.name.toLowerCase().contains(_q.toLowerCase()))
            .toList();
        final loading = appState.loadingRepos;

        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: appState.loadRepos,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.surfaceHigh,
                        backgroundImage: appState.avatarUrl == null
                            ? null
                            : NetworkImage(appState.avatarUrl!),
                        onBackgroundImageError: (_, __) {},
                        child: appState.avatarUrl == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ScreenHeader(
                          'مشاريعي',
                          subtitle:
                              '@${appState.user ?? '...'} · ${appState.repos.length} مستودع',
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (_) => appState.signOut(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'out', child: Text('تسجيل الخروج')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: const InputDecoration(
                      hintText: 'ابحث في المشاريع',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (loading && repos.isEmpty)
                    for (var i = 0; i < 4; i++)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Skeleton(),
                      ),
                  if (appState.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(appState.error!,
                          style: const TextStyle(color: AppColors.bad)),
                    ),
                  if (!loading && repos.isEmpty && appState.error == null)
                    const SizedBox(
                      height: 320,
                      child: EmptyState(
                        icon: Icons.folder_off_outlined,
                        title: 'لا توجد مشاريع',
                        subtitle: 'أنشئ مشروعًا جديدًا أو غيّر كلمة البحث',
                      ),
                    ),
                  for (final r in repos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RepoCard(
                        repo: r,
                        selected: appState.current?.fullName == r.fullName,
                        onTap: () {
                          appState.select(r);
                          widget.onOpen();
                        },
                      ),
                    ),
                ],
              ),
            ),
            PositionedDirectional(
              end: 20,
              bottom: 20,
              child: FloatingActionButton.extended(
                onPressed: () => Navigator.pushNamed(context, '/new'),
                icon: const Icon(Icons.add),
                label: const Text('مشروع جديد'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RepoCard extends StatelessWidget {
  const _RepoCard(
      {required this.repo, required this.selected, required this.onTap});
  final Repo repo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? AppColors.accent : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBadge(repo.isPrivate ? Icons.lock_outline : Icons.public),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(repo.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.call_split,
                            size: 14, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Text(repo.defaultBranch,
                            style: const TextStyle(
                                color: AppColors.muted, fontSize: 12)),
                        const SizedBox(width: 12),
                        const Icon(Icons.schedule,
                            size: 14, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Text(ago(repo.updatedAt),
                            style: const TextStyle(
                                color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.accent),
            ],
          ),
        ),
      ),
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
  int _icon = -1; // -1: بدون، 0..: قالب، -2: صورة من الجهاز
  Uint8List? _customPng;

  Future<void> _pickIcon() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null) return;
      final png = await customIconToPng(await x.readAsBytes());
      setState(() {
        _customPng = png;
        _icon = -2;
      });
    } catch (_) {
      if (mounted) toast(context, 'تعذّر قراءة الصورة');
    }
  }

  Widget _iconTile(
      {required bool selected,
      required VoidCallback onTap,
      required Widget child}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : onTap,
        child: Container(
          width: 64,
          height: 64,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _pkg.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final api = appState.api;
    if (api == null) {
      toast(context, 'سجّل الدخول عبر GitHub أولًا');
      return;
    }
    final name = _name.text.trim();
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
      toast(context, 'اسم المشروع: أحرف إنجليزية وأرقام و - _ . فقط');
      return;
    }
    final parts = _pkg.text.trim().split('.');
    final org = parts.length > 1
        ? parts.sublist(0, parts.length - 1).join('.')
        : 'com.example';

    setState(() => _busy = true);
    try {
      Uint8List? icon;
      if (_icon >= 0) {
        icon = await presetToPng(iconPresets[_icon]);
      } else if (_icon == -2) {
        icon = _customPng;
      }
      final repo = await api.bootstrapFlutterProject(
          name: name, org: org, private: _private, iconPng: icon);
      appState.addRepo(repo);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false,
          arguments: 1);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        final m = errText(e);
        toast(
            context,
            m.contains('already exists')
                ? 'يوجد مستودع بهذا الاسم في حسابك، اختر اسمًا آخر'
                : m);
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
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('جارٍ إنشاء المستودع ورفع الملفات...',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _name,
            enabled: !_busy,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'اسم المشروع',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pkg,
            enabled: !_busy,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'معرّف الحزمة',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 20),
          const Text('أيقونة التطبيق',
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _iconTile(
                  selected: _icon == -1,
                  onTap: () => setState(() => _icon = -1),
                  child: const Icon(Icons.block, color: AppColors.muted),
                ),
                for (var i = 0; i < iconPresets.length; i++)
                  _iconTile(
                    selected: _icon == i,
                    onTap: () => setState(() => _icon = i),
                    child: SizedBox.expand(
                      child: CustomPaint(painter: PresetPainter(iconPresets[i])),
                    ),
                  ),
                if (_customPng != null)
                  _iconTile(
                    selected: _icon == -2,
                    onTap: () => setState(() => _icon = -2),
                    child: Image.memory(_customPng!, fit: BoxFit.cover),
                  ),
                _iconTile(
                  selected: false,
                  onTap: _pickIcon,
                  child: const Icon(Icons.add_photo_alternate_outlined,
                      color: AppColors.accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _icon == -1
                ? 'الأيقونة الافتراضية من Flutter'
                : _icon == -2
                    ? 'صورة من جهازك'
                    : 'قالب: ${iconPresets[_icon].name}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Card(
            child: SwitchListTile(
              secondary: const IconBadge(Icons.lock_outline),
              title: const Text('مستودع خاص'),
              subtitle: const Text('أوقفه لإنشاء مستودع عام'),
              value: _private,
              onChanged: _busy ? null : (v) => setState(() => _private = v),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Icon(Icons.info_outline, size: 16, color: AppColors.muted),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'يُنشأ المستودع مع ملف Workflow لبناء Android عبر GitHub Actions.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_task),
            label: const Text('إنشاء وربط المستودع'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
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
          _error = errText(e);
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
      toast(context, 'تم الـ Commit على ${repo.defaultBranch}');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, errText(e));
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
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
      return const EmptyState(
        icon: Icons.code_off,
        title: 'لا يوجد مشروع محدد',
        subtitle: 'اختر مشروعًا من تبويب المشاريع لتحرير ملفاته',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(repo.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              Pill(repo.defaultBranch, AppColors.muted,
                  icon: Icons.call_split),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickFile,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined,
                        size: 18, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_path,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontFamily: 'monospace')),
                    ),
                    if (_dirty) ...[
                      const Pill('معدّل', AppColors.warn),
                      const SizedBox(width: 8),
                    ],
                    const Icon(Icons.unfold_more, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style:
                                    const TextStyle(color: AppColors.bad)),
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
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.6),
                          decoration: const InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.all(14),
                          ),
                        ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _dirty && !_saving ? _commit : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('Commit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: widget.onBuild,
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: const Text('بناء'),
                ),
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
      if (mounted) setState(() => _error = errText(e));
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
      height: MediaQuery.of(context).size.height * 0.65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                const Text('الملفات',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const Spacer(),
                Flexible(
                  child: Text(_dir.isEmpty ? '/' : '/$_dir',
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          color: AppColors.muted, fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _error != null
                ? Center(
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.bad)))
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
                              leading: Icon(
                                e.isDir
                                    ? Icons.folder_outlined
                                    : Icons.description_outlined,
                                color: e.isDir
                                    ? AppColors.accent
                                    : AppColors.muted,
                              ),
                              title: Text(e.name,
                                  textDirection: TextDirection.ltr),
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
          ),
        ],
      ),
    );
  }
}

// ───────────── البناء ─────────────

class BuildPage extends StatefulWidget {
  const BuildPage({super.key, required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<BuildPage> createState() => _BuildPageState();
}

class _BuildPageState extends State<BuildPage> {
  String _target = 'apk'; // apk | appbundle
  BuildSnapshot? _snap;
  bool _running = false;
  bool _saving = false;
  String? _error;
  List<SavedApk> _justSaved = const [];
  StreamSubscription<BuildSnapshot>? _sub;
  String? _lastRepo;

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

  void _reset() {
    final name = appState.current?.fullName;
    if (name != _lastRepo) {
      _lastRepo = name;
      _sub?.cancel();
      setState(() {
        _snap = null;
        _running = false;
        _error = null;
        _justSaved = const [];
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
      _justSaved = const [];
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
            : errText(e);
      });
      return;
    }
    _attach(api.watchBuild(repo.owner, repo.name,
        branch: repo.defaultBranch, startedAt: startedAt));
  }

  void _attach(Stream<BuildSnapshot> stream) {
    _sub?.cancel();
    _sub = stream.listen(
      (s) => setState(() => _snap = s),
      onError: (Object e) => setState(() {
        _running = false;
        _error = errText(e);
      }),
      onDone: () => setState(() => _running = false),
    );
  }

  /// يستأنف متابعة التشغيل نفسه بعد انقطاع الاتصال، دون بدء بناء جديد.
  void _resume() {
    final repo = appState.current;
    final api = appState.api;
    final id = _snap?.runId;
    if (repo == null || api == null || id == null) return;
    setState(() {
      _running = true;
      _error = null;
    });
    _attach(api.watchRun(repo.owner, repo.name, id));
  }

  /// ينزّل ناتج البناء، ويفك الضغط، ويحفظ ملف APK داخل التطبيق.
  Future<void> _extract(BuildArtifact a) async {
    final repo = appState.current;
    final api = appState.api;
    if (repo == null || api == null) return;
    setState(() => _saving = true);
    try {
      final bytes = await api.downloadArtifact(repo.owner, repo.name, a.id);
      final saved = await ApkStore.saveFromZip(bytes, prefix: repo.name);
      await appState.loadSaved();
      if (!mounted) return;
      setState(() => _justSaved = saved);
      toast(context, 'تم استخراج الملف وحفظه داخل التطبيق');
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _stepTile(BuildStep s) {
    final Widget icon;
    if (s.isDone) {
      if (s.failed) {
        icon = const Icon(Icons.cancel, color: AppColors.bad, size: 22);
      } else if (s.conclusion == 'skipped') {
        icon = const Icon(Icons.remove_circle_outline,
            color: AppColors.muted, size: 22);
      } else {
        icon = const Icon(Icons.check_circle, color: AppColors.ok, size: 22);
      }
    } else if (s.isRunning) {
      icon = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
            strokeWidth: 2.5, color: AppColors.warn),
      );
    } else {
      icon = const Icon(Icons.radio_button_unchecked,
          color: AppColors.muted, size: 22);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(width: 24, child: Center(child: icon)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(s.name,
                style: TextStyle(
                  color: s.isDone || s.isRunning
                      ? AppColors.text
                      : AppColors.muted,
                  fontWeight: s.isRunning ? FontWeight.w600 : FontWeight.w400,
                )),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = appState.current;
    if (repo == null) {
      return const EmptyState(
        icon: Icons.rocket_launch_outlined,
        title: 'لا يوجد مشروع محدد',
        subtitle: 'اختر مشروعًا من تبويب المشاريع لبدء البناء',
      );
    }
    final snap = _snap;
    final steps = snap?.steps ?? const <BuildStep>[];
    final done = steps.where((s) => s.isDone).length;

    final Widget status;
    if (snap == null) {
      status = Pill(_running ? 'قيد التشغيل' : 'جاهز', AppColors.muted);
    } else if (!snap.isFinished) {
      status = const Pill('قيد التنفيذ', AppColors.warn, icon: Icons.sync);
    } else if (snap.succeeded) {
      status = const Pill('اكتمل', AppColors.ok, icon: Icons.check);
    } else {
      status = const Pill('فشل', AppColors.bad, icon: Icons.close);
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ScreenHeader('بناء المشروع', subtitle: repo.fullName, trailing: status),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'apk',
                label: Text('APK'),
                icon: Icon(Icons.android)),
            ButtonSegment(
                value: 'appbundle',
                label: Text('AAB'),
                icon: Icon(Icons.inventory_2_outlined)),
          ],
          selected: {_target},
          onSelectionChanged:
              _running ? null : (s) => setState(() => _target = s.first),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _running ? null : _start,
          icon: const Icon(Icons.rocket_launch),
          label: Text(snap == null ? 'بدء البناء' : 'إعادة البناء'),
        ),
        const SizedBox(height: 20),
        if (_running || snap != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: steps.isEmpty ? null : done / steps.length,
              backgroundColor: AppColors.surfaceHigh,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: steps.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        _running
                            ? 'جارٍ تشغيل البناء على GitHub...'
                            : 'لم يبدأ بناء بعد',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                  )
                : Column(children: [for (final s in steps) _stepTile(s)]),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: AppColors.bad)),
          if (snap != null && !snap.isFinished) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _resume,
              child: const Text('استئناف المتابعة'),
            ),
          ],
        ],
        if (snap != null && snap.isFinished) ...[
          const SizedBox(height: 16),
          if (snap.succeeded)
            for (final a in snap.artifacts.where((a) => !a.expired))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const IconBadge(Icons.inventory_2_outlined,
                              color: AppColors.ok),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('ناتج البناء',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    '${a.name} · ${fmtSize(a.sizeBytes)}',
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _saving ? null : () => _extract(a),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.unarchive_outlined),
                        label: Text(_saving
                            ? 'جارٍ الاستخراج...'
                            : 'استخراج APK وحفظه داخل التطبيق'),
                      ),
                    ],
                  ),
                ),
              ),
          for (final s in _justSaved)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ApkTile(
                apk: s,
                onDeleted: () {
                  setState(() => _justSaved = _justSaved
                      .where((x) => x.file.path != s.file.path)
                      .toList());
                  appState.loadSaved();
                },
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(snap.htmlUrl),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('عرض السجل على GitHub'),
          ),
        ],
      ],
    );
  }
}

// ───────────── ملفات APK المحفوظة ─────────────

class ApkTile extends StatelessWidget {
  const ApkTile({super.key, required this.apk, required this.onDeleted});
  final SavedApk apk;
  final VoidCallback onDeleted;

  bool get _isApk => apk.name.endsWith('.apk');

  Future<void> _install(BuildContext c) async {
    final r = await OpenFilex.open(apk.file.path,
        type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done && c.mounted) toast(c, r.message);
  }

  Future<void> _delete(BuildContext c) async {
    final ok = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الملف؟'),
        content: Text(apk.name, textDirection: TextDirection.ltr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await ApkStore.delete(apk);
      onDeleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(_isApk ? Icons.android : Icons.inventory_2_outlined,
                    color: AppColors.ok),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(apk.name,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${fmtSize(apk.size)} · ${ago(apk.modified)}',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () => _delete(context),
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_isApk) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _install(context),
                      icon: const Icon(Icons.install_mobile),
                      label: const Text('تثبيت'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Share.shareXFiles([XFile(apk.file.path)]),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('مشاركة'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final items = appState.saved;
        return RefreshIndicator(
          onRefresh: appState.loadSaved,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              ScreenHeader('التنزيلات',
                  subtitle: '${items.length} ملف محفوظ داخل التطبيق'),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const SizedBox(
                  height: 420,
                  child: EmptyState(
                    icon: Icons.download_for_offline_outlined,
                    title: 'لا توجد ملفات بعد',
                    subtitle:
                        'بعد نجاح البناء اضغط «استخراج APK» في تبويب البناء لحفظ الملف هنا',
                  ),
                ),
              for (final a in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ApkTile(apk: a, onDeleted: appState.loadSaved),
                ),
            ],
          ),
        );
      },
    );
  }
}
