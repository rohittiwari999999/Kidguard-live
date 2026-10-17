import React, { useState } from 'react';
import { Smartphone, Eye, Sparkles, ArrowRight, ShieldCheck, CheckCircle } from 'lucide-react';
import { SimulatedChildScreen } from './SimulatedChildScreen';
import { ParentView } from './ParentView';
import { PeerManager } from '../services/peerManager';
import { Language } from '../types';

interface SplitDemoViewProps {
  lang: Language;
  peerManager: PeerManager;
  roomCode: string;
}

export const SplitDemoView: React.FC<SplitDemoViewProps> = ({
  lang,
  peerManager,
  roomCode,
}) => {
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [activeApp, setActiveApp] = useState<'youtube' | 'game' | 'chat' | 'homework'>('youtube');

  const handleStreamReady = (stream: MediaStream) => {
    setLocalStream(stream);
  };

  return (
    <div className="max-w-7xl mx-auto px-4 py-6">
      {/* Intro Banner */}
      <div className="mb-6 p-4 rounded-2xl bg-gradient-to-r from-blue-900/40 via-indigo-900/30 to-purple-900/40 border border-indigo-500/30 backdrop-blur-md flex flex-col md:flex-row items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-indigo-500/20 text-indigo-300 flex items-center justify-center shrink-0">
            <Sparkles className="w-5 h-5" />
          </div>
          <div>
            <h3 className="text-sm sm:text-base font-bold text-white">
              {lang === 'hi'
                ? 'लाइव स्प्लिट डेमो: दोनों फोन एक ही स्क्रीन पर टेस्ट करें'
                : 'Interactive Dual-Device Simulator: Test Both Phones Side-by-Side'}
            </h3>
            <p className="text-xs text-slate-300 mt-0.5">
              {lang === 'hi'
                ? 'बाएं बच्चे का फोन है और दाएं माता-पिता का मॉनिटर। बाएं ऐप बदलें और देखें कि दाएं स्क्रीन पर तुरंत लाइव दिखता है!'
                : 'Left side simulates the child\'s phone. Right side simulates the parent\'s monitor live stream.'}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2 text-xs text-indigo-200 bg-indigo-950/60 px-3 py-1.5 rounded-xl border border-indigo-800 shrink-0">
          <ShieldCheck className="w-4 h-4 text-emerald-400" />
          <span>{lang === 'hi' ? 'जीरो लैग P2P लाइव' : 'Zero-Lag P2P WebRTC'}</span>
        </div>
      </div>

      {/* Side-by-Side Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        {/* Left: Child Device Mockup (5 cols) */}
        <div className="lg:col-span-5 bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl">
          <div className="flex items-center justify-between mb-4 pb-3 border-b border-slate-800">
            <div className="flex items-center gap-2">
              <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-ping" />
              <h4 className="text-sm font-bold text-white flex items-center gap-1.5">
                <Smartphone className="w-4 h-4 text-blue-400" />
                <span>{lang === 'hi' ? '1. बच्चे का मोबाइल (Child)' : '1. Child Device'}</span>
              </h4>
            </div>
            <span className="text-[10px] font-mono bg-slate-800 text-slate-300 px-2 py-0.5 rounded-md">
              Code: {roomCode}
            </span>
          </div>

          <SimulatedChildScreen
            onStreamReady={handleStreamReady}
            activeApp={activeApp}
            onAppChange={(app) => setActiveApp(app)}
            isStreaming={true}
          />
        </div>

        {/* Center Arrow Indicator (Desktop only) */}
        <div className="hidden lg:flex lg:col-span-1 items-center justify-center self-center">
          <div className="p-3 bg-indigo-600/20 border border-indigo-500/40 text-indigo-400 rounded-full animate-pulse shadow-lg">
            <ArrowRight className="w-6 h-6" />
          </div>
        </div>

        {/* Right: Parent Live Viewer (6 cols) */}
        <div className="lg:col-span-6 bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl">
          <div className="flex items-center justify-between mb-4 pb-3 border-b border-slate-800">
            <div className="flex items-center gap-2">
              <span className="w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse" />
              <h4 className="text-sm font-bold text-white flex items-center gap-1.5">
                <Eye className="w-4 h-4 text-indigo-400" />
                <span>{lang === 'hi' ? '2. माता-पिता का मॉनिटर (Parent)' : '2. Parent Monitor'}</span>
              </h4>
            </div>
            <span className="text-[10px] text-emerald-400 bg-emerald-950/60 border border-emerald-800/80 px-2 py-0.5 rounded-md font-bold">
              ● {lang === 'hi' ? 'लाइव सिंक' : 'Live Sync'}
            </span>
          </div>

          <ParentView
            lang={lang}
            peerManager={peerManager}
            defaultRoomCode={roomCode}
            activeLocalStream={localStream}
          />
        </div>
      </div>
    </div>
  );
};
