import logging

from fastapi import FastAPI
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from app.database import Base, engine
from app.rate_limit import limiter
from app.routers import auth, admin, investigations, alerts

# Import models so SQLAlchemy is aware of them (needed for relationships
# to resolve correctly, e.g. Investigation.alert). Table creation itself
# is no longer done here — that's Alembic's job now (see /alembic).
# Run `alembic upgrade head` to create/update tables instead of relying
# on the app to do it as a side effect of starting up.
from app import models, models_integration, models_alert, models_investigation, models_audit  # noqa: F401

logging.basicConfig(level=logging.INFO)

# Creates tables if they don't exist yet. Fine for early dev;
# switch to Alembic migrations once the schema starts changing often.
Base.metadata.create_all(bind=engine)

app = FastAPI(title="SOC Analyst Platform")

# Rate limiting setup — must happen before routers are included so every
# route is covered by the default limit from the moment it's registered.
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)

app.include_router(auth.router)
app.include_router(admin.router)
app.include_router(investigations.router)
app.include_router(alerts.router)

@app.get("/health")
def health():
    return {"status": "ok"}