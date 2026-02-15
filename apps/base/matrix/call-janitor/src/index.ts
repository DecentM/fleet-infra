/**
 * Call Janitor - Matrix bot for cleaning up lonely Element Call sessions
 * 
 * Monitors m.call.member state events and kicks users who have been
 * alone in a call for more than 1 minute to save bandwidth.
 */

import {
  MatrixClient,
  AutojoinRoomsMixin,
  SimpleFsStorageProvider,
} from 'matrix-bot-sdk';
import { RoomServiceClient } from 'livekit-server-sdk';
import { loadConfig, logConfig } from './config';
import { CallMonitor } from './callMonitor';
import * as fs from 'fs';
import * as path from 'path';

const log = (message: string, level: 'info' | 'warn' | 'error' = 'info'): void => {
  const timestamp = new Date().toISOString();
  const prefix = `[${timestamp}] [Main]`;
  
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
};

/**
 * Validates connectivity to the LiveKit server
 */
const validateLivekitConnectivity = async (
  livekitClient: RoomServiceClient
): Promise<void> => {
  log('Validating LiveKit connectivity...');
  
  try {
    // List rooms to verify connectivity (returns empty array if no rooms)
    const rooms = await livekitClient.listRooms();
    log(`LiveKit connectivity OK - ${rooms.length} active room(s)`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Failed to connect to LiveKit: ${message}`);
  }
};

/**
 * Main entry point
 */
const main = async (): Promise<void> => {
  log('Starting Call Janitor bot...');
  
  // Load configuration
  const config = loadConfig();
  logConfig(config);
  
  // Ensure data directory exists
  if (!fs.existsSync(config.dataDir)) {
    log(`Creating data directory: ${config.dataDir}`);
    fs.mkdirSync(config.dataDir, { recursive: true });
  }
  
  // Initialize storage provider for bot state
  const storageProvider = new SimpleFsStorageProvider(
    path.join(config.dataDir, 'bot-storage.json')
  );
  
  // Initialize LiveKit client
  log('Initializing LiveKit client...');
  const livekitClient = new RoomServiceClient(
    config.livekitUrl,
    config.livekitApiKey,
    config.livekitApiSecret
  );
  
  // Validate LiveKit connectivity before proceeding
  await validateLivekitConnectivity(livekitClient);
  
  // Initialize Matrix client
  log('Initializing Matrix client...');
  const matrixClient = new MatrixClient(
    config.homeserverUrl,
    config.accessToken,
    storageProvider
  );
  
  // Enable auto-joining rooms when invited
  AutojoinRoomsMixin.setupOnClient(matrixClient);
  
  // Get bot's user ID
  const botUserId = await matrixClient.getUserId();
  log(`Bot user ID: ${botUserId}`);
  
  // Initialize call monitor
  const callMonitor = new CallMonitor(
    matrixClient,
    livekitClient,
    config,
    botUserId
  );
  
  // Set up state event handler for m.call.member events
  matrixClient.on('room.event', async (roomId: string, event: any) => {
    // Only process m.call.member state events
    if (event.type !== 'm.call.member' || !event.state_key) {
      return;
    }
    
    try {
      await callMonitor.handleCallMemberEvent(roomId, event);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      log(`Error handling call member event: ${message}`, 'error');
    }
  });
  
  // Start the client
  log('Starting Matrix client sync...');
  await matrixClient.start();
  
  log('Call Janitor bot is now running');
  log(`Monitoring for lonely callers (timeout: ${config.aloneTimeoutMs}ms)`);
  
  // Handle graceful shutdown
  const shutdown = async (): Promise<void> => {
    log('Shutting down...');
    matrixClient.stop();
    process.exit(0);
  };
  
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
};

// Run the bot
main().catch((error) => {
  log(`Fatal error: ${error.message || error}`, 'error');
  console.error(error);
  process.exit(1);
});
