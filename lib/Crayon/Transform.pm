package Crayon::Transform;
use v5.42;
use utf8;

use Exporter 'import';

use Crayon::AST qw[
    Program StatementSequence ExpressionStatement Block
    Integer Float String Bool Undef SpecialLiteral QuotedWords Yada
    Call
];

our @EXPORT_OK = qw[ transform ];

# --- Main entry point ---

sub transform ($node, $source) {
    _transform_node($node, $source);
}

# --- Recursive dispatcher ---

sub _transform_node ($node, $source) {
    my $type = $node->type;

    # Skip comment nodes
    return undef if $node->is_extra;

    my $handler = __PACKAGE__->can("_transform_${type}");
    if ($handler) {
        return $handler->($node, $source);
    }

    die sprintf(
        "Unsupported CST node type '%s' at byte %d\n",
        $type, $node->start_byte,
    );
}

# --- Structure ---

sub _transform_source_file ($node, $source) {
    my @statements;
    for my $child ($node->child_nodes) {
        next unless $child->is_named;
        next if $child->is_extra;
        my $transformed = _transform_node($child, $source);
        push @statements, $transformed if defined $transformed;
    }
    Program(StatementSequence(\@statements));
}

sub _transform_expression_statement ($node, $source) {
    my @children = grep { $_->is_named && !$_->is_extra } $node->child_nodes;
    die "expression_statement has no children\n" unless @children;
    my $expr = _transform_node($children[0], $source);
    ExpressionStatement($expr);
}

sub _transform_block ($node, $source) {
    my @statements;
    for my $child ($node->child_nodes) {
        next unless $child->is_named;
        next if $child->is_extra;
        my $transformed = _transform_node($child, $source);
        push @statements, $transformed if defined $transformed;
    }
    Block(StatementSequence(\@statements));
}

# --- Literals ---

sub _transform_number ($node, $source) {
    my $text = $node->text;
    # Float if it contains a decimal point or scientific notation,
    # but NOT if it's hex (0x...), binary (0b...), or octal (0...)
    if ($text =~ /[.eE]/ && $text !~ /^0[xXbB]/) {
        return Float($text);
    }
    Integer($text);
}

sub _transform_string_literal ($node, $source) {
    # Extract string content from between the quote delimiters
    my $value = _extract_string_content($node);
    String($value, 0);
}

sub _transform_interpolated_string_literal ($node, $source) {
    my $value = _extract_string_content($node);
    String($value, 1);
}

sub _transform_command_string ($node, $source) {
    my $value = _extract_string_content($node);
    String($value, 1);
}

sub _extract_string_content ($node) {
    my @parts;
    for my $child ($node->child_nodes) {
        if ($child->is_named) {
            push @parts, $child->text;
        }
    }
    join('', @parts);
}

sub _transform_boolean ($node, $source) {
    my $text = $node->text;
    Bool($text eq 'true' ? 1 : 0);
}

sub _transform_undef_expression ($node, $source) {
    Undef();
}

sub _transform_yadayada ($node, $source) {
    Yada();
}

sub _transform_quoted_word_list ($node, $source) {
    # qw(a b c) — extract the words from string_content children
    my @words;
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'string_content') {
            push @words, split(/\s+/, $child->text);
        }
    }
    QuotedWords(\@words);
}

sub _transform_func0op_call_expression ($node, $source) {
    my $text = $node->text;
    if ($text eq '__FILE__' || $text eq '__LINE__' || $text eq '__PACKAGE__') {
        return SpecialLiteral($text);
    }
    # For other zero-arg builtins, produce a Call
    Call($text, undef, [], undef, 0);
}

sub _transform_ambiguous_function_call_expression ($node, $source) {
    my $func_node = $node->try_child_by_field_name("function");
    my $name = $func_node->text;
    my $func_start = $func_node->start_byte;
    my @args;
    for my $child ($node->child_nodes) {
        next unless $child->is_named;
        next if $child->is_extra;
        next if $child->start_byte == $func_start;
        push @args, _transform_node($child, $source);
    }
    Call($name, undef, \@args, undef, 0);
}

sub _transform_function_call_expression ($node, $source) {
    my $func_node = $node->try_child_by_field_name("function");
    my $name = $func_node->text;
    my @args;
    my $args_node = $node->try_child_by_field_name("arguments");
    if ($args_node) {
        for my $child ($args_node->child_nodes) {
            next unless $child->is_named;
            next if $child->is_extra;
            push @args, _transform_node($child, $source);
        }
    }
    Call($name, undef, \@args, undef, 0);
}

sub _transform_func1op_call_expression ($node, $source) {
    my $func_node = $node->try_child_by_field_name("function");
    my $name = $func_node ? $func_node->text : (grep { !$_->is_named } $node->child_nodes)[0]->text;
    my $func_start = $func_node ? $func_node->start_byte : -1;
    my @args;
    for my $child ($node->child_nodes) {
        next unless $child->is_named;
        next if $child->is_extra;
        next if $func_start >= 0 && $child->start_byte == $func_start;
        push @args, _transform_node($child, $source);
    }
    Call($name, undef, \@args, undef, 0);
}

1;
