-- SELECT remove_non_utf8(column6_text) FROM table101;

CREATE OR REPLACE FUNCTION remove_non_utf8(p_string IN VARCHAR )
  RETURNS character varying AS
$BODY$
DECLARE
  v_string VARCHAR;
  cur_part RECORD;
BEGIN 
  v_string := p_string;
  RAISE NOTICE 'running remove_non_utf8 (%...%)', left(p_string,5), right(p_string,5);
  FOR cur_part IN ( SELECT
                      p_string AS word, 
                      SUBSTRING(p_string, numgen.num, 1) AS symbol, 
                      numgen.num AS POS
                    FROM ( SELECT GENERATE_SERIES AS num 
					       FROM GENERATE_SERIES(1,(SELECT MAX(LENGTH(p_string)) AS slength))) AS numgen
                    WHERE SUBSTRING(p_string, numgen.num, 1) IS NOT NULL  
                      AND LENGTH(SUBSTRING(p_string, numgen.num, 1)) >= 1
                      AND NOT    SUBSTRING(p_string, numgen.num, 1) ~ ( '^('||
                                             $$[\09\0A\0D\x20-\x7E]|$$||               -- ASCII
                                             $$[\xC2-\xDF][\x80-\xBF]|$$||             -- non-overlong 2-byte
                                             $$\xE0[\xA0-\xBF][\x80-\xBF]|$$||        -- excluding overlongs
                                             $$[\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}|$$||  -- straight 3-byte
                                             $$\xED[\x80-\x9F][\x80-\xBF]|$$||        -- excluding surrogates
                                             $$\xF0[\x90-\xBF][\x80-\xBF]{2}|$$||     -- planes 1-3
                                             $$[\xF1-\xF3][\x80-\xBF]{3}|$$||          -- planes 4-15
                                             $$\xF4[\x80-\x8F][\x80-\xBF]{2}$$||      -- plane 16
                                             ')*$' )
                    ORDER BY 3 DESC )
   LOOP					
     v_string := LEFT(v_string, cur_part.pos - 1)|| '_' || RIGHT(v_string, LENGTH(v_string) - cur_part.pos);
   END LOOP;
   RETURN v_string;
END
$BODY$  LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION process_non_utf8_at_column( p_table_name IN VARCHAR,
                                                       p_column_name IN VARCHAR)
  RETURNS VOID AS
$BODY$
DECLARE 
  v_utf8_string_filter CONSTANT VARCHAR = '(' || '''' || '^(' || '''' || '||$$[\09\0A\0D\x20-\x7E]|$$|| $$[\xC2-\xDF][\x80-\xBF]|$$||  $$\xE0[\xA0-\xBF][\x80-\xBF]|$$|| $$[\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}|$$||  $$\xED[\x80-\x9F][\x80-\xBF]|$$||$$\xF0[\x90-\xBF][\x80-\xBF]{2}|$$||$$[\xF1-\xF3][\x80-\xBF]{3}|$$||$$\xF4[\x80-\x8F][\x80-\xBF]{2}$$||' ||
  '''' || ')*$' || '''' ||')';   
  n_max_chunks BIGINT;
  ctid_row RECORD;
  i_num INTEGER;
