package Crayon;
use v5.42;
use utf8;

use Crayon::Parser;
use Crayon::Transform;

sub parse ($source) {
    my ($tree, $src) = Crayon::Parser::parse($source);
    return Crayon::Transform::transform($tree->root_node, $src);
}

1;
