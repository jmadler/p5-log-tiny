package Log::Tiny;

use strict;
use warnings;
use Scalar::Util ();
our ($AUTOLOAD, $VERSION, $errstr, %formats, $caller_depth);

# Extra caller frames to skip for the %F/%L/%P/%S formats. Wrapper
# authors can `local $Log::Tiny::caller_depth = 1;` (etc.) so those
# formats report their own caller rather than the wrapper.
$caller_depth = 0;

=head1 NAME

Log::Tiny - Log data with as little code as possible

=head1 VERSION

Version 1.1

=cut

$VERSION = '1.1';
$errstr = '';

%formats = (
    c => [ 's', sub { shift }, ],           # category: AUTOLOAD
    C => [ 's', sub { lc shift }, ],        # lcategory: AUTOLOAD lc
    f => [ 's', sub { $0 }, ],              # program_file: $0
    F => [ 's', sub { (caller(2 + $caller_depth))[1] }, ],  # caller_file: caller
    g => [ 's', sub { scalar gmtime }, ],   # gmtime: scalar gmtime
    L => [ 'd', sub { (caller(2 + $caller_depth))[2] }, ],  # caller_line: caller
    m => [ 's', sub { shift; shift }, ],    # message: args
    n => [ 's', sub { $/ }, ],              # newline: $/
    o => [ 's', sub { $^O }, ],             # osname: $^O
    p => [ 'd', sub { $$ }, ],              # pid: $$
    P => [ 's', sub { (caller(2 + $caller_depth))[0] }, ],  # caller_pkg: caller
    r => [ 'd', sub { time - $^T }, ],      # runtime: $^T
    S => [ 's', \&__format_S, ],            # caller_sub: caller
    t => [ 's', sub { scalar localtime }, ],# localtime: scalar localtime
    T => [ 'd', sub { time }, ],            # unix_time: time
    u => [ 'd', sub { $> }, ],              # effective_uid: $>
    U => [ 'd', sub { $< }, ],              # real_uid: $<
    v => [ 'd', sub { $] }, ],              # long_perl_ver: $]
    V => [ 's', sub { sprintf("%vd", $^V) }, ], # short_perl_ver
);

sub __format_S { my $t = (caller(2 + $caller_depth))[3];  if ( !defined $t || $t eq 'Log::Tiny::AUTOLOAD' ) { $t = 'main'; }; $t;  }

=head1 SYNOPSIS

This module aims to be a light-weight implementation 
*similar* to L<Log::Log4perl> for logging data to a file.

Its use is very straight forward:

    use Log::Tiny;

    my $log = Log::Tiny->new( 'myapp.log' ) or 
      die 'Could not log! (' . Log::Tiny->errstr . ')';

    foreach ( 1 .. 20 ) { 
        $log->DEBUG( "Performing extensive computations on $_" ) if $DEBUG;
        unless ( extensively_compute( $_ ) ) {
            $log->WARN( 
                "Investigating error (this may take a while)..." 
            );
            $log->ERROR( find_error() );
            save_state();
            exit 1;
        } else {
            $log->INFO( "Everything's A-OK!" );
        }
    }

=head1 FUNCTIONS

=head2 new

Create a new Log::Tiny object.  The first argument is the log
destination and, optionally, a format follows.

The destination may be:

=over 4

=item * a filename, which is opened for append (the common case);

=item * an already-open filehandle (glob, glob ref or IO::Handle
object), which is used as-is and B<not> closed when the object is
destroyed -- handy for logging to C<\*STDERR> or a handle you manage;

=item * the string C<"-">, which logs to C<STDOUT>.

=back

An optional third argument is a hash reference of format specifications
that are merged over (and so may extend or override) the defaults for
this object only.  The format table is snapshotted per-instance, so
customising one Log::Tiny object never affects another.

=cut

