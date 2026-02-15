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
  /** Array of active call memberships */
  memberships?: CallMembership[];
  /** Legacy: single membership (deprecated but may still appear) */
  membership?: CallMembership;
}

/**
 * Individual call membership within m.call.member state
 */
export interface CallMembership {
  /** Call ID this membership is for */
  call_id?: string;
  /** Application ID (e.g., "m.call") */
  application?: string;
  /** Device ID of the participant */
  device_id?: string;
  /** Scope of the call (room-wide, etc.) */
  scope?: string;
  /** Whether the membership is active */
  expires_ts?: number;
  /** Focus information for the call */
  foci?: CallFocus[];
}

/**
 * Focus configuration for distributed calls (LiveKit SFU)
 */
export interface CallFocus {
  /** Type of focus (e.g., "livekit") */
  type: string;
  /** LiveKit room alias */
  livekit_alias?: string;
  /** LiveKit service URL */
  livekit_service_url?: string;
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
