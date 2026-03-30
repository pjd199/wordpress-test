#!/bin/bash

# 1. Start WordPress
npx wp-env start

# 2. Wait for the Database
echo "Waiting for database connection..."
until docker exec $(docker ps -qf "name=cli") wp db check --allow-root &>/dev/null; do
  echo "  Database is booting up... retrying in 2s"
  sleep 2
done



wp-env run cli wp config set FORCE_SSL_ADMIN false --raw --allow-root
wp-env run cli wp config set HTTP_X_FORWARDED_PROTO 'https' --allow-root

# Tell WordPress to trust the forwarded HTTPS header from Codespaces
#wp-env run cli wp config set --type=variable _SERVER "array_merge(\$_SERVER, array('HTTPS' => 'on', 'SERVER_PORT' => '443'))" --raw --allow-root



# 4. Get the Codespace URL (Assuming port 8888 for Dev site)
PORT=8888
SITE_URL="https://${CODESPACE_NAME}-${PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"


echo "Updating WordPress to use: $SITE_URL"

wp-env run cli wp option update siteurl "$SITE_URL" --allow-root
wp-env run cli wp option update home "$SITE_URL" --allow-root

wp-env run cli wp config set WP_HOME   "$SITE_URL" --allow-root
wp-env run cli wp config set WP_SITEURL "$SITE_URL" --allow-root

# 6. Fix Permalinks
wp-env run cli wp rewrite structure '/%postname%/' --allow-root
wp-env run cli wp rewrite flush --hard --allow-root

echo "✅ Done! Visit: $SITE_URL"