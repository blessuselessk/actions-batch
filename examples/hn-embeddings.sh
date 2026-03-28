#!/bin/bash

set -e -x -o pipefail

sudo apt update -qqqy
sudo apt install -qqqy --no-install-recommends jq

# Download llamafile
curl -Lo llamafile https://github.com/mozilla-ai/llamafile/releases/download/0.10.0/llamafile-0.10.0
chmod +x llamafile

# Download embedding model (~146MB, Q8_0 for quality)
curl -Lo model.gguf https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q8_0.gguf

# Start embedding server
./llamafile --server --embedding --model model.gguf --host 127.0.0.1 --port 8080 &
SERVER_PID=$!

# Wait for server to be ready
for i in $(seq 1 60); do
  if curl -sf http://127.0.0.1:8080/health > /dev/null 2>&1; then
    echo "Server ready"
    break
  fi
  sleep 1
done

# Fetch top 20 HN story IDs
STORY_IDS=$(curl -s https://hacker-news.firebaseio.com/v0/topstories.json | jq '.[0:20][]')

mkdir -p uploads

for id in $STORY_IDS; do
  STORY=$(curl -s "https://hacker-news.firebaseio.com/v0/item/${id}.json")
  TITLE=$(echo "$STORY" | jq -r '.title // empty')
  URL=$(echo "$STORY" | jq -r '.url // empty')
  SCORE=$(echo "$STORY" | jq -r '.score // 0')

  if [ -z "$TITLE" ]; then
    continue
  fi

  # nomic-embed-text-v1.5 uses "search_document: " prefix for indexing
  REQUEST=$(jq -n --arg text "search_document: $TITLE" '{"content": $text}')

  EMBEDDING=$(curl -s http://127.0.0.1:8080/embedding \
    -H "Content-Type: application/json" \
    -d "$REQUEST" | jq '.embedding')

  jq -n \
    --argjson id "$id" \
    --arg title "$TITLE" \
    --arg url "$URL" \
    --argjson score "$SCORE" \
    --argjson embedding "$EMBEDDING" \
    '{id: $id, title: $title, url: $url, score: $score, embedding: $embedding}' \
    >> uploads/embeddings.jsonl

  echo "Embedded: $TITLE"
done

kill $SERVER_PID || true

COUNT=$(wc -l < uploads/embeddings.jsonl)
DIM=$(head -1 uploads/embeddings.jsonl | jq '.embedding | length')
echo ""
echo "Done: $COUNT stories, ${DIM}-dimensional embeddings"
echo "Output: uploads/embeddings.jsonl"
