#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h> // for open
#include <unistd.h> // for close

// Preprocessor lines are ignored by c4
// We use this to include c4-specific code.
#define int long long
#undef EOS

// Random C constants
enum {
  // false = 0,
  // true = 1,
  EOS = 256,
};

// These reimplement libc functions for c4, which has no libc. When compiling
// with a real C compiler, the #ifndef excludes them so the real libc versions
// are used. c4 ignores # directive lines but still compiles the bodies between
// them, so it always sees these definitions regardless of the guard.
#ifndef __STDC__
void memcpy(char *dest, char *src, int n) {
  int i;
  i = 0;
  while (i < n) {
    dest[i] = src[i];
    i = i + 1;
  }
}

int strlen(char *str) {
  int len;
  len = 0;
  while (str[len] != '\0') {
    len = len + 1;
  }
  return len;
}

char *strrchr(char *str, int c) {
  char *last;
  last = 0;
  while (*str != '\0') {
    if (*str == c) {
      last = str;
    }
    str = str + 1;
  }
  return last;
}
#endif

// State for the reader
//  - fd: current file pointer
//  - fd_filepath: path of the current file being read, used for error messages.
//  - fd_dirname: directory of the current file, used to resolve relative paths.
//  - include_search_path: search path for system include files.
//  - line_number: line number of the current file, used for error messages.
//  - column_number: column number of the current file, used for error messages.
//  - last_tok_line_number: line number of the last token read, used for error messages.
//  - last_tok_column_number: column number of the last token read, used for error messages.
//  - include_stack: the stack to save the state of the reader when including a file.

int fd; // Current file pointer that's being read
char* fd_filepath; // The path of the current file being read
char *fd_dirname; // The directory of the current file being read
char* include_search_path; // Search path for include files

int line_number;
int column_number;
int last_tok_line_number;
int last_tok_column_number;

// Enum for the include stack entries
enum {
  IS_FD = 0,
  IS_PATH,
  IS_DIR,
  IS_LINE,
  IS_COL,
  IS_SZ,
};

int *include_stack, *include_stack_start, *include_stack_end;

#ifndef __STDC__
int putchar(char c) {
  printf("%c", c);
}
#endif

void putstr(char *str) {
  while (*str) {
    putchar(*str);
    str = str + 1;
  }
}

void putint(int n) {
  printf("%d", n);
}

void source_code_error(char *error_prefix, char *error_msg, int token) {
  if (fd_filepath != 0) {
    printf("%s:%d:%d: ", fd_filepath, last_tok_line_number, last_tok_column_number);
  }
  printf("%s%s\n", error_prefix, error_msg);
  exit(1);
}

void fatal_error(char * msg) {
  if (fd_filepath != 0) {
    printf("%s:%d:%d: ", fd_filepath, last_tok_line_number, last_tok_column_number);
  }
  putstr(msg); putchar('\n');
  exit(1);
}

void syntax_error(char * msg) {
  source_code_error("Syntax error: ", msg, 0);
}

// Before including a file, we save the state of the reader to the include stack.
// This allows us to restore the previous file pointer and file name when we finish including the file.
void save_include_context() {
  if (include_stack >= include_stack_end - IS_SZ) fatal_error("Include stack overflow");

  if (fd != 0) {
    include_stack[IS_FD]   = (int)fd;
    include_stack[IS_PATH] = (int)fd_filepath;
    include_stack[IS_DIR]  = (int)fd_dirname;
    include_stack[IS_LINE] = (int)line_number;
    include_stack[IS_COL]  = (int)column_number;
    include_stack = include_stack + IS_SZ;
  }
}

void restore_include_context() {
  if (include_stack == include_stack_start) fatal_error("Include stack is empty");

  close(fd);
  if (fd_dirname != 0) free(fd_dirname);
  // We skip freeing the filepath because it may belong to the string pool

  include_stack = include_stack -IS_SZ;
  fd            = (int)   include_stack[IS_FD];
  fd_filepath   = (char*) include_stack[IS_PATH];
  fd_dirname    = (char*) include_stack[IS_DIR];
  line_number   = (int)   include_stack[IS_LINE];
  column_number = (int)   include_stack[IS_COL];
}

// Tokens and AST nodes
enum TOKEN {
  // C keywords
  KEYWORDS_START = 300,
  DEFINE_KW,
  DEFINED_KW,
  ELIF_KW,
  ELSE_KW,
  ENDIF_KW,
  ERROR_KW,
  IF_KW,
  IFDEF_KW,
  IFNDEF_KW,
  INCLUDE_KW,
  UNDEF_KW,
  WARNING_KW,
  KEYWORDS_END,

  // Non-character operands
  INTEGER   = 401, // Integer written in decimal
  CHARACTER = 410, // Fixed value so the ifdef above don't change the value
  STRING    = 411,

  AMP_AMP   = 450,
  AMP_EQ,
  ARROW,
  BAR_BAR,
  BAR_EQ,
  CARET_EQ,
  EQ_EQ,
  GT_EQ,
  LSHIFT_EQ,
  LSHIFT,
  LT_EQ,
  MINUS_EQ,
  MINUS_MINUS,
  EXCL_EQ,
  PERCENT_EQ,
  PLUS_EQ,
  PLUS_PLUS,
  RSHIFT_EQ,
  RSHIFT,
  SLASH_EQ,
  STAR_EQ,
  ELLIPSIS,
  MACRO_ARG = 499,
  IDENTIFIER = 500, // 500 because it's easy to remember
  MACRO = 501,

  LIST = 600, // List object
};

// tokenizer

int ch;
int tok;
int val;

// String pool for C keywords, identifiers and string literals
int string_pool_sz;
char *string_pool;
int string_pool_alloc;
int string_start;
int hash;

// These parameters give a perfect hashing of the C keywords
int hash_table_param;
int hash_table_prime;
// Some C implementations place globals on the stack, where size is limited.
int heap_size;
int *heap;
int heap_alloc;

int alloc_obj(int size) {

  if ((heap_alloc + size) > heap_size) {
    fatal_error("heap overflow");
  }

  heap_alloc = heap_alloc + size;

  return (heap_alloc - size);
}

int get_child(int node, int i) {
  return heap[node+i+1];
}

int cons(int child0, int child1)    {
  int res;
  res = alloc_obj(3);

  heap[res  ] = LIST + 2048;
  heap[res+1] = child0;
  heap[res+2] = child1;

  return res;
}

int car(int pair)                   { return get_child(pair, 0); }
int cdr(int pair)                   { return get_child(pair, 1); }
void set_cdr(int pair, int value)   { heap[pair+2] = value; }

