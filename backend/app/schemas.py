from datetime import datetime

from pydantic import BaseModel, ConfigDict

from typing import Literal


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