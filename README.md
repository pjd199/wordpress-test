# WordPress in Codespace

A single script to spin up a local WordPress development environment using Docker inside a Codespace, with an option to mount your repository root as either a plugin or a theme.

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- A GitHub Codespace

---

## Installation

### Manual Installation
Download wpc.sh into your codespace and give it execute permissions.

```bash
# Download the specific release to /usr/local/bin
sudo curl -L -o /usr/local/bin/wpc https://raw.githubusercontent.com/pjd199/wordpress-codespace/refs/tags/0.0.3/wpc.sh

# Make it executable
sudo chmod +x /usr/local/bin/wpc
```

### Automatic Installation with .devcontainer
Add these postCreateCommands and postStartCommands .devcontainer/.devcontainer.json in your reposiroty
```json
{
  "name": "WordPress Development Codespace",
  "postCreateCommand": "sudo curl -L -o /usr/local/bin/wpc https://raw.githubusercontent.com/pjd199/wordpress-codespace/refs/tags/0.0.3/wpc.sh && sudo chmod +x /usr/local/bin/wpc",
  "postStartCommand": "wpc start",
  "forwardPorts": [8080],
  "portsAttributes": {
    "8080": { 
        "label": "WordPress", 
        "onAutoForward": "openBrowserOnce" }
  }
}
```

To automatically map your git repository as either a plugin or theme into WordPress,
change the postStartCommand to either `wpc start --plugin` or `wpc start --theme`.


### Add to .gitignore
Add the `.docker-data` directory to your .gitignore file.

## Usage
```bash
wpc <command>
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
wpc start
```

Once running, your site will be available at:
```
https://<CODESPACE_NAME>-8080.<GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN>
```

---

### `stop`

Stops the running containers without deleting any data.
```bash
wpc stop
```

Run `wpc start` again to resume where you left off.

---

### `clean`

Permanently removes all containers, the Docker network, and the `.docker-data` directory (database + WordPress files).
```bash
wpc  clean
```

You will be prompted to confirm before anything is deleted.

---

### `test-data`

Imports the official [WordPress Theme Unit Test data](https://github.com/WordPress/theme-test-data) into your site. Useful for testing your plugin against a realistic variety of posts, pages, menus, and media.
```bash
wpc  test-data
```

> Run `wpc  start` first. This command installs the WordPress Importer plugin and imports the XML dataset.

---

## Data Persistence

Docker volumes are stored in the workspace under `.docker-data`:
```
.docker-data/
├── mariadb/      # Database files
└── wordpress/    # WordPress core files
```

These persist across `stop`/`start` cycles. Use `clean` to wipe everything.

---

## Plugin|Theme Mounting

Your repository root can be automatically mounted as a either a plugin or theme inside the container:
```bash
# Mount repository root as a plugin
wpc start --plugin

# Mount repository root as a theme
wpc start --theme
```

The plugin/theme name is derived from the `GITHUB_REPOSITORY` environment variable (`basename`), so it matches your repo name automatically.
