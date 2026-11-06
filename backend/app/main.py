from fastapi import Depends, FastAPI, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Tournament
from app.schemas import TournamentRead, TournamentCreate, TournamentUpdate


app = FastAPI()


@app.get("/tournaments", response_model=list[TournamentRead])
def get_tournaments(db: Session = Depends(get_db)):
    statement = select(Tournament).order_by(Tournament.id)

    tournaments = db.scalars(statement).all()

    return tournaments

@app.get("/tournaments/{tournament_id}", response_model=TournamentRead)
def get_tournament(tournament_id: int, db: Session = Depends(get_db)):
    statement = select(Tournament).where(Tournament.id == tournament_id)
    tournament = db.scalar(statement)
    if tournament is None:
        raise HTTPException(status_code=404, detail="Tournament not found")
    return tournament

@app.post("/tournaments", response_model=TournamentRead, status_code=201)
def create_tournament(
    tournament: TournamentCreate,
    db: Session = Depends(get_db),
):
    new_tournament = Tournament(
        name=tournament.name,
        games_per_match=tournament.games_per_match,
        players_per_game=tournament.players_per_game,
        match_type=tournament.match_type,
        score_style=tournament.score_style,
        limited=tournament.limited,
    )

    db.add(new_tournament)
    db.commit()
    db.refresh(new_tournament)

    return new_tournament

@app.patch("/tournaments/{tournament_id}", response_model=TournamentRead)
def update_tournament(
    tournament_id: int,
    tournament: TournamentUpdate,
    db: Session = Depends(get_db)
):
    statement = select(Tournament).where(Tournament.id == tournament_id)
    existing_tournament = db.scalar(statement)

    if existing_tournament is None:
        raise HTTPException(status_code=404, detail="Tournament not found")

    updates = tournament.model_dump(exclude_unset=True)

    if not updates:
        raise HTTPException(status_code=422, detail="No fields provided for update")

    if any(value is None for value in updates.values()):
        raise HTTPException(status_code=422, detail="Null values are not allowed for update")

    if existing_tournament.state == "Complete":
        raise HTTPException(status_code=409, detail="Cannot update fields of a completed tournament")

    locked_fields = {
        "games_per_match",
        "players_per_game",
        "match_type",
        "score_style",
        "limited",
    }

    if any(field in locked_fields for field in updates) and existing_tournament.state != "Pending":
        raise HTTPException(status_code=409, detail="Cannot update locked fields of a non-pending tournament")

    for field, value in updates.items():
        setattr(existing_tournament, field, value)

    db.commit()
    db.refresh(existing_tournament)

    return existing_tournament