package Crayon::Transform;
use v5.42;
use utf8;

use Exporter 'import';

use Crayon::AST qw[
    Program StatementSequence ExpressionStatement PostfixModifier Block
    Integer Float String Bool Undef SpecialLiteral QuotedWords Yada Version
    Call MethodCall
    Variable VariableDeclaration Assignment
    BinaryOp UnaryOp PostfixOp Ternary
    Subscript ParenExpression ExpressionList
    Conditional ElsifClause WhileLoop ForeachLoop CStyleForLoop LoopControl
    SubroutineDeclaration Signature ScalarParam SlurpyParam AnonymousSub
    ClassDeclaration RoleDeclaration MethodDeclaration FieldDeclaration Attribute
    TryCatch Defer ArrayRef HashRef Regex Dereference
    UseDeclaration PackageDeclaration DoExpression
    PostfixSlice
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
    my $block;
    for my $child ($node->child_nodes) {
        next unless $child->is_named;
        next if $child->is_extra;
        next if $child->start_byte == $func_start;
        # indirect_object contains a block — extract as the block arg
        if ($child->type eq 'indirect_object') {
            $block = _transform_indirect_object($child, $source);
            next;
        }
        push @args, _transform_node($child, $source);
    }

    # Handle 'not' as a unary operator
    if ($name eq 'not' && @args == 1 && !$block) {
        return UnaryOp('not', $args[0]);
    }

    # Qualified name: split namespace
    my ($namespace, $bare) = _split_qualified($name);

    Call($bare, $namespace, \@args, $block, 0);
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

sub _transform_function ($node, $source) {
    # Function node: may contain & sigil + varname, or just a name
    my $text = $node->text;
    if ($text =~ s/^&//) {
        my ($namespace, $name) = _split_qualified($text);
        return Variable('&', $name, $namespace);
    }
    # Bare function name — used as Call target in ambiguous contexts
    my ($namespace, $name) = _split_qualified($text);
    return Call($name, $namespace, [], undef, 0);
}

sub _transform_bareword ($node, $source) {
    return String($node->text, 0);
}

sub _transform_autoquoted_bareword ($node, $source) {
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

    # Field declarations get special treatment
    if ($declarator eq 'field') {
        # Get attributes if present
        my $attrs;
        my $attrlist_node = $node->try_child_by_field_name("attributes");
        if ($attrlist_node) {
            $attrs = _transform_attrlist($attrlist_node, $source);
        }

        # Get default value if present (assignment after =)
        my $default;
        for my $child ($node->child_nodes) {
            if ($child->is_named && $child->type eq 'assignment_expression') {
                my $right = $child->try_child_by_field_name("right");
                $default = _transform_node($right, $source) if $right;
                last;
            }
        }
        # Also check for initializer field
        if (!$default) {
            my $init = $node->try_child_by_field_name("initializer");
            $default = _transform_node($init, $source) if $init;
        }

        my $var = @variables == 1 ? $variables[0] : $variables[0];
        return FieldDeclaration($var, $attrs, $default);
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

# --- Control Flow ---

sub _transform_conditional_statement ($node, $source) {
    # Get keyword (if/unless) from first anonymous child
    my $keyword;
    for my $child ($node->child_nodes) {
        if (!$child->is_named && ($child->text eq 'if' || $child->text eq 'unless')) {
            $keyword = $child->text;
            last;
        }
    }
    my $negated = ($keyword eq 'unless') ? 1 : 0;

    # Get condition and block
    my $cond_node  = $node->try_child_by_field_name("condition");
    my $block_node = $node->try_child_by_field_name("block");

    my $condition  = _transform_node($cond_node, $source);
    my $then_block = _transform_node($block_node, $source);

    # Collect elsif/else — note: else nests inside the last elsif
    my @elsif_clauses;
    my $else_block;
    my $walk_elsif; $walk_elsif = sub ($elsif_node) {
        my $ec = $elsif_node->try_child_by_field_name("condition");
        my $eb = $elsif_node->try_child_by_field_name("block");
        if (!$ec) {
            # Find condition (scalar/expr after "elsif" keyword, before block)
            for my $c ($elsif_node->child_nodes) {
                if ($c->is_named && $c->type ne 'block' && $c->type ne 'elsif' && $c->type ne 'else') {
                    $ec = $c;
                    last;
                }
            }
        }
        if (!$eb) {
            for my $c ($elsif_node->child_nodes) {
                if ($c->is_named && $c->type eq 'block') {
                    $eb = $c;
                    last;
                }
            }
        }
        push @elsif_clauses, ElsifClause(
            _transform_node($ec, $source),
            _transform_node($eb, $source),
        ) if $ec && $eb;

        # Check for nested elsif or else
        for my $c ($elsif_node->child_nodes) {
            if ($c->type eq 'elsif' && $c->is_named) {
                $walk_elsif->($c);
            }
            elsif ($c->type eq 'else' && $c->is_named) {
                for my $gc ($c->child_nodes) {
                    if ($gc->is_named && $gc->type eq 'block') {
                        $else_block = _transform_node($gc, $source);
                        last;
                    }
                }
            }
        }
    };

    for my $child ($node->child_nodes) {
        if ($child->type eq 'elsif' && $child->is_named) {
            $walk_elsif->($child);
        }
        elsif ($child->type eq 'else' && $child->is_named) {
            for my $gc ($child->child_nodes) {
                if ($gc->is_named && $gc->type eq 'block') {
                    $else_block = _transform_node($gc, $source);
                    last;
                }
            }
        }
    }

    Conditional($condition, $negated, $then_block, \@elsif_clauses, $else_block);
}

sub _transform_loop_statement ($node, $source) {
    my $keyword;
    for my $child ($node->child_nodes) {
        if (!$child->is_named && ($child->text eq 'while' || $child->text eq 'until')) {
            $keyword = $child->text;
            last;
        }
    }
    my $negated = ($keyword eq 'until') ? 1 : 0;

    my $cond_node  = $node->try_child_by_field_name("condition");
    my $block_node = $node->try_child_by_field_name("block");

    my $condition = _transform_node($cond_node, $source);
    my $block     = _transform_node($block_node, $source);

    my $continue_block;
    my $cont_node = $node->try_child_by_field_name("continue");
    if ($cont_node) {
        $continue_block = _transform_node($cont_node, $source);
    }

    WhileLoop($condition, $negated, $block, $continue_block);
}

sub _transform_for_statement ($node, $source) {
    my $var_node   = $node->try_child_by_field_name("variable");
    my $list_node  = $node->try_child_by_field_name("list");
    my $block_node = $node->try_child_by_field_name("block");

    my $iterator = _transform_node($var_node, $source);
    my $list     = _transform_node($list_node, $source);
    my $block    = _transform_node($block_node, $source);

    my $continue_block;
    my $cont_node = $node->try_child_by_field_name("continue");
    if ($cont_node) {
        $continue_block = _transform_node($cont_node, $source);
    }

    ForeachLoop($iterator, $list, $block, $continue_block);
}

sub _transform_cstyle_for_statement ($node, $source) {
    my $init_node  = $node->try_child_by_field_name("initialiser");
    my $cond_node  = $node->try_child_by_field_name("condition");
    my $iter_node  = $node->try_child_by_field_name("iterator");
    my $block_node = $node->try_child_by_field_name("block");

    my $init = $init_node ? _transform_node($init_node, $source) : undef;
    my $cond = $cond_node ? _transform_node($cond_node, $source) : undef;
    my $incr = $iter_node ? _transform_node($iter_node, $source) : undef;
    my $block = _transform_node($block_node, $source);

    CStyleForLoop($init, $cond, $incr, $block);
}

sub _transform_postfix_conditional_expression ($node, $source) {
    # Body is first named child, condition is field
    my @named = grep { $_->is_named && !$_->is_extra } $node->child_nodes;
    my $body = _transform_node($named[0], $source);
    my $cond_node = $node->try_child_by_field_name("condition");
    my $condition = _transform_node($cond_node, $source);

    # Get keyword (if/unless)
    my $keyword;
    for my $child ($node->child_nodes) {
        if (!$child->is_named && ($child->text eq 'if' || $child->text eq 'unless')) {
            $keyword = $child->text;
            last;
        }
    }

    ExpressionStatement($body, PostfixModifier($keyword, $condition));
}

sub _transform_postfix_for_expression ($node, $source) {
    my @named = grep { $_->is_named && !$_->is_extra } $node->child_nodes;
    my $body = _transform_node($named[0], $source);
    my $list_node = $node->try_child_by_field_name("list");
    my $list = _transform_node($list_node, $source);

    ExpressionStatement($body, PostfixModifier('for', $list));
}

sub _transform_postfix_loop_expression ($node, $source) {
    my @named = grep { $_->is_named && !$_->is_extra } $node->child_nodes;
    my $body = _transform_node($named[0], $source);
    my $cond_node = $node->try_child_by_field_name("condition");
    my $condition = _transform_node($cond_node, $source);

    my $keyword;
    for my $child ($node->child_nodes) {
        if (!$child->is_named && ($child->text eq 'while' || $child->text eq 'until')) {
            $keyword = $child->text;
            last;
        }
    }

    ExpressionStatement($body, PostfixModifier($keyword, $condition));
}

sub _transform_loopex_expression ($node, $source) {
    my $loopex_node = $node->try_child_by_field_name("loopex");
    my $keyword = $loopex_node->text;

    # Check for optional label argument
    my $label;
    my @named = grep { $_->is_named && !$_->is_extra } $node->child_nodes;
    if (@named) {
        # If there's a named child that's not the loopex keyword itself
        for my $child (@named) {
            if ($child->start_byte != $loopex_node->start_byte) {
                $label = $child->text;
                last;
            }
        }
    }

    LoopControl($keyword, $label, undef);
}

sub _transform_return_expression ($node, $source) {
    my @named = grep { $_->is_named && !$_->is_extra } $node->child_nodes;
    my $expr;
    if (@named) {
        $expr = _transform_node($named[0], $source);
    }
    LoopControl('return', undef, $expr);
}

# --- Subroutines ---

sub _transform_subroutine_declaration_statement ($node, $source) {
    my $name_node = $node->try_child_by_field_name("name");
    my $body_node = $node->try_child_by_field_name("body");

    # Declarator: check for "my" lexical field
    my $declarator = 'sub';
    for my $child ($node->child_nodes) {
        if (!$child->is_named && $child->text eq 'my') {
            $declarator = 'my';
            last;
        }
    }

    # Find signature child
    my $sig;
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'signature') {
            $sig = _transform_signature($child, $source);
            last;
        }
    }

    my $name = $name_node ? $name_node->text : undef;
    my $body = $body_node ? _transform_node($body_node, $source) : undef;

    SubroutineDeclaration($declarator, $name, undef, undef, $sig, $body);
}

sub _transform_signature ($node, $source) {
    my @params;
    for my $child ($node->child_nodes) {
        next unless $child->is_named;
        next if $child->is_extra;
        my $type = $child->type;
        if ($type eq 'mandatory_parameter' || $type eq 'optional_parameter' ||
            $type eq 'named_parameter' || $type eq 'slurpy_parameter') {
            my $handler = __PACKAGE__->can("_transform_${type}");
            push @params, $handler->($child, $source) if $handler;
        }
    }
    Signature(\@params);
}

sub _transform_mandatory_parameter ($node, $source) {
    my $name = _extract_param_variable($node);
    ScalarParam($name, undef, 0);
}

sub _transform_optional_parameter ($node, $source) {
    my $name = _extract_param_variable($node);
    my $default_node = $node->try_child_by_field_name("default");
    my $default = $default_node ? _transform_node($default_node, $source) : undef;
    ScalarParam($name, $default, 0);
}

sub _transform_named_parameter ($node, $source) {
    my $name = _extract_param_variable($node);
    my $default_node = $node->try_child_by_field_name("default");
    my $default = $default_node ? _transform_node($default_node, $source) : undef;
    ScalarParam($name, $default, 1);
}

sub _transform_slurpy_parameter ($node, $source) {
    my $text = $node->text;
    # Remove leading whitespace, commas, etc.
    $text =~ s/^\s*,?\s*//;
    my $sigil = substr($text, 0, 1);
    my $name  = substr($text, 1);
    SlurpyParam($sigil, $name);
}

sub _extract_param_variable ($node) {
    # Find the scalar child to get the variable name
    for my $child ($node->child_nodes) {
        if ($child->type eq 'scalar') {
            my $text = $child->text;
            return substr($text, 1);  # strip $
        }
    }
    die "Cannot find variable in parameter node\n";
}

sub _transform_anonymous_subroutine_expression ($node, $source) {
    my $body_node = $node->try_child_by_field_name("body");

    # Find signature child
    my $sig;
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'signature') {
            $sig = _transform_signature($child, $source);
            last;
        }
    }

    my $body = $body_node ? _transform_node($body_node, $source) : undef;
    AnonymousSub($sig, undef, undef, $body, 'sub');
}

