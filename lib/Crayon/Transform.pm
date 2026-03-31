package Crayon::Transform;
use v5.42;
use utf8;

use Exporter 'import';

use Crayon::AST qw[
    Program StatementSequence ExpressionStatement Block
    Integer Float String Bool Undef SpecialLiteral QuotedWords Yada
    Call
    Variable VariableDeclaration Assignment
    BinaryOp UnaryOp PostfixOp Ternary
    Subscript ParenExpression ExpressionList
];

our @EXPORT_OK = qw[ transform ];

# --- Main entry point ---

sub transform ($node, $source) {
    _transform_node($node, $source);
}

# --- Recursive dispatcher ---

sub _transform_node ($node, $source) {
    my $type = $node->type;

    # Handle specific anonymous node types we care about
    if (!$node->is_named) {
        return _transform_scalar($node, $source) if $type eq 'scalar';
        return undef;  # skip other anonymous nodes
    }

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

sub _transform_block_statement ($node, $source) {
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
    my $text = $node->text;
    # Strip the opening and closing delimiters (first and last char)
    return substr($text, 1, length($text) - 2);
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

    # Handle 'not' as a unary operator
    if ($name eq 'not' && @args == 1) {
        return UnaryOp('not', $args[0]);
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

# --- Variables ---

sub _transform_scalar ($node, $source) {
    my $text = $node->text;
    # $x or $Foo::bar
    if ($text =~ /^\$(.+)$/) {
        my $full = $1;
        my ($namespace, $name) = _split_qualified($full);
        return Variable('$', $name, $namespace);
    }
    die "Cannot parse scalar: $text\n";
}

sub _transform_array ($node, $source) {
    my $text = $node->text;
    if ($text =~ /^\@(.+)$/) {
        my $full = $1;
        my ($namespace, $name) = _split_qualified($full);
        return Variable('@', $name, $namespace);
    }
    die "Cannot parse array: $text\n";
}

sub _transform_hash ($node, $source) {
    my $text = $node->text;
    if ($text =~ /^\%(.+)$/) {
        my $full = $1;
        my ($namespace, $name) = _split_qualified($full);
        return Variable('%', $name, $namespace);
    }
    die "Cannot parse hash: $text\n";
}

sub _transform_container_variable ($node, $source) {
    my $text = $node->text;
    if ($text =~ /^\$(.+)$/) {
        my $full = $1;
        my ($namespace, $name) = _split_qualified($full);
        return Variable('$', $name, $namespace);
    }
    die "Cannot parse container_variable: $text\n";
}

sub _split_qualified ($name) {
    if ($name =~ /^(.+)::(.+)$/) {
        return ($1, $2);
    }
    return (undef, $name);
}

sub _transform_varname ($node, $source) {
    return $node->text;
}

sub _transform_bareword ($node, $source) {
    return String($node->text, 0);
}

# --- Declarations ---

sub _transform_variable_declaration ($node, $source) {
    # Get declarator keyword (my/our/state/field) from first anonymous child
    my $declarator;
    for my $child ($node->child_nodes) {
        if (!$child->is_named && $child->text =~ /^(my|our|state|field)$/) {
            $declarator = $child->text;
            last;
        }
    }
    $declarator //= 'my';

    # Get variable(s) - could be single or multi
    my $var_node = $node->try_child_by_field_name("variable");
    my $vars_node = $node->try_child_by_field_name("variables");

    my @variables;
    if ($var_node) {
        push @variables, _transform_node($var_node, $source);
    } elsif ($vars_node) {
        for my $child ($vars_node->child_nodes) {
            my $type = $child->type;
            next if !$child->is_named && $type ne 'scalar';
            my $ast = _transform_node($child, $source);
            push @variables, $ast if defined $ast;
        }
    }

    VariableDeclaration($declarator, \@variables);
}

# --- Assignment ---

sub _transform_assignment_expression ($node, $source) {
    my $left  = $node->try_child_by_field_name("left");
    my $op    = $node->try_child_by_field_name("operator");
    my $right = $node->try_child_by_field_name("right");

    my $left_ast  = _transform_node($left, $source);
    my $op_text   = $op->text;
    my $right_ast = _transform_node($right, $source);

    Assignment($op_text, $left_ast, $right_ast);
}

# --- Binary / Comparison / Logical ---

sub _transform_binary_expression ($node, $source) {
    my $op_node = $node->try_child_by_field_name("operator");
    my $op_text = $op_node->text;
    my $op_start = $op_node->start_byte;

    # Collect named children (and anonymous scalars) excluding the operator
    my (@before_op, @after_op);
    for my $child ($node->child_nodes) {
        next if $child->start_byte == $op_start && !$child->is_named;
        my $type = $child->type;
        next if !$child->is_named && $type ne 'scalar';
        if ($child->start_byte < $op_start) {
            push @before_op, $child;
        } elsif ($child->start_byte > $op_start) {
            push @after_op, $child;
        }
    }

    my $left_ast  = @before_op ? _transform_node($before_op[-1], $source) : undef;
    my $right_ast = @after_op  ? _transform_node($after_op[0], $source)   : undef;

    BinaryOp($op_text, $left_ast, $right_ast);
}

sub _transform_equality_expression ($node, $source) {
    _transform_binary_expression($node, $source);
}

sub _transform_relational_expression ($node, $source) {
    _transform_binary_expression($node, $source);
}

sub _transform_lowprec_logical_expression ($node, $source) {
    _transform_binary_expression($node, $source);
}

# --- Unary ---

sub _transform_unary_expression ($node, $source) {
    my $op      = $node->try_child_by_field_name("operator");
    my $operand = $node->try_child_by_field_name("operand");

    UnaryOp($op->text, _transform_node($operand, $source));
}

sub _transform_preinc_expression ($node, $source) {
    my $op      = $node->try_child_by_field_name("operator");
    my $operand = $node->try_child_by_field_name("operand");

    UnaryOp($op->text, _transform_node($operand, $source));
}

sub _transform_postinc_expression ($node, $source) {
    my $op      = $node->try_child_by_field_name("operator");
    my $operand = $node->try_child_by_field_name("operand");

    PostfixOp($op->text, _transform_node($operand, $source));
}

sub _transform_refgen_expression ($node, $source) {
    # Children: "\" + operand
    my @children = $node->child_nodes;
    my $operand;
    for my $child (@children) {
        my $type = $child->type;
        next if $type eq '\\';
        my $ast = _transform_node($child, $source);
        if (defined $ast) {
            $operand = $ast;
            last;
        }
    }
    UnaryOp('\\', $operand);
}

# --- Ternary ---

sub _transform_conditional_expression ($node, $source) {
    my $cond = $node->try_child_by_field_name("condition");
    my $then = $node->try_child_by_field_name("consequent");
    my $else = $node->try_child_by_field_name("alternative");

    Ternary(
        _transform_node($cond, $source),
        _transform_node($then, $source),
        _transform_node($else, $source),
    );
}

# --- Subscript ---

sub _transform_array_element_expression ($node, $source) {
    my $array_node = $node->try_child_by_field_name("array");
    my $index_node = $node->try_child_by_field_name("index");

    my $arrow = 0;
    for my $child ($node->child_nodes) {
        if (!$child->is_named && $child->text eq '->') {
            $arrow = 1;
            last;
        }
    }

    my $target;
    if ($array_node) {
        $target = _transform_node($array_node, $source);
    } else {
        for my $child ($node->child_nodes) {
            if ($child->is_named || $child->type eq 'scalar') {
                $target = _transform_node($child, $source);
                last if defined $target;
            }
        }
    }

    Subscript($target, _transform_node($index_node, $source), 'array', $arrow);
}

sub _transform_hash_element_expression ($node, $source) {
    my $hash_node = $node->try_child_by_field_name("hash");
    my $key_node  = $node->try_child_by_field_name("key");

    my $arrow = 0;
    for my $child ($node->child_nodes) {
        if (!$child->is_named && $child->text eq '->') {
            $arrow = 1;
            last;
        }
    }

    my $target;
    if ($hash_node) {
        $target = _transform_node($hash_node, $source);
    } else {
        for my $child ($node->child_nodes) {
            if ($child->is_named || $child->type eq 'scalar') {
                $target = _transform_node($child, $source);
                last if defined $target;
            }
        }
    }

    Subscript($target, _transform_node($key_node, $source), 'hash', $arrow);
}

# --- List / Paren ---

sub _transform_list_expression ($node, $source) {
    my @exprs;
    for my $child ($node->child_nodes) {
        my $type = $child->type;
        next if !$child->is_named && $type ne 'scalar';
        next if $child->is_extra;
        my $ast = _transform_node($child, $source);
        push @exprs, $ast if defined $ast;
    }
    ExpressionList(\@exprs);
}

sub _transform_parenthesized_expression ($node, $source) {
    my @named;
    for my $child ($node->child_nodes) {
        my $type = $child->type;
        next if !$child->is_named && $type ne 'scalar';
        next if $child->is_extra;
        my $ast = _transform_node($child, $source);
        push @named, $ast if defined $ast;
    }

    if (@named == 1) {
        return ParenExpression($named[0]);
    }
    ParenExpression(ExpressionList(\@named));
}

1;