// Symbol table and string pool management
// The symbol table is implemented as a chaining hash table.
// It is stored in the beginning of the heap array, with each top-level entry
// pointing to a linked list of symbols with the same hash value.
// The symbols themselves are stored in the heap after the hash table.
// Each symbol is represented as an object in the heap with the following layout:
//  - 0: pointer to next symbol in the chain (0 if last symbol)
//  - 1: offset in the string pool where the symbol's string is stored
//  - 2: length of the symbol's string
//  - 3: token type (IDENTIFIER, MACRO, other C keyword, etc.)
//  - 4: token tag (for macros)
char *symbol_buf(int symbol) {
  return string_pool + heap[symbol + 1];
}

int symbol_len(int symbol) {
  return heap[symbol + 2];
}

int symbol_type(int symbol) {
  return heap[symbol + 3];
}

void set_symbol_type(int symbol, int type) {
  heap[symbol + 3] = type;
}

int symbol_tag(int symbol) {
  return heap[symbol + 4];
}

void set_symbol_tag(int symbol, int tag) {
  heap[symbol + 4] = tag;
}

void begin_symbol() {
  string_start = string_pool_alloc;
  hash = 0;
}

// Append the current character (ch) to the string under construction in the pool
void accum_symbol_char(char c) {
  hash = (c + (hash ^ hash_table_param)) % hash_table_prime;
  string_pool[string_pool_alloc] = c;
  string_pool_alloc = string_pool_alloc + 1;
  if (string_pool_alloc >= string_pool_sz) {
    fatal_error("string pool overflow");
  }
}

int symbol;
char *symbol_end;
char *c1;
char *c2;
int end_symbol_len;
int curr_symbol;
int end_symbol() {
  end_symbol_len = string_pool_alloc - string_start; // exclude terminator
  string_pool[string_pool_alloc] = 0; // terminate string
  string_pool_alloc = string_pool_alloc + 1; // account for terminator

  curr_symbol = hash;

  while ((symbol = heap[curr_symbol]) != 0) {
    // Skip symbols with different length
    if (end_symbol_len != heap[symbol + 2]) {
      curr_symbol = symbol; // remember previous ident
      continue;
    }

    c1 = string_pool + string_start;
    c2 = string_pool + heap[symbol + 1];
    symbol_end = c1 + end_symbol_len;
    while (c1 < symbol_end && *c1 == *c2) {
      c1 = c1 + 1;
      c2 = c2 + 1;
    }

    if (c1 == symbol_end) {
      // Loop got to the end of the symbol without mismatches => symbol already exists.
      // Deallocate the string and return the existing symbol
      string_pool_alloc = string_start;
      return symbol;
    }

    curr_symbol = symbol; // remember previous ident
  }

  // the symbol was not found, create a new one
  symbol = alloc_obj(5);

  heap[curr_symbol] = symbol; // chain new symbol to the last symbol in the chain

  heap[symbol]     = 0;               // Next symbol in chain
  heap[symbol + 1] = string_start;    // Offset in string pool
  heap[symbol + 2] = end_symbol_len;  // Length of the symbol
  heap[symbol + 3] = IDENTIFIER;      // Token type
  heap[symbol + 4] = 0;               // Token tag

  return symbol;
}

void dump_string(char *prefix, char *str) {
  putstr(prefix);
  putchar('"');
  putstr(str);
  putchar('"');
  putchar('\n');
}

void dump_int(char *prefix, int n) {
  putstr(prefix);
  putint(n);
  putchar('\n');
}

void dump_char(int c) {
  dump_int("char = ", c);
}

void dump_tok(int tok) {
  dump_int("tok = ", tok);
}

// Stack of if macro states
int *if_macro_stack, *if_macro_stack_start, *if_macro_stack_end;
int if_macro_mask;     // Indicates if the current if/elif block is being executed
int if_macro_executed; // If any of the previous if/elif conditions were 1

enum {
  IF_MACRO_MASK = 0,
  IF_MACRO_EXECUTED = 1,
  IF_MACRO_SIZE = 2,
};

// get_tok parameters:
// Whether to expand macros or not.
// Useful to parse macro definitions containing other macros without expanding them.
int expand_macro;
// Don't produce newline tokens. Used when reading the tokens of a macro definition.
int skip_newlines;

int *macro_stack, *macro_stack_start, *macro_stack_end;

enum {
  MACRO_TOKS  = 0, // Current list of tokens to replay for the macro being expanded
  MACRO_ARGS  = 1, // Current list of arguments for the macro being expanded
  MACRO_SYM   = 2, // The identifier of the macro being expanded (if any)
  MACRO_SIZE  = 3,
};

int macro_tok_lst;    // Current list of tokens to replay for the macro being expanded
int macro_args;       // Current list of arguments for the macro being expanded
int macro_ident;      // The identifier of the macro being expanded (if any)
int macro_args_count; // Number of arguments for the current macro being expanded

int prev_macro_mask() {
  // Either at the end of the stack, or the previous entry is masked off.
  return if_macro_stack == if_macro_stack_start
      || (if_macro_stack - IF_MACRO_SIZE)[IF_MACRO_MASK] == 0;
}

void push_if_macro_mask(int new_mask) {
  if (if_macro_stack >= if_macro_stack_end - IF_MACRO_SIZE)
    fatal_error("Too many nested #ifdef/#ifndef directives. Maximum supported is 20.");

  // Save current mask on the stack because it's about to be overwritten
  if_macro_stack[IF_MACRO_MASK] = if_macro_mask;
  if_macro_stack[IF_MACRO_EXECUTED] = if_macro_executed;
  if_macro_stack = if_macro_stack + IF_MACRO_SIZE;

  // If the current block is masked off, then the new mask is the logical AND of the current mask and the new mask
  new_mask = if_macro_mask & new_mask;

  // Then set the new mask value and reset the executed flag
  if_macro_mask = if_macro_executed = new_mask;
}

void pop_if_macro_mask() {
  if (if_macro_stack == if_macro_stack_start)
    fatal_error("Unbalanced #ifdef/#ifndef/#else/#endif directives.");

  if_macro_stack = if_macro_stack - IF_MACRO_SIZE;
  if_macro_mask = if_macro_stack[IF_MACRO_MASK];
  if_macro_executed = if_macro_stack[IF_MACRO_EXECUTED];
}

