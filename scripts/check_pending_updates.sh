#!/bin/bash
OUTPUT_DIR="$HOME/observability-stack/textfile-collector"
UPDATES=$(/usr/lib/update-notifier/apt-check 2>&1)
TOTAL=$(echo "$UPDATES" | cut -d';' -f1)
SECURITY=$(echo "$UPDATES" | cut -d';' -f2)

cat <<METRICS > "$OUTPUT_DIR/pending_updates.prom.tmp"
# HELP pending_updates_total Total de pacotes com atualizacao disponivel
# TYPE pending_updates_total gauge
pending_updates_total $TOTAL
# HELP pending_security_updates_total Pacotes com atualizacao de seguranca pendente
# TYPE pending_security_updates_total gauge
pending_security_updates_total $SECURITY
METRICS

mv "$OUTPUT_DIR/pending_updates.prom.tmp" "$OUTPUT_DIR/pending_updates.prom"
