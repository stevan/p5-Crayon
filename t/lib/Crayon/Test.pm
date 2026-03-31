package Crayon::Test;
use v5.42;
use utf8;
use Exporter 'import';

our @EXPORT_OK = qw[ crayon_parse crayon_expr ];

sub crayon_parse ($source) {
    require Crayon;
    return Crayon::parse($source);
}

sub crayon_expr ($source) {
    my $ast = crayon_parse($source . ';');
    # Program -> StatementSequence -> first statement
    my $stmt = $ast->{body}{statements}[0];
    return $stmt->{expression} if $stmt->{type} eq 'ExpressionStatement';
    return $stmt;
}

1;
