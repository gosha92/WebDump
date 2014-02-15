#!/usr/bin/perl

use strict;
use Mojo;
use Getopt::Long;
use File::Path;
use File::Basename;
use IO::File;
use Cwd 'abs_path';

++$|;
$\ = "\n";

help() unless @ARGV;

my ($LOG, $ELOG, $WLOG);
GetOptions(
	'log' => \$LOG,
	'elog' => \$ELOG,
	'warn' => \$WLOG,
	'h|help|?' => \&help
) or help();

my $logfh;
if ($ELOG) {
	$logfh = IO::File->new();
	if ($logfh->open('> dump.log')) {
		$logfh->autoflush(1);
	} else {
		wlog("WARNING: Can not open log file [dump.log]!");
		$ELOG = 0;
	}
}

my $baseURL = shift;
help() if ($baseURL eq '');

$baseURL = 'http://'.$baseURL unless ($baseURL =~ /^http/);
$baseURL = Mojo::URL->new($baseURL);
$baseURL->path('/') if ($baseURL->path eq '');

my $PATH = dirname(abs_path(__FILE__)).'/';

my %pages;

my $ua = Mojo::UserAgent->new()->max_redirects(5);

request($baseURL);

Mojo::IOLoop->start();
$logfh->close();



sub slog($) { # Simple log
	return unless $LOG;
	print shift;
}

sub elog($) { # Extended log
	return unless $ELOG;
	print $logfh shift;
}

sub wlog($) { # Warinig log
	return unless $WLOG;
	print "WARNING: ".shift;
}

sub request($) {
	my $URL = $_[0];
	return if $pages{$URL};
	$pages{$URL} = 1;
	$ua->get(
		$URL,
		sub {
			my ($ua, $tx) = @_;
			my $URL = $tx->req->url;
			if (@{$tx->redirects}) {
				return unless ($URL->scheme =~ /^http/);
				return unless ($URL->host eq $baseURL->host);
				return if $pages{$URL};
				$pages{$URL} = 1;	
			}
			elog("\n$URL");
			my $responseCode = $tx->res->code;
			unless ($responseCode =~ /^2/) {
				my ($err, $code) = $tx->error;
				$code = " [$code]" if $code;
				elog("ERR:$code [$err]");
				return;
			}
			my $contentType = $tx->res->headers->content_type;
			elog("$contentType\n");
			return unless $contentType =~ /^text\/html/;
			slog($URL);
			my $a = $tx->res->dom->find('a[href]');
			my @a = $a->attr('href')->each if $a->size;
			my $form = $tx->res->dom->find('form[action]');
			my @form = $form->attr('action')->each if $form->size;
			my $area = $tx->res->dom->find('area[href]');
			my @area = $area->attr('href')->each if $area->size;
			my $frame = $tx->res->dom->find('frame[src]');
			my @frame = $frame->attr('src')->each if $frame->size;
			for (@a, @form, @area, @frame) {
				my $href = $_;
				$href =~ s/#.*$//;
				next unless $href;
				elog("        FOUND: $href");
				my $newURL = Mojo::URL->new($href)->to_abs($URL);
				$newURL->path('/') if ($newURL->path eq '');
				next unless ($newURL->scheme =~ /^http/);
				next unless ($newURL->host eq $baseURL->host);
				next if $pages{$newURL};
				elog("               + $newURL");
				request($newURL);
			}
			save($URL, $tx->res->body);
		}
	);
}

sub save($$) {
	my ($URL, $text) = @_;
	my $fullPath = $PATH.($URL->host).($URL->path);
	my ($fileName, $dirName) = fileparse($fullPath);
	$fileName = 'index.html' unless $fileName;
	unless ($URL->query eq '') {
		$fileName .= '_'.($URL->query);
		$fileName =~ s/[^A-Za-z0-9\._\-\%]/_/g;
	}
	unless (-d $dirName) {
		unless (mkpath $dirName) {
			wlog "Can not make directory [$dirName] [$!]";
			return;
		}
	}
	unless (chdir $dirName) {
		wlog "Can not change directory [$dirName] [$!]";
		return;
	}
	my $fh = IO::File->new();
	unless ($fh->open("> $fileName")) {
		wlog "Can not create file [$fileName] [$!]";
		return;
	}
	$fh->autoflush(1);
	print $fh $text;
	$fh->close();
}

sub help() {
	$\ = '';
	print while (<DATA>);
	exit(0);
}

__DATA__

    USAGE:
	
      webdump.pl [OPTIONS] URL

    OPTIONS:

      -log           -  Log pages names on STDOUT
      -elog          -  Extended log into ./dump.log
      -warn          -  Print warnings on STDOUT
      -h, -help, -?  -  Show this message

    EXAMPLES:

      webdump.pl -log http://qctf.ru
      webdump.pl -log -elog -warn rydlab.ru
