%{

 /*
    csound_prs.l:

    Copyright (C) 2011
    John ffitch

    This file is part of Csound.

    The Csound Library is free software; you can redistribute it
    and/or modify it under the terms of the Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    Csound is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with Csound; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
    02111-1307 USA
*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include "csoundCore.h"
#include "corfile.h"
#define YY_DECL int yylex (CSOUND *csound, yyscan_t yyscanner)
static void comment(yyscan_t);
static void do_comment(yyscan_t);
static void do_include(CSOUND *, int, yyscan_t);
extern int isDir(char *);
static void do_macro_arg(CSOUND *, char *, yyscan_t);
static void do_macro(CSOUND *, char *, yyscan_t);
static void do_umacro(CSOUND *, char *, yyscan_t);
static void do_ifdef(CSOUND *, char *, yyscan_t);
static void do_ifdef_skip_code(CSOUND *, yyscan_t);
//static void print_csound_prsdata(CSOUND *,char *,yyscan_t);
static void csound_prs_line(CORFIL*, yyscan_t);
static void delete_macros(CSOUND*, yyscan_t);
#include "score_param.h"

#define YY_EXTRA_TYPE  PRS_PARM *
#define PARM    yyget_extra(yyscanner)

#define YY_USER_INIT {csound_prs_scan_string(csound->scorestr->body, yyscanner); \
    csound_prsset_lineno(csound->scoLineOffset, yyscanner);             \
    yyg->yy_flex_debug_r=1; PARM->macro_stack_size = 0;                 \
    PARM->alt_stack = NULL; PARM->macro_stack_ptr = 0;                  \
  }
 static MACRO *find_definition(MACRO *, char *);
%}
%option reentrant
%option noyywrap
%option prefix="csound_prs"
%option outfile="Engine/csound_prslex.c"
%option stdout

NEWLINE         (\n|\r\n?)
STSTR           \"
ESCAPE          \\.
IDENT           [a-zA-Z_][a-zA-Z0-9_]*
IDENTN          [a-zA-Z0-9_]+
MACRONAME       "$"[a-zA-Z_][a-zA-Z0-9_]*
MACRONAMED      "$"[a-zA-Z_][a-zA-Z0-9_]*\.
MACRONAMEA      "$"[a-zA-Z_][a-zA-Z0-9_]*\(
MACRONAMEDA     "$"[a-zA-Z_][a-zA-Z0-9_]*\.\(
MACROB          [a-zA-Z_][a-zA-Z0-9_]*\(
MACRO           [a-zA-Z_][a-zA-Z0-9_]*

STCOM           \/\*
INCLUDE         "#include"
DEFINE          #[ \t]*define
UNDEF           "#undef"
IFDEF           #ifn?def
ELSE            #else[ \t]*(;.*)?$
END             #end(if)?[ \t]*(;.*)?(\n|\r\n?)
CONT            \\[ \t]*(;.*)?(\n|\r\n?)

%X incl
%x macro
%x umacro
%x ifdef

%%

{CONT}          {
                  char bb[80];
                  csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),
                                       yyscanner);
#ifdef SCORE-PARSER
                  if (PARM->isString==0) {
                    sprintf(bb, "#sline %d ", csound_prsget_lineno(yyscanner));
                    corfile_puts(bb, csound->expanded_sco);
                  }
#endif
                }
{NEWLINE}       {
                  corfile_putc('\n', csound->expanded_sco);
                  csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),
                                       yyscanner);
                  csound_prs_line(csound->expanded_sco, yyscanner);
                }
"//"            {
                  if (PARM->isString != 1) {
                    comment(yyscanner);
                    corfile_putc('\n', csound->expanded_sco);
                    csound_prs_line(csound->expanded_sco, yyscanner);
                  }
                  else {
                    corfile_puts(yytext, csound->expanded_sco);
                  }
                }
";"             {
                  if (PARM->isString != 1) {
                    comment(yyscanner);
                    corfile_putc('\n', csound->expanded_sco);
                    csound_prs_line(csound->expanded_sco, yyscanner);
                  }
                  else {
                    corfile_puts(yytext, csound->expanded_sco);
                  }
                  //corfile_putline(csound_prsget_lineno(yyscanner),
                  //                csound->expanded_sco);
                }
{STCOM}         {
                  if (PARM->isString != 1)
                    do_comment(yyscanner);
                  else
                    corfile_puts(yytext, csound->expanded_sco);
                }
{ESCAPE}        { corfile_puts(yytext, csound->expanded_sco); }
{STSTR}         {
                  corfile_putc('"', csound->expanded_sco);
                  PARM->isString = !PARM->isString;
                }
{MACRONAME}     {
                   MACRO     *mm = PARM->macros;
                   mm = find_definition(mm, yytext+1);
                   if (UNLIKELY(mm == NULL)) {
                     csound->Message(csound,Str("Undefined macro: '%s'"), yytext);
                     csound->LongJmp(csound, 1);
                   }
                   /* Need to read from macro definition */
                   /* ??fiddle with buffers I guess */
                   if (UNLIKELY(PARM->macro_stack_ptr >= PARM->macro_stack_size )) {
                     PARM->alt_stack =
                       (MACRON*)
                       csound->ReAlloc(csound, PARM->alt_stack,
                                       sizeof(MACRON)*(PARM->macro_stack_size+=10));
                     /* csound->DebugMsg(csound, "alt_stack now %d long\n", */
                     /*                  PARM->macro_stack_size); */
                   }
                   PARM->alt_stack[PARM->macro_stack_ptr].n = 0;
                   PARM->alt_stack[PARM->macro_stack_ptr].line =
                     csound_prsget_lineno(yyscanner);
                   PARM->alt_stack[PARM->macro_stack_ptr++].s = NULL;
                   yypush_buffer_state(YY_CURRENT_BUFFER, yyscanner);
                   csound_prsset_lineno(1, yyscanner);
                   PARM->lstack[++PARM->depth] =
                     (strchr(mm->body,'\n') ?file_to_int(csound, yytext) : 63);
                   yy_scan_string(mm->body, yyscanner);
                   /* csound->DebugMsg(csound,"%p\n", YY_CURRENT_BUFFER); */
                }
{MACRONAMED}    {
                   MACRO     *mm = PARM->macros;
                   yytext[yyleng-1] = '\0';
                   mm = find_definition(mm, yytext+1);
                   if (UNLIKELY(mm == NULL)) {
                     csound->Message(csound,Str("Undefined macro: '%s'"), yytext);
                     csound->LongJmp(csound, 1);
                   }
                   /* Need to read from macro definition */
                   /* ??fiddle with buffers I guess */
                   if (UNLIKELY(PARM->macro_stack_ptr >= PARM->macro_stack_size )) {
                     PARM->alt_stack =
                       (MACRON*)
                       csound->ReAlloc(csound, PARM->alt_stack,
                                       sizeof(MACRON)*(PARM->macro_stack_size+=10));
                     /* csound->DebugMsg(csound, "alt_stack now %d long\n", */
                     /*                  PARM->macro_stack_size); */
                   }
                   PARM->alt_stack[PARM->macro_stack_ptr].n = 0;
                   PARM->alt_stack[PARM->macro_stack_ptr].line =
                     csound_prsget_lineno(yyscanner);
                   PARM->alt_stack[PARM->macro_stack_ptr++].s = NULL;
                   yypush_buffer_state(YY_CURRENT_BUFFER, yyscanner);
                   csound_prsset_lineno(1, yyscanner);
                   PARM->lstack[++PARM->depth] =
                     (strchr(mm->body,'\n') ?file_to_int(csound, yytext) : 63);
                   yy_scan_string(mm->body, yyscanner);
                   /* csound->DebugMsg(csound,"%p\n", YY_CURRENT_BUFFER); */
                 }
{MACRONAMEA}    {
                   MACRO     *mm = PARM->macros;
                   char      *mname;
                   int c, i, j;
                   //csound->DebugMsg(csound,"Macro with arguments call %s\n",
                   //                 yytext);
                   yytext[yyleng-1] = '\0';
                   mm = find_definition(PARM->macros, yytext+1);
                   if (UNLIKELY(mm == NULL)) {
                     csound->Message(csound,Str("Undefined macro: '%s'"), yytext);
                     csound->LongJmp(csound, 1);
                   }
                   mname = yytext;
                   /* Need to read from macro definition */
                   //csound->DebugMsg(csound,"Looking for %d args\n", mm->acnt);
                   for (j = 0; j < mm->acnt; j++) {
                     char  term = (j == mm->acnt - 1 ? ')' : '\'');
 /* Compatability */
                     char  trm1 = (j == mm->acnt - 1 ? ')' : '#');
                     MACRO *nn = (MACRO*) csound->Malloc(csound, sizeof(MACRO));
                     int   size = 100;
                     nn->name = csound->Malloc(csound, strlen(mm->arg[j]) + 1);
                     //csound->DebugMsg(csound,"Arg %d: %s\n", j+1, mm->arg[j]);
                     strcpy(nn->name, mm->arg[j]);
                     csound->Message(csound, "defining argument %s ",
                                        nn->name);
                     i = 0;
                     nn->body = (char*) csound->Malloc(csound, 100);
                     while ((c = input(yyscanner))!= term && c!=trm1) {
                       if (c == ')') {
                         csound->Die(csound, Str("Too few arguments to macro\n"));
                       }
                       if (UNLIKELY(i > 98)) {
                         csound->Die(csound,
                                     Str("Missing argument terminator\n%.98s"),
                                     nn->body);
                       }
                       nn->body[i++] = c;
                       if (UNLIKELY(i >= size))
                         nn->body = csound->ReAlloc(csound, nn->body, size += 100);
                     }
                     nn->body[i] = '\0';
                     csound->Message(csound, "as...#%s#\n", nn->body);
                     nn->acnt = 0;       /* No arguments for arguments */
                     nn->next = PARM->macros;
                     PARM->macros = nn;
                   }
                   //csound->DebugMsg(csound,"New body: ...#%s#\n", mm->body);
                   if (UNLIKELY(PARM->macro_stack_ptr >= PARM->macro_stack_size )) {
                     PARM->alt_stack =
                       (MACRON*)
                       csound->ReAlloc(csound, PARM->alt_stack,
                                       sizeof(MACRON)*(PARM->macro_stack_size+=10));
                     /* csound->DebugMsg(csound, */
                     /*        "macro_stack extends alt_stack to %d long\n", */
                     /*                  PARM->macro_stack_size); */
                   }
                   PARM->alt_stack[PARM->macro_stack_ptr].n = PARM->macros->acnt;
                   PARM->alt_stack[PARM->macro_stack_ptr].line =
                     csound_prsget_lineno(yyscanner);
                   PARM->alt_stack[PARM->macro_stack_ptr++].s = PARM->macros;
                   PARM->alt_stack[PARM->macro_stack_ptr].n = 0;
                   PARM->alt_stack[PARM->macro_stack_ptr].line =
                     csound_prsget_lineno(yyscanner);
                   /* printf("stacked line = %llu at %d\n", */
                   /*  csound_prsget_lineno(yyscanner), PARM->macro_stack_ptr-1); */
                   PARM->alt_stack[PARM->macro_stack_ptr].s = NULL;
                   //csound->DebugMsg(csound,"Push %p macro stack\n",PARM->macros);
                   yypush_buffer_state(YY_CURRENT_BUFFER, yyscanner);
                   csound_prsset_lineno(1, yyscanner);
                   PARM->lstack[++PARM->depth] =
                     (strchr(mm->body,'\n') ?file_to_int(csound, mname) : 63);
                   yy_scan_string(mm->body, yyscanner);
                 }
{MACRONAMEDA}    {
                   MACRO     *mm = PARM->macros;
                   char      *mname;
                   int c, i, j;
                   //csound->DebugMsg(csound,"Macro with arguments call %s\n",
                   //                    yytext);
                   yytext[yyleng-2] = '\0';
                   mm = find_definition(PARM->macros, yytext+1);
                   if (UNLIKELY(mm == NULL)) {
                     csound->Message(csound,Str("Undefined macro: '%s'"), yytext);
                     csound->LongJmp(csound, 1);
                   }
                   mname = yytext;
                   /* Need to read from macro definition */
                   //csound->DebugMsg(csound,"Looking for %d args\n", mm->acnt);
                   for (j = 0; j < mm->acnt; j++) {
                     char  term = (j == mm->acnt - 1 ? ')' : '\'');
 /* Compatability */
                     char  trm1 = (j == mm->acnt - 1 ? ')' : '#');
                     MACRO *nn = (MACRO*) csound->Malloc(csound, sizeof(MACRO));
                     int   size = 100;
                     nn->name = csound->Malloc(csound, strlen(mm->arg[j]) + 1);
                     //csound->DebugMsg(csound,"Arg %d: %s\n", j+1, mm->arg[j]);
                     strcpy(nn->name, mm->arg[j]);
                     csound->Message(csound, "defining argument %s ",
                                        nn->name);
                     i = 0;
                     nn->body = (char*) csound->Malloc(csound, 100);
                     while ((c = input(yyscanner))!= term && c!=trm1) {
                       if (c == ')') {
                         csound->Die(csound, Str("Too few arguments to macro\n"));
                       }
                       if (UNLIKELY(i > 98)) {
                         csound->Die(csound,
                                     Str("Missing argument terminator\n%.98s"),
                                     nn->body);
                       }
                       nn->body[i++] = c;
                       if (UNLIKELY(i >= size))
                         nn->body = csound->ReAlloc(csound, nn->body, size += 100);
                     }
                     nn->body[i] = '\0';
                     csound->Message(csound, "as...#%s#\n", nn->body);
                     nn->acnt = 0;       /* No arguments for arguments */
                     nn->next = PARM->macros;
                     PARM->macros = nn;
                   }
                   //csound->DebugMsg(csound,"New body: ...#%s#\n", mm->body);
                   if (UNLIKELY(PARM->macro_stack_ptr >= PARM->macro_stack_size )) {
                     PARM->alt_stack =
                       (MACRON*)
                       csound->ReAlloc(csound, PARM->alt_stack,
                                       sizeof(MACRON)*(PARM->macro_stack_size+=10));
                     /* csound->DebugMsg(csound, "alt_stack now %d long\n", */
                     /*                  PARM->macro_stack_size); */
                   }
                   PARM->alt_stack[PARM->macro_stack_ptr].n = PARM->macros->acnt;
                   PARM->alt_stack[PARM->macro_stack_ptr++].s = PARM->macros;
                   PARM->alt_stack[PARM->macro_stack_ptr].n = 0;
                   PARM->alt_stack[PARM->macro_stack_ptr].line =
                     csound_prsget_lineno(yyscanner);
                   PARM->alt_stack[PARM->macro_stack_ptr].s = NULL;
                   yypush_buffer_state(YY_CURRENT_BUFFER, yyscanner);
                   if (PARM->depth++>1024) {
                     csound->Die(csound, Str("Includes nested too deeply"));
                   }
                   csound_prsset_lineno(1, yyscanner);
                   PARM->lstack[PARM->depth] =
                     (strchr(mm->body,'\n') ?file_to_int(csound, mname) : 63);
                   yy_scan_string(mm->body, yyscanner);
                 }
{INCLUDE}       {
                  if (PARM->isString != 1)
                    BEGIN(incl);
                  else
                    corfile_puts(yytext, csound->expanded_sco);
                }
