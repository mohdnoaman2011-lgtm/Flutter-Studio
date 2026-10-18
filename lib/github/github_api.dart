import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_auth.dart';
import 'github_templates.dart';

class Repo {
  const Repo({
    required this.name,
    required this.fullName,
    required this.isPrivate,
    required this.defaultBranch,
    required this.updatedAt,
  });

  final String name;
  final String fullName;
  final bool isPrivate;
  final String defaultBranch;
  final DateTime updatedAt;

  String get owner => fullName.split('/').first;

  factory Repo.fromJson(Map<String, dynamic> j) => Repo(
        name: j['name'] as String,
        fullName: j['full_name'] as String,
        isPrivate: j['private'] as bool,
        defaultBranch: (j['default_branch'] as String?) ?? 'main',
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

class RepoEntry {
  const RepoEntry(this.name, this.path, this.isDir);
  final String name;
  final String path;
  final bool isDir;
}

class RepoFile {
  const RepoFile(this.content, this.sha);
  final String content;
  final String sha;
}

class BuildStep {
  const BuildStep(this.name, this.status, this.conclusion);
  final String name;
  final String status; // queued | in_progress | completed
  final String? conclusion; // success | failure | skipped ...

  bool get isDone => status == 'completed';
  bool get isRunning => status == 'in_progress';
  bool get failed => conclusion == 'failure';
}

class BuildArtifact {
  const BuildArtifact(this.id, this.name, this.sizeBytes, this.expired);
  final int id;
  final String name;
  final int sizeBytes;
  final bool expired;
}

class BuildSnapshot {
  const BuildSnapshot({
    required this.runId,
    required this.status,
    required this.conclusion,
    required this.htmlUrl,
    required this.steps,
    required this.artifacts,
  });

  final int runId;
  final String status;
  final String? conclusion;
  final String htmlUrl;
  final List<BuildStep> steps;
  final List<BuildArtifact> artifacts;

  bool get isFinished => status == 'completed';
  bool get succeeded => conclusion == 'success';
}

class GitHubApi {
  GitHubApi(this.token);

  final String token;
  static const _host = 'api.github.com';

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $token',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final req = http.Request(method, Uri.https(_host, path, query))
      ..headers.addAll(_headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode >= 400) {
      var msg = res.body;
      try {
        final j = jsonDecode(res.body) as Map;
        msg = j['message'] as String? ?? msg;
        final errs = j['errors'];
        if (errs is List && errs.isNotEmpty) {
          final details = errs
              .map((e) => e is Map
                  ? (e['message'] ?? e['code'] ?? '').toString()
                  : e.toString())
              .where((t) => t.isNotEmpty)
              .join(' · ');
          if (details.isNotEmpty) msg = '$msg ($details)';
        }
      } catch (_) {}
      throw GitHubException(msg, res.statusCode);
    }
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  // ───── الحساب والمستودعات ─────

  Future<String> login() async {
    final j = await _send('GET', '/user') as Map<String, dynamic>;
    return j['login'] as String;
  }

  Future<List<Repo>> listRepos() async {
    final j = await _send('GET', '/user/repos',
        query: {'sort': 'updated', 'per_page': '50'}) as List;
    return j.map((e) => Repo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Repo> createRepo(String name,
      {bool private = true, String? description}) async {
    final j = await _send('POST', '/user/repos', body: {
      'name': name,
      'private': private,
      'auto_init': true,
      if (description != null) 'description': description,
    }) as Map<String, dynamic>;
    return Repo.fromJson(j);
  }

  // ───── الملفات ─────

  Future<List<RepoEntry>> listDir(String owner, String repo, String path,
      {String? ref}) async {
    final j = await _send(
      'GET',
      '/repos/$owner/$repo/contents/$path',
      query: ref == null ? null : {'ref': ref},
    ) as List;
    return j
        .map((e) => RepoEntry(
              e['name'] as String,
              e['path'] as String,
              e['type'] == 'dir',
            ))
        .toList();
  }

  Future<RepoFile> readFile(String owner, String repo, String path,
      {String? ref}) async {
    final j = await _send(
      'GET',
      '/repos/$owner/$repo/contents/$path',
      query: ref == null ? null : {'ref': ref},
    ) as Map<String, dynamic>;
    final raw = (j['content'] as String).replaceAll('\n', '');
    return RepoFile(utf8.decode(base64.decode(raw)), j['sha'] as String);
  }

  /// ينشئ الملف أو يعدّله (مرّر sha عند التعديل). يعيد sha الجديد.
  Future<String> writeFile(
    String owner,
    String repo,
    String path,
    String content,
    String message, {
    String? sha,
    String? branch,
  }) async {
    final j = await _send('PUT', '/repos/$owner/$repo/contents/$path', body: {
      'message': message,
      'content': base64.encode(utf8.encode(content)),
      if (sha != null) 'sha': sha,
      if (branch != null) 'branch': branch,
    }) as Map<String, dynamic>;
    return (j['content'] as Map<String, dynamic>)['sha'] as String;
  }

  /// يكتب ملفًا ثنائيًا (مثل صورة PNG) في المستودع.
  Future<void> writeBytes(
    String owner,
    String repo,
    String path,
    List<int> bytes,
    String message, {
    String? sha,
    String? branch,
  }) async {
    await _send('PUT', '/repos/$owner/$repo/contents/$path', body: {
      'message': message,
      'content': base64.encode(bytes),
      if (sha != null) 'sha': sha,
      if (branch != null) 'branch': branch,
    });
  }

  /// ينشئ مستودعًا ويرفع ملفات Flutter الأساسية وملف workflow للبناء.
  Future<Repo> bootstrapFlutterProject({
    required String name,
    String org = 'com.example',
    bool private = true,
    List<int>? iconPng,
  }) async {
    final repo = await createRepo(name, private: private);
    await Future.delayed(const Duration(seconds: 2));
    final files = starterFiles(
        packageName: toPackageName(name),
        org: org,
        withIcon: iconPng != null);
    // ملف workflow يُكتب أخيرًا حتى تكون كل الملفات موجودة قبل تشغيله
    final workflow = files.remove(kBuildWorkflowPath)!;
    for (final e in files.entries) {
      await writeFile(repo.owner, repo.name, e.key, e.value,
          'Add ${e.key}',
          branch: repo.defaultBranch);
    }
    if (iconPng != null) {
      await writeBytes(repo.owner, repo.name, 'assets/icon/icon.png', iconPng,
          'Add app icon',
          branch: repo.defaultBranch);
    }
    await writeFile(repo.owner, repo.name, kBuildWorkflowPath, workflow,
        'Add $kBuildWorkflowPath',
        branch: repo.defaultBranch);
    return repo;
  }

  // ───── البناء عبر GitHub Actions ─────

  Future<void> dispatchBuild(String owner, String repo,
      {required String branch, String target = 'apk'}) {
    return _send(
      'POST',
      '/repos/$owner/$repo/actions/workflows/$kBuildWorkflowFile/dispatches',
      body: {
        'ref': branch,
        'inputs': {'target': target},
      },
    );
  }

  Future<BuildSnapshot> snapshot(String owner, String repo, int runId) async {
    final base = '/repos/$owner/$repo/actions/runs/$runId';
    final run = await _send('GET', base) as Map<String, dynamic>;
    final jobs = await _send('GET', '$base/jobs') as Map<String, dynamic>;

    final steps = <BuildStep>[];
    final jobList = jobs['jobs'] as List;
    if (jobList.isNotEmpty) {
      for (final s in (jobList.first['steps'] as List? ?? const [])) {
        final name = s['name'] as String;
        // إخفاء الخطوات الداخلية التي يضيفها GitHub
        if (name == 'Set up job' ||
            name == 'Complete job' ||
            name.startsWith('Post ')) {
          continue;
        }
        steps.add(BuildStep(
            name, s['status'] as String, s['conclusion'] as String?));
      }
    }

    var artifacts = <BuildArtifact>[];
    if (run['status'] == 'completed') {
      final a = await _send('GET', '$base/artifacts') as Map<String, dynamic>;
      artifacts = (a['artifacts'] as List)
          .map((e) => BuildArtifact(e['id'] as int, e['name'] as String,
              e['size_in_bytes'] as int, e['expired'] as bool))
          .toList();
    }

    return BuildSnapshot(
      runId: runId,
      status: run['status'] as String,
      conclusion: run['conclusion'] as String?,
      htmlUrl: run['html_url'] as String,
      steps: steps,
      artifacts: artifacts,
    );
  }

  bool _isTransient(Object e) =>
      e is! GitHubException || (e.statusCode ?? 0) >= 500;

  /// يتابع التشغيل الجديد بعد dispatchBuild حتى ينتهي.
  /// أخطاء الشبكة العابرة لا توقف المتابعة، بل تُعاد المحاولة.
  Stream<BuildSnapshot> watchBuild(
    String owner,
    String repo, {
    required String branch,
    required DateTime startedAt,
    Duration poll = const Duration(seconds: 3),
  }) async* {
    int? runId;
    var failures = 0;
    for (var i = 0; i < 20 && runId == null; i++) {
      await Future.delayed(poll);
      try {
        final j =
            await _send('GET', '/repos/$owner/$repo/actions/runs', query: {
          'event': 'workflow_dispatch',
          'branch': branch,
          'per_page': '5',
        }) as Map<String, dynamic>;
        failures = 0;
        for (final r in (j['workflow_runs'] as List)) {
          final created = DateTime.parse(r['created_at'] as String);
          if (created
              .isAfter(startedAt.subtract(const Duration(seconds: 30)))) {
            runId = r['id'] as int;
            break;
          }
        }
      } catch (e) {
        if (!_isTransient(e) || ++failures >= 20) rethrow;
      }
    }
    if (runId == null) {
      throw GitHubException('لم يظهر تشغيل جديد في Actions');
    }
    yield* watchRun(owner, repo, runId, poll: poll);
  }

  /// يتابع تشغيلًا موجودًا حتى ينتهي (ويُستخدم أيضًا لاستئناف المتابعة).
  Stream<BuildSnapshot> watchRun(
    String owner,
    String repo,
    int runId, {
    Duration poll = const Duration(seconds: 3),
  }) async* {
    var failures = 0;
    while (true) {
      BuildSnapshot? s;
      try {
        s = await snapshot(owner, repo, runId);
        failures = 0;
      } catch (e) {
        if (!_isTransient(e) || ++failures >= 40) rethrow;
      }
      if (s != null) {
        yield s;
        if (s.isFinished) return;
      }
      await Future.delayed(poll);
    }
  }

  /// يعيد ملف zip يحتوي ناتج البناء (APK أو AAB).
  Future<List<int>> downloadArtifact(
      String owner, String repo, int artifactId) async {
    final req = http.Request(
      'GET',
      Uri.https(
          _host, '/repos/$owner/$repo/actions/artifacts/$artifactId/zip'),
    )
      ..headers.addAll(_headers)
      ..followRedirects = false;
    final res = await http.Response.fromStream(await req.send());
    final location = res.headers['location'];
    if (res.statusCode == 302 && location != null) {
      final file = await http.get(Uri.parse(location));
      if (file.statusCode != 200) {
        throw GitHubException('فشل تنزيل الملف', file.statusCode);
      }
      return file.bodyBytes;
    }
    throw GitHubException('تعذّر الحصول على رابط التنزيل', res.statusCode);
  }
}