sub _transform_coderef_call_expression ($node, $source) {
    # First child (scalar or named) is the coderef
    my $target;
    for my $child ($node->child_nodes) {
        my $type = $child->type;
        if ($type eq 'scalar' || ($child->is_named && $type ne 'arguments')) {
            $target = _transform_node($child, $source);
            last if defined $target;
        }
    }

    # Get args from arguments field
    my @args;
    my $args_node = $node->try_child_by_field_name("arguments");
    if ($args_node) {
        for my $child ($args_node->child_nodes) {
            next unless $child->is_named || $child->type eq 'scalar';
            next if $child->is_extra;
            my $ast = _transform_node($child, $source);
            push @args, $ast if defined $ast;
        }
    }

    MethodCall($target, undef, \@args, 0);
}

# --- Classes, Roles, Methods ---

sub _transform_class_statement ($node, $source) {
    my $name_node = $node->try_child_by_field_name("name");
    my $name = $name_node ? $name_node->text : undef;

    # Version
    my $version_node = $node->try_child_by_field_name("version");
    my $version = $version_node ? $version_node->text : undef;

    # Attributes (:isa, :does, etc.)
    my $attrs;
    my $attrlist_node = $node->try_child_by_field_name("attributes");
    if ($attrlist_node) {
        $attrs = _transform_attrlist($attrlist_node, $source);
    }

    # Body block
    my $body;
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'block') {
            $body = _transform_node($child, $source);
            last;
        }
    }

    ClassDeclaration($name, $version, $attrs, $body);
}

