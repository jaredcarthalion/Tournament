--
-- PostgreSQL database dump
--

\restrict JeFAQunsx7ZhRZbXWZV8m0U9Wu4cC959dO4s4lRFO4cvljKvYoiDHgCvYdzx789

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

-- Started on 2026-11-03 09:28:57

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 241 (class 1255 OID 16640)
-- Name: ensure_tournament_consistency(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.ensure_tournament_consistency() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
entry_tournament_id BIGINT;
match_tournament_id BIGINT;
participant_withdrawn BOOLEAN;
BEGIN
SELECT tournament_entry.tournament_id, tournament_entry.withdrawn
INTO entry_tournament_id, participant_withdrawn
FROM tournament_entry
WHERE id = NEW.tournament_entry_id;
IF participant_withdrawn
THEN RAISE EXCEPTION 'Withdrawn tournament entries cannot be assigned to new matches.';
END IF;
SELECT tournament_round.tournament_id
INTO match_tournament_id
FROM tournament_round
JOIN tournament_match
	ON tournament_match.round_id = tournament_round.id
WHERE tournament_match.id = NEW.match_id;

IF match_tournament_id IS DISTINCT FROM entry_tournament_id
THEN RAISE EXCEPTION 'Tournament consistency violation: participant entry and match must belong to the same tournament.';
END IF;
RETURN NEW;
END;
$$;


ALTER FUNCTION public.ensure_tournament_consistency() OWNER TO postgres;

--
-- TOC entry 242 (class 1255 OID 16641)
-- Name: normalize_username(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.normalize_username() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
NEW.username := LOWER(NEW.username);
RETURN NEW;
END;
$$;


ALTER FUNCTION public.normalize_username() OWNER TO postgres;

--
-- TOC entry 243 (class 1255 OID 16642)
-- Name: prevent_relationship_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.prevent_relationship_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
old_value TEXT;
new_value TEXT;
BEGIN
old_value := to_jsonb(OLD) ->> TG_ARGV[0];
new_value := to_jsonb(NEW) ->> TG_ARGV[0];
IF new_value IS DISTINCT FROM old_value
THEN RAISE EXCEPTION 'The value of % on table % cannot be changed.', TG_ARGV[0], TG_TABLE_NAME;
END IF;
RETURN NEW;
END;
$$;


ALTER FUNCTION public.prevent_relationship_change() OWNER TO postgres;

--
-- TOC entry 255 (class 1255 OID 16643)
-- Name: validate_point_instance_uniqueness(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_point_instance_uniqueness() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	active BOOLEAN;
    applies VARCHAR(20);
    applies_to VARCHAR(20);
	score_style VARCHAR(20);
	tournament_score_style VARCHAR(20);
    duplicate_id BIGINT;
    current_tournament_id BIGINT;
    lock_scope_id BIGINT;
    lock_key_text TEXT;
BEGIN
	SELECT pt.active, pt.applies, pt.applies_to, pt.score_style
	INTO active, applies, applies_to, score_style
	FROM point_type AS pt
	WHERE pt.id = NEW.point_type_id;

	IF NOT FOUND THEN
	    RAISE EXCEPTION 'Invalid point type.';
	END IF;

	IF NOT active THEN
	    RAISE EXCEPTION 'This point type is inactive.';
	END IF;

    IF applies IS NULL
       OR applies NOT IN ('Each instance', 'Each game', 'Each match', 'Each tournament')
       OR applies_to IS NULL
       OR applies_to NOT IN ('One player', 'Multiple players') THEN
        RAISE EXCEPTION 'Invalid point type configuration.';
    END IF;

    -- Each instance: require a game, then validate participation.
    IF applies = 'Each instance' THEN
        IF NEW.game_id IS NULL THEN
            RAISE EXCEPTION 'This point type requires a game id.';
        END IF;
    END IF;

    -- Find the tournament belonging to this entry.
    SELECT te.tournament_id 
    INTO current_tournament_id
    FROM tournament_entry AS te
    WHERE te.id = NEW.tournament_entry_id;

    IF current_tournament_id IS NULL THEN
        RAISE EXCEPTION 'Invalid tournament entry.';
    END IF;

	-- Validate score style.
	SELECT t.score_style
	INTO tournament_score_style
	FROM tournament AS t
	WHERE t.id = current_tournament_id;
	IF tournament_score_style IS DISTINCT FROM score_style THEN
		RAISE EXCEPTION
			'Score styles must match.';
	END IF;

    -- Validate which references are required or forbidden.
    IF applies = 'Each tournament' THEN
        IF NEW.game_id IS NOT NULL OR NEW.match_id IS NOT NULL THEN
            RAISE EXCEPTION
                'Tournament points cannot reference a game or match.';
        END IF;
    ELSIF applies = 'Each game' THEN
        IF NEW.game_id IS NULL THEN
            RAISE EXCEPTION 'This point type requires a game id.';
        END IF;
    ELSIF applies = 'Each match' THEN
        IF NEW.match_id IS NULL THEN
            RAISE EXCEPTION 'This point type requires a match id.';
        END IF;
    END IF;

-- Confirm the entry participated in the referenced game
-- and belongs to the same tournament.
IF NEW.game_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM game AS g
    JOIN tournament_match AS tm
      ON tm.id = g.match_id
    JOIN tournament_round AS tr
      ON tr.id = tm.round_id
    JOIN tournament_entry AS te
      ON te.tournament_id = tr.tournament_id
    JOIN match_participant AS mp
      ON mp.match_id = tm.id
     AND mp.tournament_entry_id = te.id
    WHERE g.id = NEW.game_id
      AND te.id = NEW.tournament_entry_id
) THEN
    RAISE EXCEPTION
        'Tournament entry did not participate in this game or belongs to a different tournament.';
END IF;

-- Confirm the entry participated in the referenced match
-- and belongs to the same tournament.
IF NEW.match_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM match_participant AS mp
    JOIN tournament_match AS tm
      ON tm.id = mp.match_id
    JOIN tournament_round AS tr
      ON tr.id = tm.round_id
    JOIN tournament_entry AS te
      ON te.id = mp.tournament_entry_id
     AND te.tournament_id = tr.tournament_id
    WHERE mp.match_id = NEW.match_id
      AND mp.tournament_entry_id = NEW.tournament_entry_id
) THEN
    RAISE EXCEPTION
        'Tournament entry did not participate in this match or belongs to a different tournament.';
END IF;

	IF NEW.point_value_override IS NOT NULL THEN
    	RETURN NEW;
	END IF;

    -- Determine the scope used to coordinate concurrent awards.
    IF applies = 'Each game' THEN
        lock_scope_id := NEW.game_id;
    ELSIF applies = 'Each match' THEN
        lock_scope_id := NEW.match_id;
    ELSIF applies = 'Each tournament' THEN
        lock_scope_id := current_tournament_id;
    ELSE
        -- Each instance has no uniqueness restriction.
        RETURN NEW;
    END IF;

    lock_key_text :=
        applies || ':' || NEW.point_type_id || ':' || lock_scope_id;

    IF applies_to = 'Multiple players' THEN
        lock_key_text :=
            lock_key_text || ':' || NEW.tournament_entry_id;
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(lock_key_text, 0)
    );

    -- Check whether this award already exists in its allowed scope.
    IF applies = 'Each game' THEN
        IF applies_to = 'One player' THEN
            SELECT pi.id
            INTO duplicate_id
            FROM point_instance AS pi
            WHERE pi.point_type_id = NEW.point_type_id
              AND pi.game_id = NEW.game_id
			  AND pi.point_value_override IS NULL;
        ELSE
            SELECT pi.id
            INTO duplicate_id
            FROM point_instance AS pi
            WHERE pi.point_type_id = NEW.point_type_id
              AND pi.game_id = NEW.game_id
              AND pi.tournament_entry_id = NEW.tournament_entry_id
			  AND pi.point_value_override IS NULL;
        END IF;

    ELSIF applies = 'Each match' THEN
        IF applies_to = 'One player' THEN
            SELECT pi.id
            INTO duplicate_id
            FROM point_instance AS pi
            WHERE pi.point_type_id = NEW.point_type_id
              AND pi.match_id = NEW.match_id
			  AND pi.point_value_override IS NULL;
        ELSE
            SELECT pi.id
            INTO duplicate_id
            FROM point_instance AS pi
            WHERE pi.point_type_id = NEW.point_type_id
              AND pi.match_id = NEW.match_id
              AND pi.tournament_entry_id = NEW.tournament_entry_id
			  AND pi.point_value_override IS NULL;
        END IF;

    ELSIF applies = 'Each tournament' THEN
        IF applies_to = 'One player' THEN
            SELECT pi.id
            INTO duplicate_id
            FROM point_instance AS pi
            JOIN tournament_entry AS te
              ON te.id = pi.tournament_entry_id
            WHERE pi.point_type_id = NEW.point_type_id
              AND te.tournament_id = current_tournament_id
			  AND pi.point_value_override IS NULL;
        ELSE
            SELECT pi.id
            INTO duplicate_id
            FROM point_instance AS pi
            WHERE pi.point_type_id = NEW.point_type_id
              AND pi.tournament_entry_id = NEW.tournament_entry_id
			  AND pi.point_value_override IS NULL;
        END IF;
    END IF;

    IF duplicate_id IS NOT NULL THEN
        RAISE EXCEPTION
            'This point type has already been awarded within its allowed scope.';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validate_point_instance_uniqueness() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 221 (class 1259 OID 16644)
