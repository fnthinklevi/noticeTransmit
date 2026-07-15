$apkFile = "build\app\outputs\flutter-apk\app-release.apk"
$signedFile = "build\app\outputs\flutter-apk\app-release-signed.apk"
$finalFile = "build\app\outputs\flutter-apk\notice1.5.33.apk"

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
    Write-Host "ERROR: Signing config not found! Set environment variables or create android/key.properties"
    exit 1
}

if (Test-Path $apkFile) {
    Write-Host "Signing APK with keystore: $keystoreFile"
    jarsigner -keystore $keystoreFile -storepass $keystorePassword -keypass $keyPassword -signedjar $signedFile $apkFile $keyAlias
    
    if (Test-Path $signedFile) {
        Write-Host "Verifying signature..."
        jarsigner -verify $signedFile
        
        Move-Item $signedFile $finalFile -Force
        Remove-Item $apkFile
        
        $fileInfo = Get-Item $finalFile
        Write-Host "`nAPK signed successfully!"
        Write-Host "File: $finalFile"
        Write-Host "Size: $($fileInfo.Length) bytes"
    } else {
        Write-Host "Signing failed!"
        exit 1
    }
} else {
    Write-Host "APK file not found: $apkFile"
    exit 1
}
