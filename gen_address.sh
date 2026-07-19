  #!/usr/bin/env bash
  COUNT=10
  for _ in $(seq 1 "$COUNT"); do
    echo "0x$(openssl rand -hex 20)"
  done