sub _transform_role_statement ($node, $source) {
    my $name_node = $node->try_child_by_field_name("name");
    my $name = $name_node ? $name_node->text : undef;

    my $version_node = $node->try_child_by_field_name("version");
    my $version = $version_node ? $version_node->text : undef;

    my $attrs;
    my $attrlist_node = $node->try_child_by_field_name("attributes");
    if ($attrlist_node) {
        $attrs = _transform_attrlist($attrlist_node, $source);
    }

    my $body;
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'block') {
            $body = _transform_node($child, $source);
            last;
        }
    }

    RoleDeclaration($name, $version, $attrs, $body);
}

sub _transform_method_declaration_statement ($node, $source) {
    my $name_node = $node->try_child_by_field_name("name");
    my $name = $name_node ? $name_node->text : undef;

    # Check for "my" lexical declarator
    my $declarator = 'method';
    for my $child ($node->child_nodes) {
        if (!$child->is_named && $child->text eq 'my') {
            $declarator = 'my';
            last;
        }
    }

    # Attributes
    my $attrs;
    my $attrlist_node = $node->try_child_by_field_name("attributes");
    if ($attrlist_node) {
        $attrs = _transform_attrlist($attrlist_node, $source);
    }

    # Signature
    my $sig;
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'signature') {
            $sig = _transform_signature($child, $source);
            last;
        }
    }

    # Body
    my $body_node = $node->try_child_by_field_name("body");
    my $body = $body_node ? _transform_node($body_node, $source) : undef;

    MethodDeclaration($declarator, $name, $attrs, $sig, $body);
}

