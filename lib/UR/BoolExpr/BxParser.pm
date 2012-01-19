####################################################################
#
#    This file was generated using Parse::Yapp version 1.05.
#
#        Don't edit this file, use source file instead.
#
#             ANY CHANGE MADE HERE WILL BE LOST !
#
####################################################################
package UR::BoolExpr::BxParser;
use vars qw ( @ISA );
use strict;

@ISA= qw ( Parse::Yapp::Driver );
use Parse::Yapp::Driver;



sub new {
        my($class)=shift;
        ref($class)
    and $class=ref($class);

    my($self)=$class->SUPER::new( yyversion => '1.05',
                                  yystates =>
[
	{#State 0
		ACTIONS => {
			'LEFT_PAREN' => 2,
			'IDENTIFIER' => 1
		},
		DEFAULT => -1,
		GOTOS => {
			'boolexpr' => 3,
			'expr' => 4,
			'condition' => 6,
			'property' => 5
		}
	},
	{#State 1
		DEFAULT => -17
	},
	{#State 2
		ACTIONS => {
			'LEFT_PAREN' => 2,
			'IDENTIFIER' => 1
		},
		GOTOS => {
			'expr' => 7,
			'condition' => 6,
			'property' => 5
		}
	},
	{#State 3
		ACTIONS => {
			'' => 8,
			'ORDER_BY' => 10,
			'GROUP_BY' => 9
		}
	},
	{#State 4
		ACTIONS => {
			'AND' => 11,
			'OR' => 12
		},
		DEFAULT => -2
	},
	{#State 5
		ACTIONS => {
			'DOUBLEEQUAL_SIGN' => 13,
			'NOT_BANG' => 20,
			'NOT_WORD' => 21,
			'COLON' => 14,
			'LIKE_WORD' => 22,
			'OPERATORS' => 15,
			'EQUAL_SIGN' => 23,
			'BETWEEN_WORD' => 17,
			'TILDE' => 24,
			'IN_WORD' => 26
		},
		GOTOS => {
			'operator' => 16,
			'like_operator' => 18,
			'an_operator' => 19,
			'in_operator' => 25,
			'between_operator' => 27,
			'negation' => 28
		}
	},
	{#State 6
		DEFAULT => -5
	},
	{#State 7
		ACTIONS => {
			'AND' => 11,
			'OR' => 12,
			'RIGHT_PAREN' => 29
		}
	},
	{#State 8
		DEFAULT => 0
	},
	{#State 9
		ACTIONS => {
			'IDENTIFIER' => 1
		},
		GOTOS => {
			'group_by_list' => 30,
			'property' => 31
		}
	},
	{#State 10
		ACTIONS => {
			'IDENTIFIER' => 1,
			'MINUS' => 32
		},
		GOTOS => {
			'order_by_list' => 34,
			'property' => 33
		}
	},
	{#State 11
		ACTIONS => {
			'IDENTIFIER' => 1,
			'LEFT_PAREN' => 2
		},
		GOTOS => {
			'expr' => 35,
			'condition' => 6,
			'property' => 5
		}
	},
	{#State 12
		ACTIONS => {
			'IDENTIFIER' => 1,
			'LEFT_PAREN' => 2
		},
		GOTOS => {
			'expr' => 36,
			'condition' => 6,
			'property' => 5
		}
	},
	{#State 13
		DEFAULT => -30
	},
	{#State 14
		ACTIONS => {
			'INTEGER' => 44,
			'WORD' => 37,
			'IDENTIFIER' => 45,
			'DOUBLEQUOTE_STRING' => 38,
			'NOT_WORD' => 47,
			'MINUS' => 39,
			'LIKE_WORD' => 50,
			'AND' => 51,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 52,
			'OR' => 53,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 54
		},
		GOTOS => {
			'between_value' => 46,
			'number' => 40,
			'value' => 49,
			'keyword_as_value' => 48,
			'old_syntax_in_value' => 41
		}
	},
	{#State 15
		DEFAULT => -28
	},
	{#State 16
		ACTIONS => {
			'INTEGER' => 44,
			'WORD' => 37,
			'IDENTIFIER' => 45,
			'DOUBLEQUOTE_STRING' => 38,
			'NOT_WORD' => 47,
			'MINUS' => 39,
			'LIKE_WORD' => 50,
			'AND' => 51,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 52,
			'OR' => 53,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 54
		},
		GOTOS => {
			'number' => 40,
			'value' => 55,
			'keyword_as_value' => 48
		}
	},
	{#State 17
		DEFAULT => -44
	},
	{#State 18
		ACTIONS => {
			'INTEGER' => 44,
			'WORD' => 37,
			'IDENTIFIER' => 45,
			'DOUBLEQUOTE_STRING' => 38,
			'NOT_WORD' => 47,
			'MINUS' => 39,
			'LIKE_WORD' => 50,
			'AND' => 51,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 52,
			'OR' => 53,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 54,
			'LIKE_PATTERN' => 57
		},
		GOTOS => {
			'number' => 40,
			'value' => 58,
			'keyword_as_value' => 48,
			'like_value' => 56
		}
	},
	{#State 19
		DEFAULT => -24
	},
	{#State 20
		DEFAULT => -27
	},
	{#State 21
		DEFAULT => -26
	},
	{#State 22
		DEFAULT => -31
	},
	{#State 23
		DEFAULT => -29
	},
	{#State 24
		DEFAULT => -33
	},
	{#State 25
		ACTIONS => {
			'LEFT_BRACKET' => 59
		},
		GOTOS => {
			'set' => 60
		}
	},
	{#State 26
		DEFAULT => -37
	},
	{#State 27
		ACTIONS => {
			'INTEGER' => 44,
			'WORD' => 37,
			'IDENTIFIER' => 45,
			'DOUBLEQUOTE_STRING' => 38,
			'NOT_WORD' => 47,
			'MINUS' => 39,
			'LIKE_WORD' => 50,
			'AND' => 51,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 52,
			'OR' => 53,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 54
		},
		GOTOS => {
			'between_value' => 61,
			'number' => 40,
			'value' => 62,
			'keyword_as_value' => 48
		}
	},
	{#State 28
		ACTIONS => {
			'DOUBLEEQUAL_SIGN' => 13,
			'BETWEEN_WORD' => 64,
			'TILDE' => 67,
			'COLON' => 63,
			'LIKE_WORD' => 66,
			'OPERATORS' => 15,
			'IN_WORD' => 68,
			'EQUAL_SIGN' => 23
		},
		GOTOS => {
			'an_operator' => 65
		}
	},
	{#State 29
		DEFAULT => -8
	},
	{#State 30
		DEFAULT => -4
	},
	{#State 31
		ACTIONS => {
			'AND' => 69
		},
		DEFAULT => -22
	},
	{#State 32
		ACTIONS => {
			'IDENTIFIER' => 1
		},
		GOTOS => {
			'property' => 70
		}
	},
	{#State 33
		ACTIONS => {
			'AND' => 71
		},
		DEFAULT => -18
	},
	{#State 34
		DEFAULT => -3
	},
	{#State 35
		ACTIONS => {
			'AND' => 11
		},
		DEFAULT => -6
	},
	{#State 36
		ACTIONS => {
			'AND' => 11,
			'OR' => 12
		},
		DEFAULT => -7
	},
	{#State 37
		DEFAULT => -55
	},
	{#State 38
		DEFAULT => -56
	},
	{#State 39
		ACTIONS => {
			'INTEGER' => 73,
			'REAL' => 72
		}
	},
	{#State 40
		DEFAULT => -54
	},
	{#State 41
		DEFAULT => -12
	},
	{#State 42
		DEFAULT => -51
	},
	{#State 43
		DEFAULT => -60
	},
	{#State 44
		DEFAULT => -59
	},
	{#State 45
		DEFAULT => -53
	},
	{#State 46
		DEFAULT => -15
	},
	{#State 47
		DEFAULT => -52
	},
	{#State 48
		DEFAULT => -58
	},
	{#State 49
		ACTIONS => {
			'IN_DIVIDER' => 75,
			'MINUS' => 74
		}
	},
	{#State 50
		DEFAULT => -50
	},
	{#State 51
		DEFAULT => -47
	},
	{#State 52
		DEFAULT => -49
	},
	{#State 53
		DEFAULT => -48
	},
	{#State 54
		DEFAULT => -57
	},
	{#State 55
		DEFAULT => -9
	},
	{#State 56
		DEFAULT => -10
	},
	{#State 57
		DEFAULT => -36
	},
	{#State 58
		DEFAULT => -35
	},
	{#State 59
		ACTIONS => {
			'INTEGER' => 44,
			'WORD' => 37,
			'IDENTIFIER' => 45,
			'DOUBLEQUOTE_STRING' => 38,
			'NOT_WORD' => 47,
			'MINUS' => 39,
			'LIKE_WORD' => 50,
			'AND' => 51,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 52,
			'OR' => 53,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 54
		},
		GOTOS => {
			'set_body' => 76,
			'number' => 40,
			'value' => 77,
			'keyword_as_value' => 48
		}
	},
	{#State 60
		DEFAULT => -11
	},
	{#State 61
		DEFAULT => -14
	},
	{#State 62
		ACTIONS => {
			'MINUS' => 74
		}
	},
	{#State 63
		ACTIONS => {
			'INTEGER' => 44,
			'WORD' => 37,
			'IDENTIFIER' => 45,
			'DOUBLEQUOTE_STRING' => 38,
			'NOT_WORD' => 47,
			'MINUS' => 39,
			'LIKE_WORD' => 50,
			'AND' => 51,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 52,
			'OR' => 53,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 54
		},
		GOTOS => {
			'between_value' => 79,
			'number' => 40,
			'value' => 49,
			'keyword_as_value' => 48,
			'old_syntax_in_value' => 78
		}
	},
	{#State 64
		DEFAULT => -45
	},
	{#State 65
		DEFAULT => -25
	},
	{#State 66
		DEFAULT => -32
	},
	{#State 67
		DEFAULT => -34
	},
	{#State 68
		DEFAULT => -38
	},
	{#State 69
		ACTIONS => {
			'IDENTIFIER' => 1
		},
		GOTOS => {
			'group_by_list' => 80,
			'property' => 31
		}
	},
	{#State 70
		ACTIONS => {
			'AND' => 81
		},
		DEFAULT => -19
	},
	{#State 71
		ACTIONS => {
			'IDENTIFIER' => 1,
			'MINUS' => 32
		},
		GOTOS => {
			'order_by_list' => 82,
			'property' => 33
		}
	},
	{#State 72
		DEFAULT => -62
	},
	{#State 73
		DEFAULT => -61
	},
	{#State 74
		ACTIONS => {
			'INTEGER' => 44,
			'WORD' => 37,
			'IDENTIFIER' => 45,
			'DOUBLEQUOTE_STRING' => 38,
			'NOT_WORD' => 47,
			'MINUS' => 39,
			'LIKE_WORD' => 50,
			'AND' => 51,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 52,
			'OR' => 53,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 54
		},
		GOTOS => {
			'number' => 40,
			'value' => 83,
			'keyword_as_value' => 48
		}
	},
	{#State 75
		ACTIONS => {
			'INTEGER' => 44,
			'WORD' => 37,
			'IDENTIFIER' => 45,
			'DOUBLEQUOTE_STRING' => 38,
			'NOT_WORD' => 47,
			'MINUS' => 39,
			'LIKE_WORD' => 50,
			'AND' => 51,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 52,
			'OR' => 53,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 54
		},
		GOTOS => {
			'number' => 40,
			'value' => 85,
			'keyword_as_value' => 48,
			'old_syntax_in_value' => 84
		}
	},
	{#State 76
		ACTIONS => {
			'RIGHT_BRACKET' => 86
		}
	},
	{#State 77
		ACTIONS => {
			'SET_SEPARATOR' => 87
		},
		DEFAULT => -43
	},
	{#State 78
		DEFAULT => -13
	},
	{#State 79
		DEFAULT => -16
	},
	{#State 80
		DEFAULT => -23
	},
	{#State 81
		ACTIONS => {
			'IDENTIFIER' => 1,
			'MINUS' => 32
		},
		GOTOS => {
			'order_by_list' => 88,
			'property' => 33
		}
	},
	{#State 82
		DEFAULT => -20
	},
	{#State 83
		DEFAULT => -46
	},
	{#State 84
		DEFAULT => -39
	},
	{#State 85
		ACTIONS => {
			'IN_DIVIDER' => 75
		},
		DEFAULT => -40
	},
	{#State 86
		DEFAULT => -41
	},
	{#State 87
		ACTIONS => {
			'INTEGER' => 44,
			'WORD' => 37,
			'IDENTIFIER' => 45,
			'DOUBLEQUOTE_STRING' => 38,
			'NOT_WORD' => 47,
			'MINUS' => 39,
			'LIKE_WORD' => 50,
			'AND' => 51,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 52,
			'OR' => 53,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 54
		},
		GOTOS => {
			'set_body' => 89,
			'number' => 40,
			'value' => 77,
			'keyword_as_value' => 48
		}
	},
	{#State 88
		DEFAULT => -21
	},
	{#State 89
		DEFAULT => -42
	}
],
                                  yyrules  =>
[
	[#Rule 0
		 '$start', 2, undef
	],
	[#Rule 1
		 'boolexpr', 0,
sub
#line 10 "BxParser.yp"
{ [] }
	],
	[#Rule 2
		 'boolexpr', 1,
sub
#line 11 "BxParser.yp"
{ UR::BoolExpr::BxParser->_simplify($_[1]) }
	],
	[#Rule 3
		 'boolexpr', 3,
sub
#line 12 "BxParser.yp"
{ [@{$_[1]}, '-order', $_[3]] }
	],
	[#Rule 4
		 'boolexpr', 3,
sub
#line 13 "BxParser.yp"
{ [@{$_[1]}, '-group', $_[3]] }
	],
	[#Rule 5
		 'expr', 1,
sub
#line 16 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 6
		 'expr', 3,
sub
#line 17 "BxParser.yp"
{ UR::BoolExpr::BxParser->_and($_[1], $_[3]) }
	],
	[#Rule 7
		 'expr', 3,
sub
#line 18 "BxParser.yp"
{ UR::BoolExpr::BxParser->_or($_[1], $_[3]) }
	],
	[#Rule 8
		 'expr', 3,
sub
#line 19 "BxParser.yp"
{ $_[2] }
	],
	[#Rule 9
		 'condition', 3,
sub
#line 22 "BxParser.yp"
{ [ "$_[1] $_[2]" => $_[3] ] }
	],
	[#Rule 10
		 'condition', 3,
sub
#line 23 "BxParser.yp"
{ [ "$_[1] $_[2]" => $_[3] ] }
	],
	[#Rule 11
		 'condition', 3,
sub
#line 24 "BxParser.yp"
{ [ "$_[1] $_[2]" => $_[3] ] }
	],
	[#Rule 12
		 'condition', 3,
sub
#line 25 "BxParser.yp"
{ [ "$_[1] in" => $_[3] ] }
	],
	[#Rule 13
		 'condition', 4,
sub
#line 26 "BxParser.yp"
{ [ "$_[1] $_[2] in" => $_[4] ] }
	],
	[#Rule 14
		 'condition', 3,
sub
#line 27 "BxParser.yp"
{ [ "$_[1] $_[2]" => $_[3] ] }
	],
	[#Rule 15
		 'condition', 3,
sub
#line 28 "BxParser.yp"
{ [ "$_[1] between" => $_[3] ] }
	],
	[#Rule 16
		 'condition', 4,
sub
#line 29 "BxParser.yp"
{ [ "$_[1] $_[2] between" => $_[4] ] }
	],
	[#Rule 17
		 'property', 1,
sub
#line 32 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 18
		 'order_by_list', 1,
sub
#line 35 "BxParser.yp"
{ [ $_[1] ] }
	],
	[#Rule 19
		 'order_by_list', 2,
sub
#line 36 "BxParser.yp"
{ [ '-'.$_[2] ] }
	],
	[#Rule 20
		 'order_by_list', 3,
sub
#line 37 "BxParser.yp"
{ [$_[1], @{$_[3]}] }
	],
	[#Rule 21
		 'order_by_list', 4,
sub
#line 38 "BxParser.yp"
{ [ '-'.$_[2], @{$_[4]}] }
	],
	[#Rule 22
		 'group_by_list', 1,
sub
#line 41 "BxParser.yp"
{ [ $_[1] ] }
	],
	[#Rule 23
		 'group_by_list', 3,
sub
#line 42 "BxParser.yp"
{ [$_[1], @{$_[3]}] }
	],
	[#Rule 24
		 'operator', 1,
sub
#line 45 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 25
		 'operator', 2,
sub
#line 46 "BxParser.yp"
{ "$_[1] $_[2]" }
	],
	[#Rule 26
		 'negation', 1,
sub
#line 49 "BxParser.yp"
{ 'not' }
	],
	[#Rule 27
		 'negation', 1,
sub
#line 50 "BxParser.yp"
{ 'not' }
	],
	[#Rule 28
		 'an_operator', 1,
sub
#line 53 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 29
		 'an_operator', 1,
sub
#line 54 "BxParser.yp"
{ '=' }
	],
	[#Rule 30
		 'an_operator', 1,
sub
#line 55 "BxParser.yp"
{ '=' }
	],
	[#Rule 31
		 'like_operator', 1,
sub
#line 58 "BxParser.yp"
{ 'like' }
	],
	[#Rule 32
		 'like_operator', 2,
sub
#line 59 "BxParser.yp"
{ "$_[1] like" }
	],
	[#Rule 33
		 'like_operator', 1,
sub
#line 60 "BxParser.yp"
{ 'like' }
	],
	[#Rule 34
		 'like_operator', 2,
sub
#line 61 "BxParser.yp"
{ "$_[1] like" }
	],
	[#Rule 35
		 'like_value', 1,
sub
#line 64 "BxParser.yp"
{ '%' . $_[1] . '%' }
	],
	[#Rule 36
		 'like_value', 1,
sub
#line 65 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 37
		 'in_operator', 1,
sub
#line 68 "BxParser.yp"
{ 'in' }
	],
	[#Rule 38
		 'in_operator', 2,
sub
#line 69 "BxParser.yp"
{ "$_[1] in" }
	],
	[#Rule 39
		 'old_syntax_in_value', 3,
sub
#line 72 "BxParser.yp"
{ [ $_[1], @{$_[3]} ] }
	],
	[#Rule 40
		 'old_syntax_in_value', 3,
sub
#line 73 "BxParser.yp"
{ [ $_[1], $_[3] ] }
	],
	[#Rule 41
		 'set', 3,
sub
#line 76 "BxParser.yp"
{ $_[2] }
	],
	[#Rule 42
		 'set_body', 3,
sub
#line 79 "BxParser.yp"
{ [ $_[1], @{$_[3]} ] }
	],
	[#Rule 43
		 'set_body', 1,
sub
#line 80 "BxParser.yp"
{ [ $_[1] ] }
	],
	[#Rule 44
		 'between_operator', 1,
sub
#line 83 "BxParser.yp"
{ 'between' }
	],
	[#Rule 45
		 'between_operator', 2,
sub
#line 84 "BxParser.yp"
{ "$_[1] between" }
	],
	[#Rule 46
		 'between_value', 3,
sub
#line 87 "BxParser.yp"
{ [ $_[1], $_[3] ] }
	],
	[#Rule 47
		 'keyword_as_value', 1,
sub
#line 90 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 48
		 'keyword_as_value', 1,
sub
#line 91 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 49
		 'keyword_as_value', 1,
sub
#line 92 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 50
		 'keyword_as_value', 1,
sub
#line 93 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 51
		 'keyword_as_value', 1,
sub
#line 94 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 52
		 'keyword_as_value', 1,
sub
#line 95 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 53
		 'value', 1,
sub
#line 98 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 54
		 'value', 1,
sub
#line 99 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 55
		 'value', 1,
sub
#line 100 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 56
		 'value', 1,
sub
#line 101 "BxParser.yp"
{ ($_[1] =~ m/^"(.*?)"$/)[0]; }
	],
	[#Rule 57
		 'value', 1,
sub
#line 102 "BxParser.yp"
{ ($_[1] =~ m/^'(.*?)'$/)[0]; }
	],
	[#Rule 58
		 'value', 1,
sub
#line 103 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 59
		 'number', 1,
sub
#line 106 "BxParser.yp"
{ $_[1] + 0 }
	],
	[#Rule 60
		 'number', 1,
sub
#line 107 "BxParser.yp"
{ $_[1] + 0 }
	],
	[#Rule 61
		 'number', 2,
sub
#line 108 "BxParser.yp"
{ 0 - $_[2] }
	],
	[#Rule 62
		 'number', 2,
sub
#line 109 "BxParser.yp"
{ 0 - $_[2] }
	]
],
                                  @_);
    bless($self,$class);
}

