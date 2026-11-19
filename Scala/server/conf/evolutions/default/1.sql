# --- !Ups

CREATE TABLE page_load (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    game_name TEXT NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX page_load_loaded_at_idx ON page_load(loaded_at);

# --- !Downs

DROP TABLE page_load;
