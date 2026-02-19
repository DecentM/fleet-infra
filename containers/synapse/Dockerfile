# Custom Synapse image with anti-spam modules
# Based on the official matrixdotorg/synapse image
FROM matrixdotorg/synapse:v1.126.0

# Install anti-spam modules
# synapse-http-antispam: HTTP-based spam checking (for Meowlnir integration)
# synapse-spamcheck-badlist: Database-backed URL/hash blocklists
RUN pip install --no-cache-dir \
    'synapse-http-antispam>=0.5.0' \
    'git+https://github.com/matrix-org/synapse-spamcheck-badlist#egg=synapse-spamcheck-badlist'
