ARG NODE_VERSION=24.13.1

# Build stage - compile TypeScript
FROM node:${NODE_VERSION}-slim AS builder

WORKDIR /app

# Enable corepack and activate pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Install dependencies first for better layer caching
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copy source and compile
COPY tsconfig.json ./
COPY src/ ./src/
RUN pnpm run build

# Production dependencies stage - separate for smaller final image
FROM node:${NODE_VERSION}-slim AS deps

WORKDIR /app

# Enable corepack and activate pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Install only production dependencies
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

# Runtime stage - minimal production image
FROM node:${NODE_VERSION}-slim AS runtime

WORKDIR /app

# Copy compiled code and production dependencies
COPY --from=builder /app/dist ./dist
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./

# Create data directory for bot storage
RUN mkdir -p /data

# Environment defaults
ENV NODE_ENV=production \
    DATA_DIR=/data \
    HOMESERVER_URL=http://synapse:8008 \
    ALONE_TIMEOUT_MS=60000

# Volume for persistent bot storage
VOLUME ["/data"]

# Health check - verify process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD pgrep -x node || exit 1

# Run the bot
CMD ["node", "dist/index.js"]
