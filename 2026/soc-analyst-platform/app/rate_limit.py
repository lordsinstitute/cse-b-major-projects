from slowapi import Limiter
from slowapi.util import get_remote_address

# Keyed by client IP address. In production behind a reverse proxy
# (Render, nginx, etc.), make sure X-Forwarded-For is trusted correctly
# or every request will appear to come from the proxy's IP.
#
# default_limits applies to EVERY route automatically unless overridden
# with an explicit @limiter.limit(...) decorator on that route.
limiter = Limiter(key_func=get_remote_address, default_limits=["100/minute"])