-- Name: app_user; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.app_user (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    username character varying(50) NOT NULL,
    CONSTRAINT username_must_be_lowercase CHECK (((username)::text = lower((username)::text)))
);


ALTER TABLE public.app_user OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 16651)
-- Name: app_user_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.app_user ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.app_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 223 (class 1259 OID 16652)
-- Name: deck; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.deck (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    name character varying(100) NOT NULL,
    decklist_url text,
    created timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.deck OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 16662)
-- Name: deck_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.deck ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.deck_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 225 (class 1259 OID 16663)
-- Name: game; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.game (
    id bigint NOT NULL,
    status character varying(20) DEFAULT 'Pending'::character varying NOT NULL,
    match_id bigint NOT NULL,
    winner_match_participant_id bigint,
    created timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_game_result CHECK (((((status)::text = 'Pending'::text) AND (winner_match_participant_id IS NULL)) OR ((status)::text = 'Complete'::text) OR (((status)::text = 'Discarded'::text) AND (winner_match_participant_id IS NULL)))),
    CONSTRAINT valid_game_status CHECK (((status)::text = ANY (ARRAY[('Pending'::character varying)::text, ('Complete'::character varying)::text, ('Discarded'::character varying)::text])))
);


ALTER TABLE public.game OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 16674)
-- Name: game_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.game ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.game_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 227 (class 1259 OID 16675)
-- Name: match_participant; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.match_participant (
    id bigint NOT NULL,
    match_id bigint NOT NULL,
    tournament_entry_id bigint NOT NULL
);


