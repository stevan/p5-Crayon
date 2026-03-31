use v5.42;
use utf8;
use Test2::V0;
use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_eval crayon_output ];

# if/else
is crayon_output('if (1) { say "yes" }'), "yes\n", 'if true';
is crayon_output('if (0) { say "yes" } else { say "no" }'), "no\n", 'if-else';
is crayon_output('if (0) { say "a" } elsif (1) { say "b" } else { say "c" }'),
    "b\n", 'if-elsif-else';

# unless
is crayon_output('unless (0) { say "yes" }'), "yes\n", 'unless false';

# postfix if
is crayon_output('say "yes" if 1'), "yes\n", 'postfix if true';
is crayon_output('say "yes" if 0'), "", 'postfix if false';
is crayon_output('say "yes" unless 0'), "yes\n", 'postfix unless';

# while
is crayon_output('my $i = 0; while ($i < 3) { say $i; $i++ }'), "0\n1\n2\n", 'while';

# until
is crayon_output('my $i = 0; until ($i >= 3) { say $i; $i++ }'), "0\n1\n2\n", 'until';

# C-style for
is crayon_output('for (my $i = 0; $i < 3; $i++) { say $i }'), "0\n1\n2\n", 'c-style for';

# foreach
is crayon_output('for my $x (1, 2, 3) { say $x }'), "1\n2\n3\n", 'foreach';

# last/next
is crayon_output('for my $x (1, 2, 3, 4, 5) { last if $x == 3; say $x }'),
    "1\n2\n", 'last';
is crayon_output('for my $x (1, 2, 3, 4, 5) { next if $x == 3; say $x }'),
    "1\n2\n4\n5\n", 'next';

# return — requires subroutines (Task 9), skipping for now
# is crayon_eval('sub foo () { return 42 } foo()'), 42, 'return from sub';

done_testing;
