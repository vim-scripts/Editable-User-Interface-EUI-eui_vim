" File:                  eui_vim.vim
" Copyright (C) 2004 Suresh Govindachar 
" Version:               1.01
" Date:                  February 10, 2004
" Reference:             eui_vim.txt
" 
" General Notes:                                           {{{1
"
" Exports:  
"    The only user visible things are:
"              g:loaded_eui_vim   
"        which can be used to diable this plugin and 
"        the <f-args> based command 
"              EUIProcess 
"        which can be used to call the function s:EUIProcess()
"        The user need not know about any other variable and function;  the 
"        names of the other functions end with an underscore to emphasize this. 
"
"    There is an autocommand for VimLeavePre  
"
"---------------------------------------------------------------------------

"bookkeeping {{{1
if exists("loaded_eui_vim")    "{{{2
   finish
endif
"see help use-cpo-save for info on the variable save_cpo  {{{2
let s:save_cpo = &cpo
set cpo&vim
" In general, g:loaded_eui_vim is                         {{{2
"       undefined if this file hasn't been sourced,
"       1         if this file has been sourced and 
"       2         if EUIInit_() has been executed 
let g:loaded_eui_vim = 1
" s:vim2perl will have the full-path to the fifo-file used to send data and commands 
" from vim (using functions in eui_vim.vim) to the perl script eui_vim.pl
let s:vim2perl=' '                                        "{{{2


"functions {{{1
function! s:EUIInit_() "{{{2 
" g:loaded_eui_vim is 1 on input and 2 on output                     {{{3
" s:vim2perl is undefined on input and gets assigned the full path 
"            to the fifo-file that will be used to send data and 
"            commands to the external (perl script based) program
" A timestamp is written to the fifo-file via a call to the 
"            function s:EUIVim2perl_()
" A buffer is created for the fifo-file and is set to not have  
"            a swapfile, made locally autoreadable and hidden
" The external program is launched.  If perl.exe is in the search 
"            path, the external program is a perl script;  otherwise,
"            on windows, the external program is a self-contained 
"            execuitable.  Three arguments are given to the external 
"            program:  server=v:servername, v2pfifo=s:vim2perl and 
"            gvim=expand($VIMRUNTIME .'/gvim')
"
   "Sanity-check to see if called unnecessarily...              {{{3
   if(g:loaded_eui_vim != 1) | execute confirm("Something bad has happened w.r.t. calls to initialization !\(  ") | return | endif
   
   "Sanity-check to see if this vim-session is a server...
   if !exists("v:servername") | execute confirm("Cannot have an EUI since this VIM isn't a server :-\(  ") | return | endif 
   "...may be commented out for speed 
   
   "Create a fifo to send data to perl.  This 'fifo' is just a temporary file
   "that is written to by this script and read by the external perl script. 
   "The name of the file is the Vim server's name concatinated with the
   "timestamp.  The steps are: 
   "locate the temporary directory 
   let s:vim2perl = fnamemodify(tempname(), ":p:h")
   "add the appropriate slash (/ or \) at the end 
   let osslash = "/"
   if(match(s:vim2perl, "\\"))
      let osslash = "\\"
   endif
   let s:vim2perl = s:vim2perl . l:osslash
   "make the temporary file's name with full path (foo stores the timestamp)
   let foo = localtime()
   let s:vim2perl = s:vim2perl . v:servername . foo
   "and finally, create a sub-window for the file, create the file, set 
   "it to not have a swapfile, make it locally autoreadable and hide it
   execute 'split | drop ' . s:vim2perl . ' | set noswapfile | setlocal autoread | hide '
   
   "Convert the timestamp into human readable form and 'push it, by 
   "calling EUIVim2perl_(), into the vim2perl fifo' (ie, write it into 
   "the temp file just created).
   call s:EUIVim2perl_(strftime("%I:%M:%S %p, %a %b %d, %Y", l:foo)) 

   "build the command to launch perl code giving it args of server name, 
   "full path to xfer file and full path to gvim -- and execute it (perl
   "code will append .exe, if needed, to gvim)
   "Note: the expand adjusts the slash to match the os (also, not 
   "      using v:progname -- instead, hardcoding the name 'gvim') 
   "
   "preceding needs to be slightly modified if system does not have perl.exe!
   "begin by seeing if perl.exe exists (doing this only for Windows) 
   if(match(s:vim2perl, "\\"))
      let has_perl=substitute($path,   ";", ",", "g") 
      let has_perl=substitute(l:has_perl, "\\\\,", ",", "g") 
      let has_perl=globpath(l:has_perl, "perl.exe") 
   endif
   if(l:has_perl != "")
      let has_perl = 'perl -w ' . expand($VIM .'/vimfiles/perl/eui_vim.pl') 
   else
      let has_perl = expand($VIM .'/vimfiles/perl/eui_vim.exe') 
   endif
   execute   ' silent ! start ' . l:has_perl . 
           \ ' server=' . v:servername . ' v2pfifo=' . s:vim2perl 
           \ ' gvim='.expand($VIMRUNTIME .'/gvim')
      
   "not waiting for any confirmation from perl
   let g:loaded_eui_vim = 2