#line 112 "BxParser.yp"


use strict;
use warnings;

sub _error {
    my @expect = $_[0]->YYExpect;
    my $tok = $_[0]->YYData->{INPUT};
    my $string = $_[0]->YYData->{STRING};
    my $err = qq(Can't parse expression "$string"\n  Syntax error near token '$tok');
    my $rem = $_[0]->YYData->{REMAINING};
    $err .= ", remaining text: '$rem'" if $rem;
    $err .= "\nExpected one of: " . join(", ", @expect) . "\n";
    Carp::croak($err);
}

my %token_states = (
    'DEFAULT' => [
        AND => [ qr{and}, 'DEFAULT'],
        OR => [ qr{or}, 'DEFAULT' ],
        BETWEEN_WORD => qr{between},
        LIKE_WORD => qr{like},
        IN_WORD => qr{in},
        NOT_WORD => qr{not},
        IDENTIFIER => qr{[a-zA-Z_][a-zA-Z0-9_.]*},
        MINUS => qr{-},
        INTEGER => qr{\d+},
        REAL => qr{\d*\.\d+|\d+\.\d*},
        WORD => qr{[\/\w][-\w\/]*},   # also allow / for pathnames and - for hyphenated names
        DOUBLEQUOTE_STRING => qr{"(?:\\.|[^"])+"},
        SINGLEQUOTE_STRING => qr{'(?:\\.|[^'])+'},
        LEFT_PAREN => qr{\(},
        RIGHT_PAREN => qr{\)},
        LEFT_BRACKET => [ qr{\[}, 'set_contents'],
        RIGHT_BRACKET => [qr{\]}, 'DEFAULT' ],
        NOT_BANG => qr{!},
        EQUAL_SIGN => qr{=},
        DOUBLEEQUAL_SIGN => qr{=>},
        OPERATORS => qr{<|>|<=|>=},
        AND => [ qr{,}, 'DEFAULT' ],
        COLON => [ qr{:}, 'after_colon_value' ],
        TILDE => qr{~},
        LIKE_PATTERN => qr{[\w%_]+},
        ORDER_BY => qr{order by},
        GROUP_BY => qr{group by},
    ],
    'set_contents' => [
        SET_SEPARATOR => [qr{,}, ''],  # Depending on state, can be either AND or SET_SEPARATOR
    ],
    'after_colon_value' => [
        INTEGER => qr{\d+},
        REAL => qr{\d*\.\d+|\d+\.\d*},
        IN_DIVIDER => qr{\/},
        WORD => qr{\w+},    # Override WORD in DEFAULT to disallow /
        DOUBLEQUOTE_STRING => qr{"(?:\\.|[^"])+"},
        SINGLEQUOTE_STRING => qr{'(?:\\.|[^'])+'},
    ],
);

