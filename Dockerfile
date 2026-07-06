FROM php:8.2-cli

# Build-time args for private GitHub repos
ARG GITHUB_TOKEN=""
# PMMP version - set to "latest" to auto-detect
ARG PMMP_VERSION="latest"

# Install system deps + PHP extensions PMMP needs
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    unzip \
    curl \
    jq \
    libyaml-dev \
    libzip-dev \
    && docker-php-ext-install -j$(nproc) \
        bcmath \
        gmp \
        sockets \
        yaml \
        zip \
    && rm -rf /var/lib/apt/lists/*

# PocketMine-MP setup
ENV PMMP_DIR=/server
WORKDIR ${PMMP_DIR}

# Download PocketMine-MP phar
RUN if [ "${PMMP_VERSION}" = "latest" ]; then \
        PMMP_URL=$(curl -s https://api.github.com/repos/pmmp/PocketMine-MP/releases/latest \
            | jq -r '.assets[] | select(.name | endswith(".phar")) | .browser_download_url'); \
    else \
        PMMP_URL="https://github.com/pmmp/PocketMine-MP/releases/download/${PMMP_VERSION}/PocketMine-MP.phar"; \
    fi \
    && echo "Downloading PMMP from: ${PMMP_URL}" \
    && curl -fSL -o PocketMine-MP.phar "${PMMP_URL}" \
    && chmod +x PocketMine-MP.phar

# Create directory structure
RUN mkdir -p plugins virions plugin_data worlds resource_packs

# --- Devirion (folder-based plugin loader) ---
# Download latest Devirion phar from poggit
RUN DEVIRION_URL=$(curl -s https://poggit.pmmp.io/releases.json?name=Devirion \
        | jq -r '.[0].artifact_url // empty') \
    && if [ -n "${DEVIRION_URL}" ]; then \
        echo "Downloading Devirion from: ${DEVIRION_URL}" \
        && curl -fSL -o plugins/Devirion.phar "${DEVIRION_URL}"; \
    else \
        echo "WARN: Devirion not found on poggit, trying GitHub..." \
        && curl -fSL -o plugins/Devirion.phar \
            "https://github.com/pmmp/Devirion/releases/latest/download/Devirion.phar"; \
    fi

# --- Commando virion ---
# Clone CortexPE/Commando as virion (used by Devirion to inject into folder plugins)
RUN git clone --depth 1 https://github.com/CortexPE/Commando.git /tmp/commando \
    && mkdir -p virions/Commando \
    && cp -r /tmp/commando/src/Commando virions/Commando/src 2>/dev/null || true \
    && cp /tmp/commando/virion.yml virions/Commando/ 2>/dev/null || true \
    && rm -rf /tmp/commando

# --- SaruMC private plugins ---
# Script handles download from GitHub releases using token
COPY install-sarumc-plugins.sh /tmp/install-sarumc-plugins.sh
RUN chmod +x /tmp/install-sarumc-plugins.sh \
    && /tmp/install-sarumc-plugins.sh "${PMMP_DIR}/plugins" \
    && rm /tmp/install-sarumc-plugins.sh

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Snapshot baked-in plugins for first-run volume initialization
RUN cp -r plugins /baked-plugins \
    && cp -r virions /baked-virions

# Default server properties
RUN echo "enable-query=on" > server.properties \
    && echo "query-port=19132" >> server.properties \
    && echo "motd=SaruMC Server" >> server.properties \
    && echo "server-port=19132" >> server.properties \
    && echo "max-players=20" >> server.properties

# PocketMine-MP listens on 19132 UDP
EXPOSE 19132/udp

VOLUME ["/server/plugins", "/server/plugin_data", "/server/worlds", "/server/resource_packs"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--no-wizard", "--disable-readline"]
