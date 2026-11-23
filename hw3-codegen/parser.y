%{
/*
 * NTHU CS340400 Compiler Design - HW3 Code Generator
 *
 * Pipeline: scanner -> parser (this grammar, from HW2) -> AST -> walk the AST to emit RISC-V -> codegen.S
 *
 * Sections (the submission may only contain scanner.l / parser.y / makefile, so everything lives here):
 *   [1] AST definition and constructors (prologue, used by grammar actions)
 *   [2] Grammar (same as HW2; actions build the AST)
 *   [3] Symbol table         (epilogue)
 *   [4] Code generation      (epilogue)
 *   [5] main                 (epilogue)
 *
 * Codegen design:
 *   - Expressions use a stack machine: the result is always in t0; a binary op pushes the left side,
 *     evaluates the right side, then pops into t1. Each push takes 16 bytes so sp stays 16-byte aligned.
 *   - Every int / pointer takes one WORD (8 bytes on RV64, 4 bytes on RV32),
 *     so array stride and pointer arithmetic scale are both WORD.
 *   - Frame: s0 = sp on entry; ra at s0-W, old s0 at s0-2W, then parameters and locals.
 *     Each declaration gets its own slot (never reused); array element 0 is at the lowest address.
 *   - No optimization at all (the spec forbids constant folding and the like).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

extern int lineno;
int yylex(void);
void yyerror(const char *msg);

/* ======================================================================
 * [1] AST
 * ==================================================================== */
enum {
    /* expressions */
    E_NUM, E_FLOAT, E_STR, E_VAR, E_BIN, E_ASSIGN, E_PRE, E_POST, E_UNARY,
    E_DEREF, E_ADDR, E_CAST, E_CALL, E_INDEX, E_INITLIST,
    /* statements */
    S_EXPR, S_IF, S_WHILE, S_DO, S_FOR, S_RETURN, S_BREAK, S_CONTINUE,
    S_BLOCK, S_SWITCH, S_CASE, S_DECLS,
    /* declarations */
    D_VAR, D_FUNC
};

typedef struct Node {
    int kind;
    int op;             /* operator of E_BIN / E_UNARY / E_PRE / E_POST (token value or char) */
    int line;
    long ival;          /* value of E_NUM */
    char *name;         /* identifier, string literal */
    int is_ptr;         /* D_VAR / D_FUNC / E_CAST: is a pointer */
    int is_unsigned;    /* D_VAR / D_FUNC / E_CAST: is unsigned (unsigned, uint32_t) */
    struct Node *a, *b, *c, *d;
    struct Node *next;  /* list link (params, args, statements, declarators...) */
} Node;

/*
 * Fields used by each node kind:
 *   E_BIN(op, a, b)        E_ASSIGN(a = b)        E_PRE/E_POST(op, a)   E_UNARY(op, a)
 *   E_DEREF(a)             E_ADDR(a)              E_CAST(is_ptr, a)
 *   E_CALL(name, a=args)   E_INDEX(name, a=index list)  E_INITLIST(a=element list)
 *   S_EXPR(a)  S_IF(a=cond, b=then, c=else)  S_WHILE(a=cond, b=body)  S_DO(a=body, b=cond)
 *   S_FOR(a=init, b=cond, c=step, d=body)    S_RETURN(a)  S_BLOCK(a=items)
 *   S_SWITCH(a=expr, b=clauses)  S_CASE(a=expr, or NULL for default, b=stmts)  S_DECLS(a=declarator list)
 *   D_VAR(name, is_ptr, a=array dims, b=initializer)   D_FUNC(name, is_ptr, a=params, b=body or NULL)
 */

static Node *program_root;

static Node *mk(int kind) {
    Node *n = calloc(1, sizeof(Node));
    if (!n) { perror("calloc"); exit(1); }
    n->kind = kind;
    n->line = lineno;
    return n;
}

static Node *mk2(int kind, int op, Node *a, Node *b) {
    Node *n = mk(kind);
    n->op = op;
    n->a = a;
    n->b = b;
    return n;
}

static Node *mk_name(int kind, char *name) {
    Node *n = mk(kind);
    n->name = name;
    return n;
}

/* Append item (which may itself be a list) to the end of list */
static Node *append(Node *list, Node *item) {
    if (!list) return item;
    Node *p = list;
    while (p->next) p = p->next;
    p->next = item;
    return list;
}

/* Char literal -> integer, e.g. 'a' -> 97, '\n' -> 10, '\x41' -> 65 */
static long char_value(const char *lit) {
    const char *p = lit + 1;            /* skip the opening ' */
    if (*p != '\\') return (unsigned char)*p;
    p++;
    switch (*p) {
    case 'a': return 7;   case 'b': return 8;   case 'e': return 27;
    case 'f': return 12;  case 'n': return 10;  case 'r': return 13;
    case 't': return 9;   case 'v': return 11;
    case 'x': return strtol(p + 1, NULL, 16);
    case 'u': case 'U': return strtol(p + 1, NULL, 16);
    default:
        if (*p >= '0' && *p <= '7') return strtol(p, NULL, 8);
        return (unsigned char)*p;       /* \\ \' \" \? */
    }
}
%}

%union {
    char *s;
    int i;
    struct Node *n;
}

%token <s> CONST SIGNED UNSIGNED SHORT LONG INT CHAR FLOAT DOUBLE VOID UINT32
%token IF ELSE SWITCH CASE DEFAULT WHILE DO FOR RETURN BREAK CONTINUE
%token <s> ID INT_LIT FLOAT_LIT CHAR_LIT STRING_LIT
%token INC DEC LE GE EQ NE AND OR SHL SHR