sub new {
    my $pkg = shift;
    my $logfile = shift;
    return _error('No logfile provided') unless defined $logfile && length $logfile;
    my $format = shift || '[%t] %f:%p (%c) %m%n';
    my $custom = shift;   # optional hashref of extra/override format specs

    # snapshot the format table per-instance so customisation does not
    # leak across objects (the package %formats stays the default template)
    my %fmt = %formats;
    %fmt = ( %fmt, %$custom ) if ref $custom eq 'HASH';

    my ( $logfh, $owns_fh );
    if ( defined Scalar::Util::openhandle($logfile) ) {
        # caller passed an already-open handle: use it, and don't close it
        $logfh   = $logfile;
        $owns_fh = 0;
    } elsif ( $logfile eq '-' ) {
        $logfh   = \*STDOUT;
        $owns_fh = 0;
    } else {
        open ( $logfh, '>>', $logfile ) ||
            return _error( "Could not open $logfile: $!" );
        $owns_fh = 1;
    }
    $logfh->autoflush(1);
    my $self = bless {
        format => $format,
        methods_only => [],
        logfile => $logfile,
        logfh => $logfh,
        owns_fh => $owns_fh,
        formats => \%fmt,
    }, $pkg;
    $self->format();
    return $self;
}

=head2 format

You may, at any time, change the format.  The log format is 
similar in style to the sprintf you know and love; and, as 
a peek inside the source of this module will tell you, sprintf
is used internally.  However, be advised that these log formats 
B<are not sprintf>.

Interpolated data are specified by an percent sign (C< % >), 
followed by a character.  A literal percent sign can be 
specified via two in succession ( C< %% > ).  You may use any
of the formatting attributes as noted in L<perlfunc>, under 
"sprintf" (C<perldoc -f sprintf>).

Internally, the format routine uses a data structure (hash) 
that can be seen near the beginning of this package.  Any 
unrecognized interpolation variables will be returned 
literally.  This means that, assuming $format{d} does not 
exist, "%d" in your format will result in "%d" being outputted
to the log file.  No interpolation will occur.

You may, of course, decide to modify the format data structure.
I have done my best to ensure a wide range of variables for your 
usage, however.  They are (currently) as follows:

    c => category       => The method called (see below for more info)
    C => lcategory      => lowercase category
    f => program_file   => Value of $0
    F => caller_file    => Calling file
    g => gmtime         => Output of scalar L<gmtime> (localized date string)
    L => caller_line    => Calling line
    m => message        => Message sent to the log method
    n => newline        => Value of $/
    o => osname         => Value of $^O
    p => pid            => Value of $$
    P => caller_pkg     => Calling package
    r => runtime        => Seconds the current process has been running for
    S => caller_sub     => Calling subroutine
    t => localtime      => Output of scalar L<localtime> (localized date 
                           string)
    T => unix_time      => Time since epoch (L<time>)
    u => effective_uid  => Value of $>
    U => real_uid       => Value of $<
    v => long_perl_ver  => Value of $] (5.008008)
    V => short_perl_ver => A "short" string for the version ("5.8.8")

See L<perlvar> for information on the used global variables, and 
L<perlfunc> (under "caller") or C<perldoc -f caller> for information
on the "calling" variables.  Oh, and make sure you add %n if you want
newlines.

=cut

sub format {
    my $self = shift;
    if ( $_[0] ) {
        $self->{format} = shift;
    }
    $self->{args} = [];
    # make real format
    my $format = join '', keys %{ $self->{formats} };
    $self->{format} =~ 
      s/%(-?\d*(?:\.\d+)?)([$format])/_replace($self, $1, $2);/gex;
      # thanks, mschilli
    return $self->{format};
}

sub _replace {
    my ( $self, $num, $op ) = @_;
    return '%%' if $op eq '%';
    return "%%$op" unless defined $self->{formats}{$op};
    push @{ $self->{args} }, $op;
    return "%$num" . $self->{formats}{$op}->[ 0 ];
}

=head2 WHATEVER_YOU_WANT (log a message)

This method is whatever you want it to be.  Any method called
on a Log::Tiny object that is not reserved will be considered 
an attempt to log in the category named the same as the method 
that was called.  Currently, only in-use methods are reserved;
However, to account for expansion, please only use uppercase 
categories.  See formats above for information on customizing
the log messages.

=cut

