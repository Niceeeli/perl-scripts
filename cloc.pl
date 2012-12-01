#!/usr/bin/env perl
# cloc -- Count Lines of Code {{{1
# Copyright (C) 2006 Northrop Grumman Corporation
# Author:  Al Danial <al.danial@gmail.com>
#          First release August 2006
#
# Includes code from:
#   - SLOCCount v2.26 
#     http://www.dwheeler.com/sloccount/
#     by David Wheeler.
#   - Regexp::Common v2.120
#     http://search.cpan.org/~abigail/Regexp-Common-2.120/lib/Regexp/Common.pm
#     by Damian Conway and Abigail
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details:
# http://www.gnu.org/licenses/gpl.txt
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# 1}}}
my $VERSION = 0.68;
require 5.006;
# use modules                                  {{{1
use warnings;
use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw { tempfile tempdir };
use File::Find;
use IO::File;

# Digest::MD5 isn't in the standard distribution. Use it only if installed.
my $HAVE_Digest_MD5;
BEGIN {
    if (eval "require Digest::MD5;") {
        $HAVE_Digest_MD5 = 1;
    } else {
        $HAVE_Digest_MD5 = 0;
        warn "Digest::MD5 not installed; will skip file uniqueness checks.\n";
    }
}

# Regexp::Common also isn't in the standard distribution.  It will
# be installed in a temp directory if necessary.
my $HAVE_Rexexp_Common;
BEGIN {
    if (eval "require Regexp::Common;") {
        $HAVE_Rexexp_Common = 1;
    } else {
        $HAVE_Rexexp_Common = 0;
    }
}

use Text::Tabs qw { expand };
#use Data::Dumper::Simple;
#use Data::Dumper;
use Cwd qw { cwd };
# 1}}}
# Usage information, options processing.       {{{1
my $script = basename $0;
my $usage  = "
Usage: $script [options] <file(s)/dir(s)> | <report files>

 Count physical lines of source code in the given files and/or
 recursively below the given directories.

 Options:
   --by_file                 Report results for every source file encountered
                             in addition to reporting by language.
   --categorized=<file>      Save names of categorized files to <file>.
   --counted=<file>          Save names of processed source files to <file>.
   --exclude_dir=<D1>[,D2,]  Exclude the given comma separated directories
                             D1, D2, D3, et cetera, from being scanned.  For
                             example  --exclude_dir=.cvs,.svn  will skip
                             all files that have /.csv/ or /.svn/ as part of 
                             their path.
   --exclude_lang=<L1>[,L2,] Exclude the given comma separated languages
                             L1, L2, L3, et cetera, from being counted.
   --extract_with=<cmd>      Use <cmd> to extract binary archive files (e.g.:
                             .tar.gz, .zip, .Z).  Use the literal '>FILE<' as 
                             a stand-in for the actual file(s) to be
                             extracted.  For example, to count lines of code
                             in the input files 
                                gcc-4.2.tar.gz  perl-5.8.8.tar.gz  
                             on Unix use  
                               --extract_with='gzip -dc >FILE< | tar xfv -'
                             and on Windows use: 
                               --extract_with=\"\\\"c:\\Program Files\\WinZip\\WinZip32.exe\\\" -e -o >FILE< .\"
                             (if you have WinZip installed there).
   --found=<file>            Save names of every file found to <file>.
   --ignored=<file>          Save names of ignored files and the reason they
                             were ignored to <file>.
   --print_filter_stages     Print to STDOUT processed source code before and 
                             after each filter is applied.
   --progress_rate=<n>       Show progress update after every <n> files are
                             processed (default <n>=100).
   --quiet                   Suppress all information messages except for
                             the final report.
   --report_file=<file>      Write the results to <file> instead of STDOUT.
   --read_lang_def=<file>    Load from <file> the language processing filters.
                             (see also --write_lang_def) then use these filters
                             instead of the built-in filters.
   --show_ext[=<ext>]        Print information about all known (or just the
                             given) file extensions and exit.
   --show_lang[=<lang>]      Print information about all known (or just the
                             given) languages and exit.
   --strip_comments=<ext>    For each file processed, write to the current
                             directory a version of the file which has blank
                             lines and comments removed.  The name of each
                             stripped file is the original file name with 
                             .<ext> appended to it.
   --sum_reports             Input arguments are report files previously
                             created with the --report_file option.  Makes
                             a cummulative set of results containing the
                             sum of data from the individual report files.
   --write_lang_def=<file>   Writes to <file. the language processing filters
                             then exits.  Useful as a first step to creating
                             custom language definitions (see --read_lang_def).
   -v[=<n>]                  Verbose switch (optional numeric value).
   --version                 Print the version of this program and exit.

";
$| = 1;  # flush STDOUT
my $start_time = time();
my ($opt_found, $opt_categorized, $opt_ignored, 
    $opt_counted, $opt_show_ext, $opt_show_lang, $opt_progress_rate, 
    $opt_print_filter_stages, $opt_v, $opt_version,
    $opt_exclude_lang, $opt_exclude_dir, 
    $opt_read_lang_def, $opt_write_lang_def,
    $opt_strip_comments, $opt_quiet, $opt_report_file, $opt_sum_reports,
    $opt_extract_with, $opt_by_file,
   );
GetOptions(
           "by_file"             => \$opt_by_file             ,
           "categorized=s"       => \$opt_categorized         ,
           "counted=s"           => \$opt_counted             ,
           "exclude_lang=s"      => \$opt_exclude_lang        ,
           "exclude_dir=s"       => \$opt_exclude_dir         ,
           "extract_with=s"      => \$opt_extract_with        , 
           "found=s"             => \$opt_found               ,
           "ignored=s"           => \$opt_ignored             ,
           "quiet"               => \$opt_quiet               ,
           "read_lang_def=s"     => \$opt_read_lang_def       ,
           "show_ext:s"          => \$opt_show_ext            ,
           "show_lang:s"         => \$opt_show_lang           ,
           "progress_rate=i"     => \$opt_progress_rate       ,
           "print_filter_stages" => \$opt_print_filter_stages ,
           "report_file=s"       => \$opt_report_file         ,
           "strip_comments=s"    => \$opt_strip_comments      ,
           "sum_reports"         => \$opt_sum_reports         ,
           "v:i"                 => \$opt_v                   ,
           "version"             => \$opt_version             ,
           "write_lang_def=s"    => \$opt_write_lang_def      ,
          );
my %Exclude_Language = ();
   %Exclude_Language = map { $_ => 1 } split(/,/, $opt_exclude_lang) 
        if $opt_exclude_lang;
my %Exclude_Dir      = ();
   %Exclude_Dir      = map { $_ => 1 } split(/,/, $opt_exclude_dir ) 
        if $opt_exclude_dir ;
# Options defaults:
$opt_progress_rate = 100 unless $opt_progress_rate;
$opt_v             =   0 unless $opt_v;
die $usage unless defined $opt_show_lang       or
                  defined $opt_show_ext        or
                  defined $opt_write_lang_def  or
                  scalar @ARGV >= 1;
# 1}}}
# Step 1:  Initialize global constants.        {{{1
#
my $nFiles_Found = 0;  # updated in make_file_list
my (%Language_by_Extension, %Language_by_Script,
    %Filters_by_Language, %Not_Code_Extension, %Not_Code_Filename,
    %Language_by_File, %Scale_Factor,
   );
my %Error_Codes = ( 'Unable to read'              => -1,
                    'Neither file nor directory'  => -2, );
if ($opt_read_lang_def) {
    read_lang_def(
        $opt_read_lang_def     , #        Sample values:
        \%Language_by_Extension, # Language_by_Extension{f}    = 'Fortran 77' 
        \%Language_by_Script   , # Language_by_Script{sh}      = 'Bourne Shell'
        \%Language_by_File     , # Language_by_File{makefile}  = 'Make'
        \%Filters_by_Language  , # Filters_by_Language{Bourne Shell}[0] = 
                                 #      [ 'remove_matches' , '^\s*#'  ]
        \%Not_Code_Extension   , # Not_Code_Extension{jpg}     = 1
        \%Not_Code_Filename    , # Not_Code_Filename{README}   = 1
        \%Scale_Factor         , # Scale_Factor{Perl}          = 4.0
        );
} else {
    set_constants(               #
        \%Language_by_Extension, # Language_by_Extension{f}    = 'Fortran 77' 
        \%Language_by_Script   , # Language_by_Script{sh}      = 'Bourne Shell'
        \%Language_by_File     , # Language_by_File{makefile}  = 'Make'
        \%Filters_by_Language  , # Filters_by_Language{Bourne Shell}[0] = 
                                 #      [ 'remove_matches' , '^\s*#'  ]
        \%Not_Code_Extension   , # Not_Code_Extension{jpg}     = 1
        \%Not_Code_Filename    , # Not_Code_Filename{README}   = 1
        \%Scale_Factor         , # Scale_Factor{Perl}          = 4.0
        );
}
# 1}}}
# Step 2:  Early exits for display, summation. {{{1
#
print_extension_info($opt_show_ext ) if defined $opt_show_ext ;
print_language_info( $opt_show_lang) if defined $opt_show_lang;
exit if (defined $opt_show_ext) or (defined $opt_show_lang);
if ($opt_sum_reports) {
    my %Results = ();
    foreach my $type( "by language", "by report file" ) {
        my $found_lang = combine_results(\@ARGV, 
                                          $type, 
                                         \%{$Results{ $type }}, 
                                         \%Filters_by_Language );
        next unless %Results;
        my $end_time = time();
        my @results  = generate_report($VERSION, $end_time - $start_time,
                                       $type,
                                      \%{$Results{ $type }}, \%Scale_Factor);
        if ($opt_report_file) {
            my $ext  = ".lang";
               $ext  = ".file" unless $type eq "by language";
            next if !$found_lang and  $ext  eq ".lang";
            write_file($opt_report_file . $ext, @results);
        } else {
            print "\n", join("\n", @results), "\n";
        }
    }
    exit;
}
if ($opt_write_lang_def) {
    write_lang_def($opt_write_lang_def   ,
                  \%Language_by_Extension,
                  \%Language_by_Script   ,
                  \%Language_by_File     ,
                  \%Filters_by_Language  ,
                  \%Not_Code_Extension   ,
                  \%Not_Code_Filename    ,
                  \%Scale_Factor         ,
                  );
    exit;
}
# 1}}}
# Step 3:  Create a list of files to consider. {{{1
#  a) If inputs are binary archives, first cd to a temp
#     directory, expand the archive with the user-given
#     extraction tool, then add the temp directory to
#     the list of dirs to process.
#  b) Create a list of every file that might contain source
#     code.  Ignore binary files, zero-sized files, and
#     any file in a directory the user says to exclude.
#  c) Determine the language for each file in the list.
#
if ($opt_extract_with) {
    my $cwd = cwd();
#print "cwd main = [$cwd]\n";
    my @extract_location = ();
    foreach my $bin_file (@ARGV) {
        my $extract_dir = tempdir( CLEANUP => 0 );  # 1 = delete on exit
        chdir $extract_dir;
        print "Using temp dir [$extract_dir] to extract $bin_file\n" 
            unless $opt_quiet;
        my $bin_file_full_path = "";
        if (File::Spec->file_name_is_absolute( $bin_file )) {
            $bin_file_full_path = $bin_file;
#print "bin_file_full_path (was ful) = [$bin_file_full_path]\n";
        } else {
            $bin_file_full_path = File::Spec->catfile( $cwd, $bin_file );
#print "bin_file_full_path (was rel) = [$bin_file_full_path]\n";
        }
        (my $extract_cmd = $opt_extract_with ) =~ s/>FILE</$bin_file_full_path/g;
        print  $extract_cmd, "\n";
        system $extract_cmd;
        push @extract_location, $extract_dir;
        chdir $cwd;
    }
    @ARGV = @extract_location;
}
my @Errors    = ();
my @file_list = ();  # global variable updated in files()
my %Ignored   = ();  # files that are not counted (language not recognized or
                     # problems reading the file)
my $fh = make_file_list(\@ARGV, \%Error_Codes, \@Errors, \%Ignored);
# 1}}}
# Step 4:  Remove duplicate files.             {{{1
#
my %Language           = ();
my %unique_source_file = ();
remove_duplicate_files($fh, \%Language   , \%unique_source_file, 
                            \%Error_Codes, \@Errors , \%Ignored);
printf "%8d unique file%s.            \n", 
    plural_form(scalar keys %unique_source_file) 
    unless $opt_quiet;
# 1}}}
# Step 5:  Count code, comments, blank lines.  {{{1
#
my %Results_by_Language = ();
my %Results_by_File     = ();
my $nCounted = 0;
foreach my $file (sort keys %unique_source_file) {
    ++$nCounted;
    printf "Counting:  %d\r", $nCounted unless $nCounted % $opt_progress_rate;
    next if $Ignored{$file};
    if ($Exclude_Language{$Language{$file}}) {
        $Ignored{$file} = "--exclude_lang=$Language{$file}";
        next;
    }
    if (!defined @{$Filters_by_Language{$Language{$file}} }) {
        if ($Language{$file} eq "(unknown)") {
            $Ignored{$file} = "language unknown (#1)";
        } else {
            $Ignored{$file} = "missing Filters_by_Language{$Language{$file}}";
        }
        next;
    }

    my ($all_line_count,
        $blank_count   ,
        $comment_count ,
       ) = call_counter($file, $Language{$file});
    my $code_count = $all_line_count - $blank_count - $comment_count;
    if ($opt_by_file) {
        $Results_by_File{$file}{'code'   } = $code_count     ;
        $Results_by_File{$file}{'blank'  } = $blank_count    ;
        $Results_by_File{$file}{'comment'} = $comment_count  ;
        $Results_by_File{$file}{'lang'   } = $Language{$file};
        $Results_by_File{$file}{'nFiles' } = 1;
    }

    ++$Results_by_Language{$Language{$file}}{'nFiles'};
    $Results_by_Language{$Language{$file}}{'code'}    += $code_count   ;
    $Results_by_Language{$Language{$file}}{'blank'}   += $blank_count  ;
    $Results_by_Language{$Language{$file}}{'comment'} += $comment_count;
}
my @ignored_reasons = map { "$_: $Ignored{$_}" } sort keys %Ignored;
write_file($opt_ignored, @ignored_reasons   ) if $opt_ignored;
write_file($opt_counted, sort keys %Language) if $opt_counted;
# 1}}}
# Step 6:  Print results.                      {{{1
#
my $end_time = time();
printf "%8d file%s ignored.\n", plural_form(scalar keys %Ignored) 
    unless $opt_quiet;
print_errors(\%Error_Codes, \@Errors) if @Errors;
exit unless %Results_by_Language;

my @results = generate_report($VERSION, $end_time - $start_time,
                              "by language",
                             \%Results_by_Language, \%Scale_Factor);
if ($opt_report_file) { write_file($opt_report_file, @results); } 
else                  { print "\n", join("\n", @results), "\n"; }

if ($opt_by_file) {
    my @results = generate_report($VERSION, $end_time - $start_time,
                                  "by file",
                                 \%Results_by_File, \%Scale_Factor);
    if ($opt_report_file) { write_file($opt_report_file, @results); } 
    else                  { print "\n", join("\n", @results), "\n"; }
}
# 1}}}

