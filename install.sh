#!/bin/bash

# ExoGridChart Installation Script
# Installs market profile visualization plugin for Grid-DSL

set -e  # Exit on error

VERSION="1.0.0"
INSTALL_MODE="${1:---plugin-only}"
LICENSE_KEY="${3:---}"
INSTALL_DIR="$HOME/.exogridchart"
CONFIG_DIR="$HOME/.config/exogridchart"
DATA_DIR="$HOME/.local/share/exogridchart"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ExoGridChart Installation${NC}"
echo -e "${BLUE}Version: $VERSION${NC}"
echo -e "${BLUE}Mode: $INSTALL_MODE${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check prerequisites
echo -e "${BLUE}[1/5] Checking prerequisites...${NC}"

if ! command -v zig &> /dev/null; then
    echo -e "${RED}❌ Zig not found. Install from https://ziglang.org${NC}"
    exit 1
fi

if ! command -v cmake &> /dev/null; then
    echo -e "${RED}❌ CMake not found. Install CMake 3.20+${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites OK${NC}\n"

# Create directories
echo -e "${BLUE}[2/5] Creating directories...${NC}"
mkdir -p "$INSTALL_DIR"/{bin,lib,include/exo,docs,logs}
mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR"/{logs,cache}

echo -e "${GREEN}✅ Directories created${NC}\n"

# Build plugin
echo -e "${BLUE}[3/5] Building ExoGridChart plugin...${NC}"
cd "$(dirname "$0")"

if [ "$INSTALL_MODE" = "--plugin-only" ] || [ "$INSTALL_MODE" = "--basic" ] || [ "$INSTALL_MODE" = "--full" ] || [ "$INSTALL_MODE" = "--premium" ]; then
    zig build || { echo -e "${RED}❌ Build failed${NC}"; exit 1; }
    echo -e "${GREEN}✅ Build successful${NC}\n"
else
    echo -e "${RED}❌ Unknown installation mode: $INSTALL_MODE${NC}"
    echo "Valid modes: --plugin-only, --basic, --full, --premium"
    exit 1
fi

# Install files
echo -e "${BLUE}[4/5] Installing files...${NC}"

# Copy binary
cp zig-out/bin/exo_server "$INSTALL_DIR/bin/" 2>/dev/null || true

# Copy headers
cp src/exo/*.zig "$INSTALL_DIR/include/exo/" 2>/dev/null || true
cp include/exo/*.h "$INSTALL_DIR/include/exo/" 2>/dev/null || true

# Copy libraries (if built)
find . -name "*.a" -exec cp {} "$INSTALL_DIR/lib/" \; 2>/dev/null || true

# Copy documentation
cp README.md "$INSTALL_DIR/docs/" 2>/dev/null || true
cp INSTALL.md "$INSTALL_DIR/docs/" 2>/dev/null || true
cp READY_FOR_PRODUCTION.md "$INSTALL_DIR/docs/" 2>/dev/null || true

echo -e "${GREEN}✅ Files installed${NC}\n"

# Create configuration
echo -e "${BLUE}[5/5] Setting up configuration...${NC}"

cat > "$CONFIG_DIR/config.json" << EOF
{
  "plugin": {
    "mode": "${INSTALL_MODE#--}",
    "version": "$VERSION",
    "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "exchanges": {
    "coinbase": {
      "enabled": true,
      "url": "wss://ws-feed.exchange.coinbase.com",
      "products": ["BTC-USD", "ETH-USD"]
    },
    "kraken": {
      "enabled": true,
      "url": "wss://ws.kraken.com",
      "products": ["XBTUSDT", "ETHUSD"]
    },
    "lcx": {
      "enabled": true,
      "url": "wss://stream.production.lcx.ch",
      "products": ["BTC-USD", "ETH-USD"]
    }
  },
  "matrix": {
    "price_min": 40000.0,
    "price_max": 70000.0,
    "price_step": 10.0,
    "time_buckets": 60
  },
  "monetization": {
    "tier": "${INSTALL_MODE#--}",
    "license_key": null
  }
}
EOF

# Add install dir to PATH (optional)
if ! grep -q "$INSTALL_DIR/bin" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# ExoGridChart" >> ~/.bashrc
    echo "export PATH=\"\$PATH:$INSTALL_DIR/bin\"" >> ~/.bashrc
    echo -e "${GREEN}✅ Added to PATH${NC}"
fi

echo -e "${GREEN}✅ Configuration created${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "Installation Summary:"
echo -e "  Mode:     ${BLUE}$INSTALL_MODE${NC}"
echo -e "  Location: ${BLUE}$INSTALL_DIR${NC}"
echo -e "  Config:   ${BLUE}$CONFIG_DIR/config.json${NC}"
echo -e "  Data:     ${BLUE}$DATA_DIR${NC}\n"

echo -e "Next steps:"
echo -e "  1. Verify:  ${BLUE}./verify.sh${NC}"
echo -e "  2. Test:    ${BLUE}exo_ws_test${NC}"
echo -e "  3. Docs:    ${BLUE}cat $INSTALL_DIR/docs/README.md${NC}\n"

echo -e "Support:"
echo -e "  Issues:   ${BLUE}https://github.com/SAVACAZAN/ExoGridChart/issues${NC}"
echo -e "  Docs:     ${BLUE}$INSTALL_DIR/docs/${NC}\n"

echo -e "${GREEN}Ready to stream real market data! 🚀${NC}\n"
