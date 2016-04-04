#!/bin/bash

# create role root with superuser,login;

if [ "$1" = '-a' ]; then
	ALL=1
	shift
fi

DB=$1
VERS=$2

if [[ "$1" = '' ]]; then
	cat <<EOF
		Usage: $0 dbname
EOF
	exit
fi

case "$VERS" in
	'')
		VERS=9.2
		V=''
		PORT=5432
		;;
  9*5)
		VERS=9.5
		V=95
		PORT=5433
		;;
	*)
		VERS=9.2
		V=''
		PORT=5432
esac

sudo -u postgres psql -e -p $PORT "$DB" <<EOF

CREATE TABLE table101 (
		chardecimal	integer,
		description	character varying(2500),
		column6_text	text
);

CREATE TABLE empty_table (
    somedata  character varying
);
EOF

if [ -z "$ALL" ]; then
	CHAR_LIST="91 92 96 A3 C7 D0 D5 E9 FA"
else
	N=128
	while [[ "$N" -lt 256 ]]; do
		NH=`printf '%2X' $N`
		CHAR_LIST="$CHAR_LIST $NH"
		N=$(( ${N:-0} + 1 ))
	done
fi

for NH in $CHAR_LIST; do

	N=`printf '%d' 0x$NH`
	printf "INSERT INTO table101 (chardecimal,description,column6_text) VALUES (%3d,'CHAR 0x%2X','$NH-> \x$NH \x$NH\x$NH <- -\xC2\xBD\x$NH\xC2\xBD-');\n" $N $N | \
		sudo -u postgres psql -e -p $PORT "$DB"
done

cat <<EOF | sudo -u postgres psql -e -p $PORT "$DB"
COPY table101 (chardecimal, description, column6_text) FROM stdin;
999	This is a very long piece of text intented to take this column over the 250 char size, This is a very long piece of text intented to take this column over the 250 char size, This is a very long piece of text intented to take this column over the 250 char size, This is a very long piece of text intented to take this column over the 250 char size, This is a very long piece of text intented to take this column over the 250 char size, This is a very long piece of text intented to take this column over the 250 char size	\xFF
000	Exclude this line - no remove_non_utf8() call	plain text
500	This is an ordinary line of text, no changes expected	plain text
501	This line has a 4-byte UTF8 character in 2 columns 🐱	🐱
502	🚢 This line has a ship 🚢 UTF character in 2 columns 🚢	-> 🚢 <-
503	2-byte unicode pound	-> £ <-
504	2-byte unicode (C)	-> © <-
505	2-byte unicode e-grave	-> è <-
506	2-byte unicode e-acute	-> é <-
507	2-byte unicode ij	-> ĳ <-
508	3-byte unicode full-width A	-> Ａ <-
509	3-byte unicode full-width a	-> ａ <-
510	4-byte unicode 10185 (ancient greek)	-> 𐆅 <-
511	Do we have escapes? cat here: \xf0\x9f\x90\xb1	\xf0\x9f\x90\xb1
512	UTF8 followed by 0x80 \xf0\x9f\x90\xb1\x80 <-here	\x80\xf0\x9f\x90\xb1\x80
998	Exclude this line - no remove_non_utf8() call	plain text
\.

EOF