sub _transform_anonymous_method_expression ($node, $source) {
    # Signature
    my $sig;
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'signature') {
            $sig = _transform_signature($child, $source);
            last;
        }
    }

    # Body
    my $body_node = $node->try_child_by_field_name("body");
    if (!$body_node) {
        for my $child ($node->child_nodes) {
            if ($child->is_named && $child->type eq 'block') {
                $body_node = $child;
                last;
            }
        }
    }
    my $body = $body_node ? _transform_node($body_node, $source) : undef;

    AnonymousSub($sig, undef, undef, $body, 'method');
}

sub _transform_method_call_expression ($node, $source) {
    my $invocant_node = $node->try_child_by_field_name("invocant");
    my $invocant = $invocant_node ? _transform_node($invocant_node, $source) : undef;

    # Method name — available as named field "method"
    my $method_node = $node->try_child_by_field_name("method");
    my $method_name = $method_node ? $method_node->text : undef;

    # Collect args: everything after "->" and method name that is not punctuation
    # The "arguments" field may point to a single arg, not a container,
    # so we gather all arg children manually.
    my @args;
    my $past_method = 0;
    my $in_parens = 0;
    for my $child ($node->child_nodes) {
        if ($method_node && $child->start_byte == $method_node->start_byte && $child->is_named) {
            $past_method = 1;
            next;
        }
        next unless $past_method;
        if (!$child->is_named) {
            $in_parens = 1 if $child->text eq '(';
            next;
        }
        next if $child->is_extra;
        my $ast = _transform_node($child, $source);
        push @args, $ast if defined $ast;
    }

    MethodCall($invocant, $method_name, \@args, 0);
}

