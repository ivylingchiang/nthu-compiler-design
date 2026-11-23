%{
/*
 * NTHU CS340400 Compiler Design - HW2 Scanner
 *
 * Adapted from the HW1 scanner: output and main() removed; tokens are returned to the parser.
 * Every token's semantic value is a string (yylval.s); numbers are normalized here:
 *   integer -> atoi, printed with "%d"; float -> atof, printed with "%f"; NULL -> "0"
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "y.tab.h"

int lineno = 1;

static int tok(int t) {
    yylval.s = strdup(yytext);
    return t;
}
%}

%option noyywrap nounput noinput

%x COMMENT

DIGIT       [0-9]
IDENTIFIER  [_a-zA-Z][_a-zA-Z0-9]*
ESCAPE      \\([abefnrtv\\'"?]|[0-7]{1,3}|x[0-9a-fA-F]+|u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8})
STRING      \"({ESCAPE}|\\.|[^"\\\n])*\"
CHARACTER   \'({ESCAPE}|\\.|[^'\\\n])\'

%%

 /* ---------- comments, pragmas, whitespace ---------- */
"//"[^\n]*                  { }
"/*"                        { BEGIN(COMMENT); }
<COMMENT>[^*\n]+            { }
<COMMENT>"*"+[^*/\n]*       { }
<COMMENT>"*"+"/"            { BEGIN(INITIAL); }
<COMMENT>\n                 { lineno++; }
^[ \t]*"#pragma"[^\n]*      { }
[ \t\r]+                    { }
\n                          { lineno++; }

 /* ---------- types ---------- */
"const"                     { return tok(CONST); }
"signed"                    { return tok(SIGNED); }
"unsigned"                  { return tok(UNSIGNED); }
"short"                     { return tok(SHORT); }
"long"                      { return tok(LONG); }
"int"                       { return tok(INT); }
"char"                      { return tok(CHAR); }
"float"                     { return tok(FLOAT); }
"double"                    { return tok(DOUBLE); }
"void"                      { return tok(VOID); }

 /* ---------- keywords ---------- */
"if"                        { return IF; }
"else"                      { return ELSE; }
"switch"                    { return SWITCH; }
"case"                      { return CASE; }
"default"                   { return DEFAULT; }
"while"                     { return WHILE; }
"do"                        { return DO; }
"for"                       { return FOR; }
"return"                    { return RETURN; }
"break"                     { return BREAK; }
"continue"                  { return CONTINUE; }

 /* ---------- literals ---------- */
"NULL"                      { yylval.s = strdup("0"); return INT_LIT; }
{IDENTIFIER}                { return tok(ID); }
{DIGIT}+                    {
                                char buf[32];
                                snprintf(buf, sizeof buf, "%d", atoi(yytext));
                                yylval.s = strdup(buf);
                                return INT_LIT;
                            }
{DIGIT}+"."{DIGIT}*|"."{DIGIT}+ {
                                char buf[512];
                                snprintf(buf, sizeof buf, "%f", atof(yytext));
                                yylval.s = strdup(buf);
                                return FLOAT_LIT;
                            }
{CHARACTER}                 { return tok(CHAR_LIT); }
{STRING}                    { return tok(STRING_LIT); }

 /* ---------- multi-character operators ---------- */
"++"                        { return INC; }
"--"                        { return DEC; }
"<="                        { return LE; }
">="                        { return GE; }
"=="                        { return EQ; }
"!="                        { return NE; }
"&&"                        { return AND; }
"||"                        { return OR; }
"<<"                        { return SHL; }
">>"                        { return SHR; }

 /* ---------- single-character operators and punctuation: return the character itself ---------- */
[-+*/%<>=!~&|^:;,.\[\](){}] { return yytext[0]; }

.                           {
                                fprintf(stderr, "Error at line %d: unexpected character '%s'\n", lineno, yytext);
                                exit(1);
                            }

%%
