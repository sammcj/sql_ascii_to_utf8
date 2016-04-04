## Evgeny's scripts

This is the script that Evgeny, Ricardo and George are currently working on:

- [Replace_non_UTF8.sql](Replace_non_UTF8.sql)
- [run_process_non_utf8.sh](run_process_non_utf8.sh)


### Sam's dodgy scripts

These are some older scripts I was playing with for converting PostgreSQL SQL_ASCII databases with non-utf8 characters to UTF8

This is currently a work in progress, don't use these in production (yet).

The original script was based on some SQL from:
    http://sniptools.com/databases/finding-non-utf8-values-in-postgresql

This code _might_ work properly, if the non-UTF8 characters are already in a UTF8-encoded database.
However, in an SQL_ASCII database, a 4-byte UTF8 sequence has a string length of 4, not 1.
This means that 80-BF characters are matched both within the UTF8 sequence, and again as a single character.
The end result is that all bytes in the range 80-FF are treated as non-UTF8, even if they are part of a valid UTF8 sequence.

This function has been completely rewritten to use regexp_replace().
This will reliably _detect_ any non-UTF8 byte-sequence.
It may need to be run multiple times to ensure all possible invalid byte-combinations have been replaced by underscores.

The bash script [run_process_non_utf8.sh](run_process_non_utf8.sh) will run the function remove_non_utf8() over all columns in the database, once only.
When complete, the script calls the function `search_for_non_utf8_columns(show_timestamps := false);`
If this reports anything other than the following, then there are still non-UTF8 byte-sequences in the database
```
========= checking results =============
 search_for_non_utf8_columns
-----------------------------
(0 rows)
```

[report_nonutf8_char.sql](report_nonutf8_char.sql)- Reports on a character within a database, by default this is hard coded to look for the non-utf8 character with the byte coding of `\x09`

```sql
select * from search_columns('');
 schemaname |      tablename       |    columnname    |  rowctid
------------+----------------------+------------------+------------
 public     | cool_table           | cool_column      | (0,1)
 public     | another_table        | message          | (0,5)
 public     | chocolate            | notes            | (1,5)
(22 rows)

Time: 117608.966 ms
```

[utf8_verify.sql](utf8_verify.sql) - Reports on all non-utf8 characters in a database.

```sql
my_database=# select * from db_utf8_verify();
NOTICE:  00000: Checking table schema_version, field v
LOCATION:  exec_stmt_raise, pl_exec.c:3035
NOTICE:  00000: Checking table cool_table, field amaing_field
LOCATION:  exec_stmt_raise, pl_exec.c:3035
```

[replace_character.sql](replace_character.sql) - Replaces the character with the byte coding of `\x09` of your choosing with a `?`

* I'm fairly certainly this is not at all safe as it might break some XML etc...
* It also completely rewrites the entire database so it's slow and massively impacts performance.


Common characters I see in SQL_ASCII databases have the following bytecodes:

```
0xe9
0x09
0x39
0xa3
0x96
0x92
```
