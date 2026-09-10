/***************************************************************

    aplinks ... Another pocket link file server Version 1.03

    (c)1992,93 N.Kon

    Usage: aplinks [-p port] [-b baud] [-1|-5] [ filename ... ]

    Last change: Jan. 8th, 1993

    ---------------------------------------------------------------
    ** C17 readability variant of APLINKS.C ** - same behavior, compiled as
    C17, with bool flags and compile-time static_assert checks on the disk
    geometry.  Kept alongside the C99 APLINKS.C, which stays the reference.

    The virtual-disk logic and the
    on-wire protocol are byte-for-byte identical to the 1993 MS-DOS
    original; the platform layer (serial I/O, file globbing, memory,
    Ctrl-D polling) was ported off <dos.h> and now builds and runs on
    both Win32 and POSIX (Linux/macOS):

      Win32  : CreateFile/ReadFile/WriteFile, FindFirstFile, _kbhit
      POSIX  : termios + read/write, glob(), select() on stdin

    Improvements over the straight port:
      - serial port and baud rate are runtime options (-p / -b)
      - 128K/512K disk mode: -1 / -5 flag, plus auto-switch on the driver's
        'S' handshake at INIT (like APLINKS for Win32)
      - file paths use PATH_MAX-sized buffers (no 8.3 truncation)
      - fopen()/Win32/termios failures are checked, not assumed
      - hidden/system files are skipped like the original _A_NORMAL

    Build:
      Windows : gcc -x c -std=c17 -O2 -o aplinks32_c17.exe APLINKS_C17.C
      POSIX   : cc  -std=c17 -O2 -o aplinks_c17 APLINKS_C17.C

    (The ".C" extension makes the gcc/clang driver assume C++; pass -x c.)

***************************************************************/

#define _CRT_SECURE_NO_WARNINGS   /* quiet MSVC's fopen/strcpy nags */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <stdarg.h>
#include <stdbool.h>
#include <assert.h>
#include <signal.h>
#include <sys/stat.h>

#ifdef _WIN32
#  include <windows.h>
#  include <conio.h>
#  include <sys/utime.h>
#  define PATH_BUF     MAX_PATH
#  define DEFAULT_PORT "COM1"        /* use "\\\\.\\COM10" for ports > COM9 */
#else
#  include <limits.h>
#  include <glob.h>
#  include <sys/stat.h>
#  include <utime.h>
#  include <sys/select.h>
#  include <sys/time.h>
#  include <termios.h>
#  include <fcntl.h>
#  include <unistd.h>
#  include <sys/ioctl.h>
#  ifndef PATH_MAX
#    define PATH_MAX 4096
#  endif
#  define PATH_BUF     PATH_MAX
#  define DEFAULT_PORT "/dev/ttyUSB0"
#endif

#define VERSION      "1.04"         /* version of this modernized server     */

#define DEFAULT_BAUD 9600           /* PLINKC needs 9600 bps or faster, N,8,1 */

/* Disk geometry comes from the driver's mpb128 / mpb512 (see PLINKC.asm).
   The 512K support "just switches the MPB" (per PLINKC.DOCX): same protocol,
   only the layout changes.  Buffers are sized for the larger 512K layout and
   the active geometry is chosen at runtime by set_geometry(). */
#define MAX_SYSBUF       (80*128)   /* 512K system area (FAT + DIR), bytes */
#define MAX_DATA_SECTORS 4016       /* 512K number of data sectors         */

/* The buffers are sized for the larger (512K) layout; lock that invariant so a
   future geometry edit can't silently overflow them. */
static_assert( MAX_SYSBUF       == 80 * 128 , "MAX_SYSBUF must match the 512K system area" );
static_assert( MAX_DATA_SECTORS == 4016 ,     "MAX_DATA_SECTORS must match the 512K data area" );
static_assert( 44 * 128 <= MAX_SYSBUF ,       "the 128K system area must fit the buffer" );
static_assert( 980      <= MAX_DATA_SECTORS , "the 128K data area must fit data_sector[]" );

struct data_buffer {
    char    buffer[128];
};

char	buffer[130];
char	system_buffer[MAX_SYSBUF + 1];
int	last_fat_number, current_dir;
FILE	*source_fd;
struct data_buffer *data_sector[MAX_DATA_SECTORS], *temp_buffer_ptr;
char	filename[PATH_BUF];

/* Active disk geometry (defaults to 128K; changed by set_geometry()). */
bool	g_mode512      = false;    /* false = 128K, true = 512K           */
int	g_data_start   = 44;       /* first data sector (= sysbuf / 128)  */
int	g_dir_top      = 12 * 128; /* byte offset of the directory area   */
int	g_data_sectors = 980;      /* number of data sectors              */
int	g_sysbufsize   = 44 * 128; /* bytes of system area (FAT + DIR)    */
int	g_fat_bound    = 982;      /* data_sectors + 2 (take_file guard)  */
int	g_loaded       = 0;        /* files preloaded so far (a count)    */
bool	g_verbose      = false;    /* -v : log every command + sector     */
bool	g_rts          = true;     /* RTS line: ON. The pocket only         */
				   /* transmits when its CS (=PC RTS) is    */
				   /* high, so RTS must be ON to receive.   */
bool	g_dtr          = false;    /* DTR line: OFF (known-good default)   */
const char *g_diskdir  = NULL;     /* -d : PC folder used as the virtual disk */
FILE   *g_logfile      = NULL;     /* -l : tee the verbose log to this file    */

/* Session history: a timestamped log of high-level actions (start, preload,
   per-connection read/write counts, files saved, disconnects).  Shown on
   demand with the 'h' key and automatically at exit. */
#define HIST_MAX  1000
#define HIST_LINE 128
char	g_history[HIST_MAX][HIST_LINE];
int	g_history_n    = 0;
int	g_conn_reads   = 0;        /* read commands in the current connection  */
int	g_conn_writes  = 0;        /* write commands in the current connection */

