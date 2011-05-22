#!/usr/bin/perl
use DBI;
use XML::Simple;
use XML::Writer;
use IO::Socket qw(:DEFAULT :crlf);
use IO::String;
use JSON::XS;
local($/) = LF;
my $server = new IO::Socket::INET (
									LocalHost => 'localhost',
									LocalPort => '8002',
									Proto => 'tcp',
									Listen => 1,
									Reuse => 1,
								);
die "Could not create serveret: $!\n" unless $server;
$coder = JSON::XS->new->utf8->pretty->allow_nonref;
while($client = $server->accept()) {
   $client->autoflush(1);
	my $path;
	while(<$client>) {
		s/$CR?$LF/\n/;
		if (!(defined $path)) { 
			@parts = split(/\s/, $_);
			$path = @parts[1];
		}
		elsif ($_ eq "\n") { last; }
	}
	if ($path eq "/playlist") {
		print $client "HTTP/1.1 200 Found\n";
		print $client "Content-type: application/xml\n";
		print "Playlist Requested\n";
		
		my $xml = '';
		my $output = IO::String->new($xml);
		my $writer = XML::Writer->new(OUTPUT => $output, DATA_MODE => 1, DATA_INDENT => 2);
		$writer->xmlDecl();
		$writer->startTag('playlist');

		$dbh = DBI->connect( "dbi:SQLite:dbname=../db/media.sqlite","", "", { RaiseError => 1, AutoCommit => 0 });
		my @total_weightings = $dbh->selectcol_arrayref('SELECT MAX(cum_weighting) FROM cache');
		my $total = $total_weightings[0][0];
		for ($ii = 0; $ii < 20; $ii++) {
			my $rand = rand($total);
			my @track = $dbh->selectrow_arrayref('SELECT url, track_id, data FROM cache WHERE cum_weighting > ? ORDER BY cum_weighting ASC LIMIT 1', undef, $rand );
			$url = $track[0][0];
			$id = $track[0][1];
			$json = $track[0][2];
			$writer->startTag('track', 'id' => $id);
			$writer->dataElement('track_id', $id);
			$writer->dataElement('url', $url);
			if ($json ne "{}") {
				$data = $coder->decode($json);
				while (my($key, $val) = each(%{$data})) {
					$writer->dataElement($key, $val);
				}
			}
			$writer->endTag('track');
		}
		$dbh->disconnect;
		$writer->endTag('playlist');
		$writer->end();
		print $client $xml;
	} elsif ($path eq "/") {
		print $client "HTTP/1.1 301 Redirect\n";
		print $client "Location: /playlist\n";
		print $client "\n";
		print "Redirect: $path\n";
	} else {
		print $client "HTTP/1.1 404 Not Found\n";
		print $client "\n";
		print "Not found: $path\n";
	}
	close $client;
}
