use v5.42;
use utf8;
use experimental qw[ class ];

use Crayon::Environment;

class Crayon::Interpreter {
    field $env :param = Crayon::Environment->new;

    method eval ($ast) {
        my $type = $ast->{type};
        my $method = "eval_$type";
        $self->$method($ast);
    }

    method eval_Program ($ast) {
        $self->eval($ast->{body});
    }

    method eval_StatementSequence ($ast) {
        my $result;
        for my $stmt ($ast->{statements}->@*) {
            $result = $self->eval($stmt);
        }
        return $result;
    }

    method eval_ExpressionStatement ($ast) {
        if (my $mod = $ast->{modifier}) {
            my $kw = $mod->{keyword};
            if ($kw eq 'if') {
                return $self->eval($ast->{expression}) if $self->eval($mod->{expression});
                return undef;
            }
            if ($kw eq 'unless') {
                return $self->eval($ast->{expression}) unless $self->eval($mod->{expression});
                return undef;
            }
            if ($kw eq 'while') {
                my $result;
                while ($self->eval($mod->{expression})) {
                    $result = $self->eval($ast->{expression});
                }
                return $result;
            }
            if ($kw eq 'until') {
                my $result;
                until ($self->eval($mod->{expression})) {
                    $result = $self->eval($ast->{expression});
                }
                return $result;
            }
            if ($kw eq 'for' || $kw eq 'foreach') {
                my $list_val = $self->eval($mod->{expression});
                my @list = ref $list_val eq 'ARRAY' ? @$list_val : ($list_val);
                my $result;
                my $old_env = $env;
                $env = $env->child;
                $env->define('$_', undef);
                for my $item (@list) {
                    $env->assign('$_', $item);
                    $result = $self->eval($ast->{expression});
                }
                $env = $old_env;
                return $result;
            }
        }
        $self->eval($ast->{expression});
    }

    method eval_Integer ($ast) {
        my $value = $ast->{value};
        $value =~ s/_//g;
        if ($value =~ /^0x/i) {
            return hex($value);
        }
        if ($value =~ /^0b/i) {
            return oct($value);
        }
        if ($value =~ /^0o/i) {
            return oct("0" . substr($value, 2));
        }
        return 0 + $value;
    }

    method eval_Float ($ast) {
        my $value = $ast->{value};
        $value =~ s/_//g;
        return 0 + $value;
    }

    method eval_String ($ast) {
        my $value = $ast->{value};
        if ($ast->{interpolate}) {
            $value =~ s/\\n/\n/g;
            $value =~ s/\\t/\t/g;
            $value =~ s/\\\\/\\/g;
            $value =~ s/\\"/"/g;
        }
        return $value;
    }

    method eval_Bool ($ast) {
        return $ast->{value};
    }

    method eval_Undef ($ast) {
        return undef;
    }

    method eval_Yada ($ast) {
        die "Unimplemented";
    }

    method eval_SpecialLiteral ($ast) {
        my $kind = $ast->{kind};
        return '(eval)' if $kind eq '__FILE__';
        return 0        if $kind eq '__LINE__';
        return 'main'   if $kind eq '__PACKAGE__';
        die "Unknown special literal '$kind'\n";
    }

    method eval_Call ($ast) {
        my $name = $ast->{name};
        my @args = map { $self->eval($_) } $ast->{args}->@*;

        if ($name eq 'say') {
            say join('', @args);
            return 1;
        }
        if ($name eq 'print') {
            print join('', @args);
            return 1;
        }

        die "Unknown function '$name'\n";
    }

    # --- Variables ---

    method eval_Variable ($ast) {
        my $key = $ast->{sigil} . $ast->{name};
        return $env->lookup($key);
    }

    method eval_VariableDeclaration ($ast) {
        my @vars = $ast->{variables}->@*;
        for my $var (@vars) {
            my $key = $var->{sigil} . $var->{name};
            $env->define($key, undef);
        }
        # Return the declaration AST itself for use in assignment
        return $ast;
    }

    # --- Assignment ---