ALTER TABLE public.match_participant OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 16681)
-- Name: match_participant_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.match_participant ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.match_participant_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 229 (class 1259 OID 16682)
-- Name: point_instance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.point_instance (
    id bigint NOT NULL,
    game_id bigint,
    match_id bigint,
    tournament_entry_id bigint NOT NULL,
    point_type_id bigint NOT NULL,
    created timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    point_value_override numeric(5,1),
    CONSTRAINT nonnegative_point_value_override CHECK (((point_value_override IS NULL) OR (point_value_override >= (0)::numeric))),
    CONSTRAINT valid_match_game CHECK (((game_id IS NULL) OR (match_id IS NULL)))
);


ALTER TABLE public.point_instance OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 16691)
-- Name: point_instance_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.point_instance ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.point_instance_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 231 (class 1259 OID 16692)
-- Name: point_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.point_type (
    id bigint NOT NULL,
    active boolean DEFAULT true NOT NULL,
    applies character varying(20) DEFAULT 'Each instance'::character varying NOT NULL,
    applies_to character varying(20) DEFAULT 'One player'::character varying NOT NULL,
    point_value numeric(5,1) DEFAULT 0 NOT NULL,
    score_style character varying(20) DEFAULT 'Achievements'::character varying NOT NULL,
    title character varying(40) NOT NULL,
    description text NOT NULL,
    created timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT each_instance_multiple_players CHECK ((((applies)::text <> 'Each instance'::text) OR ((applies_to)::text = 'Multiple players'::text))),
    CONSTRAINT nonnegative_point_value CHECK ((point_value >= (0)::numeric)),
    CONSTRAINT valid_applies CHECK (((applies)::text = ANY (ARRAY[('Each tournament'::character varying)::text, ('Each match'::character varying)::text, ('Each game'::character varying)::text, ('Each instance'::character varying)::text]))),
    CONSTRAINT valid_applies_to CHECK (((applies_to)::text = ANY (ARRAY[('One player'::character varying)::text, ('Multiple players'::character varying)::text]))),
    CONSTRAINT valid_score_style CHECK (((score_style)::text = ANY (ARRAY[('Achievements'::character varying)::text, ('Wins'::character varying)::text])))
);