sub _transform_class_phaser_statement ($node, $source) {
    my $phase_node = $node->try_child_by_field_name("phase");
    my $phase_name = $phase_node ? $phase_node->text : undef;

    # Signature
    my $sig;
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'signature') {
            $sig = _transform_signature($child, $source);
            last;
        }
    }

    # Block body
    my $body;
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'block') {
            $body = _transform_node($child, $source);
            last;
        }
    }

    SubroutineDeclaration(undef, $phase_name, undef, undef, $sig, $body);
}

sub _transform_attrlist ($node, $source) {
    my @attributes;
    for my $child ($node->child_nodes) {
        next unless $child->is_named;
        next if $child->is_extra;
        if ($child->type eq 'attribute') {
            my $attr_name;
            my $attr_args;
            for my $ac ($child->child_nodes) {
                if ($ac->is_named && $ac->type eq 'attribute_name') {
                    $attr_name = $ac->text;
                }
            }
            # Look for parenthesized args — text after attribute_name
            # The full attribute text minus the name gives us the args
            if ($attr_name) {
                my $full = $child->text;
                if ($full =~ /^\Q$attr_name\E\((.+)\)$/) {
                    $attr_args = $1;
                }
            }
            push @attributes, Attribute($attr_name, $attr_args) if $attr_name;
        }
    }
    \@attributes;
}

# --- Try/Catch/Defer ---

sub _transform_try_statement ($node, $source) {
    my $try_node     = $node->try_child_by_field_name("try_block");
    my $catch_node   = $node->try_child_by_field_name("catch_block");
    my $finally_node = $node->try_child_by_field_name("finally_block");
    my $catch_var_node = $node->try_child_by_field_name("catch_expr");

    my $try_block     = $try_node     ? _transform_node($try_node, $source)     : undef;
    my $catch_block   = $catch_node   ? _transform_node($catch_node, $source)   : undef;
    my $finally_block = $finally_node ? _transform_node($finally_node, $source) : undef;
    my $catch_var     = $catch_var_node ? _transform_node($catch_var_node, $source) : undef;

    TryCatch($try_block, $catch_var, $catch_block, $finally_block);
}

sub _transform_defer_statement ($node, $source) {
    my $block_node = $node->try_child_by_field_name("block");
    # Fall back to finding block child
    if (!$block_node) {
        for my $child ($node->child_nodes) {
            if ($child->is_named && $child->type eq 'block') {
                $block_node = $child;
                last;
            }
        }
    }
    Defer(_transform_node($block_node, $source));
}

# --- Anonymous Array/Hash ---

sub _transform_anonymous_array_expression ($node, $source) {
    my @elements;
    for my $child ($node->child_nodes) {
        my $type = $child->type;
        next if !$child->is_named && $type ne 'scalar';
        next if $child->is_extra;
        my $ast = _transform_node($child, $source);
        push @elements, $ast if defined $ast;
    }
    ArrayRef(\@elements);
}

sub _transform_anonymous_hash_expression ($node, $source) {
    my @elements;
    for my $child ($node->child_nodes) {
        my $type = $child->type;
        next if !$child->is_named && $type ne 'scalar';
        next if $child->is_extra;
        my $ast = _transform_node($child, $source);
        push @elements, $ast if defined $ast;
    }
    HashRef(\@elements);
}

# --- Regex ---

sub _transform_match_regexp ($node, $source) {
    my $content_node = $node->try_child_by_field_name("content");
    my $mod_node     = $node->try_child_by_field_name("modifiers");
    my $pattern = $content_node ? $content_node->text : '';
    my $flags   = $mod_node    ? $mod_node->text      : undef;
    Regex($pattern, undef, $flags, 'm');
}

