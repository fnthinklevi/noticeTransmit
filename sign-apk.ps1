$apkFile = "build\app\outputs\flutter-apk\app-release.apk"
$alignedFile = "build\app\outputs\flutter-apk\app-release-aligned.apk"
$signedFile = "build\app\outputs\flutter-apk\notice1.5.33.apk"

$keystoreFile = $env:KEYSTORE_FILE
$keystorePassword = $env:KEYSTORE_PASSWORD
$keyAlias = $env:KEY_ALIAS
$keyPassword = $env:KEY_PASSWORD

if (-not $keystoreFile -or -not $keystorePassword -or -not $keyAlias -or -not $keyPassword) {
    $keyPropertiesFile = "android\key.properties"
    if (Test-Path $keyPropertiesFile) {
        Write-Host "Reading signing config from $keyPropertiesFile"
        Get-Content $keyPropertiesFile | ForEach-Object {
            if ($_ -match 'storeFile=(.*)') { $keystoreFile = $matches[1] }
            if ($_ -match 'storePassword=(.*)') { $keystorePassword = $matches[1] }
            if ($_ -match 'keyAlias=(.*)') { $keyAlias = $matches[1] }
            if ($_ -match 'keyPassword=(.*)') { $keyPassword = $matches[1] }
        }
    }
}

if (-not $keystoreFile -or -not $keystorePassword -or -not $keyAlias -or -not $keyPassword) {
    Write-Host "ERROR: Signing config not found!"
    exit 1
}

if (-not (Test-Path $apkFile)) {
    Write-Host "ERROR: APK file not found: $apkFile"
    exit 1
}

$buildToolsVersions = Get-ChildItem "$env:USERPROFILE\Android\sdk\build-tools" -Directory -ErrorAction SilentlyContinue
if (-not $buildToolsVersions) {
    $buildToolsVersions = Get-ChildItem "D:\fnthinklevi\Android\sdk\build-tools" -Directory -ErrorAction SilentlyContinue
}

Write-Host "=== Step 1/3: Aligning APK ==="
if ($buildToolsVersions) {
    $latestVersion = $buildToolsVersions | Sort-Object Name -Descending | Select-Object -First 1
    $zipalign = "$($latestVersion.FullName)\zipalign.exe"
    if (Test-Path $zipalign) {
        Write-Host "Using zipalign: $zipalign"
        & $zipalign -f 4 $apkFile $alignedFile
    } else {
        Write-Host "WARNING: zipalign not found, using original APK"
        Copy-Item $apkFile $alignedFile -Force
    }
} else {
    Write-Host "WARNING: build-tools not found, using original APK"
    Copy-Item $apkFile $alignedFile -Force
}

Write-Host "`n=== Step 2/3: Signing APK ==="
Write-Host "Keystore: $keystoreFile"
Write-Host "Alias: $keyAlias"
jarsigner -keystore $keystoreFile -storepass $keystorePassword -keypass $keyPassword -signedjar $signedFile $alignedFile $keyAlias

if (-not (Test-Path $signedFile)) {
    Write-Host "ERROR: Signing failed!"
    exit 1
}

Write-Host "`n=== Step 3/3: Verifying signature ==="
jarsigner -verify $signedFile

Remove-Item $apkFile -ErrorAction SilentlyContinue
Remove-Item $alignedFile -ErrorAction SilentlyContinue

$fileInfo = Get-Item $signedFile
Write-Host "`n✅ APK signed successfully!"
Write-Host "File: $signedFile"
Write-Host "Size: $($fileInfo.Length) bytes"
