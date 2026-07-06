# SaruMC Docker Base Image

Extends [`ghcr.io/pmmp/pocketmine-mp`](https://github.com/pmmp/PocketMine-MP/pkgs/container/pocketmine-mp) with:

- **Devirion** — folder-based plugin loader
- **Commando** — virion command framework (CortexPE/Commando)
- **SaruMC/core** — private core plugin
- **SaruMC/horus** — private horus plugin

## Pull

```bash
docker pull ghcr.io/sarumc/docker-base:latest
```

## Run (base only)

```bash
docker run -d \
  -p 19132:19132/udp \
  -v pmmp_data:/data \
  -v pmmp_plugins:/plugins \
  --name survival ghcr.io/sarumc/docker-base:latest
```

## Run with additional plugins

Same image, different games. Two ways:

### 1) Poggit plugins: `POCKETMINE_PLUGINS` env

Built-in from the official image. Space-separated, optional `:version`:

```bash
docker run -d -p 19132:19132/udp \
  -e POCKETMINE_PLUGINS="EconomyAPI:5.7.2 PurePerms PureChat:1.4.11" \
  --name survival ghcr.io/sarumc/docker-base:latest
```

### 2) GitHub / direct URL plugins: `ADDITIONAL_PLUGINS` env

Comma-separated. Supports GitHub repos (owner/repo), .phar URLs, archives:

```bash
# BedWars server — GitHub repo
docker run -d -p 19132:19132/udp \
  -e ADDITIONAL_PLUGINS="SaruMC/BedWars" \
  --name bedwars ghcr.io/sarumc/docker-base:latest

# KitPvP server — multiple plugins
docker run -d -p 19133:19132/udp \
  -e ADDITIONAL_PLUGINS="SaruMC/KitPvP,https://example.com/custom.phar" \
  --name kitpvp ghcr.io/sarumc/docker-base:latest
```

### 3) `--add-plugin` CLI flag

```bash
docker run -d -p 19132:19132/udp \
  --name skyblock ghcr.io/sarumc/docker-base:latest \
  --add-plugin "SaruMC/SkyBlock"
```

### Supported plugin sources

| Format | Example |
|--------|---------|
| GitHub repo shorthand | `SaruMC/BedWars` |
| Direct .phar URL | `https://poggit.pmmp.io/r/12345/plugin.phar` |
| Archive URL (.zip/.tar.gz) | `https://github.com/.../releases/.../plugin.zip` |
| Any download URL | `https://my-cdn.com/plugin-file` |

### PMMP args passthrough

Extra args after `--add-plugin` go to PocketMine-MP:

```bash
docker run ghcr.io/sarumc/docker-base:latest \
  --add-plugin "SaruMC/BedWars" \
  --debug.level=2
```

Or use `POCKETMINE_ARGS` env from the official image.

## Build locally

```bash
# Without token — skips SaruMC private plugins
docker build -t pocketmine-base .

# With token — includes SaruMC/core + SaruMC/horus
docker build \
  --secret id=github_token,env=GITHUB_TOKEN \
  -t pocketmine-base .
```

## Structure

```
/opt/pocketmine/
├── PocketMine-MP.phar      # PMMP binary (from official image)
├── virions/
│   └── Commando/            # Commando virion
├── start-pocketmine         # Official entry script
│
/plugins/                    # Volume — seeded on first run
│   ├── Devirion.phar        # Folder plugin loader
│   ├── SaruMC-core/         # Core plugin
│   └── SaruMC-horus/        # Horus plugin
│
/data/                       # Volume — server data, worlds, configs
```

## GitHub Actions

Push to `main` → builds and pushes to `ghcr.io/<repo>:latest`.

Requires secret `SARUMC_PAT` (fine-grained PAT with Contents: Read on SaruMC/core + SaruMC/horus).
