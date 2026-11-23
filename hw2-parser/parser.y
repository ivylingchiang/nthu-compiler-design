%{
/*
 * NTHU CS340400 Compiler Design - HW2 Parser
 *
 * Reads a C subset and prints its syntax tree as XML (spec p.44):
 *   <scalar_decl> <array_decl> <func_decl> <func_def> <expr> <stmt>
 * All whitespace inside tags is removed (except in char/string literals); the output has no newlines.
 *
 * The semantic value of every nonterminal is its finished output string, joined with J(...).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

extern int lineno;
int yylex(void);
void yyerror(const char *msg);

/* Concatenate any number of strings; the last argument must be NULL */
static char *J(const char *first, ...) {
    va_list ap;
    size_t len = 0;
    const char *p;

    va_start(ap, first);
    for (p = first; p; p = va_arg(ap, const char *)) len += strlen(p);
    va_end(ap);

    char *out = malloc(len + 1);
    if (!out) { perror("malloc"); exit(1); }
    out[0] = '\0';

    char *end = out;
    va_start(ap, first);
    for (p = first; p; p = va_arg(ap, const char *)) {
        size_t n = strlen(p);
        memcpy(end, p, n);
        end += n;
    }
    va_end(ap);
    *end = '\0';
    return out;
}

#define EXPR(...)  J("<expr>", __VA_ARGS__, "</expr>", NULL)
#define STMT(...)  J("<stmt>", __VA_ARGS__, "</stmt>", NULL)
%}

%union {
    char *s;
    struct { char *s; int is_array; } decl;   /* declarator list: whether it holds an array decides scalar_decl vs array_decl */
}

/* Types */
%token <s> CONST SIGNED UNSIGNED SHORT LONG INT CHAR FLOAT DOUBLE VOID
/* Keywords */
%token IF ELSE SWITCH CASE DEFAULT WHILE DO FOR RETURN BREAK CONTINUE
/* Literals and identifiers */
%token <s> ID INT_LIT FLOAT_LIT CHAR_LIT STRING_LIT
/* Multi-character operators */
%token INC DEC LE GE EQ NE AND OR SHL SHR

%type <s> program ext_list ext_decl
%type <s> type_spec base_type sign int_core size
%type <s> func_head params param_list param
%type <decl> declarator_list declarator
%type <s> dims arr_content arr_items arr_item
%type <s> expr expr_opt args arg_list
%type <s> stmt compound items item stmts switch_clauses switch_clause local_decl

/*
 * Operator precedence (lowest first), following https://en.cppreference.com/w/c/language/operator_precedence
 */
%right '='
%left  OR
%left  AND
%left  '|'
%left  '^'
%left  '&'
%left  EQ NE
%left  '<' '>' LE GE
%left  SHL SHR
%left  '+' '-'
%left  '*' '/' '%'
%right UNARY                /* prefix ++ -- + - ! ~ * & (type) */
%left  INC DEC              /* postfix ++ -- */

%start program

%%

program
    : ext_list                          { printf("%s", $1); }
    ;

ext_list
    : ext_decl                          { $$ = $1; }
    | ext_list ext_decl                 { $$ = J($1, $2, NULL); }
    ;

/* ---------------------------------------------------------------------------
 * Top level: variable declarations, function declarations, function definitions
 * After type_spec, the token following ID ('(' or not) picks the branch; LALR(1) decides it directly.
 * ------------------------------------------------------------------------- */
ext_decl
    : local_decl                        { $$ = $1; }
    | type_spec func_head ';'           { $$ = J("<func_decl>", $1, $2, ";</func_decl>", NULL); }
    | type_spec func_head compound      { $$ = J("<func_def>", $1, $2, $3, "</func_def>", NULL); }
    ;

local_decl
    : type_spec declarator_list ';'     {
            $$ = $2.is_array
               ? J("<array_decl>",  $1, $2.s, ";</array_decl>",  NULL)
               : J("<scalar_decl>", $1, $2.s, ";</scalar_decl>", NULL);
        }
    | CONST ';'                         { $$ = J("<scalar_decl>", $1, ";</scalar_decl>", NULL); }
    ;

func_head
    : ID '(' params ')'                 { $$ = J($1, "(", $3, ")", NULL); }
    | '*' ID '(' params ')'             { $$ = J("*", $2, "(", $4, ")", NULL); }
    ;

params
    : /* empty */                       { $$ = ""; }
    | param_list                        { $$ = $1; }
    ;

param_list
    : param                             { $$ = $1; }
    | param_list ',' param              { $$ = J($1, ",", $3, NULL); }
    ;

