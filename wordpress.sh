#!/bin/bash
set -e

# ── Settings ───────────────────────────────────────────────────────────────────
MARIADB_DOCKER_IMAGE="mariadb:11"
WORDPRESS_DOCKER_IMAGE="wordpress:6.9.4"
WORDPRESS_USER="admin"
WORDPRESS_PASSWORD="password"
PLUGIN_NAME=$(basename "$GITHUB_REPOSITORY")

# ── Script Version ────────────────────────────────────────────────────────────
CURRENT_VERSION="0.0.2"

case $1 in
  start)
        # ── Cleanup ────────────────────────────────────────────────────────────
        docker stop wordpress wordpressdb 2>/dev/null || true
        docker rm   wordpress wordpressdb 2>/dev/null || true

        # ── Prep ───────────────────────────────────────────────────────────────
        mkdir -p ./docker-data/mariadb ./docker-data/wordpress
        docker network create wordpress-network 2>/dev/null || true

        # ── Database ───────────────────────────────────────────────────────────
        docker run --name wordpressdb \
        --network wordpress-network \
        -e MYSQL_ROOT_PASSWORD=root \
        -e MYSQL_DATABASE=wordpress \
        -v "$(pwd)/docker-data/mariadb:/var/lib/mysql" \
        -d $MARIADB_DOCKER_IMAGE


        # ── Wait for MySQL ─────────────────────────────────────────────────────
        echo "Waiting for MariaDB to initialize..."
        until docker exec wordpressdb mariadb -uroot -proot -e "SELECT 1" &>/dev/null; do
        echo "  MariaDB starting... retrying in 2s"
        sleep 2
        done
        echo "MariaDB is up!"

        # ── WordPress ──────────────────────────────────────────────────────────
        docker run --name wordpress \
        --network wordpress-network \
        -p 8080:80 \
        -v "$(pwd)/docker-data/wordpress:/var/www/html" \
        -v "$(pwd):/var/www/html/wp-content/plugins/${PLUGIN_NAME}" \
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
                \$site_url = 'https://' . \$codespace_name . '-8080.' . \$codespace_domain;
                define('WP_HOME',    \$site_url);
                define('WP_SITEURL', \$site_url);
            }

            define('FORCE_SSL_ADMIN', true);
        " \
        -d $WORDPRESS_DOCKER_IMAGE

        # ── Wait for WordPress ─────────────────────────────────────────────────
        echo "Waiting for WordPress to initialize..."
        until docker exec wordpress curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -qE "^(200|301|302|404)"; do
        echo "  WordPress starting... retrying in 2s"
        sleep 2
        done
        echo "WordPress is up!"

        # ── Install WP-CLI ─────────────────────────────────────────────────────
        echo "Installing WP-CLI..."
        docker exec wordpress curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        docker exec wordpress chmod +x wp-cli.phar
        docker exec wordpress mv wp-cli.phar /usr/local/bin/wp

        # ── Fix URLs ───────────────────────────────────────────────────────────
        SITE_URL="https://${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
        echo "Updating site URL... to $SITE_URL"
        docker exec wordpress wp option update siteurl "$SITE_URL" --allow-root 2>/dev/null || true
        docker exec wordpress wp option update home "$SITE_URL" --allow-root 2>/dev/null || true
        docker exec wordpress wp config set WP_HOME "$SITE_URL" --allow-root 2>/dev/null || true
        docker exec wordpress wp config set WP_SITEURL "$SITE_URL" --allow-root 2>/dev/null || true

        # ── Install WordPress (skips if already installed) ─────────────────────
        docker exec wordpress wp core is-installed --allow-root 2>/dev/null || \
        (echo "Installing WordPress" && docker exec wordpress wp core install \
        --url="$SITE_URL" \
        --title="WordPress Test" \
        --admin_user=$WORDPRESS_USER \
        --admin_password=$WORDPRESS_PASSWORD \
        --admin_email="admin@example.com" \
        --skip-email \
        --allow-root)

        # ── Done ────────────────────────────────────────────────────────────────
        echo ""
        echo "WordPress is ready!"
        echo "Plugin folder: wp-content/plugins/${PLUGIN_NAME}"
        echo "Visit: ${SITE_URL}"
        echo "Username: ${WORDPRESS_USER}"
        echo "Password: ${WORDPRESS_PASSWORD}"
        ;;
    
    stop)
        echo "Stopping..."
        docker stop wordpress wordpressdb 2>/dev/null || true
        ;;

    clean)
        echo "This will permanently delete all WordPress and database files."
        read -p "Are you sure? (yes/no): " CONFIRM

        if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 0
        fi

        echo ""
        echo "Stopping and removing containers..."
        docker stop wordpress wordpressdb 2>/dev/null || true
        docker rm   wordpress wordpressdb 2>/dev/null || true

        echo "Removing network..."
        docker network rm wordpress-network 2>/dev/null || true

        echo "Removing WordPress and database files..."
        sudo rm -rf ./docker-data

        echo ""
        echo "Done! Run ./start.sh to start fresh."
        ;;

    test-data)
        # ── Install WordPress Test Data  ─────────────────────────────────
        echo "Importing Theme Unit Test data..."
        docker exec wordpress wp plugin install wordpress-importer --activate --allow-root
        docker exec wordpress curl -L -f -o theme-test-data.xml https://raw.githubusercontent.com/WordPress/theme-test-data/master/themeunittestdata.wordpress.xml
        docker exec wordpress wp import theme-test-data.xml --authors=create --allow-root
        docker exec wordpress rm theme-test-data.xml
        ;;

    update)
        # ── Check for script updates on GitHub  ───────────────────────────
        echo "Checking for latest stable release..."

        REPO="pjd199/wordpress-codespace"
        API_URL="https://api.github.com/repos/$REPO/releases/latest"
        LATEST_VERSION=$(curl -s $API_URL | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

        if [ -z "$LATEST_VERSION" ]; then
            echo "Could not fetch version info. Skipping update check."
            return
        fi

        if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
            echo "New Stable Release found: $LATEST_VERSION (You are on $CURRENT_VERSION)"
            read -p "Do you want to upgrade to the latest stable version? (y/n): " update_confirm
            
            if [ "$update_confirm" = "y" ]; then
                DOWNLOAD_URL="https://raw.githubusercontent.com/$REPO/$LATEST_VERSION/wordpress.sh"
                if curl -L -o "$0.tmp" "$DOWNLOAD_URL"; then
                    mv "$0.tmp" "$0"
                    chmod +x "$0"
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

    *)
        # ── Print usage  ─────────────────────────────────────────────────────
        echo "Usage: ./dev.sh {start|stop|clean|test-data|update}"
        exit 1
    ;;
esac