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
  CheckCircle2,
  Sparkles,
  Camera,
  Mic,
  MicOff,
  Monitor,
  AlertCircle,
  KeyRound,
  ArrowRight
} from 'lucide-react';
import { QRCodeDisplay } from './QRCodeDisplay';
import { PeerManager } from '../services/peerManager';
import { sounds } from '../utils/sound';
import { translations } from '../utils/i18n';
import { Language, BuzzerAlert, DeviceRole } from '../types';

interface ChildViewProps {
  lang: Language;
  peerManager: PeerManager;
  roomCode: string;
  onRegenerateCode: () => void;
  onStreamActive: (active: boolean, stream: MediaStream | null) => void;
  onSelectRole?: (role: DeviceRole) => void;
}

export const ChildView: React.FC<ChildViewProps> = ({
  lang,
  peerManager,
  roomCode,
  onRegenerateCode,
  onStreamActive,
  onSelectRole,
}) => {
  const t = translations[lang];

  const [streamSource, setStreamSource] = useState<'real_screen' | 'camera'>('real_screen');
  const [isStreaming, setIsStreaming] = useState(false);
  const [streamInterrupted, setStreamInterrupted] = useState(false);
  const [bannerError, setBannerError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [qrCodeDataUrl, setQrCodeDataUrl] = useState<string>('');
  const [showQrModal, setShowQrModal] = useState(false);
  const [showAndroidGuidanceModal, setShowAndroidGuidanceModal] = useState(false);
  const [broadcastSeconds, setBroadcastSeconds] = useState(0);

  // Permission states for Camera, Microphone, and Screen Sharing
  const [cameraPerm, setCameraPerm] = useState<'prompt' | 'granted' | 'denied'>('prompt');
  const [micPerm, setMicPerm] = useState<'prompt' | 'granted' | 'denied'>('prompt');
  const [screenPerm, setScreenPerm] = useState<'prompt' | 'granted' | 'denied'>('prompt');
  const [isRequestingPerms, setIsRequestingPerms] = useState(false);

  // Live timer for real screen broadcasting
  useEffect(() => {
    let timer: any;
    if (isStreaming && streamSource === 'real_screen') {
      timer = setInterval(() => {
        setBroadcastSeconds((prev) => prev + 1);
      }, 1000);
    } else {
      setBroadcastSeconds(0);
    }
    return () => clearInterval(timer);
  }, [isStreaming, streamSource]);

  const formatTimer = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  };

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

  // Check initial permissions state on mount
  useEffect(() => {
    if (typeof navigator !== 'undefined' && navigator.permissions?.query) {
      try {
        navigator.permissions.query({ name: 'camera' as any }).then((res) => {
          setCameraPerm(res.state as any);
          res.onchange = () => setCameraPerm(res.state as any);
        }).catch(() => {});

        navigator.permissions.query({ name: 'microphone' as any }).then((res) => {
          setMicPerm(res.state as any);
          res.onchange = () => setMicPerm(res.state as any);
        }).catch(() => {});
      } catch {}
    }
  }, []);

  // Explicitly prompt user for Camera Permission
  const requestCameraPermission = async () => {
    try {
      setBannerError(null);
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'user' }, audio: false });
      setCameraPerm('granted');
      sounds.playChime();
      activeStreamRef.current = stream;
      if (videoPreviewRef.current) {
        videoPreviewRef.current.srcObject = stream;
        videoPreviewRef.current.muted = true;
        videoPreviewRef.current.play().catch(() => {});
      }
      setStreamSource('camera');
      setIsStreaming(true);
      setStreamInterrupted(false);
      broadcastStreamToParent(stream);
      return true;
    } catch (err: any) {
      console.warn('Camera request error:', err);
      setCameraPerm('denied');
      setBannerError(
        lang === 'hi'
          ? 'कैमरा अनुमति अस्वीकार कर दी गई। कृपया ब्राउज़र पॉपअप में "Allow" चुनें।'
          : 'Camera permission denied. Please click "Allow" on the browser prompt.'
      );
      return false;
    }
  };

  // Explicitly prompt user for Microphone Permission
  const requestMicPermission = async () => {
    try {
      setBannerError(null);
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
      setMicPerm('granted');
      sounds.playChime();
      stream.getTracks().forEach((t) => t.stop());
      return true;
    } catch (err: any) {
      console.warn('Mic request error:', err);
      setMicPerm('denied');
      setBannerError(
        lang === 'hi'
          ? 'माइक्रोफोन अनुमति अस्वीकार कर दी गई। कृपया पॉपअप में "Allow" चुनें।'
          : 'Microphone permission denied. Please select "Allow".'
      );
      return false;
    }
  };

  // 1-Click Request All Permissions
  const requestAllPermissions = async () => {
    setIsRequestingPerms(true);
    setBannerError(null);
    try {
      // 1. First prompt Camera & Microphone
      try {
        const av = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
        setCameraPerm('granted');
        setMicPerm('granted');
        av.getTracks().forEach((t) => t.stop());
      } catch (e1) {
        console.warn('Camera/Mic permission prompt error:', e1);
      }
      // 2. Then prompt Screen Share
      await startRealScreenCapture();
    } finally {
      setIsRequestingPerms(false);
    }
  };

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

  // Only broadcast when stream becomes active or when parent explicitly requests it
  useEffect(() => {
    if (isStreaming && activeStreamRef.current) {
      broadcastStreamToParent(activeStreamRef.current);
    }
  }, [isStreaming]);

  // Start Real Screen Capture (Safe for mobile Android Chrome and Desktop)
  const startRealScreenCapture = async () => {
    setBannerError(null);
    setStreamInterrupted(false);

    try {
      if (!navigator.mediaDevices?.getDisplayMedia) {
        setBannerError(
          lang === 'hi'
            ? 'आपके ब्राउज़र में getDisplayMedia स्क्रीन शेयरिंग समर्थित नहीं है। कृपया कैमरा मोड या ऊपर असली Android APK चुनें।'
            : 'DisplayMedia screen sharing is not supported in this browser. Please use Camera mode or the Real Android APK tab.'
        );
        return;
      }

      const isMobile = typeof navigator !== 'undefined' && /Android|iPhone|iPad|iPod|webOS/i.test(navigator.userAgent);
      let screenStream: MediaStream | null = null;

      if (isMobile) {
        // Mobile Android Chrome: Cleanest single call without constraints
        screenStream = await navigator.mediaDevices.getDisplayMedia({
          video: true,
          audio: false,
        });
      } else {
        try {
          screenStream = await navigator.mediaDevices.getDisplayMedia({
            video: {
              frameRate: { ideal: 15, max: 24 },
              width: { ideal: 1280, max: 1280 },
              height: { ideal: 720, max: 720 },
            } as any,
            audio: false,
          });
        } catch (errDesktop: any) {
          if (errDesktop.name === 'NotAllowedError' || errDesktop.name === 'AbortError') {
            return; // User cancelled, don't spam prompt
          }
          screenStream = await navigator.mediaDevices.getDisplayMedia({
            video: true,
            audio: false,
          });
        }
      }

      if (!screenStream) {
        return;
      }

      activeStreamRef.current = screenStream;
      setScreenPerm('granted');
      // Do NOT attach screenStream to local videoPreviewRef!
      // Attaching the screen capture to a video element on that same screen creates
      // an infinite feedback loop that causes Android Chrome to crash or run out of GPU memory!

      const videoTrack = screenStream.getVideoTracks()[0];
      if (videoTrack) {
        videoTrack.onended = () => {
          console.log('Screen capture track ended or suspended by OS backgrounding');
          setStreamInterrupted(true);
          setIsStreaming(false);
          onStreamActive(false, null);
        };
      }

      setIsStreaming(true);
      setStreamInterrupted(false);
      broadcastStreamToParent(screenStream);
      sounds.playChime();
    } catch (err: any) {
      console.warn('Screen share error or user cancelled:', err);
      if (err.name !== 'NotAllowedError') {
        setBannerError(
          lang === 'hi'
            ? `स्क्रीन शेयरिंग शुरू नहीं हो सकी: ${err.message || 'त्रुटि'}। कृपया दोबारा कोशिश करें या ऊपर '📱 असली Android APK' टैब देखें।`
            : `Could not start screen share: ${err.message || 'Error'}. Please try again or use the Real Android APK tab.`
        );
      }
    }
  };

  // Start Camera Feed
  const startCameraCapture = async () => {
    setBannerError(null);
    setStreamInterrupted(false);

    try {
      const camStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user' },
        audio: false,
      });

      activeStreamRef.current = camStream;
      if (videoPreviewRef.current) {
        videoPreviewRef.current.srcObject = camStream;
        videoPreviewRef.current.muted = true;
        videoPreviewRef.current.play().catch(() => {});
      }

      setIsStreaming(true);
      setStreamInterrupted(false);
      broadcastStreamToParent(camStream);
      sounds.playChime();
    } catch (err: any) {
      setBannerError(
        lang === 'hi'
          ? `कैमरा चालू नहीं हो सका: ${err.message || 'अनुमति अस्वीकार'}`
          : `Camera access denied or unavailable: ${err.message}`
      );
    }
  };

  // Start Sharing (prompts guidance modal if real_screen on mobile)
  const handleStartShare = (bypassGuidance: boolean | React.MouseEvent = false) => {
    const shouldBypass = typeof bypassGuidance === 'boolean' ? bypassGuidance : false;
    setBannerError(null);
    setStreamInterrupted(false);
    if (streamSource === 'real_screen') {
      if (!shouldBypass) {
        setShowAndroidGuidanceModal(true);
        return;
      }
      startRealScreenCapture();
    } else {
      startCameraCapture();
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
    if (activeStreamRef.current) {
      activeStreamRef.current.getTracks().forEach((t) => t.stop());
      activeStreamRef.current = null;
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
      {/* Interrupted stream alert (e.g. app switch in mobile Android) */}
      {streamInterrupted && (
        <div className="mb-6 p-5 rounded-2xl bg-amber-500/15 border-2 border-amber-500/40 text-amber-200 shadow-xl space-y-3">
          <div className="flex items-start gap-3">
            <div className="p-2.5 bg-amber-500 text-slate-950 rounded-xl shrink-0 mt-0.5">
              <AlertTriangle className="w-5 h-5" />
            </div>
            <div>
              <h4 className="text-sm font-bold text-white">
                {lang === 'hi'
                  ? '⚠️ स्क्रीन शेयरिंग रुक गई है (ऐप स्विच होने के कारण)'
                  : '⚠️ Screen sharing paused (App switched or minimized)'}
              </h4>
              <p className="text-xs text-amber-200/90 mt-1 max-w-xl leading-relaxed">
                {lang === 'hi'
                  ? 'Android OS की सुरक्षा नीति: जब आप ब्राउज़र छोड़कर दूसरा ऐप (जैसे YouTube, WhatsApp आदि) खोलते हैं या वापस आते हैं, तो Android वेब ब्राउज़र की स्क्रीन रिकॉर्डिंग रोक देता है। यह कोई बग नहीं है, बल्कि Android का सिस्टम सुरक्षा नियम है।'
                  : 'Android Security Policy: When switching to another app or minimizing Chrome, the OS automatically terminates browser screen recording.'}
              </p>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2 pt-2 border-t border-amber-500/20">
            <button
              onClick={() => handleStartShare(true)}
              className="px-4 py-2.5 bg-blue-600 hover:bg-blue-500 text-white text-xs font-bold rounded-xl transition flex items-center justify-center gap-1.5 shadow-md active:scale-95 cursor-pointer"
            >
              <RefreshCw className="w-3.5 h-3.5" />
              <span>{lang === 'hi' ? '🔄 स्क्रीन शेयरिंग दोबारा शुरू करें' : '🔄 Resume Screen Share'}</span>
            </button>
            {onSelectRole && (
              <button
                onClick={() => onSelectRole('flutter-guide')}
                className="px-4 py-2.5 bg-gradient-to-r from-cyan-600 to-teal-600 hover:from-cyan-500 hover:to-teal-500 text-white text-xs font-bold rounded-xl transition shadow-md flex items-center justify-center gap-1.5 cursor-pointer active:scale-95"
              >
                <Smartphone className="w-3.5 h-3.5" />
                <span>{lang === 'hi' ? '📱 24x7 बैकग्राउंड के लिए असली APK डाउनलोड करें' : '📱 Get Real APK (24/7 Background)'}</span>
              </button>
            )}
          </div>
        </div>
      )}

      {/* Inline Error Banner */}
      {bannerError && (
        <div className="mb-6 p-4 rounded-2xl bg-rose-500/15 border border-rose-500/40 text-rose-200 shadow-lg flex items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <AlertTriangle className="w-5 h-5 text-rose-400 shrink-0" />
            <p className="text-xs font-medium text-rose-200">{bannerError}</p>
          </div>
          <button
            onClick={() => setBannerError(null)}
            className="px-2.5 py-1 bg-rose-500/20 hover:bg-rose-500/30 text-rose-200 text-xs rounded-lg transition"
          >
            ✕
          </button>
        </div>
      )}

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

      {/* Clear Android vs Chrome Device Notice */}
      <div className="mb-6 p-4 rounded-2xl bg-gradient-to-r from-blue-950/70 via-indigo-950/40 to-slate-900 border border-blue-500/30 text-xs shadow-lg space-y-2">
        <div className="flex items-center gap-2 text-cyan-300 font-bold">
          <Smartphone className="w-4 h-4 shrink-0" />
          <span>{lang === 'hi' ? 'आपका फोन Android है, लेकिन यह लिंक Chrome ब्राउज़र में खुला है:' : 'Your device is Android, but running inside Chrome Browser:'}</span>
        </div>
        <p className="text-slate-300 leading-relaxed text-[11px]">
          {lang === 'hi'
            ? 'क्योंकि यह एक वेब लिंक है, इसलिए आपका फोन इसे Google Chrome ब्राउज़र में खोलता है। Android का सुरक्षा नियम है कि Chrome ब्राउज़र बैकग्राउंड में स्क्रीन रिकॉर्ड नहीं कर सकता (मिनिमाइज़ या बंद हो जाता है)।'
            : 'Because this is a web URL, your Android phone opened it in Google Chrome. Android security policy restricts web browsers from capturing screen in background.'}
        </p>
        <div className="flex flex-wrap items-center gap-2 pt-1 text-[11px]">
          <span className="text-emerald-400 font-semibold">
            {lang === 'hi' ? '✅ बिना Chrome के 24/7 स्क्रीन शेयर चलाने के लिए:' : '✅ To run 24/7 without Chrome:'}
          </span>
          {onSelectRole && (
            <button
              onClick={() => onSelectRole('flutter-guide')}
              className="px-3 py-1 bg-cyan-600/30 hover:bg-cyan-600/50 text-cyan-200 border border-cyan-500/40 rounded-lg font-bold transition flex items-center gap-1.5 cursor-pointer shadow-xs active:scale-95"
            >
              <span>{lang === 'hi' ? '📱 असली Android APK (.apk) इनस्टॉल करें' : '📱 Install Real Android APK'}</span>
              <ArrowRight className="w-3.5 h-3.5" />
            </button>
          )}
        </div>
      </div>

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

        {/* Device Permissions Status & Activation Card */}
        <div className="my-5 p-4 rounded-2xl bg-gradient-to-r from-indigo-950/60 to-slate-900 border border-indigo-500/30 shadow-lg">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-3 pb-3 border-b border-indigo-500/20">
            <div className="flex items-center gap-2">
              <div className="p-1.5 bg-indigo-500/20 text-indigo-400 rounded-lg">
                <KeyRound className="w-4 h-4" />
              </div>
              <div>
                <h4 className="text-xs font-bold text-white uppercase tracking-wider">
                  {lang === 'hi' ? 'फोन की आवश्यक अनुमतियां (Device Permissions)' : 'Required Device Permissions'}
                </h4>
                <p className="text-[11px] text-slate-400">
                  {lang === 'hi'
                    ? 'लाइव स्क्रीन, कैमरा और माइक चालू करने के लिए फोन से अनुमति मांगें:'
                    : 'Permissions required to watch child screen, camera, and hear audio:'}
                </p>
              </div>
            </div>

            <button
              onClick={requestAllPermissions}
              disabled={isRequestingPerms}
              className="px-3.5 py-1.5 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500 disabled:opacity-50 text-white rounded-xl text-xs font-bold transition shadow-md flex items-center justify-center gap-1.5 active:scale-95 cursor-pointer shrink-0"
            >
              <CheckCircle2 className="w-3.5 h-3.5" />
              <span>{lang === 'hi' ? 'सभी अनुमतियां चालू करें (Allow All)' : 'Grant All Permissions'}</span>
            </button>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
            {/* Screen Share Perm */}
            <div className="p-2.5 rounded-xl bg-slate-950/60 border border-slate-800 flex items-center justify-between gap-2">
              <div className="flex items-center gap-2 min-w-0">
                <Monitor className="w-4 h-4 text-indigo-400 shrink-0" />
                <div className="truncate">
                  <p className="text-xs font-semibold text-white truncate">
                    {lang === 'hi' ? 'स्क्रीन शेयर' : 'Screen Share'}
                  </p>
                  <p className="text-[10px] text-slate-400">
                    {screenPerm === 'granted'
                      ? (lang === 'hi' ? '✅ अनुमति मिली' : '✅ Allowed')
                      : (lang === 'hi' ? 'अनुमति नहीं है' : 'Not Allowed')}
                  </p>
                </div>
              </div>
              <button
                onClick={startRealScreenCapture}
                className={`px-2.5 py-1 rounded-lg text-[11px] font-bold transition cursor-pointer shrink-0 ${
                  screenPerm === 'granted'
                    ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                    : 'bg-indigo-600 hover:bg-indigo-500 text-white shadow'
                }`}
              >
                {screenPerm === 'granted' ? (lang === 'hi' ? 'सक्रिय' : 'Active') : (lang === 'hi' ? 'अनुमति दें' : 'Allow')}
              </button>
            </div>

            {/* Camera Perm */}
            <div className="p-2.5 rounded-xl bg-slate-950/60 border border-slate-800 flex items-center justify-between gap-2">
              <div className="flex items-center gap-2 min-w-0">
                <Camera className="w-4 h-4 text-cyan-400 shrink-0" />
                <div className="truncate">
                  <p className="text-xs font-semibold text-white truncate">
                    {lang === 'hi' ? 'कैमरा' : 'Camera'}
                  </p>
                  <p className="text-[10px] text-slate-400">
                    {cameraPerm === 'granted'
                      ? (lang === 'hi' ? '✅ अनुमति मिली' : '✅ Allowed')
                      : (lang === 'hi' ? 'अनुमति नहीं है' : 'Not Allowed')}
                  </p>
                </div>
              </div>
              <button
                onClick={requestCameraPermission}
                className={`px-2.5 py-1 rounded-lg text-[11px] font-bold transition cursor-pointer shrink-0 ${
                  cameraPerm === 'granted'
                    ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                    : 'bg-cyan-600 hover:bg-cyan-500 text-white shadow'
                }`}
              >
                {cameraPerm === 'granted' ? (lang === 'hi' ? 'सक्रिय' : 'Active') : (lang === 'hi' ? 'अनुमति दें' : 'Allow')}
              </button>
            </div>

            {/* Microphone Perm */}
            <div className="p-2.5 rounded-xl bg-slate-950/60 border border-slate-800 flex items-center justify-between gap-2">
              <div className="flex items-center gap-2 min-w-0">
                <Mic className="w-4 h-4 text-emerald-400 shrink-0" />
                <div className="truncate">
                  <p className="text-xs font-semibold text-white truncate">
                    {lang === 'hi' ? 'माइक्रोफोन' : 'Microphone'}
                  </p>
                  <p className="text-[10px] text-slate-400">
                    {micPerm === 'granted'
                      ? (lang === 'hi' ? '✅ अनुमति मिली' : '✅ Allowed')
                      : (lang === 'hi' ? 'अनुमति नहीं है' : 'Not Allowed')}
                  </p>
                </div>
              </div>
              <button
                onClick={requestMicPermission}
                className={`px-2.5 py-1 rounded-lg text-[11px] font-bold transition cursor-pointer shrink-0 ${
                  micPerm === 'granted'
                    ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                    : 'bg-emerald-600 hover:bg-emerald-500 text-white shadow'
                }`}
              >
                {micPerm === 'granted' ? (lang === 'hi' ? 'सक्रिय' : 'Active') : (lang === 'hi' ? 'अनुमति दें' : 'Allow')}
              </button>
            </div>
          </div>
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
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <button
              onClick={() => {
                if (isStreaming) stopStreaming();
                setStreamSource('real_screen');
              }}
              className={`p-3.5 rounded-xl border text-left transition flex items-start gap-3 cursor-pointer ${
                streamSource === 'real_screen'
                  ? 'bg-blue-600/20 border-blue-500/50 text-white shadow-md'
                  : 'bg-slate-950/60 border-slate-800 text-slate-400 hover:bg-slate-800/50'
              }`}
            >
              <Cast className="w-5 h-5 text-indigo-400 shrink-0 mt-0.5" />
              <div>
                <p className="text-xs font-bold text-white">{t.modeRealScreen}</p>
                <p className="text-[10px] text-slate-400 mt-0.5 leading-tight">
                  {lang === 'hi' ? 'बच्चे के पूरे फोन की स्क्रीन शेयर (Real Screen Broadcast)' : 'Real phone screen via DisplayMedia'}
                </p>
              </div>
            </button>

            <button
              onClick={() => {
                if (isStreaming) stopStreaming();
                setStreamSource('camera');
              }}
              className={`p-3.5 rounded-xl border text-left transition flex items-start gap-3 cursor-pointer ${
                streamSource === 'camera'
                  ? 'bg-blue-600/20 border-blue-500/50 text-white shadow-md'
                  : 'bg-slate-950/60 border-slate-800 text-slate-400 hover:bg-slate-800/50'
              }`}
            >
              <Video className="w-5 h-5 text-teal-400 shrink-0 mt-0.5" />
              <div>
                <p className="text-xs font-bold text-white">{t.modeCamera}</p>
                <p className="text-[10px] text-slate-400 mt-0.5 leading-tight">
                  {lang === 'hi' ? 'बच्चे का लाइव फ्रंट/बैक कैमरा (Live Video Feed)' : 'Front/Back camera live stream'}
                </p>
              </div>
            </button>
          </div>

          {/* Android Mobile Guidance Card */}
          <div className="mt-3.5 p-3.5 bg-blue-950/30 border border-blue-900/40 rounded-2xl text-xs space-y-2">
            <div className="flex items-center gap-2 text-blue-300 font-semibold">
              <Sparkles className="w-4 h-4 text-cyan-400 shrink-0" />
              <span>
                {lang === 'hi'
                  ? 'Android फोन पर स्क्रीन शेयर के लिए विशेष जानकारी:'
                  : 'Important notes for Android screen sharing:'}
              </span>
            </div>
            <ul className="text-slate-300 text-[11px] space-y-1.5 pl-4 list-disc leading-relaxed">
              <li>
                <strong>{lang === 'hi' ? 'पूरे फोन की स्क्रीन (Entire Screen):' : 'Entire Screen:'}</strong>{' '}
                {lang === 'hi'
                  ? 'अब मोबाइल के अनुकूल सेटिंग्स के साथ क्रैश नहीं होगा। Android का "Start recording/casting" प्रॉम्प्ट आने पर "Start now" दबाएं।'
                  : 'Optimized for mobile browsers without crashing. Tap "Start now" on Android system prompt.'}
              </li>
              <li>
                <strong>{lang === 'hi' ? 'सिंगल ऐप (Single App):' : 'Single App:'}</strong>{' '}
                {lang === 'hi'
                  ? 'जब आप कोई ऐप चुनते हैं, तो Android OS खुद उस ऐप को खोल देता है।'
                  : 'Android brings the selected app to foreground automatically.'}
              </li>
              <li>
                <strong>{lang === 'hi' ? '24x7 बैकग्राउंड मॉनिटरिंग:' : '24/7 Background Monitoring:'}</strong>{' '}
                {lang === 'hi'
                  ? 'वेब ब्राउज़र दूसरा ऐप खुलने पर बैकग्राउंड में स्क्रीन रोक देता है। यदि आप चाहते हैं कि बच्चा कोई भी गेम या यूट्यूब चलाए और स्क्रीन कभी न रुके, तो'
                  : 'Mobile browsers pause when child switches to other apps. For uninterrupted background screen mirroring,'}{' '}
                {onSelectRole ? (
                  <button
                    onClick={() => onSelectRole('flutter-guide')}
                    className="text-cyan-400 font-bold underline hover:text-cyan-300 inline cursor-pointer"
                  >
                    {lang === 'hi' ? 'Flutter Android APK का इस्तेमाल करें' : 'use Flutter Android APK'}
                  </button>
                ) : (
                  <span className="text-cyan-400 font-bold">
                    {lang === 'hi' ? 'Flutter Android APK का इस्तेमाल करें' : 'use Flutter Android APK'}
                  </span>
                )}
                ।
              </li>
            </ul>
          </div>
        </div>

        {/* Live Stream View */}
        <div className="mb-6">
          {streamSource === 'real_screen' && isStreaming ? (
            /* Crash-Proof Broadcasting Active Card for Mobile */
            <div className="p-6 bg-gradient-to-br from-slate-900 via-indigo-950/40 to-slate-950 border-2 border-emerald-500/50 rounded-2xl shadow-2xl text-center space-y-4 relative overflow-hidden">
              <div className="absolute top-3 right-3 flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-500/20 border border-emerald-500/40 text-emerald-300 text-xs font-mono font-bold animate-pulse">
                <span className="w-2 h-2 rounded-full bg-emerald-400"></span>
                <span>{formatTimer(broadcastSeconds)}</span>
              </div>

              <div className="relative w-20 h-20 mx-auto flex items-center justify-center mt-2">
                <div className="absolute inset-0 rounded-full bg-emerald-500/20 animate-ping" />
                <div className="w-16 h-16 rounded-full bg-emerald-500/25 border-2 border-emerald-400 flex items-center justify-center text-emerald-300 shadow-lg shadow-emerald-500/30">
                  <Cast className="w-8 h-8 animate-pulse" />
                </div>
              </div>

              <div>
                <h3 className="text-lg font-bold text-white tracking-tight">
                  {lang === 'hi' ? '🔴 आपकी स्क्रीन लाइव प्रसारित हो रही है' : '🔴 Screen is Broadcasting Live'}
                </h3>
                <p className="text-xs text-emerald-300/90 font-mono mt-1">
                  {lang === 'hi'
                    ? `पेयरिंग कोड: ${roomCode} • माता-पिता के फोन पर लाइव दिख रही है`
                    : `Room: ${roomCode} • Live on Parent Phone`}
                </p>
              </div>

              <div className="p-3 bg-slate-950/80 rounded-xl border border-slate-800 text-xs text-slate-300 flex items-center justify-center gap-2 max-w-md mx-auto">
                <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0" />
                <span>
                  {lang === 'hi'
                    ? 'सुरक्षित WebRTC स्ट्रीम: आपका स्क्रीन वीडियो सीधे माता-पिता के फोन पर भेजा जा रहा है।'
                    : 'End-to-End Secure: Screen video is streaming directly to the paired parent device.'}
                </span>
              </div>
            </div>
          ) : (
            <div className="relative rounded-2xl overflow-hidden bg-black aspect-video max-h-[340px] flex items-center justify-center border border-slate-800 shadow-inner">
              {streamSource === 'camera' && (
                <video
                  ref={videoPreviewRef}
                  autoPlay
                  playsInline
                  muted
                  className="w-full h-full object-contain"
                />
              )}
              {!isStreaming && (
                <div className="absolute inset-0 bg-slate-950/85 backdrop-blur-xs flex flex-col items-center justify-center text-center p-4">
                  {streamInterrupted ? (
                    <>
                      <div className="p-3 bg-amber-500/20 text-amber-400 rounded-2xl mb-2 border border-amber-500/30">
                        <AlertTriangle className="w-8 h-8" />
                      </div>
                      <p className="text-sm font-bold text-white">
                        {lang === 'hi'
                          ? 'स्क्रीन शेयरिंग रुक गई (या ऐप स्विच हुआ)'
                          : 'Screen stream paused (App switched)'}
                      </p>
                      <p className="text-xs text-slate-300 mt-1 max-w-xs leading-relaxed">
                        {lang === 'hi'
                          ? 'Android फोन में ब्राउज़र बैकग्राउंड में जाते ही स्क्रीन पॉज हो जाती है।'
                          : 'Browser paused the stream because another app was opened.'}
                      </p>
                      <button
                        onClick={handleStartShare}
                        className="mt-3 px-5 py-2 bg-blue-600 hover:bg-blue-500 text-white text-xs font-bold rounded-xl transition flex items-center gap-1.5 shadow-lg active:scale-95 cursor-pointer"
                      >
                        <RefreshCw className="w-3.5 h-3.5" />
                        <span>{lang === 'hi' ? 'दोबारा स्क्रीन शेयर शुरू करें' : 'Resume Screen Share'}</span>
                      </button>
                    </>
                  ) : (
                    <>
                      <Cast className="w-10 h-10 text-slate-500 mb-2" />
                      <p className="text-sm font-medium text-slate-300">
                        {streamSource === 'real_screen'
                          ? (lang === 'hi' ? 'स्क्रीन शेयरिंग अभी शुरू नहीं हुई है' : 'Screen share not started')
                          : (lang === 'hi' ? 'कैमरा अभी शुरू नहीं हुआ है' : 'Camera not started')}
                      </p>
                      <p className="text-xs text-slate-500 mt-1 max-w-xs">
                        {lang === 'hi'
                          ? 'नीचे दिए गए नीले बटन "स्क्रीन शेयरिंग शुरू करें" पर क्लिक करें।'
                          : 'Click the button below to grant permission and start streaming.'}
                      </p>
                    </>
                  )}
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

            <div className="mx-auto mb-4 flex justify-center">
              <QRCodeDisplay
                value={typeof window !== 'undefined' ? `${window.location.origin}${window.location.pathname}?role=parent&room=${roomCode}` : `KIDGUARD:${roomCode}`}
                roomCode={roomCode}
                size={180}
                showDownload={false}
              />
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

      {/* Android Screen Sharing Guidance Modal */}
      {showAndroidGuidanceModal && (
        <div className="fixed inset-0 z-50 bg-slate-950/85 backdrop-blur-md flex items-center justify-center p-4">
          <div className="bg-slate-900 border border-slate-700/80 rounded-3xl p-6 max-w-lg w-full shadow-2xl space-y-4">
            <div className="flex items-center gap-3 pb-3 border-b border-slate-800">
              <div className="w-12 h-12 rounded-2xl bg-blue-500/20 border border-blue-500/30 flex items-center justify-center text-blue-400 shrink-0">
                <Smartphone className="w-6 h-6" />
              </div>
              <div>
                <h3 className="text-base font-bold text-white">
                  {lang === 'hi' ? 'Android स्क्रीन शेयरिंग: जरूरी जानकारी' : 'Android Screen Sharing Guide'}
                </h3>
                <p className="text-xs text-blue-300">
                  {lang === 'hi' ? 'स्क्रीन शेयर शुरू करने से पहले कृपया इसे समझें' : 'Please review this quick device note'}
                </p>
              </div>
            </div>

            <div className="space-y-3 text-xs text-slate-300">
              {/* Entire screen explanation */}
              <div className="p-3 rounded-xl bg-slate-950/80 border border-slate-800/80 space-y-1">
                <p className="font-bold text-white flex items-center gap-1.5">
                  <span className="w-5 h-5 rounded-full bg-blue-600/30 text-blue-400 flex items-center justify-center text-[11px] font-bold">1</span>
                  <span>{lang === 'hi' ? '"Entire screen" चुनने पर:' : 'When selecting "Entire screen":'}</span>
                </p>
                <p className="text-slate-400 pl-6.5 leading-relaxed">
                  {lang === 'hi'
                    ? 'Android का "Start now" दबाने पर Chrome अपने आप बैकग्राउंड में चला जाएगा और होम स्क्रीन दिखेगी। ऐप बंद या क्रैश नहीं हुआ है, बल्कि स्क्रीन शेयरिंग चालू हो गई है!'
                    : 'Android will minimize Chrome to show your home screen. The app has NOT crashed; live broadcasting is active!'}
                </p>
              </div>

              {/* Single app explanation */}
              <div className="p-3 rounded-xl bg-slate-950/80 border border-slate-800/80 space-y-1">
                <p className="font-bold text-white flex items-center gap-1.5">
                  <span className="w-5 h-5 rounded-full bg-indigo-600/30 text-indigo-400 flex items-center justify-center text-[11px] font-bold">2</span>
                  <span>{lang === 'hi' ? '"Single app" चुनने पर:' : 'When selecting "Single app":'}</span>
                </p>
                <p className="text-slate-400 pl-6.5 leading-relaxed">
                  {lang === 'hi'
                    ? 'Android खुद उस ऐप को खोल देगा। लेकिन जब आप वापस ब्राउज़र में आएंगे, तो Android सुरक्षा के कारण वेब स्क्रीन रिकॉर्डिंग बंद हो जाती है, इसलिए आपको "दोबारा शुरू करें" दबाना होगा।'
                    : 'Android launches the selected app. When you return to the browser, the OS terminates the stream by security policy.'}
                </p>
              </div>

              {/* Background 24/7 APK */}
              <div className="p-3 rounded-xl bg-cyan-950/40 border border-cyan-500/30 space-y-1 text-cyan-200">
                <p className="font-bold text-white flex items-center gap-1.5">
                  <Sparkles className="w-4 h-4 text-cyan-400" />
                  <span>{lang === 'hi' ? '24/7 बिना रुके बैकग्राउंड मॉनिटरिंग:' : '24/7 Background Monitoring:'}</span>
                </p>
                <p className="text-cyan-200/90 pl-6 leading-relaxed">
                  {lang === 'hi'
                    ? 'यदि आप चाहते हैं कि बच्चा कोई भी गेम या यूट्यूब चलाए और स्क्रीन कभी न रुके, तो हमारी असली Android APK का उपयोग करें (Foreground Service सपोर्ट)।'
                    : 'To watch while child plays games or YouTube without pausing, install the real Android APK.'}
                </p>
              </div>
            </div>

            <div className="pt-2 flex flex-col sm:flex-row items-center gap-2">
              <button
                onClick={() => {
                  setShowAndroidGuidanceModal(false);
                  startRealScreenCapture();
                }}
                className="w-full sm:flex-1 py-3 px-4 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500 text-white rounded-xl text-xs font-bold transition shadow-lg flex items-center justify-center gap-2 cursor-pointer active:scale-95"
              >
                <CheckCircle2 className="w-4 h-4" />
                <span>{lang === 'hi' ? 'समझ गया, स्क्रीन शेयर शुरू करें' : 'Got it, Start Screen Share'}</span>
              </button>

              {onSelectRole && (
                <button
                  onClick={() => {
                    setShowAndroidGuidanceModal(false);
                    onSelectRole('flutter-guide');
                  }}
                  className="w-full sm:w-auto py-3 px-4 bg-slate-800 hover:bg-slate-700 text-cyan-300 rounded-xl text-xs font-semibold transition border border-slate-700 flex items-center justify-center gap-1.5 cursor-pointer"
                >
                  <Smartphone className="w-3.5 h-3.5" />
                  <span>{lang === 'hi' ? 'असली Android APK देखें' : 'View Android APK'}</span>
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