void get_ch() {
  int c;
  c = read(fd, &ch, 1);

  if (c != 1) {
    // If it's not the last file on the stack, EOS means that we need to switch to the next file
    if (include_stack != include_stack_start) {
      restore_include_context();
      // EOS is treated as a newline so that files without a newline at the end are still parsed correctly
      // On the next get_ch call, the first character of the next file will be read
      ch = '\n';
    } else {
      // Reached the end of the top-level file: signal EOS so the tokenizer stops.
      ch = EOS;
    }
  }
  else if (ch == '\n') {
    line_number = line_number + 1;
    column_number = 0;
  } else {
    column_number = column_number + 1;
  }
}

void skip_to_end_of_line() {
  while (ch != '\n' && ch != EOS) {
    get_ch();
  }
}

int skip_inactive_line() {
  // If the line starts with #, it's potentially a preprocessor directive that
  // needs to be processed, return 1 in that case, 0 otherwise.
  // Note that this doesn't handle line continuations, but that's an acceptable
  // trade-off.

  // Skip whitespace
  while (ch <= ' ' && ch != EOS) {
    get_ch();
  }

  if (ch == '#' || ch == EOS) {
    return 1;
  } else {
    // Skip to the end of the line
    skip_to_end_of_line();
    return 0;
  }
}

char *substr(char *str, int len) {
  char *temp;
  temp = malloc(len + 1);
  memcpy(temp, str, len);
  temp[len] = '\0';
  return temp;
}

char *str_concat(char *s1, char *s2) {
  int s1_len;
  int s2_len;
  char *temp;
  s1_len = strlen(s1);
  s2_len = strlen(s2);
  temp = malloc(s1_len + s2_len + 1);

  memcpy(temp, s1, s1_len);
  memcpy(temp + s1_len, s2, s2_len);
  temp[s1_len + s2_len] = '\0';
  return temp;
}

// Removes the last component of the path, keeping the trailing slash if any.
// For example, /a/b/c.txt -> /a/b/
// If the path does not contain a slash, it returns "".
char *file_parent_directory(char *path) {
  char *last_slash;
  last_slash = strrchr(path, '/');
  if (last_slash == 0) {
    return 0;
  } else {
    return substr(path, last_slash - path + 1);
  }
}

void include_file(char *file_name, char *relative_to) {
  save_include_context();
  fd_filepath = file_name;
  if (relative_to) {
    fd_filepath = str_concat(relative_to, fd_filepath);
  }
  fd = open(fd_filepath, 0);
  if (fd == 0) {
    dump_string("#include ", fd_filepath);
    fatal_error("Could not open file");
  }

  fd_dirname = file_parent_directory(fd_filepath);
  line_number = 1;
  column_number = 0;
}

int accum_digit(int base) {
  int digit, MININT, limit;
  digit = 99;
  MININT = -2147483648;
  if ('0' <= ch && ch <= '9') {
    digit = ch - '0';
  } else if ('A' <= ch && ch <= 'Z') {
    digit = ch - 'A' + 10;
  } else if ('a' <= ch && ch <= 'z') {
    digit = ch - 'a' + 10;
  }
  if (digit >= base) {
    return 0; // character is not a digit in that base
  } else {
    limit = MININT / base;
    if (base == 10 && if_macro_mask && ((val < limit) || ((val == limit) && (digit > limit * base - MININT)))) {
      syntax_error("literal integer overflow");
    }

    val = val * base - digit;
    get_ch();
    return 1;
  }
}

void get_string_char() {

  val = ch;
  get_ch();

  if (val == '\\') {
    if ('0' <= ch && ch <= '7') {
      // Parse octal character, up to 3 digits.
      // Note that \1111 is parsed as '\111' followed by '1'
      // See https://en.wikipedia.org/wiki/Escape_sequences_in_C#Notes
      val = 0;
      accum_digit(8);
      accum_digit(8);
      accum_digit(8);
      val = (-val % 256); // keep low 8 bits, without overflowing
    } else if (ch == 'x' || ch == 'X') {
      get_ch();
      val = 0;
      // Allow 1 or 2 hex digits.
      if (accum_digit(16)) {
        accum_digit(16);
      } else {
        syntax_error("invalid hex escape -- it must have at least one digit");
      }
      val = (-val % 256); // keep low 8 bits, without overflowing
    } else {
      if (ch == 'a') {
        val = 7;
      } else if (ch == 'b') {
        val = 8;
      } else if (ch == 'f') {
        val = 12;
      } else if (ch == 'n') {
        val = 10;
      } else if (ch == 'r') {
        val = 13;
      } else if (ch == 't') {
        val = 9;
      } else if (ch == 'v') {
        val = 11;
      } else if (ch == '\\' || ch == '\'' || ch == '\"') {
        val = ch;
      } else {
        syntax_error("unimplemented string character escape");
      }
      get_ch();
    }
  }
}

void accum_string_until(char end) {
  while (ch != end && ch != EOS) {
    get_string_char();
    accum_symbol_char(val);
  }
  if (ch != end) {
    syntax_error("unterminated string literal");
  }

  get_ch();
}

// Macros that are defined by the preprocessor
int FILE__ID;
int LINE__ID;

void get_tok();

// When we parse a macro, we generally want the tokens as they are, without
// expanding them. When force_newlines is set, newline tokens are produced. This
// is used to end preprocessor directives.
void get_tok_macro(int force_newlines) {
  int prev_expand_macro;
  int prev_macro_mask;
  int skip_newlines_prev;
  prev_expand_macro = expand_macro;
  prev_macro_mask = if_macro_mask;
  skip_newlines_prev = skip_newlines;

  expand_macro = 0;
  if_macro_mask = 1;
  if (force_newlines) skip_newlines = 0;
  get_tok();
  expand_macro = prev_expand_macro;
  if_macro_mask = prev_macro_mask;
  skip_newlines = skip_newlines_prev;
}

int lookup_macro_token(int args, int tok, int val) {
  int ix;
  ix = 0;

  if (tok < IDENTIFIER) return cons(tok, val); // Not an identifier

  while (args != 0) {
    if (car(args) == val) break; // Found!
    args = cdr(args);
    ix = ix + 1;
  }

  if (args == 0) { // Identifier is not a macro argument
    return cons(tok, val);
  } else {
    return cons(MACRO_ARG, ix);
  }
}

int read_macro_tokens(int args) {
  int toks, rest; // List of token to replay
  toks = 0;

  // Accumulate tokens so they can be replayed when the macro is used
  if (tok != '\n' && tok != EOS) {
    // Append the token/value pair to the replay list
    toks = cons(lookup_macro_token(args, tok, val), 0);
    rest = toks;
    get_tok_macro(1);
    while (tok != '\n' && tok != EOS) {
      set_cdr(rest, cons(lookup_macro_token(args, tok, val), 0));
      rest = cdr(rest); // Advance tail
      get_tok_macro(1);
    }
  }

  return toks;
}

