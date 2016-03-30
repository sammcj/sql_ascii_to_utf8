-- SELECT remove_non_utf8(column6_text) FROM table101;

CREATE OR REPLACE FUNCTION remove_non_utf8(p_string IN VARCHAR )
  RETURNS character varying AS
$BODY$
DECLARE
  v_string VARCHAR;
BEGIN 
  v_string := p_string;
  RAISE NOTICE 'running remove_non_utf8 (%...%)', left(p_string,8), right(p_string,8);
  -- xFE and xFF are not currently valid UTF8 for 1st or subsequent bytes
  v_string := regexp_replace(v_string, 
	E'[\xFE\xFF]' , '_' , 'g'); 

  -- The following substitutions will not handle more that a one-off bad byte
  -- They would need to be re-applied until v_string stops changing
  -- They can be safely applied to any UTF8 test

  -- RAISE NOTICE 'Fix UTF8 continuation byte 80-BF in text: %', v_string;

  -- Catch single 80-BF - is not valid UTF8 on it's own
  -- ( ASCII or UTF8 or empty )  0x80-0xBF  ( ASCII or 0xC0-0xFF )
  v_string := regexp_replace(v_string, 
	E'(^|[\x01-\x7F]|'                  -- ASCII or empty
         '[\xC0-\xDF][\x80-\xBF]|'          -- 2 byte UTF8
         '[\xE0-\xEF][\x80-\xBF]{2}|'       -- 3 byte UTF8
         '[\xF0-\xF7][\x80-\xBF]{3}|'       -- 4 byte UTF8
         '[\xF8-\xFB][\x80-\xBF]{4}|'       -- 5 byte UTF8
         '[\xFC-\xFD][\x80-\xBF]{5})'       -- 6 byte UTF8
         '[\x80-\xBF]'                     -- replace 0x80-0xBF - not valid as 1st byte of UTF8 sequence,
	 , '\1_' , 'g');

  -- RAISE NOTICE 'Fix UTF8 2 byte C0-DF in text: %', v_string;

  -- Broken 2-byte UTF8 C0-DF
  -- ( ASCII or UTF8 or empty )  0x80-0xDF  ( ASCII or 0xC0-0xFF )
  v_string := regexp_replace(v_string, 
	E'(^|[\x01-\x7F]|'                   -- ASCII or empty
         '[\xC0-\xDF][\x80-\xBF]|'          -- 2 byte UTF8
         '[\xE0-\xEF][\x80-\xBF]{2}|'       -- 3 byte UTF8
         '[\xF0-\xF7][\x80-\xBF]{3}|'       -- 4 byte UTF8
         '[\xF8-\xFB][\x80-\xBF]{4}|'       -- 5 byte UTF8
         '[\xFC-\xFD][\x80-\xBF]{5})'       -- 6 byte UTF8
         '[\xC0-\xDF]([\x01-x7F\xC0-\xFF]|$)'   -- replace 0x80-0xBF - not valid as 1st byte of UTF8 sequence,
                                                -- replace 0xC0-0xDF - only valid if followed by 0x80-0xBF
	 , '\1_\2' , 'g');

  -- RAISE NOTICE 'Fix UTF8 3 byte E0-EF in text: %', v_string;

  -- Broken 3-byte UTF8 E0-EF
  -- ( ASCII or UTF8 or empty )  0xE0-0xDF  ( ASCII or 0xC0-0xFF )
  v_string := regexp_replace(v_string, 
	E'(^|[\x01-\x7F]|'                   -- ASCII or empty
         '[\xC0-\xDF][\x80-\xBF]|'          -- 2 byte UTF8
         '[\xE0-\xEF][\x80-\xBF]{2}|'       -- 3 byte UTF8
         '[\xF0-\xF7][\x80-\xBF]{3}|'       -- 4 byte UTF8
         '[\xF8-\xFB][\x80-\xBF]{4}|'       -- 5 byte UTF8
         '[\xFC-\xFD][\x80-\xBF]{5})'       -- 6 byte UTF8
         '[\xE0-\xEF]([\x80-\xBF]{0,1}[\x01-x7F\xC0-\xFF]|$)'   -- replace 0xE0-0xEF if invalid UTF8 char
	 , '\1_\2' , 'g');

  -- RAISE NOTICE 'Fix UTF8 4 byte F0-F7 in text: %', v_string;

  -- Broken 4-byte UTF8 F0-F7
  -- ( ASCII or UTF8 or empty )  0x80-0xDF  ( ASCII or 0xC0-0xFF )
  v_string := regexp_replace(v_string, 
	E'(^|[\x01-\x7F]|'                   -- ASCII or empty
         '[\xC0-\xDF][\x80-\xBF]|'          -- 2 byte UTF8
         '[\xE0-\xEF][\x80-\xBF]{2}|'       -- 3 byte UTF8
         '[\xF0-\xF7][\x80-\xBF]{3}|'       -- 4 byte UTF8
         '[\xF8-\xFB][\x80-\xBF]{4}|'       -- 5 byte UTF8
         '[\xFC-\xFD][\x80-\xBF]{5})'       -- 6 byte UTF8
         '[\xF0-\xF7]([\x80-\xBF]{0,2}[\x01-x7F\xC0-\xFF]|$)'   -- replace 0xF0-0xF7 if invalid
	 , '\1_\2' , 'g');

  -- RAISE NOTICE 'Fix UTF8 5 byte F8-FB in text: %', v_string;

  -- Broken 5-byte UTF8 F8-FB
  -- ( ASCII or UTF8 or empty )  0x80-0xDF  ( ASCII or 0xC0-0xFF )
  v_string := regexp_replace(v_string, 
	E'(^|[\x01-\x7F]|'                   -- ASCII or empty
         '[\xC0-\xDF][\x80-\xBF]|'          -- 2 byte UTF8
         '[\xE0-\xEF][\x80-\xBF]{2}|'       -- 3 byte UTF8
         '[\xF0-\xF7][\x80-\xBF]{3}|'       -- 4 byte UTF8
         '[\xF8-\xFB][\x80-\xBF]{4}|'       -- 5 byte UTF8
         '[\xFC-\xFD][\x80-\xBF]{5})'       -- 6 byte UTF8
         '[\xF8-\xFB]([\x80-\xBF]{0,3}[\x01-x7F\xC0-\xFF]|$)'   -- replace 0xF8-0xFB if invalid
	 , '\1_\2' , 'g');

  -- RAISE NOTICE 'Fix UTF8 6 byte FC-FD in text: %', v_string;

  -- Broken 6-byte UTF8 FC-FD
  -- ( ASCII or UTF8 or empty )  0x80-0xDF  ( ASCII or 0xC0-0xFF )
  v_string := regexp_replace(v_string, 
	E'(^|[\x01-\x7F]|'                   -- ASCII or empty
         '[\xC0-\xDF][\x80-\xBF]|'          -- 2 byte UTF8
         '[\xE0-\xEF][\x80-\xBF]{2}|'       -- 3 byte UTF8
         '[\xF0-\xF7][\x80-\xBF]{3}|'       -- 4 byte UTF8
         '[\xF8-\xFB][\x80-\xBF]{4}|'       -- 5 byte UTF8
         '[\xFC-\xFD][\x80-\xBF]{5})'       -- 6 byte UTF8
         '[\xFC-\xFD]([\x80-\xBF]{0,2}[\x01-x7F\xC0-\xFF]|$)'   -- replace 0xFC-0xFD if invalid
	 , '\1_\2' , 'g');

