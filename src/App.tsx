import React, { useState, useEffect, useMemo } from 'react';
import { Navbar } from './components/Navbar';
import { ChildView } from './components/ChildView';
import { ParentView } from './components/ParentView';
import { FlutterGuideView } from './components/FlutterGuideView';
import { PeerManager } from './services/peerManager';
import { DeviceRole, Language } from './types';
import { translations } from './utils/i18n';
import { ShieldCheck, Heart, Sparkles, Smartphone, Tv } from 'lucide-react';

export default function App() {
  const [lang, setLang] = useState<Language>(() => {
    try {
      return (localStorage.getItem('kidguard_lang') as Language) || 'hi';
    } catch {
      return 'hi';
    }
  });

  const [currentRole, setCurrentRole] = useState<DeviceRole>(() => {
    try {
      const urlRole = new URLSearchParams(window.location.search).get('role') as DeviceRole;
      if (urlRole && ['parent', 'child', 'flutter-guide'].includes(urlRole)) {
        return urlRole;
      }
      const saved = localStorage.getItem('kidguard_active_role') as DeviceRole;
      if (saved && ['parent', 'child', 'flutter-guide'].includes(saved)) {
        return saved;
      }
    } catch {
      // ignore
    }
    return 'child'; // Default to child on first launch
  });

  const [roomCode, setRoomCode] = useState<string>(() => {
    try {
      const urlRoom = new URLSearchParams(window.location.search).get('room');
      if (urlRoom) return urlRoom;
      const saved = localStorage.getItem('kidguard_room_code');
      if (saved) return saved;
    } catch {
      // ignore
    }
    return 'KID-8429';
  });

  const [isStreamActive, setIsStreamActive] = useState<boolean>(false);
  const [activeStream, setActiveStream] = useState<MediaStream | null>(null);

  // Singleton instance of PeerManager
  const peerManager = useMemo(() => new PeerManager(), []);

  // Sync state to localStorage and URL so tab reloading/app switching never loses the screen!
  useEffect(() => {
    try {
      localStorage.setItem('kidguard_active_role', currentRole);
      localStorage.setItem('kidguard_room_code', roomCode);
      localStorage.setItem('kidguard_lang', lang);

      const newUrl = `${window.location.pathname}?role=${currentRole}&room=${roomCode}`;
      window.history.replaceState(null, '', newUrl);
    } catch {
      // ignore
    }
  }, [currentRole, roomCode, lang]);

  const generateNewRoomCode = () => {
    const num = Math.floor(1000 + Math.random() * 9000);
    const newCode = `KID-${num}`;
    setRoomCode(newCode);
  };

  const handleStreamActiveChange = (active: boolean, stream: MediaStream | null) => {
    setIsStreamActive(active);
    setActiveStream(stream);
  };

  const toggleLanguage = () => {
    setLang((prev) => (prev === 'hi' ? 'en' : 'hi'));
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col selection:bg-indigo-500 selection:text-white">
      {/* Top Navigation */}
      <Navbar
        currentRole={currentRole}
        onSelectRole={setCurrentRole}
        lang={lang}
        onToggleLang={toggleLanguage}
        isStreamActive={isStreamActive}
      />

      {/* Main View Area */}
      <main className="flex-1">
        {currentRole === 'child' && (
          <ChildView
            lang={lang}
            peerManager={peerManager}
            roomCode={roomCode}
            onRegenerateCode={generateNewRoomCode}
            onStreamActive={handleStreamActiveChange}
            onSelectRole={setCurrentRole}
          />
        )}

        {currentRole === 'parent' && (
          <ParentView
            lang={lang}
            peerManager={peerManager}
            defaultRoomCode={roomCode}
            activeLocalStream={activeStream}
          />
        )}

        {currentRole === 'flutter-guide' && (
          <FlutterGuideView lang={lang} />
        )}
      </main>

      {/* Trust & Privacy Footer */}
      <footer className="border-t border-slate-900 bg-slate-950 py-6 px-4 text-center text-xs text-slate-500">
        <div className="max-w-4xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-slate-400 font-medium">
            <ShieldCheck className="w-4 h-4 text-emerald-400" />
            <span>
              {lang === 'hi'
                ? 'बाल सुरक्षा और गोपनीयता: P2P एन्क्रिप्टेड वेब कनेक्शन - कोई डेटा बाहरी सर्वर पर स्टोर नहीं होता।'
                : 'P2P Encrypted WebRTC Stream: Zero cloud storage, direct mobile-to-mobile privacy.'}
            </span>
          </div>

          <p className="text-[11px] text-slate-500">
            KidGuard Live • {lang === 'hi' ? 'माता-पिता के भरोसे के लिए' : 'Designed for Parental Peace of Mind'}
          </p>
        </div>
      </footer>
    </div>
  );
}
