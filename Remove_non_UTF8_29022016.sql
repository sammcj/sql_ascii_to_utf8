CREATE OR REPLACE FUNCTION remove_non_utf8(p_string IN VARCHAR )
  RETURNS VARCHAR AS
$BODY$
DECLARE
  v_string VARCHAR;
  cur_part record;
BEGIN
  v_string := p_string;
  FOR cur_part IN ( SELECT
                      p_string AS word,
                      SUBSTRING(p_string, numgen.num, 1) AS symbol,
                      numgen.num AS POS
                    FROM ( SELECT GENERATE_SERIES AS num
					       FROM GENERATE_SERIES(1,(SELECT MAX(LENGTH(p_string)) AS slength)) AS numgen
                    WHERE SUBSTRING(p_string, numgen.num, 1) IS NOT NULL
                      AND LENGTH(SUBSTRING(p_string, numgen.num, 1)) >= 1
                     AND NOT SUBSTRING(p_string, numgen.num, 1) ~ ( '^('||
                                             $$[\09\0A\0D\x20-\x7E]|$$||               -- ASCII
                                             $$[\xC2-\xDF][\x80-\xBF]|$$||             -- non-overlong 2-byte
                                             $$\xE0[\xA0-\xBF][\x80-\xBF]|$$||        -- excluding overlongs
                                             $$[\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}|$$||  -- straight 3-byte
                                             $$\xED[\x80-\x9F][\x80-\xBF]|$$||        -- excluding surrogates
                                             $$\xF0[\x90-\xBF][\x80-\xBF]{2}|$$||     -- planes 1-3
                                             $$[\xF1-\xF3][\x80-\xBF]{3}|$$||          -- planes 4-15
                                             $$\xF4[\x80-\x8F][\x80-\xBF]{2}$$||      -- plane 16
                                             ')*$' )
                    ORDER BY 3 DESC ) AS tb )
   LOOP
     v_string := LEFT(v_string, c_part.num - 1)|| RIGHT(v_string, LENGTH(v_string) - c_part.num);
   END LOOP;
   RETURN v_string;
END
$BODY$  LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION process_non_utf8_at_column( p_table_name IN VARCHAR,
                                                       p_column_name IN VARCHAR)
  RETURNS VARCHAR AS
$BODY$
DECLARE
  v_utf8_string_filter CONSTANT VARCHAR = '(' || '''' || '^(' || '''' || '||$$[\09\0A\0D\x20-\x7E]|$$|| $$[\xC2-\xDF][\x80-\xBF]|$$||  $$\xE0[\xA0-\xBF][\x80-\xBF]|$$|| $$[\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}|$$||  $$\xED[\x80-\x9F][\x80-\xBF]|$$||$$\xF0[\x90-\xBF][\x80-\xBF]{2}|$$||$$[\xF1-\xF3][\x80-\xBF]{3}|$$||$$\xF4[\x80-\x8F][\x80-\xBF]{2}$$||' ||
  '''' || ')*$' || '''' ||')';
  n_max_chunks BIGINT;
  ctid_row RECORD;
BEGIN
  EXECUTE 'DROP TABLE IF EXISTS x_list;';

  EXECUTE 'CREATE TEMPORARY TABLE x_list ( ' ||
          ' rid TID NOT NULL, ' ||
          ' row_value NUMERIC(11,2) NOT NULL, ' ||
          ' row_message text, ' ||
          ' row_chunk bigint ) ON COMMIT DELETE ROWS; ';

  EXECUTE 'CREATE INDEX chunk_idx ON x_list (row_chunk);';

  EXECUTE FORMAT(' INSERT INTO X_LIST (rid, row_value, row_message, row_chunk) ' ||
                 ' SELECT ctid, Row_Number() Over(), %I,' ||
                 ' (Row_Number() Over())/50000 + 1 As row_chunk ' ||
                 ' FROM %I', p_column_name, p_table_name);
  EXECUTE FORMAT(' INSERT INTO X_LIST (rid, row_value, row_message, row_chunk) ' ||
                 ' SELECT ctid, row_value, message, ' ||
                 ' (Row_Number() Over())/50000 + 1 As row_chunk ' ||
                 ' FROM %I', p_table_name);

  EXECUTE 'SELECT MAX(row_chunk) FROM x_list' INTO n_max_chunks;

  FOR i_num IN 1..n_max_chunks
  LOOP

    FOR ctid_row IN EXECUTE FORMAT('SELECT ctid FROM %I WHERE ctid IN (SELECT ctid FROM x_list WHERE row_chunk = $1) AND NOT %I ~ $2', p_table_name, p_column_name)
	                USING CAST(i_num AS VARCHAR), v_utf8_string_filter FOR UPDATE
    LOOP
       EXECUTE FORMAT('UPDATE %I SET %I = remove_non_utf8(%I) WHERE ctid = $1', p_table_name, p_column_name, p_column_name) USING ctid_row;
    END LOOP;

  END LOOP;

  EXECUTE 'DROP TABLE IF EXISTS x_list;';

END
$BODY$  LANGUAGE plpgsql;
