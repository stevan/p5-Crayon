package Crayon;
use v5.42;
use utf8;

use Crayon::Parser;
use Crayon::Transform;
use Crayon::Interpreter;

sub eval_source ($source) {
    my $ast = parse_to_ast($source);
    my $interp = Crayon::Interpreter->new;
    return $interp->eval($ast);
}

sub parse_to_ast ($source) {
    my ($tree, $src) = Crayon::Parser::parse($source);
    return Crayon::Transform::transform($tree->root_node, $src);
}

1;