<incl>[ \t]*     /* eat the whitespace */
<incl>.         { /* got the include file name */
                  do_include(csound, yytext[0], yyscanner);
                  BEGIN(INITIAL);
                }
#exit           { corfile_putc('\0', csound->expanded_sco);
                  corfile_putc('\0', csound->expanded_sco);
                  delete_macros(csound, yyscanner);
                  return 0;}
<<EOF>>         {
                  MACRO *x, *y=NULL;
                  int n;
                  /* csound->DebugMsg(csound,"*********Leaving buffer %p\n", */
                  /*                  YY_CURRENT_BUFFER); */
                  yypop_buffer_state(yyscanner);
                  PARM->depth--;
                  if (UNLIKELY(PARM->depth > 1024))
                    csound->Die(csound, Str("unexpected EOF"));
                  PARM->llocn = PARM->locn; PARM->locn = make_location(PARM);
                  /* csound->DebugMsg(csound,"%s(%d): loc=%Ld; lastloc=%Ld\n", */
                  /*                  __FILE__, __LINE__, */
                  /*        PARM->llocn, PARM->locn); */
                  if ( !YY_CURRENT_BUFFER ) yyterminate();
                  csound->DebugMsg(csound,"End of input; popping to %p\n",
                          YY_CURRENT_BUFFER);
                  csound_prs_line(csound->expanded_sco, yyscanner);
                  n = PARM->alt_stack[--PARM->macro_stack_ptr].n;
                  /* printf("lineno on stack is %llu\n", */
                  /*        PARM->alt_stack[PARM->macro_stack_ptr].line); */
                  csound->DebugMsg(csound,"n=%d\n", n);
                  if (n!=0) {
                    /* We need to delete n macros starting with y */
                    y = PARM->alt_stack[PARM->macro_stack_ptr].s;
                    x = PARM->macros;
                    if (x==y) {
                      while (n>0) {
                        mfree(csound, y->name); x=y->next;
                        mfree(csound, y); y=x; n--;
                      }
                      PARM->macros = x;
                    }
                    else {
                      MACRO *nxt = y->next;
                      while (x->next != y) x = x->next;
                      while (n>0) {
                        nxt = y->next;
                        mfree(csound, y->name); mfree(csound, y); y=nxt; n--;
                      }
                      x->next = nxt;
                    }
                    y->next = x;
                  }
                  csound_prsset_lineno(PARM->alt_stack[PARM->macro_stack_ptr].line,
                                       yyscanner);
                  csound->DebugMsg(csound, "%s(%d): line now %d at %d\n",
                                   __FILE__, __LINE__,
                                   csound_prsget_lineno(yyscanner),
                                   PARM->macro_stack_ptr);
                  csound->DebugMsg(csound,
                                   "End of input segment: macro pop %p -> %p\n",
                                   y, PARM->macros);
                  csound_prsset_lineno(PARM->alt_stack[PARM->macro_stack_ptr].line,
                                       yyscanner);
                  //print_csound_prsdata(csound,"Before prs_line", yyscanner);
                  csound_prs_line(csound->scorestr, yyscanner);
                  //print_csound_prsdata(csound,"After prs_line", yyscanner);
                }
{DEFINE}        {
                  if (PARM->isString != 1)
                    BEGIN(macro);
                  else
                    corfile_puts(yytext, csound->expanded_sco);
                }
