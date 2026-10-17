import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'github_auth.dart';

/// استخدمها هكذا:
/// final token = await Navigator.push<String>(context,
///     MaterialPageRoute(builder: (_) => GitHubLoginScreen(auth: auth)));
class GitHubLoginScreen extends StatefulWidget {
  const GitHubLoginScreen({super.key, required this.auth});
  final GitHubAuth auth;

  @override
  State<GitHubLoginScreen> createState() => _GitHubLoginScreenState();
}

class _GitHubLoginScreenState extends State<GitHubLoginScreen> {
  DeviceCode? _code;
  String? _error;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    setState(() {
      _code = null;
      _error = null;
    });
    try {
      final c = await widget.auth.start();
      if (!mounted) return;
      setState(() => _code = c);
      final token = await widget.auth.pollForToken(c);
      if (!mounted) return;
      Navigator.pop(context, token);
    } on GitHubException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول عبر GitHub')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _begin, child: const Text('إعادة المحاولة')),
                  ],
                )
              : code == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'افتح صفحة GitHub وأدخل هذا الرمز:',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          code.userCode,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: 36,
                            letterSpacing: 4,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        OutlinedButton(
                          onPressed: () => Clipboard.setData(
                              ClipboardData(text: code.userCode)),
                          child: const Text('نسخ الرمز'),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () => launchUrl(
                            Uri.parse(code.verificationUri),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text('فتح صفحة GitHub'),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'بانتظار التفويض...',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
