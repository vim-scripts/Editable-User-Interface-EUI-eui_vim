#!c:\opt\perl\bin\perl.exe  
# File:                  eui_vim.pl
# Copyright (C) 2004 Suresh Govindachar 
# Version:               1.01
# Date:                  February 10, 2004
# Reference:             eui_vim.txt
# 
# General Notes:                                           {{{1
#
# Description:                                             
#
#    This script is not directly executed by the user.  Rather, 
#    it is is invoked from eui_vim.vim as:
#    perl -w <full path name of this file> 
#            server=<vim server name> 
#            v2pfifo=<full path name of fifo-file from vim to perl> 
#            gvim=<full path name of executable gvim (.exe removed even if present)>
#
#    Once invoked, it soon goes into a while(1) loop waiting to 
#    process commands and data from the user through eui_vim.vim.  
#
#    Eui_vim.vim communicates to this process using the fifo-file (v2pfifo).  
#
#    This process communicates to the user, if needed, essentially 
#    via the --remote-send command (to the vim server that was specified 
#    during this process' invocation).
#
#---------------------------------------------------------------------------
#preamble                                                            {{{1
use strict;
use warnings;
$|++;           # disable output buffering
#---------------------------------------------------------------------------

#----------------------------------------------------
# Begin by extracting the arguments of invocation                    {{{1
#     server=<vim server name> 
#     v2pfifo=<full path name of fifo-file from vim to perl> 
#     gvim=<full path name of executable gvim (without .exe)>
my $server='';
my $vim2perl='';
my $gvim='';
foreach my $foo(@ARGV)
{
   (my $tag, my $val) = split('=', $foo);
   ($tag =~ m/server/)  and $server=$val; 
   ($tag =~ m/v2pfifo/) and $vim2perl=$val; 
   ($tag =~ m/gvim/)    and $gvim=$val; 
}
#add .exe to gvim if on windows
($gvim =~ m/^.{1}:/) and $gvim .= ".exe"; 
#build the preamble of commands sent to vim
my $preamble="$gvim --servername $server -u NONE -U NONE ";
#build the default file for messages from perl to vim -- the name 
#of this file is eui and it is in the same directory as $vim2perl
   $vim2perl =~ m:^(.*[\\/])(.+?)$:; # first match, $1, is the directory
my $perl2vim = $1 . "eui";
# we are done with extracting and processing the command line arguments
#----------------------------------------------------