<macro>[ \t]*    /* eat the whitespace */
<macro>{MACROB} {
                  yytext[yyleng-1] = '\0';
                  csound->DebugMsg(csound,"Define macro with args %s\n",
                                      yytext);
                  /* print_csound_prsdata(csound, "Before do_macro_arg",
                                          yyscanner); */
                  do_macro_arg(csound, yytext, yyscanner);
                  //print_csound_prsdata(csound,"After do_macro_arg", yyscanner);
                  BEGIN(INITIAL);
                }
<macro>{MACRO} {
                  csound->DebugMsg(csound,"Define macro %s\n", yytext);
                  /* print_csound_prsdata(csound,"Before do_macro", yyscanner); */
                  do_macro(csound, yytext, yyscanner);
                  //print_csound_prsdata(csound,"After do_macro", yyscanner);
                  BEGIN(INITIAL);
                }
<macro>.        { csound->Message(csound,
                                  Str("Unexpected character %c(%.2x) line %d\n"),
                                  yytext[0], yytext[0],
                                  csound_prsget_lineno(yyscanner));
                  csound->LongJmp(csound, 1);
                }
{UNDEF}         {
                  if (PARM->isString != 1)
                    BEGIN(umacro);
                  else
                    corfile_puts(yytext, csound->expanded_sco);
                }
