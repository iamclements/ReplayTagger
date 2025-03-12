# VideoGenreTagger.ps1
# Script to automatically tag game clips with genre metadata based on folder name
# This enables Plex to create dynamic collections per game

# Specify the parent folder path where your game clips are located
$parentFolderPath = "C:\Path\To\Your\Videos" # Change this to your actual folder path

# Define the media file extensions to look for (NVIDIA clips are typically MP4)
$fileExtensions = @("*.mp4") 

# Default ffmpeg path - change this to your actual installation path if needed
$defaultFfmpegPath = "C:\Program Files\ffmpeg\bin\ffmpeg.exe"
$ffmpegPath = $null

# Try to find ffmpeg in common locations
$commonFfmpegPaths = @(
    $defaultFfmpegPath,
    "C:\ffmpeg\bin\ffmpeg.exe",
    "$env:ChocolateyInstall\bin\ffmpeg.exe",
    "$env:ProgramFiles\ffmpeg\bin\ffmpeg.exe",
    "$env:ProgramFiles(x86)\ffmpeg\bin\ffmpeg.exe"
)

foreach ($path in $commonFfmpegPaths) {
    if (Test-Path $path) {
        $ffmpegPath = $path
        Write-Output "Found ffmpeg at: $ffmpegPath"
        break
    }
}

# Exit if ffmpeg not found
if (-not $ffmpegPath) {
    Write-Error "ffmpeg not found in common locations. Please update the script with the correct path."
    exit 1
}

# Temporary file extension
$tempFileExtension = ".temp.mp4"

# Metadata format
$metadataFormat = "ffmetadata"

# Verify parent folder exists
if (-not (Test-Path $parentFolderPath)) {
    Write-Error "Parent folder not found: $parentFolderPath"
    exit 1
}

# Get all media files
$mediaFiles = Get-ChildItem -Path $parentFolderPath -Include $fileExtensions -Recurse
$totalFiles = $mediaFiles.Count
$currentFileIndex = 0
$updatedCount = 0
$skippedCount = 0
$errorCount = 0

Write-Output "Found $totalFiles video files to process"

# Recursively find all media files and update their Genre tag if empty
$mediaFiles | ForEach-Object {
    $mediaFile = $_
    $folderName = Split-Path $mediaFile.DirectoryName -Leaf
    $currentFileIndex++

    # Use ffmpeg to check if the genre field is already set
    $metadataOutput = & $ffmpegPath -i $mediaFile.FullName -f $metadataFormat - 2>&1
    if ($metadataOutput -notmatch 'genre=') {
        # Store the original "Date Modified" timestamp
        $originalTimestamp = (Get-Item $mediaFile.FullName).LastWriteTime

        # Genre is not set, update the file's tags
        $tempFileName = "${mediaFile.FullName}$tempFileExtension"
        try {
            # Show what we're processing with game name
            Write-Output "[$currentFileIndex/$totalFiles] Adding genre '$folderName' to: $($mediaFile.Name)"
            
            & $ffmpegPath -i $mediaFile.FullName -metadata genre="$folderName" -codec copy $tempFileName -y
            
            if (Test-Path $tempFileName) {
                Move-Item -Path $tempFileName -Destination $mediaFile.FullName -Force

                # Restore the original "Date Modified" timestamp
                (Get-Item $mediaFile.FullName).LastWriteTime = $originalTimestamp
                $updatedCount++
            } else {
                Write-Output "[$currentFileIndex/$totalFiles] Error: Temp file was not created for: $($mediaFile.FullName)"
                $errorCount++
            }
        } catch {
            Write-Output "[$currentFileIndex/$totalFiles] Failed to update genre for file: $($mediaFile.FullName). Error: $_"
            $errorCount++
        }
    } else {
        Write-Output "[$currentFileIndex/$totalFiles] Genre already set for: $($mediaFile.Name), skipping."
        $skippedCount++
    }

    # Display progress bar
    Write-Progress -Activity "Processing game clips" -Status "$currentFileIndex out of $totalFiles" -PercentComplete (($currentFileIndex / $totalFiles) * 100)
}

Write-Output "Processing complete. Total files: $totalFiles | Updated: $updatedCount | Skipped: $skippedCount | Errors: $errorCount"