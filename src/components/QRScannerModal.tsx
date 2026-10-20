import React, { useEffect, useRef, useState } from 'react';
import jsQR from 'jsqr';
import { Camera, X, AlertCircle, RefreshCw, QrCode as QrIcon } from 'lucide-react';
import { sounds } from '../utils/sound';

interface QRScannerModalProps {
  isOpen: boolean;
  onClose: () => void;
  onScanSuccess: (code: string) => void;
  lang: 'hi' | 'en';
}

export const QRScannerModal: React.FC<QRScannerModalProps> = ({
  isOpen,
  onClose,
  onScanSuccess,
  lang,
}) => {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [stream, setStream] = useState<MediaStream | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [isScanning, setIsScanning] = useState(false);
  const animFrameIdRef = useRef<number | null>(null);

  useEffect(() => {
    if (!isOpen) {
      stopCamera();
      return;
    }

    startCamera();

    return () => {
      stopCamera();
    };
  }, [isOpen]);

  const startCamera = async () => {
    setErrorMsg(null);
    setIsScanning(true);
    try {
      const mediaStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment', width: { ideal: 640 }, height: { ideal: 480 } },
        audio: false,
      });

      setStream(mediaStream);
      if (videoRef.current) {
        videoRef.current.srcObject = mediaStream;
        videoRef.current.play().catch(() => {});
      }

      // Start scanning loop
      requestAnimationFrame(scanLoop);
    } catch (err: any) {
      console.warn('Camera access error:', err);
      setErrorMsg(
        lang === 'hi'
          ? 'कैमरा शुरू करने में समस्या आई। कृपया कैमरा परमिशन दें या कोड सीधे टाइप करें।'
          : 'Could not access camera. Please allow camera permissions or enter code manually.'
      );
      setIsScanning(false);
    }
  };

  const stopCamera = () => {
    if (animFrameIdRef.current) {
      cancelAnimationFrame(animFrameIdRef.current);
      animFrameIdRef.current = null;
    }
    if (stream) {
      stream.getTracks().forEach((track) => track.stop());
      setStream(null);
    }
    setIsScanning(false);
  };

  const scanLoop = () => {
    const video = videoRef.current;
    const canvas = canvasRef.current;

    if (video && canvas && video.readyState === video.HAVE_ENOUGH_DATA) {
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      if (ctx) {
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

        const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        const code = jsQR(imageData.data, imageData.width, imageData.height, {
          inversionAttempts: 'dontInvert',
        });

        if (code && code.data) {
          // Found QR Code!
          try {
            sounds.playChime();
            if (navigator.vibrate) {
              navigator.vibrate([100, 50, 100]);
            }
          } catch {
            // ignore
          }

          let extractedRoomCode = code.data.trim();

          // If URL like https://.../?room=KID-8429
          try {
            if (code.data.includes('room=')) {
              const url = new URL(code.data);
              const room = url.searchParams.get('room');
              if (room) extractedRoomCode = room;
            }
          } catch {
            // Raw text
          }

          stopCamera();
          onScanSuccess(extractedRoomCode);
          onClose();
          return;
        }
      }
    }

    animFrameIdRef.current = requestAnimationFrame(scanLoop);
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 max-w-sm w-full shadow-2xl relative">
        {/* Header */}
        <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-4">
          <div className="flex items-center gap-2">
            <Camera className="w-5 h-5 text-indigo-400" />
            <h3 className="text-base font-bold text-white">
              {lang === 'hi' ? 'QR कोड स्कैन करें' : 'Scan Child QR Code'}
            </h3>
          </div>
          <button
            onClick={() => {
              stopCamera();
              onClose();
            }}
            className="p-1.5 rounded-xl bg-slate-800 text-slate-400 hover:text-white transition"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Camera Viewfinder */}
        <div className="relative aspect-square w-full rounded-2xl overflow-hidden bg-black border-2 border-indigo-500/40 shadow-inner flex items-center justify-center">
          <video
            ref={videoRef}
            playsInline
            muted
            className="w-full h-full object-cover"
          />
          <canvas ref={canvasRef} className="hidden" />

          {/* Target Scanner Reticle */}
          {isScanning && !errorMsg && (
            <div className="absolute inset-8 border-2 border-cyan-400/80 rounded-2xl pointer-events-none flex flex-col justify-between p-2 animate-pulse">
              <div className="flex justify-between">
                <span className="w-4 h-4 border-t-2 border-l-2 border-cyan-400" />
                <span className="w-4 h-4 border-t-2 border-r-2 border-cyan-400" />
              </div>
              {/* Scan laser line */}
              <div className="w-full h-0.5 bg-gradient-to-r from-transparent via-cyan-400 to-transparent shadow-[0_0_8px_#22d3ee] animate-bounce" />
              <div className="flex justify-between">
                <span className="w-4 h-4 border-b-2 border-l-2 border-cyan-400" />
                <span className="w-4 h-4 border-b-2 border-r-2 border-cyan-400" />
              </div>
            </div>
          )}

          {errorMsg && (
            <div className="absolute inset-0 bg-slate-950/90 flex flex-col items-center justify-center p-4 text-center">
              <AlertCircle className="w-8 h-8 text-amber-400 mb-2" />
              <p className="text-xs text-slate-300 leading-relaxed mb-3">
                {errorMsg}
              </p>
              <button
                onClick={startCamera}
                className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white rounded-xl text-xs font-semibold flex items-center gap-1.5 transition"
              >
                <RefreshCw className="w-3.5 h-3.5" />
                <span>{lang === 'hi' ? 'दोबारा कोशिश करें' : 'Retry Camera'}</span>
              </button>
            </div>
          )}
        </div>

        <p className="text-xs text-slate-400 text-center mt-3">
          {lang === 'hi'
            ? 'बच्चे के फोन पर दिख रहे QR कोड के सामने अपना मोबाइल कैमरा रखें।'
            : 'Hold your camera over the QR code shown on the child\'s phone.'}
        </p>
      </div>
    </div>
  );
};