param
    : type_spec ID                      { $$ = J($1, $2, NULL); }
    | type_spec '*' ID                  { $$ = J($1, "*", $3, NULL); }
    ;

/* ---------------------------------------------------------------------------
 * Types
 *   [const] [signed|unsigned] [long long|long|short] int
 *   [const] [signed|unsigned] (long long)|long|short|char
 *   [const] signed|unsigned|float|double|void
 *   const (alone, only valid as `const ;`; see local_decl)
 * ------------------------------------------------------------------------- */
type_spec
    : base_type                         { $$ = $1; }
    | CONST base_type                   { $$ = J($1, $2, NULL); }
    ;

base_type
    : sign                              { $$ = $1; }
    | sign int_core                     { $$ = J($1, $2, NULL); }
    | int_core                          { $$ = $1; }
    | FLOAT                             { $$ = $1; }
    | DOUBLE                            { $$ = $1; }
    | VOID                              { $$ = $1; }
    ;

sign
    : SIGNED                            { $$ = $1; }
    | UNSIGNED                          { $$ = $1; }
    ;

int_core
    : size                              { $$ = $1; }
    | size INT                          { $$ = J($1, $2, NULL); }
    | INT                               { $$ = $1; }
    | CHAR                              { $$ = $1; }
    ;

size
    : SHORT                             { $$ = $1; }
    | LONG                              { $$ = $1; }
    | LONG LONG                         { $$ = J($1, $2, NULL); }
    ;

/* ---------------------------------------------------------------------------
 * Declarators: scalar, single-level pointer, array (optionally initialized)
 * ------------------------------------------------------------------------- */
declarator_list
    : declarator                        { $$ = $1; }
    | declarator_list ',' declarator    { $$.s = J($1.s, ",", $3.s, NULL); $$.is_array = $1.is_array || $3.is_array; }
    ;

declarator
    : ID                                { $$.s = $1;                          $$.is_array = 0; }
    | ID '=' expr                       { $$.s = J($1, "=", $3, NULL);        $$.is_array = 0; }
    | '*' ID                            { $$.s = J("*", $2, NULL);            $$.is_array = 0; }
    | '*' ID '=' expr                   { $$.s = J("*", $2, "=", $4, NULL);   $$.is_array = 0; }
    | ID dims                           { $$.s = J($1, $2, NULL);             $$.is_array = 1; }
    | ID dims '=' arr_content           { $$.s = J($1, $2, "=", $4, NULL);    $$.is_array = 1; }
    ;

dims
    : '[' expr ']'                      { $$ = J("[", $2, "]", NULL); }
    | dims '[' expr ']'                 { $$ = J($1, "[", $3, "]", NULL); }
    ;

arr_content
    : '{' arr_items '}'                 { $$ = J("{", $2, "}", NULL); }
    ;

arr_items
    : arr_item                          { $$ = $1; }
    | arr_items ',' arr_item            { $$ = J($1, ",", $3, NULL); }
    ;

arr_item
    : expr                              { $$ = $1; }
    | arr_content                       { $$ = $1; }
    ;

/* ---------------------------------------------------------------------------
 * Expressions
 * ------------------------------------------------------------------------- */
