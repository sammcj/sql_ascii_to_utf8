-- Initial test query with CROSSTAB to fetch data
SELECT
ct.*
FROM CROSSTAB(' SELECT DATE_TRUNC('day', cp.played_on) AS day, c.name AS name, SUM(cp.total) AS repetitions ' ||
' FROM campaign_performance AS cp JOIN campaign AS c ON c.id = cp.campaign_id ' ||
' WHERE cp.played_on > ' || '''' || '2016-02-03' || '''' ||
' GROUP BY DATE_TRUNC(' || '''' || 'day' || '''' || ', cp.played_on), c.name ',
' SELECT DISTINCT name FROM campaign')
AS ct(day date, name text)


-- PostgreSQL function which receives CAMPAIGN.ID and returns CAMPAIGN.NAME (or NULL if nothing found at given ID)
CREATE OR REPLACE FUNCTION get_campaign_name( p_campaign_id IN NUMERIC) 
  RETURNS character varying AS
$BODY$
DECLARE
  v_campaign_name VARCHAR; 
BEGIN
  SELECT
    MAX(campaign_name)
  INTO v_campaign_name
  FROM campaign
  WHERE id = p_campaign_id;
  RETURN v_campaign_name; 
END;
$BODY$
LANGUAGE plpgsql


-- PostgreSQL function which receives three parameters :
-- 1. Main query as above containing first part of CROSSTAB
-- 2. Query with names for crosstab columns - but column names are enclosed in quadruple quotation marks
-- 3. Once again query names for crosstab columns - but column names are enclosed in double quotation marks
-- Function will compose a statement for actual CROSSTAB query (becuse the amount of columns is variable)
CREATE OR REPLACE FUNCTION my_crosstab( p_main_query IN VARCHAR,
                                        p_columns_query IN VARCHAR,
										p_id_spec_query IN VARCHAR,
										p_name_spec_query IN VARCHAR ) 
  RETURNS character varying AS
$BODY$
DECLARE
  v_column_sql VARCHAR; 
  v_column_text_ids VARCHAR; 
  v_column_text_names VARCHAR;
  v_crosstab_sql VARCHAR;   
BEGIN
  v_column_sql = 'SELECT STRING_AGG(''function'' || ''"'' || id || ''"'' || ''datatype'',' || ' '','') FROM (' || p_id_spec_query || ') AS subq';
    
  EXECUTE v_column_sql INTO v_column_text;
  
  v_column_text_ids = ''"day"'' date,' ||  REPLACE(REPLACE(v_column_text, 'function', ''), 'datatype', ' text');
  
  v_column_text_ids = 'ct (' || v_column_text_ids || ')';

  v_column_text_names = 'CAST(NULL AS date) AS day,' ||  REPLACE(REPLACE(v_column_text, '"' || 'datatype', ')'), 'function' || '"', 'get_campaign_name(');
  
  v_crosstab_sql = ' SELECT ct.* FROM CROSSTAB(' || '''' ||  p_main_query || '''' || ', ' || '''' || p_columns_query || '''' || ') AS ' || v_column_text_ids
  v_crosstab_sql = v_crosstab_sql || ' UNION ALL ';
  v_crosstab_sql = v_crosstab_sql || ' SELECT ' || v_column_text_names || ' ORDER BY 1 ASC NULLS FIRST';
  
  RETURN v_crosstab_sql;
END;
$BODY$
LANGUAGE plpgsql

  
-- Query which will you actually run - it will call function MY_CROSSTAB from above and that function will compose a statement for final query
-- Output result needs to be copied and pasted to separate window and then to be executed
  SELECT my_crosstab('SELECT DATE_TRUNC('  || '''' || 'day' || '''' || ', cp.played_on) AS day, c.name AS name, CAST(SUM(cp.total) AS VARCHAR) AS repetitions ' ||
' FROM campaign_performance AS cp JOIN campaign AS c ON c.id = cp.campaign_id ' ||
' WHERE cp.played_on > ' || '''' || '2016-02-03' || '''' ||
' GROUP BY DATE_TRUNC(' || '''' || 'day' || '''' || ', cp.played_on), c.name ',  
' SELECT DISTINCT CAST(c.id AS varchar2) AS id FROM campaign_performance AS cp JOIN campaign AS c ON c.id = cp.campaign_id WHERE cp.played_on > ' || '''' || '2016-02-03' || '''',           
'SELECT DISTINCT CAST(c.id AS varchar2) AS id FROM campaign_performance AS cp JOIN campaign AS c ON c.id = cp.campaign_id WHERE cp.played_on >' || '''' || '2016-02-03' || '''') 

-- Alternatively you can create a table to insert result from previous call and then COPY-PASTE from there 
CREATE TABLE x_test (
    rid TID,
	row_value NUMERIC(11,2),
	message VARCHAR
);

INSERT INTO x_test(message)
  SELECT my_crosstab('SELECT DATE_TRUNC('  || '''' || 'day' || '''' || ', cp.played_on) AS day, c.name AS name, SUM(cp.total) AS repetitions ' ||
' FROM campaign_performance AS cp JOIN campaign AS c ON c.id = cp.campaign_id ' ||
' WHERE cp.played_on > ' || '''' || '2016-02-03' || '''' ||
' GROUP BY DATE_TRUNC(' || '''' || 'day' || '''' || ', cp.played_on), c.name ',  
' SELECT DISTINCT c.name FROM campaign_performance AS cp JOIN campaign AS c ON c.id = cp.campaign_id WHERE cp.played_on > ' || '''' || '2016-02-03' || '''',           
'SELECT DISTINCT c.name FROM campaign_performance AS cp JOIN campaign AS c ON c.id = cp.campaign_id WHERE cp.played_on >' || '''' || '2016-02-03' || '''') 

SELECT * FROM x_test
ORDER BY ctid DESC

-- As a final step you would need to run a query from output and run it