// A few things that are different from the standard:
// - We allow sequence of commas in the argument list
// - Function-like macros with 0 arguments can be called either without parenthesis or with ().
// - No support for variadic macros. Tcc only uses them in tests so it should be ok.
void handle_define() {
  int macro;      // The identifier that is being defined as a macro
  int args;       // List of arguments for a function-like macro
  int args_count; // Number of arguments for a function-like macro. -1 means it's an object-like macro
  args = 0;
  args_count = -1;

  if (tok != IDENTIFIER && tok != MACRO && (tok < KEYWORDS_START || tok > KEYWORDS_END)) {
    dump_tok(tok);
    syntax_error("#define directive can only be followed by a identifier");
  }

  set_symbol_type(val, MACRO); // Mark the identifier as a macro
  macro = val;
  if (ch == '(') { // Function-like macro
    args_count = 0;
    get_tok_macro(1); // Skip macro name
    get_tok_macro(1); // Skip '('
    while (tok != '\n' && tok != EOS) {
      if (tok == ',') {
        // Allow sequence of commas, this is more lenient than the standard
        get_tok_macro(1);
        continue;
      } else if (tok == ')') {
        get_tok_macro(1);
        break;
      }
      get_tok_macro(1);
      // Accumulate parameters in reverse order. That's ok because the arguments
      // to the macro will also be in reverse order.
      args = cons(val, args);
      args_count = args_count + 1;
    }
  } else {
    get_tok_macro(1); // Skip macro name
  }

  // Accumulate tokens so they can be replayed when the macro is used
  set_symbol_tag(macro, cons(read_macro_tokens(args), args_count));
}

int parse_expression();

int evaluate_if_condition() {
  int prev_skip_newlines;
  int previous_mask;
  int result;
  prev_skip_newlines = skip_newlines;
  previous_mask = if_macro_mask;
  // Temporarily set to 1 so that we can read the condition even if it's inside an ifdef 0 block
  // Unlike in other directives using get_tok_macro, we want to expand macros in the condition
  if_macro_mask = 1;
  skip_newlines = 0; // We want to stop when we reach the first newline
  get_tok(); // Skip the #if keyword
  result = parse_expression();

  // Restore the previous value
  if_macro_mask = previous_mask;
  skip_newlines = prev_skip_newlines;
  return result;
}

// Return whether the include was a system include or not
void handle_include() {
  char *buf;
  if (tok == STRING) {
    buf = symbol_buf(val);
    include_file(buf, fd_dirname);
    get_tok_macro(1); // Skip the string
  } else if (tok == '<') {
    accum_string_until('>');
    val = end_symbol();
    // #include <file> directives only take effect if the search path is provided
    // TODO: Issue a warning to stderr when skipping the directive
    if (include_search_path != 0) {
      buf = symbol_buf(val);
      include_file(buf, include_search_path);
    }
    get_tok_macro(1); // Skip the string
  } else {
    dump_tok(tok);
    syntax_error("expected string to #include directive");
  }
}

// Handles preprocessor directives
void handle_preprocessor_directive() {
  int temp;
  while (1) {
    get_tok_macro(1); // Get the # token
    get_tok_macro(1); // Get the directive

    if (tok == IFDEF_KW || tok == IFNDEF_KW) {
      temp = tok;
      get_tok_macro(1); // Get the macro name
      if (temp == IFDEF_KW) {
        push_if_macro_mask(tok == MACRO);
      } else {
        push_if_macro_mask(tok != MACRO);
      }
      get_tok_macro(1); // Skip the macro name
    } else if (tok == IF_KW) {
      temp = evaluate_if_condition();
      push_if_macro_mask(temp != 0);
    } else if (tok == ELIF_KW) {
      temp = evaluate_if_condition() ;
      if (prev_macro_mask() && !if_macro_executed) {
        if_macro_mask = temp != 0;
        if_macro_executed = if_macro_executed | if_macro_mask;
      } else {
        if_macro_mask = 0;
      }
    } else if (tok == ELSE_KW) {
      if (prev_macro_mask()) { // If the parent block mask is 1
        if_macro_mask = !if_macro_executed;
        if_macro_executed = 1;
      } else {
        if_macro_mask = 0;
      }
      get_tok_macro(1); // Skip the else keyword
    } else if (tok == ENDIF_KW) {
      pop_if_macro_mask();
      get_tok_macro(1); // Skip the else keyword
    } else if (if_macro_mask) {
      if (tok == INCLUDE_KW) {
        get_tok_macro(1); // Get the STRING token
        handle_include();
      }
      else if (tok == UNDEF_KW) {
        get_tok_macro(1); // Get the macro name
        if (tok == IDENTIFIER || tok == MACRO) {
          set_symbol_type(val, IDENTIFIER); // Unmark the macro
          get_tok_macro(1); // Skip the macro name
        } else {
          dump_tok(tok);
          syntax_error("#undef directive can only be followed by a identifier");
        }
      } else if (tok == DEFINE_KW) {
        get_tok_macro(1); // Get the macro name
        handle_define();
      }
      else if (tok == WARNING_KW || tok == ERROR_KW) {
        temp = tok;
        if (temp == WARNING_KW) {
          putstr("warning: ");
        } else {
          putstr("error: ");
        }
        // Print the rest of the line, it does not support \ at the end of the line but that's ok
        while (ch != '\n' && ch != EOS) {
          putchar(ch); get_ch();
        }
        putchar('\n');
        tok = '\n';
        if (temp == ERROR_KW) exit(1);
      }
      else {
        dump_tok(tok);
        dump_string("directive = ", symbol_buf(val));
        syntax_error("unsupported preprocessor directive");
      }
    } else {
      // Skip the rest of the directive
      while (tok != '\n' && tok != EOS) get_tok_macro(1);
    }

    if (tok != '\n' && tok != EOS) {
      dump_tok(tok);
      if (tok == IDENTIFIER || tok == MACRO) {
        dump_string("directive = ", symbol_buf(val));
      }
      syntax_error("preprocessor expected end of line");
    }

    // When if_macro_mask is 0, skip ahead until the next directive
    if (!if_macro_mask) {
      while (!skip_inactive_line());
      if (ch == EOS) return;
      tok = '#';
    } else {
      break; // Return to normal processing
    }
  }
}

void get_ident() {

  begin_symbol();

  while (('A' <= ch && ch <= 'Z') ||
         ('a' <= ch && ch <= 'z') ||
         ('0' <= ch && ch <= '9') ||
         (ch == '_')) {
    accum_symbol_char(ch);
    get_ch();
  }

  val = end_symbol();
  tok = symbol_type(val);
}