sub _transform_quoted_regexp ($node, $source) {
    my $content_node = $node->try_child_by_field_name("content");
    my $mod_node     = $node->try_child_by_field_name("modifiers");
    my $pattern = $content_node ? $content_node->text : '';
    my $flags   = $mod_node    ? $mod_node->text      : undef;
    Regex($pattern, undef, $flags, 'qr');
}

sub _transform_substitution_regexp ($node, $source) {
    my $content_node     = $node->try_child_by_field_name("content");
    my $replacement_node = $node->try_child_by_field_name("replacement");
    my $mod_node         = $node->try_child_by_field_name("modifiers");
    my $pattern     = $content_node     ? $content_node->text     : '';
    my $replacement = $replacement_node ? $replacement_node->text : '';
    my $flags       = $mod_node         ? $mod_node->text         : undef;
    Regex($pattern, $replacement, $flags, 's');
}

sub _transform_transliteration_expression ($node, $source) {
    my $content_node     = $node->try_child_by_field_name("content");
    my $replacement_node = $node->try_child_by_field_name("replacement");
    my $mod_node         = $node->try_child_by_field_name("modifiers");
    my $pattern     = $content_node     ? $content_node->text     : '';
    my $replacement = $replacement_node ? $replacement_node->text : '';
    my $flags       = $mod_node         ? $mod_node->text         : undef;
    Regex($pattern, $replacement, $flags, 'tr');
}

# --- Postfix Dereference ---

sub _transform_array_deref_expression ($node, $source) {
    my $target_node = $node->try_child_by_field_name("arrayref");
    if (!$target_node) {
        for my $child ($node->child_nodes) {
            if ($child->type eq 'scalar' || ($child->is_named && $child->type ne 'block')) {
                $target_node = $child;
                last;
            }
        }
    }
    Dereference(_transform_node($target_node, $source), '@');
}

sub _transform_hash_deref_expression ($node, $source) {
    my $target_node = $node->try_child_by_field_name("hashref");
    if (!$target_node) {
        for my $child ($node->child_nodes) {
            if ($child->type eq 'scalar' || ($child->is_named && $child->type ne 'block')) {
                $target_node = $child;
                last;
            }
        }
    }
    Dereference(_transform_node($target_node, $source), '%');
}

sub _transform_scalar_deref_expression ($node, $source) {
    my $target_node = $node->try_child_by_field_name("scalarref");
    if (!$target_node) {
        for my $child ($node->child_nodes) {
            if ($child->type eq 'scalar' || ($child->is_named && $child->type ne 'block')) {
                $target_node = $child;
                last;
            }
        }
    }
    Dereference(_transform_node($target_node, $source), '$');
}

# --- Use / Package ---

sub _transform_use_statement ($node, $source) {
    # Keyword: "use" or "no"
    my $keyword;
    for my $child ($node->child_nodes) {
        if (!$child->is_named && ($child->text eq 'use' || $child->text eq 'no')) {
            $keyword = $child->text;
            last;
        }
    }
    $keyword //= 'use';

    my $module_node  = $node->try_child_by_field_name("module");
    my $version_node = $node->try_child_by_field_name("version");

    my $module  = $module_node  ? $module_node->text  : undef;
    my $version = $version_node ? $version_node->text : undef;

    # Remaining named children are imports
    my @imports;
    my %skip;
    $skip{$module_node->start_byte}  = 1 if $module_node;
    $skip{$version_node->start_byte} = 1 if $version_node;
    for my $child ($node->child_nodes) {
        my $type = $child->type;
        next if !$child->is_named && $type ne 'scalar';
        next if $child->is_extra;
        next if $skip{$child->start_byte};
        my $ast = _transform_node($child, $source);
        push @imports, $ast if defined $ast;
    }

    UseDeclaration($keyword, $module, $version, @imports ? \@imports : undef);
}

sub _transform_use_version_statement ($node, $source) {
    my $version_node = $node->try_child_by_field_name("version");
    my $version = $version_node ? $version_node->text : undef;
    UseDeclaration('use', undef, $version, undef);
}

sub _transform_version ($node, $source) {
    Version($node->text);
}

sub _transform_package_statement ($node, $source) {
    my $name_node    = $node->try_child_by_field_name("name");
    my $version_node = $node->try_child_by_field_name("version");

    my $name    = $name_node    ? $name_node->text    : undef;
    my $version = $version_node ? $version_node->text : undef;

    # Optional block body
    my $body;
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'block') {
            $body = _transform_node($child, $source);
            last;
        }
    }

    PackageDeclaration($name, $version, $body);
}

