Find and Replace non-UTF8 characters in a Postgresql SQL_ASCII database
-----------------------------------------------------------------------

This respository contains the following files:

- [Replace_non_UTF8.underscore.sql](Replace_non_UTF8.underscore.sql)
- [Replace_non_UTF8.html_equiv.sql](Replace_non_UTF8.html_equiv.sql)
- [run_process_non_utf8.sh](run_process_non_utf8.sh)
- [Replace_non_UTF8.cleanup.sql](Replace_non_UTF8.cleanup.sql)
- [create_test_sql_ascii.sh](create_test_sql_ascii.sh)

Applogies for the haphazard naming of these files and functions, but it works.

The Goal
========

To be able to take a Postgres Database which is in SQL_ASCII encoding, and import it into a UTF8 encoded database.

The Problem
===========
Postresql will generate errors like this if it encounters any non-UTF8 byte-sequences during a database restore:
```
# pg_dump -Fc test_badchar | pg_restore -d test_badchar_utf8
pg_restore: [archiver (db)] Error while PROCESSING TOC:
pg_restore: [archiver (db)] Error from TOC entry 2839; 0 26852 TABLE DATA table101 postgres
pg_restore: [archiver (db)] COPY failed for table "table101": ERROR:  invalid byte sequence for encoding "UTF8": 0x91
CONTEXT:  COPY table101, line 1
WARNING: errors ignored on restore: 1
```

And the corresponding data will be omitted from the database (in this case, the whole table, even the rows which did not have a problem):
```
# echo "select * from table101;" | psql test_badchar_utf8
 chardecimal | description | column6_text
-------------+-------------+--------------
(0 rows)

```

The Solution
============

To find and replace characters in an SQL_ASCII encoded database which do not conform to the UTF8 encoding requirements.

This should be implemented as an SQL script, so that the data can be updated on a live database, to mininmise the downtime required.

There is an existing script which will _find_ the offending rows in a table:
    http://sniptools.com/databases/finding-non-utf8-values-in-postgresql

While this will find the offending rows, it cannot do anything about it, as it stands.

A more sophisticated script is required to actually replace the non-UTF8 characters with something acceptable.

Two SQL scripts are provided here

The first of these SQL scripts is:

- [Replace_non_UTF8.underscore.sql](Replace_non_UTF8.underscore.sql)

This will replace all non-UTF8 characters with underscores.
This (at least) will allow the data to be imported successfully to a UTF8 database.

The second of these SQL scripts is:

- [Replace_non_UTF8.html_equiv.sql](Replace_non_UTF8.html_equiv.sql)

will replace selected bytes with a UTF8-sequence which corresponds to what is rendered by Firefox when encoded as '&#NN;'
where NN is the hexadecimal value of the byte.
Not all values from 80-FF are covered by this script. Please add your own translations as required.
Any byte without a specific translation will be replaced with an underscore.

The Triggers Problem
====================
The functions process_non_utf8_at_column() process_non_utf8_at_schema() work just fine, BUT if there are any 'triggers' on the rows being updated, these triggers are also invoked.
Such triggers may expect a specific set of fields to be updated together, or increment sequence numbers.

Running these triggers would be an undesirable side-effect of what should be a simple text-update.

The Locking Problem
===================
The original solution was designed to minimise downtime, and these scripts would be ineffective if they were to lock table for anything more than a couple of seconds.

Unfortunately, this is exactly what happens if triggers are diabled per-table while updating the text like this:
```
ALTER TABLE _some_table_ DISABLE TRIGGER ALL;
process_non_utf8_at_column(...);
ALTER TABLE _some_table_ ENABLE TRIGGER ALL;
```

Postgres wraps it all in a transaction, and locks the table until the update is complete (which can be minutes on a large table).

The Non-Locking, Non-Triggering Solution
========================================

a) Don't use `ALTER TABLE _some_table_ DISABLE TRIGGER ALL;`
   Instead, use a session-based setting:
