#!/bin/sh
# Nagios plugin: server uptime. Alerts when the server rebooted recently.
# Usage: check_uptime.sh -w <minutes> -c <minutes>   e.g. check_uptime.sh -w 30 -c 5
#   uptime < crit minutes -> CRITICAL (just rebooted / crashed)
#   uptime < warn minutes -> WARNING  (rebooted recently)
# Exit codes: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN

WARN=30
CRIT=5
while getopts "w:c:" opt; do
  case "$opt" in
    w) WARN=$OPTARG ;;
    c) CRIT=$OPTARG ;;
    *) echo "UPTIME UNKNOWN - usage: $0 -w <minutes> -c <minutes>"; exit 3 ;;
  esac
done

SECS=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
if [ -z "$SECS" ]; then
  echo "UPTIME UNKNOWN - cannot read /proc/uptime"
  exit 3
fi

MINS=$((SECS / 60))
D=$((SECS / 86400))
H=$((SECS % 86400 / 3600))
M=$((SECS % 3600 / 60))
TEXT="up ${D} days, ${H} hours, ${M} minutes"
PERF="uptime_minutes=${MINS};${WARN}:;${CRIT}:;0"

if [ "$MINS" -lt "$CRIT" ]; then
  echo "UPTIME CRITICAL - $TEXT (rebooted less than $CRIT minutes ago) | $PERF"
  exit 2
elif [ "$MINS" -lt "$WARN" ]; then
  echo "UPTIME WARNING - $TEXT (rebooted less than $WARN minutes ago) | $PERF"
  exit 1
else
  echo "UPTIME OK - $TEXT | $PERF"
  exit 0
fi