/* Preload spec, remembered so the disk can be re-loaded after a disconnect. */
int	g_pre_argc     = 0;
char  **g_pre_argv     = NULL;
int	g_pre_first     = 0;

void usage(const char *prog);
static void print_banner(FILE *out);
static int  disk_free_sectors(void);
static void print_free_space(void);
static void hist_add(const char *fmt, ...);
static void hist_print(void);
static void on_sigint(int sig);
void set_geometry(bool use512);
void epilogue(bool keep_serving);
static void vlog(const char *fmt, ...);
static void disk_path(const char *name, char *out, size_t outsz);
static void preload_disk(void);
static void reset_disk(void);
static void set_file_mtime(const char *path, time_t mt);
static void serial_purge(void);
void append_char(char *, char);
int  open_serial(const char *port, long baud);
unsigned char get_com(void);
void put_com(unsigned char);
void sread(int);
void swrite(int);
bool serial_data_ready(void);
int  poll_console(void);
#ifdef _WIN32
void get_pathname(char *, char *);
#endif
void get_basename(char *, char *);
void get_extension(char *, char *);
void put_fat(int, int);
int get_fat(int);
void get_memory(void);
void take_file(void);
int find_first(void);
int find_next(void);

int main(int argc, char *argv[])
{
    const char	   *port = DEFAULT_PORT;
    long	    baud = DEFAULT_BAUD;
    int		    start_mode = 0;   /* 0 = 128K, 1 = 512K */
    char	    sector_low, sector_high;
    int		    sector, i, cmd;
    int		    argn;
    time_t	    last_beat = 0;
    int		    dots_shown = 0;   /* a heartbeat '.' line is open */

    print_banner( stdout );
    signal( SIGINT , on_sigint );      /* Ctrl-C: report disk state, then quit */

    /* --- parse options: -p port, -b baud, -h help; rest are filenames --- */
    argn = 1;
    while ( argn < argc && argv[argn][0] == '-' ) {
	if ( strcmp( argv[argn] , "-p" ) == 0 && argn + 1 < argc ) {
	    port = argv[++argn];
	} else if ( strcmp( argv[argn] , "-b" ) == 0 && argn + 1 < argc ) {
	    baud = atol( argv[++argn] );
	} else if ( strcmp( argv[argn] , "-5" ) == 0 ) {
	    start_mode = 1;
	} else if ( strcmp( argv[argn] , "-1" ) == 0 ) {
	    start_mode = 0;
	} else if ( strcmp( argv[argn] , "-v" ) == 0 ) {
	    g_verbose = true;
	} else if ( strcmp( argv[argn] , "--rts" ) == 0 && argn + 1 < argc ) {
	    g_rts = ( strcmp( argv[++argn] , "off" ) != 0 );
	} else if ( strcmp( argv[argn] , "--dtr" ) == 0 && argn + 1 < argc ) {
	    g_dtr = ( strcmp( argv[++argn] , "on" ) == 0 );
	} else if ( strcmp( argv[argn] , "-d" ) == 0 && argn + 1 < argc ) {
	    g_diskdir = argv[++argn];
	} else if ( strcmp( argv[argn] , "-l" ) == 0 && argn + 1 < argc ) {
	    g_logfile = fopen( argv[++argn] , "w" );
	} else if ( strcmp( argv[argn] , "-h" ) == 0 || strcmp( argv[argn] , "--help" ) == 0 ) {
	    usage( argv[0] );
	    return( 0 );
	} else {
	    fprintf( stderr , "Unknown option: %s\n" , argv[argn] );
	    usage( argv[0] );
	    return( 1 );
	}
	argn++;
    }

    set_geometry( start_mode );

    /* Remember the preload spec so the disk can be reloaded on reconnect. */
    g_pre_argc  = argc;
    g_pre_argv  = argv;
    g_pre_first = argn;          /* first non-option argument (files, if any) */

    reset_disk();
    preload_disk();
    print_free_space();          /* disk usage after loading the disk folder */

    if ( open_serial( port , baud ) != 0 ) {
	fprintf( stderr , "\nCan\'t open serial port %s\n" , port );
	return( 1 );
    }

    printf( "\nPlink server started on %s (%ld bps), %s mode, RTS=%s DTR=%s.\n" ,
	    port , baud , g_mode512 ? "512K" : "128K" ,
	    g_rts ? "ON" : "OFF" , g_dtr ? "ON" : "OFF" );
    printf( "Disk folder: %s\n" , ( g_diskdir && g_diskdir[0] ) ? g_diskdir : "(current directory)" );
    printf( "Press 'h' for the session history; Ctrl-D to flush+quit, Ctrl-C to quit.\n" );
    hist_add( "Started: %s mode, %s @ %ld bps, folder \"%s\", %d file(s) loaded" ,
	      g_mode512 ? "512K" : "128K" , port , baud ,
	      ( g_diskdir && g_diskdir[0] ) ? g_diskdir : "." , g_loaded );
    if ( g_verbose ) {
	printf( "Verbose ON: '.' = idle heartbeat (server alive, waiting);\n"
		"each byte received from the pocket is logged below.\n" );
	fflush( stdout );
    }

    do {
	if ( ! g_verbose ) {
	    printf( "\rO" );
	}

	while( ! serial_data_ready() ) {
	    int key = poll_console();
	    if ( key == 0x04 ) {                    /* Ctrl-D: flush + quit */
		epilogue( false );
	    } else if ( key == 'h' || key == 'H' ) {  /* show session history */
		hist_print();
	    }
	    if ( g_verbose ) {
		time_t now = time( NULL );
		if ( now - last_beat >= 2 ) {
		    putchar( '.' );
		    fflush( stdout );
		    last_beat = now;
		    dots_shown = 1;
		}
	    }
	}

	cmd = get_com();
	/* Close any open heartbeat-dot line so each command starts fresh. */
	if ( g_verbose && dots_shown ) {
	    putchar( '\n' );
	    dots_shown = 0;
	}
	switch ( cmd ) {
		case 'R':
		    sector_low = get_com();
		    sector_high = get_com();
		    sector = (sector_low & 0xff) + (sector_high & 0xff) * 256;
		    if ( g_verbose ) vlog( "[R] read  sector %4d\n" , sector );
		    else printf( "\rR" );
		    g_conn_reads++;  sread( sector );
		    for( i = 0; i <= 128 ; i++ ) {
			put_com( buffer[ i ] );
		    }
		    break;
		case 'W':
		    sector_low = get_com();
		    sector_high = get_com();
		    sector = (sector_low & 0xff) + (sector_high & 0xff) * 256;
		    for( i=0 ; i <= 129 ; i++ ) {
			buffer[i] = get_com();
		    }
		    if ( g_verbose ) {
			vlog( "[W] write sector %4d%s\n" , sector ,
			    (buffer[129] & 0xff) == 0xff ? "" : "   (BAD end marker!)" );
			fflush(stdout);
		    } else printf( "\rW" );
		    if ( (buffer[129] & 0xff) == 0xff ) {
			g_conn_writes++;  swrite( sector );
			put_com( 0 );
		    }
		    break;
		case 'S':
		    /* Size negotiation sent by the driver at INIT: 'S' then
		       '1' (128K) or '5' (512K).  Auto-switch an empty disk. */
		    {
			unsigned char sz = get_com();
			bool want512 = ( sz == '5' );
			if ( g_verbose ) {
			    vlog( "[S] INIT handshake: '%c' -> %s mode\n" ,
				sz , ( sz == '5' ) ? "512K" : "128K" );
			    fflush(stdout);
			}
			if ( g_loaded == 0 ) {
			    set_geometry( want512 );
			    current_dir = g_dir_top;
			    if ( ! g_verbose ) printf( "\r[%s]" , g_mode512 ? "512K" : "128K" );
			} else if ( want512 != g_mode512 ) {
			    fprintf( stderr ,
				"\nWarning: pocket asked for %s but disk was preloaded in %s; keeping %s.\n" ,
				want512 ? "512K" : "128K" ,
				g_mode512 ? "512K" : "128K" ,
				g_mode512 ? "512K" : "128K" );
			}
		    }
		    break;
		case 'D':
		    if ( g_verbose ) vlog( "[D] disconnect -> flushing files to disk\n" );
		    epilogue( true );       /* flush, then keep serving */
		    break;
		default:
		    /* The driver should only send R/W/S/D (and 'I'+zeros at
		       clear).  Anything else logged here means the server does
		       not answer a command the pocket is waiting on. */
		    if ( g_verbose ) {
			if ( cmd != 0 ) vlog( "[?] ignored stray byte 0x%02x\n" , (unsigned char)cmd );
			fflush(stdout);
		    }
		    break;
	}
    } while (1);
}

