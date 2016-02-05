-- Reports on character x09

CREATE OR REPLACE FUNCTION search_columns(
    needle text,
    haystack_tables name[] default '{}',
    haystack_schema name[] default '{public}'
)
RETURNS table(schemaname text, tablename text, columnname text, rowctid text)
AS $$
begin
  FOR schemaname,tablename,columnname IN
      SELECT c.table_schema,c.table_name,c.column_name
      FROM information_schema.columns c
      JOIN information_schema.tables t ON
        (t.table_name=c.table_name AND t.table_schema=c.table_schema)
      WHERE (c.table_name=ANY(haystack_tables) OR haystack_tables='{}')
        AND c.table_schema=ANY(haystack_schema)
        AND t.table_type='BASE TABLE'
  LOOP
    -- EXECUTE format('SELECT ctid FROM %I.%I WHERE cast(%I as text)=%L',
    EXECUTE format('SELECT ctid FROM %I.%I WHERE cast(%I as text) LIKE ''%%'' || convert_from(BYTEA ''\x09'', ''LATIN1'') || ''%%''',
       schemaname,
       tablename,
       columnname,
       needle
    ) INTO rowctid;
    IF rowctid is not null THEN
      RETURN NEXT;
    END IF;
 END LOOP;
END;
$$ language plpgsql;
