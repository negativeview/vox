/**
Copyright: Copyright (c) 2017-2019 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
/// Lexer
module fe.lexer;

import std.format : formattedWrite;
import std.string : format;
import std.range : repeat;
import std.stdio;

import all;

//                 #######    ###    #    #   #######  #     #
//                    #      #   #   #   #    #        ##    #
//                    #     #     #  #  #     #        # #   #
//                    #     #     #  ###      #####    #  #  #
//                    #     #     #  #  #     #        #   # #
//                    #      #   #   #   #    #        #    ##
//                    #       ###    #    #   #######  #     #
// -----------------------------------------------------------------------------
alias TT = TokenType;
enum TokenType : ubyte {
	@("#soi")  SOI,
	@("#eoi")  EOI,
	@(null)   INVALID,

	@("&")    AND,
	@("&&")   AND_AND,
	@("&=")   AND_EQUAL,
	@("@")    AT,
	@("\\")   BACKSLASH,
	@(":")    COLON,
	@(",")    COMMA,
	@("$")    DOLLAR,
	@(".")    DOT,
	@("..")   DOT_DOT,
	@("...")  DOT_DOT_DOT,
	@("=")    EQUAL,
	@("==")   EQUAL_EQUAL,
	@(">")    MORE,
	@(">=")   MORE_EQUAL,
	@(">>")   MORE_MORE,
	@(">>=")  MORE_MORE_EQUAL,
	@(">>>")  MORE_MORE_MORE,
	@(">>>=") MORE_MORE_MORE_EQUAL,
	@("#")    HASH,
	@("<")    LESS,
	@("<=")   LESS_EQUAL,
	@("<<")   LESS_LESS,
	@("<<=")  LESS_LESS_EQUAL,
	@("-")    MINUS,
	@("-=")   MINUS_EQUAL,
	@("--")   MINUS_MINUS,
	@("!")    NOT,
	@("!=")   NOT_EQUAL,
	@("|")    OR,
	@("|=")   OR_EQUAL,
	@("||")   OR_OR,
	@("%")    PERCENT,
	@("%=")   PERCENT_EQUAL,
	@("+")    PLUS,
	@("+=")   PLUS_EQUAL,
	@("++")   PLUS_PLUS,
	@("?")    QUESTION,
	@(";")    SEMICOLON,
	@("/")    SLASH,
	@("/=")   SLASH_EQUAL,
	@("*")    STAR,
	@("*=")   STAR_EQUAL,
	@("~")    TILDE,
	@("~=")   TILDE_EQUAL,
	@("^")    XOR,
	@("^=")   XOR_EQUAL,

	@("(")    LPAREN,
	@(")")    RPAREN,
	@("[")    LBRACKET,
	@("]")    RBRACKET,
	@("{")    LCURLY,
	@("}")    RCURLY,


	@("break")    BREAK_SYM,
	@("continue") CONTINUE_SYM,
	@("do")       DO_SYM,
	@("else")     ELSE_SYM,
	@("if")       IF_SYM,
	@("return")   RETURN_SYM,
	@("struct")   STRUCT_SYM,
	@("while")    WHILE_SYM,
	@("cast")     CAST,                 // cast(T)
	@("enum")     ENUM,

	@("#id")      IDENTIFIER,           // [a-zA-Z_] [a-zA-Z_0-9]*

	// ----------------------------------------
	// list of basic types. The order is the same as in `enum BasicType`

	@("void") TYPE_VOID,                // void
	@("bool") TYPE_BOOL,                // bool
	@("i8")   TYPE_I8,                  // i8
	@("i16")  TYPE_I16,                 // i16
	@("i32")  TYPE_I32,                 // i32
	@("i64")  TYPE_I64,                 // i64

	@("u8")   TYPE_U8,                  // u8
	@("u16")  TYPE_U16,                 // u16
	@("u32")  TYPE_U32,                 // u32
	@("u64")  TYPE_U64,                 // u64

	@("f32")  TYPE_F32,                 // f32
	@("f64")  TYPE_F64,                 // f64
	// ----------------------------------------

	@("isize") TYPE_ISIZE,              // isize
	@("usize") TYPE_USIZE,              // usize

	@("#num_dec_lit") INT_DEC_LITERAL,
	@("#num_hex_lit") INT_HEX_LITERAL,
	@("#num_bin_lit") INT_BIN_LITERAL,
	@("#str_lit") STRING_LITERAL,
	//@(null) DECIMAL_LITERAL,          // 0|[1-9][0-9_]*
	//@(null) BINARY_LITERAL,           // ("0b"|"0B")[01_]+
	//@(null) HEX_LITERAL,              // ("0x"|"0X")[0-9A-Fa-f_]+

	@("#comm") COMMENT,                 // // /*
}

immutable string[] tokStrings = gatherInfos();

private string[] gatherInfos()
{
	string[] res = new string[__traits(allMembers, TokenType).length];
	foreach (i, m; __traits(allMembers, TokenType))
	{
		res[i] = __traits(getAttributes, mixin("TokenType."~m))[0];
	}
	return res;
}

enum TokenType TYPE_TOKEN_FIRST = TokenType.TYPE_VOID;
enum TokenType TYPE_TOKEN_LAST = TokenType.TYPE_F64;


struct Token {
	TokenType type;
	TokenIndex index;
}

struct TokenIndex
{
	uint index;
	alias index this;
}

struct SourceFileInfo
{
	string name;
	/// Is set when in JIT mode
	string content;
	/// Start of file source code in CompilationContext.sourceBuffer
	uint start;
	/// Length of source code
	uint length;
}

struct SourceLocation {
	uint start;
	uint end;
	uint line;
	uint col;
	const(char)[] getTokenString(const(char)[] input) pure const { return input[start..end]; }
	void toString(scope void delegate(const(char)[]) sink) const {
		sink.formattedWrite("line %s col %s start %s end %s", line+1, col+1, start, end);
	}
}

/// Start of input
enum char SOI_CHAR = '\2';
/// End of input
enum char EOI_CHAR = '\3';

immutable string[] keyword_strings = ["bool","break","continue","do","else","f32","f64",
	"i16","i32","i64","i8","if","isize","return","struct","u16","u32","u64",
	"u8","usize","void","while","cast","enum"];
enum NUM_KEYWORDS = keyword_strings.length;
immutable TokenType[NUM_KEYWORDS] keyword_tokens = [TT.TYPE_BOOL,TT.BREAK_SYM,TT.CONTINUE_SYM,TT.DO_SYM,
	TT.ELSE_SYM,TT.TYPE_F32,TT.TYPE_F64,TT.TYPE_I16,TT.TYPE_I32,TT.TYPE_I64,
	TT.TYPE_I8,TT.IF_SYM,TT.TYPE_ISIZE,TT.RETURN_SYM,TT.STRUCT_SYM,
	TT.TYPE_U16,TT.TYPE_U32,TT.TYPE_U64,TT.TYPE_U8,TT.TYPE_USIZE,
	TT.TYPE_VOID,TT.WHILE_SYM,TT.CAST,TT.ENUM];

//                          #        #######  #     #
//                          #        #         #   #
//                          #        #          # #
//                          #        #####       #
//                          #        #          # #
//                          #        #         #   #
//                          ######   #######  #     #
// -----------------------------------------------------------------------------

void pass_lexer(ref CompilationContext ctx)
{
	Lexer lexer = Lexer(&ctx, ctx.sourceBuffer, ctx.tokenBuffer, ctx.tokenLocationBuffer);
	// TODO: when compiling multiple modules, continue buffers instead of overwriting them

	lexer.lex();

	if (ctx.printLexemes) {
		writeln("// Lexemes");
		Token tok;
		do
		{
			tok.type = ctx.tokenBuffer[tok.index];
			auto loc = ctx.tokenLocationBuffer[tok.index];
			writefln("%s %s, `%s`", tok, loc, loc.getTokenString(ctx.sourceBuffer));
			++tok.index;
		}
		while(tok.type != TokenType.EOI);
	}
}

struct Lexer
{
	CompilationContext* context;
	const(char)[] inputChars;
	TokenType[] outputTokens;
	SourceLocation[] outputTokenLocations;

	TokenIndex tokenIndex;

	private dchar c; // current symbol

	private uint position; // offset of 'c' in input
	private uint line; // line of 'c'
	private uint column; // column of 'c'

	private uint startPos; // offset of first token byte in input
	private uint startLine; // line of first token byte
	private uint startCol; // column of first token byte

	void lex()
	{
		while (true)
		{
			TokenType tokType = nextToken();

			outputTokens[tokenIndex] = tokType;
			set_loc();
			++tokenIndex;

			if (tokType == TokenType.EOI) return;
		}
	}

	private void nextChar()
	{
		++position;
		++column;
		c = inputChars[position];
	}

	private void set_loc()
	{
		outputTokenLocations[tokenIndex] = SourceLocation(startPos, position, startLine, startCol);
	}

	int opApply(scope int delegate(TokenType) dg)
	{
		TokenType tok;
		while ((tok = nextToken()) != TokenType.EOI)
			if (int res = dg(tok))
				return res;
		return 0;
	}

	TokenType nextToken()
	{
		c = inputChars[position];

		while (true)
		{
			startPos = position;
			startLine = line;
			startCol = column;

			switch(c)
			{
				case SOI_CHAR:         nextChar; return TT.SOI;
				case EOI_CHAR:         return TT.EOI;
				case '\t': nextChar;   continue;
				case '\n': lex_EOLN(); continue;
				case '\r': lex_EOLR(); continue;
				case ' ' : nextChar;   continue;
				case '!' : nextChar; return lex_multi_equal2(TT.NOT, TT.NOT_EQUAL);
				//case '#' : nextChar; return TT.HASH;
				case '$' : nextChar; return TT.DOLLAR;
				case '%' : nextChar; return lex_multi_equal2(TT.PERCENT, TT.PERCENT_EQUAL);
				case '&' : nextChar; return lex_multi_equal2_3('&', TT.AND, TT.AND_EQUAL, TT.AND_AND);
				case '(' : nextChar; return TT.LPAREN;
				case ')' : nextChar; return TT.RPAREN;
				case '*' : nextChar; return lex_multi_equal2(TT.STAR, TT.STAR_EQUAL);
				case '+' : nextChar; return lex_multi_equal2_3('+', TT.PLUS, TT.PLUS_EQUAL, TT.PLUS_PLUS);
				case ',' : nextChar; return TT.COMMA;
				case '-' : nextChar; return lex_multi_equal2_3('-', TT.MINUS, TT.MINUS_EQUAL, TT.MINUS_MINUS);
				case '.' : nextChar;
					if (c == '.') { nextChar;
						if (c == '.') { nextChar;
							return TT.DOT_DOT_DOT;
						}
						return TT.DOT_DOT;
					}
					return TT.DOT;
				case '\"': nextChar; return lex_QUOTE_QUOTE();
				case '/' :           return lex_SLASH();
				case '0' :           return lex_ZERO();
				case '1' : ..case '9': return lex_DIGIT();
				case ':' : nextChar; return TT.COLON;
				case ';' : nextChar; return TT.SEMICOLON;
				case '<' : nextChar;
					if (c == '<') { nextChar;
						if (c == '=') { nextChar;
							return TT.LESS_LESS_EQUAL;
						}
						return TT.LESS_LESS;
					}
					if (c == '=') { nextChar;
						return TT.LESS_EQUAL;
					}
					return TT.LESS;
				case '=' : nextChar; return lex_multi_equal2(TT.EQUAL, TT.EQUAL_EQUAL);
				case '#' : nextChar; return TT.HASH;
				case '?' : nextChar; return TT.QUESTION;
				case '>' : nextChar;
					if (c == '=') { nextChar;
						return TT.MORE_EQUAL;
					}
					if (c == '>') { nextChar;
						if (c == '>') { nextChar;
							if (c == '=') { nextChar;
								return TT.MORE_MORE_MORE_EQUAL;
							}
							return TT.MORE_MORE_MORE;
						}
						if (c == '=') { nextChar;
							return TT.MORE_MORE_EQUAL;
						}
						return TT.MORE_MORE;
					}
					return TT.MORE;
				//case '?' : nextChar; return TT.QUESTION;
				case '@' : nextChar; return TT.AT;
				case 'A' : ..case 'Z': return lex_LETTER();
				case '[' : nextChar; return TT.LBRACKET;
				case '\\': nextChar; return TT.BACKSLASH;
				case ']' : nextChar; return TT.RBRACKET;
				case '^' : nextChar; return lex_multi_equal2(TT.XOR, TT.XOR_EQUAL);
				case '_' : nextChar; return lex_LETTER();
				case 'a' : ..case 'z': return lex_LETTER();
				case '{' : nextChar; return TT.LCURLY;
				case '|' : nextChar; return lex_multi_equal2_3('|', TT.OR, TT.OR_EQUAL, TT.OR_OR);
				case '}' : nextChar; return TT.RCURLY;
				case '~' : nextChar; return lex_multi_equal2(TT.TILDE, TT.TILDE_EQUAL);
				default  : nextChar; return TT.INVALID;
			}
		}
	}

	private void lex_EOLR() // \r[\n]
	{
		nextChar;
		if (c == '\n') nextChar;
		++line;
		column = 0;
	}

	private void lex_EOLN() // \n
	{
		nextChar;
		++line;
		column = 0;
	}

	// Lex X= tokens
	private TokenType lex_multi_equal2(TokenType single_tok, TokenType eq_tok)
	{
		if (c == '=') {
			nextChar;
			return eq_tok;
		}
		return single_tok;
	}

	private TokenType lex_multi_equal2_3(dchar chr, TokenType single_tok, TokenType eq_tok, TokenType double_tok)
	{
		if (c == chr) { nextChar;
			return double_tok;
		}
		if (c == '=') { nextChar;
			return eq_tok;
		}
		return single_tok;
	}

	private TokenType lex_SLASH() // /
	{
		nextChar;
		if (c == '/')
		{
			consumeLine();
			return TT.COMMENT;
		}
		if (c == '*')
		{
			while (true)
			{
				switch(c)
				{
					case EOI_CHAR:
						set_loc();
						context.unrecoverable_error(tokenIndex, "Unterminated comment");
						return TT.INVALID;

					case '\n': lex_EOLN(); continue;
					case '\r': lex_EOLR(); continue;
					case '*':
						nextChar;
						if (c == '/') {
							nextChar;
							return TT.COMMENT;
						}
						break;
					default: break;
				}
				nextChar;
			}
			return TT.COMMENT;
		}
		if (c == '=') { nextChar;
			return TT.SLASH_EQUAL;
		}
		return TT.SLASH;
	}

	private TokenType lex_QUOTE_QUOTE() // "
	{
		while (true)
		{
			switch(c)
			{
				case EOI_CHAR:
					set_loc();
					context.unrecoverable_error(tokenIndex, "Unterminated string literal");
					return TT.INVALID;
				case '\n': lex_EOLN(); continue;
				case '\r': lex_EOLR(); continue;
				case '\"':
					nextChar; // skip "
					return TT.STRING_LITERAL;
				default: break;
			}
			nextChar;
		}
	}

	private TokenType lex_ZERO() // 0
	{
		nextChar;

		if (c == 'x' || c == 'X')
		{
			nextChar;
			consumeHexadecimal();
			return TT.INT_HEX_LITERAL;
		}
		else if (c == 'b' || c == 'B')
		{
			nextChar;
			consumeBinary();
			return TT.INT_BIN_LITERAL;
		}
		else
		{
			consumeDecimal();
			return TT.INT_DEC_LITERAL;
		}
	}

	private TokenType lex_DIGIT() // 1-9
	{
		nextChar;
		consumeDecimal();
		return TT.INT_DEC_LITERAL;
	}

	private TokenType lex_LETTER() // a-zA-Z_
	{
		switch (c)
		{
			case 'b':
				nextChar;
				if (c == 'o' && match("ool")) return TT.TYPE_BOOL;
				else if (c == 'r' && match("reak")) return TT.BREAK_SYM;
				break;
			case 'c':
				nextChar;
				if (c == 'o' && match("ontinue")) return TT.CONTINUE_SYM;
				else if (c == 'a' && match("ast")) return TT.CAST;
				break;
			case 'd': if (match("do")) return TT.DO_SYM; break;
			case 'e':
				nextChar;
				if (c == 'l' && match("lse")) return TT.ELSE_SYM;
				else if (c == 'n' && match("num")) return TT.ENUM;
				break;
			case 'f':
				nextChar;
				if (c == '3' && match("32")) return TT.TYPE_F32;
				if (c == '6' && match("64")) return TT.TYPE_F64;
				break;
			case 'i':
				nextChar;
				switch(c) {
					case '1': if (match("16")) return TT.TYPE_I16; break;
					case '3': if (match("32")) return TT.TYPE_I32; break;
					case '6': if (match("64")) return TT.TYPE_I64; break;
					case '8': if (match("8"))  return TT.TYPE_I8;  break;
					case 's': if (match("size")) return TT.TYPE_ISIZE; break;
					case 'f': if (match("f")) return TT.IF_SYM; break;
					default: break;
				}
				break;
			case 'r': if (match("return")) return TT.RETURN_SYM; break;
			case 's': if (match("struct")) return TT.STRUCT_SYM; break;
			case 'u':
				nextChar;
				switch(c) {
					case '1': if (match("16")) return TT.TYPE_U16; break;
					case '3': if (match("32")) return TT.TYPE_U32; break;
					case '6': if (match("64")) return TT.TYPE_U64; break;
					case '8': if (match("8"))  return TT.TYPE_U8;  break;
					case 's': if (match("size")) return TT.TYPE_USIZE; break;
					default: break;
				}
				break;
			case 'v': if (match("void")) return TT.TYPE_VOID; break;
			case 'w': if (match("while")) return TT.WHILE_SYM; break;
			default: break;
		}

		consumeId();
		return TT.IDENTIFIER;
	}

	private bool match(string identifier)
	{
		uint index = 0;
		while (identifier[index] == c)
		{
			nextChar;
			++index;
			if (index == identifier.length)
			{
				// check that no valid symbol follow this id. ifff for if id.
				if (isIdSecond(c)) return false;
				return true;
			}
		}
		return false;
	}

	private void consumeId()
	{
		while (isIdSecond(c)) nextChar;
	}

	private void consumeDecimal()
	{
		while (true)
		{
			if ('0' <= c && c <= '9') {
			} else if (c != '_') return;
			nextChar;
		}
	}

	private void consumeHexadecimal()
	{
		while (true)
		{
			if ('0' <= c && c <= '9') {
			} else if ('a' <= c && c <= 'f') {
			} else if ('A' <= c && c <= 'F') {
			} else if (c != '_') return;
			nextChar;
		}
	}

	private void consumeBinary()
	{
		while (true)
		{
			if (c == '0' || c == '1') {
			} else if (c != '_') return;
			nextChar;
		}
	}

	private void consumeLine()
	{
		while (true)
		{
			switch(c)
			{
				case EOI_CHAR: return;
				case '\n': lex_EOLN(); return;
				case '\r': lex_EOLR(); return;
				default: break;
			}
			nextChar;
		}
	}
}

private bool isIdSecond(dchar chr) pure nothrow {
	return
		'0' <= chr && chr <= '9' ||
		'a' <= chr && chr <= 'z' ||
		'A' <= chr && chr <= 'Z' ||
		chr == '_';
}


unittest
{
	CompilationContext ctx;
	TokenType[4] tokenBuffer;
	SourceLocation[4] locs;

	Lexer makeLexer(string input) {
		return Lexer(&ctx, input~EOI_CHAR, tokenBuffer, locs);
	}

	foreach(i, string keyword; keyword_strings)
	{
		Lexer lexer = makeLexer(keyword);
		TokenType token = lexer.nextToken;
		assert(token == keyword_tokens[i],
			format("For %s expected %s got %s", keyword, keyword_tokens[i], token));
	}

	foreach(i, string keyword; keyword_strings)
	{
		Lexer lexer = makeLexer(keyword~"A");
		TokenType token = lexer.nextToken;
		assert(token == TT.IDENTIFIER);
	}

	{
		string[] ops = ["&","&&","&=","@","\\",":",",","$",".","..","...",
			"=","==",">",">=",">>",">>=",">>>",">>>=","#","<","<=","<<","<<=","-",
			"-=","--","!","!=","|","|=","||","%","%=","+","+=","++","?",";","/",
			"/=","*","*=","~","~=","^","^=","(",")","[","]","{","}",];
		TokenType[] tokens_ops = [TT.AND,TT.AND_AND,TT.AND_EQUAL,TT.AT,TT.BACKSLASH,
			TT.COLON,TT.COMMA,TT.DOLLAR,TT.DOT,TT.DOT_DOT,TT.DOT_DOT_DOT,TT.EQUAL,
			TT.EQUAL_EQUAL,TT.MORE,TT.MORE_EQUAL,TT.MORE_MORE,
			TT.MORE_MORE_EQUAL,TT.MORE_MORE_MORE,
			TT.MORE_MORE_MORE_EQUAL,TT.HASH,
			TT.LESS,TT.LESS_EQUAL,TT.LESS_LESS,TT.LESS_LESS_EQUAL,TT.MINUS,
			TT.MINUS_EQUAL,TT.MINUS_MINUS,TT.NOT,TT.NOT_EQUAL,TT.OR,TT.OR_EQUAL,
			TT.OR_OR,TT.PERCENT,TT.PERCENT_EQUAL,TT.PLUS,TT.PLUS_EQUAL,TT.PLUS_PLUS,
			TT.QUESTION,TT.SEMICOLON,TT.SLASH,TT.SLASH_EQUAL,TT.STAR,TT.STAR_EQUAL,
			TT.TILDE,TT.TILDE_EQUAL,TT.XOR,TT.XOR_EQUAL,TT.LPAREN,TT.RPAREN,
			TT.LBRACKET,TT.RBRACKET, TT.LCURLY,TT.RCURLY,];
		foreach(i, string op; ops)
		{
			Lexer lexer = makeLexer(op);
			TokenType token = lexer.nextToken;
			assert(token == tokens_ops[i],
				format("For %s expected %s got %s", op, tokens_ops[i], token));
		}
	}

	void testNumeric(string input, TokenType tokType)
	{
		Lexer lexer = makeLexer(input);
		assert(lexer.nextToken == tokType);
	}

	assert(makeLexer("_10").nextToken == TT.IDENTIFIER);
	testNumeric("10", TT.INT_DEC_LITERAL);
	testNumeric("1_0", TT.INT_DEC_LITERAL);
	testNumeric("10_", TT.INT_DEC_LITERAL);
	testNumeric("0xFF", TT.INT_HEX_LITERAL);
	testNumeric("0XABCDEF0123456789", TT.INT_HEX_LITERAL);
	testNumeric("0x1_0", TT.INT_HEX_LITERAL);
	testNumeric("0b10", TT.INT_BIN_LITERAL);
	testNumeric("0B10", TT.INT_BIN_LITERAL);
	testNumeric("0b1_0", TT.INT_BIN_LITERAL);

	{
		string source = "/*\n*/test";
		Lexer lexer = makeLexer(source);
		lexer.lex;
		assert(tokenBuffer[0] == TT.COMMENT);
		assert(locs[0].getTokenString(source) == "/*\n*/", format("%s", locs[0]));
		assert(tokenBuffer[1] == TT.IDENTIFIER);
		assert(locs[1].getTokenString(source) == "test");
	}
	{
		string source = "//test\nhello";
		Lexer lexer = makeLexer(source);
		lexer.lex;
		assert(tokenBuffer[0] == TT.COMMENT);
		assert(locs[0].getTokenString(source) == "//test\n");
		assert(tokenBuffer[1] == TT.IDENTIFIER);
		assert(locs[1].getTokenString(source) == "hello");
	}
	{
		string source = `"literal"`;
		Lexer lexer = makeLexer(source);
		lexer.lex;
		assert(tokenBuffer[0] == TT.STRING_LITERAL);
		assert(locs[0].getTokenString(source) == `"literal"`, format("%s", tokenBuffer[0]));
	}
}