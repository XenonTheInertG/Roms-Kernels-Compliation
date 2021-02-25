#!/bin/bash

# build_rom.sh usage
#
# command example: ./build-rom.sh angler sync clean nolog sd norelease on
#
# Parameter 1: The device tree: angler
# Parameter 2: Repo sync or don't sync the source: sync | nosync
# Parameter 3: Make a clean build: clean (to run a "make clobber") | noclean (to run a "make installclean") (hint: installclean is usually enough to build without errors)
# Parameter 4: Save a txt log in the root repo folder: log | nolog
# Parameter 5: Upload ROM to local server to be synced with SD card: sd | nosd
# Parameter 6: Upload ROM to ABC website: release | norelease
# Parameter 7: Shutdown the system after the build is completed: on (to keep it on) | off (to switch it off after the build)

# ---------
# Functions
# ---------

# Prints a formatted header; used for outlining what the script is doing to the user
function echoText() {
   RED="\033[01;31m"
   RST="\033[0m"

   echo -e ${RED}
   echo -e "====$( for i in $( seq ${#1} ); do echo -e "=\c"; done )===="
   echo -e "==  ${1}  =="
   echo -e "====$( for i in $( seq ${#1} ); do echo -e "=\c"; done )===="
   echo -e ${RST}
}

# Creates a new line
function newLine() {
   echo -e ""
}

# ---------
# Variables
# ---------

# THREAD: Number of available threads on computer
cpu=$(nproc); THREAD=-j$[$cpu+1]

DEVICE="$1"
SYNC="$2"
CLEAN="$3"
LOG="$4"
SD=$5
RELEASE="$6"
SHUTDOWN="$7"

ROOT_PATH=$PWD
BUILD_PATH="$ROOT_PATH/out/target/product/$DEVICE"
CCACHE_PATH="/media/kantjer/fa836dce-7ba3-44e1-8999-83d924ad758e/.ccache"
TODAY="$(date +%y%m%d)"
GAPPS_AFH_ID="674106145207491329"

# Parameters to be configured manually or by using the "x-settings.sh" script
PO_APP_TOKEN=""
PO_USER_KEY=""
ABC_LOGIN=""
ABC_PASS=""
ABC_URL=""
ABC_FOLDER=""
SERVER_URL=""
SERVER_LOGIN=""
SERVER_PASS=""
SERVER_PATH=""
STACK_LOGIN=""
STACK_PASS=""
STACK_PATH=""
LAST_TEST_ZIP=""
LAST_TEST_MD5SUM=""
LAST_UPLOAD_DATE=""

# overwrite the above settings with custom file, if it exists
if [ -f $ROOT_PATH/x-settings.sh ]; then
  . $ROOT_PATH/x-settings.sh
fi

# Clear the terminal
clear

# ---------
# Start building
# ---------

# Repo sync
SYNC_LOG="sync.log"

if [ "$SYNC" == "sync" ]; then

   # Reset vendor/nexus
   cd ${ROOT_PATH}/vendor/nexus
   git reset --hard HEAD >/dev/null 2>&1
   cd ${ROOT_PATH}

   if [ -f $ROOT_PATH/$SYNC_LOG ]; then
   rm $ROOT_PATH/$SYNC_LOG
   fi

   echoText "Syncing latest sources"; newLine
   repo sync ${THREAD} -c --force-sync 2> >(tee -a $ROOT_PATH/$SYNC_LOG >&2)

   if grep -E "^error|^fatal" $ROOT_PATH/$SYNC_LOG
   then
   echoText "error: Exited sync due to fetch errors, please check $SYNC_LOG and correct the issue"; newLine

   # Send repo sync error using pushover
   echoText "Sending repo sync error to phone"

curl -s \
   --form-string "token=${PO_APP_TOKEN}" \
   --form-string "user=${PO_USER_KEY}" \
   --form-string "message=Exit repo sync due to fetch error(s), please check $SYNC_LOG" \
   https://api.pushover.net/1/messages.json &> /dev/null; newLine
   echo -e ${RED} "Done...."${RST}; newLine
   return
   else
   echoText "Repo sync successful"
   sleep 1
   fi