    method eval_Assignment ($ast) {
        my $op     = $ast->{operator};
        my $target = $ast->{target};
        my $value  = $self->eval($ast->{value});

        # If target is a VariableDeclaration, declare first then assign
        if ($target->{type} eq 'VariableDeclaration') {
            my @vars = $target->{variables}->@*;
            for my $var (@vars) {
                my $key = $var->{sigil} . $var->{name};
                $env->define($key, undef);
            }
            if (@vars == 1) {
                my $key = $vars[0]->{sigil} . $vars[0]->{name};
                $env->assign($key, $value);
                return $value;
            }
            # Multi-var: my ($x, $y) = (1, 2)
            my @vals = ref $value eq 'ARRAY' ? @$value : ($value);
            for my $i (0 .. $#vars) {
                my $key = $vars[$i]->{sigil} . $vars[$i]->{name};
                $env->assign($key, $vals[$i]);
            }
            return $value;
        }

        # Compound assignment (+=, -=, .=, etc)
        if ($op ne '=') {
            my $base_op = substr($op, 0, -1);  # strip trailing =
            my $current = $self->eval($target);
            $value = _apply_binary_op($base_op, $current, $value);
        }

        # Simple variable target
        if ($target->{type} eq 'Variable') {
            my $key = $target->{sigil} . $target->{name};
            $env->assign($key, $value);
            return $value;
        }

        die "Cannot assign to $target->{type}\n";
    }

    # --- Binary ---

    method eval_BinaryOp ($ast) {
        my $op = $ast->{operator};

        # Short-circuit operators
        if ($op eq '&&' || $op eq 'and') {
            my $left = $self->eval($ast->{left});
            return $left unless $left;
            return $self->eval($ast->{right});
        }
        if ($op eq '||' || $op eq 'or') {
            my $left = $self->eval($ast->{left});
            return $left if $left;
            return $self->eval($ast->{right});
        }
        if ($op eq '//') {
            my $left = $self->eval($ast->{left});
            return $left if defined $left;
            return $self->eval($ast->{right});
        }

        my $left  = $self->eval($ast->{left});
        my $right = $self->eval($ast->{right});
        return _apply_binary_op($op, $left, $right);
    }

    # --- Unary ---

    method eval_UnaryOp ($ast) {
        my $op = $ast->{operator};

        if ($op eq '++') {
            # prefix increment
            my $operand = $ast->{operand};
            my $key = $operand->{sigil} . $operand->{name};
            my $val = $env->lookup($key);
            $val++;
            $env->assign($key, $val);
            return $val;
        }
        if ($op eq '--') {
            my $operand = $ast->{operand};
            my $key = $operand->{sigil} . $operand->{name};
            my $val = $env->lookup($key);
            $val--;
            $env->assign($key, $val);
            return $val;
        }

        my $val = $self->eval($ast->{operand});

        return !$val      ? 1 : '' if $op eq '!' || $op eq 'not';
        return -$val             if $op eq '-';
        return +$val             if $op eq '+';
        return ~$val             if $op eq '~';
        return \$val             if $op eq '\\';

        die "Unknown unary operator '$op'\n";
    }

    # --- Postfix ---

    method eval_PostfixOp ($ast) {
        my $op = $ast->{operator};
        my $operand = $ast->{operand};
        my $key = $operand->{sigil} . $operand->{name};
        my $old = $env->lookup($key);

        if ($op eq '++') {
            my $new = $old;
            $new++;
            $env->assign($key, $new);
            return $old;
        }
        if ($op eq '--') {
            my $new = $old;
            $new--;
            $env->assign($key, $new);
            return $old;
        }

        die "Unknown postfix operator '$op'\n";
    }

    # --- Ternary ---

    method eval_Ternary ($ast) {
        my $cond = $self->eval($ast->{condition});
        return $cond ? $self->eval($ast->{then_expr}) : $self->eval($ast->{else_expr});
    }

    # --- Block ---

    method eval_Block ($ast) {
        my $old_env = $env;
        $env = $env->child;
        my $result = $self->eval($ast->{statements});
        $env = $old_env;
        return $result;
    }

    # --- Subscript ---

    method eval_Subscript ($ast) {
        my $target = $self->eval($ast->{target});
        my $index  = $self->eval($ast->{index});
        my $kind   = $ast->{kind};

        if ($kind eq 'array') {
            return $target->[$index];
        }
        if ($kind eq 'hash') {
            return $target->{$index};
        }
        die "Unknown subscript kind '$kind'\n";
    }

    # --- List / Paren ---

    method eval_ExpressionList ($ast) {
        my @results;
        for my $expr ($ast->{expressions}->@*) {
            push @results, $self->eval($expr);
        }
        return \@results;
    }

    method eval_ParenExpression ($ast) {
        return $self->eval($ast->{expression});
    }

    # --- Control Flow ---

