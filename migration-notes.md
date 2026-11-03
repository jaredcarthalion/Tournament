## Code Reconnaissance

##TournamentUtils:
--createRandomRound, accepts tournament ID and creates round, games, and associates decks to games
--createbracketRound, accepts tournament ID and creates round, games, and associates decks to games
--speedPlayoff, creates round for tied tournament stat decks
--tieBreakerNeeded, determines if there are tied tournament stat records
--canNewRound, checks if current round is over in the tournament
--updateRankings, sets the rankings on the tournament itself from the stat records
--createStats, creates parent record to track points in the instance
--recalculatePoints, rolls up points from instances to stat record
--myGames, returns games current user is in
--tournamentDecks, either looks up decks in the tournament or looks up decks current user is pilot of
--getEditType, returns what type of edits should be processed, either resetting game or removing points
--currentTournament, returns the most recent tournament current user is in
--currentRound, returns the most recent round current user is in
--currentDeck, returns the most recent Deck current user is using
--createPoints loops through variables and creates point instances for multiple point instance inputs
--_lookUpDecks, looks up the current decks in the tournament
--_lookUpRounds, looks up the game composition in previous rounds
--_createGames, generates game records and associates decks to games according to arrays of deck ids
## Data Model
tournament user (app_user)
    id (primary key, unique)
    user_name (string, unique required)
    name (string, required)
deck (deck)
    id (primary key, unique)
    user_id (foreign key, required)
    name (string, required)
    decklist_url (string, nullable)
    created (timestamp, required)
deck to match (match_participant)
    id (primary key, unique)
    deck_id (foreign key, required)
    match_id (foreign key, required)
stat (tournament_entry)
    id (primary key, unique)
    deck_id (foreign key, required)
    tournament_id (foreign key, required)
    points (decimal, required default 0)
    opponent_match_win (decimal, required default 33.33 **Recalculate when opponents wins change)
    withdrawn (boolean, default false)
    created (timestamp, required)
point type (point_type)
    id (primary key, unique)
    active (boolean, default true)
    applies (Each tournament, Each match, Each game, Each instance | required)
    applies_to (One player, Multiple players | required)
    point_value (decimal, default 0)
    score_style (Achievements, Wins | required)
    title (string, required)
    description (string, required)
    created (timestamp, required)
point instance (point_instance)
    id (primary key, unique)
    game_id (foreign key, nullable)
    match_id (foreign key, nullable)
    stat_id (foreign key, required)
    point_type_id (foreign key, required)
    created (timestamp, required)
game (game)
    id (primary key, unique)
    status (Pending, Complete, Discarded | required)
    match_id (foreign key, required)
    winner_deck_to_match_id (foreign key, nullable)
    created (timestamp, required)
match (tournament_match)
    id (primary key, unique)
    active (boolean, default true)
    round_id (foreign key, required)
round (tournament_round)
    id (primary key, unique)
    active (boolean, default true)
    number (integer, required)
    tournament_id (foreign key, required)
tournament (tournament)
    id (primary key, unique)
    name (string, required)
    state (Pending, In progress, Complete | required)
    games_per_match (integer, required default 1)
    players_per_game (integer, required default 2)
    match_type (Ranked, Random | required)
    score_style (Achievements, Wins | required)
    limited (boolean, default false)
    created (timestamp, required)


-Tournament
    -Multiple Rounds
    -Multiple Stats
    -Multiple decks
    -Active or not
    -State
    -Created
    -Games per round
    -Limited
    -Match type
    -Name
    -Players per game
    -Score style
-Game
    -Multiple Decks
    -Multiple point instances
    -Active
    -Description
    -Draw
    -Round
    -Tournament
    -Winner
    -Created
-Point type
    -Active
    -Applies
    -Applies to
    -Created
    -Description
    -Point value
    -Score style
    -Title
-Point instance
    -Created
    -Deck
    -Game
    -Point type
    -Stat record
    -Tournament
-Round
    -Many games
    -Active
    -Tie breaker
    -Tournament
    -Number
-Stats
    -Created
    -Deck
    -Logs
    -Points
    -Tournament
    -Win percentage
-Deck
    -Many games
    -Many tournaments
    -Decklist link
    -Created
    -Player
    -Limited
    -Name
-User
    -Many Decks
    -Many Tournaments
    -Many Games
    -Name
    -Created
    -Auth
