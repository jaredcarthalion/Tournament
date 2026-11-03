BEGIN;

-- Create fixture users.
INSERT INTO app_user (name, username)
VALUES
    ('Player 01', 'fixture_player_01'),
    ('Player 02', 'fixture_player_02'),
    ('Player 03', 'fixture_player_03'),
    ('Player 04', 'fixture_player_04'),
    ('Player 05', 'fixture_player_05'),
    ('Player 06', 'fixture_player_06'),
    ('Player 07', 'fixture_player_07'),
    ('Player 08', 'fixture_player_08'),
    ('Player 09', 'fixture_player_09'),
    ('Player 10', 'fixture_player_10'),
    ('Player 11', 'fixture_player_11'),
    ('Player 12', 'fixture_player_12'),
    ('Player 13', 'fixture_player_13'),
    ('Player 14', 'fixture_player_14');

-- Create two fixture decks for each user.
INSERT INTO deck (user_id, name, decklist_url)
SELECT
    u.id,
    d.deck_name,
    d.decklist_url
FROM app_user AS u
CROSS JOIN (
    VALUES
        ('Primary Deck', 'https://www.moxfield.com/'),
        ('Secondary Deck', 'https://www.archidekt.com/')
) AS d(deck_name, decklist_url)
WHERE u.username LIKE 'fixture_player_%';

-- Create fixture point types.
INSERT INTO point_type (
    active,
    applies,
    applies_to,
    point_value,
    score_style,
    title,
    description
)
VALUES
    (
        TRUE,
        'Each instance',
        'Multiple players',
        1.0,
        'Achievements',
        'Destroy Sol Ring',
        'Repeatable award for testing individual achievement scoring.'
    ),
    (
        TRUE,
        'Each game',
        'One player',
        3.0,
        'Wins',
        'Game Winner',
        'Awarded to the winner of an individual game.'
    ),
    (
        TRUE,
        'Each game',
        'Multiple players',
        1.0,
        'Wins',
        'Game Draw',
        'Awarded when a game ends in a draw.'
    ),
    (
        TRUE,
        'Each game',
        'Multiple players',
        0.0,
        'Wins',
        'Game Loss',
        'Awarded when a game ends in a loss.'
    ),
    (
        TRUE,
        'Each game',
        'Multiple players',
        3.0,
        'Achievements',
        'Have fun',
        'Harm no players.'
    ),
    (
        TRUE,
        'Each game',
        'One player',
        3.0,
        'Achievements',
        'Wipeout',
        'Kill table.'
    ),
    (
        TRUE,
        'Each match',
        'One player',
        3.0,
        'Wins',
        'Match Win',
        'Awarded once to the winner of a match.'
    ),
    (
        TRUE,
        'Each match',
        'Multiple players',
        1.0,
        'Wins',
        'Match Draw',
        'Awarded when a match ends in a draw.'
    ),
    (
        TRUE,
        'Each match',
        'Multiple players',
        0.0,
        'Wins',
        'Match Loss',
        'Awarded when losing a match.'
    ),
    (
        TRUE,
        'Each match',
        'Multiple players',
        1.0,
        'Achievements',
        'Match Participation',
        'Awarded separately to individual match participants.'
    ),
    (
        TRUE,
        'Each match',
        'One player',
        1.0,
        'Achievements',
        'Match Best',
        'Awarded for being the very best.'
    ),
    (
        TRUE,
        'Each tournament',
        'One player',
        10.0,
        'Achievements',
        'The Cheapskate Award',
        'Awarded once for entering with cheapest deck.'
    ),
    (
        TRUE,
        'Each tournament',
        'Multiple players',
        2.0,
        'Achievements',
        'Tournament Sportsmanship',
        'Awarded separately to individual tournament participants.'
    );

