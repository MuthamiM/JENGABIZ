from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    PROJECT_NAME: str = "Duka Ledger API"
    ENVIRONMENT: str = "development"
    DATABASE_URL: str = "postgresql+asyncpg://dukaledger:dukapassword123@localhost:5432/duka_ledger_db"
    REDIS_URL: str = "redis://localhost:6379/0"
    SECRET_KEY: str = "duka-super-secret-jwt-key-for-scalability-2026"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 43200  # 30 days
    RATE_LIMIT_PER_MINUTE: int = 120
    SMS_PROVIDER_API_KEY: Optional[str] = "mock_key"

    class Config:
        env_file = ".env"
        extra = "allow"

settings = Settings()
