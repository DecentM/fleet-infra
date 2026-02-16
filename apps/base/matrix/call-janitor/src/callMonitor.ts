/**
 * Call state monitoring and participant management
 */

import { MatrixClient } from 'matrix-bot-sdk';
import { RoomServiceClient } from 'livekit-server-sdk';
import {
  AppConfig,
  RoomCallState,
  CallMemberEventContent,
  KickResult,
} from './types';

/**
 * Matrix state event structure for m.call.member events
 */
interface CallMemberStateEvent {
  type: string;
  state_key: string;
  sender: string;
  content: CallMemberEventContent;
}

/**
 * Manages call state tracking and automatic cleanup of lonely participants
 */
export class CallMonitor {
  private readonly client: MatrixClient;
  private readonly livekitClient: RoomServiceClient;
  private readonly config: AppConfig;
  private readonly botUserId: string;

  /** Map of room ID to call state */
  private readonly activeCalls: Map<string, RoomCallState> = new Map();

  constructor(
    client: MatrixClient,
    livekitClient: RoomServiceClient,
    config: AppConfig,
    botUserId: string
  ) {
    this.client = client;
    this.livekitClient = livekitClient;
    this.config = config;
    this.botUserId = botUserId;
  }

  /**
   * Processes an m.call.member state event
   * Extracts user ID from state_key and determines join/leave from content
   */
  public async handleCallMemberEvent(
    roomId: string,
    stateEvent: CallMemberStateEvent
  ): Promise<void> {
    // Extract user ID from state_key format: _@user:domain_DEVICEID_m.call
    const userId = this.extractUserIdFromStateKey(stateEvent.state_key);

    if (!userId) {
      this.log(`Could not extract user ID from state_key: ${stateEvent.state_key}`, 'warn');
      return;
    }

    // Ignore our own events
    if (userId === this.botUserId) {
      return;
    }

    // Determine if user is joining or leaving based on m.calls content
    const isJoining = this.isUserJoiningCall(stateEvent.content);

    this.log(`Processing m.call.member event in ${roomId} for ${userId}: ${isJoining ? 'JOIN' : 'LEAVE'}`);

    // Get or create room call state
    let callState = this.activeCalls.get(roomId);

    if (!callState) {
      callState = {
        participants: new Set<string>(),
        roomId,
      };
      this.activeCalls.set(roomId, callState);
    }

    // Update participant set based on join/leave
    if (isJoining) {
      callState.participants.add(userId);
    } else {
      callState.participants.delete(userId);
    }

    this.log(`Room ${roomId} has ${callState.participants.size} active participant(s): ${[...callState.participants].join(', ')}`);

    // Clean up if no participants remain
    if (callState.participants.size === 0) {
      this.clearTimer(roomId);
      this.activeCalls.delete(roomId);
      this.log(`Room ${roomId}: No participants, cleared state`);
      return;
    }

    // Check if user is alone
    if (callState.participants.size === 1) {
      const loneUser = [...callState.participants][0];

      if (!callState.aloneSince) {
        // User just became alone, start timer
        callState.aloneSince = Date.now();
        this.log(`Room ${roomId}: User ${loneUser} is now alone, starting ${this.config.aloneTimeoutMs}ms timer`);

        this.clearTimer(roomId);
        callState.timer = setTimeout(
          () => this.handleAloneTimeout(roomId, loneUser),
          this.config.aloneTimeoutMs
        );
      }
    } else {
      // Multiple participants, clear any existing timer
      if (callState.aloneSince) {
        this.log(`Room ${roomId}: User no longer alone, clearing timer`);
      }
      this.clearTimer(roomId);
      callState.aloneSince = undefined;
    }
  }

  /**
   * Extracts the Matrix user ID from the state_key
   * State key format: _@user:domain_DEVICEID_m.call
   */
  private extractUserIdFromStateKey(stateKey: string): string | null {
    // Format: _@user:domain_DEVICEID_m.call
    // We need to extract @user:domain between the first two underscores
    const match = stateKey.match(/^_(@[^_]+:[^_]+)_/);
    return match ? match[1] : null;
  }

  /**
   * Determines if the user is joining a call based on event content
   * Join: content["m.calls"] exists and has items
   * Leave: content["m.calls"] is empty, missing, or content is {}
   */
  private isUserJoiningCall(content: CallMemberEventContent): boolean {
    // Empty object means leaving
    if (!content || Object.keys(content).length === 0) {
      return false;
    }

    const calls = content["m.calls"];

    // Missing or empty array means leaving
    if (!calls || !Array.isArray(calls) || calls.length === 0) {
      return false;
    }

    // Has calls = joining
    return true;
  }