sub parse {
    my $string = shift;
    my %params = @_;

    my $debug = $params{'debug'};

    print "\nStarting parse for string $string\n" if $debug;
    my $parser = UR::BoolExpr::BxParser->new();
    $parser->YYData->{STRING} = $string;

    $parser->YYData->{PARSER_STATE} = 'DEFAULT';

    my $get_next_token = sub {
        if (length($string) == 0) {
            print "String is empty, we're done!\n" if $debug;
            return (undef, '');  
       }

        my $parser_state = $parser->YYData->{PARSER_STATE};

        my $longest = 0;
        my $longest_token = '';
        my $longest_match = '';
        my $next_parser_state = $parser_state;

        for my $token_list ( $parser_state, 'DEFAULT' ) {
            print "\nTrying tokens for state $token_list...\n" if $debug;
            my $tokens = $token_states{$token_list};
            for(my $i = 0; $i < @$tokens; $i += 2) {
                my($tok, $re) = @$tokens[$i, $i+1];
                print "Trying token $tok... " if $debug;

                my($regex,$possible_next_parser_state);
                if (ref($re) eq 'ARRAY') {
                    ($regex,$possible_next_parser_state) = @$re;
                } else {
                    $regex = $re;
                    $possible_next_parser_state = $next_parser_state;
                }

                if ($string =~ m/^((\s*)($regex)(\s*))/) {
                    print "Matched >>$1<<" if $debug;
                    my $match_len = length($1);
                    if ($match_len > $longest) {
                        print "\n  ** It's now the longest" if $debug;
                        $longest = $match_len;
                        $longest_token = $tok;
                        $longest_match = $3;
                        if (length($2) or length($4)) {
                            $next_parser_state = 'DEFAULT';
                        } else {
                            $next_parser_state = $possible_next_parser_state;
                        }
                    }
                }
                print "\n" if $debug;
            }

            $string = substr($string, $longest);
            print "Consuming up to char pos $longest chars, string is now >>$string<<\n" if $debug;
            $parser->YYData->{REMAINING} = $string;
            if ($longest) {
                print "Returning token $longest_token, match $longest_match\n" if $debug;
                $parser->YYData->{PARSER_STATE} = $next_parser_state if ($next_parser_state);
                print "  next state is named ".$parser->YYData->{PARSER_STATE}."\n" if $debug;
                $parser->YYData->{INPUT} = $longest_token;
                return ($longest_token, $longest_match);
            }
            last if $token_list eq 'DEFAULT';  # avoid going over it twice if $parser_state is DEFAULT
        }
        print "Didn't match anything, done!\n" if $debug;
        return (undef, '');  # Didn't match anything
    };

    return $parser->YYParse(
               yylex => $get_next_token,
               yyerror => \&_error,
               yydebug => 0,
           );
}

