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
			'order_by_list' => 35,
			'order_by_property' => 33,
			'property' => 34
		}
	},
	{#State 11
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
	{#State 12
		ACTIONS => {
			'IDENTIFIER' => 1,
			'LEFT_PAREN' => 2
		},
		GOTOS => {
			'expr' => 37,
			'condition' => 6,
			'property' => 5
		}
	},
	{#State 13
		DEFAULT => -32
	},
	{#State 14
		ACTIONS => {
			'ASC_WORD' => 46,
			'INTEGER' => 45,
			'WORD' => 38,
			'DESC_WORD' => 48,
			'IDENTIFIER' => 47,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 50,
			'MINUS' => 40,
			'LIKE_WORD' => 53,
			'AND' => 54,
			'BETWEEN_WORD' => 43,
			'IN_WORD' => 55,
			'OR' => 56,
			'REAL' => 44,
			'SINGLEQUOTE_STRING' => 57
		},
		GOTOS => {
			'between_value' => 49,
			'number' => 41,
			'value' => 52,
			'keyword_as_value' => 51,
			'old_syntax_in_value' => 42
		}
	},
	{#State 15
		DEFAULT => -30
	},
	{#State 16
		ACTIONS => {
			'ASC_WORD' => 46,
			'INTEGER' => 45,
			'WORD' => 38,
			'DESC_WORD' => 48,
			'IDENTIFIER' => 47,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 50,
			'MINUS' => 40,
			'LIKE_WORD' => 53,
			'AND' => 54,
			'BETWEEN_WORD' => 43,
			'IN_WORD' => 55,
			'OR' => 56,
			'REAL' => 44,
			'SINGLEQUOTE_STRING' => 57
		},
		GOTOS => {
			'number' => 41,
			'value' => 58,
			'keyword_as_value' => 51
		}
	},
	{#State 17
		DEFAULT => -46
	},
	{#State 18
		ACTIONS => {
			'WORD' => 38,
			'DOUBLEQUOTE_STRING' => 39,
			'MINUS' => 40,
			'BETWEEN_WORD' => 43,
			'REAL' => 44,
			'LIKE_PATTERN' => 60,
			'INTEGER' => 45,
			'ASC_WORD' => 46,
			'IDENTIFIER' => 47,
			'DESC_WORD' => 48,
			'NOT_WORD' => 50,
			'LIKE_WORD' => 53,
			'AND' => 54,
			'IN_WORD' => 55,
			'OR' => 56,
			'SINGLEQUOTE_STRING' => 57
		},
		GOTOS => {
			'number' => 41,
			'value' => 61,
			'keyword_as_value' => 51,
			'like_value' => 59
		}
	},
	{#State 19
		DEFAULT => -26
	},
	{#State 20
		DEFAULT => -29
	},
	{#State 21
		DEFAULT => -28
	},
	{#State 22
		DEFAULT => -33
	},
	{#State 23
		DEFAULT => -31
	},
	{#State 24
		DEFAULT => -35
	},
	{#State 25
		ACTIONS => {
			'LEFT_BRACKET' => 62
		},
		GOTOS => {
			'set' => 63
		}
	},
	{#State 26
		DEFAULT => -39
	},
	{#State 27
		ACTIONS => {
			'ASC_WORD' => 46,
			'INTEGER' => 45,
			'WORD' => 38,
			'DESC_WORD' => 48,
			'IDENTIFIER' => 47,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 50,
			'MINUS' => 40,
			'LIKE_WORD' => 53,
			'AND' => 54,
			'BETWEEN_WORD' => 43,
			'IN_WORD' => 55,
			'OR' => 56,
			'REAL' => 44,
			'SINGLEQUOTE_STRING' => 57
		},
		GOTOS => {
			'between_value' => 64,
			'number' => 41,
			'value' => 65,
			'keyword_as_value' => 51
		}
	},
	{#State 28
		ACTIONS => {
			'DOUBLEEQUAL_SIGN' => 13,
			'BETWEEN_WORD' => 67,
			'TILDE' => 70,
			'COLON' => 66,
			'LIKE_WORD' => 69,
			'OPERATORS' => 15,
			'IN_WORD' => 71,
			'EQUAL_SIGN' => 23
		},
		GOTOS => {
			'an_operator' => 68
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
			'AND' => 72
		},
		DEFAULT => -24
	},
	{#State 32
		ACTIONS => {
			'IDENTIFIER' => 1
		},
		GOTOS => {
			'property' => 73
		}
	},
	{#State 33
		ACTIONS => {
			'AND' => 74
		},
		DEFAULT => -22
	},
	{#State 34
		ACTIONS => {
			'ASC_WORD' => 75,
			'DESC_WORD' => 76
		},
		DEFAULT => -18
	},
	{#State 35
		DEFAULT => -3
	},
	{#State 36
		ACTIONS => {
			'AND' => 11
		},
		DEFAULT => -6
	},
	{#State 37
		ACTIONS => {
			'AND' => 11,
			'OR' => 12
		},
		DEFAULT => -7
	},
	{#State 38
		DEFAULT => -59
	},
	{#State 39
		DEFAULT => -60
	},
	{#State 40
		ACTIONS => {
			'INTEGER' => 78,
			'REAL' => 77
		}
	},
	{#State 41
		DEFAULT => -58
	},
	{#State 42
		DEFAULT => -12
	},
	{#State 43
		DEFAULT => -53
	},
	{#State 44
		DEFAULT => -64
	},
	{#State 45
		DEFAULT => -63
	},
	{#State 46
		DEFAULT => -56
	},
	{#State 47
		DEFAULT => -57
	},
	{#State 48
		DEFAULT => -55
	},
	{#State 49
		DEFAULT => -15
	},
	{#State 50
		DEFAULT => -54
	},
	{#State 51
		DEFAULT => -62
	},
	{#State 52
		ACTIONS => {
			'IN_DIVIDER' => 80,
			'MINUS' => 79
		}
	},
	{#State 53
		DEFAULT => -52
	},
	{#State 54
		DEFAULT => -49
	},
	{#State 55
		DEFAULT => -51
	},
	{#State 56
		DEFAULT => -50
	},
	{#State 57
		DEFAULT => -61
	},
	{#State 58
		DEFAULT => -9
	},
	{#State 59
		DEFAULT => -10
	},
	{#State 60
		DEFAULT => -38
	},
	{#State 61
		DEFAULT => -37
	},
	{#State 62
		ACTIONS => {
			'ASC_WORD' => 46,
			'INTEGER' => 45,
			'WORD' => 38,
			'DESC_WORD' => 48,
			'IDENTIFIER' => 47,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 50,
			'MINUS' => 40,
			'LIKE_WORD' => 53,
			'AND' => 54,
			'BETWEEN_WORD' => 43,
			'IN_WORD' => 55,
			'OR' => 56,
			'REAL' => 44,
			'SINGLEQUOTE_STRING' => 57
		},
		GOTOS => {
			'set_body' => 81,
			'number' => 41,
			'value' => 82,
			'keyword_as_value' => 51
		}
	},
	{#State 63
		DEFAULT => -11
	},
	{#State 64
		DEFAULT => -14
	},
	{#State 65
		ACTIONS => {
			'MINUS' => 79
		}
	},
	{#State 66
		ACTIONS => {
			'ASC_WORD' => 46,
			'INTEGER' => 45,
			'WORD' => 38,
			'DESC_WORD' => 48,
			'IDENTIFIER' => 47,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 50,
			'MINUS' => 40,
			'LIKE_WORD' => 53,
			'AND' => 54,
			'BETWEEN_WORD' => 43,
			'IN_WORD' => 55,
			'OR' => 56,
			'REAL' => 44,
			'SINGLEQUOTE_STRING' => 57
		},
		GOTOS => {
			'between_value' => 84,
			'number' => 41,
			'value' => 52,
			'keyword_as_value' => 51,
			'old_syntax_in_value' => 83
		}
	},
	{#State 67
		DEFAULT => -47
	},
	{#State 68
		DEFAULT => -27
	},
	{#State 69
		DEFAULT => -34
	},
	{#State 70
		DEFAULT => -36
	},
	{#State 71
		DEFAULT => -40
	},
	{#State 72
		ACTIONS => {
			'IDENTIFIER' => 1
		},
		GOTOS => {
			'group_by_list' => 85,
			'property' => 31
		}
	},
	{#State 73
		DEFAULT => -19
	},
	{#State 74
		ACTIONS => {
			'IDENTIFIER' => 1,
			'MINUS' => 32
		},
		GOTOS => {
			'order_by_list' => 86,
			'order_by_property' => 33,
			'property' => 34
		}
	},
	{#State 75
		DEFAULT => -21
	},
	{#State 76
		DEFAULT => -20
	},
	{#State 77
		DEFAULT => -66
	},
	{#State 78
		DEFAULT => -65
	},
	{#State 79
		ACTIONS => {
			'ASC_WORD' => 46,
			'INTEGER' => 45,
			'WORD' => 38,
			'DESC_WORD' => 48,
			'IDENTIFIER' => 47,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 50,
			'MINUS' => 40,
			'LIKE_WORD' => 53,
			'AND' => 54,
			'BETWEEN_WORD' => 43,
			'IN_WORD' => 55,
			'OR' => 56,
			'REAL' => 44,
			'SINGLEQUOTE_STRING' => 57
		},
		GOTOS => {
			'number' => 41,
			'value' => 87,
			'keyword_as_value' => 51
		}
	},
	{#State 80
		ACTIONS => {
			'ASC_WORD' => 46,
			'INTEGER' => 45,
			'WORD' => 38,
			'DESC_WORD' => 48,
			'IDENTIFIER' => 47,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 50,
			'MINUS' => 40,
			'LIKE_WORD' => 53,
			'AND' => 54,
			'BETWEEN_WORD' => 43,
			'IN_WORD' => 55,
			'OR' => 56,
			'REAL' => 44,
			'SINGLEQUOTE_STRING' => 57
		},
		GOTOS => {
			'number' => 41,
			'value' => 89,
			'keyword_as_value' => 51,
			'old_syntax_in_value' => 88
		}
	},
	{#State 81
		ACTIONS => {
			'RIGHT_BRACKET' => 90
		}
	},
	{#State 82
		ACTIONS => {
			'SET_SEPARATOR' => 91
		},
		DEFAULT => -45
	},
	{#State 83
		DEFAULT => -13
	},
	{#State 84
		DEFAULT => -16
	},
	{#State 85
		DEFAULT => -25
	},
	{#State 86
		DEFAULT => -23
	},
	{#State 87
		DEFAULT => -48
	},
	{#State 88
		DEFAULT => -41
	},
	{#State 89
		ACTIONS => {
			'IN_DIVIDER' => 80
		},
		DEFAULT => -42
	},
	{#State 90
		DEFAULT => -43
	},
	{#State 91
		ACTIONS => {
			'ASC_WORD' => 46,
			'INTEGER' => 45,
			'WORD' => 38,
			'DESC_WORD' => 48,
			'IDENTIFIER' => 47,
			'DOUBLEQUOTE_STRING' => 39,
			'NOT_WORD' => 50,
			'MINUS' => 40,
			'LIKE_WORD' => 53,
			'AND' => 54,
			'BETWEEN_WORD' => 43,
			'IN_WORD' => 55,
			'OR' => 56,
			'REAL' => 44,
			'SINGLEQUOTE_STRING' => 57
		},
		GOTOS => {
			'set_body' => 92,
			'number' => 41,
			'value' => 82,
			'keyword_as_value' => 51
		}
	},
	{#State 92
		DEFAULT => -44
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
		 'order_by_property', 1,
sub
#line 35 "BxParser.yp"
{ $_[1 ] }
	],
	[#Rule 19
		 'order_by_property', 2,
sub
#line 36 "BxParser.yp"
{ '-'.$_[2] }
	],
	[#Rule 20
		 'order_by_property', 2,
sub
#line 37 "BxParser.yp"
{ '-'.$_[1] }
	],
	[#Rule 21
		 'order_by_property', 2,
sub
#line 38 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 22
		 'order_by_list', 1,
sub
#line 41 "BxParser.yp"
{ [ $_[1]] }
	],
	[#Rule 23
		 'order_by_list', 3,
sub
#line 42 "BxParser.yp"
{ [$_[1], @{$_[3]}] }
	],
	[#Rule 24
		 'group_by_list', 1,
sub
#line 45 "BxParser.yp"
{ [ $_[1] ] }
	],
	[#Rule 25
		 'group_by_list', 3,
sub
#line 46 "BxParser.yp"
{ [$_[1], @{$_[3]}] }
	],
	[#Rule 26
		 'operator', 1,
sub
#line 49 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 27
		 'operator', 2,
sub
#line 50 "BxParser.yp"
{ "$_[1] $_[2]" }
	],
	[#Rule 28
		 'negation', 1,
sub
#line 53 "BxParser.yp"
{ 'not' }
	],
	[#Rule 29
		 'negation', 1,
sub
#line 54 "BxParser.yp"
{ 'not' }
	],
	[#Rule 30
		 'an_operator', 1,
sub
#line 57 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 31
		 'an_operator', 1,
sub
#line 58 "BxParser.yp"
{ '=' }
	],
	[#Rule 32
		 'an_operator', 1,
sub
#line 59 "BxParser.yp"
{ '=' }
	],
	[#Rule 33
		 'like_operator', 1,
sub
#line 62 "BxParser.yp"
{ 'like' }
	],
	[#Rule 34
		 'like_operator', 2,
sub
#line 63 "BxParser.yp"
{ "$_[1] like" }
	],
	[#Rule 35
		 'like_operator', 1,
sub
#line 64 "BxParser.yp"
{ 'like' }
	],
	[#Rule 36
		 'like_operator', 2,
sub
#line 65 "BxParser.yp"
{ "$_[1] like" }
	],
	[#Rule 37
		 'like_value', 1,
sub
#line 68 "BxParser.yp"
{ '%' . $_[1] . '%' }
	],
	[#Rule 38
		 'like_value', 1,
sub
#line 69 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 39
		 'in_operator', 1,
sub
#line 72 "BxParser.yp"
{ 'in' }
	],
	[#Rule 40
		 'in_operator', 2,
sub
#line 73 "BxParser.yp"
{ "$_[1] in" }
	],
	[#Rule 41
		 'old_syntax_in_value', 3,
sub
#line 76 "BxParser.yp"
{ [ $_[1], @{$_[3]} ] }
	],
	[#Rule 42
		 'old_syntax_in_value', 3,
sub
#line 77 "BxParser.yp"
{ [ $_[1], $_[3] ] }
	],
	[#Rule 43
		 'set', 3,
sub
#line 80 "BxParser.yp"
{ $_[2] }
	],
	[#Rule 44
		 'set_body', 3,
sub
#line 83 "BxParser.yp"
{ [ $_[1], @{$_[3]} ] }
	],
	[#Rule 45
		 'set_body', 1,
sub
#line 84 "BxParser.yp"
{ [ $_[1] ] }
	],
	[#Rule 46
		 'between_operator', 1,
sub
#line 87 "BxParser.yp"
{ 'between' }
	],
	[#Rule 47
		 'between_operator', 2,
sub
#line 88 "BxParser.yp"
{ "$_[1] between" }
	],
	[#Rule 48
		 'between_value', 3,
sub
#line 91 "BxParser.yp"
{ [ $_[1], $_[3] ] }
	],
	[#Rule 49
		 'keyword_as_value', 1,
sub
#line 94 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 50
		 'keyword_as_value', 1,
sub
#line 95 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 51
		 'keyword_as_value', 1,
sub
#line 96 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 52
		 'keyword_as_value', 1,
sub
#line 97 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 53
		 'keyword_as_value', 1,
sub
#line 98 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 54
		 'keyword_as_value', 1,
sub
#line 99 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 55
		 'keyword_as_value', 1,
sub
#line 100 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 56
		 'keyword_as_value', 1,
sub
#line 101 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 57
		 'value', 1,
sub
#line 104 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 58
		 'value', 1,
sub
#line 105 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 59
		 'value', 1,
sub
#line 106 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 60
		 'value', 1,
sub
#line 107 "BxParser.yp"
{ ($_[1] =~ m/^"(.*?)"$/)[0]; }
	],
	[#Rule 61
		 'value', 1,
sub
#line 108 "BxParser.yp"
{ ($_[1] =~ m/^'(.*?)'$/)[0]; }
	],
	[#Rule 62
		 'value', 1,
sub
#line 109 "BxParser.yp"
{ $_[1] }
	],
	[#Rule 63
		 'number', 1,
sub
#line 112 "BxParser.yp"
{ $_[1] + 0 }
	],
	[#Rule 64
		 'number', 1,
sub
#line 113 "BxParser.yp"
{ $_[1] + 0 }
	],
	[#Rule 65
		 'number', 2,
sub
#line 114 "BxParser.yp"
{ 0 - $_[2] }
	],
	[#Rule 66
		 'number', 2,
sub
#line 115 "BxParser.yp"
{ 0 - $_[2] }
	]
],
                                  @_);
    bless($self,$class);
}