int intern_str(char* name) {
  begin_symbol();

  while (*name != 0) {
    accum_symbol_char(*name);
    name = name + 1;
  }

  return end_symbol();
}

int init_ident(int tok, char * name) {
  int i;
  i = intern_str(name);
  set_symbol_type(i, tok);
  return i;
}

void init_ident_table() {
  int i;
  i = 0;

  while (i < hash_table_prime) {
    heap[i] = 0;
    i = i + 1;
  }
  init_ident(DEFINE_KW, "define");
  init_ident(DEFINED_KW, "defined");
  init_ident(ELIF_KW, "elif");
  init_ident(ELSE_KW, "else");
  init_ident(ENDIF_KW, "endif");
  init_ident(ERROR_KW, "error");
  init_ident(IF_KW, "if");
  init_ident(IFDEF_KW, "ifdef");
  init_ident(IFNDEF_KW, "ifndef");
  init_ident(INCLUDE_KW, "include");
  init_ident(UNDEF_KW, "undef");
  init_ident(WARNING_KW, "warning");
}

int set_builtin_string_macro(int macro_id, int value_symb) {
  // Macro object shape: ([(tok, val)], arity). -1 arity means it's an object-like macro
  set_symbol_tag(macro_id, cons(cons(cons(STRING, value_symb), 0), -1));
  return macro_id;
}

int init_builtin_string_macro(char *macro_str, char* value) {
  return set_builtin_string_macro(init_ident(MACRO, macro_str), intern_str(value));
}

int set_builtin_int_macro(int macro_id, int value) {
  set_symbol_tag(macro_id, cons(cons(cons(INTEGER, -value), 0), -1));
  return macro_id;
}

int init_builtin_int_macro(char *macro_str, int value) {
  return set_builtin_int_macro(init_ident(MACRO, macro_str), value);
}

void init_builtin_macros() {
  init_builtin_string_macro("__DATE__", "Jan  1 1970");
  init_builtin_string_macro("__TIME__", "00:00:00");
  init_builtin_string_macro("__TIMESTAMP__", "Jan  1 1970 00:00:00");
  FILE__ID = init_builtin_string_macro("__FILE__", "<unknown>");
  LINE__ID = init_builtin_int_macro("__LINE__", 0);
}

// A macro argument is represented using a list of tokens.
// Macro arguments are split by commas, but commas can also appear in function
// calls and as operators. To distinguish between the two, we need to keep track
// of the parenthesis depth.
int macro_parse_argument() {
  int arg_tokens;
  int parens_depth;
  int rest;
  arg_tokens = 0;
  parens_depth = 0;

  while ((parens_depth > 0 || (tok != ',' && tok != ')')) && tok != EOS) {
    parens_depth = parens_depth + (tok == '(') - (tok == ')');

    if (arg_tokens == 0) {
      arg_tokens = cons(cons(tok, val), 0);
      rest = arg_tokens;
    } else {
      set_cdr(rest, cons(cons(tok, val), 0));
      rest = cdr(rest);
    }
    get_tok_macro(0);
  }

  return arg_tokens;
}

void check_macro_arity(int macro_args_count, int macro) {
  int expected_argc;
  expected_argc = cdr(symbol_tag(macro));
  if (macro_args_count != expected_argc) {
    dump_int("expected_argc = ", expected_argc);
    dump_int("macro_args_count = ", macro_args_count);
    dump_string("macro = ", symbol_buf(macro));
    syntax_error("macro argument count mismatch");
  }
}

// Reads the arguments of a macro call, where the arguments are split by commas.
// Note that args are accumulated in reverse order, as the macro arguments refer
// to the tokens in reverse order.
int get_macro_args_toks(int macro) {
  int args;
  int macro_args_count;
  int prev_is_comma;
  args = 0;
  macro_args_count = 0;
  prev_is_comma = tok == ',';
  get_tok_macro(0); // Skip '('

  while (tok != ')' && tok != EOS) {
    if (tok == ',') {
      get_tok_macro(0); // Skip comma
      if (prev_is_comma) { // Push empty arg
        args = cons(0, args);
        macro_args_count = macro_args_count + 1;
      }
      prev_is_comma = 1;
      continue;
    } else {
      prev_is_comma = 0;
    }

    args = cons(macro_parse_argument(), args);
    macro_args_count = macro_args_count + 1;
  }

  if (tok != ')') syntax_error("unterminated macro argument list");

  if (prev_is_comma) {
    args = cons(0, args); // Push empty arg
    macro_args_count = macro_args_count + 1;
  }

  check_macro_arity(macro_args_count, macro);

  return args;
}

int get_macro_arg(int ix) {
  int arg;
  arg = macro_args;
  while (ix > 0) {
    if (arg == 0) fatal_error("get_macro_arg: argument index out of range");
    arg = cdr(arg);
    ix = ix - 1;
  }
  return car(arg);
}

// "Pops" the current macro expansion and restores the previous macro expansion context.
// This is done when the current macro expansion is done.
void return_to_parent_macro() {
  if (macro_stack == macro_stack_start) fatal_error("return_to_parent_macro: no parent macro");

  macro_stack = macro_stack - MACRO_SIZE;
  macro_tok_lst   = macro_stack[MACRO_TOKS];
  macro_args      = macro_stack[MACRO_ARGS];
  macro_ident     = macro_stack[MACRO_SYM];
}

// Begins a new macro expansion context, saving the current context onn the macro stack.
// Takes as argument the name of the macro, the tokens to be expanded and the arguments.
void begin_macro_expansion(int ident, int tokens, int args) {
  if (macro_stack >= macro_stack_end - MACRO_SIZE)
    fatal_error("Macro recursion depth exceeded.");


  macro_stack[MACRO_TOKS] = macro_tok_lst;
  macro_stack[MACRO_ARGS] = macro_args;
  macro_stack[MACRO_SYM]  = macro_ident;
  macro_stack = macro_stack + MACRO_SIZE;

  macro_ident   = ident;
  macro_tok_lst = tokens;
  macro_args    = args;
}

// Undoes the effect of get_tok by replacing the current token with the previous
// token and saving the current token to be returned by the next call to get_tok.
void undo_token(int prev_tok, int prev_val) {
  begin_macro_expansion(0, cons(cons(tok, val), 0), 0); // Push the current token back
  tok = prev_tok;
  val = prev_val;
}

