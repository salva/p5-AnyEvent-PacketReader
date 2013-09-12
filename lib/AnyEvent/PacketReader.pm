package AnyEvent::PacketReader;

our $VERSION = '0.01';

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(packet_reader);

use AnyEvent;
use Carp;
use Errno qw(EPIPE EMSGSIZE EINTR EAGAIN EWOULDBLOCK);

our $MAX_LOAD_LENGTH = 1e6;

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

sub packet_reader {
    my $cb = pop;
    my ($fh, $templ, $max_load_length) = @_;
    croak 'Usage: packet_reader($fh, [$templ, [$max_load_length,]] $callback)'
        unless defined $fh and defined $cb;

    $max_load_length ||= $MAX_LOAD_LENGTH;
    my $header_length;

    if (defined $templ) {
        unless ($header_length = $header_length{$templ}) {
            if (my ($before, $size_templ, $after) = $templ =~ /^(?:x(\d*))(.*?)(?:x(\d*))$/) {
                if ($header_length = $header_length{$size_templ}) {
                    $header_length += ($before eq '' ? 1 : $before) if defined $before;
                    $header_length += ($after  eq '' ? 1 : $after ) if defined $after;
                    $header_length{$templ} = $header_length;
                }
            }
            $header_length or croak "bad header template '$templ'";
        }
    }


    # data is:  0:buffer, 1:fh, 2:watcher, 3:header_length, 4:total_length, 5: templ, 6: max_load_length, 7:cb
    my $data = [''      , $fh , undef    , $header_length , undef         , $templ  , $max_load_length  , $cb  ];
    my $obj = \\$data;
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
    if (defined my $fh = $data->[1]) {
        $data->[2] = AE::io $fh, 0, sub { _read($data) };
    }
}

sub DESTROY {
    my $obj = shift;
    @{$$obj} = ();
}

sub _read {
    my $data = shift;
    my $length = $data->[4] || $data->[3];
    my $offset = length $data->[0];
    my $remaining = $length - $offset;
    my $bytes = sysread($data->[1], $data->[0], $remaining, $offset);
    if ($bytes) {
        if (length $data->[0] == $length) {
            unless (defined $data->[4]) {
                my $load_length = unpack $data->[5], $data->[0];
                if ($load_length > $data->[6]) {
                    return _fatal($data, EMSGSIZE)
                }
                $data->[4] = $data->[3] + $load_length;
            }
            if (defined $data->[4]) {
                $data->[7]->($data->[0]);
                # somebody may have taken a reference to the buffer so we start clean:
                @$data = ('', @$data[1..3], undef, @$data[5..$#$data]);
            }
        }
    }
    elsif (defined $bytes) {
        return _fatal($data, EPIPE);
    }
    else {
        $! == $_ and return for (EINTR, EAGAIN, EWOULDBLOCK);
        return _fatal($data);
    }
}

sub _fatal {
    my $data = shift;
    local $! = shift if @_;
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