<umacro>[ \t]*    /* eat the whitespace */
<umacro>{MACRO}  {
                  csound->DebugMsg(csound,"Undefine macro %s\n", yytext);
                  do_umacro(csound, yytext, yyscanner);
                  BEGIN(INITIAL);
                }

{IFDEF}         {
                  if (PARM->isString != 1) {
                    PARM->isIfndef = (yytext[3] == 'n');  /* #ifdef or #ifndef */
                    csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),
                                         yyscanner);
                    corfile_putc('\n', csound->expanded_sco);
                    csound_prs_line(csound->expanded_sco, yyscanner);
                    BEGIN(ifdef);
                  }
                  else {
                    corfile_puts(yytext, csound->expanded_sco);
                  }
                }
<ifdef>[ \t]*     /* eat the whitespace */
<ifdef>{IDENT}  {
                  do_ifdef(csound, yytext, yyscanner);
                  BEGIN(INITIAL);
                }
{ELSE}          {
                  if (PARM->isString != 1) {
                    if (PARM->ifdefStack == NULL) {
                      csound->Message(csound, Str("#else without #if\n"));
                      csound->LongJmp(csound, 1);
                    }
                    else if (PARM->ifdefStack->isElse) {
                      csound->Message(csound, Str("#else after #else\n"));
                      csound->LongJmp(csound, 1);
                    }
                    PARM->ifdefStack->isElse = 1;
                    csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),
                                         yyscanner);
                    corfile_putc('\n', csound->expanded_sco);
                    csound_prs_line(csound->expanded_sco, yyscanner);
                    do_ifdef_skip_code(csound, yyscanner);
                  }
                  else {
                    corfile_puts(yytext, csound->expanded_sco);
                  }
                }
{END}           {
                  if (PARM->isString != 1) {
                    IFDEFSTACK *pp = PARM->ifdefStack;
                    if (UNLIKELY(pp == NULL)) {
                      csound->Message(csound, Str("Unmatched #end\n"));
                      csound->LongJmp(csound, 1);
                    }
                    PARM->ifdefStack = pp->prv;
                    csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),
                                         yyscanner);
                    corfile_putc('\n', csound->expanded_sco);
                    csound_prs_line(csound->expanded_sco, yyscanner);
                    mfree(csound, pp);
                  }
                  else {
                    corfile_puts(yytext, csound->expanded_sco);
                  }
                }

