# WordPress in Codespace

A single script to spin up a local WordPress development environment using Docker inside a Codespace, with your plugin automatically mounted and ready to go.

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- A GitHub Codespace

---

## Installation
Download dev.sh into your codespace and give it execute permission

```bash
curl -O https://raw.githubusercontent.com/pjd199/wordpress-test/refs/heads/main/dev.sh
chmod +x dev.sh
```

## Usage
```bash
./wordpress.sh <command>
```

| Command | Description |
|---|---|
| `start` | Start WordPress and MariaDB containers |
| `stop` | Stop running containers (data is preserved) |
| `clean` | Stop and remove all containers, networks, and data |
| `test-data` | Import the WordPress Theme Unit Test dataset |
| `update` | Check for new versions of the script |

---

## Commands

### `start`

Start the Wordpress development environment.
```bash
./wordpress.sh start
```

Once running, your site will be available at:
```
https://<CODESPACE_NAME>-8080.<GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN>
```

---

### `stop`

Stops the running containers without deleting any data.
```bash
./wordpress.sh stop
```

Run `./wordpress.sh start` again to resume where you left off.

---

### `clean`

Permanently removes all containers, the Docker network, and the `./docker-data` directory (database + WordPress files).
```bash
./wordpress.sh clean
```

You will be prompted to confirm before anything is deleted.

---

### `test-data`

Imports the official [WordPress Theme Unit Test data](https://github.com/WordPress/theme-test-data) into your site. Useful for testing your plugin against a realistic variety of posts, pages, menus, and media.
```bash
./wordpress.sh test-data
```

> Run `./wordpress.sh start` first. This command installs the WordPress Importer plugin and imports the XML dataset.

---

### `update`

Check for new version of the script from GitHub, and prompt to update if required. Please note, updating the script
may switch to newer versions of Wordpress or MariaDB.
```bash
./wordpress.sh update
```

> Run `./wordpress.sh start` first. This command installs the WordPress Importer plugin and imports the XML dataset.

---

## Data Persistence

Docker volumes are stored locally under `./docker-data/`:
```
docker-data/
├── mariadb/      # Database files
└── wordpress/    # WordPress core files
```

These persist across `stop`/`start` cycles. Use `clean` to wipe everything.

---

## Plugin Mounting

Your repository root is automatically mounted as a plugin inside the container:
```
/var/www/html/wp-content/plugins/<your-repo-name>
```

The plugin name is derived from the `GITHUB_REPOSITORY` environment variable (`basename`), so it matches your repo name automatically.
