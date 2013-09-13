package AnyEvent::PacketReader;

our $VERSION = '0.01';

use strict;
use warnings;
use 5.010;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(packet_reader);

use AnyEvent;
use Carp;
use Errno qw(EPIPE EBADMSG EMSGSIZE EINTR EAGAIN EWOULDBLOCK);

our $MAX_TOTAL_LENGTH = 1e6;

our $debug;

my %header_length = ( n => 2,
                      v => 2,
                      N => 4,
                      V => 4,
                      W => 1,
                      S => 2,
                      L => 4,
                      Q => 8 );

for my $dir (qw(> <)) {
    for my $t (qw(S L Q)) {
        $header_length{"$t$dir"} = $header_length{$t};
    }
}

my %load_offset = %header_length;
my $good_packers = join '', keys %header_length;

sub packet_reader {
    my $cb = pop;
    my ($fh, $templ, $max_total_length) = @_;
    croak 'Usage: packet_reader($fh, [$templ, [$max_total_length,]] $callback)'
        unless defined $fh and defined $cb;

    $max_total_length ||= $MAX_TOTAL_LENGTH;
    my $header_length;

    if (defined $templ) {
        unless ($header_length = $header_length{$templ}) {
            my $load_offset;
            if ($templ =~ /^(x+)(\d*)/g) {
                $header_length = length $1 + (length $2 ? $2 - 1 : 0);
            }
            elsif ($templ =~ /^\@!(\d*)/g) {
                $header_length = (length $1 ? $1 : 1);
            }
            else {
                $header_length = 0;
            }

            $templ =~ /\G([$good_packers][<>]?)/go
                or croak "bad header template '$templ'";

            $header_length += ($header_length{$1} // die "Internal error: \$header_length{$1} is not defined");

            if ($templ =~ /\G\@!(\d*)/g) {
                $load_offset =  (length $1 ? $1 : 1);
            }
            else {
                $load_offset = $header_length;
                if ($templ =~ /\G(x+)(\d*)/g) {
                    $load_offset += length $1 + (length $2 ? $2 - 1 : 0);
                }
            }

            $templ =~ /\G$/g or croak "bad header template '$templ'";

            $header_length{$templ} = $header_length;
            $load_offset{$templ} = $load_offset;
        }
    }
    else {
        $templ = 'N';
        $header_length = 4;
    }

    # data is:  0:buffer, 1:fh, 2:watcher, 3:header_length, 4:total_length, 5: templ, 6: max_total_length, 7:cb
    my $data = [''      , $fh , undef    , $header_length , undef         , $templ  , $max_total_length  , $cb  ];
    my $obj = \$data;
    bless $obj;
    $obj->resume;
    $obj;
}

sub pause {
    my $data = ${shift()};
    $data->[2] = undef;
}

sub resume {
    my $data = ${shift()};
    if (defined(my $fh = $data->[1])) {
        $data->[2] = AE::io $fh, 0, sub { _read($data) };
    }
}

sub DESTROY {
    my $obj = shift;
    $debug and warn "PR: watcher is gone, aborting read\n" if ${$obj}->[3];
    @{$$obj} = ();
}

sub _hexdump {
    no warnings qw(uninitialized);
    while ($_[0] =~ /(.{1,32})/smg) {
        my $line = $1;
        my @c= (( map { sprintf "%02x",$_ } unpack('C*', $line)),
                (("  ") x 32))[0..31];
        $line=~s/(.)/ my $c=$1; unpack("c",$c)>=32 ? $c : '.' /egms;
        print STDERR "$_[1] ", join(" ", @c, '|', $line), "\n";
    }
    print STDERR "\n";

}

sub _read {
    my $data = shift;
    my $length = $data->[4] || $data->[3];
    my $offset = length $data->[0];
    my $remaining = $length - $offset;
    my $bytes = sysread($data->[1], $data->[0], $remaining, $offset);
    if ($bytes) {
        $debug and warn "PR: $bytes bytes read\n";
        if (length $data->[0] == $length) {
            unless (defined $data->[4]) {
                my $templ = $data->[5];
                my $load_length = unpack $templ, $data->[0];
                unless (defined $load_length) {
                    $debug and warn "PR: unable to extract size field from header\n";
                    return _fatal($data, EBADMSG);
                }
                my $total_length = $load_offset{$templ} + $load_length;
                $debug and warn "PR: reading full packet ".
                    "(load length: $load_length, total: $total_length, current: $length)\n";

                if ($total_length > $data->[6]) {
                    $debug and warn "PR: received packet is too long\n";
                    return _fatal($data, EMSGSIZE)
                }
                if ($length < $total_length) {
                    $data->[4] = $total_length;
                    return;
                }
                # else, the packet is done
                if ($length > $total_length) {
                    $debug and warn "PR: header length ($length) > total length ($total_length)\n";
                    _fatal($data, EBADMSG);
                }
            }

            $debug and warn "PR: packet read, invoking callback\n";
            $data->[7]->($data->[0]);
            # somebody may have taken a reference to the buffer so we start clean:
            @$data = ('', @$data[1..3], undef, @$data[5..$#$data]);
            $debug and warn "PR: waiting for a new packet\n";
        }
    }
    elsif (defined $bytes) {
        $debug and warn "PR: EOF!\n";
        return _fatal($data, EPIPE);
    }
    else {
        $debug and warn "PR: sysread failed: $!\n";
        $! == $_ and return for (EINTR, EAGAIN, EWOULDBLOCK);
        return _fatal($data);
    }
}

sub _fatal {
    my $data = shift;
    local $! = shift if @_;
    if ($debug) {
        warn "PR: fatal error: $!\n";
        _hexdump($data->[0], 'pkt:');
    }
    $data->[7]->();
    @$data = (); # release watcher;
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

AnyEvent::PacketReader - Perl extension for blah blah blah

=head1 SYNOPSIS

  use AnyEvent::PacketReader;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for AnyEvent::PacketReader, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Salvador Fandino, E<lt>salva@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Salvador Fandino

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.2 or,
at your option, any later version of Perl 5 you may have available.


=cut
