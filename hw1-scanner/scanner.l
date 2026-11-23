%{
/*
 * NTHU CS340400 Compiler Design - HW1 Lexical Analyzer
 *
 * Output format (spec p.46):
 *   for each token        #<type>:<content>
 *   at the end of a line  <line_number>:<line_content>
 * Comments and pragmas print no token; they only appear in the line_content.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LINE_BUF_SIZE 4096

static int  line_no = 1;
static char line_buf[LINE_BUF_SIZE];
static int  line_len = 0;

static int source_on = 1;   /* #pragma source on|off */
static int token_on  = 1;   /* #pragma token  on|off */

/* Append the matched text to the current line buffer (except newlines) */
static void append_line(const char *text, int len) {
    if (line_len + len >= LINE_BUF_SIZE) len = LINE_BUF_SIZE - 1 - line_len;
    memcpy(line_buf + line_len, text, len);
    line_len += len;
    line_buf[line_len] = '\0';
}

/* End of line: print line number and content if source is on, then reset the buffer */
static void end_line(void) {
    if (source_on) printf("%d:%s\n", line_no, line_buf);
    line_no++;
    line_len = 0;
    line_buf[0] = '\0';
}

static void emit(const char *type) {
    if (token_on) printf("#%s:%s\n", type, yytext);
}

static void lex_error(void) {
    fprintf(stderr, "Error at line %d: %s\n", line_no, yytext);
    exit(1);
}

/* Before every rule, record yytext in the line buffer; newlines are handled by end_line() */
#define YY_USER_ACTION  if (yytext[0] != '\n') append_line(yytext, yyleng);
%}

%option noyywrap nounput noinput

%x COMMENT

DIGIT       [0-9]
SIGN        [+-]?
IDENTIFIER  [_a-zA-Z][_a-zA-Z0-9]*

/* Escape sequences: https://en.wikipedia.org/wiki/Escape_sequences_in_C */
ESCAPE      \\([abefnrtv\\'"?]|[0-7]{1,3}|x[0-9a-fA-F]+|u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8})
STRING      \"({ESCAPE}|\\.|[^"\\\n])*\"
CHARACTER   \'({ESCAPE}|\\.|[^'\\\n])\'

INTEGER     {SIGN}{DIGIT}+
FLOAT       {SIGN}({DIGIT}+\.{DIGIT}*|\.{DIGIT}+)

/* A pragma takes a whole line; words may be separated by spaces or tabs, but not '#' and "pragma" */
PRAGMA      ^[ \t]*"#pragma"[ \t]+
PRAGMA_END  [ \t]*

%%

 /* ---------- comments ---------- */
"//"[^\n]*                  { /* line comment: only recorded in the line buffer */ }
"/*"                        { BEGIN(COMMENT); }
<COMMENT>[^*\n]+            { }
<COMMENT>"*"+[^*/\n]*       { }
<COMMENT>"*"+"/"            { BEGIN(INITIAL); }
<COMMENT>\n                 { end_line(); }

 /* ---------- Pragma ---------- */
{PRAGMA}source[ \t]+on{PRAGMA_END}    { source_on = 1; }
{PRAGMA}source[ \t]+off{PRAGMA_END}   { source_on = 0; }
{PRAGMA}token[ \t]+on{PRAGMA_END}     { token_on = 1; }
{PRAGMA}token[ \t]+off{PRAGMA_END}    { token_on = 0; }

 /* ---------- Keywords ---------- */
"for"|"do"|"while"|"break"|"continue"|"if"|"else"|"return"|"struct"|"switch"|"case"|"default" { emit("key"); }
"void"|"int"|"double"|"float"|"char"                                                          { emit("key"); }
"const"|"signed"|"unsigned"|"short"|"long"                                                    { emit("key"); }

 /* ---------- Macros ---------- */
"NULL"|"__COUNTER__"|"__LINE__"|"INT_MAX"|"INT_MIN"|"CHAR_MAX"|"CHAR_MIN"|"MAX"|"MIN"         { emit("macro"); }

{IDENTIFIER}                { emit("id"); }

 /* ---------- Literals ---------- */
{INTEGER}                   { emit("integer"); }
{FLOAT}                     { emit("float"); }
{CHARACTER}                 { emit("char"); }
{STRING}                    { emit("string"); }

 /* ---------- Operators ---------- */
"++"|"--"|"<="|">="|"=="|"!="|"&&"|"||"   { emit("op"); }
[-+*/%<>=!&|]                             { emit("op"); }

 /* ---------- Punctuation ---------- */
[:;,.\[\](){}]              { emit("punc"); }

 /* ---------- Whitespace / newline ---------- */
[ \t\r]+                    { }
\n                          { end_line(); }

<INITIAL,COMMENT><<EOF>>    {
                                /* also print the last line when it has no trailing newline */
                                if (line_len > 0) end_line();
                                return 0;
                            }

.                           { lex_error(); }

%%

int main(void) {
    yylex();
    return 0;
}