%type <i> type_spec base_type sign            /* value: is the type unsigned */
%type <s> int_core size
%type <n> program ext_list ext_decl local_decl func_head params param_list param
%type <n> declarator_list declarator dims arr_content arr_items arr_item
%type <n> expr expr_opt args arg_list
%type <n> stmt compound items item stmts switch_clauses switch_clause

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
%right UNARY
%left  INC DEC

%start program

%%

/* ======================================================================
 * [2] Grammar (same as HW2)
 * ==================================================================== */

program
    : ext_list                          { program_root = $1; }
    ;

ext_list
    : ext_decl                          { $$ = $1; }
    | ext_list ext_decl                 { $$ = append($1, $2); }
    ;

ext_decl
    : local_decl                        { $$ = $1; }
    | type_spec func_head ';'           { $$ = $2; $$->is_unsigned = $1; }
    | type_spec func_head compound      { $$ = $2; $$->is_unsigned = $1; $$->b = $3; }
    ;

local_decl
    : type_spec declarator_list ';'     {
            $$ = mk(S_DECLS);
            $$->a = $2;
            for (Node *d = $2; d; d = d->next) d->is_unsigned = $1;
        }
    | CONST ';'                         { $$ = mk(S_DECLS); }
    ;

func_head
    : ID '(' params ')'                 { $$ = mk_name(D_FUNC, $1); $$->a = $3; }
    | '*' ID '(' params ')'             { $$ = mk_name(D_FUNC, $2); $$->a = $4; $$->is_ptr = 1; }
    ;

params
    : /* empty */                       { $$ = NULL; }
    | param_list                        { $$ = $1; }
    ;

param_list
    : param                             { $$ = $1; }
    | param_list ',' param              { $$ = append($1, $3); }
    ;

param
    : type_spec ID                      { $$ = mk_name(D_VAR, $2); $$->is_unsigned = $1; }
    | type_spec '*' ID                  { $$ = mk_name(D_VAR, $3); $$->is_ptr = 1; $$->is_unsigned = $1; }
    ;

/*
 * Types: codegen does not distinguish int/char/long...; all are one WORD.
 * It only needs to know "is pointer" (from the declarator) and "is unsigned" (type_spec's value).
 */
type_spec
    : base_type                         { $$ = $1; }
    | CONST base_type                   { $$ = $2; }
    ;

base_type
    : sign                              { $$ = $1; }
    | sign int_core                     { $$ = $1; }
    | int_core                          { $$ = 0; }
    | UINT32                            { $$ = 1; }     /* HW3 Bonus */
    | FLOAT                             { $$ = 0; }
    | DOUBLE                            { $$ = 0; }
    | VOID                              { $$ = 0; }
    ;

sign
    : SIGNED                            { $$ = 0; }
    | UNSIGNED                          { $$ = 1; }
    ;

int_core
    : size                              { $$ = $1; }
    | size INT                          { $$ = $2; }
    | INT                               { $$ = $1; }
    | CHAR                              { $$ = $1; }
    ;

size
    : SHORT                             { $$ = $1; }
    | LONG                              { $$ = $1; }
    | LONG LONG                         { $$ = $1; }
    ;

declarator_list
    : declarator                        { $$ = $1; }
    | declarator_list ',' declarator    { $$ = append($1, $3); }
    ;

declarator
    : ID                                { $$ = mk_name(D_VAR, $1); }
    | ID '=' expr                       { $$ = mk_name(D_VAR, $1); $$->b = $3; }
    | '*' ID                            { $$ = mk_name(D_VAR, $2); $$->is_ptr = 1; }
    | '*' ID '=' expr                   { $$ = mk_name(D_VAR, $2); $$->is_ptr = 1; $$->b = $4; }
    | ID dims                           { $$ = mk_name(D_VAR, $1); $$->a = $2; }
    | ID dims '=' arr_content           { $$ = mk_name(D_VAR, $1); $$->a = $2; $$->b = $4; }
    ;

dims
    : '[' expr ']'                      { $$ = $2; }
    | dims '[' expr ']'                 { $$ = append($1, $3); }
    ;

arr_content
    : '{' arr_items '}'                 { $$ = mk(E_INITLIST); $$->a = $2; }
    ;

arr_items
    : arr_item                          { $$ = $1; }
    | arr_items ',' arr_item            { $$ = append($1, $3); }
    ;

arr_item
    : expr                              { $$ = $1; }
    | arr_content                       { $$ = $1; }
    ;

