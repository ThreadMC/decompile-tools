param(
    [Parameter(Mandatory = $true)]
    [string]$McVersion,
    [string]$WorkDir = "",
    [ValidateSet("mojang", "fabric")]
    [string]$MappingType = "mojang"
)

function Error-Exit {
    param ([string]$Message)
    Write-Error $Message
    exit 1
}

function Info {
    param ([string]$Message)
    Write-Host "[+] $Message"
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($WorkDir)) {
    $WorkDir = Join-Path $ScriptDir "..\minecraft-src-$McVersion"
}
$WorkDir = Resolve-Path -Path $WorkDir
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
Set-Location $WorkDir

$ToolsDir = Join-Path $ScriptDir "tools"
$SpecialSourceJar = Join-Path $ToolsDir "specialsource.jar"
$JoptSimpleJar = Join-Path $ToolsDir "jopt-simple.jar"
$AsmJar = Join-Path $ToolsDir "asm.jar"
$AsmCommonsJar = Join-Path $ToolsDir "asm-commons.jar"
$AsmUtilJar = Join-Path $ToolsDir "asm-util.jar"
$AsmTreeJar = Join-Path $ToolsDir "asm-tree.jar"
$GuavaJar = Join-Path $ToolsDir "guava.jar"
$VineflowerJar = Join-Path $ToolsDir "vineflower.jar"
$TRCJar = Join-Path $ToolsDir "trc.jar"

$RequiredFiles = @($VineflowerJar, $SpecialSourceJar, $JoptSimpleJar, $AsmJar, $AsmCommonsJar, $AsmUtilJar, $AsmTreeJar, $GuavaJar, $TRCJar)
foreach ($File in $RequiredFiles) {
    if (-not (Test-Path $File)) {
        Error-Exit "Required tool not found: $File"
    }
}

Info "Fetching version manifest..."
$ManifestUrl = "https://piston-meta.mojang.com/mc/game/version_manifest.json"
try {
    $Manifest = Invoke-WebRequest -Uri $ManifestUrl -UseBasicParsing | ConvertFrom-Json
} catch {
    Error-Exit "Failed to retrieve version manifest."
}

$VersionInfo = $Manifest.versions | Where-Object { $_.id -eq $McVersion }
if (-not $VersionInfo) {
    Error-Exit "Version $McVersion not found in manifest."
}

$VersionUrl = $VersionInfo.url
try {
    $VersionData = Invoke-WebRequest -Uri $VersionUrl -UseBasicParsing | ConvertFrom-Json
} catch {
    Error-Exit "Failed to retrieve version data."
}

$LibrariesDir = Join-Path $WorkDir "libraries"
foreach ($lib in $VersionData.libraries) {
    if ($lib.downloads -and $lib.downloads.artifact) {
        $artifact = $lib.downloads.artifact
        $libPath = Join-Path $LibrariesDir $artifact.path
        $libDir = Split-Path $libPath -Parent
        if (-not (Test-Path $libDir)) {
            New-Item -ItemType Directory -Path $libDir -Force | Out-Null
        }
        if (-not (Test-Path $libPath)) {
            Info "Downloading library: $($lib.name)"
            try {
                Invoke-WebRequest -Uri $artifact.url -OutFile $libPath -UseBasicParsing -ErrorAction Stop
            } catch {
                Write-Warning "Failed to download library $($lib.name) from $($artifact.url)"
            }
        }
    }
}

$ServerJarUrl = $VersionData.downloads.server.url
if (-not $ServerJarUrl) {
    Error-Exit "Server JAR URL not found for version $McVersion."
}

Info "Downloading server JAR..."
Invoke-WebRequest -Uri $ServerJarUrl -OutFile "server.jar" -UseBasicParsing

Add-Type -AssemblyName System.IO.Compression.FileSystem

Info "Checking for Bundler..."
$HasBundler = $false

if (-not (Test-Path "server.jar")) {
    Error-Exit "server.jar not found after download."
}

$ServerJarInfo = Get-Item "server.jar"
Write-Output "Inspecting server.jar at path: $($ServerJarInfo.FullName), size: $($ServerJarInfo.Length) bytes"