## Win Calc
Begin a database transaction.
Identify the affected match, game, and stat records.
Reactivate the match.
Remove all point instances associated with only the match.
Reopen only the corrected game, clearing its winner and draw status.
Remove all point instances associated with only that game.
Apply the newly submitted game result.
Recalculate the match outcome using all existing resolved game results, including games that weren't edited.
If the match is complete, mark it inactive and apply the appropriate match-level scoring.
Recalculate affected stats and commit the transaction.

-Two-player matches may end early when a player clinches the match.
Multiplayer matches always continue to the configured game limit.
The participant(s) with the most game wins determine the match outcome.
Participants tied for the highest win count draw.
Participants with fewer wins lose.
Each game and each match award points independently.

Before calculating percentages, tournament matches are converted to points:
• Match Points: A match win gives 3 points, a draw gives 1 point, and a loss gives 0 points.
• Game Points: An individual game win within a match gives 3 points, a draw gives 1 point, and a loss gives 0 points (e.g., winning a match 2-1 gives you 6 game points, and your opponent 3 game points).

The Three MTG Tiebreakers (In Order)


1. Opponents' Match-Win Percentage (OMW%)

This metric evaluates the difficulty of your schedule. It is the average match-win percentage of all your opponents.
• The Formula: \(\frac{\text{Sum\ of\ Opponents}^{\prime }\text{\ Match-Win\ Percentages}}{\text{Number\ of\ Opponents}}\)
• The 33% Floor Rule: If any opponent has a match-win percentage below 33% (0.33), their percentage is automatically boosted to 33% for your calculation. This prevents a player from being heavily penalized for playing against someone who dropped out early or had an uncharacteristically bad tournament.
• Byes: Byes do not have an opponent, so they are completely excluded from this calculation.

2. Game-Win Percentage (GW%)

If you and another player have the same match points and your opponents had identical average records, the software looks at your personal game-level performance.
• The Formula: \(\frac{\text{Your\ Total\ Game\ Points}}{\text{Total\ Possible\ Game\ Points}}\)
• Example: If you played 4 matches (all best-of-three), the maximum number of games you could have played is 12 (if every match went to 3 games). However, "Total Possible Game Points" is calculated as \(3 \times \text{actual games played}\). If you won two matches 2-0 and lost two matches 1-2, you played 10 games total. Your total possible game points would be 30.
• The 33% Floor Rule: Just like OMW%, your personal GW% cannot drop below 33%. If it does, it is treated as 33%.

3. Opponents' Game-Win Percentage (OGW%)

In the rare event that match points, OMW%, and GW% are all perfectly tied, the software falls back on the average game-win percentage of your opponents.
• The Formula: \(\frac{\text{Sum\ of\ Opponents}^{\prime }\text{\ Game-Win\ Percentages}}{\text{Number\ of\ Opponents}}\)
• The 33% Floor Rule: Every opponent's individual game-win percentage is subjected to the 33% floor before being averaged.
## Scoring
Game results determine individual game points.
Match outcomes are calculated from the game results and tournament format.
Match point instances reflect the current match outcome, not a history of every outcome the match has ever had.
Stats totals are recalculated or adjusted whenever the underlying scoring changes.
Corrections trigger reconciliation of the affected game, match, point instances, and stats.
Transactions ensure related changes succeed or fail together.
Cancellation is distinct from completion and does not automatically award match points.
## invariants
A tournament has one configuration that becomes locked when it starts.
A player can have at most one active deck entry per tournament.
A deck cannot be replaced after it has participated in a game.
Withdrawn entries retain their historical records but disappear from the active leaderboard.
Completed tournaments cannot be edited or reopened.
Match outcomes and aggregate scores must reconcile with corrected game results while the tournament is in progress.
While a tournament is Pending, its configuration and setup can be edited.
While a tournament is In progress, authorized users can record and correct results and point instances. Corrections trigger reconciliation of affected scores.
Once a tournament is Completed, all point instances and game results are locked. No corrections, additions, or deletions are permitted.
Only an administrator can transition a tournament from Pending to In progress.
The backend validates entry and setup requirements when the tournament starts.
Each limited-tournament entry receives a unique deck record.
Creating the limited deck and its corresponding stat record is one atomic operation.
Once a tournament is in progress, its configuration fields that you've designated as locked cannot be changed.