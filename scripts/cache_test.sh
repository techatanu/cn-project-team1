#!/bin/bash
# Caching check: shows cache headers, then a conditional request that should return 304.
URL=https://app.team1.test/api/info
/usr/bin/curl -sI "$URL" | grep -iE '^(HTTP|x-backend|cache-control|etag)'
ETAG=$(/usr/bin/curl -sI "$URL" | grep -i '^etag' | awk '{print $2}' | tr -d '\r')
echo "--- conditional request with If-None-Match: $ETAG"
/usr/bin/curl -s -i -H "If-None-Match: $ETAG" "$URL" | grep -iE '^(HTTP|x-backend|cache-control|etag)'