-- Create fixture tournaments.
INSERT INTO tournament (
    name,
    state,
    games_per_match,
    players_per_game,
    match_type,
    score_style,
    limited
)
VALUES
    (
        'Fixture - Pending',
        'Pending',
        1,
        4,
        'Random',
        'Achievements',
        FALSE
    ),
    (
        'Fixture - In Progress',
        'In progress',
        1,
        4,
        'Random',
        'Achievements',
        FALSE
    ),
    (
        'Fixture - Limited In Progress',
        'In progress',
        3,
        2,
        'Ranked',
        'Wins',
        TRUE
    ),
    (
        'Fixture - Limited',
        'Pending',
        3,
        2,
        'Ranked',
        'Wins',
        TRUE
    );

    -- Create entries for the nonlimited in-progress tournament.
INSERT INTO tournament_entry (
    deck_id,
    tournament_id
)
SELECT
    d.id,
    t.id
FROM app_user AS u
JOIN deck AS d
    ON d.user_id = u.id
    AND d.name = 'Primary Deck'
JOIN tournament AS t
    ON t.name = 'Fixture - In Progress'
WHERE u.username LIKE 'fixture_player_%';

-- Create limited decks and tournament entries.
WITH target_tournament AS (
    SELECT id
    FROM tournament
    WHERE name = 'Fixture - Limited In Progress'
),
new_limited_decks AS (
    INSERT INTO deck (
        user_id,
        name,
        decklist_url
    )
    SELECT
        u.id,
        'Limited Deck - ' || u.username,
        NULL
    FROM app_user AS u
    WHERE u.username LIKE 'fixture_player_%'
    RETURNING id, user_id
)
INSERT INTO tournament_entry (
    deck_id,
    tournament_id
)
SELECT
    d.id,
    t.id
FROM new_limited_decks AS d
CROSS JOIN target_tournament AS t;

-- Create the first round for each in-progress tournament.
INSERT INTO tournament_round (
    tournament_id,
    number
)
SELECT
    id,
    1
FROM tournament
WHERE name IN (
    'Fixture - In Progress',
    'Fixture - Limited In Progress'
)
AND state = 'In progress'
ON CONFLICT (tournament_id, number) DO NOTHING;

DO $$
DECLARE
    tournament_record RECORD;
    participant_record RECORD;
    new_match_id BIGINT;
    participant_count INTEGER;
BEGIN
    FOR tournament_record IN
        SELECT
            t.id AS tournament_id,
            r.id AS round_id,
            t.players_per_game
        FROM tournament AS t
        JOIN tournament_round AS r
            ON r.tournament_id = t.id
            AND r.number = 1
        WHERE t.name IN (
            'Fixture - In Progress',
            'Fixture - Limited In Progress'
        )
        ORDER BY t.name
    LOOP
        participant_count := 0;
        new_match_id := NULL;

        FOR participant_record IN
            SELECT te.id AS tournament_entry_id
            FROM tournament_entry AS te
            JOIN deck AS d
                ON d.id = te.deck_id
            JOIN app_user AS u
                ON u.id = d.user_id
            WHERE te.tournament_id = tournament_record.tournament_id
              AND te.withdrawn = FALSE
            ORDER BY u.username
        LOOP
            -- Create a match when starting a new group.
            IF participant_count % tournament_record.players_per_game = 0 THEN
                INSERT INTO tournament_match (round_id)
                VALUES (tournament_record.round_id)
                RETURNING id INTO new_match_id;
            END IF;

            -- Assign the participant to the newly created match.
            INSERT INTO match_participant (
                match_id,
                tournament_entry_id
            )
            VALUES (
                new_match_id,
                participant_record.tournament_entry_id
            );

            participant_count := participant_count + 1;
        END LOOP;
    END LOOP;
END $$;

-- Create the first game for each non-bye match.
INSERT INTO game (
    match_id,
    status
)
SELECT
    tm.id,
    'Pending'
FROM tournament_match AS tm
JOIN tournament_round AS r
    ON r.id = tm.round_id
JOIN tournament AS t
    ON t.id = r.tournament_id
JOIN match_participant AS mp
    ON mp.match_id = tm.id
WHERE t.name IN (
    'Fixture - In Progress',
    'Fixture - Limited In Progress'
)
GROUP BY
    tm.id,
    t.players_per_game
HAVING COUNT(mp.id) = t.players_per_game
AND NOT EXISTS (
    SELECT 1
    FROM game AS g
    WHERE g.match_id = tm.id
);

COMMIT;