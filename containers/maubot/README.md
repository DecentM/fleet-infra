# Maubot with Plugins

Custom Maubot image with plugins pre-installed. Based on the official
`dock.mau.dev/maubot/maubot:v0.6.0` image with `.mbp` plugin files baked in.

## Included Plugins

- **CommunityBot** (`org.jobmachine.communitybot`) - Community management plugin
  ([source](https://github.com/williamkray/maubot-communitybot))

## Building

```bash
# From this directory
docker build -t ghcr.io/decentm/maubot:latest .

# Or from the repository root
docker build -t ghcr.io/decentm/maubot:latest -f containers/maubot/Dockerfile containers/maubot/
```

## Adding More Plugins

To add another plugin, add a build step in the builder stage and copy the
resulting `.mbp` file into `/data/plugins/` in the final stage:

```dockerfile
# In the builder stage
WORKDIR /build/my-plugin
RUN git clone --depth 1 https://github.com/example/maubot-my-plugin.git .
RUN python3 -m maubot.cli build -o /build/my-plugin.mbp

# In the final stage
COPY --from=builder --chown=1337:1337 /build/my-plugin.mbp /data/plugins/my-plugin.mbp
```

## CI/CD

This image is automatically built and pushed to `ghcr.io/decentm/maubot` by
the GitHub Actions workflow when changes are detected in this directory.