#----------------------------------------------------
# declarations                                                    {{{1
# names of subroutines that cannot be called from vim end with an "_"                     
my $defined_processes = '\n\tlist,\n\tdemo_plot and\n\tquit';
sub eui_list($);
sub eui_demo_plot($);
sub eui_quit($);
sub eui_undefined_($$);
# the structure used for calling subroutines here
my %eui_subs = ();
$eui_subs{"quit"}         = \&eui_quit;
$eui_subs{"demo_plot"}    = \&eui_demo_plot;
$eui_subs{"list"}         = \&eui_list;
$eui_subs{"undefined"}    = \&eui_undefined_;
#
#----------------------------------------------------
#Configuration
my $start_mark="START";  #start of record in fifo-file
my $done_mark="DONE";    #end of record in fifo-file
#
#----------------------------------------------------
#Other subroutines
sub start_processing_($); #note the semicolon!!! -- a declaration, not a definition
sub eui_talk_($);         #message shown in vim as a pop-up confirm dialog box
sub eui_write_($$$);      #message shown in vim's command-line
sub eui_remote_send_($);  #workhorse routine for perl to vim communication 
sub eui_unpack_data_($);  #generic routine to unpack the input data
#
#----------------------------------------------------
#This is the main while(1) loop                                   {{{1
#It consists of several tasks: 
#  waiting for requests from vim
#  staying in sync with the start and done markers
#  collecting data between the start and done markers
#  staying in sync with the fifo-file even if user delets some stuff in it  
#----------------------------------------------------
{
    my $foo="";
    open(VIM2PERL, $vim2perl) or die "Can't open fifo $vim2perl $! for reading-only\n";
    my $pos=tell VIM2PERL;
    my $seen_start=0;
    my $stuff='';
    while(1)
    {
        for($pos = tell VIM2PERL; <VIM2PERL>;  $pos = tell VIM2PERL)
        #reset on each start mark (system error can result in two starts without a done)
        {
	          $foo=$_;
            $stuff .= $foo;
            if($foo =~ m/^\s*$start_mark\s*$/o)
            {
               $seen_start = 1;
               $stuff ='';  # got reset
            }
            if(($foo =~ m/^\s*$done_mark\s*$/o) and ($seen_start))
            {
               $seen_start = 0;
               $stuff =~ s/\s*$done_mark\s*$//o; #remove the done mark
               # process stuff and come back here
               &start_processing_($stuff); 
               # I suppose once a file is opened for reading, it is immediately
               # broght into memory and so even if the file is changed "outside"
               # the stuff in memory is preserved.  This supposition is what 
               # happens when Vim opens a file for reading -- vim knows the 
               # entire file as of the time it opened it even though it displays 
               # only a few lines from it -- and vim continues to know this even 
               # if the file is changed outside.  The upshot is that I do not have
               # to account for external modifications -- additions or deletions -- of
               # the vim2perl file while inside this for loop.
            }
            #nothing bad happens if a done mark is seen before a start mark
        }
        sleep 1;
        # account for external additions xor deletions (not both) to the file
        # nothing needs to be done about additions (without deletions)
        # next few lines handle deletions (without additions):
        seek VIM2PERL, -1, 2; 
        $foo = tell VIM2PERL;
        $foo +=1;
        ($foo < $pos) and $pos=$foo; 
        seek VIM2PERL, $pos, 0;
    }
    die "how did this get executed? !!!";
}
#----------------------------------------------------
# definitions of subroutines                             {{{1
#----------------------------------------------------
# description:  start_processing_($) {{{2
#
# This sub-routine is called from within the while(1) loop.
# It expects that the argument passed to it has the form:
#     <required processing>=<associated data>
#
# This sub-routine extracts <required processing> and calls 
# the proper sub-routine while passing to it <associated data>
#
# If no sub-routine can be associated with <required processing>
# then the "undefined" sub-routine is called with the two 
# arguments <required processing> and <associated data>
#
sub start_processing_($) # {{{2
{
  my($stuff) = (@_);
  $stuff =~ s/^\s+//o;
  (my $do_what, $stuff) = split /\s+/, $stuff, 2;
  (defined $do_what) or $do_what=' ';
  (defined $stuff)   or $stuff=' ';
  if(exists $eui_subs{$do_what})
  {    
    &{$eui_subs{$do_what}}($stuff); 
  }
  else
  { # unknown do_what
    &{$eui_subs{"undefined"}}($do_what, $stuff); 
  } 
}
#--------------------------------------------------------
# description:  eui_undefined_($$) {{{2
#
# This sub-routine is called by start_processing() when it
# cannot determine a better sub-routine to call.  
#
# The arguments passed to this sub-routine are   
#      <required processing> and <associated data>
# where <required processing> is the string that start_processing
# tried to associate a sub-routine with, and <associated data> is
# the rest of the input provided to start_processing.
#
# This sub-routine calls eui_talk_($) to result in the user being
# presented a pop-up dialog box with an error message that 
# includes <required processing> and <associated data>
#
sub eui_undefined_($$) # {{{2
{
  my($do_what, $stuff) = (@_);
  $do_what  = "Error:  The requested processing $do_what is undefined\n";
  if(defined $stuff and ($stuff ne ' '))
  {
    $do_what .= "and so data is being returned unprocessed:\n";
    $do_what .= $stuff;
  }
  &eui_talk_($do_what);
}
#--------------------------------------------------------
# description:  eui_list($) {{{2
#
# This sub-routine is called by start_processing()
#  
# This sub-routine ignores any input data.
#
# It calls eui_tell($) to result in the user being shown (on the
# command line of the vim server) the string $defined_processes.
#
# Observe that this file is such that $defined_processes is a 
# multi-line string constituting a list of all the processes 
# that the user can call.
#
sub eui_list($) # {{{2
{
  my $stuff = "The defined processes are:  ".$defined_processes;
  &eui_tell_($stuff);
}
#--------------------------------------------------------
# description:  eui_demo_plot($) {{{2
#
# This routine was written to be a simple example of how eui_vim 
# could be used.  In essence, it takes two one dimensional arrays,
# x and y, as input and outputs simple stastistical information 
# about y (min, max, mean).  If it can find the pgnuplot utility 
# then it also plots y vs x.
#
# This sub-routine is called by start_processing() when the user
# specifies (from the vim server) "demo_plot" as the required processing.
#  
# The routine calls eui_unpack_data_() to unpack its input.
#
# It calls eui_write_() to return the computed statistical information
# to the user (at the vim server).
#
sub eui_demo_plot($) # {{{2
{
   my($return2file, $return2line, $return2column, $x, $y, @unexpected) = &eui_unpack_data_(@_);
   
   (@unexpected) and return; # returning because something bad happened 
   return unless $y;         # returning because something bad happened 

   my @x = split /\s+/, $x;
   my @y = split /\s+/, $y;

   #simple statistics on y
   my $min = $y[0];
   my $max = $y[0];
   my $sum = $y[0];
   for(my $i=1; $i < scalar(@y); $i++)
   {
      $min  = ($min < $y[$i]) ? $min : $y[$i]; 
      $max  = ($max > $y[$i]) ? $max : $y[$i]; 
      $sum += $y[$i];
   }
   my $stuff='';
   $stuff  = sprintf "%20s%4d\n", "The minimum is ", $min; 
   $stuff .= sprintf "%20s%4d\n", "The maximum is ", $max; 
   $stuff .= sprintf "%20s%4d\n", "The average is ", $sum/(scalar(@y)); 
   #send back the statistics
   &eui_write_($return2file, $return2line, $stuff);

   #-----------------------------------------------------------
   #It would actually be better to trigger the next few lines of code 
   #once during initialization.  But it is here so that readers of 
   #this file who are new to eui_vim won't get side-tracked by seeing
   #all this being triggered near the beginning of this file. 
   # 
   my $gnuplot = ''; 
   # if present but not in path, replace the preceding by something like:
   # my $gnuplot = 'C:\opt\gp373w32\pgnuplot.exe'; 
   #
   if(!$gnuplot) # for Windows only!!!
   {
     my $foo = $ENV{PATH};              # string with ; as separator 
     $foo =~ s/\\;/;/go;                # remove trailing \ in directory names
     $foo =~ s/;|$/\\pgnuplot\.exe;/go; # append \pgnuplot.exe to directory names
     foreach(reverse split(";", $foo)){ -e and $gnuplot = $_;}
   }
   return unless $gnuplot;
   #-----------------------------------------------------------

   my $pid='';
   my $sleep_count='';
   do 
   {
     $pid = open(THECOMMAND, "|-", "$gnuplot");
     unless (defined $pid) 
     {
       warn "cannot fork: $!";
       die "...tried too many times -- should never have had to retry" if $sleep_count++ > 3;
       sleep 10;
     }
   }until defined $pid;
   (!$pid) and die "Since when did win32 start returning zero on a forked open? $!\n"; 
   $min -= 10;
   $max += 10;
   print THECOMMAND  "set title \"Demo Plot for Vim Based EUI\"\n";
   print THECOMMAND  "set xlabel \"Count\"\n";
   print THECOMMAND  "set ylabel \"Square\"\n";
   print THECOMMAND  "set yrange [$min:$max]\n";
   print THECOMMAND  "set grid y\n";
   print THECOMMAND  "plot \"-\" using 1:2 title 'Squares' with linespoints \n";

   for(my $i=0; $i < scalar(@y); $i++)
   {
     print THECOMMAND  "$x[$i]  $y[$i]\n";
   }
   print THECOMMAND  "e\n";
   
   print THECOMMAND  "pause -1 \"The Demo Worked\"\n";
   close(THECOMMAND);
}
#--------------------------------------------------------
#
#-----------called from here--------------
#
#--------------------------------------------------------
# description:  eui_talk_($) {{{2
#
# This is an utility routine that can be called by other routines 
# which require some data to be poped-up in a dialog box to the user.
#
# The data can be multi-line.
#
# The data is provided as the input argument.
#
# This routine builds the necessary command and sends it to the 
# vim server by calling eui_remote_send_($)
#
sub eui_talk_($) # {{{2
{
  my($stuff) = (@_);
  $stuff =~ s/\\/\\\\/go;
  $stuff =~ s/\n/\\n/go;
  my $tellvim='"<C-\><C-N>:execute confirm(\"'.$stuff.'\")<CR>"';
  &eui_remote_send_($tellvim);
}
#--------------------------------------------------------
# description:  eui_tell_($) {{{2
#
# This is an utility routine that can be called by other routines 
# which require some data to shown to the user in the vim server's 
# command-line.  
#
# The data can be multi-line data.
#
# The data is provided as the input argument.
#
# This routine builds the necessary command and sends it to the 
# vim server by calling eui_remote_send_($)
#
sub eui_tell_($) # {{{2
{
  my ($tstuff) = (@_);
  my $tellvim='"<C-\><C-N>:echo \\"'.$tstuff.' \\" <CR>" ';
  &eui_remote_send_($tellvim);
}
#--------------------------------------------------------
# description:  eui_write_($$$) {{{2
#
# This is an utility routine that can be called by other routines 
# which require some data to be written below a specified line 
# of a specified file-buffer in the vim server 
#
# The name of the file-buffer, the line-number and the data are
# provided as the three inputs to this routine. 
#
# The data can be multi-line data.
#
# This routine builds the necessary command and sends it to the 
# vim server by calling eui_remote_send_($)
#
sub eui_write_($$$) # {{{2
{
  my ($wfile, $wline, $wstuff) = (@_);
  #NOTE: insert mode will end if there is a line with just a period 
  #      and so avoid such lines in $wstuff
  $wstuff = "\ni".$wstuff;
  my $tellvim='"<C-\><C-N>:drop '.$wfile.' | '.$wline.' | normal o '.$wstuff.' <ESC> | :w <CR>"';
  &eui_remote_send_($tellvim);
}
#--------------------------------------------------------
# description:  eui_remote_send_($) {{{2
#
# This is an utility routine that can be called by other routines 
# which require a command to be issued to the vim server.
#
# The input to this routine is the command to be issued.
#
# This routine does a --remote-send of the command to the vim server
#
sub eui_remote_send_($) # {{{2
{
  my($tellvim) = (@_);
  system("$preamble --remote-send  $tellvim");
}
#--------------------------------------------------------
# description:  eui_unpack_data_($) {{{2
#
# This is an utility routine that can be called by other 
# routines to unpack the data they received when they were 
# invoked from start_processing()
#
# The format of the input data is a line of the form: 
#
#      <file_name>=<line_number>=<column_number> 
#
# followed by one or more items of data appended with "=":
#
#      [<data>=]
#
# The <data> items can be multi-line strings;  the current 
# version of the routine assumes that <data> does not contain "=".
#
# The return is an array whose elements are:
#
#    (<file_name> <line_number> <column_number> [<data>])
# 
# Any leading and trailing white space in <data> is removed. 
# However, white space within <data> is left untouched.
#
# Note:  when there is <data>, the calling subroutine can extract 
#        each one of the <data> even when they contain spaces.
#
sub eui_unpack_data_($) # {{{2
{
   my($stuff) = (@_);

   #Separate <file_name>=<line_number>=<column_number> from the actual data
   (my $return2file_line_column, $stuff) = split /\s+/, $stuff, 2; 

   #remove leading and trailing space in return2file_line_column (may be unnecessary)
   $return2file_line_column =~ s/(^\s*)|(\s*$)//go;
   #and extract its three pieces
   my @pieces = split /=/, $return2file_line_column, 3;

   while($stuff =~ m/=/o)
   {
      (my $x, $stuff) = split /=/, $stuff, 2;

      #remove leading and trailing space 
      $x =~ s/(^\s*)|(\s*=*\s*$)//go;  #the very last piece will have a trailing '='

      push(@pieces, $x);
   }
   return @pieces;
}




#--------------------------------------------------------
# description:  eui_quit($) {{{2
#
# This sub-routine is called by start_processing()
#  
# This sub-routine ignores any input data.
#
# It delets the fifo-file vim2perl and causes 
# this process to terminate (with an exit 0).
#
sub eui_quit($) # {{{2
{
  close VIM2PERL;
  unlink $vim2perl;
  exit 0;
}

__END__