void usage(const char *prog)
{
    print_banner( stderr );
    fprintf( stderr ,
	"Usage: %s [-p port] [-b baud] [file ...]\n"
	"  -p port   serial device        (default %s)\n"
	"  -b baud   bps: 9600/19200/...   (default %d)\n"
	"  -1        128K disk mode        (default)\n"
	"  -5        512K disk mode\n"
	"  -v        verbose: log every command and sector number\n"
	"  -d dir    PC folder used as the virtual disk (auto-loads its files;\n"
	"            flushes back to it). Default: current directory.\n"
	"  -l file   also write the verbose log to 'file'\n"
	"  --rts on|off  RTS line (default on; the pocket needs it to transmit)\n"
	"  --dtr on|off  DTR line (default off)\n"
	"  file ...  specific host files to preload (instead of the whole folder)\n" ,
	prog , DEFAULT_PORT , DEFAULT_BAUD );
}

void set_geometry(bool use512)
/* Select the 128K or 512K disk layout, mirroring the driver's mpb128 / mpb512.
   Only the geometry changes; the on-wire protocol is identical in both modes. */
{
    if ( use512 ) {
	g_data_start   = 80;
	g_dir_top      = 48 * 128;
	g_data_sectors = 4016;
    } else {
	g_data_start   = 44;
	g_dir_top      = 12 * 128;
	g_data_sectors = 980;
    }
    g_sysbufsize = g_data_start * 128;
    g_fat_bound  = g_data_sectors + 2;
    g_mode512    = use512;
}

/*======================================================================
	Helpers : logging, disk folder, preload/reset, timestamps
======================================================================*/

static void vlog(const char *fmt, ...)
/* Print a verbose line to the console and (if -l) also to the log file. */
{
    va_list ap;

    va_start( ap , fmt ); vprintf( fmt , ap ); va_end( ap );
    fflush( stdout );
    if ( g_logfile ) {
	va_start( ap , fmt ); vfprintf( g_logfile , fmt , ap ); va_end( ap );
	fflush( g_logfile );
    }
}

static void print_banner(FILE *out)
/* Program identity: original author, this update, and the version. */
{
    fprintf( out , "<<< Aplinks ... Another pocket link file server Version %s   (c)1992,93 N.Kon >>>\n" , VERSION );
    fprintf( out , "<<< (c) 2026 Updating Jean-Francois Albouy >>>\n\n" );
}

static int disk_free_sectors(void)
/* Number of free data sectors, from the FAT (entry 0 = free cluster). */
{
    int	    n, free_sectors = 0;

    for ( n = 2 ; n < 2 + g_data_sectors ; n++ ) {
	if ( get_fat( n ) == 0 ) {
	    free_sectors++;
	}
    }
    return( free_sectors );
}

static void print_free_space(void)
/* Report the free space left on the virtual disk (counts BOTH preloaded and
   pocket-written files, since it walks the FAT). */
{
    int	free_sectors = disk_free_sectors();

    printf( "Disk free: %ld KB of %ld KB (%.1f%%)\n" ,
	    (long)free_sectors   * 128 / 1024 ,
	    (long)g_data_sectors * 128 / 1024 ,
	    ( g_data_sectors > 0 ) ? ( 100.0 * free_sectors / g_data_sectors ) : 0.0 );
    fflush( stdout );
}