#line 118 "BxParser.yp"


use strict;
use warnings;

sub _error {
    my @expect = $_[0]->YYExpect;
    my $tok = $_[0]->YYData->{INPUT};
    my $match = $_[0]->YYData->{MATCH};
    my $string = $_[0]->YYData->{STRING};
    my $err = qq(Can't parse expression "$string"\n  Syntax error near token $tok '$match');
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
        DESC_WORD => qr{desc},
        ASC_WORD => qr{asc},
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

    my $parser_state = 'DEFAULT';

    my $get_next_token = sub {
        if (length($string) == 0) {
            print "String is empty, we're done!\n" if $debug;
            return (undef, '');  
       }

        my $longest = 0;
        my $longest_token = '';
        my $longest_match = '';

        for my $token_list ( $parser_state, 'DEFAULT' ) {
            print "\nTrying tokens for state $token_list...\n" if $debug;
            my $tokens = $token_states{$token_list};
            for(my $i = 0; $i < @$tokens; $i += 2) {
                my($tok, $re) = @$tokens[$i, $i+1];
                print "Trying token $tok... " if $debug;

                my($regex,$next_parser_state);
                if (ref($re) eq 'ARRAY') {
                    ($regex,$next_parser_state) = @$re;
                } else {
                    $regex = $re;
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
                            $parser_state = 'DEFAULT';
                        } elsif ($next_parser_state) {
                            $parser_state = $next_parser_state;
                        }
                    }
                }
                print "\n" if $debug;
            }

            $string = substr($string, $longest);
            print "Consuming up to char pos $longest chars, string is now >>$string<<\n" if $debug;
            $parser->YYData->{REMAINING} = $string;
            if ($longest) {
                print "Returning token $longest_token, match $longest_match\n  next state is named $parser_state\n" if $debug;
                $parser->YYData->{INPUT} = $longest_token;
                $parser->YYData->{MATCH} = $longest_match;
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
