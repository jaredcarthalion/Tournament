from sqlalchemy import BigInteger, Boolean, DateTime, Integer, String, text
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

from datetime import datetime

class Tournament(Base):
    __tablename__ = "tournament"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    state: Mapped[str] = mapped_column(String, nullable=False, server_default=text("'Pending'"))
    games_per_match: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("1"))
    players_per_game: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("2"))
    match_type: Mapped[str] = mapped_column(String, nullable=False, server_default=text("'Ranked'"))
    score_style: Mapped[str] = mapped_column(String, nullable=False, server_default=text("'Wins'"))
    limited: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("FALSE"))
    created: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP"))