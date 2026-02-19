# Custom Synapse image with anti-spam modules
# Based on the official matrixdotorg/synapse image
FROM matrixdotorg/synapse:v1.147.1

RUN apt-get update && apt-get -y install git

# Install anti-spam modules
# synapse-http-antispam: HTTP-based spam checking (for Meowlnir integration)
# synapse-spamcheck-badlist: Database-backed URL/hash blocklists
RUN pip install --no-cache-dir \
    'synapse-http-antispam==0.5.0' \
    'synapse-spamcheck-badlist @ git+https://github.com/matrix-org/synapse-spamcheck-badlist@v0.3.4'
