/**
 * Call Janitor - Matrix AppService bot for cleaning up lonely Element Call sessions
 *
 * Monitors call.member state events (both stable m.call.member and
 * unstable org.matrix.msc3401.call.member) and kicks users who have been
 * alone in a call for more than 1 minute to save bandwidth.
 *
 * Runs as an Application Service, receiving events pushed from Synapse
 * via HTTP on port 8080.
 */

import {
  Appservice,
  AutojoinRoomsMixin,
  IAppserviceRegistration,
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
 * Creates the AppService registration object from config
 */
const createRegistration = (
  asToken: string,
  hsToken: string
): IAppserviceRegistration => {
  return {
    id: 'call-janitor',
    as_token: asToken,
    hs_token: hsToken,
    sender_localpart: 'call-janitor',
    namespaces: {
      users: [
        {
          exclusive: true,
          regex: '@call-janitor:.*',
        },
      ],
      aliases: [],
      rooms: [
        {
          exclusive: false,
          regex: '!.*',
        },
      ],
    },
    rate_limited: false,
    url: '', // Not used when creating Appservice instance
  };
};

/**
 * Main entry point
 */
const main = async (): Promise<void> => {
  log('Starting Call Janitor AppService bot...');

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

  // Create AppService registration
  const registration = createRegistration(config.asToken, config.hsToken);

  // Initialize AppService
  log(`Initializing AppService on ${config.bindAddress}:${config.port}...`);
  const appservice = new Appservice({
    registration,
    homeserverUrl: config.homeserverUrl,
    homeserverName: '', // Will be extracted from events
    port: config.port,
    bindAddress: config.bindAddress,
    storage: storageProvider,
  });

  // Debug: Log all incoming HTTP requests to the AppService
  appservice.expressAppInstance.use((req, _res, next) => {
    log(`[DEBUG] HTTP ${req.method} ${req.path}`);
    next();
  });

  // Get bot's user ID (uses sender_localpart from registration)
  const botUserId = appservice.botUserId;
  log(`Bot user ID: ${botUserId}`);

  // Get bot's Matrix client for API calls
  const botClient = appservice.botClient;

  // Set up auto-join for room invitations
  AutojoinRoomsMixin.setupOnClient(botClient);
  log('AutojoinRoomsMixin configured - bot will auto-accept invitations');

  // Initialize call monitor
  const callMonitor = new CallMonitor(
    botClient,
    livekitClient,
    config,
    botUserId
  );

  // Set up event handler for all room events
  // AppServices receive ALL events, so we filter for call.member events
  appservice.on('room.event', async (roomId: string, event: any) => {
    // Debug: Log all events received by the AppService
    log(`[DEBUG] Received event type=${event.type} room=${roomId} state_key=${event.state_key ?? 'N/A'}`);

    // Only process call.member state events (both stable and unstable types)
    // - m.call.member (stable/future)
    // - org.matrix.msc3401.call.member (unstable/current)
    if (!event.type.endsWith('.call.member') || !event.state_key) {
      log(`[DEBUG] Skipping event (not a call.member state event)`);
      return;
    }

    try {
      await callMonitor.handleCallMemberEvent(roomId, event);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      log(`Error handling call member event: ${message}`, 'error');
    }
  });

  // Start the AppService HTTP server
  log('Starting AppService HTTP server...');
  await appservice.begin();

  log('Call Janitor AppService bot is now running');
  log(`Listening on ${config.bindAddress}:${config.port}`);
  log(`Monitoring for lonely callers (timeout: ${config.aloneTimeoutMs}ms)`);

  // Handle graceful shutdown
  const shutdown = async (): Promise<void> => {
    log('Shutting down...');
    await appservice.stop();
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
