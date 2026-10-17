import { Peer, MediaConnection, DataConnection } from 'peerjs';

export interface PeerMessage {
  type: 'ALERT' | 'PING' | 'ACK' | 'APP_CHANGE' | 'HEARTBEAT';
  payload: any;
  timestamp: number;
}

export class PeerManager {
  private peer: Peer | null = null;
  private currentCall: MediaConnection | null = null;
  private dataConn: DataConnection | null = null;
  private broadcastChannel: BroadcastChannel | null = null;
  private onStreamCallback: ((stream: MediaStream) => void) | null = null;
  private onMessageCallback: ((msg: PeerMessage) => void) | null = null;
  private onConnectionStatusCallback: ((status: 'connected' | 'disconnected' | 'connecting') => void) | null = null;
  private myId: string = '';

  constructor() {
    if (typeof window !== 'undefined' && 'BroadcastChannel' in window) {
      try {
        this.broadcastChannel = new BroadcastChannel('kidguard_sync_channel');
        this.broadcastChannel.onmessage = (event) => {
          if (event.data && this.onMessageCallback) {
            this.onMessageCallback(event.data);
          }
        };
      } catch {
        // Fallback
      }
    }
  }

  initPeer(customId: string, onReady?: (id: string) => void, onError?: (err: any) => void) {
    if (this.peer) {
      this.peer.destroy();
    }

    this.myId = customId;
    
    // Connect to public PeerJS STUN/TURN server
    this.peer = new Peer(customId, {
      config: {
        iceServers: [
          { urls: 'stun:stun.l.google.com:19302' },
          { urls: 'stun:stun1.l.google.com:19302' },
          { urls: 'stun:stun2.l.google.com:19302' }
        ]
      },
      debug: 0 // Suppress noisy PeerJS internal console warnings for offline peers
    });

    this.peer.on('open', (id) => {
      this.myId = id;
      onReady?.(id);
    });

    this.peer.on('error', (err: any) => {
      // If target peer is offline or not created yet, it's a standard waiting state
      if (err && (err.type === 'peer-unavailable' || err.message?.includes?.('Could not connect to peer'))) {
        this.onConnectionStatusCallback?.('disconnected');
        return;
      }
      if (err && err.type === 'unavailable-id') {
        // ID temporarily active from recent session
        return;
      }
      console.warn('Peer error handled:', err?.message || err);
      onError?.(err);
    });

    // Handle incoming data connections
    this.peer.on('connection', (conn) => {
      this.setupDataConnection(conn);
    });

    // Handle incoming calls (e.g. if parent calls child or child answers)
    this.peer.on('call', (call) => {
      this.currentCall = call;
      this.onConnectionStatusCallback?.('connecting');

      // If we are parent, answer without sending stream to receive child's stream
      call.answer();

      call.on('stream', (remoteStream) => {
        this.onConnectionStatusCallback?.('connected');
        this.onStreamCallback?.(remoteStream);
      });

      call.on('close', () => {
        this.onConnectionStatusCallback?.('disconnected');
      });

      call.on('error', () => {
        this.onConnectionStatusCallback?.('disconnected');
      });
    });
  }

  // Child calls Parent with screen stream
  callWithStream(targetPeerId: string, stream: MediaStream) {
    if (!this.peer) return;

    this.onConnectionStatusCallback?.('connecting');
    const call = this.peer.call(targetPeerId, stream);
    this.currentCall = call;

    call.on('stream', (remoteStream) => {
      this.onConnectionStatusCallback?.('connected');
      this.onStreamCallback?.(remoteStream);
    });

    call.on('close', () => {
      this.onConnectionStatusCallback?.('disconnected');
    });

    call.on('error', (err) => {
      console.warn('Call error:', err);
      this.onConnectionStatusCallback?.('disconnected');
    });

    // Also connect data channel
    this.connectData(targetPeerId);
  }

  connectData(targetPeerId: string) {
    if (!this.peer || this.peer.destroyed) return;
    try {
      const conn = this.peer.connect(targetPeerId, { reliable: true });
      conn.on('error', () => {
        // Suppress unhandled peer connection errors when target is offline
      });
      this.setupDataConnection(conn);
    } catch {
      // ignore
    }
  }

  private setupDataConnection(conn: DataConnection) {
    this.dataConn = conn;
    conn.on('open', () => {
      this.onConnectionStatusCallback?.('connected');
    });

    conn.on('data', (data: any) => {
      this.onMessageCallback?.(data as PeerMessage);
    });

    conn.on('close', () => {
      this.onConnectionStatusCallback?.('disconnected');
    });
  }

  sendMessage(msg: PeerMessage) {
    // Send via WebRTC data channel if open
    if (this.dataConn && this.dataConn.open) {
      try {
        this.dataConn.send(msg);
      } catch (err) {
        console.warn('DataConn send error:', err);
      }
    }

    // Broadcast locally so same-browser tabs (e.g. parent and child testing on same machine) receive it instantly!
    if (this.broadcastChannel) {
      try {
        this.broadcastChannel.postMessage(msg);
      } catch {
        // BroadcastChannel send failed
      }
    }

    // Also sync to localStorage for cross-tab event listening
    try {
      localStorage.setItem('kidguard_last_msg', JSON.stringify(msg));
    } catch {
      // ignore
    }
  }

  onStream(callback: (stream: MediaStream) => void) {
    this.onStreamCallback = callback;
  }

  onMessage(callback: (msg: PeerMessage) => void) {
    this.onMessageCallback = callback;
  }

  onStatusChange(callback: (status: 'connected' | 'disconnected' | 'connecting') => void) {
    this.onConnectionStatusCallback = callback;
  }

  cleanup() {
    if (this.currentCall) {
      this.currentCall.close();
      this.currentCall = null;
    }
    if (this.dataConn) {
      this.dataConn.close();
      this.dataConn = null;
    }
    if (this.peer) {
      this.peer.destroy();
      this.peer = null;
    }
  }
}
