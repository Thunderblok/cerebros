#!/bin/bash

# Watch Training Logs in Real-Time
# This script tails the server log and highlights training-related messages

echo "=========================================="
echo "  🔍 Watching Cerebros Training Logs"
echo "=========================================="
echo ""
echo "Monitoring: /tmp/thunderline_server.log"
echo "Ctrl+C to stop"
echo ""
echo "==========================================
"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Tail the log file and colorize training-related messages
tail -f /tmp/thunderline_server.log 2>/dev/null | while IFS= read -r line; do
  # Highlight training messages
  if echo "$line" | grep -q "Starting Cerebros"; then
    echo -e "${CYAN}${line}${NC}"
  elif echo "$line" | grep -q "✓"; then
    echo -e "${GREEN}${line}${NC}"
  elif echo "$line" | grep -q "✗\|❌\|ERROR\|Failed"; then
    echo -e "${RED}${line}${NC}"
  elif echo "$line" | grep -q "✅"; then
    echo -e "${GREEN}${line}${NC}"
  elif echo "$line" | grep -q "Processed.*chunks\|CSV saved\|Cerebros"; then
    echo -e "${YELLOW}${line}${NC}"
  elif echo "$line" | grep -q "QUERY\|HANDLE EVENT\|MOUNT"; then
    # Suppress debug noise
    continue
  else
    echo "$line"
  fi
done
