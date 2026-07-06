# SaruMC Docker Base Image

PocketMine-MP Docker image with:
- **Devirion** — folder-based plugin loader
- **Commando** — virion command framework (CortexPE/Commando)
- **SaruMC/core** — private core plugin
- **SaruMC/horus** — private horus plugin

## Pull

```bash
docker pull ghcr.io/sarumc/pocketmine-base:latest
```

## Run (base only)

```bash
docker run -d \
  -p 19132:19132/udp \
  -v pmmp_worlds:/server/worlds \
  -v pmmp_data:/server/plugin_data \
  --name survival ghcr.io/sarumc/pocketmine-base:latest
```

## Run with additional plugins

Pass extra plugins at runtime. Same image, different games:

### Via `--add-plugin` flag

```bash
# BedWars server
docker run -d -p 19132:19132/udp --name bedwars \
  ghcr.io/sarumc/pocketmine-base:latest \
  --add-plugin "SaruMC/BedWars"

# SkyBlock server
docker run -d -p 19133:19132/udp --name skyblock \
  ghcr.io/sarumc/pocketmine-base:latest \
  --add-plugin "SaruMC/SkyBlock"
```

### Via `ADDITIONAL_PLUGINS` env (comma-separated)

```bash
docker run -d -p 19132:19132/udp \
  -e ADDITIONAL_PLUGINS="SaruMC/KitPvP,https://example.com/custom-plugin.phar" \
  --name kitpvp ghcr.io/sarumc/pocketmine-base:latest
```

### Supported plugin sources

| Format | Example |
|--------|---------|
| GitHub repo shorthand | `SaruMC/BedWars` |
| Direct .phar URL | `https://poggit.pmmp.io/r/12345/plugin.phar` |
| Archive URL (.zip/.tar.gz) | `https://github.com/.../releases/.../plugin.zip` |
| Any download URL | `https://my-cdn.com/plugin-file` |

### PMMP args passthrough

Anything after `--` or unknown flags pass directly to PocketMine-MP:

```bash
docker run ghcr.io/sarumc/pocketmine-base:latest \
  --add-plugin "SaruMC/BedWars" \
  --no-wizard --disable-readline --debug.level=2
```

## Build locally

```bash
docker build \
  --build-arg GITHUB_TOKEN=ghp_xxxxxxxx \
  --build-arg PMMP_VERSION=latest \
  -t pocketmine-base .
```

Without `GITHUB_TOKEN`, SaruMC private plugins are skipped at build time
(you can still inject them at runtime).

## Structure

```
/server/
├── PocketMine-MP.phar      # PMMP binary
├── plugins/
│   ├── Devirion.phar        # Folder plugin loader
│   ├── SaruMC-core/         # Core plugin (folder)
│   └── SaruMC-horus/        # Horus plugin (folder)
├── virions/
│   └── Commando/            # Commando virion
├── worlds/                  # World data (volume)
└── plugin_data/             # Plugin configs (volume)
```