fi

# Setup environment
echoText "Setting up build environment"
. build/envsetup.sh

# Setup ccache
export USE_CCACHE=1
export CCACHE_DIR=$CCACHE_PATH
/usr/local/bin/ccache -M 25G

# Set the device
echoText "Setting the device..."
breakfast "$DEVICE-userdebug"

# Clean out folder
if [ "$CLEAN" == "clean" ]; then
  echoText "Cleaning up the OUT folder with make clean"
  make clean;
else
  echoText "No make clean so lets do make installclean"

  make installclean;

# Set the kernel version to 1
  rm -rf .version
  touch .version
  echo 0 >> .version
fi

# Start tracking time
echoText "SCRIPT STARTING AT $( TZ=CET date +"%d-%m-%Y"\ %T )"

START=$( TZ=CET date +%s )

# Set changelog period
if [ -z "${LAST_UPLOAD_DATE}" ]; then
   echoText "Last upload date not found, use default changelog period"
else
   CHANGELOG_PERIOD="$(( ($(date --date=${TODAY} +%s) - $(date --date=${LAST_UPLOAD_DATE} +%s) )/(60*60*24)+1 ))"
   sed -i -e "s/for i in \$(seq 10)/for i in \$(seq ${CHANGELOG_PERIOD})/g" ${ROOT_PATH}/vendor/nexus/tools/changelog.sh
   echoText "Changelog period set to ${CHANGELOG_PERIOD} day(s)"
fi

# Start compilation with or without log
if [ "$LOG" == "log" ]; then
   echoText "Compiling for $DEVICE and saving a build log file"
   mka bacon 2>&1 | tee build.log;
else
   echoText "Compiling for $DEVICE without saving a build log file"
   mka bacon;
fi

# If the above was successful
if [ `ls $BUILD_PATH/ABC_ROM_*.zip 2>/dev/null | wc -l` != "0" ]; then
   BUILD_RESULT="Build successful"

# Backup current build script
gist -p -u -d "ROM build script" build_magisk.sh <${ROOT_PATH}/build-rom.sh >/dev/null 2>&1

# Move the device ROM.zip and ROM.zip.md5sum to root (and before doing this, remove old device builds but not the last one of them, adding an OLD_tag to it)
if [ `ls $ROOT_PATH/OLD_ABC_ROM_$DEVICE-*.zip 2>/dev/null | wc -l` != "0" ]; then
  rm OLD_ABC_ROM_$DEVICE-*.zip
fi

if [ `ls $ROOT_PATH/OLD_ABC_ROM_$DEVICE-*.zip.md5 2>/dev/null | wc -l` != "0" ]; then
  rm OLD_ABC_ROM_$DEVICE-*.zip.md5
fi

if [ `ls $ROOT_PATH/ABC_ROM_$DEVICE-*.zip 2>/dev/null | wc -l` != "0" ]; then
  for file in ABC_ROM_$DEVICE-*.zip
  do
    mv -f "${file}" "${file/ABC_ROM/OLD_ABC_ROM}"
  done
fi

if [ `ls $ROOT_PATH/ABC_ROM_$DEVICE-*.zip.md5 2>/dev/null | wc -l` != "0" ]; then
  for file in ABC_ROM_$DEVICE-*.zip.md5
  do
    mv -f "${file}" "${file/ABC_ROM/OLD_ABC_ROM}"
  done
fi

  if [ "$RELEASE" == "release" ]; then

  if [ `ls $ROOT_PATH/OLD_Changelog_curr.txt 2>/dev/null | wc -l` != "0" ]; then
    rm OLD_Changelog_curr.txt
  fi

  if [ `ls $ROOT_PATH/Changelog_curr.txt 2>/dev/null | wc -l` != "0" ]; then
    for file in Changelog_curr.txt
    do
      mv -f "${file}" "${file/Changelog/OLD_Changelog}"
    done
  fi