static void hist_add(const char *fmt, ...)
/* Append a timestamped line to the session history. */
{
    va_list	ap;
    time_t	now;
    struct tm  *t;
    int		off;

    if ( g_history_n >= HIST_MAX ) {
	return;
    }
    now = time( NULL );
    t   = localtime( &now );
    off = ( t != NULL ) ? (int)strftime( g_history[g_history_n] , 12 , "%H:%M:%S  " , t ) : 0;
    va_start( ap , fmt );
    vsnprintf( g_history[g_history_n] + off , HIST_LINE - off , fmt , ap );
    va_end( ap );
    g_history_n++;
}

static void hist_print(void)
/* Show the whole session history (also to the -l log file, if any). */
{
    int	i;

    printf( "\n===== Session history: %d event(s) =====\n" , g_history_n );
    for ( i = 0 ; i < g_history_n ; i++ ) {
	printf( "  %s\n" , g_history[i] );
    }
    printf( "========================================\n" );
    fflush( stdout );
    if ( g_logfile ) {
	fprintf( g_logfile , "\n===== Session history: %d event(s) =====\n" , g_history_n );
	for ( i = 0 ; i < g_history_n ; i++ ) {
	    fprintf( g_logfile , "  %s\n" , g_history[i] );
	}
	fflush( g_logfile );
    }
}

static void on_sigint(int sig)
/* Ctrl-C: show the disk state + history and quit.  Files are NOT flushed here
   - use Ctrl-D (or INIT "L:D" on the pocket) to save them. */
{
    (void)sig;
    printf( "\n" );
    if ( g_conn_reads || g_conn_writes ) {
	hist_add( "Interrupted mid-session: %d read(s), %d write(s)" , g_conn_reads , g_conn_writes );
    }
    hist_add( "Stopped (Ctrl-C) - unsaved changes discarded" );
    print_free_space();
    hist_print();
    printf( "Interrupted - files NOT saved (use Ctrl-D or INIT \"L:D\" to save).\n" );
    exit( 0 );
}

static void disk_path(const char *name, char *out, size_t outsz)
/* Build the PC path for "name" inside the disk folder (-d), or as-is if none. */
{
    if ( g_diskdir && g_diskdir[0] ) {
#ifdef _WIN32
	snprintf( out , outsz , "%s\\%s" , g_diskdir , name );
#else
	snprintf( out , outsz , "%s/%s" , g_diskdir , name );
#endif
    } else {
	snprintf( out , outsz , "%s" , name );
    }
}

static void preload_one_pattern(const char *pattern)
/* Load every PC file matching "pattern" (inside the disk folder) into RAM. */
{
    int found;

    disk_path( pattern , filename , sizeof filename );
    found = find_first();
    while ( found == 0 ) {
	if ( ( source_fd = fopen( filename , "rb" ) ) == NULL ) {
	    printf( "Can't open \"%s\". Skip this file\n" , filename );
	} else {
	    take_file();
	    fclose( source_fd );
	}
	found = find_next();
    }
}

static void preload_disk(void)
/* Fill the virtual disk: explicit files if listed, else every file in the
   disk folder (-d).  With neither, the disk simply starts empty. */
{
    if ( g_pre_first < g_pre_argc ) {
	int argn;
	for ( argn = g_pre_first ; argn < g_pre_argc ; argn++ ) {
	    preload_one_pattern( g_pre_argv[argn] );
	}
    } else if ( g_diskdir && g_diskdir[0] ) {
	preload_one_pattern( "*" );
    }
}

static void reset_disk(void)
/* Empty the virtual disk (free sectors, clear FAT/DIR, reset counters). */
{
    int i;

    for ( i = 0 ; i < MAX_DATA_SECTORS ; i++ ) {
	if ( data_sector[i] != NULL ) {
	    free( data_sector[i] );
	    data_sector[i] = NULL;
	}
    }
    for ( i = 0 ; i < MAX_SYSBUF ; i++ ) {
	system_buffer[i] = 0;
    }
    system_buffer[0] = (char)0xf0;
    current_dir     = g_dir_top;
    last_fat_number = 2;
    g_loaded        = 0;
}

static unsigned fat_date_of(const struct tm *t)
{
    int y = t->tm_year + 1900;
    if ( y < 1980 ) y = 1980;
    return ( ( (unsigned)(y - 1980) ) << 9 )
	 | ( ( (unsigned)t->tm_mon + 1 ) << 5 )
	 |   ( (unsigned)t->tm_mday );
}

static unsigned fat_time_of(const struct tm *t)
{
    return ( (unsigned)t->tm_hour << 11 )
	 | ( (unsigned)t->tm_min  << 5 )
	 | ( (unsigned)t->tm_sec  / 2 );
}

static void set_file_mtime(const char *path, time_t mt)
{
#ifdef _WIN32
    struct _utimbuf ub;
#else
    struct utimbuf  ub;
#endif
    ub.actime  = mt;
    ub.modtime = mt;
#ifdef _WIN32
    _utime( path , &ub );
#else
    utime( path , &ub );
#endif
}

