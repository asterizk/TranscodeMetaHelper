#!/bin/zsh

##############################
## Constants

BENTO_HOME=/Users/asterizk/Projects/zsh/Bento4-SDK-1-6-0-639.universal-apple-macosx/
METADATA_TEMP_FILE=${TMPDIR}metadata.txt

##############################
## Function definitions

function doWork() {
  echo "original file: [$1], new file [$2]"
  
  srcfilename=$1
  destfilename=$2
  
  # get the filename without the extension - https://www.markhneedham.com/blog/2020/08/24/unix-get-file-name-without-extension-from-file-path/
  basedestfilename=$(basename ${destfilename%.*})

  # get the destination file parent directory
  dirnamedestfilename=$(dirname ${destfilename})

  # construct a new 'fixed' file path
  fixeddestfilename=$dirnamedestfilename/$basedestfilename-fixed.mp4

  # construct a temporary 'gps' file path
  fixeddestfilenamegps=$dirnamedestfilename/$basedestfilename-fixed-gps.mp4

  # copy the date metadata from original to compressed file - https://superuser.com/a/523696/115463
  ffmpeg -i "${srcfilename}" -i "${destfilename}" -map 1 -map_metadata 0 -c copy "${fixeddestfilename}"

  # protect against fatal error
  if [ $? != 0 ]; then echo exiting; exit 1; fi

  # extract the location and other iPhone metadata and put into temp file - https://github.com/HandBrake/HandBrake/issues/345#issuecomment-562992161
  ${BENTO_HOME}/bin/mp4extract moov/meta "${srcfilename}" ${METADATA_TEMP_FILE}
  if [ $? = 0 ]; then
    # movie comes from iPhone; write metadata from temp file to compressed file
    ${BENTO_HOME}/bin/mp4edit --insert moov:${METADATA_TEMP_FILE} "${fixeddestfilename}" "${fixeddestfilenamegps}"

    # cleanup
    rm "${fixeddestfilename}"
    mv "${fixeddestfilenamegps}" "${fixeddestfilename}"
    rm "${destfilename}"
    rm ${METADATA_TEMP_FILE}
  else
    # movie does not come from iPhone; nothing to copy; just finish up instead.
    # cleanup
    rm "${destfilename}"
  fi
}

##############################
## Main execution

## Figure out the process id of the handbrake process & wait until we start transcoding
handbrakeMainAppPid=$(pgrep -o HandBrake)
while [[ ! $( lsof -F 0n -p ${handbrakeMainAppPid} | tr '\0' '|' | grep EncodeLogs ) && $? == 1 ]]; do
  sleep .1
done

echo "Waiting for transcode to finish."

## At this point, we know the Handbrake transcode has begun. A future improvement might be to look at
## the encode log files for this information, rather than trying to derive it realtime, but this is fine for now. For now
## we just need to remember to start this tool prior to starting Handbrake queue processing.

## Monitor Handbrake & store source & destination paths of all files transcoded into 'transcodes' zsh associative array
unset transcodes && declare -A transcodes
handbrakeXpcServicePid=$(pgrep HandBrakeXPCService);
doneTranscodes=0
while [[ $doneTranscodes != 1 ]]; do
  movname=$( lsof -F 0n -p ${handbrakeXpcServicePid} | tr '\0' '|' | grep \.mov | cut -d '|' -f2 | cut -b2-300 )
  mp4name=$( lsof -F 0n -p ${handbrakeXpcServicePid} | tr '\0' '|' | grep \.mp4 | cut -d '|' -f2 | cut -b2-300 )
  if [[ $mp4name != "" && $movname != "" ]]; then transcodes[$movname]=$mp4name; fi;
  if [[ ! $( lsof -F 0n -p ${handbrakeMainAppPid} | tr '\0' '|' | grep EncodeLogs ) && $? == 1 ]]; then
    doneTranscodes=1
  fi
  sleep .25
done

# # Uncomment block below and comment above to line under "Main execution" if you need to manually fix files one-at-a-time
# unset transcodes && declare -A transcodes
# 
# movname="/Volumes/Speedy/Pictures/Photos Library.photoslibrary/private/com.apple.Photos/ExternalEditSessions/6E929BB4-1061-4069-8DED-EAC24A8A10ED/6E929BB4-1061-4069-8DED-EAC24A8A10ED.mov"
# mp4name="/Users/asterizk/Library/Containers/fr.handbrake.HandBrake/Data/Movies/6E929BB4-1061-4069-8DED-EAC24A8A10ED.mp4"
# transcodes[$movname]=$mp4name

echo "Transcode finished."

## Process each transcoded file
for key value in ${(kv)transcodes}; do
  echo "============================================================================"
  echo "[$key] -> [$value]"
  doWork $key $value
done

echo "All done!"

exit 0