    method eval_Conditional ($ast) {
        my $cond = $self->eval($ast->{condition});
        $cond = !$cond if $ast->{negated};

        if ($cond) {
            return $self->eval($ast->{then_block});
        }

        if ($ast->{elsif_clauses}) {
            for my $elsif ($ast->{elsif_clauses}->@*) {
                my $ec = $self->eval($elsif->{condition});
                if ($ec) {
                    return $self->eval($elsif->{block});
                }
            }
        }

        if ($ast->{else_block}) {
            return $self->eval($ast->{else_block});
        }

        return undef;
    }

    method eval_WhileLoop ($ast) {
        my $result;
        while (1) {
            my $cond = $self->eval($ast->{condition});
            $cond = !$cond if $ast->{negated};
            last unless $cond;
            eval { $result = $self->eval($ast->{block}) };
            if ($@) {
                if (ref $@ eq 'HASH') {
                    last if $@->{type} eq 'last';
                    next if $@->{type} eq 'next';
                }
                die $@;
            }
        }
        return $result;
    }

    method eval_ForeachLoop ($ast) {
        my $list_val = $self->eval($ast->{list});
        my @list = ref $list_val eq 'ARRAY' ? @$list_val : ($list_val);

        my $iter = $ast->{iterator};
        my $var_key = $iter->{sigil} . $iter->{name};

        my $old_env = $env;
        $env = $env->child;
        $env->define($var_key, undef);

        my $result;
        for my $item (@list) {
            $env->assign($var_key, $item);
            eval { $result = $self->eval($ast->{block}) };
            if ($@) {
                if (ref $@ eq 'HASH') {
                    if ($@->{type} eq 'last') {
                        last;
                    }
                    if ($@->{type} eq 'next') {
                        next;
                    }
                }
                $env = $old_env;
                die $@;
            }
        }
        $env = $old_env;
        return $result;
    }

    method eval_CStyleForLoop ($ast) {
        my $old_env = $env;
        $env = $env->child;

        $self->eval($ast->{init}) if $ast->{init};

        my $result;
        while (1) {
            if ($ast->{condition}) {
                my $cond = $self->eval($ast->{condition});
                last unless $cond;
            }
            eval { $result = $self->eval($ast->{block}) };
            if ($@) {
                if (ref $@ eq 'HASH') {
                    if ($@->{type} eq 'last') {
                        last;
                    }
                    if ($@->{type} eq 'next') {
                        $self->eval($ast->{increment}) if $ast->{increment};
                        next;
                    }
                }
                $env = $old_env;
                die $@;
            }
            $self->eval($ast->{increment}) if $ast->{increment};
        }
        $env = $old_env;
        return $result;
    }

    method eval_LoopControl ($ast) {
        my $keyword = $ast->{keyword};
        if ($keyword eq 'return') {
            my $value = $ast->{expression} ? $self->eval($ast->{expression}) : undef;
            die +{ type => 'return', value => $value };
        }
        die +{ type => $keyword, label => $ast->{label} };
    }

    # --- Helper (plain sub, not a method) ---

    sub _apply_binary_op ($op, $left, $right) {
        # Arithmetic
        return $left + $right   if $op eq '+';
        return $left - $right   if $op eq '-';
        return $left * $right   if $op eq '*';
        return $left / $right   if $op eq '/';
        return $left % $right   if $op eq '%';
        return $left ** $right  if $op eq '**';

        # String
        return $left . $right   if $op eq '.';
        return $left x $right   if $op eq 'x';

        # Numeric comparison
        return ($left == $right ? 1 : '') if $op eq '==';
        return ($left != $right ? 1 : '') if $op eq '!=';
        return ($left <  $right ? 1 : '') if $op eq '<';
        return ($left <= $right ? 1 : '') if $op eq '<=';
        return ($left >  $right ? 1 : '') if $op eq '>';
        return ($left >= $right ? 1 : '') if $op eq '>=';
        return ($left <=> $right)         if $op eq '<=>';

        # String comparison
        return ($left eq $right ? 1 : '') if $op eq 'eq';
        return ($left ne $right ? 1 : '') if $op eq 'ne';
        return ($left lt $right ? 1 : '') if $op eq 'lt';
        return ($left le $right ? 1 : '') if $op eq 'le';
        return ($left gt $right ? 1 : '') if $op eq 'gt';
        return ($left ge $right ? 1 : '') if $op eq 'ge';
        return ($left cmp $right)         if $op eq 'cmp';

        # Bitwise
        return ($left & $right)  if $op eq '&';
        return ($left | $right)  if $op eq '|';
        return ($left ^ $right)  if $op eq '^';
        return ($left << $right) if $op eq '<<';
        return ($left >> $right) if $op eq '>>';

        # Range
        return [$left .. $right] if $op eq '..';

        die "Unknown binary operator '$op'\n";
    }
}

1;