// Try to expand a macro and returns if the macro was expanded.
// A macro is not expanded if it is already expanding or if it's a function-like
// macro that is not called with parenthesis. In that case, the macro identifier
// is returned as a normal identifier.
// If the wrong number of arguments is passed to a function-like macro, a fatal error is raised.
int attempt_macro_expansion(int macro) {
  // We must save the tokens because the macro may be redefined while reading the arguments
  int tokens;
  tokens = car(symbol_tag(macro));

  if (cdr(symbol_tag(macro)) == -1) { // Object-like macro
    // Note: Redefining __{FILE,LINE}__ macros, either with the #define or #line directives is not supported.
    if (macro == FILE__ID) {
      tokens = cons(cons(STRING, intern_str(fd_filepath)), 0);
    }
    else if (macro == LINE__ID) {
      tokens = cons(cons(INTEGER, -line_number), 0);
    }
    begin_macro_expansion(macro, tokens, 0);
    return 1;
  } else { // Function-like macro
    get_tok(); // Skip the macro identifier
    if (tok == '(') {
      begin_macro_expansion(macro, tokens, get_macro_args_toks(macro));
      return 1;
    } else {
      undo_token(IDENTIFIER, macro);
      return 0;
    }
  }
}

void get_tok() {
  int prev_tok_line_number;
  int prev_tok_column_number;

  prev_tok_line_number = line_number;
  prev_tok_column_number = column_number;

  while (1) {
    // Check if there are any tokens to replay. Macros are just identifiers that
    // have been marked as macros. In terms of how we get into that state, a
    // macro token is first returned by the get_ident call a few lines below.
    if (macro_tok_lst != 0) {
      tok = car(car(macro_tok_lst));
      val = cdr(car(macro_tok_lst));
      macro_tok_lst = cdr(macro_tok_lst);
      // Tokens that are identifiers and up are tokens whose kind can change
      // between the moment the macro is defined and where it is used.
      // So we reload the kind from the ident table.
      if (tok >= IDENTIFIER) tok = symbol_type(val);

      if (tok == MACRO) { // Nested macro expansion!
        if (attempt_macro_expansion(val)) {
          continue;
        }
        break;
      } else if (tok == MACRO_ARG) {
        begin_macro_expansion(0, get_macro_arg(val), 0); // Play the tokens of the macro argument
        continue;
      }
      break;
    } else if (macro_stack != macro_stack_start) {
      return_to_parent_macro();
      continue;
    } else if (ch <= ' ' || ch == EOS) {

      if (ch == EOS) {
        tok = EOS;
        break;
      }

      // skip whitespace, detecting when it is at start of line.
      // When skip_newlines is 0, produces a '\n' token whenever it
      // encounters whitespace containing at least a newline.
      // This condenses multiple newlines into a single '\n' token and serves
      // to end the current preprocessor directive.

      tok = 0; // Reset the token
      while (ch <= ' ' && ch != EOS) {
        if (ch == '\n') tok = ch;
        get_ch();
      }

      if (tok == '\n' && !skip_newlines) {
        // If the newline is followed by a #, the preprocessor directive is
        // handled in the next iteration of the loop.
        break;
      }

      // will continue while (1) loop
    }

    // detect '#' at start of line, possibly preceded by whitespace
    else if (tok == '\n' && ch == '#') {
      tok = 0; // Consume the newline so handle_preprocessor_directive's get_tok doesn't re-enter this case
      handle_preprocessor_directive();
      // will continue while (1) loop
    }

    else if (('a' <= ch && ch <= 'z') ||
              ('A' <= ch && ch <= 'Z') ||
              (ch == '_')) {

      get_ident();

      if (tok == MACRO) {
        // We only expand the macro if expand_macro is 1. Since this is the
        // base case of the macro expansion, we don't need to disable the other
        // places where macro expansion is done.
        if (expand_macro) {
          if (attempt_macro_expansion(val)) {
            continue;
          }
          break;
        }
      }
      break;
    } else if ('0' <= ch && ch <= '9') {

      val = 0;

      tok = INTEGER;
      if (ch == '0') { // val == 0 <=> ch == '0'
        get_ch();
        if (ch == 'x' || ch == 'X') {
          get_ch();
          if (accum_digit(16)) {
            while (accum_digit(16));
          } else {
            syntax_error("invalid hex integer -- it must have at least one digit");
          }
        } else {
          while (accum_digit(8));
        }
      } else {
        while (accum_digit(10));
      }

      break;

    } else if (ch == '\'') {

      get_ch();
      get_string_char();

      if (ch != '\'') {
        syntax_error("unterminated character literal");
      }

      get_ch();

      tok = CHARACTER;

      break;

    } else if (ch == '\"') {

      get_ch();

      begin_symbol();
      accum_string_until('\"');

      val = end_symbol();
      tok = STRING;

      break;

    } else {

      tok = ch; // fallback for single char tokens

      if (ch == '/') {

        get_ch();
        if (ch == '*') {
          get_ch();
          tok = ch; // remember previous char, except first one
          while ((tok != '*' || ch != '/') && ch != EOS) {
            tok = ch;
            get_ch();
          }
          if (ch == EOS) {
            syntax_error("unterminated comment");
          }
          get_ch();
          // will continue while (1) loop
        } else if (ch == '/') {
          skip_to_end_of_line();
          // will continue while (1) loop
        } else {
          if (ch == '=') {
            get_ch();
            tok = SLASH_EQ;
          }
          break;
        }

      } else if (ch == '&') {

        get_ch();
        if (ch == '&') {
          get_ch();
          tok = AMP_AMP;
        } else if (ch == '=') {
          get_ch();
          tok = AMP_EQ;
        }

        break;

      } else if (ch == '|') {

        get_ch();
        if (ch == '|') {
          get_ch();
          tok = BAR_BAR;
        } else if (ch == '=') {
          get_ch();
          tok = BAR_EQ;
        }

        break;

      } else if (ch == '<') {

        get_ch();
        if (ch == '=') {
          get_ch();
          tok = LT_EQ;
        } else if (ch == '<') {
          get_ch();
          if (ch == '=') {
            get_ch();
            tok = LSHIFT_EQ;
          } else {
            tok = LSHIFT;
          }
        }

        break;

      } else if (ch == '>') {

        get_ch();
        if (ch == '=') {
          get_ch();
          tok = GT_EQ;
        } else if (ch == '>') {
          get_ch();
          if (ch == '=') {
            get_ch();
            tok = RSHIFT_EQ;
          } else {
            tok = RSHIFT;
          }
        }

        break;

      } else if (ch == '=') {

        get_ch();
        if (ch == '=') {
          get_ch();
          tok = EQ_EQ;
        }

        break;

      } else if (ch == '!') {

        get_ch();
        if (ch == '=') {
          get_ch();
          tok = EXCL_EQ;
        }

        break;

      } else if (ch == '+') {

        get_ch();
        if (ch == '=') {
          get_ch();
          tok = PLUS_EQ;
        } else if (ch == '+') {
          get_ch();
          tok = PLUS_PLUS;
        }

        break;

      } else if (ch == '-') {

        get_ch();
        if (ch == '=') {
          get_ch();
          tok = MINUS_EQ;
        }
        else if (ch == '>') {
          get_ch();
          tok = ARROW;
        }
        else if (ch == '-') {
          get_ch();
          tok = MINUS_MINUS;
        }

        break;

      } else if (ch == '*') {

        get_ch();
        if (ch == '=') {
          get_ch();
          tok = STAR_EQ;
        }

        break;

      } else if (ch == '%') {

        get_ch();
        if (ch == '=') {
          get_ch();
          tok = PERCENT_EQ;
        }

        break;

      } else if (ch == '^') {

        get_ch();
        if (ch == '=') {
          get_ch();
          tok = CARET_EQ;
        }

        break;

      } else if (ch == '#') {

        get_ch();

        break;

      }
      else if (ch == '.') {
        get_ch();
        if (ch == '.') {
          get_ch();
          if (ch == '.') {
            get_ch();
            tok = ELLIPSIS;
          } else {
            dump_char(ch);
            syntax_error("invalid token");
          }
        }
        break;
      }
      else if (ch == '~' || ch == '.' || ch == '?' || ch == ',' || ch == ':' || ch == ';' || ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}') {

        get_ch();

        break;

      } else if (ch == '\\') {
        get_ch();

        if (ch == '\n') { // Continues with next token
          get_ch();
        } else {
          dump_char(ch);
          syntax_error("unexpected character after backslash");
        }
      } else {
        dump_char(ch);
        syntax_error("invalid token");
      }
    }
  }

  last_tok_line_number = prev_tok_line_number;
  last_tok_column_number = prev_tok_column_number;
}

