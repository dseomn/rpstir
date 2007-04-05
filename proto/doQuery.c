
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include "scm.h"
#include "scmf.h"
#include "err.h"

/****************
 * This is the query client, which allows a user to read information
 * out of the database and the repository.
 * The standard query is to read all ROA's from the DB and print them out.
 * However, there are options to read any type of objects, choosing
 * a variety of different values to display, and filtering based on
 * a variety of different fields.
 **************/

#define checkErr(test, printArgs...) \
  if (test) { \
     (void) fprintf (stderr, printArgs); \
     return -1; \
  }

#define MAX_VALS 20
#define MAX_CONDS 10

typedef struct _QueryField	/* field to display or filter on */
{
  char     *name;		/* name of the field */
  int      justDisplay;         /* true if not allowed to filter on field */
  int      forROAs;             /* true if field is used in a ROA */
  int      forCRLs;             /* true if field is used in a CRL */
  int      forCerts;            /* true if field is used in a cert */
  int      sqlType;             /* what type of data to expect from query */
  int      maxSize;             /* how much space to allocate for response */
  char     *dbColumn;           /* if not NULL, use this for query, not name */
  char     *otherDBColumn;      /* if not NULL, second field for query */
  char     *heading;            /* name of column heading to use in printout */
  int      requiresJoin;        /* do join with dirs table to get dirname */
  char     *description;        /* one-line description for user help */
} QueryField;

/* the set of all query fields */
static QueryField fields[] = {
  {"filename", 0, 1, 1, 1, SQL_C_CHAR, 256, NULL, NULL, "Filename", 0,
   "the filename where the data is stored in the repository"},
  {"pathname", 1, 1, 1, 1, -1, 0, "dirname", "filename", "Pathname", 1,
   "full pathname (directory plus filename) where the data is stored"},
  {"dirname", 0, 1, 1, 1, SQL_C_CHAR, 4096, NULL, NULL, "Directory", 1,
   "the directory in the repository where the data is stored"},
  {"ski", 0, 1, 0, 1, SQL_C_CHAR, 128, NULL, NULL, "SKI", 0,
   "subject key identifier"},
  {"aki", 0, 0, 0, 1, SQL_C_CHAR, 128, NULL, NULL, "AKI", 0,
   "authority key identifier"},
  {"asn", 0, 1, 0, 0, SQL_C_ULONG, 8, NULL, NULL, "AS #", 0,
   "autonomous system number"},
  {"addrrng", 1, 1, 0, 0, -1, 0, "dirname", "filename", "IP Addr Range", 1,
   "IP address range"},
  {"issuer", 0, 0, 0, 1, SQL_C_CHAR, 512, NULL, NULL, "Issuer", 0,
   "system that issued the cert/crl"},
  {"valfrom", 0, 0, 0, 1, SQL_C_CHAR, 32, NULL, NULL, "Valid From", 0,
   "date/time from which the cert is valid"},
  {"valto", 0, 0, 0, 1, SQL_C_CHAR, 32, NULL, NULL, "Valid To", 0,
   "date/time to which the cert is valid"},
  {"last_upd", 0, 0, 1, 0, SQL_C_CHAR, 32, NULL, NULL, "Last Update", 0,
   "last update time of the CRL"},
  {"next_upd", 0, 0, 1, 0, SQL_C_CHAR, 32, NULL, NULL, "Next Update", 0,
   "next update time of the CRL"},
  {"crlno", 0, 0, 1, 0, SQL_C_ULONG, 8, NULL, NULL, "CRL #", 0,
   "CRL number"}
};

static QueryField *findField (char *name)
{
  int i;
  int size = sizeof (fields) / sizeof (fields[0]);
  for (i = 0; i < size; i++) {
    if (strcasecmp (name, fields[i].name) == 0) return &fields[i];
  }
  return NULL;
}

static int fillInSrch (scmsrch *srch, int isChar, unsigned int sz,
                       int colno, char *colname)
{
  srch->colno = colno;
  srch->sqltype = isChar ? SQL_C_CHAR : SQL_C_ULONG;
  srch->colname = colname;
  srch->avalsize = 0;
  srch->valsize = isChar ? sz : sizeof (unsigned int);
  srch->valptr = calloc (sz, sizeof (char));
  checkErr (srch->valptr == NULL, "Not enough memory\n");
  return 0;
}

static int handleResults (scmcon *conp, scmsrcha *s, int idx)
{
  conp = conp; idx = idx;  // silence compiler warnings
  fprintf (stderr, "ASN = %d File = %s/%s\n   SKI = %s\n",
           *((unsigned int *) s->vec[0].valptr), (char *) s->vec[1].valptr,
           (char *) s->vec[2].valptr, (char *) s->vec[3].valptr);
  return(0);
}

