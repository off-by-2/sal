-- +goose Up
-- +goose StatementBegin
CREATE TABLE public.refresh_tokens (
    token_hash character varying(255) NOT NULL,
    user_id uuid NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT refresh_tokens_pkey PRIMARY KEY (token_hash),
    CONSTRAINT fk_refresh_tokens_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE INDEX idx_refresh_tokens_user ON public.refresh_tokens USING btree (user_id);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS public.refresh_tokens;
-- +goose StatementEnd