try {
    $Zip = [System.IO.Compression.ZipFile]::OpenRead($ServerJarInfo.FullName)
    foreach ($Entry in $Zip.Entries) {
        if ($Entry.FullName -eq "net/minecraft/bundler/Main.class") {
            $HasBundler = $true
            break
        }
    }
    $Zip.Dispose()
} catch {
    Error-Exit "Failed to inspect server.jar for Bundler. $_"
}

if ($HasBundler) {
    Info "Bundler detected. Unpacking..."
    & java -cp $ServerJarInfo.FullName net.minecraft.bundler.Main
    $ServerVersionJar = Get-ChildItem -Path "versions" -Recurse -Filter "*.jar" | Select-Object -First 1
    if (-not $ServerVersionJar) {
        Error-Exit "Unpacked server JAR not found."
    }
    $ServerJarPath = $ServerVersionJar.FullName
} else {
    Info "No Bundler detected. Using server.jar directly."
    $ServerJarPath = "server.jar"
}

$StrippedJarPath = Join-Path $WorkDir "server-stripped.jar"
Info "Stripping META-INF from server jar to avoid signature issues..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
    if (Test-Path $StrippedJarPath) { Remove-Item $StrippedJarPath -Force }
    $inStream = [System.IO.File]::OpenRead($ServerJarPath)
    $outStream = [System.IO.File]::OpenWrite($StrippedJarPath)
    $inZip = New-Object System.IO.Compression.ZipArchive($inStream, [System.IO.Compression.ZipArchiveMode]::Read)
    $outZip = New-Object System.IO.Compression.ZipArchive($outStream, [System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($entry in $inZip.Entries) {
        if ($entry.FullName -like "META-INF/*") { continue }
        $newEntry = $outZip.CreateEntry($entry.FullName)
        $entryStream = $entry.Open()
        $newEntryStream = $newEntry.Open()
        $entryStream.CopyTo($newEntryStream)
        $entryStream.Close()
        $newEntryStream.Close()
    }
    $inZip.Dispose()
    $outZip.Dispose()
    $inStream.Close()
    $outStream.Close()
    $ServerJarPath = $StrippedJarPath
} catch {
    Error-Exit "Failed to strip META-INF from server jar: $_"
}

if ($MappingType -eq "mojang") {
    $MappingsUrl = $VersionData.downloads.server_mappings.url
    if (-not $MappingsUrl) {
        Error-Exit "Mappings URL not found for version $McVersion."
    }

    Info "Downloading Mojang mappings..."
    Invoke-WebRequest -Uri $MappingsUrl -OutFile "mappings.txt" -UseBasicParsing

    Info "Applying Mojang mappings..."
    New-Item -ItemType Directory -Path "build" -Force | Out-Null
    $MappedJar = "build\server-mapped.jar"
    $Classpath = "$SpecialSourceJar;$JoptSimpleJar;$AsmJar;$AsmCommonsJar;$AsmUtilJar;$AsmTreeJar;$GuavaJar"
    & java -cp $Classpath net.md_5.specialsource.SpecialSource `
        -i $ServerJarPath `
        -m "mappings.txt" `
        -o $MappedJar
}
elseif ($MappingType -eq "fabric") {
    $FabricMetaUrl = "https://meta.fabricmc.net/v2/versions/intermediary/$McVersion"
    Info "Fetching Fabric intermediary metadata..."
    try {
        $FabricMeta = Invoke-WebRequest -Uri $FabricMetaUrl -UseBasicParsing | ConvertFrom-Json
    } catch {
        Error-Exit "Failed to retrieve Fabric intermediary metadata."
    }
    if (-not $FabricMeta -or $FabricMeta.Count -eq 0) {
        Error-Exit "No Fabric intermediary found for version $McVersion."
    }
    $MavenCoord = $FabricMeta[0].maven
    $parts = $MavenCoord -split ':'
    if ($parts.Length -ne 3) {
        Error-Exit "Invalid Maven coordinate for intermediary: $MavenCoord"
    }
    $group = $parts[0] -replace '\.', '/'
    $artifact = $parts[1]
    $version = $parts[2]
    # Try to download .tiny, fallback to extracting from .jar if not found
    $IntermediaryTinyUrl = "https://maven.fabricmc.net/$group/$artifact/$version/$artifact-$version.tiny"
    $IntermediaryJarUrl = "https://maven.fabricmc.net/$group/$artifact/$version/$artifact-$version.jar"
    $TinyPath = Join-Path $WorkDir "intermediary.tiny"
    $JarPath = Join-Path $WorkDir "intermediary.jar"
    $downloadedTiny = $false

    Info "Attempting to download Fabric intermediary mappings (.tiny): $IntermediaryTinyUrl"
    try {
        Invoke-WebRequest -Uri $IntermediaryTinyUrl -OutFile $TinyPath -UseBasicParsing -ErrorAction Stop
        $downloadedTiny = $true
    } catch {
        Info "Direct .tiny not found, downloading intermediary jar: $IntermediaryJarUrl"
        Invoke-WebRequest -Uri $IntermediaryJarUrl -OutFile $JarPath -UseBasicParsing
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $JarPath))
        $entry = $zip.Entries | Where-Object { $_.FullName -eq "mappings/mappings.tiny" }
        if (-not $entry) {
            $zip.Dispose()
            Error-Exit "mappings/mappings.tiny not found in intermediary jar."
        }
        $stream = $entry.Open()
        $fileStream = [System.IO.File]::OpenWrite($TinyPath)
        $stream.CopyTo($fileStream)
        $fileStream.Close()
        $stream.Close()
        $zip.Dispose()
        if (-not (Test-Path $TinyPath) -or ((Get-Item $TinyPath).Length -eq 0)) {
            Error-Exit "Failed to extract mappings.tiny from intermediary jar."
        }
        Remove-Item $JarPath -Force
    }

    Info "Applying Fabric intermediary mappings with tiny-remapper..."
    New-Item -ItemType Directory -Path "build" -Force | Out-Null
    $MappedJar = "build\server-mapped.jar"
    & java -jar $TRCJar `
        --input "$ServerJarPath" `
        --output "$MappedJar" `
        --mappings $TinyPath `
        --from "official" `
        --to "intermediary"

    $NamedMappingsUrl = "https://maven.fabricmc.net/net/fabricmc/yarn/$McVersion+build.1/yarn-$McVersion+build.1-tiny.gz"
    $NamedTinyGzPath = Join-Path $WorkDir "named.tiny.gz"
    $NamedTinyPath = Join-Path $WorkDir "named.tiny"
    try {
        Info "Downloading Fabric named mappings: $NamedMappingsUrl"
        Invoke-WebRequest -Uri $NamedMappingsUrl -OutFile $NamedTinyGzPath -UseBasicParsing -ErrorAction Stop
        # Decompress .gz to .tiny
        Info "Decompressing Fabric named mappings .gz..."
        $inStream = [System.IO.File]::OpenRead($NamedTinyGzPath)
        $outStream = [System.IO.File]::Create($NamedTinyPath)
        $gzipStream = New-Object System.IO.Compression.GzipStream($inStream, [System.IO.Compression.CompressionMode]::Decompress)
        $gzipStream.CopyTo($outStream)
        $gzipStream.Close()
        $inStream.Close()
        $outStream.Close()
        Remove-Item $NamedTinyGzPath -Force
        $NamedAvailable = $true
    } catch {
        Info "Fabric named mappings not found for this version, skipping named remap."
        $NamedAvailable = $false
    }
    if ($NamedAvailable) {
        $NamedMappedJar = "build\server-named.jar"
        Info "Applying Fabric named mappings with tiny-remapper..."
        & java -jar $TRCJar `
            --input "$MappedJar" `
            --output "$NamedMappedJar" `
            --mappings $NamedTinyPath `
            --from "intermediary" `
            --to "named"
        $MappedJar = $NamedMappedJar
    }
} else {
    Error-Exit "Unknown mapping type: $MappingType"
}

Info "Decompiling with VineFlower..."
New-Item -ItemType Directory -Path "sources" -Force | Out-Null
& java -jar $VineflowerJar $MappedJar --outputdir sources

Info "Decompilation complete. Sources located at: $(Resolve-Path 'sources')"