void epilogue(bool keep_serving)
/* Flush pocket-created files (dir attribute 0x20) to the disk folder.  With
   keep_serving, empty and reload the disk and return to keep the port open for
   the next connection; otherwise exit. */
{
	    int	    i, j, fat_number, current_dir, condition;
	    char    filename[256];
	    char    outpath[PATH_BUF];
	    long    file_size, saved_size;

	    printf( "\r*\nDisconnect - syncing files to disk...\n" );
	    if ( g_conn_reads || g_conn_writes ) {
		hist_add( "Connection: %d read(s), %d write(s)" , g_conn_reads , g_conn_writes );
		g_conn_reads = g_conn_writes = 0;
	    }
	    current_dir = g_dir_top;
	    while ( current_dir < g_sysbufsize ) {
		if ( ( system_buffer[ current_dir ] != 0 ) && ( (system_buffer[ current_dir ] & 0xff) != 0xe5 ) && ( system_buffer[ current_dir + 0x0b ] == 0x20 ) ) {
		    strcpy( filename , "" );
		    for( i = 0 ; i <= 7 ; i++ ) {
			if ( system_buffer[ current_dir + i ] != ' ' ) {
			    append_char( filename , system_buffer[ current_dir + i ] );
			} else {
			    break;
			}
		    }
		    strcat( filename , "." );
		    for( i = 0 ; i <= 2 ; i++ ) {
			if ( system_buffer[ current_dir + i + 8 ] != ' ' ) {
			    append_char( filename , system_buffer[ current_dir + i + 8 ] );
			} else {
			    break;
			}
		    }

		    file_size = system_buffer[ current_dir + 0x1c ] & 0xff;
		    file_size += ( system_buffer[ current_dir + 0x1d ] & 0xff ) * 0x100L;
		    file_size += ( system_buffer[ current_dir + 0x1e ] & 0xff ) * 0x10000L;
		    saved_size = file_size;

		    disk_path( filename , outpath , sizeof outpath );
		    if ( ( source_fd = fopen( outpath , "wb" ) ) == NULL ) {
			printf("Can\'t open \"%s\". Skip this file\n" , outpath );
		    } else {
			printf( "Writing \"%s\" ... ", outpath );
			condition = 0;
			fat_number = system_buffer[ current_dir + 0x1a ] & 0xff;
			fat_number += ( system_buffer[ current_dir + 0x1b ] & 0xff ) * 0x100;
			do {
			    j = 128;
			    if ( file_size < 128 ) {
				j = (int)file_size;
			    }
			    for ( i = 1 ; i <= j ; i++ ) {
				if ( fputc( data_sector[ fat_number - 2 ] -> buffer[ i - 1 ] , source_fd ) == EOF ) {
				    condition = EOF;
				}
			    }
			    file_size -= 128;
			    fat_number = get_fat( fat_number );
			} while ( fat_number != 0xff0 );
			fclose( source_fd );
			if ( condition != EOF ) {
			    /* Restore the file date/time from the directory entry. */
			    unsigned ft = ( system_buffer[ current_dir + 0x16 ] & 0xff )
					| ( ( system_buffer[ current_dir + 0x17 ] & 0xff ) << 8 );
			    unsigned fd = ( system_buffer[ current_dir + 0x18 ] & 0xff )
					| ( ( system_buffer[ current_dir + 0x19 ] & 0xff ) << 8 );
			    if ( fd != 0 ) {
				struct tm t;
				memset( &t , 0 , sizeof t );
				t.tm_year  = ( ( fd >> 9 ) & 0x7f ) + 1980 - 1900;
				t.tm_mon   = ( ( fd >> 5 ) & 0x0f ) - 1;
				t.tm_mday  =   ( fd & 0x1f );
				t.tm_hour  = ( ft >> 11 ) & 0x1f;
				t.tm_min   = ( ft >> 5 )  & 0x3f;
				t.tm_sec   = ( ft & 0x1f ) * 2;
				t.tm_isdst = -1;
				set_file_mtime( outpath , mktime( &t ) );
			    }
			    hist_add( "Saved \"%s\" (%ld bytes)" , filename , saved_size );
			    printf("done\n");
			} else {
			    printf("disk full. Skip this file\n");
			    remove( outpath );
			}
		    }
		}
		current_dir += 32;
	    }
	    printf("Sync done.\n");
	    hist_add( "Disconnected - %ld KB free" , (long)disk_free_sectors() * 128 / 1024 );

	    if ( keep_serving ) {
		reset_disk();
		preload_disk();      /* reload the folder for the next connection */
		print_free_space();
		serial_purge();
		printf("Ready for a new connection (Ctrl-D flush+quit, Ctrl-C quit, 'h' history).\n");
		return;
	    }
	    print_free_space();
	    hist_add( "Stopped (Ctrl-D) - files saved" );
	    hist_print();
	    exit(0);
}

/*======================================================================
	Platform layer : serial port + console
======================================================================*/

#ifdef _WIN32

static HANDLE serial_handle = INVALID_HANDLE_VALUE;

int open_serial(const char *port, long baud)
/* Open and configure the serial port. Returns 0 on success, -1 on error. */
{
    DCB		    dcb;
    COMMTIMEOUTS    timeouts;

    serial_handle = CreateFileA( port , GENERIC_READ | GENERIC_WRITE , 0 ,
				 NULL , OPEN_EXISTING , 0 , NULL );
    if ( serial_handle == INVALID_HANDLE_VALUE ) {
	return( -1 );
    }

    SetupComm( serial_handle , 4096 , 4096 );

    memset( &dcb , 0 , sizeof dcb );
    dcb.DCBlength = sizeof dcb;
    if ( ! GetCommState( serial_handle , &dcb ) ) {
	return( -1 );
    }
    dcb.BaudRate = (DWORD)baud;
    dcb.ByteSize = 8;
    dcb.Parity   = NOPARITY;
    dcb.StopBits = ONESTOPBIT;
    dcb.fBinary  = TRUE;
    dcb.fParity  = FALSE;
    /* No software OR hardware output flow control. PLINK carries raw binary
       sectors, so XON/XOFF (0x11/0x13) must NOT be interpreted; match this on
       the pocket with OPEN "9600,N,8,1,A,L,&1A,N,N" (flow field N, not X). */
    dcb.fOutX             = FALSE;
    dcb.fInX              = FALSE;
    dcb.fOutxCtsFlow      = FALSE;
    dcb.fOutxDsrFlow      = FALSE;
    dcb.fDsrSensitivity   = FALSE;
    dcb.fTXContinueOnXoff = FALSE;
    /* Control lines, per the known-good Sharp serial tool (Tech Ref p.54): the
       pocket transmits ONLY while its CS input is high, and CS is driven by the
       PC's RTS.  So RTS must be ON or the PC receives nothing; DTR stays OFF.
       Overridable with --rts / --dtr. */
    dcb.fRtsControl = g_rts ? RTS_CONTROL_ENABLE : RTS_CONTROL_DISABLE;
    dcb.fDtrControl = g_dtr ? DTR_CONTROL_ENABLE : DTR_CONTROL_DISABLE;
    if ( ! SetCommState( serial_handle , &dcb ) ) {
	return( -1 );
    }

    /* Blocking, one-byte-at-a-time reads (timeouts all zero = wait for data) */
    memset( &timeouts , 0 , sizeof timeouts );
    if ( ! SetCommTimeouts( serial_handle , &timeouts ) ) {
	return( -1 );
    }

    PurgeComm( serial_handle , PURGE_TXCLEAR | PURGE_RXCLEAR );
    return( 0 );
}

