import React, { useState, useEffect, useRef } from 'react';
import QRCode from 'qrcode';
import { 
  Cast, 
  Copy, 
  Check, 
  Lock, 
  Unlock, 
  AlertTriangle, 
  ShieldCheck, 
  Smartphone, 
  Video, 
  Layers, 
  BellRing,
  QrCode as QrIcon,
  RefreshCw,
  Eye,
  CheckCircle2
} from 'lucide-react';
import { SimulatedChildScreen } from './SimulatedChildScreen';
import { QRCodeDisplay } from './QRCodeDisplay';
import { PeerManager } from '../services/peerManager';
import { sounds } from '../utils/sound';
import { translations } from '../utils/i18n';
import { Language, BuzzerAlert } from '../types';

interface ChildViewProps {
  lang: Language;
  peerManager: PeerManager;
  roomCode: string;
  onRegenerateCode: () => void;
  onStreamActive: (active: boolean, stream: MediaStream | null) => void;
}

export const ChildView: React.FC<ChildViewProps> = ({
  lang,
  peerManager,
  roomCode,
  onRegenerateCode,
  onStreamActive,
}) => {
  const t = translations[lang];

  const [streamSource, setStreamSource] = useState<'simulation' | 'real_screen' | 'camera'>('simulation');
  const [isStreaming, setIsStreaming] = useState(true);
  const [copied, setCopied] = useState(false);
  const [qrCodeDataUrl, setQrCodeDataUrl] = useState<string>('');
  const [showQrModal, setShowQrModal] = useState(false);

  // Security lock PIN
  const [pin, setPin] = useState('1234');
  const [isLocked, setIsLocked] = useState(false);
  const [unlockInput, setUnlockInput] = useState('');
  const [unlockError, setUnlockError] = useState(false);
  const [showPinModal, setShowPinModal] = useState(false);

  // Active Alert from Parent
  const [activeAlert, setActiveAlert] = useState<BuzzerAlert | null>(null);

  // Video Ref for preview
  const videoPreviewRef = useRef<HTMLVideoElement | null>(null);
  const activeStreamRef = useRef<MediaStream | null>(null);

  // QR Code generator
  useEffect(() => {
    if (!roomCode) return;
    const connectUrl = `${window.location.origin}${window.location.pathname}?role=parent&room=${roomCode}`;
    QRCode.toDataURL(connectUrl, {
      width: 280,
      margin: 2,
      color: {
        dark: '#0f172a',
        light: '#ffffff',
      },
    })
      .then((url) => setQrCodeDataUrl(url))
      .catch((err) => console.error('QR code generation error:', err));
  }, [roomCode]);

  const broadcastStreamToParent = (stream: MediaStream) => {
    const parentPeerId = `kg-${roomCode}-parent`;
    peerManager.callWithStream(parentPeerId, stream);
    onStreamActive(true, stream);
  };

  // PeerJS setup as Child
  useEffect(() => {
    const childPeerId = `kg-${roomCode}-child`;
    peerManager.initPeer(
      childPeerId,
      (id) => {
        console.log('Child Peer ready:', id);
        // If we already have an active stream, send it
        if (activeStreamRef.current) {
          broadcastStreamToParent(activeStreamRef.current);
        }
      },
      (err) => {
        console.warn('Child Peer error:', err);
      }
    );

    // Listen to messages from Parent (like Buzzer / Alert or stream request)
    peerManager.onMessage((msg) => {
      if (msg.type === 'ALERT') {
        const alertData: BuzzerAlert = {
          id: String(Date.now()),
          timestamp: Date.now(),
          message: msg.payload?.message || 'माता-पिता का अलर्ट!',
          sender: 'parent',
        };
        setActiveAlert(alertData);
        sounds.playBuzzer();
      } else if (msg.type === 'REQUEST_STREAM' || msg.type === 'PARENT_JOINED') {
        console.log('Parent requested stream, sending immediately!');
        if (activeStreamRef.current) {
          setIsStreaming(true);
          broadcastStreamToParent(activeStreamRef.current);
        }
      }
    });

    return () => {
      // Don't kill everything if just re-rendering
    };
  }, [roomCode, peerManager]);

  // Handle stream from simulation
  const handleSimulationStream = (stream: MediaStream) => {
    activeStreamRef.current = stream;
    if (videoPreviewRef.current) {
      videoPreviewRef.current.srcObject = stream;
      videoPreviewRef.current.muted = true;
      videoPreviewRef.current.play().catch(() => {});
    }
    if (streamSource === 'simulation') {
      broadcastStreamToParent(stream);
    }
  };

  // Start Real Screen Capture
  const startRealScreenCapture = async () => {
    try {
      if (!navigator.mediaDevices?.getDisplayMedia) {
        alert(
          lang === 'hi'
            ? 'आपके ब्राउज़र में getDisplayMedia सपोर्ट नहीं है। कृपया सिमुलेशन मोड या कैमरा मोड चुनें।'
            : 'DisplayMedia screen sharing is not supported in this browser. Please use Simulation or Camera mode.'
        );
        return;
      }

      const screenStream = await navigator.mediaDevices.getDisplayMedia({
        video: {
          displaySurface: 'monitor',
        },
        audio: true,
      });

      activeStreamRef.current = screenStream;
      if (videoPreviewRef.current) {
        videoPreviewRef.current.srcObject = screenStream;
      }

      screenStream.getVideoTracks()[0].onended = () => {
        stopStreaming();
      };

      setIsStreaming(true);
      broadcastStreamToParent(screenStream);
      sounds.playChime();
    } catch (err: any) {
      console.warn('Screen share error or user cancelled:', err);
      if (err.name !== 'NotAllowedError') {
        alert('Screen share permission error: ' + err.message);
      }
    }
  };

  // Start Camera Feed
  const startCameraCapture = async () => {
    try {
      const camStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user' },
        audio: true,
      });

      activeStreamRef.current = camStream;
      if (videoPreviewRef.current) {
        videoPreviewRef.current.srcObject = camStream;
      }

      setIsStreaming(true);
      broadcastStreamToParent(camStream);
      sounds.playChime();
    } catch (err: any) {
      alert('Camera access denied or unavailable: ' + err.message);
    }
  };

  // Start Sharing
  const handleStartShare = () => {
    if (streamSource === 'real_screen') {
      startRealScreenCapture();
    } else if (streamSource === 'camera') {
      startCameraCapture();
    } else {
      // Simulation mode
      setIsStreaming(true);
      if (activeStreamRef.current) {
        broadcastStreamToParent(activeStreamRef.current);
      }
      sounds.playChime();
    }
  };

  // Stop Sharing
  const handleStopShareClick = () => {
    if (isLocked) {
      setShowPinModal(true);
      return;
    }
    stopStreaming();
  };

  const stopStreaming = () => {
    if (activeStreamRef.current && streamSource !== 'simulation') {
      activeStreamRef.current.getTracks().forEach((t) => t.stop());
    }
    setIsStreaming(false);
    onStreamActive(false, null);
  };

  const handleUnlockPin = (e: React.FormEvent) => {
    e.preventDefault();
    if (unlockInput === pin) {
      setIsLocked(false);
      setShowPinModal(false);
      setUnlockInput('');
      setUnlockError(false);
      stopStreaming();
    } else {
      setUnlockError(true);
      sounds.playBuzzer();
    }
  };

  const copyRoomCode = () => {
    navigator.clipboard.writeText(roomCode);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      {/* Alert Banner if Parent sends message */}
      {activeAlert && (
        <div className="mb-6 p-4 rounded-2xl bg-amber-500/15 border-2 border-amber-500/40 text-amber-200 animate-bounce shadow-xl flex items-start justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="p-2.5 bg-amber-500 text-slate-950 rounded-xl">
              <BellRing className="w-6 h-6 animate-spin" />
            </div>
            <div>
              <p className="text-xs font-semibold text-amber-400 uppercase tracking-wider">
                {t.alertFromParent}
              </p>
              <h4 className="text-lg font-bold text-white mt-0.5">
                "{activeAlert.message}"
              </h4>
            </div>
          </div>
          <button
            onClick={() => setActiveAlert(null)}
            className="px-3 py-1.5 bg-amber-500/20 hover:bg-amber-500/30 text-amber-200 text-xs font-semibold rounded-lg transition"
          >
            {t.dismissAlert}
          </button>
        </div>
      )}

      {/* Main Card */}
      <div className="bg-slate-900/80 border border-slate-800 backdrop-blur-md rounded-3xl p-6 shadow-2xl">
        {/* Child Mode Header */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-6 border-b border-slate-800">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-2xl bg-blue-600/20 border border-blue-500/30 flex items-center justify-center text-blue-400 shadow-inner">
              <Smartphone className="w-6 h-6" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-xl font-bold text-white tracking-tight">
                  {t.childHeader}
                </h2>
                <span className="px-2 py-0.5 text-[10px] font-bold uppercase rounded-md bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                  {isStreaming ? t.statusActive : t.statusWaiting}
                </span>
              </div>
              <p className="text-xs text-slate-400 mt-0.5">
                {t.childSubheader}
              </p>
            </div>
          </div>

          {/* Quick PIN Lock toggle */}
          <button
            onClick={() => {
              if (isLocked) {
                setShowPinModal(true);
              } else {
                setIsLocked(true);
                sounds.playChime();
              }
            }}
            className={`flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-semibold transition border ${
              isLocked
                ? 'bg-rose-500/20 border-rose-500/40 text-rose-300'
                : 'bg-slate-800/80 border-slate-700 text-slate-300 hover:bg-slate-700'
            }`}
          >
            {isLocked ? <Lock className="w-3.5 h-3.5" /> : <Unlock className="w-3.5 h-3.5" />}
            <span>{isLocked ? t.lockActive : t.lockWithPin}</span>
          </button>
        </div>

        {/* Pairing Code & Direct QR Box */}
        <div className="my-6 p-5 rounded-2xl bg-gradient-to-br from-slate-950 to-slate-900 border border-slate-800 flex flex-col md:flex-row items-center justify-between gap-6 shadow-xl">
          <div className="space-y-3 text-center md:text-left flex-1">
            <span className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
              {t.roomCodeLabel}
            </span>
            <div className="flex items-center justify-center md:justify-start gap-3">
              <span className="text-3xl sm:text-4xl font-extrabold tracking-widest font-mono text-transparent bg-clip-text bg-gradient-to-r from-blue-400 via-indigo-300 to-cyan-300">
                {roomCode}
              </span>
              <button
                onClick={copyRoomCode}
                title={t.copyCode}
                className="p-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 transition active:scale-95 border border-slate-700"
              >
                {copied ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              </button>
              <button
                onClick={onRegenerateCode}
                title="Generate new code"
                className="p-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-slate-200 transition border border-slate-700"
              >
                <RefreshCw className="w-4 h-4" />
              </button>
            </div>
            <p className="text-xs text-slate-300 max-w-sm leading-relaxed">
              {lang === 'hi'
                ? '📱 माता-पिता के फोन से यह सामने दिख रहा QR कोड स्कैन करें या 6-अंकीय कोड दर्ज करें।'
                : '📱 Scan this QR code with parent device camera or enter the 6-digit code to watch live.'}
            </p>
          </div>

          {/* Prominent Directly Visible QR Code */}
          <div className="shrink-0">
            <QRCodeDisplay
              value={typeof window !== 'undefined' ? `${window.location.origin}${window.location.pathname}?role=parent&room=${roomCode}` : `KIDGUARD:${roomCode}`}
              roomCode={roomCode}
              size={150}
              label={lang === 'hi' ? 'माता-पिता के फोन से स्कैन करें' : 'Scan with Parent Device'}
              sublabel={lang === 'hi' ? 'कैमरा इसके सामने लाएं' : 'Point camera directly here'}
            />
          </div>
        </div>

        {/* Source Mode Selector */}
        <div className="mb-6">
          <label className="block text-xs font-medium text-slate-300 mb-2">
            {t.selectMode}
          </label>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
            <button
              onClick={() => {
                if (isStreaming) stopStreaming();
                setStreamSource('simulation');
              }}
              className={`p-3 rounded-xl border text-left transition flex items-start gap-3 ${
                streamSource === 'simulation'
                  ? 'bg-blue-600/20 border-blue-500/50 text-white shadow-md'
                  : 'bg-slate-950/60 border-slate-800 text-slate-400 hover:bg-slate-800/50'
              }`}
            >
              <Layers className="w-5 h-5 text-blue-400 shrink-0 mt-0.5" />
              <div>
                <p className="text-xs font-bold text-white">{t.modeSimulation}</p>
                <p className="text-[10px] text-slate-400 mt-0.5 leading-tight">
                  {lang === 'hi' ? 'YouTube/Game डेमो (100% सभी फोन पर काम करता है)' : 'Interactive apps simulation (Works on all browsers)'}
                </p>
              </div>
            </button>

            <button
              onClick={() => {
                if (isStreaming) stopStreaming();
                setStreamSource('real_screen');
              }}
              className={`p-3 rounded-xl border text-left transition flex items-start gap-3 ${
                streamSource === 'real_screen'
                  ? 'bg-blue-600/20 border-blue-500/50 text-white shadow-md'
                  : 'bg-slate-950/60 border-slate-800 text-slate-400 hover:bg-slate-800/50'
              }`}
            >
              <Cast className="w-5 h-5 text-indigo-400 shrink-0 mt-0.5" />
              <div>
                <p className="text-xs font-bold text-white">{t.modeRealScreen}</p>
                <p className="text-[10px] text-slate-400 mt-0.5 leading-tight">
                  {lang === 'hi' ? 'पूरे फोन की स्क्रीन शेयर (Chrome/DisplayMedia)' : 'Real phone screen via DisplayMedia'}
                </p>
              </div>
            </button>

            <button
              onClick={() => {
                if (isStreaming) stopStreaming();
                setStreamSource('camera');
              }}
              className={`p-3 rounded-xl border text-left transition flex items-start gap-3 ${
                streamSource === 'camera'
                  ? 'bg-blue-600/20 border-blue-500/50 text-white shadow-md'
                  : 'bg-slate-950/60 border-slate-800 text-slate-400 hover:bg-slate-800/50'
              }`}
            >
              <Video className="w-5 h-5 text-teal-400 shrink-0 mt-0.5" />
              <div>
                <p className="text-xs font-bold text-white">{t.modeCamera}</p>
                <p className="text-[10px] text-slate-400 mt-0.5 leading-tight">
                  {lang === 'hi' ? 'बच्चे का फ्रंट/बैक कैमरा' : 'Front/Back camera stream'}
                </p>
              </div>
            </button>
          </div>
        </div>

        {/* Live Stream View or Interactive Simulation */}
        <div className="mb-6">
          {streamSource === 'simulation' ? (
            <div className="p-4 bg-slate-950/70 border border-slate-800/80 rounded-2xl">
              <SimulatedChildScreen
                onStreamReady={handleSimulationStream}
                isStreaming={isStreaming}
              />
            </div>
          ) : (
            <div className="relative rounded-2xl overflow-hidden bg-black aspect-video max-h-[340px] flex items-center justify-center border border-slate-800 shadow-inner">
              <video
                ref={videoPreviewRef}
                autoPlay
                playsInline
                muted
                className="w-full h-full object-contain"
              />
              {!isStreaming && (
                <div className="absolute inset-0 bg-slate-950/80 flex flex-col items-center justify-center text-center p-4">
                  <Cast className="w-10 h-10 text-slate-500 mb-2" />
                  <p className="text-sm font-medium text-slate-300">
                    {lang === 'hi' ? 'कैमरा या स्क्रीन अभी शुरू नहीं हुई है' : 'Stream is not currently started'}
                  </p>
                  <p className="text-xs text-slate-500 mt-1 max-w-xs">
                    {lang === 'hi'
                      ? 'नीचे दिए गए नीले बटन "स्क्रीन शेयरिंग शुरू करें" पर क्लिक करें।'
                      : 'Click the button below to grant permission and start streaming.'}
                  </p>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Action Controls */}
        <div className="flex flex-col sm:flex-row items-center gap-3">
          {!isStreaming ? (
            <button
              onClick={handleStartShare}
              className="w-full sm:flex-1 py-3.5 px-6 rounded-2xl bg-gradient-to-r from-blue-600 via-indigo-600 to-blue-700 hover:from-blue-500 hover:to-indigo-500 text-white font-bold text-base shadow-lg shadow-blue-500/25 active:scale-98 transition flex items-center justify-center gap-2"
            >
              <Cast className="w-5 h-5 animate-pulse" />
              <span>{t.startSharing}</span>
            </button>
          ) : (
            <button
              onClick={handleStopShareClick}
              className="w-full sm:flex-1 py-3.5 px-6 rounded-2xl bg-rose-600 hover:bg-rose-500 text-white font-bold text-base shadow-lg shadow-rose-500/25 active:scale-98 transition flex items-center justify-center gap-2"
            >
              <AlertTriangle className="w-5 h-5" />
              <span>{t.stopSharing}</span>
            </button>
          )}

          <button
            onClick={() => setShowQrModal(true)}
            className="w-full sm:w-auto py-3.5 px-5 rounded-2xl bg-slate-800 hover:bg-slate-700 text-slate-200 font-semibold text-sm border border-slate-700 transition flex items-center justify-center gap-2"
          >
            <QrIcon className="w-4 h-4 text-blue-400" />
            <span>{lang === 'hi' ? 'QR कोड दिखाएं' : 'Show QR'}</span>
          </button>
        </div>

        {/* Protection Note */}
        <div className="mt-6 pt-4 border-t border-slate-800/80 flex items-center gap-2 text-xs text-slate-400">
          <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0" />
          <span>
            {lang === 'hi'
              ? 'गोपनीयता सुरक्षित: यह स्क्रीन केवल उस माता-पिता के फोन पर दिखेगी जिसके पास पेयरिंग कोड है।'
              : 'End-to-End Secure: Screen video is streamed directly via WebRTC peer connection to the paired parent.'}
          </span>
        </div>
      </div>

      {/* QR Code Large Modal */}
      {showQrModal && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 max-w-sm w-full text-center shadow-2xl relative">
            <h3 className="text-lg font-bold text-white mb-2">
              {lang === 'hi' ? 'माता-पिता के फोन से स्कैन करें' : 'Scan with Parent Phone'}
            </h3>
            <p className="text-xs text-slate-400 mb-4">
              {lang === 'hi'
                ? 'अपने मोबाइल कैमरे से यह QR कोड स्कैन करें, लाइव स्क्रीन सीधे खुल जाएगी।'
                : 'Point parent phone camera at this QR code to connect to this live screen instantly.'}
            </p>

            <div className="p-3 bg-white rounded-2xl inline-block shadow-inner mx-auto mb-4">
              <img src={qrCodeDataUrl} alt="Pairing QR Code" className="w-56 h-56 object-contain" />
            </div>

            <div className="bg-slate-950 p-3 rounded-xl border border-slate-800 mb-4">
              <p className="text-xs text-slate-400 mb-1">{t.roomCodeLabel}</p>
              <p className="text-2xl font-mono font-bold text-blue-400 tracking-widest">{roomCode}</p>
            </div>

            <button
              onClick={() => setShowQrModal(false)}
              className="w-full py-2.5 bg-slate-800 hover:bg-slate-700 text-white text-sm font-semibold rounded-xl transition"
            >
              {lang === 'hi' ? 'बंद करें (Close)' : 'Close'}
            </button>
          </div>
        </div>
      )}

      {/* PIN Unlock Modal */}
      {showPinModal && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 max-w-xs w-full text-center shadow-2xl">
            <div className="w-12 h-12 rounded-full bg-rose-500/20 text-rose-400 flex items-center justify-center mx-auto mb-3">
              <Lock className="w-6 h-6" />
            </div>
            <h3 className="text-lg font-bold text-white mb-1">
              {t.unlockWithPin}
            </h3>
            <p className="text-xs text-slate-400 mb-4">
              {lang === 'hi' ? 'माता-पिता का 4-अंकीय PIN दर्ज करें (डिफ़ॉल्ट: 1234)' : 'Enter 4-digit Parent PIN (Default: 1234)'}
            </p>

            <form onSubmit={handleUnlockPin} className="space-y-4">
              <input
                type="password"
                maxLength={4}
                value={unlockInput}
                onChange={(e) => setUnlockInput(e.target.value)}
                placeholder="••••"
                className="w-full text-center text-2xl tracking-widest font-mono py-2.5 bg-slate-950 border border-slate-700 rounded-xl text-white focus:outline-hidden focus:border-blue-500"
                autoFocus
              />

              {unlockError && (
                <p className="text-xs text-rose-400 font-medium">
                  {lang === 'hi' ? 'गलत PIN! कृपया सही PIN डालें।' : 'Incorrect PIN! Please try again.'}
                </p>
              )}

              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => {
                    setShowPinModal(false);
                    setUnlockInput('');
                    setUnlockError(false);
                  }}
                  className="flex-1 py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded-xl text-xs font-semibold"
                >
                  {lang === 'hi' ? 'रद्द करें' : 'Cancel'}
                </button>
                <button
                  type="submit"
                  className="flex-1 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-semibold"
                >
                  {lang === 'hi' ? 'अनलॉक करें' : 'Unlock'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