ALTER TABLE public.point_type OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 16717)
-- Name: point_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.point_type ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.point_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 233 (class 1259 OID 16718)
-- Name: tournament; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tournament (
    id bigint NOT NULL,
    name character varying(150) NOT NULL,
    state character varying(20) DEFAULT 'Pending'::character varying NOT NULL,
    games_per_match integer DEFAULT 1 NOT NULL,
    players_per_game integer DEFAULT 2 NOT NULL,
    match_type character varying(20) DEFAULT 'Ranked'::character varying NOT NULL,
    score_style character varying(20) DEFAULT 'Wins'::character varying NOT NULL,
    limited boolean DEFAULT false NOT NULL,
    created timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_match_type CHECK (((match_type)::text = ANY (ARRAY[('Ranked'::character varying)::text, ('Random'::character varying)::text]))),
    CONSTRAINT valid_score_style CHECK (((score_style)::text = ANY (ARRAY[('Wins'::character varying)::text, ('Achievements'::character varying)::text]))),
    CONSTRAINT valid_tournament_state CHECK (((state)::text = ANY (ARRAY[('Pending'::character varying)::text, ('In progress'::character varying)::text, ('Complete'::character varying)::text])))
);


ALTER TABLE public.tournament OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 16740)
-- Name: tournament_entry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tournament_entry (
    id bigint NOT NULL,
    deck_id bigint NOT NULL,
    tournament_id bigint NOT NULL,
    points numeric(10,2) DEFAULT 0 NOT NULL,
    opponent_match_win numeric(5,2) DEFAULT 33.33 NOT NULL,
    withdrawn boolean DEFAULT false NOT NULL,
    created timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.tournament_entry OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 16754)
-- Name: tournament_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tournament_entry ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.tournament_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 236 (class 1259 OID 16755)
-- Name: tournament_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tournament ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.tournament_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 237 (class 1259 OID 16756)
-- Name: tournament_match; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tournament_match (
    id bigint NOT NULL,
    active boolean DEFAULT true NOT NULL,
    round_id bigint NOT NULL
);


ALTER TABLE public.tournament_match OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 16763)
-- Name: tournament_match_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tournament_match ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.tournament_match_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 239 (class 1259 OID 16764)
-- Name: tournament_round; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tournament_round (
    id bigint NOT NULL,
    tournament_id bigint NOT NULL,
    number integer NOT NULL,
    active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.tournament_round OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 16772)
-- Name: tournament_round_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tournament_round ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.tournament_round_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 4843 (class 2606 OID 16774)
-- Name: app_user app_user_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.app_user
    ADD CONSTRAINT app_user_pkey PRIMARY KEY (id);


--
-- TOC entry 4847 (class 2606 OID 16776)
-- Name: deck deck_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deck
    ADD CONSTRAINT deck_pkey PRIMARY KEY (id);


--
-- TOC entry 4849 (class 2606 OID 16778)
-- Name: game game_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.game
    ADD CONSTRAINT game_pkey PRIMARY KEY (id);


--
-- TOC entry 4852 (class 2606 OID 16780)
-- Name: match_participant match_participant_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.match_participant
    ADD CONSTRAINT match_participant_pkey PRIMARY KEY (id);


--
-- TOC entry 4858 (class 2606 OID 16782)
-- Name: point_instance point_instance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.point_instance
    ADD CONSTRAINT point_instance_pkey PRIMARY KEY (id);


--
-- TOC entry 4860 (class 2606 OID 16784)
-- Name: point_type point_type_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.point_type
    ADD CONSTRAINT point_type_pkey PRIMARY KEY (id);