####################################################################
sub combine_results {                        # {{{1
    # returns 1 if the inputs are categorized by language
    #         0 if no identifiable language was found
    my ($ra_report_files, # in
        $report_type    , # in  "by language" or "by report file"
        $rhh_count      , # out count{TYPE}{nFiles|code|blank|comment|scaled}
        $rhaa_Filters_by_Language , # in
       ) = @_;

    my $found_language = 0;

    foreach my $file (@{$ra_report_files}) {
        my $IN = new IO::File $file, "r";
        if (!defined $IN) {
            warn "Unable to read $file; ignoring.\n";
            next;
        }
        while (<$IN>) {
            next if /^(http|Language|SUM|-----)/;
            if (m{^(.*?)\s+         # language
                   (\d+)\s+         # files
                   (\d+)\s+         # blank
                   (\d+)\s+         # comments
                   (\d+)\s+         # code
                   x\s+             # x
                   \d+\.\d+\s+      # scale
                   =\s+             # =
                   (\d+\.\d+)\s*    # scaled code
                   $}x) {
                if ($report_type eq "by language") {
                    next unless defined %{$rhaa_Filters_by_Language->{$1}};
                    # above test necessary to avoid trying to sum reports
                    # of reports (which have no language breakdown).
                    $found_language = 1;
                    $rhh_count->{$1   }{'nFiles' } += $2;
                    $rhh_count->{$1   }{'blank'  } += $3;
                    $rhh_count->{$1   }{'comment'} += $4;
                    $rhh_count->{$1   }{'code'   } += $5;
                    $rhh_count->{$1   }{'scaled' } += $6;
                } else {
                    $rhh_count->{$file}{'nFiles' } += $2;
                    $rhh_count->{$file}{'blank'  } += $3;
                    $rhh_count->{$file}{'comment'} += $4;
                    $rhh_count->{$file}{'code'   } += $5;
                    $rhh_count->{$file}{'scaled' } += $6;
                }
            }
        }
    }
    return $found_language;

} # 1}}}

####################################################################
sub generate_report {                        # {{{1
    # returns an array of lines containing the results
    my ($version    , # in
        $elapsed_sec, # in
        $report_type, # in  "by language" | "by report file" | "by file"
        $rhh_count  , # in  count{TYPE}{nFiles|code|blank|comment|scaled}
        $rh_scale   , # in
       ) = @_;

    my @results       = ();

    my $sum_files     = 0;
    my $sum_code      = 0;
    my $sum_blank     = 0;
    my $sum_comment   = 0;
    foreach my $language (keys %{$rhh_count}) {
        $sum_files   += $rhh_count->{$language}{'nFiles'} ;
        $sum_blank   += $rhh_count->{$language}{'blank'}  ;
        $sum_comment += $rhh_count->{$language}{'comment'};
        $sum_code    += $rhh_count->{$language}{'code'}   ;
    }
    my $sum_lines = $sum_blank + $sum_comment + $sum_code;
    $elapsed_sec = 0.5 unless $elapsed_sec;

    my $URL        = "http://cloc.sourceforge.net";
    my $hypen_line = sprintf "%s", '-' x 79;
    my $data_line  = "";
    my $first_column;
    my $BY_LANGUAGE = 0;
    my $BY_FILE     = 0;
    if      ($report_type eq "by language") {
        $first_column = "Language";
        $BY_LANGUAGE  = 1;
    } elsif ($report_type eq "by file")     {
        $first_column = "File";
        $BY_FILE      = 1;
    } else {
        $first_column = "Report File";
    }

    my $header_line  = sprintf "%s v %4.2f", $URL, $version;
       $header_line .= sprintf("  T=%.1f s (%.1f files/s, %.1f lines/s)",
        $elapsed_sec           ,
        $sum_files/$elapsed_sec,
        $sum_lines/$elapsed_sec) unless $opt_sum_reports;

    push @results, $header_line;

    push @results, $hypen_line;

    $data_line  = sprintf "%-13s ", $first_column          ;
    $data_line .= sprintf "%9s "  , "files" unless $BY_FILE;
    $data_line .= sprintf "%9s %9s %9s %8s   %14s",
        "blank"         ,
        "comments"      ,
        "code"          ,
        "scale"         ,
        "3rd gen. equiv";
    push @results, $data_line;
    push @results, $hypen_line;

    my $sum_scaled = 0;
    foreach my $lang_or_file (sort {
                                 $rhh_count->{$b}{'code'} <=>
                                 $rhh_count->{$a}{'code'}
                               }
                          keys %{$rhh_count}) {
        my ($factor, $scaled);
        if ($BY_LANGUAGE or $BY_FILE) {
            $factor = 1;
            if ($BY_LANGUAGE) {
                if (defined $rh_scale->{$lang_or_file}) {
                    $factor = $rh_scale->{$lang_or_file};
                } else {
                    warn "No scale factor for $lang_or_file; using 1.00";
                }
            } else { # by individual code file
                $factor = $rh_scale->{$rhh_count->{$lang_or_file}{'lang'}};
            }
            $scaled = $factor*$rhh_count->{$lang_or_file}{'code'};
        } else {
            $scaled =         $rhh_count->{$lang_or_file}{'scaled'};
            $factor = $scaled/$rhh_count->{$lang_or_file}{'code'};
        }
        $data_line  = sprintf "%-13s ", $lang_or_file;
        $data_line .= sprintf "%9d ", $rhh_count->{$lang_or_file}{'nFiles'} 
            unless $BY_FILE;
        $data_line .= sprintf "%9d %9d %9d x %6.2f = %14.2f",
            $rhh_count->{$lang_or_file}{'blank'}  ,
            $rhh_count->{$lang_or_file}{'comment'},
            $rhh_count->{$lang_or_file}{'code'}   ,
            $factor                           ,
            $scaled                           ;
        $sum_scaled  += $scaled;
        push @results, $data_line;
    }
    my $avg_scale = 1;  # weighted average of scale factors
       $avg_scale = $sum_scaled / $sum_code if $sum_code;
    push @results, $hypen_line;
    $data_line  = sprintf "%-13s ", "SUM:"  ;
    $data_line .= sprintf "%9d ", $sum_files
        unless $BY_FILE                     ;
    $data_line .= sprintf "%9d %9d %9d x %6.2f = %14.2f",
        $sum_blank   ,
        $sum_comment ,
        $sum_code    ,
        $avg_scale   ,
        $sum_scaled  ;
    push @results, $data_line;
    push @results, $hypen_line;

    return @results;
} # 1}}}

####################################################################
sub print_errors {                           # {{{1
    my ($rh_Error_Codes, # in
        $raa_errors    , # in
       ) = @_;

    my %error_string = reverse(%{$rh_Error_Codes});
    my $nErrors      = scalar @{$raa_errors};
    printf "\n%d error%s:\n", plural_form(scalar @Errors);
    for (my $i = 0; $i < $nErrors; $i++) {
        printf "%s:  %s\n", 
            $error_string{ $raa_errors->[$i][0] },
            $raa_errors->[$i][1] ;
    }
    print "\n";

} # 1}}}

####################################################################
sub write_lang_def {                         # {{{1
    my ($file                     ,
        $rh_Language_by_Extension , # in
        $rh_Language_by_Script    , # in
        $rh_Language_by_File      , # in
        $rhaa_Filters_by_Language , # in
        $rh_Not_Code_Extension    , # in
        $rh_Not_Code_Filename     , # in
        $rh_Scale_Factor          , # in
       ) = @_;

    my $OUT = new IO::File $file, "w";
    die "Unable to write to $file\n" unless defined $OUT;

    foreach my $language (sort keys %{$rhaa_Filters_by_Language}) {
        next if $language eq "MATLAB or Objective C";
        printf $OUT "%s\n", $language;
        foreach my $filter (@{$rhaa_Filters_by_Language->{$language}}) {
            printf $OUT "    filter %s", $filter->[0];
            printf $OUT " %s", $filter->[1] if defined $filter->[1];
            print  $OUT "\n";
        }
        foreach my $ext (sort keys %{$rh_Language_by_Extension}) {
            if ($language eq $rh_Language_by_Extension->{$ext}) {
                printf $OUT "    extension %s\n", $ext;
            }
        }
        foreach my $filename (sort keys %{$rh_Language_by_File}) {
            if ($language eq $rh_Language_by_File->{$filename}) {
                printf $OUT "    filename %s\n", $filename;
            }
        }
        foreach my $script_exe (sort keys %{$rh_Language_by_Script}) {
            if ($language eq $rh_Language_by_Script->{$script_exe}) {
                printf $OUT "    script_exe %s\n", $script_exe;
            }
        }
        printf $OUT "    3rd_gen_scale %.2f\n", $rh_Scale_Factor->{$language};
    }

    $OUT->close;
} # 1}}}

####################################################################
sub read_lang_def {                          # {{{1
    my ($file                     ,
        $rh_Language_by_Extension , # out
        $rh_Language_by_Script    , # out
        $rh_Language_by_File      , # out
        $rhaa_Filters_by_Language , # out
        $rh_Not_Code_Extension    , # out
        $rh_Not_Code_Filename     , # out
        $rh_Scale_Factor          , # out
       ) = @_;

    my $IN = new IO::File $file, "r";
    die "Unable to read $file.\n" unless defined $IN;

    my $language = "";
    while (<$IN>) {
        next if /^\s*#/ or /^\s*$/;

        if (/^(\w+.*?)\s*$/) {
            $language = $1;
            next;
        }
        die "Missing computer language name, line $. of $file\n"
            unless $language;

        if      (/^    filter\s+(\w+)\s*$/) {
            push @{$rhaa_Filters_by_Language->{$language}}, [ $1 ]

        } elsif (/^    filter\s+(\w+)\s+(.*?)\s*$/) {
            push @{$rhaa_Filters_by_Language->{$language}}, [ $1 , $2 ]

        } elsif (/^    extension\s+(\S+)\s*$/) {
            if (defined $rh_Language_by_Extension->{$1}) {
                die "File extension collision:  $1 ",
                    "maps to languages '$rh_Language_by_Extension->{$1}' ",
                    "and '$language'\n" ,
                    "Edit $file and remove $1 from one of these two ",
                    "language definitions.\n";
            }
            $rh_Language_by_Extension->{$1} = $language;

        } elsif (/^    filename\s+(\S+)\s*$/) {
            $rh_Language_by_File->{$1} = $language;

        } elsif (/^    script_exe\s+(\S+)\s*$/) {
            $rh_Language_by_Script->{$1} = $language;

        } elsif (/^    3rd_gen_scale\s+(\S+)\s*$/) {
            $rh_Scale_Factor->{$language} = $1;

        } else {
            die "Unexpected data line $. of $file:\n$_\n";
        }

    }
    $IN->close;
} # 1}}}

####################################################################
sub print_extension_info {                   # {{{1
    my ($extension,) = @_;
    if ($extension) {  # show information on this extension
        foreach my $ext (sort {lc $a cmp lc $b } keys %Language_by_Extension) {
            # Language_by_Extension{f}    = 'Fortran 77' 
            printf "%-12s -> %s\n", $ext, $Language_by_Extension{$ext}
                if $ext =~ m{$extension}i;
        }
    } else {           # show information on all  extensions
        foreach my $ext (sort {lc $a cmp lc $b } keys %Language_by_Extension) {
            # Language_by_Extension{f}    = 'Fortran 77' 
            printf "%-12s -> %s\n", $ext, $Language_by_Extension{$ext};
        }
    }
} # 1}}}

####################################################################
sub print_language_info {                    # {{{1
    my ($language,) = @_;
    my %extensions = (); # the subset matched by the given $language value
    if ($language) {  # show information on this language
        foreach my $ext (sort {lc $a cmp lc $b } keys %Language_by_Extension) {
            # Language_by_Extension{f}    = 'Fortran 77' 
            push @{$extensions{$Language_by_Extension{$ext}} }, $ext
                if $Language_by_Extension{$ext} =~ m{$language}i;
        }
    } else {          # show information on all  languages
        foreach my $ext (sort {lc $a cmp lc $b } keys %Language_by_Extension) {
            # Language_by_Extension{f}    = 'Fortran 77' 
            push @{$extensions{$Language_by_Extension{$ext}} }, $ext
        }
    }
    if (%extensions) {
        foreach my $lang (sort {lc $a cmp lc $b } keys %extensions) {
            printf "%-24s (%s)\n", $lang, join(", ", @{$extensions{$lang}});
        }
    }
} # 1}}}

####################################################################
sub make_file_list {                         # {{{1
    my ($ra_arg_list,  # in   file and/or directory names to examine
        $rh_Err     ,  # in   hash of error codes
        $raa_errors ,  # out  errors encountered
        $rh_ignored ,  # out  files not recognized as computer languages
        ) = @_;

    my ($fh, $filename);
    if ($opt_categorized) {
        $filename = $opt_categorized;
        $fh = new IO::File $filename, "+>";  # open for read/write
        die "Unable to write to $filename:  $!\n" unless defined $fh;
    } else {
        ($fh, $filename) = tempfile(UNLINK => 1);  # delete file on exit
        print "Using temp file list [$filename]\n" unless $opt_quiet;
    }

    my @dir_list = ();
    foreach my $file_or_dir (@{$ra_arg_list}) {
#print "make_file_list file_or_dir=$file_or_dir\n";
        my $size_in_bytes = 0;
        if (!-r $file_or_dir) {
            push @{$raa_errors}, [$rh_Err->{'Unable to read'} , $file_or_dir];
            next;
        }
        if      (is_file($file_or_dir)) {
            if (!(-s $file_or_dir)) {   # 0 sized file, named pipe, socket 
                $rh_ignored->{$file_or_dir} = 'zero sized file';
                next;
            } elsif (-B $file_or_dir) { # avoid binary files
                $rh_ignored->{$file_or_dir} = 'binary file';
                next;
            }
            push @file_list, "$file_or_dir";
        } elsif (is_dir ($file_or_dir)) {
            push @dir_list, $file_or_dir;
        } else {
            push @{$raa_errors}, [$rh_Err->{'Neither file nor directory'} , $file_or_dir];
            $rh_ignored->{$file_or_dir} = 'not file, not directory';
        }
    }
    foreach my $dir (@dir_list) {
#print "make_file_list dir=$dir\n";
        find(\&files, $dir);  # populates global variable @file_list
    }
    $nFiles_Found = scalar @file_list;
    printf "%8d text file%s.\n", plural_form($nFiles_Found) unless $opt_quiet;
    write_file($opt_found, sort @file_list) if $opt_found;

    my $nFiles_Categorized = 0;
    foreach my $file (@file_list) {
        printf "classifying $file\n" if $opt_v > 2;

        my $basename = basename $file;
        if ($Not_Code_Filename{$basename}) {
            $rh_ignored->{$file} = "listed in " . '$' .
                "Not_Code_Filename{$basename}";
            next;
        } elsif ($basename =~ m{~$}) {
            $rh_ignored->{$file} = "temporary editor file";
            next;
        }

        my $size_in_bytes = (stat $file)[7];
        my $language      = classify_file($file      ,
                                          $rh_Err    ,
                                          $raa_errors,
                                          $rh_ignored);
die  "make_file_list($file) undef size" unless defined $size_in_bytes;
die  "make_file_list($file) undef lang" unless defined $language;
        printf $fh "%d,%s,%s\n", $size_in_bytes, $language, $file;
        ++$nFiles_Categorized;
        printf "classified %d files\r", 
            $nFiles_Categorized unless $nFiles_Categorized % $opt_progress_rate;
    }
    printf "classified %d files\r", $nFiles_Categorized 
        if !$opt_quiet and $nFiles_Categorized > 1;

    return $fh;   # handle to the file containing the list of files to process
}  # 1}}}

####################################################################
sub remove_duplicate_files {                 # {{{1
    my ($fh                   , # in 
        $rh_Language          , # out
        $rh_unique_source_file, # out
        $rh_Err               , # in
        $raa_errors           , # out  errors encountered
        $rh_ignored           , # out
        ) = @_;

    # Check for duplicate files by comparing file sizes.
    # Where files are equally sized, compare their MD5 checksums.

    my $n = 0;
    my %files_by_size = (); # files_by_size{ # bytes } = [ list of files ]
    seek($fh, 0, 0); # rewind to beginning of the temp file
    while (<$fh>) {
        ++$n;
        my ($size_in_bytes, $language, $file) = split(/,/, $_, 3);
        chomp($file);
        $rh_Language->{$file} = $language;
        push @{$files_by_size{$size_in_bytes}}, $file;
    }
    if ($n > $opt_progress_rate) {
        printf "Duplicate file check %d files (%d known unique)\r", 
            $n, scalar keys %files_by_size;
    }
    $n = 0;
    foreach my $bytes (sort {$a <=> $b} keys %files_by_size) {
        ++$n;
        printf "Unique: %8d files                               \r", 
            $n unless $n % $opt_progress_rate;
        $rh_unique_source_file->{$files_by_size{$bytes}[0]} = 1;
        next unless scalar @{$files_by_size{$bytes}} > 1;
        foreach my $F (different_files(\@{$files_by_size{$bytes}},
                                        $rh_Err     ,
                                        $raa_errors ,
                                        $rh_ignored ) ) {
            $rh_unique_source_file->{$F} = 1;
        }
    }
} # 1}}}