static int doQuery (char *objectType, char **displays, char **filters)
{
  scm      *scmp = NULL;
  scmcon   *connect = NULL;
  scmtab   *table = NULL;
  scmsrcha srch;
  scmsrch  srch1[MAX_VALS];
  char     whereStr[MAX_CONDS*20];
  char     errMsg[1024];
  int      srchFlags = SCM_SRCH_DOVALUE_ALWAYS;
  unsigned long blah = 0;
  int      i, j, proceed, status;
  QueryField *field, *field2;
  char     *name;
  int      isROA = strcasecmp (objectType, "roa") == 0;
  int      isCRL = strcasecmp (objectType, "crl") == 0;
  int      isCert = strcasecmp (objectType, "cert") == 0;

  checkErr ((! isROA) && (! isCRL) && (! isCert),
            "\nBad object type; must be roa, cert or crl\n\n");
  (void) setbuf (stdout, NULL);
  scmp = initscm();
  checkErr (scmp == NULL, "Cannot initialize database schema\n");
  connect = connectscm (scmp->dsn, errMsg, 1024);
  checkErr (connect == NULL, "Cannot connect to %s: %s\n", scmp->dsn, errMsg);
  connect->mystat.tabname = objectType;
  table = findtablescm (scmp, objectType);
  checkErr (table == NULL, "Cannot find table %s\n", objectType);
  table = findtablescm (scmp, objectType);

  /* set up where clause, i.e. the filter */
  srch.where = NULL;
  if (filters == NULL || filters[0] == NULL) {
    srch.wherestr = NULL;
  } else {
    sprintf (whereStr, "");
    for (i = 0; filters[i] != NULL; i++) {
      if (i != 0) strcat (whereStr, " AND ");
      strcat (whereStr, filters[i]);
      name = strtok (filters[i], "=<>");
      field = findField (name);
      checkErr (field == NULL, "Unknown field name: %s\n", name);
      checkErr (field->justDisplay, "Field only for display: %s", name);
    }
    srch.wherestr = whereStr;
  }

  /* set up columns to select */
  srch.vec = srch1;
  srch.sname = NULL;
  srch.ntot = MAX_VALS;
  srch.nused = 0;
  srch.vald = 0;
  srch.context = &blah;
  for (i = 0; displays[i] != NULL; i++) {
    field = findField (displays[i]);
    checkErr (field == NULL, "Unknown field name: %s\n", displays[i]);
    name = (field->dbColumn == NULL) ? displays[i] : field->dbColumn;
    while (name != NULL) {
      proceed = 1;
      for (j = 0; j < srch.nused; j++) {
        if (strcasecmp (name, srch1[j].colname) == 0) proceed = 0;
      }
      if (proceed) {
        field2 = findField (name);
        addcolsrchscm (&srch, name, field2->sqlType, field2->maxSize);
      }
      if (field->requiresJoin) srchFlags = srchFlags | SCM_SRCH_DO_JOIN;
      name = (name == field->otherDBColumn) ? NULL : field->otherDBColumn;
    }
  }

  /* do query */
  status = searchscm (connect, table, &srch, NULL, handleResults, srchFlags);
  for (i = 0; i < srch.nused; i++) {
    free (srch1[i].valptr);
  }
  return status;
}

static int listOptions (char *objectType)
{
  int i, j;
  int size = sizeof (fields) / sizeof (fields[0]);
  int isROA = strcasecmp (objectType, "roa") == 0;
  int isCRL = strcasecmp (objectType, "crl") == 0;
  int isCert = strcasecmp (objectType, "cert") == 0;
  
  checkErr ((! isROA) && (! isCRL) && (! isCert),
            "\nBad object type; must be roa, cert or crl\n\n");
  printf ("\nPossible fields to display or use in clauses for a %s:\n",
          objectType);
  for (i = 0; i < size; i++) {
    if ((fields[i].forROAs && isROA) || (fields[i].forCRLs && isCRL) ||
        (fields[i].forCerts && isCert)) {
      printf ("  %s: %s\n", fields[i].name, fields[i].description);
      if (fields[i].justDisplay) {
        for (j = 0; j < (int)strlen (fields[i].name) + 4; j++) printf (" ");
        printf ("(Note: This can be used only for display.)\n");
      }
    }
  }
  printf ("\n");
  return 0;
}

static int printUsage()
{
  printf ("\nPossible usages:\n  doQuery -a\n");
  printf ("  doQuery -l <type>\n");
  printf ("  doQuery -t <type> -d <disp1>...[ -d <dispn>] [-c <cls1>]...[ -c <clsn>]\n\nSwitches:\n");
  printf ("  -a: short cut for type=roa, no clauses, and display ski, asn, and addrrng\n");
  printf ("  -l: list the possible display fields and clauses for a given type\n");
  printf ("  -t: the type of object requested (roa, cert, or crl)\n");
  printf ("  -d: the name of one field of the object to display\n");
  printf ("  -c: one clause to use for filtering; a clause has the form\n");
  printf ("      <fieldName><op><value>, where op is a comparison operator\n");
  printf ("      (=, <>, >, <, >=, <=)\n\n");
  return -1;
}

int main(int argc, char **argv) 
{
  if (argc == 1) return printUsage();
  if (strcasecmp (argv[1], "-l") == 0) {
    if (argc != 3) return printUsage();
    return listOptions (argv[2]);
  }
  if (strcasecmp (argv[1], "-a") == 0) {
    if (argc > 2) return printUsage();
    char *displays[] = {"asn", "pathname", "ski", NULL};
    return doQuery ("roa", displays, NULL);
  }
  if (strcasecmp (argv[1], "-t") == 0) {
    printf ("Unimplemented option\n");
    return -1;
  }
  return printUsage();
}
