use strict;
use warnings;
package IO::Socket::Telnet::HalfDuplex;
our $VERSION = '0.02';

use base 'IO::Socket::Telnet';

=head1 NAME

IO::Socket::Telnet::HalfDuplex - more reliable telnet communication

=head1 VERSION

version 0.02

=head1 SYNOPSIS

  use IO::Socket::Telnet::HalfDuplex;
  my $socket = IO::Socket::Telnet::HalfDuplex->new(PeerAddr => 'localhost');
  while (1) {
      $socket->send(scalar <>);
      print $socket->read;
  }

=head1 DESCRIPTION

A common issue when communicating over a network is deciding when input is done
being received. If the communication is a fixed protocol, the protocol should
define this clearly, but this isn't always the case; in particular, interactive
telnet sessions provide no way to tell whether or not the data that has been
sent is the full amount of data that the server wants to send, or whether that
was just a single packet which should be combined with future packets to form
the full message. This module attempts to alleviate this somewhat by providing
a way to estimate how much time you should wait before assuming that all the
data has arrived.

The method used is a slight abuse of the telnet out-of-band option
negotiation - most telnet servers, when told to DO an option that they don't
understand, will respond that they WONT do that option, and will continue to do
so every time (this is not guaranteed by the telnet spec, however - if this
isn't the case, L<IO::Socket::Telnet> is the only option). We can use this
method to get an estimate of how long we should wait for the data. This module
sends a ping in the out-of-band data before reading, with the assumption that
by the time it gets to the server, all the output that has been generated by
your most recent C<send> will already be queued up in the server's output
buffer. This would be guaranteed if we were just communicating with the telnet
server directly, but typically we are communicating with a subprocess spawned
by the telnet server, which means that the telnet server can respond to the
ping while the subprocess is continuing to send data, making this not failsafe.
It's generally a safe assumption for interactive programs across a network,
though, since interactive programs tend to respond quickly, relative to network
latency. After sending the ping, we just read as much as we can until we get
the pong. This process is all wrapped up in the L</read> method provided by
this module; the rest of the interface is just inherited from
L<IO::Socket::Telnet>.

=cut

=head1 CONSTRUCTOR

=head2 new(PARAMHASH)

The constructor takes mostly the same arguments as L<IO::Socket::INET>, but
also accepts the key C<PingOption>, which takes an integer between 40 and 239
to use for the ping/pong mechanism. This defaults to 99 if not specified.

=cut

sub new {
    my $class = shift;
    my %args = @_;
    my $ping = delete $args{PingOption} || 99;
    die "Invalid option: $ping (must be 40-239)" if $ping < 40 || $ping >= 240;
    my $self = $class->SUPER::new(@_);
    ${*{$self}}{ping_option} = $ping;
    $self->IO::Socket::Telnet::telnet_simple_callback(\&_telnet_negotiation);
    return $self;
}

sub telnet_simple_callback {
    my $self = shift;
    ${*$self}{halfduplex_simple_cb} = $_[0] if @_;
    ${*$self}{halfduplex_simple_cb};
}

=head1 METHODS

=cut

=head2 read()

Performs a (hopefully) full read on the socket. Returns the data read. Throws an exception if the connection ends before all data is read.

=cut

sub read {
    my $self = shift;
    my $buffer;

    $self->do(chr(${*{$self}}{ping_option}));
    ${*{$self}}{got_pong} = 0;

    eval {
        local $SIG{__DIE__};

        while (1) {
            my $b;
            defined $self->recv($b, 4096, 0) and do {
                $buffer .= $b;
                die "got pong\n" if ${*{$self}}{got_pong};
                next;
            };
            die "Disconnected from server: $!" unless $!{EINTR};
        }
    };

    die $@ if $@ !~ /^got pong\n/;

    return $buffer;
}

sub _telnet_negotiation {
    my $self = shift;
    my $option = shift;

    my $external_callback = ${*{$self}}{halfduplex_simple_cb};
    my $ping = ${*{$self}}{ping_option};
    if ($option =~ / $ping$/) {
        ${*{$self}}{got_pong} = 1;
        return '' unless $external_callback;
        return $self->$external_callback($option);
    }

    return unless $external_callback;
    return $self->$external_callback($option);
}

=head1 CAVEATS

This is not actually guaranteed half-duplex communication - that's not possible
in general over a telnet connection without specifying a protocol in advance.
This module just does its best to get as close as possible, and tends to do
reasonably well in practice.

=head1 BUGS

No known bugs.

Please report any bugs through RT: email
C<bug-io-socket-telnet-halfduplex at rt.cpan.org>, or browse to
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=IO-Socket-Telnet-HalfDuplex>.

=head1 SEE ALSO

L<IO::Socket::Telnet>, L<IO::Socket::INET>, L<IO::Socket>, L<IO::Handle>

L<http://www.ietf.org/rfc/rfc854.txt>

=head1 CREDITS

This algorithm (and most of the implementation) is due to Shawn Moore (L<http://search.cpan.org/~sartak/>) for projects such as L<TAEB> and L<http://interhack.us>.

=head1 SUPPORT

You can find this documentation for this module with the perldoc command.

    perldoc IO::Socket::Telnet::HalfDuplex

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/IO-Socket-Telnet-HalfDuplex>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/IO-Socket-Telnet-HalfDuplex>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=IO-Socket-Telnet-HalfDuplex>

=item * Search CPAN

L<http://search.cpan.org/dist/IO-Socket-Telnet-HalfDuplex>

=back

=head1 AUTHOR

  Jesse Luehrs <doy at tozt dot net>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2009 by Jesse Luehrs.

This is free software; you can redistribute it and/or modify it under
the same terms as perl itself.

=cut

1;