endfunction


function! s:EUIVim2perl_(stuff) "{{{2 
" The input stuff is written to the fifo-file and thereby transferred  {{{3
" to the external program.  The writing to the fifo-file is by use
" of the redir and echon commands (for more, see help on these commands).
"
  "On error, it is good if error messages get captured in s:vim2perl   {{{3
  "but any 'DONE' token in a:stuff doesn't get put into the file.  
  "Note: Not sure how well the above intent has been achieved -- found 
  "      "help silent" to be too confusing.
  silent execute ":redir >>".s:vim2perl."|echon \"".a:stuff."\n\"|redir END"
endfunction


function! s:EUIProcess(do_what, ...) "{{{2  
"The very first argument to this function is the command (which    {{{3
"   could be quit).  
"The subsequent arguments are optional.  They are only present if the
"   command requires any data.  These arguments are used for passing 
"   any data required by the command, as follows;  the arguments are 
"   register names in which the data would have been stored
"
"Processing within this function is as follows;   
"   Unless we are quitting, we initialize if not already initialized  
"   If we have been initialized, we pass on the command/data (command 
"      might be to quit) to the external program -- see below for how 
"      this happens
"   If we are quitting, we then call EUIQuit_()  
"
"Command/data is sent to the external program by calling EUIVim2perl_()
"to write the following to the fifo-file s:vim2perl:
"   In the following, '|' is used to mark the beginning of the line that
"   gets written to the fifo-file.  Also, any stuff on a line including 
"   and after a '#' is an explanation and not part of what is written to 
"   the fifo-file.  In the third line below, 'file', 'line' and 'column' 
"   refer to where the cursor was when this function was called by the user.
"
"   |START         # beginning marker    
"   |<a:do_what>   # the command
"   |<full path to file>=<line number>=<column number> # cursor's location
"   |[(if a:0>=1, contents of a:1)=]  # in the code below, note the use of 
"   |[...]                            #    double curlies to handle variable  
"   |[(if a:0==N, contents of a:N)=]  #    number of arguments
"   |DONE          # end marker, with carriage return
"   | 
"
   "Initialize if ((not already initialized) and (we arn't quitting))   {{{3
   if((g:loaded_eui_vim != 2) && (a:do_what != "quit")) | call s:EUIInit_() | endif 
 
   "g:loaded_eui_vim may not be 2 when a:do_what is quit;  however, when
   "loaded_eui_vim is 2, we have something to send, even when do_what is quit
   if(g:loaded_eui_vim == 2)
     "start building stuff to send to perl
     let l:stuff = "START\n" . a:do_what . "\n"
     "add the caller's identity in the form <file>=<line>=<col>(bufname will 
     "have a ':' in it and so can't use ':' as record separator)
     let l:stuff = l:stuff . substitute(expand("%:p"), '\', '\\\\', 'g') . 
                  \    '=' . line(".") . '=' . col(".") . "\n"  
     "add data, if any
     let idx = 1
     while idx <= a:0
       "the record separator for data is ' =', and so any '=' in the data is
       "changed to '\=' [not a very well done escape -- so far, an unused 'feature']  
       "(for help with argument to getreg, see curly-braces-names)
       let l:stuff = l:stuff . substitute(getreg({"a:".idx}), '=', '\\\\=', "g") . " =\n" 
       let idx = idx + 1
     endwhile
     "add the end signature 
     "Actuallly, better to first send stuff without the end signature 'DONE', 
     "to then check for errors, and to send 'DONE' only if no error -- but all 
     "this will not be done in this release because need to get a better idea 
     "of possible error mechanisms
     let l:stuff = l:stuff . "DONE\n"
     "then just send it
     call s:EUIVim2perl_(l:stuff)
   endif

   "clean up if we are quitting
   if(a:do_what == "quit") | call s:EUIQuit_() | endif 
endfunction
if !exists(":EUIProcess") " see line 38 of example in help usr_41.txt {{{3
  command  -nargs=+ EUIProcess call s:EUIProcess(<f-args>) 
endif


function! s:EUIQuit_() "{{{2  
"Should not be called directly -- called by s:EUIProcess("quit")  {{{3
"EUIProcess would have told external program to quit before calling 
"   this function.
"Deletes buffer associated with the s:vim2perl fifo-file 
"Resets s:vim2perl to space
"Resets g:loaded_eui_vim to 1

   "not necessary to wait until perl calls delete file which sets deleted {{{3 
   if(s:vim2perl != ' ') 
      execute 'silent bdelete! ' . s:vim2perl 
   endif 
   let s:vim2perl = ' ' 
   let g:loaded_eui_vim = 1
endfunction

"auxiliary tasks {{{1
augroup EUICleanup  "{{{2
"Have external program quit, and clean up after ourselves (external 
"program deletes the fifo-file -- after reading the quit command in it!;
"buffers associated with fifo-file deleted by eventual call to EUIQuit_()).
au!
autocmd VimLeavePre * call s:EUIProcess("quit")
augroup END


"restore saved cpo     {{{2
let &cpo = s:save_cpo

"<SID> any functions?

"EOF
