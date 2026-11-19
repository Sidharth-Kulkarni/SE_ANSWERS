#!/bin/sh
# Nagios plugin: memory usage in percent.
# Usage: check_mem.sh -w <warn %> -c <crit %>      e.g. check_mem.sh -w 80 -c 90
# Exit codes: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN

WARN=80
CRIT=90
while getopts "w:c:" opt; do
  case "$opt" in
    w) WARN=$OPTARG ;;
    c) CRIT=$OPTARG ;;
    *) echo "MEMORY UNKNOWN - usage: $0 -w <warn%> -c <crit%>"; exit 3 ;;
  esac
done

TOTAL=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
AVAIL=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)

if [ -z "$TOTAL" ] || [ -z "$AVAIL" ] || [ "$TOTAL" -eq 0 ]; then
  echo "MEMORY UNKNOWN - cannot read /proc/meminfo"
  exit 3
fi

USED=$((TOTAL - AVAIL))
PCT=$((USED * 100 / TOTAL))
USED_MB=$((USED / 1024))
TOTAL_MB=$((TOTAL / 1024))
PERF="mem_used=${PCT}%;${WARN};${CRIT};0;100"

if [ "$PCT" -ge "$CRIT" ]; then
  echo "MEMORY CRITICAL - ${PCT}% used (${USED_MB} MB of ${TOTAL_MB} MB) | $PERF"
  exit 2
elif [ "$PCT" -ge "$WARN" ]; then
  echo "MEMORY WARNING - ${PCT}% used (${USED_MB} MB of ${TOTAL_MB} MB) | $PERF"
  exit 1
else
  echo "MEMORY OK - ${PCT}% used (${USED_MB} MB of ${TOTAL_MB} MB) | $PERF"
  exit 0
fi