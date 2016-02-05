create or replace function utf8_verify(bytea,integer) returns bool as '
DECLARE
   str ALIAS FOR $1;
   maxlen ALIAS FOR $2;
   strlen INTEGER;
   i integer;
   j INTEGER;
   len integer;
   chr integer;
   wchr integer;
BEGIN
   i := 0;
   strlen := length(str);

   WHILE i < strlen LOOP

     -- Check leading byte
     chr := get_byte(str,i);

     IF chr < 128 THEN     -- 0x00 - 0x80   - single byte
        len := 1;
        wchr := chr;
     ELSIF chr < 192 THEN  -- 0x80 - 0xC0   - illegal
        RETURN false;
     ELSIF chr < 224 THEN  -- 0xC0 - 0xE0   - two bytes
        len := 2;
        wchr := chr - 192;
     ELSIF chr < 240 THEN  -- 0xE0 - 0xF0   - three bytes
        len := 3;
        wchr := chr - 224;
     ELSIF chr < 248 THEN  -- 0xF0 - 0xF8   - four bytes
        len := 4;
        wchr := chr - 240;
     ELSIF chr < 252 THEN  -- 0xF8 - 0xFC   - five bytes
        len := 5;
        wchr := chr - 248;
     ELSIF chr < 254 THEN  -- 0xFC - 0xFE   - six bytes
        len := 6;
        wchr := chr - 252;
     ELSE
        RETURN false;   -- FE and FF not currently defined
     END IF;

--     RAISE NOTICE ''chr=%, len=%, wchr=%'', chr, len, wchr;

     IF i + len > strlen THEN
        RETURN false;
     END IF;

     IF len > maxlen THEN
        RETURN false;
     END IF;

     -- Check remaining characters
     j := 1;
     WHILE len > j LOOP
        chr := get_byte(str, i+j);
        IF chr < 128 OR chr >= 192 THEN
            RETURN false;
        END IF;
        wchr := (wchr << 6) + (chr - 128);
        j := j+1;
     END LOOP;

--     RAISE NOTICE ''chr=%, wchr=%, j=%'', chr, wchr, j;

     -- Verify shortest possible string
     IF len = 1 AND wchr >= 128 THEN
        RETURN false;
     ELSIF len = 2 AND (wchr < 128 OR wchr >= 2048) THEN
        RETURN false;
     ELSIF len = 3 AND (wchr < 2048 OR wchr >= 65536) THEN
        RETURN false;
     ELSIF len = 4 AND (wchr < 65536 OR wchr >= 2097152) THEN
        RETURN false;
     ELSIF len = 5 AND (wchr < 2097152 OR wchr >= 67108864) THEN
        RETURN false;
     ELSIF len = 6 AND (wchr < 67108864 OR wchr >= 2147483648) THEN
        RETURN false;
     END IF;

--     RAISE NOTICE ''Checked char offset %, OK (wchr=%,len=%)'', i, wchr, len;

     i := i+len;
   END LOOP;

  RETURN true;
END;
' language plpgsql;

drop type utf8_error cascade;
create type utf8_error as ( tab regclass, fld text, location tid );
CREATE CAST (text as bytea) WITHOUT FUNCTION;
CREATE CAST (bpchar as bytea) WITHOUT FUNCTION;
CREATE CAST (varchar as bytea) WITHOUT FUNCTION;

create or replace function db_utf8_verify() returns setof utf8_error as '
DECLARE
    r RECORD;
    q TEXT;
    r2 RECORD;
BEGIN
  FOR r IN
      select pgc.oid::regclass as tab, pga.attname::text as fld
      from pg_attribute pga
        join pg_class pgc on (pga.attrelid = pgc.oid)
        join pg_type pgt on (pgt.oid = pga.atttypid)
        join pg_namespace pgn on (pgc.relnamespace = pgn.oid)
     where pgc.relkind=''r''
     and pgt.typname in (''text'',''bpchar'',''varchar'')
     and pgn.nspname not like ''pg_%''
  LOOP
      RAISE NOTICE ''Checking table %, field %'', r.tab, r.fld;

      q := ''SELECT regclass('' || oid(r.tab) || ''), text('' || quote_literal(r.fld) || ''),ctid FROM '' || textin(regclassout(r.tab)) || '' WHERE NOT utf8_verify(cast('' || r.fld || '' as bytea),4)'';
--      RAISE NOTICE ''Query: %'', q;
      FOR r2 IN EXECUTE q LOOP
         RETURN NEXT r2;
      END LOOP;
  END LOOP;
  RETURN;
END;

' language plpgsql;
