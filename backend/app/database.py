
import os
from pathlib import Path
from collections.abc import Generator

from dotenv import load_dotenv
from sqlalchemy import URL, create_engine, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker


# Load environment variables from backend/.env
ENV_FILE = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(ENV_FILE)


# Retrieve database configuration
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")


# Verify required configuration exists
required_settings = {
    "DB_HOST": DB_HOST,
    "DB_PORT": DB_PORT,
    "DB_NAME": DB_NAME,
    "DB_USER": DB_USER,
    "DB_PASSWORD": DB_PASSWORD,
}

missing_settings = [
    name for name, value in required_settings.items() if not value
]

if missing_settings:
    raise RuntimeError(
        f"Missing database configuration: {', '.join(missing_settings)}"
    )


# Create the PostgreSQL connection URL
DATABASE_URL = URL.create(
    drivername="postgresql+psycopg",
    username=DB_USER,
    password=DB_PASSWORD,
    host=DB_HOST,
    port=int(DB_PORT),
    database=DB_NAME,
)


# Create the SQLAlchemy engine
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
)


# Create a reusable database session factory
SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
)


# Base class for future SQLAlchemy models
class Base(DeclarativeBase):
    pass


# Provide database sessions to FastAPI endpoints
def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()

    try:
        yield db
    finally:
        db.close()


