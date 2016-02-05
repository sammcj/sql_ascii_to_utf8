-- Replaces character x09 with the character '?'
-- Several bugs and rewrites the whole database

DO
$$
DECLARE
rw record;
BEGIN
SET session_replication_role = replica; -- disable triggers
FOR rw IN
    SELECT 'UPDATE '||C.table_name||'  SET '||C.column_name||' = REPLACE ('||C.COLUMN_NAME||',convert_from(BYTEA ''\x09'', ''LATIN1''),''?''); ' QRY
    FROM (SELECT column_name,table_name
          FROM   information_schema.columns
          WHERE  table_schema='public'
          AND    (data_type ='text' OR data_type ='character varying')
          AND    table_name in (SELECT table_name
                                FROM   information_schema.tables
                                WHERE  table_schema='public'
                                AND    table_type ='BASE TABLE'))c

LOOP
    EXECUTE rw.QRY;
END LOOP;
SET session_replication_role = DEFAULT; -- enable triggers
END;
$$;
