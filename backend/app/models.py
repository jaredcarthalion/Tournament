from sqlalchemy import BigInteger, Boolean, DateTime, Integer, String, text
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

from datetime import datetime

class User(Base):
    __tablename__ = "app_user"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    username: Mapped[str] = mapped_column(String, nullable=False, unique=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    role: Mapped[str] = mapped_column(String(20), nullable=False, server_default=text("'Player'"))
    password_hash: Mapped[str] = mapped_column(String, nullable=False)

class Deck(Base):
    __tablename__ = "deck"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    user_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    created: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP"))
    decklist_url: Mapped[str | None] = mapped_column(String)
   
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

class Entry(Base):
    __tablename__ = "tournament_entry"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    tournament_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    deck_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    points: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("0"))
    opponent_match_wins: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("33.33"))
    withdrawn: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("FALSE"))
    created: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP"))

class Round(Base):
    __tablename__ = "tournament_round"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    tournament_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    number: Mapped[int] = mapped_column(Integer, nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("TRUE"))

class Match(Base):
    __tablename__ = "tournament_match"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    round_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("TRUE"))

class Game(Base):
    __tablename__ = "game"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    match_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False, server_default=text("'Pending'"))
    winner_match_participant_id: Mapped[int | None] = mapped_column(BigInteger)
    created: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP"))

class Participant(Base):
    __tablename__ = "match_participant"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    match_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    tournament_entry_id: Mapped[int] = mapped_column(BigInteger, nullable=False)

class PointType(Base):
    __tablename__ = "point_type"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("TRUE"))
    applies: Mapped[str] = mapped_column(String, nullable=False,server_default=text("'Each instance'"))
    applies_to: Mapped[str] = mapped_column(String, nullable=False, server_default=text("'One player'"))
    point_value: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("0"))
    score_style: Mapped[str] = mapped_column(String, nullable=False, server_default=text("'Wins'"))
    title: Mapped[str] = mapped_column(String, nullable=False)
    description: Mapped[str] = mapped_column(String, nullable=False)
    created: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP"))

class PointInstance(Base):
    __tablename__ = "point_instance"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    point_type_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    game_id: Mapped[int | None] = mapped_column(BigInteger)
    match_id: Mapped[int | None] = mapped_column(BigInteger)
    tournament_entry_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    point_value_override: Mapped[int | None] = mapped_column(Integer)
    created: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP"))