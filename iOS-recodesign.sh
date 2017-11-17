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
teamName=$(/usr/libexec/PlistBuddy -c 'Print :TeamName' /dev/stdin <<< $(security cms -D -i "${newMobileProfile}"))
codeSignIdentify="iPhone Distribution: $teamName"
echo "codeSignIdentify=${codeSignIdentify}"
/usr/libexec/PlistBuddy -x -c "print :Entitlements" /dev/stdin <<< $(security cms -D -i ${newMobileProfile}) > new_${packName}_ENTITLEMENTS.entitlements
codesign -d --entitlements :- ${packName}/Payload/${applicationName} > temp_${packName}_ENTITLEMENTS.plist
python $currentDir/update-entitlements-data.py temp_${packName}_ENTITLEMENTS.plist new_${packName}_ENTITLEMENTS.entitlements
rm -r ${packName}/Payload/${applicationName}/_CodeSignature
/usr/libexec/PlistBuddy -c "Set CFBundleIdentifier ${bundleid}" ${packName}/Payload/${applicationName}/Info.plist 
cp ${newMobileProfile} ${packName}/Payload/${applicationName}/embedded.mobileprovision
/usr/bin/codesign -f -s "${codeSignIdentify}" --identifier "${bundleid}" --entitlements "new_${packName}_ENTITLEMENTS.entitlements" "${packName}/Payload/${applicationName}"
pushd $packName &&  zip -qr ${newIpaName}.ipa Payload
popd
mv ${packName}/${newIpaName}.ipa $resultDir 
