#! /usr/bin/perl

use lib ".";

use BookEmoji;

binmode STDOUT, ":utf8";

my $e = new BookEmoji;

foreach my $name ($e->names) {
  printf "* \`:$name:\` %s\n", $e->char($name);
}

1;
