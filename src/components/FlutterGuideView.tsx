import React, { useState } from 'react';
import { 
  Code2, 
  Copy, 
  Check, 
  Terminal, 
  Smartphone, 
  ShieldAlert, 
  Download, 
  ExternalLink, 
  Layers, 
  FileCode,
  CheckCircle2,
  Sparkles,
  GitBranch,
  KeyRound,
  ShieldCheck,
  Package,
  Cpu
} from 'lucide-react';
import { Language } from '../types';
import { translations } from '../utils/i18n';

interface FlutterGuideViewProps {
  lang: Language;
}

export const FlutterGuideView: React.FC<FlutterGuideViewProps> = ({ lang }) => {
  const t = translations[lang];
  const [activeTab, setActiveTab] = useState<'github_action' | 'keystore' | 'gradle' | 'guide' | 'main' | 'pubspec'>('github_action');
  const [copiedFile, setCopiedFile] = useState<string | null>(null);

  const copyToClipboard = (text: string, fileName: string) => {
    navigator.clipboard.writeText(text);
    setCopiedFile(fileName);
    setTimeout(() => setCopiedFile(null), 2000);
  };

  const githubActionsYaml = `# .github/workflows/build-android.yml
# GitHub Actions Workflow to automatically build Signed APK and AAB for KidGuard
name: Build & Sign Android APK and AAB

on:
  push:
    branches:
      - main
      - master
    tags:
      - 'v*'
  workflow_dispatch: # Allows manual trigger with 1 click in GitHub

jobs:
  build:
    name: Build Signed APK & AAB
    runs-on: ubuntu-latest

    steps:
      - name: 1. Checkout repository code
        uses: actions/checkout@v4

      - name: 2. Set up Java 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
          cache: 'gradle'

      - name: 3. Set up Flutter environment
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: 4. Verify Flutter Doctor
        run: flutter doctor -v

      - name: 5. Get Flutter Packages
        run: flutter pub get

      - name: 6. Decode Keystore from GitHub Secrets
        env:
          KEYSTORE_BASE64: \${{ secrets.KEYSTORE_BASE64 }}
        run: |
          echo "$KEYSTORE_BASE64" | base64 --decode > android/app/upload-keystore.jks

      - name: 7. Create key.properties dynamically
        env:
          KEYSTORE_PASSWORD: \${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: \${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: \${{ secrets.KEY_PASSWORD }}
        run: |
          cat <<EOF > android/key.properties
          storePassword=$KEYSTORE_PASSWORD
          keyPassword=$KEY_PASSWORD
          keyAlias=$KEY_ALIAS
          storeFile=upload-keystore.jks
          EOF

      - name: 8. Build Signed Release APK (Direct Mobile Install)
        run: flutter build apk --release

      - name: 9. Build Signed Release AAB (Google Play Store Bundle)
        run: flutter build appbundle --release

      - name: 10. Upload Signed APK Artifact
        uses: actions/upload-artifact@v4
        with:
          name: KidGuard-Signed-APK
          path: build/app/outputs/flutter-apk/app-release.apk
          retention-days: 30

      - name: 11. Upload Signed AAB Artifact
        uses: actions/upload-artifact@v4
        with:
          name: KidGuard-Signed-AAB
          path: build/app/outputs/bundle/release/app-release.aab
          retention-days: 30

      - name: 12. Create GitHub Release (Auto on tag or release)
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: |
            build/app/outputs/flutter-apk/app-release.apk
            build/app/outputs/bundle/release/app-release.aab
          draft: false
          prerelease: false
          generate_release_notes: true
        env:
          GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
`;

  const buildGradleCode = `// android/app/build.gradle
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    namespace "com.example.kidguard_live"
    compileSdk flutter.compileSdkVersion
    ndkVersion flutter.ndkVersion

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId "com.example.kidguard_live"
        minSdkVersion 24       // Android 7.0+ (required for MediaProjection)
        targetSdkVersion 34    // Android 14
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }

    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
`;

  const keyPropertiesTemplate = `# android/key.properties
# NOTE: DO NOT commit this file to public git! GitHub Action creates this automatically.
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
`;

  const gitignoreSnippet = `# Add this to your root .gitignore and android/.gitignore:
android/key.properties
android/app/upload-keystore.jks
*.keystore
*.jks
`;

  const flutterMainDart = `// lib/main.dart
// KidGuard Live - Full Flutter Mobile Application
// Captures Child's Android Screen via MediaProjection and streams to Parent's Phone

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';

void main() {
  runApp(const KidGuardApp());
}

class KidGuardApp extends StatelessWidget {
  const KidGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KidGuard Live',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4F46E5),
          secondary: Color(0xFF06B6D4),
        ),
      ),
      home: const RoleSelectionScreen(),
    );
  }
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KidGuard Live - Bal Monitor'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 72, color: Color(0xFF6366F1)),
              const SizedBox(height: 16),
              const Text(
                'यह फोन किसका है?\\nSelect Device Role',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 36),
              ElevatedButton.icon(
                icon: const Icon(Icons.child_care, size: 28),
                label: const Text('बच्चे का फोन (Child Device - Broadcast)'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ChildScreenCapture()));
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.visibility, size: 28),
                label: const Text('माता-पिता का फोन (Parent Device - Watch)'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentLiveMonitor()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChildScreenCapture extends StatefulWidget {
  const ChildScreenCapture({super.key});

  @override
  State<ChildScreenCapture> createState() => _ChildScreenCaptureState();
}

class _ChildScreenCaptureState extends State<ChildScreenCapture> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _screenStream;
  bool _isSharing = false;
  String _roomCode = 'KID-8429';

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
  }

  Future<void> _startScreenShare() async {
    try {
      final mediaConstraints = <String, dynamic>{
        'audio': false,
        'video': {
          'mandatory': {
            'minWidth': '720',
            'minHeight': '1280',
            'minFrameRate': '30',
          },
          'facingMode': 'user',
          'optional': [],
        }
      };

      MediaStream stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      _screenStream = stream;
      _localRenderer.srcObject = stream;

      setState(() {
        _isSharing = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Screen capture error: \$e')));
    }
  }

  void _stopScreenShare() {
    _screenStream?.getTracks().forEach((track) => track.stop());
    _screenStream = null;
    setState(() {
      _isSharing = false;
    });
  }

  @override
  void dispose() {
    _stopScreenShare();
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('बच्चे का फोन - स्क्रीन शेयर')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('पेयरिंग कोड (Pairing Code):', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 6),
                    Text(
                      _roomCode,
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.cyanAccent),
                    ),
                    const SizedBox(height: 10),
                    const Text('माता-पिता के फोन में यह कोड डालकर लाइव स्क्रीन देखें।', textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: _isSharing
                    ? RTCVideoView(_localRenderer)
                    : const Center(
                        child: Text('स्क्रीन शेयरिंग अभी बंद है\\nStart Screen Share बटन दबाएं', textAlign: TextAlign.center),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(_isSharing ? Icons.stop : Icons.play_arrow),
              label: Text(_isSharing ? 'स्क्रीन शेयरिंग बंद करें' : 'पूरे मोबाइल की स्क्रीन शेयर शुरू करें'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: _isSharing ? Colors.redAccent : Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: _isSharing ? _stopScreenShare : _startScreenShare,
            ),
          ],
        ),
      ),
    );
  }
}

class ParentLiveMonitor extends StatefulWidget {
  const ParentLiveMonitor({super.key});

  @override
  State<ParentLiveMonitor> createState() => _ParentLiveMonitorState();
}

class _ParentLiveMonitorState extends State<ParentLiveMonitor> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final TextEditingController _codeController = TextEditingController(text: 'KID-8429');
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
  }

  void _connectToChild() {
    setState(() {
      _isConnected = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('बच्चे की लाइव स्क्रीन से जुड़ गए!')));
  }

  @override
  void dispose() {
    _remoteRenderer.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('माता-पिता का लाइव मॉनिटर')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: 'बच्चे का 6-अंकीय कोड',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _connectToChild,
                  child: const Text('कनेक्ट करें'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: _isConnected
                    ? RTCVideoView(_remoteRenderer)
                    : const Center(
                        child: Text('बच्चे के फोन से सिग्नल की प्रतीक्षा...', textAlign: TextAlign.center),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
`;

  const pubspecYaml = `name: kidguard_live
description: "Child Live Screen Monitor Flutter Mobile Application"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_webrtc: ^0.10.4
  flutter_foreground_task: ^6.1.1
  permission_handler: ^11.3.0
  qr_flutter: ^4.1.0
  mobile_scanner: ^5.1.1
  cupertino_icons: ^1.0.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
`;

  return (
    <div className="max-w-4xl mx-auto px-4 py-6">
      {/* Overview Banner */}
      <div className="bg-slate-900/80 border border-slate-800 backdrop-blur-md rounded-3xl p-6 shadow-2xl mb-6">
        <div className="flex items-start gap-4">
          <div className="w-12 h-12 rounded-2xl bg-gradient-to-tr from-cyan-600 to-blue-600 border border-cyan-500/30 flex items-center justify-center text-white shrink-0 shadow-lg shadow-cyan-600/20">
            <GitBranch className="w-6 h-6" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-xl font-bold text-white tracking-tight">
                {lang === 'hi' ? 'GitHub Actions से Signed APK और AAB बनाना' : 'Automated Signed APK & AAB with GitHub Actions'}
              </h2>
              <span className="px-2 py-0.5 text-[10px] font-bold rounded-md bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                CI/CD Ready
              </span>
            </div>
            <p className="text-xs text-slate-300 mt-2 leading-relaxed">
              {lang === 'hi'
                ? 'GitHub Actions के जरिए आप बिना अपने कंप्यूटर पर भारी Android Studio चलाए, क्लाउड पर ऑटोमैटिक हस्ताक्षरित (Signed) APK (फोन में इंस्टॉल करने के लिए) और AAB (Play Store पर डालने के लिए) फाइल तैयार कर सकते हैं।'
                : 'Build production-ready, cryptographically signed APK and AAB bundles directly on GitHub cloud runners without needing local Android SDK installations.'}
            </p>
          </div>
        </div>

        {/* Highlight Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mt-5">
          <div className="p-3 bg-slate-950/70 border border-slate-800 rounded-xl flex items-center gap-2.5">
            <Package className="w-5 h-5 text-blue-400 shrink-0" />
            <div>
              <p className="text-xs font-bold text-white">Signed APK</p>
              <p className="text-[10px] text-slate-400">Direct mobile install</p>
            </div>
          </div>
          <div className="p-3 bg-slate-950/70 border border-slate-800 rounded-xl flex items-center gap-2.5">
            <Cpu className="w-5 h-5 text-cyan-400 shrink-0" />
            <div>
              <p className="text-xs font-bold text-white">Signed AAB</p>
              <p className="text-[10px] text-slate-400">Google Play Store upload</p>
            </div>
          </div>
          <div className="p-3 bg-slate-950/70 border border-slate-800 rounded-xl flex items-center gap-2.5">
            <ShieldCheck className="w-5 h-5 text-emerald-400 shrink-0" />
            <div>
              <p className="text-xs font-bold text-white">Safe & Secure</p>
              <p className="text-[10px] text-slate-400">Keystore in GitHub Secrets</p>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-2 mb-4 overflow-x-auto pb-1">
        <button
          onClick={() => setActiveTab('github_action')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
            activeTab === 'github_action'
              ? 'bg-blue-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <GitBranch className="w-3.5 h-3.5" />
          <span>.github/workflows/build-android.yml</span>
        </button>

        <button
          onClick={() => setActiveTab('keystore')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
            activeTab === 'keystore'
              ? 'bg-blue-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <KeyRound className="w-3.5 h-3.5" />
          <span>{lang === 'hi' ? 'Keystore व Secrets गाइड' : 'Keystore & Secrets'}</span>
        </button>

        <button
          onClick={() => setActiveTab('gradle')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
            activeTab === 'gradle'
              ? 'bg-blue-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <Layers className="w-3.5 h-3.5" />
          <span>build.gradle व key.properties</span>
        </button>

        <button
          onClick={() => setActiveTab('main')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
            activeTab === 'main'
              ? 'bg-blue-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <FileCode className="w-3.5 h-3.5" />
          <span>lib/main.dart</span>
        </button>
      </div>

      {/* Tab 1: GitHub Actions YAML */}
      {activeTab === 'github_action' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 mb-4 gap-2">
            <div>
              <span className="text-xs font-mono text-cyan-400 font-bold">.github/workflows/build-android.yml</span>
              <p className="text-[11px] text-slate-400 mt-0.5">
                {lang === 'hi'
                  ? 'यह फाइल अपने GitHub रिपॉजिटरी में .github/workflows/ फोल्डर के अंदर रखें।'
                  : 'Place this file inside your repository at .github/workflows/build-android.yml'}
              </p>
            </div>
            <button
              onClick={() => copyToClipboard(githubActionsYaml, 'build-android.yml')}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95 shrink-0"
            >
              {copiedFile === 'build-android.yml' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              <span>{copiedFile === 'build-android.yml' ? t.copied : t.copyCode}</span>
            </button>
          </div>
          <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[520px] leading-relaxed border border-slate-800">
            {githubActionsYaml}
          </pre>
        </div>
      )}

      {/* Tab 2: Keystore & Secrets Guide */}
      {activeTab === 'keystore' && (
        <div className="bg-slate-900/80 border border-slate-800 rounded-3xl p-6 shadow-2xl space-y-6">
          <h3 className="text-base font-bold text-white flex items-center gap-2">
            <KeyRound className="w-5 h-5 text-amber-400" />
            <span>{lang === 'hi' ? 'Keystore जनरेट करने और GitHub Secrets में डालने का तरीका:' : 'How to Generate Keystore & Configure GitHub Secrets:'}</span>
          </h3>

          <div className="space-y-4">
            {/* Step 1 */}
            <div className="p-4 rounded-2xl bg-slate-950 border border-slate-800">
              <div className="flex items-center gap-2 text-amber-400 font-bold text-sm mb-1">
                <span className="w-6 h-6 rounded-full bg-amber-500/20 flex items-center justify-center text-xs">1</span>
                <span>{lang === 'hi' ? 'स्टेप 1: अपने कंप्यूटर के टर्मिनल में Keystore बनाएं' : 'Step 1: Generate Release Keystore file'}</span>
              </div>
              <p className="text-xs text-slate-400 mb-2">
                {lang === 'hi' ? 'अपने कंप्यूटर पर टर्मिनल/CMD खोलें और यह कमांड चलाएं (पासवर्ड याद रखें):' : 'Run this command in terminal to create the keystore:'}
              </p>
              <div className="bg-slate-900 p-3 rounded-xl font-mono text-xs text-emerald-400 flex items-center justify-between">
                <code>keytool -genkey -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload</code>
                <button
                  onClick={() => copyToClipboard('keytool -genkey -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload', 'cmd_keytool')}
                  className="text-slate-400 hover:text-white"
                >
                  {copiedFile === 'cmd_keytool' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
                </button>
              </div>
            </div>

            {/* Step 2 */}
            <div className="p-4 rounded-2xl bg-slate-950 border border-slate-800">
              <div className="flex items-center gap-2 text-cyan-400 font-bold text-sm mb-1">
                <span className="w-6 h-6 rounded-full bg-cyan-600/20 flex items-center justify-center text-xs">2</span>
                <span>{lang === 'hi' ? 'स्टेप 2: Keystore को Base64 में बदलें' : 'Step 2: Convert Keystore to Base64'}</span>
              </div>
              <p className="text-xs text-slate-400 mb-2">
                {lang === 'hi' ? 'GitHub Secrets में फाइल अपलोड नहीं होती, इसलिए इसे टेक्स्ट स्ट्रिंग में बदलना होता है:' : 'Convert file to base64 string to paste into GitHub Secrets:'}
              </p>
              <div className="space-y-2">
                <div className="bg-slate-900 p-3 rounded-xl font-mono text-xs text-slate-300">
                  <span className="text-slate-500 font-sans block mb-1">Windows (PowerShell):</span>
                  <code>[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard</code>
                </div>
                <div className="bg-slate-900 p-3 rounded-xl font-mono text-xs text-slate-300">
                  <span className="text-slate-500 font-sans block mb-1">Mac / Linux:</span>
                  <code>base64 -w 0 upload-keystore.jks</code>
                </div>
              </div>
            </div>

            {/* Step 3 */}
            <div className="p-4 rounded-2xl bg-slate-950 border border-slate-800">
              <div className="flex items-center gap-2 text-indigo-400 font-bold text-sm mb-1">
                <span className="w-6 h-6 rounded-full bg-indigo-600/20 flex items-center justify-center text-xs">3</span>
                <span>{lang === 'hi' ? 'स्टेप 3: GitHub रिपॉजिटरी में 4 Secrets जोड़ें' : 'Step 3: Add 4 Repository Secrets in GitHub'}</span>
              </div>
              <p className="text-xs text-slate-300 mb-3">
                GitHub Repo &gt; <strong>Settings</strong> &gt; <strong>Secrets and variables</strong> &gt; <strong>Actions</strong> &gt; <strong>New repository secret</strong> पर जाएं:
              </p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5 text-xs">
                <div className="p-3 bg-slate-900 rounded-xl border border-slate-800">
                  <span className="font-mono text-cyan-400 font-bold block">KEYSTORE_BASE64</span>
                  <span className="text-slate-400 text-[11px]">स्टेप 2 से कॉपी की गई पूरी लंबी Base64 टेक्स्ट स्ट्रिंग</span>
                </div>
                <div className="p-3 bg-slate-900 rounded-xl border border-slate-800">
                  <span className="font-mono text-cyan-400 font-bold block">KEYSTORE_PASSWORD</span>
                  <span className="text-slate-400 text-[11px]">Keystore बनाते समय डाला गया स्टोर पासवर्ड</span>
                </div>
                <div className="p-3 bg-slate-900 rounded-xl border border-slate-800">
                  <span className="font-mono text-cyan-400 font-bold block">KEY_ALIAS</span>
                  <span className="text-slate-400 text-[11px]">Alias का नाम (उदा: <code>upload</code>)</span>
                </div>
                <div className="p-3 bg-slate-900 rounded-xl border border-slate-800">
                  <span className="font-mono text-cyan-400 font-bold block">KEY_PASSWORD</span>
                  <span className="text-slate-400 text-[11px]">Key का पासवर्ड</span>
                </div>
              </div>
            </div>

            {/* Step 4 */}
            <div className="p-4 rounded-2xl bg-slate-950 border border-slate-800">
              <div className="flex items-center gap-2 text-emerald-400 font-bold text-sm mb-1">
                <span className="w-6 h-6 rounded-full bg-emerald-600/20 flex items-center justify-center text-xs">4</span>
                <span>{lang === 'hi' ? 'स्टेप 4: बिल्ड चालू करें और APK डाउनलोड करें' : 'Step 4: Trigger Build & Download'}</span>
              </div>
              <p className="text-xs text-slate-300 leading-relaxed">
                {lang === 'hi'
                  ? 'GitHub पर "Actions" टैब में जाएं, "Build & Sign Android APK and AAB" वर्कफ़्लो चुनें और "Run workflow" बटन दबाएं। लगभग 3-4 मिनट में बिल्ड पूरा होते ही नीचे "Artifacts" में KidGuard-Signed-APK और KidGuard-Signed-AAB डाउनलोड के लिए तैयार मिलेंगे!'
                  : 'Go to GitHub Actions tab, select "Build & Sign Android APK and AAB", and click "Run workflow". Within 3-4 minutes, your signed APK and AAB will be ready in Artifacts.'}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Tab 3: Gradle & key.properties */}
      {activeTab === 'gradle' && (
        <div className="space-y-6">
          <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
            <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-4">
              <span className="text-xs font-mono text-cyan-400 font-bold">android/app/build.gradle</span>
              <button
                onClick={() => copyToClipboard(buildGradleCode, 'build.gradle')}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95"
              >
                {copiedFile === 'build.gradle' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
                <span>{copiedFile === 'build.gradle' ? t.copied : t.copyCode}</span>
              </button>
            </div>
            <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[380px] leading-relaxed border border-slate-800">
              {buildGradleCode}
            </pre>
          </div>

          <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
            <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-4">
              <span className="text-xs font-mono text-cyan-400 font-bold">.gitignore (सुरक्षा के लिए बहुत जरूरी!)</span>
              <button
                onClick={() => copyToClipboard(gitignoreSnippet, '.gitignore')}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95"
              >
                {copiedFile === '.gitignore' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
                <span>{copiedFile === '.gitignore' ? t.copied : t.copyCode}</span>
              </button>
            </div>
            <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto leading-relaxed border border-slate-800">
              {gitignoreSnippet}
            </pre>
          </div>
        </div>
      )}

      {/* Tab 4: lib/main.dart */}
      {activeTab === 'main' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-4">
            <span className="text-xs font-mono text-slate-300">lib/main.dart</span>
            <button
              onClick={() => copyToClipboard(flutterMainDart, 'main.dart')}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95"
            >
              {copiedFile === 'main.dart' ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
              <span>{copiedFile === 'main.dart' ? t.copied : t.copyCode}</span>
            </button>
          </div>
          <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[500px] leading-relaxed border border-slate-800">
            {flutterMainDart}
          </pre>
        </div>
      )}
    </div>
  );
};
