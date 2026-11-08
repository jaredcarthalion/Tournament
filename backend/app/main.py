from fastapi import Depends, FastAPI, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.crud import get_record, get_records, create_record, update_record, delete_record
from app.models import User, Deck, PointType, PointInstance, Tournament, Entry
from app.schemas import TournamentRead, TournamentCreate, TournamentUpdate


DELETEABLE_MODELS = {
    "tournaments": Tournament,
    "entries": Entry,
    "users": User,
    "decks": Deck,
    "point-types": PointType,
    "point-instances": PointInstance
}


app = FastAPI()


@app.get("/tournaments", response_model=list[TournamentRead])
def get_tournaments(db: Session = Depends(get_db)):
    return get_records(db, Tournament, Tournament.id)

@app.get("/tournaments/{tournament_id}", response_model=TournamentRead)
def get_tournament(tournament_id: int, db: Session = Depends(get_db)):
    tournament = get_record(db, Tournament, tournament_id)
    if tournament is None:
        raise HTTPException(status_code=404, detail="Tournament not found")
    return tournament

@app.post("/tournaments", response_model=TournamentRead, status_code=201)
def create_tournament(
    tournament: TournamentCreate,
    db: Session = Depends(get_db),
):
    new_tournament = create_record(
        db,
        Tournament,
        tournament.model_dump()
    )
    db.commit()
    return new_tournament

@app.patch("/tournaments/{tournament_id}", response_model=TournamentRead)
def update_tournament(
    tournament_id: int,
    tournament: TournamentUpdate,
    db: Session = Depends(get_db)
):
    existing_tournament = get_record(db, Tournament, tournament_id)

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

    update_record(db, existing_tournament, updates)
    db.commit()
    return existing_tournament

@app.delete("/admin/delete/{resource}/{record_id}", status_code=204)
def delete_resource(
    resource: str,
    record_id: int,
    db: Session = Depends(get_db),
):
    model = DELETEABLE_MODELS.get(resource)

    if model is None:
        raise HTTPException(
            status_code=404,
            detail="Resource not found or deletion not permitted"
        )

    record = get_record(db, model, record_id)

    if record is None:
        raise HTTPException(
            status_code=404,
            detail="Record not found"
        )

    delete_record(db, record)
    db.commit()