--
-- TOC entry 4864 (class 2606 OID 16786)
-- Name: tournament_entry tournament_entry_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournament_entry
    ADD CONSTRAINT tournament_entry_pkey PRIMARY KEY (id);


--
-- TOC entry 4867 (class 2606 OID 16788)
-- Name: tournament_match tournament_match_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournament_match
    ADD CONSTRAINT tournament_match_pkey PRIMARY KEY (id);


--
-- TOC entry 4862 (class 2606 OID 16790)
-- Name: tournament tournament_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournament
    ADD CONSTRAINT tournament_pkey PRIMARY KEY (id);


--
-- TOC entry 4869 (class 2606 OID 16792)
-- Name: tournament_round tournament_round_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournament_round
    ADD CONSTRAINT tournament_round_pkey PRIMARY KEY (id);


--
-- TOC entry 4871 (class 2606 OID 16794)
-- Name: tournament_round tournament_round_tournament_id_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournament_round
    ADD CONSTRAINT tournament_round_tournament_id_number_key UNIQUE (tournament_id, number);


--
-- TOC entry 4845 (class 2606 OID 16796)
-- Name: app_user unique_app_user_username; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.app_user
    ADD CONSTRAINT unique_app_user_username UNIQUE (username);


--
-- TOC entry 4854 (class 2606 OID 16798)
-- Name: match_participant unique_match_participant; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.match_participant
    ADD CONSTRAINT unique_match_participant UNIQUE (id, match_id);


--
-- TOC entry 4856 (class 2606 OID 16800)
-- Name: match_participant unique_match_participant_entry; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.match_participant
    ADD CONSTRAINT unique_match_participant_entry UNIQUE (match_id, tournament_entry_id);


--
-- TOC entry 4865 (class 1259 OID 16801)
-- Name: unique_active_tournament_entry; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unique_active_tournament_entry ON public.tournament_entry USING btree (deck_id, tournament_id) WHERE (withdrawn = false);


--
-- TOC entry 4850 (class 1259 OID 17082)
-- Name: unique_pending_game_per_match; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unique_pending_game_per_match ON public.game USING btree (match_id) WHERE ((status)::text = 'Pending'::text);


--
-- TOC entry 4872 (class 1259 OID 17084)
-- Name: unique_tournament_active_round; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unique_tournament_active_round ON public.tournament_round USING btree (tournament_id) WHERE (active = true);


--
-- TOC entry 4888 (class 2620 OID 16802)
-- Name: match_participant ensure_tournament_consistency; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER ensure_tournament_consistency BEFORE INSERT ON public.match_participant FOR EACH ROW EXECUTE FUNCTION public.ensure_tournament_consistency();


--
-- TOC entry 4886 (class 2620 OID 16803)
-- Name: app_user normalize_username; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER normalize_username BEFORE INSERT OR UPDATE OF username ON public.app_user FOR EACH ROW EXECUTE FUNCTION public.normalize_username();


--
-- TOC entry 4887 (class 2620 OID 16804)
-- Name: game prevent_game_match_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prevent_game_match_change BEFORE UPDATE ON public.game FOR EACH ROW EXECUTE FUNCTION public.prevent_relationship_change('match_id');


--
-- TOC entry 4893 (class 2620 OID 16805)
-- Name: tournament_match prevent_match_round_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prevent_match_round_change BEFORE UPDATE ON public.tournament_match FOR EACH ROW EXECUTE FUNCTION public.prevent_relationship_change('round_id');


--
-- TOC entry 4889 (class 2620 OID 16806)
-- Name: match_participant prevent_participant_entry_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prevent_participant_entry_change BEFORE UPDATE ON public.match_participant FOR EACH ROW EXECUTE FUNCTION public.prevent_relationship_change('tournament_entry_id');


--
-- TOC entry 4890 (class 2620 OID 16807)
-- Name: match_participant prevent_participant_match_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prevent_participant_match_change BEFORE UPDATE ON public.match_participant FOR EACH ROW EXECUTE FUNCTION public.prevent_relationship_change('match_id');


--
-- TOC entry 4894 (class 2620 OID 16808)
-- Name: tournament_round prevent_round_tournament_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prevent_round_tournament_change BEFORE UPDATE ON public.tournament_round FOR EACH ROW EXECUTE FUNCTION public.prevent_relationship_change('tournament_id');