static void serial_purge(void)
{
    PurgeComm( serial_handle , PURGE_TXCLEAR | PURGE_RXCLEAR );
}

unsigned char get_com(void)
/* Get a charactor from the serial port (blocking) */
{
    unsigned char   c;
    DWORD	    n;

    do {
	if ( ! ReadFile( serial_handle , &c , 1 , &n , NULL ) ) {
	    fprintf( stderr , "\nSerial read error\n" );
	    exit(1);
	}
    } while ( n != 1 );
    return( c );
}

void put_com(unsigned char c)
/* Put a charactor to the serial port */
{
    DWORD   n;

    if ( ! WriteFile( serial_handle , &c , 1 , &n , NULL ) || n != 1 ) {
	fprintf( stderr , "\nSerial write error\n" );
	exit(1);
    }
}

bool serial_data_ready(void)
/* Return 1 if at least one byte is waiting in the serial input queue. */
{
    COMSTAT	stat;
    DWORD	errors;

    if ( ! ClearCommError( serial_handle , &errors , &stat ) ) {
	return( false );
    }
    return( stat.cbInQue > 0 );
}

int poll_console(void)
/* Return a key pressed on the console (0 if none). */
{
    if ( _kbhit() ) {
	return( _getch() );
    }
    return( 0 );
}

#else  /* ---------------- POSIX ---------------- */

static int serial_fd = -1;

static speed_t baud_to_speed(long baud)
{
    switch ( baud ) {
	case 1200:   return( B1200 );
	case 2400:   return( B2400 );
	case 4800:   return( B4800 );
	case 9600:   return( B9600 );
	case 19200:  return( B19200 );
	case 38400:  return( B38400 );
	case 57600:  return( B57600 );
	case 115200: return( B115200 );
	default:     return( B9600 );
    }
}

int open_serial(const char *port, long baud)
/* Open and configure the serial port. Returns 0 on success, -1 on error. */
{
    struct termios  tio;
    speed_t	    sp;

    serial_fd = open( port , O_RDWR | O_NOCTTY );
    if ( serial_fd < 0 ) {
	return( -1 );
    }
    if ( tcgetattr( serial_fd , &tio ) != 0 ) {
	return( -1 );
    }
    cfmakeraw( &tio );
    sp = baud_to_speed( baud );
    cfsetispeed( &tio , sp );
    cfsetospeed( &tio , sp );
    tio.c_cflag |= ( CLOCAL | CREAD );
    tio.c_cflag &= ~PARENB;
    tio.c_cflag &= ~CSTOPB;
    tio.c_cflag &= ~CSIZE;
    tio.c_cflag |= CS8;
    tio.c_cc[VMIN]  = 1;   /* block until at least 1 byte */
    tio.c_cc[VTIME] = 0;
    if ( tcsetattr( serial_fd , TCSANOW , &tio ) != 0 ) {
	return( -1 );
    }
    /* Control lines: RTS must be ON for the pocket to transmit; DTR OFF.
       (See the Win32 branch for the why.) Overridable with --rts / --dtr. */
    {
	int mstat = 0;
	if ( ioctl( serial_fd , TIOCMGET , &mstat ) == 0 ) {
	    if ( g_rts ) mstat |= TIOCM_RTS; else mstat &= ~TIOCM_RTS;
	    if ( g_dtr ) mstat |= TIOCM_DTR; else mstat &= ~TIOCM_DTR;
	    ioctl( serial_fd , TIOCMSET , &mstat );
	}
    }
    return( 0 );
}

static void serial_purge(void)
{
    tcflush( serial_fd , TCIOFLUSH );
}

unsigned char get_com(void)
/* Get a charactor from the serial port (blocking) */
{
    unsigned char   c;
    ssize_t	    n;

    do {
	n = read( serial_fd , &c , 1 );
	if ( n < 0 ) {
	    fprintf( stderr , "\nSerial read error\n" );
	    exit(1);
	}
    } while ( n != 1 );
    return( c );
}

void put_com(unsigned char c)
/* Put a charactor to the serial port */
{
    if ( write( serial_fd , &c , 1 ) != 1 ) {
	fprintf( stderr , "\nSerial write error\n" );
	exit(1);
    }
}

bool serial_data_ready(void)
/* Return 1 if at least one byte is waiting on the serial port. */
{
    fd_set	    r;
    struct timeval  tv;

    tv.tv_sec = 0;
    tv.tv_usec = 0;
    FD_ZERO( &r );
    FD_SET( serial_fd , &r );
    return( select( serial_fd + 1 , &r , NULL , NULL , &tv ) > 0 && FD_ISSET( serial_fd , &r ) );
}

int poll_console(void)
/* Return a key available on stdin (0 if none). */
{
    fd_set	    r;
    struct timeval  tv;
    unsigned char   c;

    tv.tv_sec = 0;
    tv.tv_usec = 0;
    FD_ZERO( &r );
    FD_SET( STDIN_FILENO , &r );
    if ( select( STDIN_FILENO + 1 , &r , NULL , NULL , &tv ) > 0 && FD_ISSET( STDIN_FILENO , &r ) ) {
	if ( read( STDIN_FILENO , &c , 1 ) == 1 ) {
	    return( c );
	}
    }
    return( 0 );
}

#endif  /* _WIN32 */

/*====================================================================*/

