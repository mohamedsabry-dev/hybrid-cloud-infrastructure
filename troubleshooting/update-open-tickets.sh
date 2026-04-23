#!/bin/bash
# Scans all troubleshooting cases and regenerates OPEN-TICKETS.md
# and opens an HTML report in the browser.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_MD="$SCRIPT_DIR/OPEN-TICKETS.md"
OUTPUT_HTML="/tmp/open-tickets.html"
TODAY=$(date +%Y-%m-%d)

# --- Build markdown ---
cat > "$OUTPUT_MD" << EOF
# Open Tickets

Non-resolved cases across all categories. Last updated: $TODAY.

| Ticket | Status | What Happened |
|--------|--------|---------------|
EOF

# --- Start HTML ---
cat > "$OUTPUT_HTML" << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Open Tickets</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background: #0d1117; color: #c9d1d9; padding: 40px; }
  h1 { color: #58a6ff; margin-bottom: 6px; font-size: 24px; }
  .meta { color: #8b949e; margin-bottom: 24px; font-size: 14px; }
  table { width: 100%; border-collapse: collapse; }
  th { text-align: left; padding: 10px 14px; border-bottom: 2px solid #30363d;
       color: #8b949e; font-size: 13px; text-transform: uppercase; letter-spacing: 0.5px; }
  td { padding: 10px 14px; border-bottom: 1px solid #21262d; font-size: 14px; }
  tr:hover { background: #161b22; }
  .ticket { color: #58a6ff; font-weight: 600; font-family: monospace; }
  .status { display: inline-block; padding: 2px 8px; border-radius: 12px;
            font-size: 12px; font-weight: 600; }
  .UNRESOLVED { background: #da363340; color: #f85149; }
  .SUSPENDED { background: #d29922; color: #0d1117; }
  .WORKAROUND { background: #e3b34140; color: #e3b341; }
  .PENDING { background: #e3b34140; color: #e3b341; }
  .TEMP { background: #8b949e30; color: #8b949e; }
  .TRIGGER { background: #da363340; color: #f85149; }
  .IN { background: #58a6ff30; color: #58a6ff; }
  .desc { color: #8b949e; }
  .count { margin-top: 20px; color: #8b949e; font-size: 14px; }
</style>
</head>
<body>
HTMLHEAD

echo "<h1>Open Tickets</h1>" >> "$OUTPUT_HTML"
echo "<p class=\"meta\">Last updated: $TODAY</p>" >> "$OUTPUT_HTML"
echo "<table><tr><th>Ticket</th><th>Status</th><th>What Happened</th></tr>" >> "$OUTPUT_HTML"

COUNT=0

find "$SCRIPT_DIR" -name "*.md" -not -path "*/reference/*" -not -name "README.md" \
  -not -name "OPEN-TICKETS.md" -not -name "TEMPLATE*" | sort | while read -r file; do

  header=$(head -1 "$file")

  echo "$header" | grep -q "^# TS-" || continue
  echo "$header" | grep -qi "RESOLVED" && ! echo "$header" | grep -qi "UNRESOLVED" && continue

  ticket=$(echo "$header" | sed 's/^# //' | cut -d'|' -f1 | xargs)
  status=$(echo "$header" | awk -F'|' '{print $NF}' | xargs)

  desc=$(awk '/\[Issue Description\]/{found=1; next} found && /^[^_[:space:]]/{print; exit}' "$file")
  [ -z "$desc" ] && desc=$(awk '/\[Issue Description\]/{found=1; next} found && NF{print; exit}' "$file")
  desc=$(echo "$desc" | cut -c1-90 | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/`//g')

  relpath=$(echo "$file" | sed "s|$SCRIPT_DIR/||")
  status_class=$(echo "$status" | awk '{print $1}')

  echo "| [$ticket]($relpath) | $status | $(echo "$desc" | cut -c1-80) |" >> "$OUTPUT_MD"
  echo "<tr><td class=\"ticket\">$ticket</td><td><span class=\"status $status_class\">$status</span></td><td class=\"desc\">$desc</td></tr>" >> "$OUTPUT_HTML"
done

count=$(grep -c "^| \[TS-" "$OUTPUT_MD")
echo "" >> "$OUTPUT_MD"
echo "**Total: $count open**" >> "$OUTPUT_MD"

echo "</table>" >> "$OUTPUT_HTML"
echo "<p class=\"count\"><strong>$count</strong> open tickets</p>" >> "$OUTPUT_HTML"
echo "</body></html>" >> "$OUTPUT_HTML"

echo "Updated $OUTPUT_MD ($count open tickets)"
echo "Opening report..."
open "$OUTPUT_HTML"