"{"             { printf("*** loop not done\n");
                  corfile_putc(yytext[0], csound->expanded_sco); }

.               { corfile_putc(yytext[0], csound->expanded_sco); }

%%
static void comment(yyscan_t yyscanner)              /* Skip until nextline */
{
    char c;
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    while ((c = input(yyscanner)) != '\n' && c != '\r') { /* skip */
      if ((int)c == EOF) {
        YY_CURRENT_BUFFER_LVALUE->yy_buffer_status =
          YY_BUFFER_EOF_PENDING;
        return;
      }
    }
    if (c == '\r' && (c = input(yyscanner)) != '\n') {
      if ((int)c != EOF)
        unput(c);
      else
        YY_CURRENT_BUFFER_LVALUE->yy_buffer_status =
          YY_BUFFER_EOF_PENDING;
    }
    csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),yyscanner);
}

static void do_comment(yyscan_t yyscanner)         /* Skip until * and / chars */
{
    int c;
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
 TOP:
    c = input(yyscanner);
    switch (c) {
    NL:
    case '\n':
      csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),yyscanner);
      goto TOP;
    case '*':
    AST:
      c = input(yyscanner);
      switch (c) {
      case '*':
        goto AST;
      case '\n':
        goto NL;
      case '/':
        return;
      case EOF:
        goto ERR;
      default:
        goto TOP;
      }
    case EOF:
    ERR:
      YY_CURRENT_BUFFER_LVALUE->yy_buffer_status =
        YY_BUFFER_EOF_PENDING;
      return;
    default:
      goto TOP;
    }
}

static void do_include(CSOUND *csound, int term, yyscan_t yyscanner)
{
    char buffer[100];
    int p=0;
    int c;
    CORFIL *cf;
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    while ((c=input(yyscanner))!=term) {
      buffer[p] = c;
      p++;
    }
    buffer[p] = '\0';
    while ((c=input(yyscanner))!='\n');
    if (PARM->depth++>=1024) {
      csound->Die(csound, Str("Includes nested too deeply"));
    }
    csound_prsset_lineno(1+csound_prsget_lineno(yyscanner), yyscanner);
    csound->DebugMsg(csound,"line %d at end of #include line\n",
                     csound_prsget_lineno(yyscanner));
    {
      uint8_t n = file_to_int(csound, buffer);
      char bb[128];
      PARM->lstack[PARM->depth] = n;
      sprintf(bb, "#source %llu\n", PARM->locn = make_location(PARM));
      PARM->llocn = PARM->locn;
#ifdef SCORE-PARSER
      corfile_puts(bb, csound->expanded_sco);
#endif
    }
    csound->DebugMsg(csound,"reading included file \"%s\"\n", buffer);
    if (isDir(buffer))
      csound->Warning(csound, Str("%s is a directory; not including"), buffer);
    cf = copy_to_corefile(csound, buffer, "INCDIR", 0);
    if (cf == NULL)
      csound->Die(csound,
                  Str("Cannot open #include'd file %s\n"), buffer);
    if (UNLIKELY(PARM->macro_stack_ptr >= PARM->macro_stack_size )) {
      PARM->alt_stack =
        (MACRON*) csound->ReAlloc(csound, PARM->alt_stack,
                                  sizeof(MACRON)*(PARM->macro_stack_size+=10));
      /* csound->DebugMsg(csound, "alt_stack now %d long, \n", */
      /*                  PARM->macro_stack_size); */
    }
    csound->DebugMsg(csound,"%s(%d): stacking line %d at %d\n", __FILE__, __LINE__,
           csound_prsget_lineno(yyscanner),PARM->macro_stack_ptr);
    PARM->alt_stack[PARM->macro_stack_ptr].n = 0;
    PARM->alt_stack[PARM->macro_stack_ptr].line = csound_prsget_lineno(yyscanner);
    PARM->alt_stack[PARM->macro_stack_ptr++].s = NULL;
    csound_prspush_buffer_state(YY_CURRENT_BUFFER, yyscanner);
    csound_prs_scan_string(cf->body, yyscanner);
    corfile_rm(&cf);
    csound->DebugMsg(csound,"Set line number to 1\n");
    csound_prsset_lineno(1, yyscanner);
}

static inline int isNameChar(int c, int pos)
{
    c = (int) ((unsigned char) c);
    return (isalpha(c) || (pos && (c == '_' || isdigit(c))));
}

