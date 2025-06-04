param(
    [Parameter(Mandatory = $true)]
    [string]$McVersion,
    [string]$WorkDir = ""
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
$TRCJar = Join-Path $ToolsDir "trc.jar"
$JoptSimpleJar = Join-Path $ToolsDir "jopt-simple.jar"
$AsmJar = Join-Path $ToolsDir "asm.jar"
$AsmCommonsJar = Join-Path $ToolsDir "asm-commons.jar"
$AsmUtilJar = Join-Path $ToolsDir "asm-util.jar"
$AsmTreeJar = Join-Path $ToolsDir "asm-tree.jar"
$GuavaJar = Join-Path $ToolsDir "guava.jar"
$VineflowerJar = Join-Path $ToolsDir "vineflower.jar"

$RequiredFiles = @($VineflowerJar, $TRCJar, $JoptSimpleJar, $AsmJar, $AsmCommonsJar, $AsmUtilJar, $AsmTreeJar, $GuavaJar)
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

$MappingsUrl = $VersionData.downloads.server_mappings.url
if (-not $MappingsUrl) {
    Error-Exit "Mappings URL not found for version $McVersion."
}

Info "Downloading mappings..."
Invoke-WebRequest -Uri $MappingsUrl -OutFile "mappings.tiny" -UseBasicParsing

$Mappings = Get-Content "mappings.tiny"
if ($Mappings.Count -eq 0) {
    Set-Content "mappings.tiny" "tiny	2	0	obf	official"
} else {
    $NewMappings = @()
    $NewMappings += $Mappings[0]
    $NewMappings += "tiny	2	0	obf	official"
    if ($Mappings.Count -gt 1) {
        $NewMappings += $Mappings[1..($Mappings.Count-1)]
    }
    Set-Content "mappings.tiny" $NewMappings
}

Info "Applying mappings..."
New-Item -ItemType Directory -Path "build" -Force | Out-Null
$MappedJar = "build\server-mapped.jar"
$Classpath = "$TRCJar;$JoptSimpleJar;$AsmJar;$AsmCommonsJar;$AsmUtilJar;$AsmTreeJar;$GuavaJar"
& java -cp $Classpath com.threadmc.trc.Main `
    --input "$ServerJarPath" `
    --output "$MappedJar" `
    --mappings "mappings.tiny" `
    --from "obf" `
    --to "official"

Info "Decompiling with VineFlower..."
New-Item -ItemType Directory -Path "sources" -Force | Out-Null
& java -jar $VineflowerJar $MappedJar --outputdir sources

Info "Decompilation complete. Sources located at: $(Resolve-Path 'sources')"
