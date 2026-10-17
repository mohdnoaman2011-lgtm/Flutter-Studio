/// قوالب الملفات التي تُرسل إلى المستودع عند إنشاء مشروع من الجوال.

const kBuildWorkflowPath = '.github/workflows/build.yml';
const kBuildWorkflowFile = 'build.yml';

String toPackageName(String input) {
  var s = input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (s.isEmpty) return 'my_app';
  if (RegExp(r'^[0-9]').hasMatch(s)) s = 'app_$s';
  return s;
}

Map<String, String> starterFiles({
  required String packageName,
  String org = 'com.example',
}) {
  String fill(String t) =>
      t.replaceAll('__PACKAGE__', packageName).replaceAll('__ORG__', org);
  return {
    'pubspec.yaml': fill(_pubspec),
    'lib/main.dart': _mainDart,
    'test/widget_test.dart': _widgetTest,
    kBuildWorkflowPath: fill(_workflow),
  };
}

const _pubspec = r"""name: __PACKAGE__
description: A new Flutter project.
publish_to: none
version: 1.0.0+1

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
""";

const _mainDart = r"""import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const Scaffold(body: Center(child: Text('Hello Flutter'))),
    );
  }
}
""";

const _widgetTest = r"""import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanity', () => expect(1 + 1, 2));
}
""";

/// يبني APK أو AAB عند الطلب (workflow_dispatch) ويرفع الناتج كـ Artifact.
const _workflow = r"""name: Build Flutter

on:
  workflow_dispatch:
    inputs:
      target:
        description: apk or appbundle
        type: choice
        default: apk
        options:
          - apk
          - appbundle

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Create Android folder
        run: |
          flutter create --platforms=android --org __ORG__ --project-name __PACKAGE__ .
          git checkout -- lib pubspec.yaml test

      - name: Pub get
        run: flutter pub get

      - name: Analyze
        run: flutter analyze --no-fatal-infos

      - name: Test
        run: flutter test

      - name: Build
        run: flutter build ${{ inputs.target || 'apk' }} --release

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-release
          path: |
            build/app/outputs/flutter-apk/*.apk
            build/app/outputs/bundle/release/*.aab
""";
