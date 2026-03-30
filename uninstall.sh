#!/bin/bash

echo "⚠️  This will permanently delete all WordPress and database files."
read -p "Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "🛑 Stopping and removing containers..."
docker stop wordpress wordpressdb 2>/dev/null || true
docker rm   wordpress wordpressdb 2>/dev/null || true

echo "🌐 Removing network..."
docker network rm wordpress-network 2>/dev/null || true

echo "🗑️  Removing WordPress and database files..."
sudo rm -rf ./docker-data

echo ""
echo "✅ Done! Run ./start.sh to start fresh."