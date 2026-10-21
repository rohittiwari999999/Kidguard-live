import React, { useState, useEffect, useRef } from 'react';
import { 
  Tv, 
  Camera, 
  Video, 
  Volume2, 
  VolumeX, 
  Maximize, 
  Minimize, 
  ZoomIn, 
  RotateCcw, 
  BellRing, 
  Send, 
  Clock, 
  Trash2, 
  Download, 
  Wifi, 
  WifiOff, 
  AlertCircle, 
  CheckCircle, 
  Sparkles,
  Smartphone,
  QrCode
} from 'lucide-react';
import { PeerManager } from '../services/peerManager';
import { QRScannerModal } from './QRScannerModal';
import { sounds } from '../utils/sound';
import { translations } from '../utils/i18n';
import { Language, CapturedSnapshot, ActivityEvent } from '../types';

interface ParentViewProps {
  lang: Language;
  peerManager: PeerManager;
  defaultRoomCode?: string;
  activeLocalStream?: MediaStream | null;
}

export const ParentView: React.FC<ParentViewProps> = ({
  lang,
  peerManager,
  defaultRoomCode = '',
  activeLocalStream = null,
}) => {
  const t = translations[lang];

  const [inputCode, setInputCode] = useState(defaultRoomCode || 'KID-8429');
  const [connectedRoom, setConnectedRoom] = useState<string | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<'idle' | 'connecting' | 'connected' | 'disconnected'>('idle');
  const [showQRScanner, setShowQRScanner] = useState(false);

  // Video and Stream refs
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [hasStream, setHasStream] = useState(false);
  const [isAudioMuted, setIsAudioMuted] = useState(true); // Must be true by default for mobile browser autoplay
  const [zoomLevel, setZoomLevel] = useState<1 | 1.5 | 2>(1);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const videoContainerRef = useRef<HTMLDivElement | null>(null);

  // Recording
  const [isRecording, setIsRecording] = useState(false);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const recordedChunksRef = useRef<Blob[]>([]);

  // Screenshots Gallery
  const [snapshots, setSnapshots] = useState<CapturedSnapshot[]>(() => {
    try {
      const saved = localStorage.getItem('kidguard_snapshots');
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  });

  // Buzzer Modal & Custom Message
  const [showBuzzerModal, setShowBuzzerModal] = useState(false);
  const [buzzerText, setBuzzerText] = useState('');
  const [alertSentSuccess, setAlertSentSuccess] = useState(false);

  // Streaming Duration Timer
  const [streamDuration, setStreamDuration] = useState(0);

  // Sync default code if passed
  useEffect(() => {
    if (defaultRoomCode && defaultRoomCode !== inputCode) {
      setInputCode(defaultRoomCode);
    }
  }, [defaultRoomCode]);

  // Duration ticker
  useEffect(() => {
    let interval: any;
    if (connectionStatus === 'connected' && hasStream) {
      interval = setInterval(() => {
        setStreamDuration((prev) => prev + 1);
      }, 1000);
    } else {
      setStreamDuration(0);
    }
    return () => clearInterval(interval);
  }, [connectionStatus, hasStream]);

  // If activeLocalStream is present (e.g. testing in SplitDemo or same page)
  useEffect(() => {
    if (activeLocalStream && videoRef.current) {
      videoRef.current.srcObject = activeLocalStream;
      videoRef.current.muted = true;
      videoRef.current.play().catch(() => {});
      setHasStream(true);
      setConnectionStatus('connected');
    }
  }, [activeLocalStream]);

  // Periodic request while waiting for stream
  useEffect(() => {
    let timer: any;
    if (connectionStatus === 'connecting' && !hasStream && connectedRoom) {
      const childPeerId = `kg-${connectedRoom}-child`;
      const parentPeerId = `kg-${connectedRoom}-parent`;
      // Ping child every 2 seconds to request live stream
      timer = setInterval(() => {
        peerManager.connectData(childPeerId, () => {
          peerManager.sendMessage({
            type: 'REQUEST_STREAM',
            payload: { parentId: parentPeerId, roomCode: connectedRoom },
            timestamp: Date.now(),
          });
        });
      }, 2000);
    }
    return () => clearInterval(timer);
  }, [connectionStatus, hasStream, connectedRoom, peerManager]);

  // Handle joining room
  const handleConnect = (codeToJoin?: string) => {
    const code = (codeToJoin || inputCode).trim().toUpperCase();
    if (!code) return;

    // If local stream is already active (like in SplitDemo preview), use it directly
    if (activeLocalStream) {
      if (videoRef.current) {
        videoRef.current.srcObject = activeLocalStream;
        videoRef.current.muted = true;
        videoRef.current.play().catch(() => {});
      }
      setHasStream(true);
      setConnectionStatus('connected');
      return;
    }

    setConnectionStatus('connecting');
    setConnectedRoom(code);

    const parentPeerId = `kg-${code}-parent`;
    const childPeerId = `kg-${code}-child`;

    peerManager.initPeer(
      parentPeerId,
      () => {
        // Parent Peer is open and waiting for child to stream
        setConnectionStatus('connecting');
        peerManager.connectData(childPeerId, () => {
          peerManager.sendMessage({
            type: 'REQUEST_STREAM',
            payload: { parentId: parentPeerId, roomCode: code },
            timestamp: Date.now(),
          });
        });
      },
      () => {
        // PeerJS cloud unavailable is expected when child is native Android Flutter APK
        console.log('PeerJS fallback waiting on HTTP/ntfy bridge...');
      }
    );

    peerManager.onStream((remoteStream) => {
      console.log('Received remote stream in parent!');
      if (videoRef.current) {
        videoRef.current.srcObject = remoteStream;
        videoRef.current.muted = true; // Essential for autoplay on mobile!
        videoRef.current.playsInline = true;
        videoRef.current.play().catch((err) => {
          console.warn('Video play prevented by browser policy, will play on user tap:', err);
        });
      }
      setHasStream(true);
      setConnectionStatus('connected');
      sounds.playChime();
    });

    peerManager.onStatusChange((status) => {
      if (status === 'connected') {
        setConnectionStatus('connected');
      } else if (status === 'connecting') {
        setConnectionStatus((prev) => prev === 'connected' ? 'connected' : 'connecting');
      }
    });

    // Also connect via HTTP Signaling (enables watching Native Android Flutter APK devices)
    peerManager.startHttpParentWatch(code, (remoteStream) => {
      console.log('Received remote stream from HTTP signaling bridge!');
      if (videoRef.current) {
        videoRef.current.srcObject = remoteStream;
        videoRef.current.muted = true;
        videoRef.current.playsInline = true;
        videoRef.current.play().catch((err) => {
          console.warn('Video play prevented by browser policy:', err);
        });
      }
      setHasStream(true);
      setConnectionStatus('connected');
      sounds.playChime();
    });
  };

  // Auto connect if room param is present and not local demo
  useEffect(() => {
    if (defaultRoomCode && !activeLocalStream) {
      handleConnect(defaultRoomCode);
    }
  }, [defaultRoomCode, activeLocalStream]);

  // Take Snapshot
  const captureScreenshot = () => {
    const video = videoRef.current;
    if (!video) return;

    sounds.playScreenshot();

    try {
      const canvas = document.createElement('canvas');
      canvas.width = video.videoWidth || 640;
      canvas.height = video.videoHeight || 360;
      const ctx = canvas.getContext('2d');
      if (ctx) {
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        const dataUrl = canvas.toDataURL('image/jpeg', 0.9);

        const newSnapshot: CapturedSnapshot = {
          id: String(Date.now()),
          timestamp: Date.now(),
          dataUrl,
          appName: 'Live Screen',
          note: `Captured at ${new Date().toLocaleTimeString()}`,
        };

        const updated = [newSnapshot, ...snapshots];
        setSnapshots(updated);
        try {
          localStorage.setItem('kidguard_snapshots', JSON.stringify(updated.slice(0, 30)));
        } catch {
          // ignore quota
        }
      }
    } catch (err) {
      console.warn('Screenshot capture error:', err);
    }
  };

  // Video recording
  const startRecording = () => {
    const video = videoRef.current;
    if (!video || !video.srcObject) return;

    try {
      const stream = video.srcObject as MediaStream;
      let options: MediaRecorderOptions = {};
      if (typeof MediaRecorder !== 'undefined' && typeof MediaRecorder.isTypeSupported === 'function') {
        if (MediaRecorder.isTypeSupported('video/webm;codecs=vp8,opus')) {
          options = { mimeType: 'video/webm;codecs=vp8,opus' };
        } else if (MediaRecorder.isTypeSupported('video/webm')) {
          options = { mimeType: 'video/webm' };
        } else if (MediaRecorder.isTypeSupported('video/mp4')) {
          options = { mimeType: 'video/mp4' };
        }
      }
      const mediaRecorder = new MediaRecorder(stream, options);
      recordedChunksRef.current = [];

      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          recordedChunksRef.current.push(event.data);
        }
      };

      mediaRecorder.onstop = () => {
        const blob = new Blob(recordedChunksRef.current, { type: 'video/webm' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `kidguard-recording-${Date.now()}.webm`;
        a.click();
        sounds.playChime();
      };

      mediaRecorder.start();
      mediaRecorderRef.current = mediaRecorder;
      setIsRecording(true);
      sounds.playChime();
    } catch (err) {
      console.warn('Recording error:', err);
    }
  };

  const stopRecording = () => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      setIsRecording(false);
    }
  };

  // Send Alert to Child
  const handleSendBuzzer = (textToSend?: string) => {
    const msgText = (textToSend || buzzerText).trim();
    if (!msgText) return;

    peerManager.sendMessage({
      type: 'ALERT',
      payload: { message: msgText },
      timestamp: Date.now(),
    });

    sounds.playBuzzer();
    setAlertSentSuccess(true);
    setBuzzerText('');
    setTimeout(() => {
      setAlertSentSuccess(false);
      setShowBuzzerModal(false);
    }, 1500);
  };

  // Toggle Fullscreen
  const toggleFullscreen = () => {
    const container = videoContainerRef.current;
    if (!container) return;

    if (!document.fullscreenElement) {
      container.requestFullscreen?.().catch(() => {});
      setIsFullscreen(true);
    } else {
      document.exitFullscreen?.().catch(() => {});
      setIsFullscreen(false);
    }
  };

  // Format seconds to mm:ss
  const formatDuration = (sec: number) => {
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  };

  return (
    <div className="max-w-4xl mx-auto px-4 py-6">
      {/* Header & Connection Bar */}
      <div className="bg-slate-900/80 border border-slate-800 backdrop-blur-md rounded-3xl p-5 sm:p-6 shadow-2xl mb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 pb-5 border-b border-slate-800">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-2xl bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center text-indigo-400 shadow-inner">
              <Tv className="w-6 h-6" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-xl font-bold text-white tracking-tight">
                  {t.parentHeader}
                </h2>
                {connectionStatus === 'connected' ? (
                  <span className="flex items-center gap-1 px-2.5 py-0.5 text-[10px] font-bold rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
                    {t.streamLive} • {formatDuration(streamDuration)}
                  </span>
                ) : (
                  <span className="px-2.5 py-0.5 text-[10px] font-bold rounded-full bg-amber-500/20 text-amber-300 border border-amber-500/30">
                    {connectionStatus === 'connecting' ? t.streamConnecting : 'ऑफलाइन (Offline)'}
                  </span>
                )}
              </div>
              <p className="text-xs text-slate-400 mt-0.5">
                {t.parentSubheader}
              </p>
            </div>
          </div>

          {/* Quick Connect Form with QR Scan */}
          <div className="flex flex-wrap items-center gap-2">
            <button
              onClick={() => setShowQRScanner(true)}
              className="px-3.5 py-2.5 bg-gradient-to-r from-cyan-600 to-blue-600 hover:from-cyan-500 hover:to-blue-500 text-white rounded-xl text-xs font-bold transition shadow-md shadow-cyan-600/20 active:scale-95 flex items-center gap-1.5"
              title={lang === 'hi' ? 'कैमरे से QR कोड स्कैन करें' : 'Scan QR code with camera'}
            >
              <QrCode className="w-4 h-4" />
              <span>{lang === 'hi' ? 'QR स्कैन करें' : 'Scan QR'}</span>
            </button>

            <span className="text-xs text-slate-500 font-semibold">{lang === 'hi' ? 'या' : 'or'}</span>

            <input
              type="text"
              value={inputCode}
              onChange={(e) => setInputCode(e.target.value.toUpperCase())}
              placeholder="KID-1234"
              className="px-3 py-2.5 bg-slate-950 border border-slate-700 rounded-xl font-mono text-sm tracking-wider uppercase text-white focus:outline-hidden focus:border-indigo-500 w-28 text-center"
            />
            <button
              onClick={() => handleConnect()}
              className="px-4 py-2.5 bg-gradient-to-r from-indigo-600 to-purple-600 hover:from-indigo-500 hover:to-purple-500 text-white rounded-xl text-xs font-bold transition shadow-md shadow-indigo-600/20 active:scale-95 flex items-center gap-1.5"
            >
              <Wifi className="w-3.5 h-3.5" />
              <span>{t.joinStream}</span>
            </button>
          </div>
        </div>

        {/* Live Video Feed Container */}
        <div className="mt-5">
          <div
            ref={videoContainerRef}
            className="relative rounded-2xl overflow-hidden bg-black aspect-video max-h-[520px] w-full flex items-center justify-center border border-slate-800 shadow-2xl group"
          >
            {/* The Live Video Element */}
            <video
              ref={videoRef}
              autoPlay
              playsInline
              muted={isAudioMuted}
              onLoadedMetadata={(e) => {
                const vid = e.target as HTMLVideoElement;
                vid.play().catch(() => {});
              }}
              className={`w-full h-full object-contain transition-transform duration-300 ${
                zoomLevel === 1.5 ? 'scale-150' : zoomLevel === 2 ? 'scale-200' : 'scale-100'
              }`}
            />

            {/* Offline or Waiting State */}
            {!hasStream && (
              <div className="absolute inset-0 bg-gradient-to-b from-slate-950/95 via-slate-900/90 to-slate-950/95 flex flex-col items-center justify-center text-center p-6">
                <div className="w-16 h-16 rounded-3xl bg-slate-800/80 border border-slate-700/60 flex items-center justify-center text-slate-400 mb-3 shadow-inner">
                  <Smartphone className="w-8 h-8 text-indigo-400 animate-pulse" />
                </div>
                <h3 className="text-base font-bold text-white mb-1">
                  {connectionStatus === 'connecting' ? t.streamConnecting : t.streamOffline}
                </h3>
                <p className="text-xs text-slate-400 max-w-md mt-1">
                  {lang === 'hi'
                    ? 'बच्चे के फोन में इस वेबसाइट को खोलें, और "स्क्रीन शेयरिंग शुरू करें" दबाएं। या ऊपर दिए गए कोड (उदा. ' + inputCode + ') से कनेक्ट करें।'
                    : 'Open this app on child device and click "Start Screen Share". Then ensure the pairing code matches above.'}
                </p>

                {/* Helpful Android Tip */}
                <div className="mt-3 px-3 py-2 rounded-xl bg-slate-900/90 border border-slate-800 text-[11px] text-cyan-300 max-w-md">
                  {lang === 'hi'
                    ? '💡 नोट: यदि बच्चा दूसरा ऐप खोलता है, तो Android ब्राउज़र स्क्रीन शेयर रोक देता है। 24/7 बिना रुके स्क्रीन देखने के लिए ऊपर "📱 असली Android APK" टैब से APK लगाएं।'
                    : '💡 Note: Switching apps on Android pauses browser streaming. Use our "Real Android APK" for 24/7 background streaming.'}
                </div>

                <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
                  <button
                    onClick={() => handleConnect(inputCode)}
                    className="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold rounded-xl transition shadow cursor-pointer active:scale-95"
                  >
                    {lang === 'hi' ? 'पुनः प्रयास करें (Retry)' : 'Retry Connection'}
                  </button>
                </div>
              </div>
            )}

            {/* Live Video Sync Button for mobile browsers */}
            {hasStream && (
              <button
                onClick={() => {
                  if (videoRef.current) {
                    videoRef.current.play().catch(() => {});
                  }
                }}
                className="absolute bottom-4 left-4 z-20 px-3 py-1.5 bg-slate-900/80 hover:bg-slate-900 backdrop-blur-md rounded-xl text-white text-xs border border-white/20 transition flex items-center gap-1.5 shadow-lg active:scale-95 cursor-pointer"
              >
                <span className="w-2 h-2 rounded-full bg-emerald-400 animate-ping"></span>
                <span>{lang === 'hi' ? 'लाइव सिंक' : 'Sync Live'}</span>
              </button>
            )}

            {/* Floating Top Status (When Live) */}
            {hasStream && (
              <div className="absolute top-3 left-3 right-3 flex items-center justify-between pointer-events-none z-10">
                <div className="flex items-center gap-2 bg-black/60 backdrop-blur-md px-3 py-1 rounded-full border border-white/10 text-white text-xs pointer-events-auto">
                  <span className="w-2 h-2 rounded-full bg-red-500 animate-ping" />
                  <span className="font-bold tracking-wider text-[11px] text-red-400 uppercase">LIVE</span>
                  <span className="text-slate-400">•</span>
                  <span className="font-mono text-[11px]">{formatDuration(streamDuration)}</span>
                </div>

                {isRecording && (
                  <div className="flex items-center gap-1.5 bg-rose-600/90 text-white text-xs px-3 py-1 rounded-full font-bold animate-pulse">
                    <span className="w-2 h-2 rounded-full bg-white" />
                    REC
                  </div>
                )}
              </div>
            )}

            {/* In-Player Bottom Control Overlay */}
            {hasStream && (
              <div className="absolute bottom-3 left-3 right-3 bg-slate-950/80 backdrop-blur-md border border-slate-800 px-4 py-2.5 rounded-2xl flex items-center justify-between gap-3 text-slate-200 transition opacity-90 hover:opacity-100 shadow-xl">
                {/* Left: Quick Snapshot & Record */}
                <div className="flex items-center gap-2">
                  <button
                    onClick={captureScreenshot}
                    title={t.takeScreenshot}
                    className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-blue-600 hover:bg-blue-500 text-white text-xs font-bold transition shadow-sm active:scale-95"
                  >
                    <Camera className="w-4 h-4" />
                    <span className="hidden sm:inline">{t.takeScreenshot}</span>
                  </button>

                  {!isRecording ? (
                    <button
                      onClick={startRecording}
                      title={t.recordingStart}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold transition border border-slate-700"
                    >
                      <Video className="w-4 h-4 text-rose-400" />
                      <span className="hidden sm:inline">{t.recordingStart}</span>
                    </button>
                  ) : (
                    <button
                      onClick={stopRecording}
                      title={t.recordingStop}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-rose-600 hover:bg-rose-500 text-white text-xs font-bold transition animate-pulse"
                    >
                      <Video className="w-4 h-4" />
                      <span>{t.recordingStop}</span>
                    </button>
                  )}

                  <button
                    onClick={() => setShowBuzzerModal(true)}
                    title={t.sendBuzzer}
                    className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/30 text-xs font-bold transition"
                  >
                    <BellRing className="w-4 h-4 text-amber-400" />
                    <span className="hidden sm:inline">{t.sendBuzzer}</span>
                  </button>
                </div>

                {/* Right: Zoom, Audio, Fullscreen */}
                <div className="flex items-center gap-1.5">
                  {/* Zoom Toggle */}
                  <button
                    onClick={() => setZoomLevel((prev) => (prev === 1 ? 1.5 : prev === 1.5 ? 2 : 1))}
                    title="Zoom in to read messages"
                    className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 transition text-xs font-mono font-bold flex items-center gap-1"
                  >
                    <ZoomIn className="w-3.5 h-3.5" />
                    <span>{zoomLevel}x</span>
                  </button>

                  {/* Audio Toggle */}
                  <button
                    onClick={() => setIsAudioMuted(!isAudioMuted)}
                    title={isAudioMuted ? 'Unmute Audio' : 'Mute Audio'}
                    className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 transition"
                  >
                    {isAudioMuted ? <VolumeX className="w-4 h-4 text-rose-400" /> : <Volume2 className="w-4 h-4 text-emerald-400" />}
                  </button>

                  {/* Fullscreen */}
                  <button
                    onClick={toggleFullscreen}
                    title={t.fullscreen}
                    className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 transition"
                  >
                    {isFullscreen ? <Minimize className="w-4 h-4" /> : <Maximize className="w-4 h-4" />}
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Quick Safety Buzzer Presets Bar */}
        <div className="mt-4 p-3 bg-slate-950/50 rounded-2xl border border-slate-800/80 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-xs text-slate-300 font-semibold">
            <BellRing className="w-4 h-4 text-amber-400" />
            <span>{lang === 'hi' ? 'त्वरित ध्यान अलर्ट (Quick Alert):' : 'Quick Remote Alerts:'}</span>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <button
              onClick={() => handleSendBuzzer(t.presetAlert1)}
              className="px-2.5 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs transition border border-slate-700"
            >
              📚 {t.presetAlert1}
            </button>
            <button
              onClick={() => handleSendBuzzer(t.presetAlert2)}
              className="px-2.5 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs transition border border-slate-700"
            >
              🍲 {t.presetAlert2}
            </button>
            <button
              onClick={() => handleSendBuzzer(t.presetAlert3)}
              className="px-2.5 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs transition border border-slate-700"
            >
              📞 {t.presetAlert3}
            </button>
            <button
              onClick={() => setShowBuzzerModal(true)}
              className="px-2.5 py-1.5 rounded-lg bg-indigo-600/30 hover:bg-indigo-600/50 text-indigo-300 text-xs font-semibold transition border border-indigo-500/30"
            >
              + {lang === 'hi' ? 'कस्टम संदेश' : 'Custom'}
            </button>
          </div>
        </div>
      </div>

      {/* Captured Screenshots Gallery */}
      <div className="bg-slate-900/80 border border-slate-800 backdrop-blur-md rounded-3xl p-5 sm:p-6 shadow-2xl">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <Camera className="w-5 h-5 text-blue-400" />
            <h3 className="text-base font-bold text-white">
              {t.screenshotsHistory}
            </h3>
            <span className="text-xs px-2 py-0.5 rounded-full bg-slate-800 text-slate-400 font-mono">
              {snapshots.length}
            </span>
          </div>

          {snapshots.length > 0 && (
            <button
              onClick={() => {
                setSnapshots([]);
                localStorage.removeItem('kidguard_snapshots');
              }}
              className="text-xs text-slate-500 hover:text-rose-400 transition"
            >
              {lang === 'hi' ? 'सभी हटाएं (Clear All)' : 'Clear All'}
            </button>
          )}
        </div>

        {snapshots.length === 0 ? (
          <div className="text-center py-8 border border-dashed border-slate-800 rounded-2xl">
            <Camera className="w-8 h-8 text-slate-600 mx-auto mb-2" />
            <p className="text-xs text-slate-400">{t.noScreenshots}</p>
            <p className="text-[11px] text-slate-500 mt-1">
              {lang === 'hi'
                ? 'लाइव स्क्रीन देखते समय ऊपर दिए गए "स्क्रीनशॉट लें" बटन पर क्लिक करें।'
                : 'Click "Take Screenshot" while watching the live stream to save proof images.'}
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
            {snapshots.map((snap) => (
              <div
                key={snap.id}
                className="group relative bg-slate-950 border border-slate-800 rounded-xl overflow-hidden shadow-sm hover:border-slate-700 transition"
              >
                <img
                  src={snap.dataUrl}
                  alt="Snapshot"
                  className="w-full aspect-[9/16] object-cover bg-slate-900"
                />
                <div className="p-2 bg-slate-950/90 text-[10px] text-slate-400 flex items-center justify-between">
                  <span>{new Date(snap.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}</span>
                  <div className="flex items-center gap-1.5">
                    <a
                      href={snap.dataUrl}
                      download={`child-screen-${snap.timestamp}.jpg`}
                      className="text-slate-400 hover:text-white transition"
                      title={t.downloadSnapshot}
                    >
                      <Download className="w-3.5 h-3.5" />
                    </a>
                    <button
                      onClick={() => {
                        const next = snapshots.filter((s) => s.id !== snap.id);
                        setSnapshots(next);
                        localStorage.setItem('kidguard_snapshots', JSON.stringify(next));
                      }}
                      className="text-slate-400 hover:text-rose-400 transition"
                      title={t.deleteSnapshot}
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Custom Buzzer Modal */}
      {showBuzzerModal && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 max-w-sm w-full shadow-2xl">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-xl bg-amber-500/20 text-amber-400 flex items-center justify-center">
                <BellRing className="w-5 h-5" />
              </div>
              <div>
                <h3 className="text-base font-bold text-white">
                  {t.sendBuzzer}
                </h3>
                <p className="text-xs text-slate-400">
                  {lang === 'hi' ? 'बच्चे के फोन पर यह संदेश आवाज के साथ दिखेगा' : 'This message will chime with sound on child phone'}
                </p>
              </div>
            </div>

            <textarea
              value={buzzerText}
              onChange={(e) => setBuzzerText(e.target.value)}
              placeholder={lang === 'hi' ? 'उदा: बेटा, फोन रखकर खाना खाने आओ!' : 'e.g. Put your phone away and come for dinner!'}
              rows={3}
              className="w-full p-3 bg-slate-950 border border-slate-700 rounded-xl text-white text-xs focus:outline-hidden focus:border-amber-500 resize-none mb-4"
              autoFocus
            />

            {alertSentSuccess ? (
              <div className="p-2.5 bg-emerald-500/20 border border-emerald-500/30 text-emerald-300 rounded-xl text-xs font-semibold flex items-center justify-center gap-2 mb-2">
                <CheckCircle className="w-4 h-4" />
                <span>{lang === 'hi' ? 'अलर्ट सफलतापूर्वक भेजा गया!' : 'Alert sent successfully!'}</span>
              </div>
            ) : (
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => setShowBuzzerModal(false)}
                  className="flex-1 py-2.5 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded-xl text-xs font-semibold transition"
                >
                  {lang === 'hi' ? 'रद्द करें' : 'Cancel'}
                </button>
                <button
                  type="button"
                  onClick={() => handleSendBuzzer()}
                  className="flex-1 py-2.5 bg-gradient-to-r from-amber-500 to-orange-500 hover:from-amber-400 hover:to-orange-400 text-slate-950 font-bold rounded-xl text-xs transition flex items-center justify-center gap-1.5"
                >
                  <Send className="w-3.5 h-3.5" />
                  <span>{lang === 'hi' ? 'भेजें (Buzz)' : 'Send Buzz'}</span>
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {/* QR Scanner Modal for Camera scanning */}
      <QRScannerModal
        isOpen={showQRScanner}
        onClose={() => setShowQRScanner(false)}
        onScanSuccess={(code) => {
          setInputCode(code);
          handleConnect(code);
        }}
        lang={lang}
      />
    </div>
  );
};