fi

mv $BUILD_PATH/ABC_ROM_*.zip $ROOT_PATH
mv $BUILD_PATH/ABC_ROM_*.zip.md5sum $ROOT_PATH
rm $BUILD_PATH/$DEVICE-ota-eng.*.zip

# remove file path in md5sum file 
MD5=$(cat "$ROOTPATH"ABC_ROM_*.zip.md5sum | awk '{print $1}')
FILE_NAME=$(basename "$ROOTPATH"ABC_ROM_*.zip)
echo "$MD5 $FILE_NAME" > $(ls "$ROOTPATH"ABC_ROM_*.zip.md5sum)

# Rename md5sum to md5
for file in ABC_ROM*.zip.md5sum; do
  mv "$file" "$(basename "$file" .zip.md5sum).zip.md5"
done

sleep 1

# If the build failed
   else
   BUILD_RESULT="Build failed"
fi

# Stop tracking time
   END=$( TZ=CET date +%s )
   echoText "${BUILD_RESULT}"; newLine

   # Print the zip location and its size if the script was successful
   if [[ ${SUCCESS} = true ]]; then
      echo -e ${RED}"FILE LOCATION: $( ls ${ZIP_MOVE}/${ZIP_FORMAT} )"
      echo -e "SIZE: $( du -h ${ZIP_MOVE}/${ZIP_FORMAT} | awk '{print $1}'  )"${RST}
   fi

   # Print the time the script finished and how long the script ran for regardless of success
   echo -e ${RED}"TIME FINISHED: $( TZ=CET date +%D\ %T | awk '{print toupper($0)}' )"
   echo -e ${RED}"DURATION: $( echo $((${END}-${START})) | awk '{print int($1/60)" MINUTES AND "int($1%60)" SECONDS"}' )"${RST}; newLine

# set ROM and md5sum in preparation of upload
if [ "$SD" == "sd" ] || [ "$RELEASE" == "release" ]; then
  ROM_FILE=$(basename "$ROOTPATH"ABC_ROM_*.zip)
  MD5SUM_FILE=$(basename "$ROOTPATH"ABC_ROM_*.zip.md5)
fi

# Upload build to server
if [ "$BUILD_RESULT" == "Build successful" ]; then

# Clear last test build
  if [ -n "$LAST_TEST_ZIP" ] || [ -n "$LAST_TEST_MD5SUM" ]; then
    curl -s -u $STACK_LOGIN:$STACK_PASS -X DELETE $STACK_PATH/$LAST_TEST_ZIP
    curl -s -u $STACK_LOGIN:$STACK_PASS -X DELETE $STACK_PATH/$LAST_TEST_MD5SUM
  fi

  if [ "$SD" == "sd" ]; then
    echoText "Uploading $ROM_FILE to local server"; newLine

lftp<<INPUT_END
set ftp:ssl-allow no
set net:timeout 30
open ftp://$SERVER_URL
user $SERVER_LOGIN $SERVER_PASS
cd $SERVER_PATH
put $ROM_FILE
put $MD5SUM_FILE
bye
INPUT_END

    echo -e ${RED} "Done...."${RST}; newLine
  fi

# Upload build
  if [ "$RELEASE" == "release" ]; then

    # ABC release template
    echoText "Prepare ABC release template"; newLine

CHANGELOG="${ROOT_PATH}/Changelog.txt"
CHANGELOG_CURR="${ROOT_PATH}/Changelog_curr.txt"
CHANGELOG_ABC="${ROOT_PATH}/ABC-template.txt"
CHANGELOG_ABC_PREV="${ROOT_PATH}/ABC-template_prev.txt"

if [[ -f "${CHANGELOG_CURR}" ]]; then
    mv -f ${CHANGELOG_CURR} ${CHANGELOG_ABC_PREV}
elif [[ ! -f "${CHANGELOG_ABC_PREV}" ]]; then   
    echo "dummy file" >> ${CHANGELOG_ABC_PREV}
