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
			'INTEGER' => 45,
			'LEFT_BRACKET' => 38,
			'WORD' => 37,
			'IDENTIFIER' => 46,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 48,
			'MINUS' => 40,
			'LIKE_WORD' => 51,
			'AND' => 52,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 54,
			'OR' => 55,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 56
		},
		GOTOS => {
			'in_value' => 53,
			'between_value' => 47,
			'number' => 41,
			'value' => 50,
			'keyword_as_value' => 49,
			'set' => 44
		}
	},
	{#State 15
		DEFAULT => -28
	},
	{#State 16
		ACTIONS => {
			'INTEGER' => 45,
			'WORD' => 37,
			'IDENTIFIER' => 46,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 48,
			'MINUS' => 40,
			'LIKE_WORD' => 51,
			'AND' => 52,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 54,
			'OR' => 55,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 56
		},
		GOTOS => {
			'number' => 41,
			'value' => 57,
			'keyword_as_value' => 49
		}
	},
	{#State 17
		DEFAULT => -45
	},
	{#State 18
		ACTIONS => {
			'INTEGER' => 45,
			'WORD' => 37,
			'IDENTIFIER' => 46,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 48,
			'MINUS' => 40,
			'LIKE_WORD' => 51,
			'AND' => 52,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 54,
			'OR' => 55,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 56,
			'LIKE_PATTERN' => 59
		},
		GOTOS => {
			'number' => 41,
			'value' => 60,
			'keyword_as_value' => 49,
			'like_value' => 58
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
			'INTEGER' => 45,
			'LEFT_BRACKET' => 38,
			'WORD' => 37,
			'IDENTIFIER' => 46,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 48,
			'MINUS' => 40,
			'LIKE_WORD' => 51,
			'AND' => 52,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 54,
			'OR' => 55,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 56
		},
		GOTOS => {
			'in_value' => 62,
			'number' => 41,
			'value' => 61,
			'keyword_as_value' => 49,
			'set' => 44
		}
	},
	{#State 26
		DEFAULT => -37
	},
	{#State 27
		ACTIONS => {
			'INTEGER' => 45,
			'WORD' => 37,
			'IDENTIFIER' => 46,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 48,
			'MINUS' => 40,
			'LIKE_WORD' => 51,
			'AND' => 52,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 54,
			'OR' => 55,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 56
		},
		GOTOS => {
			'between_value' => 63,
			'number' => 41,
			'value' => 64,
			'keyword_as_value' => 49
		}
	},
	{#State 28
		ACTIONS => {
			'DOUBLEEQUAL_SIGN' => 13,
			'BETWEEN_WORD' => 66,
			'TILDE' => 69,
			'COLON' => 65,
			'LIKE_WORD' => 68,
			'OPERATORS' => 15,
			'IN_WORD' => 70,
			'EQUAL_SIGN' => 23
		},
		GOTOS => {
			'an_operator' => 67
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
			'AND' => 71
		},
		DEFAULT => -22
	},
	{#State 32
		ACTIONS => {
			'IDENTIFIER' => 1
		},
		GOTOS => {
			'property' => 72
		}
	},
	{#State 33
		ACTIONS => {
			'AND' => 73
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
		DEFAULT => -56
	},
	{#State 38
		ACTIONS => {
			'INTEGER' => 45,
			'WORD' => 37,
			'IDENTIFIER' => 46,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 48,
			'MINUS' => 40,
			'LIKE_WORD' => 51,
			'AND' => 52,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 54,
			'OR' => 55,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 56
		},
		GOTOS => {
			'set_body' => 74,
			'number' => 41,
			'value' => 75,
			'keyword_as_value' => 49
		}
	},
	{#State 39
		DEFAULT => -57
	},
	{#State 40
		ACTIONS => {
			'INTEGER' => 77,
			'REAL' => 76
		}
	},
	{#State 41
		DEFAULT => -55
	},
	{#State 42
		DEFAULT => -52
	},
	{#State 43
		DEFAULT => -61
	},
	{#State 44
		DEFAULT => -39
	},
	{#State 45
		DEFAULT => -60
	},
	{#State 46
		DEFAULT => -54
	},
	{#State 47
		DEFAULT => -15
	},
	{#State 48
		DEFAULT => -53
	},
	{#State 49
		DEFAULT => -59
	},
	{#State 50
		ACTIONS => {
			'IN_DIVIDER' => 79,
			'MINUS' => 78
		}
	},
	{#State 51
		DEFAULT => -51
	},
	{#State 52
		DEFAULT => -48
	},
	{#State 53
		DEFAULT => -12
	},
	{#State 54
		DEFAULT => -50
	},
	{#State 55
		DEFAULT => -49
	},
	{#State 56
		DEFAULT => -58
	},
	{#State 57
		DEFAULT => -9
	},
	{#State 58
		DEFAULT => -10
	},
	{#State 59
		DEFAULT => -36
	},
	{#State 60
		DEFAULT => -35
	},
	{#State 61
		ACTIONS => {
			'IN_DIVIDER' => 79
		}
	},
	{#State 62
		DEFAULT => -11
	},
	{#State 63
		DEFAULT => -14
	},
	{#State 64
		ACTIONS => {
			'MINUS' => 78
		}
	},
	{#State 65
		ACTIONS => {
			'INTEGER' => 45,
			'LEFT_BRACKET' => 38,
			'WORD' => 37,
			'IDENTIFIER' => 46,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 48,
			'MINUS' => 40,
			'LIKE_WORD' => 51,
			'AND' => 52,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 54,
			'OR' => 55,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 56
		},
		GOTOS => {
			'in_value' => 81,
			'between_value' => 80,
			'number' => 41,
			'value' => 50,
			'keyword_as_value' => 49,
			'set' => 44
		}
	},
	{#State 66
		DEFAULT => -46
	},
	{#State 67
		DEFAULT => -25
	},
	{#State 68
		DEFAULT => -32
	},
	{#State 69
		DEFAULT => -34
	},
	{#State 70
		DEFAULT => -38
	},
	{#State 71
		ACTIONS => {
			'IDENTIFIER' => 1
		},
		GOTOS => {
			'group_by_list' => 82,
			'property' => 31
		}
	},
	{#State 72
		ACTIONS => {
			'AND' => 83
		},
		DEFAULT => -19
	},
	{#State 73
		ACTIONS => {
			'IDENTIFIER' => 1,
			'MINUS' => 32
		},
		GOTOS => {
			'order_by_list' => 84,
			'property' => 33
		}
	},
	{#State 74
		ACTIONS => {
			'RIGHT_BRACKET' => 85
		}
	},
	{#State 75
		ACTIONS => {
			'SET_SEPARATOR' => 86
		},
		DEFAULT => -44
	},
	{#State 76
		DEFAULT => -63
	},
	{#State 77
		DEFAULT => -62
	},
	{#State 78
		ACTIONS => {
			'INTEGER' => 45,
			'WORD' => 37,
			'IDENTIFIER' => 46,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 48,
			'MINUS' => 40,
			'LIKE_WORD' => 51,
			'AND' => 52,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 54,
			'OR' => 55,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 56
		},
		GOTOS => {
			'number' => 41,
			'value' => 87,
			'keyword_as_value' => 49
		}
	},
	{#State 79
		ACTIONS => {
			'INTEGER' => 45,
			'LEFT_BRACKET' => 38,
			'WORD' => 37,
			'IDENTIFIER' => 46,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 48,
			'MINUS' => 40,
			'LIKE_WORD' => 51,
			'AND' => 52,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 54,
			'OR' => 55,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 56
		},
		GOTOS => {
			'in_value' => 89,
			'number' => 41,
			'value' => 88,
			'keyword_as_value' => 49,
			'set' => 44
		}
	},
	{#State 80
		DEFAULT => -16
	},
	{#State 81
		DEFAULT => -13
	},
	{#State 82
		DEFAULT => -23
	},
	{#State 83
		ACTIONS => {
			'IDENTIFIER' => 1,
			'MINUS' => 32
		},
		GOTOS => {
			'order_by_list' => 90,
			'property' => 33
		}
	},
	{#State 84
		DEFAULT => -20
	},
	{#State 85
		DEFAULT => -42
	},
	{#State 86
		ACTIONS => {
			'INTEGER' => 45,
			'WORD' => 37,
			'IDENTIFIER' => 46,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 48,
			'MINUS' => 40,
			'LIKE_WORD' => 51,
			'AND' => 52,
			'BETWEEN_WORD' => 42,
			'IN_WORD' => 54,
			'OR' => 55,
			'REAL' => 43,
			'SINGLEQUOTE_STRING' => 56
		},
		GOTOS => {
			'set_body' => 91,
			'number' => 41,
			'value' => 75,
			'keyword_as_value' => 49
		}
	},
	{#State 87
		DEFAULT => -47
	},
	{#State 88
		ACTIONS => {
			'IN_DIVIDER' => 79
		},
		DEFAULT => -41
	},
	{#State 89
		DEFAULT => -40
	},
	{#State 90
		DEFAULT => -21
	},
	{#State 91
		DEFAULT => -43
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
{
                                    foreach my $i ( 1,3 ) {
                                        unless (ref($_[$i][0])) {
                                            $_[$i] = [$_[$i]];
                                        }
                                    }
                                    my @and;
                                    foreach my $left ( @{$_[1]} ) {
                                        foreach my $right (@{$_[3]}) {
                                            push @and, [@$left, @$right];
                                        }
                                    }
                                    \@and;
                                  }
	],
	[#Rule 7
		 'expr', 3,
sub
#line 31 "BxParser.yp"
{
                                    foreach my $i ( 1,3 ) {
                                        unless (ref($_[$i][0])) {
                                            $_[$i] = [$_[$i]];
                                        }
                                    }
                                    [ @{$_[1]}, @{$_[3]} ];
                                  }
	],
	[#Rule 8
		 'expr', 3,
sub
#line 39 "BxParser.yp"
{ $_[2] }
	],
	[#Rule 9
		 'condition', 3,
sub
#line 42 "BxParser.yp"
{ [ "$_[1] $_[2]" => $_[3] ] }
	],
	[#Rule 10
		 'condition', 3,
sub
#line 43 "BxParser.yp"
{ [ "$_[1] $_[2]" => $_[3] ] }
	],
	[#Rule 11
		 'condition', 3,
sub
#line 44 "BxParser.yp"
{ [ "$_[1] $_[2]" => $_[3] ] }
	],
	[#Rule 12
		 'condition', 3,
sub
#line 45 "BxParser.yp"
{ [ "$_[1] in" => $_[3] ] }
	],
	[#Rule 13
		 'condition', 4,
sub
#line 46 "BxParser.yp"
{ [ "$_[1] $_[2] in" => $_[4] ] }
	],
	[#Rule 14
		 'condition', 3,
sub
#line 47 "BxParser.yp"
{ [ "$_[1] $_[2]" => $_[3] ] }
	],
	[#Rule 15
		 'condition', 3,
sub
#line 48 "BxParser.yp"
{ [ "$_[1] between" => $_[3] ] }
	],
	[#Rule 16
		 'condition', 4,
sub
#line 49 "BxParser.yp"
{ [ "$_[1] $_[2] between" => $_[4] ] }
	],
	[#Rule 17
		 'property', 1,
sub
#line 52 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 18
		 'order_by_list', 1,
sub
#line 55 "BxParser.yp"
{ [ $_[1] ] }
	],
	[#Rule 19
		 'order_by_list', 2,
sub
#line 56 "BxParser.yp"
{ [ '-'.$_[2] ] }
	],
	[#Rule 20
		 'order_by_list', 3,
sub
#line 57 "BxParser.yp"
{ [$_[1], @{$_[3]}] }
	],
	[#Rule 21
		 'order_by_list', 4,
sub
#line 58 "BxParser.yp"
{ [ '-'.$_[2], @{$_[4]}] }
	],
	[#Rule 22
		 'group_by_list', 1,
sub
#line 61 "BxParser.yp"
{ [ $_[1] ] }
	],
	[#Rule 23
		 'group_by_list', 3,
sub
#line 62 "BxParser.yp"
{ [$_[1], @{$_[3]}] }
	],
	[#Rule 24
		 'operator', 1,
sub
#line 65 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 25
		 'operator', 2,
sub
#line 66 "BxParser.yp"
{ "$_[1] $_[2]" }
	],
	[#Rule 26
		 'negation', 1,
sub
#line 69 "BxParser.yp"
{ 'not' }
	],
	[#Rule 27
		 'negation', 1,
sub
#line 70 "BxParser.yp"
{ 'not' }
	],
	[#Rule 28
		 'an_operator', 1,
sub
#line 73 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 29
		 'an_operator', 1,
sub
#line 74 "BxParser.yp"
{ '=' }
	],
	[#Rule 30
		 'an_operator', 1,
sub
#line 75 "BxParser.yp"
{ '=' }
	],
	[#Rule 31
		 'like_operator', 1,
sub
#line 78 "BxParser.yp"
{ 'like' }
	],
	[#Rule 32
		 'like_operator', 2,
sub
#line 79 "BxParser.yp"
{ "$_[1] like" }
	],
	[#Rule 33
		 'like_operator', 1,
sub
#line 80 "BxParser.yp"
{ 'like' }
	],
	[#Rule 34
		 'like_operator', 2,
sub
#line 81 "BxParser.yp"
{ "$_[1] like" }
	],
	[#Rule 35
		 'like_value', 1,
sub
#line 84 "BxParser.yp"
{ '%' . $_[1] . '%' }
	],
	[#Rule 36
		 'like_value', 1,
sub
#line 85 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 37
		 'in_operator', 1,
sub
#line 88 "BxParser.yp"
{ 'in' }
	],
	[#Rule 38
		 'in_operator', 2,
sub
#line 89 "BxParser.yp"
{ "$_[1] in" }
	],
	[#Rule 39
		 'in_value', 1,
sub
#line 92 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 40
		 'in_value', 3,
sub
#line 93 "BxParser.yp"
{ [ $_[1], @{$_[3]} ] }
	],
	[#Rule 41
		 'in_value', 3,
sub
#line 94 "BxParser.yp"
{ [ $_[1], $_[3] ] }
	],
	[#Rule 42
		 'set', 3,
sub
#line 97 "BxParser.yp"
{ $_[2] }
	],
	[#Rule 43
		 'set_body', 3,
sub
#line 100 "BxParser.yp"
{ [ $_[1], @{$_[3]} ] }
	],
	[#Rule 44
		 'set_body', 1,
sub
#line 101 "BxParser.yp"
{ [ $_[1] ] }
	],
	[#Rule 45
		 'between_operator', 1,
sub
#line 104 "BxParser.yp"
{ 'between' }
	],
	[#Rule 46
		 'between_operator', 2,
sub
#line 105 "BxParser.yp"
{ "$_[1] between" }
	],
	[#Rule 47
		 'between_value', 3,
sub
#line 108 "BxParser.yp"
{ [ $_[1], $_[3] ] }
	],
	[#Rule 48
		 'keyword_as_value', 1,
sub
#line 111 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 49
		 'keyword_as_value', 1,
sub
#line 112 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 50
		 'keyword_as_value', 1,
sub
#line 113 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 51
		 'keyword_as_value', 1,
sub
#line 114 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 52
		 'keyword_as_value', 1,
sub
#line 115 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 53
		 'keyword_as_value', 1,
sub
#line 116 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 54
		 'value', 1,
sub
#line 119 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 55
		 'value', 1,
sub
#line 120 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 56
		 'value', 1,
sub
#line 121 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 57
		 'value', 1,
sub
#line 122 "BxParser.yp"
{ ($_[1] =~ m/^"(.*?)"$/)[0]; }
	],
	[#Rule 58
		 'value', 1,
sub
#line 123 "BxParser.yp"
{ ($_[1] =~ m/^'(.*?)'$/)[0]; }
	],
	[#Rule 59
		 'value', 1,
sub
#line 124 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 60
		 'number', 1,
sub
#line 127 "BxParser.yp"
{ $_[1] + 0 }
	],
	[#Rule 61
		 'number', 1,
sub
#line 128 "BxParser.yp"
{ $_[1] + 0 }
	],
	[#Rule 62
		 'number', 2,
sub
#line 129 "BxParser.yp"
{ 0 - $_[2] }
	],
	[#Rule 63
		 'number', 2,
sub
#line 130 "BxParser.yp"
{ 0 - $_[2] }
	]
],
                                  @_);
    bless($self,$class);
}

