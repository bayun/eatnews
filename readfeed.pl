#!/usr/bin/perl

use warnings;
use strict;

my $usage = "Usage: feeds.pl <command [arguments]\n
Possible commands:
	add <url>	- add feed URL into read list
	remove <N>	- remove given feed from read list
	read		- read from all URLs in read list
	list		- show read list\n";

my %commands = (
	add => \&add,
	remove => \&remove,
	'read' => \&readFeeds,
	list => \&list,
	itemlist => \&itemlist,
);

if (@ARGV < 1) {
	print $usage;
	exit(1);
}

my $ command = shift @ARGV;

unless (exists $commands{$command}) {
	print $usage;
	return 2;
}

use DBI;
use Regexp::Common qw /URI/;

my $dbName = "items.db";

my $base="dbi:SQLite:dbname=$dbName";
my $dbh = DBI->connect($base,"","",
	{
		PrintError => 0,
	}
);

my @sqlTables = (
'
CREATE TABLE feeds (
id INTEGER PRIMARY KEY asc,
url TEXT UNIQUE
);',

'CREATE TABLE items (
id INTEGER PRIMARY KEY asc,
feedId INTEGER,
title TEXT, 
url TEXT,
content TEXT, 
entryId TEXT UNIQUE,
issued INTEGER
);'
);

# create tables
foreach my $sql(@sqlTables) {
	$dbh->do($sql);
}

my $result = $commands{$command}(@ARGV);
if ($result < 0) {
	print $usage;
	exit(3);
}

exit($result);

sub add {
	return -1 unless (@_ == 1);
	my $url = shift;
	return -1 unless defined $url;
	return -1 unless ( $url =~ /$RE{URI}{HTTP}{-scheme =>'https?'}/);
	$dbh->begin_work();
	my $sth = $dbh->prepare('INSERT INTO feeds (url) VALUES (?)');
#	$sth->bind(1, $url);
	my $changed = $sth->execute($url);
	$dbh->commit();
	return 0 if ($changed);
	print "URL already exists\n";
	return 100;
}

sub remove {
	return -1 unless (@_ == 1);
	my $n = shift;
	return -1 unless defined $n;
	return -1 unless ($n =~ /\d+/);
	$dbh->begin_work();
	my $sth = $dbh->prepare('DELETE FROM feeds WHERE id=?');
	$sth->bind_param(1, $n);
	my $changed = $sth->execute();
	$dbh->commit();
	return 0 if ($changed);
	print "Record with number $n does not exist\n";
	return 100;
}

sub list {
	return -1 if (@_);
	my $sth = $dbh->prepare("SELECT id, url FROM feeds");
	$sth->execute();
	while (my @row = $sth->fetchrow_array()) {
		print "$row[0]\t$row[1]\n";
	}
}

use XML::Feed;

sub readFeeds {
	return -1 if (@_);
	$dbh->begin_work();
	my $sth = $dbh->prepare("SELECT id, url FROM feeds");
	$sth->execute();
	my $sth2 = $dbh->prepare("INSERT OR IGNORE INTO items (feedId, title, url, content, entryId, issued) VALUES(?, ?, ?, ?, ?, ?)");
	if (!$sth2) {
		print "!!!\n";
		return 1;
	}
	while (my ($id, $url) = $sth->fetchrow_array()) {
		my $feed = XML::Feed->parse(URI->new($url));
		unless ($feed) {
			print "Error fetching $url: " . XML::Feed->errstr . "\n";
			next;
		}
		print "Processing $url: " . $feed->title() . "\n";
		for my $entry ($feed->entries) {
			my $result = $sth2->execute($id, $entry->title(), $entry->link(), $entry->content(), $entry->id(), $entry->issued());
		}
	}
	$dbh->commit();
}

sub itemlist {
	return -1 if (@_);
	my $sth = $dbh->prepare('SELECT id, entryId, title FROM items');
	$sth->execute();
	while (my ($id, $entryId, $title) = $sth->fetchrow_array()) {
		print "$id\t$entryId\t$title\n";
	}
}