fi

cp ${CHANGELOG} ${CHANGELOG_CURR}

    sed -i -e 's/* /• /g' ${CHANGELOG_CURR}
    sed -i -e 's/^[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]/<strong>&<\/strong>/' ${CHANGELOG_CURR}
    grep -F -v -x -f ${CHANGELOG_ABC_PREV} ${CHANGELOG_CURR} > $CHANGELOG_ABC

    if [ -s ${CHANGELOG_ABC} ]; then
        sed -i -e 's/^.\{7\} /<span style="margin-left:20px;">- /g' ${CHANGELOG_ABC}
        sed -i '/^<span style=/ s/$/<\/span>/' ${CHANGELOG_ABC}
        sed -i '/^=======================/d' ${CHANGELOG_ABC}
        sed -i -e "s,/\+$,," -e "s,^/\+,," ${CHANGELOG_ABC}
        sed -i -n '/^[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]/{x;d;};1h;1!{x;p;};${x;p;}' ${CHANGELOG_ABC}
        sed -i '/^[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]/ {$!N;/\n.*[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]/!P;D}' ${CHANGELOG_ABC}
        sed -i -e '/^[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]/i\\' -e '/sad/i\\' ${CHANGELOG_ABC}
        sed -i 's/^<strong>/\n&/g' ${CHANGELOG_ABC}
        sed -i '/&<\/strong>/a\\' ${CHANGELOG_ABC}
        sed -i '1{/^$/d}' ${CHANGELOG_ABC}
    else
        echo "Nothing new" > ${CHANGELOG_ABC}
    fi

    sed -i '1 i\<strong>Changelog</strong>\n' ${CHANGELOG_ABC}
    sed -i '1 i\\&nbsp;\n' ${CHANGELOG_ABC}
    sed -i "1 i\<a href="\"http://kantjer.com/wp-content/uploads/$(date +"%Y")/$(date +"%m")/${MD5SUM_FILE}\"">${MD5SUM_FILE}<\/a>\n" ${CHANGELOG_ABC}
    sed -i "1 i\<a href="\"http://kantjer.com/wp-content/uploads/$(date +"%Y")/$(date +"%m")/${ROM_FILE}\"">${ROM_FILE}<\/a>\n" ${CHANGELOG_ABC}
    sed -i '1 i\<strong>Download</strong>\n\n\n' ${CHANGELOG_ABC}
    sed -i '1 i\Nexus 6P (Angler)' ${CHANGELOG_ABC}
    sed -i "1 i\ABC ROM - $(date +"%B %d, %Y")" ${CHANGELOG_ABC}
    sed -i '${/^$/d;}' ${CHANGELOG_ABC}; sed -i '${/^<strong>/d;}' ${CHANGELOG_ABC}; sed -i '${/^$/d;}' ${CHANGELOG_ABC}
    rm -f ${CHANGELOG_ABC_PREV}

    # Backup ABC-ROM changelog
    gist -p -u -d "ABC_ROM changelog" ABC-changelog.txt <${ROOT_PATH}/Changelog_curr.txt >/dev/null 2>&1
    # Backup ABC relase template
    gist -p -u -d "XDA relase template" ABC-template.txt <${ROOT_PATH}/ABC-template.txt >/dev/null 2>&1

    # XDA release template
    echoText "Prepare XDA release template"; newLine

    XDA_TEMPLATE="$ROOT_PATH/XDA-template.txt"
    if [ -f $XDA_TEMPLATE ]; then
       sed -i -e "s/ABCrom_angler-8.1.0-20[0-9][0-9][0-9][0-9][0-9][0-9]/ABCrom_angler_new-8.1.0-$(date +%Y%m%d)/g" ${XDA_TEMPLATE}
       
       # Set security patch month if day of the month is greater than or equal to 5
       if (( $(date +%d) >= 5 )); then
          PREV_MONTH="$(date --date="$(date +%Y-%m-15) -1 month" +'%B %Y')"
          CURR_MONTH="$(date +"%B %Y")"
          sed -i -e "s/${PREV_MONTH} security patch/${CURR_MONTH} security patch/g" ${XDA_TEMPLATE}
          sed -i "/Download and Changelog/c\[URL="\"https://kantjer.com/$(date +"%Y")/$(date +"%m")/$(date +"%d")/abc-rom-$(date +"%b")-$(date +"%m")-$(date +"%Y")/\""]Download and Changelog[/URL]" ${XDA_TEMPLATE}
          sed -i "/Recommended GApps/c\[URL="\"https://androidfilehost.com/?fid=${GAPPS_AFH_ID}\""]Recommended GApps[/URL]" ${XDA_TEMPLATE}
       fi
    fi
    
    # Backup XDA relase template
    gist -p -u -d "XDA relase template" XDA-template.txt <${ROOT_PATH}/XDA-template.txt >/dev/null 2>&1

    echoText "Uploading ${ROM_FILE}/${MD5SUM_FILE} to ABC website"; newLine

