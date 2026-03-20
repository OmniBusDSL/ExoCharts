#!/bin/bash

# ExoGridChart Shutdown Script
# Stops all ExoGridChart processes

echo "🛑 Stopping ExoGridChart..."

pkill -f "exo_server" && echo "✅ Backend stopped" || echo "ℹ️ No backend running"

echo ""
echo "Done!"
