# Maubot standalone with CommunityBot plugin source

FROM dock.mau.dev/maubot/maubot:v0.6.0

USER root
RUN apk add --no-cache git

RUN git clone --depth 1 https://github.com/williamkray/maubot-communitybot.git /opt/maubot-plugin/

WORKDIR /opt/maubot-plugin/
