#!/usr/bin/perl
no  warnings "experimental";
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
my $port = '8002';
$| = 1; # Make sure stdout isn't buffered, so output gets seen by service module
my $server = new IO::Socket::INET (
									LocalPort => $port,
									Proto => 'tcp',
									Listen => 1,
									Reuse => 1,
								);
die "Could not create serveret: $!\n" unless $server;
print "Server running on port $port\n";
$coder = JSON::XS->new->pretty->allow_nonref;
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
		print $client "Cache-Control: no-cache, no-store, must-revalidate\n";
		print $client "Content-type: application/xml\n\n";
		
		my $xml = '';
		my $output = IO::String->new($xml);
		my $writer = XML::Writer->new(OUTPUT => $output, DATA_MODE => 1, DATA_INDENT => 2);
		$writer->xmlDecl('UTF-8');
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
	} elsif ($path =~ m~^/(api|edit)/([^\?]+?)/?(\?(.*))?$~) {
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
			given ($method) {
				when ("track") {
					if ($params{'id'}) {
						print $client "HTTP/1.1 200 Found\n";
						print $client "Content-type: application/xhtml+xml\n";
						print $client "\n";
						
						$dbh = DBI->connect( "dbi:SQLite:dbname=../db/media.sqlite","", "", { RaiseError => 1, AutoCommit => 0 });
						my $tags = $dbh->selectall_arrayref('SELECT label, value, source, tag_id FROM track_tags LEFT JOIN tag ON tag_id = id WHERE track_id = ?', { Slice => {} }, $params{'id'} );
						my $lists = $dbh->selectall_arrayref('SELECT label, value, tag_id FROM track_tags LEFT JOIN tag ON tag_id = id WHERE function = ?', { Slice => {} }, 'list' );
						$dbh->disconnect;
						
						print $client '<?xml version="1.0" encoding="UTF-8"?> 
					<!DOCTYPE HTML> 
					<html xmlns="http://www.w3.org/1999/xhtml"> 
						<head> 
							<title>LucOs - Edit Track Metadata</title> 
							<script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.5.0/jquery.min.js"></script> 
							<script type="text/javascript" src="https://ajax.googleapis.com/ajax/libs/jqueryui/1.8.9/jquery-ui.min.js"></script> 
							<link rel="stylesheet" href="http://ajax.aspnetcdn.com/ajax/jquery.ui/1.8.9/themes/dot-luv/jquery-ui.css" type="text/css" />
							<!--
							<script src="/glow/1.7.5/core/core.js" type="text/javascript"></script>
							<script src="/glow/1.7.5/widgets/widgets.js" type="text/javascript"></script>
							<link href="/glow/1.7.5/widgets/widgets.css" type="text/css" rel="stylesheet" />-->
							<script type="text/javascript" src="/api.js" />
							<script type="text/javascript" src="/track.js" />
							<link rel="stylesheet" href="/edit.css" type="text/css" />
						</head>
						<body class="track">
							<div>';
						my $trackid = encode_entities($params{'id'}, '\'<>&"');
						print $client "<table data-trackid='".$trackid."'>";
						print $client "<tr><th>Label</th><th>Value</th><th>Source</th></tr>\n";
						foreach my $tag ( @$tags ) {
							$label = encode_entities($tag->{label}, '\'<>&"');
							$tag_id = encode_entities($tag->{tag_id}, '\'<>&"');
							$value = encode_entities($tag->{value}, '\'<>&"');
							$source = encode_entities($tag->{source}, '\'<>&"');
							print $client "<tr data-tagid='".$tag_id."'><td class='label'>".$label."</td><td class='value'>".$value."</td><td class='source'>".$source."</td></tr>\n";
						}
						print $client "</table>";
						print $client "</div><div><select multiple='multiple' id='lists'>";
						foreach my $list ( @$lists ) {
							$label = encode_entities($tag->{label}, '\'<>&"');
							$tag_id = encode_entities($tag->{tag_id}, '\'<>&"');
							$value = encode_entities($tag->{value}, '\'<>&"');
							if ($tag->{value} > 0) {
								$selected = ' selected="selected"';
							} else {
								$selected = '';
							}
							print $client "<option value='".$tag_id."'".$selected.">".$label."</option>";
						}
						print $client "</select></div><a href='/edit/tag'>Edit Tags</a></body></html>";
					} else {
						print $client "HTTP/1.1 404 Not Found\n";
						print $client "Content-type: text/plain\n";
						print $client "\n";
						print $client "Need an id\n";
						
					}
				}
				when ("tag") {
					print $client "HTTP/1.1 200 Found\n";
					print $client "Content-type: application/xhtml+xml\n";
					print $client "\n";
					
					$dbh = DBI->connect( "dbi:SQLite:dbname=../db/media.sqlite","", "", { RaiseError => 1, AutoCommit => 0 });
					my $tags = $dbh->selectall_arrayref('SELECT id, label, function FROM tag', { Slice => {} });
					$dbh->disconnect;
						
					print $client '<?xml version="1.0" encoding="UTF-8"?> 
				<!DOCTYPE HTML> 
				<html xmlns="http://www.w3.org/1999/xhtml"> 
					<head> 
						<title>LucOs - Edit Track Metadata</title> 
						<script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.5.0/jquery.min.js"></script> 
						<script type="text/javascript" src="https://ajax.googleapis.com/ajax/libs/jqueryui/1.8.9/jquery-ui.min.js"></script> 
						<link rel="stylesheet" href="http://ajax.aspnetcdn.com/ajax/jquery.ui/1.8.9/themes/dot-luv/jquery-ui.css" type="text/css" />
						<!--
						<script src="/glow/1.7.5/core/core.js" type="text/javascript"></script>
						<script src="/glow/1.7.5/widgets/widgets.js" type="text/javascript"></script>
						<link href="/glow/1.7.5/widgets/widgets.css" type="text/css" rel="stylesheet" />-->
						<script type="text/javascript" src="/api.js" />
						<script type="text/javascript" src="/tag.js" />
						<link rel="stylesheet" href="/edit.css" type="text/css" />
					</head>
					<body class="tag">
						<div>';
						print $client "<table data-trackid='".$trackid."'>";
						print $client "<tr><th/><th>Tag</th><th>Function</th></tr>\n";
						foreach my $tag ( @$tags ) {
							$label = encode_entities($tag->{label}, '\'<>&"');
							$tag_id = encode_entities($tag->{id}, '\'<>&"');
							$function = encode_entities($tag->{function}, '\'<>&"');
							print $client "<tr data-tagid='".$tag_id."'><td class='id'>".$tag_id.". </td><td class='label'>".$label."</td><td class='function'>".$function."</td></tr>\n";
						}
						print $client "</table>";
						print $client "</div></body></html>";
				}
				default {
					print $client "HTTP/1.1 404 Not Found\n";
					print $client "Content-type: text/plain\n";
					print $client "\n";
					print $client "Not Found (/edit)\n";
				}
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
							my @tag = $dbh->selectrow_array('SELECT id, function FROM tag WHERE label = ?', { Slice => {} }, $params{'tag'} );
							$tagid = $tag[0];
							$function = $tag[1];
							if (!$tagid) {
								$dbh->do('INSERT INTO tag (label) VALUES (?)', undef, $params{'tag'} );
								$tagid = $dbh->last_insert_id(undef, undef, 'tag', 'id');
							} else {
								given ($function) {
									when ("multiply") {
										if ($params{'value'} !~ m/^\d+(\.\d+)?$/) {
											$output->{'error'} = ucfirst($params{'tag'})." should be a number";
										}
									}
								}
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
				when ("edittag") {
					if ($params{'label'} or $params{'id'}) {
					#	if ($params{'value'} ~ m/^\d+(\.\d+)?$/) {
					#		$tagid = $1;
					#	}
					/*	my @tag = $dbh->selectrow_array('SELECT id FROM tag WHERE label = ?', { Slice => {} }, $params{'label'} );
						$tagid = $tag[0];
						if (!$tagid) {
							$dbh->do('INSERT INTO tag (label, function) VALUES (?, ?)', undef, $params{'label'}, $params{'function'} );
							$tagid = $dbh->last_insert_id(undef, undef, 'tag', 'id');
						} else {
							$dbh->do('UPDATE tag SET function = ? WHERE id = ?)', undef, $params{'function'}, $tagid );
						}
						$output->{'tagid'} = $tagid;*/
					} else {
						$output->{'error'} = "incorrect params - label is requried (function optional)";
					}
				}
				when ("tags") {
					$output->{'tags'} = $dbh->selectcol_arrayref("SELECT label FROM tag");
				}
				when ("deletetag") {
					#DELETE FROM track_tags WHERE tag_id = ?;
					#DELETE FROM tag WHERE id = ?;
					#DELETE from sqlite_sequence where name = 'tag';
				}
				when ("mergetags") {
					#UPDATE track_tags SET tag_id = ? WHERE tag_id = ?;
					#DELETE FROM tag WHERE id = ?;
					#DELETE from sqlite_sequence where name = 'tag';

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
	} elsif ($path =~ m~^/img/track/(\d+)$~) {
		my $trackid = 1;
		$dbh = DBI->connect( "dbi:SQLite:dbname=../db/media.sqlite","", "", { RaiseError => 1, AutoCommit => 0 });
        my $sth = $dbh->prepare('SELECT img FROM track_img WHERE track_id = ?');
        $sth->execute($trackid);
        my @data = $sth->fetchrow_array();
        $img = $data[0];
		$dbh->disconnect;
		#my @row = $dbh->selectall_arrayref('SELECT img FROM track_img WHERE track_id = ?', { Slice => {} }, $trackid );
		#$img = $row[0][0];
		if ($img) {
			print $client "HTTP/1.1 200 Found\n";
			print $client "Content-type: text\n";
			print $client "\n";
			print $client $img;
			
		} else {
			print $client "HTTP/1.1 404 Not Found\n";
			print $client "\n";
			print $client "Can't find image for track $trackid\n";
			
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
			print $client "Not Found\n";
			print STDERR "Not found: $path\n";
		}
	}
	close $client;
}