sub AUTOLOAD {
    my $self = shift;
    my $method = $AUTOLOAD;
    $method =~ s/.*:://;
    return _error( "Log routine ($method) is not a class method" ) 
        unless defined ref $self;
    if (@{ $self->{methods_only} }) { 
        my $in = 0;
        foreach (@{ $self->{methods_only} }) {
            $in++ if uc $method eq uc $_;
        }
        return _error( "Log category '$method' not in whitelist" )
          unless $in;
    }
    # severity threshold (only when levels()/min_level() are configured);
    # categories that are not ranked always pass through
    if ( defined $self->{min_level} && $self->{level_map} ) {
        my $lvl = $self->{level_map}{ uc $method };
        return 0 if defined $lvl && $lvl < $self->{min_level};
    }
    my $tmp = '';
    $tmp .= sprintf ( 
        $self->{format}, 
        $self->_mk_args( $method, $_ ),
    ) foreach @_;
    return print {$self->{logfh}} $tmp;
}

sub _mk_args {
    my $self = shift;
    my ( $method, $msg ) = @_;
    $msg = '' unless defined $msg;
    my @ret = @{ $self->{args} };
    my %need = map { $_ => undef } @ret;
    foreach ( keys %need ) {
        $need{ $_ } = $self->{formats}{ $_ }->[ 1 ]->( $method, $msg );
    }
    s/^(\w)$/$need{$1}/e foreach @ret;
    return @ret;
}

sub DESTROY {
    my $self = shift;
    # only close handles we opened ourselves; leave caller-supplied
    # handles (STDERR, STDOUT, etc.) alone
    return unless $self->{owns_fh};
    close $self->{logfh} or warn "Couldn't close log file: $!";
}

=head2 errstr

Called as a class method, C< Log::Tiny->errstr > reveals the 
error that Log::Tiny encountered in creation or invocation.

=cut

sub errstr { $errstr; }
sub _error { $errstr = shift; undef; }

=head2 Caller depth (C<$Log::Tiny::caller_depth>)

The C<%F>, C<%L>, C<%P> and C<%S> formats report the file, line,
package and subroutine of the code that called the log method.  If you
wrap your logging in a helper of your own, that helper becomes the
apparent caller.  As with L<Log::Log4perl>, localise
C<$Log::Tiny::caller_depth> to skip the extra frame(s):

    sub my_log {
        local $Log::Tiny::caller_depth = 1;
        $log->INFO( @_ );
    }

=head2 log_only

Log only the given categories

=cut

sub log_only {
    my $self = shift;
    $self->{methods_only} = \@_;
}

=head2 levels

Define an ordered list of severities, least to most severe:

    $log->levels( [qw(DEBUG INFO WARN ERROR FATAL)] );

Level names are compared case-insensitively.  On their own, levels do
nothing; combine with L</min_level> to filter.  This is independent of
L</log_only> (which whitelists exact categories).

=cut

sub levels {
    my $self = shift;
    my $list = shift;
    return _error('levels() expects an array reference')
        unless ref $list eq 'ARRAY';
    my %map;
    my $i = 0;
    $map{ uc $_ } = $i++ for @$list;
    $self->{level_map} = \%map;
    return $self->{level_map};
}

=head2 min_level

Get or set the minimum severity that will be logged.  Categories at or
above the threshold are logged; those below it are dropped; categories
not present in the L</levels> list are always logged.

    $log->min_level('WARN');   # set
    my $current = $log->min_level;   # get (undef if unset)

Requires L</levels> to have been called first.  Returns C<undef> (and
sets L</errstr>) for an unknown level name.

=cut

sub min_level {
    my $self = shift;
    return $self->{min_level_name} unless @_;   # getter
    my $name = uc shift;
    my $map = $self->{level_map}
        or return _error('Call levels() before min_level()');
    return _error("Unknown level '$name'") unless exists $map->{$name};
    $self->{min_level}      = $map->{$name};
    $self->{min_level_name} = $name;
    return $name;
}

=head1 AUTHOR

Jordan M. Adler, C<< <jmadler at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-log-tiny at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Log-Tiny>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Log::Tiny

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Log-Tiny>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Log-Tiny>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Log-Tiny>

=item * Search CPAN

L<http://search.cpan.org/dist/Log-Tiny>

=item * GitHub

L<https://github.com/jmadler/p5-log-tiny>

=back

=head1 ACKNOWLEDGEMENTS

Much thanks to Michael Schilli C<CPAN:mschilli> for his great work on 
Log::Log4perl, of which this module's formatting concept is largely based upon.

=head1 COPYRIGHT & LICENSE

Copyright 2007-2022 Jordan M. Adler, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Log::Tiny
