#!/bin/zsh
# Shows ESP-IDF install progress until it finishes.
LOG=/private/tmp/claude-501/-Users-atharv-CLAUDE-FOLDER/0d3de880-a7f6-4faf-823a-d709afd2717c/tasks/bkej7nn0e.output
cd ~/esp/esp-idf
while true; do
  clear
  echo "ESP-IDF install progress  ($(date +%H:%M:%S))"
  total=$(git config -f .gitmodules --get-regexp path | wc -l | tr -d ' ')
  done_n=$(git submodule status --recursive 2>/dev/null | grep -vc '^-')
  echo "Submodules ready: $done_n / $total"
  cur=$(pgrep -fl "git clone" | grep -o 'https://[^ ]*' | head -1)
  [ -n "$cur" ] && echo "Downloading: $cur  ($(du -sh .git/modules 2>/dev/null | cut -f1) so far)"
  pgrep -f "install.sh|idf_tools.py" >/dev/null && echo "Installing toolchain..."
  echo; tail -8 "$LOG" 2>/dev/null
  if ! pgrep -f "git submodule|git clone|install.sh|idf_tools.py" >/dev/null; then echo; echo "Done."; break; fi
  sleep 3
done
