import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// يُمرَّر عند التشغيل: flutter run --dart-define=GITHUB_CLIENT_ID=xxxx
const kGitHubClientId = String.fromEnvironment('GITHUB_CLIENT_ID');

class GitHubException implements Exception {
  GitHubException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'GitHubException($statusCode): $message';
}

class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
}

/// تسجيل الدخول عبر GitHub Device Flow.
/// لا يحتاج Client Secret، فهو مناسب لتطبيقات الجوال.
/// فعّل "Device Flow" من إعدادات OAuth App في GitHub.
class GitHubAuth {
  GitHubAuth({this.clientId = kGitHubClientId});

  final String clientId;

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'github_token';
  static const _json = {'Accept': 'application/json'};

  Future<String?> savedToken() => _storage.read(key: _tokenKey);

  Future<void> signOut() => _storage.delete(key: _tokenKey);

  Future<DeviceCode> start({String scope = 'repo workflow'}) async {
    if (clientId.isEmpty) {
      throw GitHubException('GITHUB_CLIENT_ID غير مضبوط (--dart-define)');
    }
    final res = await http.post(
      Uri.https('github.com', '/login/device/code'),
      headers: _json,
      body: {'client_id': clientId, 'scope': scope},
    );
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || j['error'] != null) {
      throw GitHubException(
          (j['error_description'] ?? j['error'] ?? res.body).toString(),
          res.statusCode);
    }
    return DeviceCode(
      deviceCode: j['device_code'] as String,
      userCode: j['user_code'] as String,
      verificationUri: j['verification_uri'] as String,
      expiresIn: j['expires_in'] as int,
      interval: j['interval'] as int,
    );
  }

  /// ينتظر حتى يوافق المستخدم على الرمز ثم يحفظ التوكن ويعيده.
  Future<String> pollForToken(DeviceCode code) async {
    var interval = code.interval;
    var failures = 0;
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(Duration(seconds: interval));
      Map<String, dynamic> j;
      try {
        final res = await http.post(
          Uri.https('github.com', '/login/oauth/access_token'),
          headers: _json,
          body: {
            'client_id': clientId,
            'device_code': code.deviceCode,
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          },
        ).timeout(const Duration(seconds: 20));
        j = jsonDecode(res.body) as Map<String, dynamic>;
        failures = 0;
      } catch (_) {
        // انقطاع مؤقت في الشبكة (مثلًا عند التبديل إلى المتصفح): نعيد المحاولة
        if (++failures >= 20) {
          throw GitHubException('تعذّر الاتصال بـ GitHub، تحقق من الإنترنت');
        }
        continue;
      }
      final token = j['access_token'];
      if (token is String) {
        await _storage.write(key: _tokenKey, value: token);
        return token;
      }
      switch (j['error']) {
        case 'authorization_pending':
          break;
        case 'slow_down':
          interval = (j['interval'] as int?) ?? interval + 5;
          break;
        case 'expired_token':
          throw GitHubException('انتهت صلاحية الرمز، أعد المحاولة');
        case 'access_denied':
          throw GitHubException('تم رفض التفويض');
        default:
          throw GitHubException(
              (j['error_description'] ?? j['error'] ?? 'خطأ غير معروف')
                  .toString());
      }
    }
    throw GitHubException('انتهت صلاحية الرمز، أعد المحاولة');
  }
}
