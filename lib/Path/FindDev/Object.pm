
use strict;
use warnings;

package Path::FindDev::Object;
BEGIN {
  $Path::FindDev::Object::AUTHORITY = 'cpan:KENTNL';
}
{
  $Path::FindDev::Object::VERSION = '0.1.1';
}

# ABSTRACT: Object oriented guts to C<FindDev>

our $ENV_KEY_DEBUG = 'PATH_FINDDEV_DEBUG';
our $DEBUG = ( exists $ENV{$ENV_KEY_DEBUG} ? $ENV{$ENV_KEY_DEBUG} : undef );


use Moo;


has 'set' => ( is => ro =>, predicate => 'has_set' );


has 'os_root' => (
  is      => ro =>,
  lazy    => 1,
  builder => sub {
    require File::Spec;
    require Path::Tiny;
    return Path::Tiny::path( File::Spec->rootdir() )->absolute;
  }
);


has 'uplevel_max' => ( is => ro =>, lazy => 1, predicate => 'has_uplevel_max' );


has 'nest_retry' => ( is => ro =>, lazy => 1, builder => sub { 0 } );


has 'isdev' => (
  is      => ro =>,
  lazy    => 1,
  builder => sub {
    require Path::IsDev::Object;
    return Path::IsDev::Object->new( ( $_[0]->has_set ? ( set => $_[0]->set ) : () ) );
  }
);

my $instances   = {};
my $instance_id = 0;


sub _instance_id {
  my ($self) = @_;
  require Scalar::Util;
  my $addr = Scalar::Util::refaddr($self);
  return $instances->{$addr} if exists $instances->{$addr};
  $instances->{$addr} = sprintf '%x', $instance_id++;
  return $instances->{$addr};
}


sub BUILD {
  my ($self) = @_;
  return $self unless $DEBUG;
  $self->_debug('{');
  $self->_debug( '  set         => ' . $self->set ) if $self->has_set;
  $self->_debug( '  os_root     => ' . $self->os_root );
  $self->_debug( '  uplevel_max => ' . $self->uplevel_max ) if $self->uplevel_max;
  $self->_debug( '  nest_retry  => ' . $self->nest_retry );
  $self->_debug( '  isdev       => ' . $self->isdev );
  $self->_debug('}');
  return $self;
}


sub _debug {
  my ($self,$message) = @_;
  return unless $DEBUG;
  my $id = $self->_instance_id;
  return *STDERR->printf( qq{[Path::FindDev=%s] %s\n}, $id, $message );
}


sub _error {
  my ($self,$message) = @_;
  my $f_message = sprintf( qq{[Path::FindDev=%s] %s\n}, $id, $message );
  require Carp;
  Carp::croak($f_message);
}


sub _step {
  my ( $self, $search_root, $dev_levels, $uplevels ) = @_;

  if ( $self->has_uplevel_max and ${$uplevels} > $self->uplevel_max ) {
    $self->_debug( 'Stopping search due to uplevels(%s) >= uplevel_max(%s)', ${$uplevels}, $self->uplevel_max );
    return { type => 'stop' };
  }
  if ( $search_root->stringify eq $self->os_root->stringify ) {
    $self->_debug('Found OS Root');
    return { type => 'stop' };
  }
  if ( $self->isdev->matches($search_root) ) {
    $self->_debug( 'Found dev dir' . $search_root );
    ${$dev_levels}++;
    return { type => 'found', path => $search_root } if ${$dev_levels} >= $self->nest_retry;
    $self->_debug( sprintf 'Ignoring found dev dir due to dev_levels(%s) < nest_retry(%s)', ${$dev_levels}, $self->nest_retry );
  }
  return { type => 'next' };
}


sub find_dev {
  my ( $self, $path ) = @_;
  require Path::Tiny;
  my $search_root = Path::Tiny::path($path)->absolute;
  $self->_debug( 'Finding dev for ' . $path );
  my $dev_levels = 0;
  my $uplevels   = -1;
FLOW: {
    $uplevels++;
    my $result = $self->_step( $search_root, \$dev_levels, \$uplevels );
    if ( $result->{type} eq 'next' ) {
      $self->_debug('Trying ../');
      $search_root = $search_root->parent;
      redo FLOW;
    }
    if ( $result->{type} eq 'stop' ) {
      return;
    }
    if ( $result->{type} eq 'found' ) {
      return $result->{path};
    }
    $self->_error( 'Unexpected end of flow control with _step response type' . $result->{type} );
  }
  return;
}
1;

__END__

=pod

=encoding utf-8

=head1 NAME

Path::FindDev::Object - Object oriented guts to C<FindDev>

=head1 VERSION

version 0.1.1

=head1 SYNOPSIS

    require Path::FindDev::Object;
    my $finder = Path::FindDev::Object->new();
    my $dev = $finder->find_dev($path);

=head1 DESCRIPTION

This module implements the innards of L<< C<Path::FindDev>|Path::FindDev >>, and is
only recommended for use if the Exporter C<API> is insufficient for your needs.

=head1 METHODS

=head2 C<find_dev>

Find a parent at, or above C<$OtherPath> that resembles a C<devel> directory.

    my $path = $object->find_dev( $OtherPath );

=head1 ATTRIBUTES

=head2 C<set>

B<(optional)>

The C<Path::IsDev::HeuristicSet> subclass for your desired Heuristics.

=head2 C<os_root>

A Path::Tiny object for C<< File::Spec->rootdir >>

=head2 C<uplevel_max>

If provided, limits the number of C<uplevel> iterations done.

( that is, limits the number of times it will recurse up the hierarchy )

=head2 C<nest_retry>

The the number of C<dev> directories to C<ignore> in the heirarchy.

This is provided in the event you have a C<dev> directory within a C<dev> directory, and you wish
to resolve an outer directory instead of an inner one.

By default, this is C<0>, or "stop at the first C<dev> directory"

=head2 C<isdev>

The L<< C<Path::IsDev>|Path::IsDev >> object that checks nodes for C<dev>-ishness.

=head1 PRIVATE METHODS

=head2 C<_instance_id>

An opportunistic sequence number for help with debug messages.

Note: This is not guaranteed to be unique per instance, only guaranteed
to be constant within the life of the object.

Based on C<refaddr>, and giving out new ids when new C<refaddr>'s are seen.

    my $id = $object->_instance_id;

=head2 C<BUILD>

C<BUILD> is an implementation detail of C<Moo>/C<Moose>.

This module hooks C<BUILD> to give a self report of the object
to C<*STDERR> after C<< ->new >> when under C<$DEBUG>

=head2 C<_debug>

The debugger callback.

    export PATH_FINDDEV_DEBUG=1

to get debug info.

    $object->_debug($message);

=head2 C<_error>

The error reporting callback.

    $object->_error($message);

=head2 C<_step>

Inner codepath of tree walking.

    my ($dev_levels, $uplevels ) = (0,0);

    my $result = $object->_step( path($somepath), \$dev_levels, \$uplevels );

    $result->{type} eq 'stop'   # if flow control should end
    $result->{type} eq 'next'   # if flow control should ascend to parent
    $result->{type} eq 'found'  # if flow control has found the "final" dev directory

=head1 AUTHOR

Kent Fredric <kentfredric@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Kent Fredric <kentfredric@gmail.com>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut