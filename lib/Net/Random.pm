package Net::Random;

use strict;
use warnings;
use vars qw($VERSION);

$VERSION = '1.0';

require LWP::UserAgent;
use Config;

my $ua = LWP::UserAgent->new(
    agent   => 'perl-Net-Random/'.$VERSION,
    from    => "userid_$<\@".`$Config{aphostname}`,
    timeout => 120,
    keep_alive => 1
);

my %randomness = (
    'fourmilab.ch' => { pool => [], retrieve => sub {
        my $response = $ua->get(
	    'http://www.fourmilab.ch/cgi-bin/uncgi/Hotbits?nbytes=1024&fmt=hex'
	);
	unless($response->is_success) {
	    warn "Net::Random: Error talking to fourmilab.ch\n";
            return ();
	}
	map { map { hex } /(..)/g } grep { /^[0-9A-F]+$/ } split(/\s+/, $response->content());
    } },
    'random.org'   => { pool => [], retrieve => sub {
        my $response = $ua->get('http://www.random.org/cgi-bin/checkbuf');
	if(!$response->is_success) {
	    warn "Net::Random: Error talking to random.org\n";
            return ();
	} else {
	    $response->content() =~ /^(\d+)/;
	    if($1 < 20) {
	        warn "Net::Random: random.org buffer nearly empty, pausing\n";
	        sleep 15;
	        # return &{$randomness{'random.org'}->{retrieve}};
            }
	}
        $response = $ua->get(
	    'http://random.org/cgi-bin/randbyte?nbytes=1024&format=hex'
	);
	unless($response->is_success) {
	    warn "Net::Random: Error talking to random.org\n";
            return ();
	}
	map { hex } split(/\s+/, $response->content());
    } }
);

# recharges the randomness pool
sub _recharge {
    my $self = shift;
    $randomness{$self->{src}}->{pool} = [
        @{$randomness{$self->{src}}->{pool}},
        &{$randomness{$self->{src}}->{retrieve}}
    ];
}

=head1 NAME

Net::Random - get random data from online sources

=head1 SYNOPSIS

    my $rand = Net::Random->new( # use fourmilab.ch's randomness source,
        src => 'fourmilab.ch',   # and return results from 1 to 2000
	min => 1,
	max => 2000
    );
    @numbers = $rand->get(5);    # get 5 numbers
    
    my $rand = Net::Random->new( # use random.org's randomness source,
        src => 'random.org',     # with no explicit range - so values will
    );                           # be in the default range from 0 to 255

    $number = $rand->get();      # get 1 random number

=head1 OVERVIEW

The two sources of randomness above correspond to
L<http://www.fourmilab.ch/cgi-bin/uncgi/Hotbits?nbytes=1024&fmt=hex> and
L<http://random.org/cgi-bin/randbyte?nbytes=1024&format=hex>.  We always
get chunks of 1024 bytes at a time, storing it in a pool which is used up
as and when needed.  The pool is shared between all objects using the
same randomness source.  When we run out of randomness we go back to the
source for more juicy random goodness.

While we always fetch 1024 bytes, data can be used up one, two, three or
four bytes at a time, depending on the range between the minimum and
maximum desired values.  There may be a noticeable delay while more
random data is fetched.  Warnings may be emitted in case of network
problems.

The maintainers of both randomness sources claim that their data is
*truly* random.  A some simple tests show that they are certainly more
random than the C<rand()> function on this 'ere machine.

=head1 METHODS

=over 4

=item new

The constructor returns a Net::Random object.  It takes named parameters,
of which one - 'src' - is compulsory, telling the module where to get its
random data from.  The 'min' and 'max' parameters are optional, and default
to 0 and 255 respectively.  Both must be integers, and 'max' must be at
least min+1.  The minimum value of 'min' is 0.  The maximum value of 'max'
is 2^32-1, the largest value that can be stored in a 32-bit int, or
0xFFFFFFFF.

Currently, the only valid values of 'src' are 'fourmilab.ch' and
'random.org'.

=cut

sub new {
    my($class, %params) = @_;

    exists($params{min}) or $params{min} = 0;
    exists($params{max}) or $params{max} = 255;

    die("Bad parameters to Net::Random->new()") if(
        (grep {
            $_ !~ /^(src|min|max)$/
        } keys %params) ||
	!exists($params{src}) ||
	$params{src} !~ /^(fourmilab\.ch|random\.org)$/ ||
	$params{min} =~ /\D/ ||
	$params{max} =~ /\D/ ||
	$params{min} < 0 ||
	$params{max} > 2 ** 32 - 1 ||
	$params{min} >= $params{max}
    );

    bless({ %params }, $class);
}

=item get

Takes a single optional parameter, which must be a positive integer.
This determines how many random numbers are to be returned and, if not
specified, defaults to 1.

If it fails to retrieve data, we return undef.  Note that fourmilab.ch
rations random data and you are only permitted to retrieve a certain
amount of randomness in any 24 hour period.

=cut

sub get {
    my($self, $results) = @_;
    defined($results) or $results = 1;
    die("Bad parameter to Net::Random->get()") if($results =~ /\D/);

    my $bytes = 5; # MAXBYTES + 1
    foreach my $bits (32, 24, 16, 8) {
        $bytes-- if($self->{max} - $self->{min} < 2 ** $bits);
    }
    die("Out of cucumber error") if($bytes == 5);

    my @results = ();
    while(@results < $results) {
        $self->_recharge() if(@{$randomness{$self->{src}}->{pool}} < $bytes);
	return undef if(@{$randomness{$self->{src}}->{pool}} < $bytes);

	my $random_number = 0;
	$random_number = ($random_number << 8) + $_ foreach (splice(
	    @{$randomness{$self->{src}}->{pool}}, 0, $bytes
	));
	
	my $range = $self->{max} + 1 - $self->{min};
	my $max_multiple = $range * int((2 ** (8 * $bytes)) / $range);
	push @results, $self->{min} + ($random_number % $range)
	    unless($random_number > $max_multiple);
    }
    @results;
}

=back

=head1 BUGS

Doesn't handle really BIGNUMs.  Patches are welcome to make it use
Math::BigInt internally.  Note that you'll need to calculate how many
random bytes to use per result.  I strongly suggest only using BigInts
when absolutely necessary, because they are slooooooow.

Tests are a bit lame.  Really needs to test the results to make sure
they're truly random (to make sure I haven't introduced any bias) and
in the right range.  The current tests for whether the distributions
look sane suck donkey dick.

=head1 FEEDBACK

I welcome feedback about my code, including constructive criticism.  And,
while this is free software (both free-as-in-beer and free-as-in-speech) I
also welcome payment.  In particular, your bug reports will get moved to
the front of the queue if you buy me something from my wishlist, which can
be found at L<http://www.cantrell.org.uk/david/shopping-list/wishlist>.

I do *not* welcome automated bug reports from people who haven't read
the README.  Yes, CPAN-testers, that means you.

=head1 AUTHOR

David Cantrell E<lt>F<david@cantrell.org.uk>E<gt>

Thanks are also due to the maintainers of the randomness sources.  See
their web sites for details on how to praise them.

=head1 COPYRIGHT

Copyright 2003 David Cantrell

This module is free-as-in-speech software, and may be used, distributed,
and modified under the same terms as Perl itself.

=cut

1;
