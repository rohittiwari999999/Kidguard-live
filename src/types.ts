export type DeviceRole = 'parent' | 'child' | 'flutter-guide';

export type Language = 'hi' | 'en';

export interface ChildProfile {
  name: string;
  avatar: string;
  roomCode: string;
  pin: string;
}

export interface CapturedSnapshot {
  id: string;
  timestamp: number;
  dataUrl: string;
  appName?: string;
  note?: string;
}

export interface ActivityEvent {
  id: string;
  timestamp: number;
  type: 'connect' | 'disconnect' | 'screenshot' | 'alert_sent' | 'mode_change' | 'app_switch';
  description: string;
}

export interface BuzzerAlert {
  id: string;
  timestamp: number;
  message: string;
  sender: 'parent';
  acknowledged?: boolean;
}
