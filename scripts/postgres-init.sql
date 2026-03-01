-- Part 2: Users table and publication for Debezium CDC
-- Run after PostgreSQL is ready (e.g. kubectl exec -it deploy/postgres -n data-sources -- psql -U postgres -f - < scripts/postgres-init.sql)

CREATE TABLE IF NOT EXISTS public.users (
    user_id SERIAL PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Publication for logical replication (required by Debezium pgoutput)
DROP PUBLICATION IF EXISTS dbz_publication;
CREATE PUBLICATION dbz_publication FOR TABLE public.users;

-- Sample data
INSERT INTO public.users (full_name, email) VALUES
    ('Alice Smith', 'alice@example.com'),
    ('Bob Jones', 'bob@example.com'),
    ('Carol White', 'carol@example.com'),
    ('David Brown', 'david@example.com'),
    ('Eve Davis', 'eve@example.com');

-- Trigger to keep updated_at in sync (optional but good practice)
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS users_updated_at ON public.users;
CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Perform some updates and deletes (as per challenge)
UPDATE public.users SET full_name = 'Alice Johnson', email = 'alice.j@example.com' WHERE user_id = 1;
UPDATE public.users SET full_name = 'Bob Smith' WHERE user_id = 2;
DELETE FROM public.users WHERE user_id = 5;
