$ErrorActionPreference = "Stop"

# ============================================
# Matrix Rain - automatic raylib setup
# ============================================

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$ProjectName = Split-Path -Leaf $Root
$RootMain = Join-Path $Root "main.c"
$SrcDir = Join-Path $Root "src"
$SrcMain = Join-Path $SrcDir "main.c"
$BuildDir = Join-Path $Root "build"
$Premake = Join-Path $BuildDir "premake5.exe"
$PremakeLua = Join-Path $BuildDir "premake5.lua"

# Preserve the user's source in a temporary backup.
if (Test-Path $RootMain) {
    $OriginalSource = $RootMain
}
elseif (Test-Path $SrcMain) {
    $OriginalSource = $SrcMain
}
else {
    throw "Cannot find main.c in the root or src folder."
}

$Temp = Join-Path $env:TEMP (
    "matrix-rain-" + [guid]::NewGuid().ToString("N")
)

New-Item -ItemType Directory -Path $Temp -Force |
    Out-Null

try {
    $SourceBackup = Join-Path $Temp "main.c"
    Copy-Item $OriginalSource $SourceBackup -Force

    # 1. Find the existing compiler and Make.
    $Toolchain = "C:\raylib\w64devkit\bin"

    if (Test-Path (Join-Path $Toolchain "gcc.exe")) {
        $env:Path = "$Toolchain;$env:Path"
    }

    $Gcc = Get-Command gcc.exe -ErrorAction SilentlyContinue
    $Make = Get-Command make.exe -ErrorAction SilentlyContinue

    if (!$Make) {
        $Make = Get-Command mingw32-make.exe `
            -ErrorAction SilentlyContinue
    }

    if (!$Gcc -or !$Make) {
        throw @"
GCC and Make are required.

Install raylib with its Windows toolchain, or install W64DevKit.
The script automatically detects:

C:\raylib\w64devkit\bin
"@
    }

    Write-Host "Compiler detected." -ForegroundColor Green

    # 2. Download the official project template if necessary.
    if (!(Test-Path $Premake) -or !(Test-Path $PremakeLua)) {
        Write-Host "Downloading raylib-quickstart..." `
            -ForegroundColor Cyan

        $Zip = Join-Path $Temp "quickstart.zip"
        $ExtractDir = Join-Path $Temp "extracted"

        Invoke-WebRequest `
            -Uri "https://github.com/raylib-extras/raylib-quickstart/archive/refs/heads/main.zip" `
            -OutFile $Zip `
            -UseBasicParsing

        Expand-Archive `
            -LiteralPath $Zip `
            -DestinationPath $ExtractDir `
            -Force

        $Template = Get-ChildItem `
            -LiteralPath $ExtractDir `
            -Directory |
            Select-Object -First 1

        if (!$Template) {
            throw "Could not locate the downloaded template."
        }

        # Copy required template folders without overwriting
        # existing project configuration.
        foreach ($Name in @(
            ".vscode",
            "build",
            "include",
            "resources"
        )) {
            $From = Join-Path $Template.FullName $Name
            $To = Join-Path $Root $Name

            if (!(Test-Path $From)) {
                continue
            }

            if (!(Test-Path $To)) {
                Copy-Item `
                    -LiteralPath $From `
                    -Destination $Root `
                    -Recurse `
                    -Force
            }
            else {
                Get-ChildItem -LiteralPath $From -Force |
                    ForEach-Object {
                        $Target = Join-Path $To $_.Name

                        if (!(Test-Path $Target)) {
                            Copy-Item `
                                -LiteralPath $_.FullName `
                                -Destination $To `
                                -Recurse `
                                -Force
                        }
                    }
            }
        }

        # Copy optional template files if they are missing.
        foreach ($Name in @(
            ".clangd",
            "build-MinGW-W64.bat",
            ".gitignore"
        )) {
            $From = Join-Path $Template.FullName $Name
            $To = Join-Path $Root $Name

            if ((Test-Path $From) -and !(Test-Path $To)) {
                Copy-Item `
                    -LiteralPath $From `
                    -Destination $To `
                    -Force
            }
        }
    }

    # 3. Ensure the required folder structure exists.
    foreach ($Name in @(
        "src",
        "include",
        "resources",
        "build"
    )) {
        New-Item `
            -ItemType Directory `
            -Path (Join-Path $Root $Name) `
            -Force |
            Out-Null
    }

    if (!(Test-Path $Premake) -or !(Test-Path $PremakeLua)) {
        throw "The downloaded raylib build setup is incomplete."
    }

    # 4. Pin the raylib dependency to release 6.2.
    $LuaText = Get-Content -LiteralPath $PremakeLua -Raw

    $LuaText = $LuaText.Replace(
        "https://github.com/raysan5/raylib/archive/refs/heads/master.zip",
        "https://github.com/raysan5/raylib/archive/refs/tags/6.2.zip"
    )

    $LuaText = $LuaText.Replace(
        "raylib-master",
        "raylib-6.2"
    )

    if ($LuaText.Contains("refs/heads/master.zip")) {
        throw "Could not pin the raylib download to release 6.2."
    }

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $PremakeLua,
        $LuaText,
        $Utf8NoBom
    )

    # 5. Place the source in the standard project location.
    Copy-Item `
        -LiteralPath $SourceBackup `
        -Destination $SrcMain `
        -Force

    if (Test-Path $RootMain) {
        Remove-Item -LiteralPath $RootMain -Force
    }

    Write-Host "Project structure created." `
        -ForegroundColor Green

    # 6. Ignore generated dependencies and build outputs.
    $GitIgnore = Join-Path $Root ".gitignore"

    if (!(Test-Path $GitIgnore)) {
        New-Item -ItemType File -Path $GitIgnore |
            Out-Null
    }

    $Rules = @(
        "/bin/",
        "/build/external/",
        "/build/build_files/",
        "/build/compile_commands.json",
        "/Makefile"
    )

    $Existing = @(
        Get-Content -LiteralPath $GitIgnore `
            -ErrorAction SilentlyContinue
    )

    foreach ($Rule in $Rules) {
        if ($Existing -notcontains $Rule) {
            Add-Content `
                -LiteralPath $GitIgnore `
                -Value $Rule `
                -Encoding utf8

            $Existing += $Rule
        }
    }

    # 7. Generate the Makefiles.
    Write-Host "Generating build files..." `
        -ForegroundColor Cyan

    Push-Location $BuildDir

    try {
        & $Premake gmake

        if ($LASTEXITCODE -ne 0) {
            throw "Premake failed: exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    # 8. Compile the project.
    Write-Host "Compiling Matrix Rain..." `
        -ForegroundColor Cyan

    & $Make.Source

    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed: exit code $LASTEXITCODE."
    }

    # 9. Locate and launch the executable.
    $Exe = Join-Path $Root (
        "bin\Debug\" + $ProjectName + ".exe"
    )

    if (!(Test-Path $Exe)) {
        $BinDir = Join-Path $Root "bin"

        $Candidate = Get-ChildItem `
            -LiteralPath $BinDir `
            -Filter "*.exe" `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($Candidate) {
            $Exe = $Candidate.FullName
        }
    }

    if (!(Test-Path $Exe)) {
        throw "Build finished, but the executable was not found."
    }

    Write-Host "Launching Matrix Rain..." `
        -ForegroundColor Green

    Start-Process `
        -FilePath $Exe `
        -WorkingDirectory $Root

    Write-Host "Matrix Rain is running!" `
        -ForegroundColor Green
}
finally {
    if (Test-Path $Temp) {
        Remove-Item `
            -LiteralPath $Temp `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