# Used by the top-level expr production to turn an or-type parse tree with
# only a single AND condition into a simple AND-type tree (1-level arrayref).
# Or to add the '-or' to the front of a real OR-type tree so it can be passed
# directly to UR::BoolExpr::resolve()
sub _simplify {
    my($class, $expr) = @_;

    if (ref($expr->[0])) {
        if (@$expr == 1) {
            # An or-type parse tree, but with only one AND subrule - use as a simple and-type rule
            $expr = $expr->[0];
        } else {
            $expr = ['-or', $expr]; # an or-type parse tree with multiple subrules
        }
    }
    return $expr;
}

# Handles the case for "expr AND expr" where one or both exprs can be an
# OR-type expr.  In that case, it distributes the AND exprs among all the
# OR conditions.  For example:
# (a=1 or b=2) and (c=3 or d=4)
# is the same as
# (a=1 and c=3) or (a=1 and d=4) or (b=2 and c=3) or (b=2 and d=4)
# This is necessary because the BoolExpr resolver can only handle 1-level deep
# AND-type rules, or a 1-level deep OR-type rule composed of any number of
# 1-level deep AND-type rules
sub _and {
    my($class,$left, $right) = @_;

    # force them to be [[ "property operator" => value]] instead of just [ "property operator" => value ]
    $left  = [ $left ]  unless (ref($left->[0]));
    $right = [ $right ] unless (ref($right->[0]));

    my @and;
    foreach my $left_subexpr ( @$left ) {
        foreach my $right_subexpr (@$right) {
            push @and, [@$left_subexpr, @$right_subexpr];
        }
    }
    \@and;
}

sub _or {
    my($class,$left, $right) = @_;

    # force them to be [[ "property operator" => value]] instead of just [ "property operator" => value ]
    $left  = [ $left ]  unless (ref($left->[0]));
    $right = [ $right ] unless (ref($right->[0]));

    [ @$left, @$right ];
}

1;


1;