expr
    : expr '=' expr                     { $$ = mk2(E_ASSIGN, '=', $1, $3); }
    | expr OR  expr                     { $$ = mk2(E_BIN, OR,  $1, $3); }
    | expr AND expr                     { $$ = mk2(E_BIN, AND, $1, $3); }
    | expr '|' expr                     { $$ = mk2(E_BIN, '|', $1, $3); }
    | expr '^' expr                     { $$ = mk2(E_BIN, '^', $1, $3); }
    | expr '&' expr                     { $$ = mk2(E_BIN, '&', $1, $3); }
    | expr EQ  expr                     { $$ = mk2(E_BIN, EQ,  $1, $3); }
    | expr NE  expr                     { $$ = mk2(E_BIN, NE,  $1, $3); }
    | expr '<' expr                     { $$ = mk2(E_BIN, '<', $1, $3); }
    | expr '>' expr                     { $$ = mk2(E_BIN, '>', $1, $3); }
    | expr LE  expr                     { $$ = mk2(E_BIN, LE,  $1, $3); }
    | expr GE  expr                     { $$ = mk2(E_BIN, GE,  $1, $3); }
    | expr SHL expr                     { $$ = mk2(E_BIN, SHL, $1, $3); }
    | expr SHR expr                     { $$ = mk2(E_BIN, SHR, $1, $3); }
    | expr '+' expr                     { $$ = mk2(E_BIN, '+', $1, $3); }
    | expr '-' expr                     { $$ = mk2(E_BIN, '-', $1, $3); }
    | expr '*' expr                     { $$ = mk2(E_BIN, '*', $1, $3); }
    | expr '/' expr                     { $$ = mk2(E_BIN, '/', $1, $3); }
    | expr '%' expr                     { $$ = mk2(E_BIN, '%', $1, $3); }
    | INC expr %prec UNARY              { $$ = mk2(E_PRE, INC, $2, NULL); }
    | DEC expr %prec UNARY              { $$ = mk2(E_PRE, DEC, $2, NULL); }
    | '+' expr %prec UNARY              { $$ = mk2(E_UNARY, '+', $2, NULL); }
    | '-' expr %prec UNARY              { $$ = mk2(E_UNARY, '-', $2, NULL); }
    | '!' expr %prec UNARY              { $$ = mk2(E_UNARY, '!', $2, NULL); }
    | '~' expr %prec UNARY              { $$ = mk2(E_UNARY, '~', $2, NULL); }
    | '*' expr %prec UNARY              { $$ = mk2(E_DEREF, 0, $2, NULL); }
    | '&' expr %prec UNARY              { $$ = mk2(E_ADDR, 0, $2, NULL); }
    | '(' type_spec ')' expr %prec UNARY     { $$ = mk2(E_CAST, 0, $4, NULL); $$->is_unsigned = $2; }
    | '(' type_spec '*' ')' expr %prec UNARY { $$ = mk2(E_CAST, 0, $5, NULL); $$->is_ptr = 1; $$->is_unsigned = $2; }
    | expr INC                          { $$ = mk2(E_POST, INC, $1, NULL); }
    | expr DEC                          { $$ = mk2(E_POST, DEC, $1, NULL); }
    | ID '(' args ')'                   { $$ = mk_name(E_CALL, $1); $$->a = $3; }
    | ID dims                           { $$ = mk_name(E_INDEX, $1); $$->a = $2; }
    | '(' expr ')'                      { $$ = $2; }
    | ID                                { $$ = mk_name(E_VAR, $1); }
    | INT_LIT                           { $$ = mk(E_NUM); $$->ival = atol($1); }
    | FLOAT_LIT                         { $$ = mk_name(E_FLOAT, $1); }
    | CHAR_LIT                          { $$ = mk(E_NUM); $$->ival = char_value($1); }
    | STRING_LIT                        { $$ = mk_name(E_STR, $1); }
    ;

args
    : /* empty */                       { $$ = NULL; }
    | arg_list                          { $$ = $1; }
    ;

arg_list
    : expr                              { $$ = $1; }
    | arg_list ',' expr                 { $$ = append($1, $3); }
    ;

expr_opt
    : /* empty */                       { $$ = NULL; }
    | expr                              { $$ = $1; }
    ;

stmt
    : expr ';'                                          { $$ = mk(S_EXPR); $$->a = $1; }
    | IF '(' expr ')' compound                          { $$ = mk(S_IF); $$->a = $3; $$->b = $5; }
    | IF '(' expr ')' compound ELSE compound            { $$ = mk(S_IF); $$->a = $3; $$->b = $5; $$->c = $7; }
    | SWITCH '(' expr ')' '{' switch_clauses '}'        { $$ = mk(S_SWITCH); $$->a = $3; $$->b = $6; }
    | WHILE '(' expr ')' stmt                           { $$ = mk(S_WHILE); $$->a = $3; $$->b = $5; }
    | DO stmt WHILE '(' expr ')' ';'                    { $$ = mk(S_DO); $$->a = $2; $$->b = $5; }
    | FOR '(' expr_opt ';' expr_opt ';' expr_opt ')' stmt
                                                        { $$ = mk(S_FOR); $$->a = $3; $$->b = $5; $$->c = $7; $$->d = $9; }
    | RETURN expr ';'                                   { $$ = mk(S_RETURN); $$->a = $2; }
    | RETURN ';'                                        { $$ = mk(S_RETURN); }
    | BREAK ';'                                         { $$ = mk(S_BREAK); }
    | CONTINUE ';'                                      { $$ = mk(S_CONTINUE); }
    | compound                                          { $$ = $1; }
    ;

compound
    : '{' items '}'                     { $$ = mk(S_BLOCK); $$->a = $2; }
    ;

items
    : /* empty */                       { $$ = NULL; }
    | items item                        { $$ = append($1, $2); }
    ;

item
    : stmt                              { $$ = $1; }
    | local_decl                        { $$ = $1; }
    ;

switch_clauses
    : /* empty */                       { $$ = NULL; }
    | switch_clauses switch_clause      { $$ = append($1, $2); }
    ;

switch_clause
    : CASE expr ':' stmts               { $$ = mk(S_CASE); $$->a = $2; $$->b = $4; }
    | DEFAULT ':' stmts                 { $$ = mk(S_CASE); $$->b = $3; }
    ;

stmts
    : /* empty */                       { $$ = NULL; }
    | stmts stmt                        { $$ = append($1, $2); }
    ;

