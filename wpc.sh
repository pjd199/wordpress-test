#!/bin/bash
set -e

# ── Script Metadata ────────────────────────────────────────────────────────────
CURRENT_VERSION="0.0.5"
AUTHOR="pjd199"
SOURCE_URI="https://github.com/pjd199/wordpress-codespace"
LICENSE="MIT"

# ── Codespaces Check  ──────────────────────────────────────────────────────────
if [ -z "$CODESPACE_NAME" ] || [ -z "$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" ] || [ -z "$GITHUB_REPOSITORY" ]; then
    echo "Error: This script is designed to run inside GitHub Codespaces." >&2
    echo "CODESPACE_NAME, GITHUB_REPOSITORY and GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN must be set." >&2
    exit 1
fi

# ── Settings ───────────────────────────────────────────────────────────────────
WPC_DB_IMAGE=${WPC_DB_IMAGE:-"mariadb:lts"}
WPC_WP_IMAGE=${WPC_WP_IMAGE:-"wordpress:latest"}
WPC_USERNAME=${WPC_USERNAME:-"admin"}
WPC_PASSWORD=${WPC_PASSWORD:-"password"}
WPC_PLUGIN_NAME=${WPC_PLUGIN_NAME:-$(basename "$GITHUB_REPOSITORY")}
WPC_DIR=${WPC_DIR:-"/workspaces/${GITHUB_REPOSITORY#*/}/.wpc"}

# ── Dependency Checks ──────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo "Error: Docker is not installed or not in PATH." >&2
    echo "Install Docker: https://docs.docker.com/get-docker/" >&2
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "Error: Docker daemon is not running." >&2
    echo "Start Docker and try again." >&2
    exit 1
fi