BEGIN
  EXECUTE 'DROP TABLE IF EXISTS x_list;';
  
  EXECUTE 'CREATE TEMPORARY TABLE x_list ( ' ||
          ' rid TID NOT NULL, ' ||
          ' row_value NUMERIC(11,2) NOT NULL, ' ||
          ' row_message character varying, ' ||
          ' row_chunk bigint ) ON COMMIT DELETE ROWS; ';
  
  EXECUTE 'CREATE INDEX chunk_idx ON x_list (row_chunk);';

  EXECUTE FORMAT(' INSERT INTO X_LIST (rid, row_value, row_message, row_chunk) ' ||
                 ' SELECT ctid, Row_Number() Over(), %I,' || 
                 ' (Row_Number() Over())/50000 + 1 As row_chunk ' ||
                 ' FROM %I', p_column_name, p_table_name);

  EXECUTE 'SELECT MAX(row_chunk) FROM x_list' INTO n_max_chunks;

  FOR i_num IN 1..n_max_chunks
  LOOP
 
      EXECUTE FORMAT ('ALTER TABLE %I DISABLE TRIGGER ALL',p_table_name);
      RAISE NOTICE 'DISABLED TRIGGERS IN table: %		(column: %)', p_table_name, p_column_name;
      FOR ctid_row IN EXECUTE FORMAT('SELECT rid FROM x_list WHERE row_chunk = $1 AND NOT %I ~ $2', 'row_message') 
                USING i_num, v_utf8_string_filter FOR UPDATE
      LOOP
        EXECUTE FORMAT('UPDATE %I SET %I = remove_non_utf8(%I) WHERE ctid = $1 AND %I ~ E''[\x80-\xFF]''', p_table_name, p_column_name, p_column_name, p_column_name) USING ctid_row.rid;
      END LOOP;
      EXECUTE FORMAT ('ALTER TABLE %I ENABLE TRIGGER ALL',p_table_name);
      RAISE NOTICE 'ENABLED  TRIGGERS IN table: %		(column: %)', p_table_name, p_column_name;

  END LOOP;

  EXECUTE 'DROP TABLE IF EXISTS x_list;';
  
END
$BODY$  LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION process_non_utf8_at_schema(p_my_schema IN VARCHAR)
RETURNS VOID AS
$BODY$
DECLARE 
  cur_column RECORD;
  num_rows BIGINT;
BEGIN
  -- Loop through all character columns in target schema
  FOR cur_column IN SELECT table_name, column_name 
                    FROM information_schema.columns  
                    WHERE table_schema = p_my_schema AND NOT ( table_name = 'spatial_ref_sys' OR table_name = 'geography_columns' OR table_name = 'geometry_columns' )
                      AND (data_type  LIKE 'character%' OR data_type LIKE 'text%' OR data_type LIKE 'varchar%')
  LOOP   
    EXECUTE FORMAT('SELECT count(*) FROM %I', cur_column.table_name ) INTO num_rows;
    IF ( num_rows > 0 ) THEN
      RAISE NOTICE 'Processing table: %  	column: %', cur_column.table_name, cur_column.column_name;
      PERFORM process_non_utf8_at_column(cur_column.table_name, cur_column.column_name); 
    ELSE
      RAISE NOTICE 'Processing table: %  	(empty table skipping)', cur_column.table_name;
    END IF;
  END LOOP;
END
$BODY$  LANGUAGE plpgsql;


--
-- The following function seeks out the offending schema/table/column/row and returns these as a table
--
DROP FUNCTION IF EXISTS search_columns(needle text, haystack_tables name[], haystack_schema name[]);

CREATE OR REPLACE FUNCTION search_columns(
    needle text,
    haystack_tables name[] default '{}',
    haystack_schema name[] default '{public}'
)
--RETURNS table(schemaname text, tablename text, columnname text, rowctid text)
RETURNS table(schemaname text, tablename text, columnname text, hits integer)
AS $BODY$
begin
  FOR schemaname,tablename,columnname IN
      SELECT c.table_schema,c.table_name,c.column_name
      FROM information_schema.columns c
      JOIN information_schema.tables t ON
        (t.table_name=c.table_name AND t.table_schema=c.table_schema)
      WHERE (c.table_name=ANY(haystack_tables) OR haystack_tables='{}')
        AND c.table_schema=ANY(haystack_schema)
        AND t.table_type='BASE TABLE'
        AND (data_type  LIKE 'character%' OR data_type LIKE 'text%' OR data_type LIKE 'varchar%')
  LOOP
    -- EXECUTE format('SELECT ctid FROM %I.%I WHERE cast(%I as text)=%L',
    -- EXECUTE format('SELECT ctid FROM %I.%I WHERE cast(%I as text) LIKE ''%%'' || convert_from(BYTEA ''\xC7'', ''LATIN1'') || ''%%''',
		RAISE NOTICE 'schema: %   table: %   column: %', schemaname, tablename, columnname;
    EXECUTE format('SELECT count(*) FROM %I.%I WHERE cast(%I as text) ~  E''[\x80-\xFF]'' LIMIT 1',
       schemaname,
       tablename,
       columnname,
       needle
    ) INTO hits;
    IF hits > 0 THEN
      RETURN NEXT;
    END IF;
 END LOOP;
END;
$BODY$ language plpgsql;

