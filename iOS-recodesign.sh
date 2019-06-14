#!/usr/bin/env bash

set -o errexit

# 外部参数
downurl=$BUILD_VERSION_PATH
bundleid=$BUNDLE_IDENTIFIER
[[ -z "${PACK_TYPE}" ]] && PACK_TYPE=resign
# 参数初始化
currentDir=$(cd $(dirname $0) && pwd -P)
if [ -z "$WORKSPACE" ];then
     workDir=$currentDir/$bundleid
     [[ -d "$workDir" ]] && rm -rdf $workDir
     mkdir $workDir && cd $workDir
else
     workDir=$WORKSPACE
fi
resultDir=$workDir/artifacts
#newMobileProfile=${HOME}/ProvisioningProfiles/InHouse_${bundleid}.mobileprovision
newMobileProfile=$(find ${HOME}/ProvisioningProfiles -name "*_${bundleid}.mobileprovision")

# 数据初始化
echo "=== ini data ==="
BUILD_DATE="`date +%Y%m%d`"
readonly delimiter='/'
array=(${BUILD_VERSION_PATH//${delimiter}/ })
pdtname=${array[5]}
buildobj=${array[6]}
buildversion=${array[7]}
ipaname=${array[8]}
packName=${ipaname%.*}
newIpaName=${packName}-${bundleid}-${PACK_TYPE}
echo "INFO: $pdtname、$buildobj、$buildversion、$ipaname"
echo BUILD_DATE=$BUILD_DATE > ${JOB_NAME}.properties
echo PDT_NAME=$pdtname>> ${JOB_NAME}.properties
echo BUILD_OBJ=$buildobj>> ${JOB_NAME}.properties
echo BUILD_VERSION=$buildversion>> ${JOB_NAME}.properties
echo IPA_NAME=$ipaname>> ${JOB_NAME}.properties

# 重签名
[[ -d "$resultDir" ]] && rm -rdf "$resultDir"    
mkdir "$resultDir"  
echo [INFO] $downurl
curl -O -k ${downurl} || { echo "curl failed"; exit 1; }
[[ -d "$packName" ]] && rm -rdf $packName
unzip -q $ipaname -d $packName
applicationName=$(ls -1 "$packName/Payload" | grep ".*\.app$" | head -n1)
ipa_swift_frameworks=`find ${packName}/Payload/${applicationName}/Frameworks/ -name "libswift*" 2> /dev/null || true`
if [[ -n ${ipa_swift_frameworks} ]]; then
    for LINE in ${ipa_swift_frameworks}
    do
        echo "rm $LINE"
        rm $LINE
    done
fi
teamName=$(/usr/libexec/PlistBuddy -c 'Print :TeamName' /dev/stdin <<< $(security cms -D -i "${newMobileProfile}"))
codeSignIdentify="iPhone Distribution: $teamName"
echo "codeSignIdentify=${codeSignIdentify}"
/usr/libexec/PlistBuddy -x -c "print :Entitlements" /dev/stdin <<< $(security cms -D -i ${newMobileProfile}) > new_${packName}_ENTITLEMENTS.entitlements
codesign -d --entitlements :- ${packName}/Payload/${applicationName} > temp_${packName}_ENTITLEMENTS.plist
python $currentDir/update-entitlements-data.py temp_${packName}_ENTITLEMENTS.plist new_${packName}_ENTITLEMENTS.entitlements
rm -r ${packName}/Payload/${applicationName}/_CodeSignature
/usr/libexec/PlistBuddy -c "Set CFBundleIdentifier ${bundleid}" ${packName}/Payload/${applicationName}/Info.plist 
cp ${newMobileProfile} ${packName}/Payload/${applicationName}/embedded.mobileprovision
ipa_plugins=`find ${packName}/Payload/${applicationName}/PlugIns -name "notificationService.appex" 2> /dev/null || true`
if [[ -n ${ipa_plugins} ]]; then
    for LINE in ${ipa_plugins}
    do
        identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' $LINE/Info.plist)
        pluginName=notificationService
        new_identifier="${bundleid}.${pluginName}"
        echo "new_identifier=$new_identifier"
        pluginMobileProfile=$(find ${HOME}/ProvisioningProfiles -name "*_${new_identifier}.mobileprovision")
        #pluginTeamName=$(/usr/libexec/PlistBuddy -c 'Print :TeamName' /dev/stdin <<< $(security cms -D -i "${pluginMobileProfile}"))
        #plugincodeSignIdentify="iPhone Distribution: $pluginTeamName"
        #echo "plugincodeSignIdentify=${plugincodeSignIdentify}"
        /usr/libexec/PlistBuddy -x -c "print :Entitlements" /dev/stdin <<< $(security cms -D -i ${pluginMobileProfile}) > new_${pluginName}_ENTITLEMENTS.entitlements
        codesign -d --entitlements :- ${LINE} > temp_${pluginName}_ENTITLEMENTS.plist
        echo "rm $LINE/_CodeSignature"
        rm -r $LINE/_CodeSignature
        /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier ${new_identifier}" $LINE/Info.plist
        cp ${pluginMobileProfile} ${LINE}/embedded.mobileprovision    
        /usr/bin/codesign -f -s "${codeSignIdentify}" --identifier "${new_identifier}" --entitlements "new_${pluginName}_ENTITLEMENTS.entitlements" "${LINE}"    
    done
fi
ipa_frameworks=`find ${packName}/Payload/${applicationName}/Frameworks/ -name "*.framework" 2> /dev/null || true`
if [[ -n ${ipa_frameworks} ]]; then
    for LINE in ${ipa_frameworks}
    do
        echo "rm $LINE/_CodeSignature"
        rm -r $LINE/_CodeSignature
        identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' $LINE/Info.plist)
        /usr/bin/codesign -f -s "${codeSignIdentify}" --identifier "${identifier}" --entitlements "new_${packName}_ENTITLEMENTS.entitlements" "${LINE}"    
    done
fi
/usr/bin/codesign -f -s "${codeSignIdentify}" --identifier "${bundleid}" --entitlements "new_${packName}_ENTITLEMENTS.entitlements" "${packName}/Payload/${applicationName}"
pushd $packName &&  zip -qr ${newIpaName}.ipa Payload
popd
mv ${packName}/${newIpaName}.ipa $resultDir 