#line 133 "BxParser.yp"


use strict;
use warnings;

sub _error {
    my @expect = $_[0]->YYExpect;
    my $tok = $_[0]->YYData->{INPUT};
    my $err = "Syntax error near '$tok'";
    my $rem = $_[0]->YYData->{REMAINING};
    $err .= ", remaining text: '$rem'" if $rem;
    $err .= "\nExpected one of: " . join(", ", @expect) . "\n";
    Carp::croak($err);
}

my @tokens = (
    AND => qr{and},
    OR => qr{or},
    BETWEEN_WORD => qr{between},
    LIKE_WORD => qr{like},
    IN_WORD => qr{in},
    NOT_WORD => qr{not},
    IDENTIFIER => qr{[a-zA-Z_][a-zA-Z0-9_.]*},
    MINUS => qr{-},
    INTEGER => qr{\d+},
    REAL => qr{\d*\.\d+|\d+\.\d*},
    WORD => qr{\w+},
    DOUBLEQUOTE_STRING => qr{"(\\.|[^"])+"},
    SINGLEQUOTE_STRING => qr{'(\\.|[^'])+'},
    LEFT_PAREN => qr{\(},
    RIGHT_PAREN => qr{\)},
    LEFT_BRACKET => qr{\[},
    RIGHT_BRACKET => qr{\]},
    NOT_BANG => qr{!},
    EQUAL_SIGN => qr{=},
    DOUBLEEQUAL_SIGN => qr{=>},
    OPERATORS => qr{<|>|<=|>=},
    COMMA => qr{,},  # Depending on state, can be either AND or SET_SEPARATOR
    COLON => qr{:},
    TILDE => qr{~},
    LIKE_PATTERN => qr{[\w%_]+},
    IN_DIVIDER => qr{\/},
    ORDER_BY => qr{order by},
    GROUP_BY => qr{group by},
);

