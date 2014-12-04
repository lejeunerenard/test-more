package Test::Workflow;
use strict;
use warnings;

use Test::Stream;

use Test::Workflow::Group;
use Test::Workflow::Block;
use Test::Workflow::Scheduler;

use Test::Stream::Util qw/try/;
use Test::Stream::Carp qw/croak/;

use Test::Stream::Exporter;

our %STACKS;

Test::Workflow::Scheduler->define(
    tests => {},

    case => { affix => 'each', alter => 'tests' },

    before_all => { affix => 'all', alter => 'tests' },
    after_all  => { affix => 'all', alter => 'tests' },
    around_all => { affix => 'all', alter => 'tests' },

    before_each => { affix => 'each', alter => 'tests', outside => ['case'] },
    after_each  => { affix => 'each', alter => 'tests', outside => ['case'] },
    around_each => { affix => 'each', alter => 'tests', outside => ['case'] },

    before_case => { affix => 'each', alter => 'case' },
    after_case  => { affix => 'each', alter => 'case' },
    around_case => { affix => 'each', alter => 'case' },
);

for my $prefix (qw/before after around/) {
    for my $component (qw/case each all/) {
        _generate_adder("${prefix}_${component}");
    }
}

_generate_adder('case');
_generate_adder('tests');

{
    no warnings 'once';
    *it       = \&tests;
    *cases    = \&workflow;
    *describe = \&workflow;
}

default_export qw{
    before_each after_each around_each
    before_all  after_all  around_all
    before_case after_case around_case

    case

    workflow cases describe

    tests it

    run_workflow
    root_workflow
};

sub before_import {
    my ($caller, $args) = @_;
    my @new_args;
    my %run_params;

    while(my $arg = shift @$args) {
        if ($arg =~ m/^-(.+)$/) {
            $run_params{$arg} = shift @$args;
            next;
        }
        push @new_args => $arg;
    }
    @$args = @new_args;

    return if $run_params{no_auto};

    Test::Stream->shared->follow_up(
        sub {
            run_workflow(%run_params, workflow => $STACKS{$caller});
        }
    );
}

sub _parse_params {
    my ($tool, $args) = @_;

    my $name   = shift;
    my $code   = pop;
    my %params = @_;

    my ($pkg, $file, $line, $sub) = caller(1);

    die "The first argument to '$tool' must be a name at $file line $line.\n"
        unless $name && !ref $name;

    die "The last argument to '$tool' must be a coderef at $file line $line.\n"
        unless $code && ref($code) && reftype($code) eq 'CODE';

    my $block = Test::Workflow::Block->new_from_pairs(
        coderef => $code,
        name    => $name,
        caller  => [$pkg, $file, $line, $sub],
        params  => \%params
    );

    $STACKS{$pkg} ||= [Test::Workflow::Group->new_from_pairs(
        name   => "$pkg (root)",
        caller => [$pkg, $file, 0, undef],
        root   => $pkg
    )];

    return ($name, $block, \%params, [$pkg, $file, $line, $sub]);
}

sub _generate_adder {
    my ($type) = @_;
    my $subname = "add_$type";

    # Use an eval to ensure the sub is named instead of __ANON__ in any traces.
    eval <<"    EOT" || die $@;
        sub $subname {
            my (\$name, \$block, \$params, \$caller) = _parse_params('$subname', \\\@_);
            \$STACKS{\$caller->[0]}->[-1]->add(type => '$type', item => \$block);
        }

        1;
    EOT
}

sub workflow {
    my ($name, $block, $params, $caller) = _parse_params('workflow', \@_);
    my $pkg = $caller->[0];

    my $workflow = Test::Workflow::Group->new_from_pairs(
        type   => 'group',
        params => $params,
        name   => $name,
        caller => $caller,
        block  => $block,
    );

    push @{$STACKS{$pkg}} => $workflow;
    my ($ok, $err) = &try($block->coderef);
    pop @{$STACKS{$pkg}};

    if ($ok) {
        $STACKS{$pkg}->[-1]->add(type => 'group', item => $workflow);
    }
    else {
        die $err;
    }

    return $workflow;
}

sub run_workflow {
    my %params = @_;
    my $caller = caller;

    $params{workflow} ||= $STACKS{$caller} || croak "No workflow for package '$caller', and no workflow provided.";

    my $scheduler = delete $params{scheduler} || 'Test::Workflow::Scheduler';
    $scheduler->run(%params);
}

sub root_workflow {
    my $pkg = shift || caller;
    return $STACKS{$pkg};
}

1;