expr
    /* binary operators */
    : expr '=' expr                     { $$ = EXPR($1, "=",  $3); }
    | expr OR  expr                     { $$ = EXPR($1, "||", $3); }
    | expr AND expr                     { $$ = EXPR($1, "&&", $3); }
    | expr '|' expr                     { $$ = EXPR($1, "|",  $3); }
    | expr '^' expr                     { $$ = EXPR($1, "^",  $3); }
    | expr '&' expr                     { $$ = EXPR($1, "&",  $3); }
    | expr EQ  expr                     { $$ = EXPR($1, "==", $3); }
    | expr NE  expr                     { $$ = EXPR($1, "!=", $3); }
    | expr '<' expr                     { $$ = EXPR($1, "<",  $3); }
    | expr '>' expr                     { $$ = EXPR($1, ">",  $3); }
    | expr LE  expr                     { $$ = EXPR($1, "<=", $3); }
    | expr GE  expr                     { $$ = EXPR($1, ">=", $3); }
    | expr SHL expr                     { $$ = EXPR($1, "<<", $3); }
    | expr SHR expr                     { $$ = EXPR($1, ">>", $3); }
    | expr '+' expr                     { $$ = EXPR($1, "+",  $3); }
    | expr '-' expr                     { $$ = EXPR($1, "-",  $3); }
    | expr '*' expr                     { $$ = EXPR($1, "*",  $3); }
    | expr '/' expr                     { $$ = EXPR($1, "/",  $3); }
    | expr '%' expr                     { $$ = EXPR($1, "%",  $3); }
    /* prefix unary operators */
    | INC expr %prec UNARY              { $$ = EXPR("++", $2); }
    | DEC expr %prec UNARY              { $$ = EXPR("--", $2); }
    | '+' expr %prec UNARY              { $$ = EXPR("+",  $2); }
    | '-' expr %prec UNARY              { $$ = EXPR("-",  $2); }
    | '!' expr %prec UNARY              { $$ = EXPR("!",  $2); }
    | '~' expr %prec UNARY              { $$ = EXPR("~",  $2); }
    | '*' expr %prec UNARY              { $$ = EXPR("*",  $2); }
    | '&' expr %prec UNARY              { $$ = EXPR("&",  $2); }
    | '(' type_spec ')' expr %prec UNARY     { $$ = EXPR("(", $2, ")",  $4); }
    | '(' type_spec '*' ')' expr %prec UNARY { $$ = EXPR("(", $2, "*)", $5); }
    /* postfix operators */
    | expr INC                          { $$ = EXPR($1, "++"); }
    | expr DEC                          { $$ = EXPR($1, "--"); }
    | ID '(' args ')'                   { $$ = EXPR($1, "(", $3, ")"); }
    | ID dims                           { $$ = EXPR($1, $2); }
    /* primary expressions */
    | '(' expr ')'                      { $$ = EXPR("(", $2, ")"); }
    | ID                                { $$ = EXPR($1); }
    | INT_LIT                           { $$ = EXPR($1); }
    | FLOAT_LIT                         { $$ = EXPR($1); }
    | CHAR_LIT                          { $$ = EXPR($1); }
    | STRING_LIT                        { $$ = EXPR($1); }
    ;

args
    : /* empty */                       { $$ = ""; }
    | arg_list                          { $$ = $1; }
    ;

arg_list
    : expr                              { $$ = $1; }
    | arg_list ',' expr                 { $$ = J($1, ",", $3, NULL); }
    ;

expr_opt
    : /* empty */                       { $$ = ""; }
    | expr                              { $$ = $1; }
    ;

/* ---------------------------------------------------------------------------
 * Statements
 * The spec requires an if body to be a compound_stmt, so there is no dangling-else problem.
 * ------------------------------------------------------------------------- */
stmt
    : expr ';'                                          { $$ = STMT($1, ";"); }
    | IF '(' expr ')' compound                          { $$ = STMT("if(", $3, ")", $5); }
    | IF '(' expr ')' compound ELSE compound            { $$ = STMT("if(", $3, ")", $5, "else", $7); }
    | SWITCH '(' expr ')' '{' switch_clauses '}'        { $$ = STMT("switch(", $3, "){", $6, "}"); }
    | WHILE '(' expr ')' stmt                           { $$ = STMT("while(", $3, ")", $5); }
    | DO stmt WHILE '(' expr ')' ';'                    { $$ = STMT("do", $2, "while(", $5, ");"); }
    | FOR '(' expr_opt ';' expr_opt ';' expr_opt ')' stmt
                                                        { $$ = STMT("for(", $3, ";", $5, ";", $7, ")", $9); }
    | RETURN expr ';'                                   { $$ = STMT("return", $2, ";"); }
    | RETURN ';'                                        { $$ = STMT("return;"); }
    | BREAK ';'                                         { $$ = STMT("break;"); }
    | CONTINUE ';'                                      { $$ = STMT("continue;"); }
    | compound                                          { $$ = STMT($1); }
    ;

compound
    : '{' items '}'                     { $$ = J("{", $2, "}", NULL); }
    ;

items
    : /* empty */                       { $$ = ""; }
    | items item                        { $$ = J($1, $2, NULL); }
    ;

item
    : stmt                              { $$ = $1; }
    | local_decl                        { $$ = $1; }
    ;

switch_clauses
    : /* empty */                       { $$ = ""; }
    | switch_clauses switch_clause      { $$ = J($1, $2, NULL); }
    ;

switch_clause
    : CASE expr ':' stmts               { $$ = J("case", $2, ":", $4, NULL); }
    | DEFAULT ':' stmts                 { $$ = J("default:", $3, NULL); }
    ;

stmts
    : /* empty */                       { $$ = ""; }
    | stmts stmt                        { $$ = J($1, $2, NULL); }
    ;

%%

int main(void) {
    yyparse();
    return 0;
}

void yyerror(const char *msg) {
    fprintf(stderr, "Error at line %d: %s\n", lineno, msg);
    exit(1);
}
