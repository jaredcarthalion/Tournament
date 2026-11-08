from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import Base

def get_record(db: Session, model: type[Base], record_id: int):
    return db.get(model, record_id)

def get_records(db: Session, model: type[Base], order_by=None):
    statement = select(model)

    if order_by is not None:
        statement = statement.order_by(order_by)

    return db.scalars(statement).all()

def create_record(db: Session, model: type[Base], data: dict):
    record = model(**data)

    db.add(record)
    db.flush()
    db.refresh(record)

    return record

def update_record(db: Session, record, data: dict):
    for field, value in data.items():
        setattr(record, field, value)

    db.flush()
    db.refresh(record)

    return record

def delete_record(db: Session, record):
    db.delete(record)
    db.flush()