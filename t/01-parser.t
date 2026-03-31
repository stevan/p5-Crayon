use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Parser;

# Smoke test: can we parse Perl source?
{
    my ($tree, $source) = Crayon::Parser::parse('my $x = 42;');
    my $root = $tree->root_node;
    is $root->type, 'source_file', 'root node is source_file';
    ok $root->child_count > 0, 'root has children';
}

# Verify key node types exist
{
    my ($tree, $source) = Crayon::Parser::parse('my $x = 1 + 2;');
    my $root = $tree->root_node;

    # Walk and collect all named node types
    my @types;
    my $walk; $walk = sub ($node) {
        push @types, $node->type if $node->is_named;
        for my $child ($node->child_nodes) {
            $walk->($child);
        }
    };
    $walk->($root);

    ok((grep { $_ eq 'variable_declaration' } @types), 'found variable_declaration');
    ok((grep { $_ eq 'binary_expression' } @types),    'found binary_expression');
    ok((grep { $_ eq 'number' } @types),               'found number');
}

# Verify node text
{
    my $code = 'say "hello";';
    my ($tree, $source) = Crayon::Parser::parse($code);
    my $root = $tree->root_node;
    is $root->text, $code, 'node text returns source text';
}

done_testing;
