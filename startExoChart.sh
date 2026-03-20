#!/bin/bash

# ExoGridChart Startup Script
# Starts backend server on port 9090 (accessible from Windows + WSL)

cd "$(dirname "$0")"

echo "🚀 Starting ExoGridChart..."
echo ""

# Kill any existing instances
pkill -f "exo_server" 2>/dev/null

# Build if needed
if [ ! -f "zig-out/bin/exo_server" ]; then
    echo "📦 Building..."
    zig build || exit 1
fi

echo "🔧 Starting backend on 0.0.0.0:9090..."
./zig-out/bin/exo_server &

sleep 2

echo ""
echo "✅ ExoGridChart Online!"
echo "📊 URL: http://localhost:9090"
echo "🔌 Data: Coinbase, Kraken, LCX (live)"
echo ""
echo "Press Ctrl+C to stop"
wait