  /**
   * Handles the timeout when a user has been alone for too long
   */
  private async handleAloneTimeout(roomId: string, userId: string): Promise<void> {
    this.log(`Room ${roomId}: Timeout triggered for user ${userId}`);

    // Verify state from our tracked participants
    const callState = this.activeCalls.get(roomId);

    if (!callState || callState.participants.size !== 1 || !callState.participants.has(userId)) {
      this.log(`Room ${roomId}: State changed, aborting kick (current participants: ${callState?.participants.size ?? 0})`);
      this.clearTimer(roomId);
      if (callState) {
        callState.aloneSince = undefined;
      }
      return;
    }

    // Proceed with kick
    const result = await this.kickFromCall(roomId, userId);

    if (result.success) {
      // Send DM explaining the removal
      await this.sendRemovalDM(userId);
    }

    // Clean up state
    this.clearTimer(roomId);
    this.activeCalls.delete(roomId);
  }

  /**
   * Kicks a user from the LiveKit call
   */
  private async kickFromCall(roomId: string, userId: string): Promise<KickResult> {
    const timestamp = new Date();

    try {
      // LiveKit uses a room name that typically maps to the Matrix room
      // The participant identity is usually the Matrix user ID
      const livekitRoomName = this.getLivekitRoomName(roomId);

      this.log(`Removing participant ${userId} from LiveKit room ${livekitRoomName}`);

      await this.livekitClient.removeParticipant(livekitRoomName, userId);

      this.log(`[KICK] Successfully removed ${userId} from ${roomId} at ${timestamp.toISOString()}`);

      return {
        success: true,
        userId,
        roomId,
        timestamp,
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.log(`[KICK FAILED] Error removing ${userId} from ${roomId}: ${errorMessage}`, 'error');

      return {
        success: false,
        userId,
        roomId,
        error: errorMessage,
        timestamp,
      };
    }
  }

  /**
   * Converts Matrix room ID to LiveKit room name
   * Element Call typically uses the room ID or an alias
   */
  private getLivekitRoomName(roomId: string): string {
    // Element Call uses the Matrix room ID as the LiveKit room name
    // Some implementations may use a hash or alias - adjust as needed
    return roomId;
  }

  /**
   * Sends a direct message to the user explaining the removal
   */
  private async sendRemovalDM(userId: string): Promise<void> {
    try {
      this.log(`Sending removal DM to ${userId}`);

      // Create or find existing DM room
      const dmRoomId = await this.getOrCreateDMRoom(userId);

      await this.client.sendMessage(dmRoomId, {
        msgtype: 'm.text',
        body: 'You were removed from the call to save bandwidth as you were alone for more than 1 minute.',
      });

      this.log(`Successfully sent removal DM to ${userId}`);
    } catch (error) {
      // Log but don't crash - DM failure is not critical
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.log(`Failed to send DM to ${userId}: ${errorMessage}`, 'warn');
    }
  }

  /**
   * Gets an existing DM room with the user or creates a new one
   */
  private async getOrCreateDMRoom(userId: string): Promise<string> {
    try {
      // Check for existing DM rooms
      const joinedRooms = await this.client.getJoinedRooms();

      for (const roomId of joinedRooms) {
        try {
          const members = await this.client.getJoinedRoomMembers(roomId);

          // A DM room has exactly 2 members: the bot and the user
          if (members.length === 2 && members.includes(userId)) {
            // Verify it's a direct room by checking if it's marked as such
            // or if it's small enough to be a DM
            return roomId;
          }
        } catch {
          // Skip rooms we can't query
          continue;
        }
      }
    } catch (error) {
      this.log(`Error searching for existing DM room: ${error}`, 'warn');
    }

    // Create new DM room
    this.log(`Creating new DM room with ${userId}`);

    const roomId = await this.client.createRoom({
      preset: 'trusted_private_chat',
      is_direct: true,
      invite: [userId],
    });

    return roomId;
  }

  /**
   * Clears any active timer for a room
   */
  private clearTimer(roomId: string): void {
    const callState = this.activeCalls.get(roomId);
    if (callState?.timer) {
      clearTimeout(callState.timer);
      callState.timer = undefined;
    }
  }

  /**
   * Logs a message with timestamp
   */
  private log(message: string, level: 'info' | 'warn' | 'error' = 'info'): void {
    const timestamp = new Date().toISOString();
    const prefix = `[${timestamp}] [CallMonitor]`;

    switch (level) {
      case 'error':
        console.error(`${prefix} ${message}`);
        break;
      case 'warn':
        console.warn(`${prefix} ${message}`);
        break;
      default:
        console.log(`${prefix} ${message}`);
    }
  }

  /**
   * Returns the current state for debugging/monitoring
   */
  public getActiveCallsCount(): number {
    return this.activeCalls.size;
  }
}
