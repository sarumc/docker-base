FROM ghcr.io/pmmp/pocketmine-mp:latest

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    jq git unzip curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/pocketmine

# --- Devirion (folder-based plugin loader) ---
# SaruMC/devirion (PM5-compatible fork) as primary source.
# Fall back to poggit if the release asset is unavailable.
RUN curl -fSL -o /tmp/Devirion.phar \
        "https://github.com/SaruMC/devirion/releases/latest/download/Devirion.phar" \
    || curl -fSL -o /tmp/Devirion.phar \
        "https://poggit.pmmp.io/get/Devirion"

# --- Commando virion ---
# RUN git clone --depth 1 https://github.com/CortexPE/Commando.git /tmp/commando \
#     && mkdir -p virions/Commando/src \
#     && cp -r /tmp/commando/src/CortexPE/Commando virions/Commando/src/ \
#     && cp /tmp/commando/virion.yml virions/Commando/ 2>/dev/null || true \
#     && rm -rf /tmp/commando

# --- Assemble baked plugins ---
# All built-in plugins go into /baked-plugins, then seeded to volume on first run.
COPY install-sarumc-plugins.sh /tmp/install-sarumc-plugins.sh
RUN mkdir -p /baked-plugins \
    && cp /tmp/Devirion.phar /baked-plugins/Devirion.phar \
    && chmod +x /tmp/install-sarumc-plugins.sh
RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN \
    /tmp/install-sarumc-plugins.sh /baked-plugins \
    && rm /tmp/install-sarumc-plugins.sh
RUN cp -r virions /baked-virions \
    && chown -R pocketmine:pocketmine /baked-virions /opt/pocketmine/virions

# Custom entrypoint wrapper
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER pocketmine
ENTRYPOINT ["/entrypoint.sh"]
CMD ["start-pocketmine"]
