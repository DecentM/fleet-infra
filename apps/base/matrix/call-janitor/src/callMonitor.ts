/**
 * Call state monitoring and participant management
 */

import { MatrixClient } from 'matrix-bot-sdk';
import { RoomServiceClient } from 'livekit-server-sdk';
import {
  AppConfig,
  RoomCallState,
  CallMemberEventContent,
  CallMembership,
  KickResult,
} from './types';

/**
 * Matrix state event structure
 */
interface StateEvent {
  type: string;
  state_key: string;
  sender: string;
  content: unknown;
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
   */
  public async handleCallMemberEvent(
    roomId: string,
    stateEvent: StateEvent
  ): Promise<void> {
    const senderId = stateEvent.sender;

    // Ignore our own events
    if (senderId === this.botUserId) {
      return;
    }

    this.log(`Processing m.call.member event in ${roomId} from ${senderId}`);

    // Extract active participants from the room
    const participants = await this.extractActiveParticipants(roomId);

    this.log(`Room ${roomId} has ${participants.size} active participant(s): ${[...participants].join(', ')}`);

    // Update or create room call state
    let callState = this.activeCalls.get(roomId);

    if (participants.size === 0) {
      // No active participants, clean up state
      this.clearTimer(roomId);
      this.activeCalls.delete(roomId);
      this.log(`Room ${roomId}: No participants, cleared state`);
      return;
    }

    if (!callState) {
      callState = {
        participants,
        roomId,
      };
      this.activeCalls.set(roomId, callState);
    } else {
      callState.participants = participants;
    }

    // Check if user is alone
    if (participants.size === 1) {
      const loneUser = [...participants][0];

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
      // Multiple participants or none, clear any existing timer
      if (callState.aloneSince) {
        this.log(`Room ${roomId}: User no longer alone, clearing timer`);
      }
      this.clearTimer(roomId);
      callState.aloneSince = undefined;
    }
  }

  /**
   * Extracts currently active participants from room state
   */
  private async extractActiveParticipants(roomId: string): Promise<Set<string>> {
    const participants = new Set<string>();

    try {
      // Get all m.call.member state events for this room
      const stateEvents = await this.client.getRoomState(roomId);
      const now = Date.now();

      for (const event of stateEvents) {
        if (event.type !== 'm.call.member') continue;

        const userId = event.state_key;
        const content = event.content as CallMemberEventContent;

        // Skip bot's own membership
        if (userId === this.botUserId) continue;

        // Check if user has active memberships
        const memberships = content.memberships ||
          (content.membership ? [content.membership] : []);

        for (const membership of memberships) {
          if (this.isMembershipActive(membership, now)) {
            participants.add(userId);
            break;
          }
        }
      }
    } catch (error) {
      this.log(`Error extracting participants from ${roomId}: ${error}`, 'error');
    }

    return participants;
  }

  /**
   * Checks if a call membership is currently active
   */
  private isMembershipActive(membership: CallMembership, now: number): boolean {
    // If no expiry, check for other indicators
    if (!membership.expires_ts) {
      // Membership exists with foci = likely active
      return Boolean(membership.foci && membership.foci.length > 0);
    }

    // Check if expiry is in the future
    return membership.expires_ts > now;
  }

  /**
   * Handles the timeout when a user has been alone for too long
   */
  private async handleAloneTimeout(roomId: string, userId: string): Promise<void> {
    this.log(`Room ${roomId}: Timeout triggered for user ${userId}`);

    // Double-check state to prevent race conditions
    const currentParticipants = await this.extractActiveParticipants(roomId);

    if (currentParticipants.size !== 1 || !currentParticipants.has(userId)) {
      this.log(`Room ${roomId}: State changed, aborting kick (current participants: ${currentParticipants.size})`);
      this.clearTimer(roomId);
      const callState = this.activeCalls.get(roomId);
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
