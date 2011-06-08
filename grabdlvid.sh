#!/bin/bash
# Grab Downloading Flash Video
#
# ------------------------------------------------------------------------------
# Copyright 2011 by RichD (richd44@gmail.com)
# Released under the GNU General Public License
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# ------------------------------------------------------------------------------
#
# Wait for the Flash video currently playing to finish downloading, then save it.
# Designed for the Linux GNOME desktop.
#
# Important: Not all websites serving Flash videos use the same technique.
#  In particular, for YouTube videos and for sites where the "Video URL" is
#  explicitly specified, you may have better success using a download utility
#  such as 'youtube-dl'.
#
# Requirements:
#  'zenity' installed (part of the GNOME desktop). To check, do this from terminal:
#     # zenity --version
#  Firefox or Chrome browser with Flash plugin. To check your version:
#     Type "about:plugins" in the browser address bar. Then scroll down to
#     find the Shockwave Flash Version. It should be something like "10.2 r159"
#  'mplayer' installed - used to find the final size of the video that's
#     currently being downloaded. To check, do this from terminal:
#     # mplayer --help
#
# Setup:
#  1. Make this script executable (e.g. chmod 744 ~/bin/grabdlvid.sh)
#  2. Configure the script by editing the Configuration Section.
#  3. If you want to call grabdlvid.sh via a GNOME custom keyboard shortcut
#     (recommended), set it up at System/Preferences/Keyboard Shortcuts:
#        Click 'Add' then:
#           Name: Grab Downloading Video
#           Command: grabdlvid.sh
#  4. If you also want a 'Save Now' option via a (different) GNOME custom  
#     keyboard shortcut (recommended), click 'Add' again, then:
#        Name: Save Downloading Video Now
#        Command: grabdlvid.sh savenow
#
# Usage:
#  This script must be called DURING video playback. If you set up a GNOME
#  custom keyboard shortcut, simply press that key. Otherwise from the terminal:
#     grabdlvid.sh
#
# How it works:
#  This script tries to find videos that are being downloaded using either
#  of two different Flash techniques: 
#     a) Temp file. Prior to Flash 10.2, it was easy to find the file yourself
#        in the /tmp file but starting with version 10.2, this script is a lot
#        more useful because the file is deleted but internally still open.
#     b) Browser cache - backup method. Less reliable because there may be a
#        size limit that this script cannot overcome.
#  If neither finds the file, try a download utility such as youtube-dl.
#
# Tested on Fedora 14 with:
#     Firefox 3.6.17 with Shockwave Flash 10.2 r159
#     Google Chrome 7.0.517.44 with Shockwave Flash 10.1 r103
#     Google Chrome 11.0.696.77 with Shockwave Flash 10.3 r181

#####################   CONFIGURATION SECTION   #####################
# SAVETODIR - directory where incoming videos will be copied
SAVETODIR=~/Downloads

# SAVENOWKEY - text representation of GNOME Custom Shortcut key (example: 'F8')
#  that you set up to call this script with the 'savenow' parameter.
#  Note that this is a DIFFERENT function key from the one used to call this script.
#  It is recommended that you set up a custom 'Save Now' shortcut key.
#  If this is left empty, you won't have the option of copying everything downloaded
#     so far to SAVETODIR. That means if you want to interrupt this script before
#     the download completes, your only choice will be to abort. It also means that
#     you won't be able to save your video if Autosave is OFF, which can happen
#     if mplayer cannot determine the video file size (or is not installed).
SAVENOWKEY=''

# GRABDEBUG - don't change this unless you're debugging the code
GRABDEBUG=0    # set this to 1 for debugging
##################### END CONFIGURATION SECTION #####################

