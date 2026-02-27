# Maubot with pre-installed plugins
# Stage 1: Build plugin .mbp files

FROM dock.mau.dev/maubot/maubot:v0.6.0 AS builder

USER root
RUN apk add --no-cache git
RUN pip install --no-cache-dir --break-system-packages 'maubot[cli]'

# Build CommunityBot plugin
WORKDIR /build/communitybot
RUN git clone --depth 1 https://github.com/williamkray/maubot-communitybot.git .
RUN python3 -m maubot.cli build -o /build/communitybot.mbp

# Stage 2: Maubot image with plugins pre-installed

FROM dock.mau.dev/maubot/maubot:v0.6.0

COPY --from=builder --chown=1337:1337 /build/communitybot.mbp /data/plugins/communitybot.mbp