static void do_macro_arg(CSOUND *csound, char *name0, yyscan_t yyscanner)
{
    MACRO *mm = (MACRO*) csound->Malloc(csound, sizeof(MACRO));
    int   arg = 0, i, c;
    int   size = 100;
    int mlen = 40;
    char *q = name0;
    char *mname = malloc(mlen);
    mm->margs = MARGS;    /* Initial size */
    mm->name = (char*)csound->Malloc(csound, strlen(name0) + 1);
    strcpy(mm->name, name0);
    do {
      i = 0;
      q = name0;
      mname[i++] = '_';
      while ((c = *q++)) {
        mname[i++] = c;
        if (UNLIKELY(i==mlen))
          mname = (char *)realloc(mname, mlen+=40);
      }
      mname[i++] = '_';
      if (UNLIKELY(i==mlen))
          mname = (char *)realloc(mname, mlen+=40);
      mname[i++] = '_';
      if (UNLIKELY(i==mlen))
          mname = (char *)realloc(mname, mlen+=40);
      while (isspace((c = input(yyscanner))));

      while (isNameChar(c, i)) {
        mname[i++] = c;
        if (UNLIKELY(i==mlen))
          mname = (char *)realloc(mname, mlen+=40);
        c = input(yyscanner);
      }
      mname[i] = '\0';
      mm->arg[arg] = csound->Malloc(csound, i + 1);
      strcpy(mm->arg[arg++], mname);
      if (UNLIKELY(arg >= mm->margs)) {
        mm = (MACRO*) csound->ReAlloc(csound, mm, sizeof(MACRO)
                               + mm->margs * sizeof(char*));
        mm->margs += MARGS;
      }
      while (isspace(c))
        c = input(yyscanner);
    } while (c == '\'' || c == '#');
    if (UNLIKELY(c != ')')) {
      csound->Message(csound, Str("macro error\n"));
    }
    free(mname);
    c = input(yyscanner);
    while (c!='#') {
      if (c==EOF) csound->Die(csound, Str("define macro runaway\n"));
      else if (c==';') {
        while ((c=input(yyscanner))!= '\n')
          if (c==EOF) {
            csound->Die(csound, Str("define macro runaway\n"));
          }
      }
      else if (c=='/') {
        if ((c=input(yyscanner))=='/') {
          while ((c=input(yyscanner))!= '\n')
            if (c==EOF)
              csound->Die(csound, Str("define macro runaway\n"));
        }
        else if (c=='*') {
          while ((c=input(yyscanner))!='*') {
          again:
            if (c==EOF) csound->Die(csound, Str("define macro runaway\n"));
          }
          if ((c=input(yyscanner))!='/') goto again;
        }
      }
      else if (!isspace(c))
        csound->Die(csound,
               Str("define macro unexpected character %c(0x%.2x) awaiting #\n"),
                    c, c);
      c = input(yyscanner); /* skip to start of body */
    }
    mm->acnt = arg;
    i = 0;
    mm->body = (char*) csound->Malloc(csound, 100);
    while ((c = input(yyscanner)) != '#') { /* read body */
      if (UNLIKELY(c == EOF))
        csound->Die(csound, Str("define macro with args: unexpected EOF"));
      if (c=='$') {             /* munge macro name? */
        int n = strlen(name0)+4;
        if (UNLIKELY(i+n >= size))
          mm->body = csound->ReAlloc(csound, mm->body, size += 100);
        mm->body[i] = '$'; mm->body[i+1] = '_';
        strcpy(&mm->body[i+2], name0);
        mm->body[i + n - 2] = '_'; mm->body[i + n - 1] = '_';
        i+=n;
        continue;
      }
      mm->body[i++] = c=='\r'?'\n':c;
      if (UNLIKELY(i >= size))
        mm->body = csound->ReAlloc(csound, mm->body, size += 100);
      if (c == '\\') {                    /* allow escaped # */
        mm->body[i++] = c = input(yyscanner);
        if (UNLIKELY(i >= size))
          mm->body = csound->ReAlloc(csound, mm->body, size += 100);
      }
      if (UNLIKELY(c == '\n' || c == '\r')) {
        csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),yyscanner);
        corfile_putc('\n', csound->expanded_sco);
        csound_prs_line(csound->expanded_sco, yyscanner);
      }
    }
    mm->body[i] = '\0';
    mm->next = PARM->macros;
    PARM->macros = mm;
}

static void do_macro(CSOUND *csound, char *name0, yyscan_t yyscanner)
{
    MACRO *mm = (MACRO*) csound->Malloc(csound, sizeof(MACRO));
    int   i, c;
    int   size = 100;
    mm->margs = MARGS;    /* Initial size */
    csound->DebugMsg(csound,"Macro definition for %s\n", name0);
    mm->name = (char*)csound->Malloc(csound, strlen(name0) + 1);
    strcpy(mm->name, name0);
    mm->acnt = 0;
    i = 0;
    while ((c = input(yyscanner)) != '#') {
      if (c==EOF) csound->Die(csound, Str("define macro runaway\n"));
      else if (c==';') {
        while ((c=input(yyscanner))!= '\n')
          if (c==EOF) {
            csound->Die(csound, Str("define macro runaway\n"));
          }
      }
      else if (c=='/') {
        if ((c=input(yyscanner))=='/') {
          while ((c=input(yyscanner))!= '\n')
            if (c==EOF)
              csound->Die(csound, Str("define macro runaway\n"));
        }
        else if (c=='*') {
          while ((c=input(yyscanner))!='*') {
          again:
            if (c==EOF) csound->Die(csound, Str("define macro runaway\n"));
          }
          if ((c=input(yyscanner))!='/') goto again;
        }
      }
      else if (!isspace(c))
        csound->Die(csound,
                    Str("define macro unexpected character %c(0x%.2x) awaiting #\n"),
                    c, c);
    }
    mm->body = (char*) csound->Malloc(csound, 100);
    while ((c = input(yyscanner)) != '#') {
      if (UNLIKELY(c == EOF || c==0))
        csound->Die(csound, Str("define macro: unexpected EOF"));
      mm->body[i++] = c=='\r'?'\n':c;
      if (UNLIKELY(i >= size))
        mm->body = csound->ReAlloc(csound, mm->body, size += 100);
      if (c == '\\') {                    /* allow escaped # */
        mm->body[i++] = c = input(yyscanner);
        if (UNLIKELY(i >= size))
          mm->body = csound->ReAlloc(csound, mm->body, size += 100);
      }
      if (UNLIKELY(c == '\n' || c == '\r')) {
        csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),yyscanner);
        corfile_putc('\n', csound->expanded_sco);
        csound_prs_line(csound->expanded_sco, yyscanner);
      }
    }
    mm->body[i] = '\0';
    csound->DebugMsg(csound,"Body #%s#\n", mm->body);
    mm->next = PARM->macros;
    PARM->macros = mm;
}