# Undocumented params - useful if you want to avoid editing this script and/or
#  write your own front-end script that calls this one.
[ $# -ge 2 ] && SAVETODIR="$2"
[ $# -ge 3 ] && SAVENOWKEY="$3"
SAVENOWFILE="${SAVETODIR}/grabdlvidsavenow.txt"
[ $# -ge 4 ] && SAVENOWFILE="$4"

if [[ "$1" == "savenow" ]]; then
   echo "1" > $SAVENOWFILE
   exit 0
fi

GRABLOG="${SAVETODIR}/grabdlvid.log"
bDone=0
SaveNowFlag=0

# File selection criteria for finding the file currently being played - don't
#  change this unless you understand lsof output and awk.
#  These lines are basically hacks since the the Flash plugin algorithm is
#  undocumented (AFAIK) and may therefore change in subsequent versions.
if [ "$(pidof firefox)" ]; then
   strBrowserName="Firefox"
   # files created by npviewer.bin in /tmp/Flash* (code takes the newest one)
   lsofawk1='$4!="mem" && $5=="REG" && $1 ~ /npviewer/ && $9 ~ /Flash/'
   # if trial 1 finds nothing, then look in browser cache (but it might have size limit)
   lsofawk2='$4!="mem" && $5=="REG" && $1=="firefox" && $9 ~ /Cache/ && $9 !~ /_CACHE/'
elif [ "$(pidof chrome)" ]; then
   strBrowserName="Chrome"
   # files created by chrome in /tmp/Flash* (code takes the newest one)
   lsofawk1='$4!="mem" && $5=="REG" && $1 ~ /chrome/ && $9 ~ /Flash/'
   # if trial 1 finds nothing, then look in browser cache (but it might have size limit)
   lsofawk2='$4!="mem" && $5=="REG" && $1=="chrome" && $9 ~ /Cache/ && $9 !~ /data_/ && $9 !~ /index/'
else
   zenity --title "Unknown Browser" --error --text "grabdlvid cannot find Firefox or Chrome"
   exit 0
fi

if ! [ -d "$SAVETODIR" ]; then
   zenity --title "Missing Directory" --error --text "grabdlvid cannot find SAVETODIR: $SAVETODIR"
   exit 0
fi

strCancelText="Press Cancel to abort"
if [ -n "$SAVENOWKEY" ]; then
   strCancelText="Press $SAVENOWKEY to save now, Cancel to abort"
   echo "0" > $SAVENOWFILE # initialize signal flag to 'off'
fi
: > $GRABLOG   # truncate GRABLOG

# GetSaveNowFlag function - set global SaveNowFlag
# Usage Example:  GetSaveNowFlag
#                 [[ "$SaveNowFlag" == "1" ]] && break
GetSaveNowFlag(){
   if [ -n "$SAVENOWKEY" ]; then
      SaveNowFlag=`cat $SAVENOWFILE`
   fi
}

# getnewestof - get newest output file that matches specific criteria
#  Param: $1 - awk selection criteria to apply to lsof output lines
#  Return (echo) string to be used as input to array definition, e.g. "basnam linkpath"
#     or '' if no suitable open file is found
#  NB: 'while read' is run as a separate process so changes to variables will be lost.
getnewestof() {
   local bestftime
   local bestfpath
   local retstr
   [ $GRABDEBUG -ne 0 ] && echo "getnewestof ($strBrowserName) $1" >> $GRABLOG
   lsof | awk "$1" |
   ( while read strlsof; do
      # Parse one lsof output line. Sample string:
      #  npviewer.  7660      joe   11u      REG        8,7  54076786      73246 /tmp/FlashR3NdKG (deleted)
      [ $GRABDEBUG -ne 0 ] && echo "  ** $strlsof" >> $GRABLOG
      declare -a aryof=( $strlsof )
      ofpid=${aryof[1]} # e.g. 7660
      offds=${aryof[3]} # e.g. 11u
      ofsiz=${aryof[6]} # e.g. 54076786
      ofnam=${aryof[8]} # e.g. /tmp/FlashR3NdKG
      ofbas=$(basename "$ofnam")                      # e.g. FlashR3NdKG
      # Strip off (alphabetic) mode character(s) at the end of the FD string
      offd=${offds//[^0-9]/}     # e.g. '11u' to '11'
      tryfpath="/proc/$ofpid/fd/$offd"
      if [[ -h "$tryfpath" ]]; then    # sanity check: it's a symlink
         [ $GRABDEBUG -ne 0 ] && echo "  ** Found symlink: $tryfpath" >> $GRABLOG
         if [ -n "$bestfpath" ]; then  # this is not the first candidate file
            # compare Unix 'last modified' timestamps (seconds in epoch)
            [ -z "$bestftime" ] && bestftime=$(stat -L -c%Y "$bestfpath")
            tryftime=$(stat -L -c%Y "$tryfpath")   # -L => follow $tryfpath symlink
            if [[ $tryftime -gt $bestftime ]]; then   # this one is even newer
               bestftime=$tryftime
               bestfpath=$tryfpath
               retstr="$ofbas $tryfpath"
            fi
         else  # this is the first candidate file => best so far
            bestfpath=$tryfpath
            retstr="$ofbas $tryfpath"
         fi
      else
         echo "grabdlvid ERROR: Not a symlink: $tryfpath" >> $GRABLOG
      fi
   done
   [ $GRABDEBUG -ne 0 ] && echo "  ** Returning ${retstr}." >> $GRABLOG
   echo "$retstr" )
}

# getMBsize - returns nice displayable MB size string from integer byte value
getMBsize() {
   local fsizquo=$(( $1 / 1000000 ))
   local fsizrem=$(( $1 % 1000000 ))
   if [ $fsizquo -ge 2 ]; then
      echo "$fsizquo"
   elif [ $fsizquo -ge 1 ]; then
      printf "%.1f" "${fsizquo}.${fsizrem}"   # rounded
   else
      printf "%.2f" "${fsizquo}.${fsizrem}"   # rounded
   fi
}

# Start Main Code
fpath=''
fsize=0
finfotxt=''
retrycnt=10
stuckcnt=0  # how many times we've let it sleep even though file d/l appears stuck
while true; do    # NB: run in subshell => main won't see variable changes
   if [ -z "$fpath" ]; then      # have not yet found downloading file
      errtxt=''
      cachewarning=''
      strfinfo=$(getnewestof "$lsofawk1")    # gets open temp file(s) matching criteria
      if [[ -z "$strfinfo" ]]; then    # no "open but deleted" temp file found
         strfinfo=$(getnewestof "$lsofawk2")    # so look in browser cache
         cachewarning="\nWARNING: $strBrowserName cache limit may prevent full save."   
      fi
      if [ -n "$strfinfo" ]; then      # e.g. "FlashR3NdKG /proc/27542/fd/11"
         declare -a aryfinfo=( $strfinfo )
         fbas=${aryfinfo[0]}
         fpath=${aryfinfo[1]}
      else  # no temp or cached file found - retry if indicated
         let "retrycnt -= 1"
      fi
      if [ -z "$fpath" ] && [ $retrycnt -le 0 ]; then
         echo "# Cannot find any downloading Flash videos.\n\nTry youtube-dl <url>."
         break
      fi
      
      if [ -n "$fpath" ]; then    # found file
         # Mplayer may know final file length even though download isn't complete.
         # Use the 'filesize' value if available, otherwise 'datasize' is OK.
         #  Sample lines from mplayer 'identify' output:
         #     ID_CLIP_INFO_NAME19=filesize
         #     ID_CLIP_INFO_VALUE19=24796443
         #     ID_CLIP_INFO_N=25
         finfotxt="${fpath} has unknown size"
         eval $(mplayer -vo null -ao null -frames 0 -identify "$fpath" 2>>$GRABLOG |
               sed -ne '/^ID_/ { s/[]()|&;<>`'"'"'\\!$" []/\\&/g;p }')
         if [ -n "$ID_CLIP_INFO_N" ]; then
            for ((n=0;n<$ID_CLIP_INFO_N;n+=1)); do
               varname="ID_CLIP_INFO_NAME$n"
               if [[ "${!varname}" == "filesize" ]] || [[ "${!varname}" == "datasize" ]]; then
                  varvalue="ID_CLIP_INFO_VALUE$n"
                  fsize=${!varvalue}
                  fsizMB=$(getMBsize "$fsize")
                  finfotxt="${fpath} has ${!varname}=${fsize}"
                  [[ "${!varname}" == "filesize" ]] && break
               fi
            done
         fi
      
         fext='flv'
         fdestpath="$SAVETODIR/${fbas}.${fext}"
      else  # retry file search after sleep
         finfotxt="Not in /tmp. Checking $strBrowserName cache..."
      fi
   fi
   
   if [ -n "$fpath" ] && [ $bDone -eq 0 ]; then
      fcursize=$(stat -L -c%s "$fpath")   # -L => follow $fpath symlink
      if [ $? -ne 0 ]; then   # stat failed => we lost chance to copy
         echo "# ERROR: Lost access to $fpath"
         break
      fi
      if [ $fsize -gt 0 ]; then  # we think we know target file size
         errtxt="Autosave is ON (when size reaches 100%)${cachewarning}"
         if [ $fcursize -ge $fsize ]; then   # target size reached => assume d/l is done
            if [ $fcursize -gt $fsize ]; then
               [ $GRABDEBUG -ne 0 ] && echo "Size Warning: fsize=$fsize cursize=$fcursize" >> $GRABLOG
               errtxt="WARNING: actual file size exceeds mplayer ${!varname}"
            else
               [ $GRABDEBUG -ne 0 ] && "Assuming done because fcursize=$fcursize ge fsize=$fsize" >> $GRABLOG
               finfotxt="Download complete ($fsize bytes)"
            fi
            bDone=1
         fi
      else  # unknown target file size so user must press interrupt key to save it
         errtxt="Autosave is OFF (press $SAVENOWKEY to save file)${cachewarning}"
      fi
   fi
   if [ $bDone -eq 0 ]; then
      GetSaveNowFlag    # sets global SaveNowFlag
      if [[ "$SaveNowFlag" == "1" ]]; then
         [ $GRABDEBUG -ne 0 ] && echo "Detected interrupt key $SAVENOWKEY" >> $GRABLOG
         [ -n "$fpath" ] && finfotxt="File copy size: $fcursize bytes"
         bDone=1
      fi
   fi
   if [ $bDone -eq 1 ]; then  # download is done (or user pressed interrupt key)
      if [[ -z "$fpath" ]]; then
         zenstat="No file found - nothing was done"
      elif [ $GRABDEBUG -ne 0 ]; then  # debug only
         zenstat="DEBUG - No copy was done"
      else
         statxt="DONE"
         cp "$fpath" "$fdestpath"
         [ $? -ne 0 ] && statxt="ERROR $?"
         zenstat="${statxt}: cp $fpath $fdestpath"
      fi
      echo "# ${finfotxt}\n\n${zenstat}\n\n" # zenity progress text
      break
   else  # Keep waiting
      if [ -z "$fpath" ]; then
         zenstat="Cache search retries remaining: ${retrycnt}"
      elif [ $fsize -eq 0 ]; then
         zenstat="Downloaded so far: ${fcursize} bytes"
      else
         let "zenpercent = (100 * $fcursize) / $fsize"
         echo "$zenpercent"   # zenity progress bar percentage
         fcurMB=$(getMBsize "$fcursize")
         zenstat="${fbas}: ${zenpercent}% ($fcurMB of $fsizMB MB)"
      fi
      echo "# ${finfotxt}\n\n${errtxt}\n\n${zenstat}\n\n${strCancelText}"  # zenity progress text
      sleep 2
   fi
done | zenity --progress --auto-kill --title="grabdlvid" --text "Finding active video..."