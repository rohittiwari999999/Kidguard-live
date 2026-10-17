import React, { useEffect, useRef, useState } from 'react';
import { Play, Pause, Smartphone, MessageSquare, Gamepad2, Tv, BookOpen } from 'lucide-react';

interface SimulatedChildScreenProps {
  onStreamReady?: (stream: MediaStream) => void;
  activeApp?: 'youtube' | 'game' | 'chat' | 'homework';
  onAppChange?: (app: 'youtube' | 'game' | 'chat' | 'homework') => void;
  isStreaming?: boolean;
}

export const SimulatedChildScreen: React.FC<SimulatedChildScreenProps> = ({
  onStreamReady,
  activeApp: controlledApp,
  onAppChange,
  isStreaming = true,
}) => {
  const [internalApp, setInternalApp] = useState<'youtube' | 'game' | 'chat' | 'homework'>('youtube');
  const currentApp = controlledApp || internalApp;
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const animFrameRef = useRef<number | null>(null);

  const [isPlaying, setIsPlaying] = useState(true);

  const setApp = (app: 'youtube' | 'game' | 'chat' | 'homework') => {
    setInternalApp(app);
    onAppChange?.(app);
  };

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let tick = 0;
    let ballX = 60;
    let ballY = 200;
    let ballDx = 3.5;
    let ballDy = 2.5;

    const render = () => {
      tick++;

      // Canvas dimensions 360 x 640 (9:16 mobile aspect ratio)
      const w = canvas.width;
      const h = canvas.height;

      // Clear background
      ctx.fillStyle = '#0f172a';
      ctx.fillRect(0, 0, w, h);

      // 1. Android Status Bar (Top)
      ctx.fillStyle = '#020617';
      ctx.fillRect(0, 0, w, 28);
      ctx.fillStyle = '#94a3b8';
      ctx.font = '11px sans-serif';
      const now = new Date();
      const timeStr = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
      ctx.fillText(timeStr, 14, 18);
      ctx.fillText('5G  📶 88%', w - 75, 18);

      if (currentApp === 'youtube') {
        // --- YouTube Kids Mockup ---
        // Top Bar
        ctx.fillStyle = '#dc2626';
        ctx.fillRect(0, 28, w, 44);
        ctx.fillStyle = '#ffffff';
        ctx.font = 'bold 15px sans-serif';
        ctx.fillText('▶ YouTube Kids', 14, 56);

        // Video Player Box
        const playerH = 200;
        ctx.fillStyle = '#000000';
        ctx.fillRect(10, 80, w - 20, playerH);

        // Animated Cartoon Scene
        // Sky
        ctx.fillStyle = '#38bdf8';
        ctx.fillRect(10, 80, w - 20, 140);
        // Sun
        ctx.fillStyle = '#facc15';
        ctx.beginPath();
        ctx.arc(60 + Math.sin(tick * 0.05) * 10, 120, 24, 0, Math.PI * 2);
        ctx.fill();
        // Rolling Hills
        ctx.fillStyle = '#22c55e';
        ctx.beginPath();
        ctx.moveTo(10, 220);
        ctx.quadraticCurveTo(100, 170 + Math.sin(tick * 0.03) * 5, 200, 210);
        ctx.quadraticCurveTo(280, 180, w - 10, 220);
        ctx.lineTo(w - 10, 280);
        ctx.lineTo(10, 280);
        ctx.fill();

        // Animated Cartoon Character (Bouncing ball / character)
        const charX = 180 + Math.cos(tick * 0.04) * 50;
        const charY = 210 - Math.abs(Math.sin(tick * 0.08) * 35);
        ctx.fillStyle = '#f43f5e';
        ctx.beginPath();
        ctx.arc(charX, charY, 18, 0, Math.PI * 2);
        ctx.fill();
        // Eyes
        ctx.fillStyle = '#ffffff';
        ctx.beginPath();
        ctx.arc(charX - 5, charY - 4, 4, 0, Math.PI * 2);
        ctx.arc(charX + 5, charY - 4, 4, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = '#000000';
        ctx.beginPath();
        ctx.arc(charX - 4, charY - 4, 2, 0, Math.PI * 2);
        ctx.arc(charX + 6, charY - 4, 2, 0, Math.PI * 2);
        ctx.fill();

        // Video Progress bar
        const progress = (tick % 400) / 400;
        ctx.fillStyle = 'rgba(255,255,255,0.3)';
        ctx.fillRect(10, 276, w - 20, 4);
        ctx.fillStyle = '#ef4444';
        ctx.fillRect(10, 276, (w - 20) * progress, 4);

        // Video Title & Channel
        ctx.fillStyle = '#ffffff';
        ctx.font = 'bold 13px sans-serif';
        ctx.fillText('Peppa & Chhota Bheem Jungle Adventure EP 44', 12, 305);
        ctx.fillStyle = '#94a3b8';
        ctx.font = '11px sans-serif';
        ctx.fillText('Kids Fun Station • 2.4M views • 14 mins ago', 12, 325);

        // Recommended Videos Cards
        for (let i = 0; i < 3; i++) {
          const yOff = 345 + i * 85;
          ctx.fillStyle = '#1e293b';
          ctx.roundRect(10, yOff, 110, 68, 6);
          ctx.fill();

          ctx.fillStyle = '#3b82f6';
          ctx.fillRect(16, yOff + 8, 98, 52);
          ctx.fillStyle = '#ffffff';
          ctx.font = '10px sans-serif';
          ctx.fillText(`Cartoons #${i + 1}`, 22, yOff + 36);

          ctx.fillStyle = '#f1f5f9';
          ctx.font = '11px sans-serif';
          ctx.fillText(i === 0 ? 'Motu Patlu Ice Cream Run' : i === 1 ? 'Minecraft Building for Kids' : 'Doraemon Magic Gadget', 130, yOff + 24);
          ctx.fillStyle = '#64748b';
          ctx.font = '10px sans-serif';
          ctx.fillText('Cartoon Network Kids • 1.1M', 130, yOff + 42);
        }

      } else if (currentApp === 'game') {
        // --- Endless Runner / Arcade Game Mockup ---
        ctx.fillStyle = '#064e3b';
        ctx.fillRect(0, 28, w, h - 28);

        // Road / Track
        ctx.fillStyle = '#1e293b';
        ctx.beginPath();
        ctx.moveTo(110, 28);
        ctx.lineTo(250, 28);
        ctx.lineTo(340, h);
        ctx.lineTo(20, h);
        ctx.fill();

        // Road divider lines
        const offset = (tick * 8) % 60;
        ctx.fillStyle = '#f59e0b';
        for (let y = 30 + offset; y < h; y += 60) {
          ctx.fillRect(w / 2 - 4, y, 8, 30);
        }

        // Bouncing Ball Physics
        ballX += ballDx;
        ballY += ballDy;
        if (ballX < 60 || ballX > w - 60) ballDx = -ballDx;
        if (ballY < 120 || ballY > h - 100) ballDy = -ballDy;

        // Player Avatar
        ctx.fillStyle = '#38bdf8';
        ctx.shadowColor = '#0284c7';
        ctx.shadowBlur = 12;
        ctx.beginPath();
        ctx.arc(ballX, ballY, 20, 0, Math.PI * 2);
        ctx.fill();
        ctx.shadowBlur = 0;

        // Score Card
        ctx.fillStyle = 'rgba(0,0,0,0.7)';
        ctx.roundRect(14, 40, 140, 50, 8);
        ctx.fill();
        ctx.fillStyle = '#ffffff';
        ctx.font = 'bold 12px sans-serif';
        ctx.fillText('SUBWAY RUNNER', 22, 60);
        ctx.fillStyle = '#fbbf24';
        ctx.font = 'bold 16px monospace';
        ctx.fillText(`SCORE: ${1240 + tick * 3}`, 22, 80);

        // Coins collected
        ctx.fillStyle = '#eab308';
        ctx.beginPath();
        ctx.arc(w - 30, 60, 12, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = '#ffffff';
        ctx.font = 'bold 12px sans-serif';
        ctx.fillText('🪙 48', w - 80, 64);

      } else if (currentApp === 'chat') {
        // --- WhatsApp / Chat Mockup ---
        ctx.fillStyle = '#075e54';
        ctx.fillRect(0, 28, w, 50);
        ctx.fillStyle = '#ffffff';
        ctx.font = 'bold 14px sans-serif';
        ctx.fillText('Class 6th Friends Group 🎒', 20, 58);

        // Chat background pattern
        ctx.fillStyle = '#0b141a';
        ctx.fillRect(0, 78, w, h - 130);

        // Chat bubbles
        const messages = [
          { sender: 'Aarav', text: 'Did you finish chapter 4 science?', isMe: false, time: '3:45 PM' },
          { sender: 'Child', text: 'Yes, question answers are done 👍', isMe: true, time: '3:48 PM' },
          { sender: 'Rohan', text: 'Can anyone share page 42 photo?', isMe: false, time: '3:50 PM' },
          { sender: 'Child', text: 'Wait let me take photo and send', isMe: true, time: '3:52 PM' },
          { sender: 'Aarav', text: 'Let’s play Roblox after 5 PM!', isMe: false, time: '3:54 PM' },
        ];

        let curY = 100;
        messages.forEach((m) => {
          const bubbleW = 220;
          const bubbleH = 46;
          const bubbleX = m.isMe ? w - bubbleW - 14 : 14;

          ctx.fillStyle = m.isMe ? '#005c4b' : '#202c33';
          ctx.roundRect(bubbleX, curY, bubbleW, bubbleH, 10);
          ctx.fill();

          if (!m.isMe) {
            ctx.fillStyle = '#22c55e';
            ctx.font = 'bold 10px sans-serif';
            ctx.fillText(m.sender, bubbleX + 10, curY + 14);
          }

          ctx.fillStyle = '#e9edef';
          ctx.font = '11px sans-serif';
          ctx.fillText(m.text, bubbleX + 10, curY + (m.isMe ? 22 : 30));

          ctx.fillStyle = '#8696a0';
          ctx.font = '9px sans-serif';
          ctx.fillText(m.time, bubbleX + bubbleW - 48, curY + 38);

          curY += 60;
        });

        // Bottom Input bar
        ctx.fillStyle = '#202c33';
        ctx.fillRect(0, h - 55, w, 55);
        ctx.fillStyle = '#2a3942';
        ctx.roundRect(10, h - 45, w - 60, 36, 18);
        ctx.fill();
        ctx.fillStyle = '#8696a0';
        ctx.font = '12px sans-serif';
        ctx.fillText('Type a message...', 24, h - 22);

        // Send Button
        ctx.fillStyle = '#00a884';
        ctx.beginPath();
        ctx.arc(w - 25, h - 27, 18, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = '#ffffff';
        ctx.font = '12px sans-serif';
        ctx.fillText('➤', w - 30, h - 23);

      } else if (currentApp === 'homework') {
        // --- Educational / Math Quiz App ---
        ctx.fillStyle = '#4338ca';
        ctx.fillRect(0, 28, w, 52);
        ctx.fillStyle = '#ffffff';
        ctx.font = 'bold 15px sans-serif';
        ctx.fillText('📚 Byju\'s / NCERT Math Practice', 16, 60);

        ctx.fillStyle = '#0f172a';
        ctx.fillRect(0, 80, w, h - 80);

        // Card
        ctx.fillStyle = '#1e293b';
        ctx.roundRect(16, 100, w - 32, 220, 12);
        ctx.fill();

        ctx.fillStyle = '#818cf8';
        ctx.font = 'bold 13px sans-serif';
        ctx.fillText('QUESTION 4 OF 10', 32, 130);

        ctx.fillStyle = '#ffffff';
        ctx.font = '15px sans-serif';
        ctx.fillText('Find the area of a rectangle with', 32, 160);
        ctx.fillText('length = 12 cm and width = 8 cm.', 32, 185);

        // Options
        const opts = ['A) 84 cm²', 'B) 96 cm² (Selected ✓)', 'C) 108 cm²', 'D) 40 cm²'];
        opts.forEach((opt, idx) => {
          const isSelected = idx === 1;
          ctx.fillStyle = isSelected ? '#312e81' : '#0f172a';
          ctx.roundRect(32, 210 + idx * 46, w - 64, 38, 8);
          ctx.fill();
          if (isSelected) {
            ctx.strokeStyle = '#6366f1';
            ctx.lineWidth = 2;
            ctx.stroke();
          }

          ctx.fillStyle = isSelected ? '#a5b4fc' : '#cbd5e1';
          ctx.font = '13px sans-serif';
          ctx.fillText(opt, 44, 234 + idx * 46);
        });

        // Time spent badge
        ctx.fillStyle = 'rgba(255,255,255,0.1)';
        ctx.roundRect(16, 420, w - 32, 50, 8);
        ctx.fill();
        ctx.fillStyle = '#34d399';
        ctx.font = '12px sans-serif';
        ctx.fillText('⏱ Time Spent on Quiz: 14 mins 32 sec', 28, 450);
      }

      // Android Navigation Bar (Bottom)
      ctx.fillStyle = '#020617';
      ctx.fillRect(0, h - 22, w, 22);
      ctx.fillStyle = '#64748b';
      // Triangle (Back)
      ctx.beginPath();
      ctx.moveTo(w * 0.25 - 6, h - 11);
      ctx.lineTo(w * 0.25 + 4, h - 17);
      ctx.lineTo(w * 0.25 + 4, h - 5);
      ctx.fill();
      // Circle (Home)
      ctx.beginPath();
      ctx.arc(w * 0.5, h - 11, 5, 0, Math.PI * 2);
      ctx.fill();
      // Square (Recents)
      ctx.fillRect(w * 0.75 - 5, h - 16, 10, 10);

      // Watermark indicator
      ctx.fillStyle = 'rgba(0, 0, 0, 0.4)';
      ctx.fillRect(w - 110, 32, 102, 22);
      ctx.fillStyle = '#38bdf8';
      ctx.font = '9px monospace';
      ctx.fillText('🔴 LIVE SCREEN', w - 104, 46);

      animFrameRef.current = requestAnimationFrame(render);
    };

    render();

    // Capture canvas stream to produce a real MediaStream
    try {
      if (!streamRef.current && canvas.captureStream) {
        const stream = canvas.captureStream(25);
        streamRef.current = stream;
        onStreamReady?.(stream);
      }
    } catch (e) {
      console.warn('captureStream error:', e);
    }

    return () => {
      if (animFrameRef.current) {
        cancelAnimationFrame(animFrameRef.current);
      }
    };
  }, [currentApp, onStreamReady]);

  return (
    <div className="flex flex-col items-center w-full max-w-sm mx-auto">
      {/* App Switcher Tabs */}
      <div className="flex items-center gap-1.5 p-1 bg-slate-900/90 border border-slate-800 rounded-xl mb-3 text-xs w-full overflow-x-auto">
        <button
          onClick={() => setApp('youtube')}
          className={`flex items-center gap-1 px-3 py-1.5 rounded-lg font-medium transition ${
            currentApp === 'youtube'
              ? 'bg-red-600 text-white shadow-sm'
              : 'text-slate-400 hover:text-white hover:bg-slate-800'
          }`}
        >
          <Tv className="w-3.5 h-3.5" />
          <span>YouTube Kids</span>
        </button>

        <button
          onClick={() => setApp('game')}
          className={`flex items-center gap-1 px-3 py-1.5 rounded-lg font-medium transition ${
            currentApp === 'game'
              ? 'bg-amber-600 text-white shadow-sm'
              : 'text-slate-400 hover:text-white hover:bg-slate-800'
          }`}
        >
          <Gamepad2 className="w-3.5 h-3.5" />
          <span>Roblox/Game</span>
        </button>

        <button
          onClick={() => setApp('chat')}
          className={`flex items-center gap-1 px-3 py-1.5 rounded-lg font-medium transition ${
            currentApp === 'chat'
              ? 'bg-emerald-600 text-white shadow-sm'
              : 'text-slate-400 hover:text-white hover:bg-slate-800'
          }`}
        >
          <MessageSquare className="w-3.5 h-3.5" />
          <span>Chat</span>
        </button>

        <button
          onClick={() => setApp('homework')}
          className={`flex items-center gap-1 px-3 py-1.5 rounded-lg font-medium transition ${
            currentApp === 'homework'
              ? 'bg-indigo-600 text-white shadow-sm'
              : 'text-slate-400 hover:text-white hover:bg-slate-800'
          }`}
        >
          <BookOpen className="w-3.5 h-3.5" />
          <span>Homework</span>
        </button>
      </div>

      {/* Realistic Mobile Frame */}
      <div className="relative rounded-[32px] p-2 bg-gradient-to-b from-slate-700 via-slate-800 to-slate-900 shadow-2xl border-2 border-slate-700/60 ring-1 ring-white/10">
        {/* Speaker notch */}
        <div className="absolute top-4 left-1/2 -translate-x-1/2 w-16 h-1.5 bg-black/60 rounded-full z-10" />

        {/* Screen Canvas */}
        <div className="rounded-[24px] overflow-hidden bg-black aspect-[9/16] w-[270px] sm:w-[290px] shadow-inner relative">
          <canvas
            ref={canvasRef}
            width={360}
            height={640}
            className="w-full h-full object-cover"
          />

          {/* Live broadcast pill */}
          <div className="absolute top-2 right-2 bg-red-600/90 text-white text-[10px] px-2 py-0.5 rounded-full font-bold flex items-center gap-1 backdrop-blur-xs shadow-md animate-pulse">
            <span className="w-1.5 h-1.5 rounded-full bg-white animate-ping" />
            LIVE
          </div>
        </div>
      </div>

      <p className="text-[11px] text-slate-400 text-center mt-2">
        💡 ऊपर दिए गए बटन्स (YouTube Kids, Game, Chat, Homework) पर क्लिक करके देखें कि बच्चे के फोन पर जो चल रहा है वो तुरंत माता-पिता के फोन पर दिखता है।
      </p>
    </div>
  );
};