static void do_umacro(CSOUND *csound, char *name0, yyscan_t yyscanner)
{
    int i,c;
    if (UNLIKELY(csound->oparms->msglevel))
      csound->Message(csound,Str("macro %s undefined\n"), name0);
    csound->DebugMsg(csound, "macro %s undefined\n", name0);
    if (strcmp(name0, PARM->macros->name)==0) {
      MACRO *mm=PARM->macros->next;
      mfree(csound, PARM->macros->name); mfree(csound, PARM->macros->body);
      for (i=0; i<PARM->macros->acnt; i++)
        mfree(csound, PARM->macros->arg[i]);
      mfree(csound, PARM->macros); PARM->macros = mm;
    }
    else {
      MACRO *mm = PARM->macros;
      MACRO *nn = mm->next;
      while (strcmp(name0, nn->name) != 0) {
        mm = nn; nn = nn->next;
        if (UNLIKELY(nn == NULL)) {
          csound->Message(csound, Str("Undefining undefined macro"));
          csound->LongJmp(csound, 1);
        }
      }
      mfree(csound, nn->name); mfree(csound, nn->body);
      for (i=0; i<nn->acnt; i++)
        mfree(csound, nn->arg[i]);
      mm->next = nn->next; mfree(csound, nn);
    }
    while ((c=input(yyscanner)) != '\n' &&
           c != EOF && c != '\r'); /* ignore rest of line */
    csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),yyscanner);
}

static void do_ifdef(CSOUND *csound, char *name0, yyscan_t yyscanner)
{
    int c;
    MACRO *mm;
    IFDEFSTACK *pp;
    pp = (IFDEFSTACK*) csound->Calloc(csound, sizeof(IFDEFSTACK));
    pp->prv = PARM->ifdefStack;
    pp->isDef = PARM->isIfndef;
    for (mm = PARM->macros; mm != NULL; mm = mm->next) {
      if (strcmp(name0, mm->name) == 0) {
        pp->isDef ^= (unsigned char) 1;
        break;
      }
    }
    PARM->ifdefStack = pp;
    pp->isSkip = pp->isDef ^ (unsigned char) 1;
    if (pp->isSkip)
      do_ifdef_skip_code(csound, yyscanner);
    else
      while ((c = input(yyscanner)) != '\n' && c != '\r' && c != EOF);
}

static void do_ifdef_skip_code(CSOUND *csound, yyscan_t yyscanner)
{
    int i, c, nested_ifdef = 0;
    char *buf;
    IFDEFSTACK *pp;
    buf = (char*)malloc(8*sizeof(char));
    pp = PARM->ifdefStack;
    c = input(yyscanner);
    for (;;) {
      while (c!='\n' && c!= '\r') {
        if (UNLIKELY(c == EOF)) {
          csound->Message(csound, Str("Unmatched #if%sdef\n"),
                          PARM->isIfndef ? "n" : "");
          csound->LongJmp(csound, 1);
        }
        c = input(yyscanner);
    }
      csound_prsset_lineno(1+csound_prsget_lineno(yyscanner),
                           yyscanner);
      corfile_putc('\n', csound->expanded_sco);
      csound_prs_line(csound->expanded_sco, yyscanner);
      while (isblank(c = input(yyscanner)));  /* eat the whitespace */
      if (c == '#') {
        for (i=0; islower(c = input(yyscanner)) && i < 7; i++)
          buf[i] = c;
        buf[i] = '\0';
        if (strcmp("end", buf) == 0 || strcmp("endif", buf) == 0) {
          if (nested_ifdef-- == 0) {
            PARM->ifdefStack = pp->prv;
            mfree(csound, pp);
            break;
          }
        }
        else if (strcmp("ifdef", buf) == 0 || strcmp("ifndef", buf) == 0) {
          nested_ifdef++;
        }
        else if (strcmp("else", buf) == 0 && nested_ifdef == 0) {
          if (pp->isElse) {
            csound->Message(csound, Str("#else after #else\n"));
            csound->LongJmp(csound, 1);
          }
          pp->isElse = 1;
          break;
        }
      }
    }
    free(buf);
    while (c != '\n' && c != EOF && c != '\r') c = input(yyscanner);
}

static void delete_macros(CSOUND *csound, yyscan_t yyscanner)
{
    MACRO * qq = PARM->macros;
    if (qq) {
      MACRO *mm = qq;
      while (mm) {
        csound->Free(csound, mm->body);
        csound->Free(csound, mm->name);
        qq = mm->next;
        csound->Free(csound, mm);
        mm = qq;
       }
    }
}

