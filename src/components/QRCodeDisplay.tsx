import React, { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { QrCode as QrIcon, Copy, Check, Download, ExternalLink } from 'lucide-react';

interface QRCodeDisplayProps {
  value: string;
  roomCode: string;
  size?: number;
  label?: string;
  sublabel?: string;
  showDownload?: boolean;
}

export const QRCodeDisplay: React.FC<QRCodeDisplayProps> = ({
  value,
  roomCode,
  size = 200,
  label,
  sublabel,
  showDownload = true,
}) => {
  const [svgString, setSvgString] = useState<string>('');
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!value) return;

    // Use QRCode.toString with 'svg' type: 100% reliable, zero canvas dependencies
    QRCode.toString(value, {
      type: 'svg',
      margin: 1,
      color: {
        dark: '#0f172a',
        light: '#ffffff',
      },
    })
      .then((svg) => {
        setSvgString(svg);
      })
      .catch((err) => {
        console.error('Error generating SVG QR code:', err);
      });
  }, [value]);

  const copyLink = () => {
    navigator.clipboard.writeText(value);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const downloadQR = () => {
    if (!svgString) return;
    const blob = new Blob([svgString], { type: 'image/svg+xml' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `kidguard-qr-${roomCode}.svg`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="flex flex-col items-center bg-slate-950/80 border border-slate-800 p-4 rounded-2xl shadow-xl text-center">
      {/* SVG Container */}
      <div 
        className="p-3 bg-white rounded-2xl shadow-md overflow-hidden flex items-center justify-center transition-transform hover:scale-102"
        style={{ width: size + 24, height: size + 24 }}
      >
        {svgString ? (
          <div 
            dangerouslySetInnerHTML={{ __html: svgString }} 
            className="w-full h-full flex items-center justify-center [&>svg]:w-full [&>svg]:h-full"
          />
        ) : (
          <div className="flex flex-col items-center justify-center text-slate-400 gap-2">
            <QrIcon className="w-8 h-8 animate-pulse text-indigo-500" />
            <span className="text-[10px] font-mono">QR Code Loading...</span>
          </div>
        )}
      </div>

      {label && (
        <p className="text-xs font-bold text-white mt-3 flex items-center gap-1.5">
          <QrIcon className="w-3.5 h-3.5 text-cyan-400" />
          <span>{label}</span>
        </p>
      )}

      {sublabel && (
        <p className="text-[11px] text-slate-400 max-w-xs mt-0.5">
          {sublabel}
        </p>
      )}

      {/* Action buttons */}
      <div className="flex items-center gap-2 mt-3">
        <button
          onClick={copyLink}
          className="flex items-center gap-1 px-3 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold transition border border-slate-700"
          title="पेयरिंग लिंक कॉपी करें"
        >
          {copied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
          <span>{copied ? 'लिंक कॉपी हो गया!' : 'पेयरिंग लिंक कॉपी करें'}</span>
        </button>

        {showDownload && (
          <button
            onClick={downloadQR}
            className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs transition border border-slate-700"
            title="QR कोड डाउनलोड करें"
          >
            <Download className="w-3.5 h-3.5" />
          </button>
        )}
      </div>
    </div>
  );
};