-- Invalid sequences:
-- ASCII  80-FF ASCII | C0-FF  -> excludes 80-BF 80-BF .... hmmm
-- ASCII  C0-DF ASCII | C0-FF  -> exclude C0-DF  80-BF
-- ASCII  E0-EF 80-BF {0,1} ASCII | C0-FF  -> exclude E0-EF  80-BF  80-BF
-- ASCII  F0-F7 80-BF {0,2} ASCII | C0-FF  -> exclude F0-F7  80-BF  80-BF  80-BF
-- ASCII  F8-FB 80-BF {0,3} ASCII | C0-FF  -> exclude F8-FB  80-BF  80-BF  80-BF  80-BF
-- ASCII  FC-FD 80-BF {0,4} ASCII | C0-FF  -> exclude FC-FD  80-BF  80-BF  80-BF  80-BF  80-BF
--  80-BF ? 

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
 
      -- EXECUTE FORMAT ('ALTER TABLE %I DISABLE TRIGGER ALL',p_table_name);
      -- RAISE NOTICE 'DISABLED TRIGGERS IN table: %		(column: %) time: %', p_table_name, p_column_name, clock_timestamp();
			RAISE NOTICE '%: table: %    (column: %) time: %', i_num, p_table_name, p_column_name, clock_timestamp();
      FOR ctid_row IN EXECUTE FORMAT('SELECT rid FROM x_list WHERE row_chunk = $1 AND NOT %I ~ $2', 'row_message') 
                USING i_num, v_utf8_string_filter FOR UPDATE
      LOOP
        EXECUTE FORMAT('UPDATE %I SET %I = remove_non_utf8(%I) WHERE ctid = $1 AND %I ~ E''[\x80-\xFF]''', p_table_name, p_column_name, p_column_name, p_column_name) USING ctid_row.rid;
      END LOOP;
      -- EXECUTE FORMAT ('ALTER TABLE %I ENABLE TRIGGER ALL',p_table_name);
      -- RAISE NOTICE 'ENABLED  TRIGGERS IN table: %		(column: %) time: %', p_table_name, p_column_name, clock_timestamp();
			RAISE NOTICE '%: table: %    (column: %) time: %', i_num, p_table_name, p_column_name, clock_timestamp();

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
      RAISE NOTICE 'Processing table: %  	column: %		time: %', cur_column.table_name, cur_column.column_name, clock_timestamp();
      PERFORM process_non_utf8_at_column(cur_column.table_name, cur_column.column_name); 
      RAISE NOTICE 'return from function time: %', clock_timestamp();
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
		RAISE NOTICE 'schema: %		table: %		column: %		time: %', schemaname, tablename, columnname, clock_timestamp();
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

