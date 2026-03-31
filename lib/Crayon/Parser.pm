package Crayon::Parser;
use v5.42;
use utf8;

use Exporter 'import';
use File::Spec ();

use Text::Treesitter::Language;
use Text::Treesitter::Parser;

our @EXPORT_OK = qw[ parse node_text ];

# Locate the share directory relative to this module's location.
# This file lives at lib/Crayon/Parser.pm, so share/ is two levels up.
my $SHARE_DIR = do {
    my $this_file = __FILE__;
    my ($vol, $dir, $file) = File::Spec->splitpath($this_file);
    File::Spec->catdir($vol ? $vol : (), $dir, File::Spec->updir, File::Spec->updir, 'share');
};

my $_parser;

sub _get_parser () {
    return $_parser if $_parser;

    # Try .dylib (macOS) then .so (Linux)
    my $dylib;
    for my $candidate (
        File::Spec->catfile($SHARE_DIR, 'perl.dylib'),
        File::Spec->catfile($SHARE_DIR, 'perl.so'),
    ) {
        if (-f $candidate) {
            $dylib = $candidate;
            last;
        }
    }
    die "Cannot find tree-sitter-perl grammar in $SHARE_DIR\n" unless $dylib;

    my $lang = Text::Treesitter::Language::load($dylib, "perl");

    $_parser = Text::Treesitter::Parser->new;
    $_parser->set_language($lang);

    return $_parser;
}

sub parse ($source) {
    my $tree = _get_parser()->parse_string($source);
    return ($tree, $source);
}

sub node_text ($node, $source) {
    return $node->text;
}

1;
