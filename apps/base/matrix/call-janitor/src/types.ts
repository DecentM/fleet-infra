/**
 * TypeScript interfaces for the call-janitor Matrix bot
 */

/**
 * Represents the state of an active call in a room
 */
export interface RoomCallState {
  /** Set of Matrix user IDs currently in the call */
  participants: Set<string>;
  /** Timestamp when the user became alone (undefined if not alone) */
  aloneSince?: number;
  /** Timer reference for the kick countdown */
  timer?: NodeJS.Timeout;
  /** The Matrix room ID */
  roomId: string;
}

/**
 * Parsed m.call.member state event content
 * Based on MSC3401 native group calls
 */
export interface CallMemberEventContent {
  /** Array of active calls the user is participating in */
  "m.calls"?: CallInfo[];
}

/**
 * Call information within m.call.member state
 */
export interface CallInfo {
  /** Call ID for this call */
  "m.call_id": string;
  /** Devices participating in this call */
  "m.devices"?: CallDevice[];
}

/**
 * Device information for a call participant
 */
export interface CallDevice {
  /** Device ID of the participant */
  device_id: string;
  /** Session ID for this device's connection */
  session_id: string;
  /** Media feeds from this device */
  feeds?: unknown[];
}

/**
 * Application configuration loaded from environment
 */
export interface AppConfig {
  homeserverUrl: string;
  asToken: string;
  hsToken: string;
  livekitUrl: string;
  livekitApiKey: string;
  livekitApiSecret: string;
  aloneTimeoutMs: number;
  dataDir: string;
  bindAddress: string;
  port: number;
}

/**
 * Kick action result for logging
 */
export interface KickResult {
  success: boolean;
  userId: string;
  roomId: string;
  error?: string;
  timestamp: Date;
}
