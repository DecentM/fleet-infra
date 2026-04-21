# NutriTrack — production app image
# https://github.com/sderosiaux/nutritrack
#
# To update: change NUTRITRACK_REF to the desired commit SHA or tag.
# The upstream repo has no releases/tags yet, so we track main.
ARG NUTRITRACK_REF=main

# ── Stage 1: clone + generate lockfile ────────────────────────────────────
FROM alpine/git:2.47.2 AS source
ARG NUTRITRACK_REF
RUN apk add --no-cache nodejs npm \
 && npm install -g pnpm
RUN git clone --depth 1 https://github.com/sderosiaux/nutritrack.git /src
WORKDIR /src
RUN git fetch --depth 1 origin ${NUTRITRACK_REF} && git checkout ${NUTRITRACK_REF}
# Generate lockfile — upstream repo does not commit pnpm-lock.yaml
RUN pnpm install --lockfile-only

# ── Stage 2: deps ──────────────────────────────────────────────────────────
FROM node:22-alpine AS deps
RUN apk add --no-cache libc6-compat unzip
RUN npm install -g pnpm
WORKDIR /app
COPY --from=source /src/package.json /src/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# ── Stage 3: builder ───────────────────────────────────────────────────────
FROM node:22-alpine AS builder
RUN npm install -g pnpm
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=source /src .
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm build

# ── Stage 4: runner ────────────────────────────────────────────────────────
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs \
 && adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

RUN chown -R nextjs:nodejs /app
USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]
