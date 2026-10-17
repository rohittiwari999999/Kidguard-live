import React from 'react';
import { 
  ShieldCheck, 
  Smartphone, 
  Tv, 
  Sparkles, 
  Code2, 
  Languages, 
  Radio
} from 'lucide-react';
import { DeviceRole, Language } from '../types';
import { translations } from '../utils/i18n';

interface NavbarProps {
  currentRole: DeviceRole;
  onSelectRole: (role: DeviceRole) => void;
  lang: Language;
  onToggleLang: () => void;
  isStreamActive: boolean;
}

export const Navbar: React.FC<NavbarProps> = ({
  currentRole,
  onSelectRole,
  lang,
  onToggleLang,
  isStreamActive,
}) => {
  const t = translations[lang];

  return (
    <header className="sticky top-0 z-40 bg-slate-950/80 backdrop-blur-xl border-b border-slate-800/80">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between gap-2 sm:gap-4">
        {/* Brand */}
        <div 
          onClick={() => onSelectRole('split-demo')}
          className="flex items-center gap-2.5 cursor-pointer group"
        >
          <div className="w-10 h-10 rounded-2xl bg-gradient-to-tr from-blue-600 via-indigo-600 to-cyan-500 flex items-center justify-center text-white shadow-lg shadow-indigo-500/25 group-hover:scale-105 transition">
            <ShieldCheck className="w-6 h-6" />
          </div>
          <div>
            <div className="flex items-center gap-1.5">
              <span className="font-extrabold text-base sm:text-lg tracking-tight text-white">
                KidGuard<span className="text-cyan-400">Live</span>
              </span>
              {isStreamActive && (
                <span className="flex h-2 w-2 relative">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75" />
                  <span className="relative inline-flex rounded-full h-2 w-2 bg-red-500" />
                </span>
              )}
            </div>
            <p className="text-[10px] text-slate-400 hidden sm:block">
              {lang === 'hi' ? 'बाल सुरक्षा स्क्रीन मॉनिटर' : 'Live Screen Safety Monitor'}
            </p>
          </div>
        </div>

        {/* Navigation Tabs */}
        <nav className="flex items-center gap-1 sm:gap-1.5 bg-slate-900/90 border border-slate-800 p-1 rounded-2xl overflow-x-auto max-w-full">
          {/* Parent Mode */}
          <button
            onClick={() => onSelectRole('parent')}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
              currentRole === 'parent'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
            }`}
          >
            <Tv className="w-3.5 h-3.5" />
            <span>{t.parentMode}</span>
          </button>

          {/* Child Mode */}
          <button
            onClick={() => onSelectRole('child')}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
              currentRole === 'child'
                ? 'bg-blue-600 text-white shadow-md shadow-blue-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
            }`}
          >
            <Smartphone className="w-3.5 h-3.5" />
            <span>{t.childMode}</span>
          </button>

          {/* Demo Split Mode */}
          <button
            onClick={() => onSelectRole('split-demo')}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
              currentRole === 'split-demo'
                ? 'bg-emerald-600 text-white shadow-md shadow-emerald-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
            }`}
          >
            <Sparkles className="w-3.5 h-3.5" />
            <span className="hidden md:inline">{t.splitDemo}</span>
            <span className="md:hidden">डेमो</span>
          </button>

          {/* Flutter Guide */}
          <button
            onClick={() => onSelectRole('flutter-guide')}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
              currentRole === 'flutter-guide'
                ? 'bg-cyan-600 text-white shadow-md shadow-cyan-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
            }`}
          >
            <Code2 className="w-3.5 h-3.5" />
            <span className="hidden md:inline">{t.flutterGuide}</span>
            <span className="md:hidden">Flutter</span>
          </button>
        </nav>

        {/* Right: Language switch */}
        <div className="flex items-center gap-2">
          <button
            onClick={onToggleLang}
            className="flex items-center gap-1 px-3 py-1.5 rounded-xl bg-slate-900 border border-slate-800 hover:border-slate-700 text-slate-300 text-xs font-bold transition"
            title="Toggle Language / भाषा बदलें"
          >
            <Languages className="w-3.5 h-3.5 text-cyan-400" />
            <span>{lang === 'hi' ? 'English' : 'हिन्दी'}</span>
          </button>
        </div>
      </div>
    </header>
  );
};
