use strict;
use warnings;

use Test::More tests => 2;

use POE qw(
		Wheel::ReadWrite
		Driver::SysRW
		Filter::Line
		Filter::Stream
		Filter::HTTPHead
		Filter::HTTPChunk
		Filter::XML
	);

ok (defined $INC{"POE/Filter/HTTPChunk.pm"}, "loaded");

use IO::File;

my $session = POE::Session->create(
	inline_states => {
		_start => \&start,
		input => \&input,
		error => \&error,
		flushed => \&flushed,
	},
);

autoflush STDOUT 1;
$poe_kernel->run;


sub start {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

	my $filter = POE::Filter::HTTPHead->new;
	my $fh = IO::File->new_from_fd (fileno (DATA), "r");
	$fh->seek (tell(DATA), 0);
	$fh->autoflush;
	
	my $wheel = POE::Wheel::ReadWrite->new (
		Handle => $fh,
		Driver => POE::Driver::SysRW->new (BlockSize => 100),
		InputFilter => $filter,
		InputEvent => 'input',
		ErrorEvent => 'error',
	);
	$heap->{'wheel'} = $wheel;
}

sub input {
	my ($kernel, $heap, $data) = @_[KERNEL, HEAP, ARG0];
	#print STDERR "$data";
	if ($heap->{wheel}->get_input_filter->isa('POE::Filter::HTTPHead')) {
	  if (UNIVERSAL::isa ($data, 'HTTP::Response')) {
	  	my $te = $data->header('Transfer-Encoding');
		my @te = split(/\s*,\s*/, lc($te));
		$te = pop(@te);
		#warn "transfer encoding $te";
		if ($te eq 'chunked') {
	  		$heap->{wheel}->set_input_filter (POE::Filter::HTTPChunk->new);
		} else {
	  		$heap->{wheel}->set_input_filter (POE::Filter::Line->new);
		}
	  } else {
	    #print STDERR "not a response\n";
	  }
	} elsif ($heap->{wheel}->get_input_filter->isa('POE::Filter::HTTPChunk')) {
		if (UNIVERSAL::isa ($data, 'HTTP::Headers')) {
			warn "end";
	  		$heap->{wheel}->set_input_filter (POE::Filter::HTTPHead->new);
		}
		warn $data;
	}
}

sub error {
	my $heap = $_[HEAP];
	my ($type, $errno, $errmsg, $id) = @_[ARG0..$#_];

	is ($errno, 0, "Got EOF");

	delete $heap->{wheel};
}

__DATA__
HTTP/1.1 200 OK
Date: Thu, 11 Nov 2004 19:43:00 GMT
Transfer-Encoding: chunked
Content-Type: text/plain

9
chunk one
CRAP
9
chunk two
0
Server: Apache/1.3.31 (Unix) DAV/1.0.3 mod_gzip/1.3.26.1a PHP/4.3.5 mod_ssl/2.8.19 OpenSSL/0.9.6c

HTTP/1.1 200 OK
Date: Thu, 11 Nov 2004 19:43:00 GMT
Server: Apache/1.3.31 (Unix) DAV/1.0.3 mod_gzip/1.3.26.1a PHP/4.3.5 mod_ssl/2.8.19 OpenSSL/0.9.6c
Transfer-Encoding: chunked
Content-Type: text/plain

B
chunk three
A
chunk four
0

