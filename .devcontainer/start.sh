#!/bin/bash
set -e

# ── Cleanup ────────────────────────────────────────────────────────────────────
docker stop wordpress wordpressdb 2>/dev/null || true
docker rm   wordpress wordpressdb 2>/dev/null || true

# ── Prep ───────────────────────────────────────────────────────────────────────
mkdir -p ./docker-data/mysql ./docker-data/wordpress
docker network create wordpress-network 2>/dev/null || true

PLUGIN_NAME=$(basename "$GITHUB_REPOSITORY")
SITE_URL="https://${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"

# ── Database ───────────────────────────────────────────────────────────────────
docker run --name wordpressdb \
  --network wordpress-network \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=wordpress \
  -v "$(pwd)/docker-data/mysql:/var/lib/mysql" \
  -d mariadb:lts

# ── Wait for MariaDB ───────────────────────────────────────────────────────────
echo "Waiting for MariaDB to initialize..."
until docker exec wordpressdb mariadb -uroot -proot -e "SELECT 1" &>/dev/null; do
  echo "  MariaDB starting... retrying in 2s"
  sleep 2
done
echo "MariaDB is up!"

# ── WordPress ──────────────────────────────────────────────────────────────────
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
  -d wordpress:php8.3-apache

# ── Wait for WordPress ─────────────────────────────────────────────────────────
echo "Waiting for WordPress to initialize..."
until docker exec wordpress curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -qE "^(200|301|302|404)"; do
  echo "  WordPress starting... retrying in 2s"
  sleep 2
done
echo "WordPress is up!"

# ── Install WP-CLI ─────────────────────────────────────────────────────────────
echo "Installing WP-CLI..."
docker exec wordpress curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
docker exec wordpress chmod +x wp-cli.phar
docker exec wordpress mv wp-cli.phar /usr/local/bin/wp

# ── Fix URLs in DB (handles Codespace restarts with new URL) ───────────────────
echo "Updating site URL in database..."
docker exec wordpress wp option update siteurl "$SITE_URL" --allow-root 2>/dev/null || true
docker exec wordpress wp option update home    "$SITE_URL" --allow-root 2>/dev/null || true

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "✅ WordPress is ready!"
echo "🔌 Plugin folder: wp-content/plugins/${PLUGIN_NAME}"
echo "🌐 Visit: ${SITE_URL}"