####################################################################
sub files {                                  # {{{1
    # invoked by File::Find's find()   Populates global variable @file_list
    if ($opt_exclude_dir) {
        my $return = 0;
        foreach my $skip_dir (keys %Exclude_Dir) {
            if ($File::Find::dir =~ m{/$skip_dir(/|$)} ) {
                $Ignored{$File::Find::name} = "--exclude_dir=$skip_dir";
                $return = 1;
                last;
            }
        }
        return if $return;
    }
    my $nBytes = -s     $_ ;
    if (!$nBytes and $opt_v > 5) {
        printf "files(%s)  zero size\n", $File::Find::name;
    }
    return unless $nBytes  ; # attempting other tests w/pipe or socket will hang
    my $is_dir = is_dir($_);
    my $is_bin = -B     $_ ;
    printf "files(%s)  size=%d is_dir=%d  -B=%d\n",
        $File::Find::name, $nBytes, $is_dir, $is_bin if $opt_v > 5;
    return if $is_dir or $is_bin;
    ++$nFiles_Found;
    printf "%8d files\r", $nFiles_Found unless $nFiles_Found % $opt_progress_rate;
    push @file_list, $File::Find::name;
} # 1}}}

####################################################################
sub is_file {                                # {{{1
    # portable method to test if item is a file
    # (-f doesn't work in ActiveState Perl on Windows)
    my $item = shift @_;

    my $mode = (stat $item)[2];
       $mode = 0 unless $mode;
    if ($mode & 0100000) { return 1; } 
    else                 { return 0; }
} # 1}}}

####################################################################
sub is_dir {                                 # {{{1
    # portable method to test if item is a directory
    # (-d doesn't work in ActiveState Perl on Windows)
    my $item = shift @_;

    my $mode = (stat $item)[2];
       $mode = 0 unless $mode;
    if ($mode & 0040000) { return 1; } 
    else                 { return 0; }
} # 1}}}

####################################################################
sub classify_file {                          # {{{1
    my ($full_file   , # in
        $rh_Err      , # in   hash of error codes
        $raa_errors  , # out
        $rh_ignored  , # out
       ) = @_;

    print "-> classify_file($full_file)\n" if $opt_v > 2;
    my $language = "(unknown)";

    my $look_at_first_line = 0;
    my $file = basename $full_file; 
    return $language if $Not_Code_Filename{$file}; # (unknown)
    return $language if $file =~ m{~$}; # a temp edit file (unknown)

    if ($file =~ /\.(\w+)$/) { # has an extension
        print "$full_file extension=[$1]\n" if $opt_v > 2;
        my $extension = $1;
        if ($Not_Code_Extension{$extension}) {
            $rh_ignored->{$full_file} = 
                'listed in $Not_Code_Extension{' . $extension . '}';
            return $language;
        }
        if (defined $Language_by_Extension{$extension}) {
            if ($Language_by_Extension{$extension} eq
                'MATLAB or Objective C') {
                my $lang_M_or_O = "";
                matlab_or_objective_C($full_file , 
                                      $rh_Err    ,
                                      $raa_errors,
                                     \$lang_M_or_O);
                if ($lang_M_or_O) {
                    return $lang_M_or_O;
                } else { # an error happened in matlab_or_objective_C()
                    $rh_ignored->{$full_file} = 
                        'failure in matlab_or_objective_C()';
                    return $language; # (unknown)
                }
            } else {
                return $Language_by_Extension{$extension};
            }
        } else { # has an unmapped file extension
            $look_at_first_line = 1;
        }
    } elsif (defined $Language_by_File{lc $file}) {
        return $Language_by_File{lc $file};
    } else {  # no file extension
        $look_at_first_line = 1;
    }

    if ($look_at_first_line) {
        # maybe it is a shell/Perl/Python/Ruby/etc script that
        # starts with pound bang:
        #   #!/usr/bin/perl
        #   #!/usr/bin/env perl
        my $script_language = peek_at_first_line($full_file , 
                                                 $rh_Err    , 
                                                 $raa_errors);
        if (!$script_language) {
            $rh_ignored->{$full_file} = "language unknown (#2)";
            # returns (unknown)
        }
        if (defined $Language_by_Script{$script_language}) {
            if (defined $Filters_by_Language{
                            $Language_by_Script{$script_language}}) {
                $language = $Language_by_Script{$script_language};
            } else {
                $rh_ignored->{$full_file} = 
                    "undefined:  Filters_by_Language{" . 
                    $Language_by_Script{$script_language} .
                    "} for scripting language $script_language";
                # returns (unknown)
            }
        } else {
            $rh_ignored->{$full_file} = "language unknown (#3)";
            # returns (unknown)
        }
    }
    print "<- classify_file($full_file)\n" if $opt_v > 2;
    return $language;
} # 1}}}

####################################################################
sub peek_at_first_line {                     # {{{1
    my ($file        , # in
        $rh_Err      , # in   hash of error codes
        $raa_errors  , # out
       ) = @_;

    print "-> peek_at_first_line($file)\n" if $opt_v > 2;

    my $script_language = "";
    if (!-r $file) {
        push @{$raa_errors}, [$rh_Err->{'Unable to read'} , $file];
        return $script_language;
    }
    my $IN = new IO::File $file, "r";
    if (!defined $IN) {
        push @{$raa_errors}, [$rh_Err->{'Unable to read'} , $file];
        print "<- peek_at_first_line($file)\n" if $opt_v > 2;
        return $script_language;
    }
    chomp(my $first_line = <$IN>);
    if (defined $first_line) {
#print "peek_at_first_line first_line=$first_line\n";
        if ($first_line =~ /^#\!(.*?)$/) {
            my @pound_bang = split(' ', $1);
#print "peek_at_first_line basename 0=[", basename($pound_bang[0]), "]\n";
            if (basename($pound_bang[0]) eq "env" and 
                scalar @pound_bang > 1) {
                $script_language = $pound_bang[1];
#print "peek_at_first_line pound_bang A $pound_bang[1]\n";
            } else {
                $script_language = basename $pound_bang[0];
#print "peek_at_first_line pound_bang B $script_language\n";
            }
        }
    }
    $IN->close;
    print "<- peek_at_first_line($file)\n" if $opt_v > 2;
    return $script_language;
} # 1}}}

####################################################################
sub different_files {                        # {{{1
    # See which of the given files are unique by computing each file's MD5
    # sum.  Return the subset of files which are unique.
    my ($ra_files    , # in
        $rh_Err      , # in
        $raa_errors  , # out
        $rh_ignored  , # out
       ) = @_;

    print "-> different_files(@{$ra_files})\n" if $opt_v > 2;
    my %file_hash = ();  # file_hash{ md5 hash } = file name
    foreach my $F (@{$ra_files}) {
        next if is_dir($F);  # needed for Windows
        my $IN = new IO::File $F, "r";
        if (!defined $IN) {
            push @{$raa_errors}, [$rh_Err->{'Unable to read'} , $F];
            $rh_ignored->{$F} = 'cannot read';
        } else {
            if ($HAVE_Digest_MD5) {
                binmode $IN;
                $file_hash{ Digest::MD5->new->addfile($IN)->hexdigest } = $F;
            } else {
                # all files treated unique
                $file_hash{ $F } = $F;
            }
            $IN->close;
        }
    }
    my @unique = values %file_hash;
    print "<- different_files(@unique)\n" if $opt_v > 2;
    return @unique;
} # 1}}}

