#!/bin/bash
set -e

# ── Settings ───────────────────────────────────────────────────────────────────
MYSQL_DOCKER_IMAGE="mysql:9"
WORDPRESS_DOCKER_IMAGE="wordpress:6.9.4"
WORDPRESS_USER="admin"
WORDPRESS_PASSWORD="password"
IMPORT_TEST_DATA=false
PLUGIN_NAME=$(basename "$GITHUB_REPOSITORY")
SITE_URL="https://${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"

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
  -d $MYSQL_DOCKER_IMAGE

# ── Wait for MySQL ───────────────────────────────────────────────────────────
echo "Waiting for MySQL to initialize..."
until docker exec wordpressdb mysql -uroot -proot -e "SELECT 1" &>/dev/null; do
  echo "  MyQL starting... retrying in 2s"
  sleep 2
done
echo "MySQL is up!"

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
  -d $WORDPRESS_DOCKER_IMAGE

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

# ── Fix URLs ───────────────────
echo "Updating site URL... to $SITE_URL"
docker exec wordpress wp option update siteurl "$SITE_URL" --allow-root 2>/dev/null || true
docker exec wordpress wp option update home "$SITE_URL" --allow-root 2>/dev/null || true
docker exec wordpress wp config set WP_HOME "$SITE_URL" --allow-root 2>/dev/null || true
docker exec wordpress wp config set WP_SITEURL "$SITE_URL" --allow-root 2>/dev/null || true

# ── Install WordPress (skips if already installed) ─────────────────────────────
docker exec wordpress wp core is-installed --allow-root 2>/dev/null || \
(echo "Installing WordPress" && docker exec wordpress wp core install \
 --url="$SITE_URL" \
 --title="WordPress Test" \
 --admin_user=$WORDPRESS_USER \
 --admin_password=$WORDPRESS_PASSWORD \
 --admin_email="admin@example.com" \
 --skip-email \
 --allow-root)

# ── Install WordPress Test Data (skips if already installed) ─────────────────────────────
if $IMPORT_TEST_DATA; then
  echo "Importing Theme Unit Test data..."
  docker exec wordpress wp plugin install wordpress-importer --activate --allow-root
  docker exec wordpress curl -L -f -o theme-test-data.xml https://raw.githubusercontent.com/WordPress/theme-test-data/master/themeunittestdata.wordpress.xml
  docker exec wordpress wp import theme-test-data.xml --authors=create --allow-root
  docker exec wordpress rm theme-test-data.xml
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "✅ WordPress is ready!"
echo "🔌 Plugin folder: wp-content/plugins/${PLUGIN_NAME}"
echo "🌐 Visit: ${SITE_URL}"