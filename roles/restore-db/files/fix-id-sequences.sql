DO $$
DECLARE
    tbl RECORD;
    seq_name TEXT;
    next_id BIGINT;
BEGIN
    FOR tbl IN
        SELECT
            c.table_name
        FROM information_schema.columns c
        JOIN information_schema.table_constraints tc
          ON c.table_schema = tc.table_schema
         AND c.table_name = tc.table_name
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
         AND tc.table_name = kcu.table_name
         AND c.column_name = kcu.column_name
        WHERE c.table_schema = 'public'
          AND c.column_name = 'id'
          AND c.data_type IN ('integer', 'bigint')
          AND tc.constraint_type = 'PRIMARY KEY'
          AND c.column_default IS NULL
          AND c.is_identity = 'NO'
    LOOP
        seq_name := tbl.table_name || '_id_seq';

        EXECUTE format(
            'CREATE SEQUENCE IF NOT EXISTS public.%I',
            seq_name
        );

        EXECUTE format(
            'SELECT COALESCE(MAX(id), 0) + 1 FROM public.%I',
            tbl.table_name
        ) INTO next_id;

        EXECUTE format(
            'ALTER TABLE public.%I ALTER COLUMN id SET DEFAULT nextval(%L::regclass)',
            tbl.table_name,
            'public.' || quote_ident(seq_name)
        );

        EXECUTE format(
            'ALTER SEQUENCE public.%I OWNED BY public.%I.id',
            seq_name,
            tbl.table_name
        );

        EXECUTE format(
            'SELECT setval(%L::regclass, %s, false)',
            'public.' || quote_ident(seq_name),
            next_id
        );
    END LOOP;
END $$;