%%

/* ======================================================================
 * Shared: error handling
 * ==================================================================== */
static void fatal(const Node *n, const char *fmt, ...) {
    va_list ap;
    fprintf(stderr, "Error at line %d: ", n ? n->line : lineno);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

void yyerror(const char *msg) {
    fprintf(stderr, "Error at line %d: %s\n", lineno, msg);
    exit(1);
}

/* ======================================================================
 * [3] Symbol table
 *   Array-based scope stack: entering a block does depth+1; leaving removes that level's symbols.
 *   Lookup searches from the end, so it finds the innermost definition (shadowing).
 * ==================================================================== */
enum { SYM_LOCAL, SYM_GLOBAL, SYM_FUNC };

typedef struct {
    const char *name;
    int kind;
    int is_ptr;
    int is_array;
    int is_unsigned;
    int offset;     /* SYM_LOCAL: offset from s0 (negative) */
    int depth;
} Sym;

#define MAX_SYMS 4096
static Sym syms[MAX_SYMS];
static int nsyms;
static int depth;

static void scope_push(void) { depth++; }

static void scope_pop(void) {
    while (nsyms > 0 && syms[nsyms - 1].depth == depth) nsyms--;
    depth--;
}

static Sym *sym_add(const Node *where, const char *name, int kind, int is_ptr, int is_array, int offset) {
    if (nsyms >= MAX_SYMS) fatal(where, "too many symbols");
    Sym *s = &syms[nsyms++];
    s->name = name;
    s->kind = kind;
    s->is_ptr = is_ptr;
    s->is_unsigned = where ? where->is_unsigned : 0;
    s->is_array = is_array;
    s->offset = offset;
    s->depth = depth;
    return s;
}

static Sym *sym_lookup(const char *name) {
    for (int i = nsyms - 1; i >= 0; i--)
        if (strcmp(syms[i].name, name) == 0) return &syms[i];
    return NULL;
}

/* ======================================================================
 * [4] Code generation
 * ==================================================================== */
static FILE *out;

/* Target parameters: RV64 by default, `--rv32` switches to RV32 (HW3 Bonus) */
static int W = 8;                   /* WORD size (bytes) */
static int W_SHIFT = 3;             /* log2(W), for pointer scaling */
static const char *LOAD = "ld";
static const char *STORE = "sd";
static const char *DATA_WORD = ".dword";
static int pext_emulate = 0;       /* testing: P-extension intrinsics call __pext_<op> instead (see bonus/tests) */

static const char *const ARG_REG[8] = { "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7" };

#define PUSH_SIZE 16                /* each push takes 16 bytes to keep sp 16-byte aligned */

static int label_count;
static int cur_off;                 /* frame size allocated so far in this function (excluding temp pushes) */
static int ret_label;               /* label of this function's epilogue */

#define MAX_NEST 256
static int break_stack[MAX_NEST], n_break;
static int cont_stack[MAX_NEST], n_cont;

static int new_label(void) { return ++label_count; }

/* Emit one instruction (indented by two spaces) */
static void ins(const char *fmt, ...) {
    va_list ap;
    fputs("  ", out);
    va_start(ap, fmt);
    vfprintf(out, fmt, ap);
    va_end(ap);
    fputc('\n', out);
}

static void put_label(int id) { fprintf(out, ".L%d:\n", id); }

static int fits_imm12(long v) { return v >= -2048 && v <= 2047; }

/* rd = rs + imm (uses t2 as scratch when imm does not fit in 12 bits) */
static void addi_any(const char *rd, const char *rs, long imm) {
    if (fits_imm12(imm)) {
        ins("addi %s, %s, %ld", rd, rs, imm);
    } else {
        ins("li t2, %ld", imm);
        ins("add %s, %s, t2", rd, rs);
    }
}

/* op reg, off(s0): load/store one frame slot */
static void frame_mem(const char *op, const char *reg, int off) {
    if (fits_imm12(off)) {
        ins("%s %s, %d(s0)", op, reg, off);
    } else {
        ins("li t2, %d", off);
        ins("add t2, s0, t2");
        ins("%s %s, 0(t2)", op, reg);
    }
}

static void push(const char *reg) {
    ins("addi sp, sp, -%d", PUSH_SIZE);
    ins("%s %s, 0(sp)", STORE, reg);
}

static void pop(const char *reg) {
    ins("%s %s, 0(sp)", LOAD, reg);
    ins("addi sp, sp, %d", PUSH_SIZE);
}

/* Jump to label if t0 == 0; uses bnez + j to avoid the +/-4KB range limit of conditional branches */
static void jump_if_zero(int label) {
    int skip = new_label();
    ins("bnez t0, .L%d", skip);
    ins("j .L%d", label);
    put_label(skip);
}

/* Allocate n WORDs in the frame; return the offset of element 0 from s0 */
static int frame_alloc(int n) {
    cur_off += n * W;
    return -cur_off;
}

/* ---------- declaration helpers ---------- */

/* Array length: 1-D only, length must be an integer constant */
static int array_length(const Node *decl) {
    const Node *dim = decl->a;
    if (!dim) return 0;
    if (dim->next) fatal(decl, "only 1-D arrays are supported: '%s'", decl->name);
    if (dim->kind != E_NUM || dim->ival <= 0)
        fatal(decl, "array size of '%s' must be a positive integer constant", decl->name);
    return (int)dim->ival;
}

static int decl_slots(const Node *decl) {
    int len = array_length(decl);
    return len ? len : 1;
}

/* Count the slots a function body needs so the prologue can allocate the frame at once */
static int count_slots(const Node *n) {
    int total = 0;
    for (; n; n = n->next) {
        switch (n->kind) {
        case S_DECLS:
            for (const Node *d = n->a; d; d = d->next) total += decl_slots(d);
            break;
        case S_BLOCK:  total += count_slots(n->a); break;
        case S_IF:     total += count_slots(n->b) + count_slots(n->c); break;
        case S_WHILE:  total += count_slots(n->b); break;
        case S_DO:     total += count_slots(n->a); break;
        case S_FOR:    total += count_slots(n->d); break;
        case S_SWITCH: total += 1 + count_slots(n->b); break;   /* +1: holds the switch value */
        case S_CASE:   total += count_slots(n->b); break;
        default: break;
        }
    }
    return total;
}

/* ---------- expressions ---------- */
static void gen_expr(const Node *n);
static void gen_stmt(const Node *n);

static Sym *need_sym(const Node *n, const char *name) {
    Sym *s = sym_lookup(name);
    if (!s) fatal(n, "'%s' undeclared", name);
    return s;
}

/* ---------- HW3 Bonus: Andes P-extension intrinsics ---------- */
typedef struct { const char *name; const char *insn; } Intrinsic;

static const Intrinsic INTRINSICS[] = {
    { "__rv__ukadd8",  "ukadd8"  },     /* per-byte unsigned saturating add */
    { "__rv__uksub8",  "uksub8"  },     /* per-byte unsigned saturating subtract */
    { "__rv__cmpeq8",  "cmpeq8"  },     /* per byte: 0xFF if equal, else 0 */
    { "__rv__ucmplt8", "ucmplt8" },     /* per byte: 0xFF if unsigned less-than, else 0 */
};

static const Intrinsic *find_intrinsic(const char *name) {
    for (size_t i = 0; i < sizeof INTRINSICS / sizeof INTRINSICS[0]; i++)
        if (strcmp(INTRINSICS[i].name, name) == 0) return &INTRINSICS[i];
    return NULL;
}

/*
 * Whether an expression is unsigned (selects unsigned compare, divide, modulo, right shift).
 * Per C's usual arithmetic conversions: signed op unsigned of the same rank is unsigned.
 */
static int is_unsigned_expr(const Node *n) {
    Sym *s;
    switch (n->kind) {
    case E_VAR:
    case E_INDEX:
        s = sym_lookup(n->name);
        return s && s->is_unsigned;
    case E_DEREF:
        return n->a->kind == E_VAR && is_unsigned_expr(n->a);
    case E_CAST:
        return n->is_unsigned && !n->is_ptr;
    case E_ASSIGN:
    case E_PRE:
    case E_POST:
        return is_unsigned_expr(n->a);
    case E_UNARY:
        return n->op != '!' && is_unsigned_expr(n->a);
    case E_CALL:
        if (find_intrinsic(n->name)) return 1;
        s = sym_lookup(n->name);
        return s && s->kind == SYM_FUNC && s->is_unsigned && !s->is_ptr;
    case E_BIN:
        switch (n->op) {
        case '<': case '>': case LE: case GE: case EQ: case NE: case AND: case OR:
            return 0;
        case SHL: case SHR:
            return is_unsigned_expr(n->a);
        default:
            return is_unsigned_expr(n->a) || is_unsigned_expr(n->b);
        }
    default:
        return 0;
    }
}

/* Whether an expression is a pointer (decides if +/- scales by WORD) */
static int is_ptr_expr(const Node *n) {
    Sym *s;
    switch (n->kind) {
    case E_VAR:
        s = need_sym(n, n->name);
        return s->is_ptr || s->is_array;
    case E_ADDR:   return 1;
    case E_CAST:   return n->is_ptr;
    case E_ASSIGN: return is_ptr_expr(n->a);
    case E_PRE:
    case E_POST:   return is_ptr_expr(n->a);
    case E_CALL:
        s = sym_lookup(n->name);
        return s && s->kind == SYM_FUNC && s->is_ptr;
    case E_BIN:
        if (n->op == '+') return is_ptr_expr(n->a) || is_ptr_expr(n->b);
        if (n->op == '-') return is_ptr_expr(n->a) && !is_ptr_expr(n->b);
        return 0;
    default:
        return 0;
    }
}

/* Address of a symbol -> t0 */
static void gen_sym_addr(const Sym *s) {
    if (s->kind == SYM_GLOBAL) ins("la t0, %s", s->name);
    else addi_any("t0", "s0", s->offset);
}

/* Address of an lvalue -> t0 */
static void gen_addr(const Node *n) {
    Sym *s;
    switch (n->kind) {
    case E_VAR:
        s = need_sym(n, n->name);
        if (s->kind == SYM_FUNC) fatal(n, "'%s' is a function", n->name);
        gen_sym_addr(s);
        break;
    case E_DEREF:
        gen_expr(n->a);
        break;
    case E_INDEX:
        s = need_sym(n, n->name);
        if (n->a->next) fatal(n, "only 1-D array subscripts are supported");
        if (s->is_array) {
            gen_sym_addr(s);                    /* array: the base is the array's own address */
        } else if (s->is_ptr) {
            gen_sym_addr(s);                    /* pointer: load the pointer value first */
            ins("%s t0, 0(t0)", LOAD);
        } else {
            fatal(n, "'%s' is not an array or pointer", n->name);
        }
        push("t0");
        gen_expr(n->a);
        ins("slli t0, t0, %d", W_SHIFT);
        pop("t1");
        ins("add t0, t1, t0");
        break;
    default:
        fatal(n, "expression is not assignable");
    }
}

static void gen_binary(const Node *n) {
    /* && / || short-circuit, so both sides cannot be evaluated up front */
    if (n->op == AND || n->op == OR) {
        int short_label = new_label(), end = new_label();
        gen_expr(n->a);
        if (n->op == AND) {
            jump_if_zero(short_label);
        } else {
            int skip = new_label();
            ins("beqz t0, .L%d", skip);
            ins("j .L%d", short_label);
            put_label(skip);
        }
        gen_expr(n->b);
        ins("snez t0, t0");
        ins("j .L%d", end);
        put_label(short_label);
        ins("li t0, %d", n->op == AND ? 0 : 1);
        put_label(end);
        return;
    }

    int lptr = 0, rptr = 0;
    if (n->op == '+' || n->op == '-') {
        lptr = is_ptr_expr(n->a);
        rptr = is_ptr_expr(n->b);
    }
    /* compare: unsigned if either side is unsigned; right shift: depends on the left operand */
    int uns = (n->op == SHR) ? is_unsigned_expr(n->a)
                             : (is_unsigned_expr(n->a) || is_unsigned_expr(n->b));
    const char *slt = uns ? "sltu" : "slt";

    gen_expr(n->a);
    push("t0");
    gen_expr(n->b);
    pop("t1");                          /* t1 = left operand, t0 = right operand */

    switch (n->op) {
    case '+':
        if (lptr && !rptr) ins("slli t0, t0, %d", W_SHIFT);
        if (rptr && !lptr) ins("slli t1, t1, %d", W_SHIFT);
        ins("add t0, t1, t0");
        break;
    case '-':
        if (lptr && !rptr) ins("slli t0, t0, %d", W_SHIFT);
        ins("sub t0, t1, t0");
        if (lptr && rptr) ins("srai t0, t0, %d", W_SHIFT);   /* pointer difference -> element count */
        break;
    case '*': ins("mul t0, t1, t0"); break;
    case '/': ins("%s t0, t1, t0", uns ? "divu" : "div"); break;
    case '%': ins("%s t0, t1, t0", uns ? "remu" : "rem"); break;
    case '&': ins("and t0, t1, t0"); break;
    case '|': ins("or t0, t1, t0"); break;
    case '^': ins("xor t0, t1, t0"); break;
    case SHL: ins("sll t0, t1, t0"); break;
    case SHR: ins("%s t0, t1, t0", uns ? "srl" : "sra"); break;
    case '<': ins("%s t0, t1, t0", slt); break;
    case '>': ins("%s t0, t0, t1", slt); break;
    case LE:  ins("%s t0, t0, t1", slt); ins("xori t0, t0, 1"); break;
    case GE:  ins("%s t0, t1, t0", slt); ins("xori t0, t0, 1"); break;
    case EQ:  ins("sub t0, t1, t0"); ins("seqz t0, t0"); break;
    case NE:  ins("sub t0, t1, t0"); ins("snez t0, t0"); break;
    default:  fatal(n, "unsupported binary operator");
    }
}

/*
 * Intrinsics: emit the P-extension instruction directly instead of a call
 *   rd = t0, rs1 = 1st argument (t1), rs2 = 2nd argument (t0)
 */
static void gen_intrinsic(const Node *n, const Intrinsic *in) {
    if (!n->a || !n->a->next || n->a->next->next)
        fatal(n, "%s expects exactly 2 arguments", n->name);
    gen_expr(n->a);
    push("t0");
    gen_expr(n->a->next);
    pop("t1");
    if (pext_emulate) {
        /* test mode: same operand order, but call the C reference so it runs on Spike without the P-extension */
        ins("mv a0, t1");
        ins("mv a1, t0");
        ins("jal ra, __pext_%s", in->insn);
        ins("mv t0, a0");
    } else {
        ins("%s t0, t1, t0", in->insn);
    }
}

static void gen_call(const Node *n) {
    const Intrinsic *in = find_intrinsic(n->name);
    if (in) { gen_intrinsic(n, in); return; }

    int argc = 0;
    for (const Node *a = n->a; a; a = a->next) {
        gen_expr(a);                    /* evaluate left to right, pushing each */
        push("t0");
        argc++;
    }
    if (argc > 8) fatal(n, "more than 8 arguments are not supported");
    for (int i = argc - 1; i >= 0; i--) pop(ARG_REG[i]);
    ins("jal ra, %s", n->name);
    ins("mv t0, a0");
}

static void gen_expr(const Node *n) {
    Sym *s;
    switch (n->kind) {
    case E_NUM:
        ins("li t0, %ld", n->ival);
        break;
    case E_VAR:
        s = need_sym(n, n->name);
        if (s->kind == SYM_FUNC) fatal(n, "function '%s' used as a value", n->name);
        gen_sym_addr(s);
        if (!s->is_array) ins("%s t0, 0(t0)", LOAD);   /* an array name's value is its address */
        break;
    case E_INDEX:
    case E_DEREF:
        gen_addr(n);
        ins("%s t0, 0(t0)", LOAD);
        break;
    case E_ADDR:
        gen_addr(n->a);
        break;
    case E_ASSIGN:
        gen_addr(n->a);
        push("t0");
        gen_expr(n->b);
        pop("t1");
        ins("%s t0, 0(t1)", STORE);
        break;
    case E_PRE:
    case E_POST: {
        int step = is_ptr_expr(n->a) ? W : 1;
        if (n->op == DEC) step = -step;
        gen_addr(n->a);
        ins("mv t1, t0");
        ins("%s t0, 0(t1)", LOAD);
        if (n->kind == E_PRE) {
            ins("addi t0, t0, %d", step);
            ins("%s t0, 0(t1)", STORE);
        } else {
            ins("addi t2, t0, %d", step);
            ins("%s t2, 0(t1)", STORE);  /* the result keeps the old value */
        }
        break;
    }
    case E_UNARY:
        gen_expr(n->a);
        switch (n->op) {
        case '-': ins("neg t0, t0"); break;
        case '!': ins("seqz t0, t0"); break;
        case '~': ins("not t0, t0"); break;
        case '+': break;
        }
        break;
    case E_CAST:
        gen_expr(n->a);                 /* all ints and pointers are one WORD, so a cast emits nothing */
        break;
    case E_BIN:
        gen_binary(n);
        break;
    case E_CALL:
        gen_call(n);
        break;
    case E_FLOAT:
        fatal(n, "floating-point literals are not supported");
        break;
    case E_STR:
        fatal(n, "string literals are not supported");
        break;
    case E_INITLIST:
        fatal(n, "initializer list is only allowed in array declarations");
        break;
    default:
        fatal(n, "unsupported expression");
    }
}

/* ---------- statements ---------- */
static void gen_local_decl(const Node *d) {
    int len = array_length(d);
    int off = frame_alloc(len ? len : 1);
    sym_add(d, d->name, SYM_LOCAL, d->is_ptr, len > 0, off);

    if (!d->b) return;
    if (len) {
        /* 1-D array initializer: write {e0, e1, ...} into the elements in order */
        if (d->b->kind != E_INITLIST) fatal(d, "array '%s' needs a {...} initializer", d->name);
        int i = 0;
        for (const Node *e = d->b->a; e; e = e->next, i++) {
            if (i >= len) fatal(d, "too many initializers for '%s'", d->name);
            if (e->kind == E_INITLIST) fatal(d, "nested initializer for 1-D array '%s'", d->name);
            gen_expr(e);
            frame_mem(STORE, "t0", off + i * W);
        }
    } else {
        gen_expr(d->b);
        frame_mem(STORE, "t0", off);
    }
}

static void gen_switch(const Node *n) {
    int slot = frame_alloc(1);
    int end = new_label(), default_label = 0, nclause = 0;
    const Node *c;

    for (c = n->b; c; c = c->next) nclause++;
    int *labels = malloc(sizeof(int) * (nclause ? nclause : 1));

    gen_expr(n->a);
    frame_mem(STORE, "t0", slot);

    /* compare each case; jump to its body on a match */
    int i = 0;
    for (c = n->b; c; c = c->next, i++) {
        labels[i] = new_label();
        if (!c->a) { default_label = labels[i]; continue; }
        gen_expr(c->a);
        frame_mem(LOAD, "t1", slot);
        ins("xor t0, t0, t1");
        jump_if_zero(labels[i]);
    }
    ins("j .L%d", default_label ? default_label : end);

    /* case bodies keep source order, so a missing break falls through */
    break_stack[n_break++] = end;
    i = 0;
    for (c = n->b; c; c = c->next, i++) {
        put_label(labels[i]);
        for (const Node *s = c->b; s; s = s->next) gen_stmt(s);
    }
    n_break--;
    put_label(end);
    free(labels);
}

static void push_loop(int brk, int cont) {
    if (n_break >= MAX_NEST || n_cont >= MAX_NEST) fatal(NULL, "loops nested too deeply");
    break_stack[n_break++] = brk;
    cont_stack[n_cont++] = cont;
}

static void pop_loop(void) { n_break--; n_cont--; }

static void gen_stmt(const Node *n) {
    int l_cond, l_body, l_cont, l_end, l_else;
    switch (n->kind) {
    case S_EXPR:
        gen_expr(n->a);
        break;
    case S_DECLS:
        for (const Node *d = n->a; d; d = d->next) gen_local_decl(d);
        break;
    case S_BLOCK:
        scope_push();
        for (const Node *s = n->a; s; s = s->next) gen_stmt(s);
        scope_pop();
        break;
    case S_IF:
        l_else = new_label();
        l_end = new_label();
        gen_expr(n->a);
        jump_if_zero(l_else);
        gen_stmt(n->b);
        ins("j .L%d", l_end);
        put_label(l_else);
        if (n->c) gen_stmt(n->c);
        put_label(l_end);
        break;
    case S_WHILE:
        l_cond = new_label();
        l_end = new_label();
        put_label(l_cond);
        gen_expr(n->a);
        jump_if_zero(l_end);
        push_loop(l_end, l_cond);
        gen_stmt(n->b);
        pop_loop();
        ins("j .L%d", l_cond);
        put_label(l_end);
        break;
    case S_DO:
        l_body = new_label();
        l_cont = new_label();
        l_end = new_label();
        put_label(l_body);
        push_loop(l_end, l_cont);
        gen_stmt(n->a);
        pop_loop();
        put_label(l_cont);
        gen_expr(n->b);
        jump_if_zero(l_end);
        ins("j .L%d", l_body);
        put_label(l_end);
        break;
    case S_FOR:
        l_cond = new_label();
        l_cont = new_label();
        l_end = new_label();
        if (n->a) gen_expr(n->a);
        put_label(l_cond);
        if (n->b) {
            gen_expr(n->b);
            jump_if_zero(l_end);
        }
        push_loop(l_end, l_cont);
        gen_stmt(n->d);
        pop_loop();
        put_label(l_cont);
        if (n->c) gen_expr(n->c);
        ins("j .L%d", l_cond);
        put_label(l_end);
        break;
    case S_SWITCH:
        gen_switch(n);
        break;
    case S_RETURN:
        if (n->a) {
            gen_expr(n->a);
            ins("mv a0, t0");
        }
        ins("j .L%d", ret_label);
        break;
    case S_BREAK:
        if (n_break == 0) fatal(n, "'break' outside of loop or switch");
        ins("j .L%d", break_stack[n_break - 1]);
        break;
    case S_CONTINUE:
        if (n_cont == 0) fatal(n, "'continue' outside of loop");
        ins("j .L%d", cont_stack[n_cont - 1]);
        break;
    default:
        fatal(n, "unsupported statement");
    }
}

/* ---------- functions and globals ---------- */
static void gen_function(const Node *f) {
    int nparams = 0;
    for (const Node *p = f->a; p; p = p->next) nparams++;
    if (nparams > 8) fatal(f, "functions with more than 8 parameters are not supported");

    int frame = 2 * W + (nparams + count_slots(f->b)) * W;
    frame = (frame + 15) & ~15;

    fprintf(out, "\n.global %s\n%s:\n", f->name, f->name);

    /* prologue */
    addi_any("sp", "sp", -frame);
    if (fits_imm12(frame)) {
        ins("%s ra, %d(sp)", STORE, frame - W);
        ins("%s s0, %d(sp)", STORE, frame - 2 * W);
        ins("addi s0, sp, %d", frame);
    } else {
        addi_any("t2", "sp", frame);
        ins("%s ra, %d(t2)", STORE, -W);
        ins("%s s0, %d(t2)", STORE, -2 * W);
        ins("mv s0, t2");
    }

    cur_off = 2 * W;
    ret_label = new_label();
    scope_push();

    /* store parameters from a0..a7 into their slots so &param has an address */
    int i = 0;
    for (const Node *p = f->a; p; p = p->next, i++) {
        int off = frame_alloc(1);
        sym_add(p, p->name, SYM_LOCAL, p->is_ptr, 0, off);
        frame_mem(STORE, ARG_REG[i], off);
    }

    gen_stmt(f->b);

    /* epilogue: restore sp from s0, unaffected by pending pushes */
    put_label(ret_label);
    ins("%s ra, %d(s0)", LOAD, -W);
    ins("mv t2, s0");
    ins("%s s0, %d(t2)", LOAD, -2 * W);
    ins("mv sp, t2");
    ins("jalr zero, 0(ra)");

    scope_pop();
}

static long const_value(const Node *e) {
    if (e->kind == E_NUM) return e->ival;
    if (e->kind == E_UNARY && e->op == '-' && e->a->kind == E_NUM) return -e->a->ival;
    fatal(e, "global initializer must be an integer constant");
    return 0;
}

static void gen_global(const Node *d) {
    int len = array_length(d);
    if (sym_lookup(d->name)) fatal(d, "redefinition of '%s'", d->name);
    sym_add(d, d->name, SYM_GLOBAL, d->is_ptr, len > 0, 0);

    fprintf(out, "\n.data\n.align %d\n%s:\n", W_SHIFT, d->name);
    int n = len ? len : 1, written = 0;
    if (d->b) {
        const Node *e = (len && d->b->kind == E_INITLIST) ? d->b->a : d->b;
        for (; e && written < n; e = len ? e->next : NULL, written++)
            ins("%s %ld", DATA_WORD, const_value(e));
    }
    if (written < n) ins(".zero %d", (n - written) * W);
    fprintf(out, ".text\n");
}

static void gen_program(const Node *root) {
    fprintf(out, ".text\n");
    for (const Node *n = root; n; n = n->next) {
        if (n->kind == D_FUNC) {
            Sym *s = sym_lookup(n->name);
            if (!s) sym_add(n, n->name, SYM_FUNC, n->is_ptr, 0, 0);
            if (n->b) gen_function(n);
        } else if (n->kind == S_DECLS) {
            for (const Node *d = n->a; d; d = d->next) gen_global(d);
        }
    }
}

/* ======================================================================
 * [5] main
 *   ./codegen < input.c            emit RV64 assembly (HW3)
 *   ./codegen --rv32 < input.c     emit RV32 assembly (HW3 Bonus)
 *   --pext-emulate                 testing: P-extension instructions become calls to __pext_<op>()
 *   the environment variable CODEGEN_TARGET=rv32 also works
 * ==================================================================== */
static void use_rv32(void) {
    W = 4;
    W_SHIFT = 2;
    LOAD = "lw";
    STORE = "sw";
    DATA_WORD = ".word";
}

int main(int argc, char **argv) {
    const char *target = getenv("CODEGEN_TARGET");
    if (target && strcmp(target, "rv32") == 0) use_rv32();
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--rv32") == 0) use_rv32();
        else if (strcmp(argv[i], "--rv64") == 0) { /* default */ }
        else if (strcmp(argv[i], "--pext-emulate") == 0) pext_emulate = 1;
        else { fprintf(stderr, "usage: %s [--rv32] [--pext-emulate] < input.c\n", argv[0]); return 1; }
    }

    yyparse();

    out = fopen("codegen.S", "w");
    if (!out) { perror("codegen.S"); return 1; }
    gen_program(program_root);
    fclose(out);
    return 0;
}