sub parse {
    my $string = shift;
    my %params = @_;

    my $debug = $params{'debug'};

    print "\nStarting parse for string $string\n" if $debug;
    my $parser = UR::BoolExpr::BxParser->new();

    my $parser_state = '';

    my $get_next_token = sub {
        if (length($string) == 0) {
            print "String is empty, we're done!\n" if $debug;
            return (undef, '');  
       }

        my $longest = 0;
        my $longest_token = '';
        my $longest_match = '';

        for(my $i = 0; $i < @tokens; $i += 2) {
            my($tok, $regex) = @tokens[$i, $i+1];
            print "Trying token $tok... " if $debug;

            if ($string =~ m/^(\s*($regex)\s*)/) {
                print "Matched >>$1<<" if $debug;
                my $match_len = length($1);
                if ($match_len > $longest) {
                    print "\n  ** It's now the longest" if $debug;
                    $longest = $match_len;
                    $longest_token = $tok;
                    $longest_match = $2;
                }
            }
            print "\n" if $debug;
        }

        $string = substr($string, $longest);
        print "Consuming up to char pos $longest chars, string is now >>$string<<\n" if $debug;
        $parser->YYData->{REMAINING} = $string;
        if ($longest) {
            print "Returning token $longest_token, match $longest_match\n" if $debug;
            if ($longest_token eq 'LEFT_BRACKET') {
                $parser_state = 'set_contents';
            } elsif ($longest_token eq 'RIGHT_BRACKET') {
                $parser_state = '';
            } elsif ($longest_token eq 'COMMA') {
                $longest_token = $parser_state eq 'set_contents' ? 'SET_SEPARATOR' : 'AND';
            }
            $parser->YYData->{INPUT} = $longest_token;
            return ($longest_token, $longest_match);
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

1;


1;