// parser

void expect_tok(int expected_tok) {
  if (tok != expected_tok) {
    dump_int("expected tok = ", expected_tok);
    dump_int("current tok = ", tok);
    syntax_error("unexpected token");
  }
  get_tok();
}

int parse_expression();

int parse_primary_expression() {
  int result;

  if      (tok == CHARACTER)  { result = val; }
  else if (tok == INTEGER)    { result = -val; }
  else                        { syntax_error("literal expected"); }

  get_tok();
  return result;
}

int parse_unary_expression() {
  if (tok == '+') {
    get_tok();
    return parse_unary_expression();
  } else if (tok == '-') {
    get_tok();
    return - parse_unary_expression();
  } else if (tok == '~') {
    get_tok();
    return ~ parse_unary_expression();
  } else if (tok == '!') {
    get_tok();
    return ! parse_unary_expression();
  } else {
    return parse_primary_expression();
  }
}

int parse_multiplicative_expression() {
  int result;
  int op;
  result = parse_unary_expression();

  while (tok == '*' || tok == '/' || tok == '%') {
    op = tok;
    get_tok();

    if (op == '*')       result = result * parse_unary_expression();
    else if (op == '/')  result = result / parse_unary_expression();
    else                 result = result % parse_unary_expression();

  }

  return result;
}

int parse_additive_expression() {
  int result;
  int op;
  result = parse_multiplicative_expression();

  while (tok == '+' || tok == '-') {
    op = tok;
    get_tok();

    if (op == '+') result = result + parse_multiplicative_expression();
    else           result = result - parse_multiplicative_expression();
  }

  return result;
}

int parse_shift_expression() {
  int result;
  int op;
  result = parse_additive_expression();

  while (tok == LSHIFT || tok == RSHIFT) {
    op = tok;
    get_tok();
    if (op == LSHIFT) result = result << parse_additive_expression();
    else              result = result >> parse_additive_expression();
  }

  return result;
}

int parse_relational_expression() {
  int result;
  int op;
  result = parse_shift_expression();

  while (tok == '<' || tok == '>' || tok == LT_EQ || tok == GT_EQ) {
    op = tok;
    get_tok();

    if (op == '<')        result = result < parse_shift_expression();
    else if (op == '>')   result = result > parse_shift_expression();
    else if (op == LT_EQ) result = result <= parse_shift_expression();
    else                  result = result >= parse_shift_expression();
  }

  return result;
}

int parse_equality_expression() {
  int result;
  int op;
  result = parse_relational_expression();

  while (tok == EQ_EQ || tok == EXCL_EQ) {
    op = tok;
    get_tok();
    if (op == EQ_EQ) result = result == parse_relational_expression();
    else             result = result != parse_relational_expression();
  }

  return result;
}

int parse_AND_expression() {
  int result;
  result = parse_equality_expression();

  while (tok == '&') {
    get_tok();
    result = result & parse_equality_expression();
  }

  return result;
}

int parse_exclusive_OR_expression() {
  int result;
  result = parse_AND_expression();

  while (tok == '^') {
    get_tok();
    result = result ^ parse_AND_expression();
  }

  return result;
}

int parse_inclusive_OR_expression() {
  int result;
  result = parse_exclusive_OR_expression();

  while (tok == '|') {
    get_tok();
    result = result | parse_exclusive_OR_expression();
  }

  return result;
}

int parse_logical_AND_expression() {
  int result;
  result = parse_inclusive_OR_expression();

  while (tok == AMP_AMP) {
    get_tok();
    // Use non-short-circuiting behavior for the preprocessor expression
    // evaluation because we're parsing as we evaluate and can't lazily parse
    // the right-hand side.
    result = result & parse_inclusive_OR_expression();
  }

  return result;
}

int parse_logical_OR_expression() {
  int result;
  result = parse_logical_AND_expression();

  while (tok == BAR_BAR) {
    get_tok();
    // Use non-short-circuiting behavior for the preprocessor expression
    // evaluation because we're parsing as we evaluate and can't lazily parse
    // the right-hand side.
    result = result | parse_logical_AND_expression();
  }

  return result;
}

int parse_conditional_expression() {
  int result;
  result = parse_logical_OR_expression();

  if (tok == '?') {
    get_tok();
    if (parse_expression() == 0) {
      parse_conditional_expression();          // Skip the true branch
      expect_tok(':');
      result = parse_conditional_expression(); // Evaluate the false branch
    } else {
      result = parse_conditional_expression(); // Evaluate the true branch
      expect_tok(':');
      parse_conditional_expression();          // Skip the false branch
    }
  }

  return result;
}

