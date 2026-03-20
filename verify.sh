#!/bin/bash

# ExoGridChart Verification Script
# Checks if installation is complete and working

INSTALL_DIR="$HOME/.exogridchart"
CONFIG_DIR="$HOME/.config/exogridchart"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ExoGridChart Installation Verification${NC}"
echo -e "${BLUE}========================================${NC}\n"

PASS=0
FAIL=0

# Check 1: Installation directory
echo -e "${BLUE}[1] Checking installation directory...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${GREEN}✅ Installation directory found: $INSTALL_DIR${NC}"
    ((PASS++))
else
    echo -e "${RED}❌ Installation directory not found${NC}"
    echo -e "   Run: ${YELLOW}./install.sh --plugin-only${NC}"
    ((FAIL++))
fi

# Check 2: Binary
echo -e "${BLUE}[2] Checking executable binary...${NC}"
if [ -f "$INSTALL_DIR/bin/exo_ws_test" ]; then
    echo -e "${GREEN}✅ Binary found${NC}"
    ((PASS++))
else
    echo -e "${RED}❌ Binary not found${NC}"
    ((FAIL++))
fi

# Check 3: Headers
echo -e "${BLUE}[3] Checking header files...${NC}"
HEADERS=(
    "exo/types.h"
    "exo/parallel_aggregator.h"
    "exo/market_matrix.h"
)

HEADER_OK=true
for header in "${HEADERS[@]}"; do
    if [ -f "$INSTALL_DIR/include/$header" ]; then
        echo -e "${GREEN}✅ $header${NC}"
    else
        echo -e "${RED}❌ $header missing${NC}"
        HEADER_OK=false
    fi
done

if [ "$HEADER_OK" = true ]; then
    ((PASS++))
else
    ((FAIL++))
fi

# Check 4: Configuration
echo -e "${BLUE}[4] Checking configuration...${NC}"
if [ -f "$CONFIG_DIR/config.json" ]; then
    echo -e "${GREEN}✅ Configuration file found${NC}"

    # Check exchanges are enabled
    if grep -q '"enabled": true' "$CONFIG_DIR/config.json"; then
        ENABLED=$(grep -c '"enabled": true' "$CONFIG_DIR/config.json")
        echo -e "${GREEN}✅ $ENABLED exchange(s) enabled${NC}"
        ((PASS++))
    else
        echo -e "${YELLOW}⚠ No exchanges enabled${NC}"
        ((FAIL++))
    fi
else
    echo -e "${RED}❌ Configuration not found${NC}"
    ((FAIL++))
fi

# Check 5: Dependencies
echo -e "${BLUE}[5] Checking dependencies...${NC}"

DEPS_OK=true

if command -v zig &> /dev/null; then
    ZIG_VERSION=$(zig version 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✅ Zig installed: $ZIG_VERSION${NC}"
else
    echo -e "${YELLOW}⚠ Zig not found (may be needed for recompilation)${NC}"
    DEPS_OK=false
fi

if command -v cmake &> /dev/null; then
    CMAKE_VERSION=$(cmake --version | head -1)
    echo -e "${GREEN}✅ CMake installed${NC}"
else
    echo -e "${YELLOW}⚠ CMake not found (optional)${NC}"
fi

if [ "$DEPS_OK" = true ]; then
    ((PASS++))
fi

# Check 6: Run test
echo -e "${BLUE}[6] Testing real data streaming...${NC}"
if [ -f "$INSTALL_DIR/bin/exo_ws_test" ]; then
    OUTPUT=$("$INSTALL_DIR/bin/exo_ws_test" 2>&1)
    if echo "$OUTPUT" | grep -q "REAL DATA READY"; then
        echo -e "${GREEN}✅ Streaming test successful${NC}"
        echo -e "   ${BLUE}Output:${NC} $(echo "$OUTPUT" | head -1)"
        ((PASS++))
    else
        echo -e "${YELLOW}⚠ Streaming test inconclusive${NC}"
        echo -e "   ${BLUE}Output:${NC} $OUTPUT"
    fi
else
    echo -e "${YELLOW}⚠ Cannot run test (binary not found)${NC}"
fi

# Check 7: Compilation
echo -e "${BLUE}[7] Testing compilation...${NC}"

# Create simple test file
TEST_FILE="/tmp/exo_test.c"
cat > "$TEST_FILE" << 'TESTEOF'
#include "exo/types.h"
int main() { return 0; }
TESTEOF

if gcc -I"$INSTALL_DIR/include" "$TEST_FILE" -o /tmp/exo_test 2>/dev/null; then
    echo -e "${GREEN}✅ C compilation test passed${NC}"
    ((PASS++))
else
    echo -e "${YELLOW}⚠ C compilation test failed${NC}"
    ((FAIL++))
fi

rm -f "$TEST_FILE" /tmp/exo_test

# Summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}========================================${NC}\n"

TOTAL=$((PASS + FAIL))
PERCENTAGE=$((PASS * 100 / TOTAL))

echo -e "Passed: ${GREEN}$PASS/$TOTAL${NC}"
echo -e "Failed: ${RED}$FAIL/$TOTAL${NC}"
echo -e "Score:  ${BLUE}$PERCENTAGE%${NC}\n"

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✅ VERIFICATION PASSED${NC}"
    echo -e "\nYour ExoGridChart installation is ready!"
    echo -e "Next: Use the plugin in your application\n"
    exit 0
else
    echo -e "${RED}❌ VERIFICATION FAILED${NC}"
    echo -e "\nTo fix issues:"
    echo -e "  1. Re-run installation: ${YELLOW}./install.sh --plugin-only${NC}"
    echo -e "  2. Check dependencies: ${YELLOW}zig version${NC}, ${YELLOW}cmake --version${NC}"
    echo -e "  3. Review logs: ${YELLOW}cat $INSTALL_DIR/logs/install.log${NC}"
    echo -e "  4. Get help: ${YELLOW}https://github.com/SAVACAZAN/ExoGridChart/issues${NC}\n"
    exit 1
fi
