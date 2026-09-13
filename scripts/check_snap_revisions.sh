#!/bin/bash
OUTPUT_DIR="$HOME/observability-stack/textfile-collector"
COUNT=$(/usr/bin/snap list --all | grep -c disabled)

cat <<METRICS > "$OUTPUT_DIR/snap_old_revisions.prom.tmp"
# HELP snap_old_revisions_count Revisoes antigas de snap acumuladas, candidatas a limpeza
# TYPE snap_old_revisions_count gauge
snap_old_revisions_count $COUNT
METRICS

mv "$OUTPUT_DIR/snap_old_revisions.prom.tmp" "$OUTPUT_DIR/snap_old_revisions.prom"
