import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import 'github/github_auth.dart';

class SavedApk {
  const SavedApk(this.file, this.size, this.modified);
  final File file;
  final int size;
  final DateTime modified;

  String get name => file.path.split('/').last;

  static Future<SavedApk> fromFile(File f) async {
    final st = await f.stat();
    return SavedApk(f, st.size, st.modified);
  }
}

/// يحفظ ملفات apk/aab المستخرجة داخل مجلد التطبيق نفسه.
class ApkStore {
  static Future<Directory> _dir() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/builds');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// يفك ضغط ناتج GitHub Actions ويحفظ ملفات apk وaab فقط.
  static Future<List<SavedApk>> saveFromZip(
    List<int> zipBytes, {
    required String prefix,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final dir = await _dir();
    final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final out = <SavedApk>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final base = f.name.split('/').last;
      if (!base.endsWith('.apk') && !base.endsWith('.aab')) continue;
      final dot = base.lastIndexOf('.');
      final name =
          '$prefix-${base.substring(0, dot)}-$stamp${base.substring(dot)}';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(f.content as List<int>);
      out.add(await SavedApk.fromFile(file));
    }
    if (out.isEmpty) {
      throw GitHubException('لا يحتوي الناتج على ملف apk أو aab');
    }
    return out;
  }

  static Future<List<SavedApk>> list() async {
    final dir = await _dir();
    final out = <SavedApk>[];
    await for (final e in dir.list()) {
      if (e is File) out.add(await SavedApk.fromFile(e));
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  static Future<void> delete(SavedApk a) => a.file.delete();
}