void sread(int sector)
/* Read datas from virtual disk and set it to "BUFFER" */
{
    int	    i;

    if ( sector >= g_data_start ) {
	if ( data_sector[ sector - g_data_start ] == NULL ) {
	    get_memory();
	    data_sector[ sector - g_data_start ] = temp_buffer_ptr;
	}
	for( i = 0 ; i <= 127 ; i++ ) {
	    buffer[i] = data_sector[ sector - g_data_start ] -> buffer[i];
	}
    } else {
	for( i = 0 ; i <= 128 ; i++ ) {
	    buffer[i] = system_buffer[sector * 128 + i];
	}
    }
}

void swrite(int sector)
/* Write datas of "BUFFER" to the virtual disk */
{
    int	    i;

    if ( sector >= g_data_start ) {
	if ( data_sector[ sector - g_data_start ] == NULL ) {
	    get_memory();
	    data_sector[ sector - g_data_start ] = temp_buffer_ptr;
	}
	for( i = 0 ; i <= 127 ; i++ ) {
	    data_sector[ sector - g_data_start ] -> buffer[i] = buffer[i];
	}
    } else {
	for( i = 0 ; i <= 128 ; i++ ) {
	    system_buffer[sector * 128 + i] = buffer[i];
	}
    }
}

void append_char( char *s , char c )
/* Append one character to the end of string "s" (avoids the original,
   undefined self-overlapping sprintf(s,"%s%c",s,c) idiom) */
{
    size_t  l = strlen( s );

    s[ l ] = c;
    s[ l + 1 ] = '\0';
}

#ifdef _WIN32
void get_pathname( char *pathname , char *filename )
/* Set the directory part of "filename" to "pathname" (Win32 only: FindFirstFile
   returns bare names, so the pattern's directory has to be prepended). */
{
    int	    i, max;

    strcpy( pathname , "" );
    max = -1;
    for( i = 0 ; i < (int)strlen( filename ) ; i++ ) {
	if ( ( filename[i] == ':' ) || ( filename[i] == '\\' ) || ( filename[i] == '/' ) ) {
	    max = i;
	}
    }

    for( i = 0 ; i <= max ; i++ ) {
	append_char( pathname , filename[i] );
    }
}
#endif

void get_basename( char *basename , char *filename )
/* Set the basename of "filename" to "basename" */
{
    char    temp_str[PATH_BUF];
    char    *p;
    int	    i;

    strcpy( temp_str , filename );
    if ( ( p = strrchr( temp_str , ':' ) )  != NULL ) strcpy( temp_str , p + 1 );
    if ( ( p = strrchr( temp_str , '\\' ) ) != NULL ) strcpy( temp_str , p + 1 );
    if ( ( p = strrchr( temp_str , '/' ) )  != NULL ) strcpy( temp_str , p + 1 );
    strcpy( basename , "" );
    for( i = 0 ; (i <= 7) && (temp_str[i] != '\0') ; i++ ) {
	if ( temp_str[i] != '.' ) {
	    append_char( basename , temp_str[i] );
	} else {
	    break;
	}
    }
    strcat( basename , "        " );
}

void get_extension( char *extension , char *filename )
/* Set the extension of "filename" to "extension" */
{
    char    temp_str[PATH_BUF];
    char    *p;

    strcpy( temp_str , filename );
    if ( ( p = strrchr( temp_str , ':' ) )  != NULL ) strcpy( temp_str , p + 1 );
    if ( ( p = strrchr( temp_str , '\\' ) ) != NULL ) strcpy( temp_str , p + 1 );
    if ( ( p = strrchr( temp_str , '/' ) )  != NULL ) strcpy( temp_str , p + 1 );
    if ( ( p = strrchr( temp_str , '.' ) )  != NULL ) {
	strcpy( temp_str , p + 1 );
    } else {
	strcpy( temp_str , "" );
    }
    strcpy( extension , temp_str );
    strcat( extension , "        " );
}

void put_fat( int fat_number , int value )
/* Write a fat data "value" to where "fat_number" indicates */
{
    fat_number *= 3;
    if ( ( fat_number % 2 ) == 0 ) {
	system_buffer[ fat_number / 2 ] = value & 0xff;
	system_buffer[ fat_number / 2 + 1 ] = ( system_buffer[ fat_number / 2 + 1] & 0xf0 ) + value / 256;
    } else {
	system_buffer[ fat_number / 2 ] = ( system_buffer[ fat_number / 2 ] & 0xf ) + ( value & 0x0f ) * 16;
	system_buffer[ fat_number / 2 + 1 ] = value / 16;
    }
}

int get_fat( int fat_number )
/* Read a fat data from where "fat_number" indicates, and return it */
{
    int	    value;

    fat_number *= 3;
    if ( ( fat_number % 2 ) == 0 ) {
	value = system_buffer[ fat_number / 2 ] & 0xff;
	value += ( system_buffer[ fat_number / 2 + 1 ] & 0xf ) * 0x100;
    } else {
	value = ( system_buffer[ fat_number / 2 ] & 0xff ) / 16;
	value += ( system_buffer[ fat_number / 2 + 1 ] & 0xff ) * 16;
    }
    return( value );
}

void get_memory(void)
/* Get 128bytes from main-memory and set the pointer */
{
    temp_buffer_ptr = (struct data_buffer *) malloc( sizeof( struct data_buffer ) );
    if ( temp_buffer_ptr == NULL ) {
	printf( "\nCan\'t get enough memory\n" );
	exit(1);
    }
}