# ── Version Check ─────────────────────────────────────────────────────────────
check_for_updates() {
    REPO="pjd199/wordpress-codespace"
    LATEST_VERSION=$(curl -sf "https://api.github.com/repos/$REPO/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ "$1" != "quiet" ]; then
        if [ -z "$LATEST_VERSION" ]; then
            echo ">>> Could not check for updates."
        elif [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
            echo ">>> Update available: $LATEST_VERSION (you are on $CURRENT_VERSION)"
            echo ">>> Run {$0} update to upgrade."
        fi
    fi
}

# ── Stop Containers ───────────────────────────────────────────────────────────
stop_containers() {
    docker stop wordpress wordpressdb 2>/dev/null || true
    docker rm   wordpress wordpressdb 2>/dev/null || true
    docker network rm wordpress-network 2>/dev/null || true
}

wait_for_container() {
    local NAME=$1
    local CHECK_CMD=$2
    local TIMEOUT=${3:-60}
    local ELAPSED=0

    printf "Waiting for $NAME to initialize..."
    until eval "$CHECK_CMD" &>/dev/null; do
        if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
            echo ""
            echo "Error: $NAME did not start within ${TIMEOUT}s." >&2
            exit 1
        fi
        printf "."
        sleep 1
        ELAPSED=$((ELAPSED + 2))
    done
    echo ""
    echo "$NAME is up!"
}

is_wordpress_running() {
    docker ps --filter "name=wordpress" --filter "status=running" -q | grep -q .
}

is_database_running() {
    docker ps --filter "name=wordpressdb" --filter "status=running" -q | grep -q .
}

case $1 in
  start)
        # ── Cleanup ────────────────────────────────────────────────────────────
        if is_wordpress_running || is_database_running; then
            echo "Cleaning up from previous start..."
            stop_containers
        fi

        # ── Prep ───────────────────────────────────────────────────────────────
        mkdir -p $WPC_DIR/mariadb $WPC_DIR/wordpress
        docker network create wordpress-network 2>/dev/null || true

        # ── Database ───────────────────────────────────────────────────────────
        echo "Starting MariaDB Docker image ${WPC_DB_IMAGE}..."
        docker run --name wordpressdb \
        --network wordpress-network \
        -e MYSQL_ROOT_PASSWORD=root \
        -e MYSQL_DATABASE=wordpress \
        -v "${WPC_DIR}/mariadb:/var/lib/mysql" \
        -d $WPC_DB_IMAGE


        # ── Wait for MySQL ─────────────────────────────────────────────────────
        wait_for_container "MariaDB" "docker exec wordpressdb mariadb -uroot -proot -e 'SELECT 1'"

        # ── WordPress ──────────────────────────────────────────────────────────
        echo "Starting Wordpress Docker image ${WPC_WP_IMAGE}..."
        docker run --name wordpress \
        --network wordpress-network \
        -p 80:80 \
        -v "${WPC_DIR}/wordpress:/var/www/html" \
        -v "$(pwd):/var/www/html/wp-content/plugins/${WPC_PLUGIN_NAME}" \
        -e WORDPRESS_DB_HOST=wordpressdb \
        -e WORDPRESS_DB_USER=root \
        -e WORDPRESS_DB_PASSWORD=root \
        -e WORDPRESS_DB_NAME=wordpress \
        -e CODESPACE_NAME="$CODESPACE_NAME" \
        -e GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN="$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" \
        -e WORDPRESS_CONFIG_EXTRA="
            \$_SERVER['HTTP_HOST'] = \$_SERVER['HTTP_X_FORWARDED_HOST'] ?? \$_SERVER['HTTP_HOST'];
            \$_SERVER['HTTPS'] = 'on';

            \$codespace_name   = getenv('CODESPACE_NAME');
            \$codespace_domain = getenv('GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN');

            if (\$codespace_name && \$codespace_domain) {
                \$site_url = 'https://' . \$codespace_name . '-80.' . \$codespace_domain;
                define('WP_HOME',    \$site_url);
                define('WP_SITEURL', \$site_url);
            }

            define('FORCE_SSL_ADMIN', true);
        " \
        -d $WPC_WP_IMAGE

        # ── Wait for WordPress ─────────────────────────────────────────────────
        wait_for_container "WordPress" "docker exec wordpress curl -s -o /dev/null -w '%{http_code}' http://localhost | grep -qE '^(200|301|302|404)'"

        # ── Install WP-CLI ─────────────────────────────────────────────────────
        if ! docker exec wordpress command -v wp >/dev/null 2>&1; then
            echo "Installing WP-CLI..."
            docker exec wordpress curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
            docker exec wordpress chmod +x wp-cli.phar
            docker exec wordpress mv wp-cli.phar /usr/local/bin/wp
        fi

        # ── Fix URLs ───────────────────────────────────────────────────────────
        SITE_URL="https://${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
        echo "Updating site URL to $SITE_URL"
        docker exec wordpress wp option update siteurl "$SITE_URL" --allow-root 2>/dev/null || true
        docker exec wordpress wp option update home "$SITE_URL" --allow-root 2>/dev/null || true
        docker exec wordpress wp config set WP_HOME "$SITE_URL" --allow-root 2>/dev/null || true
        docker exec wordpress wp config set WP_SITEURL "$SITE_URL" --allow-root 2>/dev/null || true

        # ── Install WordPress (if needed) ─────────────────────
        docker exec wordpress wp core is-installed --allow-root 2>/dev/null || \
        (echo "Installing WordPress" && docker exec wordpress wp core install \
        --url="$SITE_URL" \
        --title="WordPress Test" \
        --admin_user=$WPC_USERNAME \
        --admin_password=$WPC_PASSWORD \
        --admin_email="admin@example.com" \
        --skip-email \
        --allow-root)

        # ── Fix file permissions ───────────────────────────────────────────────────
        echo "Fixing file permissions..."
        sudo chmod -R 777 $WPC_DIR

        # ── Done ────────────────────────────────────────────────────────────────
        echo ""
        echo "WordPress is ready!"  
        echo "Visit: ${SITE_URL}"
        echo "Username: ${WPC_USERNAME}"
        echo "Password: ${WPC_PASSWORD}"
        echo "Plugin mounted at: $WPC_DIR/wordpress/wp-content/plugins/${WPC_PLUGIN_NAME}"

        check_for_updates
        ;;

    stop)
        echo "Stopping..."
        stop_containers
        
        check_for_updates
        ;;

    clean)
        echo "This will permanently delete all WordPress and database files at $WPC_DIR"
        read -p "Are you sure? (yes/no): " CONFIRM

        if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 0
        fi

        echo ""
        echo "Stopping and removing containers..."
        stop_containers
        docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "wordpress|mariadb" | xargs -r docker rmi

        echo "Removing network..."
        docker network rm wordpress-network 2>/dev/null || true

        echo "Removing WordPress and database files..."
        sudo rm -rf $WPC_DIR

        echo ""
        echo "Done! Run ./start.sh to start fresh."
        
        check_for_updates
        ;;

    test-data)
        if ! is_wordpress_running || ! is_database_running; then
            echo "Error: WordPress and database containers must be running." >&2
            echo "Run {$0} start first." >&2
            exit 1
        fi

        # ── Install WordPress Test Data  ─────────────────────────────────
        echo "Importing Theme Unit Test data..."
        docker exec wordpress wp plugin install wordpress-importer --activate --allow-root
        docker exec wordpress curl -L -f -o theme-test-data.xml https://raw.githubusercontent.com/WordPress/theme-test-data/master/themeunittestdata.wordpress.xml
        docker exec wordpress wp import theme-test-data.xml --authors=create --allow-root
        docker exec wordpress rm theme-test-data.xml
        
        check_for_updates
        ;;

    update)
        # ── Check for script updates on GitHub  ───────────────────────────
        echo "Checking for latest stable release..."
        
        check_for_updates
        echo ""

        if [ -z "$LATEST_VERSION" ]; then
            echo "Could not fetch version info. Skipping update check."
            return
        fi

        if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
            echo "New Stable Release found: $LATEST_VERSION (You are on $CURRENT_VERSION)"
            read -p "Do you want to upgrade to the latest stable version? (y/n): " update_confirm
            
            if [ "$update_confirm" = "y" ]; then
                DOWNLOAD_URL="https://raw.githubusercontent.com/$REPO/$LATEST_VERSION/wordpress.sh"
                if sudo curl -L -o "$0.tmp" "$DOWNLOAD_URL"; then
                    sudo mv "$0.tmp" "$0"
                    sudo chmod +x "$0"
                    echo "Successfully upgraded to $LATEST_VERSION! Please restart the script."
                    exit 0
                else
                    echo "Download failed."
                fi
            fi
        else
            echo "You are running the latest stable version ($CURRENT_VERSION)."
        fi
        ;;

    status)
        echo "── Containers ───────────────────────────────────────────────────────"
        if is_wordpress_running; then
            echo "  WordPress:  running"
        else
            echo "  WordPress:  stopped"
        fi

        if is_database_running; then
            echo "  Database:   running"
        else
            echo "  Database:   stopped"
        fi

        echo ""
        echo "── Site ─────────────────────────────────────────────────────────────"
        if is_wordpress_running; then
            SITE_URL="https://${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
            echo "  URL:        ${SITE_URL}"
            echo "  Username:   ${WPC_USERNAME}"
            echo "  Password:   ${WPC_PASSWORD}"
            echo "  Plugin:     wp-content/plugins/${WPC_PLUGIN_NAME}"
        else
            echo "  Not available (WordPress is not running)"
        fi

        check_for_updates "quiet"
        echo ""
        echo "── Versions ─────────────────────────────────────────────────────────"
        echo "  Script:     ${CURRENT_VERSION}"

        if [ -n "$LATEST_VERSION" ] && [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
            echo "  Latest:     ${LATEST_VERSION} (update available)"
        else
            echo "  Latest:     ${LATEST_VERSION:-unknown}"
        fi

        if is_database_running; then
            DB_VERSION=$(docker exec wordpressdb mariadb --version 2>/dev/null \
                | sed -E 's/.*Ver ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
            echo "  MariaDB:    ${DB_VERSION:-unknown}"
        else
            echo "  MariaDB:    not running"
        fi

        if is_wordpress_running; then
            WP_VERSION=$(docker exec wordpress wp core version --allow-root 2>/dev/null)
            PHP_VERSION=$(docker exec wordpress php -r 'echo PHP_VERSION;' 2>/dev/null)
            echo "  WordPress:  ${WP_VERSION:-unknown}"
            echo "  PHP:        ${PHP_VERSION:-unknown}"
        else
            echo "  WordPress:  not running"
            echo "  PHP:        not running"
        fi
        
        ;;
    *)
        # ── Print usage  ─────────────────────────────────────────────────────
        echo "Usage: $0 {start|stop|clean|status|test-data|update}"
        exit 1
    ;;
esac