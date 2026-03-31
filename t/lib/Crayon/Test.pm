package Crayon::Test;
use v5.42;
use utf8;
use Exporter 'import';
use Capture::Tiny qw[ capture_stdout ];

our @EXPORT_OK = qw[ crayon_eval crayon_output crayon_ast ];

sub crayon_eval ($source) {
    require Crayon;
    return Crayon::eval_source($source);
}

sub crayon_output ($source) {
    require Crayon;
    my $output = capture_stdout { Crayon::eval_source($source) };
    return $output;
}

sub crayon_ast ($source) {
    require Crayon;
    return Crayon::parse_to_ast($source);
}

1;
