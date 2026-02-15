/**
 * Environment configuration for call-janitor AppService bot
 */

import { AppConfig } from './types';

/**
 * Loads and validates configuration from environment variables
 * @throws Error if required environment variables are missing
 */
export const loadConfig = (): AppConfig => {
  const asToken = process.env.AS_TOKEN;
  const hsToken = process.env.HS_TOKEN;
  const livekitUrl = process.env.LIVEKIT_URL;
  const livekitApiKey = process.env.LIVEKIT_API_KEY;
  const livekitApiSecret = process.env.LIVEKIT_API_SECRET;

  // Validate required environment variables
  const missing: string[] = [];
  if (!asToken) missing.push('AS_TOKEN');
  if (!hsToken) missing.push('HS_TOKEN');
  if (!livekitUrl) missing.push('LIVEKIT_URL');
  if (!livekitApiKey) missing.push('LIVEKIT_API_KEY');
  if (!livekitApiSecret) missing.push('LIVEKIT_API_SECRET');

  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }

  // Parse timeout with validation
  const aloneTimeoutMs = parseInt(process.env.ALONE_TIMEOUT_MS || '60000', 10);
  if (isNaN(aloneTimeoutMs) || aloneTimeoutMs < 1000) {
    throw new Error('ALONE_TIMEOUT_MS must be a number >= 1000');
  }

  // Parse port with validation
  const port = parseInt(process.env.PORT || '8080', 10);
  if (isNaN(port) || port < 1 || port > 65535) {
    throw new Error('PORT must be a valid port number (1-65535)');
  }

  return {
    homeserverUrl: process.env.HOMESERVER_URL || 'http://synapse:8008',
    asToken: asToken!,
    hsToken: hsToken!,
    livekitUrl: livekitUrl!,
    livekitApiKey: livekitApiKey!,
    livekitApiSecret: livekitApiSecret!,
    aloneTimeoutMs,
    dataDir: process.env.DATA_DIR || '/data',
    bindAddress: process.env.BIND_ADDRESS || '0.0.0.0',
    port,
  };
};

/**
 * Logs configuration (without sensitive values)
 */
export const logConfig = (config: AppConfig): void => {
  console.log(`[${new Date().toISOString()}] Configuration loaded:`);
  console.log(`  Homeserver URL: ${config.homeserverUrl}`);
  console.log(`  LiveKit URL: ${config.livekitUrl}`);
  console.log(`  Alone timeout: ${config.aloneTimeoutMs}ms`);
  console.log(`  Data directory: ${config.dataDir}`);
  console.log(`  Bind address: ${config.bindAddress}:${config.port}`);
  console.log(`  AS token: [REDACTED]`);
  console.log(`  HS token: [REDACTED]`);
  console.log(`  LiveKit API key: ${config.livekitApiKey.substring(0, 4)}...`);
};