void cs_init_smacros(CSOUND *csound, PRS_PARM *qq, NAMES *nn)
{
    while (nn) {
      char  *s = nn->mac;
      char  *p = strchr(s, '=');
      char  *mname;
      MACRO *mm;

      if (p == NULL)
        p = s + strlen(s);
      if (csound->oparms->msglevel & 7)
        csound->Message(csound, Str("Macro definition for %*s\n"), p - s, s);
      s = strchr(s, ':') + 1;                   /* skip arg bit */
      if (UNLIKELY(s == NULL || s >= p)) {
        csound->Die(csound, Str("Invalid macro name for --omacro"));
      }
      mname = (char*) csound->Malloc(csound, (p - s) + 1);
      strncpy(mname, s, p - s);
      mname[p - s] = '\0';
      /* check if macro is already defined */
      for (mm = qq->macros; mm != NULL; mm = mm->next) {
        if (strcmp(mm->name, mname) == 0)
          break;
      }
      if (mm == NULL) {
        mm = (MACRO*) csound->Calloc(csound, sizeof(MACRO));
        mm->name = mname;
        mm->next = qq->macros;
        qq->macros = mm;
      }
      else
        mfree(csound, mname);
      mm->margs = MARGS;    /* Initial size */
      mm->acnt = 0;
      if (*p != '\0')
        p++;
      mm->body = (char*) csound->Malloc(csound, strlen(p) + 1);
      strcpy(mm->body, p);
      nn = nn->next;
    }
}

static void csound_prs_line(CORFIL* cf, void *yyscanner)
{
    int n = csound_prsget_lineno(yyscanner);
    //printf("line number %d\n", n);
    /* This assumes that the initial line was not written with this system  */
    if (cf->p>0 && cf->body[cf->p-1]=='\n') {
      uint64_t locn = PARM->locn;
      uint64_t llocn = PARM->llocn;
#ifdef SCORE-PARSER
      if (locn != llocn) {
        char bb[80];
        sprintf(bb, "#source %llu\n", locn);
        corfile_puts(bb, cf);
      }
#endif
      PARM->llocn = locn;
#ifdef SCORE-PARSER
      if (n!=PARM->line+1) {
        char bb[80];
        sprintf(bb, "#line   %d\n", n);
        //printf("#line %d\n", n);
        corfile_puts(bb, cf);
      }
#endif
    }
    PARM->line = n;
}

static MACRO *find_definition(MACRO *mmo, char *s)
{
    MACRO *mm = mmo;
    //printf("****Looking for %s\n", s);
    while (mm != NULL) {  /* Find the definition */
      //printf("looking at %p(%s) body #%s#\n", mm, mm->name, mm->body);
      if (!(strcmp(s, mm->name))) break;
      mm = mm->next;
    }
    if (mm == NULL) {
      mm = mmo;
      s++;                      /* skip _ */
    looking:
      while (*s++!='_') { if (*s=='\0') return NULL; }
      if (*s++!='_') { s--; goto looking; }
      //printf("now try looking for %s\n", s);
      while (mm != NULL) {  /* Find the definition */
        //printf("looking at %p(%s) body #%s#\n", mm, mm->name, mm->body);
        if (!(strcmp(s, mm->name))) break;
        mm = mm->next;
      }
    }
    //if (mm) printf("found body #%s#\n****\n", mm->body);
    return mm;
}


#if 0
static void print_csound_prsdata(CSOUND *csound, char *mesg, void *yyscanner)
{
    struct yyguts_t *yyg =(struct yyguts_t*)yyscanner;
    csound->DebugMsg(csound,"********* %s extra data ************", mesg);
    csound->DebugMsg(csound,"yyscanner = %p", yyscanner);
    csound->DebugMsg(csound,"yyextra_r = %p, yyin_r = %p, yyout_r = %p,"
                     " yy_buffer_stack_top = %d",
           yyg->yyextra_r, yyg->yyin_r,yyg->yyout_r, yyg->yy_buffer_stack_top);
    csound->DebugMsg(csound,"yy_buffer_stack_max = %d1, yy_buffer_stack = %p, "
                     "yy_hold_char = %d '%c'",
           yyg->yy_buffer_stack_max, yyg->yy_buffer_stack, yyg->yy_hold_char,
           yyg->yy_hold_char);
    csound->DebugMsg(csound,"yy_n_chars = %d, yyleng_r = %d, yy_c_buf_p = %p %c",
           yyg->yy_n_chars, yyg->yyleng_r, yyg->yy_c_buf_p, *yyg->yy_c_buf_p);
    csound->DebugMsg(csound,"yy_init = %d, yy_start = %d, "
                     "yy_did_buffer_switch_on_eof = %d",
           yyg->yy_init, yyg->yy_start, yyg->yy_did_buffer_switch_on_eof);
    csound->DebugMsg(csound,"yy_start_stack_ptr = %d,"
                     " yy_start_stack_depth = %d, yy_start_stack = %p",
           yyg->yy_start_stack_ptr, yyg->yy_start_stack_depth, yyg->yy_start_stack);

    csound->DebugMsg(csound,"yy_last_accepting_state = %d, "
                     "yy_last_accepting_cpos = %p %c",
           yyg->yy_last_accepting_state, yyg->yy_last_accepting_cpos,
                     *yyg->yy_last_accepting_cpos);
    csound->DebugMsg(csound,"yylineno_r = %d, yy_flex_debug_r = %d, "
                     "yytext_r = %p \"%s\", yy_more_flag = %d, yy_more_len = %d",
           yyg->yylineno_r, yyg->yy_flex_debug_r, yyg->yytext_r, yyg->yytext_r,
                     yyg->yy_more_flag, yyg->yy_more_len);
    {
      PRS_PARM* pp = yyg->yyextra_r;
      printf("macros = %p, isIfndef = %d, isString = %d, line - %d loc = %d\n",
             pp->macros, pp->isIfndef, pp->isString, pp->line, pp->locn);
      printf
        ("llocn = %d dept=%d\n", pp->llocn, pp->depth);
    }
    csound->DebugMsg(csound,"*********\n");
}
#endif
