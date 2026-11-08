from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from typing import Literal

class UserCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str
    name: str
    password: str = Field(min_length=12)
    
class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    name: str

class UserUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str | None = None
    name: str | None = None


class DeckCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str
    user_id: int
    decklist_url: str | None = None

class DeckRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    user_id: int
    created: datetime
    decklist_url: str | None

class DeckUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = None
    decklist_url: str | None = None


class TournamentRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    state: str
    games_per_match: int
    players_per_game: int
    match_type: str
    score_style: str
    limited: bool
    created: datetime

class TournamentCreate(BaseModel):
    name: str
    games_per_match: int
    players_per_game: int
    match_type: Literal["Ranked", "Random"]
    score_style: Literal["Wins", "Achievements"]
    limited: bool

class TournamentUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = None
    games_per_match: int | None = None
    players_per_game: int | None = None
    match_type: Literal["Ranked", "Random"] | None = None
    score_style: Literal["Wins", "Achievements"] | None = None
    limited: bool | None = None


class EntryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tournament_id: int
    user_id: int
    deck_id: int

class EntryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    tournament_id: int
    user_id: int
    deck_id: int
    created: datetime

class EntryUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    withdrawn: bool


class RoundCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tournament_id: int
    number: int


class RoundRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    tournament_id: int
    number: int
    active: bool


class RoundUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    active: bool


class MatchRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    round_id: int
    active: bool


class GameRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    match_id: int
    status: Literal["Pending", "Complete", "Discarded"] | None = None
    winner_match_participant_id: int | None
    created: datetime


class ParticipantRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    match_id: int | None
    tournament_entry_id: int


class PointTypeCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str
    description: str
    active: bool = True
    applies: Literal["Each instance", "Each game", "Each match", "Each tournament"] = "Each instance"
    applies_to: Literal["One player", "Multiple players"] = "One player"
    point_value: int = Field(default=0, ge=0)
    score_style: Literal["Wins", "Achievements"] = "Wins"

class PointTypeRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    active: bool
    applies: Literal["Each instance", "Each game", "Each match", "Each tournament"]
    applies_to: Literal["One player", "Multiple players"]
    point_value: int
    score_style: Literal["Wins", "Achievements"]
    title: str
    description: str
    created: datetime

class PointTypeUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    active: bool | None = None
    applies: Literal["Each instance", "Each game", "Each match", "Each tournament"] | None = None
    applies_to: Literal["One player", "Multiple players"] | None = None
    point_value: int | None = Field(default=None, ge=0)
    score_style: Literal["Wins", "Achievements"] | None = None
    title: str | None = None
    description: str | None = None


class PointInstanceCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    point_type_id: int
    game_id: int | None = None
    match_id: int | None = None
    tournament_entry_id: int
    point_value_override: int | None = Field(default=None, ge=0)

class PointInstanceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    point_type_id: int
    game_id: int | None
    match_id: int | None
    tournament_entry_id: int
    point_value_override: int | None
    created: datetime

class PointInstanceUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    point_value_override: int | None = Field(default=None, ge=0)