lftp<<INPUT_END
set net:timeout 30
open sftp://$ABC_URL
user $ABC_LOGIN $ABC_PASS
cd $ABC_FOLDER
put $ROM_FILE
put $MD5SUM_FILE
bye
INPUT_END

    # Clear last test build variable
    sed -i "s/^\LAST_TEST_ZIP=.*/LAST_TEST_ZIP=\"\"/" $ROOT_PATH/x-settings.sh
    sed -i "s/^\LAST_TEST_MD5SUM=.*/LAST_TEST_MD5SUM=\"\"/" $ROOT_PATH/x-settings.sh

    # set last upload date variable
    sed -i "s/^\LAST_UPLOAD_DATE=.*/LAST_UPLOAD_DATE=\"$TODAY\"/" $ROOT_PATH/x-settings.sh  

    echo -e ${RED} "Done...."${RST}; newLine
  else
    # Upload last testbuild
    if [ "$SD" == "sd" ] || [ "$RELEASE" == "release" ]; then
      echoText "Uploading ${ROM_FILE}/${MD5SUM_FILE} to Stack cloud"; newLine
      curl -u $STACK_LOGIN:$STACK_PASS -o /dev/stdout -T $ROM_FILE $STACK_PATH/$ROM_FILE; newLine; newLine
      curl -u $STACK_LOGIN:$STACK_PASS -o /dev/stdout -T $MD5SUM_FILE $STACK_PATH/$MD5SUM_FILE; newLine; newLine
#     curl -u $STACK_LOGIN:$STACK_PASS -o /dev/stdout -T $CHANGELOG $STACK_PATH/$CHANGELOG; newLine; newLine
      echo -e ${RED} "Done...."${RST}; newLine

      # Set last test build variable
      sed -i "s/^\LAST_TEST_ZIP=.*/LAST_TEST_ZIP=\"$ROM_FILE\"/" $ROOT_PATH/x-settings.sh
      sed -i "s/^\LAST_TEST_MD5SUM=.*/LAST_TEST_MD5SUM=\"$MD5SUM_FILE\"/" $ROOT_PATH/x-settings.sh
    fi
  fi
fi

# Send build result using pushover
echoText "Sending build result to phone"

BUILDTIME="Build time: $(echo $((${END}-${START})) | awk '{print int($1/60)" minutes and "int($1%60)" seconds"}')"

curl -s \
  --form-string "token=${PO_APP_TOKEN}" \
  --form-string "user=${PO_USER_KEY}" \
  --form-string "message=
$BUILD_RESULT
$BUILDTIME" \
  https://api.pushover.net/1/messages.json &> /dev/null; newLine
  echo -e ${RED} "Done...."${RST}; newLine

#kill java
pkill java

# Shutdown the system if required by the user
if [ "$SHUTDOWN" == "off" ]; then
  sleep 5
# qdbus org.kde.ksmserver /KSMServer logout 0 2 2; newLine
  sudo poweroff; newline
fi
