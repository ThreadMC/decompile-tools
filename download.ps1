param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("vineflower", "specialsource", "jopt-simple", "asm", "guava", "all")]
    [string]$App
)

function Download-File {
    param (
        [string]$Url,
        [string]$Destination
    )
    Write-Host "Downloading $Url to $Destination"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Get-Latest-Maven-Version {
    param (
        [string]$GroupId,
        [string]$ArtifactId
    )
    $GroupPath = $GroupId -replace '\.', '/'
    $MetadataUrl = "https://repo1.maven.org/maven2/${GroupPath}/${ArtifactId}/maven-metadata.xml"
    try {
        $Metadata = Invoke-WebRequest -Uri $MetadataUrl -UseBasicParsing
        $Xml = [xml]$Metadata.Content
        return $Xml.metadata.versioning.latest
    } catch {
        Write-Error "Failed to retrieve metadata for ${GroupId}:${ArtifactId}"
        return $null
    }
}

function Download-Maven-Jar {
    param (
        [string]$GroupId,
        [string]$ArtifactId,
        [string]$DestinationPath
    )
    $Version = Get-Latest-Maven-Version -GroupId $GroupId -ArtifactId $ArtifactId
    if ($null -eq $Version) {
        Write-Error "Could not determine latest version for ${ArtifactId}"
        return
    }
    $GroupPath = $GroupId -replace '\.', '/'
    $JarUrl = "https://repo1.maven.org/maven2/${GroupPath}/${ArtifactId}/${Version}/${ArtifactId}-${Version}.jar"
    Download-File -Url $JarUrl -Destination $DestinationPath
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ToolsDir = Join-Path $ScriptDir "tools"
New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null

switch ($App) {
    "vineflower" {
        Download-Maven-Jar -GroupId "org.vineflower" -ArtifactId "vineflower" -DestinationPath "$ToolsDir\vineflower.jar"
    }
    "specialsource" {
        Download-Maven-Jar -GroupId "net.md-5" -ArtifactId "SpecialSource" -DestinationPath "$ToolsDir\specialsource.jar"
    }
    "jopt-simple" {
        Download-Maven-Jar -GroupId "net.sf.jopt-simple" -ArtifactId "jopt-simple" -DestinationPath "$ToolsDir\jopt-simple.jar"
    }
    "asm" {
        Download-Maven-Jar -GroupId "org.ow2.asm" -ArtifactId "asm" -DestinationPath "$ToolsDir\asm.jar"
        Download-Maven-Jar -GroupId "org.ow2.asm" -ArtifactId "asm-commons" -DestinationPath "$ToolsDir\asm-commons.jar"
        Download-Maven-Jar -GroupId "org.ow2.asm" -ArtifactId "asm-util" -DestinationPath "$ToolsDir\asm-util.jar"
        Download-Maven-Jar -GroupId "org.ow2.asm" -ArtifactId "asm-tree" -DestinationPath "$ToolsDir\asm-tree.jar"
    }
    "guava" {
        Download-Maven-Jar -GroupId "com.google.guava" -ArtifactId "guava" -DestinationPath "$ToolsDir\guava.jar"
    }
    "all" {
        & $MyInvocation.MyCommand.Definition -App "vineflower"
        & $MyInvocation.MyCommand.Definition -App "specialsource"
        & $MyInvocation.MyCommand.Definition -App "jopt-simple"
        & $MyInvocation.MyCommand.Definition -App "asm"
        & $MyInvocation.MyCommand.Definition -App "guava"
    }
}
