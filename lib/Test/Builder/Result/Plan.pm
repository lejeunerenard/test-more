package Test::Builder::Result::Plan;
use strict;
use warnings;

use parent 'Test::Builder::Result';

Test::Builder::Result::_accessors(qw/max directive reason/);

sub to_tap {
    my $self = shift;

    my $max       = $self->max;
    my $directive = $self->directive;
    my $reason    = $self->reason;

    my $plan = "1..$max";
    $plan .= " # $directive" if defined $directive;
    $plan .= " $reason"      if defined $reason;

    return "$plan\n";
}


1;