=head1 NAME

Timelime::SVG - Create SVG timeline charts

=head1 SYNOPSIS

    use SVG::Timeline;

    my $tl = SVG::Timeline->new;

    $tl->add_event({
      start => 1914,
      end   => 1918,
      text  => 'World War I',
    });

    $tl->add_event({
      start => 1939,
      end   => 1945,
      text  => 'World War II',
    });

    print $tl->draw;

=head1 DESCRIPTION

TODO

=head1 METHODS

=head2 new(\%options)

Creates and returns a new SVG::Timeline object. 

Takes an optional hash reference containing configuration options. You
probably don't need any of these, but the following options are supported:

=over 4

=cut


package SVG::Timeline;

use 5.010;

use Moose;
use Moose::Util::TypeConstraints;
use SVG;
use List::Util qw[min max];
use Carp;

use SVG::Timeline::Event;

subtype 'ArrayOfEvents', as 'ArrayRef[SVG::Timeline::Event]';

coerce 'ArrayOfEvents',
  from 'HashRef',
  via { [ SVG::Timeline::Event->new($_) ] },
  from 'ArrayRef[HashRef]',
  via { [ map { SVG::Timeline::Event->new($_) } @$_ ] };

=item * events - a reference to an array containing events. Events are hash
references. See L<add_event> below for the format of events.

=cut

has events => (
  traits  => ['Array'],
  isa     => 'ArrayOfEvents',
  is      => 'rw',
  coerce  => 1,
  default => sub { [] },
  handles => {
    all_events   => 'elements',
    add_event    => 'push',
    count_events => 'count',
    has_events   => 'count',
  },
);

=item * width - the width of the output in any format used by SVG. The default
is 100%.

=cut

has width => (
  is      => 'ro',
  isa     => 'Str',
  default => '100%',
);

=item * height - the height of the output in any format used by SVG. The
default is 100%.

=cut

has height => (
  is      => 'ro',
  isa     => 'Str',
  default => '100%',
);

=item * viewport - a viewport definition (which is a space separated list of
four integers. Unless you know what you're doing, it's probably best to leave
the class to work this out for you.

=cut

has viewbox => (
  is         => 'ro',
  isa        => 'Str',
  lazy_build => 1,
);

sub _build_viewbox {
  my $self = shift;
  return join ' ',
    $self->min_year,
    0,
    $self->years,
    ($self->bar_height * $self->count_events) + $self->bar_height
    + (($self->count_events - 1) * $self->bar_height * $self->bar_spacing);
}

=item * svg - an instance of the SVG class that is used to generate the final
SVG output. Unless you're using a subclass of this class for some reason,
there is no reason to set this manually.

=cut

has svg => (
  is         => 'ro',
  isa        => 'SVG',
  lazy_build => 1,
  handles    => [qw[xmlify line text rect cdata]],
);

sub _build_svg {
  my $self = shift;

  $_->{end} //= (localtime)[5] + 1900 foreach $self->all_events;

  return SVG->new(
    width   => $self->width,
    height  => $self->height,
    viewBox => $self->viewbox,
  );
}

=item * default_colour - the colour that is used to fill the timeline
blocks. This should be defined in the RGB format used by SVG. For example,
red would be 'RGB(255,0,0)'.

=cut

has default_colour => (
  is         => 'ro',
  isa        => 'Str',
  lazy_build => 1,
);

sub _build_default_colour {
  return 'rgb(255,127,127)';
}

=item * years_per_grid - the number of years between vertical grid lines
in the output. The default of 10 should be fine unless your timeline covers
a really long timespan.

=cut

# The number of years between vertical grid lines
has years_per_grid => (
  is      => 'ro',
  isa     => 'Int',
  default => 10, # One decade by default
);

=item * bar_height - the height of an individual timeline bar.

=cut

has bar_height => (
  is      => 'ro',
  isa     => 'Int',
  default => 50,
);

=item * bar_spacing - the height if the vertical space between bars (expresssed
as a decimal fraction of the bar height).

=cut

# Size of the vertical gap between bars (as a fraction of a bar)
has bar_spacing => (
  is      => 'ro',
  isa     => 'Num',
  default => 0.25,
);

=item * decade_line_colour - the colour of the grid lines.

=cut

# The colour that the decade lines are drawn on the chart
has decade_line_colour => (
  is      => 'ro',
  isa     => 'Str',
  default => 'rgb(127,127,127)',
);

=item * bar_outline_colour - the colour that is used for the outline of the
timeline bars.

=cut

# The colour that the bars are outlined
has bar_outline_colour => (
  is      => 'ro',
  isa     => 'Str',
  default => 'rgb(0,0,0)',
);

=back

=head2 draw_grid

=cut

sub draw_grid{
  my $self = shift;

  my $curr_year = $self->min_year;

  # Draw the grid lines
  while ( $curr_year <= $self->max_year ) {
    unless ( $curr_year % $self->years_per_grid ) {
      $self->line(
        x1           => $curr_year,
        y1           => 0,
        x2           => $curr_year,
        y2           => ($self->bar_height * ($self->count_events + 1))
                      + ($self->bar_height * $self->bar_spacing
                         * ($self->count_events - 1)),
        stroke       => $self->decade_line_colour,
        stroke_width => 1
      );
      $self->text(
        x           => $curr_year + 1,
        y           => 20,
        'font-size' => $self->bar_height / 2
      )->cdata($curr_year);
    }
    $curr_year++;
  }

  $self->rect(
     x             => $self->min_year,
     y             => 0,
     width         => $self->years,
     height        => ($self->bar_height * ($self->count_events + 1))
                    + ($self->bar_height * $self->bar_spacing
                       * ($self->count_events - 1)),
     stroke        => $self->bar_outline_colour,
    'stroke-width' => 1,
    fill           => 'none',
  );

  return $self;
}

=head2 draw

=cut

sub draw {
  my $self = shift;
  my %args = @_;

  croak "Can't draw a timeline with no events"
    unless $self->has_events;

  $self->draw_grid;

  my $curr_event_idx = 1;
  foreach ($self->all_events) {
    my $x = $_->start;
    my $y = ($self->bar_height * $curr_event_idx)
          + ($self->bar_height * $self->bar_spacing
             * ($curr_event_idx - 1));

    $self->rect(
      x              => $x,
      y              => $y,
      width          => $_->end - $_->start,
      height         => $self->bar_height,
      fill           => $_->colour // $self->default_colour,
      stroke         => $self->bar_outline_colour,
      'stroke-width' => 1
    );

    $self->text(
      x => $x + $self->bar_height * 0.2,
      y => $y + $self->bar_height * 0.8,
      'font-size' => $self->bar_height * 0.8,
    )->cdata($_->text);

    $curr_event_idx++;
  }

  return $self->xmlify;
}

=head2 min_year

=cut

sub min_year {
  my $self = shift;
  return unless $self->has_events;
  my @years = map { $_->start } $self->all_events;
  return min(@years);
}

=head2 max_year

=cut

sub max_year {
  my $self = shift;
  return unless $self->has_events;
  my @years = map { $_->end // (localtime)[5] } $self->all_events;
  return max(@years);
}

=head2 years

=cut

sub years {
  my $self = shift;
  return $self->max_year - $self->min_year;
}

=head1 AUTHOR
 
Dave Cross <dave@perlhacks.com>
 
=head1 COPYRIGHT AND LICENCE
 
Copyright (c) 2017, Magnum Solutions Ltd. All Rights Reserved.
 
This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
 
=cut

1;
