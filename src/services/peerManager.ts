import { Peer, MediaConnection, DataConnection } from 'peerjs';

export interface PeerMessage {
  type: 'ALERT' | 'PING' | 'ACK' | 'APP_CHANGE' | 'HEARTBEAT' | 'REQUEST_STREAM' | 'PARENT_JOINED';
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
    if (typeof window !== 'undefined') {
      if ('BroadcastChannel' in window) {
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

      // Also listen to storage events for cross-tab multi-window sync
      window.addEventListener('storage', (e) => {
        if (e.key === 'kidguard_last_msg' && e.newValue) {
          try {
            const parsed = JSON.parse(e.newValue);
            this.onMessageCallback?.(parsed);
          } catch {
            // ignore
          }
        }
      });
    }
  }

  private onPeerConnectedCallback: ((peerId: string) => void) | null = null;

  initPeer(customId: string, onReady?: (id: string) => void, onError?: (err: any) => void) {
    if (this.peer) {
      try {
        this.peer.destroy();
      } catch {}
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
        // ID temporarily active from recent session, fallback cleanly
        return;
      }
      console.warn('Peer error handled:', err?.message || err);
      onError?.(err);
    });

    // Handle incoming data connections (e.g. Parent connects to Child)
    this.peer.on('connection', (conn) => {
      this.setupDataConnection(conn);
      this.onPeerConnectedCallback?.(conn.peer);
    });

    // Handle incoming calls (e.g. Child calls Parent with stream)
    this.peer.on('call', (call) => {
      this.currentCall = call;
      this.onConnectionStatusCallback?.('connecting');

      // Answer without sending stream (parent receiving child's screen)
      call.answer();

      // Unified Plan ontrack direct listener to prevent empty event.streams bug
      if (call.peerConnection) {
        call.peerConnection.ontrack = (event: RTCTrackEvent) => {
          console.log(`🔥 [WebRTC] Track received: ${event.track.kind}, streams count: ${event.streams?.length || 0}`);
          if (event.track.kind === 'video' || event.track.kind === 'audio') {
            let streamToUse: MediaStream;
            if (event.streams && event.streams.length > 0 && event.streams[0]) {
              streamToUse = event.streams[0];
            } else {
              // Fallback: If event.streams is empty under Unified Plan, construct MediaStream from track!
              console.log('⚡ Unified Plan Fallback: Creating MediaStream from track');
              streamToUse = new MediaStream([event.track]);
            }
            this.onConnectionStatusCallback?.('connected');
            this.onStreamCallback?.(streamToUse);
          }
        };

        call.peerConnection.oniceconnectionstatechange = () => {
          const state = call.peerConnection?.iceConnectionState;
          console.log(`📡 [WebRTC] ICE Connection State: ${state}`);
          if (state === 'connected' || state === 'completed') {
            this.onConnectionStatusCallback?.('connected');
          } else if (state === 'failed' || state === 'disconnected') {
            this.onConnectionStatusCallback?.('disconnected');
          }
        };
      }

      call.on('stream', (remoteStream) => {
        console.log('📺 [PeerJS] stream event received');
        this.onConnectionStatusCallback?.('connected');
        this.onStreamCallback?.(remoteStream);
      });

      call.on('close', () => {
        this.onConnectionStatusCallback?.('disconnected');
      });

      call.on('error', (err) => {
        console.warn('Call error caught safely:', err);
        this.onConnectionStatusCallback?.('disconnected');
      });
    });
  }

  onPeerConnected(callback: (peerId: string) => void) {
    this.onPeerConnectedCallback = callback;
  }

  // Child calls Parent with screen stream
  callWithStream(targetPeerId: string, stream: MediaStream) {
    if (!this.peer || this.peer.destroyed || !this.peer.open) return;

    // Verify video tracks are present and enabled before creating offer
    const videoTracks = stream.getVideoTracks();
    if (videoTracks.length === 0) {
      console.warn('⚠️ Cannot callWithStream: stream has 0 video tracks');
      return;
    }
    videoTracks.forEach((t) => (t.enabled = true));

    // Prevent duplicate calls if already connecting or connected
    if (this.currentCall) {
      const pc = this.currentCall.peerConnection;
      if (pc && (pc.connectionState === 'connected' || pc.connectionState === 'connecting' || pc.iceConnectionState === 'connected')) {
        return; // Connection is already active, don't recreate encoder
      }
      try {
        this.currentCall.close();
      } catch {}
      this.currentCall = null;
    }

    try {
      this.onConnectionStatusCallback?.('connecting');
      const call = this.peer.call(targetPeerId, stream);
      if (!call) return;
      this.currentCall = call;

      if (call.peerConnection) {
        call.peerConnection.ontrack = (event: RTCTrackEvent) => {
          let streamToUse: MediaStream;
          if (event.streams && event.streams.length > 0 && event.streams[0]) {
            streamToUse = event.streams[0];
          } else {
            streamToUse = new MediaStream([event.track]);
          }
          this.onConnectionStatusCallback?.('connected');
          this.onStreamCallback?.(streamToUse);
        };

        call.peerConnection.oniceconnectionstatechange = () => {
          console.log(`📡 [WebRTC] ICE Connection State: ${call.peerConnection?.iceConnectionState}`);
        };
      }

      call.on('stream', (remoteStream) => {
        this.onConnectionStatusCallback?.('connected');
        this.onStreamCallback?.(remoteStream);
      });

      call.on('close', () => {
        this.currentCall = null;
        this.onConnectionStatusCallback?.('disconnected');
      });

      call.on('error', (err) => {
        console.warn('Call error caught safely:', err?.message || err);
        this.currentCall = null;
        this.onConnectionStatusCallback?.('disconnected');
      });

      // Also connect data channel to ensure two-way messaging
      this.connectData(targetPeerId);
    } catch (err) {
      console.warn('callWithStream non-fatal error:', err);
    }
  }

  connectData(targetPeerId: string, onOpen?: () => void) {
    if (!this.peer || this.peer.destroyed || !this.peer.open) return;
    try {
      if (this.dataConn && this.dataConn.open && this.dataConn.peer === targetPeerId) {
        onOpen?.();
        return;
      }
      const conn = this.peer.connect(targetPeerId, { reliable: true });
      conn.on('error', () => {
        // Suppress unhandled peer connection errors when target is offline
      });
      this.setupDataConnection(conn, onOpen);
    } catch {
      // ignore
    }
  }

  private setupDataConnection(conn: DataConnection, onOpen?: () => void) {
    this.dataConn = conn;
    conn.on('open', () => {
      this.onConnectionStatusCallback?.('connected');
      onOpen?.();
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

  // -------------------------------------------------------------
  // CROSS-PLATFORM HTTP SIGNALING (Connects Web <-> Flutter APK)
  // -------------------------------------------------------------
  private httpPc: RTCPeerConnection | null = null;
  private httpPollTimer: any = null;
  private httpCandidateTimer: any = null;
  private isHttpRemoteDescSet = false;
  private queuedCandidates: RTCIceCandidate[] = [];
  private lastCandidateTs = 0;

  async startHttpChildBroadcast(roomCode: string, stream: MediaStream) {
    this.stopHttpSignaling();
    const cleanCode = roomCode.trim().toUpperCase();

    try {
      this.httpPc = new RTCPeerConnection({
        iceServers: [
          { urls: 'stun:stun.l.google.com:19302' },
          { urls: 'stun:stun1.l.google.com:19302' },
          { urls: 'stun:stun2.l.google.com:19302' },
        ],
      });

      this.httpPc.onicecandidate = (event) => {
        if (event.candidate) {
          fetch(`/api/signal/room/${cleanCode}/candidate`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              candidate: event.candidate.candidate,
              sdpMid: event.candidate.sdpMid,
              sdpMLineIndex: event.candidate.sdpMLineIndex,
              sender: 'kid',
            }),
          }).catch(() => {});
        }
      };

      // Exact Sequence Rule: addTrack BEFORE createOffer!
      stream.getTracks().forEach((track) => {
        this.httpPc?.addTrack(track, stream);
      });

      const offer = await this.httpPc.createOffer();
      await this.httpPc.setLocalDescription(offer);

      await fetch(`/api/signal/room/${cleanCode}/offer`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sdp: offer.sdp, type: offer.type }),
      });

      // Poll for parent answer
      this.httpPollTimer = setInterval(async () => {
        if (this.isHttpRemoteDescSet || !this.httpPc) return;
        try {
          const res = await fetch(`/api/signal/room/${cleanCode}/answer`);
          if (res.ok) {
            const data = await res.json();
            if (data?.sdp && !this.isHttpRemoteDescSet) {
              this.isHttpRemoteDescSet = true;
              clearInterval(this.httpPollTimer);
              await this.httpPc.setRemoteDescription(new RTCSessionDescription(data));
              // Drain candidates
              for (const c of this.queuedCandidates) {
                await this.httpPc.addIceCandidate(c).catch(() => {});
              }
              this.queuedCandidates = [];
              this.startListeningToCandidates(cleanCode, 'kid');
              this.onConnectionStatusCallback?.('connected');
            }
          }
        } catch {}
      }, 1000);
    } catch (e) {
      console.warn('HTTP Child Broadcast error:', e);
    }
  }

  async startHttpParentWatch(roomCode: string, onStream: (stream: MediaStream) => void) {
    this.stopHttpSignaling();
    const cleanCode = roomCode.trim().toUpperCase();

    const tryConnect = async () => {
      try {
        const res = await fetch(`/api/signal/room/${cleanCode}/offer`);
        if (!res.ok) return false;
        const offerData = await res.json();
        if (!offerData?.sdp) return false;

        this.httpPc = new RTCPeerConnection({
          iceServers: [
            { urls: 'stun:stun.l.google.com:19302' },
            { urls: 'stun:stun1.l.google.com:19302' },
            { urls: 'stun:stun2.l.google.com:19302' },
          ],
        });

        // Debug Check 1: ICE state
        this.httpPc.oniceconnectionstatechange = () => {
          const state = this.httpPc?.iceConnectionState;
          console.log(`📡 [HTTP WebRTC] ICE Connection State: ${state}`);
          if (state === 'connected' || state === 'completed') {
            this.onConnectionStatusCallback?.('connected');
          } else if (state === 'failed' || state === 'disconnected') {
            this.onConnectionStatusCallback?.('disconnected');
          }
        };

        // Fix 2: Unified Plan ontrack Fallback
        this.httpPc.ontrack = (event: RTCTrackEvent) => {
          console.log(`🔥 [HTTP WebRTC] Track received: ${event.track.kind}, streams count: ${event.streams?.length || 0}`);
          let streamToUse: MediaStream;
          if (event.streams && event.streams.length > 0 && event.streams[0]) {
            streamToUse = event.streams[0];
          } else {
            streamToUse = new MediaStream([event.track]);
          }
          this.onConnectionStatusCallback?.('connected');
          onStream(streamToUse);
        };

        this.httpPc.onicecandidate = (event) => {
          if (event.candidate) {
            fetch(`/api/signal/room/${cleanCode}/candidate`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                candidate: event.candidate.candidate,
                sdpMid: event.candidate.sdpMid,
                sdpMLineIndex: event.candidate.sdpMLineIndex,
                sender: 'parent',
              }),
            }).catch(() => {});
          }
        };

        // Timing Rule: setRemoteDescription BEFORE adding candidates!
        await this.httpPc.setRemoteDescription(new RTCSessionDescription(offerData));
        this.isHttpRemoteDescSet = true;

        const answer = await this.httpPc.createAnswer();
        await this.httpPc.setLocalDescription(answer);

        await fetch(`/api/signal/room/${cleanCode}/answer`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ sdp: answer.sdp, type: answer.type }),
        });

        this.startListeningToCandidates(cleanCode, 'parent');
        return true;
      } catch (err) {
        console.warn('HTTP Parent Watch attempt failed:', err);
        return false;
      }
    };

    const connected = await tryConnect();
    if (!connected) {
      // Poll until child offer arrives
      this.httpPollTimer = setInterval(async () => {
        if (this.httpPc) {
          clearInterval(this.httpPollTimer);
          return;
        }
        const ok = await tryConnect();
        if (ok) {
          clearInterval(this.httpPollTimer);
        }
      }, 2000);
    }
  }

  private startListeningToCandidates(roomCode: string, forRole: 'kid' | 'parent') {
    this.httpCandidateTimer = setInterval(async () => {
      if (!this.httpPc) return;
      try {
        const res = await fetch(`/api/signal/room/${roomCode}/candidates?for=${forRole}&since=${this.lastCandidateTs}`);
        if (res.ok) {
          const data = await res.json();
          if (data?.candidates && Array.isArray(data.candidates)) {
            for (const item of data.candidates) {
              if (item.timestamp > this.lastCandidateTs) {
                this.lastCandidateTs = item.timestamp;
              }
              if (item.candidate) {
                const candidate = new RTCIceCandidate({
                  candidate: item.candidate,
                  sdpMid: item.sdpMid,
                  sdpMLineIndex: item.sdpMLineIndex,
                });
                if (this.isHttpRemoteDescSet) {
                  await this.httpPc.addIceCandidate(candidate).catch(() => {});
                } else {
                  this.queuedCandidates.push(candidate);
                }
              }
            }
          }
        }
      } catch {}
    }, 1500);
  }

  stopHttpSignaling() {
    clearInterval(this.httpPollTimer);
    clearInterval(this.httpCandidateTimer);
    this.httpPollTimer = null;
    this.httpCandidateTimer = null;
    this.isHttpRemoteDescSet = false;
    this.queuedCandidates = [];
    this.lastCandidateTs = 0;
    if (this.httpPc) {
      try {
        this.httpPc.close();
      } catch {}
      this.httpPc = null;
    }
  }

  cleanup() {
    this.stopHttpSignaling();
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
