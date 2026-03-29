#!/bin/bash
set -e

# ── Cleanup ────────────────────────────────────────────────────────────────────
docker stop wordpress wordpressdb 2>/dev/null || true
docker rm   wordpress wordpressdb 2>/dev/null || true

# ── Prep ───────────────────────────────────────────────────────────────────────
mkdir -p ./docker-data/mysql ./docker-data/wordpress
docker network create wordpress-network 2>/dev/null || true

# ── Database ───────────────────────────────────────────────────────────────────
docker run --name wordpressdb \
  --network wordpress-network \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=wordpress \
  -v "$(pwd)/docker-data/mysql:/var/lib/mysql" \
  -d mariadb:lts

# ── Wait for MySQL ─────────────────────────────────────────────────────────────
echo "Waiting for MySQL to initialize..."
until docker exec wordpressdb mysqladmin ping -h localhost -proot --silent 2>/dev/null; do
  echo "  MySQL starting... retrying in 2s"
  sleep 2
done
echo "MySQL is up!"

# ── WordPress ──────────────────────────────────────────────────────────────────
docker run --name wordpress \
  --network wordpress-network \
  -p 8080:80 \
  -v "$(pwd)/docker-data/wordpress:/var/www/html" \
  -v "$(pwd):/var/www/html/wp-content/plugins/$(basename "$GITHUB_REPOSITORY")" \
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
  -d wordpress:php8.3-alpine

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "✅ WordPress is starting up!"
echo "🌐 Visit: https://${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
echo ""
echo "Note: WordPress may take 15–20s on first boot to unpack core files."