void take_file(void)
/* Take the DOS files into virtual disk */
{
    long    file_size;
    int	    i, read_count;
    char    basename[32], extension[32];
    bool    first_sector;

    printf( "Reading \"%s\" ... " , filename );

    if ( current_dir >= g_sysbufsize ) {
	printf( "Exceeded 128 directory. Skip this file\n");
	return;
    }

    fseek( source_fd , 0 , SEEK_END );
    file_size = ftell( source_fd );
    fseek( source_fd , 0 , SEEK_SET );

    read_count = 0;
    if ( ( ( file_size / 128 ) + 1 ) <= ( g_fat_bound - last_fat_number ) ) {
	get_basename( basename , filename );
	get_extension( extension , filename );

	for ( i = 0 ; i <= 7 ; i++ ) {
	    system_buffer[ current_dir + i ] = toupper( (unsigned char)basename[ i ] );
	}
	for ( i = 0 ; i <= 2 ; i++ ) {
	    system_buffer[ current_dir + i + 8 ] = toupper( (unsigned char)extension[ i ] );
	}
	system_buffer[ current_dir + 0x0b ] = 0x21;
	system_buffer[ current_dir + 0x1a ] = last_fat_number & 0xff;
	system_buffer[ current_dir + 0x1b ] = last_fat_number / 256;
	system_buffer[ current_dir + 0x1c ] = file_size & 0xff;
	system_buffer[ current_dir + 0x1d ] = ( file_size / 0x100 ) & 0xff;
	system_buffer[ current_dir + 0x1e ] = ( file_size / 0x10000 ) & 0xff;

	/* Stamp the directory entry with the PC file's modification date/time. */
	{
	    struct stat st;
	    if ( stat( filename , &st ) == 0 ) {
		struct tm *t = localtime( &st.st_mtime );
		if ( t != NULL ) {
		    unsigned fdate = fat_date_of( t );
		    unsigned ftime = fat_time_of( t );
		    system_buffer[ current_dir + 0x16 ] = ftime & 0xff;
		    system_buffer[ current_dir + 0x17 ] = ( ftime >> 8 ) & 0xff;
		    system_buffer[ current_dir + 0x18 ] = fdate & 0xff;
		    system_buffer[ current_dir + 0x19 ] = ( fdate >> 8 ) & 0xff;
		}
	    }
	}
	first_sector = true;

	while ( ( read_count = fread( buffer , sizeof( char ) , 128 , source_fd ) ) == 128 ) {
	    get_memory();
	    data_sector[ last_fat_number - 2 ] = temp_buffer_ptr;
	    for( i = 0 ; i < read_count ; i++ ) {
		temp_buffer_ptr -> buffer[i] = buffer[i];
	    }
	    if ( ! first_sector ) {
		put_fat( last_fat_number - 1 , last_fat_number );
	    } else {
		first_sector = false;
	    }
	    last_fat_number++;
	}
	get_memory();
	data_sector[ last_fat_number - 2 ] = temp_buffer_ptr;
	for( i = 0 ; i < read_count ; i++ ) {
	    temp_buffer_ptr -> buffer[i] = buffer[i];
	}
	if ( ! first_sector ) {
	    put_fat( last_fat_number - 1 , last_fat_number );
	} else {
	    first_sector = 0;
	}
	put_fat( last_fat_number , 0xff0 );
	last_fat_number++;
	current_dir += 32;
	g_loaded++;
	printf( "done\n" );
    } else {
	printf( "not enough disk. Skip this file\n" );
    }
}

/*======================================================================
	Platform layer : file pattern matching (host -> virtual disk)
======================================================================*/

#ifdef _WIN32

static HANDLE		find_handle = INVALID_HANDLE_VALUE;
static WIN32_FIND_DATAA	find_data;

static int store_current_match(void)
/* Skip directory/hidden/system entries (like the original _A_NORMAL); on the
   first ordinary file, build its full path into "filename".  Returns 0 on
   success, EOF when the enumeration is exhausted. */
{
    char    pathname[PATH_BUF];
    size_t  pl, nl;

    for ( ;; ) {
	DWORD a = find_data.dwFileAttributes;
	if ( ! ( a & ( FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM ) ) ) {
	    get_pathname( pathname , filename );
	    pl = strlen( pathname );
	    nl = strlen( find_data.cFileName );
	    if ( pl + nl < sizeof filename ) {
		memcpy( filename , pathname , pl );
		memcpy( filename + pl , find_data.cFileName , nl + 1 );
		return( 0 );
	    }
	    /* path too long for the buffer: fall through and skip it */
	}
	if ( ! FindNextFileA( find_handle , &find_data ) ) {
	    FindClose( find_handle );
	    find_handle = INVALID_HANDLE_VALUE;
	    return( EOF );
	}
    }
}

int find_first(void)
/* Start matching the glob pattern in "filename"; leave the first match there. */
{
    find_handle = FindFirstFileA( filename , &find_data );
    if ( find_handle == INVALID_HANDLE_VALUE ) {
	return( EOF );
    }
    return( store_current_match() );
}

int find_next(void)
/* Advance to the next match, leaving it in "filename". */
{
    if ( find_handle == INVALID_HANDLE_VALUE ) {
	return( EOF );
    }
    if ( ! FindNextFileA( find_handle , &find_data ) ) {
	FindClose( find_handle );
	find_handle = INVALID_HANDLE_VALUE;
	return( EOF );
    }
    return( store_current_match() );
}

#else  /* ---------------- POSIX ---------------- */

static glob_t	px_glob;
static size_t	px_index;
static int	px_active = 0;

static int store_current_match(void)
/* Advance px_index to the next regular file and copy its path to "filename".
   Returns 0 on success, EOF when the list is exhausted. */
{
    struct stat	st;

    while ( px_index < px_glob.gl_pathc ) {
	const char *p = px_glob.gl_pathv[ px_index ];
	if ( stat( p , &st ) == 0 && S_ISREG( st.st_mode ) && strlen( p ) < sizeof filename ) {
	    strcpy( filename , p );
	    return( 0 );
	}
	px_index++;
    }
    return( EOF );
}

int find_first(void)
/* Expand the shell glob in "filename"; leave the first match there. */
{
    if ( px_active ) {
	globfree( &px_glob );
	px_active = 0;
    }
    if ( glob( filename , 0 , NULL , &px_glob ) != 0 ) {
	return( EOF );
    }
    px_active = 1;
    px_index = 0;
    return( store_current_match() );
}

int find_next(void)
/* Advance to the next match, leaving it in "filename". */
{
    px_index++;
    return( store_current_match() );
}

#endif  /* _WIN32 */