```
     SET session_replication_role = replica;
```
This has the effect of disabling triggers, but does not lock the whole table while the function is running.

b) Don't try to run the whole DB in one go.

The following script does a search for offending table,column combinations, and then invokes process_non_utf8_at_column() on each of these individually.

- [run_process_non_utf8.sh](run_process_non_utf8.sh)


Sample DB and Outputs
=====================
A test database can be created using the script:
- [create_test_sql_ascii.sh](create_test_sql_ascii.sh)

This should be run as follows:
```
	createdb -e --template=template0 -E SQL_ASCII test_badchar
	./create_test_sql_ascii.sh test_badchar
```

When we run the script, we should see the following output:
```
# psql test_badchar < Replace_non_UTF8.html_equiv.sql
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
# ./run_process_non_utf8.sh test_badchar
========================================
Start: Tue Apr 19 09:16:30 AEST 2016
========================================
INFO:  schema: public		table: table101		column: description		time: 2016-04-19 09:16:30.949714+10
INFO:  schema: public		table: table101		column: non_utf8_text		time: 2016-04-19 09:16:30.991793+10
INFO:  schema: public		table: empty_table		column: somedata		time: 2016-04-19 09:16:31.406256+10
    search_for_non_utf8_columns
------------------------------------
 (public,table101,description,1)
 (public,table101,non_utf8_text,11)
(2 rows)

'table101','description'
'table101','non_utf8_text'
========================================
Initial search completed: Tue Apr 19 09:16:31 AEST 2016
Search run time 1 seconds
========================================
processing: 'table101','description'
SET session_replication_role = replica;
SET
SELECT process_non_utf8_at_column('table101','description');
NOTICE:  table "x_list" does not exist, skipping
NOTICE:  1: table: table101    (column: description) time: 2016-04-19 09:16:31.425359+10
INFO:  running remove_non_utf8 (UTF8 follo...��� <-here)
NOTICE:  1: table: table101    (column: description) time: 2016-04-19 09:16:31.481739+10
 process_non_utf8_at_column
----------------------------

(1 row)

SET session_replication_role = DEFAULT;
SET
processing: 'table101','non_utf8_text'
SET session_replication_role = replica;
SET
SELECT process_non_utf8_at_column('table101','non_utf8_text');
NOTICE:  table "x_list" does not exist, skipping
NOTICE:  1: table: table101    (column: non_utf8_text) time: 2016-04-19 09:16:31.498909+10
INFO:  running remove_non_utf8 (91-> � ���...<- -½�½-)
INFO:  running remove_non_utf8 (92-> � ���...<- -½�½-)
INFO:  running remove_non_utf8 (96-> � ���...<- -½�½-)
INFO:  running remove_non_utf8 (A3-> � ���...<- -½�½-)
INFO:  running remove_non_utf8 (C7-> � ���...<- -½�½-)
INFO:  running remove_non_utf8 (D0-> � ���...<- -½�½-)
INFO:  running remove_non_utf8 (D5-> � ���...<- -½�½-)
INFO:  running remove_non_utf8 (E9-> � ���...<- -½�½-)
INFO:  running remove_non_utf8 (FA-> � ���...<- -½�½-)
INFO:  running remove_non_utf8 (�...�)
INFO:  running remove_non_utf8 (�🐱�...�🐱�)
NOTICE:  1: table: table101    (column: non_utf8_text) time: 2016-04-19 09:16:32.358957+10
 process_non_utf8_at_column
----------------------------

(1 row)

SET session_replication_role = DEFAULT;
SET
========================================
Update complete: Tue Apr 19 09:16:32 AEST 2016
Update run time 1 seconds
========================================
========= checking results =============
 search_for_non_utf8_columns
-----------------------------
(0 rows)

========================================
Finish: Tue Apr 19 09:16:32 AEST 2016
Total run time 2 seconds
========================================
# psql test_badchar < Replace_non_UTF8.cleanup.sql
DROP FUNCTION
DROP FUNCTION
DROP FUNCTION
DROP FUNCTION
```

----

