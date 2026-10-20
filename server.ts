import express, { Request, Response } from 'express';
import { createServer as createViteServer } from 'vite';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface RoomSignal {
  offer?: { sdp: string; type: string; timestamp: number };
  answer?: { sdp: string; type: string; timestamp: number };
  kidCandidates: Array<{ candidate: string; sdpMid?: string; sdpMLineIndex?: number; timestamp: number }>;
  parentCandidates: Array<{ candidate: string; sdpMid?: string; sdpMLineIndex?: number; timestamp: number }>;
  updatedAt: number;
}

const rooms = new Map<string, RoomSignal>();

function getOrCreateRoom(code: string): RoomSignal {
  const normalized = code.trim().toUpperCase();
  if (!rooms.has(normalized)) {
    rooms.set(normalized, {
      kidCandidates: [],
      parentCandidates: [],
      updatedAt: Date.now(),
    });
  }
  return rooms.get(normalized)!;
}

// Clean up stale rooms older than 6 hours
setInterval(() => {
  const sixHoursAgo = Date.now() - 6 * 60 * 60 * 1000;
  for (const [code, room] of rooms.entries()) {
    if (room.updatedAt < sixHoursAgo) {
      rooms.delete(code);
    }
  }
}, 60 * 60 * 1000);

async function startServer() {
  const app = express();
  const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 3000;
  const isProd = process.env.NODE_ENV === 'production';

  app.use(express.json({ limit: '10mb' }));

  // CORS headers so external Android native APK can reach this server
  app.use((_req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    if (_req.method === 'OPTIONS') {
      res.sendStatus(200);
      return;
    }
    next();
  });

  // Signaling API Endpoints for WebRTC (Kid <-> Parent)
  // 1. Post Offer (from Kid)
  app.post('/api/signal/room/:code/offer', (req: Request, res: Response) => {
    const room = getOrCreateRoom(req.params.code);
    const { sdp, type } = req.body;
    if (!sdp || !type) {
      res.status(400).json({ error: 'Missing sdp or type' });
      return;
    }
    room.offer = { sdp, type, timestamp: Date.now() };
    // Clear previous answer and candidates on new offer
    room.answer = undefined;
    room.kidCandidates = [];
    room.parentCandidates = [];
    room.updatedAt = Date.now();
    console.log(`[Signal] Offer registered for room ${req.params.code.toUpperCase()}`);
    res.json({ success: true, roomCode: req.params.code.toUpperCase() });
  });

  // 2. Get Offer (Parent polls for Kid's offer)
  app.get('/api/signal/room/:code/offer', (req: Request, res: Response) => {
    const normalized = req.params.code.trim().toUpperCase();
    const room = rooms.get(normalized);
    if (!room || !room.offer) {
      res.status(404).json({ error: 'No offer found for this room' });
      return;
    }
    res.json(room.offer);
  });

  // 3. Post Answer (from Parent)
  app.post('/api/signal/room/:code/answer', (req: Request, res: Response) => {
    const room = getOrCreateRoom(req.params.code);
    const { sdp, type } = req.body;
    if (!sdp || !type) {
      res.status(400).json({ error: 'Missing sdp or type' });
      return;
    }
    room.answer = { sdp, type, timestamp: Date.now() };
    room.updatedAt = Date.now();
    console.log(`[Signal] Answer registered for room ${req.params.code.toUpperCase()}`);
    res.json({ success: true, roomCode: req.params.code.toUpperCase() });
  });

  // 4. Get Answer (Kid polls for Parent's answer)
  app.get('/api/signal/room/:code/answer', (req: Request, res: Response) => {
    const normalized = req.params.code.trim().toUpperCase();
    const room = rooms.get(normalized);
    if (!room || !room.answer) {
      res.status(404).json({ error: 'No answer found yet' });
      return;
    }
    res.json(room.answer);
  });

  // 5. Post ICE Candidate
  app.post('/api/signal/room/:code/candidate', (req: Request, res: Response) => {
    const room = getOrCreateRoom(req.params.code);
    const { candidate, sdpMid, sdpMLineIndex, sender } = req.body;
    if (!candidate) {
      res.status(400).json({ error: 'Missing candidate' });
      return;
    }
    const item = {
      candidate,
      sdpMid: sdpMid ?? undefined,
      sdpMLineIndex: typeof sdpMLineIndex === 'number' ? sdpMLineIndex : undefined,
      timestamp: Date.now(),
    };
    if (sender === 'parent') {
      room.parentCandidates.push(item);
    } else {
      room.kidCandidates.push(item);
    }
    room.updatedAt = Date.now();
    res.json({ success: true, count: sender === 'parent' ? room.parentCandidates.length : room.kidCandidates.length });
  });

  // 6. Get ICE Candidates (Kid asks for parent's, Parent asks for kid's)
  app.get('/api/signal/room/:code/candidates', (req: Request, res: Response) => {
    const normalized = req.params.code.trim().toUpperCase();
    const room = rooms.get(normalized);
    if (!room) {
      res.json({ candidates: [] });
      return;
    }
    const forRole = req.query.for as string; // 'parent' wants 'kid' candidates, 'kid' wants 'parent' candidates
    const since = req.query.since ? parseInt(req.query.since as string, 10) : 0;
    const source = forRole === 'parent' ? room.kidCandidates : room.parentCandidates;
    const candidates = source.filter((c) => c.timestamp > since);
    res.json({ candidates });
  });

  // 7. Get Room Status & Ping
  app.get('/api/signal/room/:code/status', (req: Request, res: Response) => {
    const normalized = req.params.code.trim().toUpperCase();
    const room = rooms.get(normalized);
    if (!room) {
      res.json({ exists: false, hasOffer: false, hasAnswer: false });
      return;
    }
    res.json({
      exists: true,
      hasOffer: !!room.offer,
      hasAnswer: !!room.answer,
      kidCandidatesCount: room.kidCandidates.length,
      parentCandidatesCount: room.parentCandidates.length,
      updatedAt: room.updatedAt,
    });
  });

  // 8. Delete / Reset Room
  app.delete('/api/signal/room/:code', (req: Request, res: Response) => {
    const normalized = req.params.code.trim().toUpperCase();
    rooms.delete(normalized);
    res.json({ success: true });
  });

  // Vite Integration
  if (!isProd) {
    const vite = await createViteServer({
      server: { middlewareMode: true, host: '0.0.0.0', port: PORT },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    app.use(express.static(path.resolve(__dirname, 'dist')));
    app.get('*', (_req, res) => {
      res.sendFile(path.resolve(__dirname, 'dist', 'index.html'));
    });
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`KidGuard Server running at http://0.0.0.0:${PORT} (${isProd ? 'production' : 'development'})`);
  });
}

startServer().catch((err) => {
  console.error('Failed to start server:', err);
});
