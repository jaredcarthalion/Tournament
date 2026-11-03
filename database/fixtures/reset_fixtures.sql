BEGIN;

TRUNCATE TABLE
    point_instance,
    game,
    match_participant,
    tournament_match,
    tournament_round,
    tournament_entry,
    deck,
    tournament,
    point_type,
    app_user
RESTART IDENTITY;

COMMIT;