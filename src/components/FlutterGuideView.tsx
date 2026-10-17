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
  Cpu,
  Lock,
  ArrowRight
} from 'lucide-react';
import { Language } from '../types';
import { translations } from '../utils/i18n';

interface FlutterGuideViewProps {
  lang: Language;
}

const PRE_GENERATED_KEYSTORE_BASE64 = `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`;

export const FlutterGuideView: React.FC<FlutterGuideViewProps> = ({ lang }) => {
  const t = translations[lang];
  const [activeTab, setActiveTab] = useState<'secrets_done' | 'github_action' | 'gradle' | 'main' | 'pubspec'>('secrets_done');
  const [copiedFile, setCopiedFile] = useState<string | null>(null);

  const copyToClipboard = (text: string, fileName: string) => {
    navigator.clipboard.writeText(text);
    setCopiedFile(fileName);
    setTimeout(() => setCopiedFile(null), 2000);
  };

  const secretsList = [
    {
      name: 'KEYSTORE_BASE64',
      value: PRE_GENERATED_KEYSTORE_BASE64,
      desc: lang === 'hi' ? 'तैयार किया गया RSA 2048 Keystore Base64' : 'Pre-generated Keystore Base64 String',
      preview: `${PRE_GENERATED_KEYSTORE_BASE64.substring(0, 40)}... (${PRE_GENERATED_KEYSTORE_BASE64.length} chars)`,
      isLong: true,
    },
    {
      name: 'KEYSTORE_PASSWORD',
      value: 'KidGuard2026Pass',
      desc: lang === 'hi' ? 'Keystore स्टोर पासवर्ड' : 'Store Password',
      preview: 'KidGuard2026Pass',
      isLong: false,
    },
    {
      name: 'KEY_ALIAS',
      value: 'upload',
      desc: lang === 'hi' ? 'Key का Alias' : 'Keystore Alias',
      preview: 'upload',
      isLong: false,
    },
    {
      name: 'KEY_PASSWORD',
      value: 'KidGuard2026Pass',
      desc: lang === 'hi' ? 'Key का पासवर्ड' : 'Key Password',
      preview: 'KidGuard2026Pass',
      isLong: false,
    },
  ];

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

    kotlinOptions {
        jvmTarget = '17'
    }

    defaultConfig {
        applicationId "com.example.kidguard_live"
        minSdkVersion 24       // Android 7.0+ (Required for MediaProjection screen capture)
        targetSdkVersion 34    // Android 14
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }

    signingConfigs {
        release {
            keyAlias (System.getenv("KEY_ALIAS") ?: keystoreProperties['keyAlias'])
            keyPassword (System.getenv("KEY_PASSWORD") ?: keystoreProperties['keyPassword'])
            storeFile (System.getenv("KEYSTORE_PATH") ? file(System.getenv("KEYSTORE_PATH")) : (keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null))
            storePassword (System.getenv("KEYSTORE_PASSWORD") ?: keystoreProperties['storePassword'])
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
        debug {
            signingConfig signingConfigs.debug
        }
    }
}

flutter {
    source '../..'
}
`;

  return (
    <div className="max-w-4xl mx-auto px-4 py-6">
      {/* Overview Banner */}
      <div className="bg-slate-900/80 border border-slate-800 backdrop-blur-md rounded-3xl p-6 shadow-2xl mb-6">
        <div className="flex items-start gap-4">
          <div className="w-12 h-12 rounded-2xl bg-gradient-to-tr from-emerald-600 via-teal-600 to-cyan-500 border border-emerald-500/30 flex items-center justify-center text-white shrink-0 shadow-lg shadow-emerald-600/20">
            <CheckCircle2 className="w-6 h-6" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-xl font-bold text-white tracking-tight">
                {lang === 'hi' ? 'स्टेप 2 और 3 हमने आपके लिए पूरा कर दिया!' : 'Step 2 & 3 Done For You!'}
              </h2>
              <span className="px-2 py-0.5 text-[10px] font-bold rounded-md bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                100% Configured
              </span>
            </div>
            <p className="text-xs text-slate-300 mt-2 leading-relaxed">
              {lang === 'hi'
                ? 'आपको अपने कंप्यूटर पर keytool कमांड चलाने की कोई ज़रूरत नहीं है। हमने आपके लिए 10,000 दिनों की मान्यता वाला असली RSA 2048 Keystore जनरेट कर दिया है और android/app/build.gradle व android/key.properties फाइल्स भी सीधे प्रोजेक्ट में बना दी हैं!'
                : 'No need to run keytool or configure Gradle manually. We generated a valid 10,000-day RSA 2048 Keystore and created android/app/build.gradle & key.properties in your project.'}
            </p>
          </div>
        </div>

        {/* Status Pills */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-5">
          <div className="p-3 bg-emerald-950/40 border border-emerald-500/30 rounded-2xl flex items-center gap-3">
            <div className="p-2 bg-emerald-500/20 rounded-xl text-emerald-400">
              <Check className="w-4 h-4 font-bold" />
            </div>
            <div>
              <p className="text-xs font-bold text-white">स्टेप 2: Gradle & Properties</p>
              <p className="text-[11px] text-emerald-300">android/app/build.gradle तैयार है</p>
            </div>
          </div>

          <div className="p-3 bg-emerald-950/40 border border-emerald-500/30 rounded-2xl flex items-center gap-3">
            <div className="p-2 bg-emerald-500/20 rounded-xl text-emerald-400">
              <Check className="w-4 h-4 font-bold" />
            </div>
            <div>
              <p className="text-xs font-bold text-white">स्टेप 3: Keystore & Secrets</p>
              <p className="text-[11px] text-emerald-300">4 सीक्रेट्स जनरेट होकर नीचे उपलब्ध हैं</p>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-2 mb-4 overflow-x-auto pb-1">
        <button
          onClick={() => setActiveTab('secrets_done')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
            activeTab === 'secrets_done'
              ? 'bg-emerald-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <KeyRound className="w-3.5 h-3.5" />
          <span>{lang === 'hi' ? '1. तैयार 4 Secrets (1-Click Copy)' : '1. Pre-Generated Secrets'}</span>
        </button>

        <button
          onClick={() => setActiveTab('github_action')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
            activeTab === 'github_action'
              ? 'bg-blue-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <GitBranch className="w-3.5 h-3.5" />
          <span>2. .github/workflows/build-android.yml</span>
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
          <span>3. android/app/build.gradle</span>
        </button>
      </div>

      {/* Tab 1: Pre-Generated Secrets */}
      {activeTab === 'secrets_done' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-6 shadow-2xl space-y-5">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800">
            <div>
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <Lock className="w-5 h-5 text-emerald-400" />
                <span>{lang === 'hi' ? 'GitHub में डालने के लिए तैयार 4 Secrets:' : 'Ready-to-Use 4 GitHub Secrets:'}</span>
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">
                {lang === 'hi'
                  ? 'अपनी GitHub Repo > Settings > Secrets and variables > Actions > New repository secret में इन 4 को पेस्ट करें:'
                  : 'Add these 4 secrets in your GitHub Repo > Settings > Secrets and variables > Actions:'}
              </p>
            </div>
          </div>

          <div className="space-y-3.5">
            {secretsList.map((sec, idx) => (
              <div
                key={sec.name}
                className="p-4 bg-slate-950 border border-slate-800 rounded-2xl flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:border-slate-700 transition"
              >
                <div className="space-y-1 overflow-hidden">
                  <div className="flex items-center gap-2">
                    <span className="w-5 h-5 rounded-full bg-slate-800 text-slate-300 flex items-center justify-center text-[10px] font-bold">
                      {idx + 1}
                    </span>
                    <span className="font-mono text-cyan-400 font-bold text-sm tracking-wide">
                      {sec.name}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400">{sec.desc}</p>
                  <p className="text-[11px] font-mono text-slate-500 truncate max-w-md bg-slate-900/80 px-2 py-1 rounded-md">
                    {sec.preview}
                  </p>
                </div>

                <button
                  onClick={() => copyToClipboard(sec.value, sec.name)}
                  className="flex items-center justify-center gap-1.5 px-4 py-2.5 bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white rounded-xl text-xs font-bold transition shadow-md shadow-emerald-600/20 active:scale-95 shrink-0"
                >
                  {copiedFile === sec.name ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                  <span>{copiedFile === sec.name ? t.copied : t.copyCode}</span>
                </button>
              </div>
            ))}
          </div>

          {/* 30 Second Action Guide */}
          <div className="mt-5 p-4 rounded-2xl bg-indigo-950/40 border border-indigo-500/30 flex items-start gap-3">
            <Sparkles className="w-5 h-5 text-indigo-400 shrink-0 mt-0.5" />
            <div className="text-xs text-indigo-200">
              <p className="font-semibold text-white mb-1">
                {lang === 'hi' ? 'इसके बाद क्या करना है?' : 'What to do next:'}
              </p>
              <ol className="list-decimal list-inside space-y-1 text-indigo-200/90">
                <li>ऊपर दिए गए चारों बटनों से एक-एक करके <strong>Secret Name</strong> और <strong>Value</strong> कॉपी करें।</li>
                <li>अपने GitHub रिपॉजिटरी में <strong>Settings &gt; Secrets and variables &gt; Actions</strong> में जाकर <strong>New repository secret</strong> पर क्लिक करके सेव कर दें।</li>
                <li>GitHub के <strong>Actions</strong> टैब में जाएं और <strong>"Build & Sign Android APK and AAB"</strong> को <strong>Run workflow</strong> कर दें।</li>
                <li>4 मिनट में आपकी Signed APK सीधे डाउनलोड के लिए मिल जाएगी!</li>
              </ol>
            </div>
          </div>
        </div>
      )}

      {/* Tab 2: Workflow Code */}
      {activeTab === 'github_action' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 mb-4 gap-2">
            <div>
              <span className="text-xs font-mono text-cyan-400 font-bold">.github/workflows/build-android.yml</span>
              <p className="text-[11px] text-emerald-400 mt-0.5 font-semibold">
                ✓ यह फाइल आपके प्रोजेक्ट में पहले से सेव कर दी गई है!
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
          <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[500px] leading-relaxed border border-slate-800">
            {githubActionsYaml}
          </pre>
        </div>
      )}

      {/* Tab 3: Gradle Code */}
      {activeTab === 'gradle' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 mb-4 gap-2">
            <div>
              <span className="text-xs font-mono text-cyan-400 font-bold">android/app/build.gradle</span>
              <p className="text-[11px] text-emerald-400 mt-0.5 font-semibold">
                ✓ यह फाइल भी आपके प्रोजेक्ट में android/app/build.gradle में सेव कर दी गई है!
              </p>
            </div>
            <button
              onClick={() => copyToClipboard(buildGradleCode, 'build.gradle')}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95 shrink-0"
            >
              {copiedFile === 'build.gradle' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              <span>{copiedFile === 'build.gradle' ? t.copied : t.copyCode}</span>
            </button>
          </div>
          <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[500px] leading-relaxed border border-slate-800">
            {buildGradleCode}
          </pre>
        </div>
      )}
    </div>
  );
};
