import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    secret_key: str = os.getenv("SECRET_KEY", "")
    algorithm: str = os.getenv("ALGORITHM", "HS256")
    access_token_expire_minutes: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 15))
    refresh_token_expire_days: int = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", 7))
    database_url: str = os.getenv("DATABASE_URL", "sqlite:///./dev.db")
    encryption_key: str = os.getenv("ENCRYPTION_KEY", "")

    class Config:
     env_file = ".env"
     extra = "ignore"


settings = Settings()

if not settings.secret_key:
    raise RuntimeError(
        "SECRET_KEY is not set. Copy .env.example to .env and fill it in."
    )