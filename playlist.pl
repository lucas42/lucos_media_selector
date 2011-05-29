#!/usr/bin/perl
use DBI;
use XML::Simple;
use XML::Writer;
use IO::Socket qw(:DEFAULT :crlf);
use IO::String;
use JSON::XS;
use HTML::Entities;
use URI::Escape;
use 5.010;
local($/) = LF;
my $server = new IO::Socket::INET (
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
			if ($json) {
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
	} elsif ($path =~ m~^/(api/([^\?]+)|edit)(\?(.*))?$~) {
		$page = $1;
		my $method = $2;
		my %params = ();
		if ($4) {
			my @keyvals = split('&', $4);
			foreach my $keyval (@keyvals) {
				$keyval =~ m/([^=]*)(=(.*))?/;
				$key = $1;
				$val = $3;
				$key =~ s/\+/ /g;
				$val =~ s/\+/ /g;
				$key = uri_unescape($key);
				$val = uri_unescape($val);
				$params{$key} = $val;
			}
			
		}
		if ($page eq "edit") {
			if ($params{'id'}) {
				print $client "HTTP/1.1 200 Found\n";
				print $client "Content-type: application/xhtml+xml\n";
				print $client "\n";
				
				$dbh = DBI->connect( "dbi:SQLite:dbname=../db/media.sqlite","", "", { RaiseError => 1, AutoCommit => 0 });
				my $tags = $dbh->selectall_arrayref('SELECT label, value, source, tag_id FROM track_tags LEFT JOIN tag ON tag_id = id WHERE track_id = ?', { Slice => {} }, $params{'id'} );
				$dbh->disconnect;
				
				print $client '<?xml version="1.0" encoding="UTF-8"?> 
			<!DOCTYPE HTML> 
			<html xmlns="http://www.w3.org/1999/xhtml"> 
				<head> 
					<title>LucOs - Edit Track Metadata</title> 
					<script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.5.0/jquery.min.js"></script> 
					<script type="text/javascript" src="https://ajax.googleapis.com/ajax/libs/jqueryui/1.8.9/jquery-ui.min.js"></script> 
					<link rel="stylesheet" href="http://ajax.aspnetcdn.com/ajax/jquery.ui/1.8.9/themes/dot-luv/jquery-ui.css" type="text/css" />
					<script type="text/javascript" src="/api.js" />
					<script type="text/javascript" src="/edit.js" />
					<link rel="stylesheet" href="/edit.css" type="text/css" />
				</head>
				<body>';
				my $trackid = encode_entities($params{'id'}, '\'<>&"');
				print $client "<table data-trackid='".$trackid."'>";
				print $client "<tr><th>Label</th><th>Value</th><th>Source</th></tr>\n";
				print $client "<tr class='static'><td>track_id</td><td>".$trackid."</td><td></td></tr>\n";
				foreach my $tag ( @$tags ) {
					$label = encode_entities($tag->{label}, '\'<>&"');
					$tag_id = encode_entities($tag->{tag_id}, '\'<>&"');
					$value = encode_entities($tag->{value}, '\'<>&"');
					$source = encode_entities($tag->{source}, '\'<>&"');
					print $client "<tr data-tagid='".$tag_id."'><td class='label'>".$label."</td><td class='value'>".$value."</td><td class='source'>".$source."</td></tr>\n";
				}
				print $client "</table>";
				print $client "</body></html>";
			} else {
				print $client "HTTP/1.1 404 Not Found\n";
				print $client "Content-type: text/plain\n";
				print $client "\n";
				print $client "Need an id\n";
				
			}
			
		} else {
			undef $output;
			$dbh = DBI->connect( "dbi:SQLite:dbname=../db/media.sqlite","", "", { RaiseError => 1, AutoCommit => 0 });
			given ($method) {
				when ("update") {
					if ($params{'tag'} && $params{'value'} && $params{'trackid'}) {
						
						my @track = $dbh->selectrow_array('SELECT 1 FROM track WHERE id = ?', { Slice => {} }, $params{'trackid'} );
						$output->{'track'} = $track[0];
						if ($track[0]) {
							my @tag = $dbh->selectrow_array('SELECT id FROM tag WHERE label = ?', { Slice => {} }, $params{'tag'} );
							$tagid = $tag[0];
							if (!$tagid) {
								$dbh->do('INSERT INTO tag (label) VALUES (?)', undef, $params{'tag'} );
								$tagid = $dbh->last_insert_id(undef, undef, 'tag', 'id');
							}
							$output->{'tagid'} = $tagid;
							$source = 'manual';
							$dbh->do('REPLACE INTO track_tags (track_id, tag_id, value, source) VALUES (?, ?, ?, ?)', undef, $params{'trackid'}, $tagid, $params{'value'}, $source );
							$output->{'source'} = $source;
						} else {
							$output->{'error'} = "Track not found";
						}
					} else {
						$output->{'error'} = "incorrect params - trackid, tag and value are requried";
					}
				}
				when ("tags") {
					$output->{'tags'} = $dbh->selectcol_arrayref("SELECT label FROM tag");
				}
				default {
					$output->{'error'} = "API method not found";
					$output->{'method'} = $method;
				}
			}
			if (!$output->{'error'}) {
				$dbh->commit;
			}
			$dbh->disconnect;
			while (($key, $val) = each(%params)){
					$output->{'params'}->{$key} = $val;
			}
			print $client "HTTP/1.1 200 Found\n";
			print $client "Content-type: application/json\n";
			print $client "\n";
			print $client encode_json $output;
		}
	} else {
		$path =~ s/\.\.//g;
		$path =~ s/\/$/\/index.html/g;
		if (open File, "data".$path) {
			print $client "HTTP/1.1 200 Found\n";
			$path =~ m/^(.+?)(\.(.+?))?$/;
			$base = $1;
			$ext = $3;
			given ($ext) {
				when (['html', 'htm']) {
					$mimetype = "text/html";
				}
				when ('xhmtl') {
					$mimetype = "application/xhtml+xml";
				}
				when ('css') {
					$mimetype = "text/css";
				}
				when ('js') {
					$mimetype = "text/javascript";
				}
				when ('txt') {
					$mimetype = "text/plain";
				}
				default {
					$mimetype = "text/html";
				}
			}
			print $client "Content-type: ".$mimetype."\n";
			print $client "\n";
			while (<File>) {
				print $client $_;
			}
		} else {
			print $client "HTTP/1.1 404 Not Found\n";
			print $client "\n";
			print "Not found: $path\n";
		}
	}
	close $client;
}