int parse_expression() {
  return parse_conditional_expression();
}

void print_string_char(int c) {
  if (c == 7)       putstr("\\a");
  else if (c == 8)  putstr("\\b");
  else if (c == 12) putstr("\\f");
  else if (c == 10) putstr("\\n");
  else if (c == 13) putstr("\\r");
  else if (c == 9)  putstr("\\t");
  else if (c == 11) putstr("\\v");
  else if (c == '\\' || c == '\'' || c == '"') { putchar('\\'); putchar(c); }
  else if (c < 32 || c > 126) { putchar('\\'); putint(c >> 6); putint((c >> 3) & 7); putint(c & 7); }
  else putchar(c);
}

void print_tok_string(int symbol) {
  char *string_start;
  char *string_end;
  string_start = symbol_buf(symbol);
  string_end = string_start + symbol_len(symbol);

  while (string_start < string_end) {
    print_string_char(*string_start);
    string_start = string_start + 1;
  }
}

int print_tok_indent_level;
int print_tok_preceding_nl_count;
void print_tok_indent() {
  int i;
  i = 0;
  while (i < print_tok_indent_level) {
    putchar(' ');
    i = i + 1;
  }
}

void print_tok(int tok, int val) {
    // print_tok treats '{', '}' and '\n' specially:
  // - '{' increases the indent level by 2
  // - '}' decreases the indent level by 2
  // - '\n' prints a newline and increments print_tok_preceding_nl_count

  // When print_tok_preceding_nl_count is not 0, print_tok_indent is called
  // before printing the token This ensures that tokens are properly indented
  // after a newline.

  if (tok == '\n') {
    if (print_tok_preceding_nl_count >= 2) return; // Skip consecutive newlines
    print_tok_preceding_nl_count = print_tok_preceding_nl_count + 1;
    putchar('\n');
    return;
  } else if (tok == '{') {
    print_tok_indent();
    putchar(tok);
    print_tok_indent_level = print_tok_indent_level + 2;
    return;
  } else if (tok == '}') {
    print_tok_indent_level = print_tok_indent_level - 2;
    print_tok_indent();
    putchar(tok);
    return;
  }

  if (print_tok_preceding_nl_count != 0) {
    print_tok_indent();
    print_tok_preceding_nl_count = 0;
  }

  if ((KEYWORDS_START <= tok && tok <= KEYWORDS_END) || tok == IDENTIFIER) {
    putstr(symbol_buf(val));
  }
  else if (tok == AMP_AMP)      putstr("&&");
  else if (tok == AMP_EQ)       putstr("&=");
  else if (tok == BAR_BAR)      putstr("||");
  else if (tok == BAR_EQ)       putstr("|=");
  else if (tok == CARET_EQ)     putstr("^=");
  else if (tok == EQ_EQ)        putstr("==");
  else if (tok == GT_EQ)        putstr(">=");
  else if (tok == LSHIFT_EQ)    putstr("<<=");
  else if (tok == LSHIFT)       putstr("<<");
  else if (tok == LT_EQ)        putstr("<=");
  else if (tok == MINUS_EQ)     putstr("-=");
  else if (tok == MINUS_MINUS)  putstr("--");
  else if (tok == EXCL_EQ)      putstr("!=");
  else if (tok == PERCENT_EQ)   putstr("%=");
  else if (tok == PLUS_EQ)      putstr("+=");
  else if (tok == RSHIFT_EQ)    putstr(">>=");
  else if (tok == RSHIFT)       putstr(">>");
  else if (tok == SLASH_EQ)     putstr("/=");
  else if (tok == STAR_EQ)      putstr("*=");
  else if (tok == PLUS_PLUS)    putstr("++");
  else if (tok == MINUS_MINUS)  putstr("--");
  else if (tok == ELLIPSIS)     putstr("...");
  else if (tok == INTEGER)      putint(-val);
  else if (tok == CHARACTER) {
    putchar('\'');
    print_string_char(val);
    putchar('\'');
  } else if (tok == STRING) {
    putchar('"');
    print_tok_string(val);
    putchar('"');
  } else {
    putchar(tok);
  }

  if (tok != '\n') putchar(' ');
}

int main(int argc, char **argv) {
  int i;

  fd = 0; // Current file pointer that's being read
  fd_filepath = 0; // The path of the current file being read
  fd_dirname = 0; // The directory of the current file being read
  include_search_path = 0; // Search path for include files

  line_number = 1;
  column_number = 0;
  last_tok_line_number = 1;
  last_tok_column_number = 0;

  print_tok_indent_level = 0;
  print_tok_preceding_nl_count = 0;

  hash_table_param = 1026;
  hash_table_prime = 1009;

  include_stack = include_stack_start = malloc(30 * IS_SZ * sizeof(int));
  include_stack_end = include_stack_start + 30 * IS_SZ;

  string_pool_sz = 262144; // 256 KB
  string_pool = malloc(string_pool_sz * sizeof(char));
  string_pool_alloc = 0;

  heap_size = 131072; // 128 KB
  heap = malloc(heap_size);
  heap_alloc = hash_table_prime;

  if_macro_stack = if_macro_stack_start = malloc(20 * IF_MACRO_SIZE * sizeof(int));
  if_macro_stack_end = if_macro_stack_start + 20 * IF_MACRO_SIZE;
  if_macro_mask = 1;
  if_macro_executed = 0;
  expand_macro = 1;
  skip_newlines = 1;

  macro_tok_lst = 0;
  macro_args = 0;
  macro_ident = 0;

  macro_stack = macro_stack_start = malloc(100 * MACRO_SIZE * sizeof(int));
  macro_stack_end = macro_stack_start + 100 * MACRO_SIZE;

  init_ident_table();
  init_builtin_macros();

  i = 1;
  while (i < argc) {
    if (argv[i][0] == '-') {
      if (argv[i][1] == 'D') {
        // pnut-sh only needs -D<macro> and no other options
        init_builtin_int_macro(argv[i] + 2, 1); // +2 to skip -D
      } else {
        putstr("Option "); putstr(argv[i]); putchar('\n');
        fatal_error("unknown option");
      }
    } else {
      // Options that don't start with '-' are file names
      include_file(argv[i], 0);
    }
    i = i + 1;
  }

  if (fd == 0) {
    putstr("Usage: "); putstr(argv[0]); putstr(" <filename>\n");
    fatal_error("no input file");
  }

  ch = '\n';
  get_tok();
  while (tok != EOS) {
    skip_newlines = 0; // Don't skip newlines so print_tok knows where to break lines
    print_tok(tok, val);
    get_tok();
  }
  return 0;
}