# --- Map/Grep/Sort ---

sub _transform_map_grep_expression ($node, $source) {
    # Get function name from anonymous keyword child
    my $name;
    for my $child ($node->child_nodes) {
        if (!$child->is_named && ($child->text eq 'map' || $child->text eq 'grep')) {
            $name = $child->text;
            last;
        }
    }

    my $callback_node = $node->try_child_by_field_name("callback");
    my $list_node     = $node->try_child_by_field_name("list");

    my $block = $callback_node ? _transform_node($callback_node, $source) : undef;
    my @args;
    if ($list_node) {
        push @args, _transform_node($list_node, $source);
    }

    Call($name, undef, \@args, $block, 0);
}

sub _transform_sort_expression ($node, $source) {
    my $callback_node = $node->try_child_by_field_name("callback");
    my $list_node     = $node->try_child_by_field_name("list");

    my $block = $callback_node ? _transform_node($callback_node, $source) : undef;
    my @args;
    if ($list_node) {
        push @args, _transform_node($list_node, $source);
    }

    Call('sort', undef, \@args, $block, 0);
}

# --- Localization ---

sub _transform_localization_expression ($node, $source) {
    my @vars;
    for my $child ($node->child_nodes) {
        my $type = $child->type;
        next if !$child->is_named && $type ne 'scalar';
        next if $child->is_extra;
        # skip the "local" keyword
        next if !$child->is_named && $type eq 'local';
        my $ast = _transform_node($child, $source);
        push @vars, $ast if defined $ast;
    }
    VariableDeclaration('local', \@vars);
}

# --- Do Expression ---

# --- Indirect Object (block arg in reduce { } @list style) ---

sub _transform_indirect_object ($node, $source) {
    # Contains a block child — extract it
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'block') {
            return _transform_node($child, $source);
        }
    }
    # Fallback: just transform first named child
    for my $child ($node->child_nodes) {
        if ($child->is_named) {
            return _transform_node($child, $source);
        }
    }
    return undef;
}

# --- Slices ---

sub _transform_slice_expression ($node, $source) {
    # @a[0,1] or @h{qw(a b)} — container + index list
    my ($target, $index, $kind);
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'slice_container_variable') {
            $target = _transform_slice_container_variable($child, $source);
        } elsif ($child->is_named && !$index) {
            $index = _transform_node($child, $source);
        } elsif (!$child->is_named) {
            $kind = 'array' if $child->text eq '[';
            $kind = 'hash'  if $child->text eq '{';
        }
    }
    $kind //= 'array';
    Subscript($target, $index, $kind, 0);
}

sub _transform_slice_container_variable ($node, $source) {
    my $text = $node->text;
    # @arr or %hash — extract sigil and name
    if ($text =~ /^([@%])(.+)$/) {
        my ($sigil, $name) = ($1, $2);
        my ($namespace, $bare) = _split_qualified($name);
        return Variable($sigil, $bare, $namespace);
    }
    die "Cannot parse slice_container_variable: $text\n";
}

# --- Array length ($#array) ---

sub _transform_arraylen ($node, $source) {
    my $text = $node->text;
    $text =~ s/^\$#//;
    my ($namespace, $name) = _split_qualified($text);
    Variable('$#', $name, $namespace);
}

# --- Stub expression (forward declaration body) ---

sub _transform_stub_expression ($node, $source) {
    Yada();
}

# --- Escape sequence (inside interpolated strings) ---

sub _transform_escape_sequence ($node, $source) {
    String($node->text, 0);
}

# --- Do Expression ---

sub _transform_do_expression ($node, $source) {
    # Check for block child
    for my $child ($node->child_nodes) {
        if ($child->is_named && $child->type eq 'block') {
            return DoExpression('block', _transform_node($child, $source));
        }
    }
    # Otherwise it's a do FILE
    for my $child ($node->child_nodes) {
        my $type = $child->type;
        next if !$child->is_named && $type ne 'scalar';
        next if $child->is_extra;
        my $ast = _transform_node($child, $source);
        return DoExpression('file', $ast) if defined $ast;
    }
    DoExpression('block', undef);
}

1;
