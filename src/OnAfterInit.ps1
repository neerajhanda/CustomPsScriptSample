<#

Feel free to modify this file by implementing your logic.

This script is invoked after initialization scripts completed running 
but before user has logged in.

This script runs under Administrator account but without any UI, 
meaning this script can't ask for user input. 

It's OK for this script to run a few minutes, as it runs before
users log in.

#>

Write-Host "OnAfterInit script started running at $(Get-Date)."

Set-Location "C:\Users\Administrator"
[string] $workDirectory = "C:\Users\Administrator\AWS-workshop-assets"
[string] $scriptPath = "$workDirectory\bobs-used-bookstore-classic\db-scripts\bobs-used-bookstore-classic-db.sql"

$sqlUsername = ((Get-SECSecretValue -SecretId "SQLServerRDSSecret").SecretString | ConvertFrom-Json).username
$sqlPassword = ((Get-SECSecretValue -SecretId "SQLServerRDSSecret").SecretString | ConvertFrom-Json).password

$endpointAddress = Get-RDSDBInstance | Select-Object -ExpandProperty Endpoint | select Address
[string] $SQLDatabaseEndpoint = $endpointAddress.Address

[string] $SQLDatabaseEndpointTrimmed = $SQLDatabaseEndpoint.Replace(':1433','')

# Set the database name
$databaseName = "BookStoreClassic"

# SQL query to check if the database exists
$checkDbQuery = "IF EXISTS (SELECT name FROM sys.databases WHERE name = N'$databaseName') SELECT 1 ELSE SELECT 0"

# Run the sqlcmd command to check if the database exists
$checkDbResult = sqlcmd -U $sqlUsername -P $sqlPassword -S $SQLDatabaseEndpointTrimmed -Q $checkDbQuery -h -1 -W

# Trim any whitespace from the result
$checkDbResult = $checkDbResult.Trim()

if ($checkDbResult -eq "0") {
    Write-Host "Database '$databaseName' does not exist. Creating database..."
    # Run the sqlcmd command to create the database
    sqlcmd -U $sqlUsername -P $sqlPassword -S $SQLDatabaseEndpointTrimmed -i $scriptPath
} else {
    Write-Host "Database '$databaseName' already exists. Skipping creation."
}

[string] $connectionString = "Server=$SQLDatabaseEndpointTrimmed;Database=$databaseName;User Id=$sqlUsername;Password=$sqlPassword;"

[string] $webConfigFolder = "$workDirectory\bobs-used-bookstore-classic\app\Bookstore.Web\"
$webConfigPath = Join-Path $webConfigFolder "Web.config"

$webConfigXml = [xml](Get-Content -Path $webConfigPath)

$addElement = $webConfigXml.configuration.appSettings.add | Where-Object { $_.key -eq "ConnectionStrings/BookstoreDatabaseConnection" }
$addElement.value = $connectionString

$webConfigXml.Save($webConfigPath)

# Bucket and folder path in S3
$bucketName = "windows-dev-env-ec2"
$folderPath = "artifacts"

# Get the directory where the PowerShell script file is located
$localPath = Join-Path $PSScriptRoot "s3-artifacts"

# Create local directory if it doesn't exist
if (-not (Test-Path $localPath)) {
    Write-Host "Creating local directory: $localPath"
    New-Item -Path $localPath -ItemType Directory
} else {
    Write-Host "Local directory already exists: $localPath"
}
# Silent installation of the VSIX package
$vsixFilePath = Join-Path $localPath "AWSToolkitPackage.vsix"

# Download files from S3
Invoke-RestMethod -uri https://$bucketName.s3.us-west-2.amazonaws.com/$folderPath/AWSToolkitPackage.vsix -OutFile $vsixFilePath



if (Test-Path $vsixFilePath) {
    # Path to Visual Studio 2022 VSIXInstaller.exe
    $vsixInstallerPath = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\VSIXInstaller.exe"
    
    # Check if VSIXInstaller.exe exists (adjust path if using a different version of Visual Studio)
    if (Test-Path $vsixInstallerPath) {
        # Uninstall existing extensions first
        $extensionFolderPath = "C:\Users\Administrator\AppData\Local\Microsoft\VisualStudio\17.0_7653a119\Extensions"
        if (Test-Path $extensionFolderPath) {
            # Search for files named "extension.vsixmanifest" recursively
            $files = Get-ChildItem -Path $extensionFolderPath -Filter "extension.vsixmanifest" -Recurse
            foreach ($file in $files) {
                # Read the content of the file
                $content = Get-Content -Path $file.FullName -Raw
            
                # Parse the XML content
                $xml = [xml]$content
            
                # Extract the value of the "Id" attribute of the "Identity" tag
                $id = $xml.PackageManifest.Metadata.Identity.Id
            
                # Print the "Id" value
                Write-Host "File: $($file.FullName)"
                Write-Host "Id: $id"
                Write-Host "---"
            
                # Run VSIXInstaller.exe with the "Id" as an argument
                $argumentList = @("/uninstall:$id","/q")
                Start-Process -FilePath $vsixInstallerPath -ArgumentList $argumentList -Wait -NoNewWindow
                 if ($LASTEXITCODE -eq 0) {
                        Write-Host "VSIX package uninstalled successfully."
                    } else {
                        Write-Host "VSIX package uninstall failed. Exit code: $LASTEXITCODE."
                    }
                }
        }
         # Run silent install of the VSIX package using Start-Process with logging
        $arguments = @("$vsixFilePath", "/q")

        Start-Process -FilePath $vsixInstallerPath -ArgumentList $arguments -Wait -NoNewWindow

        # Check the installation result
        if ($LASTEXITCODE -eq 0) {
            Write-Host "VSIX package installed successfully."
        } else {
            Write-Host "VSIX package installation failed. Exit code: $LASTEXITCODE."
        }
       
    } else {
        Write-Host "VSIXInstaller.exe not found. Please verify the Visual Studio installation path."
    }
} else {
    Write-Host "VSIX package not found in the downloaded files."
}

Write-Host "OnAfterInit script finished running at $(Get-Date)."