--
-- TOC entry 4892 (class 2620 OID 16809)
-- Name: tournament_entry prevent_tournament_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prevent_tournament_change BEFORE UPDATE ON public.tournament_entry FOR EACH ROW EXECUTE FUNCTION public.prevent_relationship_change('tournament_id');


--
-- TOC entry 4891 (class 2620 OID 16810)
-- Name: point_instance trg_validate_point_instance; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validate_point_instance BEFORE INSERT ON public.point_instance FOR EACH ROW EXECUTE FUNCTION public.validate_point_instance_uniqueness();


--
-- TOC entry 4873 (class 2606 OID 16811)
-- Name: deck deck_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deck
    ADD CONSTRAINT deck_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id);


--
-- TOC entry 4874 (class 2606 OID 16816)
-- Name: game game_match_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.game
    ADD CONSTRAINT game_match_id_fkey FOREIGN KEY (match_id) REFERENCES public.tournament_match(id);


--
-- TOC entry 4875 (class 2606 OID 16821)
-- Name: game game_winner_same_match_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.game
    ADD CONSTRAINT game_winner_same_match_fkey FOREIGN KEY (winner_match_participant_id, match_id) REFERENCES public.match_participant(id, match_id);


--
-- TOC entry 4876 (class 2606 OID 16826)
-- Name: match_participant match_participant_match_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.match_participant
    ADD CONSTRAINT match_participant_match_id_fkey FOREIGN KEY (match_id) REFERENCES public.tournament_match(id);


--
-- TOC entry 4877 (class 2606 OID 16831)
-- Name: match_participant match_participant_tournament_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.match_participant
    ADD CONSTRAINT match_participant_tournament_entry_id_fkey FOREIGN KEY (tournament_entry_id) REFERENCES public.tournament_entry(id);


--
-- TOC entry 4878 (class 2606 OID 16836)
-- Name: point_instance point_instance_game_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.point_instance
    ADD CONSTRAINT point_instance_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.game(id);


--
-- TOC entry 4879 (class 2606 OID 16841)
-- Name: point_instance point_instance_match_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.point_instance
    ADD CONSTRAINT point_instance_match_id_fkey FOREIGN KEY (match_id) REFERENCES public.tournament_match(id);


--
-- TOC entry 4880 (class 2606 OID 16846)
-- Name: point_instance point_instance_point_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.point_instance
    ADD CONSTRAINT point_instance_point_type_id_fkey FOREIGN KEY (point_type_id) REFERENCES public.point_type(id);


--
-- TOC entry 4881 (class 2606 OID 16851)
-- Name: point_instance point_instance_tournament_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.point_instance
    ADD CONSTRAINT point_instance_tournament_entry_id_fkey FOREIGN KEY (tournament_entry_id) REFERENCES public.tournament_entry(id);


--
-- TOC entry 4882 (class 2606 OID 16856)
-- Name: tournament_entry tournament_entry_deck_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournament_entry
    ADD CONSTRAINT tournament_entry_deck_id_fkey FOREIGN KEY (deck_id) REFERENCES public.deck(id);


--
-- TOC entry 4883 (class 2606 OID 16861)
-- Name: tournament_entry tournament_entry_tournament_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournament_entry
    ADD CONSTRAINT tournament_entry_tournament_id_fkey FOREIGN KEY (tournament_id) REFERENCES public.tournament(id);


--
-- TOC entry 4884 (class 2606 OID 16866)
-- Name: tournament_match tournament_match_round_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournament_match
    ADD CONSTRAINT tournament_match_round_id_fkey FOREIGN KEY (round_id) REFERENCES public.tournament_round(id);


--
-- TOC entry 4885 (class 2606 OID 16871)
-- Name: tournament_round tournament_round_tournament_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournament_round
    ADD CONSTRAINT tournament_round_tournament_id_fkey FOREIGN KEY (tournament_id) REFERENCES public.tournament(id);


-- Completed on 2026-11-03 09:28:57

--
-- PostgreSQL database dump complete
--

\unrestrict JeFAQunsx7ZhRZbXWZV8m0U9Wu4cC959dO4s4lRFO4cvljKvYoiDHgCvYdzx789

