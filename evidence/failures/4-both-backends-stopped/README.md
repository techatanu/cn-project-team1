# Both backends stopped
To add: curl -v shows DNS + TLS still succeed, then HTTP/2 502 Bad Gateway with no X-Backend; error.log connect() failed for both upstreams.
Related unplanned observation already in mac2 logs (2 Oct 23:52): Mac 3 unreachable → upstream timed out → 504 Gateway Timeout.
