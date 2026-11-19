#!/usr/bin/env bash
set -euo pipefail
url="${WHALEY_SERVER_URL:-http://127.0.0.1:9000}"
count() {
  docker compose exec -T db psql -U whaley -d whaley -tAc \
    "SELECT count(*) FROM page_load WHERE game_name = 'Gray Whale';" | tr -d '[:space:]'
}
curl -fsS "$url/health" >/dev/null
before="$(count)"
page="$(curl -fsS "$url/")"
[[ "$page" == *'id="game"'* ]] || { echo "Missing Canvas in Twirl page" >&2; exit 1; }
[[ "$page" == *'/assets/main.js'* ]] || { echo "Missing Scala.js module reference" >&2; exit 1; }
[[ "$page" == *'/assets/styles.css'* ]] || { echo "Missing CSS reference" >&2; exit 1; }
curl -fsS "$url/assets/main.js" >/dev/null || { echo "Missing linked Scala.js game" >&2; exit 1; }
curl -fsS "$url/assets/styles.css" >/dev/null
curl -fsS "$url/assets/player.png" >/dev/null
for asset in level1-568h.png level2-568h.png level3-568h.png level4-568h.png level5-568h.png level6-568h.png scanlines-568h.png A.mp3 B.mp3 bg01.mp3 knock.mp3 bounce01.wav coin01.wav flame01.wav goal01.wav jump01.wav pause01.wav; do
  curl -fsS "$url/assets/$asset" >/dev/null
done
curl -fsS "$url/" >/dev/null
after="$(count)"
[[ "$after" -eq "$((before + 2))" ]] || {
  echo "Expected exactly two new Whaley page loads: before=$before after=$after" >&2
  exit 1
}
echo "PASS: Twirl Canvas, Scala.js, CSS, paintings, audio and two recorded PostgreSQL page loads"