####################################################################
sub call_counter {                           # {{{1
    my ($file    , # in
        $language, # in
       ) = @_;

    # Logic:  pass the file through the following filters:
    #         1. remove blank lines
    #         2. remove comments using each filter defined for this language
    #            (example:  SQL has two, remove_starts_with(--) and 
    #             remove_c_comments() )
    #         3. compute comment lines as 
    #               total lines - blank lines - lines left over after all
    #                   comment filters have been applied

    print "-> call_counter($file, $language)\n" if $opt_v > 2;
    my @routines = @{$Filters_by_Language{$language}};
#print "call_counter:  ", Dumper(@routines), "\n";

    my $IN = new IO::File $file, "r";
    my @lines = <$IN>;
    $IN->close;
    # Some files don't end with a new line.  Force this:
    $lines[$#lines] .= "\n" unless $lines[$#lines] =~ m/\n$/;

    my $total_lines = scalar @lines;

    print_lines($file, "Original file:", \@lines) if $opt_print_filter_stages;
    if ($language eq "COBOL") {
        @lines = remove_cobol_blanks(\@lines);
    } else {
        @lines = remove_matches(\@lines, '^\s*$'); # removes blank lines
    }
    my $blank_lines = $total_lines - scalar @lines;
    print_lines($file, "Blank lines removed:", \@lines) 
        if $opt_print_filter_stages;

    foreach my $call_string (@routines) {
#print "call_counter:  call_string=", Dumper($call_string), "\n";
        my $subroutine = $call_string->[0];
        if (! defined &{$subroutine}) {
            warn "call_counter undefined subroutine $subroutine for $file\n";
            next;
        }
        print "call_counter file=$file sub=$subroutine\n" if $opt_v > 1;
        my @args  = @{$call_string};
        shift @args; # drop the subroutine name
        if (@args and $args[0] eq '>filename<') {
            shift   @args;
            unshift @args, $file;
        }

        no strict 'refs';
        @lines = &{$subroutine}(\@lines, @args);   # apply filter...

        print_lines($file, "After $subroutine(@args)", \@lines) 
            if $opt_print_filter_stages;
        @lines = remove_matches(\@lines, '^\s*$'); # ...then remove blank lines
        print_lines($file, "post $subroutine(@args) blanks cleanup:", \@lines) 
            if $opt_print_filter_stages;
    }
    my $comment_lines = $total_lines - $blank_lines - scalar  @lines;
    if ($opt_strip_comments) {
        my $stripped_file = basename $file . ".$opt_strip_comments";
        write_file($stripped_file, @lines);
    }

    print "<- call_counter($total_lines, $blank_lines, $comment_lines)\n" 
        if $opt_v > 2;
    return ($total_lines, $blank_lines, $comment_lines);
} # 1}}}

####################################################################
sub write_file {                             # {{{1
    my ($file  , # in
        @lines , # in
       ) = @_;

    print "-> write_file($file)\n" if $opt_v > 2;

    my $OUT = new IO::File $file, "w";
    if (defined $OUT) {
        chomp(@lines);
        print $OUT join("\n", @lines), "\n";
        $OUT->close;
    } else {
        warn "Unable to write to $file\n";
    }
    print "Wrote $file\n";
    
    print "<- write_file\n" if $opt_v > 2;
} # 1}}}

####################################################################
sub remove_f77_comments {                    # {{{1
    my ($ra_lines, ) = @_;
    print "-> remove_f77_comments\n" if $opt_v > 2;

    my @save_lines = ();
    foreach (@{$ra_lines}) {
        next if m{^[*cC]};
        push @save_lines, $_;
    }

    print "<- remove_f77_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}

####################################################################
sub remove_f90_comments {                    # {{{1
    # derived from SLOCCount
    my ($ra_lines, ) = @_;
    print "-> remove_f90_comments\n" if $opt_v > 2;

    my @save_lines = ();
    foreach (@{$ra_lines}) {
        # a comment is              m/^\s*!/
        # an empty line is          m/^\s*$/
        # a HPF statement is        m/^\s*!hpf\$/i
        # an Open MP statement is   m/^\s*!omp\$/i
        if (! m/^(\s*!|\s*$)/ || m/^\s*!(hpf|omp)\$/i) {
            push @save_lines, $_;
        }
    }

    print "<- remove_f90_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}

####################################################################
sub remove_matches {                         # {{{1
    my ($ra_lines, # in
        $pattern , # in   Perl regular expression (case insensitive)
       ) = @_;
    print "-> remove_matches(pattern=$pattern)\n" if $opt_v > 2;

    my @save_lines = ();
    foreach (@{$ra_lines}) {
        next if m{$pattern}i;
        push @save_lines, $_;
    }

    print "<- remove_matches\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}

####################################################################
sub remove_below {                           # {{{1
    my ($ra_lines, $marker, ) = @_;
    print "-> remove_below(marker=$marker)\n" if $opt_v > 2;

    my @save_lines = ();
    foreach (@{$ra_lines}) {
        last if m{$marker};
        push @save_lines, $_;
    }

    print "<- remove_below\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}

####################################################################
sub remove_cobol_blanks {                    # {{{1
    # subroutines derived from SLOCCount
    my ($ra_lines, ) = @_;

    my $free_format = 0;  # Support "free format" source code.
    my @save_lines  = ();
  
    foreach (@{$ra_lines}) {
        next if m/^\s*$/;
        my $line = expand($_);  # convert tabs to equivalent spaces
        $free_format = 1 if $line =~ m/^......\$.*SET.*SOURCEFORMAT.*FREE/i;
        if ($free_format) {
            push @save_lines, $_;
        } else {
            push @save_lines, $_ unless m/^\d{6}\s*$/ or
                              ($line =~ m/^\d{6}\s{66}/);
        }
    }
    return @save_lines;
} # 1}}}

####################################################################
sub remove_cobol_comments {                  # {{{1
    # subroutines derived from SLOCCount
    my ($ra_lines, ) = @_;

    my $free_format = 0;  # Support "free format" source code.
    my @save_lines  = ();
  
    foreach (@{$ra_lines}) {
        if (m/^......\$.*SET.*SOURCEFORMAT.*FREE/i) {$free_format = 1;}
        if ($free_format) {
            push @save_lines, $_ unless m{^\s*\*};
        } else {
            push @save_lines, $_ unless m{^......\*} or m{^\*};
        }
    }
    return @save_lines;
} # 1}}}

####################################################################
sub remove_jcl_comments {                    # {{{1
    my ($ra_lines, ) = @_;

    print "-> remove_jcl_comments\n" if $opt_v > 2;

    my @save_lines = ();
    my $in_comment = 0;
    foreach (@{$ra_lines}) {
        next if /^\s*$/;
        next if m{^\s*//\*};
        last if m{^\s*//\s*$};
        push @save_lines, $_;
    }

    print "<- remove_jcl_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}

####################################################################
sub remove_jsp_comments {                    # {{{1
    #  JSP comment is   <%--  body of comment   --%>
    my ($ra_lines, ) = @_;

    print "-> remove_jsp_comments\n" if $opt_v > 2;

    my @save_lines = ();
    my $in_comment = 0;
    foreach (@{$ra_lines}) {

        next if /^\s*$/;
        s/<\%\-\-.*?\-\-\%>//g;  # strip one-line comments
        next if /^\s*$/;
        if ($in_comment) {
            if (/\-\-\%>/) {
                s/^.*?\-\-\%>//;
                $in_comment = 0;
            }
        }
        next if /^\s*$/;
        $in_comment = 1 if /^(.*?)<\%\-\-/;
        next if defined $1 and $1 =~ /^\s*$/;
        push @save_lines, $_;
    }

    print "<- remove_jsp_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}

####################################################################
sub determine_lit_type {                     # {{{1
  my ($file) = @_;

  open (FILE, $file);
  while (<FILE>) {
    if (m/^\\begin{code}/) { close FILE; return 2; }
    if (m/^>\s/) { close FILE; return 1; }
  }

  return 0;
} # 1}}}

####################################################################
sub remove_haskell_comments {                # {{{1
    # Bulk of code taken from SLOCCount's haskell_count script.
    # Strips out {- .. -} and -- comments and counts the rest.
    # Pragmas, {-#...}, are counted as SLOC.
    # BUG: Doesn't handle strings with embedded block comment markers gracefully.
    #      In practice, that shouldn't be a problem.
    my ($ra_lines, $file, ) = @_;

    print "-> remove_haskell_comments\n" if $opt_v > 2;

    my @save_lines = ();
    my $in_comment = 0;
    my $incomment  = 0;
    my ($literate, $inlitblock) = (0,0);
  
    $literate = 1 if $file =~ /\.lhs$/;
    if($literate) { $literate = determine_lit_type($file) }

    foreach (@{$ra_lines}) {
        if ($literate == 1) {
            if (!s/^>//) { s/.*//; }
        } elsif ($literate == 2) {
            if ($inlitblock) {
                if (m/^\\end{code}/) { s/.*//; $inlitblock = 0; }
            } elsif (!$inlitblock) {
                if (m/^\\begin{code}/) { s/.*//; $inlitblock = 1; }
                else { s/.*//; }
            }
        }

        if ($incomment) {
            if (m/\-\}/) { s/^.*?\-\}//;  $incomment = 0;}
            else { s/.*//; }
        }
        if (!$incomment) {
            s/--.*//;
            s!{-[^#].*?-}!!g;
            if (m/{-/ && (!m/{-#/)) {
              s/{-.*//;
              $incomment = 1;
            }
        }
        if (m/\S/) { push @save_lines, $_; }
    }
#   if ($incomment) {print "ERROR: ended in comment in $ARGV\n";}

    print "<- remove_haskell_comments\n" if $opt_v > 2;
    return @save_lines;
} # 1}}}

####################################################################
sub print_lines {                            # {{{1
    my ($file     , # in
        $title    , # in
        $ra_lines , # in
       ) = @_;
    printf "->%-30s %s\n", $file, $title;
    for (my $i = 0; $i < scalar @{$ra_lines}; $i++) {
        printf "%5d | %s", $i+1, $ra_lines->[$i];
        print "\n" unless $ra_lines->[$i] =~ m{\n$}
    }
} # 1}}}

####################################################################
sub set_constants {                          # {{{1
    my ($rh_Language_by_Extension , # out
        $rh_Language_by_Script    , # out
        $rh_Language_by_File      , # out
        $rhaa_Filters_by_Language , # out
        $rh_Not_Code_Extension    , # out
        $rh_Not_Code_Filename     , # out
        $rh_Scale_Factor          , # out
       ) = @_;
# 1}}}
%{$rh_Language_by_Extension} = (                 # {{{1
            'abap'        => "ABAP"                  ,
            'ada'         => 'Ada'                   ,
            'adb'         => 'Ada'                   ,
            'ads'         => 'Ada'                   ,
            'adso'        => "ADSO/IDSM"             ,
            'asa'         => 'ASP'                   ,
            'asax'        => 'ASP.Net'               ,
            'ascx'        => 'ASP.Net'               ,
            'asm'         => 'Assembler'             ,
            'asmx'        => 'ASP.Net'               ,
            'asp'         => 'ASP'                   ,
            'aspx'        => 'ASP.Net'               ,
            'awk'         => 'awk'                   ,
            'bash'        => "Bourne Shell"          ,
            'bas'         => "Visual Basic"          ,
            'bat'         => 'DOS Batch'             ,
            'BAT'         => 'DOS Batch'             ,
            'cbl'         => 'COBOL'                 ,
            'CBL'         => 'COBOL'                 ,
            'c'           => 'C'                     ,
            'C'           => 'C++'                   ,
            'cc'          => 'C++'                   ,
            'ccs'         => 'CCS'                   ,
            'cfm'         => "ColdFusion"            ,
            'cl'          => 'Lisp'                  ,
            'cob'         => 'COBOL'                 ,
            'COB'         => 'COBOL'                 ,
            'config'      => 'ASP.Net'               ,
            'cpp'         => 'C++'                   ,
            'cs'          => 'C#'                    ,
            'csh'         => 'C Shell'               ,
            'cxx'         => 'C++'                   ,
            'dpr'         => 'Pascal'                ,
            'dtd'         => "DTD"                   ,
            'ec'          => 'C'                     ,
            'el'          => 'Lisp'                  ,
            'exp'         => 'Expect'                ,
            'f77'         => 'Fortran 77'            ,
            'F77'         => 'Fortran 77'            ,
            'f90'         => 'Fortran 90'            ,
            'F90'         => 'Fortran 90'            ,
            'f95'         => 'Fortran 95'            ,
            'F95'         => 'Fortran 95'            ,
            'f'           => 'Fortran 77'            ,
            'F'           => 'Fortran 77'            ,
            'fmt'         => "Oracle Forms"          ,
            'focexec'     => "Focus"                 ,
            'frm'         => "Visual Basic"          ,
            'gnumakefile' => 'Make'                  ,
            'Gnumakefile' => 'Make'                  ,
            'h'           => 'C/C++ Header'          ,
            'H'           => 'C/C++ Header'          ,
            'hh'          => 'C/C++ Header'          ,
            'hpp'         => 'C/C++ Header'          ,
            "hs"          => "Haskell"               , 
            'htm'         => "HTML"                  ,
            'html'        => "HTML"                  ,
            'i3'          => "Modula3"               ,
            'idl'         => "IDL"                   ,
            'ig'          => "Modula3"               ,
            'inc'         => 'inc'                   , # might be PHP
            'itk'         => 'Tcl/Tk'                ,
            'java'        => 'Java'                  ,
            'jcl'         => "JCL"                   , # IBM Job Control Lang.
            'jl'          => 'Lisp'                  ,
            'js'          => "Javascript"            ,
            "jsp"         => "JSP"                   , # Java server pages
            'ksh'         => 'Korn Shell'            ,
            "lhs"         => "Haskell"               ,
            'l'           => 'lex'                   ,
            'lsp'         => 'Lisp'                  ,
            'lua'         => 'lua'                   ,
            "m3"          => "Modula3"               , 
            'makefile'    => 'Make'                  ,
            'Makefile'    => 'Make'                  ,
            "mg"          => "Modula3"               , 
            "mli"         => "ML"                    ,
            "ml"          => "ML"                    , 
            'm'           => 'MATLAB or Objective C' ,
            "mps"         => "MUMPS"                 ,
            'pad'         => 'Ada'                   , # Oracle Ada preprocessor
            'pas'         => 'Pascal'                ,
            'pcc'         => 'C++'                   , # Oracle C++ preprocessor
            'perl'        => 'Perl'                  ,
            'pfo'         => 'Fortran 77'            ,
            'pgc'         => 'C'                     , # Postgres embedded C/C++
            'php3'        => 'PHP'                   ,
            'php4'        => 'PHP'                   ,
            'php5'        => 'PHP'                   ,
            'php6'        => 'PHP'                   ,
            'php'         => 'PHP'                   ,
            'plh'         => 'Perl'                  ,
            'pl'          => 'Perl'                  ,
            'PL'          => 'Perl'                  ,
            'plx'         => 'Perl'                  ,
            'pm'          => 'Perl'                  ,
            'p'           => 'Pascal'                ,
            'pp'          => 'Pascal'                ,
            'psql'        => 'SQL'                   ,
            'py'          => 'Python'                ,
            "rb"          => "Ruby"                  ,
            'resx'        => 'ASP.Net'               ,
            'rex'         => "Oracle Reports"        ,
            'rexx'        => "Rexx"                  ,
            's'           => 'Assembler'             ,
            'S'           => 'Assembler'             ,
            'sc'          => 'Lisp'                  ,
            'scm'         => 'Lisp'                  ,
            'sed'         => 'sed'                   ,
            'sh'          => "Bourne Shell"          ,
            'sql'         => 'SQL'                   ,
            'tcl'         => 'Tcl/Tk'                ,
            'tcsh'        => 'C Shell'               ,
            'tk'          => 'Tcl/Tk'                ,
            'vba'         => "Visual Basic"          ,
            'vbp'         => "Visual Basic"          ,
            'vb'          => "Visual Basic"          ,
            'vbw'         => "Visual Basic"          ,
            'webinfo'     => 'ASP.Net'               ,
            "xml"         => "XML"                   ,
            'xsd'         => "XSD"                   ,
            "xslt"        => "XSLT"                  ,
            "xsl"         => "XSL"                   ,
            'y'           => 'yacc'                  ,
            );
# 1}}}
%{$rh_Language_by_Script}    = (                 # {{{1
            'awk'      => 'awk'                   ,
            'bash'     => 'Bourne Shell'          ,# Bourne Again Shell too long
            'bc'       => 'bc'                    ,# calculator
            'csh'      => 'C Shell'               ,
            'idl'      => 'IDL'                   ,
            'ksh'      => 'Korn Shell'            ,
            'make'     => 'Make'                  ,
            'octave'   => 'Octave'                ,
            'perl5'    => 'Perl'                  ,
            'perl'     => 'Perl'                  ,
            'sed'      => 'sed'                   ,
            'sh'       => 'Bourne Shell'          ,
            'tcl'      => 'Tcl/Tk'                ,
            'tcsh'     => 'C Shell'               ,
            'wish'     => 'Tcl/Tk'                ,
            );
# 1}}}
%{$rh_Language_by_File}      = (                 # {{{1
            'Makefile'    => 'Make'                  ,
            'makefile'    => 'Make'                  ,
            'gnumakefile' => 'Make'                  ,
            'Gnumakefile' => 'Make'                  ,
            );
# 1}}}
%{$rhaa_Filters_by_Language} = (                 # {{{1
    'ABAP'               => [   [ 'remove_matches'      , '^\*'    ], ],
    'ASP'                => [   [ 'remove_matches'      , '^\s*\47'], ],  # \47 = '
    'ASP.Net'            => [   [ 'call_regexp_common'  , 'C'      ], ],
    'Ada'                => [   [ 'remove_matches'      , '^\s*--' ], ],
    'ADSO/IDSM'          => [   [ 'remove_matches'      , '^\s*\*[\+\!]' ], ],
    'Assembler'          => [  
                                [ 'remove_matches'      , '^\s*//' ],
                                [ 'remove_matches'      , '^\s*;'  ],
                                [ 'call_regexp_common'  , 'C'      ], 
                            ],
    'awk'                => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'bc'                 => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'C'                  => [   [ 'call_regexp_common'  , 'C'      ], ], 
    'C++'                => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ],
    'C/C++ Header'       => [   [ 'call_regexp_common'  , 'C'      ], ],
    'C#'                 => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ],
    'CCS'                => [   [ 'call_regexp_common'  , 'C'      ], ],
    'COBOL'              => [   [ 'remove_cobol_comments',         ], ],
    'ColdFusion'         => [   [ 'call_regexp_common'  , 'HTML'   ], ],
    'Crystal Reports'    => [   [ 'remove_matches'      , '^\s*//' ], ],
    'DOS Batch'          => [   [ 'remove_matches'      , '^\s*rem', ], ],
    'DTD'                => [   [ 'call_regexp_common'  , 'HTML'   ], ],
    'Expect'             => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'Focus'              => [   [ 'remove_matches'      , '^\s*\-\*'  ], ],
    'Fortran 77'         => [   [ 'remove_f77_comments' ,          ], ],
    'Fortran 90'         => [   [ 'remove_f77_comments' ,          ],
                                [ 'remove_f90_comments' ,          ], ],
    'Fortran 95'         => [   [ 'remove_f77_comments' ,          ],
                                [ 'remove_f90_comments' ,          ], ],
    'HTML'               => [   [ 'call_regexp_common'  , 'HTML'   ], ],
    'Haskell'            => [   [ 'remove_haskell_comments', '>filename<' ], ],
    'IDL'                => [   [ 'remove_matches'      , '^\s*;'  ], ],
    'JSP'                => [   [ 'call_regexp_common'  , 'HTML'   ],
                                [ 'remove_jsp_comments',           ], ],
    'Java'               => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ],
    'Javascript'         => [   
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ],
                            ],
    'JCL'                => [   [ 'remove_jcl_comments' ,          ], ],
    'Lisp'               => [   [ 'remove_matches'      , '^\s*;'  ], ],
    'lua'                => [   [ 'call_regexp_common'  , 'lua'    ], ],
    'Make'               => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'MATLAB'             => [   [ 'remove_matches'      , '^\s*%'  ], ], 
    'Modula3'            => [   [ 'call_regexp_common'  , 'Pascal' ], ],
        # Modula 3 comments are (* ... *) so applying the Pascal filter
        # which also treats { ... } as a comment is not really correct.
    'Objective C'        => [   [ 'call_regexp_common'  , 'C'      ], ], 
    'MATLAB or Objective C' => [ [ 'die' ,          ], ], # never called
    'MUMPS'              => [   [ 'remove_matches'      , '^\s*;'  ], ], 
    'Octave'             => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'Oracle Forms'       => [   [ 'call_regexp_common'  , 'C'      ], ],
    'Oracle Reports'     => [   [ 'call_regexp_common'  , 'C'      ], ],
    'Pascal'             => [   [ 'call_regexp_common'  , 'Pascal' ], ],
    'Perl'               => [   [ 'remove_below'        , '^__(END|DATA)__'],
                                [ 'remove_matches'      , '^\s*#'  ], ], 
    'Python'             => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'PHP'                => [   
                                [ 'remove_matches'      , '^\s*#'  ],
                                [ 'remove_matches'      , '^\s*//' ], 
                                [ 'call_regexp_common'  , 'C'      ], 
                            ],
    'Rexx'               => [   [ 'call_regexp_common'  , 'C'      ], ],
    'Ruby'               => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'SQL'                => [   
                                [ 'remove_matches'      , '^\s*--' ],
                                [ 'call_regexp_common'  , 'C'      ], 
                            ],
    'sed'                => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'Bourne Shell'       => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'C Shell'            => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'Korn Shell'         => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'Tcl/Tk'             => [   [ 'remove_matches'      , '^\s*#'  ], ], 
    'Visual Basic'       => [   [ 'remove_matches'      , '^\s*\47'], ],  # \47 = '
    'yacc'               => [   [ 'call_regexp_common'  , 'C'      ], ], 
    'lex'                => [   [ 'call_regexp_common'  , 'C'      ], ], 
    'XML'                => [   [ 'call_regexp_common'  , 'HTML'   ], ],
    'XSL'                => [   [ 'call_regexp_common'  , 'HTML'   ], ],
    'XSD'                => [   [ 'call_regexp_common'  , 'HTML'   ], ],
    'XSLT'               => [   [ 'call_regexp_common'  , 'HTML'   ], ],
    );
# 1}}}
%{$rh_Not_Code_Extension}    = (                 # {{{1
   "1"       => 1,  # Man pages (documentation):
   "2"       => 1,
   "3"       => 1,
   "4"       => 1,
   "5"       => 1,
   "6"       => 1,
   "7"       => 1,
   "8"       => 1,
   "9"       => 1,
   "a"       => 1,  # Static object code.
   "ad"      => 1,  # X application default resource file.
   "afm"     => 1,  # font metrics
   "am"      => 1,  # Debatable.
   "arc"     => 1,  # arc(1) archive
   "arj"     => 1,  # arj(1) archive
   "au"      => 1,  # Audio sound filearj(1) archive
   "bak"     => 1,  # Backup files - we only want to count the "real" files.
   "bdf"     => 1,
   "bmp"     => 1,
   "bz2"     => 1,  # bzip2(1) compressed file
   "csv"     => 1,  # comma separated values
   "desktop" => 1,
   "dic"     => 1,
   "doc"     => 1,
   "elc"     => 1,
   "eps"     => 1,
   "fig"     => 1,
   "gif"     => 1,
   "gz"      => 1,
   "hdf"     => 1,  # hierarchical data format
   "in"      => 1,  # Debatable.
   "jpg"     => 1,
   "kdelnk"  => 1,
   "m4"      => 1,  # Debatable.
   "man"     => 1,
   "man"     => 1,
   "mf"      => 1,
   "mp3"     => 1,
   "n"       => 1,
   "o"       => 1,  # Object code is generated from source code.
   "pbm"     => 1,
   "pdf"     => 1,
   "pfb"     => 1,
   "png"     => 1,
   "po"      => 1,
   "ps"      => 1,  # Postscript is _USUALLY_ generated automatically.
   "sgm"     => 1,
   "sgml"    => 1,
   "so"      => 1,  # Dynamically-loaded object code.
   "Tag"     => 1,
   "tex"     => 1,
   "text"    => 1,
   "tfm"     => 1,
   "tgz"     => 1,  # gzipped tarball
   "tiff"    => 1,
   "txt"     => 1, 
   "vf"      => 1,
   "wav"     => 1,
   "xbm"     => 1,
   "xpm"     => 1,
   "Y"       => 1,  # file compressed with "Yabba"
   "Z"       => 1,  # file compressed with "compress"
   "zip"     => 1,  # zip archive
); # 1}}}
%{$rh_Not_Code_Filename}     = (                 # {{{1
   "AUTHORS"     => 1,
   "README"      => 1,
   "Readme"      => 1,
   "readme"      => 1,
   "README.tk"   => 1, # used in kdemultimedia, it's confusing.
   "Changelog"   => 1,
   "ChangeLog"   => 1,
   "Repository"  => 1,
   "CHANGES"     => 1,
   "Changes"     => 1,
   ".cvsignore"  => 1,
   "Root"        => 1, # CVS
   "BUGS"        => 1,
   "TODO"        => 1,
   "COPYING"     => 1,
   "MAINTAINERS" => 1,
   "Entries"     => 1,
   "iconfig.h"   => 1, # Skip "iconfig.h" files; they're used in Imakefiles
                       # (used in xlockmore):
);
# 1}}}
%{$rh_Scale_Factor}          = (                 # {{{1
    '1032/af'                      =>   5.00,
    '1st generation default'       =>   0.25,
    '2nd generation default'       =>   0.75,
    '3rd generation default'       =>   1.00,
    '4th generation default'       =>   4.00,
    '5th generation default'       =>  16.00,
    'aas macro'                    =>   0.88,
    'abap/4'                       =>   5.00,
    'ABAP'                         =>   5.00,
    'accel'                        =>   4.21,
    'access'                       =>   2.11,
    'actor'                        =>   3.81,
    'acumen'                       =>   2.86,
    'Ada'                          =>   0.52,
    'Ada 83'                       =>   1.13,
    'Ada 95'                       =>   1.63,
    'adr/dl'                       =>   2.00,
    'adr/ideal/pdl'                =>   4.00,
    'ads/batch'                    =>   4.00,
    'ads/online'                   =>   4.00,
'ADSO/IDSM'                        =>   3.00,
    'advantage'                    =>   2.11,
    'ai shell default'             =>   1.63,
    'ai shells'                    =>   1.63,
    'algol 68'                     =>   0.75,
    'algol w'                      =>   0.75,
    'ambush'                       =>   2.50,
    'aml'                          =>   1.63,
    'amppl ii'                     =>   1.25,
    'ansi basic'                   =>   1.25,
    'ansi cobol 74'                =>   0.75,
    'ansi cobol 85'                =>   0.88,
    'SQL'                          =>   6.15,
    'answer/db'                    =>   6.15,
    'apl 360/370'                  =>   2.50,
    'apl default'                  =>   2.50,
    'apl*plus'                     =>   2.50,
    'applesoft basic'              =>   0.63,
    'application builder'          =>   4.00,
    'application manager'          =>   2.22,
    'aps'                          =>   0.96,
    'aps'                          =>   4.71,
    'apt'                          =>   1.13,
    'aptools'                      =>   4.00,
    'arc'                          =>   1.63,
    'ariel'                        =>   0.75,
    'arity'                        =>   1.63,
    'arity prolog'                 =>   1.25,
    'art'                          =>   1.63,
    'art enterprise'               =>   1.74,
    'artemis'                      =>   2.00,
    'artim'                        =>   1.74,
    'as/set'                       =>   4.21,
    'asi/inquiry'                  =>   6.15,
    'ask windows'                  =>   1.74,
'asa'                         =>   1.29,
'ASP'                         =>   1.29,
'ASP.Net'                     =>   1.29,
'aspx'                        =>   1.29,
'resx'                        =>   1.29,
'asax'                        =>   1.29,
'ascx'                        =>   1.29,
'asmx'                        =>   1.29,
'config'                      =>   1.29,
'webinfo'                     =>   1.29,
'CCS'                         =>   5.33,

#   'assembler (basic)'            =>   0.25,
    'Assembler'                    =>   0.25,

    'assembler (macro)'            =>   0.51,
    'associative default'          =>   1.25,
    'autocoder'                    =>   0.25,
    'awk'                          =>   3.81,
    'aztec c'                      =>   0.63,
    'balm'                         =>   0.75,
    'base sas'                     =>   1.51,
    'basic'                        =>   0.75,
    'basic a'                      =>   0.63,
#   'basic assembly'               =>   0.25,
    'bc'                           =>   1.50,
    'berkeley pascal'              =>   0.88,
    'better basic'                 =>   0.88,
    'bliss'                        =>   0.75,
    'bmsgen'                       =>   2.22,
    'boeingcalc'                   =>  13.33,
    'bteq'                         =>   6.15,

    'C'                            =>   0.77,

    'c set 2'                      =>   0.88,

    'C#'                           =>   1.36,

    'C++'                          =>   1.51,

    'c86plus'                      =>   0.63,
    'cadbfast'                     =>   2.00,
    'caearl'                       =>   2.86,
    'cast'                         =>   1.63,
    'cbasic'                       =>   0.88,
    'cdadl'                        =>   4.00,
    'cellsim'                      =>   1.74,
'ColdFusion'               =>   4.00,
    'chili'                        =>   0.75,
    'chill'                        =>   0.75,
    'cics'                         =>   1.74,
    'clarion'                      =>   1.38,
    'clascal'                      =>   1.00,
    'cli'                          =>   2.50,
    'clipper'                      =>   2.05,
    'clipper db'                   =>   2.00,
    'clos'                         =>   3.81,
    'clout'                        =>   2.00,
    'cms2'                         =>   0.75,
    'cmsgen'                       =>   4.21,
    'COBOL'                        =>   1.04,
    'COBOL ii'                     =>   0.75,
    'COBOL/400'                    =>   0.88,
    'cobra'                        =>   4.00,
    'codecenter'                   =>   2.22,
    'cofac'                        =>   2.22,
    'cogen'                        =>   2.22,
    'cognos'                       =>   2.22,
    'cogo'                         =>   1.13,
    'comal'                        =>   1.00,
    'comit ii'                     =>   1.25,
    'common lisp'                  =>   1.25,
    'concurrent pascal'            =>   1.00,
    'conniver'                     =>   1.25,
    'cool:gen/ief'                 =>   2.58,
    'coral 66'                     =>   0.75,
    'corvet'                       =>   4.21,
    'corvision'                    =>   5.33,
    'cpl'                          =>   0.50,
    'Crystal Reports'              =>   4.00,
    'csl'                          =>   1.63,
    'csp'                          =>   1.51,
    'cssl'                         =>   1.74,
    'culprit'                      =>   1.57,
    'cxpert'                       =>   1.63,
    'cygnet'                       =>   4.21,
    'data base default'            =>   2.00,
    'dataflex'                     =>   2.00,
    'datatrieve'                   =>   4.00,
    'dbase iii'                    =>   2.00,
    'dbase iv'                     =>   1.54,
    'dcl'                          =>   0.38,
    'decision support default'     =>   2.22,
    'decrally'                     =>   2.00,
    'delphi'                       =>   2.76,
    'dl/1'                         =>   2.00,
    'dna4'                         =>   4.21,
    'DOS Batch'                    =>   0.63,
    'dsp assembly'                 =>   0.50,
    'dtabl'                        =>   1.74,
    'dtipt'                        =>   1.74,
    'dyana'                        =>   1.13,
    'dynamoiii'                    =>   1.74,
    'easel'                        =>   2.76,
    'easy'                         =>   1.63,
    'easytrieve+'                  =>   2.35,
    'eclipse'                      =>   1.63,
    'eda/sql'                      =>   6.67,
    'edscheme 3.4'                 =>   1.51,
    'eiffel'                       =>   3.81,
    'enform'                       =>   1.74,
    'englishbased default'         =>   1.51,
    'ensemble'                     =>   2.76,
    'epos'                         =>   4.00,
    'erlang'                       =>   2.00,
    'esf'                          =>   2.00,
    'espadvisor'                   =>   1.63,
    'espl/i'                       =>   1.13,
    'euclid'                       =>   0.75,
    'excel'                        =>   1.74,
    'excel 12'                     =>  13.33,
    'excel 34'                     =>  13.33,
    'excel 5'                      =>  13.33,
    'express'                      =>   2.22,
    'exsys'                        =>   1.63,
    'extended common lisp'         =>   1.43,
    'eznomad'                      =>   2.22,
    'facets'                       =>   4.00,
    'factorylink iv'               =>   2.76,
    'fame'                         =>   2.22,
    'filemaker pro'                =>   2.22,
    'flavors'                      =>   2.76,
    'flex'                         =>   1.74,
    'flexgen'                      =>   2.76,
    'Focus'                        =>   1.90,
    'foil'                         =>   1.51,
    'forte'                        =>   4.44,
    'forth'                        =>   1.25,
    'Fortran 66'                   =>   0.63,
    'Fortran 77'                   =>   0.75,
    'Fortran 90'                   =>   1.00,
    'Fortran 95'                   =>   1.13,
    'Fortran II'                   =>   0.63,
    'foundation'                   =>   2.76,
    'foxpro'                       =>   2.29,
    'foxpro 1'                     =>   2.00,
    'foxpro 2.5'                   =>   2.35,
    'framework'                    =>  13.33,
    'g2'                           =>   1.63,
    'gamma'                        =>   5.00,
    'genascript'                   =>   2.96,
    'gener/ol'                     =>   6.15,
    'genexus'                      =>   5.33,
    'genifer'                      =>   4.21,
    'geode 2.0'                    =>   5.00,
    'gfa basic'                    =>   2.35,
    'gml'                          =>   1.74,
    'golden common lisp'           =>   1.25,
    'gpss'                         =>   1.74,
    'guest'                        =>   2.86,
    'guru'                         =>   1.63,
    'gw basic'                     =>   0.82,
    'Haskell'                      =>   2.11,
    'high c'                       =>   0.63,
    'hlevel'                       =>   1.38,
    'hp basic'                     =>   0.63,

'HTML'     => 1.90 ,
'XML'      => 1.90 ,
'XSL'      => 1.90 ,
'XSLT'     => 1.90 ,
'DTD'      => 1.90 ,
'XSD'      => 1.90 ,

    'HTML 2'                       =>   5.00,
    'HTML 3'                       =>   5.33,
    'huron'                        =>   5.00,
    'ibm adf i'                    =>   4.00,
    'ibm adf ii'                   =>   4.44,
    'ibm advanced basic'           =>   0.82,
    'ibm cics/vs'                  =>   2.00,
    'ibm compiled basic'           =>   0.88,
    'ibm vs cobol'                 =>   0.75,
    'ibm vs cobol ii'              =>   0.88,
    'ices'                         =>   1.13,
    'icon'                         =>   1.00,
    'ideal'                        =>   1.54,
    'idms'                         =>   2.00,
    'ief'                          =>   5.71,
    'ief/cool:gen'                 =>   2.58,
    'iew'                          =>   5.71,
    'ifps/plus'                    =>   2.50,
    'imprs'                        =>   2.00,
    'informix'                     =>   2.58,
    'ingres'                       =>   2.00,
    'inquire'                      =>   6.15,
    'insight2'                     =>   1.63,
    'install/1'                    =>   5.00,
    'intellect'                    =>   1.51,
    'interlisp'                    =>   1.38,
    'interpreted basic'            =>   0.75,
    'interpreted c'                =>   0.63,
    'iqlisp'                       =>   1.38,
    'iqrp'                         =>   6.15,
    'j2ee'                         =>   1.60,
    'janus'                        =>   1.13,
    'Java'                         =>   1.36,
'Javascript'                   =>   1.48,
'JSP'                          =>   1.48,
    'JCL'                          =>   1.67,
    'joss'                         =>   0.75,
    'jovial'                       =>   0.75,
    'jsp'                          =>   1.36,
    'kappa'                        =>   2.00,
    'kbms'                         =>   1.63,
    'kcl'                          =>   1.25,
    'kee'                          =>   1.63,
    'keyplus'                      =>   2.00,
    'kl'                           =>   1.25,
    'klo'                          =>   1.25,
    'knowol'                       =>   1.63,
    'krl'                          =>   1.38,
    'Korn Shell'                   =>   3.81,
    'ladder logic'                 =>   2.22,
    'lambit/l'                     =>   1.25,
    'lattice c'                    =>   0.63,
    'liana'                        =>   0.63,
    'lilith'                       =>   1.13,
    'linc ii'                      =>   5.71,
    'Lisp'                         =>   1.25,
    'loglisp'                      =>   1.38,
    'loops'                        =>   3.81,
    'lotus 123 dos'                =>  13.33,
    'lotus macros'                 =>   0.75,
    'lotus notes'                  =>   3.64,
    'lucid 3d'                     =>  13.33,
    'lyric'                        =>   1.51,
    'm'                            =>   5.00,
    'macforth'                     =>   1.25,
    'mach1'                        =>   2.00,
    'machine language'             =>   0.13,
    'maestro'                      =>   5.00,
    'magec'                        =>   5.00,
    'magik'                        =>   3.81,
    'Lake'                         =>   3.81,
'Make'                       =>   2.50,
    'mantis'                       =>   2.96,
    'mapper'                       =>   0.99,
    'mark iv'                      =>   2.00,
    'mark v'                       =>   2.22,
    'mathcad'                      =>  16.00,
    'mdl'                          =>   2.22,
    'mentor'                       =>   1.51,
    'mesa'                         =>   0.75,
    'microfocus cobol'             =>   1.00,
    'microforth'                   =>   1.25,
    'microsoft c'                  =>   0.63,
    'microstep'                    =>   4.00,
    'miranda'                      =>   2.00,
    'model 204'                    =>   2.11,
    'modula 2'                     =>   1.00,
    'mosaic'                       =>  13.33,
    # 'ms c ++ v. 7'                 =>   1.51,
    'ms compiled basic'            =>   0.88,
    'msl'                          =>   1.25,
    'mulisp'                       =>   1.25,
    'MUMPS'                        =>   4.21,
    'Nastran'                      =>   1.13,
    'natural'                      =>   1.54,
    'natural 1'                    =>   1.51,
    'natural 2'                    =>   1.74,
    'natural construct'            =>   3.20,
    'natural language'             =>   0.03,
    'netron/cap'                   =>   4.21,
    'nexpert'                      =>   1.63,
    'nial'                         =>   1.63,
    'nomad2'                       =>   2.00,
    'nonprocedural default'        =>   2.22,
    'notes vip'                    =>   2.22,
    'nroff'                        =>   1.51,
    'object assembler'             =>   1.25,
    'object lisp'                  =>   2.76,
    'object logo'                  =>   2.76,
    'object pascal'                =>   2.76,
    'object star'                  =>   5.00,
    'Objective C'                  =>   2.96,
    'objectoriented default'       =>   2.76,
    'objectview'                   =>   3.20,
    'ogl'                          =>   1.00,
    'omnis 7'                      =>   2.00,
    'oodl'                         =>   2.76,
    'ops'                          =>   1.74,
    'ops5'                         =>   1.38,
    'oracle'                       =>   2.76,
    'Oracle Reports'               =>   2.76,
    'Oracle Forms'                 =>   2.67,
    'Oracle Developer/2000'        =>   3.48,
    'oscar'                        =>   0.75,
    'pacbase'                      =>   1.67,
    'pace'                         =>   2.00,
    'paradox/pal'                  =>   2.22,
    'Pascal'                       =>   0.88,
    'pc focus'                     =>   2.22,
    'pdl millenium'                =>   3.81,
    'pdp11 ade'                    =>   1.51,
    'peoplesoft'                   =>   2.50,
    'Perl'                         =>   4.00,
    'persistance object builder'   =>   3.81,
    'pilot'                        =>   1.51,
    'pl/1'                         =>   1.38,
    'pl/m'                         =>   1.13,
    'pl/s'                         =>   0.88,
    'pl/sql'                       =>   2.58,
    'planit'                       =>   1.51,
    'planner'                      =>   1.25,
    'planperfect 1'                =>  11.43,
    'plato'                        =>   1.51,
    'polyforth'                    =>   1.25,
    'pop'                          =>   1.38,
    'poplog'                       =>   1.38,
    'power basic'                  =>   1.63,
    'powerbuilder'                 =>   3.33,
    'powerhouse'                   =>   5.71,
    'ppl (plus)'                   =>   2.00,
    'problemoriented default'      =>   1.13,
    'proc'                         =>   2.96,
    'procedural default'           =>   0.75,
    'professional pascal'          =>   0.88,
    'program generator default'    =>   5.00,
    'progress v4'                  =>   2.22,
    'proiv'                        =>   1.38,
    'prolog'                       =>   1.25,
    'prose'                        =>   0.75,
    'proteus'                      =>   0.75,
    'qbasic'                       =>   1.38,
    'qbe'                          =>   6.15,
    'qmf'                          =>   5.33,
    'qnial'                        =>   1.63,
    'quattro'                      =>  13.33,
    'quattro pro'                  =>  13.33,
    'query default'                =>   6.15,
    'quick basic 1'                =>   1.25,
    'quick basic 2'                =>   1.31,
    'quick basic 3'                =>   1.38,
    'quick c'                      =>   0.63,
    'quickbuild'                   =>   2.86,
    'quiz'                         =>   5.33,
    'rally'                        =>   2.00,
    'ramis ii'                     =>   2.00,
    'rapidgen'                     =>   2.86,
    'ratfor'                       =>   0.88,
    'rdb'                          =>   2.00,
    'realia'                       =>   1.74,
    'realizer 1.0'                 =>   2.00,
    'realizer 2.0'                 =>   2.22,
    'relate/3000'                  =>   2.00,
    'reuse default'                =>  16.00,
    'Rexx'                         =>   1.19,
    'Rexx (mvs)'                   =>   1.00,
    'Rexx (os/2)'                  =>   1.74,
    'rm basic'                     =>   0.88,
    'rm cobol'                     =>   0.75,
    'rm fortran'                   =>   0.75,
    'rpg i'                        =>   1.00,
    'rpg ii'                       =>   1.63,
    'rpg iii'                      =>   1.63,
    'rtexpert 1.4'                 =>   1.38,
    'sabretalk'                    =>   0.90,
    'sail'                         =>   0.75,
    'sapiens'                      =>   5.00,
    'sas'                          =>   1.95,
    'savvy'                        =>   6.15,
    'sbasic'                       =>   0.88,
    'sceptre'                      =>   1.13,
    'scheme'                       =>   1.51,
    'screen painter default'       =>  13.33,
    'sequal'                       =>   6.67,
    'Bourne Shell'                 =>   3.81,
    'ksh'                          =>   3.81,
    'C Shell'                      =>   3.81,
    'siebel tools '                =>   6.15,
    'simplan'                      =>   2.22,
    'simscript'                    =>   1.74,
    'simula'                       =>   1.74,
    'simula 67'                    =>   1.74,
    'simulation default'           =>   1.74,
    'slogan'                       =>   0.98,
    'smalltalk'                    =>   2.50,
    'smalltalk 286'                =>   3.81,
    'smalltalk 80'                 =>   3.81,
    'smalltalk/v'                  =>   3.81,
    'snap'                         =>   1.00,
    'snobol24'                     =>   0.63,
    'softscreen'                   =>   5.71,
    'solo'                         =>   1.38,
    'speakeasy'                    =>   2.22,
    'spinnaker ppl'                =>   2.22,
    'splus'                        =>   2.50,
    'spreadsheet default'          =>  13.33,
    'sps'                          =>   0.25,
    'spss'                         =>   2.50,
    'SQL'                          =>   2.29,
    'sqlwindows'                   =>   6.67,
    'statistical default'          =>   2.50,
    'strategem'                    =>   2.22,
    'stress'                       =>   1.13,
    'strongly typed default'       =>   0.88,
    'style'                        =>   1.74,
    'superbase 1.3'                =>   2.22,
    'surpass'                      =>  13.33,
    'sybase'                       =>   2.00,
    'symantec c++'                 =>   2.76,
    'symbolang'                    =>   1.25,
    'synchroworks'                 =>   4.44,
    'synon/2e'                     =>   4.21,
    'systemw'                      =>   2.22,
    'tandem access language'       =>   0.88,
    'Tcl/Tk'                       =>   1.25,
    'telon'                        =>   5.00,
    'tessaract'                    =>   2.00,
    'the twin'                     =>  13.33,
    'themis'                       =>   6.15,
    'tiief'                        =>   5.71,
    'topspeed c++'                 =>   2.76,
    'transform'                    =>   5.33,
    'translisp plus'               =>   1.43,
    'treet'                        =>   1.25,
    'treetran'                     =>   1.25,
    'trs80 basic'                  =>   0.63,
    'true basic'                   =>   1.25,
    'turbo c'                      =>   0.63,
    # 'turbo c++'                    =>   1.51,
    'turbo expert'                 =>   1.63,
    'turbo pascal >5'              =>   1.63,
    'turbo pascal 14'              =>   1.00,
    'turbo pascal 45'              =>   1.13,
    'turbo prolog'                 =>   1.00,
    'turing'                       =>   1.00,
    'tutor'                        =>   1.51,
    'twaice'                       =>   1.63,
    'ucsd pascal'                  =>   0.88,
    'ufo/ims'                      =>   2.22,
    'uhelp'                        =>   2.50,
    'uniface'                      =>   5.00,
    # 'unix shell scripts'           =>   3.81,
    'vax acms'                     =>   1.38,
    'vax ade'                      =>   2.00,
    'vbscript'                     =>   2.35,
    'vectran'                      =>   0.75,
    'vhdl '                        =>   4.21,
    'visible c'                    =>   1.63,
    'visible cobol'                =>   2.00,
    'visicalc 1'                   =>   8.89,
    'visual 4.0'                   =>   2.76,
    'visual basic'                 =>   1.90,
    'visual basic 1'               =>   1.74,
    'visual basic 2'               =>   1.86,
    'visual basic 3'               =>   2.00,
    'visual basic 4'               =>   2.22,
    'visual basic 5'               =>   2.76,
'Visual Basic'               =>   2.76,
    'visual basic dos'             =>   2.00,
    'visual c++'                   =>   2.35,
    'visual cobol'                 =>   4.00,
    'visual objects'               =>   5.00,
    'visualage'                    =>   3.81,
    'visualgen'                    =>   4.44,
    'vpf'                          =>   0.84,
    'vsrexx'                       =>   2.50,
    'vulcan'                       =>   1.25,
    'vz programmer'                =>   2.22,
    'warp x'                       =>   2.00,
    'watcom c'                     =>   0.63,
    'watcom c/386'                 =>   0.63,
    'waterloo c'                   =>   0.63,
    'waterloo pascal'              =>   0.88,
    'watfiv'                       =>   0.94,
    'watfor'                       =>   0.88,
    'web scripts'                  =>   5.33,
    'whip'                         =>   0.88,
    'wizard'                       =>   2.86,
    'xlisp'                        =>   1.25,
    'yacc'                         =>   1.51,
    'yacc++'                       =>   1.51,
    'zbasic'                       =>   0.88,
    'zim'                          =>   4.21,
    'zlisp'                        =>   1.25,

'Expect'  => 2.00,
'C/C++ Header'  => 1.00, 
'inc'     => 1.00,
'lex'     => 1.00,
'MATLAB'  => 4.00,
'IDL'     => 3.80,
'Octave'  => 4.00,
'ML'      => 3.00,
'Modula3' => 2.00,
'PHP'     => 3.50,
'Python'  => 4.20,
'Ruby'    => 4.20,
'sed'     => 4.00,
'lua'     => 4.00,
);
# 1}}}
} # end sub set_constants()

####################################################################
sub Install_Regexp_Common {                  # {{{1
    # Installs portions of Damian Conway's & Abigail's Regexp::Common
    # module, v2.120, into a temporary directory for the duration of
    # this run.

    my %Regexp_Common_Contents = ();
$Regexp_Common_Contents{'Common'} = <<'EOCommon'; # {{{2
package Regexp::Common;

use 5.00473;
use strict;

local $^W = 1;

use vars qw /$VERSION %RE %sub_interface $AUTOLOAD/;

($VERSION) = q $Revision: 2.120 $ =~ /([\d.]+)/;


####################################################################
sub _croak {
    require Carp;
    goto &Carp::croak;
}

####################################################################
sub _carp {
    require Carp;
    goto &Carp::carp;
}

####################################################################
sub new {
    my ($class, @data) = @_;
    my %self;
    tie %self, $class, @data;
    return \%self;
}

####################################################################
sub TIEHASH {
    my ($class, @data) = @_;
    bless \@data, $class;
}

####################################################################
sub FETCH {
    my ($self, $extra) = @_;
    return bless ref($self)->new(@$self, $extra), ref($self);
}

# Modification for cloc:  only need a few modules from Regexp::Common.
my %imports = map {$_ => "Regexp::Common::$_"}
              qw /balanced comment delimited /;
#my %imports = map {$_ => "Regexp::Common::$_"}
#              qw /balanced CC     comment   delimited lingua list
#                  net      number profanity SEN       URI    whitespace
#                  zip/;

####################################################################
sub import {
    shift;  # Shift off the class.
    tie %RE, __PACKAGE__;
    {
        no strict 'refs';
        *{caller() . "::RE"} = \%RE;
    }

    my $saw_import;
    my $no_defaults;
    my %exclude;
    foreach my $entry (grep {!/^RE_/} @_) {
        if ($entry eq 'pattern') {
            no strict 'refs';
            *{caller() . "::pattern"} = \&pattern;
            next;
        }
        # This used to prevent $; from being set. We still recognize it,
        # but we won't do anything.
        if ($entry eq 'clean') {
            next;
        }
        if ($entry eq 'no_defaults') {
            $no_defaults ++;
            next;
        }
        if (my $module = $imports {$entry}) {
            $saw_import ++;
            eval "require $module;";
            die $@ if $@;
            next;
        }
        if ($entry =~ /^!(.*)/ && $imports {$1}) {
            $exclude {$1} ++;
            next;
        }
        # As a last resort, try to load the argument.
        my $module = $entry =~ /^Regexp::Common/
                            ? $entry
                            : "Regexp::Common::" . $entry;
        eval "require $module;";
        die $@ if $@;
    }

    unless ($saw_import || $no_defaults) {
        foreach my $module (values %imports) {
            next if $exclude {$module};
            eval "require $module;";
            die $@ if $@;
        }
    }

    my %exported;
    foreach my $entry (grep {/^RE_/} @_) {
        if ($entry =~ /^RE_(\w+_)?ALL$/) {
            my $m  = defined $1 ? $1 : "";
            my $re = qr /^RE_${m}.*$/;
            while (my ($sub, $interface) = each %sub_interface) {
                next if $exported {$sub};
                next unless $sub =~ /$re/;
                {
                    no strict 'refs';
                    *{caller() . "::$sub"} = $interface;
                }
                $exported {$sub} ++;
            }
        }
        else {
            next if $exported {$entry};
            _croak "Can't export unknown subroutine &$entry"
                unless $sub_interface {$entry};
            {
                no strict 'refs';
                *{caller() . "::$entry"} = $sub_interface {$entry};
            }
            $exported {$entry} ++;
        }
    }
}

sub AUTOLOAD { _croak "Can't $AUTOLOAD" }

sub DESTROY {}

my %cache;

my $fpat = qr/^(-\w+)/;

sub _decache {
        my @args = @{tied %{$_[0]}};
        my @nonflags = grep {!/$fpat/} @args;
        my $cache = get_cache(@nonflags);
        _croak "Can't create unknown regex: \$RE{"
            . join("}{",@args) . "}"
                unless exists $cache->{__VAL__};
        _croak "Perl $] does not support the pattern "
            . "\$RE{" . join("}{",@args)
            . "}.\nYou need Perl $cache->{__VAL__}{version} or later"
                unless ($cache->{__VAL__}{version}||0) <= $];
        my %flags = ( %{$cache->{__VAL__}{default}},
                      map { /$fpat\Q$;\E(.*)/ ? ($1 => $2)
                          : /$fpat/           ? ($1 => undef)
                          :                     ()
                          } @args);
        $cache->{__VAL__}->_clone_with(\@args, \%flags);
}

use overload q{""} => \&_decache;


sub get_cache {
        my $cache = \%cache;
        foreach (@_) {
                $cache = $cache->{$_}
                      || ($cache->{$_} = {});
        }
        return $cache;
}

sub croak_version {
        my ($entry, @args) = @_;
}

sub pattern {
        my %spec = @_;
        _croak 'pattern() requires argument: name => [ @list ]'
                unless $spec{name} && ref $spec{name} eq 'ARRAY';
        _croak 'pattern() requires argument: create => $sub_ref_or_string'
                unless $spec{create};

        if (ref $spec{create} ne "CODE") {
                my $fixed_str = "$spec{create}";
                $spec{create} = sub { $fixed_str }
        }

        my @nonflags;
        my %default;
        foreach ( @{$spec{name}} ) {
                if (/$fpat=(.*)/) {
                        $default{$1} = $2;
                }
                elsif (/$fpat\s*$/) {
                        $default{$1} = undef;
                }
                else {
                        push @nonflags, $_;
                }
        }

        my $entry = get_cache(@nonflags);

        if ($entry->{__VAL__}) {
                _carp "Overriding \$RE{"
                   . join("}{",@nonflags)
                   . "}";
        }

        $entry->{__VAL__} = bless {
                                create  => $spec{create},
                                match   => $spec{match} || \&generic_match,
                                subs    => $spec{subs}  || \&generic_subs,
                                version => $spec{version},
                                default => \%default,
                            }, 'Regexp::Common::Entry';

        foreach (@nonflags) {s/\W/X/g}
        my $subname = "RE_" . join ("_", @nonflags);
        $sub_interface{$subname} = sub {
                push @_ => undef if @_ % 2;
                my %flags = @_;
                my $pat = $spec{create}->($entry->{__VAL__},
                               {%default, %flags}, \@nonflags);
                if (exists $flags{-keep}) { $pat =~ s/\Q(?k:/(/g; }
                else { $pat =~ s/\Q(?k:/(?:/g; }
                return exists $flags {-i} ? qr /(?i:$pat)/ : qr/$pat/;
        };

        return 1;
}

sub generic_match {$_ [1] =~  /$_[0]/}
sub generic_subs  {$_ [1] =~ s/$_[0]/$_[2]/}

sub matches {
        my ($self, $str) = @_;
        my $entry = $self -> _decache;
        $entry -> {match} -> ($entry, $str);
}

sub subs {
        my ($self, $str, $newstr) = @_;
        my $entry = $self -> _decache;
        $entry -> {subs} -> ($entry, $str, $newstr);
        return $str;
}


package Regexp::Common::Entry;
# use Carp;

local $^W = 1;

use overload
    q{""} => sub {
        my ($self) = @_;
        my $pat = $self->{create}->($self, $self->{flags}, $self->{args});
        if (exists $self->{flags}{-keep}) {
            $pat =~ s/\Q(?k:/(/g;
        }
        else {
            $pat =~ s/\Q(?k:/(?:/g;
        }
        if (exists $self->{flags}{-i})   { $pat = "(?i)$pat" }
        return $pat;
    };

sub _clone_with {
    my ($self, $args, $flags) = @_;
    bless { %$self, args=>$args, flags=>$flags }, ref $self;
}
# 
#    Copyright (c) 2001 - 2005, Damian Conway and Abigail. All Rights
#  Reserved. This module is free software. It may be used, redistributed
#      and/or modified under the terms of the Perl Artistic License
#            (see http://www.perl.com/perl/misc/Artistic.html)
EOCommon
# 2}}}
$Regexp_Common_Contents{'Common/comment'} = <<'EOC';   # {{{2
# $Id: comment.pm,v 2.116 2005/03/16 00:00:02 abigail Exp $

package Regexp::Common::comment;

use strict;
local $^W = 1;

use Regexp::Common qw /pattern clean no_defaults/;
use vars qw /$VERSION/;

($VERSION) = q $Revision: 2.116 $ =~ /[\d.]+/g;

my @generic = (
    {languages => [qw /ABC Forth/],
     to_eol    => ['\\\\']},   # This is for just a *single* backslash.

    {languages => [qw /Ada Alan Eiffel lua/],
     to_eol    => ['--']},

    {languages => [qw /Advisor/],
     to_eol    => ['#|//']},

    {languages => [qw /Advsys CQL Lisp LOGO M MUMPS REBOL Scheme
                       SMITH zonefile/],
     to_eol    => [';']},

    {languages => ['Algol 60'],
     from_to   => [[qw /comment ;/]]},

    {languages => [qw {ALPACA B C C-- LPC PL/I}],
     from_to   => [[qw {/* */}]]},

    {languages => [qw /awk fvwm2 Icon mutt Perl Python QML R Ruby shell Tcl/],
     to_eol    => ['#']},

    {languages => [[BASIC => 'mvEnterprise']],
     to_eol    => ['[*!]|REM']},

    {languages => [qw /Befunge-98 Funge-98 Shelta/],
     id        => [';']},

    {languages => ['beta-Juliet', 'Crystal Report', 'Portia'],
     to_eol    => ['//']},

    {languages => ['BML'],
     from_to   => [['<?_c', '_c?>']],
    },

    {languages => [qw /C++/, 'C#', qw /Cg ECMAScript FPL Java JavaScript/],
     to_eol    => ['//'],
     from_to   => [[qw {/* */}]]},

    {languages => [qw /CLU LaTeX slrn TeX/],
     to_eol    => ['%']},

    {languages => [qw /False/],
     from_to   => [[qw !{ }!]]},

    {languages => [qw /Fortran/],
     to_eol    => ['!']},

    {languages => [qw /Haifu/],
     id        => [',']},

    {languages => [qw /ILLGOL/],
     to_eol    => ['NB']},

    {languages => [qw /INTERCAL/],
     to_eol    => [q{(?:(?:PLEASE(?:\s+DO)?|DO)\s+)?(?:NOT|N'T)}]},

    {languages => [qw /J/],
     to_eol    => ['NB[.]']},

    {languages => [qw /Nickle/],
     to_eol    => ['#'],
     from_to   => [[qw {/* */}]]},

    {languages => [qw /Oberon/],
     from_to   => [[qw /(* *)/]]},
     
    {languages => [[qw /Pascal Delphi/], [qw /Pascal Free/], [qw /Pascal GPC/]],
     to_eol    => ['//'],
     from_to   => [[qw !{ }!], [qw !(* *)!]]},

    {languages => [[qw /Pascal Workshop/]],
     id        => [qw /"/],
     from_to   => [[qw !{ }!], [qw !(* *)!], [qw !/* */!]]},

    {languages => [qw /PEARL/],
     to_eol    => ['!'],
     from_to   => [[qw {/* */}]]},

    {languages => [qw /PHP/],
     to_eol    => ['#', '//'],
     from_to   => [[qw {/* */}]]},

    {languages => [qw !PL/B!],
     to_eol    => ['[.;]']},

    {languages => [qw !PL/SQL!],
     to_eol    => ['--'],
     from_to   => [[qw {/* */}]]},

    {languages => [qw /Q-BAL/],
     to_eol    => ['`']},

    {languages => [qw /Smalltalk/],
     id        => ['"']},

    {languages => [qw /SQL/],
     to_eol    => ['-{2,}']},

    {languages => [qw /troff/],
     to_eol    => ['\\\"']},

    {languages => [qw /vi/],
     to_eol    => ['"']},

    {languages => [qw /*W/],
     from_to   => [[qw {|| !!}]]},
);

my @plain_or_nested = (
   [Caml         =>  undef,       "(*"  => "*)"],
   [Dylan        =>  "//",        "/*"  => "*/"],
   [Haskell      =>  "-{2,}",     "{-"  => "-}"],
   [Hugo         =>  "!(?!\\\\)", "!\\" => "\\!"],
   [SLIDE        =>  "#",         "(*"  => "*)"],
);

#
# Helper subs.
#

sub combine      {
    local $_ = join "|", @_;
    if (@_ > 1) {
        s/\(\?k:/(?:/g;
        $_ = "(?k:$_)";
    }
    $_
}

sub to_eol  ($)  {"(?k:(?k:$_[0])(?k:[^\\n]*)(?k:\\n))"}
sub id      ($)  {"(?k:(?k:$_[0])(?k:[^$_[0]]*)(?k:$_[0]))"}  # One char only!
sub from_to      {
    local $^W = 1;
    my ($begin, $end) = @_;

    my $qb  = quotemeta $begin;
    my $qe  = quotemeta $end;
    my $fe  = quotemeta substr $end   => 0, 1;
    my $te  = quotemeta substr $end   => 1;

    "(?k:(?k:$qb)(?k:(?:[^$fe]+|$fe(?!$te))*)(?k:$qe))";
}


my $count = 0;
sub nested {
    local $^W = 1;
    my ($begin, $end) = @_;

    $count ++;
    my $r = '(??{$Regexp::Common::comment ['. $count . ']})';

    my $qb  = quotemeta $begin;
    my $qe  = quotemeta $end;
    my $fb  = quotemeta substr $begin => 0, 1;
    my $fe  = quotemeta substr $end   => 0, 1;

    my $tb  = quotemeta substr $begin => 1;
    my $te  = quotemeta substr $end   => 1;

    use re 'eval';

    my $re;
    if ($fb eq $fe) {
        $re = qr /(?:$qb(?:(?>[^$fb]+)|$fb(?!$tb)(?!$te)|$r)*$qe)/;
    }
    else {
        local $"      =  "|";
        my   @clauses =  "(?>[^$fb$fe]+)";
        push @clauses => "$fb(?!$tb)" if length $tb;
        push @clauses => "$fe(?!$te)" if length $te;
        push @clauses =>  $r;
        $re           =   qr /(?:$qb(?:@clauses)*$qe)/;
    }

    $Regexp::Common::comment [$count] = qr/$re/;
}

#
# Process data.
#

foreach my $info (@plain_or_nested) {
    my ($language, $mark, $begin, $end) = @$info;
    pattern name    => [comment => $language],
            create  =>
                sub {my $re     = nested $begin => $end;
                     my $prefix = defined $mark ? $mark . "[^\n]*\n|" : "";
                     exists $_ [1] -> {-keep} ? qr /($prefix$re)/
                                              : qr  /$prefix$re/
                },
            version => 5.006,
            ;
}


foreach my $group (@generic) {
    my $pattern = combine +(map {to_eol   $_} @{$group -> {to_eol}}),
                           (map {from_to @$_} @{$group -> {from_to}}),
                           (map {id       $_} @{$group -> {id}}),
                  ;
    foreach my $language  (@{$group -> {languages}}) {
        pattern name    => [comment => ref $language ? @$language : $language],
                create  => $pattern,
                ;
    }
}
                

    
#
# Other languages.
#

# http://www.pascal-central.com/docs/iso10206.txt
pattern name    => [qw /comment Pascal/],
        create  => '(?k:' . '(?k:[{]|[(][*])'
                          . '(?k:[^}*]*(?:[*][^)][^}*]*)*)'
                          . '(?k:[}]|[*][)])'
                          . ')'
        ;

# http://www.templetons.com/brad/alice/language/
pattern name    =>  [qw /comment Pascal Alice/],
        create  =>  '(?k:(?k:[{])(?k:[^}\n]*)(?k:[}]))'
        ;


# http://westein.arb-phys.uni-dortmund.de/~wb/a68s.txt
pattern name    => [qw (comment), 'Algol 68'],
        create  => q {(?k:(?:#[^#]*#)|}                           .
                   q {(?:\bco\b(?:[^c]+|\Bc|\bc(?!o\b))*\bco\b)|} .
                   q {(?:\bcomment\b(?:[^c]+|\Bc|\bc(?!omment\b))*\bcomment\b))}
        ;


# See rules 91 and 92 of ISO 8879 (SGML).
# Charles F. Goldfarb: "The SGML Handbook".
# Oxford: Oxford University Press. 1990. ISBN 0-19-853737-9.
# Ch. 10.3, pp 390.
pattern name    => [qw (comment HTML)],
        create  => q {(?k:(?k:<!)(?k:(?:--(?k:[^-]*(?:-[^-]+)*)--\s*)*)(?k:>))},
        ;


pattern name    => [qw /comment SQL MySQL/],
        create  => q {(?k:(?:#|-- )[^\n]*\n|} .
                   q {/\*(?:(?>[^*;"']+)|"[^"]*"|'[^']*'|\*(?!/))*(?:;|\*/))},
        ;

# Anything that isn't <>[]+-.,
# http://home.wxs.nl/~faase009/Ha_BF.html
pattern name    => [qw /comment Brainfuck/],
        create  => '(?k:[^<>\[\]+\-.,]+)'
        ;

# Squeak is a variant of Smalltalk-80.
# http://www.squeak.
# http://mucow.com/squeak-qref.html
pattern name    => [qw /comment Squeak/],
        create  => '(?k:(?k:")(?k:[^"]*(?:""[^"]*)*)(?k:"))'
        ;

#
# Scores of less than 5 or above 17....
# http://www.cliff.biffle.org/esoterica/beatnik.html
@Regexp::Common::comment::scores = (1,  3,  3,  2,  1,  4,  2,  4,  1,  8,
                                    5,  1,  3,  1,  1,  3, 10,  1,  1,  1,
                                    1,  4,  4,  8,  4, 10);
pattern name    =>  [qw /comment Beatnik/],
        create  =>  sub {
            use re 'eval';
            my ($s, $x);
            my $re = qr {\b([A-Za-z]+)\b
                         (?(?{($s, $x) = (0, lc $^N);
                              $s += $Regexp::Common::comment::scores
                                    [ord (chop $x) - ord ('a')] while length $x;
                              $s  >= 5 && $s < 18})XXX|)}x;
            $re;
        },
        version  => 5.008,
        ;


# http://www.cray.com/craydoc/manuals/007-3692-005/html-007-3692-005/
#  (Goto table of contents/3.3 Source Form)
# Fortran, in fixed format. Comments start with a C, c or * in the first
# column, or a ! anywhere, but the sixth column. Then end with a newline.
pattern name    =>  [qw /comment Fortran fixed/],
        create  =>  '(?k:(?k:(?:^[Cc*]|(?<!^.....)!))(?k:[^\n]*)(?k:\n))'
        ;


# http://www.csis.ul.ie/cobol/Course/COBOLIntro.htm
# Traditionally, comments in COBOL were indicated with an asteriks in
# the seventh column. Modern compilers may be more lenient.
pattern name    =>  [qw /comment COBOL/],
        create  =>  '(?<=^......)(?k:(?k:[*])(?k:[^\n]*)(?k:\n))',
        version =>  '5.008',
        ;

1;
#
#    Copyright (c) 2001 - 2003, Damian Conway. All Rights Reserved.
#      This module is free software. It may be used, redistributed
#     and/or modified under the terms of the Perl Artistic License
#           (see http://www.perl.com/perl/misc/Artistic.html)
EOC
# 2}}}
$Regexp_Common_Contents{'Common/balanced'} = <<'EOB';   # {{{2
package Regexp::Common::balanced; {

use strict;
local $^W = 1;

use vars qw /$VERSION/;
($VERSION) = q $Revision: 2.101 $ =~ /[\d.]+/g;

use Regexp::Common qw /pattern clean no_defaults/;

my %closer = ( '{'=>'}', '('=>')', '['=>']', '<'=>'>' );
my $count = -1;
my %cache;

sub nested {
    local $^W = 1;
    my ($start, $finish) = @_;

    return $Regexp::Common::balanced [$cache {$start} {$finish}]
            if exists $cache {$start} {$finish};

    $count ++;
    my $r = '(??{$Regexp::Common::balanced ['. $count . ']})';

    my @starts   = map {s/\\(.)/$1/g; $_} grep {length}
                        $start  =~ /([^|\\]+|\\.)+/gs;
    my @finishes = map {s/\\(.)/$1/g; $_} grep {length}
                        $finish =~ /([^|\\]+|\\.)+/gs;

    push @finishes => ($finishes [-1]) x (@starts - @finishes);

    my @re;
    local $" = "|";
    foreach my $begin (@starts) {
        my $end = shift @finishes;

        my $qb  = quotemeta $begin;
        my $qe  = quotemeta $end;
        my $fb  = quotemeta substr $begin => 0, 1;
        my $fe  = quotemeta substr $end   => 0, 1;

        my $tb  = quotemeta substr $begin => 1;
        my $te  = quotemeta substr $end   => 1;

        use re 'eval';

        my $add;
        if ($fb eq $fe) {
            push @re =>
                   qr /(?:$qb(?:(?>[^$fb]+)|$fb(?!$tb)(?!$te)|$r)*$qe)/;
        }
        else {
            my   @clauses =  "(?>[^$fb$fe]+)";
            push @clauses => "$fb(?!$tb)" if length $tb;
            push @clauses => "$fe(?!$te)" if length $te;
            push @clauses =>  $r;
            push @re      =>  qr /(?:$qb(?:@clauses)*$qe)/;
        }
    }

    $cache {$start} {$finish} = $count;
    $Regexp::Common::balanced [$count] = qr/@re/;
}


pattern name    => [qw /balanced -parens=() -begin= -end=/],
        create  => sub {
            my $flag = $_[1];
            unless (defined $flag -> {-begin} && length $flag -> {-begin} &&
                    defined $flag -> {-end}   && length $flag -> {-end}) {
                my @open  = grep {index ($flag->{-parens}, $_) >= 0}
                             ('[','(','{','<');
                my @close = map {$closer {$_}} @open;
                $flag -> {-begin} = join "|" => @open;
                $flag -> {-end}   = join "|" => @close;
            }
            my $pat = nested @$flag {qw /-begin -end/};
            return exists $flag -> {-keep} ? qr /($pat)/ : $pat;
        },
        version => 5.006,
        ;

}

1;
#
#     Copyright (c) 2001 - 2003, Damian Conway. All Rights Reserved.
#       This module is free software. It may be used, redistributed
#      and/or modified under the terms of the Perl Artistic License
#            (see http://www.perl.com/perl/misc/Artistic.html)
EOB
# 2}}}
$Regexp_Common_Contents{'Common/delimited'} = <<'EOD';   # {{{2
# $Id: delimited.pm,v 2.104 2005/03/16 00:22:45 abigail Exp $

package Regexp::Common::delimited;

use strict;
local $^W = 1;

use Regexp::Common qw /pattern clean no_defaults/;
use vars qw /$VERSION/;

($VERSION) = q $Revision: 2.104 $ =~ /[\d.]+/g;

sub gen_delimited {

    my ($dels, $escs) = @_;
    # return '(?:\S*)' unless $dels =~ /\S/;
    if (length $escs) {
        $escs .= substr ($escs, -1) x (length ($dels) - length ($escs));
    }
    my @pat = ();
    my $i;
    for ($i=0; $i < length $dels; $i++) {
        my $del = quotemeta substr ($dels, $i, 1);
        my $esc = length($escs) ? quotemeta substr ($escs, $i, 1) : "";
        if ($del eq $esc) {
            push @pat,
                 "(?k:$del)(?k:[^$del]*(?:(?:$del$del)[^$del]*)*)(?k:$del)";
        }
        elsif (length $esc) {
            push @pat,
                 "(?k:$del)(?k:[^$esc$del]*(?:$esc.[^$esc$del]*)*)(?k:$del)";
        }
        else {
            push @pat, "(?k:$del)(?k:[^$del]*)(?k:$del)";
        }
    }
    my $pat = join '|', @pat;
    return "(?k:$pat)";
}

sub _croak {
    require Carp;
    goto &Carp::croak;
}

pattern name   => [qw( delimited -delim= -esc=\\ )],
        create => sub {my $flags = $_[1];
                       _croak 'Must specify delimiter in $RE{delimited}'
                             unless length $flags->{-delim};
                       return gen_delimited (@{$flags}{-delim, -esc});
                  },
        ;

pattern name   => [qw( quoted -esc=\\ )],
        create => sub {my $flags = $_[1];
                       return gen_delimited (q{"'`}, $flags -> {-esc});
                  },
        ;


1;
#
#     Copyright (c) 2001 - 2003, Damian Conway. All Rights Reserved.
#       This module is free software. It may be used, redistributed
#      and/or modified under the terms of the Perl Artistic License
#            (see http://www.perl.com/perl/misc/Artistic.html)
EOD
# 2}}}
    my $problems        = 0;
    $HAVE_Rexexp_Common = 0;
    my $dir = tempdir( CLEANUP => 0 );  # 1 = delete on exit
    print "Using temp dir [$dir] to install Regexp::Common\n" unless $opt_quiet;
    my $Regexp_dir        = "$dir/Regexp";
    my $Regexp_Common_dir = "$dir/Regexp/Common";
    mkdir $Regexp_dir       ;
    mkdir $Regexp_Common_dir;

    foreach my $module_file (keys %Regexp_Common_Contents) {
        my $OUT = new IO::File "$dir/Regexp/${module_file}.pm", "w";
        if (defined $OUT) {
            print $OUT $Regexp_Common_Contents{$module_file};
            $OUT->close;
        } else {
            warn "Failed to install Regexp::${module_file}.pm\n";
            $problems = 1;
        }
    }

    push @INC, $dir;
    eval "use Regexp::Common qw /comment RE_comment_HTML/";
    $HAVE_Rexexp_Common = 1 unless $problems;
} # 1}}}

####################################################################
sub call_regexp_common {                     # {{{1
    my ($ra_lines, $language ) = @_;

    Install_Regexp_Common() unless $HAVE_Rexexp_Common;

    print "-> call_regexp_common\n" if $opt_v > 2;

    my $all_lines = join("", @{$ra_lines});

    no strict 'vars';
    # otherwise get:
    #  Global symbol "%RE" requires explicit package name at cloc line xx.
    if ($all_lines =~ $RE{comment}{$language}) {
        # Suppress "Use of uninitialized value in regexp compilation" that
        # pops up when $1 is undefined--happens if there's a bug in the $RE
        # This Pascal comment will trigger it:
        #         (* This is { another } test. **)
        # Curiously, testing for "defined $1" breaks the substitution.
        no warnings; 

        $all_lines =~ s/$1//g;
    }
    # a bogus use of %RE to avoid:
    # Name "main::RE" used only once: possible typo at cloc line xx.
    print scalar keys %RE if $opt_v < -20;

    print "<- call_regexp_common\n" if $opt_v > 2;
    return split("\n", $all_lines);
} # 1}}}

####################################################################
sub plural_form {                            # {{{1
    # For getting the right plural form on some English nouns.
    my $n = shift @_;
    if ($n == 1) { return ( 1, "" ); }
    else         { return ($n, "s"); }
} # 1}}}

sub matlab_or_objective_C {                  # {{{1
    my ($file        , # in
        $rh_Err      , # in   hash of error codes
        $raa_errors  , # out
        $rs_language , # out
       ) = @_;

    print "-> matlab_or_objective_C\n" if $opt_v > 2;
    # matlab markers:
    #   first line starts with "function"
    #   some lines start with "%"
    #
    # Objective C markers:
    #   has /* ... */ style comments
    #   some lines start with @
    #   some lines start with #include

    ${$rs_language} = "";
    my $IN = new IO::File $file, "r";
    if (!defined $IN) {
        push @{$raa_errors}, [$rh_Err->{'Unable to read'} , $file];
        return;
    }

    my $matlab_points      = 0;
    my $objective_C_points = 0;
    while (<$IN>) {
        if      (m{^\s*/\*}) {           #   /*
            ++$objective_C_points;
            --$matlab_points;
        } elsif (m{^\s*#include}) {
            ++$objective_C_points;
            --$matlab_points;
        } elsif (m{^\s*@(interface|implementation|protocol|public|protected|private|end)\s}o) {
            # Objective C without a doubt
            $objective_C_points = 1;
            $matlab_points      = 0;
            last;
        } elsif (m{^\s*function}) {
            --$objective_C_points;
            ++$matlab_points;
        } elsif (m{^\s*%}) {              #   %
            --$objective_C_points;
            ++$matlab_points;
        }
    }
    $IN->close;

    print "<- matlab_or_objective_C(M=$matlab_points, C=$objective_C_points)\n"
        if $opt_v > 2;
    if ($matlab_points > $objective_C_points) {
        ${$rs_language} = "MATLAB";
    } else {
        ${$rs_language} = "Objective C";
    }

} # 1}}}

# subroutines copied from SLOCCount
my %lex_files    = ();  # really_is_lex()
my %expect_files = ();  # really_is_expect()
my %pascal_files = ();  # really_is_pascal(), really_is_incpascal()
my %php_files    = ();  # really_is_php()

####################################################################
sub really_is_lex {                          # {{{1
# Given filename, returns TRUE if its contents really is lex.
# lex file must have "%%", "%{", and "%}".
# In theory, a lex file doesn't need "%{" and "%}", but in practice
# they all have them, and requiring them avoid mislabeling a
# non-lexfile as a lex file.

 my $filename = shift;
 chomp($filename);

 my $is_lex = 0;      # Value to determine.
 my $percent_percent = 0;
 my $percent_opencurly = 0;
 my $percent_closecurly = 0;

 # Return cached result, if available:
 if ($lex_files{$filename}) { return $lex_files{$filename};}

 open(LEX_FILE, "<$filename") ||
      die "Can't open $filename to determine if it's lex.\n";
 while(<LEX_FILE>) {
   $percent_percent++     if (m/^\s*\%\%/);
   $percent_opencurly++   if (m/^\s*\%\{/);
   $percent_closecurly++   if (m/^\s*\%\}/);
 }
 close(LEX_FILE);

 if ($percent_percent && $percent_opencurly && $percent_closecurly)
          {$is_lex = 1;}

 $lex_files{$filename} = $is_lex; # Store result in cache.

 return $is_lex;
} # 1}}}

####################################################################
sub really_is_expect {                       # {{{1
# Given filename, returns TRUE if its contents really are Expect.
# Many "exp" files (such as in Apache and Mesa) are just "export" data,
# summarizing something else # (e.g., its interface).
# Sometimes (like in RPM) it's just misc. data.
# Thus, we need to look at the file to determine
# if it's really an "expect" file.

 my $filename = shift;
 chomp($filename);

# The heuristic is as follows: it's Expect _IF_ it:
# 1. has "load_lib" command and either "#" comments or {}.
# 2. {, }, and one of: proc, if, [...], expect

 my $is_expect = 0;      # Value to determine.

 my $begin_brace = 0;  # Lines that begin with curly braces.
 my $end_brace = 0;    # Lines that begin with curly braces.
 my $load_lib = 0;     # Lines with the Load_lib command.
 my $found_proc = 0;
 my $found_if = 0;
 my $found_brackets = 0;
 my $found_expect = 0;
 my $found_pound = 0;

 # Return cached result, if available:
 if ($expect_files{$filename}) { return expect_files{$filename};}

 open(EXPECT_FILE, "<$filename") ||
      die "Can't open $filename to determine if it's expect.\n";
 while(<EXPECT_FILE>) {

   if (m/#/) {$found_pound++; s/#.*//;}
   if (m/^\s*\{/) { $begin_brace++;}
   if (m/\{\s*$/) { $begin_brace++;}
   if (m/^\s*\}/) { $end_brace++;}
   if (m/\};?\s*$/) { $end_brace++;}
   if (m/^\s*load_lib\s+\S/) { $load_lib++;}
   if (m/^\s*proc\s/) { $found_proc++;}
   if (m/^\s*if\s/) { $found_if++;}
   if (m/\[.*\]/) { $found_brackets++;}
   if (m/^\s*expect\s/) { $found_expect++;}
 }
 close(EXPECT_FILE);

 if ($load_lib && ($found_pound || ($begin_brace && $end_brace)))
          {$is_expect = 1;}
 if ( $begin_brace && $end_brace &&
      ($found_proc || $found_if || $found_brackets || $found_expect))
          {$is_expect = 1;}

 $expect_files{$filename} = $is_expect; # Store result in cache.

 return $is_expect;
} # 1}}}

####################################################################
sub really_is_pascal {                       # {{{1
# Given filename, returns TRUE if its contents really are Pascal.

# This isn't as obvious as it seems.
# Many ".p" files are Perl files
# (such as /usr/src/redhat/BUILD/ispell-3.1/dicts/czech/glob.p),
# others are C extractions
# (such as /usr/src/redhat/BUILD/linux/include/linux/umsdos_fs.p
# and some files in linuxconf).
# However, test files in "p2c" really are Pascal, for example.

# Note that /usr/src/redhat/BUILD/ucd-snmp-4.1.1/ov/bitmaps/UCD.20.p
# is actually C code.  The heuristics determine that they're not Pascal,
# but because it ends in ".p" it's not counted as C code either.
# I believe this is actually correct behavior, because frankly it
# looks like it's automatically generated (it's a bitmap expressed as code).
# Rather than guess otherwise, we don't include it in a list of
# source files.  Let's face it, someone who creates C files ending in ".p"
# and expects them to be counted by default as C files in SLOCCount needs
# their head examined.  I suggest examining their head
# with a sucker rod (see syslogd(8) for more on sucker rods).

# This heuristic counts as Pascal such files such as:
#  /usr/src/redhat/BUILD/teTeX-1.0/texk/web2c/tangleboot.p
# Which is hand-generated.  We don't count woven documents now anyway,
# so this is justifiable.

 my $filename = shift;
 chomp($filename);

# The heuristic is as follows: it's Pascal _IF_ it has all of the following
# (ignoring {...} and (*...*) comments):
# 1. "^..program NAME" or "^..unit NAME",
# 2. "procedure", "function", "^..interface", or "^..implementation",
# 3. a "begin", and
# 4. it ends with "end.",
#
# Or it has all of the following:
# 1. "^..module NAME" and
# 2. it ends with "end.".
#
# Or it has all of the following:
# 1. "^..program NAME",
# 2. a "begin", and
# 3. it ends with "end.".
#
# The "end." requirements in particular filter out non-Pascal.
#
# Note (jgb): this does not detect Pascal main files in fpc, like
# fpc-1.0.4/api/test/testterminfo.pas, which does not have "program" in
# it

 my $is_pascal = 0;      # Value to determine.

 my $has_program = 0;
 my $has_unit = 0;
 my $has_module = 0;
 my $has_procedure_or_function = 0;
 my $found_begin = 0;
 my $found_terminating_end = 0;
 my $has_begin = 0;

 # Return cached result, if available:
 if ($pascal_files{$filename}) { return pascal_files{$filename};}

 open(PASCAL_FILE, "<$filename") ||
      die "Can't open $filename to determine if it's pascal.\n";
 while(<PASCAL_FILE>) {
   s/\{.*?\}//g;  # Ignore {...} comments on this line; imperfect, but effective.
   s/\(\*.*?\*\)//g;  # Ignore (*...*) comments on this line; imperfect, but effective.
   if (m/\bprogram\s+[A-Za-z]/i)  {$has_program=1;}
   if (m/\bunit\s+[A-Za-z]/i)     {$has_unit=1;}
   if (m/\bmodule\s+[A-Za-z]/i)   {$has_module=1;}
   if (m/\bprocedure\b/i)         { $has_procedure_or_function = 1; }
   if (m/\bfunction\b/i)          { $has_procedure_or_function = 1; }
   if (m/^\s*interface\s+/i)      { $has_procedure_or_function = 1; }
   if (m/^\s*implementation\s+/i) { $has_procedure_or_function = 1; }
   if (m/\bbegin\b/i) { $has_begin = 1; }
   # Originally I said:
   # "This heuristic fails if there are multi-line comments after
   # "end."; I haven't seen that in real Pascal programs:"
   # But jgb found there are a good quantity of them in Debian, specially in 
   # fpc (at the end of a lot of files there is a multiline comment
   # with the changelog for the file).
   # Therefore, assume Pascal if "end." appears anywhere in the file.
   if (m/end\.\s*$/i) {$found_terminating_end = 1;}
#   elsif (m/\S/) {$found_terminating_end = 0;}
 }
 close(PASCAL_FILE);

 # Okay, we've examined the entire file looking for clues;
 # let's use those clues to determine if it's really Pascal:

 if ( ( ($has_unit || $has_program) && $has_procedure_or_function &&
     $has_begin && $found_terminating_end ) ||
      ( $has_module && $found_terminating_end ) ||
      ( $has_program && $has_begin && $found_terminating_end ) )
          {$is_pascal = 1;}

 $pascal_files{$filename} = $is_pascal; # Store result in cache.

 return $is_pascal;
} # 1}}}

####################################################################
sub really_is_incpascal {                    # {{{1
# Given filename, returns TRUE if its contents really are Pascal.
# For .inc files (mainly seen in fpc)

 my $filename = shift;
 chomp($filename);

# The heuristic is as follows: it is Pacal if any of the following:
# 1. really_is_pascal returns true
# 2. Any usual reserverd word is found (program, unit, const, begin...)

 # If the general routine for Pascal files works, we have it
 if (&really_is_pascal ($filename)) { 
   $pascal_files{$filename} = 1;
   return 1;
 }

 my $is_pascal = 0;      # Value to determine.
 my $found_begin = 0;

 open(PASCAL_FILE, "<$filename") ||
      die "Can't open $filename to determine if it's pascal.\n";
 while(<PASCAL_FILE>) {
   s/\{.*?\}//g;  # Ignore {...} comments on this line; imperfect, but effective.
   s/\(\*.*?\*\)//g;  # Ignore (*...*) comments on this line; imperfect, but effective.
   if (m/\bprogram\s+[A-Za-z]/i)  {$is_pascal=1;}
   if (m/\bunit\s+[A-Za-z]/i)     {$is_pascal=1;}
   if (m/\bmodule\s+[A-Za-z]/i)   {$is_pascal=1;}
   if (m/\bprocedure\b/i)         {$is_pascal = 1; }
   if (m/\bfunction\b/i)          {$is_pascal = 1; }
   if (m/^\s*interface\s+/i)      {$is_pascal = 1; }
   if (m/^\s*implementation\s+/i) {$is_pascal = 1; }
   if (m/\bconstant\s+/i)         {$is_pascal=1;}
   if (m/\bbegin\b/i) { $found_begin = 1; }
   if ((m/end\.\s*$/i) && ($found_begin = 1)) {$is_pascal = 1;}
   if ($is_pascal) {
     last;
   }
 }

 close(PASCAL_FILE);
 $pascal_files{$filename} = $is_pascal; # Store result in cache.
 return $is_pascal;
} # 1}}}

####################################################################
sub really_is_php {                          # {{{1
# Given filename, returns TRUE if its contents really is php.

 my $filename = shift;
 chomp($filename);

 my $is_php = 0;      # Value to determine.
 # Need to find a matching pair of surrounds, with ending after beginning:
 my $normal_surround = 0;  # <?; bit 0 = <?, bit 1 = ?>
 my $script_surround = 0;  # <script..>; bit 0 = <script language="php">
 my $asp_surround = 0;     # <%; bit 0 = <%, bit 1 = %>

 # Return cached result, if available:
 if ($php_files{$filename}) { return $php_files{$filename};}

 open(PHP_FILE, "<$filename") ||
      die "Can't open $filename to determine if it's php.\n";
 while(<PHP_FILE>) {
   if (m/\<\?/)                           { $normal_surround |= 1; }
   if (m/\?\>/ && ($normal_surround & 1)) { $normal_surround |= 2; }
   if (m/\<script.*language="?php"?/i)    { $script_surround |= 1; }
   if (m/\<\/script\>/i && ($script_surround & 1)) { $script_surround |= 2; }
   if (m/\<\%/)                           { $asp_surround |= 1; }
   if (m/\%\>/ && ($asp_surround & 1)) { $asp_surround |= 2; }
 }
 close(PHP_FILE);

 if ( ($normal_surround == 3) || ($script_surround == 3) ||
      ($asp_surround == 3)) {
   $is_php = 1;
 }

 $php_files{$filename} = $is_php; # Store result in cache.

 return $is_php;
} # 1}}}
__END__
Other counting tools:
    http://www.qsm.com/CodeCounters.html  (directory of tools)
    http://www.cmcrossroads.com/bradapp/clearperl/sclc.html
mode values (stat $item)[2]
       Unix    Windows
file:  33188   33206
dir :  16832   16895
link:  33261   33206
pipe:   4544    null